# Design sources

- `AppIcon.svg` — the app icon on the 1024 grid, full square (iOS applies the
  squircle). Four groups map to Icon Composer layers: background, iMac, iPad,
  window. Render the asset with:

  ```
  qlmanage -t -s 1024 -o . design/AppIcon.svg   # then flatten alpha before adding to the catalog
  ```

  The three-direction exploration and the final board live on the design
  canvas linked from `docs/BRIEF.md`.

- The Mac app's icon comes from the same file. `Scripts/make-app.sh` renders
  it with Quick Look (`qlmanage -t -s 1024`), makes the render the one layer
  of a generated Icon Composer document, and compiles that with Xcode's
  `actool` into `Assets.car` (macOS 26 and later mask and light it natively)
  plus a pre-masked `AppIcon.icns` for macOS 14–15. A plain `.icns` made with
  `sips`/`iconutil` shows up on macOS 27 as a shrunken icon inside a grey
  tile. The result is cached in `.build/icon`. A layered
  `Packaging/AppIcon.icon` made in Icon Composer from the SVG's four groups
  replaces the generated one as soon as it exists.
- `DMGBackground.svg` — the window of Sill.dmg, the Mac download: 660 x 400
  points of white, an arrow from where Sill.app sits (170, 180) to
  Applications (490, 180) in the app icon's greys, and "To install Sill, drag
  it to Applications." under them. `Scripts/make-dmg.sh` renders it with Quick
  Look at 1x and 2x into one TIFF and puts the icons on it with a `.DS_Store`;
  moving either icon means changing the SVG's arrow and the script's `--item`
  lines together (`Tests/checks/dmg-layout` holds the same numbers). Keep
  every edge white: the window is sized for macOS 27's title bar, so under
  macOS 14's and 15's shorter one it shows 4 points below the picture.
- The menu bar glyph is drawn in code from the same geometry
  (`Sources/SillMenuBar/StatusGlyph.swift`): the iMac outline with the tilted
  iPad, as a template image. `SillMenuBar -SillRenderPreviews <dir>` writes
  `glyphs.png` with every state on light and dark bars.
