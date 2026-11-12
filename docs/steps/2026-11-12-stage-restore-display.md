**A staged window goes home before Sill's display goes (2026-11-12, branch `stage-restore-display` from main at
0d22bbf; draft PR #358; fault A of Noah's test of PR #355, merged into `desktop-displays` so he tests both together).**
Noah, testing #355 with the lid closed, the Lenovo as the main display and the Dell to its left: "when I have a window open
on Display 2 (for example) and switch to windowed mode and back, it puts the window on Display 1 for some reason. Windows
should return to the display, size and position they were in before windowed mode". That sentence is a requirement.
- What happened (Sill.log, twice in a row; macOS's log of that second saved in
  ~/Downloads/sill-handoff/triage/2026-11-12/restore-display/): Google Chrome, filling the Dell at (-1920,186,1920×1050),
  was picked and staged on Sill's display (2560,30,2234×1220); when the Desktop was picked, `select` ran `stage.release()`:
  `releaseWindow()`'s Accessibility writes sent Chrome home and `destroyDisplay()` removed the display in the same main-actor
  turn (04:30:10.716). The window list shows an Accessibility move only once the app commits it, a few to tens of
  milliseconds after the writes return (VirtualStage's `lastReleased`, 2026-09-23); the window server still had Chrome's
  window (0x5a) on the removed display's space, moved it to the main display's ("window 5a joined space 1" at .726), and
  Chrome, which had filled its screen, filled the main one (0,30,2560×1410: "occludedByWindow=Google Chrome(0x5a) …
  display=65" at .799). The next pick took that for its home. Earlier the same night the same order left Chrome home
  (03:03:53): a race. Main has it as well: VirtualStage.release (VirtualStage.swift, `release()`: `releaseWindow()` then
  `destroyDisplay()`) and select's way out (StreamCoordinator.swift, the `else { … stage.release() }` of "The stage follows
  the selection"), unchanged by #355.
- The rule (`StageRelease`, pure; `Tests/checks/stage-release`): Sill's display goes only once the window server shows the
  window off it (listed at its home, anywhere off the display, or not listed: closed), read every 10 ms, or after 1 s (an app
  that never commits, a hung one); once it has gone the window is watched for 1.5 s and put back once if macOS moved it (or
  it never left in time), compared with where it was once off the display (a window kept on the main display because its
  home display was unplugged stays there). 2 pt on every edge is the same place.
- Where (`VirtualStage.releaseHome()`, async): select's Desktop or nothing, Virtual Display turned off, the off-console view,
  a window not found, a staging that failed (its window already sent home by `prepare`: `homeward`, the window and the
  display it left, is waited for), a capture on the display that failed, a stream that did not start, a lock mid-switch
  (`lockedMidSwitch` is async now). Unchanged: a pick of another window keeps the display (`releaseWindow` alone); Quit, the
  signals and a shutdown mid-switch keep the synchronous `release()` (they cannot wait); the display's own loss
  (`lost(generation:)`); the grow path's recreation (the window is re-placed on the new display).
- Lines: "Removed virtual display 81 (Google Chrome home after 38 ms)", or "(Google Chrome was still on it after 1000 ms)";
  "Put Google Chrome — … back at (…): macOS had moved it to (…) as Sill's display went." (`vd.putBack`); the CLI's output is
  unchanged where no window is staged.
- Why this order and not the Desktop first: starting the Desktop's capture while Sill's display still exists, and removing
  it under a running capture, is a display reconfiguration during ScreenCaptureKit's start that nothing here can test (no
  real display may be made or captured on this Mac tonight, and a capture of the wrong display was seen tonight, cause
  unknown); the wait is the app's commit time, tens of milliseconds, before a switch that takes hundreds anyway, and 1 s at
  worst.
- Verified (05:08–05:12, on main 0d22bbf with this change): `swift build -c release`, only the CaptureProbe warning;
  `Tests/checks/stage-release` 847 checks (the model: 402 commit times each way, 0 to 2,000 ms and never; the old order
  lost 401 windows, every one but a commit at 0 ms; the new order brought every one home, removed within 20 ms of a commit
  up to 1 s with no put-back, past it removed at 1 s and put back once) and 25 of 25 mutants (20 of the rule, 5 of the
  wiring); `Tests/checks/repo-rules` 10 of 10; H2 against main's CLI (0d22bbf, from git archive), synthetic hosts on
  loopback with the software encoder and no screen, idle 35 s and with a test client: identical masked and sorted but for
  the once-a-second lines' counters, a heartbeat and the order the client first met each kind in (7 of 7, 12 of 12 and 33 of
  33 lines identical without them): no window is staged there, so nothing of this runs.
- Not verified: anything with a real window on a real display (Chrome, the Dell, the commit time of a real app, macOS
  moving a window on the removal and the put-back's effect on it): no display may be made or changed on this Mac while
  Noah tests, and the bounded probe below waits for a minute with no device connected.
- **Untested, for Noah:** with Virtual Display on and two monitors, pick a window on each monitor (Chrome filling the Dell,
  as tonight, and one not filling its screen), then the Desktop, then the window again, five times each: the window stays on
  its monitor at its size and place; Sill.log "Restored …", then "Removed virtual display N (… home after N ms)", and no
  "Put … back" line unless a window came back late; disconnect while a window streams (the same); Virtual Display off while
  a window streams (the same); Quit while a window streams (as before: the window back, the display gone at once).
