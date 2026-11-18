**Privacy, part 1: Sill for Mac locks this Mac when the last device leaves (2026-11-18, branch `privacy-lock` from main at 8dbbb50, on #184's head).**

- **What it is.** Settings › Devices gains one switch, off until turned on: **Lock this Mac when the last device
  leaves** (`lockAfterSession` in me.saffer.sill.mac; Noah's #283, and #275's "turn off display immediately after end
  a session"). 30 s after the last session of any kind ends, unless one comes back, Sill locks the Mac with
  login.framework's `SACLockScreenImmediate` (the call macOS's own Lock Screen makes) and then puts its display to
  sleep (`pmset displaysleepnow`). A paired device unlocks it again by typing the password at the lock screen, as
  LockPolicy already allows (#271). Mac only: no message kind, no field, nothing on the device. Darkening the screen
  while a device uses the Mac (part 2 of docs/privacy-mode-plan.md) is not here: it waits for Noah's G0 probe.
- **Built on #184** (addhumal), the way #355 carried #173: its head 22f0673d merged in as it is (5f3a4632), main's side
  of the four conflicts kept (ci.yml's mutants matrix, the checks README without its table; AppDelegate and AppModel
  both sides), `SessionLock.unlocked` a property since #271, and the check's README.md that repo-rules asks for; it
  built and behaved as #184 does (49 of 49). The commits after it replace #184's app-side code: its lock moves into
  `SillHostCore` with the wait #283 asks for (#184 locked the moment the count reached zero, D2 in the assessment),
  checked against SessionLock's reading (D10), refused on a Mac with no display to type at (D11, #298), and its
  darkening (the black windows, its Remote Access section, `privacyMode`) comes out until part 2, which takes its
  window recipe from #184's history. #184's `privacyMode` and `lockOnDisconnect` keys never shipped.
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
  instead, which locks a Mac that asks for its password at once after display sleep). One lock at a time.
- **The glue** (`PrivacyLock`, main actor): the server's count from `onClientCountChanged`, the switch from `setTarget`
  at once (never a restart; `HostConfig.lockAfterSession` is the Mac's alone, absent from everything a device sends),
  the reading from `lockChanged`, a quit from `shutdownForExit`, the CLI's signal path (`releaseKeysForExit`) and
  Sill.app's `applicationShouldTerminate` before an update's install step or a full-screen window makes it wait
  (`quitBegins`). A half-second tick on a main-actor Task while a wait or a confirmation runs, on ContinuousClock
  (a wait that spans a sleep ends at the wake). `ScreenLocker` makes the call and runs pmset on `sill.privacy.lock`;
  on a test host (`--synthetic`) it is a dry run that prints "Privacy (test host): would lock this Mac now; nothing is
  locked." and counts `priv.lockDry`. Sill.app holds App Nap off during a wait (`NapHold.lockWait`, allowing idle
  sleep) so the tick keeps its time. The CLI takes `--lock-after-session` only with `--synthetic`; without the flag
  its stdout is as before.
- **Never locked this Mac.** Nothing here called `SACLockScreenImmediate` or `pmset`; a test host's locker is the dry
  run, and only Sill.app's is real. The symbol was only looked up (`dlopen` and `dlsym` by both paths the locker uses,
  from a scratch program with no call site; and `dyld_info -exports`): found on macOS 27.2.
- **Verified.** `Tests/checks/privacy` 157 checks, its 55 mutants every one caught on the final rule (one equivalent
  mutant found on the way, tick's second guard against a quit, replaced by one a quit catches); `away-quality` with the
  knob's cases, 49 of 49 mutants (5 new); `stage-release`, `update-install` and `repo-rules`, which read the changed
  files; `Tests/checks/run-all.sh`, all 75 (run outside the heavy lock at nice 19 while the build waited for it);
  the host library, the app and the CLI typechecked with swiftc against each other, clean; the merge of #184
  (5f3a4632) built with `swift build -c release` and its own check passed, 49 of 49; CI on the pull request (run
  44299093908, at 86cadb58, main merged into the branch): `swift build -c release`, run-all, the iOS app for the
  simulator and the CLI's paths, all green.
- **Live, on test hosts** (after a first turn of the heavy lock found 24 GB free and stopped before building, as the rule
  says; the second, with 38 GB, built): `swift build -c release` of 1655f272, no warning; `Scripts/privacy-check/live.py
  OUT all`, 39 of 39 verdicts in its twelve cases, each a synthetic loopback host under a minute whose lock is the dry
  run: the switch off says and counts nothing; the wait from the departure to "would lock" 5.12 s (5 s and a tick), the
  test's lock file then confirming it 0.53 s later with the display sleep after it, one wait and one lock, `priv.lockDry`
  and `priv.sleepDry` in the stats; a device back 2 s in ends the wait, its own departure's lock unconfirmed fails at
  3.08 s with the display sleep instead; two overlapping sessions start no wait until the last leaves; locked already,
  another user and no display each say why and lock nothing; no lock call fails at once; SIGTERM during the wait says
  Sill is quitting and locks nothing; SIGKILL during it locks nothing and the next launch, 12 s with no device, starts
  no wait; a `sill-pair/1` ask (answered `shown`) starts no wait alone and ends none during one; a device the gate
  refuses (`SILL_TEST_MIN_DEVICE_VERSION=1.2`, hello 0.6) ends none. A session cut off has no headless path (Direct
  Wireless off needs AWDL; Remove and Require pairing are the app's): the check's model of the server covers it, and
  Noah's list. H2: main's CLI (8dbbb500, built from `git
  archive`) and this branch's, idle 45 s (9 lines each) and with a Desktop client 20 s (35 each), identical masked and
  sorted. The previews from the bare binary (`pane-devices-{lock,locknodisplay,lockfailed}`, light and dark, and the
  switch off in every other Devices sample): the section after the off-console view's, its footnotes, its warnings.
- **Defaults taken for Noah to confirm** (the plan's recommendations): the switch in Settings › Devices (open decision
  1); a 30 s wait (4); after any session, home or away (5: so an iPad used as a second screen at the desk locks the Mac
  30 s after it disconnects); the display sleeps after the lock (6) and after a failed one; a quit never locks; a
  crash or a force quit leaves the Mac as it is and the next launch never locks by itself (the person who opens Sill
  again is usually at the Mac; macOS's own "Require password after the screen saver begins or display is turned off"
  stays the fallback); at the wait's end a Mac that is locked already, or has another user on its screen, is left as
  it is (no display sleep either); an unlock at the Mac during the wait does not cancel the lock (the plan's rule; a
  person who sits down within the 30 s sees it lock and unlocks with Touch ID); rule 10 counts only a screen until
  #200's display joins it; no menu item and no device switch (12, 11); the CLI dry-run only (17).
- **Left for whoever merges second:** #200 (Lane A) makes Sill's own display for a Mac with no screen: rule 10 then
  also counts "#200's display would show the lock screen at the next connect" (its make guard), PrivacyPolicy.typesAt
  and its check. The overview's #200 note says so too.
- **Proposed words** (not in any published page; for the release that ships it):
  - support.html, inside a marker: "Lock your Mac when you’re done. In Sill on the Mac, Settings › Devices: turn on
    Lock this Mac when the last device leaves. 30 seconds after your last iPhone or iPad disconnects, your Mac locks
    and its display goes to sleep; if your connection drops and comes back within that time, nothing happens. Unlock
    it again from a paired device with your password."
  - What's New for Sill for Mac: "Privacy: Sill can lock your Mac 30 seconds after your last device disconnects
    (Settings › Devices)."
  - privacy.html: nothing new is collected or sent; no change needed for part 1.
  - Replies drafted for Noah on #283 and #275 (posted only on his word): "Lock this Mac when the last device leaves is
    in pull request #402 (Settings › Devices, off by default): 30 seconds after the last device disconnects, Sill locks
    the Mac and its display sleeps; a reconnect within that time keeps it unlocked. Darkening the screen while a
    device uses the Mac (#133) comes after a measurement." and on #184: thanks to addhumal, whose commits are merged in.
