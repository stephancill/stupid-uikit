# iOS-simulator triple on the x86_64 guest (Swift 6.4.2)

**Date:** 2026-10-31. **Branch:** `ios-triple` (on `swift64`).
**Host:** x86_64 Linux, Swift 6.4.2, clang/lld-18. **SDK input:** Xcode 27's iPhoneSimulator27.0 SDK (a local subset, never committed).

## Status

`build_full.sh` builds for `TARGET=x86_64-apple-ios26.0-simulator` (Mach-O `LC_BUILD_VERSION`
platform 7, minos 26.0, sdk 26.1) beside the macOS-triple build, and its outputs run under
machorun on x86_64. App code compiled for this triple takes its `#if os(iOS)` branches.

- `IOSTargetGuestProbe` under machorun matches the iOS 26.1 simulator transcript
  (`full/iostarget/oracle-ios26.1.txt`, all 14 lines including `#available` 26.2 no / 27.0 no).
- stupid social (stupid-app-preview's `stupid-social-guest.sh` with `TARGET` set to the iOS triple)
  compiles unmodified, including the 22 `#if os(iOS)` sites, links, runs and renders its root screen
  with the plain-list feed its iOS build uses.
- The macOS triple is unchanged: phase 2 rung b passes on this branch.

## Using it

```bash
# once per SDK: stage the compile sysroot (scratch/sysroot_fe4-x86_64-iossim) and the Darwin
# overlays (scratch/apple-overlays-x86_64-iossim) over the macOS x86_64 sysroot
IOS_SDK=<local iPhoneSimulator SDK subset> W=$PWD bash scripts/x86/stage_ios_sim_sysroot.sh
# build (outputs: build/full-x86_64-iossim, scratch/mrroot_full-x86_64-iossim)
TARGET=x86_64-apple-ios26.0-simulator bash full/scripts/build_full.sh
```

The SDK subset is `usr/lib/swift/*.swiftmodule/x86_64-apple-ios-simulator.swift{interface,doc}`,
`usr/lib/swift/*.tbd`, `usr/lib/{libSystem.B,libobjc.A}.tbd` and `SDKSettings.json` (the script
header has the `tar` line). Apple SDK files stay on the build host.

## Design

| question | answer |
|---|---|
| paths | `guest_arch.inc` derives the OS from `TARGET`: `GUEST_LINK_PLATFORM` (`macos`/`ios-simulator`), `GUEST_MINOS` (the triple's version), `SWIFT_MODULE_TRIPLE`. An x86_64 iOS-simulator build appends `-iossim` to `FULL_OUT_SUFFIX` (build/full, scratch/sysroot_fe4, mrroot_full, modcache, memo). `RUNTIME_SOURCE_SUFFIX` keeps the runtime inputs (scratch/mrroot, mrroot_fe, the OpenCombine export) per architecture: build_full copies them and retargets its private copies to platform 7, as the arm64 iOS route does. |
| build_full defaults | `MINOS`/`LINK_PLATFORM` from `guest_arch.inc`; `LINK_SDK_VERSION` 26.1 on the simulator (what `ios_availability.c` presents); `APPLE_SWIFT_USER_OVERLAYS` defaults to `scratch/apple-overlays-x86_64-iossim`; the four are exported because FoundationInternationalization's sub-build reads them from the environment (MEASURED: without the export it linked for macOS, "has platform iOS Simulator, which is different from target platform macOS"). |
| sysroot | `stage_ios_sim_sysroot.sh` runs the arm64 route's `stage_true_ios_full_sdk.sh` (now `STAGE_TRUE_IOS_ARCH`-aware) over the macOS x86_64 sysroot: Apple's iOS-simulator interfaces for Swift, `_Concurrency`, `_StringProcessing`, `Synchronization`, `Observation`, `SwiftOnoneSupport`, `_Builtin_float` in the SDK, and the Darwin/ObjectiveC overlays as `-I` modules. |
| link inputs | Every `.tbd` the macOS sysroot generated from the guest's own dylibs replaces Apple's, retargeted to `x86_64-ios-simulator`, so the link binds what the open-source 6.4.2 runtime under machorun exports (a symbol only Apple's runtime has fails at link time, not at load). Only `libswiftSwiftOnoneSupport.tbd` stays Apple's (the macOS sysroot has a dylib, no `.tbd`). |
| Swift's interface | Apple's iOS-simulator `Swift.swiftinterface`, as on arm64. The guest's source-built macOS interface (which matches the runtime) was tried and fails: it was emitted for macOS x86_64, which has no `Float16`, and Apple's iOS-simulator `Synchronization` interface needs `Float16` (MEASURED: "value of type 'Float16' has no member 'bitPattern'"). Consequence: stdlib SPI (e.g. `String._nfd`) is not visible on this triple. |
| machorun | No change: it loads platform-7 x86_64 images. |

## Port fixes found by stupid social on this triple

| change | why |
|---|---|
| `scrollContentBackground(_:)` (`.hidden` clears the List/Form background) | FeedView, NotificationDetailView, ProfileDetailView (`#if os(iOS)`). |
| A Section in a `.plain` List has no grouped chrome (no grouped background, no 12 pt gaps, transparent rows) and, on the iOS cut, spans the list width with its rows taking the plain row padding; `.automatic` lists are unchanged. | The feed rendered grey grouped sections under `.listStyle(.plain)`. |
| `listRowInsets(_:)` is its own modification (still laid out as padding); a plain-list section row that carries it gets no default insets | SwiftUI replaces the default row insets; stupid social's feed rows use 8/12 pt. |
| OpenUIKit's `AttributeDynamicLookup` subscript for `OpenUIKitAttributes` is internal on the iOS triple | The literal `UIKit` module declares Apple's complete, equally disfavoured `UIKitAttributes` lookup; two disfavoured candidates made `attributed.font = UIFont…` ambiguous. |
| The guest's `[UInt8]` `pngData()`/`jpegData(compressionQuality:)` are disfavoured | A `Data?` overload added on top lost wherever the call had no type context. |

## Open

- The x86_64 Swift runtime is built for macOS, where x86_64 has no `Float16`; the iOS-simulator interface declares it, so app code using `Float16` would fail to link (honestly) on this triple.
- `ios_availability.c` presents iOS 26.1; the iOS 27 SDK's own `@available(iOS 27…)` paths take their fallbacks.
- No iOS-simulator screenshot comparison yet: the plain-list geometry follows SwiftUI's rules and the app's explicit insets, not a measured golden.
