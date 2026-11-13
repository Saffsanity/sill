# `dmg-layout`

**Checks:** the `.DS_Store` of Sill.dmg's window byte by byte against Finder's own layout of the file (blocks, free lists, header), the window's bounds (the picture and macOS 27's 32-point title bar), view options and icon places; the background's alias field by field; the encoder and decoder, a two-level tree among them; the volume icon's flag; an alias for a real file where it runs; that make-dmg.sh and the SVG still give that window

**Compiles:** `Scripts/dmg-layout/DSStore.swift`, `FinderAlias.swift`, `DMGLayout.swift` (with make-dmg.sh's layout arguments and `design/DMGBackground.svg`)
