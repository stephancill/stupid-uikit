# The swift.org release runtime on aarch64 Linux hosts

An aarch64 Linux build host does not cross-build the Darwin stdlib (`build_stdlib.sh`). It runs the
Swift project's own prebuilt Darwin runtime, from the swift.org 6.4.2 macOS toolchain package, and
builds only the Darwin SDK overlays that package does not carry.

## Fetch: `scripts/fetch_release_runtime.sh`

Downloads `swift-6.4.2-RELEASE-osx.pkg` (pinned by URL and SHA-256), unpacks it with bsdtar (xar +
gzip cpio, so it runs on Linux) and stages the artifacts layout `phase2.sh` reads
(`phase2_swiftcore_artifacts`, default `build/release-runtime` on aarch64): `swift-macosx/arm64/` for
libswiftCore, _Concurrency, _Builtin_float, _RegexParser, _StringProcessing, Observation,
Synchronization and SwiftOnoneSupport, and `swift-macosx/<Module>.swiftmodule/` for their macOS
modules. `SOURCE.txt` records the package and every staged file's SHA-256.

**The dylibs are the iOS-simulator slices, retargeted to macOS.** Measured:

- The macOS arm64 libswiftCore reads Darwin's thread-specific data inline from `TPIDRRO_EL0` (two
  sites, `swift_beginAccess`'s TLS among them). A Linux process cannot give that register a Darwin
  TSD base: under machorun the read returns 0 and `swift_beginAccess` faults at `0x358`.
- The iOS-simulator slices (libswiftCore, _Concurrency) have no such reads; they reach TSD through
  `pthread_getspecific`, which machorun's userland implements. They also carry no crash backtracer
  (the macOS slice's `posix_spawn`, `task_threads`, `thread_suspend`, ... imports).
- Their exports equal the macOS slices' apart from `$ld$previous` linker markers and two Mac Catalyst
  variant availability checks no macOS-triple code calls.

They are retargeted to the macOS slice's `LC_BUILD_VERSION` (platform 1) like the rest of the base
runtime root; `build_full.sh` retargets the root to the iOS simulator for an iOS triple.

## Overlays: `scripts/build_release_overlays.sh`

The package has no Darwin SDK overlays (Apple ships them in the OS and SDK). The script builds the
six the x86_64 artifacts carry, against the release runtime:

- `_DarwinFoundation1/2/3`, `_errno` and `ObjectiveC` through `build_sdk_overlays.sh`, in the SDK
  `stage_sdk.sh` assembles (the one `build_stdlib.sh` uses). phase2's `*-fe-clang` FE sysroot cannot
  stand in: its Darwin and `_DarwinFoundation1` Clang modules form a cycle (`errno.h` ->
  `sys/wait.h`).
- `Darwin` from the Swift 6.2.4 stdlib's `stdlib/public/Platform` sources (Swift 6.4 no longer has
  the Darwin overlay in its tree), with the stdlib's `-define-availability` macros.

## libSystem surface

The release runtime is configured as Apple configures it, so machorun's libSystem
(`darwin/src/libsystem.c`) gained: `_availability_version_check` (against the 26.1.0
`os_system_version_get_current_version` reports), `os_log_create`, `os_signpost_enabled` (false: no
signpost backend), `os_signpost_id_generate`, `_os_signpost_emit_with_name_impl` (unreachable; loud),
`asl_log` (stderr), `csops` (an unsigned process), and the 128-bit division builtins, which Darwin's
libSystem re-exports from libcompiler_rt and libswiftCore binds two-level. `os_log_create`,
`os_signpost_*`, `csops` and the division builtins left `sdk/compat/swiftcompat.c`. The macOS
backtracer's process and Mach thread calls are `src/host_deny.c` rows.

## Verification (aarch64 OrbStack VM, Ubuntu 24.04)

- machorun fixtures: 70 pass, 0 fail, 1 xfail, 1 no-oracle (as before the change).
- `scripts/swift_gate.sh`'s fixture against the release runtime, both link orders: byte-identical to
  `tests/expected/swift_class.stdout`. A 128-bit division probe prints what native macOS prints.
- phase 2 rung b: `b=PASS/widget+onboarding under ARM64 loader`.
