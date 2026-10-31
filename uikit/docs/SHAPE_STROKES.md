# Shape strokes, the badge-plus symbol and the iOS 27 platter rim

Root-screen parity pass against stupid social on an iOS 27.0 iPhone 16e simulator (390 x 844 pt,
compared at 2x with the x86_64 iOS-simulator guest, network on).

## Centred shape strokes

SwiftUI's `stroke(_:lineWidth:)` centres the line on the shape's outline: half lies outside the
shape's frame and is not clipped. `strokeBorder` insets the shape by half the line first, so the
line stays inside. This port drew every `stroke` as an inside border (`layer.borderWidth`), so
stupid social's 3 pt story rings sat 1.5 pt inside where iOS draws them.

- Solid strokes of `Rectangle`, `RoundedRectangle`, `Capsule` and `Circle` stay a layer border
  (so `.mask { shape.stroke }` keeps mirroring them as shape layers), on a view grown by half the
  line on every side, with corner radius r + w/2 (0 for a square corner, the default miter
  join). The border's inner radius, r + w/2 - w, is the outline offset inward: the result is
  exactly the centred stroke (`Hosting._applyStrokeBorder`). `_OpenStrokePlacement` carries
  `.centered` (`stroke`) or `.inside` (`strokeBorder`).
- Gradient (ShapeStyle) strokes: the style is masked by the same stroke drawn in black; for a
  centred stroke the style is placed over the frame grown by the overhang (the placement-only
  `strokeOverhang` modification), and a `LinearGradient` keeps its unit points relative to the
  shape's frame, as SwiftUI resolves them.
- `StrokeStyle` arcs (`Circle().trim(...).stroke(_:style:)`, caps, dashes): the arc radius is the
  circle's own, and the view is grown by half the line (a square cap's corner, w/2 x sqrt 2, for
  `.square`). The trimmed circle now also takes the size it is offered (it measured 0 x 0 in an
  overlay before).
- New API: `strokeBorder` (Color and ShapeStyle) on `Circle` and `Capsule`, `stroke`/
  `strokeBorder` on `Rectangle`, ShapeStyle `strokeBorder` on `RoundedRectangle` now insets
  (it was `stroke`). Hosts that declared their own `Circle.strokeBorder` must drop it.
- Not added: `stroke(_:style:)` on untrimmed shapes (no general path dasher yet).

Measured (2x px, column through the top of the story rings): torres's 3 pt black ring covers
rows 363-369 on iOS and in the guest (366-372 before); alix.photos's gradient ring rows 363-369
both (366-372 before). Horizontally, torres's left ring edge 193 px vs iOS 192.8 (196 before).

## `person.fill.badge.plus` (open symbols)

The mapping drew Phosphor `user-plus`, a plus beside the figure. iOS draws a figure with a
green disc, the plus cut out of it, overlapping the figure's lower right, with a knocked-out gap
around the disc. New open-symbol composite `badge-plus` (mapping.tsv, generate.py,
`OpenSymbols.badgePlusGeometry`), drawn from primitives measured on the reference at 3x: head
ellipse, half-ellipse body (Phosphor's filled figure merges head and body with a much larger
head), disc, plus, knockout radius. The knockout is a clip in `OpenSymbols.draw` (the figure's
paths are drawn outside the knockout circle; `OpenSymbols.paths` still returns them unclipped).

iOS centres the figure, not the ink, in the image's frame and lets the badge hang off it.
`OpenSymbols.Layout.anchor` records that point, and SwiftUI now places a fixed-size
(non-resizable) open symbol at its font-derived size, centred on its anchor, instead of scaling
it to fill its frame (`.frame(width: 28, height: 32)` shrank the 29 pt-wide symbol).

Measured ink boxes (pt, 2x): iOS [16.5, 414, 40.5, 437.5]; guest before [14.5, 415, 37.5, 432]
(plus beside the figure); after [17, 411.5, 41, 435.5] (the row itself sits 2.5 pt higher in the
guest; relative to the row's avatar the symbol top is 6.5 pt below on both). The `at` symbol in the
same column moved from [14, 492, 38, 516] to [14.5, 492.5, 37.5, 515.5] (iOS [14.5, 490.5, 37,
513.5]); the reply arrow, bubble and chevrons are unchanged.

## iOS 27 platter rim

Corrected in `ROOT_SCREEN_RESIDUALS.md`: the rim is a 0.5 pt band just *outside* the platter's
outline (a lone 44 pt button shows it at [15.5, 16] pt), so the toolbar capsule's frame is
106.67 pt wide at the 16 pt margin, not 108. The colours and shadow below stand.

`OpenUIKitRuntime.chromeRelease` (`.iOS26` default, `.iOS27`): the iOS 27 glass platter (shared
toolbar platters and glass item platters, light appearance) draws a 0.5 pt rim inside its
outline, black at 0.30 at the capsule's left and right extremes and 0.10 along the straight
edges, following the outline normal's horizontal component (one horizontal gradient, linear
across each semicircular end), and casts a lighter shadow (opacity 0.02, was 0.075). Measured on
the reference toolbar capsule (108 x 44 pt): 3x side rim 215/175 over 255/250, top/bottom
241/231 and 227/238; shadow at most 3 counts below and none above. Guest at 2x after: side rim
179 in one pixel (iOS 223/204 over two: the same total), top 228 (iOS 250/237), bottom 228
(iOS 233/247); below the capsule 252-254 (iOS 252-254; 243-249 before), above 254 (iOS 255; 248-251
before). Dark appearance and the navigation back-button platter are not measured and unchanged.

## Verification

- `swift run swiftuistrokeprobe` (uikit package, native, 123 checks): centred circle, rounded
  rect and rectangle strokes (frames, radii, pixels inside and outside the frame), strokeBorder,
  gradient strokes (frame and unit points), trimmed StrokeStyle arcs including square caps, an
  overlay stroke over a `clipShape` not being clipped, the story-ring mask, through the render
  pass on both backends and the layers compositor; the badge-plus composite (hole, gap, figure)
  on both backends; the rim (hidden on iOS 26, alpha at the ends and edges, width, shadow).
- `swiftuishapemaskprobe` updated for the centred ring (the masked band is now the stroke's inner
  half); `swiftuinavchromeprobe`, `swiftuilazyprobe` pass.
- stupid social iOS-triple 2x render against the simulator (numbers above); phase 2 rung b.

## Risks

- Every SwiftUI shape stroke in every guest moves outward by half its width; layouts that relied
  on the inside border (stroke kept within the frame) now draw outside it, as on iOS.
- Fixed-size open symbols no longer scale to their frame; a symbol in a frame smaller than its
  natural size overflows it, as in SwiftUI. Only the open-symbol path (opt-in) changes.
