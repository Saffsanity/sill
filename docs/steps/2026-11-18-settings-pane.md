**Settings as a whole-screen pane on iPhone and iPad (2026-11-18, branch `settings-pane` from main at 8dbbb50).**

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
  name, a page title now, the readout and route, the away line, Done; Disconnect pinned under it) and this
  device's (`devicePart`: This iPad's group, Take the Tour, the version). `SettingsPane.Layout` (pure,
  `Tests/checks/settings-pane`) places them: one column (phones upright, the Duo's cover, the Duo open flat
  upright, narrow iPad windows), two columns side by side (sideways from 652 pt, upright from 732: phones on
  their side, iPads, the Duo open flat sideways), a column on each page in the book pose, and in the laptop pose
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
