# The Settings window on a small screen: the plan

2026-10-14. Branch `settings-window-height` (worktree `/Users/noah/Downloads/winstream-settings-height`,
PR #74) from origin/main at 985a733; line numbers are at 985a733. Issue #59 (rosstex, a 14-inch MacBook Pro
on macOS 26.6.2, Sill 0.5.1 (563)): "The Remote Access settings on Mac are too tall and cannot be
resized." Mac app only: no wire change, nothing on the iOS side, the CLI untouched.

## The problem, measured

The Settings window is as tall as the selected pane's whole content, whatever the screen.

- `SettingsWindowController` makes an `NSWindow(contentViewController:)` of an `NSTabViewController`
  in toolbar style, without `.resizable` (SettingsWindow.swift:43-44). Each tab is an
  `NSHostingController` with `sizingOptions = [.preferredContentSize]` (SettingsWindow.swift:89-92)
  around a grouped `Form` 520 pt wide with no height limit (SettingsPanes.swift:27-28).
- A scratch AppKit probe of the same setup on this Mac (macOS 27.0.1, not committed) showed how the
  height is set. AppKit gives the selected pane's view a constraint named
  `NSViewController.preferredContentSize.height`, the pane's height equal to the hosting
  controller's `preferredContentSize` (SwiftUI's ideal size: the whole Form), at priority 501, just
  over the window's own 500 for keeping its size. Auto Layout then sets the window's frame in the
  display cycle (`NSWindow(NSConstraintBasedLayoutInternal)` calling `setFrame(_:display:)`),
  keeping its top-left corner. A 40-row pane made a 1,653 pt window and a 50-row one 2,028 pt, its
  bottom 1,128 pt below the screen. AppKit's own `constrainFrameRect(_:to:)` shortens only
  resizable windows, and it is not on this path anyway.
- The constraint follows growth live (a switch turned on), and every tab switch makes a new one
  at that tab's full height. In the probe it did not follow shrinking: its pane (a `ForEach` over a
  count) made shorter, or a SwiftUI height limit lowered while it showed, left the window at its old
  height. Sill's own Remote Access pane did shrink the window when the internet switch went off
  (Results), so this varies with the pane; the cap below does not depend on it.
- The panes' natural heights (the previews at 985a733, pixels ÷ 2): Remote Access 700 to 703 pt
  with Tailscale and the other VPNs' rows, 754 with a port warning, 949 to 983 with "Allow
  connections from the internet" on; General 738; Streaming 474; Devices up to 435; Permissions
  275; Virtual Display 231. In the live window in test pattern mode (Results): General 727,
  Streaming 568, Remote Access 327 off and 909 on with the internet switch and this Mac's
  addresses. The window adds the title bar and the toolbar: 80 pt in Sill's window (88 in the
  probe's, whose toolbar differed).
- The screens: this Mac's 14-inch display at its default scaling is 1,512 × 982 pt, 949 pt under
  the menu bar (33 pt on macOS 27, measured; the Dock hidden here). A Dock at the bottom takes
  some 70 pt more. The scalings with larger text make the screen 878, 745 or 665 pt tall before
  the menu bar and the Dock, and More Space 1,169. Against the cap below (the visible frame less
  the chrome and 12 pt above and below): the Remote Access pane with the internet switch on (909 to
  983 pt, a 989 to 1,063 pt window) fits a 14-inch only at More Space, and at its tallest not there
  with the Dock; rosstex's 951 pt window fits only at More Space; the General pane (727, an 807 pt
  window) fits at the default scaling, Dock or not, and at 1,352 × 878 with the Dock hidden, but
  not at the larger-text scalings with the Dock, nor at 1,147 × 745 or 1,024 × 665 without it.
  `Tests/checks/settings-window` has each case.

## The design

### The cap: one constraint the window controller owns

`SettingsWindowController` adds one `NSLayoutConstraint` to the window's content view (the tab
controller's view): its height at most the limit for the window's screen, at priority 750
(`.defaultHigh`), over AppKit's 501 and the window's 500. The panes are grouped Forms, which scroll
when given less than their content. The probe, with the same setup and this constraint:

| Step | Window frame | The pane shows | Its content |
|---|---|---|---|
| shown on the 40-row pane, cap 600 | 688 | 600 | 1,565 (scrolls) |
| a 6-row pane | 378 | 290 | 290 |
| that pane grown to 50 rows | 688 | 600 | 1,940 (scrolls) |
| cap lowered to 400 while it shows | 488 | 400 | 1,940 |
| cap raised to 800 | 888 | 800 | 1,940 |
| the 40-row pane, then a 4-row one | 888, then 303 | 800, then 215 | 1,565, then 215 |

No frame on the way was taller than the cap, and AppKit reported no conflict. Two other places for
the cap failed in the same probe: an `NSHostingController` subclass clamping `preferredContentSize`
(SwiftUI never calls its setter: the subclass saw nothing and the window grew as before), and a
SwiftUI `.frame(maxHeight:)` on the pane (it capped the window at first, but lowered while a pane
showed it left the window tall, the Form centred in it, because the probe's 501 constraint did not
follow it down). An `NSWindow` subclass clamping `setFrame` would fight Auto Layout, which sets the
frame from the constraints at every layout pass.

The constraint's constant is `SettingsWindowFit.contentLimit`, set by `refit()`:
- at `show(tab:)` (before and after `WindowPlacement.bringForward`, which may move the window off
  Sill's virtual display),
- on every tab switch (`SettingsTabController.tabView(_:didSelect:)`; the Dock may have changed
  since),
- on `NSApplication.didChangeScreenParametersNotification` (a display added or removed, its
  resolution, the Dock),
- on `windowDidChangeScreen(_:)` (the window dragged to another display).

### The arithmetic: `SettingsWindowFit` (pure, `Tests/checks/settings-window`)

`Sources/SillMenuBar/SettingsWindowFit.swift`, CoreGraphics only:
- `screenIndex(windowOn:screens:)`: the screen whose visible frame bounds the window: the one it is
  on; on none, or on Sill's own virtual display (where a streamed window lives, off the user's
  screens), the first other screen, where `bringForward` puts it.
- `visible(_:testHeight:)`: that screen's `visibleFrame` (under the menu bar, beside the Dock), or,
  TEST ONLY, its top `testHeight` points.
- `contentLimit(visible:chrome:)`: the visible height less the window's chrome (frame height less
  content height, read from the window: the title bar and the toolbar, 80 pt on macOS 27.0.1) and
  a margin of 12 pt above and below, in whole points, never under 200. On this Mac's 949 pt: 845.
- `placed(_:in:)`: where the window goes. Unchanged while it lies within the visible frame top to
  bottom. Its bottom below it (under the Dock, or off the screen): moved up to 12 pt above the
  bottom, or as far as keeps its top inside. Its top above it: moved down to 12 pt under the top,
  or as far as keeps its bottom inside. Taller than the visible frame: its top at the top, so the
  title bar stays reachable. Never resized, never moved sideways.

### The move: only after Sill's own changes

`windowDidResize(_:)` (the layout's resize after a tab switch, a pane that grew, or a new cap) and
`refit()` apply `placed`, but only while the window is on screen and no mouse button is down: a
window the user is dragging is never moved under the pointer; a move that falls due then waits for
every button to be released (`placeOnRelease`, a Timer in the common modes looking ten times a
second). A window the user left partly off the screen stays there until Sill next changes its size
or shows it. A new cap lays a window on screen out at once (`layoutIfNeeded`) before it is placed:
placed at its old height and then shortened from the bottom, it would keep no margin above (seen in
the first runs: its top at the top of the visible frame). `show` lays the window out after
`bringForward` and places it then.

AppKit places the window too, and `placed` keeps what it does whenever the window fits: a saved
frame sets where the window's top-left goes (its pane, not the saved frame, sets its height), and
a window that ran off the bottom of the screen while it was hidden is ordered in with its bottom at
the screen's bottom (seen with the Dock hidden). A window inside the visible frame is never moved,
so the 12 pt margin is kept only on a side Sill moved the window away from: a capped window can
sit right under the menu bar with all 24 pt over the Dock, or on the screen's bottom with the 24 pt
above it (Results).

### Hooks (TEST ONLY; the bare SillMenuBar binary)

- `-SillSettingsAfter '<s> <tab>[; <s> <tab> …]'`: opens Settings on that tab s seconds after
  launch, through the menu's own path, and 0.6 s later prints one line with the window's frame, its
  content and chrome, the pane's whole height and what it shows (the Form's scroll view: its
  visible height against its content's, and how far it is scrolled), the screen's visible frame
  and the one used, the limit, and the room above and below the window. A tab is its name or the
  start of one (`remote`, `general`); `close` closes the window, `report` prints it as it stands,
  `end` scrolls the pane to its last row, and `height=<points>` sets `-SillTestScreenHeight` (0:
  the screen's own) and posts `NSApplication.didChangeScreenParametersNotification`, so the path a
  real change of display or Dock takes runs.
- `-SillTestScreenHeight <points>`: the cap and the move use the top `<points>` of the screen's
  visible frame, as if the screen were that short with the Dock at its bottom, so the cap shows on
  a large screen.
- `-SillSettingsShot <dir>`: each `-SillSettingsAfter` step also writes the window (its title bar,
  toolbar and pane, as `cacheDisplay` draws them) to `<dir>/settings-<s>s-<tab>.png`.

Sill.app itself ignores all three with one line each, as it does every `-Sill…After` hook
(`DebugHooks.timedHooks` and `windowHooks`, under `AppModel.bundled`).

## Open questions, with the default taken

1. **The margin.** The cap leaves 12 pt for above and below the window, 24 in all, and a window
   Sill moves keeps 12 pt from the edge it is moved away from; where AppKit or the user put a
   window that fits, it stays, even flush with the menu bar or the screen's bottom (The move).
   Alternatives: none (a capped window fills the visible frame, as the green button's zoom does),
   or 20; or also moving a window that lies inside but within 12 pt of an edge (not taken: it
   would move a window the user put there at every tab click).
2. **Which tabs.** Every tab gets the cap, not only Remote Access: General overflows a 14-inch with
   larger text too.
3. **Resizable.** The window stays fixed in size; the cap decides its height, and the pane scrolls.
   Making it resizable alone would not help (each tab switch sets the height again) and would add a
   saved height to reconcile with every pane's own.
4. **A pane that gets shorter.** Nothing done. Sill's Remote Access pane shrank the window with it
   (Results); the probe's pane did not, so another pane might leave the window taller than its
   content until the next tab switch, as before this change. Forcing it would need AppKit's own
   constraint, which only AppKit names.
5. **A drag between screens.** The cap follows the window's new screen at once (it shortens or
   grows during the drag), but the window is not moved while it is dragged; if the cap changed on
   the way and the window runs off that screen, it is moved once the button is released.
6. **The pairing window** (up to 568 pt of content plus its title bar, a fixed size) would not fit
   the smallest 14-inch scaling with the Dock either. Not part of #59; not changed here.

## Test plan

- The check: every case the issue raises (a 14-inch at its default and larger-text scalings, with
  and without the Dock), an external 4K display at two scalings, a second screen above and to the
  side (its own origin), a window already partly off the screen above and below, the virtual
  display excluded, the test height; then random screens, chromes and frames against the
  properties (the window fits with its margins whenever the screen allows, uses the room to within
  a point, a taller screen never gives less, `placed` is idempotent, never resizes or moves
  sideways, and leaves a window inside alone). Mutants of every rule.
- `swift build -c release`; `Tests/checks/run-all.sh`; the new check's `--mutants`.
- The bare binary with `--synthetic` (no Screen Recording, nothing advertised), test hosts on
  loopback with the software encoder, only while the no-device check passes, Sill.app untouched:
  each tab at this screen's height (natural heights, nothing capped but what overflows 949 pt) and
  with `-SillTestScreenHeight 700` (capped inside the imagined screen, 12 pt over the imagined
  Dock when Sill moved it there, the Form scrolling); Remote Access with Remote Access and the
  internet switch on (`-SillSetAfter`), the tallest pane; a switch from a tall tab to a short one
  and back; the window reopened after `close`; photos of each. A window opened at a saved frame
  from before the fix (951 pt tall), capped; after the review, where a capped window sits when
  AppKit placed it (a saved frame, a Dock appearing under it, a pane grown while it was closed).
- Previews (`-SillRenderPreviews`) against 985a733's: identical (no pane changes).
- No iOS file changes, so no iOS build is needed for this change; the CLI's output is untouched (no
  host file changes).

## Results

All on this Mac (a 14-inch MacBook Pro at its default scaling, 1,512 × 982 pt, 949 under the menu
bar, the Dock hidden; macOS 27.0.1), 2026-10-14, with the screen locked and nobody at it. Every live
run was the bare `.build/release/SillMenuBar --synthetic` with `SILL_TEST_LOOPBACK=1
SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1` (its doors on 127.0.0.1 alone, remote access on
port 17459 where turned on, Sill.app's 7455 untouched), each started only while
`Scripts/encoder-check/no-device.sh` found no device connected to Sill.app, each under 21 s.
Nothing touched Sill.app, its preferences or the keychain; the bare binary's `SillMenuBar` domain
was emptied after.

- **Builds.** `swift build -c release` from `git archive` of the branch, clean: 85 s, only the old
  CaptureProbe warning, as at 985a733; again after the review (5962ad4, whose Swift sources are
  bb2451e's): 54 s, the same warning alone. No iOS, host, CLI, protocol or site file changes (`git
  diff --stat origin/main...`), so no iOS build was needed.
- **Checks.** `Tests/checks/settings-window`: 307,689 checks, 27 of 27 mutants caught (42 s); after
  the review 307,709 (20 for which pane fits which 14-inch scaling), 27 of 27 again (60 s).
  `Tests/checks/run-all.sh`: all 41 passed, and again after the review (372 s).
- **Previews.** `-SillRenderPreviews` of the branch's binary and of 985a733's, run from the same
  path: 130 files each, identical byte for byte.
- **Every tab at this screen's height** (limit 845): each at its natural height, nothing capped:
  General 727 (window 807), Devices 281, Streaming 568, Virtual Display 227, Permissions 275,
  Remote Access 327 (off).
- **The tallest pane** (Remote Access on, with the internet switch, this Mac's addresses: 909):
  capped at 845, scrolling, the window 925 pt, 12 pt from the visible frame's bottom and top (Sill
  moved it there: the switches went on with the window's top at 600, and it ran off the bottom as
  it grew).
- **A pane that grows past the cap with the window low.** The window placed by a saved frame with
  its top at 600; Remote Access off (407 pt window), then turned on with the internet switch: the
  window capped at 925 and moved up to 12 pt over the bottom (it would have run 325 pt below the
  screen). The same for a tab switch from Virtual Display (307 pt) to Remote Access.
- **The screen changing while it shows** (`height=`, the notification's path): 845, then 596 (700
  pt), 396 (500 pt), back to 845, each time 12 pt from both edges of the frame in use; the window
  shrank and grew while the 909 pt pane showed. General at a 600 pt screen: capped at 496.
- **`-SillTestScreenHeight 700`**: General (727) and Remote Access with the internet switch (909)
  capped at 596 and scrolling, 12 pt from both edges; Devices, Virtual Display and Streaming (568)
  at their natural heights. Close and reopen: capped again.
- **Scrolled to the end** at a 600 pt screen: General scrolled 231 pt (727 − 496) and Streaming 72
  (568 − 496), their last rows in view (`~/Downloads/sill-handoff/settings-window/`).
- **rosstex's window**: a frame saved by a version before the fix, 951 pt tall with its top at the
  menu bar. A saved frame sets only this window's top-left (the review's logging build saw it 500
  × 580 before its first layout), so the run shows a window opened with its top at the menu bar
  being capped, not a 951 pt frame shortened: 925 pt, Remote Access scrolling, 0 pt under the menu
  bar and 24 over the bottom, left there since it fits.
- **Where a capped window sits** (after the review, with the screen unlocked and nobody at it for
  over half an hour: a scratch build of the branch whose Settings window was invisible, took no
  click and never activated, `WindowPlacement.bringForward` alone changed and never committed; its
  own defaults domain, deleted after). rosstex's saved frame again: 925 pt, 0 under the menu bar,
  24 over the bottom. A Dock of 70 and then 140 pt (`height=879`, `height=809`): 855 and 785 pt,
  its top kept, 24 over the Dock; the screen's own again: 925; General then 807, its top kept.
  Remote Access and the internet switch turned on while Settings was closed (its top at 600): the
  hidden window laid out at 925 pt, its bottom at −325; reopened, AppKit ordered it in at the
  screen's bottom: 0 pt over the bottom, 24 under the menu bar. Every window fit, and `placed`
  moved none (each lay inside the visible frame): the 12 pt margin holds only on a side Sill moved
  the window away from (The move).
- **A pane that gets shorter**: the internet switch turned off while Remote Access showed: the pane
  909 → 734, the window 925 → 814 (open question 4).
- **Sill.app ignores the hooks.** The same binary in a scratch bundle (its own bundle ID, so
  nothing of Sill.app's preferences was read or written) under `sandbox-exec` with `network-bind`
  denied (a bundle is never a test host, so its doors would not keep to loopback): one "ignored"
  line each for `-SillSettingsAfter`, `-SillTestScreenHeight`, `-SillSettingsShot` (and the old
  `-SillQuitAfter`); no window opened, no photo written, no preferences domain made.
- **Photos** (`-SillSettingsShot`): every tab at its natural height and General and Streaming
  capped at a 600 pt screen, at the top and scrolled to the end, in
  `~/Downloads/sill-handoff/settings-window/`. Those of Remote Access turned on show this Mac's
  Tailscale name and addresses; they were deleted, not kept.

Not verified here:
- macOS 26, the reporter's (rosstex: 26.6.2). Everything the fix rests on was measured on macOS
  27.0.1 alone: AppKit's constraint at 501, under the cap's 750; the window keeping its top-left as
  it is laid out; a hidden window laid out all the same. Merging the pull request closes #59 (U6).
- Sill's virtual display present. None was made here: adding a display can move the windows of
  whoever uses this Mac. That the cap and the move never use it is in the check (`screenIndex`),
  and the move off it is `WindowPlacement.bringForward`'s, as before (U7).
- Another display (this Mac has one), the Dock showing or changing (the notification's path was
  run with `height=`, not by the Dock itself), a drag between screens or a mouse button held during
  a resize (no input is posted here), VoiceOver in a capped pane, Sill.app itself (the bundle's own
  executable was not run: it would read and write Sill.app's preferences), and macOS 14 and 15.

## The review

An adversarial review of the pull request (2026-10-14, at bb2451e) re-ran the builds, the checks,
the previews and every live case above with a quiet build of its own (the same numbers), and found
three things, each fixed in a commit of its own:
1. **Should fix: the untested lists left out macOS 26 and Sill's virtual display** (5962ad4). The
   issue is from macOS 26.6.2, everything here ran on 27.0.1, and "Fixes #59" closes the issue on
   merge; the virtual display was in the implementer's report as not verified live, but not in
   this plan, the pull request or CLAUDE.md. Both are in "Not verified here" now, with U6 and U7.
2. **Nit: CLAUDE.md and the pull request said the 501 constraint never shrinks and that General
   does not fit a 14-inch with the Dock** (7a7efcb). In the probe it did not follow a pane made
   shorter, but Sill's Remote Access pane shrank the window (Results); General's 807 pt window fits
   at the default scaling with a 70 pt Dock. Corrected there and in "The problem, measured" (which
   also had nothing fitting a 14-inch at More Space), with 20 checks for which pane fits which
   scaling.
3. **Nit: U1, U2 and the pull request's steps promised 12 pt above and below**, which the design
   keeps only on a side Sill moved the window away from (99bd169). Reworded there, in "The move",
   open question 1, CLAUDE.md and docs/DEVELOPMENT.md, and measured (Results, "Where a capped
   window sits"). Moving a window that fits but lies within 12 pt of an edge was not taken: it
   would move a window the user put there at every tab click.

## Untested, for Noah

With Sill.app from this branch (`Scripts/make-app.sh --install --open`) on the 14-inch MacBook:
- **U1.** System Settings › Displays at the scaling at the far left (larger text), and the Dock
  showing (System Settings › Desktop & Dock, "Automatically hide and show the Dock" off). Open
  Settings (⌘,) and click every tab: each window fits between the menu bar and the Dock (12 pt
  clear on a side Sill moved it away from; a window that fit where macOS put it stays there, so it
  can sit right under the menu bar with 24 pt over the Dock); General scrolls to Quit Sill; Remote
  Access, with Remote Access and "Allow connections from the internet" on, scrolls to Sleep. At
  the default scaling Remote Access with the internet switch still scrolls a little, and the others
  show whole.
- **U2.** With Settings open on Remote Access (the internet switch on), change the scaling, then
  the Dock's size, then hide and show it: Settings shortens or grows to fit each time and stays
  between the menu bar and the Dock. If a Dock change shows only at the next tab click, note it
  (macOS would then not announce the Dock's changes as a change of screens).
- **U3.** An external display: drag Settings from the larger screen to the smaller one; it
  shortens on the way; let go with it low on the smaller screen: once the button is up it moves up
  until its bottom clears the Dock. Drag it back: it grows to its pane's own height.
- **U4.** With Settings low on the screen, press and hold the Remote Access tab: the window never
  moves while the button is held, and moves up once it is released if it ran off the screen.
- **U5.** VoiceOver in a capped pane (General, larger text): moving through it reaches Quit Sill,
  the pane scrolling to it.
- **U6.** macOS 26, the reporter's (rosstex: 26.6.2), before #59 is closed (merging this pull
  request closes it): U1 on a Mac with macOS 26, or a build of this branch for rosstex to try.
- **U7.** Sill's virtual display: Virtual Display on (Sill's menu) and a window streaming to the
  iPad, so Sill's own display exists. Open Settings from Sill's menu and click every tab: it shows
  on the built-in display, never on Sill's, and fits it as in U1 (Remote Access with the internet
  switch on scrolls, at any scaling but More Space). Then turn Virtual Display off with Settings
  open: it stays where it is and still fits.
- **U8.** On macOS 14 or 15, if a Mac with one is at hand: U1.

## Progress

- 2026-10-14: the probe; this plan (3b8c61d). `SettingsWindowFit` and its check (ec0d850); the
  cap, the move and the hooks (f009b09); the check at Sill's measured chrome (367e8c8); a move
  that waits for the buttons, the docs (654d782); the `end` step (c4a39a7). Every result above on
  c4a39a7 (after it only the hooks' messages and the docs changed). PR #74 opened; left open for
  Noah. Then the cap's constant starts at 10,000 pt (no cap) instead of 200 until a screen is
  known, so a Mac with no usable screen (none, or only Sill's virtual display) never gets a 200 pt
  pane; a run of every step kind on it (General and Streaming natural, capped at a 600 pt screen,
  scrolled to the end, back to the screen's own, closed and reopened) gave the same numbers.
  `swift build -c release` of c2339e2 from `git archive`: only the CaptureProbe warning. CI's
  "Build and check" passed on c2339e2 (run 38483417858: the build, all the pure checks, the iOS
  app for the simulator, the CLI).
- 2026-10-14, after the review (The review): the fit and shrink claims and 20 checks (7a7efcb),
  the margins (99bd169), macOS 26 and the virtual display among the untested (5962ad4); the
  re-runs in Results (the build, `run-all.sh`, the check's mutants, where a capped window sits);
  the test plan's margin (1865ada). CI's "Build and check" passed on 1865ada (run 38489891977: the
  build, all the pure checks, the iOS app for the simulator, the CLI). The pull request's
  description says the same. Left open for Noah.
