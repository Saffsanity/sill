**After an update started in Settings, the new Sill opens Settings on General again (2026-11-15, branch `update-reopen-settings` from main at 19af958).**

- **Noah, in the rehearsal** (2026-11-15, after the update from 0.6.91 to 0.6.92): "It worked! Only thing is that it
  didn't start up in General settings, I had to click from the menu bar." Then: "Reopen General Settings after an
  update you start there." Every update a person starts is started there: the menu's item for an update that
  Update Now can install opens Settings › General, and Install Now, for a copy that waits, is in that pane. The
  window goes with the old Sill, and the new one started as a menu bar app with no window.
- **The rule** (`UpdateInstallPolicy.reopensSettings`): a Sill that starts after an update opens Settings on General
  when the person started that update, and never after one Sill installed by itself, which nobody is watching.
  It holds for the update that worked and for the three ways the watcher's word reads (the old copy put back and
  started, the new one left in place not started, no whole Sill left): the pane then says what came of it.
- **How.** The update's note already says which kind it was ("manual" or "automatic"); `AppUpdater.afterHostUp`
  reads it once the host is up and, by the rule, calls `showUpdated`, which AppModel sets to Settings on General.
  No new state, nothing stored.
- **And it says so, in green** (Noah, minutes later: "I want it to show in green text that 'Sill x.y.z was
  installed successfully.'"). `UpdateInstallPolicy.installedLine`: "Sill 0.6.3 was installed successfully." after
  an update the person started (a nightly by its name, "Sill nightly 0.6.2 (1600)"), none after one Sill
  installed by itself. The updater keeps it for that launch and puts it in the pane (`Pane.installed`) while no
  other update has the pane's line; Settings › General draws it in green above the check's line.
- **Verified.** `update-install` 984 of 984 (11 new: the rule both ways, the updater asking it at each of the four
  places, the window being General, the line's words for a release and a nightly, none for an automatic update,
  the pane and the green); nine new mutants, 9 of 9. `swift build -c release`. The rehearsal's build
  0.6.96 carries the same edits: what the update to it did on Noah's Mac is in the handoff's
  `one-click-update/rehearsal/RESULTS.md`.
- **Not done:** the menu bar icon's dot for an update that waits (Noah: "Don't worry about the dot for now, we can
  work on a notification system later").
