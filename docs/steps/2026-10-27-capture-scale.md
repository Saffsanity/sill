**Capture at the display's own pixel scale (2026-10-27, branch `capture-scale` from main at
74d099c2, main at 76bc100 (#157) and 48a4ef3 (#147) merged in; PR #233).** Noah, tonight, Sill.app from 74d099c2 on
this Mac with its lid closed, an external 2560×1440 display at 1x as the main one and a 1920×1080 at
1x to its left (CGDisplayBounds (-1920, 214); read, nothing captured): a window picked showed in the
top-left quarter of the iPad's picture, black around it, Aa changing nothing, while the Desktop
looked right; and a drag to the bottom of the Desktop's picture never brought up the auto-hidden
Dock. Host only: no wire change, no device file, VirtualStage and VirtualDisplay untouched.
- The cause (Sill.log): `Capture started: 5120×2880 … filter (2560.0, 1440.0) scale 1.0` for the
  Desktop, `2234×1220 … filter (1117.0, 610.0) scale 1.0` for the window (and 4468×2440, 3024×1898,
  2912×2140, 1960×1200 of others since 2026-10-26): the points times the Resolution knob
  (`captureScale` 2), while ScreenCaptureKit draws a window at its display's own scale into the
  top-left of a larger buffer, never scaling it up, and scales a display up to fill one (four times
  the pixels: the encoder's 1–2 fps there).
- The rule (`CaptureScale.effective(knob:displayScale:)`, pure, `Sources/SillHost/CaptureScale.swift`):
  the lesser of the knob and the display's own scale, ScreenCaptureKit's for the filter being
  captured (`pointPixelScale`, the capture line's "scale"; not CGDisplayMode's pixel width ÷ point
  width: only the filter's is the scale it draws that content at, a window across two displays
  held to the one it picks, so no rule of Sill's can disagree). On a 1x display Retina and Standard
  both capture at 1x (2560×1440, that window 1116×610 at the merge, 1118×610 since its follow-ups (#234):
  an odd side rounded up, drawn whole); a 2x display as before; the test pattern
  1512×949 × the knob; a window staged on Sill's 2x virtual display at the knob. The same scale
  sizes a window's restart on a resize, each catalog poll restarts a window that moved onto a
  display of another scale (`catalogPolled`: the list never changes for it), the away pair goes
  through it, and the link's suggestion and the re-check's test size follow it; `restartNeeded`
  still compares the knob (a Resolution change on a 1x display restarts once, to the same size).
  The line: "Capture started: 2560×1440 @60 fps, cursor out, filter (2560.0, 1440.0) scale 1.0,
  capturing at 1x, the display's own (2x asked)".
- The Dock (`InputLanding.point`, the same file): a device's bottom edge is y = 1 (PadCursor clamps
  to 0…1 with 1 in; the iPad's pointer, a Pencil and a drag past the picture are held to it), which
  InputInjector posted at `minY + 1 × height`: 1440.0 on a 1440-point display, not short of the last
  row but the row past it (1439 is the last), off the display by CGRect's containment and by
  PointerControl's own inside test. Where the window server puts that move, and whether the Dock's
  trigger takes it, is not known here. Now a fraction is held to 0…1 and lands at most at
  `maxX − 1/scale`, `maxY − 1/scale` (1439 at 1x, 981.5 at 2x, a point in for the test pattern), where
  a pointer pinned at the edge is; elsewhere where it did. Not changed, the next suspect if the Dock
  still does not come: Sill's moves carry no mouse deltas, and macOS moves the Dock to another
  display only for a push against the edge (a Dock last shown on the 1920×1080 display).
- Verified: `swift build -c release` from `git archive` of b2bb428 and of main at 76bc100, only the
  CaptureProbe warning; `Tests/checks/capture-scale` 79 checks and 19 of 19 mutants (the first
  commit alone 42 and 9 of 9), in CI's mutants matrix; `Tests/checks/run-all.sh`, all 53 at b2bb428
  (454 s; 54 since the merge of 48a4ef3 brought `text-composition`: all 54 on the follow-ups' branch,
  473 s);
  H2 against main's CLI at 76bc100, both from `git archive`, `--synthetic` on loopback (the software
  encoder, no router, no screen): idle 35 s identical masked and sorted (8 lines), and with
  `sillclient.py PORT 8 desktop` identical masked and sorted but for the stats lines of the seconds
  the client leaves in, the same kinds reaching the client (the test pattern has no capture line,
  so no new words); a dry run of input there (SILL_TEST_INPUT_LOG, a scripted pointer, nothing
  posted): a tap at the pattern's far corner went to 1512,949 on main, to 1511,948 here, its middle
  (756,475) and origin as before. A second round was refused by no-device.sh (Noah's iPad connected
  at 01:50). Not run: `--virtual-display-selftest`, which warps this Mac's cursor, posts a HID move
  and makes a display (its sources, VirtualDisplay's and VirtualStage's are untouched); any capture
  of this Mac's displays or windows; Sill.app.
- **Untested, for Noah** (Sill.app from this branch, release-signed with the embedded profile; the
  iPad): on the 2560×1440 display a window picked fills the picture (Sill.log: "…, capturing at 1x,
  the display's own (2x asked)") and Aa still fits it; the Desktop captures at 2560×1440 and runs at
  60 fps (`enc.out` near `cap.complete`); with the Dock auto-hidden and the Desktop streaming, a drag
  to the picture's bottom edge (the portrait trackpad, the Magic Keyboard's trackpad) brings up the
  Dock (if not, note which display it was last on); a window dragged between the two 1x displays
  streams on with no restart; with Virtual Display on, a picked window still at 2x.
- From the post-merge verification, for Noah (no code; the verdict, in the entry above): a drag-select
  past a text window's bottom or right edge may no longer creep-scroll. A device's far edge now lands on
  the window's last pixel row or column (InputLanding), where main's landed one pixel outside the
  window, and AppKit autoscrolls a text view only while the pointer is outside the view: in a window
  whose text reaches its edge, the last row is still inside it. A hypothesis, not tried: if a selection
  dragged to the picture's edge stops scrolling the text, that is why, and a drag alone could land a
  pixel outside again. And the Desktop reads its display's scale once, at `select` (its filter's
  `pointPixelScale`); nothing reads it again while it streams (a window's is looked at each catalog
  poll, `catalogPolled`), so a display misreported at the moment of a pick (the verification saw one, a
  display going away as the lid closed) keeps that capture size until the next restart (a pick, a
  settings change, the encoder's fallback).
