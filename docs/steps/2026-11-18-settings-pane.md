**Settings as a whole-screen pane on iPhone and iPad (2026-11-18, branch `settings-pane` from main at 8dbbb50; PR #393, a draft).**

- **Noah, 2026-11-18**: "Anything that it would make sense to add a toggle to you should add a toggle, also author a
  change to make the settings menu a full pane instead of a floating window". Asked which shape: "Whole screen
  everywhere: Settings covers the stream completely on every device, with Done to go back, like a settings page."
  This branch is that pane. The six features he asked for the same day (a Virtual Desktop, microphone and camera
  passthrough, recording, files and photos, privacy mode) each bring switches of their own; the pane is built to
  take them (each part scrolls on its own; a feature's group goes into the Mac's part or this device's), and none
  of their rows is added here.
- **What** (docs/settings-pane-plan.md has the design and its open decisions): `HostSettingsPanel` is a
  whole-screen pane over the stream screen, a sibling over the layouts in StreamScreen's root (never a system
  presentation: the harness's fake screen, the fold). Its rows are the panel's, the same views, in the same order
  and meaning; what changed is the container. Two parts: the Mac's (`macPart`, under the pinned header: the Mac's
  name, a page title now, the readout and route, the away line, Done; Disconnect under it, right under the rows
  while they fit and pinned where they scroll, as the panel had it) and this
  device's (`devicePart`: This iPad's group, Take the Tour, the version). `SettingsPane.Layout` (pure,
  `Tests/checks/settings-pane`) places them: one column (phones upright, the Duo's cover, the Duo open flat
  upright, narrow iPad windows), two columns side by side (sideways from 652 pt, upright from 732: phones on
  their side, iPads, the Duo open flat sideways; one column there too since 2026-11-23, below), a column on
  each page in the book pose, and in the laptop pose
  the Mac's part above the fold and this device's below it; nothing on the fold; at most 600 pt a column; right
  to left mirrored. The rows grow to the third accessibility text size (the header and Disconnect stop at
  xxLarge). It comes up from the bottom edge (0.35 s) and goes down (0.25 s), a fade under Reduce Motion.
- **Closing** (`SettingsPane.Close`): Done, Esc, ⌘. and VoiceOver's escape gesture go back to the stream screen
  (the keyboard back if the pane took it down, VoiceOver told the screen changed once it has gone); Pair This
  iPad…, an outside link, Take the Tour, Full Screen and a bar's control decide about the keyboard themselves,
  and the tour and full screen wait for the pane's motion (`StreamScreen.afterSettings`). Gone: the tap outside
  and the gear's close, both under the pane now.
- **The stream underneath** keeps running and keeps its layout: the layouts stay in place, so no viewport goes to
  the Mac while the pane is up; they take no touch and are hidden from VoiceOver (iOS 18's `isEnabled:`);
  Larger Picture still applies as Settings closes; sound, auto-lock (DeviceIdlePolicy), the hardware keyboard's
  hold and Picture in Picture are as with the panel.
- **What went with the floating panel**: its placement only: the tap catchers, the transition from the gear's
  corner, `BarMetrics.settingsWidth`, `DuoPosture.BookBar.panelWidth` (and `bookBar`'s `panelWidth:`),
  `PhonePortraitLayout.settings` and `settingsAnchor`, PortraitStreamScreen's `settingsTransition`,
  `pairThisDevice`, `takeTour` and `fullScreen` parameters. `phone-portrait` and `duo` lost the checks and
  mutants that held them (phone-portrait's M15 and M17, duo's M33); their other checks are as they were.
- **Kept for the parallel branches**: the file and type names (`HostSettingsPanel`), and the rows' code where it
  was (the Mac's block keeps its indentation; `middle` is `macPart` with `devicePart` split off after it), so a
  branch that adds a row there merges.
- **Its edges**: each part's rows fade over 12 pt where they scroll out of sight under the header, Disconnect or
  the fold (`ScrollEdgeFade`): the first photos showed a sliver of a line under the laptop pose's fold.
- **The review of #393** (2026-11-18), three findings, all real:
  - *The home indicator's room never reached the pane.* StreamScreen passed its reader's
    `geo.safeAreaInsets.bottom`, and a GeometryReader that ignores an edge (the stream screen's ignores the bottom,
    under the home indicator) reports no inset there, as full screen had found for its hidden room
    (docs/full-screen-plan.md, "Found and fixed"). So Disconnect sat 16 pt from the screen's edge, inside the home
    indicator's 34 (21 on a phone on its side, 20 on an iPad), and this device's part scrolled its last line under
    the indicator; the harness photos showed it (measured: Disconnect's foot 16 pt from the edge in every photo
    where it is pinned; this device's last line, at its end, 13). Now the pane takes the window's inset,
    `deviceInsets` (UIKit's, or the harness's fake screen's), as full screen does; the room under Disconnect is a
    rule of the pure layout, `SettingsPane.Layout.footBottom` (the home indicator's room, 16 pt at least; 12 over
    the laptop pose's fold), checked at every real size and over the grid, with mutants M32 to M34; Disconnect
    comes right under the rows only where that room is left under it too; and the console's `settings:` line says
    the bottom the pane was given ("one column 361 pt wide at 16 (393×793, 34 pt kept at the bottom)"), so a gate
    sees it arrive. The tour's card is given the same 0 (TourOverlay, StreamScreen's `bottomInset:` beside it):
    main's, untouched here.
  - *`-SillSettingsEnd 1` stopped short on an upright iPhone* (Take the Tour's footnote faded at the edge, the
    version out of view), the only `-end` photo that did: `StartAnchor` anchored only the
    initial offset on iOS 18, so a size change after the first layout left the rows where they were. It
    anchors size changes to the end too now, as the panel's plain anchor (every role) did; the alignment
    stays at the top, so rows shorter than their room still start there.
  - *docs/DEVELOPMENT.md said Settings stays on one side of the book pose's fold*: it has a column on each
    page (and in the laptop pose the Mac's part above the fold, this device's below); the paragraph says so.
- **Verified** (2026-11-18, on this Mac, nothing on a device): `Tests/checks/run-all.sh` all 75 pass;
  `settings-pane` 199 checks (708,590 layouts on the grid) and 31 of 31 mutants; `phone-portrait` 71 of 71 and
  `duo` 169 of 169 mutants caught after their panel checks went; the iOS app built for the simulator with CI's line
  (Xcode 27.1), no new warning (StreamClient.swift:4527's is main's). Harness photos through
  `Scripts/harness-photos.sh` on the agents' Duo (iOS 27.1, every pose by duorig) and iPad (iOS 27.0), 39
  cases against origin/main (`Scripts/harness-photos/settings-pane-duo.cases`, `settings-pane-ipad.cases`):
  the 7 cases with Settings closed are main's pixel for pixel; the rest show the pane in one column, two
  columns, the book pose's pages and the laptop pose's, scrolled to the end, a long list (the link's
  callout, Picture in Picture, a Paste note), the third accessibility text size and right to left. Photos and
  side-by-side pairs: `~/Downloads/sill-handoff/next/settings-pane/photos/`.
- **Verified after the review** (2026-11-18, fa90df8f, on this Mac): `run-all.sh` all 75 pass; `settings-pane` 258
  checks (708,590 layouts on the grid, Disconnect's room among the rules) and 34 of 34 mutants; the iOS app built
  with CI's line here and on GitHub's CI, no new warning. The same 39 photo cases against origin/main (eb48ac9f):
  with Settings closed, main's (6 of 7 pixel for pixel; `ipad-upright-stream` 3,161 pixels one level apart in the
  strip's fading thumbnail, a gradient that nothing here draws: the simulator's rendering). Measured in them:
  Disconnect, where pinned, ends 34 pt above the screen's edge on the Duo, its cover and an upright iPhone, 21 on
  a phone on its side, 20 on an iPad, 16 on an SE (each 16 before); this device's last line at its end 46.7 pt
  (book), 47 (laptop), 34 (phone on its side), 33 (iPad) (12.7 to 13 before); where the rows fit (iPads upright
  and sideways) Disconnect stays right under them; `phone-upright-end` reaches the version. The photos, the
  first set beside them and the measures: `~/Downloads/sill-handoff/next/settings-pane/photos/` (its README).
- **Not tested here** (Noah's list in the pull request): anything on a device; the motion; VoiceOver's order
  and its escape gesture, Esc and ⌘. on a hardware keyboard; Picture in Picture started with Settings open;
  rotating and folding with Settings open; the keyboard coming back after Done; Take the Tour and Full Screen
  from the pane.
- **2026-11-23: one column, and the scroll view across the screen.** Noah tried #393 on his iPad mini and his
  iPhone 15 Pro: "Settings should not be 2 columns, please make it 1 column" (the plan's open decision 1). So
  `SettingsPane.Layout` puts the two parts in one column on every screen without a fold to keep to (an iPad
  either way round, an iPhone on its side, the Duo open flat sideways, as an upright iPhone already was): the
  header pinned at the top, both parts in one scroll view, Disconnect under them, the column at most 600 pt and
  centred. Gone with the side-by-side columns: `gap`, `minUprightColumn`, `twoColumnsFrom` and
  `twoColumnsUprightFrom` (`minColumn` now only says when a book pose's pages are kept to), and the mutants of
  that code (M2, M4, M5, M19, M20, M22); M35 and M36 bring two columns back without a fold and must fail. The
  Duo's folded poses keep theirs: a column on each page of the book pose (one centred column would lie across
  the fold), the laptop pose's two pages; whether the book pose should change too is the plan's decision 7.
  Half an hour later, having seen one column on both devices in a test build, Noah: "Everything looks good
  except that on iPad in landscape, you have to touch the middle 3rd of the display to scroll instead of
  anywhere on the screen": the scroll view was only the column's width (600 of an iPad mini's 1,133 pt). Now
  each scroll view spans its page, the whole screen in one column, the book pose's page from the screen's edge
  to the fold's band, the laptop pose's page the screen's width, out to the screen's edges through the safe
  area beside the stream screen (an iPhone on its side: 44 to 62 pt by its sensor housing and as much on the
  other side; the Duo's cover: its camera's 84), and the header, the rows and Disconnect keep to their column
  inside it (HostSettingsPanel's `inColumn`; the rows that scroll by their scroll view's content margins, so the
  scroll view lays them out at the column's width as it did when it was the column's: padded inside it instead,
  Full Screen's footnote, which fitted its line with a point to spare, broke "them back." onto a second line in
  the first photos, b3a9029b). The pane is laid out in the safe area as before; each scroll view
  reaches past it with `ignoresSafeArea(edges: .horizontal)`, as far as the pane's own reader says the safe
  area goes (`geo.safeAreaInsets`, in the same layout, so a turn moves both at once), and its rows are placed
  from its reached edge. The pure rule says both (`Layout.macScroll`, `deviceScroll`, `page(_:)`, the column
  inside), the console's `settings:` line says the scroll views ("one column 600 pt wide at 266.5, its scroll
  view 0–1133 (1133×720, 20 pt kept at the bottom)" on an iPad mini on its side, "… at 67, its scroll view
  -59–793 (734×393, …)" on an iPhone 15 Pro on its side), and the check holds them at every real size and over
  the grid (both side strips, the leading alone, the trailing alone), with mutants M37 to M48 (a scroll view
  narrowed back to its column, short of the screen's edge, onto the fold, the strips swapped, a page laid out
  past the stream screen). DEBUG `-SillSettingsScrollArea 1` outlines each scroll view, so a still shows where a
  drag scrolls. What a wider scroll view changes: its edge fades run its width,
  which holds nothing beside the column, so they look as before; its indicator is at the page's trailing edge
  (the screen's in one column), as in iOS's own Settings; VoiceOver's order is the same (no element added or
  moved); right to left mirrors it all from the leading edge.
