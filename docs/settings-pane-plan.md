# Settings as a whole-screen pane on iPhone and iPad

2026-11-18, branch `settings-pane` from main at 8dbbb50 (#387, 0.6.3). Device only: no wire change,
nothing on the Mac, nothing new stored.

Noah, 2026-11-18: "Anything that it would make sense to add a toggle to you should add a toggle, also author
a change to make the settings menu a full pane instead of a floating window". Asked which shape, he chose:
"Whole screen everywhere: Settings covers the stream completely on every device, with Done to go back, like
a settings page." The same day he asked for six features (a Virtual Desktop, microphone and camera
passthrough, recording, files and photos, privacy mode), each with switches of its own: the pane is built
for many more rows, and none of theirs is added here.

## What it is

Settings is a page over the whole stream screen, on every device and in every layout: an iPad either way
round and in its narrow windows, an iPhone upright and on its side, the iPhone Duo's cover and its inner
display in every pose. It opens from the same gear button and closes with Done. Its rows are the Settings
panel's rows, the same views in one place (`HostSettingsPanel`), unchanged in meaning and in order.

- **In the view hierarchy, not a presentation.** As the panel, the tour and the pairing overlay are: a
  sheet or a full-screen cover would escape the harness's fake screen, adapts by size classes the Duo does
  not settle, and knows nothing of the fold. The pane is a sibling over the stream screen's layouts, under
  the tour and the pairing overlay (which close it before they open). Its background, the bars' colour,
  runs under the status bar and into the side insets; its content stays in the safe area and above the
  home indicator.
- **Its two parts** are the places for rows (`SettingsPane.Layout`, pure, `Tests/checks/settings-pane`):
  - the Mac's: the header (the Mac's name, a page's title now, with the readout and its route, "On the
    virtual display", the remote route and round trip, the away line, a locked Mac's line, and Done), the
    callouts (the encoder, a refused change, the link's callout and its button, the slow link), Quality,
    Resolution and Frame Rate, Full Screen and Shake to Show Controls (after Frame Rate, Noah 2026-11-12),
    Prioritize Encoding Speed, Virtual Display, Send Audio with Mute, Direct Wireless Connection, the
    SillHost note, Away from home; then Disconnect;
  - this device's: This iPad (This iPhone) and its switches, Take the Tour, the version.
- **Arranged by the screen and the fold** (the rule is `SettingsPane.Layout`'s):
  - *One column* (an iPhone upright, the Duo's cover either way, the Duo open flat upright, an iPad window
    narrower than two columns): the header pinned at the top, both parts in one scroll view, Disconnect
    pinned at the bottom, as the panel had them. At most 600 pt wide, centred, 16 pt from the safe area.
  - *Two columns* (a screen held sideways with room for two of 300 pt: every iPhone on its side, the SE's
    667 pt included; the Duo open flat sideways; an iPad sideways; and upright where two of 340 pt fit: an
    iPad upright, the mini's 744 included, but never the Duo's 669): the Mac's part in the leading column
    with Disconnect pinned under it, this device's in the trailing one, each scrolling on its own; each at
    most 600 pt, 20 pt apart, the pair centred. The header runs over both: the Mac's name and lines over the
    Mac's column, Done at the far column's trailing end. Why: a phone on its side is 375 to 440 pt tall and
    shows twice as much; an iPad has room for both parts side by side; and the book pose needs exactly this.
  - *The book pose* (the Duo's inner display sideways, half-folded): the two columns one on each page,
    centred there, 16 pt from the page's edges; the fold's band between them holds nothing (the header's
    words stay on the leading page, Done is on the trailing one).
  - *The laptop pose* (upright, half-folded): two pages, the Mac's part above the fold (the header, its
    groups and Disconnect at the page's foot) and this device's below it, each scrolling on its own;
    nothing on the band. A fold whose pages could not hold a column (no device has one) is not kept to.
  - Right to left (Arabic, Hebrew): the Mac's part is on the leading side, the right, Done on the left; a
    fold's pages are the right page and the left one.
- **For the rows to come**: a feature of the Mac (Virtual Desktop, privacy mode) adds its group to the Mac's
  part, a feature of this device (microphone and camera passthrough, recording, files and photos) to this
  device's: a group is a `Rows` with its `Footnote`, and a group that begins a topic of its own carries a
  header the way Away from home and This iPad do. Each part scrolls on its own, so neither runs out of room.
- **Large type**: the parts' rows grow with Dynamic Type to the third accessibility size (the panel stopped
  at xxLarge for want of room; a whole screen has it, and every row stacks its control under its words when
  the words need the width); the pinned header and Disconnect stay at most at xxLarge, so on a phone on its
  side they never take the screen from the rows.
- **Light and dark**: the app is dark in both appearances (ContentView's `.preferredColorScheme(.dark)`),
  and so is the pane; its colours are the panel's (`Palette`).

## Opening and closing

- Opening (the gear in every bar, as before): the drawer, a thumbnail's lights and the Aa ruler go, the
  person's keyboard goes down (and comes back when they close it), and the pane comes up from the bottom
  edge, a full-screen page's motion (0.35 s; a fade under Reduce Motion).
- Closing (`SettingsPane.Close`): Done, Esc, ⌘. and VoiceOver's escape gesture, as before: back to the stream
  screen, the keyboard back if the pane took it down, and VoiceOver reads the screen afresh. Pair This
  iPad…, an outside sill://pair link, Take the Tour and Full Screen close it on their way to what they open
  (the tour and full screen wait for its motion, 0.25 s); Disconnect ends the session. Gone with the floating
  panel: a tap outside it (there is no outside) and the gear button, which is under the pane. No swipe
  down: a whole-screen page closes with Done. No ⌘W: the app has none, and under Sill's hold ⌘W is the
  Mac's own Close Window.
- VoiceOver: the pane is one modal element, as the panel was: its focus starts on the Mac's name, then the
  header's lines, Done, the Mac's part, Disconnect, and this device's part; the stream screen under it is
  hidden from VoiceOver and takes no touch.

## The stream underneath

It keeps running, and nothing about it changes while the pane is up:
- **The picture**: the layouts stay in place under the pane at the size they had, so no viewport goes to
  the Mac and nothing is resized; the picture keeps decoding out of sight, and is there as it was at Done.
  Larger Picture keeps the arrangement it had when the pane opened and applies as it closes, as before
  (its footnote, "A change applies when you close Settings", stays true).
- **Sound**: as before; Send Audio and Mute are in the pane.
- **Auto-lock** (DeviceIdlePolicy): unchanged. A window streams, so the device's own auto-lock is held off
  while the person uses Sill (the pane's controls count, as the panel's did) and is the device's again ten
  minutes after the last use.
- **Input**: none reaches the Mac, as with the panel: the keyboard is down, a hardware keyboard's hold lets
  go (`HardwareKeyboardPolicy.Taker.settings`), and the layouts take no touch.
- **Picture in Picture**: unchanged; the pane is not a cover over the picture (`PictureInPicturePolicy`'s
  `covered` is the locked Mac's), so leaving Sill with Settings open offers the window's picture as
  leaving without it does. Whether iOS starts it from a layer under an opaque view is iOS's to say:
  untested on a device (Noah's list).

## The tour and Full Screen

- The tour's settings card points at the gear, which has not moved; its words ("Disconnect is at the bottom
  of Settings", "Take the Tour is there too") stay true (in the laptop pose Disconnect is at the foot of the
  Mac's page). Take the Tour closes the pane, waits for its motion, then runs the tour of the layout on
  screen, as before.
- Full Screen and Shake to Show Controls stay after Frame Rate; Full Screen closes the pane, waits for its
  motion, and hides the controls, as before.

## What went with the floating panel

Its placement only: the tap catcher, the transition from the gear's corner, its widths
(`BarMetrics.settingsWidth`, `DuoPosture.BookBar.panelWidth`), and the phone's rect for it
(`PhonePortraitLayout.settings` and `settingsAnchor`); the checks that held them changed with them. The rows
and their behaviour are untouched.

## Open decisions for Noah, and the default taken for each

1. **Two columns on wide screens** (taken: sideways from 652 pt, upright from 732 pt) or one centred column
   everywhere but the book pose. Two columns show twice as much on a phone on its side and use an iPad's
   width; one column would read the same on every device. One constant (`SettingsPane.minColumn`) changes it.
2. **Disconnect in the laptop pose**: at the foot of the Mac's page, above the fold (taken), with the Mac's
   things and away from the palms on the lower page; or at the screen's bottom, under this device's part.
3. **Large type to the third accessibility size** (taken) or kept at xxLarge as the panel was.
4. **The motion**: up from the bottom edge (taken), as a full-screen page comes; or a fade.
5. **The Mac's name as the page's title** (taken: 20 pt semibold, the panel's was 17) or as it was.
6. **No swipe down to close** (taken): a whole-screen page closes with Done; a swipe down from the header
   could be added for one-handed use.
