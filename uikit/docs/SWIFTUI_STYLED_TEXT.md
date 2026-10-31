# SwiftUI styled Text

`Text` is an ordered list of runs, as in SwiftUI, so concatenated and
interpolated text keeps per-run styling and inline images:

```swift
Text("\(Text(image).baselineOffset(-1)) \(Text(name).bold())\(Text(remainder))")
Text(a).foregroundColor(.red) + Text(b)
Text("Last seen \(date, format: .relative(presentation: .named))")
```

Before this, `_OpenText` held one string, and an app-side compatibility layer
had to flatten these to a string (dropping bold, colour and the inline image).

## Model (`View.swift`)

- `_OpenText.runs: [_OpenTextRun]`. A run is a string or an `Image`, plus an
  `_OpenTextAttributes` value: font, weight, italic, monospaced digits,
  foreground colour, baseline offset, kerning, tracking, underline and
  strikethrough (each with an optional colour). A nil attribute inherits.
- Text modifiers return `Text`, as Apple's do: `font`, `fontWeight`, `bold`,
  `bold(_:)`, `italic`, `italic(_:)`, `monospacedDigit`, `monospaced`,
  `foregroundColor`, `foregroundStyle` (single style), `baselineOffset`,
  `kerning`, `tracking`, `underline(_:color:)`, `underline(_:pattern:color:)`,
  `strikethrough(_:color:)`, `strikethrough(_:pattern:color:)`. A modifier
  sets the attribute only on runs that have not set it, so the innermost
  setting wins: `(Text("a").foregroundColor(.red) + Text("b")).foregroundColor(.blue)`
  is a red "a" and a blue "b". Line patterns draw as solid rules.
- `Text(_ image: Image)` and `static func + (Text, Text) -> Text`.
- `content` (not SwiftUI API) is the runs' plain string; images contribute
  nothing.
- `Text(_ content: String)` is `@_disfavoredOverload` like Apple's
  `StringProtocol` initializer, so a string literal, interpolated or not,
  resolves to `Text(_ key: LocalizedStringKey)`. `Text(AttributedString)`
  (FoundationEssentials' `AttributedString` is string-literal expressible) and
  `Text(_:tableName:bundle:comment:)` are disfavoured too, so `Text("x")` has
  exactly one best candidate.

## LocalizedStringKey interpolation (`Compatibility.swift`)

`LocalizedStringKey.StringInterpolation` gains Apple's
`appendInterpolation(_: Text)`, `appendInterpolation(_: Image)` and
`appendInterpolation(_:format:)` (`F.FormatInput: Equatable`,
`F.FormatOutput == String`). Every segment is also recorded as a run; when a
Text or Image was interpolated, `Text(key)` is built from those runs, otherwise
from `rawValue` exactly as before. `rawValue` stays the plain string (images
contribute nothing) and key equality compares `rawValue` only. Other values
still interpolate with `String(describing:)` (Apple formats numbers through
format specifiers, e.g. `"\(3.14)"` shows `3.140000` there).

## Rendering (`Hosting.swift`)

- A Text whose runs are all strings with one attribute set limited to font,
  weight, monospaced digits and foreground colour builds exactly the node a
  plain Text built before runs existed: `.text(joined string)` wrapped in the
  matching `.monospacedDigits`, `.fontWeight`, `.font` and `.foregroundColor`
  modifications. Plain `Text("x")` and `Text("x").bold().foregroundColor(…)`
  therefore render pixel-identically (checked on stupid social's 2x render:
  every region without a styled headline is identical to the previous render).
- Anything else builds `.modified(.text(plain string), .styledText(runs))`.
  Tree visitors that read `.text` (menu titles, `_containsText`) still see the
  plain string. Measuring and placing set `_RenderEnvironment.styledText`, and
  `makeLabel` gives the UILabel an attributed string: each run resolves its
  attributes over the environment (`run ?? environment ?? .body` for the font,
  `run ?? environment` for weight and colour, italic via `Font.italic()`), and
  the existing `AttributedTextLayout` / `AttributedTextDraw` lay it out and
  draw it.
- An inline image is an `NSTextAttachment` on U+FFFC. A bitmap
  (`Image(uiImage:)`, `Image(_ name:bundle:)`) keeps its point size with its
  bottom on the baseline, raised by the run's `baselineOffset` (attachment
  `bounds.origin.y`). A system symbol is `UIImage(systemName:withConfiguration:)`
  at the run's font point size, tinted with the run's colour and centred on
  the cap height. An image that does not resolve (unknown asset or symbol) is
  left out of the line.

## Gaps

- Attributed labels do not ellipsize: a `lineLimit` cap cuts the text at the
  last allowed line without "…", and `minimumScaleFactor` /
  `allowsTightening` do not apply (UILabel's attributed path has neither).
- The label's `text` (and the view dump) contains U+FFFC for each image; the
  image's accessibility label is not read.
- `fontDesign`, `fontWidth`, `textScale`, `Text.DateStyle` interpolation,
  `appendInterpolation(_:formatter:)`, `appendInterpolation(_:specifier:)`,
  `Text(AttributedString)` runs and `Text: Equatable` are not implemented.
- Text-level `foregroundStyle` resolves the style to one colour, like the view
  modifier (gradients draw their first colour).
- Bold body text under the iOS cut mixes fonts: `glyph_ink_ios.json` has only
  97 `system-bold|17|light` masks (no `m`, `t`, `h`, …), and a miss draws the
  outline fallback (DejaVu Sans Bold in the portable bundle) at SF Pro's
  advances. DejaVu Bold is wider, so runs like "alex_smith" / "amy_stories"
  look tight or overlapping. Advances and kerning are correct; the fix is
  harvesting `system-bold|17` ASCII (light + dark, F0.0/F0.5) with
  `SIM_DEVICE=2x scripts/ink_probe_sim.sh`.
