**Privacy, part 2: this Mac's screens dark while a device uses it, built up to the one place that darkens them and waiting for Noah's probe (2026-11-18, branch `privacy-darken` from `privacy-lock` at 4d6a470, which is main at 8dbbb50 with #184 and part 1).**

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
  through DesktopDisplays.role (rule 13); its TEST ONLY hooks and every word.
- **The code up to the seam, `PrivacyScreen`** (main actor): the rule's state and tick; the screens (CoreGraphics'
  online displays through `DarkenPolicy.screens`, or a test host's SILL_TEST_PRIVACY_DISPLAYS); its lock through its
  own `ScreenLocker` (part 1's, a dry run on a test host); `HostStatus.privacyDark`. Two seams: `Curtain` (raise, lift,
  hint) and `LocalInput` (the Mac's own keys, clicks and pointer, only while dark). On a test host `DryCurtain` says what
  it would draw (`priv.raise`, `priv.lift`, `priv.hint`) and `FileInput` reads the Mac's "own" input from
  SILL_TEST_PRIVACY_INPUT (`priv.localDry`). In Sill.app both are empty, so darkening stays off there whatever the
  config says (one line if it is ever on).
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
- **Verified**: the darken check (202 checks, among them 20,000 random sessions running this rule beside part 1's
  against nine invariants; 91 of 91 mutants caught, the equivalent ones named in its mutants.py); away-quality with the
  new knobs (58 of 58 mutants, AQ-D1..9 new); stage-release and repo-rules; `Tests/checks/run-all.sh` (all passed);
  typecheck of SillHostCore, the CLI and Sill.app; the probe compiled (`--build-only`); `swift build -c release` (62 s,
  through heavy.sh); `Scripts/privacy-check/darken.py OUT all` on loopback, 25 of 25 verdicts (order: the black up at
  1.006 s, the wake counted after it in the same turn; home; away at the remote door from a relay on this Mac, and at
  home by address; wait, lit 3.1 s after the last departure; keys; pass; takeback, lit at the settled unlock; hold, lit
  0.5 s after the lock's outcome; quit). Not run: H2 (the CLI's stdout without the new flags, against main).
- **Docs**: one entry each in docs/LAYOUT.md (DarkenPolicy and PrivacyScreen; the probe and darken.py) and
  docs/BUILD-AND-RUN.md (the probe's command; the dry run), carried there from CLAUDE.md by `Scripts/migrate-notes.py`
  when `privacy-lock` took main's #388 and was merged in here (a34c675d).
- **Defaults taken** (the pull request lists them for Noah): the plan's recommendations for its open decisions; the
  black under the lock screen until G0; one key's lock may hold the dark up to 3 s past the wait; a failed key lock
  stops key locks until a lock shows or a switch changes; a change of scope lifts at once, a move home under "only away"
  waits 30 s; the hint at most once a second.
- **Not yet** (the next runs, after G0): the real `Curtain` (the windows at G0's level and opacity, the hint view, the
  re-sync at display changes) and `LocalInput` (NSEvent's monitors), InputInjector's tag, the watchdog
  (`PrivacyWatchdog`, SILL_TEST_PRIVACY_STALL), Settings › Devices' section and previews, Sill.app's App Nap hold on
  `privacyDark`, the remote door's away case live, rule 6's "not taken back" in part 1's lock (a Mac its owner took
  back still locks 30 s after the last device leaves: one input to PrivacyPolicy, coordinated with `privacy-lock`),
  docs and the site.
- **Proposed words** (for the release that ships it; not in any published page): What's New: "Privacy: keep your Mac’s
  screen dark while you use it from afar, and lock it when someone touches it (Settings › Devices)." Support:
  "Keep your Mac’s screen dark while you use it from afar. In Sill on the Mac, Settings › Devices: turn on Darken this
  Mac’s screen. While your iPhone or iPad uses the Mac from away (or whenever one is connected, if you choose), every
  display of the Mac is black, and a key or click on the Mac locks it." and "If your Mac’s screen stays black: press
  any key; the Mac locks, and your password or Touch ID brings it back." Privacy page: "While Darken this Mac’s screen
  is on and the screen is dark, Sill for Mac notices whether a key is pressed or the mouse is used on the Mac itself,
  only to lock it. It reads no key and keeps or sends nothing of it."
