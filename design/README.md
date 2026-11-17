# Design sources

- `../Packaging/AppIcon.icon` — the app icon, an Icon Composer document and
  the one source for both apps (since 2026-11-17, replacing the iMac with the
  tilted iPad). A window lifted out of the Mac's screen, its empty place left
  dashed, now held in an iPhone turned sideways. Three groups, front to back:
  the window; the phone (its frame glass, its screen and Dynamic Island);
  the Mac (its frame glass, the dashed place). Each layer is a 1024 × 1024 SVG
  in `Assets/`; the background is the document's own blue gradient. iOS,
  iPadOS and macOS apply Liquid Glass and make the Dark, Clear and Tinted
  looks from it. Open it in Icon Composer (Xcode › Open Developer Tool) to
  change it. Render a look from the command line with Icon Composer's `ictool`:

  ```
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Packaging/AppIcon.icon --export-image --output-file icon.png --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
  ```

  The iOS app takes it as a resource (`ASSETCATALOG_COMPILER_APPICON_NAME`
  AppIcon; Xcode 26 or later), with PNG fallbacks for iOS 17 to 25.
- `AppIcon.svg` — a flat copy of that icon on the 1024 grid, full square, no
  glass: for the website (`site/icon.svg` is the same file) and anything that
  takes a plain picture. Change the `.icon` first, then this.
  The original three-direction exploration and its board live on the design
  canvas linked from `docs/BRIEF.md`.

- The Mac app's icon: `Scripts/make-app.sh` compiles `Packaging/AppIcon.icon`
  with Xcode's `actool` into `Assets.car` (macOS 26 and later mask and light
  it natively) plus a pre-masked `AppIcon.icns` for macOS 14–15. A plain
  `.icns` made with `sips`/`iconutil` shows up on macOS 27 as a shrunken icon
  inside a grey tile. The result is cached in `.build/icon`. Without the
  `.icon`, the script falls back to rendering `AppIcon.svg` with Quick Look
  as the one layer of a generated document.
- The menu bar glyph (`Sources/SillMenuBar/StatusGlyph.swift`) still draws
  the old icon's iMac and tilted iPad; it has not followed the new icon yet.
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
- `screenshots/`: the App Store's iPad screenshots that the README shows, at
  half size (1032 × 1376, JPEG). Open-source app lists link these files, so
  keep their names.
