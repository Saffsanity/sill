**A window Sill sized goes back (2026-10-14, branch `restore-window-frames` from main at 985a733,
PR #75; docs/restore-window-frames-plan.md has the rule, the open questions with the defaults taken,
the review, the results and Noah's steps).** Issue #57 (rosstex): "disconnecting on the iOS app doesn't revert
apps back to their original shape/size on Mac". In regular mode (Virtual Display off) Aa resized the
real window (`StreamCoordinator.fitToViewport`) and nothing put it back, on purpose until now. Host
only; no wire change, nothing on the device, nothing stored.
- The rule (`WindowRestore`, pure; `Tests/checks/window-restore`): each fit's record (`original`,
  the AX frame before Sill first touched it; `set`, the frame read back; `asked`; `moved`, noted at
  a later fit by `movedSince`: at Sill's size its top-left corner elsewhere, at another size both
  edges of an axis gone the same way from where Sill left it, at either of Sill's sizes, so a resize
  from any edge or corner, or with Option, is no move; 2 pt tolerance) and, when the window stops
  streaming, `decide`: gone (nothing), full screen (left, a line), home (nothing), `settle` (Sill
  asked another size and the read-back never showed it: an app that applies a size late, stopped
  first; the original written again, no line), resized on the Mac after Sill's last fit (left
  entirely, a line), unmoved (the whole original frame), moved (its own size where it is, kept on its
  display by `keep`). Lines in the stage's style: "Restored ‹app› — ‹title› to (x,y,w×h)", "…, its
  own size where it was moved", "Left … at (…): it was resized on the Mac", "Left … as it is: it is
  full screen", "Could not restore …", "…: it is not answering Accessibility"; `win.restored` in the
  `[1s]` lines.
- The sequences (WindowRestore's since the review, generic over `WindowRestore.Access`, which
  `WindowSizer.AXWindows` answers through Accessibility, an isolated `@MainActor` conformance, and the
  check's stand-in Mac in the model): `fit`, WindowSizer.resize's (nothing for a window in full
  screen; the frame before, the nudge, the size; a refusal puts the nudge back and records nothing; a
  size gone unanswered, `Write.timedOut` from cannotComplete, puts it back and is recorded from where
  the window was; no read-back: recorded as not yet shown, its old size where Sill put it; the second
  nudge); `stop`, one window's way back (one read: no frame and listed is not answering, left with a
  line; not listed, gone; else `decide` and `put` through `WindowSizer.restore`); `stageHome`;
  `Ledger.restore` (every window that stops but the staged one); `keepsStreaming` and
  `coversDisplay` (below).
- Where: `fitToViewport` records every resize the app took or left unanswered (`WindowSizer.resize`
  returns `Fit`; no fit once `shuttingDown`); `select` restores every fitted window but the next
  source's once the old pipeline has stopped (a pick, the Desktop, `.none` when the last device
  leaves or the stream stops), and its defer every one when nothing streams; `shutdownForExit`
  (Quit, the signals under `HostShutdown.install`) and `releaseKeysForExit` (the CLI's default path
  at a signal) restore every one. `windowsChanged` (the review): a regular-mode window missing from
  the on-screen list keeps streaming through three looks, as a staged full-screen one does, when it
  was full screen when last listed or picked (`listedFullScreen`, `coversDisplay`: the stage's 98 %
  rule) or, fitted, Accessibility says it is full screen (`keepsStreaming`; `missingPolls` reset when
  another source is picked), so a window entering or leaving full screen keeps streaming and its way
  back waits for the real stop; the stream no longer ends there (the device was left on an empty
  panel). Virtual Display turned on while a fitted window streams: `VirtualStage.prepare(…, home:)`
  keeps the frame it would have gone back to (`stageHome`) and the record is handed over
  (`Ledger.take`) only once staged; `restoreFits` skips the staged window (Quit mid-`prepare`).
- Defaults taken (the plan's 19): the CLI's Ctrl-C restores too (a line only when a window was
  sized, the same exit status); full screen at the stop left (it keeps Sill's size when it leaves
  full screen; support.html says so); resized left, position included; moved keeps its place, also
  after a re-fit; a resize a re-fit undid is forgotten, from any edge or corner; a move and a resize
  between two fits judged as the edges show them; a failed restore tried once; nothing after a crash
  or `kill -9` (memory only); a window in full screen never fitted ("… is full screen; not
  resizing."); an unanswered size and a failed read-back recorded; the App Store text unchanged.
- The review (2026-10-14: two should-fix, four nits, each checked against the code, fixed in a
  commit of its own): 1, a window leaving full screen was stopped at the catalog's first miss and its
  way back decided mid-change (cb3045b); 2, a fit of a full-screen window was recorded if AppKit
  answered success (65c6645); 3, a resize from the left or top edge counted as a move (4beb02c; the
  review's simpler rule, no move once the size changed, would forget a move made before a later
  resize); 4, an unanswered size or a failed read-back went unrecorded (913deef; recorded as not yet
  shown, not the size asked, which the model showed wrong for late apps); 5, the check's model was a
  hand-written copy (ecd141a: the sequences are WindowRestore's and the check runs them; the glue
  around them, select, the poll and the stage, is still a copy, and the docs say so); 6, Noah's list
  and the public copy (the docs commit).
- Verified (after the review's fixes; the plan's Results): `swift build -c release` from clean copies of
  origin/main and of this branch, only the CaptureProbe warning; `Tests/checks/run-all.sh`, all 41
  (6 min 5 s on the final code); `window-restore` 41,499 checks (208 cases; the model's 5,000 sessions with windows
  that cannot be resized, full-screen writes answered either way, slow and flaky apps, resizes from
  every edge, and windows off the list on their way into or out of full screen: 214 looks kept
  streaming, 36 windows that left full screen while streaming went back) and 95 of 95 mutants
  (in CI's matrix; the first full run caught 94, F1's pattern gone stale, 299557c); H2 against 985a733: idle identical masked and sorted, a Desktop client identical
  but for the seconds where it comes and goes, as base against base; the restore probe live, 20 of 20
  (the screen unlocked, Noah idle, no device on Sill.app): step 13, the app stopped during a fit, its
  size unanswered then taken late (667×473), put back whole; step 14, the left edge dragged in before
  a re-fit, back whole. No iOS file changed; no screen changed.
- Not verified: Sill.app with a device; anything in full screen live (a full-screen Space would
  take over Noah's screen); the virtual display with a fitted window; the coordinator's glue live (a
  synthetic host picking a window would capture Noah's windows). Known: a pick, Disconnect or Quit
  within the second a window takes to enter or leave full screen may still leave it at Aa's size.
- **Untested, for Noah** (the plan's twelve, with Sill.app from this branch, the iPad, Virtual
  Display off, Aa at 1.5×): pick another window, Disconnect, Quit: back each time ("Restored …");
  moved on the Mac then disconnect: its size where it is; resized from the bottom-right then
  disconnect within 2 s: left; the left or top edge dragged, 2 s, disconnect: back whole at its old
  place; Virtual Display on, then deselect or Quit: back at its old frame; full screen and out again
  from the lights (and the green button) while it streams: the stream goes on, then disconnect: back;
  full screen, disconnect: left in full screen; a window already full screen when picked: never the
  display's size; two devices: only the last to leave restores; a second display unplugged while it
  streams; Terminal, an Electron app, System Settings; the probe again after any change.
