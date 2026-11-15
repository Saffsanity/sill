**Update Now's new copy starts once the old Sill has quit: the launch wait asks the kernel (2026-11-15, branch `update-launch-wait` from main at 588ae90).**

- **Found in the rehearsal's first real update** (the plan's §12, Noah at his Mac, 2026-11-15 00:49; rehearsal builds
  0.6.90 to 0.6.91 in a throwaway repository). The update itself took two seconds: the manifest read and verified,
  6.8 MB downloaded, the app checked both ways, /Applications/Sill.app replaced, the new copy started. Then the new
  copy said "Another Sill is running (pid 73996); waiting for it to quit before starting.", and 30 s later
  "Another Sill is still running after 30 s (pid 73996); this one quits." No Sill ran until Noah opened it by hand.
  The system log has the old Sill's end 0.2 s after its "quitting" (`launchd: removing child: pid/73996` at
  00:49:22.789, the new copy's give-up at 00:49:52.476): the old one had gone at once, and the new one never saw it.
- **Why.** `AppUpdater.waitForOtherSill` asked `NSRunningApplication.isTerminated` of the object it had from
  `runningApplications(withBundleIdentifier:)`, five times a second, on the main run loop. That value is one AppKit
  keeps from LaunchServices' notifications, and in a Sill that had only just launched (nothing started yet: that is
  the wait's point) it stayed false for the whole wait. Nothing had run this path before: the harness's bundles are
  not Developer ID signed, so they never count as "genuine" and never wait, and the smoke test of 2026-11-14 ran
  only the case of a Sill that stays (the second launch that leaves after 30 s).
- **The fix.** `ProcessLife` (new, Foundation only): a process by its pid and the time it started, both the
  kernel's (`kill` with signal 0, where only ESRCH means none; `kern.proc.pid` for the start), so a pid given to
  another process is not taken for the Sill that had it. The wait takes each other Sill's `ProcessLife` as it
  begins and counts it gone when AppKit says so or the kernel does. A start that can't be read decides nothing: a
  process with the pid then counts as still there, so a Sill is never started beside one that may still run.
- **Verified.** `update-install` 973 of 973 (18 new: the rule, this process, launchd as another account's, a child
  of the check's own before and after it exits, and the wait's source asking both); its seven new mutants 7 of 7,
  the first of them the fault as it was (the seventh slipped through the first draft of the checks: a pid no
  process has must read no start time). `swift build -c release`. The rehearsal's builds 0.6.92 to 0.6.94 carry the
  same two changes on its scratch branch; what the update to 0.6.92 did is in the handoff's
  `one-click-update/rehearsal/`.
- **Left as it is, to decide:** when the wait does run out (an old Sill that truly hangs), the new copy quits
  through the same quit as a person's, which tells the watcher all is well and lets the replaced copy go, though
  the new version never served anyone. With the kernel's word that case is rare; whether it should count as the
  new version's failure instead is a question for the plan's §15.5.
