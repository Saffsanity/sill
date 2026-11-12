**A device's viewport held to what a host takes (2026-10-29, branch `sec-viewport-bounds` from main at
150479b5, PR #251; the security scan's finding 4, Low; Noah's go of 2026-10-29 for the batch).** Kind 9 carried
the panel and Aa's scale as Doubles with no bounds and the host took any number above 0: a viewport of 1e300 points
(or a scale of 1e-300) from any device a Mac admitted reached the window's fit (`fitToViewport`), whose "Resized …"
line made an Int of it, which traps, so Sill died with every device's session (the scan's chain with finding 3: its
Bonjour name then free for an impostor); with the virtual display `VirtualStage.windowSize` was unheld and the
"insists on …" line trapped the same way (a full-screen window's crop of an infinite panel was NaN, which
`evenPixels` traps on). No wire change.
- `ViewportBounds` (StreamProtocol's Viewport.swift, pure, `Tests/checks/viewport-bounds`): each side 1 to 16384
  points, a text scale 0.25 to 4 or none. The host refuses any other viewport whole at kind 9, and one that does not
  decode (JSON carries no NaN or infinity): the last viewport stands and nothing of the message is taken, its rate
  neither; one line naming the device, at most one a second per connection ("Viewport from sillclient refused: width
  1e+300 (1 to 16384 points), height 1e+300 (1 to 16384 points)"), `vp.refused` in the `[1s]` lines counting every
  one. Every device build's viewport is within them (the compatibility floor's new line), and a device holds what it
  sends to them (`held`, in `sendViewport`). The two lines print through `ViewportBounds.whole` (Int()'s number,
  toward zero, without its trap); no other host line prints a device's number through Int() (a click's point is held
  to the source by InputLanding, the rest are the Mac's own).
- The window's size on the virtual display held to 1…65536 points a side, the most a host takes (16384 points at
  0.25; `VirtualDisplaySize.windowSize`, `Tests/checks/capture-scale`): every viewport a host takes is asked as before
  (a side under half a point 1, not 0), the placement fits it to the display, and a full-screen window's crop keeps
  the panel's shape (the review's second finding: held at the display's 4096 it did not).
- `sillclient.py --raw9=JSON@T` sends a literal viewport.
- Verified: `viewport-bounds` 79 checks and 26 of 26 mutants (18,566 of its 200,000 random viewports main's guard
  took and its line trapped on, none taken now), `capture-scale` 172 and 48 of 48; `run-all.sh`, all 57; `swift
  build -c release` from `git archive`, only the CaptureProbe warning; the three iOS builds, only the known
  `StreamClient` capture warning; live, a loopback synthetic host streaming the test pattern: 1e300, -1, NaN,
  Infinity and a scale of 1e-300 each refused with its line (NaN and Infinity: "it does not decode as a viewport"),
  three in 0.4 s one line and `vp.refused 3`, 16384 points at 0.25 taken, the stream going throughout (47–58 frames
  a second). main's own lines (the handler, the fit's guard, target and line, the stage's window size and line, cut
  from 150479b5 and compiled with its Viewport.swift) trap on the scan's payload and on a scale of 1e-300 (exit
  133); the branch's refuse and go on. Not live on main's host: only a real window resized through Accessibility
  reaches that line, which no test host lists.
- The review (2026-10-29, after a02c1afe; the report's "The review"): two findings, each reproduced first and fixed in
  a commit of its own. (1) f664a04d: a device's ClientStats `audioLate` was added to the stats line's count with a
  plain `+` (StreamServer, from the audio work, after the scanned commit), so two reports of Int.max within the line's
  1.5 s trapped: a loopback host built from a02c1afe died at the third report (exit 133), and lived with 1000; now
  `ClientStats.lateSince` (Viewport.swift, pure: nothing for a missing or negative count, the sum stopping at
  Int.max), and the rebuilt host took ten reports of Int.max and printed "9223372036854775807 late". (2) 972e2b87: the
  window's size on the virtual display held at 4096 changed a full-screen window's crop for a panel past the display
  (from the commits' own lines, a 2560×1400 panel at 0.5x: main 4096×2240, 1.829:1, the panel's shape; a02c1afe
  4096×2800, 1.463:1, black bars on the device); now 65536, every row as main's. Re-verified: `viewport-bounds` 87
  checks and 30 of 30 mutants, `capture-scale` 175 and 50 of 50; `run-all.sh`, all 57 (8 min 16 s); `swift build -c
  release` from `git archive`, only the CaptureProbe warning; the three iOS builds, only the known `StreamClient`
  capture warning; live on one loopback host, every kind 9 above refused again with its line, and the review's tries
  (1.7976931348623157e308 refused, as -0 and 5e-324 were in a run on a02c1afe; 1e999 and a rate of 1e300 "does not
  decode"; a duplicate key and a rate of Int.max taken, the rate held by `wantedFPS`; a rate of Int.min, on a02c1afe,
  a restart at 24 fps), beside them a second client's ten stats reports of Int.max: the host alive throughout.
- A second review (2026-10-29, after 37e47e68; scripts and logs in sill-handoff's
  `triage/2026-10-29-security/f4-live/review2/`): one docs fix, e057acaf (DEVELOPMENT.md gave the refusal line's
  limit per device; it is per connection: one device on two connections got two lines 0.11 s apart). No bypass: 92
  hostile payloads of every kind a device sends but 19 and 32, on a loopback host with a scripted pointer, every ping
  and kind 17 answered; 2,178 viewports a host takes in 15 s from two devices (236 restarts), the host streaming
  after. Re-run: `viewport-bounds` 87 and 30 of 30 (five more mutants of the reviewer's caught), `capture-scale` 175
  and 50 of 50, `compatibility`'s mutants 34 of 34 (one of Viewport.swift); `run-all.sh`, all 57 (8 min 28 s);
  `swift build -c release`, only the CaptureProbe warning; the three iOS builds, only the known `StreamClient`
  capture warning. Built, as the first review had not: the pacing harness from origin/main and this tree (`home`:
  60.0 fps both, every gate), the audio harness and the restore probe's driver (not run).
- **Untested, for Noah:** nothing should change on a device: Aa's steps and none, a rotation and the virtual display
  as before on the iPad and iPhone, and Sill.log without a "Viewport from … refused" line; if an iPad with Stage
  Manager on a large external display is at hand, a full-screen window (a video) on the virtual display at Aa 0.5x
  fills the panel as on main.
