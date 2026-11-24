**Privacy, part 2: this Mac's screens dark while a device uses it, built for real in Sill.app from Noah's probe G0 of 2026-11-23 (2026-11-18, branch `privacy-darken` from `privacy-lock` at 4d6a470, which is main at 8dbbb50 with #184 and part 1; main merged in since, last at 5d062a3c with #402, #389 and #418).**

docs/privacy-mode-plan.md (part 2: rules 2–5, 7–9, 11–14; G0) and docs/privacy-mode-assessment.md. Part 1, the lock when
the last device leaves, is the branch `privacy-lock` underneath this one; this branch's pull request is based on it, so
its diff is part 2 alone. Noah, 2026-11-18: "Privacy mode options (blank local display when remote access is being
used)"; #323: "as a toggle".

- **G0, the probe** (`Scripts/privacy-probe/`, TEST ONLY, Noah's to run: it darkens the screen in spells of at most
  10 s, each under a hard 12 s kill from the shell). `run.sh` builds `probe.swift` (AppKit and ScreenCaptureKit, no
  encoder) and `window.swift` (the test window's app, me.saffer.sill.privacyprobe), then: step 1, the test window, a
  Safari video and an Electron window captured uncovered and under S1 (opaque, .screenSaver, #184's), S2 (not opaque,
  .screenSaver), S3 (opaque, shielding) and S4 (opaque, 1500); step 2, the window server's list while Noah locks, gets
  a notification, presses the volume keys, ⌘Space, F3, ⌥⌘⎋ and moves the pointer; step 3, kill -9 and a stopped
  probe; step 4, a tagged and an untagged posted event and Noah's own through NSEvent's global monitor; step 5, black
  on every screen. His answers go into the report with the measurements. Only `check` (read-only) and `gone` were run
  here; `--build-only` compiles both without running anything. His instructions: sill-handoff's
  next/privacy-darken/PROBE-FOR-NOAH.md.
- **What G0's answers choose**, and nothing else: the black windows' level and opacity (step 1: if S1 freezes what it
  covers and S2 does not, S2; if both freeze, the plan's open decision 10, a note in Settings; step 2: the lowest level
  that every notification, HUD, Spotlight, Mission Control and Force Quit stays behind); `DarkenPolicy
  .staysUnderLockScreen` (step 2: whether the lock screen sits in front of that level); how Sill's own posted events
  are told apart (step 4: `eventTag` in `CGEventSource.userData` if NSEvent's global monitor keeps it, else the source
  pid); whether the watchdog matters as planned (step 3: a stopped process keeps its windows). Each fills one seam of
  `PrivacyScreen` or flips one constant; the rule and its check stay as they are.
- **The rule, `DarkenPolicy`** (pure, `Tests/checks/darken`): which sessions darken (off, only away, whenever: rule 2);
  dark while one is connected, a screen to cover, not quitting, not taken back (rule 3); `raise` returned from the
  session count at the connect, which the coordinator calls before `deviceActive(.connect)` (rule 5); the 30 s wait
  after the last one leaves, a return within it, and, when that same departure started the lock's wait (no session
  left, part 1's switch on), the dark held while the lock is under way (part 1's `pending`, read from HostStatus), never
  past the wait + 3 s + 1 s (rule 6); under the lock screen, or the fallback down at a lock and up at an unlock (rule 4);
  a key or click on the dark, unlocked Mac locking it (once per 3 s; unconfirmed or unavailable: the ⌃⌘Q hint and no
  more key locks until a lock shows or a switch changes), the pointer only showing the hint, Sill's own events nothing
  (rule 7); taken back by the Mac's own unlock, the device's unlock (its input at the locked screen in the 10 s before)
  keeping the dark (rule 8); the switches (rule 9); a quit (rule 11); the watchdog's decisions (rule 12); the screens
  through DesktopDisplays.role (rule 13); who darkens (rule 14, `darkensForReal`: Sill.app itself alone, the lock's own
  rule `PrivacyPolicy.locksForReal`; `heldBack` until G0 fills Sill.app's seams); its TEST ONLY hooks and every word.
- **The code up to the seam, `PrivacyScreen`** (main actor): the rule's state and tick; the screens (CoreGraphics'
  online displays through `DarkenPolicy.screens`, or a test host's SILL_TEST_PRIVACY_DISPLAYS); its lock through its
  own `ScreenLocker` (part 1's, a dry run anywhere but in Sill.app itself); `HostStatus.privacyDark`. Two seams:
  `Curtain` (raise, lift, hint) and `LocalInput` (the Mac's own keys, clicks and pointer, only while dark). Everywhere
  but in Sill.app itself (`real` false: the CLI, the bare SillMenuBar binary, every test host) `DryCurtain` says what it
  would draw ("Privacy (dry run): would darken 1 display; nothing is drawn.", `priv.raise`, `priv.lift`, `priv.hint`)
  and a test host's `FileInput` reads the Mac's "own" input from SILL_TEST_PRIVACY_INPUT (`priv.localDry`). In Sill.app
  both are empty, so darkening stays off there whatever the config says (`heldBack`; one line if it is ever on).
- **The coordinator**: `darkenSessions()` (the routes, cut-off ones left out, away and at home) after `routesChanged` at
  a connect and before `deviceActive(.connect)`, and at a departure; `darken.readingChanged()` in `lockChanged`;
  `darken.deviceInputAtLockedScreen` where the lock takes a paired session's input at a locked screen;
  `darken.switched` in `setTarget`; `darken.quit()` in `shutdownForExit`, `releaseKeysForExit` and `quitBegins`; the
  start lines; under SILL_TEST_PRIVACY_LOG the connect's `disp.wakeDry` stamped beside the dry curtain's line.
- **HostConfig** `darkenScreen` (`.off`, `.away`, `.any`; off in `standard` and `app`) and `darkenKeysLock` (on), the
  Mac's alone, named in `changes(to:)`, never moved by a device (away-quality AQ-D1..9). **The CLI**: `--darken=away|any`
  and `--darken-keys=lock|pass`, with `--synthetic` only (a dry run), otherwise one line each; stdout unchanged without
  them. **TestHooks**: SILL_TEST_PRIVACY_INPUT, SILL_TEST_PRIVACY_LOG. **Sill.app**: no switch yet (HostSettings passes
  `.off`); Settings › Devices gets its section once the seams are filled.
- **Verified, 2026-11-18** (the first run, then the merge of part 1's review at e39eceb5, whose hold's logs are in
  sill-handoff's next/privacy-darken/logs): the darken check (202 checks, among them 20,000 random sessions running
  this rule beside part 1's against nine invariants; 91 of 91 mutants caught in the first run, the equivalent ones
  named in its mutants.py); away-quality with the new knobs (58 of 58 mutants in the first run, AQ-D1..9 new; the merge
  brought part 1's review's 9, so the check has 67 since, run in run 3 below); stage-release and repo-rules;
  `Tests/checks/run-all.sh` (all passed, 662 s); typecheck of SillHostCore, the CLI and Sill.app; the probe compiled
  (`--build-only`); `swift build -c release` (58.83 s, through heavy.sh; the first run's took 62 s);
  `Scripts/privacy-check/live.py OUT all`, part 1's, 48 of 48; `Scripts/privacy-check/darken.py OUT all` on loopback,
  25 of 25 verdicts (order: the black up at 1.039 s, the wake counted after it in the same turn; home; away at the
  remote door from a relay on this Mac, and at home by address; wait, lit 3.1 s after the last departure; keys; pass;
  takeback, lit at the settled unlock; hold, lit 0.52 s after the lock's outcome; quit). H2 was not run then.
- **The review of #400 (run 3, 2026-11-19)**, its three follow-ups:
  1. *Who darkens.* Darkening chose its dry run by `dry: synthetic`, so the bare SillMenuBar binary (whose previews
     any agent runs) would have had a real curtain, input watch and locker once G0 filled the seams; it was harmless
     only because darkening is held off outside a test host until then. The policy now decides it as the lock does:
     `DarkenPolicy.darkensForReal(synthetic:bundled:)` is `PrivacyPolicy.locksForReal` (Sill.app itself alone, never
     with `--synthetic`), which the coordinator passes to PrivacyScreen as `real`, and `DarkenPolicy.heldBack(real:
     filled:)` keeps Sill.app off until its seams are filled (a dry run never). Everything else prints the dry run's
     lines, now "Privacy (dry run): …" like the lock's (they said "(test host)"), and its start line says "A dry run
     here (only Sill.app itself darkens a Mac’s screen)"; the start and probe lines moved into DarkenPolicy.Words. The
     check: the four ways a host runs, each against the lock's rule, the hold-back and the words, with 10 mutants;
     darken.py reads the new words, and its home case checks the start line's dry run sentence.
  2. *Both rules together.* The check ran the lock's rule with its switch alone. Now 11 scripted cases run both (its
     `Pair`: the server's callback order, setTarget's, both rules' ticks) with part 1's three switches and each
     session's route: a visit away and one at home under Only after a device away from home, a device away that left
     first, a device at home left behind, a move home, a device at home joining during the waits, the lock's switch
     turned on or off and only away turned on during them, the display left on, the lock off. The random model gives
     the lock its three switches (random, and switched) and each session's route (`joined(away:)` after its count, in
     the server's order); I8's departure is the one whose wait the lock's own line says started; new I10, a hold begins
     only for a departure that left no session with the lock on (nothing since ending that) while the lock is under
     way. 7 more mutants: the dark's copy of the lock's switch (2), and PrivacyPolicy.swift's switches and route as the
     scripted cases see them (5). The model reaches 1,266 holds begun (374 under only away), 1,328 visits at home the
     lock let go, 63 lock waits only away ended and 296 locks with the display left on.
  3. *The numbers.* The bullet above said away-quality's mutants were 58 of 58, the release build 62 s and darken.py's
     order 1.006 s: the first run's. The merge's hold (logs/) says 58.83 s and 1.039 s, and since the merge
     away-quality has 67 mutants (part 1's review's 9 with them), run below.
- **Verified in run 3** (at f4bcb5f3, in one hold of heavy.sh's slot B, 2026-11-19 08:31 to 09:49; logs in
  sill-handoff's next/privacy-darken/run3/logs): `swift build -c release` (59.77 s); typecheck of SillHostCore, the CLI
  and Sill.app; the darken check (258 checks, 0 failed) and its mutants, 108 of 108 caught (1,916 s); privacy (217
  checks) and its mutants, 87 of 87 (1,339 s); away-quality (183 checks) and its mutants, 67 of 67 (233 s, AQ-D1..9
  among them); `Scripts/privacy-check/live.py OUT all` 48 of 48; `Scripts/privacy-check/darken.py OUT all` 26 of 26
  (order: the black up at 1.013 s, before the wake in the same turn; the start line's dry run sentence; lit 3.11 s after
  the last departure; a key's lock unconfirmed 3.05 s later, then the ⌃⌘Q hint; the Mac's own unlock at 8.06 s; hold,
  lit 0.52 s after the lock's outcome); H2, this build's CLI against privacy-lock's own release SillHost (built from
  c3b5b96b, whose code privacy-lock still has) in the same hold, idle 45 s and a test client on the Desktop 30 s, no new
  flag: the same output (9 and 34 lines each, every other line identical with digits masked, the per-second statistics
  the same 7 names; run3/h2.py); `Tests/checks/run-all.sh` (all 76 pure checks passed, 693 s); CI green at f4bcb5f3
  (run 44534158115).
- **Docs**: one entry each in docs/LAYOUT.md (DarkenPolicy and PrivacyScreen; the probe and darken.py) and
  docs/BUILD-AND-RUN.md (the probe's command; the dry run), carried there from CLAUDE.md by `Scripts/migrate-notes.py`
  when `privacy-lock` took main's #388 and was merged in here (a34c675d). Run 4 adds PrivacyCurtain and PrivacyWatchdog to
  docs/LAYOUT.md, the stall hook and the three keys to docs/BUILD-AND-RUN.md, and G0's results to the plan.
- **Defaults taken in runs 1 to 3** (the two about G0 superseded by run 4's, below): the plan's recommendations for its open decisions; the
  black under the lock screen until G0; one key's lock may hold the dark up to 3 s past the wait; a failed key lock
  stops key locks until a lock shows or a switch changes; a change of scope lifts at once, a move home under "only away"
  waits 30 s; the hint at most once a second; no Settings switch until G0 (one that darkens nothing would mislead); the
  dry run's lines begin "Privacy (dry run):" like the lock's (run 3); with only away and a device at home left behind,
  the screen is lit 30 s after the last device away leaves and the lock comes 30 s after the one at home does, and with
  part 1's only after a device away and a visit at home alone, whenever ends lit at its wait with no lock (rule 6 as
  planned, now checked with both rules together).
- **Not yet after run 3** (run 4 below built all of it but the away case from a real distance, rule 6's "not taken
  back" in part 1's lock and the site's words): the real `Curtain` (the windows at G0's level and opacity, the hint view, the
  re-sync at display changes) and `LocalInput` (NSEvent's monitors), InputInjector's tag, the watchdog
  (`PrivacyWatchdog`, SILL_TEST_PRIVACY_STALL), Settings › Devices' section and previews, Sill.app's App Nap hold on
  `privacyDark`, the remote door's away case live, rule 6's "not taken back" in part 1's lock (a Mac its owner took
  back still locks 30 s after the last device leaves: one input to PrivacyPolicy, coordinated with `privacy-lock`),
  docs and the site.
- **Proposed words of runs 1 to 3** (run 4's, below, replace them): What's New: "Privacy: keep your Mac’s
  screen dark while you use it from afar, and lock it when someone touches it (Settings › Devices)." Support:
  "Keep your Mac’s screen dark while you use it from afar. In Sill on the Mac, Settings › Devices: turn on Darken this
  Mac’s screen. While your iPhone or iPad uses the Mac from away (or whenever one is connected, if you choose), every
  display of the Mac is black, and a key or click on the Mac locks it." and "If your Mac’s screen stays black: press
  any key; the Mac locks, and your password or Touch ID brings it back." Privacy page: "While Darken this Mac’s screen
  is on and the screen is dark, Sill for Mac notices whether a key is pressed or the mouse is used on the Mac itself,
  only to lock it. It reads no key and keeps or sends nothing of it."
- **Run 4 (2026-11-23): Noah ran the probe G0, and darkening is built for real.** He ran it in Terminal.app at 15:19
  on his Mac14,9 (macOS 27.2.1; the report is sill-handoff's next/privacy-darken/probe-report.txt, whose first ten lines
  are a refused run at 15:14, before Terminal had Accessibility). What it measured, checked line by line against the
  report:
  - *Step 1, covered windows.* Under all four covers (S1 opaque at the screen saver's level 1000, #184's; S2 not opaque
    at 1000; S3 opaque at the shielding level 2147483628; S4 opaque at 1500) the probe's test window, a Safari window
    playing a video and an Electron app's window kept drawing at 99 to 101 % of their uncovered rate, macOS still
    called the test window 100 % visible, and the captures, the Desktop's with the black left out among them, stayed at
    57 to 58 frames a second. So the black freezes nothing on this Mac, the level costs nothing, and the plan's note
    for frozen apps is not needed (its risk 1 did not happen).
  - *Step 2, what shows in front (all at 1000).* Spell 1: loginwindow's lock screen came in front (layers 2001 and 2004,
    from 2.1 s to 4.5 s) and Noah wrote "When I clicked Control-Command-Q it brought me to regular lock screen. When I
    logged in it still showed the black screen with the text for a little then eventually went away." Behind the black,
    and unseen by him: a notification (Notification Center, layer 23: "No"), the volume indicator (layer 101, and another
    app's own indicator at 23: "No"), Spotlight (layer 23: "No"), Mission Control (layers 2 to 20: "Only black") and the
    Force Quit window (loginwindow, layer 996: "No"). The pointer showed on the black ("Yes"). Another app's window
    (1×1 pt, transparent) at the same layer 1000 was listed in front of the black for the whole of spell 3 (0.0 to
    8.9 s), when that app showed its own volume indicator: two windows at one level stack by who ordered last.
  - *The "IN FRONT … from 0.0 s to 0.0 s" lines* (every ordinary window, at layers far below 1000, in every spell): the
    probe's first sample, taken before the window server listed the black window. Its source took every window as in
    front when none of the black windows was listed (`frontmost` was `Int.max`) and never touched a window again once it
    was behind. So it is so; fixed in probe.swift (a sample without the black windows listed judges nothing).
  - *Step 3, killed or frozen.* After `kill -9` the black windows were gone in 14 and 16 ms; a stopped probe's stayed
    listed and the screen stayed black until the kill ("Yes", "Yes and yes"). Only the end of the process lifts a hung
    Sill's black: the watchdog is needed.
  - *Step 4, whose input.* NSEvent's global monitor kept the tag (0x53494C4C50525631) on the posted pointer move and
    Shift, and an untagged post carried 0; the posted events named the probe's own process as their source, and Noah's
    own pointer move process 0 with no tag. His own Shift press is not in the report (only the move is), so whether a
    person's key reaches the monitor on this Mac is not shown by G0; a click (a mouse event) is.
  - *Step 5, black.* With "All the above" set up (Night Shift, True Tone, an HDR video, a monitor or Sidecar), two
    screens went black and "Every screen was pure black". The report does not say which second screen it was.
  - *The script's own fault.* zsh's `print` took each heading that begins with "-" for its options ("print:93: bad
    option: -" at lines 93, 110, 135, 162 and 169), so those five headings were lost. Every print in run.sh is now
    `print -r --` (the rest were harmless, but an answer typed with a backslash would have been read as an escape).
- **What G0 decided** (each a constant in DarkenPolicy, checked):
  - *The level, 1501* (`windowLevel`, `levelFits`): above everything spell 1 to 7 saw stay hidden (996 at most), above
    1000 (the screen saver's level, where another app's window can be ordered in front of the black) and above 1500
    (kCGAssistiveTechHighWindowLevel, the highest level macOS names under its lock screen, which assistive windows such
    as spoken text's captions share), so no window of a named level ties with the black; and 500 under the lock screen's
    2001, so a person at the Mac always sees it. Step 1 measured no cost at 1000, 1500 or the shielding level, so a level
    between costs nothing either (inferred: 1501 itself was not a candidate; the probe's new S5 re-runs a step at it).
  - *Opaque*, #184's (`windowOpaque`): S2 drew no differently, and step 5 was pure black opaque.
  - *Under the lock screen* (`staysUnderLockScreen` stays true): the lock screen came in front at 1000, and 1501 is
    still under it. The fallback stays in the rule, checked, for a macOS that moves its lock screen.
  - *Sill's own input* (`ownEvent`): an event is Sill's when it carries the tag (InputInjector's source now sets it on
    every event it posts) or names Sill's own process as its source; a person's hardware (process 0, no tag) and other
    apps' events are a person's. Either one alone would do on G0's numbers; both keep a device's input from ever locking
    the Mac.
  - *The hint* now says "Press any key or click to lock it.": a click always reaches the observer, while a focused
    password field and Terminal's Secure Keyboard Entry withhold keys from every observer, and G0 did not see a person's
    key.
- **Built** (Sill.app itself only: `DarkenPolicy.darkensForReal`, the lock's rule; the CLI, the bare SillMenuBar binary
  and every test host keep the dry run, and the pre-G0 hold-back `heldBack` and its line are gone):
  - `PrivacyCurtain.swift`: `WindowCurtain`, one black window per screen (#184's recipe as the probe made it:
    borderless, black, opaque, no shadow, ignoring the mouse, on every Space and beside full-screen windows, stationary,
    out of the window cycle) at level 1501, plus never hidden with Sill (`canHide` false: Hide Others in another app
    leaves it up), no animation, out of the Window menu; ordered in by `raise` in the connect's own turn, before the wake;
    re-synced at each display change, a new screen's window in before an old one goes, framed from CoreGraphics' bounds
    as soon as the reconfiguration callback runs. `CurtainView`: black, and the hint's two lines in the middle (15 pt, 35 %
    white) for 10 s, faded. `MonitorInput`: NSEvent's global and local monitors for key downs, button downs, moves, drags
    and scrolls (`watchedEventTypes`, `localKind`), each telling the rule its kind and whether it is Sill's, never a key
    code or a character. `DisplayChanges`: the reconfiguration callback and AppKit's screen notification, while
    darkening is on.
  - `PrivacyWatchdog.swift` (rule 12): while the black is up the main actor beats once a second; a timer on
    `sill.privacy.watchdog` looks once a second on a clock that stops while the Mac sleeps. Ten seconds without a beat:
    the line, the log flushed, Sill opened again with `open -n -g` on its own bundle (at most once in 10 minutes, kept in
    ~/Library/Application Support/Sill/privacy-watchdog, which the next launch reads for its line), then `_exit(70)`,
    with a second `_exit` 2 s later in case the line or the log is what hangs. A test host's dry run says so and goes on;
    `SILL_TEST_PRIVACY_STALL=<s>` stops a test host's main thread once, a second after the black first goes up.
  - Settings › Devices, before Lock this Mac when the last device leaves: **Darken this Mac's screen** (off), and under
    it while on **Only while a device is away from home** (on) and **A key or click on this Mac locks it** (on), with
    Accessibility's warning while keys lock and Sill lacks it, and a footnote for each state (`DarkenPolicy.Words`).
    Saved as `darkenScreen`, `darkenOnlyAway` and `darkenKeysLock` in me.saffer.sill.mac (the scope kept while off:
    `DarkenPolicy.scope`); the bare binary's `-SillSetAfter` takes `darkenScreen=off|away|any` and `darkenKeysLock`.
    No device sets them, as before (absent from everything a device sends).
  - Sill.app holds App Nap off while the black is up with no device left (the wait, the hold), so the ticks and the
    watchdog's beats keep their time; with a device connected its own hold already does.
  - The probe: `print -r --`, the first sample, and S5 (opaque at 1501, Sill's level) for `--candidate S5`.
- **Every way the black ends** (none of them needs Sill's menu or Settings, which the black covers):
  1. *The last device leaves*: 30 s later it lifts (`grace`, the lock's). If Lock this Mac when the last device leaves
     is on and the same departure started its wait, the black holds until the lock's outcome, at most 30 + 3 + 1 s after
     the departure, so the room sees the lock screen and never the desktop. A device back within the 30 s keeps it dark.
  2. *The switch is turned off*: lit at once (rule 9), from Settings › Devices on the Mac (under the black: with keys
     passing, a click where the switch is reaches it; a device never sees Sill's own windows, which every capture
     leaves out).
  3. *Sill quits* (its Quit, a logout, a restart, an update's install, SIGTERM): lit at once (rule 11), before the quit
     goes on, and the windows go with the process anyway.
  4. *Sill crashes or is force-quit*: the window server removes a dead process's windows (G0: 14 and 16 ms).
  5. *Sill freezes*: the watchdog ends it 10 to 11 s after the main thread stops answering, and reopens it once in 10
     minutes. A process stopped whole (`kill -STOP`, a debugger) stops its watchdog too: nothing in Sill does that.
  6. *The Mac locks* (a key or click with keys locking, ⌃⌘Q, the screen saver, a device's Lock Screen): the black stays
     under the lock screen (spell 1), which shows above it. An unlock at the Mac itself (password, Touch ID, a Watch)
     takes it back: lit about 2 s later (the gate's settle) and kept lit until every device has left (rule 8). An unlock
     typed from a paired device keeps it dark.
  7. *The Mac sleeps*: the windows stay; at the wake the lock screen (if the Mac asks for its password) shows over them.
     A device that dropped during the sleep starts the 30 s wait (a clock that counts the sleep, so it may end at the
     first tick after the wake); one that comes back keeps it dark. A sleep is no hang for the watchdog (its clock stops).
  8. *Another user takes the screen* (fast user switching, the login window): this account's windows are not on the
     screen at all; coming back with the password at the Mac is the Mac's own unlock: lit.
  9. *A display is added or removed while dark*: the new one gets its black window as soon as macOS reports the change
     (its picture shows until then, a moment, not measured); a removed one's window goes; with no screen left the rule
     lifts ("no screen to darken") and darkens again when one returns, from the same watch.
- **If the screen stays black** (for the step file's readers and Noah), in order:
  1. Wait 35 seconds after the last device left (the 30 s wait, the lock's 3 s confirmation and a second).
  2. Press any key or click (with A key or click on this Mac locks it on), or press Control-Command-Q (macOS's own
     lock, which works whatever Sill does): the lock screen shows over the black. Unlock it with Touch ID or your
     password: about 2 seconds later the screens light, and stay lit until every device has left.
  3. Still black 15 seconds after the unlock: Sill has stopped answering, and its watchdog quits it (the black goes with
     it) and opens it again; wait those 15 seconds.
  4. Still black: quit Sill. A device that still shows the Mac can open Terminal on it (a device never sees Sill's own
     menu or windows: every capture leaves them out) and run `osascript -e 'quit app "Sill"'`, or `killall -9 Sill` if
     that does nothing; so can another Mac or an SSH session. The black goes at once with the process.
  5. Last resort: hold the power button to turn the Mac off; nothing of the black survives a restart.
- **Known visible behaviour, each a default or a question for Noah:** the pointer shows and moves on the black (hiding
  it while Sill is in the background needs a private window-server property: not built; the plan's open decision 14
  recommends shown); the Mac's speakers keep playing the session's sound (open decision 13: unchanged in this version);
  a key on the dark Mac while a password field or Secure Keyboard Entry has the keyboard is not noticed (it goes to that
  field; a click still locks); the key or click that locks still reaches the app under it (an observer cannot stop it,
  open decision 3); the black lifts 2 s after an unlock at the Mac, not at once (open decision 8's settled unlock); a
  display plugged in while dark shows its picture until its window is in; the pairing window, Settings and Sill's menu
  are under the black, so a new device pairs only after the Mac is taken back; a window another app puts above 1501 (an
  overlay at the shielding level) would show over the black (none in G0); a main-thread stall of 10 s while dark (a
  slow answer to a keychain prompt, or Accessibility waiting on an app that hangs while Sill sizes its window:
  WindowSizer is the main actor's) ends Sill and reopens it; a Touch Bar keeps the front app's controls, and VoiceOver
  started at the Mac with keys passing reads the covered windows aloud (the plan's small leaks).
- **Defaults taken in run 4** (the pull request lists them for Noah): level 1501, opaque; the black under the lock
  screen, lit 2 s after an unlock at the Mac; Sill's own input by its tag or its own process; the hint's "Press any key
  or click to lock it."; moving, dragging and scrolling only show the hint, a modifier key alone does nothing; Only
  while a device is away from home a switch (on) under Darken this Mac's screen, not the plan's picker, like #402's Only
  after a device away from home; the section just before #402's in Settings › Devices, with no header (as #402's); the
  pointer shown (open decision 14); the speakers unchanged (13); the watchdog's 10 s, and one reopening in 10 minutes
  (9); Accessibility's warning only while keys lock; the earlier runs' defaults above, but for their two about G0.
- **Noah's trial** (only on his Mac, with a test build of Sill.app from this branch installed as his test builds are;
  the pull request has the same steps). What it does, in plain words: while an iPhone or iPad uses the Mac, every screen
  of the Mac is black, so nobody near it sees anything; a key or click on the Mac locks it; 30 seconds after the last
  device leaves, the screens come back. Shortest first; the first is safe and takes a minute, each later one tries one
  way out of the black:
  1. With no device connected, Settings › Devices: turn on Darken this Mac's screen, turn off Only while a device is
     away from home (at home a device is not away), and turn off Lock this Mac when the last device leaves for now.
     Connect the iPad: every screen of the Mac turns black within 2 seconds, before the iPad shows the Mac, with "This
     Mac is in use from another device. Press any key or click to lock it." for 10 seconds; the iPad shows the Mac as
     always. Close Sill on the iPad: about 30 seconds later the Mac's screens come back.
  2. Turn off A key or click on this Mac locks it and leave Settings › Devices open in front on the Mac. Connect again
     (black), and click on the Mac where the Darken this Mac's screen switch is (the click reaches Settings under the
     black; a device never sees Sill's own windows): lit at once. Turn it on again: black. (The switch.)
  3. With the iPad connected (black), from the iPad open Terminal on the Mac and run `osascript -e 'quit app "Sill"'`:
     lit at once (the iPad's session ends). Open Sill again. (Sill quits.)
  4. Connect again (black); from the iPad, in Terminal on the Mac, run `killall -9 Sill`: lit at once. Open Sill again.
     (Sill crashes.)
  5. Keys still passing; connect again (black). On the Mac press Command-Space, F3 and the volume keys: nothing shows
     over the black (G0 saw that at 1000; Sill's 1501 is above it). Press Control-Command-Q: the lock screen over the
     black; unlock at the Mac: lit about 2 seconds later. Close Sill on the iPad. (macOS's own lock; the Mac's own
     unlock.)
  6. Turn A key or click on this Mac locks it on again. Connect (black) and press a letter key on the Mac: the lock
     screen shows over the black; unlock with Touch ID: lit about 2 seconds later, and lit while the iPad stays. Close
     Sill on the iPad, connect again, and do it with a click. (A key or click locks.)
  7. Black: plug a monitor in, then out (or connect Sidecar): the new screen turns black within a moment (say how long
     its picture showed first); the others stay black. (A display while dark.)
  8. Black: from the iPad put the Mac to sleep (Apple menu › Sleep), wake it at the Mac and unlock there: lit. Then
     switch to another user from the lock screen and back with the password: lit. (Sleep; another user.)
  9. From away: turn Only while a device is away from home back on; connect the iPhone through Tailscale: black; at home
     on Wi-Fi: nothing. Turn Lock this Mac when the last device leaves on and close Sill on the iPhone: the black holds
     30 seconds, then the lock screen shows and the display sleeps.
  A frozen Sill (the watchdog) cannot be tried without a debugger, which this Mac must not run: its dry run is checked on
  a test host. If the screen ever stays black: the list above, "If the screen stays black".
- **Proposed words** (for the release that ships it; not in any published page). What's New: "Privacy: keep your Mac’s
  screens black while you use it from afar, and lock it when someone touches it (Settings › Devices)." Support: "Keep
  your Mac’s screen dark while you use it from afar. In Sill on the Mac, Settings › Devices: turn on Darken this Mac’s
  screen. While your iPhone or iPad uses the Mac from away from home (or whenever one is connected, if you turn off
  Only while a device is away from home), every display of the Mac is black, and a key or click on the Mac locks it.
  The displays come back 30 seconds after you’re done." Under troubleshooting: "If your Mac’s screen stays black: press
  any key or click, or press Control-Command-Q; unlock it with your password or Touch ID, and the screen comes back. If
  Sill has stopped answering, it quits by itself within about 10 seconds, and the screen comes back." Privacy page:
  "While Darken this Mac’s screen is on and the screen is dark, Sill for Mac notices whether a key is pressed or the
  mouse is used on the Mac itself, only to lock it. It reads no key and keeps or sends nothing of it." Review notes
  (Sill for Mac ships outside the App Store; for the App Store's Sill for iPhone and iPad, once that Mac release is out):
  "Your Mac’s own screen can stay dark while you use it from afar."
- **Run 5 (2026-11-23): run 4's code compiled and verified for the first time.** Run 4 had pushed the darkening and
  ended while its one hold was still queued, so none of it had compiled. Main 5d062a3c (#389, #418) merged in
  (aee63f9c, no conflict). Read as a reviewer before the hold: nothing seen wrong in the Swift, and nothing in the hold
  that could darken, cover or lock this Mac (the real seams are made only in PrivacyScreen.init with `real`, which the
  CLI's `testHooks: true`, `--synthetic` and the bare binary's ad hoc signature all rule out; the bare binary's
  previews exit before any coordinator is made, and CurtainView's is drawn with cacheDisplay, never in a window; every
  host synthetic, on 127.0.0.1, under 30 s). New: darken.py's `switch` case, Sill.app's own code for the switches and
  its Quit in the bare SillMenuBar binary as a synthetic test host on loopback (`-requirePairing NO`,
  `-virtualDisplay 0`, a TLS test client at home, `-SillSetAfter`, `-SillQuitAfter`; the three keys HostSettings saves
  are read from the bare binary's defaults domain and removed), so ways 2 and 3 below have a dry run through
  HostSettings, `setTarget` and AppDelegate's Quit, not only the CLI's.
- **Verified in run 5** (at 2695c1f9, in one hold of heavy.sh's slot B, 16:51 to 18:25; logs in sill-handoff's
  next/privacy-darken/run5/logs): `swift build -c release` 55 s (53.48 s), no warning; the probe compiles
  (`--build-only`); the darken check, 332 checks, 0 failed, and its mutants, 141 of 141 caught (2,837 s; each new one by
  its own case); the privacy check, 217 checks, and its mutants, 87 of 87 caught (1,429 s);
  `Scripts/privacy-check/darken.py OUT all`, 39 of 39 verdicts (144 s): the black up at 0.620 s, before the connect's
  wake counted in the same turn; lit
  3.1 s after the last departure; a key's lock unconfirmed 3.04 s later, then the ⌃⌘Q hint; the Mac's own unlock at
  8.06 s; the hold lit at the lock's outcome (9.375 s); SIGTERM lit, then its line; the watchdog's dry run once, 9.01 s
  into a 12 s stall, the host going on; and the switch case: dark at the connect and at each switch back on (4.06,
  10.57, 16.57 s), off lit at once (8.57 s), only away with the device at home lit at once (13.57 s), the ⌃⌘Q hint with
  keys passing, Sill's own Quit while dark lit before its line (19.57 s), the keys saved as Settings would (1, 0, 0) and
  removed; `Scripts/privacy-check/live.py OUT all` 48 of 48 (183 s); the previews from the bare binary, 336 PNGs (9 s),
  the ten new ones (the Devices pane's darken, darkenany, darkenpass and darkennoaccessibility in both appearances, the
  hint's lock and pass) looked at; H2, this build's CLI against main 5d062a3c's, built from `git archive` in the same
  hold (45 s), no new flag: idle 45 s 9 lines each, the 7 others identical masked, and a test client 30 s 35 lines each,
  the 12 others identical masked, the same 7 statistic names (run5/h2.py); `Tests/checks/run-all.sh`, all 77 pure checks passed (723 s); a
  parse-only text check that away-quality's 67, stage-release's 25 and key-repeat's 42 patterns and update-install's
  AppModel one are each still found once (their files changed only in comments, or not at all: their mutants not run);
  CI green at 2695c1f9 (run 45162791943, Build and check 23 m 41 s), the commits after it docs only.
- **Every way the black ends, and what covers it** (run 5's review of the code, once everything was green):
  1. *The last device leaves*: the check (rule 6: the wait, a return, 29.9 and 30 s, the hold for the lock and its
     bound; both rules scripted; the model's R0 and I8), the dry runs `wait` and `hold`, part 1's live.py; trial steps 1
     and 9.
  2. *The switch is turned off*: the check (rule 9), the dry run `switch` (Sill.app's own HostSettings and `setTarget`,
     in the bare binary); trial step 2.
  3. *Sill quits*: the check (rule 11), the dry runs `quit` (the CLI's SIGTERM) and `switch` (AppDelegate's Quit and
     `quitBegins`, in the bare binary); trial step 3.
  4. *Sill crashes*: nothing of Sill's to check (the window server removes a dead process's windows); G0 measured 14 and
     16 ms; trial step 4.
  5. *Sill freezes*: the check (rule 12's decisions), the dry run `watchdog`; the real end only with a debugger, which
     this Mac must not run: under "not verified". A process stopped whole stops its watchdog too (G0's step 3).
  6. *The Mac locks*: the check (rules 4, 7 and 8), the dry runs `takeback`, `keys` and `pass`, G0's spell 1 (the lock
     screen in front at 1000; 1501 inferred); trial steps 5 and 6.
  7. *The Mac sleeps*: the check covers the wake's part (the lock screen, then the Mac's own unlock); that the
     watchdog's clock stops in sleep (CLOCK_UPTIME_RAW), so a sleep is no hang, and that the wait's clock counts it, is
     read in the code, not run (no test may sleep this Mac): under "not verified"; trial step 8.
  8. *Another user takes the screen*: the check (rule 8: back from off console is the Mac's own), the dry run
     `takeback` for the same glue with a lock; trial step 8.
  9. *A display is added or removed while dark*: the check (rule 13's count: every screen gone lifts, one back darkens);
     no dry run (a test host's displays are fixed, and DisplayChanges and WindowCurtain.resync are Sill.app's alone): a
     hook to change them would touch DarkenPolicy and its 141 mutants, not small; under "not verified"; trial step 7.
  Findings: the step file said a device's view of Settings could turn the switch off (captures leave Sill's windows
  out: corrected, way 2 above); the pull request lacked the plan's small leaks (a Touch Bar, VoiceOver) and Sill's own
  menu under the black (added to its defects); and a main-thread stall need not be a keychain prompt: WindowSizer is the
  main actor's, so Accessibility waiting on an app that hangs while Sill sizes its window can reach the watchdog's 10 s
  and end the session (named in the defects; WindowSizer itself is outside this pull request).
- **Run 6 (2026-11-24): the pointer hidden while dark, and dark 5 s after the last device leaves.** Noah installed a
  test build with this branch today and tried it with his iPad and iPhone. Sill.log: "Privacy: this Mac’s screen is
  dark while a device is connected (1 display)." 14 ms after "Client connected", and "this Mac’s screen is lit again."
  30.2 s after the last device left. His words, in order: the cursor still shows on the darkened screen and the screen
  does not undarken when the client disconnects; then "Scratch that, it does work, 30 seconds seems to long. Why did
  you choose that and could we make it fast?"; then "The cursor is still shown when darkened". His log has, twice, a
  few seconds after his device left and while the screen was still black for its 30 s, "Privacy: locking this Mac:
  someone pressed a key or clicked on it.": he touched his Mac in the wait, and it locked on him. That was "does not
  undarken". Why 30 s: a connection that drops and comes back (a Wi-Fi blip, a network switch, a moment in another
  app) never showed the desktop to the room in between, and it matched the lock's own wait (#402). Main d9b3e995
  (#410, #406, #405) merged in (8af2688d, no conflict).
  - *The pointer, hidden (rule 15; the plan's open decision 14 decided by Noah: "The cursor is still shown when
    darkened").* While the black is up and the Mac reads unlocked, with Settings' Hide the pointer too on (on by
    default, `HostConfig.darkenHidesPointer`), the pointer is hidden: after the black is up and its line and hint, never
    over the desktop. Shown for the lock screen (macOS's own, in front of the black) and another user's session, and
    hidden again at a device's unlock. Shown before the black comes down, whichever way it ends (below). How: macOS has
    one pointer; CoreGraphics' public CGDisplayHideCursor and CGDisplayShowCursor hide and show it on every screen at
    once (the SDK's CGDirectDisplay.h: "Hide the mouse cursor and increment the hide cursor count. The `display'
    parameter is ignored."), but act only for the app in front unless the app's own connection to the window server
    says it may set the pointer from the background: the connection property "SetsCursorInBackground", set with the
    private CGSSetConnectionProperty on Sill's own connection (CGSMainConnectionID). Sill.app stays in the background
    while a device uses the Mac (activating it would take the keys from the app the device uses), and its black
    windows must ignore the mouse for the device's input, so no cursor of theirs can do it: nothing public hides an
    app-in-the-background's pointer, and the private property is what macOS's own frameworks use for it. Read, not
    run, on this Mac (macOS 27.2.1): `dyld_info -exports` of CoreGraphics re-exports `_CGSSetConnectionProperty`,
    `_CGSMainConnectionID` and `_CGDisplayHideCursor` from SkyLight's `_SLS…`/`_SL…`; the dyld shared cache has
    "SetsCursorInBackground" in SkyLight's event code (beside `CGXTrackBackgroundEventShape`), and in ViewBridge as
    "CGSSetConnectionProperty (SetsCursorInBackground)" and "settingMousePointerImageInBackgroundIsAllowed" (macOS's
    own use); the window server keeps the hide count apart from the cursor's image ("cursorShow:%d (cursorHideCount)",
    "cursorVisState") and says "%s Unwound cursor hides", consistent with a connection's hides ending with it. That the
    hide is counted per connection and ends with the process is the long-known behaviour this rests on, not measured
    here: Noah's step 3 (a `killall -9 Sill` while dark) is its proof. `PointerCalls` (PrivacyCurtain.swift) looks the
    two calls up by name (dlopen of the already loaded CoreGraphics, then SkyLight's own names; never linked), beside
    the virtual display's surface, the lock's SACLockScreenImmediate and the shortcuts' getters, Sill's other private
    calls: missing, darkening goes on and the log says once that the pointer stays visible. `PointerHider` keeps at most
    one hide outstanding, sets the property just before it and takes it back just after the show, and hides again at a
    wake. Every test host's dry run says what it would do and looks the two calls up by name (found on this Mac), never
    calling them; the pointer of this Mac was never hidden by an agent.
  - *What the device draws, unchanged (b).* The host never reports the pointer's visibility: the frames never carry the
    cursor (`showsCursor` false), kind 26 says where the pointer is (CGEvent(source: nil)'s location, whatever its
    visibility) and kind 14 what shape (CursorShapeWatcher, NSCursor.currentSystem at 20 Hz). AppKit's
    `currentSystemCursor` (disassembled here with `dyld_info -disassemble`) reads the registered cursor
    "com.apple.coregraphics.GlobalCurrent"'s images (two calls, the second with that name and five out-arguments: the
    shape of CGSCopyRegisteredCursorImages): the image, not its visibility, which the hide count does not change. So a
    device's pointer keeps its place and its shape over text and links while the Mac's is hidden. An app that hides the
    Mac's cursor with the hide count (a video player, a game) was never told to a device (docs/pointer-visibility-plan.md
    Q8: "no public API tells another app's cursor is hidden"; the device's arrow stays), and one that sets a blank
    cursor image still blanks the device's pointer as before: nothing the host reported can now be mistaken for Sill's
    hide, and nothing new is told apart or lost. Were the shape to read nil while hidden (not expected), the device would
    keep the last shape until the screen is lit (the watcher keeps the last); were it to read blank, the device's
    pointer would vanish while dark: Noah's step 1 looks at exactly this. (CursorClass is ready-175's, not in main: the
    standard cursors told from an app's own, by shape; no visibility either.)
  - *More than one screen (d).* macOS hides its one pointer on every screen at once, so the rule goes by what the person
    at the Mac needs: no pointer while every screen they can see is black (a screen just plugged in is about to be;
    Sill's own displays are seen by nobody at the Mac), and the pointer whenever they are to use the Mac: every screen
    lit (taken back by their own unlock, the wait over, a key after the last device left, the switch off, a quit), the
    lock screen in front, another user's session.
  - *Every way the black ends, and the pointer:* 1, the last device gone and the wait over: shown, then lit (the rule's
    order; a key in the wait the same); 2, the switch off: shown, then lit; 3, Sill quits: shown, lit, its line, and
    the process's end anyway; 4, Sill crashes or is killed: the window server ends the dead connection's hide with it
    (Noah's step 3); 5, the watchdog: `_exit`, as 4; 6, the Mac locked and unlocked at the Mac: shown as the lock screen
    shows, lit at the Mac's own unlock with the pointer already shown (a device's unlock: hidden again, still dark);
    7, a sleep and wake: the lock screen at the wake shows it; without a password the hide stays, made again at the wake
    (a show and a hide, the count still one); 8, another user: shown at the switch; 9, a display added or removed: the
    hide covers every screen, a screen not yet covered included; with no screen left, shown, then lit. And
    WindowCurtain's lift shows it whatever the rule said: never a pointer left hidden.
  - *Dark 5 s after the last device leaves (rule 6, as Noah asked).* Settings' new row under Darken this Mac's screen,
    Stay dark after the last device leaves: 5 seconds (the default) or 30 seconds (`HostConfig.darkenWait`). With no lock
    to follow, the departure's hint says "This Mac’s screen comes back within 5 seconds. Press any key or click to bring
    it back now.", and a key or click at the Mac lights the screen at once and locks nothing: the lock at a key is for
    while a device is connected. With Lock this Mac when the last device leaves on, nothing changes: the black holds
    until the lock shows (bounded by the lock's own 30 s + its 3 s confirmation + 1 s, `DarkenPolicy.lockGrace`), and a
    key or click in that wait, or during the hold, locks at once. A device back inside the wait: still dark, the hint
    reworded; back after a key lit it: dark again at once. Two devices of which one leaves: no wait. The watchdog beats
    while the black is up, the wait included, as before; the lock's own wait and its lines are part 1's, unchanged
    (main's behaviour). A wait chosen while one runs: it ends by the new choice at the next tick.
  - *A deliberate leave (d) is not told apart, so left out.* The host can tell a connection the device closed cleanly
    (end of stream, no error) from one that timed out or stopped draining, but a clean close is not a deliberate leave:
    the device's own liveness check closes its connection the same way (NWConnection.cancel(), after 6 s without
    hearing the Mac) and then reconnects, so a blip that ends with that close reaching the Mac would light the room a
    second later; and a relay on this Mac closes the host's side cleanly whatever happened to the device. Telling them
    apart needs a word from the device, a change to the wire the task rules out: every departure waits the same.
  - *Settings › Devices* gets two rows under Darken this Mac's screen, after A key or click on this Mac locks it: **Hide
    the pointer too** (on) and **Stay dark after the last device leaves** (5 seconds, or 30 seconds), worded as the
    section's rows and as #402's Turn off its display too; the footnote says the wait, and with #402's lock on that the
    black holds for its lock screen. Saved as `darkenHidesPointer` and `darkenWait` (seconds) in me.saffer.sill.mac;
    `-SillSetAfter` takes `darkenWait=5|30` and `darkenHidesPointer`; the CLI `--darken-wait=5|30` and
    `--darken-pointer=hide|show` (with `--synthetic` only); no device sets them. Previews: pane-devices-darkenlong (30 s,
    the pointer shown), pane-devices-darkenlock (the footnote with #402's lock on) and privacy-hint-left.
  - *The rule and its check* (DarkenPolicy, `Tests/checks/darken`): rule 15 (`shouldHidePointer`, `.pointer(hidden:)`:
    after the raise, before the lift, by the reading and its switch), rule 6's `wait` (Settings' choice, or a test
    host's SILL_TEST_PRIVACY_GRACE as before) apart from `lockGrace` (the lock's own wait, the hold's bound),
    `lightsAtKey` (the wait with no lock to follow and no lock being confirmed), the departure's hint `.left(seconds)`,
    `holding` (a line when the dark holds for a lock), `litByKey`. HostConfig's two knobs in away-quality (AQ-D10 to
    D20). The check's cases written before run 6 run with the long wait and the pointer's switch off, so their actions
    stay as they were; run 6's cases and Pair's use the defaults.
  - *Defaults taken in run 6* (the pull request lists them for Noah): the pointer hidden while dark, with a switch (on);
    shown for the lock screen and another user's session; one pointer for every screen (hidden while every screen one
    can see is black); 5 s by default, 30 s the other choice; the wait's hint and a key or click lighting it with no lock
    to follow; #402's lock on unchanged; every departure waits the same (no wire change).
  - *Known visible behaviour, changed:* the pointer no longer shows on the black (the first item of the list above);
    new: with the 5 s wait, a connection that drops and stays away longer than 5 s shows the desktop to the room until
    it is back (the 30 s choice keeps the old cover); the key or click that lights the screen after the last device left
    still reaches the app under it, as the one that locks does.
  - *Noah's trial (run 6; it replaces the list above, shortest first).* What it does, in plain words: while the iPhone or
    iPad uses the Mac, every screen of the Mac is black and the Mac's pointer is gone, while the iPad still shows its
    own; a key or click on the Mac while the iPad is connected locks it; when the iPad leaves, the screens come back 5
    seconds later, or at once with a key or click. Set up: Darken this Mac's screen on, Only while a device is away from
    home off, Hide the pointer too on, Stay dark after the last device leaves 5 seconds, Lock this Mac when the last
    device leaves off.
    1. *The pointer:* connect the iPad (black); move the Mac's mouse: no pointer on the black; on the iPad, the pointer
       over text and a link: still shown, an I-beam and a hand; ⌃⌘Q: the lock screen with its pointer; unlock: lit.
    2. *The wait:* close Sill on the iPad: back in about 5 s, the hint saying so; connect, close again and press a key on
       the Mac within those seconds: lit at once, not locked.
    3. *A crash:* connect (black, no pointer), then from the iPad's Terminal on the Mac `killall -9 Sill`: lit, and the
       pointer back.
    4. *The switches:* Settings › Devices in front, keys passing; connect; click Hide the pointer too under the black:
       the pointer shows; again: hidden; click Darken this Mac's screen: lit; again: black.
    5. *Sill quits:* `osascript -e 'quit app "Sill"'` from the iPad: lit with the pointer.
    6. *What stays hidden:* ⌘Space, F3, the volume keys: nothing over the black.
    7. *A key or click while connected:* locks; Touch ID: lit about 2 s later, while the iPad stays.
    8. *A display:* plugged in and out while dark: black within a moment, no pointer on it.
    9. *Sleep and another user:* sleep from the iPad, wake at the Mac: the lock screen with its pointer; unlock: lit;
       another user and back: lit.
    10. *From away with the lock:* Only while away on, #402's lock on; the iPhone through Tailscale: black; close Sill:
        the black holds about 30 s, then the lock screen; again, a key in those 30 s: locks at once.
  - *Verified in run 6* (at 82019be0, in one hold of heavy.sh's slot B, 17:52 to 19:45; logs in sill-handoff's
    next/privacy-darken/run6/logs): `swift build -c release` 52 s (50.76 s), no warning; the darken check, 445 checks, 0
    failed (332 before), the model holding I1 to I12 through 20,000 random sessions that now also draw Settings' wait and
    the pointer's switch (23,884 pointers hidden, 656 keys or clicks lighting a screen in a wait with no lock to follow,
    2,870 holds begun); its mutants, 180 of 180 caught (3,594 s; 39 new, 15 patterns repaired for the changed code, and
    the hold for no lock under way, listed as equivalent before, now a mutant its line catches); the privacy check, 217
    checks, its mutants 87 of 87 (1,369 s); away-quality, 197 checks, its mutants 78 of 78 (300 s; AQ-D10 to D20 new);
    `Scripts/privacy-check/darken.py OUT all`, 60 of 60 verdicts (255 s): 59 in the hold, and the `pass` case's
    start-line verdict, which failed on the script's own stale string (the line now goes on past "reach its apps"),
    true with the string fixed (5ba45171) on that same host run's saved log, rather than in a second hold: the disk
    stood at 24.7 GiB after the hold, under the 25 GB floor, and the only code between the two heads is that line. The
    new cases: the pointer hidden once after the black is up (1.08 s), both private calls found by name and never
    called, shown for the lock screen (4.08 s), lit at the Mac's own unlock with it shown, SIGTERM showing it before the
    lift, `--darken-pointer=show` never touching it; lit 5.25 s after the last device left by default and 30.15 s after
    with `--darken-wait=30` (no test shortcut); a key 1.09 s after the departure lit it with nothing locking, a device
    back after it dark again at once, back inside the next wait kept dark; with `--lock-after-session` a key in the wait
    locked as before; the switch case's pointer shown at once (18.13 s) and its five keys saved and removed. Also
    `live.py OUT all` 48 of 48 (184 s); the previews from the bare binary, 341 PNGs (8 s), the darkening's 15 looked at;
    H2 against main d9b3e995's CLI built in the same hold (47 s), no new flag: idle 9 and 9 lines (the 7 others identical
    masked), a test client 35 and 35 (the 12 others identical, the same 7 statistic names); `Tests/checks/run-all.sh`, all
    78 pure checks passed (761 s); CI green at 82019be0 (run 45392480338, 20 m 38 s).
  - *Not verified in run 6*, and why: the pointer's hide on a real screen (no agent may hide this Mac's pointer: Noah's
    steps 1 to 4); that the hide ends with the process (step 3); the shape while hidden (step 1); the hide made again at a
    wake (no test may sleep this Mac: step 9); a deliberate leave told apart (left out: it needs the wire).
