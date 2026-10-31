# Guest locale and the 24-hour preference

On iOS an app's `Locale.current`, `Locale.preferredLanguages` and the
12/24-hour clock come from the global preferences (`AppleLocale`,
`AppleLanguages`, `AppleICUForce24HourTime` / `AppleICUForce12HourTime`).
Xcode's scheme language/region options and `simctl launch <app>
-AppleLocale en_GB` set them through the launch arguments' NSArgumentDomain.
Linux guests have no CFPreferences, so swift-foundation's non-framework
`LocaleCache` hard-coded `en_001` (English, World) and every guest formatted
times in 12-hour ("11:35 AM").

## Launch arguments (FoundationEssentials patch)

`full/foundation/patches/FoundationEssentials-LocaleArgumentDomain.patch`
(applied by `build_fe.sh` to a derived copy of `Locale/Locale_Cache.swift`,
both hashes pinned) reads the argument domain in the non-framework branch:

```
<guest> ... -AppleLocale en_GB -AppleLanguages "(en-GB, fr)" -AppleICUForce24HourTime YES
```

- `-AppleLocale <identifier>`: the preferred locale (`prefs.locale`).
- `-AppleLanguages`: an old-style property-list array or one identifier.
- `-AppleICUForce24HourTime YES` / `-AppleICUForce12HourTime YES` (YES, NO,
  true, false, 1, 0): `LocalePreferences.force24Hour` / `force12Hour`, which
  ICU formats honour (`Locale.hourCycle`, `Date.FormatStyle`).
- None of them: the upstream neutral default (`en_001`, no hour override).
  No regional locale is assumed.

`Locale.current` is then FoundationInternationalization's `_LocaleICU`,
built as on iOS: the preferred locale, matched against the main bundle's
localizations with the preferred languages.

The facade `DateFormatter` (`full/foundation/DateFormatter.swift`, golden
style tables for en_US, en_GB, de_DE, fr_FR, ja_JP, en_US_POSIX) applies a
forced hour cycle to its style patterns as CFDateFormatter does: forced
24-hour turns h/K into H/k and drops the day period; forced 12-hour turns
H/k into h/K and appends it. Without a preference the tables are unchanged.

## One FoundationEssentials per process

FI swaps in its ICU classes with `@_dynamicReplacement(for:
_localeICUClass())` (and `_calendarICUClass`, `_timeZoneICUClass`). That only
reaches the FoundationEssentials copy FI binds to,
`libFoundationEssentials.dylib`. An executable that also links
FoundationEssentials' objects has a second copy whose `Locale.current` stays
`_LocaleUnlocalized` (`en_001` whatever the preferences) and whose
`TimeZone(identifier:)` is nil. MEASURED in stupid social's guest: with the
objects linked, `-AppleLocale de_DE` still printed `current=en_001` and
"9:59 PM"; linked against the dylib it printed `de_DE`, "21:59" and
"vor 2 Stunden". build_full's own executables (`link_app_executable`,
`COMMON_LINK_OBJECTS`) still link the objects; the phase 2 gates depend on
today's unlocalized behaviour, so switching them is left to a separate change
with its own golden review.

## Verified (stupid social, harness `SSG_LOCALE`)

`SSG_PRINT_LOCALE=1` lines (instant 2026-10-31 21:59 UTC):

| harness | current | languages | `.shortened` | DateFormatter `.short` | day+month | relative (-2 h) |
|---|---|---|---|---|---|---|
| none | en_001 | en-001 | 9:59 PM | (no table) | 31/10 | 2 hours ago |
| `SSG_LOCALE=en_GB` | en_GB | en-GB | 21:59 | 21:59 | 31/10 | 2 hours ago |
| `SSG_LOCALE=en_US SSG_HOUR_CYCLE=24` | en_US | en-US | 21:59 | 21:59 | 10/31 | 2 hours ago |
| `SSG_LOCALE=de_DE` | de_DE | de-DE | 21:59 | 21:59 | 31.10. | vor 2 Stunden |
