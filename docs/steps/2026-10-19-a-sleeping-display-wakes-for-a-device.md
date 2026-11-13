**A sleeping display wakes for a device (2026-10-19, PR #151 from acalatrava's
`fix/keep-display-awake`, reworked on top of its 2b8be47; issue #134).** Noah: "Modify the black
windows pull request to implement it properly (user activity when a device connects as you said)."
Host only: no wire change, nothing on the device, no setting. Towards #134, not Fixes: the device
test is Noah's.
- The rule (`DisplayWake`, pure, with StreamMessage.swift and Input.swift; `Tests/checks/display-wake`,
  190 checks and 60 of 60 mutants, in CI's matrix): user activity is declared on the Mac as a key
  press would declare it (`IOPMAssertionDeclareUserActivity`, `kIOPMUserActiveLocal`:
  `DisplayActivity`, on a queue of its own) for a person at a device: its session connecting (every
  connection), and an app opened (kind 7), input (8), a window's button (15), a menu item (25) or a
  gesture (28), each only 5 s or more after the last declaration. Never what the device sends by
  itself: a pick (kind 6: its own Desktop requests at a connection's start, after a capture stop and
  once a watched window closed, and its re-pick after a move), the viewport (9), settings (17), "show
  your pairing code" (21), a menu fetch (27), the clipboard (32), any other kind, input that does not
  decode, nor a bare pointer move within 2 s after the host's own stream restart or new frame size
  (`streamChanged`: a stream's first parameter sets and any that differ, the coordinator's
  `parameterSetsSent`; the device's `pointerFrameChanged` re-centre). `handle` forwards every message
  to the rule once (`deviceActive`), the connect from the client-connected path. Nothing is held: the
  display sleeps again by the Mac's own setting, counted from the last declaration.
- The lines (`DisplayWake.Report`, on DisplayActivity's queue): the main display read just before a
  declaration and again 0.5 s later on the same queue (`secondLook`); "Woke the display for iPad
  (iPad14,1), which connected." only when it read asleep then on, once for one wake (two connects in
  a second share it); else "Declared activity for …, which sent input." (", but the display read
  asleep 0.5 s later." when it did) at most once a minute, a woke line counting as that minute's;
  `disp.wake` in the stats line. A test host (`--synthetic`, as `injector.dryRun`) declares nothing and
  counts `disp.wakeDry`. TEST ONLY `SILL_TEST_USER_ACTIVE=remote` (every real host, Sill.app included,
  with a "TEST:" line) declares `kIOPMUserActiveRemote` instead. docs/DEVELOPMENT.md, "A sleeping
  display"; site/support.html, "The picture is black" (its Sill paragraph inside `<!-- Display wake`
  markers, cut by docs/release-checklist.md part 1 §3's perl line for a republish before the release).
- Changed from the PR as opened: its PreventUserIdleDisplaySleep assertion, held for every session
  (the panel lit all session long, against #133's privacy mode, and at home the Mac kept from idle
  sleep), and its single `kIOPMUserActiveRemote` declaration at the first device are gone; nothing
  runs on test hosts; no NSLog. Its device change (the idle timer off while the stream screen shows)
  is dropped: one window's stream screen leaving put auto-lock back while another window's session
  went on, a window closed mid-session may never run its onDisappear, and a device kept lit beside a
  Mac whose display now sleeps by itself shows black; it is its own decision, for its own PR.
- The verifier's findings (2026-10-20), fixed: the support page's line; DEVELOPMENT.md's claims (counted
  from the last declaration, the CLI's plain door, a pointer move or modifier key rather than a tap);
  the device's own Desktop requests and re-centre no longer wake the display; which kinds count moved
  from the coordinator's switch into the rule, checked; the woke line only once the display reads on,
  never twice for one wake; the Untested list below.
- Verified (2026-10-20, merged with main at 9a8e30c): `swift build -c release`, no new warning (the
  real call never ran here); the check and its 60 mutants; `run-all.sh`, all 46; a loopback synthetic
  host on the software encoder with two stand-in devices (a scratch client that, as
  `pointerFrameChanged` does, moves its own pointer to the middle as a restarted stream's parameter
  sets arrive; the software encoder's test pattern never changes size, so a restart stood in for a
  new size): `disp.wakeDry` at both connects (1.3 s apart), a tap, a move 8 s after a restart and a
  gesture; none for the Desktop asked for by itself (twice, each restarting the stream), the
  stand-in's own move as the restarted stream's parameter sets arrived (6 s after the last
  declaration), the other device's tap 1.3 s after the first's, a key 2 s after a move, or a pick of
  nothing; no `disp.wake`, no line, `pmset -g assertions` nothing of the host's; Sill.app's previews
  (140 files) identical to main's, rendered from one path. Again on the tree merged with main at
  4d990e9 (#110, #87, #88; only lists conflicted, kept whole): `swift build -c release`, no warning;
  the check (190); its mutants re-run until a pause stopped them, 54 of 60 caught and none missed (the
  rule, its check and the two wire files are byte for byte those of the 60 of 60 run); `run-all.sh`,
  all 47; the previews (140) identical; loopback runs with two stand-in devices and with two
  `sillclient.py` devices: `disp.wakeDry` at both connects, a tap, a person's move 3.3 s after a
  restart, a gesture and ⌘ alone; none for a second device's tap 2 s after the first, a pick of
  nothing, the Desktop picked again, the device's own re-centres (5.8 to 8.2 s after the last
  declaration), the viewport, a settings change, the clipboard, a menu fetch or input that does not
  decode.
- Known: a connection the device opens by itself counts as a connect (its reconnect after a dropped
  connection, a move to the cable, to Wi-Fi or home), and so does its re-centre when it reaches the Mac
  more than 2 s after the new stream's first parameter sets left (a slow remote link): either can wake
  a sleeping display once with nobody at the device (docs/DEVELOPMENT.md, A sleeping display). Telling
  them apart would need the device to say so, a wire change.
- The waking click (2026-10-29, PR #228 from addhumal's `swallow-wake-click`, finished with maintainer
  edits): a left or right press whose spot is on a display that reads asleep is held back
  (`DisplayWake.pass`; the coordinator's `pressLandsAsleep`: `CGDisplayIsAsleep` of the display under
  the press in the source, the virtual display for a window staged there, the main display when
  nothing streams): the pointer moves there instead, the press declares at once whatever the 5 s
  (`Event.wakingPress`; "Woke the display for iPad (iPad14,1), which clicked while the display was
  asleep; the click was held back."), and its release is held back too, whenever it comes; each
  device's and each button's own; a display that keeps reading asleep has its presses held back for
  5 s from the first (`wakeGrace`), then they go on (a display a press does not wake, or one whose
  picture is live while macOS reads it asleep), and a gap of 5 s or a clock set back starts afresh; a
  device that leaves is forgotten; `disp.heldPress` in the stats line; TEST ONLY
  `SILL_TEST_DISPLAY_ASLEEP=<file>` (a --synthetic host's display reads asleep while the file
  exists). Keys, text and scrolls go on as before. `Tests/checks/display-wake`: 265 checks (P1–P6 for
  the click, I7 for its declaration) and 80 of 80 mutants. Changed from the PR as opened: it kept one
  flag for every device, so another device's release could be held back for this one's press and its
  button stay down on the Mac (every later move a drag); it read the main display on the main actor
  for every input event; it never held back a press on a window staged on the virtual display, on by
  default since #236, where it now judges that display; a press within 5 s of the last declaration
  was held back and woke nothing; a display that kept reading asleep lost every click for good; a
  test host could not show it. Verified: `swift build -c release`, only the CaptureProbe warning;
  `run-all.sh`, all 55; H2 against main at 6c5b5d24 (idle and with a test client, masked and sorted:
  identical); live on a loopback synthetic host with the dry run's input log and a scripted pointer:
  under the TEST ONLY file a press became "pointer move" with `disp.heldPress 1` and `disp.wakeDry 1`
  2 s after the connect's, its release 3 s later (the file gone at 4.5 s) printed nothing, and a tap
  after posted "left mouse down/up"; main's host and this one without the file posted the press and
  its release. **Untested, for Noah:** a Calculator window streaming, `pmset displaysleepnow` on the
  Mac, then a tap on the black picture where its 7 is: the picture comes back and the display reads 0
  (main's build types 7), Sill.log's "Woke the display for …, which clicked while the display was
  asleep; the click was held back."; the same with Virtual Display on (whether a staged window's
  picture is black while the panel sleeps, and whether that tap was held back: `disp.heldPress` in
  the log's `[1s]` lines); a long press (right click) and the trackpad's tap the same.
- **Untested, for Noah,** with Sill.app from this branch (release-signed with the embedded profile):
  `pmset displaysleepnow`, then connect the iPad at home and through Tailscale: the picture, not black
  windows, and Sill.log's "Woke the display for …, which connected."; `pmset -g assertions` lists
  `UserIsActive named: "Sill: a device is using this Mac"`, its timeout the display-sleep setting; with
  the iPad left connected and untouched the display sleeps by its own setting and stays asleep (no
  "Woke" line without a touch, also after "Capture stopped: …"), and a pointer move on the trackpad or
  ⌘ alone on the Magic Keyboard wakes it (Shift alone goes to the device's text system and the key
  row's modifiers only latch, so neither sends anything); a locked Mac (⌃⌘Q, the display asleep): its
  lock screen on the iPad. Then:
  whether `kIOPMUserActiveRemote` also wakes the panel, or keeps the picture live with the panel dark
  (#133): quit Sill, `open --env SILL_TEST_USER_ACTIVE=remote /Applications/Sill.app` (Sill.log's
  "TEST: user activity is declared as remote …"), `pmset displaysleepnow`, connect; Virtual Display
  on, a window streaming from Sill's own CGVirtualDisplay with the panel asleep: whether its picture
  needs the panel woken at all (if not, those sessions light the panel needlessly); and a laptop with
  its lid closed on power (Sill.log's "…, but the display read asleep 0.5 s later." and no "Woke"
  line; with an external display, that display).
