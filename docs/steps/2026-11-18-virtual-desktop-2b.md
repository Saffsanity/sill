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
- Pending at the time of writing: the heavy lock's second turn (the release build here, the mutants of compatibility,
  viewport-bounds, away-quality, desktop-displays and lock-policy's new one, run-all), then the live gates and H2.
