**Capture scale follow-ups (2026-10-27, branch `capture-scale-followups` from main at b4caa910; PR #234).**
The post-merge verification of #233 (sill-handoff's
`triage/2026-10-20-reports/verdicts-2026-10-26/pr233-verdict.md`) left small follow-ups, all taken here.
Host only: no wire change, no device file.
- A window's odd side, drawn whole (`CaptureScale.windowPixels`, `windowSize`, `windowNeedsRestart`,
  pure): on a 1x display a 1117×610-point window was asked 1116×610 (`evenPixels`, down to even), and
  ScreenCaptureKit, which only scales a window down (`scalesToFit` left false), shrank its 1117 columns
  into 1116: up to half a pixel of blur mid-picture, where a text stem is one pixel wide. A window
  captured at its display's own scale is drawn 1:1 at the buffer's top-left, so an odd side now rounds
  up to even: 1118×610, one black column past the window (Sill.log's 818×565, 728×535 and 377×235:
  818×566, 728×536, 378×236); a half point on a 2x display the same; Standard on a 2x display (scaled
  down anyway), the Desktop, a staged crop and the test pattern as before. Chosen over asking even
  points in the Aa fit (`fitToViewport`), which would reach only windows Sill sizes and that take the
  size, not one sized by hand, one with Aa unset or an app that keeps its own steps. The device draws
  the frame aspect-fit on black (HEVCDisplayView): the column joins a letterbox beside it, or is a black
  hairline (a frame's pixel) at the picture's right edge where the frame fills its panel; the viewport
  it sends is the panel or the room, never the frame's shape, so nothing feeds back into a fit. A
  device's position lands as the same fraction of the window (InputLanding), and the Mac's arrow is
  drawn at its fraction of the frame: at most a pixel apart from the picture, at the far side, the far
  edges still landing on the window's last pixel row and column. `select` (and the real window after a
  failed stage) sizes a window with `windowSize`; `windowsChanged` asks `windowNeedsRestart`, the same
  rule, so a rounded-up window never restarts at every poll (the old comparison would have: 1116 against
  an encoder at 1118) and 1117 to 1118 points needs no restart; `catalogPolled` still compares only the
  scale.
- The words, true on a 1x display too (Retina and Standard capture the same there, and the software
  encoder runs at the hardware's size): the status menu's Resolution › Standard, "On a Retina display, a
  quarter of the pixels to encode" (it was "A quarter of the pixels; much lighter to encode"); the
  fallback's two lines, "switching to the software encoder, capturing at 1x, until …" (CaptureScale.words
  of the software knob; it was "at half scale"); the coordinator's comments and DEVELOPMENT.md's "restarts
  at half resolution on the CPU".
- Verified: `swift build -c release` from `git archive` of 70e3d171 (the code; the commits after it are
  docs) and of main at b4caa910, only the CaptureProbe warning; `Tests/checks/capture-scale` 122 checks
  and 30 of 30 mutants (eleven new: the window rule's ten, `evenPixels`' one; in CI's mutants matrix);
  `Tests/checks/run-all.sh`, all 54 (473 s); H2 against main's CLI, both from `git archive`,
  `--synthetic` on loopback (the software encoder, no router, no screen; Noah's iPad streamed from
  Sill.app over the cable meanwhile, and nothing here touched the hardware encoder): idle 35 s identical
  masked and sorted (8 lines), and with `sillclient.py PORT 8 desktop` every host line but the stats
  lines, and every client line but the count of kinds received, identical masked and sorted (the test
  pattern keeps `evenPixels`, 1512×948, and SILL_TEST_SOFTWARE_ENCODER prints no fallback line, so no
  new words reach H2), the stats lines and the count of cursor shapes differing as main's from itself in
  a second run (`cursor.shape` follows the Mac's own cursor; the second the client leaves in); the
  previews from the two bare SillMenuBar binaries, run from one path: identical but menu.txt's Standard
  line, in each of its 25 samples. Not run: any capture of this Mac's screen or windows, the hardware
  encoder, input to this Mac, `--virtual-display-selftest`, Sill.app.
- **Untested, for Noah** (Sill.app from this branch, release-signed with the embedded profile; the iPad,
  the 2560×1440 display at 1x): a window with an odd width at Aa 1x (Sill.log: "Capture started: 1118×610
  … filter (1117.0, 610.0) scale 1.0, capturing at 1x, the display's own (2x asked)") shows its text as
  sharp as the Desktop's, with at most a black hairline at the picture's right edge; the window made a
  point wider on the Mac (1117 to 1118): no second "Capture started"; Resolution › Standard's new line.
