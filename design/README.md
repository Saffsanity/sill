# Design sources

- `AppIcon.svg` — the app icon on the 1024 grid, full square (iOS applies the
  squircle). Four groups map to Icon Composer layers: background, iMac, iPad,
  window. Render the asset with:

  ```
  qlmanage -t -s 1024 -o . design/AppIcon.svg   # then flatten alpha before adding to the catalog
  ```

  The three-direction exploration and the final board live on the design
  canvas linked from `docs/BRIEF.md`.
