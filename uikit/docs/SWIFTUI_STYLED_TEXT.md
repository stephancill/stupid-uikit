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

## Bold is a trait, not a weight

`Text.bold()`, `View.bold()` and `Font.bold()` add the bold trait. On the iOS
font cut it resolves per font (`_OpenFont.boldTraitWeight`), as MEASURED on
the iOS 27.0 simulator (iPhone SE 3rd generation, SwiftUI `ImageRenderer` at
2x, pixel-identical matches against `.weight(...)`): `.largeTitle`, `.title`
and `.title2` become bold; every other text style and `.system(size:)` at
10-34 pt become **semibold**; an explicit medium or semibold system weight is
unchanged. `fontWeight(.bold)` and `.weight(.bold)` stay the bold weight. So
stupid social's `Text(actor).bold()` in `.body` is semibold 17, which is why
its actor names looked too heavy and wide. The macOS cut keeps bold.
Unmeasured: light/thin bases (kept bold). A text style that already carries
a weight keeps its style (`SWIFTUI_TEXT_METRICS.md`) and takes the style rule:
`.title2.weight(.semibold).bold()` is bold and `.body.weight(.medium).bold()`
semibold, as measured on iOS.

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
  bottom on the baseline, moved by the run's `baselineOffset`, which stays a
  `.baselineOffset` attribute of the attachment run so the line box grows
  with it (`SWIFTUI_TEXT_METRICS.md`). A system symbol is `UIImage(systemName:withConfiguration:)`
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
- Bold text under the iOS cut used to mix fonts: `glyph_ink_ios.json` had
  only 97 `system-bold|17|light` masks, and a miss drew the outline fallback
  (DejaVu Sans Bold in the portable bundle) at SF Pro's advances, so runs like
  "alex_smith" looked tight or overlapping. Harvested 2026-10-31 (below); a
  font or size outside the table still falls back the same way. Find the keys
  a screen needs with `OPENUIKIT_INK_LOG` (stupid social: `SSG_INK_LOG`) and
  feed that log to the probe as its keys file.

## iOS 27 ink harvest (2026-10-31)

- Probe: `Tools/oracle2/inkprobe` adopts the scene lifecycle (iOS 27 traps
  at launch in `UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`
  otherwise): `InkProbe-Info.plist` declares a `UIApplicationSceneManifest`
  whose `InkProbeSceneDelegate` builds the window on its scene and runs the
  harvest. Keys may carry the `I|` prefix `OPENUIKIT_INK_LOG` writes, so a
  miss log is a keys file as is. The probe already accepts the runtime's
  `F<fraction>` tags (`GlyphInkTable.phaseIOS`); harvest those, not the
  Catalyst `0`/`P1` tags.
- Script: `scripts/ink_probe_sim.sh` uses the newest installed iOS runtime
  (`SIM_RUNTIME` overrides) and `SIM_UDID` runs on an existing simulator, e.g.
  a temporary one the caller creates and deletes:

  ```sh
  U=$(xcrun simctl create tmp-ink-harvest \
      com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation \
      com.apple.CoreSimulator.SimRuntime.iOS-27-0)
  xcrun simctl boot $U
  SIM_UDID=$U SIM_DEVICE=2x INK_KEYS=keys.txt scripts/ink_probe_sim.sh out/
  xcrun simctl shutdown $U; xcrun simctl delete $U
  ```

- Provenance: iPhone SE (3rd generation), scale 2, iOS 27.0 simulator runtime
  (build 24A434). Keys: stupid social's root screen logged 84 misses
  (`system-bold|17` actor names, `system-bold|34` large title,
  `system-semibold|17` and `|12`, `system-regular|15` incl. U+2014 and `|11`).
  Harvested ASCII 33–126 light for `system-bold|17` at all 8 F phases,
  `system-bold|34` and `system-semibold|17` at F0.0/F0.5 (the 2x grid from
  17 pt), `system-regular|11`, `|15` and `system-semibold|12` at
  F0.0/F0.25/F0.5/F0.75 (the grid below 17 pt), plus the logged keys:
  2257 keys, none skipped. Only missing keys were merged: 1743 (655
  `system-bold|17|light`), table 9148 → 10891; existing keys keep their
  iOS 26.1 masks.
- iOS 27 vs 26.1 on the 514 overlapping keys: identical geometry; masks
  differ by 1/255 on most glyphs and by more than 20/255 on 64 (edge pixels,
  at most 76/255), 4.2 % of pixels changed, ink sums within 1.6 %. The table therefore mixes two
  runtimes' rasterisation at that level. Dark-appearance masks for these
  families were not harvested (the root screen is light).
