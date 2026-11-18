# Design sources

- `AppIcon.svg` — the app icon on the 1024 grid, full square (iOS applies the
  squircle), flat: an iMac with an iPad tilted in front, the streamed window
  on the iPad, on a dark gradient. The website's `site/icon.svg` is a copy of
  it, and it stays the flat original.

  The three-direction exploration and the final board live on the design
  canvas linked from `docs/BRIEF.md`.

- `Packaging/AppIcon.icon` — the same icon as an Icon Composer document, so
  the system draws it in Liquid Glass (2026-11-18, docs/app-icons-plan.md):
  the SVG's background as the document's fill, and its groups as two layer
  groups, front to back: the iPad (the window, the screen and camera, the
  slate body as glass) and the iMac (the screen, the space grey body with its
  neck and foot as glass). Each layer is a 1024 × 1024 SVG cut from
  `AppIcon.svg` at the same coordinates; the original's gloss is in the
  layers' own fills, and its white rims and drop shadows are left to the
  system (the glass's specular edges and the groups' shadows). The iMac body
  has a lighter fill for the Clear and Tinted looks only, so the iMac reads
  there. It is Sill for Mac's icon (`Scripts/make-app.sh` compiles it with
  `actool` into `Assets.car` and a masked `AppIcon.icns` for macOS 14–15; a
  plain `.icns` shows up on macOS 27 shrunk inside a grey tile) and the iOS
  app's primary icon. `Packaging/AppIconCommunity.icon`, grub-basket's design
  from pull request #386, is the iOS app's alternate icon (Settings, App
  Icon). Render any look of either with Icon Composer's command-line tool:

  ```
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
      Packaging/AppIcon.icon --export-image --output-file out.png --platform iOS \
      --rendition Default --width 1024 --height 1024 --scale 1   # Dark, ClearLight, ClearDark, TintedLight, TintedDark; macOS
  Scripts/app-icon-previews.sh   # the Settings picker's previews of every icon, from the documents
  ```
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
