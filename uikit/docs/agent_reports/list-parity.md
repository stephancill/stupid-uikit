# stupid social list parity: separators, page dots, symbol weight

Reference: stupid social's root screen on an iPhone 16e (390x844 pt, @3x) iOS 27.0 simulator in
demo mode, against the x86_64 iOS-simulator guest rendered at 2x, offline (avatars and stories
are initials and gradients offline; that is not a renderer gap).

## Row separators (SwiftUI `placeSection`, `placeList`)

MEASURED (3x reference): separators run from x = 52 to 374 pt, 3 device pixels (1 pt) of
(232,232,232) on white, i.e. the iOS `separator` colour (60,60,67 at 0.12) over white. The feed
rows have `listRowInsets` leading 12, a 28 pt type icon and 12 pt spacing, so 52 pt is the row's
text column: SwiftUI's default `listRowSeparatorLeading`.

The feed's rows are a `Section` inside a `.plain` List, which `placeSection` lays out; it drew a
0.5 pt separator from x = 16 to the trailing edge. On the iOS cut in a plain list it now uses
what `placeList` already measured for plain rows: x = the smallest x of a visible label in the
row (`_rowTextLeading`, shared with `placeList`; hidden subtrees such as a button's pressed copy
or unrevealed swipe actions no longer count), trailing inset 16 pt, 1 pt thick. Grouped sections
and the macOS cut are unchanged.

Both placers now hide the separator between rows i and i+1 when row i hides its bottom edge or
row i+1 hides its top edge (`.listRowSeparator(_:edges:)`); `placeSection` ignored the modifier,
`placeList` honoured only the bottom edge.

Not implemented: explicit `.alignmentGuide(.listRowSeparatorLeading/Trailing)` (this SwiftUI has
no alignment guides; stupid social does not use them) and `listSectionSeparator`.

Result (2x guest): separators 104...747 px, 2 px thick, (231,231,232), identical to the 2x
reference (104...747 px). Before: 32...778 px, 1 px.

## HomePager page dots (OpenUIKit Auto Layout)

stupid social's `HomePagerController` (a `UIViewControllerRepresentable`) adds its
`HomePageDotsView` in `viewDidLoad` with `centerX == view.centerX`,
`bottom == view.safeAreaLayoutGuide.bottom - 4` and an intrinsic size. The view dump had it at a
zero frame: the SwiftUI host creates the controller from its `layoutSubviews`, after
`layoutIfNeeded`'s solve, and the holder's `setNeedsLayout` from activation was consumed by the
same pass, so nothing ever solved the new constraints.

Fix: `LayoutEngine.constraintsChangedSinceSolve` is set by constraint activation/deactivation
and cleared by a whole-hierarchy solve; `UIView._layoutSubtree` re-solves (after safe-area
propagation) before laying out the next dirty view while it is set, so constraints installed
during a pass are applied in that pass, as UIKit's engine does. Regression test:
`ConstraintsInstalledDuringLayoutTests`.

Result: the pill and both dots draw at x = 178.67 pt (reference 178.67), 33x17 pt (reference
33x17), y = 823 pt against the reference's 789 pt. The 34 pt difference is the guest's missing
bottom safe area (home indicator), which is outside this change.

## SF Symbol weight and the reply arrow (OpenSymbols)

Ink measured per icon (pt², luminance-weighted, same colours both sides; chevrons are tertiary
grey):

| symbol (font) | reference | before | after |
| --- | --- | --- | --- |
| `arrowshape.turn.up.left.fill` (title2 semibold) | 23.3x20.3, 149 | 23x18, 51 | 23x19, 112 |
| `at` (title2 semibold) | 22.7x23, 112 | 24x24, 103 | 24x24, 103 |
| `chevron.forward` (body semibold) | 8.7x15, 11.0 | 8x14.5, 5.8 | 8.5x15.5, 9.0 |
| `person.fill.badge.plus` | 23.7x23, ~98 | 23x17, 95 | unchanged |
| `message.fill` | 26x21.7, 261 | 23x23, 240 | unchanged |

- Weight: `OpenSymbols.paths/draw` take a `UIImage.SymbolWeight`; semibold and heavier use
  Phosphor's bold drawing for regular-weight rows, placed by the regular glyph's bounds so strokes
  thicken outward. SwiftUI passes the resolved font weight, `UIImage(systemName:)` its
  configuration weight. The generator vendors `assets/bold/<icon>-bold.svg` for every regular row
  (694 glyphs, catalog 335 KB). Bold overshoots `at` (1.37x the reference ink against 0.91x for
  regular), so the mapping gained a `regular-only` weight, used for `at`.
- Shape: `arrowshape.turn.up.left/backward(.fill)` map to Phosphor `share-fat` mirrored (new
  `mirror` composite), `…right/forward` to `share-fat`; the thin `arrow-bend-up-*` arrows are
  gone.
- Remaining: `person.fill.badge.plus` draws the plus beside the figure (SF: a badge disc at the
  lower right, 6 pt taller); chevrons are still ~20% lighter than SF semibold.

## Verification

- `swift test --filter "^SwiftUITests\.|OpenUIKitTests\.(AutoLayout|SafeArea|Layout|OpenSymbols|ConstraintsInstalled|ViewControllerLayout|UIPageViewController|UIStackView|SystemImage|Symbol)"`
  on the x86_64 Linux host: all pass (the package's `SceneLaunchTests` and
  `ActorIsolationTests.swift` do not compile on Linux on swift64 itself and were left out of
  that build).
- stupid social iOS-triple 2x render before/after against the reference; phase 2 rung b on the
  macOS triple.
