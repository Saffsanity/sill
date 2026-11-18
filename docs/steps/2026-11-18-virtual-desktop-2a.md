**A Mac with no working screen: Sill's own display, sized to the device (2026-11-18, branch `virtual-desktop-2a` from
main at 8dbbb50; phase 2a of `docs/virtual-desktop-plan.md` as revised 2026-11-18 (the revision in
`~/Downloads/sill-handoff/next/virtual-desktop/plan.md`); addhumal's PR #200 finished, for #298 and #61).** Noah's words,
2026-11-18: "Work on #200, the option to give Sill its own virtual display (for headless macs or for adding an additional
screen, if so allow the user to select resolution, should default to resolution and refresh of client device, not what
we originally proposed)". This branch is the first of the plan's three pull requests: the display a Mac with no working
screen gets by itself (on by default, Noah on #61, with a switch of its own since the review round below), at the
device's size and rate. The Virtual Desktop (its switch, its stop,
its lifetime, its windows, following a device's turn) is phase 2b, the resolution and refresh choices phase 3; nothing of
either is here, and nothing on the wire.
- How it was built: addhumal's head dad9a911 merged as it is (2d8147a2: his 14 commits, two of them the maintainer fixes of
  2026-11-11, keep their hashes, so GitHub shows #200 merged when this lands, as #173 with #355; nothing pushed to his
  fork); then the four local fixes of 2026-11-12 that were never pushed (`pr200-review-2026-11-11` in `~/Downloads/sill`),
  cherry-picked with `-x`: 0ccd12a `Watch` (the 1 s settle, the 2 s hysteresis; Noah: "I approve the bug fix plan"),
  d79dce2 the live gate, eaa1731 the screens' sleep (the 73-second case), df982a2 its scenarios. Resolved against main's
  #355: the scripted list's variable is `SILL_TEST_HEADLESS` (main's `SILL_TEST_DISPLAYS` is the Desktop stops' hook),
  honoured only by `DoorPolicy.isTestHost`; Tests/checks/README.md's table is frozen, so its rows were not edited and no
  count is written; DisplayWake's declaration keeps main's display and gains `personDeclared()`. On main's tree the gate
  gave 41 of 41, as on 2026-11-12.
- Roles, not the vendor (the assessment's defect 3): `HeadlessDesktopPolicy.Kind` gains `stage` and `gone`, mapped from
  `DesktopDisplays.role` (`HeadlessDisplayKind.swift`; VirtualDisplay.swift stays free of StreamProtocol for
  VirtualDisplayProbe); the Desktop's pool never takes the stage's display or one that has gone; `displayKind` and
  `isStandIn` go.
- The size and rate (Noah's decision; `VirtualDesktopSize`, pure): the panel of the device that asked for the Desktop
  (its pick, or a step), else the one whose viewport came last, in its points at Retina, grown evenly to 800 points on
  the shorter side and held to 4096 (an iPad mini's 1133 × 744 is 1218 × 800), at that device's rate held to 24 and to
  Frame Rate's limit; #200's 1920 × 1080 at 60 when no device has sent its size. Decided once, when it is made; never
  resized (2b follows a device in place). `room` (2b's wire field) is taken when there is one; 2a sends none.
  `lastBuiltInDisplayPoints` is kept for phase 3's "Same as this Mac's screen" and written only by Sill.app (defect 10).
- The Desktop's rate is held to Sill's display's refresh rate, as to a stop's (defect 4): a 120 Hz iPhone beside the 60 Hz
  iPad mini it was made for streams at 60 (`VirtualDesktopSize.refreshHeld`, `streamRate`, `holdDesktopRate`).
- Its line names the mode it came up at, and what was asked when that differs (defect 6): "Headless display: created
  1218×800 pt @2× at 60 Hz (id 66) for iPad mini, its screen."; one that never came up is removed with a line.
- One follower for a display change (defect 7): `followDesktopDisplay(look:)` in place of #355's `followDesktopStop` and
  #200's `desktopFollowsDisplaySize`, judged after its look, so one lid opening restarts the Desktop once.
- The guard for #380 (`DisplayMakeGuard`, pure; open decision 8): Sill.app writes `~/Library/Application
  Support/Sill/making-display` just before it makes any display of its own (the stage's from just before its old display
  goes, since #380's stops came right after "Removed virtual display N"; the Desktop's), synced, and removes it once the
  display is up or failed and at a clean quit (Quit, SIGINT, SIGTERM, SIGHUP); a marker at launch is one stop
  (`displayMakeStops`); two in a row and Sill makes no display by itself (the stage streams windows where they are,
  `VirtualStage.Failure.guarded`; no headless display) until Try Again in Settings › Virtual Display; a display that comes
  up resets the count. The CLI keeps none; TEST ONLY `SILL_TEST_MAKE_GUARD=<folder>` gives a test host one of its own.
- The lock's exception written down (defect 9): `LockPolicy.makesDesktopDisplay` (unlocked and at a locked screen, never
  off console, the off-console view included) beside `Allowed.virtualDisplay`'s doc, and docs/locked-mac-plan.md's table.
  Off console, an existing one is removed at once (plan §2 and §10: it would be the displays of the user on the screen);
  back on the console with no screen it is made again after the return's 2 s.
- Sill.app: the card's source row "Sill’s display · 1218×800" (`Stream.onSillDisplay`, `HostStatusSnapshot.sillDisplay`);
  Settings › Virtual Display's Status shows the guard with Try Again ("Sill stopped twice while making its display, so it
  makes none by itself now."), and a section of its own, "A Mac with no screen": the switch "Make a display when this Mac
  has no screen" (`HostConfig.headlessDisplay`, on by default), a row "Sill’s display" while it exists ("1218 × 800 for
  iPad mini, streaming now", or "…, kept until a screen works" while no device shows it), and its footnote. Previews:
  `pane-virtualDisplay-noscreen`, `pane-virtualDisplay-noscreen-kept`, `pane-virtualDisplay-guard`, `card-sills-display`.
- Wire: nothing. No kind, no field, no hello flag; older devices and Macs are unaffected. A Mac with no screen still sends
  no Desktop stops (Sill's display is no stop), so every device shows today's one-stop button.
- Docs: docs/DEVELOPMENT.md (after the Desktop's stops: what it does, its lines, the guard, the headless hooks; the locked
  Mac's exception), docs/locked-mac-plan.md's row, and the one-line entries in docs/LAYOUT.md and docs/BUILD-AND-RUN.md
  (written into CLAUDE.md's Layout and Build and run, then moved there by `Scripts/migrate-notes.py` when main's #388, the
  lean CLAUDE.md, was merged in: df04c7c8). Not here: the Compatibility floor's kind 47 line (the overview's
  reserve-the-numbers docs change), site/support.html and README (proposed text below).

**Defaults taken for Noah to confirm** (the plan's open decisions, each as recommended, and this branch's own):
1. #200 lands first, alone, as this pull request (open decision 1 (a)): his commits merged as they are, ours on top.
2. Sill's display on a Mac with no screen is the device's size (2 (a)); the built-in screen as last seen is kept only for
   phase 3's choice.
3. "The device's resolution" is, in 2a, the device's panel (the viewport's width and height): `room`, the Full Screen
   room, is 2b's wire field (3 (a) then). A device whose bar shows makes a display of its picture's shape.
4. Small screens grow evenly to 800 points on the shorter side (4 (a)); P1 below decides whether 1133 × 744 may stay.
5. Never resized in 2a, locked or not (6 (a)'s in-place resize comes with 2b's in-place modes, P2).
6. A real screen back: Sill's display goes 2 s later, whatever the lid and the devices (7 (a), 0ccd12a).
7. The guard (8 (a)), and that it also holds the stage's display; Try Again in Settings › Virtual Display.
8. #298's leftover case, a closed-lid monitor switched off but still listed: nothing now (9 (a)).
9. The screens-asleep rules of 11-12 as written (10 (a)): an asleep monitor counts, nothing is made while they sleep, a
   tap on the device is the wake.
10. With no viewport from any device when it is made: 1920 × 1080 at 60 (#200's).
11. Whose size: the device that asked for the Desktop last before it was made (a pick or a step), else the newest
    viewport's; a second device that asks during the settle wins.
12. Off console: removed at once, made again after the return if there is still no screen.
13. A clean quit while a display is being made is no stop; a crash or Force Quit (SIGKILL) is.
14. Sill.app's guard is the bundled app's alone; the bare `SillMenuBar` binary is a test host.
15. The card reads "Sill’s display · 1218×800" (points, `rectangle.dashed`); in 2a its section sits in the Virtual Display
    tab, and 2b's Displays tab takes it.
16. The switch (the review round; Noah, 2026-11-18: "Anything that it would make sense to add a toggle to you should add a
    toggle"): "Make a display when this Mac has no screen", on by default (Noah on #61), the Mac's alone (no device turns
    it), in a section of its own under "Stream from a virtual display", which stays the windows' and does not turn this
    off (#380's workaround on GitHub names only that one). Turned off, Sill's display goes at once and the Desktop moves
    to what macOS shows; turned on, a Desktop streaming with no screen gets it about a second later. The CLI keeps it on (it needs `--virtual-display` anyway) and turns it off with
    `--no-headless-display`, like `--no-clipboard`.
17. Its lifetime as built and now said in Settings: made when a device shows the Desktop, then kept with no device
    connected until a real screen has worked 2 s, the switch is turned off, the session goes off console, or Sill quits
    (plan §1: remaking it is a display change macOS may lock a closed-lid Mac on, addhumal 2026-11-02).

**Proposed words, not written into any page** (for the release that ships it, Sill for Mac 0.6.3 if Noah takes it there;
no device update needed):
- site/support.html, a section "A Mac with no screen", inside a release marker: "When your Mac has no working screen, a
  MacBook with its lid closed and nothing attached or a Mac mini with no monitor, Sill for Mac gives it a display of its
  own when your iPhone or iPad shows the Desktop, the size of your device. You see the login screen and can type your
  password, and the Mac stays unlocked. The display stays after your device disconnects, with any windows you left on
  it, until a real screen works again or you quit Sill for Mac. To turn it off, open Sill for Mac's Settings › Virtual
  Display and turn off Make a display when this Mac has no screen."
- README's Good to know, in one line inside a comment until the release: "A Mac with no working screen gets a display of
  its own, the size of your device, when you stream its Desktop (Settings › Virtual Display turns it off)."
- The release notes: "A Mac with no working screen (a closed MacBook, a Mac mini with no monitor) now gets a display of
  its own when you stream its Desktop, the size of your iPhone or iPad, so its login screen streams and takes your
  password. It is on by default; Settings › Virtual Display turns it off (#298, #61; thanks to addhumal, PR #200)." Noah
  posts on #61 when there is a build to try, as he promised.

**Verified** (on this Mac; nothing made a display, posted input, locked, slept or switched anything):
- The four fixes on main's tree before anything else of ours: `Scripts/headless-check/live.py` 41 of 41 verdicts, as on
  2026-11-12.
- `Tests/checks/virtual-display-api` 282 checks, 79 of 79 mutants (9 new: the kinds by role and the pool's exclusions; the
  gate's guard; the old size rule's 2 gone); `virtual-desktop` (new) 33,194 checks, 54 of 54 mutants; `lock-policy` 1,418
  checks, its 2 new mutants caught and all 192 of its patterns still found exactly once (the whole list is CI's mutants
  job by hand, well over an hour here); `desktop-displays` 140; `repo-rules` 11 of 11.
- `swift build -c release` of the merged tree: no warning. CI's CLI step: `SillHost --internet` exits 2 with "--internet
  needs --remote.", `--print-reachability` exits 0.
- Previews from the bare binary (`.build/release/SillMenuBar -SillRenderPreviews`, which starts no host):
  pane-virtualDisplay-noscreen, pane-virtualDisplay-guard and card-sills-display, light and dark, read as written above.
- `Scripts/headless-check/live.py` on the merged tree: 60 of 60 verdicts, 17 scenarios on loopback test hosts (synthetic,
  the software encoder, no router, no screen, the lock by its file): the 12 of 2026-11-12 as before, and size (an iPad
  mini's 1133×744 at 30 Hz asking on a screenless, locked Mac: "Headless display: created 1218×800 pt @2× at 30 Hz (TEST
  ONLY: none made, SILL_TEST_HEADLESS) for iPad mini, its screen.", the Desktop at 30 fps and not restarted at 60 when an
  iPhone at 60 joined), nosize (1920×1080 at 60, "no device's screen known yet"), guard (two stops: one line for two asks,
  nothing made or waited for, the marker taken, the count 2), guardok (made, the marker gone, the count 0) and offconsole
  (removed 0.06 s after the switch, none made off console, made again 2.1 s after the return).
- `Tests/checks/run-all.sh`: all 75 checks passed, 0 failed (at `nice -n 19`, outside the heavy lock, whose jobs are the
  builds, xcodebuild and harness photos).
- CI's iOS step locally through heavy.sh (Xcode 27.1, Debug, the generic simulator, arm64, unsigned): BUILD SUCCEEDED, only
  the known capture warning in StreamClient.swift; nothing under iOSClient, StreamProtocol or Package.swift differs from
  main. GitHub's CI on #395 (run 44283282836, head f4f2e977): every step of Build and check passed (the release build,
  run-all, the iOS app, the CLI's two paths).
- H2 (the CLI against main's) was not run in the first round, and the claim made in its place was wrong (the review's
  finding 2): two lines this branch adds reach the plain CLI. The `Displays:` line after each `Locked:` and `Unlocked:`
  (plan §2) is in every host, the CLI's included, and "Desktop: the display is W×H pt now (was …); restarting at its
  size." (#200's follower folded into one, defect 7) in every host but a synthetic one. Every other line this branch adds
  is behind a TEST ONLY hook, the AppKit loop (`--virtual-display`) or a display that was made. The idle and client
  comparison, run twice on this branch's CLI, never locked the Mac, so it could not have shown the first.

**Review round (2026-11-18, from 06:00; the reviewer's three findings on #395, each confirmed here):**
1. *No switch, and none put to Noah* (confirmed: `headlessGateAllows` read no setting, so a Mac whose user turned "Stream
   from a virtual display" off, as #380's workaround says, still got "Sill Desktop"; and the no-screen sentence sat in
   the footnote under that switch, as if it governed it). Fixed: `HostConfig.headlessDisplay`, on in `standard` and `app`
   (Noah on #61), the Mac's alone (absent from kinds 16 and 17, `accepted`, `applying`, `restartNeeded`); Sill.app's
   switch "Make a display when this Mac has no screen" in its own section of Settings › Virtual Display, "A Mac with no
   screen", with the row and the footnote; the key `headlessDisplay` (`-headlessDisplay 0` for one run, `-SillSetAfter
   '<s> headlessDisplay=0'`); the CLI's `--no-headless-display`, like `--no-clipboard`; the gate's `switchOn`
   (`needsVirtualDesktop`), its one line when it alone keeps the display from being made, and in `adopt` the switch
   applied at once: off removes the display (`removeHeadlessAtOnce`, which the off-console removal now shares), on asks
   again for a Desktop streaming with no screen. Checked: `virtual-display-api` (the gate with the switch off, the two
   lines; its 2 new mutants caught) and `away-quality` (on in both, its log words, kept by `validated`, never moved by a
   device's change; 4 new mutants, AQ-O1 rewritten for the new `standard` line); the live gate gains `switchoff`
   (written, not yet run: below).
2. *H2 skipped on a false premise* (confirmed: SessionLock prints the `Displays:` line after every `Locked:` and
   `Unlocked:` in every host, the plain CLI too, as plan §2 asks; and `followDesktopDisplay`'s "Desktop: the display is …
   now (was …); restarting at its size." is in every host but a synthetic one, #200's follower folded in). The claim is
   corrected under Verified; `Scripts/desktop-check/live.py` and `Scripts/lock-check/live.py poll start paired view`
   were run, H2 not yet (below).
3. *The words misstate how long it stays* (confirmed: `Watch.release` answers `.keep` while no real screen works, devices
   or not; the screenless scenario of run2 kept it from the client's leaving at 5.06 s to the next one at 7.05 s). Fixed:
   the footnote ("…when a device shows the Desktop… The display stays after the device disconnects, until a screen works
   again, you turn this off, or you quit Sill."), the row ("…, streaming now" only while the Desktop streams on it, else
   "…, kept until a screen works"), the proposed support, README and release words, DEVELOPMENT.md and the snapshot's doc;
   the live gate's new `kept` (3 of 3, below) shows the rule they now describe.

**Verified in the review round** (06:00–07:30; nothing made a display, posted input, locked, slept or switched anything):
- `virtual-display-api` 284 checks, 81 of 81 mutants; `away-quality` all passed, 48 of 48 mutants; `stage-release` 847;
  `Tests/checks/run-all.sh` all 75 passed (576d86cb, at `nice -n 19` outside the heavy lock).
- SillHostCore, SillMenuBar and SillHostCLI typecheck clean (`swiftc -typecheck` against the built StreamProtocol module;
  a planted error in a function body was caught, so it reads the bodies). GitHub's CI on 576d86cb (run 44294273593):
  every step of Build and check passed (the release build, run-all, the iOS app, the CLI's two paths).
- On the pushed head's CLI from before this round (5786e36d's code, built 05:04, snapshotted in the scratchpad; the gates
  and the test client are main's own, unchanged here): `Scripts/desktop-check/live.py` 24 of 24 (`followDesktopDisplay`
  in place of #355's `followDesktopStop`); `Scripts/lock-check/live.py` poll 42 of 42, start 4 of 4, paired 6 of 6, view
  26 of 26 (`notify` left out: it posts a Darwin notification), the `Displays:` line after each `Locked:` and `Unlocked:`
  in their hosts' logs; `Scripts/headless-check/live.py kept` 3 of 3 (made at 2.07 s, the client gone at 6.07 s, kept
  with nobody connected, removed at 14.02 s, 2 s after a monitor came back at 12 s). No host of those two gates has
  Sill's display, so this round's change to `lockChanged` (the shared `removeHeadlessAtOnce`) is off their paths.
- Not run: the release build here, main's `SillHost` for H2, H2 itself (idle, a test client, and locked then unlocked by
  the TEST ONLY lock file, where the `Displays:` line is the one expected difference), the `switchoff` scenario, the
  gates on this round's CLI and the previews of the new section (they need the new SillMenuBar). The heavy lock's turn came at 07:18 after 63 minutes in a queue of fifteen, with 24 GB free
  where the rule's floor is 25, so the job stopped before building (privacy-lock's had too). All of it is one command
  away once the disk allows: `~/Downloads/sill-handoff/tools/heavy.sh "vd-2a: build, main's CLI" --
  ~/Downloads/sill-handoff/next/vd-2a/verify/heavy-job.sh && ~/Downloads/sill-handoff/next/vd-2a/verify/gates-after-build.sh`.

**For Noah** (only he can: each makes a display, locks or switches his Mac, or needs a Mac with no screen; the same list is
in the pull request). Install this branch as a release is built (his grants and pairings kept): `cd ~/Downloads/wt-vd-2a &&
SILL_RELEASE_DRY_RUN=1 SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'
SILL_PROVISION_PROFILE=/Users/noah/Downloads/winstream/Packaging/embedded.provisionprofile Scripts/make-app.sh --release
--install --open`, and watch `grep -E "Headless|Displays:|Locked:|Unlocked:|Woke|Desktop:|Removed virtual display|Sill
stopped|Try Again" ~/Library/Logs/Sill/Sill.log | tail -40`.
1. **P1, the self test at the default sizes**, on a Mac at rest (Sill.app quit, no device connected, nothing streaming; each
   run makes a display for a moment and moves the pointer onto it and back): `swift build -c release && for a in "60
   1218x800" "120 1376x1032" "120 1496x800" "60 1133x744"; do .build/release/SillHost --virtual-display-selftest $a; done`.
   Each should say "online at requested mode: true", its bounds at the size asked and "@2×", and "current mode refresh:" the
   rate asked. The last decides open decision 4: at 2x, a device's own points could be made as they are, without the 800.
2. **Lid open: nothing changes.** Connect the iPad; `pmset displaysleepnow`, wait 30 s, connect again; ⌃⌘Q and the password
   on the iPad. No `Headless display` line anywhere.
3. **Lid closed, monitors on:** no `Headless display` line; the Desktop button steps the two monitors; ⌃⌘Q and the password:
   unlocked, and still after 30 s.
4. **Lid closed, an account switch** with the iPad on the Desktop: wait 30 s, come back. `looking again …` then `a real screen
   works again; none made`, and no "Sill Desktop" in System Settings › Displays.
5. **Lid closed, the screens asleep** (the 73-second case): lock with the iPad on the Desktop and touch nothing for 40 s: `the
   2 screens are asleep, not gone; none made`, and no `created`. Tap the iPad's picture: the monitors light, the lock screen is
   on the iPad within 1–2 s (`Woke the display for …`), and the password works. Then 2 minutes: nothing new.
6. **No display attached, lid closed** (the #61 case; this MacBook Pro may not reach it: on 11-12 its built-in screen stayed
   working with the lid closed and `disablesleep`): lid open, unplug both monitors, `sudo pmset -a disablesleep 1`, ⌃⌘Q,
   close the lid, wait 10 s, connect from the iPad mini, and read the `Displays:` line. If it shows a stand-in or nothing
   working: `Headless display: created 1218×800 pt @2× at 60 Hz (id N) for iPad …, its screen.`; the lock screen with its
   password field fills the iPad; the password sticks 30 s; disconnect and reconnect twice: no second `created`, no relock;
   the iPhone instead while locked: the same display, its stream at 60 fps (`Streaming … 60 fps`), not 120; the card reads
   "Sill’s display · 1218×800" and Settings › Virtual Display's row "Sill’s display" "1218 × 800 for iPad …, streaming
   now"; disconnect every device: the row reads "…, kept until a screen works" and System Settings › Displays still lists
   Sill Desktop; open the lid: `a display is online again; removed …` about 2 s later, the windows on the built-in screen,
   one `Desktop:` restart.
   If the built-in still reads working, this Mac cannot reach the case: go to 8. Undo: `sudo pmset -a disablesleep 0`.
7. **Lid closed, cables pulled one at a time:** with the Desktop on the Dell, unplug it: the Desktop on the Lenovo, no
   `Headless` line; unplug the Lenovo too: `looking again …`, then `created …` at the iPad's shape (the Mac may sleep unless
   `disablesleep` is on); plug one back: removed about 2 s after it works, the Desktop on it, no relock.
8. **A Mac with no monitor at all** (a Mac mini or Studio, his or a #298 reporter's, with a nightly): connect: the lock screen at
   the device's shape, the password sticks; an iPhone after the iPad: the same display; switch to another account and back:
   `this session is off the console; removed Sill's display …`, then made again about 2 s after the return; Quit Sill: the
   display goes.
9. **#357's watch during 6 to 8:** with Virtual Display on while Sill's display exists, pick a still window (System
   Settings): a picture, not black; the `[1s]` lines' `cap.idle` high and `cap.complete` low.
10. **The guard for #380, without a crash:** Sill quit, then `mkdir -p ~/Library/Application\ Support/Sill && printf 'stage
    2026-11-18T12:00:00Z\n' > ~/Library/Application\ Support/Sill/making-display && defaults write me.saffer.sill.mac
    displayMakeStops -int 1`, and open Sill. Sill.log: `Sill stopped while making a display last time (2 runs in a row: its
    window display, 2026-11-18T12:00:00Z); it makes none by itself until you choose Try Again in Settings › Virtual Display.`
    Settings › Virtual Display's Status: "Sill stopped twice while making its display, so it makes none by itself now." with
    Try Again; a window picked from the iPad streams where it is (the card: "real window (virtual display: Sill stopped twice
    while making its display)"). Try Again: `Displays: Try Again chosen; Sill makes its displays again.`, the next pick is
    staged as before, and `defaults read me.saffer.sill.mac displayMakeStops` says 0.
11. **The switch** (in 6 or 8, while Sill's display shows the Desktop): turn off Settings › Virtual Display › "Make a
    display when this Mac has no screen": `Settings: headless display on → off`, `Headless display: turned off in
    Settings; removed Sill's display.`, then, as the Desktop starts again on what macOS shows (its 1x stand-in),
    `Headless display: no real screen, but Sill's display for a Mac with no screen is turned off; none made.` once; the
    row gone, nothing named Sill Desktop in System Settings › Displays, and `defaults read me.saffer.sill.mac
    headlessDisplay` says 0. Turn it on: `looking again in 1.0 s …`, then `created …`, and the default says 1.
