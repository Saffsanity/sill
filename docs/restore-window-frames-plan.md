# A window Sill sized goes back: the plan

2026-10-14. Branch `restore-window-frames` (worktree `/Users/noah/Downloads/winstream-restore-frames`)
from origin/main at 985a733; line numbers are at 985a733. Issue #57 (rosstex): "disconnecting on the
iOS app doesn't revert apps back to their original shape/size on Mac, so everything is shrunken. It
would be great if the windows fix themselves after disconnecting." The triage of 2026-10-13
(`sill-handoff/triage/2026-10-13-open-items.md`) rated it "do soon" and a prerequisite for fitting by
default (#70). Host only; no wire change, nothing on the device.

## The problem

In regular mode (Virtual Display off) Aa resizes the real Mac window to the device's panel at the
text scale it asks for, through Accessibility:

- `StreamCoordinator.fitToViewport` (StreamCoordinator.swift:1089-1101) runs on every pick
  (select's regular path, 1344), every restart of the same window (a rate change, the encoder
  fallback, the catalog's resize check at 2135-2140) and every new viewport
  (`applyViewportToActiveWindow`, 1107-1128). It does nothing until Aa is first touched (the
  device sends no scale before that).
- `WindowSizer.resize` (WindowSizer.swift:27-68) records nothing: no frame before, no element.
- Nothing puts the window back. The last device leaving clears the viewport and selects `.none`
  (401-418, 1294-1297); Quit and the signals release only the virtual display (`shutdownForExit`,
  1848-1853); a pick of another window just streams the next one. The doc comment says so on
  purpose: "nothing ever restores an earlier size on its own" (1087-1088).

Only the virtual display records and restores: `WindowSizer.placement` and `restore`
(172-193, 212-229), `VirtualStage.prepare` steps (2) and (5) (286-293, 316-319), `releaseWindow`,
`release` and the atexit snapshot (649-673, 708-717).

So a window streamed with Aa at 0.75× on a 1000×710 panel stays 1333×947 on the Mac after the
device goes, and one at 1.5× stays 667×473: "everything is shrunken".

This change reverses that for the windows Sill itself sized: each goes back when it stops streaming.

## The design

### The rule (pure: `Sources/SillHost/WindowRestore.swift`)

For each window Sill fits, a record:

- `original`: the frame before Sill first touched it (Accessibility's frame, read just before the
  first resize: the window server's list can be two seconds stale, AX is live).
- `set`: the frame Sill last left it at, as the app took it (read back after the resize: an app
  enforces a minimum, snaps to a grid, or keeps the window on screen).
- `asked`: the size Sill last asked for. An app that applies a size after answering the write reads
  back its old size (VirtualStage.swift's settle loop has the same caveat); at the stop it is at the
  asked size, which is Sill's doing all the same.
- `moved`: the window was found away from where Sill left it at a later fit (the person at the Mac
  moved it, or its app did).

A fit (`WindowRestore.fitted`): the first makes the record; a later one (a rotation, another Aa
step, a restart that resized) keeps `original`, takes the new `set` and `asked`, and sets `moved`
when the window was moved since the last fit (`movedSince`, after the review: at Sill's size, read
back or asked, its top-left corner more than 2 pt from `set`'s; at another size, both its left and
right edges, or both its top and bottom, gone the same way by more than 2 pt from where Sill left it,
at either of Sill's sizes). A resize from any edge or corner keeps the opposite edge where it was, and
one with Option held moves the two apart, so neither is a move: the next fit undoes it and the window
still goes back whole. Once set, `moved` stays.

When the window stops streaming (`WindowRestore.decide`), from its frame now:

1. No frame (the window closed, its app quit): nothing to do (`gone`).
2. Full screen: left as it is (`leave(.fullScreen)`): a window in a full-screen Space refuses moves
   and sizes, and taking it out of full screen is the person's call in regular mode.
3. Within 2 pt of `original`: already home, nothing to do (`home`; no line). Unless Sill asked for
   another size and the app never showed it (`set`'s size is `original`'s, `asked` is not): then the
   original frame is written again, without a line (`settle`). An app that applies a size after
   answering the write, stopped within that moment (a pick right after a pick, Quit right after a
   fit), would otherwise take Sill's size after the stop and keep it; for an app at its minimum the
   write changes nothing. The check's model found this race (Results).
4. Its size is not Sill's (more than 2 pt from both `set` and `asked`): it was resized after Sill's
   last fit, by the person at the Mac. Left alone, position too (`leave(.resized)`).
5. Its size is Sill's and it has not moved (its origin within 2 pt of `set`'s, `moved` false): the
   whole `original` frame (`restore(original, whole: true)`).
6. Its size is Sill's and it was moved: `original`'s size where it is now, its origin nudged so the
   frame stays in the visible area of the display it is on, as a fit keeps it
   (`restore(…, whole: false)`).
7. A target within 2 pt of where it is: `home`.

A resize on the Mac while the window streams is undone today within about two seconds (the
catalog's resize check restarts the pipeline, 2135-2140, and the restart fits the window again,
1344), so rule 4 mostly sees a resize made in the last two seconds before the stop, or after the
fit that a restart would have redone. Such a re-fit keeps `original`: the window goes back to the
frame it had before Sill first touched it, not to the size the person tried for a moment, whichever
edge or corner was dragged (since the review; before, a drag of the left or top edge counted as a
move).

`WindowRestore.Ledger<Handle>` keeps the records by window ID, each with the coordinator's handle
(a `WindowSizer.Placement`: the window's AX element, matched once at the first fit, its pid, app and
title). `stopping(keeping:)` takes out every record but the window that streams next, in window ID
order; `take(_:)` takes one out for the virtual display; `homeForStage` is the frame the stage keeps
as the window's way home. `keep(_:in:)` (moved here from WindowSizer, which calls it) is the one
rule for keeping a frame's top-left reachable inside an area. The log lines are here too, so the
check pins them.

### Where the coordinator calls it

- `fitToViewport`: every resize that went through (the size write accepted), or went unanswered
  (after the review), is a fit for the ledger, with the frames `WindowSizer.resize` now returns
  (`WindowSizer.Fit`: the element, the frame before and the frame after). A fit after `shuttingDown`
  does nothing (nothing would restore it). A window in full screen is not resized (after the review).
- `select`: after the old pipeline stops and the virtual display has sent a staged window home,
  every fitted window but the one about to stream is restored (`restoreFits(keeping:)`): a pick of
  another window or the Desktop, `select(.none)` when the last device leaves or the stream stops,
  each window's restart keeps its own. Its defer restores every fitted window when nothing streams
  at the end (a window that closed, a stream that failed to start).
- `shutdownForExit` (Sill.app's Quit, and the signals under `HostShutdown.install`): every fitted
  window, after the goodbye, beside the stage's release. `releaseKeysForExit` (the CLI's default
  path at a signal, `HostShutdown.installKeyRelease`): every fitted window too, after the keys.
- The virtual display turned on while a fitted window streams (the restart `restartNeeded` asks
  for): `VirtualStage.prepare(…, home:)` takes the frame the window would have been restored to as
  its placement's `originalFrame`, so the stage's own restore (deselect, switch, last device, Quit,
  the signals, atexit's snapshot, a lost display) puts it there; the record is handed over
  (`take`) only once the stage has it. A staging that fails keeps the record. Turning the virtual
  display off sends the staged window home as before; the regular path then fits it from there,
  a new record whose `original` is that home.
- `windowsChanged` (after the review): the streamed window missing from the catalog's on-screen list
  in regular mode keeps streaming through three looks, as a staged full-screen window does, when it
  was full screen when last listed or when picked (its frame covered a display: `coversDisplay`,
  VirtualStage's 98 % rule) or, when Sill fitted it, Accessibility says it is full screen now; unless
  Accessibility and the window server both say it is gone (`WindowRestore.keepsStreaming`). A window
  entering or leaving full screen is off every list for a second or two, and stopping it then decided
  its way back mid-change. It now comes back at the size Sill gave it and keeps streaming.

The two sequences that read and move a window are WindowRestore's since the review, generic over
`WindowRestore.Access` (a window's frame, whether it is full screen, whether the window server lists
it, its display's visible area, the position and size writes, the move home, its name), which
WindowSizer implements with Accessibility (`WindowSizer.AXWindows`) and the check with its stand-in
Mac, so the coordinator, the check and the live probe run the same code:

- `WindowRestore.fit`, WindowSizer.resize's sequence once the window's element is matched: nothing
  for a window in full screen (`FitResult.fullScreen`); the frame before (Accessibility's, else the
  window server's); a nudge so the asked frame stays on its display; the size; a refusal puts the
  nudge back and records nothing; a size that goes unanswered (`Write.timedOut`, Accessibility's
  cannotComplete) puts it back too and is recorded from where the window was, since a busy app may
  take it later; then the size the app took and a second nudge for it; with no read-back, the old
  size where Sill put the window (as a read-back that has not shown the size yet).
- `WindowRestore.stop`, one window's way back: one read first (no frame from a window the window
  server no longer lists is `gone`; none from one it lists means its app does not answer, a beach
  ball, and the window is left with a line after at most a second, instead of up to six seconds of
  writes on the main actor), then `decide`, and a `restore` or `settle` written through
  `WindowSizer.restore` (position, size, position through the element kept from the first fit; a
  window gone is nothing to restore, a `cannotComplete` gets one more try while the window is listed,
  a window left off every display is nudged onto the main one), so a window that is gone, minimized,
  in full screen or refusing AX is handled as the virtual display's is. `Ledger.restore` runs it for
  every window that stops, but the staged one; `stageHome` is the decision's way home, nothing moved.

One line per window acted on, in the stage's style: "Restored Safari — Apple Developer to
(212,95,1280×800)"; "Restored … to (300,140,1280×800), its own size where it was moved"; "Left … at
(…): it was resized on the Mac"; "Left … as it is: it is full screen"; "Could not restore … to
(…)". None for a window that is gone or already home. `win.restored` counts in the `[1s]` lines
when it happens.

`WindowSizer.resize` also undoes its own nudge when the app refuses the size (it moved the window
first to keep the asked frame on screen, then the size write failed): before, such a window stayed
moved with nothing to say so.

### What does not change

- The Desktop is never fitted, so a Desktop stream (and every synthetic test host's) prints and
  does exactly what it did: the CLI's stdout on a synthetic host is unchanged (H2 below).
- Changed after the review: a window streaming in regular mode that leaves full screen (or enters
  it) no longer ends the stream when the catalog looks while it is off the list (the device was left
  on an empty panel); it keeps streaming, as a staged window already did.
- The virtual display's own placement, restore and atexit snapshot: unchanged but for the home it
  is given.
- No wire change, no device change, no setting, nothing stored: the records live in memory for
  the life of the host.

## Open questions, and the default taken for each

1. **A signal in the CLI's default path** (no `--virtual-display`): restore there too? Default:
   yes. `releaseKeysForExit` restores after the keys, so a Ctrl-C of `swift run SillHost` puts a
   window back; it prints one "Restored" line only when a window was fitted, and dies of the signal
   with the same status as before. HostShutdown's comment changes with it.
2. **Full screen at the stop**: leave it, with a line. The window returns to Sill's size when it
   leaves full screen. Alternative: take it out of full screen first, as the virtual display does
   (`leaveFullScreenIfNeeded`); rejected for regular mode, where full screen may be the person's.
3. **Resized on the Mac after the last fit**: leave it entirely, position included (Noah's
   statement of the issue: "if it was resized on the Mac meanwhile, leave it").
4. **Moved**: its own size where it is, kept on its display as a fit keeps it.
5. **A move between fits**: remembered (`moved`), so a rotation after the person moved the window
   does not later send it back to its old place.
6. **A resize on the Mac that a re-fit undid**: forgotten; the original frame is still the way home.
7. **Restore whenever nothing streams the window**: also after a stream that failed to start, a
   capture that stopped, a window picked again after a failed start. Default: yes (select's defer).
8. **Lines**: one per window acted on (restored, left, could not); none when gone or already home.
9. **A re-fit's element**: the first fit's element is kept (an AX element stays valid while its
   window exists); a re-fit matches the window again only to resize it.
10. **A restore that fails**: tried once and forgotten, as the stage does.
11. **A crash or `kill -9`**: no restore. Records are not persisted: a frame applied to a window at
    the next launch, perhaps days later, is worse than none.
12. **Turning the virtual display on with a fitted window**: staged with the frame it would have
    been restored to as its home (above).
13. **The App Store text**: unchanged. "Aa makes text larger or smaller" stays true; the next What's
    New is written from the release notes at release time.
14. **Undo a nudge after a refused size** (`WindowSizer.resize`): yes, at once.

Added by the review's fixes (2026-10-14):

15. **A resize from the left or top edge, or a corner, that the next fit undid** (finding 3): not a
    move; the window goes back whole. A move and a resize between two fits are judged as the frames
    show them (both edges of an axis gone the same way: moved), since where they ended can be either.
    The review's simpler rule, no move once the size changed, would forget a move made long before a
    later resize (a move alone starts no re-fit), and the window would jump back to its old place.
16. **A window in full screen at a fit** (finding 2): not resized, one line ("… is full screen; not
    resizing."), nothing recorded. Whatever AppKit answers there, recording it took the display's
    frame for the window's.
17. **A size write with no answer in time** (finding 4): recorded as asked, from where the window
    was (its nudge put back), so a busy app that takes it later still goes back.
18. **A size write that went through with no read-back** (finding 4): recorded as a read-back that
    has not shown the size yet, the old size where Sill put the window. The review suggested the
    size asked; the check's model showed that wrong for an app that also applies sizes late (the
    stop found it at its own frame, nothing to settle, and the size landed after). For an app that
    clamps to a minimum and takes a size unseen, a stop that comes before the next fit sees it judges
    it resized on the Mac and leaves it; the next fit (the catalog's resize check, within about two
    seconds) heals the record.
19. **A window off the list while entering or leaving full screen** (finding 1): three of the
    catalog's looks, as a staged window has, for any regular-mode window that was listed in full
    screen and for one Sill fitted that Accessibility says is full screen. Also when Sill did not fit
    it: the stream goes on rather than end on an empty panel. Left: a pick, Disconnect, Quit or a
    restart within that second still decides mid-change, and so does a window Sill never saw in full
    screen whose flag is already down when the catalog misses it; either may stay at the size Aa gave it.

## The test plan

- **The check** `Tests/checks/window-restore` (WindowRestore.swift alone, Foundation and
  CoreGraphics; in CI's run and its mutants matrix): `keep` at every edge; `fitted` first and
  later, `moved` at its 2 pt edge and staying set; `decide` for every outcome at its edges (gone,
  full screen, home, resized against `set` and `asked`, unmoved, moved by origin and by flag, the
  nudge on every edge, no area, a target already reached); the ledger (`stopping` keeps one and
  returns the rest in order, `take`, a re-fit keeping the first handle); `homeForStage` for each
  outcome; every line. Then a model of the coordinator's glue: random sessions of picks, viewports,
  the person moving and resizing windows, apps that clamp, snap or apply late, windows that close
  or go full screen, the virtual display on and off, the last device leaving and Quit, against an
  oracle of where each window must end: every transition the issue names (first fit, re-fit,
  switch away, last device, quit, moved, resized, gone, virtual display on and off). Mutants of
  WindowRestore.swift, every one caught. After the review: the sequences (`fit`, `stop`,
  `stageHome`, `Ledger.restore`, `keepsStreaming`) against a stand-in window that logs every call,
  and the model's stand-in Mac answering the real sequences; the glue around them (select, the
  catalog's poll, the stage) is a copy of the coordinator's, written again in the check, and can
  drift from it.
- **Builds**: `swift build -c release` (only the known CaptureProbe warning). No iOS file changes.
- **`Tests/checks/run-all.sh`**: all.
- **H2, the CLI's stdout**: origin/main's `SillHost` and this branch's, each built from
  `git archive`, `--synthetic` with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1
  SILL_TEST_NO_ROUTER=1`: idle 35 s, and a test client picking the Desktop; digits masked, lines
  sorted: identical. Only while no device is connected to Sill.app (no-device.sh), though neither
  touches the hardware encoder.
- **Live, with Accessibility** (only if this shell is trusted, `AXIsProcessTrusted()`, read
  without prompting): `Scripts/restore-probe/run.sh`. An AppKit app of its own (`owner.swift`, a
  bundle that never activates) makes one window at the lower left, behind every other window, and
  a driver compiled with the real `WindowSizer.swift` and `WindowRestore.swift` fits it as
  `fitToViewport` does and restores it as `restoreFits` does, frames before, during and after: a
  stop (whole frame), a rotation's re-fit then a stop, moved (the owner app moves its own window)
  then a stop, moved then re-fitted, resized (the owner resizes it) then a stop, an app minimum
  (the owner's `minSize`), a window that closes, the nudge at the display's edge, a window that
  cannot be resized (its nudge put back), an app that does not answer (`SIGSTOP`), the stage's way
  home worked out, and two windows (a pick, then the last device leaving); after the review, an app
  stopped during a fit (its size unanswered and recorded, taken once it runs again, then put back) and
  the left edge dragged in before a re-fit (the whole frame back). The front app is read before and
  after and must not change. Never one of Noah's windows, never a virtual display, never input.
- **Untested, for Noah**, with a Sill.app built from this branch and a device: below, in Results.

## Results

All on 2026-10-14, on this Mac (macOS 27.0, M2 Pro, one 1512×982 display), with Sill.app idle and no
device connected (`Scripts/encoder-check/no-device.sh` before each host). The first round's, then the
review's and its fixes' (below).

- **The check**, `Tests/checks/window-restore`: 41,391 checks pass in about 4 s: 90 cases of the
  rule at its edges, then the model's 5,000 sessions (20 to 80 steps each). What came up in them:
  10,493 first fits, 5,393 re-fits, 6,417 fits refused (full screen); stops by a switch 4,319, the
  Desktop 1,410, `.none` 2,150, Quit 600, a window gone 252; decisions whole 7,164, moved 726,
  resized 250, full screen 307, home 2, settle 30; 1,702 windows staged with a home and 60 as
  found, 11,332 stage releases, 2,223 restarts by the catalog's resize check. The model asserts
  that every one came up.
- **What the model found.** Its first run failed 12 sessions: a window of an app that applies a
  size after answering the write (the model's `late` app) ended at Sill's size. A stop right after
  a fit (Quit in the model, a pick right after a pick on a real Mac) read the window at its
  original frame, so there was nothing to do, and then the app applied the fit's size. Fixed by
  `settle` (rule 3): the original frame is written again, without a line, when Sill asked for
  another size and the read-back never showed it. Unit cases and mutants W12 to W14 hold it.
- **Mutants**: 48 of 48 caught (`run.sh --mutants`, 3 min 24 s): the first fit, re-fits and moves,
  every decision and its order, the tolerance (0, 3, and strict compares), `keep`'s four edges and
  their order, the stage's way home, the ledger (the handle, the record, stopping's order and
  what it takes out, `take`), and every line.
- **Builds**: `swift build -c release`, only the known CaptureProbe warning; the CLI built again
  from `git archive` of this branch for H2. No iOS file changed, so no iOS build.
- **`Tests/checks/run-all.sh`**: all 41 passed (383 s), `window-restore` among them.
- **H2, the CLI's stdout** (origin/main at 985a733 against this branch, each built from
  `git archive`; `--synthetic` with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1
  SILL_TEST_NO_ROUTER=1`; two rounds, alternating): idle 35 s identical, masked and sorted (7
  lines each); with `sillclient.py PORT 22 desktop` (about 34 fps of the test pattern on the
  software encoder), identical without the `[Ns]` stats lines, and with them differing only in the
  last partial second's line, which differs the same way between two runs of the same build (base
  against base, new against new). No "Restored", "Left" or "Could not restore" line in any run.
- **Live, the first round: not run.** Accessibility was trusted here (`AXIsProcessTrusted()` true,
  read without prompting) and Screen Recording too, but the console session was locked with the display asleep
  (`CGSSessionScreenIsLocked` 1, `CGDisplayIsAsleep`, no input for 7.8 hours). A window the probe
  made then was listed by the window server at about 0.9 of its frame about the display's middle
  (900×632 at (20,328) listed as 811×570 at (93,344)), and Accessibility listed only a placeholder
  for its app (its name at (0,0), size 0): the same unbundled and as a bundle, with and without
  the opening animation, ordered front or back. So `WindowSizer.resize` matched nothing ("no
  Accessibility window matches") and no window could be fitted or put back. The probe is
  `Scripts/restore-probe/run.sh`, built here; it now refuses while the screen is locked (exit 2,
  checked). Nothing of Noah's was moved or sized; the diagnosis read window bounds only. The review
  ran it later with the screen unlocked (17 of 17), and so did the fixes (below).

### The review and its fixes

An adversarial review of the pull request (2026-10-14) found two faults worth fixing and four nits,
each checked against the code before it was fixed, one commit each:

- **1. Leaving full screen while a fitted window streams lost its record** (should fix; cb3045b).
  In regular mode the catalog stopped the streamed window (`select(.none)`) the first time it was
  missing from the on-screen list; only a staged full-screen window had three polls of grace, though
  the code says a window leaving full screen is off every list for a second or two, and the device's
  full-screen light makes the catalog look at once. The stop then decided mid-change: still full
  screen ("Left … as it is"), or at the display's frame or mid-animation ("resized on the Mac"); the
  record was gone when the window settled at Sill's size. Fixed by `WindowRestore.keepsStreaming` in
  `windowsChanged` (open question 19): three looks for a window full screen when last listed or
  picked (`coversDisplay`) or, fitted, full screen to Accessibility, unless both Accessibility and the
  window server say it is gone. The check's model could not see this case (its catalog only took a
  closed window off the list); its windows now go off the list for a step or two on the way into or
  out of full screen, Accessibility reading the flag flipped or not and a frame from, to or between.
- **2. A fit of a window in full screen was recorded if AppKit answered success** (should fix;
  65c6645). The model assumed an error; nobody had measured it. With success and nothing changed, a
  restart after going full screen recorded the display's frame and a move, and a window full screen
  when picked recorded the display's frame as its original (the review's scratch traces: back to the
  nudge instead of its own place, and as large as the display; the check with success answers failed
  105 of 47,532). Fixed in `WindowRestore.fit`: nothing read or written but AXFullScreen for a window in
  full screen. The model's Mac answers full-screen writes one way or the other per session; mutant F0
  is caught 31 times by the model.
- **3. A resize from the left or top edge counted as a move** (nit; 4beb02c). The re-fit kept the new
  top-left corner and `fitted` noted a move, so the window went back at its own size at the shifted
  place. Fixed by `movedSince` (open question 15). Judged from the frame read back alone, the model's
  first run with edge resizes failed 52 checks (the one traced: an app that applies sizes late, which
  reads back its old size), so a resized window is judged from either of Sill's sizes; the one session
  left was two resizes between fits (top edge, then bottom), which look like a move, and the oracle
  now takes either way back after such compound changes. The model's person resizes from any edge or
  corner or with Option.
- **4. A resize Sill made could go unrecorded** (nit; 913deef): a size write that went through with a
  failed read-back, and one that timed out and landed later. Fixed in `WindowRestore.fit` (open
  questions 17 and 18). The review's suggested record for the first (the size asked) failed 3 of the
  model's sessions (the one traced: an app that also applies sizes late, read at its own frame at the
  stop, nothing to settle, the size landing after); recorded as not yet shown, all pass. The model's
  Mac has slow and flaky apps; the restore probe's step 13 shows the second case live.
- **5. The check's "model of the glue" was a hand-written copy** (nit; ecd141a). The sequences that
  read and move a window are WindowRestore's now, over `WindowRestore.Access`, which
  `WindowSizer.AXWindows` answers through Accessibility (an isolated `@MainActor` conformance) and the
  check's Mac in the model: `fit`, `stop`, `stageHome`, `Ledger.restore`, `keepsStreaming`. The
  model's counts were the same as before, decision by decision, with the sequences moved. What the
  check still copies is the glue around them (select, the catalog's poll, the stage), and this plan,
  CLAUDE.md and the pull request say so.
- **6. Noah's list and the public copy** (nit; this commit): the probe has run; the list gains the
  flows above, two devices and a display unplugged while it streams; support.html says a window left
  full screen keeps Sill's size when it leaves full screen, and that with several devices the last to
  disconnect restores it; README's How it works says "your last device disconnects".

Verified after the fixes (2026-10-14; the build machine was shared with other agents, load averages
up to several hundred, so times are long):

- **The check**, `Tests/checks/window-restore`: 41,499 checks pass in about 5 s: 208 cases of the
  rule and the sequences, then the model's 5,000 sessions: 9,510 first fits, 4,788 re-fits, 1,706
  refused (windows that cannot be resized), 6,376 not tried in full screen, 897 sizes unanswered and
  734 read-backs failed; 10,162 resizes from an edge or corner (195 re-fits right after one) and 34
  compound changes between fits; 3,666 windows off the list on their way into full screen and 784 out
  of it, 214 looks that kept a window streaming, 96 stops mid-change (counted, not judged), and 36
  windows that left full screen while they streamed and went back at their stop; stops by a switch
  3,946, the Desktop 1,274, `.none` 1,937, Quit 535, a window gone 243; decisions whole 6,112, moved
  602, resized 262, full screen 612, home 4, settle 117; 1,507 windows staged with a home and 51 as
  found, 11,550 stage releases, 2,225 restarts by the resize check. The model asserts every one came
  up.
- **Mutants**: 95 of 95 caught (`run.sh --mutants`, 11 min 8 s): F0 to F7 the fit, S1 to S11 the
  stop and the ledger's restore, T1 to T5 an unanswered size and a failed read-back, E1 to E10 and W4
  to W6 a move, G1 to G9 the grace, C1 to C4 the full-screen frame, and the first round's 48. The
  first full run after the fixes caught 94 of 95 (12 min 41 s): F1's pattern no longer matched the
  nudge line, so it was not applied; matched again (299557c), it is caught.
- **`Tests/checks/run-all.sh`**: all 41 passed (6 min 25 s), and again on the final code (299557c) in 6 min 5 s.
- **Builds**: `swift build -c release` from clean copies, origin/main (985a733) in 1 min 28 s and this
  branch's tracked files in 55 s, only the known CaptureProbe warning in each; every commit built
  incrementally in the worktree with no new warning, and the restore probe's driver and owner compile.
  No iOS file changed, so no iOS build; no screen changed, so no harness photos.
- **H2, the CLI's stdout** (origin/main at 985a733 against this branch, each from a clean copy;
  `--synthetic` with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1`, each
  host started only while no device was connected to Sill.app and ended by SIGTERM, exit 143; two
  rounds, alternating): idle 35 s identical, masked and sorted (7 lines each); with
  `sillclient.py PORT 22 desktop`, identical without the `[Ns]` lines, and the `[1s]` lines identical
  masked but for the seconds where the client comes and goes, which differ the same way between two
  runs of the same build (base against base, new against new). No "Restored", "Left", "Could not
  restore" or "Window sizing" line in any run.
- **Live, the restore probe** (`Scripts/restore-probe/run.sh`, the screen unlocked, the display awake,
  Noah idle 97 minutes, no device on Sill.app): 20 of 20 in 35 s, the front app unchanged. Steps 1 to
  12 as the review saw them (step 9: AppKit answers -25200 to a window that cannot be resized, and the
  nudge is put back; step 10: not answering after 1.00 s, left at Sill's size). Step 13, new: the app
  stopped once its window was matched, the fit took 3.02 s (three one-second timeouts) and recorded
  the size as unanswered; after SIGCONT the app took the size late (667×473), and the stop put the
  window back whole (20,73,900×600): before the fix nothing was recorded and it would have stayed at
  667×473. Step 14, new: the left edge dragged in 60 pt, a re-fit at (80,73,667×473), the stop: back
  whole at (20,73,900×600), not its own size at (80,73).
- **Not run**: Sill.app with a device; anything in full screen live (a full-screen Space would take
  over Noah's screen); the virtual display with a fitted window; the coordinator's glue live (a
  synthetic host picking a window would capture Noah's windows for its catalog). No iOS file changed,
  so no iOS build; no screen changed, so no harness photos.

### Untested, for Noah

With Sill.app from this branch (`Scripts/make-app.sh --install --open`) and the iPad, Virtual Display
off, and Aa slid to 1.5× while a window streams:

1. Pick another window: the first goes back to its old frame, Sill.log "Restored ‹app› — ‹title› to
   (x,y,w×h)". The same after Disconnect, and after Quit Sill.
2. Move the window on the Mac, then disconnect: its own size where it is now, "…, its own size where
   it was moved". The same with a rotation of the iPad after the move.
3. Resize the window on the Mac from its bottom-right corner and disconnect within about two seconds
   (before the next fit undoes it): left as it is, "Left … at (…): it was resized on the Mac".
4. Drag its left edge (or its top edge) on the Mac, wait two seconds (it snaps back to the device's
   size, the new left edge kept), then disconnect: back at its old frame and place, "Restored … to
   (…)", not "where it was moved".
5. Turn Virtual Display on (the Mac's menu or the iPad's panel): the window moves to the virtual
   display; deselect or Quit: it comes back at its old frame, not the size Aa gave it.
6. Full screen from the thumbnail's lights, then out of full screen from the lights while it streams:
   the stream goes on (no empty panel), the window back at the size Aa gave it; disconnect: back at
   its old frame. The same with the Mac's green button.
7. Full screen from the lights, then disconnect while it is still full screen: left in full screen,
   "Left … as it is: it is full screen"; out of full screen afterwards it keeps the size Aa gave it
   (resize it yourself), as support.html says.
8. A window already full screen when you pick it: no "Resized" line (Sill.log "Window sizing: … is
   full screen; not resizing."); out of full screen while it streams, then disconnect: back at its own
   frame, never the display's size.
9. Two devices streaming the same window: the first to disconnect changes nothing; the last puts the
   window back.
10. A window on a second display, that display unplugged while it streams, then disconnect: on the
    main display at its own size, never off every display.
11. Apps that size differently: Safari, Terminal (a character grid), VS Code or another Electron app
    (may apply a size late: back at its frame, no line when settled), System Settings (a fixed
    width).
12. `Scripts/restore-probe/run.sh` once more after any change here (20 of 20 on 2026-10-14).

Known, and left: after a crash or Force Quit of Sill the window stays at the size Aa gave it; a pick,
Disconnect or Quit within the second a window takes to enter or leave full screen may still leave it
at the size Aa gave it, and so may a window Sill never saw in full screen whose full-screen flag is
already down when the catalog misses it.

## Progress

- 2026-10-14: plan written; worktree from origin/main at 985a733.
- 2026-10-14: the rule, the check (90 cases and the model; the late app's race found and fixed
  with `settle`), 48 of 48 mutants, the coordinator, WindowSizer, VirtualStage and HostShutdown,
  CI's mutants matrix (eda1c27).
- 2026-10-14: H2, `run-all.sh`, the probe script (refuses while the screen is locked), docs (this
  plan's Results, CLAUDE.md, docs/DEVELOPMENT.md, README's How it works, site/support.html,
  Tests/checks/README.md) (d804132, abb5b94); a clean `swift build -c release` of abb5b94 from
  `git archive`, only the CaptureProbe warning. Pull request #75, left open for Noah.
- 2026-10-14: the review (two should-fix, four nits), each fixed in a commit of its own: the fit and
  the stop as WindowRestore's sequences, run by the check (ecd141a); no fit in full screen (65c6645);
  an unanswered size and a failed read-back recorded (913deef); a resize from an edge is not a move
  (4beb02c); a window entering or leaving full screen keeps streaming (cb3045b); the restore probe
  live, 20 of 20; the full mutants run, 94 of 95, then F1's stale pattern matched again and the check's
  header (299557c), 95 of 95; docs and Noah's list (this commit).
