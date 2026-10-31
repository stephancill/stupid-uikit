# Story viewer parity (stupid social, iOS-simulator triple)

stupid social's `UnifiedStoryViewer` is a SwiftUI `fullScreenCover` holding a
`NavigationStack { GeometryReader { ZStack { … } } }` whose progress bar runs on
`Timer.publish(every: 1/60)`. Reaching it in the x86_64 iOS-simulator guest
(`tap 0.34 0.26` on the Social page) and comparing with the iOS 27 simulator
(iPhone 16e) found one runtime ABI bug and a set of general SwiftUI/UIKit gaps.
Native gate: `swift run swiftuifullscreencoverprobe` (uikit package). Guest gate:
`full/iostarget/heap_xi_guest.sh` (`IOSHeapXIGuestProbe`, built by
`build_full.sh` on the iOS triple).

## Heap-object extra inhabitants (runtime ABI, iOS-simulator triple)

The guest's x86_64 Swift runtime is built for macOS, where Objective-C reserves
the low pointer bit, so the runtime encodes a heap pointer's extra inhabitant
`i` as `i << 1`. swiftc for `x86_64-apple-ios*-simulator` reserves the high bit
instead and encodes `i` as `i` (MEASURED, swiftc 6.4.2 `-emit-ir -O`, `enum E
{ case a(C), b, c }`: `.c` is `ret i64 1` on the simulator triple, `ret i64 2`
on macOS; same for AnyObject, metatypes and AnyClass). Index 0 (`nil`) agrees;
every second level (`C??`, `[C?]` through `IndexingIterator.next()`,
`[K: URL?]` lookups, `Any??`) written by the runtime's value witnesses as 0x2
was read by guest code as a reference and retained: the story viewer faulted in
`swift_retain(0x2)` reading `previewURLs[trackId]`, and the first navigation
push in `objc_retain(0x2)` (worked around earlier in
`_UITransitionCoordinator.attach`, which can now go back to `for vc in`).

`full/shims/swiftcorepatch.c` (linked into every guest executable; the block is
compiled only for `__APPLE_EMBEDDED_SIMULATOR__` on x86_64) replaces, before any
Swift code runs, the `getEnumTagSinglePayload` / `storeEnumTagSinglePayload`
witnesses of the runtime's heap-pointer value witness tables with ones that
call the runtime's own `swift_{get,store}EnumTagSinglePayloadGeneric` using the
simulator encoding: `Bo`, `BO` (AnyObject, ObjC-compatible classes, one-reference
structs such as URL), `Bb`, thick metatypes, class-bound existentials and
existential metatypes with 1-2 witness tables, opaque existentials (`Any`) with
0-1. Not covered: existentials with 3+ witness tables (runtime-allocated
tables), and macOS-compiled Swift inside the runtime dylibs that builds a
second-level inhabitant concretely. The real fix is a runtime built for the
simulator triple.

`heap_xi_guest.sh` runs 16 checks (iteration, dictionary lookups, each patched
witness family, both directions): all PASS; `--unpatched`
(`OPENUIKIT_KEEP_MACOS_HEAP_EXTRA_INHABITANTS=1`) faults in `swift_retain` on
the first check.

## SwiftUI / UIKit

- `fullScreenCover(isPresented:onDismiss:content:)` and `(item:…)` are native:
  `_OpenPresentationKind.fullScreenCover`, UIKit `.fullScreen` (no dimming or
  sheet platter, the window's frame and safe area). The compat module's
  sheet-based stand-in is gone.
- `_SwiftUIPresentationContainerController` forwards appearance to its hosting
  controller (OpenUIKit does not auto-forward to custom containers), so a
  sheet's or cover's root `onAppear` / `.task` / `onDisappear` run.
- `.toolbar(.hidden, for: .navigationBar)` (and `.automatic`) hides the
  NavigationStack's bar like `navigationBarHidden(true)`.
- Safe area on the iOS cut: a screen-level host (UIHostingController's view, a
  NavigationStack page) lays its content out in its safe area. Scroll views,
  lists, forms, navigation/tab containers and UIKit views/controllers at the
  root extend under it (and inset themselves, as before); `.ignoresSafeArea`
  extends a view whose edge reaches the safe area's edge; `.ignoresSafeArea(.keyboard)`
  alone keeps the container safe area; `background(_:ignoresSafeAreaEdges:)`
  fills into it. Without a device safe area (macOS cut, gates) nothing changes.
- Frames place their content at the content's size, aligned in the frame
  (`.frame(maxHeight: .infinity)` centres a stack instead of pinning it to the top).
- VStack: when ideal heights overflow, children are offered the remaining
  height least-flexible first (SwiftUI's allocation), so a flexible group beside
  a fixed button no longer takes the whole column. HStack: children that take
  every width offered share an overflowing row like spacers (equal progress
  segments).
- GeometryReader content is built during graph evaluation at the size layout
  last placed the reader at (`_OpenGeometryReaderState`), so its views' `@State`,
  `.task`s and appearance actions persist; the first placement or a resize
  builds at layout time and re-evaluates. Before, content built only at layout
  time ran outside the graph: the viewer's CachedAsyncImage avatars never loaded.
- Screenshot status bar: the topmost full-screen controller's
  `preferredStatusBarStyle`; `.default` samples the luminance under the bar
  (iOS 26+ adapts `.default` to the content). MEASURED light ink over black:
  white glyphs, bolt grey 128 with a black rim. The bar stays topmost over
  presentations.
- Automation: `wait <n>s` / `wait <n>ms` (host-clock time), `--no-settle` on
  `tap`/`swipe` (screens with a running timer never settle), and the session
  commits layout every turn while waiting or delivering input (a presentation
  triggered by `--no-settle` waited for the next snapshot's layout).

## Remaining differences (guest vs iOS 27, story at ~2 s)

- Medium/semibold text (`starred …`, `Open on GitHub`, `12.4k`) is heavier:
  missing iOS ink masks for those weights fall back to DejaVu Sans Bold.
- `arrow.up.forward.app` and `speaker.wave.2.fill` are Phosphor approximations.
- Progress fill: the app adds 1/60 s per timer fire; the guest's slower host turns
  fire it less often, so the fill trails (compare geometry, not fill). The
  relative time ("5m"/"6m") follows the wall clock, which a slow run stretches.
