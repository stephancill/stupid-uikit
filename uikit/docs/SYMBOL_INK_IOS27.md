# iOS 27 symbol ink overlay

Follow-up to `ROOT_SCREEN_RESIDUALS.md`: the guest drew stupid social's toolbar `gear` from the
iOS 26.1 harvest (`Resources/symbol_ink_ios_3x.json`), and iOS 27 redrew the symbol, so the gear's
UIKit image item was narrower than iOS 27's and the root toolbar capsule's left edge and the
magnifier sat 0.8 pt right.

## Where the symbol masks come from

`SymbolInkTable` (OpenUIKit) stamps `UIImage(systemName:withConfiguration:)` on the iOS cut from
masks harvested on the simulator by `Tools/oracle2/symbolinkprobe` (`scripts/symbol_ink_probe_sim.sh`):
a `UIImageView` of the symbol, `UIColor.label` over opaque white, coverage = 255 - gray, cropped to
the ink with the alignment box kept (`pw`, `ph`, `ox`, `oy`). Keys are
`name|pointSize|weight|scale|phase` at four configurations (17 regular unspecified, 17 regular
large, 17 medium large, 18 medium large); 2x has phases F0/F0.5, 3x F0 only. The table is selected
by `OpenUIKitRuntime.imageScreenScale` (3 on the iPhone 16e stupid social renders as). The base
tables are iOS 26.1 (iPhone SE 3rd generation 2x, iPhone 16 3x) and the Hackers iOS 26.1 golden
draws its gear from them, so they stay.

## The overlay

- `Resources/symbol_ink_ios27.json` (2x) and `symbol_ink_ios27_3x.json` (3x): the same probe on the
  **iOS 27.0 simulator runtime (build 24A434)**, temporary iPhone SE (3rd generation) at 2x and
  iPhone 16 at 3x (the original harvest's device types and scales), 2026-10-31. Provenance is in
  each file (`device`, `runtimeBuild`, `deviceType`, `scale`, `harvested`).
- Names: the 34 names of the base table that stupid social's sources use (`systemName:` /
  `systemImage:` literals intersected with `names.txt`), at the four stored configurations: 272
  entries at 2x, 136 at 3x. Names the guest draws from the open (Phosphor) set were not harvested.
- `SymbolInkTable.stampTemplate`: with `OpenUIKitRuntime.chromeRelease == .iOS27` a name in the
  overlay draws from it; otherwise, and on the iOS 26 chrome every existing gate pins, the iOS 26.1
  table as before. The missing-key precondition applies to whichever table resolved.
- The aliases still hold on iOS 27 for every harvested name: unconfigured is byte-identical to
  17|regular|unspecified, `textStyle: .body` medium large to 17|medium|large.

## What iOS 27 changed (MEASURED, 3x)

| key | iOS 26.1 image / ink (pt) | iOS 27.0 image / ink (pt) |
| --- | --- | --- |
| `gear\|17\|medium\|large` | 27.67 x 27.67 / 23.67 x 23.33 | 29 x 29 / 25 x 25 |
| `gear\|18\|medium\|large` | 29 x 29 / 25 x 25 | 30.33 x 30.33 / 26.33 x 26.33 |
| `magnifyingglass\|17\|medium\|large` | 25.67 x 25.33 / 21 x 21.33 | unchanged geometry, edge pixels differ |
| every `\|17\|regular\|unspecified` | alignment box 2 px taller, ink 1 px lower (`oy` 3 → 4) | |

`gear` is a redrawn glyph (more, finer teeth): correlation of the 3x mask with the reference
screenshot's gear (stupid social root, iPhone 16e, iOS 27.0) is 0.705 for iOS 26.1 and 0.9999
for iOS 27.0. 111 of the 136 3x masks and 197 of the 272 2x masks differ from iOS 26.1 at all.

## Verification

- Harvest: `scripts/symbol_ink_probe_sim.sh` with `SIM_UDID` on a temporary simulator
  (`xcrun simctl create tmp-sy-harvest-3x com.apple.CoreSimulator.SimDeviceType.iPhone-16
  com.apple.CoreSimulator.SimRuntime.iOS-27-0`, `SIMCTL_CHILD_INK_SCALE=3`; and the SE with
  `SIM_DEVICE=2x`), `SYMBOL_NAMES` = the 34 names; no skipped keys, no missing names. The probe now
  adopts the scene lifecycle (iOS 27 traps at launch without it, as for `inkprobe`).
- `rootresidualsprobe`: gear 3x 83 px / ink 71 on the iOS 26 chrome and 87 / 75 on iOS 27, gear
  2x 56 x 55 vs 58 x 58, the magnifier's iOS 27 size, `chevron.right` unconfigured 50 vs 52 px tall,
  and a name outside the overlay (`house`) pixel-identical on both chromes.
- `swiftuinavchromeprobe`, `swiftuistrokeprobe` pass unchanged (the iOS 26 checks are untouched;
  the iOS 27 width check derives from the image, now 29 + 22).
- Phase 2 rung b (macOS triple, Catalyst cut: the table is not consulted there).

## stupid social root, 2x render against the iOS 27.0 reference (iPhone 16e)

Offline guest render (`SSG_OFFLINE=1`, `SSG_CHROME=ios27`), ink boxes at 2x in points, centroids
coverage-weighted; reference `sim-2x.png` (3x reference in brackets where it differs).

| element | reference | before | after |
| --- | --- | --- | --- |
| capsule incl. rim | [266.5, 46, 375, 92] ([266.67, 46.33, 374.67, 91.67]) | [267.5, 46.5, 374.5, 91.5] | [266.5, 46.5, 374.5, 91.5] |
| platter frame (view dump) | [267.33, 47, 106.67, 44] (3x) | [268, 47, 106, 44] | [267, 47, 107, 44] |
| gear ink | [336, 57, 360.5, 81.5] | [337, 57, 360.5, 80.5] | [336, 57.5, 360.5, 82] |
| gear centroid | (348.41, 69.32) | (348.83, 68.83) | (348.43, 69.69) |
| search ink | [280.5, 58.5, 301.5, 79.5] | [281.5, 58.5, 302.5, 79.5] | [280.5, 58.5, 301.5, 79.5] |
| search centroid | (290.99, 68.89) | (291.78, 68.74) | (290.83, 68.73) |

Toolbar crop (240 x 120 px) RMSE against the reference 0.132 → 0.057; differing pixels at fuzz 10 %
1341 → 697. The render changed only inside the toolbar capsule (2773 px, bounding box
[266.5, 46.5, 361, 91.5]); no other symbol on the root screen draws from the overlay's changed
configurations.

Residual: the gear sits ~0.35 pt low. Its 29 pt image is centred in the 44 pt item and
`_UIBarButtonItemView.layoutSubviews` rounds the y origin to whole points (7.5 → 8); the reference
matches 7.67 (the 3x pixel grid). Rounding to the device grid instead would move the magnifier
(9.33, already whole-point rounded to 9) 0.17 pt below its reference, so the vertical rule is not
settled by this screen and was left as is.

## Risks

- The overlay selects on `chromeRelease`, the host's iOS 27 opt-in. A host that renders iOS 27 bar
  chrome now also gets iOS 27 masks for the 34 names, including `17|regular|unspecified` boxes that
  are 2 px taller at 2x and 3x, which moves symbols centred on their alignment box by up to
  1/3 pt.
- Other names stay iOS 26.1 on the iOS 27 chrome; the table mixes releases per name.
- Dark appearance was not harvested (opaque-label masks were byte-identical light/dark on iOS 26.1).
