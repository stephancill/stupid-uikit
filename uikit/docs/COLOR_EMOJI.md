# Colour emoji

Emoji in text used to draw nothing: no bundled font (the harvested SF ink
table, DejaVu Sans) has them, and a glyph-less scalar was skipped silently.
`Sources/OpenUIKit/ColorEmoji.swift` adds colour emoji to every text path
(plain labels, attributed and SwiftUI styled text, text inputs through the
shared glyph-line drawer). Native gate: `swift run coloremojiprobe`.

## Font

Apple Color Emoji is never shipped, read or derived. Glyph images come from
**Noto Color Emoji** (SIL Open Font License 1.1, `THIRD_PARTY_LICENSES/NotoColorEmoji.md`),
provided like DejaVu: a distro package pinned by checksum in
`env/contract.json` (row `noto-color-emoji`), not vendored.

- Package: Ubuntu noble `fonts-noto-color-emoji=2.047-0ubuntu0.24.04.1`
  (upstream googlefonts/noto-emoji v2.047), file
  `/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf`, SHA-256
  `93cdc4ee9aa40e2afceecc63da0ca05ec7aab4bec991ece51a6b52389f48a477`.
  `.cursor/Dockerfile` and `.codex/setup.sh` install that version.
- Lookup (first readable wins): `OpenUIKitRuntime.fontPaths["emoji"]`,
  `<resourceRoot>/fonts/NotoColorEmoji.ttf` (app bundles copy it to
  `OpenUIKit/fonts/` beside DejaVu), the distro path.
- Format: CBDT/CBLC, one strike of PNG images at 109 ppem (136x128 px).
  `ColorEmojiFont` reads cmap (format 12, else 4), every GSUB ligature lookup
  (type 4, or 4 in a type 7 extension) in lookup order, and the strike's
  index subtables (formats 1 and 3) and images (formats 17 and 18). Anything
  else is `OPENUIKIT_EMOJI_FONT_INVALID`.

## What is an emoji

A grapheme cluster (Swift `Character`) whose first scalar is Emoji and that
has Emoji_Presentation, or carries U+FE0F, a keycap U+20E3, a skin-tone
modifier, a ZWJ, tag characters, or is a regional-indicator pair; plus
text-default pictographs at or above U+1F000, which no bundled text font
covers and which iOS draws in colour through its cascade. U+FE0E keeps the
text path, and so do text-default BMP emoji without U+FE0F (a bare U+2764,
U+263A): whether iOS draws those in colour depends on SF's coverage, which is
not measured; DejaVu draws them in the text colour.

Shaping: the cluster's scalars go through cmap with variation selectors
dropped (as a shaper does for this font), then the ligature lookups, so ZWJ
sequences, skin tones, keycaps, flags and tag flags (England) become one
glyph. A sequence the font does not ligate draws its glyphs side by side,
one advance each, as CoreText does. A scalar the font lacks inside an emoji
cluster is `OPENUIKIT_EMOJI_MISSING` (Noto v2.047 predates it).

## Layout

- An emoji cluster is one unbreakable unit: one advance, never kerned, never
  split by character wrapping. Text without a scalar at or above U+203C keeps
  the old scalar loops byte for byte (`ColorEmoji.mayContainEmoji`).
- Line height is unchanged: the font's line metrics stay the run's. MEASURED:
  chat rows with and without emoji in a one-line `.subheadline` preview are
  both 64 pt, two-line rows both 75.333 pt; the reaction chips (20 pt emoji)
  are 34.333 pt like a 20 pt system line plus their insets.

### Advance (MEASURED, iOS 27.0 simulator, iPhone 16e 3x, stupid social)

| size | where | measurement | advance |
|---|---|---|---|
| 20 pt | UIKit reaction chips `👍 1`, `🔥 2`, `🎉 5`, `💯 2` | chip width - insets (10 + 11) - SF semibold 15 " n" | 25.04-25.10 pt (label width rounds up to 1/3 pt): 1.25 em |
| 15 pt | SwiftUI preview "ever 🚀 see" | pen of "s" - pen after "ever " - space, from the SF 15 ink table's bearings | 21.22 pt: 1.415 em |
| 15 pt | 👀, 🤯, 😄, 🚀, 🧗 after a space | image ink starts 0.08-0.13 em after the pen; 1.13-1.24 em of ink | (consistent with 1.42 em, bearings symmetric) |
| 17 pt | SwiftUI `.headline` "Weekend Climbing 🧗" before an 8 pt-spaced symbol | symbol ink 11.7 pt right of the emoji ink | about 1.33-1.36 em |

So below 20 pt iOS leaves extra space after the emoji image (a tracking-like
term: 0.165 em at 15 pt, none at 20 pt). `ColorEmoji.advanceEm(size:)` is
1.25 em at 20 pt and above, 1.415 em at 15 pt and below, linear in between
(17 pt: 1.349 em, inside the 17 pt estimate). Unmeasured: sizes outside
15-20 pt, and whether the extra term belongs to SwiftUI text rather than to
the size (the 20 pt sample is UIKit, the 15/17 pt ones SwiftUI).

### Image placement

The Noto image is drawn at its own em (= the run's point size, as CoreText
sizes a fallback font) with its own bearings from the pen and baseline: its
ink starts 0.07 em after the pen (Apple: 0.08-0.13 em) and its box bottom is
0.248 em below the baseline (Apple's deepest ink: 0.244 em below, 🚀 and 🧗).
Shapes differ by design, so ink centres differ per glyph: Noto minus Apple,
in em, 👀 +0.006, 📸 (17 pt) +0.008, 🚀 +0.091, 🧗 +0.095 (Apple draws those
two smaller); 👍 in the 20 pt chip: Noto ink 18.5 x 20.5 pt at the same
place as Apple's 19.7 x 21.3 pt, ink top 1.2 pt lower, bottom within 0.2 pt,
the following "1" at the same distance (27.0 pt) from the ink's left edge.

### Drawing

The PNG strike (3-4x the device size) is area-averaged to the device pixels
the image covers (premultiplied while filtering), cached per glyph and pixel
size, and drawn on the pixel grid; a rotated or scaled canvas uses the
canvas' image interpolation. Colour glyphs ignore the text colour and its
alpha, as on iOS (MEASURED: emoji in the 50% `.secondary` previews keep
black pupils, 0-22 per channel, where the text's darkest pixel is 127).

## Glyphs no font covers

Before, a scalar without a glyph in the outline fallback drew nothing.
Now it is `OPENUIKIT_NO_GLYPH: U+XXXX (<name>) at <size> pt` (fatal, like
`OPENUIKIT_IOS_INK_MISS`), except default-ignorable and control scalars,
which draw nothing on iOS either. A tofu box would not be faithful: on iOS
such scalars draw from a cascade font (PingFang, Noto Sans …), and only a
scalar no system font covers gets LastResort's box.

## Not covered

- `UITextView`'s own caret/selection geometry still counts scalars; an emoji
  there measures and draws as one cluster but caret stops inside a sequence
  are not modelled.
- Truncation (`TextLayout.truncate`) cuts at scalar boundaries and can drop
  the tail of a sequence (the head still draws as an emoji).
- Dark-appearance or tinted emoji, `Text` foreground gradients over emoji.
