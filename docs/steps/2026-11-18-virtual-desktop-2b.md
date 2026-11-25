**The Virtual Desktop, phase 2b's first part: the modes probe and one manager for every display Sill makes (2026-11-18,
branch `virtual-desktop-2b` from `virtual-desktop-2a` at 84d60f3, draft PR #395, which merged main at eb48ac9; phase 2b
of `docs/virtual-desktop-plan.md` as revised 2026-11-18, the revision in
`~/Downloads/sill-handoff/next/virtual-desktop/plan.md`; draft PR #408).** Noah's words, 2026-11-18: "Work on #200, the
option to give Sill its own virtual display (for headless macs or for adding an additional screen, if so allow the user
to select resolution, should default to resolution and refresh of client device, not what we originally proposed)".
Phase 2b is the Virtual Desktop itself: its switch at both ends, its stop after the Mac's screens, its size by default
the device's room and rate, its lifetime, its windows, following the device's turn. This first part is the plan's
commits 1 to 3 of twelve; nothing a person sees changes, and nothing changes on the wire.
- The modes probe, P2 (commit 1, TEST ONLY): can Sill's Desktop display take a device's turn without being removed and
  made again (plan §5)? `VirtualDisplay` is made with more than one mode when asked (`otherModes`: the asked mode first,
  then the others, each once, `modeList`; the descriptor's maximum sized for the largest, `maxPixels`; none by default,
  so every display Sill makes is made as before), moves the live display to another listed mode with public
  CoreGraphics (`switchMode`: `selectRequestedMode`, CGConfigureDisplayWithDisplayMode, as `waitUntilOnline` already
  selects the mode asked at creation), and takes a new list on the live display (`applyModes`: `applySettings:` sent
  again). Nothing in Sill calls the last two. `Scripts/display-modes-probe/run.sh` builds `probe.swift` with
  VirtualDisplay.swift alone: its dry run, the default, looks up the private API (no display) and prints the modes, their
  backing and the steps; `--make` is Noah's (below).
- `SillDisplays` (commit 2): every display Sill makes, in one place (plan §9). For each role (`SillDisplayRole`, pure:
  the stage's "Sill" 0x5111/0x0001/1 since milestone 3, the Desktop's "Sill Desktop" 0x5111/0x0002/2 since #200; macOS
  remembers a display by them and DesktopDisplays.role tells them apart by them, so they never change; the raw value is
  the guard's marker word) it makes the display with the role's identity, writes the guard for #380's marker (`willMake`)
  and takes it back when a make throws and once the wait ends, waits until the display is online and until
  ScreenCaptureKit lists it, hears it lost (the role's newest display alone, hopped to the main actor, handed to the
  role's `onLost`), removes it at once (`destroy`), and gives the stage's IDs to the catalog. The stage (VirtualStage)
  asks it for its display, in the order it always made it: the marker before its old display goes (#380's stops came
  right after "Removed virtual display N"), the make, the wait, the menu bar's measure and remake, the listing; with the
  same lines and failures. It keeps its window, its sizes and its menu-bar remake; `VirtualStage.vendorID` and the rest
  read the stage role's identity.
- The Desktop's display under it (commit 3): the display a Mac with no working screen gets (PR #200, phase 2a) is made,
  waited for and removed through it; the coordinator keeps no display of its own (`headlessDisplay` reads the `.desktop`
  role's). A test host's display that is only said to be made (SILL_TEST_HEADLESS) is `SillDisplays.say`, the seam the
  Virtual Desktop's dry run will go through; it counts as up for a test host's guard, as before. macOS's reconfiguration
  callback (#200's) is `watchReconfiguration`: one for the process, registered once, never removed, a change's
  beginning left out; the coordinator hears each change through it as before. Quit and the signals: the stage's window
  home and its display gone (`stage.release()`), then `removeAll`.
- One difference, in a race only (commit 3): a Desktop display removed while its make still waited for it to come up
  (at most 3 s, beside a removal that had waited 5 s for the switch to end) is destroyed at once and prints no "created"
  line; before, the wait's own reference kept it up until the wait ended, and its line and Settings' row then named a
  display already let go.
- Checks: `virtual-display-api` gains the modes (ModeSize.turned, modeList, maxPixels) and `init`'s and `switchMode`'s
  wiring read as text in the VirtualDisplay.swift it compiled (its build.sh now keeps that file beside the binary, a
  mutant's too); `sill-displays` (new) holds the roles' identities against DesktopDisplays.role and the guard's marker,
  and the wiring read as text (no display made anywhere but `SillDisplays.make` and the self test; each role's display
  made, waited for, listed, lost and removed there; the stage's marker before its old display goes; the said display;
  Quit; the one callback). `stage-release` is unchanged and passes as before.
- Wire: nothing. No kind, field or flag; the iPhone and iPad app is untouched.
- Docs: docs/LAYOUT.md (VirtualDisplay's modes, SillDisplays and SillDisplayRole, the probe), docs/BUILD-AND-RUN.md
  (the probe's command).

**Defaults taken for Noah to confirm:**
1. This part is the plan's commits 1 to 3 (the probe and the manager); 4 to 12 follow on this branch, each group pushed
   as it is done (the plan's order: VirtualDesktopLife, DesktopWindowLedger and `follow`; the wire's fields; the
   setting's places; the stop; the coordinator; the device; Sill.app; the CLI and gates; the words).
2. The probe's display is "Sill Probe" with the Desktop's vendor and product and serial 0xF00D, so macOS remembers
   nothing for Sill's own display; the room 1376 × 1032 (an iPad Pro 13-inch sideways) and its turn by default, at 60 Hz;
   refused while a Sill runs.
3. The Desktop's display gets no lost callback yet: as in #200 and #395, macOS removing it by itself is found at the next
   Desktop (offline) and it is made again. The plan's §6 ("when macOS removes it (its termination handler)") comes with
   the Virtual Desktop's lifetime, commit 8.
4. The race above: removed during its make's wait, destroyed at once, no "created" line.
5. A check of its own, `sill-displays`, for the identities and the wiring, rather than growing `stage-release`.
6. No switch in this part. The Virtual Desktop's switch (commits 6, 9, 10) goes where Settings is on this base (Sill
   for Mac's Virtual Display tab, the device's Settings panel) and moves into #393's whole-screen pane, its Mac part,
   once that lands.
7. The plan's open decisions that phase 2b builds (5 following the device, 11 changing it from away, 12 switched on from
   a device shows it at once, 13 Aa dimmed on it, 14 its lifetime, 15 the name) are taken as the plan recommends, each
   listed here again by the commit that builds it; none is built in this part.

**Verified** (on this Mac; nothing made a display, posted input, locked, slept or switched anything):
- The probe's dry run (`Scripts/display-modes-probe/run.sh`, and with `1133x744 120`): built (VirtualDisplay.swift and
  probe.swift alone, no VideoToolbox), the private API's 17 selectors present by lookup, the modes, their backing (the
  room both ways: 2752 × 2752 px) and the steps printed, nothing made; a bad argument and a room under 320 points exit 2.
- SillHostCore typechecks clean after each commit (`swiftc -typecheck` against the StreamProtocol module built from this
  tree). `virtual-display-api` 302 checks, `sill-displays` 45, `stage-release` 847, each passing; every mutant's pattern
  found once (92, 33 and 25) before the mutants ran.
- GitHub's CI on de243b10 (run 44399067304): every step of Build and check passed: the release build, every pure check
  (`Tests/checks/run-all.sh`, `sill-displays` among them), the iOS app, the CLI's two paths. Its mutant jobs are skipped
  on pull requests, as on #395, so the mutants ran here.
- One turn of the heavy lock (2026-11-18 23:27–23:40, slot B; queued at 15:39): `swift build -c release` in 65 s with no
  warning but CaptureProbe's known one; `SillHost --internet` exits 2 with "--internet needs --remote."; the mutants:
  `virtual-display-api` 302 checks and 92 of 92 mutants caught, `sill-displays` 45 checks and 33 of 33, `stage-release`
  847 checks and 25 of 25; the working tree clean after (two of the three patch sources in place and put them back).
  run-all was not run again there: CI had run it on the same head.
- The live gates on this branch's CLI, synthetic test hosts on 127.0.0.1 (the software encoder, no router, no screen),
  outside the lock: `Scripts/headless-check/live.py OUT all` 66 of 66 verdicts (19 scenarios, as on #395: the said
  display now SillDisplays' `say`); `Scripts/desktop-check/live.py` 24 of 24; `Scripts/lock-check/live.py` poll 42 of
  42, start 4 of 4, view 26 of 26, and paired 6 of 6 on a second run: its first run, at 23:49 while a simulator booted
  beside it (load average 136), gave 5 of 6, the held key's down posted at 11.3 s, 2.3 s after it was sent and outside
  the gate's window, with the software encoder stalled 3.7 s in the same second ("the encoder was busy, not stuck");
  at 00:05, load 9, the same gate gave 6 of 6, the down at 9.14 s.
- H2, this branch's CLI against #395's (built from 576d86cb's code, #395's head but for docs), each host's stdout masked
  and sorted (`~/Downloads/sill-handoff/next/vd-2b/verify/h2.py`): idle identical (7 distinct lines), with a test client
  identical (14), started locked identical (11), and with `--virtual-display` and a test client identical (17: the
  AppKit loop, so SillDisplays' reconfiguration callback is registered for real; nothing is staged on a synthetic host).

**For Noah** (only he can: each makes a display, or needs Sill.app on his Mac; the same list is in the pull request):
1. P2, the modes probe, on a Mac at rest (Sill quit, nothing streaming, no device connected; it makes "Sill Probe" for
   about ten seconds and a window of its own on it): `cd ~/Downloads/wt-vd-2b && Scripts/display-modes-probe/run.sh
   --make`, then upright at 120 Hz: `Scripts/display-modes-probe/run.sh --make 1032x1376 120`. Its last three lines
   decide plan §5 ("P2 in place by the modes listed at creation: yes|no", "P2 new modes on the live display …: yes|no",
   and what a mode beyond the display's backing did); the output goes into PR #408.
2. P1 (from #395, still open), on the same Mac at rest: `swift build -c release && for a in "60 1218x800" "120
   1376x1032" "120 1496x800" "60 1133x744"; do .build/release/SillHost --virtual-display-selftest $a; done`.
3. The stage as before (its display now goes through SillDisplays): this branch built as a release and installed
   (`SILL_RELEASE_DRY_RUN=1 SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'
   SILL_PROVISION_PROFILE=/Users/noah/Downloads/winstream/Packaging/embedded.provisionprofile Scripts/make-app.sh
   --release --install --open`), Virtual Display on: pick a window from the iPad (`Virtual display … created …`, the
   window on Sill's display); pick another (the first home, the display kept); pick the Desktop (`Removed virtual
   display N (… home after … ms)`); then Quit Sill with a window staged (the window home, no "Sill" left in System
   Settings › Displays).

**Second part (2026-11-19): the plan's commits 4 to 7, the Virtual Desktop's rules, its wire, its switch's places and its
stop.** Still nothing a person sees and nothing any device or Mac sends differently: the coordinator calls none of it
yet (commit 8), and the switch is reported to no device until it does.
- The rules (commit 4, 0239fb8f; pure, `Tests/checks/virtual-desktop`):
  - `VirtualDesktopLife` (plan §6, §10): when it exists. Made only when a device shows its stop (a step onto it, the
    switch turned on from a device, the Desktop coming back to it) with the switch on, a real screen working, unlocked,
    on the console, Sill able to make it and the guard for #380 clear. Kept while shown and 30 s after the look that
    found it no longer shown; kept while locked until the unlock, then 30 s from it; a switch turned off while locked
    waits for the unlock. Removed off console at once; switched off, or at the grace's end, no sooner than 3 s after the
    last change of the Desktop's display and never past ten changes a minute (the newest request wins: the answer is
    each look's); never the main display beside a real screen once one has worked 2 s (Watch's 2 s, read from
    VirtualDisplay.swift by the check), locked or not. One display in two roles: with no real screen it is the headless
    display, made and released by `HeadlessDesktopPolicy.Watch` alone; a real screen back while a device shows it with
    the switch on and macOS left it an extra display, it is the Virtual Desktop again, else Watch's release; a display
    it was not told of is Watch's. Its lines ("Virtual Desktop: no device has shown it for 30 s; moved 3 windows to
    Built-in Retina Display and removed it.", the lock's, the spacing's).
  - `DesktopWindowLedger` (plan §7): the windows on it out to the main display as it goes (out of full screen first,
    at most 2 s, one that will not leave left to macOS; the same share of the visible area's room each way, whole
    points, their size kept; where the app took it read back and kept), and back as it returns (exactly where they
    were on the same area, the same share of a new one; left when moved or resized more than 2 points on the Mac,
    closed, in full screen, or not answering). Over `WindowRestore.Access` plus `leaveFullScreen`. Memory only.
  - `VirtualDesktopSize.Follow` and `followStep` (plan §5): the matched device's room taken after 1 s steady and at
    most every 3 s from the make or the last follow, a room back to the size taken within the wait nothing, the newest
    size winning; how, by probe P2's verdict: `followWay`, one line, `.nextMake` until Noah has run P2.
  - The check: the rules case by case; 5,000 random sessions of the lifetime (a fifth churning as fast as a device can,
    a fifth quiet) with a model of Watch for the headless role, judged by the check's own records against the plan's
    sentences, with floors on how often each rule ran; 2,000 random rooms; the ledger over a stand-in Mac and 2,000
    random windows out and back. About 103,000 checks in 4 s; 90 new mutants, 144 in all.
- The wire (commit 5, 3bf0d9ce), each field optional, nothing sending or reading them yet: `Viewport.room`
  (`ViewportRoom`, the picture's room with Sill's controls hidden, in device points; ViewportBounds refuses a room out
  of 1…16384 points a side and names it, `held` holds a device's to the bounds and sends none with a side that is not a
  positive number); `WindowList.desktopVirtual`; `StreamSettings.virtualDesktop` (required in its initializer, as
  directWireless and sendAudio, so no host forgets it) and `HostSettingsChange.virtualDesktop`; and
  `HostSettingsState.virtualDesktopState` (`VirtualDesktopState`: available, note, shown, size "1218x800@2", hz),
  named so beside the settings' Bool (the overview of 2026-11-18, clash 7). Checks: `compatibility` (each left out when
  nil, round-tripped, nil from an older peer and skipped by 0.6.2's readers; 12 new mutants) and `viewport-bounds` (the
  room case by case and 100,000 random ones; 8 new mutants). COMPATIBILITY.md is unchanged: these join the floor when a
  public build carries them (the overview's rule 8); the words to add then are below.
- The switch's places (commit 6, 9bfe9d15): `HostConfig.virtualDesktop`, off in `standard` and `app`, named in the log
  ("virtual desktop off → on"); `applying` (and so `applyingAway`: one value for the Mac); `DeviceSettings.accepted` takes
  it only from a paired session, home or away, on only where the host can make it now, off always; Sill.app's key
  `virtualDesktop` (registered off, saved like a menu click) and `-SillSetAfter '<s> virtualDesktop=1'`. Until commit 8
  the host reports no switch (kind 16's settings say nil) and the coordinator refuses every "on" as unavailable.
  Check: `away-quality` (10 new mutants; AQ23, AQ-O1 and AQ-H1 follow the lines they mutate).
- The stop (commit 7, d4ed355e and b6ceb227): `DesktopDisplays.candidates(_:main:virtualDesktop:)` puts the Virtual
  Desktop after the screens while its switch is on and Sill can make it (its display while it is on now, else a stop
  with ID 0 that a step onto makes; never the stage's display; with no screen the only stop, so the button is today's);
  its choice is kept by a fixed key (`virtualDesktopChoice`), not a display's UUID; its name "Virtual Desktop";
  `virtualNumber` is the list's `desktopVirtual`; the button on its stop is `rectangle.dashed` over "Virtual", VoiceOver
  "Virtual Desktop, 3 of 3". LockPolicy.list withdraws `desktopVirtual` with the other stop fields. Checks:
  `desktop-displays` (the stop case by case and 2,000 random arrangements; five mutants moved onto the new lines, 16
  new, 88 in all: b6ceb227 added the 16 that d4ed355e's message promised and left out) and `lock-policy` (its locked and
  off-console lists; one new mutant).

**Defaults taken for Noah to confirm** (this part's; the first part's 1 to 7 stand):
8. P2's verdict is not in, so the Virtual Desktop follows the device by its next make (`VirtualDesktopSize.followWay =
   .nextMake`): it is made with one mode, as every display Sill makes, and a turn takes effect the next time it is made
   ("Virtual Desktop: iPad mini turned; the next one is made at 800×1218 pt."). That way rests on nothing P2 has not
   measured. P2's "yes" by the modes listed at creation is the one line `.listedModes` (made with the room both ways, a
   turn switched in place with public CoreGraphics); by new modes on the live display, `.newModes`; phase 3's remake is
   `.remake`. The headless display follows only in place and only unlocked, never removed and made again.
9. The grace's 30 s count from the look that found it no longer shown; while locked it is kept past them until the
   unlock, then 30 s from the unlock, and a switch turned off while locked waits for the unlock too.
10. The spacing counts every change of the Desktop's display, the headless role's too; off console's removal never
    waits (it would join another user's displays); the never-main removal waits for the spacing and applies while
    locked too, as the headless release does (a real screen works then).
11. A real screen back while Sill's display exists and is not the main display: it stays as the Virtual Desktop only if a
    device shows it at that moment with the switch on (the 11-12 plan's §5); otherwise the headless release.
12. Windows out go to the same share of the main display's visible area each way (flush stays flush, the middle the
    middle), their size kept, a window larger than the area at its top-left corner; back, exactly where they were when
    the Virtual Desktop has the same area, else the same share of its new one; a window moved or resized more than 2
    points on the Mac meanwhile, or in full screen, stays.
13. The wire's names: `virtualDesktopState` in kind 16 (the overview's clash 7), its `size` "1218x800@2" (points and
    scale, the form phase 3's size ids take), `StreamSettings.virtualDesktop` required in the initializer.
14. The switch is the Mac's and a paired device's, home or away; an unpaired session never sets it, on or off; an "on"
    is refused while this Mac cannot make it ("virtual desktop (this Mac cannot make it now)"), an "off" always taken.
    No device is told of the switch before the Mac can make the Virtual Desktop (commit 8).
15. The stop's choice is kept by a fixed key, not its display's UUID; the stop is named "Virtual Desktop" among the
    stops' names, so a 0.6.2 device reads "Display 3 of 3, Virtual Desktop".

**Words for COMPATIBILITY.md once a public build carries them** (proposed; not written there): "a viewport's optional
`room` within `ViewportBounds` (each side 1 to 16384 points; a host from 2b refuses any other whole); the window list's
optional `desktopVirtual`, the Virtual Desktop's stop among `desktopDisplays` and sent only with them, never while
locked or off console; kind 16's optional `settings.virtualDesktop` and `virtualDesktopState` (`available` and `shown`
always, `note`, `size` "WxH@S" and `hz` optional), and kind 17's optional `virtualDesktop`, which a device sends only to
a host that reported the switch and a host takes only from a paired session."

**Verified in the second part** (on this Mac; nothing made a display, posted input, locked, slept or switched anything):
- Each check run as written after each commit, and the host's modules typechecked (`swiftc -emit-module`/`-typecheck`
  of StreamProtocol, SillHostCore, SillMenuBar and SillHostCLI against each other): clean, no warning.
- `virtual-desktop`: about 103,000 checks in 4 s, 0 failed, 28 runs in a row (its random sessions and rooms change each
  run); 144 of 144 mutants caught, in the heavy lock on a `git archive` snapshot of 0239fb8f (05:11–05:36, slot A),
  whose files the later commits did not change. Every mutant pattern of every check found exactly once before each
  commit (a text check, no build).
- GitHub's CI on b6ceb227 (run 44505874693): every step of Build and check passed (the release build, every pure check,
  the iOS app, the CLI's two paths); its mutant jobs are skipped on pull requests.
- The heavy lock's second turn (06:30–06:55, slot B, after 61 minutes in a queue of five agents' jobs), on a `git
  archive` snapshot of b6ceb227: `swift build -c release` in the worktree in 58 s with no warning but CaptureProbe's
  known one; `SillHost --internet` exits 2 with "--internet needs --remote.", `--print-reachability` exits 0;
  compatibility 193 checks and 50 of 50 mutants caught; away-quality all passed, 58 of 58; desktop-displays 174 passed,
  88 of 88; lock-policy's one new mutant caught by `module.mutate` alone (its 192 others' patterns found once by the text
  check, as this run's rule for that check allows; their 47 minutes not spent); viewport-bounds 100 checks and 37 of 38:
  R8 did not compile (its closure's type left to infer), fixed in 418cb9b5 and run again in a third turn (below). run-all
  was not run in the lock: CI ran it on b6ceb227.
- The third turn (06:55–06:57, slot B), on a snapshot of 418cb9b5: viewport-bounds 100 checks and 38 of 38 mutants
  caught, R8 among them.
- The live gates on b6ceb227's CLI (built in that turn), test hosts on 127.0.0.1 (the software encoder, no router, no
  screen), outside the lock at load 6: `Scripts/desktop-check/live.py` 24 of 24 (the stops through `candidates`' new
  shape); `Scripts/lock-check/live.py` poll 42 of 42, start 4 of 4, paired 6 of 6, view 26 of 26 (LockPolicy.list's new
  line); `Scripts/headless-check/live.py OUT all` 66 of 66.
- H2 (`~/Downloads/sill-handoff/next/vd-2b/verify/h2.py`, each host's stdout masked and sorted): b6ceb227's CLI against
  61a96d3c's (this branch's previous head, run 1's build kept for it), identical in all four modes (idle 7 distinct
  lines, a test client 14, started locked 11, `--virtual-display` with a test client 17), so commits 4 to 7 add no line
  on these paths; against main's eb48ac9f (`files/run2/SillHost-main-eb48ac9f`), identical idle, with a client and with
  `--virtual-display`, and started locked the one difference #395's review round named: "Displays: N online, N active,
  N asleep, N Sill's, N macOS's stand-in." (11 lines and 10).

**Third part (2026-11-19): the plan's commits 8 to 12, the Virtual Desktop working end to end.** The switch now does
something: a device steps onto the Virtual Desktop's stop (or turns it on) and the Mac makes it; its windows go and come back;
Sill for Mac has its Settings, menu item and card row; the CLI has its flag; the desktop gate has its scenarios.
- The coordinator (commit 8, 6329077e; StreamCoordinator.swift's "The Virtual Desktop"): VirtualDesktopLife is asked at
  every change that bears on it (each switch of source, display change, lock change, device come or gone, settings change,
  and the time it said: one scheduled look). A make happens inside the Desktop's select, so the capture that follows is built
  on it: the matched device's size and rate (the device that stepped onto it or turned it on; `VirtualDesktopSize.device`
  of its room, else its panel; #200's 1920×1080 at 60 with no viewport), made through SillDisplays (`newDisplay = try
  displays.make(.desktop, …)`), waited for online and listed, the catalog looked at again (WindowCatalog keeps Sill's display
  beside the real screens while it is the Virtual Desktop: HeadlessDesktopPolicy.pool's `virtualDesktop`), the windows Sill
  moved off it before back in their places. While the spacing holds a make, the Desktop shows the main display
  (DesktopDisplays.streamed) and the look at the spacing's end makes it. A removal re-asks the rule on a fresh look once a
  switch under way is over (a removal asked by an older look never acts on a newer state): the Desktop off it first, its
  windows to the main display (DesktopWindowLedger.moveAllOut through WindowSizer.DesktopWindows: Accessibility, out of full
  screen first, at most 2 s; none off console), the display, one line. A make that throws or never comes up turns it off for
  the run (VirtualDesktopWords.failed) until its switch is turned off and on. Following: the matched device's viewports feed
  `Follow`; with `followWay` `.nextMake` a turn is a line and the next make's size. One display in two roles: the headless
  release and its switch leave the Virtual Desktop to its own rules; the roles change hands with a line. macOS removing the
  Desktop's display is heard (`onLost[.desktop]`, either role). Quit moves its windows out synchronously, a full-screen one
  left to macOS, before `removeAll`. A device that turns it on is shown it at once. Kind 16: the switch reported by every
  host (`streamSettings`), `virtualDesktopState` per connection (available and the Mac's note, VirtualDesktopWords.note;
  shown; the size and rate it has or would have for that device). HostStatus: `SillDisplay.virtualDesktop` and
  `virtualDesktop` (available, note, shown). TEST ONLY: SILL_TEST_VIRTUAL_DESKTOP=1 with SILL_TEST_DISPLAYS (said, never
  made, one more test stop) and SILL_TEST_VD_GRACE=<s> (VirtualDesktopLife.testHook). Co-authored by dr-apple (#156),
  lepeos (#312) and addhumal (#225), whose device-sized display, kept while an overlay comes and goes, is this default.
  3f377ccd and 19eb210c: the windows' moves take each display's visible area from AppKit only when it is that display's,
  else its bounds (a display NSScreen does not list yet, just made, gave the main display's area: its windows would have
  stayed where they were and been forgotten), and move none while the target is, or overlaps, the Virtual Desktop.
- The device (commit 9, 0d8f4305): the stream screen measures Full Screen's room whether the controls show or not
  (FullScreenPolicy.hiddenRoom) and sends it in every viewport (`Viewport.room`), again when it changes; the Desktop button
  shows the dashed screen over "Virtual" on its stop (`hostDesktopVirtual`), VoiceOver "Virtual Desktop, 3 of 3", also after
  its own step; the Settings panel's switch after Virtual Display's row, its footnotes from VirtualDesktopWords, disabled on
  an unpaired session and where the Mac cannot make it; the ledger's eighth field and rule 11 (only on a session the Mac says
  is paired); mock cases vdesk, vdeskon, vdeskunpaired, vdeskunavailable, `-SillSettingsScroll vdesk`,
  `-SillDesktopDisplays 3,3,v`, noted in ContentView's harness notes (ef52d7e4; 70f04d13 put the sound's bullet back
  together, which ef52d7e4 had split).
- Sill for Mac (commit 10, 767fcad8 and 13ea556c): Settings › Displays (the Virtual Display tab renamed, its raw value kept):
  the Virtual Desktop section ("Add a desktop for your devices", Resolution, Refresh Rate, its status with Try Again for the
  guard, its footnotes); the status menu's "Virtual Desktop" with its subtitle; the card's "Virtual Desktop · 1218×800"; the
  previews. Noah's "allow the user to select resolution", on the Mac in 2b: HostConfig.virtualDesktopSize ("device", "main",
  or a size of `VirtualDesktopSize.offered`) and virtualDesktopHz (0: the device's; 30, 60, 120), saved by Sill.app, taken at
  the next make; only Match the device (the plan's This device) follows a device. Settings › Permissions' Accessibility
  row names the window moves (ef52d7e4).
- The CLI and the gate (commit 11, 77de9514): `SillHost --virtual-desktop[=device|main|WxH@S[:HZ]]`; sillclient.py's
  `--room`, `--room-after`, the switch's `--set` and `--expect` keys, `desktopVirtual=` and `vdesk=…`; desktop-check's two
  more hosts (the stop, a step onto it, its turn, its grace, made again, locked, off console, the span; a paired device's
  switch shown at once, an unpaired one's refused, the switch flipped four times a second against the spacing, off).
  818bbe86: its test pattern at its size in points, as every test stop's (the verdict had wanted Retina pixels);
  b83f5ed8: the CLI's start line names its two choices as Settings › Displays does ("Virtual Desktop on for this run
  (Resolution: Match the device, Refresh Rate: Match the device): …"); e84a1601: a turn back after its follow asks
  nothing, and the unpaired client leaves before the paired one turns the Mac's switch on.
- Docs (commit 12, 92f52478 and this note): docs/DEVELOPMENT.md (how to try it, its lines), docs/locked-mac-plan.md's
  table, docs/LAYOUT.md, docs/BUILD-AND-RUN.md with each commit.

**Defaults taken for Noah to confirm** (this part's; the first two parts' 1 to 15 stand):
16. The Virtual Desktop is made inside the Desktop's select, so the Desktop moves onto it as it comes up; while the spacing
    holds a make (3 s since the last change), the Desktop shows the main display and moves on once it is made, and the
    button reads the main display's number meanwhile.
17. A make that throws or never comes up turns it off for this run (its stop leaves the cycle; Settings and the device say
    "Off for this session: …. Turn it off and on to try again."), as the stage's own failures do.
18. Off console it goes at once and its windows go where macOS puts them (Sill moves no window in a session another user has
    the screen of), so they do not come back.
19. Its windows out: up to 2 s per full-screen window, which holds Sill's main actor that long; at Quit and the signals
    none (a full-screen window is left to macOS).
20. macOS removing the Desktop's display by itself is heard now in both roles (#395's included): forgotten at once, and a
    Desktop on it starts again on what is left (before: found offline at the next Desktop).
21. Every 2b host reports the switch, the CLI without its AppKit loop too (disabled with "Start SillHost with
    --virtual-desktop to use it."); kind 16's size and rate only while the switch is on, a kind 16 per viewport then.
22. The device's room is Full Screen's measured whatever shows (`hiddenRoom`), in every viewport, a new viewport when it
    changes.
23. The device's switch sits after Virtual Display's row, before the closing footer; it moves into #393's pane, its Mac part.
24. The ledger's rule 11: a Virtual Desktop pick goes only on a session the Mac says is paired; a Mac that says nothing gets
    none (every Mac with the switch says).
25. The size and rate are the Mac's choice in 2b (Settings › Displays, the CLI's flag); a device's pickers and their wire
    fields stay phase 3's. A new choice is taken at the next make (P2 not run); only Match the device follows a device.
26. The sizes offered: Match the device (the plan's This device), Same as main display (the 11-12 rule: its mode, its
    pixels held inside 3840 × 2160), then 1440 × 900, 1512 × 982, 1728 × 1117, 1920 × 1080, 1920 × 1200 and 2560 × 1440 at
    Retina, and 1920 × 1080, 2560 × 1440 and 3440 × 1440 at 1x; no 1280 × 720 (under 800 points), 6K or 8K until phase 3's
    self test of each. The rate is its own choice: Match the device (the device's rate, whatever the size), 30, 60 or 120 Hz.
27. Settings' fourth tab is "Displays" (raw value `virtualDisplay` kept, so a saved tab opens it); the menu's item follows
    Virtual Display's.
28. A device that turns it on is shown it at once (open decision 12 (a)): the one stream moves to it for every device, a window
    streaming included.
29. Its test hooks need SILL_TEST_DISPLAYS (the screens) and a test host; a test host's said display is never the main one.

**Verified in the third part** (on this Mac; nothing made a display, posted input, locked, slept or switched anything;
every live run a synthetic test host on 127.0.0.1 with the software encoder, its Virtual Desktop only said to be made):
- The Mac's modules typechecked after each commit with Swift in it (`swiftc` of StreamProtocol, SillHostCore, SillHostCLI
  and SillMenuBar against each other), and the iOS app's sources for the simulator against StreamProtocol after commit 9:
  clean, no warning. CI built the iOS app on every head pushed since.
- Commit 8 live on its CLI (`~/Downloads/sill-handoff/next/vd-2b/run3/probe8.py`, a `--pairing` test host with
  SILL_TEST_VIRTUAL_DESKTOP and a 3 s grace): a paired device's "on" shown to it at once and made (said) at 1218×800 pt
  @2× at 60 Hz for its 1133×744 room, the Desktop on the third stop at 60 fps; an unpaired device's "on" refused ("only a
  paired device"); stepped off, removed 3.0 s later; off.
- The heavy lock's first turn (08:34–09:31, slot A), on 6329077e (commit 8): `swift build -c release` in 53 s with no
  warning but CaptureProbe's known one; `SillHost --internet` exits 2, `--print-reachability` 0; on a `git archive`
  snapshot, sill-displays 53 checks and 43 of 43 mutants caught, virtual-display-api 308 and 97 of 97, virtual-desktop
  103,262 and 166 of 166 (32 minutes), desktop-displays 213 and 92 of 92, away-quality all passed and 59 of 59. No later
  commit changed sill-displays', virtual-display-api's or desktop-displays' checks, nor the lines their mutants change
  (every pattern found exactly once at the head); virtual-desktop and away-quality, which commits 9 to 11 grew, ran again
  in the second turn.
- The heavy lock's second turn (09:31–10:36, slot A, after 23 minutes queued), on b83f5ed8: `swift build -c release`
  in the worktree in 59 s with no warning; `SillHost --internet` exits 2, `--print-reachability` 0,
  `--virtual-desktop=999x999@2` exits 2 naming the sizes it takes. H2 (`run3/h2b.py`: each pair run one right after the
  other there, every line but the statistics masked and sorted, the statistics compared by name): against b6ceb227 (run
  2's head) identical in all four runs (idle 7 distinct lines and 3 statistics, a test client 14 and 11, started locked 11
  and 3, `--virtual-display` with a test client 17 and 11), so the Virtual Desktop off (its default) changes nothing on
  these paths; against main's eb48ac9f identical but the locked run's "Displays: N online, …" line, #395's, as before.
  Sill for Mac's previews from the bare SillMenuBar (its own log file, defaults deleted after): 345 files, the Virtual
  Desktop's looked at (Settings › Displays in eight states, light and dark; the card's row; the menu's item). On a `git
  archive` snapshot: virtual-desktop 191 of 191 mutants caught (39 minutes), away-quality 67 of 67, ledger 24 of 24,
  full-screen 72 of 72; then run-all, all 76 checks passed (virtual-desktop 105,424 checks, full-screen 101,607).
- The live gates on b83f5ed8's CLI (the second turn's build), outside the lock at load 6 to 7: `Scripts/desktop-check/live.py`
  51 of 51 (24 of its stops as before and 27 of the Virtual Desktop's: the stop after the screens, made (said) at the iPad
  mini's 1133×744 room grown to 1218×800 pt @2× at 60 Hz, a turn held 1 s followed by one line, a turn and back within the
  second nothing, removed 3.0 s after it was stepped off, made again, kept while locked past its grace and back after the
  unlock, removed at once off console, the span, never two changes within 3 s; on a `--pairing` host an unpaired device's
  "on" refused, a paired one's shown at once, the switch flipped four times a second making four changes 3 s or more apart,
  off); its first run held 49 of 51, both misses the gate's own expectations (a turn back after its follow asks nothing,
  since the display still has that size; the unpaired client still connected when the paired one turned the Mac's switch
  on), fixed in e84a1601. `Scripts/lock-check/live.py` poll 42 of 42, start 4 of 4, paired 6 of 6, view 26 of 26;
  `Scripts/headless-check/live.py OUT all` 66 of 66.
- The harness's photos (`Scripts/harness-photos.sh`, the agents' Duo on iOS 27.1, the heavy lock's slot A 10:35–10:41) of
  0d8f4305 (commit 9; the app's own code at the head differs from it only in ContentView's comments, and StreamProtocol
  only by Sill for Mac's words), looked at: the Virtual
  Desktop's 25 cases, the Desktop button on its stop (the dashed screen over "Virtual", its third dot lit) on the Duo flat
  both ways and as a laptop, its cover screen both ways, an iPad both ways and in half, phones both ways and the SE, and
  while a window streams (the stop's face, no dots, Aa back); the panel's switch off, on with "Its size: 1218 × 800 at 60
  Hz.", on an unpaired session (disabled, "Only a device paired with Mac mini can change this.") and where the Mac cannot
  make it (disabled, "Needs Screen Recording."), on the Duo, its cover, an iPad and phones. Four unchanged cases (an
  ordinary stop's button on the Duo and a phone; the panel of a Mac without the Virtual Desktop on the Duo, and at its end
  on a phone) identical pixel for pixel to #395's head, 84d60f30.
- GitHub's CI on 92f52478 (run 44540470678), b83f5ed8 (run 44544695482, the head's code) and e84a1601 (run 44548679666):
  every step of Build and check passed each time (the release build, every pure check, the iOS app, the CLI's two paths);
  its mutant jobs are skipped on pull requests.

**For Noah** (all of 2b's, shortest first, as in the pull request; this list takes the first part's place, whose three
are 1, 2 and 12. Each makes a display or needs this branch's Sill.app on your Mac. Watch `grep -E "Virtual
Desktop|Headless|Displays:|Desktop:|Settings from" ~/Library/Logs/Sill/Sill.log | tail -40` meanwhile):
1. P2, the modes probe, on a Mac at rest (Sill quit, nothing streaming, no device connected; it makes "Sill Probe" for
   about ten seconds, with a window of its own on it): `cd ~/Downloads/wt-vd-2b && Scripts/display-modes-probe/run.sh
   --make`, then upright at 120 Hz: `Scripts/display-modes-probe/run.sh --make 1032x1376 120`. Its last three lines decide
   how a turned device is followed (default 8, one line); the output goes into PR #408.
2. P1 (from #395), on the same Mac at rest: `swift build -c release && for a in "60 1218x800" "120 1376x1032" "120
   1496x800" "60 1133x744"; do .build/release/SillHost --virtual-display-selftest $a; done`.
3. Install this branch: Sill.app (`SILL_RELEASE_DRY_RUN=1 SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'
   SILL_PROVISION_PROFILE=/Users/noah/Downloads/winstream/Packaging/embedded.provisionprofile Scripts/make-app.sh
   --release --install --open`), and the iPad mini and the iPhone 15 Pro on a build of it. 4 to 14 use them.
4. Turn it on in Settings › Displays and step past the screens from the iPad: "Virtual Desktop 1218×800 pt @2× at 60 Hz id
   N: made in … ms for iPad mini (its screen).", listed in System Settings › Displays with a menu bar; with Full Screen on it
   fills the iPad; the button's dashed screen over "Virtual".
5. From the iPhone's Settings panel: switch it on (shown at once, about 1496 × 800 at 120 Hz if the encoder holds it:
   Sill.log's "Streaming … fps"), then off (the main display, its windows moved).
6. Quit Sill.app while it shows: its windows on the main display, no "Sill Desktop" left in System Settings › Displays.
7. Settings › Displays' Resolution 1920 × 1080 (Retina) and Refresh Rate 60 Hz, then step onto it again after it went:
   made at that size and rate.
8. Turn the iPad while it shows: "iPad mini turned; the next one is made at 800×1218 pt." (P2 not run); step away 30 s
   and back: made upright.
9. Windows on it: move one there, step away and back within 30 s (it stays), wait 30 s on another stop (it moves to the
   main display: "moved 1 window to …"), step back (it returns: "1 window back in its place").
10. Locked: ⌃⌘Q while it shows (the main display's lock screen), the password, back on it; disconnect, gone 30 s later.
11. From an unpaired session (Require pairing off) the panel's switch is disabled; from away (Tailscale) on and off work.
12. The stage as before (its display now goes through SillDisplays): Virtual Display on, pick a window from the iPad
    (`Virtual display … created …`, the window on Sill's display); pick another (the first home, the display kept); pick
    the Desktop (`Removed virtual display N (… home after … ms)`); then Quit Sill with a window staged (the window home,
    no "Sill" left in System Settings › Displays).
13. Lid closed with both monitors, it showing, then both cables pulled: it stays as the Mac's only display ("no real
    screen works now"); plug one back: it goes or stays as the Virtual Desktop (never the main display).
14. #333's kind of monitor, if one is at hand: whether a step onto it switches the monitor off.

**Words proposed for the site, What's New and the review notes** (not written there; 0.7.0, both apps):
- support.html, "A desktop of its own for your iPhone or iPad": "Turn on Virtual Desktop in Sill's Settings on your iPhone
  or iPad, or in Sill for Mac (Settings › Displays). After your Mac's screens, tap Desktop to step to a desktop that is your
  device's own: its size and its refresh rate. Move windows onto it as onto any screen. It is there only while a device
  shows it; thirty seconds after none does, its windows move to your main screen, and they go back when it returns. With
  Full Screen on, it fills your device's screen exactly. In Sill for Mac you can choose another size or refresh rate."
- privacy.html's Accessibility line gains: "… and to move windows off the Virtual Desktop and back."
- App Store What's New: "Virtual Desktop: turn it on in Settings and tap Desktop to step to a desktop of your own on your
  Mac, the size of this iPhone or iPad. Needs Sill for Mac 0.7."
- The review notes' NEW IN 0.7: "Virtual Desktop (Settings, needs Sill for Mac 0.7): the Mac makes a desktop the size of
  this device after its own screens; the Desktop button steps to it. Nothing leaves the user's own Mac." (under 300 bytes)
- contribute.html's credits: addhumal (#200, #225), dr-apple (#156), lepeos (#312).

**Main brought in, through `virtual-desktop-2a` (2026-11-23: #395's branch with main c33d1057 merged, a297443b and
303112f6; this branch's merge 66e0fe85).** Noah tested and merged #399 (a streamed window follows its native tab
switches, #366), #396 (a staged window's sound built on Sill's display, its bounded retry, #365) and #402 (Lock this Mac
when the last device leaves, #283 and #275) into main; #395 took main in first (its step file has that merge), and this
branch took #395's new head with `git fetch origin virtual-desktop-2a` and `git merge FETCH_HEAD` in a worktree of its
own (`~/Downloads/wt-vd-2b-main`). Eight files conflicted, each settled keeping both sides; nothing under iOSClient or
StreamProtocol differs from this branch's, so the wire and the device are as they were and no photo changed:
- `HostConfig.swift`: the initializer and `standard` take the lock's three knobs, then `headlessDisplay`, then the
  Virtual Desktop's three, as git merged the declarations and `changes(to:)`; the doc lines say both.
- `DebugHooks.swift` and `HostSettings.swift`: both, the lock's three keys before `headlessDisplay` and the Virtual
  Desktop's three.
- away-quality's `main.swift`, `mutants.py` and `README.md`: every case and every mutant of both, 81 mutants (this
  branch's 67 and main's 14). Each HostConfig the check makes takes every knob: the lock's blocks give the Virtual
  Desktop's three their defaults, and the Virtual Desktop's block gives the lock's three theirs. AQ-O1 keeps main's
  pattern; AQ-H1 and AQ-V1 match the merged `standard`'s `headlessDisplay: true, virtualDesktop: false,` line. This
  branch's size and rate mutants AQ-S1 to AQ-S8 are AQ-VS1 to AQ-VS8, since main's lock display switch is AQ-S1 to AQ-S4
  (docs/steps/2026-11-18-privacy-lock.md names them).
- docs/BUILD-AND-RUN.md: both, the `--virtual-desktop` line and the `--lock-after-session` dry run; the saved keys name
  the lock's three and the Virtual Desktop's.
- docs/LAYOUT.md: both, VirtualStage's `adoptTab` note before `SillDisplays`, and desktop-check's Virtual Desktop
  sentence before privacy-check's.

Where main meets the Virtual Desktop, read in the merged program:
- The lock (#402): `PrivacyLock` counts only a real screen for its rule 10, and the Virtual Desktop has the Desktop's
  identity (`.sillDesktop`), so beside a real screen nothing changes, and as the Mac's only display (its screens gone,
  the Virtual Desktop kept) it is #395's question, default 18 there. Both 30 s count from the last device leaving: the
  lock's wait and the Virtual Desktop's grace (default 9); whichever ends first acts, and a lock that lands first keeps
  the Virtual Desktop and its windows until 30 s after the next unlock, as any lock does (default 30).
- The tab switches (#399): `VirtualStage.adoptTab` reads the stage's display through `display`, which is
  `displays.display(.stage)` here; the catalog's tab tracking is beside this branch's look, and the Virtual Desktop's
  windows are moved by the coordinator's own `moveVirtualDesktopWindowsOut`, not by the stage's eviction that #399
  changed.
- The sound (#396): `appAudioDisplay` reads `stage.scDisplay` (`displays.listed(.stage)` here), so a staged window's
  sound follows a stage display made again as on main; the Desktop's sound is built on `catalog.mainDisplay` and keeps
  running across a step onto the Virtual Desktop (the `.desktop` key does not change). A window on the Virtual Desktop
  streamed in regular mode has its app's sound built on the main display, as a window on any other monitor does: #365's
  open case, which #396 left as it was (not tried: no real window here).

**Defaults taken for Noah to confirm** (this run's; 1 to 29 stand):
30. Lock this Mac when the last device leaves and the Virtual Desktop's grace both count 30 s from the last device
    leaving; whichever ends first acts. If the lock lands first, the Virtual Desktop and its windows stay, as while any
    lock (default 9), until 30 s after the next unlock; if the grace ends first, its windows move to the main display
    and then the Mac locks.

**Verified in this run** (2026-11-23; nothing made a display, posted input, locked, slept or switched anything; every
live run a synthetic test host on 127.0.0.1 with the software encoder, its Virtual Desktop only said to be made):
- The merge's tree is the one tried first (fdb41c89, the same merge of #395's a297443b, kept local), but for #395's step
  file: `git merge` of 303112f6 met the same eight conflicts, and the trial's resolution was taken whole (`git diff
  fdb41c89 66e0fe85` is 87 lines of docs/steps/2026-11-18-virtual-desktop-2a.md). The checks below ran on the trial's
  snapshot, the build and the gates on 66e0fe85.
- On a `git archive` snapshot (the heavy lock's slot B, 16:08–16:31): away-quality 286 checks and 81 of 81 mutants
  caught; stage-release 847 checks and 25 of 25; sill-displays 53 checks and 43 of 43 (both read VirtualStage.swift's
  and StreamCoordinator.swift's wiring, where main's lines landed); then `Tests/checks/run-all.sh`, all 77 checks passed
  (virtual-desktop 104,874, desktop-displays 213, full-screen 101,607, ledger (1,929 runs of the Virtual Desktop's rule
  11), compatibility 193, viewport-bounds 100, privacy 217, lock-policy 1,420, catalog-windows 107, window-restore
  41,944, audio-packetizer 106, update-install 1,062, virtual-display-api 308, repo-rules 11 of 11). Every other check's
  mutant patterns are found exactly once in the merged sources (a text check of every `mutants.py`; its few hits were
  short generic strings in files those checks never mutate).
- `swift build -c release` of 66e0fe85 (slot B, 16:31): 69 s, no warning but CaptureProbe's known one; `SillHost
  --internet` exits 2, `--print-reachability` 0, `--virtual-desktop=999x999@2` exits 2 naming the sizes it takes.
- The live gates on its CLI (synthetic hosts on 127.0.0.1, 16:32–16:49): `Scripts/desktop-check/live.py` 51 of 51 (24 of
  the stops and 27 of the Virtual Desktop's, as in the third part); `Scripts/lock-check/live.py` poll 42 of 42, start 4
  of 4, paired 6 of 6, view 26 of 26; `Scripts/headless-check/live.py OUT all` 66 of 66; main's
  `Scripts/privacy-check/live.py OUT all` 48 of 48; #396's sound gate (`retry_gate.py`, R1 to R4) 17 of 17; #399's
  loopback smoke 6 of 6.
- H2 against main's c33d1057 (built in #395's hold), run one right after the other in this hold, the statistics by name:
  idle identical (7 distinct lines, 3 statistics), with a test client identical (14 and 11), with `--virtual-display`
  and a test client identical (17 and 11); started locked, #395's one line, "Displays: N online, …" (11 lines and 10).
  Against #395's merged CLI it was not run in a hold: hold A's try found no base binary (its glob dropped every path in
  the folder vd-main), and a second hold queued behind other agents' jobs was withdrawn. In all four runs the masked
  lines and the statistics' names of each are the same sets as main's c33d1057 (#395's in its hold, this branch's in
  this one), so they are each other's too.
- Previews from the bare binary (its own log file, its defaults domain deleted after): 353 files; looked at: Settings ›
  Displays with the Virtual Desktop's section and A Mac with no screen's, the card's "Virtual Desktop · 1218×800", and
  Settings › Devices' lock section, main's.
- The iOS app as CI builds it (Xcode 27.1, Debug, the generic simulator, arm64, unsigned; its DerivedData removed
  after): BUILD SUCCEEDED, only the known capture warning in StreamClient.swift.
- GitHub's CI on 66e0fe85 (run 45158295317): every step of Build and check passed, and #408 read mergeable with its
  base.

The pull request's list of Noah's steps gains an 11 (Lock this Mac when the last device leaves with the Virtual Desktop
showing, default 30); its 11 to 14 are now 12 to 15. The list above keeps its old numbers.

**Fourth part (2026-11-23): main 5d062a3c brought in, and the Virtual Desktop follows its device in place, by Noah's
probes.** Main moved to 5d062a3c (#389, the words for the promised features; #418, the iPhone's key row above any
software keyboard): `virtual-desktop-2a` took it with no conflict (87367adc), and this branch took that head (4f14b58f)
with one conflict, iOSClient/HostSettingsPanel.swift, where #418's scroll anchor `hideThumbnailsRowID` and this branch's
`virtualDesktopID` were added on the same line: both stay. No source of this branch met main's change otherwise.

Then the probes. Noah ran four on his Mac on 2026-11-23 (Mac14,9, macOS 27.2.1, 26B131; Sill quit, no device connected).
Their outputs stay outside the repository, in `~/Downloads/sill-handoff/next/vd-2b/`: `noah-probes-20261123.md` (P2's two
runs, transcribed), `p1-20261123.txt` (P1 at the four sizes), `probe2/out-20261123-162350.txt` (P2b) and
`probe3/out-20261123-165306.txt` (P2c). The probes are in `Scripts/display-modes-probe/` as he ran them (P2's verdict lines
corrected, below). What they found:
- **P1** (`--virtual-display-selftest` at the four sizes): each came up at the mode asked, at 2x: 1218×800 and 1133×744 at
  60 Hz, 1376×1032 and 1496×800 at 120 Hz, online in 213 to 273 ms, ScreenCaptureKit listing it after 18 to 21 ms, gone
  after 58 to 327 ms. So #395's open decision 4 is answered: macOS keeps an iPad mini's own 1133 × 744 at 2x (the 800-point
  floor stays until Noah decides otherwise; it is #395's).
- **P2** (the room both ways listed at creation): the turn listed at creation is refused (the switch answered false and
  nothing changed); after `applySettings:` with three modes the display WAS at the new one 333 and 339 ms later, the same
  ID, though `switchMode` answered false (it looked in macOS's list from before; P2b showed why); a mode beyond the
  backing is listed and never taken.
- **P2b** (`probe2/`): a mode listed beside another (at creation, or `[room, turn]` later) reads "NOT usable for the
  desktop" (flags 0x1), and a CoreGraphics switch to it answers configure 0, complete 1001 (illegal argument), nothing
  changing: there is no way by the modes listed at creation. `applySettings:` with the turn ALONE moves the live display
  in place, the same ID, but to the turned pixels at 1x (1600×2436 @1× for 800×1218, in 351 ms; 1600×2992 @1× for
  800×1496, in 308 ms), and 300 ms later macOS lists the turn at 2x as usable (flags 0x2000003). Another shape of the same
  orientation inside the backing, alone, lands at 2x: 1496×800 to 1218×800 in 300 ms, back in 317 ms, the same ID; one
  beyond the backing (1496×800 on a display made 2436 px square) is never taken. Back to the room by `applySettings:` with
  it alone: 2x, 319 to 325 ms, from 1x too. Which mode macOS takes from a longer list is no rule of first, last, current,
  smallest or largest. `applySettings:` holds its caller 278 to 287 ms every time. The two windows of the probe's own on
  the display stayed on it, inside it, their size kept, through every step (the display never turned).
- **P2c** (`probe3/`): the turn in two steps works: `applySettings:` with the turn alone, then, as soon as the display reads
  the turned pixels at 1x and macOS lists the turn at 2x usable (both at +316 to +368 ms), a CoreGraphics switch to that
  mode answers configure 0, complete 0, and the display reads the turn at 2x at +650 ms (iPad mini, 800×1218 at 60 Hz),
  +683 ms (iPhone, 800×1496 at 120 Hz), +661 and +706 ms on displays made with the room alone (no turn listed at
  creation, the same square backing: listing the turn at creation is not needed); the switch call holds its caller 321 to
  334 ms; `switchMode`'s own lookup would pick the same mode. Back to the room by `applySettings:` with it alone: 2x in 317
  to 326 ms. The same display ID throughout, never removed or added; two reconfiguration callbacks for a turn (1x, then
  2x). hiDPI read back 2 before and after, the physical size unchanged (281×185 mm for the iPad mini's room). The probe's
  small window kept its size and stayed on the display; its window wider than the turn (974 or 1196 points of 800) was
  narrowed by macOS to 800 and stayed on it, and when the display turned back it was at its own width and place again
  without the probe moving it. Rotation (the private `rotation` setting, an unsigned int of unknown units) was not tried
  and is never used.
- **Never measured, by rule**: a ScreenCaptureKit stream of the display while it changes size in place, and how other
  apps' windows behave. Both are Noah's to try in this branch's build (the steps below).

What they decided, each in the code (`VirtualDesktopSize`: `followWay`, `backing`, `followStep`, `InPlace`; the
coordinator's `followVirtualDesktop`, `followVirtualDesktopInPlace`, `driveInPlace`, `adoptVirtualDesktopDevice`):
- **In place, by `applySettings:` with the new size alone** (`followWay = .newModes`; `.listedModes` is gone): a size of
  the display's orientation in one step (P2b step e), a turn in two (P2c step 1). The Virtual Desktop is made with its room
  alone, so macOS lists no unusable turn (P2c step 4).
- **The switch only once the display reads the size's pixels at 1x and macOS lists its 2x mode usable**, a usable mode
  chosen first (`VirtualDisplay.switchToListed`, `listsUsable`); a size macOS lands at 2x by itself needs none.
- **Each step read back, with a bounded wait**: the display's change within 2 s of `applySettings:` (measured 0.31 to 0.37
  s), the 2x listing within 1 s of the 1x landing (measured at once), 2x within 1.5 s of the switch (measured 0.33 s); a
  look every 20 ms.
- **A step refused, late or landing elsewhere falls back**: `applySettings:` with the size it had, alone (2x in about 320
  ms, from 1x too: P2b, P2c), and the new size waits for the next make, the letterbox as before; when even that does not
  land, the display goes (its windows to the main display first) and the Desktop that still shows its stop makes it again
  at the new size 3 s later: never a display left at 1x.
- **The backing** (`VirtualDesktopSize.backing`, VirtualDisplay's `backing`): a size past the backing it was made with is
  never taken (P2 step 3, P2b step e), and P2c made a turn on a display whose backing was larger than its modes. So This
  device's Virtual Desktop is made with a square backing of the longest side, at 2x, among its own size and every
  connected device's (either way round, as each may turn), at least 3072 pixels a side (every iPhone's and iPad's room
  both ways as far as is known: an iPhone Pro Max held sideways is about 1510 × 800 points, an iPad Pro 13-inch 1376 ×
  1032), at most 4096 (the widest picture every Mac's encoder takes, #295; 64 MiB at 4 bytes a pixel if macOS keeps it
  all, not measured), never less than its own pixels. A chosen size or Same as main display never follows a device and is
  made as before, with its own pixels. A size that does not fit waits for the next make, with one line.
- **The Desktop's stream restarts once, at the final size at 2x**: a turn is two reconfigurations (P2c), so the
  Desktop's display follower waits while a follow runs (`virtualDesktopResizing`); at its end the coordinator waits until
  ScreenCaptureKit lists the display at the new size (at most 1.5 s) and the follower restarts the Desktop once
  ("Desktop: the display is 800×1218 pt now (was 1218×800); restarting at its size.").
- **The main actor**: `applySettings:` holds it about 0.3 s and the switch about 0.33 s (P2b, P2c), as a make's own calls
  already do. The private object has only ever been called on the main thread, the probes' too, so it stays there; a
  device's input waits that long during a follow.
- **Windows**: at a turn macOS narrows a window wider than the display and keeps it on it, and gave the probe's own window
  its width and place back when the display turned back (P2c), so Sill moves none at a follow; the ledger
  (DesktopWindowLedger) is for the display's removal and return, as before. Other apps' windows are not measured (a step
  below; a known visible behaviour if an app's window stays narrow).
- **The device it is for**: the plan's rule (§5), kept as devices come and go: a device that steps onto the Virtual
  Desktop takes it (its room followed in place); when the device it was for leaves, the next device the make's own rule
  names (the one that asked for the Desktop last, as each does as it connects, else the newest viewport's) takes it while a
  device shows it. Two devices at once share it, sized for the one that stepped onto it last, as before.
- **The rate**: a turn keeps the rate it has; another device's rate (the person's choice, else the device's, held to the
  Frame Rate limit, as at a make) is asked with its size in the same `applySettings:`, and the stream is held to the rate
  CoreGraphics reads back (a rate changed in place is not measured).
- **A device before 0.7** (0.6.2): it sends no room, only its panel, which may change as its own controls come and go:
  its turn waits for the next make, as before (`followStep`'s `sendsRoom`). Every other path is as it was: the headless
  display (#395's) never follows; a test host and the CLI without the Virtual Desktop print nothing new.
- **Its lines**: "Virtual Desktop: in place: applySettings: with 800×1218 alone answered YES at +285 ms; at 1600×2436 @1×
  at +318 ms; …" (the steps, before each outcome), "Virtual Desktop: iPad mini turned; followed in place in 650 ms:
  800×1218 pt @2× at 60 Hz.", "Virtual Desktop: iPhone shows it now; followed in place in 300 ms: 1496×800 pt @2× at 120
  Hz.", "…; not followed in place: macOS refused the switch to its 2x mode (complete 1001); back at 1218×800 pt @2× in 980
  ms; the next one is made at 800×1218 pt.", "…, and it did not come back to 1218×800 pt @2×; removed it: the next one
  is made at 800×1218 pt.", "…; 1900×800 pt @2× is beyond the backing it was made with (3072×3072 px); the next one is
  made at 1900×800 pt.".
- **TEST ONLY**: a test host's said Virtual Desktop runs the same machine against `VirtualDesktopSize.TestDisplay`, the
  display as the probes measured one (a size of its orientation at 2x 0.32 s after `applySettings:`, a turn at its pixels
  at 1x first with its 2x mode then listed, the switch 0.32 s, nothing past the backing); `SILL_TEST_VD_STEPS`
  (`switch-refused`, `stuck`, `late`) makes a step fail. The desktop gate's scenarios use both.

The probes in the repository (`Scripts/display-modes-probe/`): `p2b/` (P2b: `probe2.swift` as run, `run.sh`) and `p2c/`
(P2c: `probe3.swift` as run, `VirtualDisplay-probe.patch` with its two PROBE ONLY changes, `run.sh`), both compiled with
`VirtualDisplay-b7339612.swift`, this branch's VirtualDisplay.swift as it was when they ran; each run.sh checks the
sources' sha256 against the ones Noah ran, never builds for `--dry-run`, refuses the real run without a terminal and while
a Sill runs, links no VideoToolbox or ScreenCaptureKit, stops each case at its limit and writes to
`.build/display-modes-probe/`; P2c's refuses `--quarter-turn`. P2's own `probe.swift` now says what the display did, read
back, beside the call's answer: its 2026-11-23 output said "new modes on the live display …: no" only because the verdict
wanted `switchMode` to answer true; the display was at the new size with the same ID. Its run.sh now refuses `--make`
without a terminal too, before it builds.

Checks: `virtual-desktop` (the backing and 2,000 random makes, the step, InPlace driven against TestDisplay and by hand,
P2c's own times in the detail line, 2,000 random follows against the invariants, the lines, the knobs; 235 mutants, 57
new), `virtual-display-api` (the backing asked for, the follow's calls' wiring as text; 108 mutants, 11 new),
`sill-displays` (the make with its backing; a display's size changed in place only by the coordinator's follow; 46
mutants, 3 new). The desktop gate's first Virtual Desktop host now follows the turn in place and back; two more hosts
show a refused switch falling back, the iPhone taking it over after the iPad, a room beyond the backing, and a way back
that never lands removing it and making it again.

**Defaults taken for Noah to confirm** (this part's; 1 to 30 stand, 8 replaced):
31. **In place** (replaces 8): a turn of the device it is for, or another device of the same orientation, is followed in
    place after 1 s steady (the plan's settle) and at most once every 3 s, inside the backing; refused or late, it falls back
    to the size it had and waits for the next make.
32. **The backing**: a square of 3072 to 4096 pixels a side for This device (every phone and iPad both ways, and the
    devices connected when it is made), its own pixels for a chosen size; a size past it waits for the next make.
33. **No new switch**: the follow in place lives inside the Virtual Desktop's switch (off by default) and its Resolution's
    Match the device; a fixed Resolution stops it, as before.
34. **The device it is for** passes to a device that steps onto it, and, once the one it was for leaves, to the next device
    that asks for the Desktop on it (the make's own rule); two at once share the one that stepped onto it last.
35. **A display that will not come back to 2x is removed** (its windows to the main display first) and made again 3 s later
    by the Desktop that shows its stop, rather than left at 1x.
36. **The main actor holds about 0.3 s per step** (0.6 s for a turn): the private object stays on the thread it was
    measured on.
37. **Sill moves no window at a follow**: macOS keeps them on the display and narrows a wider one; whether every app's
    comes back to its width when it turns back is Noah's step.
38. **A device of another rate taking it over** asks its rate in the same `applySettings:`; the stream is held to the rate
    CoreGraphics reads back.

**For Noah** (this part's; they come first in the pull request's list, after the install). Watch Sill.log meanwhile:
`grep -E "Virtual Desktop|Desktop:" ~/Library/Logs/Sill/Sill.log | tail -30`.
- **Turn the iPad while it shows the Virtual Desktop.** About two seconds later the Mac's desktop turns with it and fills
  the iPad again. Sill.log: "Virtual Desktop: in place: …" then "Virtual Desktop: iPad mini turned; followed in place in
  … ms: 800×1218 pt @2× at 60 Hz." and "Desktop: the display is 800×1218 pt now (was 1218×800); restarting at its size.";
  turn back: "… followed in place in … ms: 1218×800 pt @2× at 60 Hz.". A window wider than the iPad held upright is
  narrowed; turned back, it should be as wide as before. A failure: "not followed in place: …" (the iPad stays letterboxed
  until it is made again), "removed it" (it comes back upright 3 s later), a picture that freezes or stays the old shape
  after "restarting", or a window thrown onto another screen.
- **Let the iPhone take it over after the iPad.** With the iPad on the Virtual Desktop, disconnect the iPad and connect
  the iPhone within 30 s: its Desktop comes back onto the Virtual Desktop, which takes the iPhone's shape. Sill.log:
  "Virtual Desktop: iPhone shows it now; followed in place in … ms: 1496×800 pt @2× at 120 Hz." (at 60 Hz if macOS keeps
  the rate it had). A failure: "not followed in place: …" or "beyond the backing", or the iPhone letterboxed.

**Verified in the fourth part** (2026-11-23; nothing made a display, posted input, locked, slept or switched anything;
every live run a synthetic test host on 127.0.0.1 with the software encoder, its Virtual Desktop only said to be made;
the probes only as dry runs):
- `virtual-desktop-2a` with main 5d062a3c (87367adc), light, as the task asked, in the heavy lock (hold 1, 18:08–18:24):
  `swift build -c release` 67 s (CaptureProbe's known warning only), `SillHost --internet` exits 2,
  `--print-reachability` 0; `Tests/checks/run-all.sh` all 77 passed (749 s; main's phone-keyboard-lift 184,
  phone-portrait 484, tour 732,447, text-composition 194, repo-rules 11 of 11); the iOS app as CI builds it: BUILD
  SUCCEEDED (28 s, the known capture warning only). GitHub's CI on 87367adc (run 45170315810) and on this branch's merge
  4f14b58f (run 45170399117): every step of Build and check passed; both pull requests read mergeable.
- The same hold built 94b84331 (the coordinator's commit) from a snapshot: 66 s, no new warning; virtual-display-api
  316 checks and sill-displays 55 passed; virtual-desktop failed 126 of 109,264, all the check's own (its random follows
  that start on a turned display placed it with `late` already on; `applied` took an answer after the end): fixed in
  b9733f66, with one more mutant. ae797ee9 then wrote out the test hook's variable, since `away-quality` compiles
  VirtualDesktopSize.swift without VirtualDesktopLife.swift (found by reading the checks' compile lists before the holds).
- Hold A (slot A, 18:26–18:47) on ae797ee9, the code's head: `swift build -c release` 54 s, no warning; `SillHost
  --internet` exits 2, `--print-reachability` 0, `--virtual-desktop=999x999@2` exits 2 naming the sizes it takes. The live
  gates on its CLI: `Scripts/desktop-check/live.py` 69 of 69 on its first run (24 of the stops; the Virtual Desktop's
  first host 24, its turn now followed in place in 664 ms, 1x at +335 ms then the switch, the Desktop restarted once at
  800×1218, back in one step in 338 ms and once at 1218×800, a turn and back within the settle nothing, its grace, made
  again, locked, off console, the span, never two changes within 3 s; the `--pairing` host 7; the new `vd-in` host 11:
  the refused switch fell back to 1218×800 at 2x in 658 ms with no picture at the turn, the iPad gone, the iPhone that
  came took it over in place in 341 ms at 1496×800 with no switch and the Desktop at its size, a room 1900×800 pt wide
  beyond the 3072×3072 backing waited for the next make, made once in all; the `vd-stuck` host 3: removed at 10.5 s when
  the way back never landed, made again at 800×1218 at 13.5 s, the Desktop on it upright); `Scripts/headless-check/live.py
  OUT all` 66 of 66; `Scripts/lock-check/live.py` poll 42 of 42, start 4 of 4, paired 6 of 6, view 26 of 26;
  `Scripts/privacy-check/live.py OUT all` 48 of 48; #396's sound gate 17 of 17; #399's loopback smoke 6 of 6.
- H2 in the same hold, against main's CLI (main's host sources are the same at 5d062a3c as at c33d1057, whose binary
  #395's hold built), run one right after the other, every line but the statistics masked and sorted, the statistics by
  name: idle identical (7 distinct lines, 3 statistics), with a test client identical (14 and 11), with
  `--virtual-display` and a test client identical (17 and 11); started locked, #395's one line, "Displays: N online, …"
  (11 and 10). So the follow in place adds nothing on these paths.
- Sill for Mac's previews from the bare binary (its own log file, its defaults deleted after): 353 files, the Virtual
  Desktop's pane looked at (unchanged: this run changes no word of Sill for Mac's).
- The probes, as dry runs and refusals only: P2's dry run built and printed its plan; `--make` from an agent's shell
  answered "REFUSED: no terminal"; P2b and P2c: `--dry-run` with no build refused to build, `--build` built each (linking
  AppKit, CoreGraphics and Foundation, no VideoToolbox or ScreenCaptureKit), `--dry-run` printed each plan with nothing
  made (P2c's reads the rotation setting's type on a settings object given to no display, as when Noah ran it), the
  real run from an agent's shell answered "REFUSED: no terminal", P2c's `--quarter-turn 90` "REFUSED". Their dry runs end
  with the handoff folder's run.sh, as the sources Noah ran print it.
- The iOS app as CI builds it: BUILD SUCCEEDED (32 s, the known capture warning only). No device-side code changed this
  run, so no harness photo was retaken.
- Hold B (slot B, 18:26–19:59), on a `git archive` snapshot of ae797ee9: `virtual-desktop` 109,301 checks and 236 of
  236 mutants caught (64 minutes); `virtual-display-api` 316 checks and 108 of 108; `sill-displays` 55 checks and 46 of 46;
  then `Tests/checks/run-all.sh`, all 78 checks passed (797 s; away-quality, desktop-displays 213, full-screen 101,607,
  ledger, compatibility 193, lock-policy 1,420, stage-release 847, virtual-desktop 109,190, repo-rules 11 of 11 among
  them). Every other check's mutant patterns are found exactly once in this run's files (a text check, nothing compiled:
  vd-main's `patterns3.py` against 4f14b58f; its few flags were short generic strings in files those checks never
  mutate, and two replacement strings of this run's own mutants); `stage-release` and `away-quality`, which read or
  compile files of this run's, mutate none of them, and both passed in run-all.
- GitHub's CI on ae797ee9 (run 45179138167): every step of Build and check passed; #408 read mergeable with its base.

**Fifth part (2026-11-24): the room, after Noah's first try on real hardware.** Main moved to d9b3e995 (#410, Arrow Keys
on an iPhone's key row; #406, Picture in Picture's end with Sill in the background; #405, the Apps list's apps on other
disks): `virtual-desktop-2a` took it with no conflict (61adbfcf), and this branch took that head (bc905244) with one,
iOSClient/HostSettingsPanel.swift, where #410's `-SillSettingsScroll keys` and this branch's `vdesk` were added on the same
line; both stay. Noah then installed a build of this branch on his MacBook Pro, iPad mini and iPhone 15 Pro and tried it.
His words, whole: "There are issues with Virtual Desktop. When it loads in, you see black bars because the aspect ratio is
set to the devices aspect ratio. What it should do is size the window to be as large as the available space, the same way
Virtual Display works. In addition, the same behavior should happen when the device is rotated, but it doesn't really as
there are still vertical bars. Same thing should happen when full screen is enabled or disabled." His Mac's log of that
trial (the first time any of this ran on a real display): made 800×1218 pt @2× at 60 Hz in 490 ms for the iPad (its
screen); the iPad's turn followed in place in 402 ms (applySettings: answered YES at +284 ms, 2x at +402 ms), back in 456
ms, the Desktop restarted at its size; the iPhone taking it over sideways in 380 ms (1494×800 at 120 Hz); and the iPhone
upright, 800×1614 pt, "beyond the backing it was made with (3072×3072 px)", until the display was made again (444 ms). So
following in place works on a real display, and two things were wrong.

- **A. The size.** It was the device's room: Full Screen's, the shape of the whole screen (less the Dynamic Island's
  strip on an iPhone), whether the controls show or not. The picture is drawn in what the controls leave: on the iPad
  mini sideways the pane under the bar, 1117 × 618; upright the halves' upper pane, 728 × 535. So bars from the first
  moment, and again after each turn. Noah's decision: the space the picture has, as a window on the stage display is
  fitted to it, at the make, at a turn, when Full Screen goes on or off, and whenever else that space changes for good;
  never bars while Match the device is chosen.
- **B. The backing.** Run 4 made This device's display with a square backing of the longest size among the devices
  connected, at least 3072 px, "every iPhone and iPad room both ways". The iPhone upright needs 800 × 1614 pt at 2x, 3228
  px: it was never followed, and kept bars at its sides until the display was made again.

What the space is, read from the device (StreamScreen and PortraitStreamScreen, and the "viewport:" lines its DEBUG console
prints): the viewport's panel (`width`, `height`), in every layout, the very rectangle the stage fits a window to
(VirtualStage.windowSize: the panel ÷ Aa; Aa never resizes the Desktop):
- an iPad sideways, an iPhone on its side, the Duo's displays sideways: the pane under the bar, inside its 8-point margin
  (iPad mini 1117 × 618, iPhone 15 Pro 718 × 299, an iPhone 12 to 14 734 × 296);
- an iPad upright and the Duo's inner display upright (the halves): the upper half's pane (iPad mini 728 × 535; the Duo
  half folded above the fold; open flat at the picture's own shape, below);
- an iPhone upright: its 16:10 pane over the controls (377 × 235 on an iPhone 15 Pro); Larger Picture's taller room acts
  only while a window streams;
- with Full Screen, in every layout: Full Screen's room, which the panel then is (iPad mini 1133 × 744 and 744 × 1133,
  iPhone 15 Pro 393 × 793 upright and 734 × 393 on its side).
The device already keeps the panel still while the software keyboard comes up, the key row lifts above a tall one (#418:
"Never the lifted room: the Mac resizes nothing for a keyboard"), Settings, the drawer, Aa's ruler or a thumbnail's lights
open (each over the picture, not beside it), and a pinch zooms it (inside the pane): it never resized a Mac window for any
of them. It changes the panel, and sends a new viewport 0.25 s after the last change, when the device turns, its window is
resized or folded, Full Screen goes on or off (the bar or the rows go; in the halves the pane takes the whole screen), the
controls come back by themselves, or what streams changes a phone's arrangement. So nothing changes on the device, and
nothing on the wire: every device build sends its panel, 0.6.2 among them. The room stays, and now tells a turn from a tap.

What changed (VirtualDesktopSize, its check `virtual-desktop`, the coordinator; 180cf0c5):
- **Rule A**: `device(space:)` takes the panel (`device(room:panel:)` took the room first). An iPad mini sideways with its
  controls: 1446 × 800 pt; upright: 1089 × 800 (wide: the upper half is wider than tall); Full Screen: 1218 × 800 and 800
  × 1218. An iPhone 15 Pro upright: 1283 × 800 with the controls, 800 × 1614 with Full Screen; on its side 1921 × 800 and
  1494 × 800. Each keeps the picture's shape within the rounding of a point: no bars. The headless display (#395's) took the
  panel already; it still never follows.
- **Its timing** (`Follow`, `Cause`): a change whose room is the same and whose panel is not is a tap (Full Screen on or
  off, the controls back by themselves): followed at once. Another device taking it over (a step onto it, or its Desktop
  back on the stop once the one it was for left): at once. A change of the room (a turn, a fold, a resized window), a
  device that sends no room (0.6.2: a tap or a turn cannot be told), and the Desktop shown again after a window or another
  stop (what streams may still change a phone's arrangement): after 1 s steady, as the plan's settle. Never sooner than 1 s
  after the make or the last follow's end (was 3 s from its start: each follow is one or two calls of about 0.3 s and a
  restart of the Desktop's stream, so a run of taps follows about once a second, the newest last). Never during a follow
  (`started`, `going`): a change that comes meanwhile waits for its end, so Full Screen on and then a turn, or on and off,
  end at the device's last space, each in place, in order, with no make. Only while it shows: the phone's arrangement and
  the Duo's pane follow a window's shape while one streams, and a follow then would turn the display, and narrow its
  windows, for nothing.
- **Every device follows in place**: `followStep`'s `sendsRoom` is gone (a 0.6.2 device's panel is its space too).
- **Rule B** (`backing`): This device's display is made with a square backing of 4096 px (the cap run 4 already had: the
  widest picture every Mac's encoder takes, #295), never less than its own pixels, whatever devices are connected. Every
  iPhone's and iPad's space in a layout of its own, made for one and followed to by any other, either way round, fits:
  the widest is an iPhone 12 to 14's (and 16e's) on its side with its controls, 734 × 296 pt, 1984 × 800, 3968 px; an
  iPhone 15 Pro's 718 × 299 is 1921 × 800; held upright with Full Screen, 800 × 1614, 3228 px; an iPad Pro 13-inch's 1376 ×
  1032 is 2752 px. Only a window shaped past 2.56 : 1 (2048 × 800 pt), as Stage Manager or Split View can make on an iPad,
  does not: "… is beyond the backing it was made with (4096×4096 px); the next one is made at …", and that device sees
  bars until the Virtual Desktop is next made (30 s after none shows it, or the switch off and on). Memory: a 4096 px
  square is 64 MiB at 4 bytes a pixel if macOS keeps it whole (not measured); the stage's own display is made larger than
  that for every window an iPad mini streams (its envelope, 2234 pt square at 2x for a 1117-point panel, is its mode).
- **Its lines**: "Virtual Desktop 1446×800 pt @2× at 60 Hz id N: made in 490 ms for iPad mini (its picture: 1117×618
  pt).", "Virtual Desktop: iPad mini hid its controls; followed in place in 330 ms: 1218×800 pt @2× at 60 Hz.", "… showed
  its controls; …", "… turned; …" (wide became tall or tall wide, its shorter side the same), "…'s picture changed size;
  …" (a fold, a resized window, a device that cannot tell),
  "… shows it now; …" (another device), "… shows it again; …".
- **The device's side**: comments only (FullScreenPolicy.hiddenRoom, StreamScreen; Viewport.room's in StreamProtocol): the
  room tells the Mac a turn from a tap. No picture changes, so no harness photo was taken.

The desktop gate (ad38e4dd; sillclient.py's `--panel=WxH` and `--view-after=PANEL[,ROOM]@T`): the existing Virtual Desktop
hosts now send Full Screen's panel (the panel is the room), so their sizes, turns and fall backs are as they were; the
turn back now comes 1 s after the first follow's end. A host of its own for rule A: an iPad mini made at the space with
its controls showing (1446 × 800), Full Screen on and off followed in place at once (1218 × 800, back), a turn with the
controls showing after 1 s (its upper half's 1089 × 800, one step), Full Screen on upright (800 × 1218: 1x, then the
switch), Full Screen off and a turn 0.3 s later (each in place, in order, no make), then the iPhone 15 Pro upright with
Full Screen after the iPad (800 × 1614, inside the backing) and its controls back (1283 × 800), and the iPhone back on it
within its grace after Full Screen went on while away (nothing while away; its space then, after 1 s steady: "iPhone
shows it again", fab40170). A space beyond the backing is 2200 × 800 now. Each Virtual Desktop verdict that finds nothing
prints what the host said in its window.

**The gate where this branch meets #400 (the darkening).** In a local build of both (`test-070-all`), two of the gate's
verdicts failed every time, on a quiet Mac too: "the iPad gone, the iPhone that comes takes it over in place" and "a room
beyond the backing: the next make" found empty lists. The host had printed "Virtual Desktop: iPhone changed its room;
followed in place in 342 ms: …" and "… Wide iPad changed its room; …" where this branch alone prints "… shows it now; …".
The line said "shows it now" only when `vd.device != vd.sizedFor`, and `sizedFor` kept the iPad's ObjectIdentifier after
it left; an ObjectIdentifier is the object's address, and in that build the iPhone's connection object took the iPad's
(then the Wide iPad's took the iPhone's). Fixed where it began: `sizedFor` is gone, and the cause travels with the change
(`Follow.saw(_:cause:at:)`, `.device` from `adoptVirtualDesktopDevice`); the device it is for is still forgotten the
moment its connection leaves. The gate itself now prints, beside a verdict that finds nothing, the host's Virtual Desktop
lines of that window.

**For whichever of this branch and #400 lands second** (sill-displays fails where both are merged: "the reconfiguration
callback is registered in SillDisplays alone"): #400's Sill.app display watch (PrivacyCurtain.swift's DisplayChanges)
registers a CGDisplayRegisterReconfigurationCallback of its own; the second to land makes it take its display changes from
SillDisplays (a second listener on `watchReconfiguration`'s one callback, the change's beginning left out as both do) and
keeps the check as it is.

**The 800-point floor, for Noah** (reported, not built). Noah's first words for this feature (2026-11-18) were that it
"should default to resolution and refresh of client device"; probe P1 showed macOS keeps a device's own points at 2x
(1133 × 744 on the iPad mini). What an upright iPhone 15 Pro gets:
- with the floor (now): 800 × 1614 pt with Full Screen, drawn on a screen 393 points wide, so everything is at 0.49 of its
  size; 1283 × 800 with the controls showing (its 16:10 pane), at 0.29;
- with its own points: 393 × 793 (Full Screen) or 377 × 235 (the controls showing), at 2x, everything full size.
What macOS does at such a width (from what is known of it; nothing here was made, so not measured): the menu bar stays 24
points tall, and the menus that do not fit are not shown (the status items go first), so at 377 to 393 points the Apple
menu, the app's name and two or three of its menus show; Mac windows have minimum sizes, commonly 400 to 800 points wide,
and macOS lets a window stand larger than its display, past its edges, so most would not fit; the smallest resolution
macOS offers its own displays is about 1024 × 640 points. The question is in the pull request.

**Defaults taken for Noah to confirm** (this part's; 1 to 38 stand):
39. **Rule A in every layout**: the space is the viewport's panel, as for a window on the stage. On an iPad held upright
    with the controls showing that is the upper half, so the Virtual Desktop is wide there (1089 × 800 on an iPad mini)
    and tall only with Full Screen (800 × 1218); on an iPhone upright with the controls, its 16:10 pane (1283 × 800).
40. **The timing**: Full Screen on or off, the controls back by themselves, and another device taking it over: at once
    (the device has waited 0.25 s already); a turn, a fold, a resized window, a 0.6.2 device's change and the Desktop shown
    again: after 1 s steady; at least 1 s between follows (was 3 s).
41. **Only while it shows**: no follow while a window streams or another stop shows; back on it, its device's space then.
42. **Every device in place**, a 0.6.2 device too.
43. **The backing**: a 4096 px square for Match the device, whatever is connected (replaces 32).
44. **The make's line** names the picture's space.
45. **The iPhone Duo open flat and upright** (unchanged): its pane takes the picture's shape, so there the Virtual Desktop
    keeps the shape it was made with, with no bars either way; making the pane 16:10, as for a window the Mac sizes,
    needs the device to know the Mac sizes the Virtual Desktop to it (a later change if wanted).

**For Noah** (this part's; first in the pull request's list, after the install). Watch Sill.log meanwhile:
`grep -E "Virtual Desktop|Desktop:" ~/Library/Logs/Sill/Sill.log | tail -30`.
- **Step onto it with the controls showing** (the iPad mini sideways): no black bars. Sill.log: "Virtual Desktop 1446×800
  pt @2× at 60 Hz id N: made in … ms for iPad … (its picture: 1117×618 pt)." A failure: bars at its sides or top and
  bottom, or a made line without "(its picture: …)".
- **Full Screen on and off** (Settings › This iPad › Full Screen; the swipe in from the left edge brings the controls
  back): no bars either way, about half a second after each. Sill.log: "… hid its controls; followed in place in N ms:
  1218×800 pt @2× at 60 Hz." and "… showed its controls; …: 1446×800 …"; N is how long the display took (about 300 ms
  here; 650 for an upright iPad, whose desktop turns). A failure: bars that stay, "not followed in place", or a picture
  that freezes.
- **Turn the iPad with the controls showing**: after about a second and a half, no bars: upright "… turned; followed in
  place in … ms: 1089×800 pt …" (the upper half is wider than tall), and back sideways 1446×800. A failure: vertical bars
  after the turn, as in the first try.
- **The iPhone upright after the iPad**: with the iPad on the Virtual Desktop, disconnect it, then connect the iPhone held
  upright with Full Screen on, within 30 s: "iPhone shows it now; followed in place in … ms: 800×1614 pt @2× at 120 Hz."
  (at 60 if macOS keeps the rate it had). A failure: "beyond the backing", or bars at its sides.

**Verified in the fifth part** (2026-11-24; nothing made a display, posted input, locked, slept or switched anything;
every live run a synthetic test host on 127.0.0.1 with the software encoder, its Virtual Desktop only said to be made):
- `virtual-desktop-2a` with main d9b3e995 (61adbfcf), light, in the heavy lock (hold 1, 17:37–17:52): `swift build -c
  release` 92 s (CaptureProbe's known warning only), `SillHost --internet` exits 2, `--print-reachability` 0;
  `stage-release`'s 25 of 25 mutants caught (it reads StreamCoordinator.swift's wiring, which #405 changed); then
  `Tests/checks/run-all.sh`, all passed. Its local iOS build stopped at the disk's floor (24 GB free); GitHub's CI on
  61adbfcf (run 45388088370) built the iOS app and passed every step, and on this branch's merge bc905244 (run
  45388164100) too; both pull requests read mergeable.
- Hold 2 (17:52–17:58) on ad38e4dd, the first build of rules A and B: `swift build -c release` 68 s, no new warning;
  `sill-displays` 59 checks, `virtual-display-api` 316, `away-quality`, `viewport-bounds` 100 and `full-screen` passed;
  `virtual-desktop` did not compile (a top-level `turn` declared twice: a486ffb3, then 3fe92422 for five messages, then
  CI's run of 3fe92422 found two cases of its own wrong: 272567ab). `Scripts/desktop-check/live.py` 82 of 82 on its first
  run: the old hosts as before (the turn in place in 672 ms, back in 325 ms; the refused switch's fall back; the iPhone
  taking it over in 340 ms at 1496×800; 2200×800 beyond the 4096 px backing); the new host 13: made at 1446×800 for the
  iPad mini's 1117×618 pane; Full Screen on followed in 332 ms, its line 0.4 s after the viewport, off in 328 ms; the turn
  with the controls showing after 1 s in 331 ms at 1089×800, one step; Full Screen on upright in 656 ms, 1x then the
  switch; Full Screen off and a turn 0.3 s later: 332 ms, then the turn 1.4 s later in 330 ms, no make; the iPhone upright
  after the iPad in 663 ms at 800×1614 (inside the backing); its controls back in 323 ms at 1283×800.
- Hold 3 (slot B, 19:56–23:16; the Mac slept 20:41–22:27 on a 1 % battery, and the mutants with it), on a `git archive`
  snapshot of 272567ab: `virtual-desktop` 109,709 checks and 250 of 250 mutants caught (rule A, the cause, the follow's
  timing, the backing, the lines); `sill-displays` 59 checks and 51 of 51 (5 new: the space read as the room, the make
  sized by the room, made with its own pixels alone, followed while it does not show, a tap told from a turn by this
  viewport alone); then `Tests/checks/run-all.sh`, all 79 passed (821 s). `virtual-display-api` and `away-quality` were
  not run with their mutants: neither their rules nor their files' patterns changed (every pattern of every check found
  exactly once in the files this run changed, a text check, nothing compiled: vd-main's `patterns3.py` against bc905244;
  its flags were replacement strings of this run's own mutants and short strings of home-records and version-label,
  which mutate HostIdentity, SavedMacs and VersionLabel alone).
- GitHub's CI on fab40170 (run 45414428634): every step of Build and check passed (the release build; run-all, all
  passed: virtual-desktop 109,781, sill-displays 59, protocol, repo-rules 11 of 11; the iOS app, BUILD SUCCEEDED; the
  CLI's paths); #408 read MERGEABLE and CLEAN. On 272567ab (run 45407341666) `protocol` failed once by chance ("generate:
  digits uniform (chi² 28.5 < 27.9, 9 df, p 0.001)": the pairing code's random digits, a one-in-a-thousand test of a file
  this branch does not touch); it passed on the next head.
- The heavy lock's fourth hold (the release build of the head, the gates, H2, the previews) never began: from 23:00 to
  01:23 the disk stood at 24.1 to 24.3 GB free (`df -g`: 24) with no heavy job running anywhere, under the 25 GB floor at
  which a hold may start, and nothing of this run's was left to remove (both worktrees' `.build` folders were gone
  already). So the live gates ran outside the lock, where nothing compiles (01:24–01:45, load 2 to 3), on hold 2's build
  of ad38e4dd, whose host code differs from the head's only in 272567ab's words for a turn, which none of these scenarios
  meets (each turn in them is an exact swap of the room's sides): `Scripts/desktop-check/live.py` 84 of 84 (the 82 above,
  and the iPhone back on it within its grace: nothing while it showed the main display and Full Screen went on; back on
  it, "iPhone shows it again; followed in place in 666 ms: 800×1614 pt", 1.7 s after the step, its 1 s settle and the
  two steps); `Scripts/headless-check/live.py OUT all` 66 of 66; `Scripts/privacy-check/live.py OUT all` 48 of 48. This
  Mac's own screen was locked then (`IOConsoleLocked`), which #396's sound gate, #399's smoke and H2's runs read (they do
  not set SILL_TEST_LOCK_IGNORE_MAC): their first run gave every host the locked placeholder (3 of 17, 5 of 6, and #395's
  locked "Displays:" line in all four of H2's runs). Again with SILL_TEST_LOCK_IGNORE_MAC=1 for both CLIs: the sound gate
  17 of 17, the smoke 6 of 6, and H2 against main d9b3e995's CLI (as privacy-darken's run 6 built it at 18:02 from
  `git archive d9b3e995`, `swift build -c release --product SillHost`), run one right after the other: idle identical (8
  distinct lines, 3 statistics), with a test client identical (15 and 11), with `--virtual-display` and a test client
  identical (18 and 11); started locked, #395's one line, "Displays: N online, …" (11 and 10). Not run: `lock-check`,
  whose keyframe decoder (`Scripts/lock-check/build.sh`) compiles (this run changes nothing of the lock's); Sill for Mac's
  previews (no build of SillMenuBar; its sources are unchanged since run 4's 353 previews); the release build of the head
  here (CI built it on fab40170 and 73f09137).
- The disk came back to 29 GB free near 02:00, and the fourth hold ran (slot B, 02:32–02:54) on the head, aa968534:
  `swift build -c release` 72 s, no warning but CaptureProbe's known one; `SillHost --internet` exits 2,
  `--print-reachability` 0, `--virtual-desktop=999x999@2` exits 2 naming the sizes it takes; main d9b3e995's CLI built
  from a `git archive` snapshot (46 s). The live gates on the head's own CLI: `desktop-check` 84 of 84; `headless-check`
  66 of 66; `lock-check` poll 42 of 42, start 4 of 4, paired 6 of 6, view 26 of 26; `privacy-check` 48 of 48; #396's
  sound gate 17 of 17 and #399's smoke 6 of 6 (SILL_TEST_LOCK_IGNORE_MAC=1 for both, as for H2). H2 against that main
  CLI, run one right after the other: idle identical (8 and 3), a test client identical (15 and 11), `--virtual-display`
  with a test client identical (18 and 11), started locked #395's one "Displays:" line (11 and 10). Sill for Mac's
  previews from the bare SillMenuBar: 353 files, each byte for byte the same as run 4's (no word or view of Sill for Mac
  changed). The iOS app was left to GitHub's CI, which built it on every head of this run.

**Sixth part (2026-11-25, run 6): main 22ab5a3e brought in, an iPhone's Virtual Desktop pixel for pixel (part A), and
custom sizes (part B).** Main moved to 22ab5a3e (#414, Hold, Then Drag on by default; #393, Settings on a device as a
whole-screen pane in one column): `virtual-desktop-2a` took it with no conflict (18a47362; nothing under Sources/ changed,
so the Mac is as it was), and this branch took that head (023201d5) with one conflict, docs/LAYOUT.md's paragraph naming
MockCatalog, HostSettingsLedger and HostSettingsPanel: main's whole-screen pane kept as main wrote it, with this branch's
words in it (the `vdesk…` cases, the ledger's eighth field and rule 11, the Virtual Desktop's switch among the Mac's
part's groups). git placed the Virtual Desktop's switch and its footnotes after Virtual Display's row inside #393's
`macPart`, where default 23 had said it would go. GitHub's CI on both merges passed every step (2a: run 45498083096; 2b:
run 45498202041), the iOS app with #393's pane and this branch's switch among them.

**Part A: the iPhone's size.** Noah was shown three choices for an iPhone: as it was (the 800-point floor, about half
size), life size (its own points: macOS barely fits), and in between, one Mac pixel on one iPhone pixel (its own pixels
made as a 2x desktop: about two thirds size and the sharpest). His decision, whole (2026-11-24): "middle one for iPhones,
and leaving iPads as they are." So while Match the device is chosen:
- **An iPhone's Virtual Desktop is its picture's space counted in its own pixels, made as a 2x desktop of that many
  pixels** (`VirtualDesktopSize.phone`): rule A's space (the viewport's panel, not the whole screen unless the picture has
  it) times the screen's pixels a point, each side halved for a 2x desktop. An iPad keeps `device(space:)` as it was (its
  own points at 2x, the shorter side grown to 800 points), and so does a device that says nothing of its screen.
- **Which devices are iPhones**: the device says so itself, by its idiom (UIDevice's `.phone`): every iPhone, and the
  iPhone Duo on both its screens (default 46 below). Nothing on the Mac keeps a table of models.
- **How the Mac knows the pixels**: every viewport from a device of this branch carries `screen` (`ViewportScreen`, kind
  9, optional): the screen's own pixels held upright (`nativeBounds`: an iPhone 15 Pro's 1179 × 2556), the pixels a
  point the picture is drawn at (`scale`: 3) and `phone`. The Duo's window moves between its screens as it folds, and
  the viewport it sends then names the screen it is on. A Mac takes a screen within ViewportBounds.screen (1 to 32768
  pixels a side, 1 to 4 pixels a point) and ignores any other; it never refuses a viewport for it, so a later device
  with a screen past these bounds is served as one that says nothing. An older device (sends none) gets what it had: the
  800-point floor. An older Mac skips the key (JSONDecoder) and keeps its own rule (this branch's run 5: the floor; a
  Mac before 0.7 has no Virtual Desktop at all).
- **Odd pixel counts**: a 2x desktop has an even number of pixels a side, and an iPhone's side can be odd (an iPhone 15
  Pro upright with Full Screen: 393 × 793 points, 1179 × 2379 pixels). The desktop takes the even count below (589 × 1189
  points, 1178 × 2378 pixels), one pixel short at most. Fitted aspect-fit that picture would be scaled by 1179/1178, a
  hair, which resamples every pixel; so the device draws a picture that is its pane's own pixels less at most two a side
  one for one, from the pane's top-left pixel (`PictureFit`, new, `Tests/checks/picture-fit`), and the spare pixel is a
  hairline at its right or bottom edge (black with Full Screen, the panel's grey otherwise). The stream view's frame
  (ZoomedStreamView), the pointer sprite (HEVCDisplayView) and every touch (InputOverlay) take the same rectangle, so a
  touch lands where the finger is; a pinch still scales the whole pane about its middle.
- **The layouts of an iPhone 15 Pro** (393 × 852 points at 3x, 1179 × 2556 pixels; the spaces as its console prints
  them):

  | Layout | The space | Its pixels | The Virtual Desktop | On the iPhone |
  |---|---|---|---|---|
  | Upright, Full Screen | 393 × 793 pt | 1179 × 2379 | 589 × 1189 pt @2× | pixel for pixel, two thirds size |
  | On its side, Full Screen | 734 × 393 pt | 2202 × 1179 | 1101 × 589 pt @2× | pixel for pixel |
  | On its side, its controls showing | 718 × 299 pt | 2154 × 897 | 1077 × 448 pt @2× | pixel for pixel |
  | Upright, its controls showing (the 16:10 pane) | 377 × 235 pt | 1131 × 705 | 800 × 499 pt @2× | scaled to 0.71 (default 47) |

  Run 5 made them 800 × 1614, 1494 × 800, 1921 × 800 and 1283 × 800.
- **The one bend of his rule** (default 47, the first for Noah to confirm): where a layout's pixel-for-pixel desktop would
  have a side under 400 points, or both sides under 800, it is grown evenly from the space's shape until it has neither,
  and the picture is scaled to fit. Why there: macOS kept no display of Sill's at 2x with both sides under 800 points
  (the stage's 754 × 784 came up at 800 × 832 at 1x, five times: VirtualDisplaySize), and a desktop shorter than 400
  points leaves under 370 below its 30-point menu bar, too little for a Mac window with its title bar and toolbar. Every
  layout of a current iPhone but one is past both: the 16:10 pane over an upright iPhone's controls (565 × 352 at 2x on an
  iPhone 15 Pro: both sides under 800, and 352 tall) becomes 800 × 499. 400 sits clear of every iPhone's own shortest
  layout (on its side with its controls: 444 on an iPhone 12 to 14, 448 on a 15 Pro, about 489 on a Pro Max), so none is
  scaled by a hair. An iPhone SE (2x) and a mini are bent more often.
- **What macOS does at these sizes is not known**: no display narrower than 744 points was ever made on Noah's Mac (P1:
  1133 × 744). Probe P3 (`Scripts/display-modes-probe/p3/`, Noah's, about a minute and a half) makes each size an iPhone
  15 Pro gets for a few seconds, reads back its mode, its menu bar and the room under it, follows the first in place to
  the others, and removes it. Until it says, Sill falls back by itself: **a make** that comes up elsewhere (at 1x, or
  another size), throws or never comes up is made again at once at the size that works (the 800-point floor, which macOS
  has always kept at 2x), with one line ("Virtual Desktop: macOS did not keep 589×1189 pt @2× (it came up at 800×1615 pt
  @1×); made it at 800×1614 pt @2×, the size that works, the picture scaled."), and that size is not asked again this
  run (`afterMake`, `notKeptAtMake`); **a follow in place** to one that does not land falls back to the size it had, says
  so in one line, and follows the size that works next, in place, after the spacing (`phoneSizeNotKept`). Never without a
  desktop. TEST ONLY: `SILL_TEST_VD_STEPS=short-1x` makes a test host's said display do what macOS did with the stage's
  754 × 784 to any side under 744 points.
- **Rules A and B, the timing and the follow in place still hold**: the space is still the viewport's panel (rule A); the
  4096-pixel backing holds every iPhone's pixel-for-pixel size either way round (the largest, the Duo's inner screen flat,
  1426 × 1003 points, is 2852 pixels); the cause and its timing (a tap at once, a turn after 1 s) are the space's, not the
  size's; a size of the display's own orientation lands in one step, a turn in two (the said display does both at these
  sizes in the gate; P3 does them on a real display).
- **A chosen Resolution changes nothing**: it keeps its own size and rate, for an iPhone too. The headless display of a
  Mac with no screen (#395) keeps its own rule (the floor): it is the Mac's only display, its login window included.
- **The lines**: the make's names an iPhone's pixels ("… for iPhone (its picture: 393×793 pt, 1179×2379 px; pixel for
  pixel)."; grown: "…; scaled to fit: an iPhone's desktop is at least 800×400 pt"), a follow's ends ", pixel for pixel.",
  and the fall back's one line above.

**Defaults taken for Noah to confirm** (this part's; 1 to 45 stand):
46. **The iPhone Duo is an iPhone on both its screens**: pixel for pixel on its outer screen (466 × 678 points at 3x:
    about 699 × 1017 with Full Screen upright) and on its inner one (669 × 951 at 3x: flat with Full Screen 1426 × 1003
    points, two thirds size and sharp, where the iPad's rule would give 1137 × 800, larger and scaled).
47. **The one bend**: no side of an iPhone's Virtual Desktop under 400 points and the longer at least 800, grown evenly
    from the space's shape where it would be smaller, the picture then scaled: only the 16:10 pane over an upright iPhone's
    controls on a current iPhone (800 × 499 on an iPhone 15 Pro, scaled to 0.71).
48. **The spare pixel** of an odd side is a hairline at the picture's right or bottom edge, never a hair's scaling.
49. **A size macOS does not keep** is never asked again in that run of Sill; the next run tries pixel for pixel again.

**Part B: custom sizes.** Noah, 2026-11-24, whole: "For Virtual Desktop, I would also like to allow users to be able to set
custom resolutions/refresh rates up to 2x native resolution of device panel and 120Hz. So for an iPad Pro 13" for example,
max would be 5504 × 4128 at 120Hz or any resolution/refresh rate that is less than 2726461440 pixels per second (so 4K at
same refresh would work, ultra wide, higher res at 60Hz, etc). What do you think?" He was answered that the rule is good,
with one addition (the Mac, not the device's panel, stops people first: some Macs refuse a picture wider than about 4096
pixels, and no Mac known encodes 2.7 billion pixels a second in real time), in four points: the budget is the ceiling of
what can be typed, refused above it with a plain sentence; Sill says what this Mac can carry; a desktop larger than the
encoder takes still works, the picture scaled down to fit it (as a contributor's open pull request does for wide
windows); Match the device stays the default; and, the setting being the Mac's and the budget a device's, the display keeps
its size and a device with a smaller budget gets the picture scaled for it. His answer, whole: "I agree with your
assessment on the custom sizes, implement it. Make it work depending on the device (iPhone, iPad, etc as you described).
Add to the pull request before it merges please."
- **Where** (B1): Settings › Displays, Resolution's last entry "Custom…": a width and a height in pixels, Retina (a 2x
  desktop: half as many points each way; on by default) and a refresh rate typed (24 to 120 Hz, whole numbers; empty: the
  device's), taken by Use This Size. Rates: any whole number from 24 (the least Sill streams at, its floor for every
  rate) to 120 (the most any iPhone or iPad shows); a rate that does not divide the device's own (90 on a 120 Hz iPad)
  shows uneven motion, which is the person's choice to make. The saved value is the list's form, "WxH@S" in points
  (`HostConfig.virtualDesktopSize`, `virtualDesktopHz`; no new key and no new parameter of HostConfig's initializer), so
  a Sill for Mac before custom sizes reads a typed one as none of its choices and takes Match the device (its `choice`
  knew the list alone; validated() then: never a crash), and a typed rate as the device's. The CLI's
  `--virtual-desktop=WxH@S[:HZ]` takes the same, refused over the largest current iPad's budget (it knows no device) with
  the same sentence. A device's own pickers stay phase 3's (default 50). A device shows the Mac's choice as it showed any
  size: its Settings' "Its size: 2752 × 2064 at 120 Hz." (points, from kind 16's `virtualDesktopState.size`, whose form and
  parse are the same: an older device reads a typed size as it read the list's, and nothing new is sent to any device).
- **The ceiling, by device** (B2, `VirtualDesktopBudget`): a device's budget is (2 × its screen's pixels wide) × (2 × its
  screen's pixels high) × 120 pixels a second, "at most" including the number itself: an iPad Pro 13-inch's 2064 × 2752 is
  5504 × 4128 at 120 Hz, 2,726,461,440. The screen is the one its viewport names (`Viewport.screen`, part A's field), and
  `current` lists every current iPhone's and iPad's, from Xcode 27.1's simulator profiles (CoreSimulator's DeviceTypes,
  each one's ScreenDimensionsCapability: Apple's own numbers), the iPhone Duo's two screens among them. What may be
  typed: the largest budget among the devices this Mac knows (Sill for Mac keeps each device that connected and said its
  screen, `HostSettings.knownDevices`, saved as JSON under `virtualDesktopDevices`), or the largest current iPad's when it
  knows none (default 51). Beside the entry, each known device's line: "Your iPad: as it is, at 120 Hz." or "Your
  iPhone: scaled to 4008 × 3006 at 120 Hz."; with none known, "No device has connected yet: up to 5504 × 4128 at 120 Hz,
  the largest current iPad’s, or as many pixels a second at a lower rate." Refused, with one sentence each: a side not
  typed ("Type a width and a height in pixels."), under 640 or over 8192 pixels, an odd Retina side, a Retina desktop
  under 1600 pixels on both sides (macOS shows it at standard resolution: the stage's 754 × 784), a rate out of 24 to 120
  Hz, and over the ceiling: "That’s more than Sill sends to iPad Pro 13-inch: up to 5504 × 4128 at 120 Hz, or as many pixels
  a second at a lower rate." with no device known, "… to your iPad: up to …" with that device's size when it is one this
  Mac knows.
- **A device's name** (default 56): a device of Sill's calls itself by its kind and model identifier, "iPad (iPad16,6)"
  (UIDevice's name, which since iOS 16 is the kind alone, and the identifier: ClientStatsReporter.deviceName), and the
  status menu shows it as "iPad"; so Settings says "your iPad" (`VirtualDesktopBudget.shownName`), and "your iPad
  (iPad16,6)" while another device of its kind is known, so the two read apart. Sill for Mac keeps each device by that
  whole name, the 24 that connected last. The host lists for it only the devices whose names it knows, anew when a name
  comes with a hello or stats (`publishBudgetDevices`), so a device that said its screen before its name is never kept as
  "a device" (desktop-check's first try at 39b76f54 found the budget's line naming "a device": its clients sent no hello;
  a device of this build sends its hello, and its name, first).
- **What this Mac can carry** (B3): Sill already learns at launch whether its hardware encoder answers (one small frame,
  `EncoderProbe.hardwareResponds`), and while it streams on the software encoder, how fast the hardware runs at the
  stream's size (`throughput`, the re-check of docs/steps/2026-09-24-encoder-recovery.md, kept as `enginePixelRate`);
  #295 adds whether the hardware takes a picture that wide at all (`HEVCEncoder.hardwareTakes`). For a chosen size and rate
  the coordinator asks the last two once a run, off the main actor (`lookAtVirtualDesktopEncoder`: the width at once, the
  rate only while no device is connected, so no stream is disturbed; else when the last device leaves), and Settings shows
  one line beside the size in use when it cannot run at full size or full rate: "This Mac’s video encoder takes at most
  4096 pixels a side: Sill streams this scaled down to 4096 × 2304, at about 38 frames a second." (or either half), "This
  Mac streams this at about 61 frames a second.", or on the software encoder, that (`encoderNote`). The same line goes to
  the log. No agent ran either measure: in the gates and previews they are given (TEST ONLY `SILL_TEST_ENCODER=widest=
  4096,fps=31`, a test host's alone, never its hardware's).
- **Above the encoder's limit** (B4): the contributor addhumal's #295 ("Hold a stream to 4096 px when the Mac's hardware
  encoder refuses its size (#278)") is merged into this branch, its commit kept, its one conflict settled (below). Judged
  sound: it asks the hardware for a session that must be hardware only for a size past 4096 pixels (once a size, about 1
  ms, 200 ms the first time), holds the encoder and the capture to 4096 pixels on the longer side with the shape kept when
  that fails, compares a window's new size with the size asked before the hold (no restart loop), holds the re-check's
  test the same way (a way back from the software encoder), in integer arithmetic, with its check (20,000 sizes) and six
  mutants; a Mac whose hardware takes the size is unchanged. Extended: `EncoderLimit.held` takes the side (a test host's
  said widest), the Virtual Desktop's capture at a chosen size goes through it like any source's (the display keeps its
  size, the picture is scaled to fit), and a test host on the software encoder says and makes the same hold under
  SILL_TEST_ENCODER.
- **A smaller device** (B5): while the Desktop streams the Virtual Desktop at a chosen size, its picture is held to the
  smallest budget among the devices connected that say their screen (`virtualDesktopBudgetHold`: `fitted`, the largest
  even size of its shape whose pixels a second at the stream's rate are within it), the display keeping its size, one
  line ("Virtual Desktop: 5120×2880 at 60 Hz is more than iPhone SE takes (480240000 pixels a second): streaming it at
  3772×2120."). Sill streams one picture to every connected device, so a second device of another kind showing the
  Desktop too gets the same picture: an iPad Pro beside an iPhone 15 Pro gets the iPhone's (4008 × 3006 for 5504 × 4128 at
  120 Hz), shown scaled up to fill its screen, until the iPhone leaves; then the Desktop starts again at the full size
  (or the encoder's). A device's rate is its own (the display's, held to what it shows), as for every stream. A device that
  says nothing of its screen (before 0.7) adds no budget. Match the device and the main display's size never are held.
- **The rest at a custom size** (B6): every touch is a fraction of the picture, and lands on the display's own rectangle
  (InputLanding), whatever the picture's scale; a pinch scales the picture on the device; the keyboard is the Mac's. A
  chosen size never follows the device (it keeps its size and may show bars, as every chosen Resolution does); its 30 s
  life, the lock's and the darkening's rules are the display's, unchanged. Its backing is its own pixels (as every chosen
  size's): 5504 × 4128 is 87 MiB a frame at 4 bytes a pixel (macOS may keep two or three; not measured), 8192 × 4608 at 60
  Hz 144 MiB; the hard stop is 8192 pixels a side (VirtualDisplay's ceiling, and the entry's). Match the device stays the
  default, and nothing changes for a person who never opens Custom….
- **#295's conflict**: Sources/SillHost/StreamCoordinator.swift, where main's #399 added `followTabSwap` right before the
  `encoderWidth` and `encoderHeight` that #295 replaces with `encoderAsked`: both kept (followTabSwap as main has it;
  `encoderAsked` in place of the two, which nothing else reads).

**Defaults taken for Noah to confirm** (part B's; 1 to 49 stand):
50. **The choice is the Mac's**: Settings › Displays' Custom… and the CLI's flag; a device's own pickers stay phase 3's.
51. **The ceiling** with no device known is the largest current iPad's budget (5504 × 4128 at 120 Hz); with devices known,
    the largest of theirs (the iPhone Duo's inner screen, 2007 × 2853, is a little larger than an iPad Pro 13-inch's).
52. **Rates** of 24 to 120 Hz, whole numbers; empty is the device's.
53. **A Retina desktop** needs one side of 1600 pixels or more, and even sides; each side 640 to 8192 pixels.
54. **One picture for every device**: two devices of different budgets showing it both get the smaller one's picture.
55. **Sill measures the encoder** at a chosen size once a run, its rate only while no device is connected.
56. **A device is "your iPad"** in Custom…'s lines and sentences (as the status menu's "iPad"), whole ("your iPad
    (iPad16,6)") only while two of a kind are known; no table of model names.
57. **Sill for Mac keeps the 24 devices that connected last** for the ceiling and the lines; nothing forgets one by hand,
    so a device given away keeps its budget the ceiling until 24 newer ones replace it.

**Words for COMPATIBILITY.md once a public build carries them** (the sixth part's; proposed, not written there): "a
viewport's optional `screen` (`ViewportScreen`: `pixelWidth` and `pixelHeight` held upright, `scale`, `phone` optional),
which every device from this build on sends and a host takes only within `ViewportBounds.screen` (each side 1 to 32768
pixels, 1 to 4 pixels a point), ignoring any other and never refusing the viewport for it; an older host skips it, and a
host serves a device that sends none as before (the 800-point floor, no budget)."

**For whichever of this branch and #400 lands second** (the sixth part's; the fifth's words stand): a direct merge of the
two meets in the same files with the same number of conflict blocks as the fifth part's head did (git merge-tree, read
only): this run adds no parameter to HostConfig's initializer, keeps `standard`'s "headlessDisplay: true, virtualDesktop:
false," as it is, and keeps Sill for Mac's known devices beside the log's switch, away from the darkening's new settings
(39b76f54), so the local combined build's settling script finds its blocks where it expects them.

**For Noah** (the sixth part's; first in the pull request's list). Watch Sill.log meanwhile:
`grep -E "Virtual Desktop|Desktop:|This Mac's hardware" ~/Library/Logs/Sill/Sill.log | tail -40`.
1. **Probe P3, two minutes, no install**: `zsh ~/Downloads/wt-vd-2b/Scripts/display-modes-probe/p3/run.sh` with Sill quit
   and no device connected; it makes each size an iPhone 15 Pro gets for a few seconds and says whether macOS kept it at
   2x. A failure: "kept at 2x: no" (Sill then makes the 800-point size for that layout and says so, default 49).
2. **Install this branch**: Sill for Mac, and the app on the iPhone and the iPad (both changed: they say their screen, and
   an iPhone draws its desktop one pixel for one).
3. **The iPhone upright with Full Screen** on the Virtual Desktop (Match the device): text about two thirds of its own size
   and sharp, no bars; "Virtual Desktop 589×1189 pt @2× at 120 Hz id N: made in … ms for iPhone (its picture: 393×793 pt,
   1179×2379 px; pixel for pixel)."; on its side 1101×589, its controls 1077×448, upright with its controls 800×499
   (scaled). A failure: half-size text (800×1614), bars, or a picture soft everywhere.
4. **A size of your own within the budget**: Custom… 3840 × 2160, Retina off, 60 Hz: "Your iPad: as it is, at 60 Hz." and
   "Your iPhone: as it is, at 60 Hz."; Use This Size; made at that size the next time. A failure: no line per device, or a
   made line at another size.
5. **One over the budget**: 8192 × 4608 at 120 Hz: "That’s more than Sill sends to your iPad: up to 4532 × 2976 at 120 Hz,
   or as many pixels a second at a lower rate." (the iPad mini's), Use This Size disabled; at 30 Hz, taken.
6. **One over this Mac's encoder**: 6016 × 3384 at 60 Hz, no device connected for a moment: the note says what this Mac
   carries ("This Mac streams this at about 38 frames a second." or "… scaled down to 4096 × 2304 …"); it works from the
   iPad. A failure: no picture, or one far slower than the note.
7. **The same desktop on the iPhone after the iPad**: 4096 × 3072, Retina, 120 Hz; the iPad on it, then the iPhone too:
   "Virtual Desktop: 4096×3072 at 120 Hz is more than iPhone (iPhone16,1) takes (1446491520 pixels a second): streaming it
   at 4008×3006.", both showing that picture; the iPhone gone, the full size again. A failure: no line, or a stuttering
   picture.

**Verified in the sixth part** (2026-11-25; nothing made a display, posted input, locked, slept or switched anything, and
nothing used the hardware video encoder: every live run a synthetic test host on 127.0.0.1 with the software encoder, its
Virtual Desktop and its encoder's limits only said; probe P3 built and run with --dry-run only):
- Main brought in: CI on virtual-desktop-2a's merge 18a47362 (run 45498083096) and on this branch's 023201d5 (run
  45498202041) passed every step (the release build, run-all, the iOS app with #393's pane, the CLI). 2a was verified
  through CI alone: main changed no source under Sources/.
- The Virtual Desktop's switch in #393's pane, harness photos of 00f096a2 (`Scripts/harness-photos.sh`): an iPad Pro
  13-inch on its side (on) and upright (off), an iPad mini on its side (on; unpaired: disabled, its warning), a phone
  upright (on) and on its side (off), an SE (unavailable), the Duo flat: the row in the Mac's part after Virtual Display's,
  in the pane's own style, its footnotes under it.
- Part A, pushed and verified before part B began (PART A IS PUSHED AND BUILDS: fbef64e3): the release build 61 s; the
  checks virtual-desktop 110,055, sill-displays 63, viewport-bounds 108, compatibility 200, picture-fit 21, away-quality,
  each 0 failed; their mutants virtual-desktop 274 of 274 (P3 lived on the first try; a pane of fractions of a pixel
  catches it), sill-displays 56 of 56, viewport-bounds 44 of 44 (SC3 changed nothing on its first try), compatibility 52
  of 52, picture-fit 12 of 12. desktop-check 96 of 96 (the iPhone host: made at 589×1189 pixel for pixel, on its side
  after 1 s in place in 650 ms at 1101×589, its controls at once at 1077×448, upright with its controls 800×499, Full
  Screen upright at once at 589×1189; the short-1x host: the make fell back at once to 800×1614 in one line, and a turn
  fell back, then followed 1494×800 1 s later), headless-check 66 of 66, privacy-check 48 of 48. CI on fbef64e3 (run
  45512001157) passed every step.
- Part B (a278ed22, then 458caeb5's case): the release build 52 s, no warning but CaptureProbe's; the CLI's refusals each
  its sentence ("That’s more than Sill sends to iPad Pro 13-inch: up to 5504 × 4128 at 120 Hz, …" for 3840x2160@2:120);
  the checks virtual-desktop 109,597, capture-scale 184, away-quality, sill-displays 63, viewport-bounds 108, compatibility
  200, picture-fit 21, each 0 failed. Mutants: virtual-desktop 321 of 321 (the 286 whose files did not change after
  16629e1a caught there, in two halves; "8K offered" and B6 lived there and are caught by the list's sizes checked within
  the ceiling and a side's bounds said before Retina's evenness; B24 found its pattern twice there, made unique; the 34 of
  VirtualDesktopBudget.swift and "8K offered" at a278ed22, where B33 lived until 458caeb5's case, B28 to B34 7 of 7
  there), capture-scale 57 of 57 (E7 lived first: the side given now not 4096 in its cases), away-quality 82 of 82; of the
  text checks reading the files part B changed (sill-displays, stage-release, away-copy, away-wire, update-install) every
  mutant's pattern found once at a278ed22.
- The gates on a278ed22's CLI: desktop-check 104 of 104, among them the custom host (a size of its own, 5120 × 2880 at
  60 Hz, its encoder said to take 4096 pixels at most and 31 frames a second): its start line and the encoder's note, made
  (said) at its own size, the picture held to 4096 × 2304, an iPhone SE joining at 8 s held to its budget, 3772 × 2120,
  in one line naming it, the encoder's 4096 × 2304 again once it left, never followed; the iPhone host as part A's (on its
  side in 677 ms, its controls in 645 ms, upright with its controls in 665 ms, Full Screen in 343 ms). On 39b76f54 (a278ed22
  changed only the names and when Sill for Mac's list is sent): headless-check 66 of 66, lock-check 42, 4, 6 and 26,
  privacy-check 48 of 48, #396's sound gate 17 of 17, #399's smoke 6 of 6; H2 against main's CLI (d9b3e995's host) one
  right after the other: identical but #395's locked line (8 and 3, 15 and 11, 18 and 11; 11 and 10), as in run 5.
- Sill for Mac's previews from the bare SillMenuBar: 363 files; the ten new are Custom…'s five states (nothing typed,
  within, over, the encoder's note, scaled) in light and dark, looked at; the other 353 byte for byte run 5's.
- Probe P3's build, found after the run (2026-11-25): `p3/run.sh` gave swiftc `probe-phone.swift` under its own name,
  and beside another file swiftc takes top-level code from a file named `main.swift` alone, so the pushed script did not
  build ("expressions are not allowed at the top level") and "built" above was not true of it. It now compiles a copy
  named `main.swift`, as P2b's and P2c's do; `run.sh --build` and `run.sh --dry-run` pass on this Mac (all 17 selectors
  looked up, the four cases listed, nothing made).
