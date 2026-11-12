**The iPhone's portrait layout (2026-09-27, branch `iphone-portrait` from main
at cf05a78, PR #30; the plan, its open questions with the defaults taken, its
gates and the review's fixes are in `docs/iphone-portrait-plan.md`).** Noah: on an iPhone
held upright the software keyboard covered the key row's keyboard cap, so
nothing on screen could take it down, and the picture's half left black bars
around a 16:9 or 16:10 window. Approved (2026-09-27): the picture in a fixed
16:10 pane at the top (a 16:9 window gets black bars above and below; nothing
below the pane ever moves), then row 1, Apps, Aa, Keyboard, Desktop and
Settings, widened to the row with the key row's 8 pt between them; row 2, the
thumbnails; row 3, esc, tab, ctrl, opt, cmd and shift (no arrows, no Spotlight
cap); the trackpad in the rest. Landscape, the iPad and the Duo's inner
display unchanged; no wire change.
- `PhonePortraitLayout` (pure, CoreGraphics only; `Tests/checks/phone-portrait`,
  149 cases and 28 of 28 mutants, in CI's mutants matrix): every rect from the
  stream screen's size, the screen less its top inset (the bottom inset and
  the keyboard are ignored, so nothing moves for them). The picture 8 pt from
  the edges, ⌊(W − 16) ÷ 1.6⌋ tall (424×265 on an 18 Pro Max, 386×241 on an
  18 Pro), giving way only where the trackpad would drop under 120 pt (an SE
  with Display Zoom, by 2 pt); row 1's five buttons (W − 60) ÷ 5 wide (76,
  68.4) and 50 tall, centred in a 62 pt band as the compact window bar holds
  its own, so 24 pt under the picture and 22 over the thumbnails (the approved
  mockup's rhythm); the strip 62 tall from 6 to W − 6, its first thumbnail at
  14 with Apps and esc; six caps (W − 68) ÷ 6 wide and 44 tall; the trackpad to
  16 pt above the bottom (412×389 on the Pro Max, 374×331 on the Pro, the
  mockup's; 243 and 202 tall before); the Aa ruler centred on Aa and inside the
  row (36 pt a detent on every phone); the drawer and the Settings panel 8 pt
  under row 1 and across it, Apps' leading edge to Settings' trailing one (523
  and 465 pt of room; 351 and 310 before); the dim and the tap catcher
  everything but row 1's buttons.
- Detection: `DuoLayout.outerPortrait`, unchanged (taller than wide, narrower
  than 600 pt), draws the phone's arrangement on an iPhone: every iPhone
  upright and the Duo's outer display (500×710), which has the same keyboard
  problem, a choice Noah can reverse (`DuoLayout`'s doc says how). An iPad
  window that narrow keeps the compact halves as on main, the key row's fold
  into two rows included: the idiom, read once in `DuoLayout.phoneArrangement`
  (DEBUG `-SillIdiom pad|phone` swaps it). `PortraitMetrics.phone` (`.phone`)
  draws the phone's arrangement, `.compact` and `.regular` the halves.
- `PortraitStreamScreen`: the picture pane, key row, trackpad, drawer and panel
  are built once for both arrangements; the phone's are placed by a small
  `Layout` in reading order (picture, row 1, strip, keys, trackpad). Row 1 is
  the landscape bar's five in its order (Keyboard lit while the keyboard is up,
  "Show the keyboard"/"Hide the keyboard"), each symbol and Aa's text in a
  24 pt box so the five labels share one line; at the accessibility text sizes
  a long press shows a button or cap large (not Aa). The Aa ruler unfolds over
  row 1, its value inside it, and the other four fade and take no touch. The
  drawer and the Settings panel hang under row 1, which stays live and
  undimmed as the landscape bar does (Apps, Settings and Keyboard behave as
  there); the strip hides while either is open, and while the drawer is,
  VoiceOver skips what it dims. A held thumbnail's lights open below the
  strip. The viewport sends the 16:10 pane, so Aa and the virtual display
  shape Mac windows to 16:10. `TrackpadSurface.verticalSpan`: the phone's pad
  measures pointer motion, two-finger scrolling and its coast against its width
  ÷ 1.6, so the extra height is room, not a slower pointer (today's arithmetic
  would be about 40 % slower vertically on the Pros). `KeyRow` has two sets,
  `.full` (the halves' twelve) and `.phone` (six); each cap's action is
  `tap(key)`.
- DEBUG (ContentView's contract): the harness draws a fake screen larger than
  the simulator scaled down, laid out at its own size (the Duo's and the iPad's
  sizes on iPhone simulators); `-SillKeyboard 1` raises the keyboard for real
  in a live session; `-SillKeyboardToggle <s>[,<s>…]` toggles it as the
  Keyboard button does; `-SillDrawer`, `-SillSettings` and `-SillScaleOpen`
  open theirs 1.5 s into a live session; `viewport: 386×241 pt, scale off,
  60 fps` on the console; `-SillInputTest 1` (loopback only) runs the key
  row's and the trackpad's own code once; `-SillIdiom pad` draws an iPad
  window's arrangement on an iPhone simulator.
- Verified at the first build (2026-09-27, 01:05–02:15, d44c132, on private
  simulators of the iPhone 18 Pro Max, 18 Pro and 17e, deleted after; `simctl
  io screenshot` only): the check (141 cases, 24 of 24 mutants) and
  `Tests/checks/run-all.sh`, all 16; iOS Debug and Release for the simulator
  and Debug for a generic device, only the known `StreamClient` capture
  warning; 52 harness photos of the other layouts pixel for pixel the base
  build's but for what the base shows against itself; the phone layout at
  every phone's stream screen in eight states, measured against the rule; the
  normal app on each phone against a stand-in Mac: the viewport, the keyboard
  from row 1 up and down (its top at 636, 573 and 543 pt: 320 and 301 pt tall,
  no suggestions bar, which the check's table uses), the drawer, the panel,
  the ruler, AX-XL, `-SillInputTest`; a 16:10 picture filling the pane and a
  16:9 one with bars of 13.2, 11.9 and 11.3 pt above and below, everything
  under the picture the same for both. Not run then: `SillHost --synthetic`,
  which no-device.sh blocked from 01:00 to 02:48 (Noah's iPad mini streaming).
- Review fixes (2026-09-27, after d44c132; the plan's "Review fixes"): row 1
  back in the mockup's band (it sat 6 pt high and everything under it 12, the
  trackpads 401 and 343); the labels on one line; the ruler's value inside the
  ruler (also in the compact halves' 50 pt window bar); the drawer and the
  panel across row 1 (at 380 and 360 pt they left cut slivers beside them) with
  the strip hidden under them; VoiceOver skipping what the drawer dims; the
  lights below the strip on every phone (over row 1 on the SE and at 500×710
  before); the Duo's keyboard in the table; the Large Content Viewer; an iPad
  window narrower than 600 pt back on the compact halves (the approval was for
  iPhones). Verified (04:40–05:10, the same simulators, one at a time, deleted
  after): the check 149 cases and 28 of 28 mutants; 81 harness photos of every
  other layout, the iPad's narrow windows included (`-SillIdiom pad`), against
  the base: 56 identical at once, the compact halves' ruler value changed as
  intended, the rest the held thumbnail's wiggle and Δ1–2 anti-aliasing that
  retakes reproduce; 60 harness photos of the phone layout at seven sizes
  measured against the rule (rows within a pixel at 3x, label tops within
  2 px, the panels' edges on row 1's, the ruler's value 2.3 pt inside, the
  lights below the strip); the normal app against `SillHost --synthetic` behind
  a relay that drops input, no-device.sh passing before, during and after, each
  host under 55 s: on the Pro Max the viewport 424×265, Apps at 359–409 pt and
  the trackpad 412×389, the keyboard's top 95 pt under row 3, the panels, the
  ruler, a 16:9 picture's 13.3 pt bars with row 1, the keys and the pad pixel
  for pixel the same as at 16:10, with the keyboard up and at AX-XL,
  `-SillInputTest` (every event dropped at the relay); on the 18 Pro 386×241,
  374×331 and 56 pt; on the 17e 374×233, 362×324 and 49 pt; S3's text sizes.
  Merged with main at 676b362 (PR #29, the disk image; merge e73f231): only
  ci.yml's mutants matrix and CLAUDE.md conflicted. After it
  `Tests/checks/run-all.sh`, all 17; `swift build -c release` (only the
  CaptureProbe warning); iOS Debug and Release for the simulator and Debug for
  a generic device, from clean (only the `StreamClient` capture warning).
- For the other branches (`pointer-visibility`, `first-run-walkthrough` and
  `trackpad-gestures` have merged this since, PRs #31, #35 and #38):
  `pointer-visibility` changes the picture pane's
  `InputOverlay` and the `Trackpad`'s closures once (both arrangements share
  them now) and keeps both edits to `TrackpadSurface.moveCursor` (its
  `setOwnPointer`, this branch's `ySpan` on the `cursor.y` line);
  `DuoLayout.isPortrait` stays right. `first-run-walkthrough`: on phones
  upright `windows` lights Apps (row 1) and the strip (row 2), `bar` lights
  Aa, Keyboard and Desktop as in landscape, `keyboard` is row 1's button, and
  `keys` the six caps (its "keyboard key" row belongs to the halves only); its
  500×710 row takes `PhonePortraitLayout`'s rects on an iPhone and the compact
  halves on an iPad (`DuoLayout.phoneArrangement`, as `StreamScreen` asks),
  and its card placement in portrait the phone's rects (the picture 224–302 pt
  tall at the top, the drawer and the panel across row 1). `trackpad-gestures`:
  the arrows are gone from phones (⌃ with the key row's ↑ is the halves'
  only); its two-finger deltas follow the span. `home-pairing`: textual merges
  in `StreamScreen.swift` and the harness.
- **Untested, for Noah (the plan's P1–P8, on the iPhone 15 Pro and the iPad
  mini):** a 16:10 and a 16:9 window upright (bars above and below, nothing
  below the picture moves when switching); the keyboard from row 1 (up with
  esc to shift in view on the 15 Pro, typing, down again), cmd-latch then C,
  cmd then space for Spotlight with the Desktop streaming, a hardware
  keyboard's arrows; the trackpad (a diagonal at the finger's angle, one
  stroke down crossing the picture, two-finger scrolling at about today's
  speed, tap, two-finger tap, hold and drag); Aa (the ruler over row 1; on
  release the Mac window resizes to 16:10, Sill.log's "Resized … for a 377×235
  panel"); the drawer and Settings under a live row 1, as wide as it (Apps
  again closes, a tap on the picture closes and clicks nothing); a held
  thumbnail's lights below the strip; rotation both ways with the drawer, the
  panel, the keyboard and a latch; VoiceOver's order (Apps, Text size,
  Keyboard, Desktop, Settings, the thumbnails, Escape to Shift, the trackpad's
  hint; with the drawer open, row 1 then the drawer); a long press on a button
  or cap at an accessibility text size; the iPad mini upright and sideways as
  before, and in a window narrower than 600 pt upright, the compact halves as
  before.
