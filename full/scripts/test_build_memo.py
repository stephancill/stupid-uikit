#!/usr/bin/env python3
"""Behavioural tests for full/scripts/build_memo.py (BUILD_FULL_INCREMENTAL=1).

Each test drives the memo exactly the way build_full.sh's PATH shims do
(`build_memo.py exec <tool> <argv...>` with BUILD_FULL_MEMO_* set) and checks
the property that makes reuse safe: a step is replayed only when its complete
input set is unchanged, and a replay leaves exactly the recorded bytes.

Needs clang-18 and ld64.lld-18 on PATH (the Linux builders); the Swift cases
also need swiftc and a Darwin compile sysroot (BUILD_MEMO_TEST_SDK, default
scratch/sysroot_fe4-x86_64 in this checkout). Missing tools skip.

Usage: python3 full/scripts/test_build_memo.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MEMO = ROOT / "full/scripts/build_memo.py"
SDK = Path(os.environ.get("BUILD_MEMO_TEST_SDK", ROOT / "scratch/sysroot_fe4-x86_64"))
TARGET = os.environ.get("BUILD_MEMO_TEST_TARGET", "x86_64-apple-macos15.0")


def have(tool: str) -> bool:
    return shutil.which(tool) is not None


class MemoCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="build-memo-test."))
        self.state = self.tmp / "memo"
        self.state.mkdir()
        self.env = dict(os.environ)
        self.env.update({
            "BUILD_FULL_MEMO_DIR": str(self.state),
            "BUILD_FULL_MEMO_REAL_PATH": os.environ["PATH"],
            "BUILD_FULL_MEMO_SALT": "test-salt",
        })

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def memo(self, tool: str, *argv: str, check: bool = True) -> subprocess.CompletedProcess:
        log = self.state / "log"
        before = log.read_text() if log.exists() else ""
        proc = subprocess.run(
            [sys.executable, "-B", str(MEMO), "exec", tool, *argv],
            cwd=self.tmp, env=self.env, capture_output=True, text=True)
        after = log.read_text() if log.exists() else ""
        proc.memo_line = after[len(before):].strip()  # type: ignore[attr-defined]
        if check:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc

    def kind(self, proc: subprocess.CompletedProcess) -> str:
        return proc.memo_line.split(" ", 1)[0]  # type: ignore[attr-defined]

    def write(self, rel: str, text: str) -> Path:
        p = self.tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p


@unittest.skipUnless(have("clang-18"), "clang-18 not on PATH")
class ClangSteps(MemoCase):
    def compile(self, *extra: str, check: bool = True) -> subprocess.CompletedProcess:
        return self.memo("clang-18", *extra, "-Ia", "-Ib", "-c", "src/f.c", "-o", "out/f.o",
                         check=check)

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "out").mkdir()
        (self.tmp / "a").mkdir()
        self.write("b/v.h", "#define V 1\n")
        self.write("src/f.c", '#include "v.h"\nint f(void) { return V; }\n')

    def test_hit_after_miss_and_touch_is_not_a_change(self) -> None:
        self.assertEqual(self.kind(self.compile()), "miss")
        first = (self.tmp / "out/f.o").read_bytes()
        self.assertEqual(self.kind(self.compile()), "hit")
        os.utime(self.tmp / "b/v.h")
        os.utime(self.tmp / "src/f.c")
        self.assertEqual(self.kind(self.compile()), "hit")
        self.assertEqual((self.tmp / "out/f.o").read_bytes(), first)

    def test_hit_refreshes_output_mtime_like_a_run(self) -> None:
        self.compile()
        old = 1_000_000_000
        os.utime(self.tmp / "out/f.o", (old, old))
        self.assertEqual(self.kind(self.compile()), "hit")
        self.assertGreater((self.tmp / "out/f.o").stat().st_mtime, old + 1)
        self.assertEqual(self.kind(self.compile()), "hit")

    def test_header_content_change_rebuilds(self) -> None:
        self.compile()
        self.write("b/v.h", "#define V 2\n")
        proc = self.compile()
        self.assertEqual(self.kind(proc), "miss")
        self.assertIn("b/v.h", proc.memo_line)

    def test_shadowing_header_in_earlier_search_dir_rebuilds(self) -> None:
        self.compile()
        self.write("a/v.h", "#define V 3\n")
        proc = self.compile()
        self.assertEqual(self.kind(proc), "miss")
        self.assertIn("a/v.h", proc.memo_line)

    def test_revert_hits_an_older_entry(self) -> None:
        self.compile()
        first = (self.tmp / "out/f.o").read_bytes()
        self.write("b/v.h", "#define V 2\n")
        self.assertEqual(self.kind(self.compile()), "miss")
        self.write("b/v.h", "#define V 1\n")
        proc = self.compile()
        self.assertEqual(self.kind(proc), "hit")
        self.assertIn("entry=2", proc.memo_line)
        self.assertEqual((self.tmp / "out/f.o").read_bytes(), first)

    def test_entries_are_bounded_and_unreferenced_blobs_dropped(self) -> None:
        self.env["BUILD_FULL_MEMO_KEEP"] = "2"
        for v in range(4):
            self.write("b/v.h", f"#define V {v + 10}\n")
            self.assertEqual(self.kind(self.compile()), "miss")
        entries = list(self.state.glob("steps/*/entries/*.json"))
        self.assertEqual(len(entries), 2)
        referenced = set()
        for e in entries:
            rec = json.loads(e.read_text())
            referenced.update(m["sha256"] for m in rec["outputs"].values())
            referenced.update((rec["stdout"], rec["stderr"]))
        blobs = {b.name for b in self.state.glob("steps/*/blobs/*")}
        self.assertEqual(blobs, referenced)

    def test_flag_change_rebuilds(self) -> None:
        self.compile()
        self.assertEqual(self.kind(self.compile("-O2")), "miss")

    def test_clobbered_output_is_restored_byte_for_byte(self) -> None:
        self.compile()
        good = (self.tmp / "out/f.o").read_bytes()
        (self.tmp / "out/f.o").write_bytes(b"stale")
        proc = self.compile()
        self.assertEqual(self.kind(proc), "hit")
        self.assertIn("restored=1", proc.memo_line)
        self.assertEqual((self.tmp / "out/f.o").read_bytes(), good)
        (self.tmp / "out/f.o").unlink()
        self.assertEqual(self.kind(self.compile()), "hit")
        self.assertEqual((self.tmp / "out/f.o").read_bytes(), good)

    def test_corrupt_blob_is_never_restored(self) -> None:
        self.compile()
        entries = list(self.state.glob("steps/*/entries/*.json"))
        self.assertEqual(len(entries), 1)
        meta = json.loads(entries[0].read_text())["outputs"][str(self.tmp / "out/f.o")]
        blob = entries[0].parent.parent / "blobs" / meta["sha256"]
        blob.write_bytes(b"corrupt")
        (self.tmp / "out/f.o").unlink()
        self.assertEqual(self.kind(self.compile()), "miss")

    def test_failure_is_not_recorded_and_keeps_its_status(self) -> None:
        self.write("src/f.c", "int f(void) { return }\n")
        proc = self.compile(check=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self.kind(proc), "fail")
        self.assertFalse(list(self.state.glob("steps/*/entries/*.json")))
        proc = self.compile(check=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self.kind(proc), "fail")

    def test_diagnostics_are_replayed_on_a_hit(self) -> None:
        self.write("src/f.c", "int f(int x) { int unused; return x; }\n")
        first = self.compile("-Wunused-variable")
        self.assertIn("unused", first.stderr)
        second = self.compile("-Wunused-variable")
        self.assertEqual(self.kind(second), "hit")
        self.assertEqual(second.stderr, first.stderr)

    def test_link_through_clang_is_not_memoized(self) -> None:
        proc = self.memo("clang-18", "src/f.c", "-shared", "-o", "out/libf.so", check=False)
        self.assertEqual(self.kind(proc), "pass")


@unittest.skipUnless(have("clang-18") and have("ld64.lld-18") and (SDK / "usr/lib").is_dir(),
                     f"clang-18/ld64.lld-18 or the Darwin sysroot {SDK} is missing")
class LinkSteps(MemoCase):
    def setUp(self) -> None:
        super().setUp()
        for d in ("l1", "l2", "out"):
            (self.tmp / d).mkdir()
        self.write("g.c", "int g(void) { return 1; }\n")
        self.write("f.c", "int g(void);\nint f(void) { return g(); }\n")
        for src, obj in (("g.c", "g.o"), ("f.c", "f.o")):
            subprocess.run(["clang-18", "-target", TARGET, "-c", src, "-o", obj],
                           cwd=self.tmp, check=True)
        subprocess.run(["ld64.lld-18", "-arch", TARGET.split("-")[0], "-platform_version",
                        "macos", "15.0", "15.0", "-dylib", "-install_name", "/x/libg.dylib",
                        "-o", "l2/libg.dylib", "g.o"], cwd=self.tmp, check=True)

    def link(self) -> subprocess.CompletedProcess:
        return self.memo("ld64.lld-18", "-arch", TARGET.split("-")[0], "-platform_version",
                         "macos", "15.0", "15.0", "-syslibroot", str(SDK), "-dylib",
                         "-install_name", "@rpath/libf.dylib", "-Ll1", "-Ll2", "-lg",
                         "-lSystem", "-o", "out/libf.dylib", "f.o")

    def test_hit_and_install_name_tokens_are_not_response_files(self) -> None:
        self.assertEqual(self.kind(self.link()), "miss")
        self.assertEqual(self.kind(self.link()), "hit")

    def test_library_appearing_earlier_on_the_search_path_relinks(self) -> None:
        self.link()
        shutil.copy(self.tmp / "l2/libg.dylib", self.tmp / "l1/libg.dylib")
        proc = self.link()
        self.assertEqual(self.kind(proc), "miss")
        self.assertIn("l1/libg", proc.memo_line)

    def test_linked_dylib_content_change_relinks(self) -> None:
        self.link()
        self.write("g.c", "int g(void) { return 2; }\nint h(void) { return 3; }\n")
        subprocess.run(["clang-18", "-target", TARGET, "-c", "g.c", "-o", "g.o"],
                       cwd=self.tmp, check=True)
        subprocess.run(["ld64.lld-18", "-arch", TARGET.split("-")[0], "-platform_version",
                        "macos", "15.0", "15.0", "-dylib", "-install_name", "/x/libg.dylib",
                        "-o", "l2/libg.dylib", "g.o"], cwd=self.tmp, check=True)
        self.assertEqual(self.kind(self.link()), "miss")


@unittest.skipUnless(have("swiftc") and (SDK / "usr/lib/swift").is_dir(),
                     f"swiftc or the Darwin sysroot {SDK} is missing")
class SwiftSteps(MemoCase):
    def compile(self, *srcs: str) -> subprocess.CompletedProcess:
        return self.memo("swiftc", "-target", TARGET, "-sdk", str(SDK),
                         "-module-cache-path", str(self.tmp / "mc"),
                         "-runtime-compatibility-version", "none", "-wmo", "-parse-as-library",
                         "-I", "mods", "-module-name", "M",
                         "-emit-module", "-emit-module-path", "out/M.swiftmodule",
                         "-emit-object", "-o", "out/m.o", *srcs)

    def setUp(self) -> None:
        super().setUp()
        for d in ("mods", "out"):
            (self.tmp / d).mkdir()
        self.write("a.swift", "public func a() -> Int { 1 }\n")
        self.write("b.swift", "#if canImport(Extra)\npublic let extra = true\n#else\n"
                              "public let extra = false\n#endif\n")

    def test_side_outputs_recorded_and_restored(self) -> None:
        self.assertEqual(self.kind(self.compile("a.swift", "b.swift")), "miss")
        doc = (self.tmp / "out/M.swiftdoc").read_bytes()
        (self.tmp / "out/M.swiftdoc").unlink()
        proc = self.compile("a.swift", "b.swift")
        self.assertEqual(self.kind(proc), "hit")
        self.assertEqual((self.tmp / "out/M.swiftdoc").read_bytes(), doc)

    def test_canimport_target_appearing_rebuilds(self) -> None:
        self.compile("a.swift", "b.swift")
        self.assertEqual(self.kind(self.compile("a.swift", "b.swift")), "hit")
        subprocess.run(["swiftc", "-target", TARGET, "-sdk", str(SDK),
                        "-module-cache-path", str(self.tmp / "mc"),
                        "-runtime-compatibility-version", "none", "-parse-as-library",
                        "-module-name", "Extra", "-emit-module",
                        "-emit-module-path", "mods/Extra.swiftmodule", "a.swift"],
                       cwd=self.tmp, check=True, capture_output=True)
        proc = self.compile("a.swift", "b.swift")
        self.assertEqual(self.kind(proc), "miss")
        self.assertIn("Extra.swiftmodule", proc.memo_line)

    def test_typecheck_is_never_memoized(self) -> None:
        proc = self.memo("swiftc", "-target", TARGET, "-sdk", str(SDK),
                         "-module-cache-path", str(self.tmp / "mc"), "-typecheck", "a.swift")
        self.assertEqual(self.kind(proc), "pass")


if __name__ == "__main__":
    unittest.main(verbosity=2)
