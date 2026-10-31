# Noto Color Emoji

- Use: OpenUIKit's colour emoji (`Sources/OpenUIKit/ColorEmoji.swift`,
  `docs/COLOR_EMOJI.md`) draws emoji glyph images from this font. The font is
  not vendored in this repository: hosts install it from the distro package and
  app bundles copy it to `OpenUIKit/fonts/NotoColorEmoji.ttf`.
- Upstream: https://github.com/googlefonts/noto-emoji, release v2.047
  (Copyright 2013-2017 Google Inc., Arjen Nienhuis).
- Package: Ubuntu noble `fonts-noto-color-emoji=2.047-0ubuntu0.24.04.1`
  (Debian builds `fonts/NotoColorEmoji.ttf` from the v2.047 sources).
- File: `/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf`, SHA-256
  `93cdc4ee9aa40e2afceecc63da0ca05ec7aab4bec991ece51a6b52389f48a477`
  (pinned in `env/contract.json`, row `noto-color-emoji`).
- Licence: SIL Open Font License 1.1 (`NotoColorEmoji-OFL.txt`, the upstream
  `fonts/LICENSE`, SHA-256
  `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`).
  The font's tools and images are Apache-2.0; only the font file is used.
- Apple Color Emoji is never shipped, read or derived: advances and placement
  are measured from iOS Simulator screenshots, glyph images are Noto's.
