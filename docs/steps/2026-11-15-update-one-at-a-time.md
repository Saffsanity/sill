**One update at a time: a Sill just installed waits until it has proved itself, and the watcher leaves a later update's copy alone (2026-11-15, branch `update-one-at-a-time` from main at 19af958).**

- **Found in the nightly rehearsal** (Noah's Mac, 2026-11-15 02:20; rehearsal builds, a throwaway repository). Update
  Now from 0.6.97 to the release 0.6.98 at 02:20:33, then, with Use nightly builds just turned on, Update Now to the
  nightly 0.6.98 (1599) at 02:21:02: both worked, 29 s apart. A minute later /Applications/Sill.app was 0.6.97 again,
  under the running nightly, with "Update Now restored.txt" in Sill's notes.
- **Why.** Each update leaves a watcher that waits for the new Sill's word (after `provedAfter`, 30 s with the host
  up) and puts the old copy back when the new process ends without it. The release 0.6.98 quit after 29 s to hand
  over to the nightly. Its quit's `willQuit` gives the watcher that word only when the pending note names this
  Sill, and the note by then named the nightly (the second update had written its own). So the first watcher took
  the quit for a failure, moved what stood at Sill's path aside (the nightly, which was running) and put 0.6.97
  there; `open` then only brought the running Sill forward. Nothing was lost, and the next launch would have been
  0.6.97 saying 0.6.98 didn't run.
- **The fix, two halves.**
  - `Refusal.finishingUpdate`: a Sill that an update installed begins no other update until it has given that
    update's watcher its word (`AppUpdater.proving`, from the launch's notes to `proved`). Update Now is dimmed for
    that half minute with "Sill was just updated. Update Now is ready again in half a minute."; `proved` looks
    again, so the note goes by itself. The automatic update asks the same refusal.
  - The watcher's own guard (`later`, exit 4): a genuine Sill at Sill's path that is neither the copy it watched nor
    the one it would put back was installed since, by an update with a watcher of its own; it is left alone. A copy
    that isn't a genuine Sill is moved aside as before.
- **Verified.** `update-install` 983 of 983 on this branch (10 new: the rule and its order among the refusals, its
  words, the updater holding from the launch's notes to its word, the look carrying it, the watcher's two lines);
  seven new mutants, 7 of 7. The watcher's script run by `/bin/sh` against three real copies (the rehearsal's
  notarized 0.6.97, 0.6.98 and nightly 1599, in a scratch folder): a later copy at Sill's path → exit 4, nothing
  moved, no note; the watched copy there → the old one put back as before, the note written; a tampered copy
  there → put back as before. `swift build -c release`. What two updates in quick succession do on Noah's Mac
  with the rehearsal's build of this (0.6.100, nightly 1603) is in the handoff's `one-click-update/rehearsal/`.
- **And a helper Sill is starting is no other copy of Sill** (the same night, a third finding). Twice Settings said
  "Another copy of Sill is running. Quit it first, then update." with one Sill running (01:53:59 and 02:42:07; the
  process list and the system log had no second one). The look for other copies lists every process and takes
  those whose program path is Sill's; a process being started shows its parent's path until its own program is
  loaded, and Sill starts five as Settings › General opens (the firewall check's `socketfilterfw`), the moment the
  pane looks. Measured with a program that starts helpers while another thread looks: 4 of 1,972 looks saw a
  second process under the program's own path, each time its own child. `UpdateInstaller.processesRunning` now
  leaves out a process whose parent is this one (`ProcessLife.parent`); a Sill that an update starts is launchd's
  child, never this process's. `update-install` 988 of 988 (5 more: a process's parent for this process, a helper
  of the check's own before and after it exits, no pid, and the look's line); three more mutants, 10 of 10 in all.
- **Left:** the kept copy of an update whose watcher stands down this way stays in the temporary folder until macOS
  empties it (the leftover note names one folder).
