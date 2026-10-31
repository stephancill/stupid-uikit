# SwiftUI text metrics on the iOS cut

Text layout rules SwiftUI applies on iOS that OpenUIKit's SwiftUI layer did
not, found by comparing stupid social's root screen (iOS 27.0 simulator,
iPhone 16e, 3x, demo mode) with the guest's 2x render. All of them apply only
on the iOS font cut (`OpenUIKitRuntime.systemFontCut == .iOS`); the macOS cut,
which the phase 2 gates use, is unchanged. Native gate:
`swift run swiftuitextmetricsprobe` (uikit package).

## Text-style line spacing

SwiftUI's text-style fonts (`.subheadline`, `.body`, `.headline`, …, and
their `.weight(_:)`, `.bold()`, `.italic()` and `.system(_:design:weight:)`
variants) carry the style's line spacing, as `UIFont.preferredFont(forTextStyle:)`
does: `lineHeight + leading` is the integer in
`UIFont.iOSTextStyleLineSpacingLarge` (subheadline 20, body and headline 22,
footnote 18, …), and the leading sits between lines, not above the first.

- Measured: stupid social's feed rows are 119.333 pt with a two-line
  `.subheadline` preview, 99.333 with a one-line preview and 75.333 without,
  so the preview is 38 pt for two lines and 18 for one (2 x 17.900 + 2.100,
  up to the pixel). The 2x render's preview baselines are 40 px apart. The
  guest used `systemFont(ofSize: 15)` (no leading): 36 pt, 36 px apart.
- `Font` resolution (`Values.swift`) applies
  `UIFont._applyingTextStyleLineSpacing(_:)`; a `.uiFont` storage keeps the
  `textStyle` it came from. `Font.system(size:)` and `Font(uiFont)` have no
  text-style leading.
- `AttributedTextLayout` (styled Text, attributed UILabels) now adds a
  text-style font's leading between lines like the plain label path
  (`FontEngine.labelBlockHeight`); fonts without a text style carry none, so
  UIKit attributed text with `systemFont` is unchanged.

## `.bold()` and weighted text styles

The bold trait rule is in `SWIFTUI_STYLED_TEXT.md` ("Bold is a trait, not a
weight"). Independent confirmation from the root screen: after each `.bold()`
actor name ("alex_smith", "nova.builds", "jules_dev", "maya.co",
"amy_stories") the next word starts where 17 pt semibold advances put it;
bold advances put it 4-6 px (2x) further right. Per-glyph starts in
"alex_smith" follow semibold within 1 px (a→h: iOS 153 px, semibold 152.5,
bold 157.5). The bold advance and kerning tables were right; the runs were
the wrong weight. With semibold they draw from the `system-semibold|17` ink
and match the simulator glyph for glyph.

Because a weighted text style now keeps its style (above), the trait uses
the style's rule there too: `.title2.weight(.semibold).bold()` is bold and
`.body.weight(.medium).bold()` semibold, the two measured cases.

## Inline images with a baseline offset

`Text(image).baselineOffset(-1)` keeps the offset as the attachment run's
`.baselineOffset` attribute (bounds origin 0) instead of folding it into the
attachment bounds. The image draws in the same place, and the line box grows
by the offset as a lowered text run's does: the run's descent is the font's
descent plus 1.

- Measured: stupid social's headline (`Text(badge).baselineOffset(-1)`, a
  14 pt badge, 17 pt text) is 21.333 pt tall (16.187 + 4.101 + 1, up to the
  pixel); the guest made it 20.333/20.5.
- `AttributedTextLayout.lineMetrics` moves an attachment's box by the run's
  baseline offset, matching where `AttributedTextDraw` already drew it.

## Stack children: modified EmptyView

A modified `EmptyView` (`EmptyView().padding(.trailing, 24)`) takes no slot
and no spacing in a stack, like a bare one. Measured: stupid social's follow
row (whose `VStack(spacing: 6)` ends in that padded EmptyView) is 75.333 pt,
as if the child were absent; the guest added the 6 pt spacing (80.5).

## `fixedSize` on one axis

`.fixedSize(horizontal: false, vertical: true)` is the child's size for the
adjusted proposal on both axes; the non-fixed axis passes the proposal through
but still takes the child's answer. Measured: the story names
(`Text.lineLimit(1).fixedSize(horizontal: false, vertical: true).frame(width: 70)`)
are centred under their bubbles ("Nico" ink at x 80-123 px in a 70 pt column
at x 16); the guest gave the label the full 70 pt and drew it left-aligned
(x 40-78).

## Orphan avoidance

SwiftUI Text on the iOS cut avoids a single-word last line: when greedy
wrapping leaves one word alone on the text's last line, the previous line's
last word moves down if it fits (TextKit's `LineBreakStrategy.pushOut`, part
of `.standard`). Measured: "Big fan of showing notifications without the
feed." in the 302 pt `.subheadline` preview wraps "...without / the feed." on
iOS; greedy wrapping gave "...without the / feed.".

- `UILabel._avoidsOrphanLastWord` (not UIKit API) enables it; SwiftUI's
  labels set it. Plain UILabels keep greedy wrapping: UIKit's default
  strategy is `.standard` too, but no UIKit golden was re-measured for it.
- Only the last line of the whole text, and only when all the text is laid
  out (a capped block that truncates is left alone). Apple's full rule set
  (multiple paragraphs, how far it looks back, CJK/Hangul rules) is not
  modelled.

## Root screen after these changes (2x, vs the iOS 27.0 simulator)

Text baselines and word positions are within 0-2 px of the simulator across
the feed (title, "All Stories", story names, timestamps, headlines, previews,
separators). The residual drift (about +0.3 px per row) is pixel rounding: the
guest lays out at 2x (a 21.5 pt headline) where the simulator rounds at 3x
(21.333).

Remaining text differences that belong elsewhere: glyph shapes where an iOS
ink mask is missing and the outline fallback (DejaVu) draws, e.g. "All
Stories" (`system-semibold|12`); the network badge bitmap draws from the 1x
file (`UIImage(contentsOfFile:)` does not pick the @2x/@3x variant), so it is
blurrier than the simulator's.
