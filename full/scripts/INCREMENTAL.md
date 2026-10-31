# build_full.sh: incremental and parallel builds

`full/scripts/build_full.sh` can skip every compile and link step whose complete
input set is unchanged, and it spreads independent work over the host's cores.

## Switches

| Variable | Default | Effect |
| --- | --- | --- |
| `BUILD_FULL_INCREMENTAL` | `0` | `1` memoizes every `swiftc`, `clang-18 -c`, `clang++-18 -c` and `ld64.lld-18` step (here and in the FE, FI and host-bridge sub-builders). |
| `BUILD_FULL_CLEAN` | `0` | `1` is the cold build: before anything is written it deletes `$OUT`, the step memo, the stage cache and the module cache. |
| `BUILD_FULL_MEMO_DIR` | `$OUT.memo` | Where the memo lives (outside `$OUT`, so no output inventory sees it). |
| `BUILD_FULL_JOBS` | `nproc` | Width of every parallel section, and the ICU job count unless `FOUNDATION_ICU_JOBS` is set. |

Incremental mode is opt-in, like `BUILD_FULL_STAGE_CACHE`: the authority routes
keep compiling everything unless the caller exports `BUILD_FULL_INCREMENTAL=1`
(it passes through `scripts/x86/phase2.sh` and the widget/onboarding gates,
which call this script). A cold build is

```sh
BUILD_FULL_CLEAN=1 bash full/scripts/build_full.sh            # cold, then full
BUILD_FULL_CLEAN=1 BUILD_FULL_INCREMENTAL=1 bash full/scripts/build_full.sh
```

`rm -rf build/full-x86_64.memo` alone also forces every step to run again.

## How a step is skipped

`build_full.sh` puts shims for the four tools first on `PATH`
(`$BUILD_FULL_MEMO_DIR/toolchain/usr/bin`, whose `../lib` links to the real
toolchain so code that locates Swift from `command -v swiftc` still works). Each
shim runs `full/scripts/build_memo.py`, which keys the step by SHA-256 over:

* the toolchain identity (`swiftc`/`clang` versions and binary hashes, computed
  once per build) and the memo tool itself, the working directory and the
  tool-relevant environment;
* the full argv, and the content of every file it names;
* the content of every file the tool reported reading the last time it ran
  (Swift driver dependency files via a whole-module output file map, clang
  `-MD`, ld64.lld `-dependency_info`): sources, every `.swiftmodule` /
  `.swiftinterface`, every header and module map, every linked library;
* negative lookups a dependency file cannot list: every library path ld64.lld
  probed and did not find; for each module name a Swift step imports, tests
  with `canImport`, or loaded, which `<Name>.swiftmodule` / `.swiftinterface` /
  `.framework` / `<Name>/module.modulemap` exist in any search directory
  (including the SDK's); same-relative-path headers anywhere on the header
  search path; module maps at depth one and two of each Clang search
  directory; `.apinotes` beside used module maps; macro plugins and their
  sibling libraries.

Content, never mtimes, is the key: `touch` is not a change. On a hit every
recorded output (side outputs too: `.swiftdoc`, `.swiftsourceinfo`, `.abi.json`,
`-output-file-map` objects) must already hold its recorded SHA-256 or is restored
from the copy kept in the memo, after that copy is re-verified, and gets the
current time as its mtime, exactly as running the tool would (the guest-root
manifest grades an umbrella dylib "newer than its inputs"); the step's recorded
stdout/stderr is replayed. A failed step is never recorded. Typechecks
(the negative guards that must fail) and anything the memo cannot model (links
through clang, response files) always run.

Every gate still runs: only tool invocations are memoized, so each count,
load-list, symbol, inventory and subject check in `build_full.sh` and its
sub-builders inspects the (identical) outputs on every run, and the commit
marker is still removed first and written last.

`$BUILD_FULL_MEMO_DIR/log` lists every step as `hit`, `miss (<first changed
input>)`, `pass (<why not memoized>)` or `fail`; the build ends with a
`build_full: incremental steps hit=… miss=…` summary.

## machorun's loader and userland

The guest root is staged from machorun's built products (`machorun/build/machorun`,
`machorun/darwin/usr/lib`), which are git-ignored. For the in-repo machorun, build_full asks
`machorun/scripts/check_stale.sh` first: the loader and the darwin userland (libSystem.B, libc++.1,
libc++abi) count as current only when the input hash `scripts/build.sh` recorded equals the hash of
their sources now. Otherwise, or with no stamp, it runs `scripts/build.sh loader` or
`scripts/build.sh darwin` + `tbd`, and stops if they are still not current. Before this, a pulled
`machorun/darwin/src` change (the pinned guest clock) staged the old libSystem silently. libobjc
and libquartz are not rebuilt here (`scripts/build.sh objc4` / `quartz`).

## Parallel work (always on)

* FoundationInternationalization's 474 ICU translation units (one alone takes
  ~50 s) need only the pinned sources and the SDK. With the stage cache off,
  the FI builder's `objects` step runs them niced in the background from the
  start; its `finish` step refuses objects built from another source list or
  command. With `BUILD_FULL_STAGE_CACHE=1` the single-step route is kept.
* The `-O` OpenUIKit objects for `host_full` start before the `-Onone`
  OpenUIKit compile (they compile the same sources themselves) and use
  `-num-threads $BUILD_FULL_JOBS`, which keeps whole-module optimization but
  emits one object per source file (`host-opt/openuikit/NNN-<file>.o`, linked
  into `host_full` in source order). Only `host_full` changes bytes.
* The RealAppProbe stub modules and the Focus graph run as a dependency graph
  (`app_dag_add` / `app_dag_run`): two modules keep their sequential order when
  either one's sources name the other (transitively, through `-module-alias`),
  so every compile sees exactly the modules it saw sequentially.
  `BUILD_FULL_JOBS=1` reproduces the old order.
* `APPMODS` starts empty on every run, so no compile can see a module a later
  step left behind in an earlier run.

## Measured (x86_64 Linux host, i5-14600KF, 20 threads, Swift 6.4.2)

Wall time of `build_full.sh` alone. "Before" is the script without these
changes; any rebuild then took a full run.

| Build | Before | After |
| --- | --- | --- |
| cold (`BUILD_FULL_CLEAN=1`) | 212 s | 155 s |
| cold, incremental (`BUILD_FULL_CLEAN=1 BUILD_FULL_INCREMENTAL=1`) | — | 147 s |
| rerun, no change | 195 s | 11–14 s |
| `touch full/shims/concpatch.c` | 195 s | 11–18 s (no step reruns) |
| edit `full/shims/concpatch.c` (new function) | 195 s | 12–16 s (umbrella + 18 dependent links) |
| edit `uikit/Sources/SwiftUI/AppLifecycle.swift` | 195 s | 34–35 s |
| edit `uikit/Sources/OpenUIKit/UIView.swift` | 195 s | 70–72 s |
| revert any of the edits above | 195 s | 12–19 s (an older memo entry) |

Phase 2 rung b passes (`b=PASS/widget+onboarding`, `PHASE2_EXIT=0`) with and
without `BUILD_FULL_INCREMENTAL=1`; with a warm memo it takes 291 s instead of
~510 s.

## Limits

* Each step keeps its 4 most recently used input sets
  (`BUILD_FULL_MEMO_KEEP`), so reverting an edit, or alternating between the
  widget and onboarding gates' different module-cache paths, hits; a fifth
  distinct input set evicts the oldest.
* The memo holds a copy of every output version it keeps (about 0.6 GB per
  input set of the whole build, next to a ~0.8 GB `$OUT`; outputs shared by
  several input sets are stored once).
* A hit restores the `.swiftsourceinfo` of the run that recorded it, which
  carries that run's source mtimes (a `touch` alone does not rebuild).
* Steps skipped on a hit do not repopulate module caches they would have
  written into (`fi-work/.../module-cache`): those are caches, not outputs.
* A `__has_include` that was false and turns true without any other input
  changing is not detected; the header search directories involved are the
  pinned SDK and the project's own include trees.
* libxml2 is built by its own CMake/ninja (already incremental) with the real
  compilers, because CMake caches the compiler path.
