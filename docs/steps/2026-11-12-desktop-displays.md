**The Desktop button steps through the Mac's screens, the main one first (2026-11-12, branch `desktop-displays` from
main at dd6ea6a, main at 936d627, 57a6d86 and a4bad80 merged in since; draft PR #355; phase 1 of
`docs/virtual-desktop-plan.md` (draft PR #352), built on addhumal's #173, whose head 3925bac is merged in as it is so
#173 shows as merged when this lands; towards #91, for #345).** Noah's words: "For users with multiple monitors, the
desktop button will toggle which desktop is being shown … it will default to my default monitor, then toggle through
each monitor, then the virtual desktop", and for #91 (2026-10-19) the tapping method, the button showing which desktop
is up and that a tap moves to the next. No setting; nothing of the Virtual Desktop itself (phase 2), #200, #312, #156 or
#225.
- The stops (`DesktopDisplays`, StreamProtocol, pure; `Tests/checks/desktop-displays`): every display ScreenCaptureKit
  lists but Sill's own (vendor 0x5111) and macOS's 1x stand-in ('unkn'/'virt', `StreamCoordinator.isStandInDisplay`),
  one per mirror set (CGDisplayMirrorsDisplay; two that say they mirror each other both kept), in the arrangement's
  order (left to right, then top to bottom, ties by ID) turned so the main display (CGMainDisplayID) is Desktop 1; a tap
  moves one display to the right, wrapping to the leftmost and back to the main display. #173 numbered from the
  leftmost.
- The stop shown (`resolve`, WindowCatalog): the main display while locked or off console, the off-console view included
  (`mainOnly`, set from the lock's reading as `select` starts, in `desktopCapture` and in `lockChanged`; `enforceLock`
  and `followDesktopStop` move a Desktop on another display), the choice by UUID otherwise, else the main display,
  Virtual Display on or off (#345; `preferMainDisplay` gone). The choice is the Mac's for the session: kept while a
  device is connected and `choiceGrace` (30 s) after the last one left, forgotten at the next connect after that
  (`WindowCatalog.devicesArrived`: nothing runs while idle). A step that does not stream goes back to the choice before
  it.
- The rate (`DesktopDisplays.rate`, the coordinator's `streamRate`): the devices' held to the shown stop's refresh rate
  when it reports one (CGDisplayModeGetRefreshRate above 0), rounded, never under 24; wherever the running rate is
  compared (a viewport, a device leaving, `restartNeeded`) and once more after the Desktop's capture is built. The
  sound's filter on the main display (`WindowCatalog.mainDisplay`); DisplayActivity's woke line reads the shown stop;
  kind 47 a person's request (DisplayWake `.nextDisplay`, "stepped the Desktop to the next display"). The pointer to the
  new stop's centre as #173, never on a test host or locked. A locked kind 47 is still refused and counted as a window
  pick, as #173 has it.
- Wire (additive): #173's kind 47 and `WindowList.desktopDisplays`/`desktopDisplay` (1 now the main display), and
  `desktopDisplayNames` (#296's name; NSScreen's, cleaned), all three only with two stops or more, never locked or off
  console (`LockPolicy.list`), never from a synthetic host without its hook. `{"number": n}` stays #296's. Not yet in
  the Compatibility floor (no public build carries it).
- Device: `DesktopDisplays.button` → `StreamClient.desktopButton`; TopBar, PortraitStreamScreen's `desktopButton` and
  the phone's row 1: today's button with one stop or an older Mac; "Desktop 2" and `DesktopStopDots` (a dot per stop,
  the shown one filled, "3/7" from seven) in the button's bottom margin while the Desktop streams; VoiceOver "Desktop",
  "Display 2 of 3, DELL U2723QE", "Shows the next display." / "Shows the Mac’s desktop."; after its own step the device
  announces where it landed (`desktopStopsChanged`). Harness: `-SillDesktopDisplays 3,2` (`-SillActive desktop` for the
  dots), `-SillDesktopDisplayNames 'A|B|C'`.
- Words: docs/DEVELOPMENT.md (trying it without monitors); support.html's "More than one screen on your Mac" between
  `Desktop displays` markers (the cut gives main's page byte for byte) and README's line inside an HTML comment, both
  for the release (docs/release-checklist.md's Open line).
- TEST ONLY: `SILL_TEST_DISPLAYS='NAME:WxH@SCALE:HZ:X,Y;…'` (DesktopDisplaysHook, a synthetic host only): stops in place
  of this Mac's, the test pattern at the shown stop's size with its number and name drawn on it; nothing read, posted or
  warped. `sillclient.py --next-display@T` (only to a `--synthetic` host on this Mac) and `--expect=desktopDisplay=N`;
  `Scripts/desktop-check/live.py OUT`, the live gate.
- Verified: `Tests/checks/desktop-displays` 115 checks (every arrangement of one to six displays in a row and a grid
  with the main one anywhere, mirror sets, the stand-in, the span, the lock, the rate, the button; 5,000 random
  arrangements, 5,000 random sessions against an independent model, 20,000 random buttons and rates) and 60 of 60
  mutants in one run (CI's matrix); display-wake 272 (3 new mutants of 3), lock-policy 1,411 (4 of 4), compatibility 165
  (2 of 2) (the new mutants alone: each check's whole list, 83, 188 and 38, still applies); `run-all.sh` all 67 before
  main's #351 came in, and in CI all 68 on 755955d and all 69 on 4a0e868 (after #353); `swift build -c release`, only
  the CaptureProbe warning (the merge of 57a6d86 changed no host source); the iOS app Debug and Release for the
  simulator and Debug for a device, only the known `StreamClient` capture warning, Release without the harness, again
  after 57a6d86 came in, and after a4bad80 (#353, Picture in Picture: the coordinator's merge 4a0e868, which left the
  Desktop button's code as it was) Debug for the simulator; dd6ea6a's StreamProtocol (v0.6.1's, byte for byte) decodes
  the list with the three fields and reads kind 47 as unknown; `Scripts/desktop-check/live.py` 24 of 24 on loopback (the
  steps 1→2→3→1→2 with each stop's size and rate, 60 and 30 fps to a 120 fps client, taps landing in each stop's own
  space, the main display while locked and kind 47 refused, the chosen stop after the unlock, the span at 4 s and 33 s,
  a host without the stops unchanged); H2 against dd6ea6a's CLI, idle and with a client: identical masked and sorted but
  for the `[1s]` lines' counters and the heartbeats, which vary run to run (the same stats keys), and one cursor-shape
  message more in main's run (this Mac's own cursor changed during it); harness photos of 4a0e868 against main's
  a4bad80, pixel by pixel, through the agents' shared tool (wt-tooling's `Scripts/harness-photos.sh`): on "Sill agents
  Duo" (iOS 27.1) at 951×669 (flat and the book pose), 669×951 (the laptop pose), 466×678 and 678×466 (the cover), 18
  cases, and on "Sill agents iPad" (iOS 27.0) at 1000×710, 710×1000, 710×500, 500×710 and an iPhone's 402×874, 874×402
  and 320×568, 21 cases: every one-stop case main's (9 of 10 identical, the tenth differing by 2 levels in the mock's
  thumbnail, which the same layout with three stops did not), every other case differing only at the Desktop button
  ("Desktop 2" with three dots, "Desktop 3" with "3/7", "Desktop 2" alone while a window streams); every bar's labels
  are a fixed 11 pt, which a larger text size leaves alone (photos asking for accessibility-extra-large are the
  default's byte for byte); VoiceOver's dumps (a private Duo simulator before the restart, 951×669 and 466×678: the top
  bar and the phone's row). Found and fixed: an 8 pt "3/7" overlapped "Desktop 3" in the 58 pt window bar; sillclient.py
  refused `--next-display@T`.
- Not verified: anything on real displays (the order on a real desk, mirroring, Sidecar, the stand-in, a monitor
  unplugged, a real lock screen's password field, CGDisplayModeGetRefreshRate's answers, the pointer's warp, the sound
  across steps, the woke line on a stop), a device, VoiceOver itself, two devices, mixed builds on devices; the iOS
  app's Release and device builds after #353 came in (built before it); VoiceOver's dumps at the iPad's and iPhone's
  sizes (the Duo's at 951×669 and 466×678 take both code paths).
- **Untested, for Noah (the pull request's 1–14, the MacBook Pro with one or two monitors, the iPad and iPhone):** the
  order and wrap from the main screen (Sill.log "Desktop: display 2 of 3 (…), asked by …"); a window then the Desktop;
  #345 (Virtual Display off, a screen left of the main one or Sidecar: Desktop 1 the main screen); the lid closed; a
  monitor unplugged and back; ⌃⌘Q on Desktop 2 (the main screen's lock screen, is the password field there, back on
  Desktop 2 after the unlock); a 120 Hz device on a 60 Hz monitor ("… 60 fps"); the span (30 s); the sound across steps;
  mirroring and Sidecar; VoiceOver; two devices; mixed builds; Spaces on another monitor.
