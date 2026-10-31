# Shape masks: CAShapeLayer and SwiftUI `.mask { shape }`

Before this change `CALayer.mask` in the pure-Swift render pass supported only
a solid layer (background colour with a rounded rect; sublayers trapped), the
portable CALayer family had no `CAShapeLayer`, and SwiftUI's `.mask` always
installed a white rectangle the size of the mask's frame. A gradient masked by
a stroked circle (stupid social's story-bubble ring) rendered as a solid
gradient square.

## UIKit / Core Animation

- `CAShapeLayer` (Linux ELF and Mach-O guests; QuartzCore's own class where
  `canImport(CoreGraphics)`), `uikit/Sources/OpenUIKit/CAShapeLayer.swift`:
  `path` (the renderer's `Path`, the type `UIBezierPath.cgPath` returns on
  those targets), `fillColor` (default black), `strokeColor` (default nil),
  `fillRule` (`.nonZero`/`.evenOdd`), `lineWidth`, `lineCap`, `lineJoin`,
  `miterLimit`. Not declared, so code using them does not compile:
  `strokeStart`/`strokeEnd`, `lineDashPattern`/`lineDashPhase`, and path or
  colour animations.
- Render pass (`RenderPass.swift`): `renderLayer` fills then strokes a shape
  layer above its background and below its sublayers and border.
- Masks in the render pass: a plain layer with only a background colour (no
  sublayers, no nested mask, no border, not a shape or gradient layer) keeps
  the analytic single-path mask, unchanged, so solid-mask output is
  byte-identical. Every other mask is drawn by `renderLayer` into a scratch
  surface of the same size, backend, scale and CTM
  (`Canvas.beginMaskedTransparencyLayer(drawingMask:)`), and that surface's
  alpha multiplies the masked group once at its end, as Core Animation
  composites a mask. Fill rule, fill/stroke alpha, opacity, sublayers,
  gradients and nested masks therefore all count; strokes use the backend's
  real stroker (no offset-outline approximation). The old precondition on mask
  sublayers is gone. Cost: one full-surface RGBA scratch bitmap per masked
  view per frame.
- Layers compositor (`LayerBridge.swift`): a `CAShapeLayer` becomes a quartz
  `QZShapeLayer` (path, fill/stroke colour, even-odd, width, cap, join, miter
  limit); quartz already renders an arbitrary mask layer tree's alpha
  (`QZLayerSetMask`).
- The Swift rasterizer backend ignores cap/join styles (butt caps, round
  joins), as it does for every stroke.

## SwiftUI `.mask`

`Hosting.place` for `.mask(content, alignment)` now checks whether the mask
content is built only from shapes and layout: `Rectangle`, `RoundedRectangle`,
`Capsule`, `Circle` (filled or stroked), `Color`, `Spacer`, stacks, groups and
modifiers. If so it places the mask content on a scratch view exactly where it
would render and mirrors the placed views as a layer tree: a container
`CALayer` per view (frame, alpha, clipping) holding a `CAShapeLayer` per
background (rounded rect at the view's corner radius) and per border (the
inside ring the render pass draws for `borderWidth`: outer rounded rect minus
the rect inset by the width at radius `cornerRadius - width`, even-odd). The
mask is therefore exactly the alpha the same shape draws unmasked. Anything
else among the placed views (text, images, gradients, custom-drawn views,
transforms, shadows) keeps the previous rectangular mask.

General content masks (text, images, gradients as masks) would need the placed
mask views rasterised to an alpha mask: render the scratch view into the
scratch surface instead of a layer tree. The render-pass side already takes
any drawing (`beginMaskedTransparencyLayer(drawingMask:)`); what is missing is
a `CALayer` that carries a view subtree as a mask, and the layers compositor's
equivalent.

## Stroking with a ShapeStyle

`Circle`, `Capsule` and `RoundedRectangle` gain
`stroke(_ content: some ShapeStyle, lineWidth:)` (and `RoundedRectangle`
`strokeBorder`), disfavoured against the existing `Color` overloads. A style
that is a view (`LinearGradient`) becomes the gradient masked by the same shape
stroked in black; any other style strokes in its resolved colour.

`stroke` is centred on the outline and `strokeBorder` inset, as in SwiftUI;
a centred gradient stroke paints its style over the frame grown by half the
line (docs/SHAPE_STROKES.md).

## Verification

`swift run swiftuishapemaskprobe` (uikit package, native): filled, stroked,
even-odd, half-alpha and offset `CAShapeLayer` masks, and a `CAShapeLayer`
sublayer, through the render pass on both canvas backends and through the
layers compositor; SwiftUI ring, padded rounded-rect and text masks through
both compositors.
