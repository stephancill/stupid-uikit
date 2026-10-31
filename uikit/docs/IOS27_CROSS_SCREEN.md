# iOS 27 cross-screen values: palette, glyph ink, docked search field

Follow-up to `SWIFTUI_PUSHED_SCREENS.md` and `ROOT_SCREEN_RESIDUALS.md`. Reference: stupid
social (demo mode, network on) on a temporary iOS 27.0 (24A434) iPhone 16e simulator, 390 x 844
pt @3x, eight screens (root, notification detail, settings, search, chats, Telegram chat, group
chat, story). Guest: the x86_64 iOS-simulator build driven by `SSG_SCRIPT` taps, rendered at 2x
with `SSG_CHROME=ios27`. Everything new here is selected by `OpenUIKitRuntime.chromeRelease ==
.iOS27` on the iOS cut, except where noted; the iOS 26 chrome every gate pins is unchanged.

## 1. System colours

### The iOS 27.0 palette (probe)

`Tools/oracle2/colorprobe` now adopts the scene lifecycle (iOS 27 traps at launch without it,
as `inkprobe` and `symbolinkprobe` did) and records the runtime build; `scripts/color_probe_sim.sh`
takes `SIM_UDID` / `SIM_RUNTIME` like the ink probe. Run on a temporary iPhone SE (3rd
generation), iOS 27.0 (24A434), 2026-10-31, it resolves the same 37 semantic names as the iOS
26.1 table. **Only `opaqueSeparator` changed:**

| name | iOS 26.1 light / dark | iOS 27.0 light / dark |
| --- | --- | --- |
| `opaqueSeparator` | (198, 198, 200) / (56, 56, 58) | (231, 231, 232) / (42, 42, 44) |

Every other name (including `systemBlue` (0, 136, 255) light / (0, 145, 255) dark, `link`, the
label, fill, separator, background and grouped-background colours, all eleven tints and the
greys) is identical to six decimals. The elevated dark backgrounds are unchanged too.

`Resources/system_colors_ios27.json` holds the iOS 27 dump (provenance in `_provenance`;
`tintColor`, not a UIKit class colour on iOS, is copied from the iOS 26.1 table as there).
`SystemColors.activeTable` serves it on the iOS cut with the iOS 27 chrome and fails loudly if
the file is missing; the iOS 26 chrome keeps `system_colors_ios.json`.

The previously recorded "guest draws iOS 26.1's systemBlue (0, 145, 255)" was not reproduced:
(0, 145, 255) is the **dark** `systemBlue`, and the guest's "Add Account" already drew
(0, 136, 255), pixel-identical to the reference, before this change.

### Colours visible in the reference screenshots (3x)

Exact-pixel counts of each light system colour, opaque or composited over white / over
`systemGroupedBackground` (`colorscan.py` over the eight `*-3x.png`). All match the iOS 27
table:

| colour (sRGB) | system colour | screens |
| --- | --- | --- |
| (255, 255, 255) | systemBackground / secondarySystemGroupedBackground | all |
| (242, 242, 247) | systemGroupedBackground | detail, settings, search, chat, group chat |
| (0, 0, 0) | label | all |
| (0, 136, 255) | systemBlue / tint | root, settings, chats, chat, group chat |
| (52, 199, 89), (255, 45, 85), (203, 48, 224), (0, 195, 208), (255, 141, 40), (255, 204, 0), (142, 142, 147) | systemGreen, Pink, Purple, Teal, Orange, Yellow, Gray (avatars, badges, status bar) | various |
| (232, 232, 232) | separator (60, 60, 67, 0.12) over white | root, detail, settings, chats |
| (133, 133, 139) | secondaryLabel over grouped | detail, settings, search, chat, group chat |
| (138, 138, 142) | secondaryLabel over white | root (page dots), detail |
| (239, 239, 240) | tertiarySystemFill over white | chats (search field) |
| (231, 231, 232) | opaqueSeparator (iOS 27) | group chat (167 px) |

SwiftUI's hierarchical `.secondary` / `.tertiary` (black at 0.5 / 0.25 on iOS 27, measured in
`ROOT_SCREEN_RESIDUALS.md`) appear as (127, 127, 127) / (191, 191, 191) on white.

### Guest vs reference, per element

`inkaudit.py`: the strongest ink colour inside each reference tree element's frame, reference vs
guest. Before this work, three differences; after it, two (residuals):

| element | reference | guest before | guest after |
| --- | --- | --- | --- |
| Search: `ContentUnavailableView` description | (133, 133, 139) secondaryLabel | (121, 121, 124) black 0.5 | (133, 133, 139) |
| Search: docked field magnifier | (0, 0, 0) label | (135, 135, 141) secondaryLabel | (0, 0, 0) |
| Settings: "Advanced" header (`Button` with `.foregroundStyle(.secondary)` in a section header) | (133, 133, 139) | (121, 121, 124) | unchanged (residual) |
| glass back chevron | (13, 13, 15) on (243, 243, 248) | (0, 0, 0) on (251, 251, 254) | unchanged (residual) |

- `ContentUnavailableView`'s description uses UIKit's `secondaryLabel` (the view is UIKit's
  content-unavailable configuration on iOS), not the hierarchical `.secondary`; changed on the
  iOS layout for both chromes (on the iOS 26 chrome `.secondary` already resolved to
  `secondaryLabel`, so nothing changes there).
- Residual: a `.secondary` style inside a list **section header** draws `secondaryLabel` on iOS
  27, while the same style in rows draws black at 0.5. One sample; the guest resolves hierarchical
  styles without their container, so this is left open rather than guessed.
- Residual: separators composite to (231, 231, 232) in the guest and (232, 232, 232) on iOS
  (`separator`'s 0.12 alpha quantised to 31/255 by the 8-bit renderer). 1/255; not changed (the
  renderer's compositing is shared with every exact-match gate).

## 2. Glyph ink beyond the root screen

`SSG_INK_LOG` now also works in scripted runs (stupid-app-preview harness patch: the cumulative
miss list is written at every `snapshot` and at the end, so a later failing step still leaves the
log). Screens logged: root, detail, settings, search, story (`tap 0.34 0.26 --no-settle`,
`wait 2s`), chats, chat. **Group chat ("apron.chat / general") is not reachable** on this
base: the guest segfaults on that tap (Chats work is in flight elsewhere); the Telegram chat is
reached but lays out wrongly (same work), so its keys are those of the guest's layout.

87 misses before: `system-bold|22` (the search empty-state title), `system-medium|15` and
`system-semibold|13/14/15` (story viewer: "starred …", "Open on GitHub", "12.4k"; chats),
`system-regular|17/20` (search, settings), `system-bold|12`, `system-regular|12/15`
(timestamps, U+2022, U+2014, U+202F), plus emoji.

Harvest (`scripts/ink_probe_sim.sh`, `SIM_DEVICE=2x`, `SIM_UDID` = a temporary iPhone SE (3rd
generation), iOS 27.0 (24A434), created, claimed, deleted per run): for each logged
family/size, printable ASCII 33-126 at the size's phase grid (F0.0/F0.5 from 17 pt,
F0.0/0.25/0.5/0.75 below) plus every logged key, excluding emoji: 2127 keys, 2123 harvested,
4 skipped as "no ink" (U+202F). A second run added `system-bold|20` (the corrected title font,
below): 161 keys. Only missing keys were merged: `glyph_ink_ios.json` 10891 -> 13175 keys
(existing keys keep their masks).

U+202F NARROW NO-BREAK SPACE (the space before "PM" in en_US times) is skipped like SPACE and
U+00A0 in `UILabel` and `AttributedTextDraw`, as the harvest found it has no ink.

After: the miss log is **empty** for root, detail, settings, search and story. Chats and chat
log only emoji (U+1F440, U+1F4F8, U+1F604, U+1F680, U+1F92F, U+1F9D7, U+1F44D): colour glyphs,
which a coverage-mask table cannot represent; the guest leaves them out of the line as before.

### Search empty-state title: 20 pt bold, not title2

With real masks the title was still 9 % too wide. MEASURED on the reference: "Search Profiles"
ink [125, 312, 266, 327] (141 pt wide, "S" 11.33 x 15 pt); the guest's title2 bold (22 pt) drew
[118.5, 311, 272.5, 327.5] ("S" 12.5 x 16.5). `ContentUnavailableView`'s iOS title is now
`.title3.weight(.bold)` (20 pt bold), and the symbol gap / space below are refitted (21.17 and
27.83 pt) so the block keeps its measured place:

| ink (pt) | reference | before | after |
| --- | --- | --- | --- |
| title | [125, 312, 266, 327] | [118.5, 311, 272.5, 327.5] | [125, 312, 266, 327] |
| description first glyph top | 339.33 | 340.5 | 339.5 |
| symbol | [176, 245.67, 214.33, 284.33] | [175.5, 246, 214, 284.5] | [175.5, 246, 214, 284.5] |

## 3. Docked search field (iOS 27)

MEASURED on the Search reference (3x): the glass platter is unchanged ([28, 768, 334, 48]), but
the text field is the platter's full width and 28 pt tall, centred ([28, 778, 334, 28] in the
accessibility tree); the magnifier (the same 6.667 pt ring + handle vector as iOS 26.1, 2 pt
strokes) is drawn in `label` with its ring centred at (20.667, 11.333) in the field; the
placeholder (17 pt medium) starts its text box 40.667 pt into the field, with its line box top at
783 (1 pt below UILabel's rounded centring); the placeholder grey is vibrant (every backdrop
channel drops by 102: (248, 247, 252) -> (146, 145, 150)), drawn as black at 0.41. The platter
has iOS 27's grey rim (the bar platters' `_UIBarPlatterRimView`) and only a faint shadow below
(<= 3 counts), i.e. `_UIBarMetrics.iOS27ShadowOpacity`.

`UISearchBar.BottomDock.usesIOS27Field` (iOS 27 chrome, iOS cut, portrait) selects these;
`UITextField._textLineDrop` (0 by default) carries the 1 pt line drop. Compact height and dark
appearance are not measured and keep iOS 26.1's geometry / `secondaryLabel`.

| ink (pt) | reference | before | after |
| --- | --- | --- | --- |
| magnifier | [42, 783.33, 58.67, 800] black | [48, 782.5, 62, 798.5] (135, 135, 141) | [42, 782.5, 58.5, 800] black |
| placeholder "S" | x 69.67, y 786 ... 798.67 | x 75.5, y 785 ... 798 | x 69.5, y 786 ... 799 |
| placeholder "Search" width | 53.0 | 53.0 | 53.0 |
| placeholder colour on the glass | (146, 145, 150) | (135, 135, 141) | (148, 148, 150) |
| platter rim / shadow below | rim; 3 counts | no rim; ~10 counts | rim; faint |

## Verification

- `swift run swiftuiscreensprobe` section 6 (both chromes): docked field frame, text box and
  placeholder line box, magnifier ring centre, placeholder colour, rim view and shadow,
  `opaqueSeparator` per chrome, `systemBlue`, `ContentUnavailableView` description colour and
  title font; iOS 26 values unchanged. `rootresidualsprobe`, `swiftuinavchromeprobe`,
  `swiftuitextmetricsprobe` pass.
- stupid social scripted runs before/after against the references (tables above). Differing
  pixels at fuzz 10 % against the 2x references: search 15165 -> 5436, story 18730 -> 16293,
  detail 17547 -> 16983, settings 8058 -> 8058. The root render is pixel-identical to the
  base's (0 differing pixels).
- Phase 2 rung b (macOS triple): the rim view is only created where it applies, the palette and
  field changes are iOS-cut + iOS 27 chrome only, and the U+202F skip changes no gate text.
