# Root-screen residuals (iOS 27)

Follow-up to `SWIFTUI_TEXT_METRICS.md` and `SHAPE_STROKES.md`: the remaining differences between
stupid social's root screen (x86_64 iOS-simulator guest, 2x, network on, `SSG_CHROME=ios27`) and
the iOS 27.0 simulator reference (iPhone 16e, 390 x 844 pt @3x, demo mode, status bar preset).
Measurements are ink bounding boxes in points, guest at 2x against the reference at 3x.

## Scale variants in `UIImage(contentsOfFile:)`

UIKit's documented `imageWithContentsOfFile:` lookup: on a screen with a scale above 1, a path
without a scale suffix first tries the same name with the screen's `@Nx` suffix and loads it at
that scale; otherwise the unmodified path at the scale its own suffix names (1 without one).
OpenUIKit only read the suffix of the path it was given. stupid social's network badges
(`Bundle.main.path(forResource: "XBadge", ofType: "png")` then `UIImage(contentsOfFile:)`) drew
from the 14 px 1x file. The screen scale is `OpenUIKitRuntime.imageScreenScale`
(`configureDevice` sets it, 3 for the iPhone 16e), so the guest now loads `@3x` as iOS does.
Lower-scale fallbacks (`@2x` on a 3x screen) and `~iphone` device modifiers are not tried: the
documented rule names only the screen's scale. `UIImage(named:)` and `UIImage(named:in:compatibleWith:)`
already preferred the screen-scale variant (`loadNamed`).

Badge region RMSE against the reference (2x, 14 x 14 pt): Instagram 0.146 → 0.045, Bluesky
0.099 → 0.088, X 0.209 → 0.189 (the X badge also sits 0.5 pt right).

## iOS 27 glass platter: rim outside, grouped item widths

`SHAPE_STROKES.md` placed the iOS 27 rim inside the platter's outline and inferred a 108 pt
grouped platter with 50 pt items. Re-measured at 3x, the rim is a 0.5 pt band just outside the
glass: a lone 44 pt back button (search screen reference) at x 16 shows its full-strength rim
pixel at px 47 and a half-covered one at 46 (band [15.5, 16] pt), glass from px 48 (16 pt) to 180
(60 pt); the trailing filter button and the root toolbar capsule show the same. So the capsule's
frame is [267.33, 47, 106.67, 44] with the 16 pt trailing margin, not [266.67, 108] at 15.33.

- `_UIBarPlatterRimView.frame(around:)`: the rim view is the platter's bounds grown by the rim
  width and draws its own outer band (iOS 27 chrome only, as before).
- `_UIBarMetrics.iOS27GroupedSymbolWidth`: on the iOS 27 chrome a SwiftUI symbol in a shared
  platter run is as wide as a UIKit image item, `max(22, image width) + 2 x 11`, with the 8 pt
  grouped gap. Evidence: the magnifier's 17 / medium / large image is 25.67 pt (harvested 3x
  mask, ink centred), which puts its item at [267.33, 315] and its ink centre at 291.17, the
  reference's exactly; equal 49.33 pt items would put it at 292.33. The gear item then ends at
  374 with its ink centre on the reference's 348.33 for a ~29.3 pt image: iOS 27 redrew `gear`
  (ink 24.67 wide there, 23.67 in the iOS 26.1 mask the guest has). The iOS 26 chrome keeps
  `swiftUIGroupedSymbolWidth` (50).
- A SwiftUI `Image(systemName: "magnifyingglass")` toolbar item is a symbol image item on the
  iOS 27 chrome, like the gear, instead of UIKit's lighter `.search` bar stamp (ink 20.33 x 18.67
  pt; the reference's is 21 x 21, the 17 / medium / large symbol's).

| element | reference | before | after |
| --- | --- | --- | --- |
| capsule (visible, incl. rim) | [266.67, 46.67, 374.67, 91.67] | [266, 47, 374, 91] | [267.5, 46.5, 374.5, 91.5] |
| search ink | [280.67, 58.67, 301.67, 79.67] | [281, 60, 301, 78.5] (stamp) | [281.5, 58.5, 302.5, 79.5] |
| gear ink | [336, 57, 360.67, 81.67] | [337, 57, 360.5, 80.5] | unchanged |

The capsule's left edge and the search glyph stay 0.8 pt right because the guest's gear image is
the iOS 26.1 one (28 pt at 2x): its item is ~1.3 pt narrower than iOS 27's. An iOS 27 symbol
harvest of `gear|17|medium|large` would close both.

## iOS 27 hierarchical styles

`.foregroundStyle(.secondary)` text on the reference draws its full-coverage pixels at exactly
(127, 127, 127): black at 0.5 over white. UIKit's `secondaryLabel` is (138, 138, 142) (the app's
UIKit page dots in the same screenshot), which the guest drew. The `.tertiary` chevron symbol is
(191, 191, 191), black at 0.25 (`tertiaryLabel` is (197, 197, 199)). With
`OpenUIKitRuntime.chromeRelease == .iOS27`, light appearance, `_OpenHierarchicalShapeStyle`
resolves `.secondary` and `.tertiary` to `UIColor.label` at 0.5 and 0.25. Quaternary, dark
appearance and the iOS 26 chrome keep the UIKit label colours (unmeasured).

The `ShapeStyle` statics (`.white`, `.red`, …, `.primary`, `.secondary`, `.link`) are
`nonisolated` now. `_OpenShapeStyle` is `@MainActor`, so its extension statics were main-actor
isolated, and stupid-app-preview's compat module carried a concrete `foregroundStyle(_: Color)`
overload to use `.white` from nonisolated code. That overload also captured `.secondary` as
`Color.secondary` (UIKit's `secondaryLabel`), which on Apple it is not: implicit-member lookup
through a generic `ShapeStyle` never sees `Color.secondary`. The compat overload is removed in the
same change (harness patch).

## Glyph ink

`SSG_INK_LOG` on the root screen reports 0 ink-table misses after the iOS 27 harvest
(`SWIFTUI_STYLED_TEXT.md`): "All Stories" (`system-semibold|12`) draws from harvested masks.

## Full-screen audit after these changes

Differing pixels against `sim-2x.png` (780 x 1688, flattened onto white): fuzz 10 %: 3.210 % →
3.200 %; fuzz 3 %: 7.105 % → 6.702 %. Element positions (status bar, title, "All Stories", page
dots, story rings and names, avatars, badges, headlines, previews, timestamps, chevrons,
separators) are within 1 pt. Remaining differences larger than 1 pt or visibly different:

| difference | size | cause |
| --- | --- | --- |
| gear glyph shape | ink 23.5 vs 24.67 wide, spokes and teeth differ | iOS 27 redrew `gear`; the guest draws the iOS 26.1 harvested mask. Needs an iOS 27 symbol harvest. |
| capsule left edge, search glyph | 0.8 pt right | follows from the gear image width (above) |
| `message.fill` icon (row 5) | 22 x 22 vs 26 x 21.7 | Phosphor `chat-circle` fill approximates SF's wide oval bubble |
| `arrowshape.turn.up.left.fill`, `heart.fill` (rows 1, 4, 6) | ~1 pt, shape | Phosphor approximations |
| `person.fill.badge.plus` (row 2) | bottom 1.2 pt low | measured composite (`SHAPE_STROKES.md`), row offset 0.5 pt |
| previews of rows 4-5 | 0.8-1.0 pt low | accumulated 2x layout rounding (the reference rounds at 3x) |
| Nico's story artwork | rotation | animated (excluded) |
| text anti-aliasing | per-pixel | 2x masks vs downscaled 3x; the bulk of the fuzz-10 % pixels |

## Verification

- `swift run rootresidualsprobe` (uikit, native): `contentsOfFile` variant selection on 1x/2x/3x
  screens, explicit suffixes, fallbacks; hierarchical colours on both chromes and both
  appearances; nonisolated `ShapeStyle` statics (compile-time) and generic `.secondary`.
- `swiftuinavchromeprobe`: the iOS 26 checks unchanged (50 pt items, 108 pt platter, `.search`
  item); new iOS 27 checks (symbol image items, image + 22 widths, margin 16, gap 8, platter span,
  rim 0.5 pt outside). `swiftuistrokeprobe`: the rim check now expects the rim view 0.5 pt outside
  the platter (its pixel checks are unchanged). `swiftuishapemaskprobe`, `swiftuitextmetricsprobe`,
  `swiftuilazyprobe` pass.
- `Tests/OpenUIKitTests/AppDrawingTests.testContentsOfFileReadsScaleFromNameSuffix` asserted the
  1x file for an unsuffixed path while `@2x`/`@3x` siblings existed; it now pins the screen scale
  and expects the variant (not run: the XCTest target is not built on this host).
- stupid social 2x render before/after against the simulator (numbers above); phase 2 rung b.

## Risks

- Every `UIImage(contentsOfFile:)` with an unsuffixed path now loads the screen-scale sibling
  when one exists (default `imageScreenScale` is 2), as iOS does.
- The rim, grouped widths, magnifier item and hierarchical colours apply only with
  `chromeRelease == .iOS27` (host opt-in); the iOS 26 default is unchanged.
- The grouped-width rule rests on one two-item group; the magnifier's position fits it exactly,
  the gear's needs the (unharvested) iOS 27 gear image to confirm.
