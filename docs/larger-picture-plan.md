# Larger Picture on an iPhone held upright — the plan

2026-10-14. Branch `larger-picture` (worktree `/Users/noah/Downloads/winstream-larger-picture`) from
origin/main at 985a733. Issue #58 (rosstex: "The menu and touchpad take up more than half of the
vertical space on the iOS app. When using Mac apps that rely heavily on scrolling like Notes,
Chrome, etc. they feel tiny on the phone screen."), which Noah answered on 2026-10-12 with a
settings option. The triage of 2026-10-13 (sill-handoff `triage/2026-10-13-open-items.md`, #58)
recommended the design below, and the run that started this branch took it as the default. Device
only: no wire change, nothing on the host, the switch is the device's own and never sent. An
adversarial review the same day found five things, each fixed on this branch (Results, "The review
and its fixes"): rules 8, 10 and 11 and open questions 9 to 11 come from it. Noah tried the branch
on his iPhone 15 Pro on 2026-10-15: "Larger Picture seems to work properly. However, when in Desktop
mode, there is negative space on the bottom, seemingly because of the Mac aspect ratio. Can we
disable this feature when Desktop mode is active?" Since then it applies only while a window streams
(rule 12, open questions 12 to 14; Results, "The Desktop keeps the standard arrangement").

## The problem

On a phone held upright (`PhonePortraitLayout`, docs/iphone-portrait-plan.md) the picture is a
fixed 16:10 pane at the top (PhonePortraitLayout.swift: `picture`), 30 % of an 18 Pro Max's
screen: 424×265 pt. Under it come row 1 (Apps, Aa, Keyboard, Desktop, Settings), the thumbnails,
the key row and the trackpad, which takes the rest: 412×389 on the Pro Max. The rows take a fixed
240 pt. Shrinking them buys 25 to 30 pt. The real limit is the software keyboard: it comes up over
the bottom of the screen and must never cover the key row (the portrait plan's keyboard table: 320
pt on the 18 Pro Max, 301 on the 18 Pro and the 17e, 216 on the SE, which measures 233: Results).
Below the key row there is only the trackpad, which the keyboard covers anyway.

## Decision

### In one paragraph

Settings › This iPhone gains **Larger Picture** (off by default; `Sill.largerPicture` in the app's
defaults; shown only on an iPhone without a hinge whose picture it makes larger, where it acts: not
where Display Zoom makes the screen 320 pt wide). With it on, a phone held upright
draws the Larger Picture arrangement while a window streams (the Desktop, which Aa never resizes,
and nothing streaming keep the standard one: rule 12): the thumbnails' row goes, and the picture
gets every point that keeps the key row 10 pt above the software keyboard: room = container −
keyboard − 152 pt (18 Pro Max 424×265 → 424×422, 15 Pro 377×235 → 377×340, SE 359×224 →
359×262: the triage's 279 took the SE's keyboard as 216 pt, and it measures 233). The trackpad
becomes the keyboard's footprint, so nothing moves when the keyboard comes up; row 1 and the key row
stay where that rule puts them. The picture's frame takes the picture's own shape inside its room,
from the top: a 16:10 window keeps its shape, a taller one gains, and a window the Mac fits to the
room (Aa set, or the virtual display) fills it. The viewport is the whole room, so toggling sends
one new viewport (one restart while the Mac fits the window), and so does a switch between the
Desktop and a window, as a rotation does. The trackpad's vertical span follows
the picture's real shape, so a stroke moves the pointer as far down as across. Windows stay
reachable from Apps (tapping an open app again shows its next window) and from the Mac's Window
menu: the Menus button moves into row 1, after Apps, while the Mac sent menus. The Apps drawer opens
above row 1, over the room, so no keyboard covers it, and a change of the switch (or of what
streams) shows when the Settings panel closes, so the panel never moves under the finger. Every rect
is a pure function of the screen's size, the keyboard's height and the switch with what streams (and
the frame and the span also of the picture's shape), in `PhonePortraitLayout`, checked in
`Tests/checks/phone-portrait`.

### The rule

W × H is the stream screen (the screen less its top inset, as before); K the keyboard's height
(below); K' = max(K, 136), so the trackpad keeps its least 120 pt.

1. **The room:** x 8, y 8, W − 16 wide, ⌊H − K' − 152⌋ tall (never below 0). 152 pt is everything
   above the keyboard but the picture: 8 + 8 + 10 + 6 (the margins and row 1's band above), 50
   (row 1), 6 + 10 (its band below and a row gap), 44 (the key row), 10 (the clearance).
2. **Row 1:** 24 pt under the room, as today under the picture; five buttons of (W − 60) ÷ 5, or,
   while the Mac sent its menus, six of (W − 68) ÷ 6: Apps, Menus, Aa, Keyboard, Desktop, Settings
   (the landscape bar's order with the strip gone).
3. **No row 2.** The strip is a row of no height at row 1's band's bottom (for the rules' order).
4. **The key row:** 16 pt under row 1's buttons (its band and a row gap), its bottom 10 pt above the
   keyboard's top.
5. **The trackpad:** from the keyboard's top (H − K') to H − 16, 14 pt from each side: the
   keyboard's footprint.
6. **The frame** for a picture of shape w × h (16:10 before the first frame): as wide as the room
   and ⌊room width × h ÷ w⌋ tall, from the room's top; a shape taller than the room is as tall as
   the room, ⌊room height × w ÷ h⌋ wide and centred across it. Whole points, past a hundredth of a
   point, so a window fitted to the room fills it exactly.
7. **The trackpad's span:** its width × the frame's height ÷ its width, so the pad's width moves the
   pointer the frame's width and the span its height. (Today's arrangement keeps its width ÷ 1.6.)
8. **The ruler** on Aa (of five, or of six while the Mac sent menus), the **Settings panel** under
   row 1 across its span, the **dim**: today's rules, on the new row 1. The **drawer** opens upward
   instead: from 8 pt under the stream screen's top to 8 pt above row 1, across row 1's span (the
   room + 16: 438 pt on the Pro Max, 278 on the SE), 128 pt clear of the planned keyboard's top.
   Under row 1 is the keyboard's footprint, where a keyboard up, the Mac's or the one the drawer's
   own search field brings, left only its padding and search field in view (62 pt on every phone;
   the review). The panel stays under row 1: opening it takes the keyboard down, and the picture
   stays in view while a setting changes.
9. **The keyboard's height** K: the software keyboard as Sill's input view shows it (autocorrection
   off: no suggestions bar), from the stream screen's shape and width, since it is only known once
   it shows. A stream screen under 1.9 times as tall as wide is a Home-button iPhone (the SE's
   375×647 is 1.73, with Display Zoom 320×548 1.71): 233 pt. Else one with Face ID (2.0 and more,
   zoomed too): 320 from 414 pt wide (the 11, 11 Pro Max, Air, Plus and Pro Max sizes), 301 from 390
   (the 12 to 18, 16e and 17e, the Pros), 310 from 375 (the 12 and 13 mini; the 11 Pro's is 301),
   and narrower than any phone (Display Zoom) the tallest, 320, so a keyboard nobody measured still
   leaves the key row clear. All measured on the iOS 27 simulators (Results, S2); the plan began
   with docs/iphone-portrait-plan.md's table, whose SE (216, the classic) and whose Air, 11s and
   minis (taken as 301) the measurements corrected. On a device with a hinge (the iPhone Duo) there
   is none: its cover's keyboard was never measured, so the switch is hidden there and the cover
   stays as it is (`PhonePortraitLayout.keyboard(for:largerPicture:foldable:)`).
10. **Only where it is larger:** the arrangement applies only where its room is taller than today's
   picture and row 1's six buttons are 44 pt or more, a touch target (`largerPictureGains`,
   `minButtonWidth`), so on a stream screen 332 pt wide or more; elsewhere `keyboard(for:…)` gives
   none and the layout stays today's. Display Zoom makes an SE, a 12 or 13 mini or a 6.1-inch iPhone
   320 pt wide: above a 6.1-inch one's keyboard the room would be 304×173 against today's 304×190 (the
   Desktop 266×173 against 304×190), above the zoomed SE's 304×163 against 304×188, and six buttons
   42 pt (the review). The Settings panel offers the switch only where it acts
   (`offersLargerPicture(screen:)`, passed down as the environment's `largerPictureOffered`, with
   the hinge's rule and the idiom), judging the stream screen held upright whichever way it is held:
   sideways its longer side is short of the upright one by the side insets, which leaves the answer
   the same on every iPhone, zoomed or not (the check tries every side inset from 0 to 70 pt).
11. **When it applies:** a change of the switch shows when the Settings panel closes, in the panel's
   own motion (StreamScreen's `largerPictureHeld`, held by `setSettings`): the panel hangs under row
   1, which the switch moves by the picture's growth (118 pt on an 18 Pro, 157 on a Pro Max), so the
   switch would jump from under the finger that flipped it (the review). Its footnote says so. Since
   rule 12 the panel holds the arrangement itself, Larger Picture as it was in effect when it opened
   (`largerPictureNow`), so a change of what streams while it is open (a window closed on the Mac,
   another device's pick) waits for it to close too.
12. **Only while a window streams** (Noah, 2026-10-15): Larger Picture is in effect with the switch on
   while the Mac's window list says a window streams (`PhonePortraitLayout.largerPicture(switchOn:
   streaming:)`, from `StreamClient.active`); the Desktop keeps the standard arrangement, the 16:10
   pane and the thumbnails, because Aa never resizes the Desktop, so the room's extra height could
   only be black under it (on the 15 Pro a 14-inch MacBook Pro's Desktop drew 377×244 at the top of a
   377×340 room, 96 pt of black; on the 18 Pro Max 424×275 in 424×422, 147 pt). So does nothing
   streaming (connecting until the Desktop starts; a window closed, until the Desktop the device then
   asks for; a window off the Mac's list for a moment, a Space change; a pick that failed), so the
   Desktop's first picture arrives into the arrangement it keeps and nothing flips after it (open
   question 13). The Mac never reports nothing between two windows (it names the old window until
   the new one streams), so a switch from window to window keeps Larger Picture throughout. One rule
   for everything the switch decides: StreamScreen hands `keyboard(for:largerPicture:foldable:)` its
   answer, and the arrangement, its viewport, the tour's targets and words and the cards' places all
   follow from that keyboard; the Settings panel's switch and its footnote do not depend on what
   streams (the switch is offered as for a window, the footnote says it is a window's picture).

```swift
struct PhonePortraitLayout {        // additions
    static let keyboardClearance: CGFloat = 10
    static let homeButtonKeyboard: CGFloat = 233, faceIDKeyboard: CGFloat = 301, miniKeyboard: CGFloat = 310
    static let wideKeyboard: CGFloat = 320, wideKeyboardFrom: CGFloat = 414, faceIDKeyboardFrom: CGFloat = 390
    static let miniKeyboardFrom: CGFloat = 375, faceIDShape: CGFloat = 1.9, minButtonWidth: CGFloat = 44
    let keyboard: CGFloat?                    // Larger Picture's keyboard; nil: today's arrangement
    var largerPicture: Bool
    let buttonsBesideMenus: [CGRect]          // row 1 while the Mac sent menus
    let rulerBesideMenus: CGRect, rulerStepBesideMenus: CGFloat
    init(size: CGSize, keyboard: CGFloat? = nil)
    func pane(video: CGSize) -> CGRect        // the frame, rule 6
    func trackpadSpan(video: CGSize) -> CGFloat
    static func keyboardHeight(for container: CGSize) -> CGFloat
    enum Streaming: CaseIterable { case nothing, desktop, window }                       // rule 12
    static func largerPicture(switchOn: Bool, streaming: Streaming) -> Bool             // switchOn && .window
    static func keyboard(for container: CGSize, largerPicture: Bool, foldable: Bool) -> CGFloat?
    static func largerPictureGains(_ container: CGSize, keyboard: CGFloat) -> Bool   // rule 10
    static func offersLargerPicture(screen: CGSize) -> Bool                             // the panel's switch
}
```

### The numbers

From the rule (the prototype is the code: `Tests/checks/phone-portrait` pins these). The container
is the screen less its top inset (as the simulators gave it: the Air's is 68 pt); "today" is the
switch off; K is the keyboard as measured (Results, S2), which the rule's estimate gives on each
(marked * where nobody measured it: Display Zoom's). The drawer is the room + 16 pt, above row 1.

| Phone (container) | K | Room (today's picture) | Row 1 | Key row | Trackpad (today) | Panel room (today) | Drawer | A window of the Desktop's shape |
|---|---|---|---|---|---|---|---|---|
| 18 Pro Max (440×894) | 320 | 424×422 (424×265), +59 % | 454–504 | 520–564 | 412×304 at 574 (389) | 366 (523) | 438 | 424×275 |
| 15 Pro Max, 16 Plus (430×873) | 320 | 414×401 (414×258), +55 % | 433–483 | 499–543 | 402×304 at 553 (375) | 366 (509) | 417 | 414×268 |
| Air (420×844) | 320 | 404×372 (404×252), +48 % | 404–454 | 470–514 | 392×304 at 524 (352) | 366 (486) | 388 | 404×262 |
| 11 Pro Max (414×852) | 320 | 398×380 (398×248), +53 % | 412–462 | 478–522 | 386×304 at 532 (364) | 366 (498) | 396 | 398×258 |
| 18 Pro (402×812) | 301 | 386×359 (386×241), +49 % | 391–441 | 457–501 | 374×285 at 511 (331) | 347 (465) | 375 | 386×250 |
| 15 Pro, Noah's (393×793) | 301 | 377×340 (377×235), +45 % | 372–422 | 438–482 | 365×285 at 492 (318) | 347 (452) | 356 | 377×244 |
| 17e, 16e (390×797) | 301 | 374×344 (374×233), +48 % | 376–426 | 442–486 | 362×285 at 496 (324) | 347 (458) | 360 | 374×242 |
| 12 and 13 mini (375×762) | 310 | 359×300 (359×224), +34 % | 332–382 | 398–442 | 347×294 at 452 (298) | 356 (432) | 316 | 359×233 |
| SE (375×647) | 233 | 359×262 (359×224), +17 % | 294–344 | 360–404 | 347×217 at 414 (183) | 279 (317) | 278 | 359×233 |
| 6.7-inch with Display Zoom (375×762) | 310* | 359×300 (359×224), +34 % | 332–382 | 398–442 | 347×294 at 452 (298) | 356 (432) | 316 | 359×233 |
| 6.9-inch Pro Max with Display Zoom (402×812) | 301* | 386×359 (386×241), +49 % | 391–441 | 457–501 | 374×285 at 511 (331) | 347 (465) | 375 | 386×250 |
| 6.1-inch or mini with Display Zoom (320×645) | 320* | not offered: 304×173 against today's 304×190, six buttons of 42 | | | | | | |
| SE with Display Zoom (320×548) | 233* | not offered: 304×163 against today's 304×188, six buttons of 42 | | | | | | |

A window of the shape of a 14-inch MacBook Pro's Desktop (1512×982 pt, 1.54:1) is a little taller
than 16:10, so its frame gains 10 pt on the Pro Max; a 16:10 window gains nothing until the Mac fits
it to the room. The Desktop itself keeps the standard arrangement since 2026-10-15 (rule 12): its
frame is today's picture, the Desktop fitted inside it (408×265 on the Pro Max, 362×235 on the 15
Pro), where the branch drew it 424×275 and 377×244 at the top of the room, 147 and 96 pt of black
under it.
Row 1's six buttons with Menus are 62 pt wide on the Pro Max and 51.2 on the 375 pt phones, the
narrowest Larger Picture applies to; at 320 pt they would be 42, under a touch target's 44. The
ruler's step is 36 with six on every phone. The panel room with Larger Picture is K + 46 pt (279 on
the SE, the shortest: the compact halves' 259 at 500×710 stays the least, and the panel scrolls
there as it does); the drawer's is the room + 16 (278 on the SE). With the keyboard up, a drawer
under Larger Picture's row 1 kept 62 pt in view on every phone, today's keeps 219 on the Pro Max,
167 on the 15 Pro, 138 on a mini and 100 on the SE, and the drawer above row 1 all of it.

### The views

- **`PortraitStreamScreen.phone`** places `PhoneRows` at the rule's rects in reading order:
  picture, row 1, (the strip, today), the key row, the trackpad. With Larger Picture the strip is
  not declared (VoiceOver: Apps, Menus, Text size, Keyboard, Desktop, Settings, Escape … Shift, the
  trackpad's hint), and the picture's pane is placed at `pane(video: client.videoSize)` (its
  background, corners and stroke follow it; the black around it is the screen's). The pane reports
  no size of its own then: the viewport is the room (`onPanelSize(layout.picture.size)`), so the
  Mac fits a window to all of it. Nothing else changes in the pane (the same `StreamView` and
  `InputOverlay`, so the keyboard's first responder survives the toggle). The drawer is placed at
  `layout.drawer`, above row 1, and read after it: the accessibility tree orders one level top to
  bottom, so the drawer is one container sorted after the rest (`AfterRow1`), and VoiceOver reads
  row 1, then the list.
- **Row 1** gets the Menus button after Apps while the Mac sent menus (`buttonsBesideMenus`,
  `rulerStepBesideMenus`), fading with the others under the Aa ruler.
- **The trackpad** gets `trackpadSpan(video:)`.
- **`StreamScreen`** reads the switch (`@AppStorage`), what streams (`client.active`, mapped to
  `PhonePortraitLayout.Streaming`) and the hinge (`posture.hinge`), puts the first two through rule
  12 (`largerPictureNow`), asks `PhonePortraitLayout.keyboard(for:largerPicture:foldable:)` for the
  phone's layout, and passes it down; the tour learns whether the thumbnails show and the room.
  While the Settings panel is open it keeps Larger Picture as it was in effect when the panel opened
  (`largerPictureHeld`, rule 11), and it tells the panel whether to offer the switch
  (`largerPictureOffered`, rule 10). Its viewport follows the arrangement (PortraitStreamScreen's
  picture), so a switch between the Desktop and a window sends a new one, as a rotation does; and a
  thumbnail's lights, which hang from the strip, close when the arrangement changes under them
  (what streams changed, or a turn), rather than come back unasked with the strip.
- **`HostSettingsPanel`**, This iPhone: "Larger Picture" before Three-Finger Gestures, with its
  footnote: "Held upright, a window’s picture takes the place of the window thumbnails and reaches
  down to where the keyboard comes up. The Desktop keeps the thumbnails. Switch windows with Apps:
  tap an open app again for its next window. To fill the taller picture with a window, set its text
  size with Aa. A change applies when you close Settings." (Until 2026-10-15: "Held upright, the
  picture takes the place …" and "The picture changes when you close Settings.") Only where the
  stream screen offers it (`largerPictureOffered`): an iPhone without a hinge whose picture it makes
  larger, whatever streams.
- **The tour** (`TourPolicy`): a target for Apps (`TourTarget.apps`, row 1's Apps on a phone);
  without the thumbnails the bar card lights Apps, Aa and Keyboard (Menus between them) and its
  first row is about Apps ("Apps lists the apps on ‹Mac›: tap an open one again for its next
  window."; under VoiceOver "Apps lists the apps on ‹Mac›. Choose an open one again for its next
  window."); its hint "Under the picture, in the row of buttons: Apps, Aa and Keyboard."; the
  laptop card's hint "Under the buttons: the row of keys, then the trackpad.". A card upright is
  placed against the picture's room (`TourPolicy.place`'s new `room`), so it can stand in the black
  under a short picture with its tail at row 1; the picture's card still lights and centres on the
  picture itself. The layout stays `.phone` for the tour's rule (toggling is no turn).
- **DEBUG:** `-Sill.largerPicture 1` (the switch for one run, as `-Sill.trackpadGestures 0`);
  `-SillVideoSize 848x844` (the mock's frame, so the harness can draw a window fitted to the room);
  `-SillLargerPictureToggle 4,8` (the switch flipped at those seconds, as the panel's does; with the
  panel open it says it waits for the panel to close); `-SillDrawerSearch <text>` (the open drawer
  searches with its field's keyboard up);
  `-SillAXDump <s>` (the screen's accessibility elements in the tree's order, VoiceOver's order
  without VoiceOver, once a private simulator's `ApplicationAccessibilityEnabled` is on); console
  lines `keyboard: up, 320 pt tall, its top at 574 pt in the stream screen; the key row ends 10 pt
  above it, …` and `trackpad: 412×304 pt, vertical span 410.1 pt (Larger Picture: …)` in the
  phone's arrangement, and (rule 12) `larger picture: the switch on, the Desktop streams: the
  standard arrangement` or `…, a window streams: Larger Picture above a 320 pt keyboard` whenever
  the switch, what streams or the outcome changes (nothing while the switch is off); the mock streams
  a window unless `-SillActive desktop|none`.

## Open questions for Noah (the default is taken unless Noah says otherwise)

1. **What the switch gives up.** Default: **the thumbnails' row** (the triage's recommendation).
   The alternative keeps the thumbnails and lets the keyboard cover the rows under it.
2. **The picture's frame.** Default: **the picture's own shape, at the top of its room,** black
   around it (a 16:10 window as today, a taller one taller). Alternatives: the whole room as the
   frame with bars inside it, or the frame centred in the room or against row 1.
3. **The keyboard's height.** Default: **measured heights by the screen's shape and width** (233,
   301, 310, 320), so the layout never moves. Another keyboard (an input method's candidate bar is
   about 44 pt taller, a third-party keyboard) or a future iPhone can cover the key row, never row
   1 (70 pt of margin), whose Keyboard button takes it down. The alternative learns the tallest
   keyboard the device showed and moves the layout once, while the keyboard is up.
4. **The Menus button.** Default: **in row 1 after Apps while the Mac sent menus** (six buttons;
   five before the menus come, a moment after connecting). The alternative keeps six places always.
5. **The iPhone Duo's cover.** Default: **unchanged, the switch hidden on the Duo** (its keyboard
   was never measured). The alternative takes the iPhone's 301 pt there.
6. **Off by default.** The alternative turns it on for new installs.
7. **No fit without Aa.** Default: **a window keeps its shape until Aa sets a text size** (or on the
   virtual display), as everywhere today; #70 decides whether the Mac fits windows by default.
8. **The trackpad's span.** Default: **the picture's own shape** with the switch on. The alternative
   keeps the width ÷ 1.6.
9. **Display Zoom.** Default: **only where it makes the picture larger** (rule 10). Display Zoom
   makes an SE, a 12 or 13 mini and a 6.1-inch iPhone 320 pt wide, where the keyboard rule would
   make the picture smaller (a 6.1-inch one's 304×173 against today's 304×190, the zoomed SE's
   304×163 against 304×188) and six buttons 42 pt: there the layout stays today's and the switch is
   hidden. The 6.7-inch iPhones zoom to 375×812 and the 6.9-inch Pro Max to 402×874, and take it
   with the estimate (310 and 301 pt), which nobody has measured zoomed. The alternatives: measure
   the zoomed keyboards (Display Zoom in a private simulator's Settings) and keep the keyboard rule
   on purpose there (the picture shorter, the key row clear of the keyboard, which today covers
   it), or offer the switch on every iPhone. (This question first covered the zoomed SE alone, with
   the keyboard rule as its default; the review found the 6.1-inch phones and the minis.)
10. **The Apps drawer with Larger Picture.** Default: **above row 1, over the picture's room**
   (rule 8), always, so no keyboard covers it and Apps leaves the keyboard as it is, as everywhere
   else. The review's suggestion was the alternative: under row 1 as today, Apps taking the keyboard
   down while it is open and putting it back after, and the drawer moving above row 1 while a
   keyboard is up or its search field has focus (so it would jump as the field is tapped).
11. **When the switch applies.** Default: **when the Settings panel closes** (rule 11). The
   alternative applies it at once, animated, and scrolls the panel's rows by the room's growth to
   keep the switch under the finger (the panel's height changes by as much, and it can change
   between its scrolling and its fitting forms meanwhile, which resets the scroll).
12. **The Desktop with the switch on.** Noah's decision (2026-10-15, his test on the iPhone 15 Pro):
   **the standard arrangement** (rule 12): Aa never resizes the Desktop, so the room's extra height
   was black under it. Before, the branch gave the Desktop the room too.
13. **Nothing streaming.** Default: **the standard arrangement**, as for the Desktop (rule 12):
   connecting, a window closed until the Desktop the device then asks for, a window off the Mac's
   list for a moment (a Space change), a pick that failed. The Desktop's first picture then arrives
   into the arrangement it keeps. The alternative keeps the last source's arrangement while nothing
   streams: a window back on the Mac's list would come back with no flip, but the Desktop asked for
   once a window has closed could show its first picture in the room and then flip, since its frames
   can reach the device before the window list that names it (the Mac starts the capture, then
   sends the list). The Mac never reports nothing between two windows, so neither choice touches a
   switch from window to window.
14. **The viewport while the Desktop streams.** Default: **the arrangement's picture, the 16:10
   pane**, as everywhere. While Aa is set (or on the virtual display) a window picked from the
   Desktop is fitted twice: to the pane by the pick (the last viewport the Mac has), then to the
   room once the window list reaches the device and the arrangement changes, one restart, as a
   rotation's (Results); a window already at the room's size, picked again after the Desktop,
   shrinks to the pane on the Mac and grows back, and on the device it shows at the pane's size for
   a moment first. The alternative sends the room while the Desktop (or nothing) streams with the
   switch on (a Mac ignores a viewport's size then), so a picked window starts at the room's size,
   with no second fit and no restart; the viewport would then not be the picture on screen.

## Test plan

Hard rules: only this worktree; nothing on Noah's devices, Sill.app, his windows or his keychain;
simulators private (named "Sill larger-picture …"), one at a time, deleted after; `simctl io
screenshot` only (no recording, no XCUITest, no simulator panel); live hosts only `SillHost
--synthetic` with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1`, reached
with `-SillConnect 127.0.0.1:P`, each under a minute and killed by PID; DerivedData in the session's
scratchpad.

| # | Check | Pass when |
|---|---|---|
| H1 | iOS Debug and Release for the generic simulator, Debug for a generic device, `CODE_SIGNING_ALLOWED=NO` | `** BUILD SUCCEEDED **`, only the known `StreamClient` capture warning |
| H2 | `Tests/checks/phone-portrait`: today's 165 unchanged (the standard arrangement's keyboard table with the measured SE and mini); the table above phone by phone (room, rows, trackpad, clearance 10, the trackpad the keyboard's footprint); the estimate (every phone, Display Zoom, the Duo's cover, the switch, the hinge); the frame (16:10, the room's own shape, taller, the Desktop, before a frame, today's arrangement whatever the video); the span; row 1 with six; a grid of widths 300–599, heights to 1,400 and keyboards 233, 301, 310, 320; mutants for each new rule | All pass, every mutant caught |
| H3 | `Tests/checks/tour`: Apps' target, the bar card without thumbnails (targets, rows, VoiceOver rows, hints), the laptop hint, the room's placement (pinned, an oracle, the grid with the Larger Picture screens), mutants | All pass, every mutant caught |
| H4 | `Tests/checks/run-all.sh` | All pass |
| H5 | Harness photos, switch off, at the phone sizes against main's build | Pixel for pixel equal, but for the Settings panel's new row |
| S1 | Harness photos, switch on: 440x894, 402x812, 393x793, 390x797, 375x647 plain, `-SillDrawer 1`, `-SillSettings 1`, `-SillScaleOpen 1`, `-SillVideoSize` a fitted window and a tall one, `-SillTour bar` | Against the table |
| S2 | Live, the normal app with `-Sill.largerPicture 1 -SillKeyboard 1 -SillKeyboardToggle 9` against a synthetic host, on every iPhone size the iOS 27 runtime has a simulator of; `-SillLargerPictureToggle` once | The keyboard's top where the estimate puts it, the key row ≥ 10 pt above it, the photos on the rule, the `viewport:` line the room, the `trackpad:` line's span, one viewport per switch |
| S3 | VoiceOver's order with the strip hidden; the Settings row at accessibility sizes | Apps … Settings, the keys, the trackpad; the row whole |
| R1 | The review: harness photos with the switch on at Display Zoom's 320x645 and 320x548, plain and Settings at its end, against main's build | Pixel for pixel main's (no arrangement, no row) |
| R2 | The review: live, the drawer with the Mac's keyboard up and with its search field's, on the 18 Pro Max, the 15 Pro and the SE; the switch off for comparison | The whole drawer above the keyboard, at the rule's rect |
| R3 | The review: the switch flipped with the Settings panel open (harness and live) | Nothing moves until the panel closes; then one viewport |
| R4 | The review: VoiceOver's order with the drawer open above row 1 | Row 1, then the drawer |
| D1 | Rule 12: `Tests/checks/phone-portrait`: the rule's table; on every phone of the table the Desktop and nothing streaming with the switch on against the switch off (every rect, the viewport, the frames and the spans), a window against Larger Picture; the grid (a window gets the keyboard, the Desktop and nothing none, the switch off none, a hinge none); Noah's numbers; the Duo's cover; mutants of the rule | All pass, every mutant caught |
| D2 | Rule 12: `Tests/checks/tour`: the tour as StreamScreen hands it to the overlay, from the rule: with the switch on, every card of the Desktop's and of nothing's (words, lights, places, under VoiceOver too) against the switch off's, a window's against Larger Picture's; mutants of the rule | All pass, every mutant caught |
| D3 | Rule 12: harness photos on a private iPhone 18 Pro Max simulator, at its own stream screen (`-SillLayout 440x956 -SillSafeArea 62,0,34,0`) and the 15 Pro's (393x793): the switch on against off with the Desktop and with nothing streaming (plain, the drawer, the ruler, the tour's bar card, Settings); a window against the branch's build before the change (af462f7) | The Desktop's and nothing's the switch off's pixel for pixel (Settings: but the switch); a window's the branch's (Settings: but the footnote) |
| D4 | Rule 12, live: the new build against `SillHost --synthetic` (loopback, software encoder), Larger Picture on, Aa at 1× and not set, a test client switching the Mac between the Desktop and a test window of the agent's own (all but invisible, behind every window, never key) | The arrangement and the viewport follow each switch; at most one restart per switch |

**Untested, for Noah (P), on the iPhone 15 Pro:** since rule 12, with the switch on, the Desktop
as with the switch off (the 16:10 picture and the thumbnails, no black under it); a window picked
from the thumbnails or Apps: Larger Picture as the window appears (the thumbnails go), and with Aa
set the window grows into the room once, a moment later; the Desktop again (row 1's Desktop): the
thumbnails back; a window closed on the Mac: the thumbnails back at once, then the Desktop; the
footnote's new words; the switch on and off with Notes and Chrome
streaming (a 16:10 window keeps its shape; Aa then fits it to the taller picture; a taller window
gains; the change shows as Settings closes); the keyboard up and down (the key row stays above it,
nothing moves); windows from Apps and from Menus › Window; Apps with the keyboard up and a search in
it (the whole list above the keyboard); the tour on a fresh install with the switch on; VoiceOver's
order, with the drawer open too; Display Zoom on (Settings › Display & Brightness): no Larger Picture
on a 6.1-inch iPhone; and, on any iPhone with iOS 17 or 18, the keyboard's height (every height here
was measured on iOS 27 simulators).

## Results

2026-10-14 (every simulator private and deleted after; every host `SillHost --synthetic` of this
worktree on 127.0.0.1 alone, on the software encoder, each under a minute and killed by PID; no
device touched). H1 to H4 are the final code's, after the review's fixes; H5 and S1 to S3 were run
on the build the review read, and "The review and its fixes" below has what changed since and its
own runs (R1 to R4).

- **H1, builds:** iOS Debug and Release for the generic simulator (arm64) and Debug for a generic
  device, `CODE_SIGNING_ALLOWED=NO`: `** BUILD SUCCEEDED **`, only the known `StreamClient` capture
  warning (StreamClient.swift:3435, 3430 at main); the Release binary holds none of the DEBUG
  arguments or console lines. `swift build -c release` (nothing of the host changed): built from
  clean in 43 s, only the CaptureProbe warning.
- **H2, `phone-portrait`:** 401 checks (165 at main, unchanged but for the standard arrangement's
  keyboard table, which now has the SE's and the minis' measured keyboards) and 68 of 68 mutants
  (31 at main; M12 and M13 follow the ruler into a function; 28 new with the build, 9 with the
  review's fixes).
- **H3, `tour`:** 111,079 checks (51,840 at main) and 80 of 80 mutants (72 at main, 8 new).
- **H4:** `Tests/checks/run-all.sh`, all 40 passed (6 min, on cfad7f3).
- **H5, nothing else moved:** 33 harness photos on an 18 Pro Max simulator, the switch off, against
  main's build (985a733, from `git archive`): 402x812, 393x793, 390x797, 375x762 and 375x647 plain,
  drawer, ruler, the Desktop, Settings at its end and a thumbnail's lights, 874x402 plain and
  Settings, 710x1000. 25 identical; the 5 lights photos differ by the held thumbnail's wiggle (main
  against itself differs the same way, 11,630 and 7,417 px in that thumbnail); 3 Settings photos by
  a sub-point offset of their last rows (max 21 levels: the panel is one row taller, the new row
  above them out of view). 440x894, drawn as a phone on an iPad simulator (`-SillIdiom phone`):
  plain, drawer, ruler and Settings identical, the lights the wiggle. The viewport lines identical
  (`viewport: 386×241 pt` at 402x812, and so on). With the switch on, the iPhone Duo is main's pixel
  for pixel (the cover with `-SillHinge closed`, its Settings panel, which has no row, and the inner
  display half folded), and so are an iPad's 500x710 window (`-SillIdiom pad`) and a phone on its
  side (874x402); the sideways Settings panel differs by the new row alone.
- **S1, the switch on:** 55 harness photos at the five phone sizes (plain, a window fitted to the
  room with `-SillVideoSize`, one twice as tall as wide, the drawer, Settings, the ruler, no menus,
  the Desktop, the tour's bar, laptop and picture cards) and 440x894 on the iPad. Measured by a tool
  compiled with `PhonePortraitLayout.swift` (each part's four edges: the pixel inside is the part's,
  the one outside the screen's black): the picture's frame, row 1 (five or six), the six caps and the
  trackpad within 1 px at 3x in all 24 photos measured (0 at 402x812, 390x797 and 440x894). The bar
  card stands in the room under a short picture, its tail at row 1 (440x894: card 16,165.5
  360×252.5, tail down at 150); the picture's card rings the picture itself. The Menus pull-down
  opens from row 1 (`-SillMenusOpen 1`).
- **S2, live, the keyboard measured:** the normal app with `-Sill.largerPicture 1 -SillKeyboard 1
  -SillKeyboardToggle 9`, on a simulator of every iPhone size the iOS 27 runtime has (the iOS 27.1
  runtime has only the iPhone Duo). The keyboard as its frame reports it, and where the key row ends:

  | Phone (stream screen) | Keyboard | Key row |
  |---|---|---|
  | 18 Pro Max (440×894) | 320 | 10 pt above it |
  | 15 Pro Max, 16 Plus (430×873) | 320 | 10 above |
  | Air (420×844, its top inset 68) | 320 | 9 under with the first estimate (301); 10 above |
  | 11 Pro Max (414×852), 11 (414×848) | 320 | 9 under with the first estimate; 10 above (the 11) |
  | 18 Pro (402×812), 15 Pro (393×793) | 301 | 10 above |
  | 17e, 16e (390×797) | 301 | 10 above |
  | 12 and 13 mini (375×762) | 310 | 1 above with the first estimate; 10 above (the 13 mini) |
  | 11 Pro (375×768) | 301 | 19 above (planned for the minis' 310) |
  | SE, 3rd generation (375×647) | 233 | 7 under with the first estimate (216); 10 above |

  The first estimate was the portrait plan's table (216 for the SE, 301 for every other phone but
  the Pro Max); the rule now has the measured classes, and every phone re-run after the correction
  ended its key row 10 pt above the keyboard (the 11 Pro 19). Each photo with the keyboard down
  measured 0–1 px off the rule (the minis' 2.88x screens left out); the keyboard's top in the photo
  where the frame put it (636 pt on the 18 Pro Max's screen). The viewport is the room (`viewport:
  424×422 pt` on the Pro Max, 386×359 on the 18 Pro, 377×340 on the 15 Pro, 359×262 on the SE), and
  the span follows the picture (`trackpad: 374×285 pt, vertical span 234.5 pt` for the test
  pattern's 386×242 frame on the 18 Pro). `-SillLargerPictureToggle 4,8` on the Pro Max: one
  viewport per switch (424×265, 424×422, 424×265) and the trackpad 389, 304, 389 pt tall. The
  host logged the device connecting once and leaving once each run.
- **S3, VoiceOver's order and larger text:** with the simulator's app accessibility on
  (`ApplicationAccessibilityEnabled`), `-SillAXDump` lists, with Larger Picture: Open the app list,
  ‹App› menus, Text size, Show the keyboard, Show the full Mac desktop, Settings for ‹Mac›, Escape,
  Tab, Control, Option, Command, Shift, the trackpad's hint (13; the picture none, as before;
  live, without the Mac's menus, 12); with the drawer open, row 1, then the drawer's search field
  and apps; with the switch off, main's order (row 1, the six thumbnails, Menus with main's
  unlabeled element beside it, the caps, the hint). The Settings row at xxxLarge, AX-XL and AX-XXXL
  (the panel stops at xxLarge): whole, its footnote scrolling under the pinned Disconnect.
- **Found:** the SE's keyboard is 233 pt on iOS 27, not 216, so the standard arrangement's SE key
  row is 24 pt under the keyboard (the portrait plan's open question 5 said 7); Larger Picture puts
  it 10 pt above. The phone-portrait check and docs/iphone-portrait-plan.md say so.

### The review and its fixes

An adversarial review of the branch the same day (its head then 0b9db22) re-ran the builds, the
checks and their mutants, the harness against main and live runs, and found five things. Each was
checked against the code first; all five hold, and each theme is a commit of its own.

1. **Should fix, the Apps drawer with the keyboard up** (0b9db22: the drawer under row 1, which
   ends 70 pt above the planned keyboard, so 62 pt of it, its padding and search field, stayed in
   view on every phone; today's arrangement keeps 219 on the Pro Max, 167 on the 15 Pro, 138 on a
   mini, 100 on the SE; Apps never takes the keyboard down, and the drawer's own search field brings
   it up, so a search could not show its results). Fixed in 77abae3 and d6322a9: the drawer opens
   above row 1 (rule 8, open question 10), and VoiceOver reads it after row 1.
2. **Should fix, Display Zoom made the picture smaller** (a 6.1-inch iPhone zoomed, 320×645 under
   its status bar: the room 304×173 against today's 304×190, the Desktop 266×173 against 304×190;
   the check's "larger on every phone but the SE with Display Zoom" passed only because its table
   had no such phone). Fixed in 0e9aa0e: rule 10, open question 9 rewritten for every zoomed phone.
3. **Nit, row 1's six buttons at 320 pt** (42 pt, "Keybo…"): gone with rule 10, which needs six
   buttons of 44 pt; the narrowest phone it applies to has six of 51.2, "Keyboard" whole (the 375x647
   photos). Not done: a Large Content Viewer on the Menus button in row 1. That button is a UIKit
   button whose pull-down is its primary action, in every bar on main as well (the strip's row, the
   landscape bar); how the viewer's long press and the pull-down's press-and-drag would share it
   needs a device, so it is left for Noah.
4. **Nit, the switch moved from under the finger** (118 pt on an 18 Pro, 157 on a Pro Max, with no
   animation; a quick second tap landed on the footnote, or in the gap under row 1, which closes
   the panel). Fixed in 0cbe883: rule 11, open question 11.
5. **Nit, the docs:** the panel's comment (279 pt on the SE with Larger Picture, not 262, which is
   the picture's room), README (a window keeps its shape until Aa sets its text size, or the
   virtual display is on), Untested (Display Zoom, the drawer and its search with the keyboard up,
   keyboards on iOS 17 and 18, the deployment target being 17.0), and the support page (closing,
   minimizing and full screen go with the thumbnails: the app's own menus instead). Fixed in the
   docs commit, with the support page's Display Zoom and "close Settings".

Run after the fixes, on an 18 Pro Max simulator of its own (and an SE's and a 15 Pro's, each
created for its runs and deleted after), against main's build (985a733, from `git archive`):

- **R1, Display Zoom and nothing else moved:** 13 harness photos against main's: 10 pixel for
  pixel identical (the switch on at 320x645 and 320x548, plain, Settings at its end and with the
  Mac's menus; the iPhone Duo's cover and its Settings panel; a phone on its side; the switch off
  at 402x812 and 375x647 with the drawer); 2 differ only in the simulator's own home indicator,
  outside the drawn screen (the switch off at 402x812, and Settings sideways); 1 only in the
  Settings panel's scroll indicator, shorter by the new row (the switch off, Settings at its end).
- **R2, the drawer with the keyboard up:** live, the switch on, `-SillKeyboard 1 -SillDrawer 1`
  and `-SillDrawer 1 -SillDrawerSearch Go` (its field's keyboard): on the 18 Pro Max, the 15 Pro and
  the SE the whole drawer above the keyboard, its edges where the rule puts them to the pixel (the
  SE: 28 to 306 pt on the screen, row 1 from 314; the 15 Pro: 67 to 423, row 1 from 431), the search
  results in view ("Google Chrome", "Gotham Sports"). The search field's keyboard is taller than the
  Mac's by its suggestions bar (347 pt on the Pro Max, 328 on the 15 Pro, 260 on the SE), so it
  covers the key row by 17 pt then, dimmed under the drawer, and leaves row 1 43 pt clear. The
  switch off: today's drawer under row 1, the second result under the keyboard, as on main. Harness
  photos of the drawer at 402x812, 375x647 and 375x762, measured: 0 px off the rule.
- **R3, the switch with Settings open:** the harness at 402x812 (`-SillSettings 1
  -SillSettingsScroll gestures -SillLargerPictureToggle 5`, the review's own case): the photos at 4
  and 8 s differ only in the switch (12,428 px within 63×28 pt), no new viewport. Live on the Pro Max
  (`-SillSettings 1 -SillLargerPictureToggle 4 -SillKeyboardToggle 9`): "Larger Picture switched on
  at 4 s; the Settings panel is open, so it applies when the panel closes", row 1 and the panel at
  the same pixels at 3 and 6 s, then the panel closing at 9 s with one viewport, 424×422, and the
  key row 10 pt above the keyboard.
- **R4, VoiceOver's order with the drawer open:** `-SillAXDump`, the switch on: Close the app list,
  Text size, Show the keyboard, Show the full Mac desktop, Settings, then the drawer's search field,
  its two headers and its 119 rows. (Before `AfterRow1` the tree put the drawer's 123 elements first, row 1 after.)
  The switch off: main's order, row 1 then the drawer; the switch on with nothing open: as in S3.

### The Desktop keeps the standard arrangement (Noah's test, 2026-10-15)

Noah, on his iPhone 15 Pro: "Larger Picture seems to work properly. However, when in Desktop mode,
there is negative space on the bottom, seemingly because of the Mac aspect ratio. Can we disable this
feature when Desktop mode is active?" The Desktop is the Mac's display, 1.54:1 on a 14-inch MacBook
Pro, and Aa never resizes it, so in the room it stayed at its own shape with black under it (377×244
in 377×340 on the 15 Pro, 96 pt; 424×275 in 424×422 on the Pro Max, 147 pt). Now rule 12: Larger
Picture is in effect only while a window streams, one pure function of the switch and of what
streams (`PhonePortraitLayout.largerPicture(switchOn:streaming:)`) that StreamScreen puts in front
of `keyboard(for:largerPicture:foldable:)`, so the arrangement, its viewport and the tour's targets,
words and room all follow it; nothing streaming keeps the standard arrangement too (open question
13); the Settings panel holds the arrangement itself while it is open (rule 11), and its footnote
says the switch is for a window's picture. The iPhone Duo's cover is as the branch left it (no
keyboard on a hinge, whatever streams). Device only, as before. Run on 2026-10-15 (the simulator
private, "Sill larger-picture desktop", an iPhone 18 Pro Max on iOS 27.0, deleted after; every host
`SillHost --synthetic` of this worktree on 127.0.0.1 alone and on the software encoder, killed by
PID; Noah's iPhone was streaming from Sill.app over the cable meanwhile, so nothing used the
hardware encoder):

- **D1, `phone-portrait`:** 484 checks (401 before; among the new, the rule's table, every phone of
  the table with the switch on against off for the Desktop and for nothing streaming, every rect,
  the viewport, the frames for six shapes and the spans, a window against Larger Picture, Noah's
  numbers, the Duo's cover, and a grid rule over the 285,150 sizes) and 73 of 73 mutants (68 before;
  5 of the rule: the Desktop with Larger Picture, nothing streaming with it, what streams ignored,
  the switch ignored while a window streams, the rule turned around).
- **D2, `tour`:** 111,189 checks (111,079 before: on six phones the tour as StreamScreen hands it,
  composed from the rule, every card's words, lights and places at three heights, under VoiceOver
  too) and 84 of 84 mutants (80 before; 4 of the rule in PhonePortraitLayout.swift, which the check
  compiles: the Desktop's tour about Apps, nothing's, what streams ignored, the switch ignored).
- **H1 and H4 again:** iOS Debug and Release for the generic simulator and Debug for a generic
  device, `CODE_SIGNING_ALLOWED=NO`: `** BUILD SUCCEEDED **`, only the known `StreamClient` capture
  warning (StreamClient.swift:3436); the Release binary holds the new footnote and none of the DEBUG
  lines (the new `larger picture:` line included). `Tests/checks/run-all.sh`: all 40 passed (6 min).
- **D3, harness photos** (36 of the new build, 16 of the branch's before the change, af462f7 from
  `git archive`; the 18 Pro Max's own stream screen, `-SillLayout 440x956 -SillSafeArea 62,0,34,0`,
  its console's `trackpad: 412×389 pt`, and the 15 Pro's, `-SillLayout 393x793`):
  - The Desktop with the switch on against off, both sizes: plain, the drawer, the Aa ruler and the
    tour's bar card pixel for pixel identical; the Settings panel (at This iPhone) only in the switch
    itself, 12,428 px within 63×28 pt (the review's R3 measured the same).
  - Nothing streaming, the switch on against off: identical. The Desktop with the switch on against
    the branch's with it off: identical, so the standard arrangement is the branch's (and main's).
  - A window with the switch on against the branch's: plain, the drawer, the ruler and the tour's
    bar card identical at both sizes; the Settings panel only from the footnote down (its words; on
    the Pro Max it is a line longer, seven against six).
  - The branch's Desktop with the switch on, Noah's finding: the Desktop's frame at the top of the
    room, the black under it, which the new build no longer draws.
- **D4, live** (the normal app with `-SillConnect 127.0.0.1:P -Sill.largerPicture 1`, the 18 Pro Max;
  a test window of the agent's own, 1 % opaque, ignoring clicks, behind every window and refusing to
  be raised or made key; `sillclient.py` picking it, the Desktop, it and the Desktop 4, 12, 20 and
  28 s in). With Aa at 1× (`-SillScaleOpen 1 -SillScale 1`), the device's console: `larger picture:
  the switch on, nothing streams: the standard arrangement` and `viewport: 424×265 pt` as it
  connected; the Desktop: the standard arrangement, 424×265; each pick of the window: `larger
  picture: the switch on, a window streams: Larger Picture above a 320 pt keyboard`, then
  `viewport: 424×422 pt, scale 1, 60 fps`; each return to the Desktop: the standard arrangement,
  `viewport: 424×265 pt`. The host: the first pick "Resized testwindow to 424×265 pt (asked 424×265
  for a 424×265 panel at 1.0×)", streaming at 800×532 (the capture read the window's size from
  before the resize, the lag the virtual display's notes describe), then the room's "Resized
  testwindow to 424×422 pt (asked 424×422 for a 424×422 panel at 1.0×)" and one restart, streaming
  at 424×422; the Desktop "Streaming a synthetic test pattern", its 424×265 viewport changing nothing
  (a Mac ignores a viewport's size while the Desktop streams); the second pick resized to 424×265 and
  to 424×422 again, no restart (its capture had started at the room's size). So one restart at most
  per switch, as a rotation's. With Aa not set: no resize and no restart, the viewport still
  following the arrangement (424×422 with the window, 424×265 with the Desktop) and the window at its
  own shape (424×281 in the room). One test client and the device connected once and left once.
- **The lights:** a thumbnail's lights hang from the strip, so with the arrangement now changing by
  itself (what streams) they would have stayed open unseen in Larger Picture and come back with the
  strip; they now close when the arrangement changes (StreamScreen). The harness with a window,
  `-SillWindowMenu 1 -SillLargerPictureToggle 4,8` on a second private simulator (deleted after):
  "lights: closed, the phone's arrangement changed under them" at the 4 s switch. Five photos of
  this final build (the Desktop and a window, both sizes, the tour's card, the drawer) are pixel for
  pixel the ones above.
- **Found:** with Aa set, a window picked from the Desktop is fitted twice (the 16:10 pane by the
  pick, the room once the arrangement changes), and the agent's window, already at the room's size
  on the second pick, shrank to 424×265 and grew back to 424×422: open question 14 has the
  alternative. Each switch sends the same viewport twice, 0.25 s apart (StreamScreen's repeat when
  the source changes, then the arrangement's own); the Mac's 2 pt compare makes the second a no-op.

**Not verified here:** a real window fitted to the room (a synthetic host's Desktop is never
resized; the harness drew it with `-SillVideoSize`; the live run fitted the agent's own test window,
whose picture is all but transparent); a device's own keyboard (only simulators were
measured, and only iOS 27's), input methods with a candidate bar, third-party keyboards and Display
Zoom's keyboards; VoiceOver itself (the dump is the tree's order); the tour on a fresh install on a
device; a real iPhone Duo; the Menus button's Large Content Viewer (the review's third finding);
the Desktop and a window switching on a device with Noah's own windows.

## Progress

- 2026-10-14: the plan (22055ed); the layout and its check (d0343a2); the tour and its check
  (812d7df); the keyboards measured and the estimate corrected (0444d80); the views, Settings and
  the DEBUG arguments (127f5ec); the docs and these results (a251edf). Simulators deleted; photos
  in `~/Downloads/sill-handoff/larger-picture/` (harness and live). PR #79 opened, left for Noah.
- 2026-10-14, the review's fixes: Larger Picture only where it is larger, and the panel's switch
  only there (0e9aa0e); the drawer above row 1 (77abae3) and read after it by VoiceOver (d6322a9);
  the switch applying as Settings closes (0cbe883); the docs, these results and the review's section
  (cfad7f3, and this line). Simulators deleted; the review's photos in
  `~/Downloads/sill-handoff/larger-picture/review-fixes/`. PR #79's body updated; left for Noah.
- 2026-10-15, Noah's test on his iPhone 15 Pro (the Desktop's negative space): Larger Picture only
  while a window streams (rule 12, open questions 12 to 14, the Results' "The Desktop keeps the
  standard arrangement"), the checks and their mutants, the docs and the support page, in one commit.
  The simulator deleted; the photos and the live run's logs in
  `~/Downloads/sill-handoff/larger-picture/desktop/`. PR #79's body updated; left for Noah.
