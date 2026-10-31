#!/usr/bin/env python3
"""Content-keyed step memo for full/scripts/build_full.sh (BUILD_FULL_INCREMENTAL=1).

build_full.sh puts tiny shims for swiftc, clang-18, clang++-18 and ld64.lld-18
first on PATH. Each shim runs `build_memo.py exec <tool> <argv...>`, which
either runs the real tool or proves that running it would reproduce outputs it
already recorded, and then puts exactly those bytes back.

A step is one compiler or linker invocation. Its key is a SHA-256 over:
  * schema version, BUILD_FULL_MEMO_SALT (toolchain identity, computed once per
    build), the resolved real tool, the working directory and the tool-relevant
    environment;
  * the complete argv (output paths included: a different destination is a
    different step);
  * the CONTENT of every regular file named in argv (also `-Ifoo`, `-x=foo`
    spellings) that is not one of the step's outputs;
  * the CONTENT of every file the tool reported reading the last time it ran:
    swiftc's frontend dependency file (sources, every loaded .swiftmodule /
    .swiftinterface, every Clang header and module map), clang's -MD file, and
    ld64.lld's -dependency_info inputs;
  * negative lookups, which a dependency file cannot list: for ld64.lld every
    path it probed and did not find (still absent?); for Swift, for every
    module name the sources import or test with canImport, and every module
    that was loaded, which of <dir>/<Name>.swiftmodule|.swiftinterface|
    .framework|/module.modulemap exist across every search directory
    (including the SDK's implicit ones); for every header that was read, which
    same-relative-path headers exist in any header search directory; and which
    module maps sit at depth one and two of every Clang search directory;
  * the content of every .apinotes file beside a module map that was read, and
    of a Swift macro plugin plus the libraries beside it.
Like ninja's depfile scheme, the dependency list of the previous run is what
the next run re-hashes: if none of those inputs changed, the tool reads the same
bytes and writes the same bytes.

On a hit every recorded output (including side outputs such as .swiftdoc,
.swiftsourceinfo, .abi.json) is checked against its recorded SHA-256 and, if
missing or different, restored from the copy taken when the step last ran
(that copy is itself verified first), then given the current time as its mtime,
exactly as running the tool would. The step's recorded stdout/stderr are
replayed. Failed invocations are never recorded, and typechecks (build_full's
negative guards are typechecks that must fail) always run untouched. Anything
this module cannot model (a link driven through clang, response files, several
sources under one -MF, a compile without explicit outputs) runs unmemoized.

Usage:
  build_memo.py exec <tool> <argv...>     (from the PATH shims)
  build_memo.py summary <log>              print hit/miss/pass counts
State (BUILD_FULL_MEMO_DIR): steps/<id>/entries/<key>.json (up to
BUILD_FULL_MEMO_KEEP=4 most recently used input sets per step, so a revert or
an alternating configuration also hits) + blobs/<sha256>, and log.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time

SCHEMA = "build-full-memo-v2"
CHUNK = 1 << 20

ENV_EXACT = {
    "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJC_INCLUDE_PATH",
    "OBJCPLUS_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT", "TMPDIR_UNUSED",
    "MACOSX_DEPLOYMENT_TARGET", "IPHONEOS_DEPLOYMENT_TARGET", "ZERO_AR_DATE",
    "SOURCE_DATE_EPOCH", "LD_LIBRARY_PATH", "LD_PRELOAD", "LANG", "LC_ALL",
}
ENV_PREFIXES = ("SWIFT_", "CLANG_", "LLVM_", "DYLD_", "RC_", "CCC_", "LIBCLANG_")

SWIFT_SEARCH_FLAGS = {"-I", "-F", "-Fsystem", "-Isystem"}
CLANG_SEARCH_FLAGS = ("-I", "-isystem", "-iquote", "-idirafter", "-F", "-iframework",
                      "-isystemafter", "-iwithsysroot")
CLANG_ARG_FLAGS = {
    "-o", "-I", "-isystem", "-iquote", "-idirafter", "-F", "-iframework",
    "-isysroot", "-target", "-include", "-imacros", "-D", "-U", "-Xclang",
    "-x", "-MF", "-MT", "-MQ", "-arch", "-L", "-Xlinker", "-Xassembler",
    "-Xpreprocessor", "-mllvm", "-iprefix", "-iwithprefix", "-isysroot",
    "-include-pch", "-resource-dir", "--sysroot", "-B",
}
SOURCE_SUFFIXES = (".c", ".cc", ".cpp", ".cxx", ".c++", ".C", ".m", ".mm", ".s", ".S")

IMPORT_RE = re.compile(
    rb"^[ \t]*(?:@[A-Za-z_]\w*(?:\([^)\n]*\))?[ \t]+)*"
    rb"(?:(?:public|internal|private|fileprivate|package|open)[ \t]+)?"
    rb"import[ \t]+(?:(?:typealias|struct|class|enum|protocol|let|var|func)[ \t]+)?"
    rb"([A-Za-z_]\w*)", re.M)
CANIMPORT_RE = re.compile(rb"canImport\(\s*([A-Za-z_]\w*)")


class Passthrough(Exception):
    pass


INSTALL_NAME_TOKENS = ("@rpath", "@loader_path", "@executable_path")


def has_response_file(argv: list[str]) -> bool:
    return any(a.startswith("@") and not a.startswith(INSTALL_NAME_TOKENS) for a in argv)


# ---------------------------------------------------------------- hashing
_hash_cache: dict[str, str] = {}


def file_digest(path: str) -> str:
    """sha256 of a regular file's content, 'missing', or 'dir'/'other'."""
    cached = _hash_cache.get(path)
    if cached is not None:
        return cached
    try:
        st = os.stat(path)
    except FileNotFoundError:
        result = "missing"
    except NotADirectoryError:
        result = "missing"
    else:
        if stat.S_ISREG(st.st_mode):
            h = hashlib.sha256()
            with open(path, "rb") as f:
                while True:
                    block = f.read(CHUNK)
                    if not block:
                        break
                    h.update(block)
            result = h.hexdigest()
        elif stat.S_ISDIR(st.st_mode):
            result = "dir"
        else:
            result = "other"
    _hash_cache[path] = result
    return result


def stat_sig(path: str) -> list[int] | None:
    try:
        st = os.stat(path)
    except OSError:
        return None
    return [st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns]


def absnorm(path: str, cwd: str) -> str:
    return os.path.normpath(os.path.join(cwd, path))


def exists(path: str) -> bool:
    return os.path.lexists(path)


# ---------------------------------------------------------------- depfiles
def parse_make_depfile(path: str) -> list[str]:
    with open(path, "rb") as f:
        text = f.read().decode("utf-8", "surrogateescape")
    text = text.replace("\\\r\n", " ").replace("\\\n", " ")
    deps: list[str] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        tokens: list[str] = []
        cur = []
        i = 0
        while i < len(line):
            c = line[i]
            if c == "\\" and i + 1 < len(line) and line[i + 1] in " #\\":
                cur.append(line[i + 1])
                i += 2
                continue
            if c == "$" and i + 1 < len(line) and line[i + 1] == "$":
                cur.append("$")
                i += 2
                continue
            if c in " \t":
                if cur:
                    tokens.append("".join(cur))
                    cur = []
            else:
                cur.append(c)
            i += 1
        if cur:
            tokens.append("".join(cur))
        # targets ... ":" deps ...  (the colon may be glued to the last target)
        seen_colon = False
        for tok in tokens:
            if not seen_colon:
                if tok == ":":
                    seen_colon = True
                elif tok.endswith(":"):
                    seen_colon = True
                continue
            deps.append(tok)
    return deps


def parse_dependency_info(path: str) -> tuple[list[str], list[str]]:
    data = open(path, "rb").read()
    inputs: list[str] = []
    notfound: list[str] = []
    i = 0
    while i < len(data):
        op = data[i]
        end = data.index(b"\0", i + 1)
        value = data[i + 1:end].decode("utf-8", "surrogateescape")
        i = end + 1
        if op == 0x10:
            inputs.append(value)
        elif op == 0x11:
            notfound.append(value)
    return inputs, notfound


# ---------------------------------------------------------------- tool models
def joined_or_next(argv: list[str], i: int, flag: str) -> tuple[str | None, int]:
    """For flag spelled `-Xfoo` or `-X foo`, return (value, next index)."""
    a = argv[i]
    if a == flag:
        if i + 1 < len(argv):
            return argv[i + 1], i + 2
        return None, i + 1
    return a[len(flag):], i + 1


class Step:
    def __init__(self, tool: str, real: str, argv: list[str], cwd: str):
        self.tool = tool
        self.real = real
        self.argv = argv
        self.cwd = cwd
        self.kind = ""
        self.outputs: list[str] = []          # declared primary outputs (abs)
        self.side_candidates: list[str] = []  # outputs if (re)written by the run
        self.inject: list[str] = []
        self.depfile = ""
        self.swift_dirs: list[str] = []
        self.clang_dirs: list[str] = []
        self.plugin_files: list[str] = []
        self.aliases: list[tuple[str, str]] = []
        self.user_ofm = ""


def model_swiftc(step: Step) -> None:
    argv = step.argv
    modes = {"-emit-object", "-c", "-emit-module"}
    if has_response_file(argv):
        raise Passthrough("response file")
    # A typecheck has no outputs to replay, and build_full's negative guards
    # are typechecks that MUST fail: never inject anything into them.
    if "-typecheck" in argv:
        raise Passthrough("typecheck")
    for bad in ("-version", "--version", "-print-target-info", "-###", "-v",
                "-emit-executable", "-emit-library", "-emit-dependencies",
                "-incremental", "-emit-sil", "-emit-ir", "-emit-assembly", "-dump-ast",
                "-index-store-path", "-save-temps"):
        if bad in argv:
            raise Passthrough(f"unmodelled {bad}")
    if not modes.intersection(argv):
        raise Passthrough("not a compile")
    if "-emit-module" in argv and "-emit-module-path" not in argv:
        raise Passthrough("-emit-module without -emit-module-path")
    sources = [a for a in argv if a.endswith(".swift") and not a.startswith("-")]
    wmo = "-wmo" in argv or "-whole-module-optimization" in argv
    if not wmo and len(sources) != 1:
        raise Passthrough("multi-file non-WMO compile")
    sdk = None
    i = 0
    while i < len(argv):
        a = argv[i]
        nxt = argv[i + 1] if i + 1 < len(argv) else None
        if a == "-o" and nxt is not None:
            step.outputs.append(absnorm(nxt, step.cwd)); i += 2; continue
        if a == "-emit-module-path" and nxt is not None:
            mp = absnorm(nxt, step.cwd)
            step.outputs.append(mp)
            base = mp[:-len(".swiftmodule")] if mp.endswith(".swiftmodule") else mp
            for suffix in (".swiftdoc", ".swiftsourceinfo", ".abi.json"):
                step.side_candidates.append(base + suffix)
            d, b = os.path.split(base)
            step.side_candidates.append(os.path.join(d, "Project", b + ".swiftsourceinfo"))
            i += 2; continue
        if a in ("-emit-objc-header-path", "-emit-module-interface-path",
                 "-emit-private-module-interface-path", "-emit-tbd-path",
                 "-emit-loaded-module-trace-path", "-emit-module-source-info-path",
                 "-emit-module-doc-path", "-emit-abi-descriptor-path") and nxt is not None:
            step.outputs.append(absnorm(nxt, step.cwd)); i += 2; continue
        if a == "-output-file-map" and nxt is not None:
            step.user_ofm = absnorm(nxt, step.cwd)
            with open(step.user_ofm) as f:
                ofm = json.load(f)
            if not isinstance(ofm, dict):
                raise Passthrough("output file map is not an object")
            for entry_name, entry in ofm.items():
                if not isinstance(entry, dict):
                    raise Passthrough("output file map entry is not an object")
                for kind, path in entry.items():
                    if kind in ("dependencies", "emit-module-dependencies", "swift-dependencies"):
                        raise Passthrough("output file map already names dependency files")
                    step.outputs.append(absnorm(path, step.cwd))
            i += 2; continue
        if a == "-sdk" and nxt is not None:
            sdk = absnorm(nxt, step.cwd); i += 2; continue
        if a == "-module-alias" and nxt is not None:
            if "=" in nxt:
                alias, real_name = nxt.split("=", 1)
                step.aliases.append((alias, real_name))
            i += 2; continue
        if a in ("-load-plugin-library", "-load-plugin-executable") and nxt is not None:
            step.plugin_files.append(absnorm(nxt.split("#", 1)[0], step.cwd)); i += 2; continue
        if a == "-plugin-path" and nxt is not None:
            step.plugin_files.append(absnorm(nxt, step.cwd)); i += 2; continue
        if a in SWIFT_SEARCH_FLAGS and nxt is not None:
            step.swift_dirs.append(absnorm(nxt, step.cwd))
            step.clang_dirs.append(absnorm(nxt, step.cwd))
            i += 2
            continue
        if a.startswith("-I") and a != "-Isystem" and len(a) > 2:
            step.swift_dirs.append(absnorm(a[2:], step.cwd))
            step.clang_dirs.append(absnorm(a[2:], step.cwd))
            i += 1
            continue
        if a.startswith("-F") and a != "-Fsystem" and len(a) > 2:
            step.swift_dirs.append(absnorm(a[2:], step.cwd))
            i += 1
            continue
        if True:
            if a == "-Xcc" and nxt is not None:
                for flag in CLANG_SEARCH_FLAGS:
                    if nxt == flag and i + 3 < len(argv) and argv[i + 2] == "-Xcc":
                        step.clang_dirs.append(absnorm(argv[i + 3], step.cwd))
                        i += 4
                        break
                    if nxt.startswith(flag) and len(nxt) > len(flag):
                        step.clang_dirs.append(absnorm(nxt[len(flag):], step.cwd))
                        i += 2
                        break
                else:
                    i += 2
                continue
            i += 1
    if not step.outputs:
        raise Passthrough("compile without explicit outputs")
    if sdk:
        for rel in ("usr/lib/swift", "System/Library/Frameworks", "Library/Frameworks",
                    "System/Library/SubFrameworks"):
            step.swift_dirs.append(os.path.join(sdk, rel))
        for rel in ("usr/include", "usr/local/include", "System/Library/Frameworks"):
            step.clang_dirs.append(os.path.join(sdk, rel))
    step.kind = "swift"
    step.depfile = "swift"
    # Frontend -emit-dependencies-path conflicts with the supplementary output
    # file map the driver uses for large modules; a driver output file map with
    # only the whole-module "" entry adds the two dependency files and nothing
    # else (objects and modules are byte-identical with and without it).
    step.inject = ["-emit-dependencies", "-output-file-map", "@OFM@"]


def model_clang(step: Step) -> None:
    argv = step.argv
    if has_response_file(argv):
        raise Passthrough("response file")
    if "-c" not in argv:
        raise Passthrough("not a -c compile (link via clang)")
    for bad in ("-M", "-MM", "-MD", "-MMD", "-MF", "-E", "-save-temps", "-", "-###", "-fmodules"):
        if bad in argv:
            raise Passthrough(f"unmodelled {bad}")
    sources = []
    sysroot = None
    i = 0
    while i < len(argv):
        a = argv[i]
        nxt = argv[i + 1] if i + 1 < len(argv) else None
        if a == "-o" and nxt is not None:
            step.outputs.append(absnorm(nxt, step.cwd)); i += 2; continue
        if a == "-isysroot" and nxt is not None:
            sysroot = absnorm(nxt, step.cwd); i += 2; continue
        matched = False
        for flag in CLANG_SEARCH_FLAGS:
            if a == flag or (a.startswith(flag) and len(a) > len(flag)):
                v, j = joined_or_next(argv, i, flag)
                if v is not None:
                    step.clang_dirs.append(absnorm(v, step.cwd))
                i = j
                matched = True
                break
        if matched:
            continue
        if a in CLANG_ARG_FLAGS:
            i += 2; continue
        if not a.startswith("-") and a.endswith(SOURCE_SUFFIXES):
            sources.append(absnorm(a, step.cwd))
        i += 1
    if len(sources) != 1 or len(step.outputs) != 1:
        raise Passthrough("not exactly one source and one -o")
    step.clang_dirs.insert(0, os.path.dirname(sources[0]))
    if sysroot:
        for rel in ("usr/include", "usr/local/include", "System/Library/Frameworks"):
            step.clang_dirs.append(os.path.join(sysroot, rel))
    step.kind = "clang"
    step.depfile = "make"
    step.inject = ["-MD", "-MF", "@DEPFILE@"]


def model_ld(step: Step) -> None:
    argv = step.argv
    if has_response_file(argv):
        raise Passthrough("response file")
    for bad in ("-dependency_info", "-map", "-object_path_lto", "-r", "--version",
                "-v", "-why_live", "-t", "-cache_path_lto"):
        if bad in argv:
            raise Passthrough(f"unmodelled {bad}")
    i = 0
    while i < len(argv):
        if argv[i] == "-o" and i + 1 < len(argv):
            step.outputs.append(absnorm(argv[i + 1], step.cwd))
            i += 2
            continue
        i += 1
    if len(step.outputs) != 1:
        raise Passthrough("link without exactly one -o")
    step.kind = "ld"
    step.depfile = "depinfo"
    step.inject = ["-dependency_info", "@DEPFILE@"]


MODELS = {
    "swiftc": model_swiftc,
    "clang-18": model_clang,
    "clang++-18": model_clang,
    "ld64.lld-18": model_ld,
}


# ---------------------------------------------------------------- key
def env_items() -> list[str]:
    items = []
    for k in sorted(os.environ):
        if k.startswith("BUILD_FULL_MEMO"):
            continue
        if k in ENV_EXACT or k.startswith(ENV_PREFIXES):
            items.append(f"{k}={os.environ[k]}")
    return items


def argv_file_candidates(step: Step) -> list[str]:
    seen = []
    for a in step.argv:
        cands = []
        if not a.startswith("-"):
            cands.append(a.split("#", 1)[0])
        if "=" in a:
            cands.append(a.split("=", 1)[1])
        if a[:2] in ("-I", "-L", "-F") and len(a) > 2:
            cands.append(a[2:])
        for c in cands:
            if not c:
                continue
            p = absnorm(c, step.cwd)
            if p in seen:
                continue
            try:
                if stat.S_ISREG(os.stat(p).st_mode):
                    seen.append(p)
            except OSError:
                pass
    return seen


def module_names_from(paths: list[str]) -> set[str]:
    names: set[str] = set()
    for p in paths:
        parts = p.split("/")
        for part in parts:
            for suf in (".swiftmodule", ".swiftinterface", ".framework"):
                if part.endswith(suf) and len(part) > len(suf):
                    names.add(part[: -len(suf)])
        if p.endswith(".swift"):
            try:
                data = open(p, "rb").read()
            except OSError:
                continue
            for m in IMPORT_RE.finditer(data):
                names.add(m.group(1).decode())
            for m in CANIMPORT_RE.finditer(data):
                names.add(m.group(1).decode())
    return names


def uniq(seq):
    out, seen = [], set()
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def negative_entries(step: Step, deps: list[str], outputs: set[str]) -> list[str]:
    entries: list[str] = []
    clang_dirs = uniq(step.clang_dirs)
    # Module maps clang can discover in each header search directory.
    for d in clang_dirs:
        for name in ("module.modulemap", "module.map"):
            p = os.path.join(d, name)
            if exists(p):
                entries.append(f"MM {p}")
        try:
            subs = sorted(os.listdir(d))
        except OSError:
            subs = None
        if subs is None:
            entries.append(f"NODIR {d}")
            continue
        for s in subs:
            for name in ("module.modulemap", "module.map"):
                p = os.path.join(d, s, name)
                if exists(p):
                    entries.append(f"MM {p}")
    # Same-relative-path headers anywhere on the header search path.
    rels: set[str] = set()
    for dep in deps:
        if dep.endswith((".h", ".hpp", ".hh", ".inc", ".def", ".modulemap")) or "/c++/v1/" in dep:
            for d in clang_dirs:
                if dep.startswith(d + "/"):
                    rels.add(dep[len(d) + 1:])
    for rel in sorted(rels):
        for d in clang_dirs:
            p = os.path.join(d, rel)
            if p not in outputs and exists(p):
                entries.append(f"H {p}")
    if step.kind == "swift":
        names = module_names_from(deps)
        # An alias only matters to a compile that names one of its sides; the
        # other side of an unused alias may be appearing concurrently (the
        # app-module graph) and must not make the key nondeterministic.
        for alias, real_name in step.aliases:
            if alias in names or real_name in names:
                names |= {alias, real_name}
        for name in sorted(names):
            for d in uniq(step.swift_dirs + clang_dirs):
                for cand in (f"{name}.swiftmodule", f"{name}.swiftinterface",
                             f"{name}.framework", f"{name}/module.modulemap",
                             f"{name}/module.map"):
                    p = os.path.join(d, cand)
                    if p not in outputs and exists(p):
                        entries.append(f"N {p}")
    return entries


def plugin_entries(step: Step) -> list[str]:
    entries = []
    for p in step.plugin_files:
        targets = []
        if os.path.isdir(p):
            targets.append(p)
        else:
            entries.append(f"P {p} {file_digest(p)}")
            targets += [os.path.dirname(p), os.path.dirname(os.path.dirname(p))]
        for d in uniq(targets):
            try:
                names = sorted(os.listdir(d))
            except OSError:
                entries.append(f"PD {d} missing")
                continue
            for n in names:
                q = os.path.join(d, n)
                if os.path.isfile(q):
                    entries.append(f"PF {q} {file_digest(q)}")
    return entries


def compute_components(step: Step, deps: list[str], notfound: list[str],
                       outputs: set[str]) -> list[str]:
    comps = [
        f"schema {SCHEMA}",
        f"salt {os.environ.get('BUILD_FULL_MEMO_SALT', '')}",
        f"tool {step.tool} {os.path.realpath(step.real)}",
        f"cwd {step.cwd}",
    ]
    comps += [f"env {e}" for e in env_items()]
    comps += [f"arg {a}" for a in step.argv]
    for p in argv_file_candidates(step):
        if p not in outputs:
            comps.append(f"argfile {p} {file_digest(p)}")
    for p in uniq(deps):
        if p not in outputs:
            comps.append(f"dep {p} {file_digest(p)}")
    for p in uniq(notfound):
        comps.append(f"notfound {p} {'present' if exists(p) else 'absent'}")
    comps += negative_entries(step, deps, outputs)
    comps += plugin_entries(step)
    comps += apinotes_entries(deps)
    return comps


def apinotes_entries(deps: list[str]) -> list[str]:
    """Clang reads <Module>.apinotes beside a module map without reporting it."""
    entries = []
    for d in sorted({os.path.dirname(p) for p in deps
                     if p.endswith(("module.modulemap", "module.map"))}):
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for n in names:
            if n.endswith((".apinotes", ".apinotesc")):
                q = os.path.join(d, n)
                entries.append(f"apinotes {q} {file_digest(q)}")
    return entries


def key_of(comps: list[str]) -> str:
    h = hashlib.sha256()
    for c in comps:
        h.update(c.encode("utf-8", "surrogateescape"))
        h.update(b"\n")
    return h.hexdigest()


# ---------------------------------------------------------------- state
def state_dir() -> str:
    d = os.environ.get("BUILD_FULL_MEMO_DIR")
    if not d:
        raise SystemExit("build_memo: BUILD_FULL_MEMO_DIR is not set")
    return d


def step_id(step: Step) -> str:
    h = hashlib.sha256()
    h.update(step.tool.encode())
    if step.outputs:
        for o in sorted(step.outputs):
            h.update(b"\0o" + o.encode("utf-8", "surrogateescape"))
    else:
        h.update(b"\0cwd" + step.cwd.encode())
        for a in step.argv:
            h.update(b"\0a" + a.encode("utf-8", "surrogateescape"))
    return h.hexdigest()[:32]


def log(line: str) -> None:
    try:
        with open(os.path.join(state_dir(), "log"), "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def atomic_write(path: str, data: bytes) -> None:
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp.")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def copy_bytes(src: str, dst: str, mode: int) -> None:
    d = os.path.dirname(dst)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix="." + os.path.basename(dst) + ".memo.")
    try:
        with os.fdopen(fd, "wb") as out, open(src, "rb") as inp:
            shutil.copyfileobj(inp, out, CHUNK)
        os.chmod(tmp, mode)
        os.replace(tmp, dst)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------- run
def run_tool(cmd: list[str]) -> tuple[int, bytes, bytes]:
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    bufs = {1: bytearray(), 2: bytearray()}

    def pump(src, sink, buf):
        while True:
            chunk = src.read1(65536) if hasattr(src, "read1") else src.read(65536)
            if not chunk:
                break
            buf.extend(chunk)
            sink.write(chunk)
            sink.flush()

    threads = [
        threading.Thread(target=pump, args=(proc.stdout, sys.stdout.buffer, bufs[1])),
        threading.Thread(target=pump, args=(proc.stderr, sys.stderr.buffer, bufs[2])),
    ]
    for t in threads:
        t.start()
    rc = proc.wait()
    for t in threads:
        t.join()
    return rc, bytes(bufs[1]), bytes(bufs[2])


def keep_entries() -> int:
    value = os.environ.get("BUILD_FULL_MEMO_KEEP", "4")
    if not value.isdigit() or int(value) < 1:
        raise SystemExit("build_memo: BUILD_FULL_MEMO_KEEP must be a positive integer")
    return int(value)


def list_entries(sdir: str) -> list[str]:
    """Entry records of a step, most recently used first."""
    d = os.path.join(sdir, "entries")
    try:
        names = [n for n in os.listdir(d) if n.endswith(".json")]
    except FileNotFoundError:
        return []
    paths = [os.path.join(d, n) for n in names]
    return sorted(paths, key=lambda p: os.stat(p).st_mtime_ns, reverse=True)


def change_reason(comps: list[str], old: list[str]) -> str:
    old_set = set(old)
    for c in comps:
        if c not in old_set:
            return "changed: " + c[:300]
    new_set = set(comps)
    for c in old:
        if c not in new_set:
            return "gone: " + c[:300]
    return "inputs"


def try_hit(step: Step, sdir: str) -> tuple[bool, str]:
    """Replay the step if one of its recorded entries matches its inputs now.

    A step keeps up to BUILD_FULL_MEMO_KEEP entries (input sets), so switching
    back and forth between configurations or reverting an edit hits too.
    """
    entries = list_entries(sdir)
    if not entries:
        return False, "no-record"
    reason = ""
    rec = rec_path = None
    for path in entries:
        try:
            with open(path) as f:
                candidate = json.load(f)
        except (OSError, ValueError):
            reason = reason or "unreadable-record"
            continue
        if candidate.get("schema") != SCHEMA:
            reason = reason or "schema"
            continue
        comps = compute_components(step, candidate["deps"], candidate["notfound"],
                                   set(candidate["outputs"]))
        if key_of(comps) == candidate["key"]:
            rec, rec_path = candidate, path
            break
        reason = reason or change_reason(comps, candidate.get("components", []))
    if rec is None:
        return False, reason
    outs = rec["outputs"]
    # Outputs: identical bytes already in place, or restore the verified copy.
    restored = 0
    for path, meta in outs.items():
        sig = stat_sig(path)
        if sig is not None and sig == meta.get("stat"):
            continue
        if sig is not None and file_digest(path) == meta["sha256"]:
            continue
        blob = os.path.join(sdir, "blobs", meta["sha256"])
        if file_digest(blob) != meta["sha256"]:
            return False, f"blob-missing-or-corrupt {path}"
        _hash_cache.pop(path, None)
        copy_bytes(blob, path, meta["mode"])
        restored += 1
    # A hit stands in for running the tool, which would have rewritten every
    # output just now: freshness checks that compare mtimes (the guest-root
    # manifest grades an umbrella dylib "newer than its inputs") must see the
    # same thing. Record the new stat so the next run's fast path still holds;
    # rewriting the entry also marks it most recently used.
    for path, meta in outs.items():
        os.utime(path, None)
        meta["stat"] = stat_sig(path)
    atomic_write(rec_path, json.dumps(rec, indent=0).encode("utf-8", "surrogateescape"))
    for stream, name in ((sys.stdout.buffer, "stdout"), (sys.stderr.buffer, "stderr")):
        digest = rec.get(name)
        if not digest:
            continue
        blob = os.path.join(sdir, "blobs", digest)
        if file_digest(blob) != digest:
            continue
        with open(blob, "rb") as f:
            stream.write(f.read())
        stream.flush()
    which = entries.index(rec_path)
    detail = f"restored={restored}" if restored else "in-place"
    return True, detail + (f" entry={which + 1}" if which else "")


def store_blob(sdir: str, src: str | None, data: bytes | None = None) -> str:
    """Content-addressed copy of a file (or bytes) in the step's blob store."""
    blobs = os.path.join(sdir, "blobs")
    os.makedirs(blobs, exist_ok=True)
    if src is not None:
        _hash_cache.pop(src, None)
        digest = file_digest(src)
    else:
        digest = hashlib.sha256(data or b"").hexdigest()
    blob = os.path.join(blobs, digest)
    if file_digest_uncached(blob) != digest:
        if src is not None:
            copy_bytes(src, blob, 0o644)
        else:
            atomic_write(blob, data or b"")
        if file_digest_uncached(blob) != digest:
            raise RuntimeError(f"blob copy of {src or 'output stream'} does not match")
    return digest


def record(step: Step, sdir: str, deps: list[str], notfound: list[str],
           outputs: list[str], out_stdout: bytes, out_stderr: bytes) -> None:
    out_set = set(outputs)
    metas = {}
    for o in outputs:
        st = os.stat(o)
        if not stat.S_ISREG(st.st_mode):
            raise RuntimeError(f"output is not a regular file: {o}")
        digest = store_blob(sdir, o)
        metas[o] = {"sha256": digest, "mode": stat.S_IMODE(st.st_mode), "stat": stat_sig(o)}
    # Hash inputs AFTER the run, as the run saw them.
    for p in deps:
        _hash_cache.pop(p, None)
    comps = compute_components(step, deps, notfound, out_set)
    key = key_of(comps)
    rec = {
        "schema": SCHEMA, "key": key, "components": comps,
        "argv": [step.tool] + step.argv, "cwd": step.cwd,
        "deps": deps, "notfound": notfound, "outputs": metas,
        "stdout": store_blob(sdir, None, out_stdout),
        "stderr": store_blob(sdir, None, out_stderr),
    }
    os.makedirs(os.path.join(sdir, "entries"), exist_ok=True)
    atomic_write(os.path.join(sdir, "entries", key + ".json"),
                 json.dumps(rec, indent=0).encode("utf-8", "surrogateescape"))
    # Keep the most recently used entries and exactly the blobs they name.
    keep = list_entries(sdir)[:keep_entries()]
    for path in list_entries(sdir)[len(keep):]:
        os.unlink(path)
    referenced = set()
    for path in keep:
        with open(path) as f:
            entry = json.load(f)
        referenced.update(m["sha256"] for m in entry["outputs"].values())
        referenced.update(entry[k] for k in ("stdout", "stderr") if entry.get(k))
    for name in os.listdir(os.path.join(sdir, "blobs")):
        if name not in referenced:
            try:
                os.unlink(os.path.join(sdir, "blobs", name))
            except OSError:
                pass


def file_digest_uncached(path: str) -> str:
    _hash_cache.pop(path, None)
    return file_digest(path)


def cmd_exec(tool: str, argv: list[str]) -> int:
    real_path = os.environ.get("BUILD_FULL_MEMO_REAL_PATH")
    if not real_path:
        print("build_memo: BUILD_FULL_MEMO_REAL_PATH is not set", file=sys.stderr)
        return 2
    real = shutil.which(tool, path=real_path)
    if not real:
        print(f"build_memo: {tool} not found on BUILD_FULL_MEMO_REAL_PATH", file=sys.stderr)
        return 127
    cwd = os.getcwd()
    step = Step(tool, real, argv, cwd)
    t0 = time.time()
    try:
        MODELS[tool](step)
    except Passthrough as why:
        rc = subprocess.call([real] + argv)
        log(f"pass {time.time() - t0:7.2f}s rc={rc} {tool} ({why}) {' '.join(argv)[:200]}")
        return rc
    sid = step_id(step)
    sdir = os.path.join(state_dir(), "steps", sid)
    label = os.path.basename(step.outputs[0]) if step.outputs else "typecheck"
    hit, why = try_hit(step, sdir)
    if hit:
        log(f"hit  {time.time() - t0:7.2f}s {tool} {label} {sid[:12]} {why}")
        return 0
    os.makedirs(sdir, exist_ok=True)
    before = {p: stat_sig(p) for p in step.side_candidates}
    work = tempfile.mkdtemp(dir=sdir, prefix=".run.")
    depfile = os.path.join(work, "deps")
    depfiles = [depfile]
    ofm = os.path.join(work, "ofm.json")
    run_argv = list(argv)
    if step.depfile == "swift":
        depfiles.append(os.path.join(work, "deps-module"))
        merged = {}
        if step.user_ofm:
            with open(step.user_ofm) as f:
                merged = json.load(f)
            run_argv[run_argv.index("-output-file-map") + 1] = ofm
            step.inject = ["-emit-dependencies"]
        whole = dict(merged.get("", {}))
        whole.update({"dependencies": depfiles[0], "emit-module-dependencies": depfiles[1]})
        merged[""] = whole
        with open(ofm, "w") as f:
            json.dump(merged, f)
    subst = {"@DEPFILE@": depfile, "@OFM@": ofm}
    cmd = [real] + run_argv + [subst.get(a, a) for a in step.inject]
    rc, out, err = run_tool(cmd)
    if rc != 0:
        shutil.rmtree(work, ignore_errors=True)
        log(f"fail {time.time() - t0:7.2f}s rc={rc} {tool} {label} {sid[:12]} (not recorded)")
        return rc
    try:
        if step.depfile == "depinfo":
            deps, notfound = parse_dependency_info(depfile)
            deps = [absnorm(p, cwd) for p in deps]
            notfound = [absnorm(p, cwd) for p in notfound]
        else:
            deps = []
            for df in depfiles:
                if os.path.exists(df):
                    deps += [absnorm(p, cwd) for p in parse_make_depfile(df)]
            if not deps:
                raise RuntimeError("the tool wrote no dependency file")
            notfound = []
        shutil.rmtree(work, ignore_errors=True)
        outputs = list(step.outputs)
        for p in step.side_candidates:
            sig = stat_sig(p)
            if sig is not None and sig != before[p]:
                outputs.append(p)
        missing = [o for o in outputs if not os.path.isfile(o)]
        if missing:
            raise RuntimeError(f"declared outputs not written: {missing}")
        record(step, sdir, uniq(deps), uniq(notfound), outputs, out, err)
    except Exception as exc:  # recording must never fail the build
        # No entry was written (entries are written atomically, last), so the
        # next run simply runs the step again.
        shutil.rmtree(work, ignore_errors=True)
        log(f"warn record failed for {label}: {exc}")
        print(f"build_memo: WARNING: {label} not recorded: {exc}", file=sys.stderr)
        return 0
    log(f"miss {time.time() - t0:7.2f}s {tool} {label} {sid[:12]} ({why})")
    return 0


def cmd_summary(path: str) -> int:
    counts: dict[str, int] = {}
    try:
        lines = open(path).read().splitlines()
    except FileNotFoundError:
        lines = []
    for line in lines:
        kind = line.split(" ", 1)[0]
        counts[kind] = counts.get(kind, 0) + 1
    print(" ".join(f"{k}={counts.get(k, 0)}" for k in ("hit", "miss", "pass", "fail", "warn")))
    return 0


def main() -> int:
    if len(sys.argv) >= 3 and sys.argv[1] == "exec":
        tool = sys.argv[2]
        if tool not in MODELS:
            print(f"build_memo: no model for {tool}", file=sys.stderr)
            return 2
        return cmd_exec(tool, sys.argv[3:])
    if len(sys.argv) == 3 and sys.argv[1] == "summary":
        return cmd_summary(sys.argv[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
