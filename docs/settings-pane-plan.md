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
  - *One column* on every screen without a fold to keep to (Noah, 2026-11-23: "Settings should not be 2
    columns, please make it 1 column"): an iPhone upright and on its side, an iPad either way round and in
    its narrow windows, the Duo's cover either way, and its inner display open flat either way. The header
    pinned at the top, both parts in one scroll view (the Mac's, then this device's), Disconnect under them,
    as the panel had them. The column is at most 600 pt wide, centred, 16 pt from the safe area; the scroll
    view spans the whole screen with the column inside it, so a drag anywhere on the pane scrolls the rows
    (Noah, the same day, of the first build with one column: "on iPad in landscape, you have to touch the
    middle 3rd of the display to scroll instead of anywhere on the screen"; that build's scroll view was the
    column's 600 pt, of an iPad mini's 1,133). The header and Disconnect keep to the column. Until that day a
    screen with room for two columns (sideways from 652 pt, upright from 732: every iPhone on its side, an
    iPad either way round, the Duo open flat sideways) had the two parts side by side, the Mac's in the
    leading column; Noah tried that on his iPad mini and his iPhone 15 Pro and asked for one column.
  - *The book pose* (the Duo's inner display sideways, half-folded): a column on each page, centred there,
    16 pt from the page's edges, the Mac's part on the leading page and this device's on the trailing one,
    each page's scroll view across the page from the screen's edge to the fold's band; the band between them
    holds nothing (the header's words stay on the leading page, Done is on the trailing one). One centred
    column would lie across the fold, so each page keeps its column: the alternative this plan gave ("one
    centred column everywhere but the book pose"). Whether the book pose should change too is open (decision
    7). A fold whose pages could not hold a column of 300 pt (no device has one: the Duo's hold 423.5) is not
    kept to.
  - *The laptop pose* (upright, half-folded): two pages, the Mac's part above the fold (the header, its
    groups and Disconnect at the page's foot) and this device's below it, each scrolling on its own, each
    scroll view the screen's width with the column inside it; nothing on the band. A fold whose pages could
    not hold a column (no device has one) is not kept to.
  - Right to left (Arabic, Hebrew): the Mac's part is on the leading side, the right, Done on the left; a
    fold's pages are the right page and the left one.
- **Disconnect** ends the Mac's part, as the panel had it: in one column after both parts, right under the
  rows while they all fit without scrolling and pinned under their scroll view where they do not; on the
  book pose's leading page and the laptop pose's upper page the same way under the Mac's rows. In reach
  either way.
- **Scrolling**: the rows scroll (in one column both parts together; around the fold each part on its own)
  and bounce only when they do not fit. Each scroll view spans its page, the whole screen in one column, and
  the rows keep to their column inside it (`SettingsPane.Layout`'s `macScroll` and `deviceScroll`), so a drag
  beside them scrolls them as a drag on them does; a tap there does nothing. Their edges fade over 12 pt where
  rows go out of sight under the header, Disconnect or the fold (the panel cut them sharply, which at the
  laptop pose's fold left a sliver of a line); the fade runs the scroll view's width, which holds nothing
  beside the column, so it reads as before. The scroll indicator is the scroll view's: at the trailing edge of
  the screen in one column (of the page around the fold, beside the band on the book pose's leading page),
  away from the rows on a wide screen, as in iOS's own Settings, whose lists run the screen's width while their
  rows keep a readable one.
- **For the rows to come**: a feature of the Mac (Virtual Desktop, privacy mode) adds its group to the Mac's
  part, a feature of this device (microphone and camera passthrough, recording, files and photos) to this
  device's: a group is a `Rows` with its `Footnote`, and a group that begins a topic of its own carries a
  header the way Away from home and This iPad do. The rows scroll, so neither part runs out of room.
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
  header's lines, Done, the Mac's part, and this device's part, with Disconnect last in one column, where it
  ends both parts (the panel's order), and after the Mac's part on the book pose's and the laptop pose's
  pages; a scroll view wider than its rows adds no element and moves none, and VoiceOver's three-finger
  scroll takes the whole page. The stream screen under it is hidden from VoiceOver (iOS 18 and later; before,
  the modal trait alone keeps VoiceOver in the pane, as it did in the panel) and takes no touch.
- A hardware keyboard: Esc and ⌘. close the pane. The scroll view's width changes nothing for the keyboard:
  the same one scroll view (one per page around the fold) holds the same rows; whether iPadOS's own keys
  scroll it is untested on a device, as it was before.

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

## Decided

1. **One column; Noah, 2026-11-23**, having tried the pane on his iPad mini and his iPhone 15 Pro: "Settings
   should not be 2 columns, please make it 1 column". One centred column on every screen without a fold to
   keep to, the iPhone Duo's folded poses as they were (a column on each page of the book pose, a page each
   side of the laptop pose's fold). Until then the default taken was two columns on wide screens, sideways
   from 652 pt and upright from 732. Half an hour later, having seen one column on both devices in a test
   build: "Everything looks good except that on iPad in landscape, you have to touch the middle 3rd of the
   display to scroll instead of anywhere on the screen". So one column stands on the iPad and the iPhone,
   both ways round, and each scroll view now spans its page (the whole screen in one column), the rows, the
   header and Disconnect keeping to their column inside it.

## Open decisions for Noah, and the default taken for each

2. **Disconnect in the laptop pose**: at the foot of the Mac's page, above the fold (taken), with the Mac's
   things and away from the palms on the lower page; or at the screen's bottom, under this device's part.
3. **Large type to the third accessibility size** (taken) or kept at xxLarge as the panel was.
4. **The motion**: up from the bottom edge (taken), as a full-screen page comes; or a fade.
5. **The Mac's name as the page's title** (taken: 20 pt semibold, the panel's was 17) or as it was.
6. **No swipe down to close** (taken): a whole-screen page closes with Done; a swipe down from the header
   could be added for one-handed use.
7. **The book pose** after decision 1 (taken: as it was, a column on each page, the Mac's part on the leading
   page and this device's on the trailing one, each scrolling on its own across its page), or one column there
   too: both parts in one scroll view on the leading page, the trailing page empty. A column centred on the
   screen would lie across the fold. The photos `book` and `book-end` show what is taken.
