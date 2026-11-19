**The Mac's menus on the device (2026-09-26/27, branch `menu-bar-mirror` from
main at 150f781, main merged in at cf05a78, 676b362, ed7f8c6 (PRs #30–#32) and
2b38179 (#33), never rebased, PR #36; the plan, its critique, the review and
every result are in `docs/menu-bar-plan.md`, "Results").** Noah: "For apps used
in Window mode, how can we access the menu bar options? Is there a way we can
add that menu and submenu?" (2026-09-25), item 10 of "Work on 5-12 as well
please" (2026-09-26). The streamed app's menu bar (the Desktop's: the frontmost
app's, as the Mac's own bar shows) reaches the device: on an iPad with
iPadOS 26 in the iPad's own menu bar, and behind a Menus button in the bar.
Each menu is read from the Mac when it opens, and an item chosen there is
pressed on the Mac through Accessibility. The Mac's shortcuts show as text,
never as key commands (⌘S typed still reaches the Mac as a key). Never the
Apple menu, never Sill's own. Built, reviewed (eleven findings, all fixed) and
checked; PR #36 merged (59c4ec8), and Noah's device tests below are still open.
- Wire (additive; `MacMenu.swift`; the compatibility floor below): kind 24
  `macMenu` (host → device: a top level, or the answer to one request), 25
  `pressMenuItem`, 27 `fetchMenu` (one menu's items; without an id, the
  subscription to the top level), around the pointer's 26. An id is a path
  ("2.9": Accessibility's child indexes below the bar, separators counted) that
  names one item for every device within one tree version; the version is the
  host's, +1 when the app, its top level or a submenu at its place changes, and
  when the last subscriber leaves. A fetch and a choice carry the title the
  device showed, and the host acts only while the item there still has it. A
  device's tokens come back in `answering`. Only a connection that sent the
  subscription is served (older devices and test clients cost the Mac
  nothing); an older host skips 25 and 27, and no button shows.
- Host (`MenuFormat`, `MenuPolicy`, `MenuReader`, `MenuMirror`,
  `MenuSelfTest`; Layout): Accessibility on its own queue (`sill.menus`), a 1 s
  timeout on each element, 1.5 s and 500 items a menu; one request at a time,
  and one that could no longer be answered in time for its device (its wait,
  from the connection's round trip) is not read, a choice that late refused; a
  menu read less than a second ago answered from that read (AppKit validates a
  menu at most once a second); the top level read at a pick, when the app
  changes, and with a fetch at most once a second while nothing waits behind
  it, never on a timer. A window source's app is made active and its window key
  first, as a device's click does (the states are then the Mac's own); never
  for the Desktop or on a synthetic host. Only a leaf the device was shown is
  pressed: two parts or more, no children, its title now the one shown,
  enabled. 20 fetches and 4 presses a second per connection. The Desktop
  follows the frontmost app after a device's click, under the AppKit loop at
  once (NSWorkspace), else at the catalog's poll. One line per press, "Menu
  from ‹device›: menufixture › Probe › Set Label A", and a line for a refusal,
  an app that stops or starts answering again, or a device over its rate;
  nothing else prints, and `menu.*` stats keys only while menus are used.
- Device (`MacMenuState`, `MacMenuElements`, `MacMenuHub`, `SillAppDelegate`,
  `MacMenuButton`; Layout): the subscription at a connection's first window
  list and on a move's new connection; each menu an uncached deferred element
  (UIKit's placeholder while the Mac answers), its completion settled exactly
  once (the answer, a new tree, the timeout max(4 s, 4 × the worst recent round
  trip), a move, the end); leaves are `UIAction`s with the shortcut as the
  subtitle, and no `UIKeyCommand` or `UICommand` anywhere (a clash drops the
  whole inserted menu, a duplicate throws: the plan's probe). The iPad's bar
  (iPadOS 26): the menus of the app's one window's session right after the
  iPad's View, inserted once per build next to an anchor looked up first; with
  two or more windows none (every window is key in its own scene, so nothing
  says whose session the bar would act on). The button: between the window
  strip and Aa in the landscape bar and an iPad's portrait window bar, where
  the bar holds it and still a whole thumbnail (not in a 320 pt Slide Over),
  and on a phone held upright at the end of the thumbnails' row, under
  Settings; a UIKit pull-down over the bar's look, the Mac's order top to
  bottom whichever way it opens, faded under the Aa ruler; opened over the
  Settings panel, it puts back the keyboard the panel took down when it goes.
  A refused choice: the warning haptic (iPhone) and a VoiceOver announcement,
  nothing on screen.
- Sill.app: nothing on its screen changes (no setting, no menu item); its
  coordinator is the CLI's; `--menu-selftest` works in the bundle, and the
  "Menu from" lines are in Show Log….
- Observed: iOS 27 rebuilds the main menu lazily, as the plan measured on 26:
  a top level that arrived after the window became key was in the bar only
  after a focus change (opening the pull-down, or the stream screen going), so
  each bar menu asks by the title it was built with (§7.2 rule 11).
- The review (2026-09-27, the plan's "The review and its fixes"): a fetch
  never checked against the menu the device opened (after an app inserted an
  item above a submenu in place, the device's "600 Items" listed 300 Items'
  items and a choice among them ran there); a queue with no deadline and a
  top-level read per fetch (a slow app's fourth menu answered after the device
  gave up); the compatibility floor without 24, 25 and 27; non-subscribers
  served and a departed device's fetch still read; two windows' bar acting on
  the other session; the button pushing narrow bars off the window and leaving
  a phone's strip less than a thumbnail; the keyboard left down after Menus
  over Settings; rule 11 across sessions; the stale note like a dimmed menu;
  the harness choosing on any Mac. Each reproduced, then fixed (992229f the
  host, 9dfa45a the device).
- Verified after the fixes (2026-09-27; the plan's Results have every number):
  `Tests/checks/run-all.sh`, all 22; mutants: menus 43 of 43 (309 checks),
  menu-state 29 of 29 (5,122), phone-portrait 31 of 31 (152), pointer-control
  33 of 33 (155), protocol 20 of 20; `Scripts/menu-check/run.sh`, reader 40,
  budget 4 and mirror 69 (the shift, the walks, only subscribers, the
  deadline, a sweep's one top-level read); through synthetic hosts on loopback
  with the fixture, one at a time, no device on Sill.app and the front never
  changing: H2 against main at 2b38179 (the CLI byte for byte, masked and
  sorted, idle and with a client, with and without `--direct-wireless`), and
  H4–H11, H14 (the tree changed in place) and H15 (only subscribers), 99
  checks; an app busy 500 ms a call, swept menu by menu: the four answered by
  3.6 s with one top-level read (5.6 s and four reads before); iOS Debug and
  Release for the simulator and Debug for a device, only the old
  `StreamClient` capture warning; `swift build -c release` from `git archive`,
  only the CaptureProbe warning; `make-app.sh` without `--install`, and the
  bundle's `--menu-selftest` against the fixture; in a private simulator,
  screenshots only: no button at 320x700 and 460x400, the phone's row at five
  widths, the note's own section, the bar empty with two windows, the
  keyboard's console lines, and `-SillMacMenu none` pixel for pixel main's
  build at the Duo's four sizes and the phone's 393x793; live against the
  fixture through a synthetic host (Probe asked by its title, Set Label A
  chosen), and a renamed copy of it refused by `-SillMenuPress` and
  `-SillMenusOpen`.
- Known: an app busier still (700 ms a call) answered the fourth menu at
  4.25 s, after the device's 4 s: the deadline is kept between Accessibility
  calls, not inside one. H12 (TextEdit through a host) was not run: TextEdit
  was not open, and none is started.
- **For Noah:** the plan's open questions took their defaults (Q1 the Mac's
  menus after the iPad's View, Sill's own kept; Q2 the button in every bar that
  holds it; Q3 shortcuts as subtitles; Q4 no Apple menu; Q5 the app activated
  when a menu opens; Q6 Option alternates as rows of their own; Q7 the
  Desktop's frontmost app; Q8 ⌘W unchanged; Q9 no banner; Q10 no setting; Q11
  kinds 24, 25, 27; Q12 no timer). Two placements are the review's defaults
  (Q2): on a phone the button ends the thumbnails' row (row 1's five kept; the
  key row is the other place), and a window too narrow for it leaves it out,
  so before iPadOS 26 a Slide Over has no menus.
- For the other branches: kind 28 (`trackpad-gestures`, merged since: PR #38)
  flipped `Tests/checks/protocol`'s, `menus`' and `pointer-control`'s "28
  unknown", and the three mutants that renumber a kind onto 28 or 29 moved to
  free numbers (Tests/checks/README.md); the pbxproj block A040–A044/F040–F044;
  StreamClient's `handle` gains `.macMenu`, its first window list the
  subscription, a move's `finishMove` `menusMoved()` and `tearDown`
  `resetMenus()`; `TopBar`, the portrait `windowBar` and the phone's
  thumbnails' row (`PhonePortraitLayout.menus`) the button; `SillApp` the
  adaptor.
- **Untested, for Noah (the plan's P1–P13, and the review's):** VS Code (its
  ten menus, Copy enabled with a selection, Themes, New Text File, "F5"),
  Weather (a ✓ toggled), Bambu Studio, Blender's two menus, the Desktop
  following the frontmost app (at once in Sill.app), the virtual display (Save
  As…'s sheet), ⌘S through a hardware keyboard with the menu showing it as
  text, the iPadOS 26 bar itself (a pointer at the top edge or a swipe down:
  the subtitles, the placeholder, ten or more menus, the lazy rebuild after a
  thumbnail tap), an app that stops answering, mixed builds, VoiceOver ("Code
  menus"), five minutes of use (frame age and rtt unchanged), an iPhone (the
  button at the end of the thumbnails' row); two Sill windows (the bar shows
  none of the Mac's menus, each window's button its own); a Slide Over (no
  button); Menus over the Settings panel with a hardware keyboard (keys reach
  the Mac again once the pull-down goes); a menu whose parent changes while it
  is open ("The menus changed…" once, then the new items); Blender's Window
  menu while the iPad's bar is swept (no answer later than the iPad waits).
