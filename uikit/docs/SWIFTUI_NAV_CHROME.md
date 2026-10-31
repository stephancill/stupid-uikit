# iOS navigation chrome parity (device safe area, status bar, large titles, toolbar groups)

Reference: stupid social's root screen on an iOS 27 iPhone 16e simulator (390 x 844 pt @3x,
status-bar preset, light), compared at 2x with the x86_64 iOS-simulator guest
(`TARGET=x86_64-apple-ios26.0-simulator`, offline demo data).

## What changed

| area | change |
| --- | --- |
| device model | `OpenUIKitDeviceModel` (`OpenUIKit/DeviceModel.swift`) is the one table of devices a host renders as: screen size, scale, portrait safe area (iPhone 16e 47/34, 16 59/34, 16 Pro and Pro Max 62/34, SE 3 20/0). `OpenUIKitRuntime.configureDevice(_:)` configures `UIScreen.main`, the `UIImage(named:)` scale, and makes every `UIWindow(windowScene:)` (the SwiftUI `App` and scene-manifest paths) report the device's safe area. Nothing reads it unless a host configures a device, so existing hosts keep zero window insets. |
| status bar | `UIWindow._installScreenshotStatusBar(time:)` draws the simulator's screenshot preset (fixed time, full cellular, Wi-Fi, charging battery) over the window's top inset as its topmost subview. Geometry measured from the reference screenshot (`OpenUIKit/UIStatusBarScreenshot.swift`). Host-requested only. |
| large titles | A SwiftUI `NavigationStack` follows SwiftUI's display modes on the iOS cut: `.automatic` inherits the closest explicit mode below it in the stack and is large at the root, `.inline` opts out, `.large` in; a destination without a title keeps the inline bar. The macOS cut keeps large titles opt-in (`.large` only). UIKit's existing large-title bar (54 + 52 pt, 34 pt bold title) does the layout. |
| ToolbarItemGroup | Native `ToolbarItemGroup`: each view of the group is its own bar item at the group's placement (it was a compat-module `ToolbarItem { HStack { ... } }`, which became one bar item showing only the first symbol). Trailing items keep SwiftUI's declaration order (first declared is leading-most). |
| shared glass platter | Adjacent SwiftUI symbol items on one side of the bar share one platter (`UIBarButtonItem._sharesSwiftUISymbolPlatter`); a `ToolbarSpacer` or a non-symbol item ends a run, and a lone symbol item keeps its measured isolated 44 pt platter (Hackers). Measured: a two-item group is a 108 x 44 platter, 50 pt item views, 8 pt gap. |
| page view controller | `UIPageViewController`'s queuing scroll view uses `contentInsetAdjustmentBehavior = .never`, and a `.never` scroll view no longer rebases its offset when its safe area changes. Before, the queue rested at offset -47 once the window had a safe area, so its pages (stupid social's NavigationStacks) lost the top inset and the bar sat at y 10. |
| plain List rows | A top-level row of a plain List with its own `listRowInsets` drops the default 15/16 pt row insets, as the rows of a plain Section already did (stupid social's story bar row: 23 pt top inset became 8, its own padding). |

Hosts: the stupid social harness (`stupid-social-guest.sh`, stupid-app-preview) sets
`SSG_DEVICE` (default `iphone16e`) and `SSG_STATUS_BAR` (default `screenshot`,
`SSG_STATUS_BAR_TIME` default `09:41`, the reference simulator's 24-hour locale), and drops the
compat module's `ToolbarItemGroup`.

## Measurements (points, ink bounding boxes at 2x)

| element | simulator | guest before | guest after |
| --- | --- | --- | --- |
| status bar time | [42.5, 20, 84.5, 32] | none | [42, 20, 84.5, 32] |
| cellular + Wi-Fi | [285.5, 19, 329, 32.5] | none | [285.5, 19, 329, 32] |
| battery | [335.5, 19.5, 363.5, 32.5] | none | [335.5, 19.5, 363.5, 32.5] |
| toolbar platter | [266.67, 47, 108, 44] | one 44 pt circle at y 10 (search only) | [266, 47, 108, 44] |
| search glyph | [281, 58.5, 301.5, 79.5] | [342, 23, 362, 41.5] | [281, 60, 301, 78.5] |
| gear glyph | [336, 57, 360.5, 81.5] | missing | [337, 57.5, 360.5, 80.5] |
| title "Social" | [17.5, 112, 110.5, 137] large, leading | inline [172, 24.5, 218, 37.5] | [17.5, 112, 110.5, 137.5] |
| "All Stories" | x 16.67, top 163.5 | x 32.5, top 89.5 | x 16.67, top 163.5 |
| first feed row icon | top 297.5 | top 240 | top 298.5 |

Remaining differences in this region: the search symbol is the bar's lighter `.search` stamp;
the gear is the open-symbol (Phosphor) approximation. The iOS 27 platter's grey rim and lighter
shadow are drawn when a host sets `OpenUIKitRuntime.chromeRelease = .iOS27`
(docs/SHAPE_STROKES.md, "iOS 27 platter rim"); the default `.iOS26` keeps the measured iOS 26.1
platter, which has neither.

## Version notes

The guest presents iOS 26.1; the reference is iOS 27. The bar metrics (54 pt content row, 52 pt
large-title zone, 16 pt side margin, 8 pt grouped gap) are UIKit's measured iOS 26.1 numbers and
match the iOS 27 screenshot to within 1 pt. The 50 pt grouped SwiftUI item width and the status
bar geometry are measured on iOS 27 only.

Revised in `ROOT_SCREEN_RESIDUALS.md`: the iOS 27 rim lies outside the platter, so the reference
capsule is a 106.67 pt frame at the 16 pt margin; on the iOS 27 chrome grouped SwiftUI symbols are
UIKit image items (image width + 22) and `magnifyingglass` is a symbol image item, not the `.search`
stamp. The iOS 26 chrome keeps the 50 pt items.

## Verification

- `swift run swiftuinavchromeprobe` (uikit package, native): display modes, ToolbarItemGroup
  items/order/platter, spacer separation, device safe area, status bar install (21 checks).
- stupid social iOS-triple 2x render against the simulator screenshot (table above).
- Phase 2 rung b on the macOS triple.

## Risks

- Large titles now apply to every iOS-cut SwiftUI `NavigationStack` with a title and no explicit
  `.inline`; screens that relied on the inline bar get the 106 pt large-title bar, as on iOS.
- Grouped platters apply to any two adjacent SwiftUI toolbar symbol items, not only
  ToolbarItemGroups; this is iOS 26 behaviour, but only the two-item group is measured.
- Large-title collapse on scroll was not exercised against the simulator for SwiftUI Lists.
- The screenshot status bar is drawn for a notch device; Dynamic Island and home-button devices
  reuse its geometry centred in their inset.
- Found on the way: the first `_openGroupAdjacentSymbolItems` (a nested function capturing a local
  array, with `defer`) crashed in `objc_retain` on a bogus pointer in the x86_64 iOS-triple guest
  while the same code passed natively; it is written as an index loop now. The miscompile or
  runtime cause was not isolated.
