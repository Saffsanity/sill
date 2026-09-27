# The Mac's menu bar on the device — the plan

## Status and hand-off (2026-09-26 03:50; critiqued 2026-09-27; the host finished 2026-09-27)

Stopped by Noah at about 95 % of the week's usage, in the middle of the host build ("Stop trackpad
gestures and menu bar mirror for now. Mark down next steps for agents that will pick up the task.").
Resumed 2026-09-26 23:38 ("Continue working where you left off with Opus 5.5 subagents").
What the branch `menu-bar-mirror` holds (worktree `/Users/noah/Downloads/winstream-menubar`, from main
at 150f781): 556f31a this plan; 42d3116 the protocol, kinds 24, 25 and 27 and
`Sources/StreamProtocol/MacMenu.swift`; 4896088 the host side as the interrupted build agent left it:
`MenuFormat.swift`, `MenuPolicy.swift`, `MenuReader.swift`, `MenuMirror.swift`, `MenuSelfTest.swift`,
the hooks in `StreamCoordinator.swift`, `WindowCatalog.swift`, the CLI's `--menu-selftest[=APP]` and
the app's main, `Scripts/menufixture.swift`, the new `sillclient.py` flags and `Tests/checks/menus`.
It built clean on 2026-09-26 03:48, and the menus check passed 267 of 267 (run again 2026-09-27);
its mutants and the H4 gate never finished, and none of it is reviewed. No iOS file has changed.
The host step since (2026-09-27, "The host finished" below) fixed C1–C5 and merged main at cf05a78.

**The critique (2026-09-27)** read §§3–4 against 4896088, §7 against the probe's iPadOS hazards (a
mirrored `UIKeyCommand` firing with no first responder, a shortcut equal to one the root holds
dropping the inserted menu, duplicates crashing), and §10's gates against both. The plan is fixed in
place. Where 4896088 departs from the plan as it now stands:
- **The code must change** (the verify step, 2 below; done, "The host finished"):
  - C1. `servePress` presses any id that resolves: a bar item's ("2") and a submenu item's too.
    AXPress there opens that menu on the Mac, and the app then sits in menu tracking. Now refused
    before anything is pressed (§3.3, §4.3).
  - C2. A kept element is pressed whatever its title now. Apps that fill a menu through its delegate
    reuse their NSMenuItems, so the same element can stand for another command after the validation
    the press's own read sets off. Now the current title must be the one shown, for the kept element
    as for one found again, and an empty title never matches (§4.2). The menus check's "a kept
    element is authoritative" cases and the mutant "the title checked for a kept element" invert.
  - C3. `MenuReader.items` has no time budget: 500 items at Blender's 6 ms a call take seconds, and
    every request waits behind it. Now it stops at 1.5 s, and the unread rest counts in `more`
    (§4.3).
  - C4. `MenuCache` waits out the second after a read made while the app was not frontmost even when
    `prepare` finds it still not frontmost. AppKit would answer from that read, so the entry now
    answers. The wait after such a read runs to 1.05 s, not 1.0: the probe's reads 0.83 s after a
    validation got none, 1.03 s after did (§4.2).
  - C5. A top-level read that fails with `failed` publishes `menus: []` for the new version, and
    nothing but a new subscription reads it again. Now nothing is sent, and each catalog poll reads
    it again. The same goes for a top level refused for Accessibility, so a grant shows the menus
    without a pick (§4.4).
- **The plan adopts the code:**
  - A1. One request at a time, in arrival order (`enqueue`), in place of `waiting[id]`.
  - A2. The same app (the same pid) keeps the version, the ids and the kept elements; only the cache
    is cleared (`Target.window`). The old §4.4 moved the version at every change, against §9.
  - A3. `WindowCatalog.onPolled`, after every poll, in place of `windowsChanged`'s end, which runs
    only when the list changed. The Desktop's re-check and the retries need every poll.
  - A4. The interface's extras: `onSubscribersChanged`, `who:`, `clientLeft(NWConnection)`,
    `MenuRefusal`, `MenuLog`, `MenuFormat.topItem` and `displayTitle`, `MenuReader.Menu` and
    `Pressed`, and `MenuPath.lineage`. Also: no leading zeros in an id, and a menu's children that
    are not `AXMenuItem`s are skipped, though their indexes still count.
  - A5. Three log lines: "… more than 4 choices a second.", "…: Accessibility refused it (‹error›)",
    and a refusal for another version, which gives the id: the host no longer has that version's
    titles.
  - A6. The version starts at 1, and the first app the mirror takes makes it 2. Rate refusals are
    answered at once, ahead of answers still queued.
  - A7. `focusForMenus` makes the streamed window key on every uncached fetch and every press,
    whether or not the app is frontmost: an AX window lookup and two writes on the main actor. §4.9
    now says so; it said "whose app is not active".
- **Beyond the host** (no code yet):
  - §7.2–§7.4: the builder inserts once per build and checks its anchor. A bar menu is resolved by
    its title when it opens, since UIKit rebuilds the bar lazily. "No items" shows only without a
    note.
  - `.replace`'s cost (Q1). The Apple menu's privacy reason (Q4).
  - The gates: H4's cache timing was wrong (4.5 s is 1.5 s after the read at 3), and H4 takes two
    runs, since the ids of Deep and its levels come from the first. H5's old version needs
    `--raw25`. H5 also presses a bar item, a submenu item and a kept element under another title
    (C1, C2). H6 gains Dynamic N, and H8 accepts either note, since a poll can land between the kill
    and the fetch. H9 sends a title under the 1 MiB cap and a message over it. H12 reads only
    TextEdit (the workflow's rule; H11 reads the fixture), and H13's greps are fixed. P8 checks the
    lazy rebuild.

**The host finished (2026-09-27).** On top of f5344e8, one commit each:
- 4aeb7d1, C1 and C2. A press only for a leaf whose title now is the one shown: the mirror refuses
  an id of one part before anything is activated or read; the reader reads the item's title,
  description, enabled flag and children in one call, kept or found again; `PressDecision.decide`
  takes the title now and `hasChildren` (title, then leaf, then enabled).
- c6f75ec, the fixture. It ran `.accessory`, and an accessory app started from a shell took the
  front at launch: `lsappinfo front` named it for a whole 20 s run (00:47, with Claude back once it
  exited, while a device was on Sill.app). It runs `.prohibited` now, as the probe's fixture did.
  SIGUSR1 and SIGUSR2 give Probe › Rebuilt a new NSMenu, since AppKit's item elements are
  positional (§"Pressing").
- d238710, C3: `MenuReader.readBudget` 1.5 s, `Menu.unread`, the answer's `more`.
- 07fc56c, C4: `MenuCache.fresh(_:now:frontmostNow:)`, `MenuCache.revalidation` 1.05 s.
- d392679, C5: `publishTop` sends nothing for a target whose top level is unread (unless stale);
  each catalog poll reads it again, and a top level refused for Accessibility (`needsRetry`).
- 53522ab, main at cf05a78 merged (PRs #22–#28), without a conflict; CLAUDE.md and ci.yml are
  main's, as this branch has not edited them yet.
- 8ea4882: whatever a fetch's top-level read finds goes out to the subscribers (a top level read
  there for the first time in its version was answered but never published, and the polls stop
  retrying once it is read).

Checked, without the hardware encoder:
- `Tests/checks/menus` 279 of 279 and 33 of 33 mutants (at d392679; the check's inputs are the
  same files at 8ea4882); `Tests/checks/run-all.sh` 16 of 16 on the merge; `swift build -c
  release` of 8ea4882 from `git archive`, only the CaptureProbe warning; the iOS app for the
  simulator (Debug, arm64, the CI command) from the merge, only the StreamClient capture warning.
- The reader alone against the fixture (a harness compiling MenuReader, MenuFormat, MenuPolicy
  and StreamProtocol; no host, no encoder), 27 checks at 8ea4882's sources: the bar item and Deep
  refused in 3–8 ms with no fixture callback naming Deep (reading a submenu item's children opens
  nothing); 4.0 pressed; 4.1 kept under another title refused; 4.1 found again by its path
  pressed; Unavailable refused as disabled; Dynamic N pressed 0.3 s after its read and refused
  1.8 s after (the press's own read validated Probe and retitled it); Rebuilt found again after a
  new NSMenu, and refused as Renamed Leaf; Deep Leaf pressed; 600 Items read 500 with 100 more in
  62 ms. A build with a 5 ms budget read 1 of 600 Items (the walk alone took 25 ms) and counted 599
  more. Slow Action: `AXPress` answered in 2–5 ms, before the action ran, and a read of Probe
  during the action's 2 s sleep timed out at 1,000 ms (`notAnswering`), then the app answered
  again. `lsappinfo front` sampled every 0.1 s never changed.
- The fixture (H0): its label reads "none" over AX from another process; its window is off every
  display; the host's read-only `--menu-selftest=<its pid>` reads its four menus (the top level
  22 ms at first read, menus 0.6–11 ms: H11's times, within the probe's).
- H13's greps: no system-wide timeout, no AX call in MenuMirror, no `assumeIsolated` in the new
  files, `SILL_TEST_MENU_PID` taken only when synthetic, `kAXPressAction` only in MenuReader (after
  `PressDecision`) and WindowSizer's close button.

Not run in this step:
- H2 and H4–H11 through the host: every synthetic host encodes on the hardware (its launch probe,
  and the Desktop it streams), and a device streamed the Desktop from Sill.app the whole time
  (`Scripts/encoder-check/no-device.sh` blocked from 00:41 on). The gate scripts wait for it:
  session scratchpad `menubar-finish/tools/gates.py` (H4–H11, one host at a time, each after
  `no-device.sh`, `lsappinfo front` sampled throughout) and `h2.py`, with builds of main at
  150f781 and cf05a78 and of 8ea4882 beside them.
- H12: TextEdit was not running, and none is started.
- H13's previews: the bare SillMenuBar is an accessory app, which takes the front when started from
  a shell; the only app change is `--menu-selftest`'s branch in its main, before NSApplication.

Found, for the review (step 5):
- A fetch by id does not check that the item at that id is still the one the device opened.
  AppKit's elements and the paths are positional, so after an app rebuilds a menu's items in place
  a submenu id can name another submenu, whose items the device then lists under the old title.
  Presses stay safe (their title check); a fetch could compare the item's title with the kept one,
  as C2 does for presses.
- Q12: a top-level read alone made the fixture run no delegate or validation callback (the
  interrupted build's H4 run of 2026-09-26: a subscription 2 s before any fetch, no callback; this
  step's self-test and reader runs: callbacks only for the menus read). A read at each poll would
  then cost the app nothing; Noah's call, H4 records it again.
- `Tests/checks/README.md` on main repeats three paragraphs (a merge's leftovers); the menus row and
  ci.yml's mutants matrix entry are step 4's.

Next agent, in order:
1. (Done) Merge main: cf05a78 at 53522ab. Main has not changed StreamCoordinator, StreamClient,
   StreamMessage or the pbxproj since 150f781, so this plan's line numbers still hold there.
2. (Done but for the gates through the host) Verify and fix the host. Run H2 and H4–H11 once no
   device is on Sill.app: the scratchpad's scripts, or by hand from §10.
3. The iOS side, §7: the files and their four pbxproj entries by hand, `MacMenuState` checked with
   swiftc and mutants, the iPadOS 26 menu bar, the Menus button, `StreamClient`, the harness cases
   of §7.8; photos at the four Duo sizes and on an iPhone.
4. Sill.app, §6; the docs (CLAUDE.md's Layout and Current step, docs/DEVELOPMENT.md,
   `Tests/checks/README.md`'s table and ci.yml's mutants matrix for `menus`).
5. Review (wire and hard rules, the AX reader's queue and timeouts, the device UI and its hazards in
   §7.3, the fetch finding above), then a PR against main with Noah's device tests.
Rules the build must keep: the reader presses nothing in any test but the fixture; no XCUITest or
`simctl io recordVideo` while Sill.app streams; the CLI's output unchanged unless a device uses the
menus. The workflow prompt must quote Noah's authorization in his words: "For apps used in Window
mode, how can we access the menu bar options? Is there a way we can add that menu and submenu?"
(2026-09-25) and "Work on 5-12 as well please" (2026-09-26, item 10), plus this stop and its
resumption, so a relayed message about another topic does not stop the agents again.


2026-09-26. It stands alone: the implementer needs no other design document. Written from a
read-only survey of main (the `menu-bar-mirror` worktree, `/Users/noah/Downloads/winstream-menubar`),
begun at 8b0d418 and checked again at 150f781, after PRs #20 and #21 merged; line numbers are at
150f781. Of the files cited, only StreamCoordinator.swift changed between the two (one line, at
231). Main at cf05a78 (2026-09-27) has changed none of them; on this branch StreamCoordinator's
lines after :130 have moved with the host's hooks. Nothing but this file was written. The evidence
is the feasibility probe of 2026-09-25 (session scratchpad `menubar-result.json` and `menubar/`).
It read the menu bars of 13 Mac apps and of a scratch AppKit fixture over Accessibility, read-only:
nothing was pressed. It also ran a scratch SwiftUI app shaped like Sill in a private iOS 27
simulator. For this plan no host was started, no app was activated and no menu item was pressed.

**Noah's request (2026-09-25):**
> For apps used in Window mode, how can we access the menu bar options? Is there a way we can add
> that menu and submenu?

On 2026-09-26 he asked for items 5–12 of the list as well. Item 10 is the Mac menu bar mirrored in
the iPad's menu bar.

**Reading of it.**
- **The streamed app's menus reach the device.** File, Edit, View and the rest, with their
  submenus, can be opened on the device. Choosing an item does on the Mac what choosing it there
  would.
- **On an iPad with iPadOS 26 or later they appear in the iPad's own menu bar.** That is the bar
  that the pointer at the top edge, or a swipe down from it, reveals.
- **Everywhere, a Menus button in Sill's bar opens the same menus.** That covers iPhone, the Duo's
  outer display, iPadOS before 26, and an iPad whose bar is hidden.
- **With the Desktop streaming, the menus are the frontmost app's,** as the Mac's own menu bar
  shows.
- **The Mac's shortcuts are shown, never taken over.** ⌘S typed on a hardware keyboard still goes
  to the Mac as a key, as today.

**Where this plan departs from the task that commissioned it**, each explained where it is decided:
- the Menus button shows in every layout, not only where there is no menu bar (Q2);
- the button is a UIKit pull-down, not SwiftUI's `Menu` (§7.5);
- the host sends the top level only to a device that asks for it, with a kind 27 that carries no
  id (§3.3). An older device then costs the Mac nothing.

---

## Decision

### What the device shows, and where

| Surface | Where | Content |
|---|---|---|
| **The iPadOS 26 menu bar** | An iPad (idiom `.pad`) on iPadOS 26 or later, while the key window's session streams an app with menus | One menu per Mac menu, in the Mac's order, the Apple menu left out (Q4). Inserted after the iPad's View menu, the HIG's place for an app's own menus (Q1) |
| **The Menus button** | Every bar, in every layout, whenever the Mac sent menus (Q2) | A pull-down with the same menus as submenus |
| **Each menu** | Both surfaces | Loaded when it opens and fresh every time, from the Mac (kind 27, answered by a read of at most 1 s ago) |

What each item shows:
- **Enabled or disabled.** A disabled item is greyed and cannot be chosen.
- **Its mark.** The Mac's ✓ is on and its "-" is mixed.
- **Separators** become sections.
- **Submenus**, each loaded when it opens.
- **The Mac's shortcut as text.** It is the item's subtitle ("⇧⌘S"), never a key command (Q3).
- **Stale.** While the Mac reports the app not answering, every item is disabled, under a note.

### How the host reads: the streamed app's AXMenuBar, one menu at a time

- **Where.** `AXUIElementCreateApplication(pid)` → `kAXMenuBarAttribute` → the bar's items → each
  item's one `AXMenu` → its `AXMenuItem`s. Every app the probe tried was readable this way: AppKit,
  Electron, wxWidgets, Mac Catalyst, SwiftUI and Chrome, 13 of 13.
- **The top level** is the titles of the bar's items. It is read:
  - when the streamed source is picked;
  - when the app behind it changes (a window of another app, or the Desktop's frontmost app);
  - alongside every fetch.
  It costs 0.4–3.8 ms, 26 ms in Blender, and 15–50 ms the first time the host reads that app.
- **A menu's items are read only when a device opens that menu** (kind 27), and are kept for 1 s.
  One menu costs 3–20 ms; Blender's 42-item Window menu took 290 ms.
- **Why 1 s.** AppKit validates a menu when it is read and throttles that to about once a second
  per menu. A read within the second returns the state computed at the last one (measured).
- **Why never the whole tree.**
  - It costs 15–130 ms, and 0.8–1.6 s in Blender.
  - It makes the app update and validate every menu it has. The fixture logged `menuNeedsUpdate:`,
    `menuWillOpen:`, `validateMenuItem:` for each item, then `menuDidClose:`, on every read of a
    menu's children.
  - The states it reads go stale within a second anyway.
- **Why no polling.** AppKit computes enabled states only when a menu is read or opened (NSMenu.h
  line 137; measured). No Accessibility notification announces a change, so there is nothing to
  observe. A timer would make the streamed app go through its menu delegates every few seconds for
  nothing.
- **Off the main actor.** Every read and press runs on a serial queue of its own, `sill.menus`. The
  coordinator's main actor carries every device's input, and one AX call into Blender takes 6 ms;
  into a hung app it waits out the whole timeout.

### Why the app is activated first

- **What the probe saw.**
  - All 13 apps were inactive. In every one, Window › Minimize, Zoom and Close read disabled.
  - VS Code had 314 of its 431 items disabled, among them Undo, Find and Settings.
  - TextEdit, hidden, had Cut, Copy, Paste and Undo disabled.
- **Why.** The states are computed for an inactive app. A nil-targeted action (Copy, Close) has no
  key window to go to.
- **So for a window source**, before a menu's items are read or an item is pressed, the host
  activates the streamed app and makes the streamed window key.
  - It does exactly what a click from the device does today: Accessibility only, never Launch
    Services (`raiseIfInteracting`, StreamCoordinator.swift:1093-1158, and the rule at :1052-1069).
  - The states the device then sees are the ones the Mac would show, and a press acts on the
    streamed window, not another window of the same app.
- **The Desktop's app is already frontmost.** Nothing is activated for it.
- The alternative, activating only on a press, is Q5.

### Pressing: AXPress on the element, its path as the fallback

- **The element.** The host keeps the AX element of every item it read in the current tree version,
  and presses exactly that one with `AXPress`. Nothing is typed. So an item without a shortcut
  works, and so does one whose shortcut the device's keyboard cannot type (fn, F-keys).
- **When the element is gone.** Some apps build their menus again: Electron makes new NSMenus, and
  a delegate can empty and refill its menu in `menuNeedsUpdate:`. AppKit's menu item elements are
  positional (measured on the fixture, 2026-09-27): with the items replaced inside the same NSMenu,
  the element read before was `CFEqual` to the new one and read the new item's title; only a new
  NSMenu left it invalid (-25202). So a kept element can outlive its item and stand for whatever
  item is at its place now, which the title check below catches; an invalid one gives way to the
  path, and the host finds the item again by its indexes.
- **Only what the device showed.** Either way the item's title now must be the title the device
  showed, or nothing is pressed ("The menus changed. Open the menu again.").
  - Why the kept element too: a delegate that fills its menu with `numberOfItemsInMenu:` and
    `menu:updateItem:atIndex:shouldCancel:` keeps the same NSMenuItems and rewrites them. The press
    reads the element first, and that read makes the app validate the menu, which runs the
    delegate. The same element can then stand for another recent document or history entry.
  - It costs no extra call: the title comes back with `AXEnabled` in one.
  - The price is an item the app retitled in between ("Undo Typing" → "Undo Paste"). It is refused,
    which is also what a device that showed the old title should hear.
  - An empty title never matches: the device was never shown such an item.
- **Only a leaf.** An id of one part (one of the bar's menus), or an item with a submenu, is refused
  before anything is pressed. `AXPress` on either opens that menu on the Mac, and the app then sits
  in menu tracking until someone closes it: System Events' `click menu bar item` waits out its
  timeout the same way. The device never sends one, but a test client can.
- **What happens next is the app's.** The result shows in the picture. For dialogs in regular mode,
  see §9.
- **A press can wait, or not.** On the fixture, an AppKit app, `AXPress` on a menu item answered in
  2–3 ms, before the action ran (measured 2026-09-27: Slow Action's 2 s sleep began after the
  answer). An action that then holds the app's main thread (that sleep) makes a read made meanwhile
  run into the 1 s timeout: the app shows as not answering until a poll finds it answering again. A
  modal loop may keep answering Accessibility (not measured). An app whose `AXPress` answers only
  once its action has run holds `sill.menus` up to the timeout instead.
  - This happens on `sill.menus`, never on the main actor.
  - An answer that does not come within the 1 s timeout counts as pressed, with a note in the log.
    The app may just be showing a dialog.

### Why the device never registers the Mac's shortcuts as key commands

The probe measured every one of these:
- **While InputOverlay is first responder, the first responder wins.** F5, ⌘S, ⇧⌘E and ⌘C/V/Z/A/,/W
  all reached its `pressesBegan`, with or without `wantsPriorityOverSystemBehavior`. So a mirrored
  `UIKeyCommand` would only ever label the item there.
- **With no first responder, main-menu key commands fire.** That is the state with the keyboard
  hidden or the Settings panel open. A key the user meant for nothing would press a Mac menu. The
  system's own ⌘W Close destroyed the probe's scene.
- **A clash drops the whole menu.** An inserted shortcut equal to one the root already holds (the
  Mac's ⌘C against Edit › Copy) makes UIKit silently drop the entire inserted menu. UIKit logs it
  as "Inserted elements conflict with existing elements", with no crash.
- **A duplicate crashes the app.** Duplicate shortcuts, identifiers, or action and property-list
  pairs throw `NSInvalidArgumentException`. UIKit logs it as "Inserted elements contain duplicates"
  (the probe's three crash runs: two `UIMenu`s with one identifier, two equal shortcuts, two
  `UICommand`s with one action and property list).

So the device uses no `UIKeyCommand` and no `UICommand`:
- **Leaves are `UIAction`s,** with the Mac's shortcut as `subtitle` text. The context-menu system
  draws that subtitle on iOS. Whether the iPadOS bar draws it is P8.
- **The Mac's shortcuts still work as keys,** through InputOverlay, as today (P7).
- **What is left of the three hazards is identifiers.** The bar's menus carry identifiers of their
  own, and every element under them carries none, so UIKit makes unique ones. The builder also
  inserts them at most once per build: a menu inserted twice under one identifier would be a
  duplicate (a crash), or a conflict with the root (the whole insertion dropped). §7.3 rule 2 and
  §7.4 have the rules.

A fourth fact shapes the bar: **the rebuild is lazy.** `setNeedsRebuild()` ran only at the next key
event or focus change (measured). So after the Mac's app changes, the bar can still hold the previous
app's menus. A bar menu built from an older top level therefore asks by its title when it opens,
not by the id and version it was built with (§7.2 rule 11, §7.3 rule 5). Whether showing the bar
rebuilds it is P8.

### Measured (the probe, 2026-09-25; macOS 27.0 26A428, Xcode 27, the iOS 27 simulator)

| What | Result |
|---|---|
| Apps readable | 13 of 13: Finder, VS Code (Electron), Blender, Bambu Studio (wxWidgets), Preview, Messages and Clock (Catalyst), Terminal, System Settings, Chrome, Developer (SwiftUI), App Store, TextEdit. Error 0, no call timed out at 2 s |
| Top-level titles | 0.4–3.8 ms (Blender 26 ms). The first `AXMenuBar` read per app took 15–50 ms, later ones 0.04–1.5 ms |
| One menu's items, `AXUIElementCopyMultipleAttributeValues`, no action names | Finder Edit (24 items) 3.9–8.3 ms; Preview Edit (40) 6.1–19; Terminal Edit (88) 14–19; Chrome Edit (45) 9–16; Blender Window (42) 289–297 |
| Whole tree (not used) | 15–130 ms with `AXUIElementCopyMultipleAttributeValues` (Clock 15–18, Finder 27–131); Blender 0.8–1.6 s (about 6 ms a call) |
| Freshness | Each read of a menu's children makes AppKit run `menuNeedsUpdate:`, `menuWillOpen:`, `validateMenuItem:` for each item, then `menuDidClose:`. That is throttled to about once a second, per menu; a read in between returns the last state. A delegate-built submenu fills in at read time |
| Inactive apps | States are computed for an inactive app (see "Why the app is activated first") |
| Separators | An `AXMenuItem` titled "" (empty, not missing), disabled, with no children. No role or subrole marks one |
| Marks | `AXMenuItemMarkChar` "✓" (36 items); "-" for mixed; missing when off |
| Shortcuts | `AXMenuItemCmdChar` is uppercase with no Shift bit ("k" reads "K"). Special keys are raw characters (\u{8} \u{1b} \r \t space); F-keys and arrows are private-use (U+F700…); some apps put glyphs there ("↩", "⎋"). `AXMenuItemCmdModifiers`: Shift 1, Option 2, Control 4, NoCommand 8, plus an undocumented 16 for fn on system items. `AXMenuItemCmdVirtualKey` and `AXMenuItemCmdGlyph` (Carbon Menus.h codes) are present for non-character keys |
| Alternates | Ordinary adjacent items: nothing marks them (`AXMenuItemPrimaryUIElement` returns the item itself). Hidden items are left out of `AXChildren` |
| Odd items | Custom-view items (Finder's Tags row) have no title and no actions. Chrome's 27 bookmark items have no `AXTitle`. AppKit's Continuity Camera item reads "<<Import From Device - unlocalized>>" with an empty submenu |
| Identifiers | `AXIdentifier` is the item's selector by default. It says nothing per command: every VS Code item is "itemSelected:", every wx item "clickedAction:". Catalyst items carry UIKit identifiers |
| Blender | Only Apple, Blender and Window are in `AXMenuBar`. Its File, Edit and Render menus are drawn in its window |
| Actions | `AXMenuItem` has `AXPress`, `AXPick` and `AXCancel`. Nothing was pressed |
| iPad: the adaptor | A `@UIApplicationDelegateAdaptor` subclass of UIResponder received `buildMenu(with:)` for `.main` 29–91 ms after launch, called by SwiftUI's own AppDelegate. `UIMainMenuSystem.setBuildConfiguration`'s handler never ran |
| iPad: rebuilds | `setNeedsRebuild()` is lazy: the rebuild ran inside the next key event, or at a focus change. A 2,041-element tree took 10.5 ms, and 21 ms inside a key event |
| iPad: lazy menus | `UIDeferredMenuElement.uncached` runs its provider when its menu is shown. In a pull-down: 5 ms after it opened, with a loading placeholder until the completion 0.56 s later. A lazy element in an unopened submenu was never asked for. In the main menu nothing ran in 11 s headless, because the bar was never shown |
| iPad: key commands | The hazards in "Why the device never registers the Mac's shortcuts as key commands" |
| iPad: builder | Clean with no key commands, nil submenu identifiers and `UIAction` leaves: 2,041 elements, 10 levels deep, a 2,000-item submenu, no diagnostics |

### What the probe did not settle (the gates do)

- **Pressing.** H5 is the first press through Sill's own code, against the fixture.
- **Whether reading the top level alone makes an app validate its menus.** H4 records it in the
  fixture's delegate log. It decides Q12.
- **States in an active app.** P1.
- **How the iPadOS bar draws all this:** subtitles, marks, deferred loading, width with ten or more
  menus. It is P8, because the bar cannot be shown headless (S3).
- **Whether showing the bar rebuilds it.** The probe saw a rebuild only at a key event or a focus
  change. §7.2 rule 11 covers a bar built from an older top level; P8 says how often it happens.
- **Whether an app reuses a menu item's element for another command** after a validation. The
  host no longer relies on it either way (§4.2); H6's Dynamic N shows a retitled element refused.

---

## Final plan

### 1. Scope

**In this step:**
1. **Wire.** Kinds 24 (`macMenu`), 25 (`pressMenuItem`) and 27 (`fetchMenu`), and
   `Sources/StreamProtocol/MacMenu.swift`.
2. **Host.**
   - The streamed app's menu bar: the top level to devices that asked for it, each menu's items on
     request (kept 1 s), and presses. All of it off the main actor.
   - Activation first for window sources; for the Desktop, the frontmost app.
   - `--menu-selftest`, the TEST ONLY hook `SILL_TEST_MENU_PID`, the fixture
     (`Scripts/menufixture.swift`) and new `sillclient.py` flags.
3. **Device.**
   - `MacMenuState` (pure) and one element builder.
   - The iPadOS 26 bar through an app delegate adaptor.
   - The Menus button in every bar.
   - Harness cases.
4. **Tests.** Two pure checks (`Tests/checks/menus`, `Tests/checks/menu-state`), and gates H and S.

**Not in this step:**
- the Apple menu (Q4);
- menu extras (the status items) and Control Center;
- context menus: right-click menus are pop-ups, not in `AXMenuBar`, and the long-press right-click
  already opens them in the picture;
- menu search: Help's search field is a custom view, and is skipped;
- the Mac's shortcuts as iPad key commands (never);
- `UIDeferredMenuElement.usingFocus` and `provider(for:)`, both iOS 26 (later, if several windows
  need them);
- revealing Option alternates (Q6);
- any change to what ⌘W does on the iPad (Q8);
- a setting (Q10);
- the Mac's pointer (kind 26, its own branch).

### 2. The design on one page

```
 ┌──────────────── Mac (Sill.app / SillHost) ─────────────────────────────────────────────────┐
 │ kind 27 without an id (a device asks for the menus, once per connection) ─▶ subscribers ◀──┼── kind 27 {token}
 │ main: select; the Desktop's frontmost app changes ─▶ MenuMirror.setTarget(pid)             │
 │   └▶ sill.menus: MenuReader.topLevel(pid): the bar's titles, 0.4–50 ms                     │
 │        └▶ main: version += 1 when the app or its titles changed ─▶ each subscriber ────────┼─▶ kind 24 {version, app, menus}
 │ kind 27 {version, id, token} ─▶ main: MenuMirror.fetch (one request at a time, in order)   │◀─ kind 27
 │   a window source: its app activated, the window made key (as a click), up to 0.6 s        │
 │   read less than 1 s ago? answered from the cache                                          │
 │   else sill.menus: MenuReader.items(path): one menu, 3–20 ms, 1.5 s at most (validated)    │
 │     └▶ main: cache, elements[id] ─▶ that device ───────────────────────────────────────────┼─▶ kind 24 {version, answering, menu, items}
 │ kind 25 {version, id, title, token} ─▶ main: MenuMirror.press                              │◀─ kind 25
 │   a leaf; the same activation; sill.menus: AXPress, if its title is still the one shown    │
 │     └▶ main: "Menu from …" ─▶ that device ─────────────────────────────────────────────────┼─▶ kind 24 {version, answering, pressed, note?}
 └────────────────────────────────────────────────────────────────────────────────────────────┘
 ┌──────────────── device ────────────────────────────────────────────────────────────────────┐
 │ StreamClient: first window list ─▶ kind 27 without an id; kind 24 ─▶ main: MacMenuState    │
 │ iPadOS 26 iPad: MacMenuHub (the key window's client) ─▶ UIMenuSystem.main.setNeedsRebuild  │
 │   SillAppDelegate.buildMenu ─▶ one UIMenu per Mac menu, after View                         │
 │ every layout: the Menus button (a UIKit pull-down over the bar's BarButton)                │
 │ both from MacMenuElements: UIMenu ▸ UIDeferredMenuElement.uncached ▸ fetch (kind 27)       │
 │   leaves: UIAction(title, subtitle "⇧⌘S", disabled?, state) ─▶ press (kind 25)             │
 └────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3. Wire protocol

#### 3.1 The kinds (`Sources/StreamProtocol/StreamMessage.swift`, after `hello`)

```swift
    // The Mac's menus (MacMenu.swift). Older readers map all three to `.unknown` and skip them. 26 is
    // the Mac's pointer (docs/pointer-visibility-plan.md), so the fetch is 27.
    case macMenu = 24        // host → device: JSON MacMenu — the streamed app's menu bar (the Desktop's: the frontmost
                             // app's), to a device that asked for it with a kind 27 without an id: its top level then, and
                             // again whenever the app or its titles change. With `answering` set: the reply to one of
                             // that device's kind 27s (one menu's items) or kind 25s
    case pressMenuItem = 25  // device → host: JSON PressMenuItem — choose one item, by the id and title the device was
                             // shown in that tree version. Answered to that device alone (a kind 24 with `pressed`)
    case fetchMenu = 27      // device → host: JSON FetchMenu — one menu's current items, asked when the device opens it;
                             // without an id, the top level, and a request for every later one on this connection.
                             // Answered to that device alone, from a read of at most 1 s ago
```

- **Who skips them.** Every device and test client since b67f87d (2026-09-23) skips an unknown
  kind: `parseHeader` maps it to `.unknown` (StreamMessage.swift:95-104, the mapping at :99), and
  StreamClient's `handle` ignores it (StreamClient.swift:2444-2445). A host from before this change
  skips 25 and 27 the same way: `default: break` at StreamCoordinator.swift:664-666.
- **Nothing else changes.** Kinds 0–23 are untouched, and so is the catalog sent on connect
  (`sendCatalog`, StreamCoordinator.swift:1582-1601). `SillProtocol.current` stays 1: these kinds
  are additive (Compatibility.swift:16-23). Its comment's "kinds 0–23" becomes "kinds 0–23, and any
  later kind an older peer can skip".
- **Order in the enum.** 24, 25 and 27 are written in that order. If the pointer's 26 lands first,
  it goes between them.

#### 3.2 The payloads (`Sources/StreamProtocol/MacMenu.swift`, new; the app gets it through the package, no pbxproj entry)

```swift
/// Host → device (kind 24). One of three shapes, told apart by which fields are set:
/// a top level (`menus`, and `answering` only when it replies to the kind 27 that asked for it),
/// the answer to a kind 27 for one menu (`answering`, `menu`, `items`), the answer to a kind 25
/// (`answering`, `pressed`). Every field optional (HostSettings.swift's rules).
public struct MacMenu: Codable, Hashable, Sendable {
    /// The tree this belongs to. The host adds 1 whenever the app whose menus these are changes, or
    /// its top level does; ids are good only within one version. In every kind 24.
    public var version: Int?
    /// "Code", "com.microsoft.VSCode": the app, in a top level only.
    public var app: String?
    public var bundleID: String?
    /// The top level in the Mac's order, the Apple menu left out: each a submenu whose items come
    /// with kind 27. Empty when there are no menus (nothing streams, Sill's own app, no menu bar,
    /// no Accessibility: `note` says which when the device should show it).
    public var menus: [MacMenuItem]?
    /// The token of the kind 27 or 25 this answers.
    public var answering: Int?
    /// The answer to a kind 27: the menu's id, its items (at most 500), and how many more it has.
    public var menu: String?
    public var items: [MacMenuItem]?
    public var more: Int?
    /// The answer to a kind 25: whether the host pressed the item.
    public var pressed: Bool?
    /// The app did not answer the last read within 1 s: what is shown may be old, and presses are
    /// refused until it answers again. The device shows every item disabled.
    public var stale: Bool?
    /// Words the device shows as they are: why there are no menus, why a press was refused, why a
    /// menu could not be read.
    public var note: String?
}

/// One menu or item, as the Mac draws it.
public struct MacMenuItem: Codable, Hashable, Sendable {
    /// "3.4": the item's indexes from the menu bar, 0-based as Accessibility lists them (separators
    /// count; the Apple menu is 0, so the first mirrored menu is 1). Good within one version.
    public var id: String?
    public var title: String?
    /// A separator: no id, no title.
    public var separator: Bool?
    /// Nil counts as true.
    public var enabled: Bool?
    /// The Mac's mark: "✓" (on), "-" (mixed), or another single character an app set; nil unmarked.
    public var mark: String?
    /// The shortcut as the Mac draws it: "⇧⌘S", "⌃⌘←", "F5", "fn ⌃F". Display only.
    public var key: String?
    /// Has items of its own, fetched with kind 27 when the device opens it.
    public var submenu: Bool?
}

/// Device → host (kind 27). No `id`: the top level, and every later top level on this connection.
public struct FetchMenu: Codable, Hashable, Sendable {
    public var version: Int?
    public var id: String?
    public var token: Int?
}

/// Device → host (kind 25).
public struct PressMenuItem: Codable, Hashable, Sendable {
    public var version: Int?
    public var id: String?
    /// The title the device showed: checked when the host has to find the item again by its path.
    public var title: String?
    public var token: Int?
}
```

Each type gets an explicit public memberwise `init`, as HostSettings.swift's types have.

#### 3.3 Ids, versions, tokens, and who is sent what

- **Ids are paths.**
  - An id is "i.j.k": the item's `AXChildren` index at each level below the bar, separators
    counted.
  - Each part is at most 4 digits, without a leading zero, with at most 8 levels. So an item has
    exactly one id.
  - A request whose id starts at 0 (the Apple menu), has more levels, or does not parse is refused
    with a note.
  - A path is stable while the menu's structure is. Where it is not (a Window list, Open Recent),
    the kept element or the title check catches it (§4.3).
- **Presses are for leaves.** A kind 25's id has at least two parts, since one part names one of
  the bar's menus. It must also name an item without a submenu. Any other is refused with "The
  menus changed. Open the menu again.", and nothing is pressed: `AXPress` on a bar item or a
  submenu item opens that menu on the Mac (§4.3).
- **The version is the host's, one for all devices.** There is one stream, so one app.
  - It starts at 1 each launch, and the first app the mirror takes moves it. So on a fresh host
    the first app's top level is version 2, whether the subscription or the pick came first (a
    subscription before any app is answered `{version 1, menus: []}`). H5 relies on it.
  - The host adds 1 when the target app changes (to none included, and when the app quits), or when
    a re-read finds the top level's titles, count or enabled flags changed.
  - Another window of the same app keeps the version, since it is the same menu bar. The cache is
    cleared: the key window, and with it the states, changed (§4.4).
  - A kind 25 or 27 with another version is answered in its turn and never read or pressed:
    - fetch: `items: []` with "The menus changed. Open the menu again.";
    - press: `pressed: false` with the same note.
- **Tokens are the device's,** strictly increasing per connection, as kind 17's are. The host only
  echoes them in `answering`.
- **Who is sent what.**
  - The host keeps a set of subscribers: the connections that sent a kind 27 without an id. The
    set is cleared per connection when it closes.
  - Top levels go only to subscribers.
  - With no subscriber the host reads nothing, and the coordinator's target changes cost one
    comparison.
  - So an older device, `sillclient.py` without `--menus`, and every parity run are served exactly
    as before.
- **Order.** Each connection is one TCP stream, and the host serves every request one at a time in
  arrival order (§4.4), so answers follow requests. The one exception is a refusal over the rate
  limit: it goes out at once, ahead of answers still queued. Tokens match answers to requests either
  way, and no clock is compared anywhere.

#### 3.4 Examples

```jsonc
// kind 27, the device's subscription after its first window list
{"token":1}
// kind 24, the answer and the top level
{"version":3,"answering":1,"app":"Code","bundleID":"com.microsoft.VSCode","menus":[
  {"id":"1","title":"Code","submenu":true},{"id":"2","title":"File","submenu":true},
  {"id":"3","title":"Edit","submenu":true}, … ,{"id":"10","title":"Help","submenu":true}]}
// kind 27, File opened on the device
{"version":3,"id":"2","token":2}
// kind 24, its items (2.2, the separator, still counts in the ids)
{"version":3,"answering":2,"menu":"2","items":[
  {"id":"2.0","title":"New Text File","key":"⌘N"},{"id":"2.1","title":"New File…","key":"⌃⌥⌘N"},
  {"separator":true},{"id":"2.3","title":"Open Recent","submenu":true},
  … ,{"id":"2.9","title":"Save","key":"⌘S"},{"id":"2.12","title":"Auto Save","mark":"✓"},
  {"id":"2.14","title":"Revert File","enabled":false}]}
// kind 25, Save chosen
{"version":3,"id":"2.9","title":"Save","token":3}
// kind 24, the answer
{"version":3,"answering":3,"pressed":true}
// kind 24, a refusal
{"version":4,"answering":4,"pressed":false,"note":"The menus changed. Open the menu again."}
// kind 24, a top level while the app does not answer
{"version":4,"app":"Blender","bundleID":"org.blenderfoundation.blender","menus":[…],"stale":true,
 "note":"Blender isn’t responding."}
// kind 24, no menus (nothing streams, or Sill itself is frontmost)
{"version":5,"menus":[]}
```

#### 3.5 Compatibility

| Device | Host | Result |
|---|---|---|
| Older (any build since b67f87d) | This host | Never sends kind 27, so it is never a subscriber. The host reads nothing for it and sends it nothing |
| This device | Older host (main at 150f781, and every earlier Sill.app and CLI) | Its kind 27 is skipped as unknown and no kind 24 comes. No Menus button, no menus in the iPad's bar, nothing else changes. The device waits for nothing: it shows the button only once a kind 24 arrives |
| This device | This host | This plan |
| `sillclient.py` at 150f781 | This host | Unaffected: it never sends kind 27 |
| Devices before b67f87d | Any current host | They already stop at kinds 14–23; nothing new |

#### 3.6 Rules for later changes

HostSettings.swift's rules apply to all four types:
- JSON only;
- new fields optional;
- strings, not enums;
- never rename or retype a field.

A later "alternate of the item above" flag, or an SF Symbol name from a Catalyst app, would be an
optional field.

---

### 4. Host (`SillHostCore`, folder `Sources/SillHost`), file by file

The ground rules for this section:
- Nothing becomes `public`. The pure files use `package` access, so their checks compile them with
  `-package-name sill`, as `clientlink`'s does.
- The main actor is reached with `Task { @MainActor }`, never `MainActor.assumeIsolated`.
- Accessibility:
  - It runs only on `sill.menus`, except the activation, which is the coordinator's existing code
    on the main actor: the app made active and the streamed window made key (`focusForMenus`, §4.5),
    as for a click.
  - Every element touched gets `AXUIElementSetMessagingTimeout(element, 1.0)` before its first
    call. That is a local call, with no IPC.
  - The process-wide default is never changed. It would change the timeouts of the injector and the
    sizer too.

#### 4.1 `MenuFormat.swift` (new; pure: Foundation and StreamProtocol; checked with swiftc)

```swift
/// What Accessibility gave for one menu item, before anything is decided about it.
package struct RawMenuItem: Equatable {
    package var title: String?          // nil: no AXTitle at all (NoValue); "" is a separator's
    package var description: String?    // AXDescription (setAccessibilityLabel)
    package var enabled: Bool?
    package var mark: String?           // AXMenuItemMarkChar
    package var char: String?           // AXMenuItemCmdChar
    package var modifiers: Int?         // AXMenuItemCmdModifiers
    package var virtualKey: Int?        // AXMenuItemCmdVirtualKey
    package var glyph: Int?             // AXMenuItemCmdGlyph
    package var childCount: Int
    package var firstChildRole: String? // "AXMenu" for a submenu
}

package enum MenuFormat {
    /// The item as the device gets it, or nil for one it never shows.
    package static func item(_ raw: RawMenuItem, id: String) -> MacMenuItem?
    /// One of the bar's menus (every one a submenu), or nil for one without a title.
    package static func topItem(_ raw: RawMenuItem, index: Int) -> MacMenuItem?
    /// The title a device is shown, and the one a press compares: AXTitle, else AXDescription,
    /// `SafeText.label` to 100 characters. A title of "" stays "".
    package static func displayTitle(title: String?, description: String?) -> String
    /// The shortcut as the Mac draws it, or nil for none.
    package static func shortcut(char: String?, modifiers: Int?, virtualKey: Int?, glyph: Int?) -> String?
    package static let titleLimit = 100, keyLimit = 16
}

/// An id: indexes from the menu bar.
package struct MenuPath: Hashable {
    package let indexes: [Int]
    package init?(_ id: String)          // "3.4.1"; 1–8 parts of 1–4 digits, no leading zero; the first at least 1
    package var id: String
    package var parent: MenuPath?
    package func child(_ i: Int) -> MenuPath?   // nil past 8 levels or 9999
    package var lineage: [MenuPath]             // "4.21.0" → 4, 4.21, 4.21.0 (the log line's titles)
}
```

**`item`, in order:**
1. **A separator.** A title of "" (empty, not missing), disabled, with no children →
   `MacMenuItem(separator: true)`. An enabled item titled "" is not one: it is an image-only item,
   and rule 2 decides it.
2. **The title.** `SafeText.label(title ?? description ?? "", limit: 100)`. Empty after that →
   nil: a custom view (Finder's Tags), an image-only item, or an untitled item with no
   description. Chrome's untitled bookmarks show if they carry a description (P4).
3. **A submenu.** Children, and the first child's role is `AXMenu` → `submenu: true`. Children of
   any other role (a custom view's) → nil.
4. **Enabled.** `enabled: false` only when AX said false. A missing value counts as enabled.
5. **The mark.** Its first character, cleaned: "✓", "-", "•"…; nil when missing or empty.
6. **The key.** `shortcut(…)`, nil when there is none.

**`shortcut`, in order:**
1. **No key.** Nil when the character, the virtual key and the glyph are all missing. The
   modifiers are present on every item, shortcut or not (0 or 8), so they decide nothing alone.
2. **The key, first match wins:**
   - The glyph when it has a name in the table below.
   - Else the character: a special one from the table; U+F704…U+F726 → F1…F35; any other
     private-use character → no key (and nil overall, since nothing readable remains); a printable
     one → itself, as AX gives it (uppercase letters: the Mac draws them so).
   - Else the virtual key from the table.
   - A glyph that is not in the table (150, dictation) with a printable character → that character
     ("🎤").
3. **Modifiers, in Apple's order:** "fn " (bit 16), ⌃ (4), ⌥ (2), ⇧ (1), then ⌘ unless bit 8
   (NoCommand) is set.
4. **Length.** At most 16 characters, else nil.

| Source | Value → shown |
|---|---|
| Character | \u{8} and \u{7f} → ⌫, \u{1b} → ⎋, \r → ↩, \u{3} → ⌤, \t → ⇥, " " → Space, U+F700 → ↑, U+F701 → ↓, U+F702 → ←, U+F703 → →, U+F728 → ⌦, U+F729 → ↖, U+F72B → ↘, U+F72C → ⇞, U+F72D → ⇟ |
| Glyph (Carbon Menus.h) | 2 ⇥, 4 ⌤, 9 Space, 10 ⌦, 11 ↩, 23 ⌫, 27 ⎋, 28 ⌧, 98 ⇞, 100 ←, 101 →, 102 ↖, 104 ↑, 105 ↘, 106 ↓, 107 ⇟, 111–122 F1–F12, 135–137 F13–F15 |
| Virtual key (Events.h) | 36 ↩, 48 ⇥, 49 Space, 51 ⌫, 53 ⎋, 76 ⌤, 115 ↖, 116 ⇞, 117 ⌦, 119 ↘, 121 ⇟, 123 ←, 124 →, 125 ↓, 126 ↑, 122 F1, 120 F2, 99 F3, 118 F4, 96 F5, 97 F6, 98 F7, 100 F8, 101 F9, 109 F10, 103 F11, 111 F12 |

Examples from the probe:
- "K" with 0 → "⌘K";
- "E" with 1 → "⇧⌘E";
- U+F708 with 8 → "F5";
- \u{8} with glyph 23 and 0 → "⌘⌫";
- the Fill item's "F" with 28 → "fn ⌃F";
- a tiling item with only virtual key 123 and 29 → "fn ⌃⇧←".

#### 4.2 `MenuPolicy.swift` (new; pure: Foundation and StreamProtocol; checked with swiftc)

The mirror's decisions as values, so they can be checked without Accessibility:

```swift
package struct MenuCache {
    package static let lifetime = 1.0                    // answered from within this
    package static let revalidation = 1.05               // AppKit validates a menu again only after about a second
    package struct Entry { package let items: [MacMenuItem]; package let more: Int; package let at: Double; package let appWasFrontmost: Bool }
    package mutating func store(_ id: String, _ entry: Entry)
    /// An entry to answer from: read less than `lifetime` ago, while the app was frontmost; or while
    /// it was not, when `frontmostNow` is false too (AppKit would answer a read now from that
    /// validation). Asked with `frontmostNow: true` before `prepare`, and again after it with what
    /// `prepare` found.
    package func fresh(_ id: String, now: Double, frontmostNow: Bool) -> Entry?
    /// How long to wait before reading `id` again, the app now frontmost: the rest of
    /// `revalidation` after a read made while it was not; else 0.
    package func wait(_ id: String, now: Double) -> Double
    package mutating func clear()
}

package struct RequestRate {
    package static let fetchesPerSecond = 20, pressesPerSecond = 4
    package mutating func allowFetch(now: Double) -> Bool
    package mutating func allowPress(now: Double) -> Bool
    package mutating func ignoredLineDue(now: Double) -> Bool   // one "ignored" line a second at most
}

package struct TopLevel: Equatable {
    package var titles: [String]; package var enabled: [Bool]
    /// Only a change here moves the version (with the app's own change).
}

/// Why a fetch or a press was not served: its note (§7.7) and the end of its log line (§4.7).
package enum MenuRefusal: Equatable {
    case disabled, changed, gone, notAnswering, notTrusted, tooMany, failed(String)
    package func note(app: String) -> String
    package func logReason(app: String) -> String
}

package enum PressDecision: Equatable {
    case press                  // the kept element, its title still the one shown
    case pressFound             // found again by its path, its title the one shown
    case refuse(MenuRefusal)
    /// `elementValid`: the kept element answered; `current`: the item's title now (the kept
    /// element's, or the one found at the path; nil: nothing there); `shown`: the device's;
    /// `enabled`: its AXEnabled; `hasChildren`: it has a submenu (or a custom view's children).
    package static func decide(elementValid: Bool, current: String?, shown: String?, enabled: Bool?,
                               hasChildren: Bool) -> PressDecision
}

/// "Code › File › Save" from the host's own titles, each `SafeText.label`'s 64 characters; nil when
/// any is unknown (the line then gives the id).
package enum MenuLog { package static func path(app: String, titles: [String?]) -> String? }
```

The rules:
- **The title is compared for every press.** The item's title now must be the title the device
  showed, for a kept element as for one found again by its path. The reason is in "Pressing" above:
  delegates that reuse their NSMenuItems. An empty or missing title never matches → `.changed`.
- **A leaf only.** An item with children → `.changed`, and nothing is pressed. The mirror refuses an
  id of one part before it reaches the reader.
- **A disabled item is refused** with "It isn’t available right now." The title is checked first, so
  a retitled and disabled item reads as changed.
- **The cache** answers only where a read now would return the same thing: within the second
  AppKit repeats its last validation, whatever the app's state. So a read under a second old
  answers, unless it was made while the app was not frontmost and `prepare` has since brought it
  forward: then the states the device should see are an active app's, and a new read is made once
  `revalidation` has passed. The probe's reads 0.43 and 0.83 s after a validation got no new one,
  and reads 1.03, 1.29 and 1.83 s after did.

#### 4.3 `MenuReader.swift` (new): Accessibility on `sill.menus`

```swift
/// Accessibility reads and presses of one app's menu bar. Every call runs on `queue`, never on the
/// main actor or `sill.net`: an app's answer can take a second (Blender: 6 ms a call; a hung app the
/// whole timeout), and a press waits for the app's action.
final class MenuReader: @unchecked Sendable {
    let queue = DispatchQueue(label: "sill.menus", qos: .userInitiated)
    static let timeout: Float = 1.0
    static let maxMenus = 32, maxItems = 500
    static let readBudget = 1.5                  // seconds for one menu's items

    struct Read { let item: RawMenuItem; let index: Int; let element: AXUIElement }
    struct Menu { let reads: [Read]; let total: Int; let ms: Double }   // total: all AXChildren
    enum Failure: Error, Equatable {
        case notTrusted                  // AXIsProcessTrusted() false, or .apiDisabled
        case noMenuBar                   // no AXMenuBar (a background-only app)
        case gone                        // the process exited (an error from a pid no longer alive)
        case notAnswering                // .cannotComplete after at least 0.9 × timeout
        case failed(String)              // any other error: WindowSizer.axErrorName (WindowSizer.swift:232)
    }
    func topLevel(pid: pid_t) -> Result<(titles: [Read], ms: Double), Failure>
    func items(pid: pid_t, of parent: AXUIElement?, path: MenuPath) -> Result<Menu, Failure>
    func press(pid: pid_t, element: AXUIElement?, path: MenuPath, shownTitle: String?) -> Pressed
}
struct Pressed { enum Outcome { case pressed, pressedNoAnswer, refused(MenuRefusal) }; let outcome: Outcome; let foundTitle: String? }
```

**`topLevel`:**
- The app element's `kAXMenuBarAttribute`, then its `AXChildren`.
- For each child but the first (the Apple menu, first in 13 of 13 apps), one
  `AXUIElementCopyMultipleAttributeValues` of `[AXTitle, AXEnabled]`.
- At most 32 menus.

**`items`:**
- The parent's element is the bar item or submenu item the host kept, or else the path walked from
  the bar. A kept one that fails (`failed`: rebuilt, gone) gives way to the walk.
- Its `AXChildren`: the first `AXMenu`, then that menu's `AXChildren`. This read makes the app
  validate the menu.
- Then one `AXUIElementCopyMultipleAttributeValues` per item, of `[AXRole, AXTitle, AXDescription,
  AXEnabled, AXMenuItemMarkChar, AXMenuItemCmdChar, AXMenuItemCmdModifiers,
  AXMenuItemCmdVirtualKey, AXMenuItemCmdGlyph, AXChildren]`. No action names: every
  `AXMenuItem` has `AXPress`.
- A child whose role is not `AXMenuItem` is skipped. Its index still counts, so the ids stay
  Accessibility's.
- A missing attribute comes back as an AXValue holding an AX error. Read it as nil (nil title:
  missing; "" title: a separator). An `.invalidUIElement` inside the answer fails the read (the item
  went meanwhile).
- For a titled item with children: one more `AXRole` read of its first child.
- At most 500 items are read; `more` counts the rest from `AXChildren`'s count.
- **At most `readBudget` (1.5 s) per menu.** Past it, the read stops after the item in hand, and the
  unread rest counts in `more` too (the device shows "‹n› more on the Mac"). One call may take up to
  the 1 s timeout, so a read ends by about 2.5 s.
  - Why: a menu costs a call per item, two for a submenu item, and every request queues behind it
    (§4.4). 500 items at Blender's 6 ms a call take 3 s or more, near or past the device's 4 s wait.
  - Blender's 42-item Window menu (290 ms) and every menu the probe timed stay far inside it.

**`press`, in order:**
1. **The item as it is now.**
   - A kept element: one `AXUIElementCopyMultipleAttributeValues` of `[AXTitle, AXDescription,
     AXEnabled, AXChildren]`. It is fresh within a second: the read validates the menu.
   - That read fails with `failed` (`.invalidUIElement`: rebuilt), or there is no kept element:
     walk the path from the bar and read the same four of the item found.
   - Then `PressDecision.decide`: the title against the one shown (`displayTitle`, as the device
     was sent it), the children, the enabled flag.
2. **`AXUIElementPerformAction(element, kAXPressAction)`.**
   - `.success` → pressed.
   - `.cannotComplete` after at least 0.9 s → `pressedNoAnswer`: the action is running, often a
     modal dialog.
   - Anything else → refused, with the error's name.

**Every failure is typed,** so the mirror can tell a hung app (stale) from a closed one (gone),
from missing permission.

#### 4.4 `MenuMirror.swift` (new): the coordinator's menus (main actor)

```swift
@MainActor
final class MenuMirror {
    struct Target: Equatable {
        let pid: pid_t; let app: String; let bundleID: String?
        /// The streamed window, for a window source: another window of the same app is another
        /// target (the cache goes) with the same version (the same menu bar).
        var window: UInt32? = nil
    }
    init(server: StreamServer, reader: MenuReader = MenuReader())
    /// Before a read or a press of a window source: its app active and the window key (the
    /// coordinator's `focusForMenus`). True when the app is frontmost as it returns; true at once
    /// for the Desktop and for nothing.
    var prepare: () async -> Bool = { true }
    /// The app behind the current source, asked when the first device subscribes (the coordinator
    /// tells the mirror of changes only while someone subscribes).
    var currentTarget: () -> Target? = { nil }
    /// The first device subscribed (true) or the last one left (false): the coordinator watches
    /// NSWorkspace's activations only in between.
    var onSubscribersChanged: ((Bool) -> Void)?
    func setTarget(_ t: Target?)                                  // from the coordinator
    func fetch(_ r: FetchMenu, from c: NWConnection, who: String) // kind 27, with or without an id
    func press(_ r: PressMenuItem, from c: NWConnection, who: String)
    func clientLeft(_ c: NWConnection)
    func catalogPolled()                                          // the retries (below)
    var hasSubscribers: Bool { get }
}
```

**The state it holds:**
- the target and `version`;
- the top level (items, whether this version's has been read, and `TopLevel` for comparing);
- `stale` and `note`;
- `elements[path] = (element, title)`: this version only, at most 5,000 entries, filled by reads;
- `cache: MenuCache`;
- the subscribers, by `ObjectIdentifier`, with their connections;
- a `RequestRate` per connection;
- the last top level broadcast, so an unchanged one is not sent again;
- `chain`: the request being served. **One request at a time, in arrival order**: a fetch (its
  activation, its wait, its read), a press, a subscription's read, a target change's read, a
  retry. So a device's answers follow its requests, two reads of one app never overlap, and a
  fetch of a menu whose read is under way is answered from that read's cache entry when its turn
  comes. The cost is that a slow request holds the rest back, which `readBudget` and the 1 s AX
  timeout bound. A refusal over the rate limit is answered at once, outside the chain.

**`setTarget`:**
- **Equal to the current target:** nothing.
- **The same app (the same pid), another window:** the version, the ids and the kept elements stay;
  the cache is cleared, since its states belong to another key window. With subscribers, the top
  level is sent again only if it changed (a name shown differently).
- **Otherwise:** `version += 1`, and the cache, the elements and the top level are cleared.
  - Nil target, or no subscribers: send `{version, menus: []}` to the subscribers, if any. Read
    nothing.
  - Else read the top level on `sill.menus`, and send one kind 24 to each subscriber when it
    returns. Never send an empty one in between: the device's button would flicker.
  - A read that fails with `failed` (a passing error) sends nothing. The next catalog poll reads
    again (`catalogPolled`), and so on while it fails. Until then the devices keep the previous
    top level, whose fetches and presses the version check refuses.
- A read that returns for a target that has since changed is dropped.

**`fetch` without an id (the subscription):**
- Add the connection to the subscribers.
- The first subscriber: take `currentTarget()`, as `setTarget` would (a different app moves the
  version). Until then the mirror heard of no change.
- Answer with the current top level, read again first (nobody may have watched it change while no
  one subscribed), with `answering` set.
- A second one on the same connection is answered the same way and adds nothing.

**`fetch` with an id:**
1. **Checks, in order:**
   - the rate (20 a second; the excess gets "Too many requests. Open the menu again." at once, and
     at most one "ignored" line a second);
   - then, in its turn in the chain: the version; the path (§3.3); a target;
   - stale: answered with the note, no read.
2. **A cache entry `fresh(id, now, frontmostNow: true)`** → answered from it (`menu.cached`), with no
   activation.
3. **Otherwise:**
   - `let frontmost = await prepare()`;
   - `frontmost` false and `fresh(id, now, frontmostNow: false)` → answered from it (`menu.cached`);
   - else wait `cache.wait(id, now)`;
   - on `sill.menus`: re-read the top level, then read the menu.
4. **Back on main:**
   - A changed top level → `version += 1`, broadcast it, and answer this fetch "The menus changed.
     Open the menu again.".
   - `notAnswering` → stale with "‹App› isn’t responding.": the top level is sent again with
     `stale: true` and the same version.
   - `gone` → a nil target: the version moves, `menus: []`, and this fetch gets "‹App› is no
     longer open.".
   - `notTrusted` → the note in §7.7.
   - Else: store the cache (`appWasFrontmost` as `prepare` found it) and the elements, then answer.

**`press`:**
- **Checks, in order:** the rate (4 a second), then in its turn the version, the path, **at least two
  parts** (never one of the bar's menus), stale.
- `await prepare()`.
- On `sill.menus`: `reader.press(…)`, which refuses an item with children or another title (§4.2).
- Back on main: log (§4.7), answer, and clear the cache: a press can change any state.

**`catalogPolled`** (each catalog poll, every 2 s while a device is connected and someone
subscribes), one read at a time:
- While stale, re-read the top level. A read that succeeds clears stale ("answering again") and
  sends the top level.
- While this version's top level is unread (its read failed with `failed`), or was refused for
  Accessibility, read it again. A grant of Accessibility then shows the menus within 2 s, without
  a pick.

**`clientLeft`:** drop the subscriber and its rate. With the last one gone, let go of the kept
elements and the cache; the next subscriber reads afresh.

**Target and version are main-actor state.** Reads carry the version they were started for, and
anything older is dropped when it comes back, so no read can answer for the wrong tree.

#### 4.5 `StreamCoordinator.swift`

- **`let menus = MenuMirror(server: server)`,** made in `init` after `server`, with
  `menus.prepare = { [weak self] in await self?.focusForMenus() ?? true }`,
  `menus.currentTarget = { [weak self] in self?.menuTarget() }`,
  `menus.onSubscribersChanged` (the NSWorkspace observer below) and `catalog.onPolled`
  (`menusPolled`, below).
- **`handle` (StreamCoordinator.swift:572-667)** gains two cases:
  - `.fetchMenu`: decode `FetchMenu`, then `menus.fetch(r, from: connection, who:
    deviceName(connection))`;
  - `.pressMenuItem`: decode `PressMenuItem`, then `menus.press(r, from: connection, who:
    deviceName(connection))`.
  - JSON that does not decode is ignored: it has no token to answer.
  - Neither awaits in `handle`: the mirror schedules its own work, as `setTarget` does for settings.
- **`active`'s didSet (StreamCoordinator.swift:130-137)** calls `menuTargetChanged()`, which is
  `menus.setTarget(menuTarget())` when `menus.hasSubscribers`, and nothing otherwise. `menuTarget()`:
  - `.none` → nil;
  - `.window(id)` → the staged placement's pid (`stage.placement`) or
    `catalog.window(id:)?.owningApplication`'s, with the window's id; the name and bundle ID from
    `NSRunningApplication(processIdentifier:)`, as for the Desktop, so one app has one name;
  - `.desktop` → `desktopMenuTarget()`.
  - The mirror calls it through `currentTarget` when its first device subscribes.
- **`desktopMenuTarget()`:**
  - A synthetic host: the hook's process (§4.8), else nil.
  - Otherwise `Self.activePID(trustAppKit: appKitLoop)` (StreamCoordinator.swift:1246-1249).
    - That is `NSWorkspace.frontmostApplication` under the AppKit loop, else the owner of the
      topmost layer-0 window, since the frontmost application is stale without the loop. In the
      plain CLI an app with no window on screen (Finder with only the desktop) therefore reads as
      the next app with one, or none, as input's activation already does.
    - The name and bundle ID come from `NSRunningApplication(processIdentifier:)`.
  - Nil when it is this process (`WindowCatalog.ownPID`, WindowCatalog.swift:119): Sill never
    mirrors itself (a device's "Quit Sill" would end the host).
- **The Desktop's frontmost app changes.** `menuTargetChanged()` runs, while the Desktop streams
  and someone subscribes:
  - after every catalog poll (2 s): `WindowCatalog.onPolled`, new, fires after each poll's window
    list read, changed or not. (`windowsChanged`, StreamCoordinator.swift:1521-1567, runs only when
    the list changed, and a new frontmost app need not change it.)
  - 0.3 s after a delivered left or right mouse down, or a key down, at most once per 0.5 s (a click
    in the picture on another app's window activates it 50–200 ms later);
  - under the AppKit loop (Sill.app, the CLI's `--virtual-display`), on
    `NSWorkspace.didActivateApplicationNotification`, observed only while someone subscribes.
- **`menusPolled()`**, the `onPolled` hook: with a subscriber, the Desktop's target check above,
  then `menus.catalogPolled()` (the retries of §4.4). Nothing without a subscriber.
- **`onClientDisconnected` (StreamCoordinator.swift:235-247)** calls `menus.clientLeft(connection)`.
- **`focusForMenus() async -> Bool`**, new, next to `activateAndRaise`; true when the app is
  frontmost as it returns:
  - `.desktop` and `.none` → true at once. A switch in flight (`switching`: `active` still names
    the old source) → at once, with whether the app is frontmost now.
  - `.window`:
    - The app's pid, as `raiseIfInteracting` finds it (:1113-1114).
    - Not the active app (`activePID`) → `activate(pid:)` (:1185-1199), throttled by the same
      `lastActivationAt` (one attempt per 2 s).
    - The attempt throttled (another activation, a click's included, under 2 s ago) → false at once:
      the menu then reads as an inactive app's, and the cache keeps it apart (§4.2).
    - `WindowSizer.makeKey` on the staged element, or on the one `sizer.element(for:)` matches,
      **every time, frontmost or not**. The app can be frontmost with another of its windows key, and
      then its states and a press's nil-targeted action (Close, Save) would be that window's. On the
      main actor this is an AX window lookup (the app's windows, each one's title and frame) and two
      writes per uncached fetch and per press: about what a click that activates costs. A frontmost
      app that hangs costs the main actor that lookup's timeout once: the read after it marks the
      app stale, and a stale app's requests are answered without `prepare`.
    - Then poll every 20 ms until the app is active, for up to `activationTimeout` (0.6 s, :1077).
  - No raise: a menu needs the app active and the window key, not uncovered.
  - An app that ran into the AX timeout gets nothing more (`activate` returns false). Its menus
    then read as an inactive app's.
- **Nothing in `select` or `sendCatalog` changes.** Devices ask; the catalog is as it was.

#### 4.6 Which app, per source

| Source | Menus of | Activation before a read or press |
|---|---|---|
| Nothing (`.none`) | None (`menus: []`) | — |
| A window, regular mode | The window's app (`SCWindow.owningApplication`) | The app activated and the window made key, as a click does |
| A window on the virtual display | The staged window's app (`stage.placement.pid`) | The same, with the staged element made key. The Mac's focus moves to that app, as a click from the device already moves it (Q5) |
| The Desktop | The frontmost app, unless it is Sill | None: it is already frontmost |
| The synthetic test pattern | None; the hook's process with `SILL_TEST_MENU_PID` | None, ever: the Desktop's rule |

#### 4.7 Log lines and Stats keys (exact; none unless a device uses the menus)

```
Menu from iPad (iPad14,1): Code › File › Save
Menu from iPad (iPad14,1): Code › File › Save (Code did not answer within 1 s; a dialog may be open)
Menu from iPad (iPad14,1) refused: Code › File › Revert File: the menus changed
Menu from iPad (iPad14,1) refused: Code › File › Save: disabled
Menu from iPad (iPad14,1) refused: Code › File › Save: Code is no longer open
Menu from iPad (iPad14,1) refused: Code › File › Save: Code is not answering Accessibility
Menu from iPad (iPad14,1) refused: Code › File › Save: Accessibility refused it (failure)
Menu from iPad (iPad14,1) refused: 2.9: the menus changed
Menu from iPad (iPad14,1) refused: 2.9: no Accessibility permission
Menus from iPad (iPad14,1) ignored: more than 20 requests a second.
Menus from iPad (iPad14,1) ignored: more than 4 choices a second.
Menus of Blender not answering (1.0 s); shown as unavailable until it answers.
Menus of Blender answering again.
```

- **The titles in a line are the host's own,** from its element table: the app, each menu on the
  path, the item, and for an item found again by its path the title found there. Each is cleaned
  with `SafeText.label` (64 characters). The device's `title` is never logged. Without a title the
  line gives the id: a request for another version (the host keeps only the current version's
  titles), an id that names nothing, or no Accessibility.
- **Fetches print nothing.** They happen whenever a menu is opened.
- **Stats keys** join the `[1s]` line only in seconds that bumped them (Stats.swift:112):
  - `menu.top`: top-level reads;
  - `menu.read`: menus read;
  - `menu.cached`: fetches answered from the cache;
  - `menu.press`, `menu.refused`;
  - `menu.axTimeout`: reads or presses that ran into the timeout.

#### 4.8 The self-test and the TEST ONLY hook

- **`--menu-selftest[=APP]`**, in the CLI and in Sill.app (`Sill.app/Contents/MacOS/Sill
  --menu-selftest`), like the two other self-tests.
  - **Read-only:** it never activates anything and never presses.
  - **The app.** `APP` is a pid, or the start of a running app's name, case-insensitive. Without
    it, the frontmost app.
  - **What it prints:** the top level and each top-level menu's items one level deep, exactly as a
    device would get them, with each read's time. Then it exits 0, or 1 when nothing could be read.
  - **The "=" is needed:** a bare second argument is the CLI's window match (main.swift:18).
  - **Each menu it reads, the app validates,** as if that menu had been opened.

  ```
  Menu self-test: Code (com.microsoft.VSCode, pid 812), not frontmost: states are an inactive app's.
    top level, 10 menus in 2.1 ms: Code, File, Edit, Selection, View, Go, Run, Terminal, Window, Help
    1 Code, 9 items in 4.2 ms: About Visual Studio Code | — | Settings ▸ | — | Services ▸ | — | Hide Visual Studio Code ⌘H | …
    2 File, 24 items in 6.0 ms: New Text File ⌘N | New File… ⌃⌥⌘N | New Window ⇧⌘N | — | … | Revert File (off) | …
  ```

- **`SILL_TEST_MENU_PID=<pid>`.** Honoured only by a `--synthetic` host, which does not advertise.
  - The test pattern's menus are that process's.
  - The host reads and presses them through the same code, and never activates it (the Desktop's
    rule).
  - One line at startup:

  ```
  Test menus: the test pattern's menus are pid 4242's (menufixture); read and pressed without activating it.
  SILL_TEST_MENU_PID=4242 ignored: only a --synthetic host takes it.
  SILL_TEST_MENU_PID=abc ignored: not a running process.
  ```

#### 4.9 Cost

| What | Cost | How often |
|---|---|---|
| Top level | 0.4–3.8 ms (Blender 26 ms; 15–50 ms the first read of an app) | At a pick or app change, alongside each fetch, only with a subscriber |
| One menu | 3–20 ms (Blender 290 ms for 42 items), on `sill.menus`; 1.5 s at most (`readBudget`) | When a device opens it, unless read less than 1 s ago |
| A press | One read of the item (title, description, enabled, children) and one `AXPress`; up to 1 s when the action is modal | Per choice |
| Activation | As a click's (StreamCoordinator.swift:1185-1199), at most one attempt per 2 s | Before a read or press of a window source whose app is not active |
| The streamed window made key | An AX window lookup and two writes, on the main actor | Before every uncached read and every press of a window source |
| Idle, or no subscriber | Nothing | The mirror reads only for requests, target changes with subscribers, and the retries (stale, unread, no Accessibility) at each catalog poll |

---

### 5. CLI, `sillclient.py` and the fixture

**`Sources/SillHostCLI/main.swift`:**
- `--menu-selftest[=APP]` (§4.8).
- **The default path is byte for byte what it prints today, idle and streaming.**
  - A synthetic host has no menus without the hook.
  - No device subscribes without a kind 27; the parity runs' `sillclient.py` sends none.
  - Nothing prints until a device presses.

**`Scripts/sillclient.py` gains:**
- `--menus`: a kind 27 without an id right after the select (token 1). Each kind 24 is printed on
  one line:
  - `  menus v3 at 1.234s: menufixture ▸ | File ▸ | Edit ▸ | Probe ▸ (menufixture, stale=0)`;
  - `  menu 4 v3 (answering 2) at 1.456s: 4.0 Set Label A ⌥⌘A | 4.1 Set Label B ⌃⇧B | — | 4.3 Checked ✓ | …`;
  - `  press 4.0 v3 (answering 3) at 2.001s: pressed=1`, and `note=…` when there is one.
- `--fetch=ID[xN]@T`: N kind 27s back to back (default 1), with the last top level's version.
- `--press=ID[,TITLE]@T`: a kind 25. The title defaults to the one the last answer listed for that
  id. It always carries the last top level's version, so a press with an older one takes `--raw25`.
- `--raw25=JSON@T`, `--raw27=JSON@T`: literal payloads, for the malformed cases.
- `--expect-menus=TITLE[,TITLE…]`: at exit, the last top level's titles, in order.
- **A guard.** `--fetch`, `--press`, `--raw25` and `--raw27` exit 2 unless `SILL_TEST_MENU_PID` is
  set in sillclient's own environment: "sillclient.py: --fetch and --press would open and choose
  the menus of whatever app this Mac has in front; run them against a host started with
  SILL_TEST_MENU_PID." `--menus` alone is allowed: a top level is read, and nothing is activated.
- Tokens are shared with `--set`'s: 1, 2, 3… in send order.
- `KIND` gains `24: "menu"`, and kind 24 counts in `kinds=` like any other.

**`Scripts/menufixture.swift` (new): the gates' app.**
- **Build:** `swiftc -O Scripts/menufixture.swift -o $T/menufixture -framework AppKit`.
- **`menufixture serve LOG SECONDS`:**
  - Activation policy `.prohibited`, a background-only app that cannot be activated. An accessory
    app started from a shell took the front at launch (measured 2026-09-27: `lsappinfo front` named
    it for a whole 20 s run). Accessibility reads its menus as any app's, as the probe's fixture
    (also `.prohibited`) showed, and its label still reads over AX.
  - It exits by itself after SECONDS (at most 120).
  - It logs every delegate and validation callback with a time, as the probe's fixture did.
  - It logs "ACTION ‹item›" for every action, and sets its label to that item's name.
  - SIGUSR1 gives Probe › Rebuilt a new NSMenu whose one item has the same title; SIGUSR2 one
    titled "Renamed Leaf". A new menu, not new items in the old one: AppKit's elements are
    positional, so only a new menu leaves the kept element invalid and makes the host find the item
    again by its path (Dynamic N shows the title check for an element that outlived its item).
- **Its window.** Borderless, 240×40, at (−20000, −20000): off every display.
  - `ignoresMouseEvents`, ordered in with `orderFrontRegardless()`, never key.
  - One `NSTextField` label, starting as "none".
  - If H0 finds macOS moved it onto a display: alpha 0 at the main display's corner instead.
- **`menufixture label PID`:** prints that process's label, its `AXValue`, read over Accessibility
  from this second process.
- **The tree.** The app menu's bar title is the process name (the probe's fixture, built as
  "fixture", read "fixture"). The ids are the ones a device sees.

| Menu (id) | Items (ids from 0) |
|---|---|
| menufixture (1) | About menufixture · — · Quit menufixture ⌘Q |
| File (2) | New ⌘N · Open… ⌘O · — · Open Recent ▸ (a delegate fills it at each read: Recent 1, Recent 2, —, Clear Menu) · — · Close ⌘W (validates disabled) |
| Edit (3) | Undo ⌘Z · Redo ⇧⌘Z · — · Cut ⌘X · Copy ⌘C · Paste ⌘V (nil-targeted: disabled in an app with no key window) |
| Probe (4) | 4.0 Set Label A ⌥⌘A · 4.1 Set Label B ⌃⇧B (no ⌘) · 4.2 — · 4.3 Checked ✓ · 4.4 Mixed (mixed) · 4.5 Unavailable (validates false) · Hidden (isHidden: not listed) · a custom-view item · an image-only item · — · F5 Item (F5) · Delete Item ⌘⌫ · Up Item ⌃⌘↑ · Escape Item ⎋ · Space Item ⌥⌘Space · Primary ⌘K · Alternate ⌥⌘K (isAlternate) · Dynamic N (retitled at each validation) · Slow Action (sleeps 2 s in its action) · Rebuilt ▸ (Rebuilt Leaf; see the signals) · Deep ▸ Level 2 ▸ Level 3 ▸ Deep Leaf · 300 Items ▸ · 600 Items ▸ |

Ids after 4.5 depend on where AppKit lists the hidden item: H4 records them. Each action sets the
label: Set Label A → "A", Deep Leaf → "Deep", Rebuilt Leaf → "Rebuilt".

### 6. Sill.app

Nothing changes on the Mac's screen:
- no setting (Q10);
- no menu item;
- previews identical.

The app's host is the same coordinator. It observes `NSWorkspace.didActivateApplicationNotification`
while a device subscribes and the Desktop streams. `--menu-selftest` works in the bundle. Show Log…
shows the "Menu from" lines. App Nap is unchanged: the latency activity already holds while a device
is connected.

---

### 7. iOS client

#### 7.1 Files

| File | Change |
|---|---|
| `MacMenuState.swift` (new; pure: Foundation and StreamProtocol; checked with swiftc) | One connection's menus: the top level, waiting fetches, presses, their timeouts (§7.2) |
| `MacMenuElements.swift` (new; UIKit) | The one builder of `UIMenuElement`s, for the bar and the button (§7.3) |
| `MacMenuHub.swift` (new; UIKit) | Which client is the key window's; rebuilds (§7.4) |
| `SillAppDelegate.swift` (new; UIKit) | `buildMenu(with:)` (§7.4) |
| `MacMenuButton.swift` (new; SwiftUI and UIKit) | The bar's Menus button and its UIKit trigger (§7.5) |
| `SillApp.swift` | `@UIApplicationDelegateAdaptor(SillAppDelegate.self) var appDelegate` |
| `StreamClient.swift` | The subscription, kind 24, `fetchMenu`, `pressMenuItem`, the timeout, tear-down (§7.6) |
| `StreamScreen.swift`, `PortraitStreamScreen.swift` | The button in `TopBar` and `windowBar` (§7.5) |
| `ContentView.swift` | The key-window observer (§7.4); the harness contract (§7.8) |
| `MockCatalog.swift` | The menu cases (§7.8) |

**The pbxproj.** The five new files need their four pbxproj entries each, by hand. They take a
block of their own, clear of the other open branches: A040–A044 for the build files and F040–F044
for the file references (`A1000001000000000000A040` … `F044`). Main ends at A01E/F01E, plus A101,
A201, F101 and F201; home-pairing uses F00D; pointer-visibility took A301/F301 and remote-pacing
A020/F020. A040–A044 and F040–F044 were free on main (cf05a78) and on every branch on 2026-09-27.

Swift 5 language mode, as now. The deployment target stays iOS 17.0:
- `UIDeferredMenuElement.uncached` and `UIAction.subtitle` are iOS 15;
- `.displayInline` is iOS 14;
- `performPrimaryAction()` is iOS 17.4, used only by the DEBUG harness;
- only the menu bar's insertion is behind `#available(iOS 26, *)`.

#### 7.2 `MacMenuState` (pure)

```swift
struct MacMenuState: Equatable {
    struct Row: Equatable {
        enum Kind: Equatable { case item, submenu, note }
        enum Mark: Equatable { case off, on, mixed }
        var kind: Kind; var id: String?; var title: String; var key: String?
        var enabled: Bool; var mark: Mark
    }
    typealias Section = [Row]
    enum Content: Equatable { case sections([Section], more: Int), message(String) }
    struct Done: Equatable { let key: Int; let content: Content }     // a UIKit completion's key, and what it gets

    private(set) var version: Int?
    private(set) var app: String?
    private(set) var menus: [Row] = []          // the top level, each a `.submenu`
    private(set) var stale = false
    private(set) var note: String?
    var hasMenus: Bool { !menus.isEmpty || note != nil }

    /// A kind 24: a top level, or an answer. Returns the completions it settles and whether the
    /// top level changed (the bar rebuilds, the button's menu is replaced).
    mutating func receive(_ m: MacMenu, now: Double) -> (done: [Done], topChanged: Bool, refusal: String?)
    /// A menu opened (an uncached element's provider). The kind 27 to send, or nil when a fetch of
    /// the same menu is already waiting (the completion joins it) or nothing may be sent (rule 1).
    mutating func fetch(_ id: String, key: Int, token: Int, now: Double) -> FetchMenu?
    /// Rule 11: the id a bar menu built from `builtVersion` asks for now, or nil (none any more).
    func barMenuID(builtID: String, builtVersion: Int, title: String) -> String?
    mutating func press(_ row: Row, token: Int) -> PressMenuItem?
    mutating func expire(now: Double, timeout: Double, mac: String) -> [Done]
    mutating func reset() -> [Done]
    static func sections(_ items: [MacMenuItem], stale: Bool, note: String?, more: Int) -> [Section]
}
```

The rules:
1. **Nothing before the first top level.** Nothing is fetched or pressed until one has arrived:
   until then, for all this device knows, the Mac is an older one.
2. **A top level replaces the one before.** A new version settles every waiting fetch of an older
   version with "The menus changed. Open the menu again.".
3. **One fetch per menu.** Opening a menu whose fetch is waiting joins it. UIKit may ask a provider
   more than once; one kind 27 goes out.
4. **An answer settles only the fetch with its token.** An unknown token is dropped: a late answer
   after its timeout.
5. **An answer whose version is not the fetch's** settles it with "The menus changed. Open the
   menu again.".
6. **Timeout.** `max(4 s, 4 × the worst recent round trip)`, as the settings ledger's
   (StreamClient.swift:2613): "‹Mac› didn’t answer. Open the menu again." ("The Mac" when the name
   is empty).
7. **Stale.**
   - A stale top level: no menu is fetched. In the bar each Mac menu holds only the note, as a
     disabled row. The Menus button still opens: the note first, then each Mac menu as a disabled
     row.
   - A stale answer: its rows, every one disabled, under the note.
8. **Presses.** Never for a disabled row, and never while stale. `pressed: false` → a refusal (the
   warning haptic and an announcement, §7.6). `pressed: true` → nothing: the Mac shows the result.
9. **`reset()`** on tear-down settles every waiting completion with "Not connected." and empties
   everything.
10. **`sections`:**
    - Separators split the items into sections; leading, trailing and doubled ones are dropped.
    - An item without a title is dropped.
    - `mark` "-" or "–" is mixed; any other mark is on.
    - `more > 0` adds a last disabled row "‹n› more on the Mac".
    - No items at all, and no note, gives one disabled row, "No items". A stale answer or a refusal
      carries its note and no items, and shows the note alone.
11. **A bar menu asks by what it showed.** UIKit rebuilds the bar lazily (at the next key event or
    focus change, measured), so a bar menu can have been built from an older top level than the
    current one.
    - Built from the current version: its own id.
    - Built from an older one: the id of the current top level's first menu with the same title
      (the old app's File finds the new app's File), fetched with the current version.
    - With no such menu: its completion gets "The menus changed. Open the menu again." at once,
      nothing is sent, and `MacMenuHub` asks for a rebuild again.
    - The Menus button needs none of this: its menu is replaced at every change (§7.5).

Each completion is exactly-once: a key leaves the state when it is settled.

#### 7.3 `MacMenuElements`: one builder for the bar and the button

```swift
@MainActor
enum MacMenuElements {
    /// The top level: one UIMenu per Mac menu, each holding one uncached deferred element.
    /// `barIdentifiers`: the menu bar's unique identifiers (rule 2 below); the pull-down uses none.
    static func topMenus(_ client: StreamClient, barIdentifiers: Bool) -> [UIMenu]
    /// A menu's contents once its fetch is settled.
    static func elements(_ content: MacMenuState.Content, client: StreamClient) -> [UIMenuElement]
}
```

The builder's rules. The probe measured what breaks the main menu: a silently dropped menu ("conflict
with existing elements"), or a thrown exception ("contain duplicates"). These rules keep both from
happening.
1. **No `UIKeyCommand` and no `UICommand`, ever.** No shortcut can then clash with one of the
   root's (the whole inserted menu would vanish) or repeat (it would throw). With none, no key a
   user presses with nothing first responder can reach a Mac menu either. The Mac's shortcut is the
   `UIAction`'s `subtitle`.
2. **Identifiers.**
   - Each menu inserted in the bar gets `UIMenu.Identifier("me.saffer.sill.macmenu.\(i)")`, where
     `i` is the Mac menu's id (its index in the Mac's bar, 1–32), unique within a build. In `.one`
     the wrapper is `me.saffer.sill.macmenu` and the Mac's menus inside keep theirs.
   - Every nested menu, every action, every deferred element's contents and the pull-down's menus
     get none: UIKit makes unique ones (the probe's 2,041 elements went in clean that way).
   - **Inserted at most once per build.** Before inserting, `MacMenuBar.insert` looks for its first
     identifier (`builder.menu(for:)`) and inserts nothing if it is there already. A second
     insertion in one build would be a duplicate (a crash) or a conflict with the root (the whole
     insertion dropped). The probe's adaptor was called once per build, but nothing promises it.
   - The Mac's menus are never told apart or merged by title. Two menus named "Window", the Mac's
     and the iPad's, stay two.
3. **Leaves.** A leaf is `UIAction(title:, subtitle: key, attributes: enabled ? [] : .disabled,
   state:)`. Its handler calls `client.pressMenuItem(row)`, which sends the version the row came
   from. Handlers and providers hold the client weakly: a window closed with its menu open leaves
   nothing behind.
4. **Disabled submenus.** A disabled submenu is a disabled `UIAction` without children. A disabled
   Mac submenu cannot open either.
5. **Every submenu holds exactly one `UIDeferredMenuElement.uncached`.** Its provider calls
   `client.fetchMenu(id) { content in completion(elements(content, client: client)) }`. It is
   fresh each time it opens, and UIKit's loading placeholder covers the round trip. A menu of the
   bar's top level asks with `barMenuID(builtID:builtVersion:title:)` first (§7.2 rule 11): the bar
   may be older than the current top level. Every completion is called once, on the main queue.
6. **Sections are `UIMenu(title: "", options: .displayInline, children:)`.** A titled inline group
   shows a header, as the probe's pull-down drew "Edit".
7. **A note, "No items", or "‹n› more on the Mac"** is one disabled `UIAction`.
8. **Nothing here needs iOS 26.**

#### 7.4 The iPadOS 26 menu bar (`SillAppDelegate`, `MacMenuHub`)

**`SillAppDelegate: UIResponder, UIApplicationDelegate`** implements nothing but
`buildMenu(with:)`. SwiftUI keeps its own handling of `sill://` links (`onOpenURL`, ContentView)
and of scenes (S5 checks it).

```swift
override func buildMenu(with builder: UIMenuBuilder) {
    super.buildMenu(with: builder)
    guard builder.system == .main, UIDevice.current.userInterfaceIdiom == .pad else { return }
    guard #available(iOS 26, *) else { return }   // before 26 the main menu only feeds the ⌘ list of key commands; ours has none
    guard let client = MacMenuHub.shared.focused, !client.menus.menus.isEmpty else { return }
    MacMenuBar.insert(MacMenuElements.topMenus(client, barIdentifiers: true), app: client.menus.app, into: builder)
    #if DEBUG
    if UserDefaults.standard.bool(forKey: "SillMenuDump") { MacMenuBar.dump(builder) }   // the probe's root dump (S3)
    #endif
}
```

**`MacMenuBar.insert`** follows `MacMenuBar.layout` (Q1; DEBUG `-SillMenuBarLayout`). Every call is
behind `#available(iOS 26, *)`, so it uses iOS 26's `insertElements`, which puts all the Mac's menus
in with one call, in order:
- **Once per build.** If `builder.menu(for:)` finds the first identifier already there, nothing is
  inserted (§7.3 rule 2).
- **Its anchor, looked up first.** UIMenuBuilder's headers do not say what an insertion next to a
  missing identifier does, so none is ever made: each anchor is checked with `builder.menu(for:)`,
  and the root's end is the last resort (`insertElements(_:atEndOfMenu: .root)`).
- **`.perMenu` (the default).** The Mac's menus in order right after the iPad's View,
  `insertElements(_:afterMenu: .view)`; without View, `insertElements(_:beforeMenu: .window)`;
  without either, at the root's end. Sill's own menus stay.
- **`.replace`.** Sill's File, Edit, Format and View are removed first, each only where
  `builder.menu(for:)` finds it (SwiftUI's root has no Format). Then the Mac's menus go in order
  before `.window` (else at the root's end).
  - Removing Edit also removes its key commands (⌘C, ⌘V, ⌘Z, ⌘A) while a session streams. Sill's
    own text fields may need them with a hardware keyboard: the pairing overlay's code field, over
    the stream. Q1 says so; S3 cannot check it.
- **`.one`.** One menu, titled with the app's name and identified `me.saffer.sill.macmenu`, holds
  the Mac's menus. It goes after View, with the same fallbacks.

**`MacMenuHub`** (main actor, one per process):
- **`weak var focused: StreamClient?`:** the client of the window that is key. The bar is the key
  window's (the app can have several, `UIApplicationSupportsMultipleScenes`).
- **Set by `KeyWindowObserver`,** a zero-size `UIViewRepresentable` in `ContentView` (one per
  scene, next to its `StreamClient`):
  - it watches `UIWindow.didBecomeKeyNotification` for its own window;
  - it also reports its window's `isKeyWindow` when it moves into it.
- **`menusChanged(_ client:)`** is called by a client whose top level, version, stale flag or note
  changed. A change of `focused` counts too. Either calls `UIMenuSystem.main.setNeedsRebuild()`
  when it concerns the focused client.
  - The rebuild is lazy (measured): it runs at the next key event or focus change, and perhaps
    when the bar is shown (P8). Until then the bar holds the menus it was built with, and §7.2 rule
    11 resolves each by its title when it opens.
  - A build of at most 32 menus, each with one deferred element, is far smaller than the probe's
    2,041 elements (10.5 ms).
- **Nothing is inserted** when:
  - the device is not an iPad;
  - it runs iOS before 26;
  - no window is key;
  - the key window's session has no menus;
  - the builder already holds them (a second call in one build).

#### 7.5 The Menus button

- **Where.** Right after the window strip, before Aa:
  - in `TopBar` (StreamScreen.swift:439-450): Apps · strip · **Menus** · Aa · Keyboard · Desktop ·
    Settings;
  - in `windowBar` (PortraitStreamScreen.swift:267-276): Apps · strip · **Menus** · Aa · Desktop ·
    Settings.
  - It sits next to the thumbnails because its menus are the picked window's app's.
- **When.** Only while `client.menus.hasMenus`. With nothing streaming the strip takes its room
  back, with the bar's own animation.
- **The Aa ruler.** While it is open, the button fades to 0 and takes no touches, as the buttons
  after Aa do. The ruler is centred on Aa and reaches over its neighbours.
- **The look** is the bar's own `BarButton`: symbol `filemenu.and.selection`, label "Menus",
  `open` (the accent) while its menu shows. Its size is `metrics.buttonWidth` and
  `metrics.buttonHeight`, and `metrics.buttonRadius` in portrait.
- **The mechanism: `MacMenuTrigger`,** a `UIViewRepresentable`:
  - A clear `UIButton` fills the BarButton's frame, with `showsMenuAsPrimaryAction = true` and
    `menu = UIMenu(children: MacMenuElements.topMenus(client, barIdentifiers: false))`.
  - `updateUIView` replaces the menu when the top level changed.
  - A `UIButton` subclass overrides `contextMenuInteraction(_:willDisplayMenuFor:animator:)` and
    `…willEndFor…` to report `open`.
  - The SwiftUI button under it is only drawn: `.allowsHitTesting(false)`, `.accessibilityHidden`.
  - The `UIButton` is the accessible element, labelled "‹App› menus" ("Code menus").
- **Why UIKit, not SwiftUI's `Menu`.** Both nest. But SwiftUI's `Menu` has no lazy element and no
  callback when a submenu opens. Every menu would then have to be fetched ahead: every Mac menu
  validated in the app, and a round trip for each, every time the tree changed. The UIKit pull-down
  runs the same deferred elements as the bar, and the probe measured them there: the provider at
  5 ms, the placeholder until the answer.
- **One thing open at a time.** Opening the menu closes the drawer, the Settings panel and a
  thumbnail's lights, as `setSettings` does for the panel (StreamScreen.swift:264-279).
- **The keyboard stays as it is.** A presented menu should take its own keys. If P finds that ↓
  reaches the Mac while a menu is open, the fix is the Settings panel's: down on display, back up
  on close (`InputOverlayProxy.setKeyboard`, InputOverlay.swift:403-417).

#### 7.6 `StreamClient`

- **State.**
  - `@Published private(set) var menus = MacMenuState()`;
  - `private var menuCompletions: [Int: (MacMenuState.Content) -> Void]`;
  - `menuToken` and `menuKey` counters;
  - `menusExpiry: DispatchWorkItem?`.
- **The subscription.** When a connection's first window list arrives (`sessionListed` becomes
  true, StreamClient.swift:2332), `send(.fetchMenu, payload: Wire.encode(FetchMenu(token:)))`.
  That is once per connection; a move's new connection does it again at its own first list.
- **`case .macMenu` in `handle` (StreamClient.swift:2302-2447),** the `.hostSettings` case its
  template (:2408-2415):
  - Decode, then hop to main behind `self.connection === from`.
  - `menus.receive(…)`, then call the settled completions.
  - A changed top level → `MacMenuHub.shared.menusChanged(self)`.
  - A refusal →
    - `UINotificationFeedbackGenerator().notificationOccurred(.warning)` (iPhones only: iPads have
      no Taptic Engine);
    - `UIAccessibility.post(notification: .announcement, argument: "Couldn’t choose ‹title›. ‹note›")`;
    - the console line.
  - Refusals show nothing on screen (Q9).
- **`fetchMenu(_ id: String, completion:)`** stores the completion under a new key and asks the
  state. A kind 27 goes out only when the state returns one. Then `scheduleMenusExpiry()`, like
  `scheduleSettingsExpiry` (:2616-2624).
- **`pressMenuItem(_ row:)`:** the state's kind 25, sent with `send(.pressMenuItem, payload:)`.
- **`tearDown` (:2066-2120):** `menus.reset()`'s completions are called, and
  `MacMenuHub.shared.menusChanged(self)`.
- **DEBUG, with no connection (the mock):**
  - A fetch is answered from `MockCatalog.macMenu(case)` after 0.2 s; `slow` after 1.5 s; `timeout`
    never.
  - A press gets `pressed: true`, or a refusal under `refuse`.

#### 7.7 Copy (exact)

| Where | Words |
|---|---|
| The bar button | "Menus" |
| Its VoiceOver label | "‹App› menus": "Code menus" |
| A menu loading | UIKit's own placeholder |
| No answer in time (device) | "Mac mini didn’t answer. Open the menu again." ("The Mac" when the name is empty) |
| The tree changed while open (device or host) | "The menus changed. Open the menu again." |
| Disconnected while open (device) | "Not connected." |
| An empty menu (device) | "No items" |
| More than 500 (device) | "‹n› more on the Mac" |
| No Accessibility on the Mac (host `note`) | "Allow Accessibility for Sill on the Mac (System Settings › Privacy & Security › Accessibility)." |
| The app not answering (host `note`) | "Blender isn’t responding." |
| A disabled item pressed (host `note`) | "It isn’t available right now." |
| The app gone (host `note`) | "Code is no longer open." |
| Too many requests (host `note`) | "Too many requests. Open the menu again." |
| A refused press (announcement) | "Couldn’t choose Save. The menus changed. Open the menu again." |

"Mac" stays singular and never possessive (the public copy rule, 0081711).

#### 7.8 Harness (DEBUG; the contract comment at ContentView.swift:55-171, and CLAUDE.md)

- **`-SillMacMenu <case>`** sets the mock's menus. The default is `code`, so the default bar is the
  bar as it will be.
  - **`code`:** Code, File, Edit, Selection, View, Go, Run, Terminal, Window, Help.
    - File has shortcuts, sections, a ✓, a disabled item and Open Recent ▸.
    - Code › Settings ▸ Themes ▸ Color Theme goes three deep.
    - View has a mixed mark.
  - **`blender`:** Blender and Window.
  - **`long`:** a Window menu of 300 windows, and 600 in another (the cap).
  - **`stale`, `noaccess`** (a note, no menus), **`none`** (no button).
  - **`slow`, `timeout`, `refuse`.**
- **`-SillMenusOpen 1`** opens the pull-down after launch (`performPrimaryAction()`, iOS 17.4).
- **`-SillMenuBarLayout perMenu|replace|one`:** Q1's flip for one run.
- **`-SillMenuDump 1`:** the root after each build, on the console (S3).
- **`-SillMenuBuildTwice 1`, `-SillMenuNoView 1`:** the insertion's guards under test (S3): the
  insertion made twice in one build; View removed before it.
- All but `-SillMenuDump` and the two guards' flags are ignored with `-SillLive 1`, whose session
  has the real menus.

#### 7.9 DEBUG console lines (device)

```
menus: Code, 10 menus (version 3)
menus: none (version 5)
menus: File (2) in 41 ms, 24 items
menus: File (2) waited 4.0 s: no answer
menus: chose Save (2.9)
menus: the Mac refused Save (2.9): The menus changed. Open the menu again.
menubar: built: 10 Mac menus after View (perMenu)
menubar: File was built from version 3; asked as 2 in version 5
menubar: Selection was built from version 3; version 5 has none
```

---

### 8. Timeouts and limits

| What | Value |
|---|---|
| AX messaging timeout (menu reads, presses) | 1.0 s, set on each element; never process-wide |
| Activation before a read or press (window sources) | As input: at most one attempt per 2 s; up to 0.6 s for the app to come up |
| The host's cache of a menu | 1 s. A read made while the app was frontmost answers any fetch; one made while it was not answers only while `prepare` still finds it not frontmost. An app brought forward after such a read is read again once 1.05 s have passed |
| One menu's read | 1.5 s (`readBudget`), then the rest counts in `more`; about 2.5 s at worst with a call's own timeout |
| The device's wait for an answer | max(4 s, 4 × the worst recent round trip) |
| Kind 27 | 20 a second per connection |
| Kind 25 | 4 a second per connection |
| Items per answer | 500 (`more` counts the rest, and what the budget left unread) |
| Top-level menus | 32 |
| Depth | 8 levels below the bar |
| Title | 100 characters (`SafeText.label`); the log's 64 |
| Shortcut text | 16 characters |
| Kept elements | This version's only; 5,000 |
| Stale, an unread top level, no Accessibility | Retried at each catalog poll (2 s), one read at a time |
| Requests | One at a time per host, in arrival order; a rate refusal at once |
| Payloads | Kind 24 up to about 100 KB (500 items). The caps stay: `maxOtherHostPayload` 4 MiB, `maxClientPayload` 1 MiB (a larger kind 25 or 27 closes its connection, as any message does) |

### 9. Edge cases

| Case | Behaviour |
|---|---|
| Blender, and apps that draw their own menus | Only what AX lists: Blender and Window. Blender's File, Edit and Render are in its window: tap them in the picture. A Window read takes about 0.3 s, under the placeholder |
| VS Code, and other Electron apps | Full menus, 3 deep. Every item's identifier is "itemSelected:", which the paths do not use. Its states need the activation (314 of 431 items read disabled while inactive). Chord shortcuts show in titles ("Keyboard Shortcuts [⌘K ⌘S]"). A menu rebuilt by the app leaves the kept element invalid: the path and title find it again |
| Mac Catalyst (Weather, Messages) | Readable; UIKit's ✓ comes through as the mark |
| wxWidgets (Bambu Studio) | Readable. "Hide BambuStudio"; Edit › Deselect all shows "⎋"; Recent projects fills at read time |
| Chrome's untitled bookmark items | Shown with their description, if they have one; otherwise left out |
| Custom-view items (Finder's Tags, Help's search field), image-only items | Left out |
| Option alternates (Close All ⌥⌘W, Quit and Keep Windows) | Their own rows (Q6) |
| Hidden items | Not listed (AX leaves them out) |
| Open Recent, Services and other menus a delegate fills | Filled at read time. Long ones stop at 500 (or at the 1.5 s budget), with "‹n› more on the Mac". A delegate that rewrites its NSMenuItems in place can make an item another command by the time it is pressed: the title check refuses it (§4.2) |
| A menu the app fills lazily and slowly (a History of hundreds of entries in a slow app) | The first items read within 1.5 s, then "‹n› more on the Mac" |
| An app that stops answering | The next read runs into the 1 s timeout: stale, with every item disabled under "‹App› isn’t responding.", and presses refused. Retried at each catalog poll |
| The app quits | The next read or press finds it gone: "‹App› is no longer open.", and a top level with no menus. A window source's window also leaves the list, and the stream stops as today |
| Another window of the same app picked | Same app: same version, ids and kept elements. The cache is cleared at the change: the key window changed |
| An item retitled between the menu opening and the choice ("Undo Typing" → "Undo Paste", "Dynamic 5" → "Dynamic 6") | Refused: "The menus changed. Open the menu again." The press's own read validates the menu, so this happens only when the app's state changed meanwhile |
| A kind 25 for one of the bar's menus ("2") or an item with a submenu | Refused, nothing pressed: `AXPress` there would open that menu on the Mac, in menu tracking. The device never sends one |
| A press that opens a new window (File › New, Window › a window's name) | The new window appears where the app puts it. The device keeps its source until someone picks the new window, which the strip lists at the next catalog poll. The Desktop shows it at once |
| The Desktop: the frontmost app changes (a click in the picture, the Mac's own user) | Within about 0.3 s after a device's click; at once in Sill.app (NSWorkspace); by the next catalog poll (2 s) in the plain CLI, where the owner of the topmost window stands for the frontmost app. The version moves, and the device rebuilds. A menu open on the device at that moment settles with "The menus changed…" |
| Sill itself frontmost on the Desktop (its Settings window) | No menus |
| A press whose action takes long (a runModal alert, a blocking action) | An AppKit app answers `AXPress` before running the action (the fixture: 2–3 ms). An action that holds the app's main thread makes the reads meanwhile run into the 1 s timeout: stale until a poll finds it answering (a modal loop may keep answering; not measured). An app that answers only after its action holds `sill.menus` up to 1 s: logged with "did not answer within 1 s", answered `pressed: true`. Nothing else waits |
| A dialog or panel in regular mode (Save…, Page Setup) | It is a window of its own. Window capture does not show it, so the device sees nothing happen, as with ⌘S from the keyboard today. The Desktop and the virtual display show it (P6) |
| A press during a source switch | No activation (the old source is still named). The version check decides: another app → refused; the same app → pressed |
| Two devices | One tree for both. Each fetches for itself; answers go to the asker; presses from either act on the one app |
| A remote session (TLS, a slow link) | The same. The device's wait grows with the round trip |
| Accessibility off on the Mac | The note, no menus. Input is dropped too, as today |
| A background-only app on the Desktop (no menu bar) | No menus |
| Titles with control or bidirectional characters | Cleaned (`SafeText.label`) |
| A pointer sweeping across the iPad's bar | Each menu that opens asks once; the host serves them in turn, and a second fetch of a menu just read is answered from that read; at most 20 a second |
| The iPad's bar not rebuilt yet after the Mac's app changed (the rebuild waits for a key or focus event) | Each bar menu asks by its title: one the new app also has opens with the new app's items, and any other says "The menus changed. Open the menu again." (§7.3 rule 5; P8) |
| What a device can do with the menus | What it can already do with a click: choose what the streamed app offers. Never the Apple menu (Restart, Shut Down, Log Out, Force Quit), and never Sill's own app. Titles (Open Recent's file names, History) travel on the session's connection, as window titles already do |
| Several Sill windows on an iPad | The bar shows the key window's session's menus. The Menus button in each window shows its own |
| iPhone, the Duo's outer display, iPadOS 17–25 | The Menus button only |
| Keys while a menu is open | Unchanged; P checks that none reach the Mac |
| ⌘W on the iPad with nothing first responder (the keyboard down, the Settings panel open) | Unchanged by this step: the iPad's File › Close closes Sill's window, as the probe measured for its scratch app (Q8) |
| An older device, newer host (and the reverse) | §3.5 |

### 10. Test gates

**Hard rules for the implementing session** (the workflow's of 2026-09-26 included):
- **Never touch** `/Applications/Sill.app`, the `me.saffer.sill.mac` domain or Noah's iPad and
  iPhone: nothing connects to Sill.app, and nothing is installed on a device. No
  `make-app.sh --install` or `--open`; building is fine. No `tccutil`, no system settings.
- **Presses** happen only through the host's own code (a synthetic host's kind 25). They go only to
  the fixture, a process the gate starts and kills.
- **No device on Sill.app while a gate presses or streams:** `Scripts/encoder-check/no-device.sh`
  exits 0 (it reads Sill.log only). Otherwise wait, and say so in the results.
- **Real apps' menus are read only with `--menu-selftest=TextEdit`** (or `=menufixture`), never a
  bare `--menu-selftest`, which reads whatever app is frontmost. The self-test is read-only and
  never activates. No gate starts, quits, activates or raises an app of Noah's, and no gate posts
  an input event. `sillclient.py --menus` goes only to a synthetic host: against any other it
  would read the frontmost app's menu bar.
- **The encoder rule for every host that streams** (the synthetic Desktop encodes on the hardware):
  `no-device.sh` first, one host at a time, under 90 s.
- **Synthetic hosts only,** from `.build/release`, started from Python with
  `start_new_session=True`, killed by PID, none left running. `SILL_TEST_MENU_PID` is the fixture's
  pid. Test listeners on loopback only.
- **The fixture never activates:** the prohibited policy (it cannot be activated), its window off
  every display, ignoring the mouse. The synthetic Desktop's path never activates it either. The
  gates sample `lsappinfo front` throughout: it must never change.
- **The simulator:**
  - a device of its own named "Sill menubar", in a device set under the scratchpad, deleted when
    the step ends;
  - screenshots with `xcrun simctl io <udid> screenshot` only;
  - taps with the control tool's headless `tap` (never its `attach`: the Simulator panel encodes on
    the Mac's one engine);
  - no XCUITest, no `simctl io recordVideo`.
- **Builds:** at least 25 GB free first (`df -g /System/Volumes/Data`); DerivedData under the step's
  scratchpad folder, deleted when the step ends.
- **`$T`** is a fresh temporary directory per gate.

**Headless (H).** Accessibility comes from the session's responsible process, as the probe's did.
No Screen Recording is needed.

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record the base (this plan's commit); `git archive` it to `$SP/base` and build it; H2's baselines. Kinds 24, 25 and 27 still free on every branch. Build the fixture: `menufixture serve` for 20 s; `menufixture label PID` prints "none"; `CGWindowListCopyWindowInfo` shows its window off every display (or the alpha-0 fallback) | Files exist; the fixture's label reads over AX; its window is invisible |
| H1 | **Builds.** `swift build -c release`; iOS Debug and Release for the simulator | Only the known warnings (CaptureProbe; the old `StreamClient` capture warning) |
| H2 | **The CLI byte for byte.** Base and new `SillHost --synthetic`: idle 35 s, and with `sillclient.py PORT 5 desktop`; both again with `--direct-wireless`; digits masked, sorted | Identical; `kinds=` and `first kinds:` identical (no 24) |
| H3 | **Pure checks, each with mutants caught.** `menus`: `MenuFormat.shortcut` (at least 45: every row of §4.1's tables, the probe's examples, fn, NoCommand, unknown private-use, a glyph outside the table, the 16-character limit); `item` (separators, missing and empty titles, the description fallback, custom views, submenus, marks, enabled); `MenuPath` (parse, format, 0 first, 9 levels, 5 digits, junk); `MenuCache` (0.99 s and 1.0 s; a read made while not frontmost answering while the app still is not, and waited out to 1.05 s once it is); `RequestRate` (20 and 21, 4 and 5, the one line a second); `PressDecision` (every row: the title compared for a kept element and for one found again, an empty or missing title, children, disabled); `TopLevel` equality; `MacMenu` JSON (round trips, `{}` decodes, unknown keys ignored). `menu-state`: `MacMenuState` (at least 45: rules 1–11, a joined fetch, a late answer, a version change mid-fetch, stale, refusals, reset's completions exactly once, `sections`' collapses, a bar menu resolved by its title after the top level changed) | All pass. At least 10 mutants of `menus` (for example the ⌘ shown with NoCommand, ⌥ before ⌃, the character over the glyph, F-keys off by one, the Apple menu allowed, `<=` for the cache's `<`, the kept element's title not compared, an empty title matching, an item with children pressed, the inactive entry served to a frontmost app, the wait ending at 1.0 s) and 8 of `menu-state` (stale not disabling, separators kept doubled, the version ignored, `>` for `>=` in the timeout, a joined fetch sending twice, reset missing a completion, "-" as on, a press for a disabled row) |
| H4 | **The fixture's tree through the host.** A synthetic host with `SILL_TEST_MENU_PID`. Run 1: `sillclient.py PORT 20 desktop --menus --fetch=2@2 --fetch=4@3 --fetch=4@3.4 --fetch=4@4.6`; it prints Probe's ids. Run 2, with run 1's ids (Deep is 4.19 if AppKit leaves the hidden item out, as the probe saw): `--fetch=` Deep, Level 2 and Level 3 in turn, a second apart. Also, in a scratch copy with `readBudget` 0.005 s: `--fetch=` 600 Items | The "Test menus" line. Top level `menufixture, File, Edit, Probe`, ids 1–4. Probe's items as §5's table: "✓", "-" mixed, `enabled:false`, keys "⌥⌘A", "⌃⇧B", "F5", "⌘⌫", "⌃⌘↑", "⎋", "⌥⌘Space", "⌘K", "⌥⌘K". The hidden item absent; the custom-view and image-only items absent; Deep reached level by level. Whether Edit's Cut, Copy and Paste read disabled (no key window) is recorded, not judged. The fetch at 3.4 answered from the cache (`menu.cached`, no fixture callback logged after the one at 3); the one at 4.6 read again (callbacks logged); Dynamic N's number grew. The budgeted read: fewer than 500 items and `more` counting the rest. **Recorded:** whether the top-level read made the fixture log any callback (decides Q12) |
| H5 | **Presses.** `--press=4.0@3`, Deep Leaf's (its id from H4, its levels fetched first), and Unavailable's (4.5); Set Label B's id with another title (`--press=4.1,Set Label A@…`); a bar item (`--press=4,Probe@…`) and a submenu item (`--press=4.19,Deep@…`, Deep's id from run 1); a press with an old version, after `--pick=none@5 --pick=desktop@6`: `--raw25='{"version":2,"id":"4.0","title":"Set Label A","token":90}@7'`, 2 being the fixture's first top level's version on a fresh host (§3.3; check it in the run's own output; `--press` always sends the newest) | `pressed=1` twice. `menufixture label PID` prints "A", then "Deep". The fixture logged "ACTION Set Label A" and "ACTION Deep Leaf". The host printed "Menu from sillclient: menufixture › Probe › Set Label A". Refused, with no ACTION: the disabled one ("disabled", `pressed=0`), the other title ("the menus changed"), the old version ("the menus changed", the line giving the id), the bar item and the submenu item ("the menus changed", each answered within 100 ms, and no line naming Deep in the fixture's log after them: nothing opened). Nothing activated: the frontmost app before and after is the same (`lsappinfo front`) |
| H6 | **A rebuilt menu, a retitled item.** Fetch Probe › Rebuilt, SIGUSR1 (same title), press its leaf; again with SIGUSR2 (renamed). Fetch Probe at T and press Dynamic N 0.3 s later; fetch Probe at T+2 and press Dynamic N at T+3.5 | Rebuilt: first pressed, found again by its path, the label "Rebuilt"; second refused, the label unchanged. Dynamic N: first pressed (AppKit's second had not passed, so the title held); second refused, "the menus changed" (the press's own read validated the menu and retitled it) |
| H7 | **Rates.** `--fetch=4x50@2`; ten presses of 4.0 within 0.5 s | At most 20 fetches answered with items that second, the rest "Too many requests…", one "ignored" line. Presses: 4 pressed, 6 refused |
| H8 | **The target moves.** `--pick=none@3 --pick=desktop@4`; kill the fixture at 6; `--fetch=4@7` | Kind 24s: `menus:[]` with version+1 at 3; the fixture's top level with version+2 at 4; after the kill a top level `menus:[]` with version+3, and the fetch refused with "menufixture is no longer open.", or with "The menus changed…" when a catalog poll saw the process gone first (both are right) |
| H9 | **Compatibility and junk.** The base's `sillclient.py` against an H4 host; the base's StreamMessage.swift reading headers of kinds 24, 25 and 27 (swiftc); the base host with the new `sillclient.py --menus --fetch`; `--raw27` with `{"id":"0"}`, nine levels, `"-1"`, `"a"`, `"04"`, not JSON; `--raw25` without a version, and with 4.0's id and a title of 1,000,000 bytes (under the 1 MiB cap); a message over the cap | The old client fails nothing and gets no 24. `.unknown` three times. The base host sends no 24 and prints nothing new. Junk is answered with a note or ignored, and the host streams on; the long title is refused ("the menus changed") and never printed; the message over the cap closes that connection with StreamServer's "announced a … message" line |
| H10 | **The main actor stays free.** Press Slow Action (2 s); fetch Probe 0.3 s later; `--set=bitrate=25000000@…` 0.6 s and `--set=bitrate=15000000@…` 1.0 s after the press | The press answered `pressed=1` (at once where `AXPress` answers before the action runs, as on the fixture; else after about 1 s, with "did not answer within 1 s"). The fetch, made while the action holds the fixture's main thread, answered stale with "menufixture isn’t responding.", the host's not-answering line, a stale top level, then "answering again" and a fresh top level at a later poll. Both kind 16 answers within 100 ms while `sill.menus` waits; `[1s]` lines every second |
| H11 | **Cost.** `--menu-selftest=menufixture` times. A subscribed client idle 35 s | Its times within the probe's ranges; no `menu.*` keys while nothing is asked; idle CPU 0.0 % |
| H12 | **A real app, read-only.** `SillHost --menu-selftest=TextEdit`, only if TextEdit is already running (none is started; otherwise recorded as not run). No other app of Noah's: the workflow's rule of 2026-09-26 | It reads; the top-level titles equal the probe's `menubar/dumps/textedit.txt`; the times within twice the probe's |
| H13 | **Hard rules** (grep), and previews | No `UIKeyCommand(` or `UICommand(` in the new iOS files. No `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide`. No AX call in MenuMirror (the reader's only). No `assumeIsolated` in the new files (HostShutdown's and the app's are older). `SILL_TEST_MENU_PID` honoured only where `synthetic` (it is read on every host, for §4.8's "ignored" line). `kAXPressAction` only in MenuReader, after `PressDecision`, and WindowSizer's close button. Every `insertSibling`, `insertElements` and `remove(menu:)` in `MacMenuBar` after a `menu(for:)` check. The bare app's `-SillRenderPreviews` identical before and after |

**Simulator (S):**

| # | Check |
|---|---|
| S1 | **The button.** `-SillMacMenu code` at 1000x710, 710x1000, 500x710 and 710x500: Menus between the strip and Aa, the bar otherwise as before. `none` at the four: no button, the bars as the base's photos. `code` with `-SillScaleOpen 1` at 1000x710 and 500x710: Menus faded. Ten photos; send Noah the sheet |
| S2 | **The pull-down.** `-SillMenusOpen 1` at the four sizes: Code, File, Edit, Selection, View, Go, Run, Terminal, Window, Help. A headless tap on File, at 1000x710 and 500x710: subtitles, sections, ✓, a disabled row. `slow`: the placeholder at 0.5 s, then the items. `timeout`: "Mac mini didn’t answer. Open the menu again." after 4 s. `stale`: the note, then every row disabled. `noaccess`: the note. `long`: 300 rows scroll, and "100 more on the Mac" in the 600 one. xxLarge text at 1000x710 and 500x710. A tap on Save: the console's "menus: chose Save". `refuse`: the console's refusal and its announcement |
| S3 | **The main menu's root,** on an iPad simulator with an iOS 26 or later runtime, `-SillMenuDump 1`. `code`: the 10 menus right after View, identifiers `me.saffer.sill.macmenu.1`…`10`, each holding one deferred element, and no key command or command inside any. `-SillMenuBarLayout replace`: File, Edit and View gone, the 10 before Window. `one`: one "Code" menu holding the 10. `none`: nothing inserted. An iPhone simulator: nothing inserted. An iOS 17 or 18 runtime, if one is installed: nothing inserted. The guards: DEBUG `-SillMenuBuildTwice 1` calls `MacMenuBar.insert` twice in one build (the dump shows the 10 once, no exception), and `-SillMenuNoView 1` removes View first (the 10 before Window). **The iPadOS 26 menu bar itself cannot be shown headless.** It appears only for a pointer at the top edge or a finger swiping down from it, which the harness cannot drive without the live panel. So everything up to it is checked here, and its drawing (subtitles, marks, deferred loading, its width) is P8's |
| S4 | **Live.** A synthetic host with the fixture; `-SillLayout 1000x710 -SillLive 1 -SillConnect 127.0.0.1:P`. The Menus button shows the fixture's menus. Tap Probe: its items load. Tap Set Label A: `menufixture label PID` prints "A", and the host logs the press. `-SillMenuDump 1` shows the fixture's four menus after View |
| S5 | **Tear-down and SwiftUI's own handling.** Disconnect from the Settings panel: the button goes; the next dump has nothing inserted. `xcrun simctl openurl <udid> 'sill://pair?…'` still reaches the link's confirmation, so the adaptor took nothing from SwiftUI |

**Noah's Mac and devices (P), handed over at the end:** the iPad (iPadOS 26 or later for P8) and an
iPhone for P13.

| # | Check |
|---|---|
| P1 | **VS Code, regular mode.** Menus lists Code, File, Edit, Selection, View, Go, Run, Terminal, Window, Help. Edit › Copy is enabled with a selection (it read disabled while Code was inactive). Code › Settings ▸ Themes ▸ Color Theme opens. File › New Text File makes one. Run › Start Debugging shows "F5" |
| P2 | **Weather (Catalyst).** Its menus open; a View item with ✓ toggles, and shows its new mark next time. It may ask for Location on its first launch: answer that on the Mac first |
| P3 | **Bambu Studio.** File › Recent projects is filled. Edit › Deselect all shows "⎋". View › Use Perspective View toggles its ✓ |
| P4 | **Blender's limits.** Only Blender and Window. Its File and Edit are tapped in the picture. The Window menu shows the placeholder briefly |
| P5 | **The Desktop.** With only the desktop clicked, the menus are Finder's. Click a Safari window in the picture: Safari's within about a second (at once in Sill.app). Open Sill's Settings on the Mac: no menus |
| P6 | **The virtual display.** A staged window's app not frontmost on the Mac: opening Menus brings it forward, as a click does. File › Save As… opens its sheet, and the device shows it. In regular mode the same sheet does not show on the device (window capture); note it |
| P7 | **⌘-shortcuts still pass through the keyboard.** A Magic Keyboard with the keyboard up: ⌘S reaches the Mac (the app saves) while the menu shows "⌘S" as text. With the Settings panel open (nothing first responder): ⌘S does nothing on the Mac and no mirrored item fires. Keys while the Menus pull-down is open reach neither the Mac nor a mirrored item |
| P8 | **The iPadOS 26 menu bar.** Reveal it with the pointer at the top or a swipe down: the Mac's menus after View; each opens with a brief placeholder, then its items; ✓ and disabled items as on the Mac; sections; shortcuts as subtitles (or not drawn: note which). Note whether ten or more menus fit. **The lazy rebuild:** with the keyboard down and no key pressed, pick another app's window with a tap on its thumbnail, then reveal the bar with a swipe. Note whether it shows the new app's menus (showing the bar rebuilt it) or the old titles. With the old titles, a menu the new app also has (File) must open with the new app's items, and one it lacks must say "The menus changed. Open the menu again."; after one key press the bar must be the new app's. The console's "menubar: built" lines say when each rebuild ran. Q1: try `-SillMenuBarLayout replace` and `one` from Xcode's scheme, and pick one |
| P9 | **An app that stops answering** (a paused or beach-balled one). Its menus show "‹App› isn’t responding." within about 2 s, every item disabled; they come back once it answers |
| P10 | **Mixed builds.** This iPad against main's Sill.app: no Menus button, no bar menus, the rest as before. An iPad on main's build against this Sill.app: as before |
| P11 | **VoiceOver.** The button reads "Code menus"; items read with their states and shortcuts; a refused press is announced |
| P12 | **Five minutes streaming,** the menus used now and then. Frame age and rtt in the `client …` lines unchanged. Sill.app's CPU as before. `menu.*` keys only in seconds a menu was opened |
| P13 | **An iPhone.** The Menus pull-down: submenus open in place; a choice works |

### 11. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit). Branch `menu-bar-mirror` from main at this plan's commit, then H0.
1. **"Protocol: kinds 24, 25 and 27, the Mac's menus."**
   - StreamMessage.swift: the three cases and their notes.
   - MacMenu.swift: the four types.
   - Compatibility.swift's comment.

   Gates: H1, H3 (the JSON), H9 (the decoder).
2. **"Host: the streamed app's menus, read and pressed through Accessibility."**
   - `MenuFormat` and `MenuPolicy`, with `Tests/checks/menus` and its mutants.
   - `MenuReader` and `MenuMirror`.
   - The coordinator's hooks and `focusForMenus`.
   - `--menu-selftest` in the CLI and the app.
   - The hook.
   - `Scripts/menufixture.swift`.
   - `sillclient.py`'s flags.

   Gates: H1, H2, H3 (`menus`), H4–H13.
3. **"iOS: the Mac's menus in the iPad's menu bar and behind a Menus button."**
   - `MacMenuState`, with `Tests/checks/menu-state` and its mutants.
   - `MacMenuElements`, `MacMenuHub`, `SillAppDelegate` and `MacMenuButton`, with their pbxproj
     entries A040–A044/F040–F044.
   - The adaptor in SillApp.
   - StreamClient.
   - The two bars.
   - The key-window observer.
   - The harness.

   Gates: H1 (iOS), H3 (`menu-state`), S1–S5.
4. **"docs: the Mac's menus on the device."**
   - This plan's Results.
   - CLAUDE.md:
     - the Current step;
     - Layout (the new files);
     - Build and run: `--menu-selftest`, the hook, the fixture, `sillclient.py`'s flags,
       `-SillMacMenu`, `-SillMenusOpen`, `-SillMenuBarLayout`, `-SillMenuDump`,
       `-SillMenuBuildTwice`, `-SillMenuNoView`;
     - Untested, for Noah: P1–P13.
   - docs/DEVELOPMENT.md's test tools.
   - `Tests/checks/README.md`'s table.
   - `.github/workflows/ci.yml`'s mutants matrix.
5. **Review and hand-over.**
   - Three lenses:
     - the host's threads, timeouts and activation;
     - the wire: versions, staleness, races and the refusals;
     - the device: four layouts, the pull-down and the main menu's builder.
   - A "Review fixes" commit if needed, then H4–H10 and S2–S4 again on the final build.
   - Hand P1–P13 to Noah. **Stop there.**

**Rebases.** Kind 26 and the pbxproj block were chosen so nothing collides. Whichever lands first,
the other takes a small rebase:
- the pointer (StreamMessage.swift, StreamClient, the bars): kind 26, `macPointer`;
- home-pairing (StreamClient, the pbxproj);
- the gestures (kind 28, `gesture`, and `WindowList.gestures`; its plan only so far) and pacing
  branches.
- `Tests/checks/protocol` expects 26 and 28 to read as `.unknown`, and `menus` 26: the branch
  that brings either flips those cases (the gestures plan says the same of its own checks).

encoder-two-in-flight (PR #20) is already in main at 150f781.

### 12. Hard rules (for every step)

- **No mirrored shortcut is ever a key command.** No `UIKeyCommand` or `UICommand` in the Mac's
  menus. The Mac's shortcuts reach it only as keys through InputOverlay.
- **The bar's insertion can neither drop nor throw:** identifiers only on the inserted top level,
  unique per build; inserted at most once per build; every anchor looked up first (§7.3, §7.4).
- **Only a leaf the device was shown is pressed:** two parts or more, no children, its title now
  the one shown, enabled (§4.2). Nothing else reaches `AXPress`.
- **Accessibility for menus runs on `sill.menus`,** with a 1 s timeout set per element and 1.5 s a
  menu. Never process-wide, and never a read on the main actor. The activation (the app made
  active, the streamed window made key) stays the coordinator's own code.
- **Activation is a click's:** AX only, never Launch Services, never `NSRunningApplication.activate`.
  None for the Desktop, and never on a synthetic host.
- **Never mirror Sill itself,** and never the Apple menu (Q4).
- **Never `MainActor.assumeIsolated`** in core code.
- **The CLI's stdout stays byte for byte on the default path,** idle and streaming, with and
  without `--direct-wireless`. New output only when a device uses the menus, under the hook, or
  from `--menu-selftest`.
- **Kinds 0–23 and their payloads are untouched.** 26 stays the pointer's.
- **Tests press only the fixture,** only through the host, only while no device is connected to
  Sill.app. They never touch `/Applications/Sill.app`, `me.saffer.sill.mac` or Noah's iPad.
- **TEST ONLY hooks** are honoured only by synthetic hosts, which do not advertise.
- **New iOS files** need their four pbxproj entries by hand. Swift 5 language mode. Only the bar's
  insertion needs `#available(iOS 26, *)`.
- **Apple frameworks only.**

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **Where the Mac's menus sit in the iPad's bar.** Default: **one menu per Mac menu, after the
   iPad's View**, in the Mac's order, Sill's own menus kept. The Mac's app menu (named after the
   app) marks where they begin. The bar then repeats File, Edit, View, Window and Help.
   Alternatives, each one constant away (`MacMenuBar.layout`; DEBUG `-SillMenuBarLayout`):
   - **`replace`:** Sill's File, Edit, Format and View go while the Mac's menus show. Fewer menus,
     no second File, Edit or View; Sill's ⌘W Close and its Edit commands go with them while
     streaming. Those commands carry ⌘C, ⌘V, ⌘Z and ⌘A, which Sill's own text fields may need with a
     hardware keyboard (the pairing overlay's code field, over the stream).
   - **`one`:** one menu named after the app holds the Mac's menus. No repeats, one level deeper.
     Its title changes with the app, so it too waits for UIKit's lazy rebuild (§7.2 rule 11).
     Titled with a fixed word instead, it would need no rebuild at all, since its one deferred
     element would list the current top level each time it opens. That is the fallback if P8 finds
     that showing the bar does not rebuild it.
2. **The Menus button.** Default: **in every bar, in every layout, whenever the Mac sent menus.**
   The iPad's bar stays hidden until revealed, and the HIG asks that every function also be
   reachable in the app's own interface. The bar also cannot be tried headless (S3), so the button
   is the one path the gates can check. Alternative (the commissioning task's): only on iPhone,
   the outer layouts, and iPadOS before 26 (`MacMenuButton.onlyWithoutMenuBar`).
3. **The Mac's shortcuts.** Default: **shown as the item's subtitle** ("⇧⌘S"), display only.
   Alternatives: none; appended to the title.
4. **The Apple menu.** Default: **left out.** It is the system's (About This Mac, System Settings…,
   Force Quit, Sleep, Restart, Shut Down, Lock Screen, Log Out), and the iPad's bar has none. It
   also names the Mac's user ("Log Out ‹full name›…", the probe's dump) and lists Recent Items.
   Alternative: mirrored like the rest.
5. **Activating the app when a menu opens on the device** (window sources). Default: **yes, as a
   click does.** The states are then the ones the Mac would show; an inactive app's Copy, Close and
   Minimize read disabled (measured). The Mac's focus moves to the app, as a click from the device
   already moves it. Alternative: activate only when an item is chosen; the menus then show an
   inactive app's states.
6. **Option alternates** (Close All ⌥⌘W, Quit and Keep Windows). Default: **their own rows.** AX
   does not mark them, and the device has no Option key to hold. Alternative: hide an item whose
   shortcut differs from the row above's only by ⌥. That is a heuristic: it would also catch pairs
   that are not alternates.
7. **The Desktop.** Default: **the frontmost app's menus.** Alternative: none on the Desktop, where
   the Mac's own menu bar is in the picture.
8. **⌘W on the iPad with nothing first responder** closes Sill's window (the probe's measurement of
   the system's File › Close). Default: **unchanged in this step.** Alternative: remove the iPad's
   File › Close while a session streams (Q1's `replace` does).
9. **A refused choice.** Default: **the warning haptic (iPhone) and a VoiceOver announcement,
   nothing on screen.** Refusals are rare: the menus changed, or the app stopped answering.
   Alternative: a short banner under the bar.
10. **A setting.** Default: **none.** Alternative: "Show app menus on devices" in
    Settings › Streaming and the menu.
11. **The kind numbers.** Default: **24, 25 and 27,** with 26 the pointer's.
12. **When the top level is read.** Default: **at a pick, when the app changes, and alongside each
    fetch; never on a timer.** H4 records whether a top-level read makes the app run its menu
    delegates. If it does not, the alternative adds a read at each catalog poll (2 s), so a top
    level that changes by itself (Xcode's editors) shows before the next fetch.
