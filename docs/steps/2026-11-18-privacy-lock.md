**Privacy, part 1: Sill for Mac locks this Mac when the last device leaves (2026-11-18, branch `privacy-lock` from main at 8dbbb50, on #184's head).**

- **What it is.** Settings › Devices gains one switch, off until turned on: **Lock this Mac when the last device
  leaves** (`lockAfterSession` in me.saffer.sill.mac; Noah's #283, and #275's "turn off display immediately after end
  a session"). 30 s after the last session of any kind ends, unless one comes back, Sill locks the Mac with
  login.framework's `SACLockScreenImmediate` (the call macOS's own Lock Screen makes) and then puts its display to
  sleep (`pmset displaysleepnow`). A paired device unlocks it again by typing the password at the lock screen, as
  LockPolicy already allows (#271). Under it, while it is on, two switches of its own (since the review, below):
  **Turn off its display too** (`lockSleepsDisplay`, on) and **Only after a device away from home**
  (`lockOnlyAfterAway`, off: on, a visit whose sessions were all at home starts no wait). Mac only: no message kind,
  no field, nothing on the device. Darkening the screen while a device uses the Mac (part 2 of
  docs/privacy-mode-plan.md) is not here: it waits for Noah's G0 probe.
- **Built on #184** (addhumal), the way #355 carried #173: its head 22f0673d merged in as it is (5f3a4632), main's
  side of the four conflicts kept (ci.yml's mutants matrix, the checks README without its table; AppDelegate and
  AppModel both sides), `SessionLock.unlocked` a property since #271, and the check's README.md that repo-rules asks
  for; it built and behaved as #184 does (49 of 49). The commits after it replace #184's app-side code: its lock moves
  into `SillHostCore` with the wait #283 asks for (#184 locked the moment the count reached zero, D2 in the
  assessment), checked against SessionLock's reading (D10), refused on a Mac with no display to type at (D11, #298),
  and its darkening (the black windows, its Remote Access section, `privacyMode`) comes out until part 2, which takes
  its window recipe from #184's history. #184's `privacyMode` and `lockOnDisconnect` keys never shipped.
- **The rule** (`PrivacyPolicy`, pure, `Tests/checks/privacy`): every registered session counts (either door, paired
  or not, home or away; a session cut off counts as it leaves); a connection that only pairs (`sill-pair/1`), one the
  device gate refuses and one an update's hold sends away never register, so they neither start a wait nor end one.
  The last departure with the switch on starts the 30 s wait; a session registering, the switch turned off or a quit
  ends it, each with a line. At its end: locked already, another user (or the login window) on the screen, or no
  reading yet: nothing, with the line; no display a lock screen could take a password at (rule 10: a screen by
  DesktopDisplays.role, never Sill's stage or Desktop display nor macOS's stand-in): nothing, with the line and a
  warning in Settings; otherwise the lock, then its confirmation: SessionLock's reading says locked within 3 s (the
  displays then sleep, unless a device came back meanwhile), or the call is unavailable or the Mac still reads
  unlocked (the failure's line, Settings' "Sill couldn’t lock this Mac the last time: …", and the displays sleep
  instead, which locks a Mac that asks for its password at once after display sleep). One lock at a time. Turn off
  its display too off: the confirmed lock's own line and no display sleep (a failure still sleeps it). Only after a
  device away from home: the last departure starts the wait only when a session of the visit was away from home
  (AwayPolicy.isAway, from the coordinator's `onClientConnected` after the count: `joined`); a visit is the sessions
  since the Mac last had none with no wait under way, so a device back within a wait goes on with it; otherwise "the
  last device left; none connected from away from home, so this Mac won’t be locked."; turned on during a wait for a
  visit with none away, it ends that wait with its line.
- **The glue** (`PrivacyLock`, main actor): the server's count from `onClientCountChanged`, each session's route from
  `onClientConnected` (`joined`), the three switches from `setTarget` at once (never a restart;
  `HostConfig.lockAfterSession`, `lockSleepsDisplay` and `lockOnlyAfterAway` are the Mac's alone, absent from
  everything a device sends), the reading from `lockChanged`, a quit from `shutdownForExit`, the CLI's signal path
  (`releaseKeysForExit`) and Sill.app's `applicationShouldTerminate` before an update's install step or a full-screen
  window makes it wait (`quitBegins`). A half-second tick on a main-actor Task while a wait or a confirmation runs, on
  ContinuousClock (a wait that spans a sleep ends at the wake). `ScreenLocker` makes the call and runs pmset on
  `sill.privacy.lock` in Sill.app itself alone (`PrivacyPolicy.locksForReal`: its own executable, not `--synthetic`);
  the CLI, the bare SillMenuBar binary and every test host make the dry run, which prints "Privacy (dry run): would
  lock this Mac now; nothing is locked." and counts `priv.lockDry`. Sill.app holds App Nap off during a wait
  (`NapHold.lockWait`, allowing idle sleep) so the tick keeps its time. The CLI takes
  `--lock-after-session[=away][,nosleep]` only with `--synthetic`; without the flag its stdout is as before.
- **Never locked this Mac.** Nothing here called `SACLockScreenImmediate` or `pmset`; every test ran a test host,
  whose locker is the dry run. Until the review (finding 1) the bare SillMenuBar binary started without `--synthetic`
  had the real locker too, which `-SillSetAfter '… lockAfterSession=1'` would have turned on and saved in its own
  domain; no run here did that (the previews render and exit before any host starts, and `defaults read SillMenuBar`
  has no lock key), and since c3b5b96b only Sill.app itself has it. The symbol was only looked up (`dlopen` and
  `dlsym` by both paths the locker uses, from a scratch program with no call site; and `dyld_info -exports`): found
  on macOS 27.2.
- **Verified (the first round, at 1655f272).** `Tests/checks/privacy` 157 checks, its 55 mutants every one caught on
  the final rule (one equivalent mutant found on the way, tick's second guard against a quit, replaced by one a quit
  catches); `away-quality` with the knob's cases, 49 of 49 mutants (5 new); `stage-release`, `update-install` and
  `repo-rules`, which read the changed files; `Tests/checks/run-all.sh`, all 75 (run outside the heavy lock at nice 19
  while the build waited for it); the host library, the app and the CLI typechecked with swiftc against each other,
  clean; the merge of #184 (5f3a4632) built with `swift build -c release` and its own check passed, 49 of 49; CI on
  the pull request (run 44299093908, at 86cadb58, main merged into the branch): `swift build -c release`, run-all, the
  iOS app for the simulator and the CLI's paths, all green.
- **Live, on test hosts (the first round)** (after a first turn of the heavy lock found 24 GB free and stopped before
  building, as the rule says; the second, with 38 GB, built): `swift build -c release` of 1655f272, no warning;
  `Scripts/privacy-check/live.py OUT all`, 39 of 39 verdicts in its twelve cases, each a synthetic loopback host under
  a minute whose lock is the dry run: the switch off says and counts nothing; the wait from the departure to "would
  lock" 5.12 s (5 s and a tick), the test's lock file then confirming it 0.53 s later with the display sleep after it,
  one wait and one lock, `priv.lockDry` and `priv.sleepDry` in the stats; a device back 2 s in ends the wait, its own
  departure's lock unconfirmed fails at 3.08 s with the display sleep instead; two overlapping sessions start no wait
  until the last leaves; locked already, another user and no display each say why and lock nothing; no lock call fails
  at once; SIGTERM during the wait says Sill is quitting and locks nothing; SIGKILL during it locks nothing and the
  next launch, 12 s with no device, starts no wait; a `sill-pair/1` ask (answered `shown`) starts no wait alone and
  ends none during one; a device the gate refuses (`SILL_TEST_MIN_DEVICE_VERSION=1.2`, hello 0.6) ends none. A session
  cut off has no headless path (Direct Wireless off needs AWDL; Remove and Require pairing are the app's): it is read
  in StreamServer.swift (`closeSessions` says goodbye and cancels the connection, whose `.cancelled` calls
  `unregister`, the one place but `register` that changes `clients` and calls onClientCountChanged), and it is Noah's
  list's item 10. H2: main's CLI (8dbbb500, built from `git archive`) and this branch's, idle 45 s (9 lines each) and
  with a Desktop client 20 s (35 each), identical masked and sorted. The previews from the bare binary
  (`pane-devices-{lock,locknodisplay,lockfailed}`, light and dark, and the switch off in every other Devices sample):
  the section after the off-console view's, its footnotes, its warnings.
- **The review (c3b5b96b): four findings, each real, each fixed.** (1) Whether the lock was real hung on `--synthetic`
  alone, which AppModel passes through, so the bare SillMenuBar binary started without it had the real locker:
  `PrivacyPolicy.locksForReal(synthetic:bundled:)`, Sill.app's own executable (the coordinator's `testHooks` false,
  from AppIdentity.isSillApp) and not `--synthetic`, so the CLI (always `testHooks: true`) never locks, with its three
  mutants; the dry run's lines say "(dry run)" and its start line that only Sill.app locks. (2) The display sleep and
  the scope were fixed (Noah's "a toggle wherever sensible", 2026-11-18): the two switches under the lock, at the plan's
  recommendations (open decisions 6 and 5), the CLI's `=nosleep` and `=away`, 25 privacy mutants and 9 away-quality
  ones (AQ-S1..4, AQ-A1..5). (3) The check's model of the server had `neverRegisters()` and a cut-off that only
  counted: gone, and its header and README say that which connections register is StreamServer's (`clients` changes
  in `register` and `unregister` alone), run live by the pairing and gate cases; `PrivacyPolicy.mac(_:established:)`
  moved in from PrivacyLock (LockPolicy.swift joins the check's module) with four mutants. (4) The pull request's
  defaults left out open decisions 15 and 16: both are in it now, with what a squash or a rebase would do to #184.
- **Verified (the review round, at c3b5b96b).** Read against the four findings: each fixed (the only two places that
  make a StreamCoordinator are the CLI, `testHooks: true`, and AppModel, `testHooks: !AppModel.bundled`; the dry run
  never loads login.framework or runs pmset). Outside the heavy lock, at nice 19: `Tests/checks/privacy` 217 checks
  (its 20,000 random sessions reach 3,362 locks, 1,062 of them only after a device away, 6,074 visits at home alone and
  588 locks with the display left on), its mutants 87 of 87 caught (32 new); `away-quality` 170 checks, 58 of 58
  mutants (9 new); `lock-policy` 1,411 of 1,411. CI on the pull request (run 44313954856, at c3b5b96b): `swift build -c
  release`, `Tests/checks/run-all.sh`, the iOS app for the simulator and the CLI's paths, all green. The review's own
  heavy turn (08:35) built c3b5b96b (49 s) and passed live.py's off, wait and back before its session stopped; the
  close-out's turn ran at 22:37 at 34c899ed: `swift build -c release` passed; `Scripts/privacy-check/live.py OUT all`,
  48 of 48 verdicts hold, the nosleep and away cases among them; the previews drawn from the bare binary (326, the
  eight lock panes among them, SillMenuBar's lock keys in this Mac's defaults as they were); run-all, every check
  passed. H2 again (the CLI's stdout without the flag): idle, identical to main's recorded lines; with a Desktop
  client, five runs differ from the lines recorded in the first round only in the statistics line of the second the
  client leaves (which counters it holds, and whether it still counts the client), and main's own CLI (eb48ac9f), run
  twice the same night, differs from its own recorded lines in the same way, line for line as the branch's last two
  runs: the branch's stdout is main's.
- **Defaults taken for Noah to confirm** (the plan's recommendations): the switch in Settings › Devices (open decision
  1); a 30 s wait (4); after any session, home or away (5, now the switch Only after a device away from home, off: so
  an iPad used as a second screen at the desk locks the Mac 30 s after it disconnects unless it is turned on); the
  display sleeps after the lock (6, now the switch Turn off its display too, on) and after a failed one whatever that
  switch says; #184 merged in as it is (15), so it shows as merged only if #402 lands with a merge commit (main's
  ruleset allows squash and rebase too, which would leave #184 open); two pull requests, the lock first (16); a quit
  never locks; a crash or a force quit leaves the Mac as it is and the next launch never locks by itself (the person
  who opens Sill again is usually at the Mac; macOS's own "Require password after the screen saver begins or display
  is turned off" stays the fallback); at the wait's end a Mac that is locked already, or has another user on its
  screen, is left as it is (no display sleep either); an unlock at the Mac during the wait does not cancel the lock
  (the plan's rule; a person who sits down within the 30 s sees it lock and unlocks with Touch ID); rule 10 counts
  only a screen until #200's display joins it; no menu item and no device switch (12, 11); the CLI dry-run only (17).
- **Untested, for Noah (Noah's list, the pull request's 1–15):** the real lock, which only Sill.app makes, so only on
  his Mac, with Sill.app built from this branch (release-signed, as every branch test is) and the App Store's Sill on
  the iPhone or iPad: (1) the three switches in Settings › Devices, their keys and "Settings:" lines, and the start
  line after a relaunch with no "A dry run here"; (2) a device leaves: the wait's line, the lock about 30 s later (the
  real `SACLockScreenImmediate`, on `sill.privacy.lock`), the locked line and the display asleep; (3) unlocked again
  from the device by its password, and by Touch ID at the Mac; (4) Turn off its display too off: the lock screen lit;
  (5) Only after a device away from home: at home no lock and its line, through Tailscale the lock; (6) a drop that
  comes back within 30 s; (7) two devices; (8) the switch off during the wait; (9) locked already; (10) a session cut
  off (Remove, or Require pairing on) locks 30 s later; (11) another user on the screen; (12) Quit and force quit during
  the wait, and a relaunch that never locks by itself; (13) Sill in the background during the wait (App Nap held off);
  (14) a Mac with no display; (15) the defaults above.
- **Left for whoever merges second:** #200 (Lane A) makes Sill's own display for a Mac with no screen: rule 10 then
  also counts "#200's display would show the lock screen at the next connect" (its make guard), PrivacyPolicy.typesAt
  and its check. The overview's #200 note says so too.
- **Proposed words** (not in any published page; for the release that ships it):
  - support.html, inside a marker: "Lock your Mac when you’re done. In Sill on the Mac, Settings › Devices: turn on
    Lock this Mac when the last device leaves. 30 seconds after your last iPhone or iPad disconnects, your Mac locks
    and its display goes to sleep; if your connection drops and comes back within that time, nothing happens. Unlock
    it again from a paired device with your password. Under the switch, Turn off its display too keeps the lock
    screen lit when it’s off, and Only after a device away from home leaves your Mac unlocked after an iPad or iPhone
    you used at home."
  - What's New for Sill for Mac: "Privacy: Sill can lock your Mac 30 seconds after your last device disconnects
    (Settings › Devices)."
  - privacy.html: nothing new is collected or sent; no change needed for part 1.
  - Replies drafted for Noah on #283 and #275 (posted only on his word): "Lock this Mac when the last device leaves is
    in pull request #402 (Settings › Devices, off by default): 30 seconds after the last device disconnects, Sill locks
    the Mac and its display sleeps; a reconnect within that time keeps it unlocked. Darkening the screen while a
    device uses the Mac (#133) comes after a measurement." and on #184: thanks to addhumal, whose commits are merged in.
