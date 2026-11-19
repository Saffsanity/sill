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
  818bbe86: its test pattern at its size in points, as every test stop's (the verdict had wanted Retina pixels).
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
- Each module typechecked after each commit (`swiftc` of StreamProtocol, SillHostCore, SillHostCLI and SillMenuBar against
  each other, and of the iOS app's sources for the simulator against StreamProtocol): clean, no warning.
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
