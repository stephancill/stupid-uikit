# Phosphor Icons (open symbol fallback)

- What: SVG path data for the glyphs listed in `uikit/Tools/opensymbols/mapping.tsv`,
  regular and fill weights only, generated into
  `uikit/Sources/OpenUIKit/OpenSymbols/OpenSymbolCatalog.generated.swift`.
  Nothing else from the package is vendored.
- Source: npm package `@phosphor-icons/core` 2.1.1
  (https://www.npmjs.com/package/@phosphor-icons/core, repository
  https://github.com/phosphor-icons/core), tarball
  https://registry.npmjs.org/@phosphor-icons/core/-/core-2.1.1.tgz,
  sha256 `313332be6190b724da24107addd781799b48bf76b13963f24501112ffe1baadd`,
  npm integrity `sha512-v4ARvrip4qBCImOE5rmPUylOEK4iiED9ZyKjcvzuezqMaiRASCHKcRIuvvxL/twvLpkfnEODCOJp5dM4eZilxQ==`.
  Files read: `assets/regular/<icon>.svg` and `assets/fill/<icon>-fill.svg`.
- Licence: MIT, Copyright (c) 2023 Phosphor Icons — `PhosphorIcons-LICENSE`.
- Why: SwiftUI `Image(systemName:)` / UIKit `UIImage(systemName:)` need real icons
  for SF Symbol names; Apple's SF Symbols may not be copied or shipped, so open
  glyphs are chosen per SF Symbol name instead.
- Regenerate: `python3 -I uikit/Tools/opensymbols/generate.py --phosphor <unpacked package>
  --out uikit/Sources/OpenUIKit/OpenSymbols/OpenSymbolCatalog.generated.swift`.
