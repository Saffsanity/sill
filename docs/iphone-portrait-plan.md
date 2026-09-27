# The iPhone's portrait layout — the plan

2026-09-27. Branch `iphone-portrait` (worktree `/Users/noah/Downloads/winstream-iphone-portrait`)
from origin/main at cf05a78; line numbers are at cf05a78. Written from a read-only survey of
`PortraitStreamScreen.swift`, `StreamScreen.swift`, `TrackpadView.swift`, `InputOverlay.swift`,
`HEVCDisplayView.swift`, `StreamClient+Viewport.swift`, `HostSettingsPanel.swift` and the harness
contract in `ContentView.swift`, and of the open branches that touch this screen. Nothing of the
app was built or run. The tables come from a scratch Swift prototype of the rules below (not
committed), which also held them at every width from 300 to 599 pt and every height to 1,400.
Screen sizes are the iOS 27 simulator's device profiles; the top insets and keyboard heights are
the usual ones, marked where assumed, and S2 measures them.

**Noah's request and approvals (2026-09-27, as the workflow relayed them):**
1. "Sill for iPhone specifically needs some tweaks in portrait mode. I would get rid of the arrow
   keys and spotlight button, and move the keyboard button up to the top row with
   Aa/Desktop/Settings. Then, I would move the window sill down a level (below search and the stuff
   I described, but above esc/tab/ctrl/opt/cmd/shift). The reason I want to do this is because
   when you open the keyboard it covers the keyboard button so it can't be dismissed. I would also
   make the trackpad area larger as the top window tends to be 16:9 or 16:10 so instead of black
   bars we can push it higher on the screen and have more mouse space. ... If I approve, we will
   detect iPhones and change the portrait layout. Landscape stays the same."
2. "The proposal looks good to me, approved"
3. "I don't want the trackpad and buttons to move to different spots for 16:9 vs 16:10. Please just
   use black bars on 16:9. Approved"
4. "The top row icons should be widened so that there is similar whitespace between buttons to the
   command row"

**Reading of it.**
- **Today** every iPhone held upright gets the Duo's outer-display layout
  (`DuoLayout.outerPortrait`, StreamScreen.swift:56-60, drawn with `PortraitMetrics.compact`,
  PortraitStreamScreen.swift:120-126): the picture in the top half, then the window bar, the key
  row folded into two (the arrows, the keyboard cap and Spotlight in the second), the trackpad. The
  software keyboard covers the keyboard cap: StreamScreen ignores the keyboard's safe area
  (StreamScreen.swift:169), so nothing moves up. On an 18 Pro Max the key rows sit at 591–687 pt
  on the screen and the keyboard's top is near 610.
- **The half is taller than the picture needs.** A 16:10 window fills 424×265 of the Pro Max's
  424×431 pane, with 83 pt of black above and below it.
- **The change, upright on a phone only:** the picture in a fixed 16:10 pane at the top; row 1
  Apps, Aa, Keyboard, Desktop, Settings, widened to the row; row 2 the thumbnails; row 3 esc, tab,
  ctrl, opt, cmd, shift; the trackpad takes the rest. Landscape, the iPad and the Duo's inner
  display stay as they are. No wire change.

---

## Decision

### In one paragraph

`PortraitStreamScreen` gains a second arrangement, the phone's, for an iPhone held upright
(`.outerPortrait` on an iPhone: taller than wide, narrower than 600 pt), the Duo's outer display
included; an iPad window of that shape keeps today's compact halves (the review; open question 1).
Every rect in it comes from a new pure file, `PhonePortraitLayout.swift`, a function of the stream
screen's size alone, checked with swiftc in `Tests/checks/phone-portrait` with mutants. The picture
keeps the same `StreamView` and `InputOverlay` (so the keyboard's first responder, the letterbox
mapping and the client-drawn pointer are untouched) in a pane that never changes size with the
window; the viewport sends that pane, so Aa and the virtual display shape Mac windows to 16:10.
Row 1 holds the Keyboard button, which the keyboard never covers on any phone. The key row loses
its arrows, Spotlight and keyboard cap there. The drawer and the Settings panel hang from under row
1 across its span, and row 1 stays live, as the landscape bar does. The trackpad's vertical motion
is measured against its width ÷ 1.6, so the extra height is extra room, not a slower pointer.

### The layout

The iPhone 18 Pro (402×874 pt, top inset 62; the stream screen's container is 402×812):

```
   y ┌───────────────────────────────────────────────────┐  above it: the top inset
   8 │ ┌───────────────────────────────────────────────┐ │
     │ │ the picture, 386×241 (16:10, fixed)           │ │  16:9: black bars above and below
 249 │ └───────────────────────────────────────────────┘ │
 273 │ [ Apps ] [  Aa  ] [Keyboard] [Desktop] [Settings] │  row 1: five 68.4×50, 8 apart, in a 62 pt band
 339 │ [=] [=] [=] [=] [=]  the thumbnails, scrolling  › │  row 2: the strip, 62 tall
 411 │ [ esc ] [ tab ] [ ctrl ] [ opt ] [ cmd ] [shift]  │  row 3: six 55.7×44, 8 apart
 465 │ ┌───────────────────────────────────────────────┐ │
     │ │ the trackpad, 374×331 (today 202)             │ │  under the keyboard when it is up
 796 │ └───────────────────────────────────────────────┘ │
 812 └───────────────────────────────────────────────────┘  16 pt, then the screen's edge
```

| Phone (screen, top inset) | Container | Picture | Row 1 (button) | Row 2 | Row 3 (cap) | Trackpad (today) | Panel room (today) |
|---|---|---|---|---|---|---|---|
| 18 Pro Max (440×956, 62) | 440×894 | 424×265 | 297–347 (76) | 363–425 | 435–479 (62) | 412×389 (243) | 523 (351) |
| 18 Pro, 17 (402×874, 62) | 402×812 | 386×241 | 273–323 (68.4) | 339–401 | 411–455 (55.7) | 374×331 (202) | 465 (310) |
| 15 Pro, Noah's (393×852, 59) | 393×793 | 377×235 | 267–317 (66.6) | 333–395 | 405–449 (54.2) | 365×318 (192) | 452 (300) |
| 17e (390×844, 47) | 390×797 | 374×233 | 265–315 (66) | 331–393 | 403–447 (53.7) | 362×324 (194) | 458 (302) |
| 13 mini (375×812, 50) | 375×762 | 359×224 | 256–306 (63) | 322–384 | 394–438 (51.2) | 347×298 (177) | 432 (285) |
| SE 3rd gen (375×667, 20) | 375×647 | 359×224 | 256–306 (63) | 322–384 | 394–438 (51.2) | 347×183 (119) | 317 (227) |
| Duo outer (500×710, the harness) | 500×710 | 484×302 | 334–384 (88) | 400–462 | 472–516 (72) | 472×168 (151) | 302 (259) |

y is from the container's top. The vertical rhythm is the approved mockup's, whose trackpads (389
and 331 on the two Pros) these are: row 1's 50 pt buttons centred in a 62 pt band, as the compact
window bar holds its own, so 24 pt from the picture to the buttons and 22 from them to the
thumbnails; then 10 pt to the key row and 10 to the trackpad, and 16 at the bottom, the compact
halves' gaps. (The first build dropped the band, 12 pt higher and trackpads of 401 and 343, and
called that today's gaps; the review put the mockup back: Review fixes.)

### The rules (`PhonePortraitLayout`, pure)

Its input is the size `StreamScreen`'s GeometryReader measures: the screen less its top safe-area
inset (the status bar, the Dynamic Island), down to the screen's bottom edge, since the stream
screen ignores the bottom inset (StreamScreen.swift:169) and the trackpad keeps today's 16 pt off
the edge. An iPhone upright has no side insets. So the safe area enters once, as the container; the
check's device table turns a screen and its inset into one. W × H is that size.

1. **The picture:** x 8, y 8, width W − 16, height ⌊(W − 16) ÷ 1.6⌋: whole points, never taller
   than 16:10. Only when that would leave the trackpad under 120 pt does the picture give way, to
   H − 240 − 120 (never below 0); 240 pt is everything else. Only the shortest phone is that
   short, and only just: an iPhone SE with Display Zoom (320×548 under its status bar), whose
   picture is 188 pt, 2 short of 16:10.
2. **Row 1:** a 62 pt band 18 pt under the picture (its 8 pt margin and the controls' 10), its
   50 pt buttons centred in it, so 24 pt under the picture, from 14 to W − 14; five buttons of
   (W − 60) ÷ 5, 8 apart: Apps, Aa, Keyboard, Desktop, Settings.
3. **Row 2, the strip:** 10 under row 1's band (16 under its buttons), 62 tall (50 pt thumbnails
   and 6 above and below for the badge and the halo, so 22 pt from the buttons to the thumbnails),
   from 6 to W − 6. `WindowStrip` pads its thumbnails 8 pt, so the first one lines up with Apps and
   esc at 14.
4. **Row 3:** 10 under, 44 tall, six caps of (W − 68) ÷ 6, 8 apart.
5. **The trackpad:** 10 under, from 14 to W − 14, down to H − 16. Its vertical span (below) is
   its width ÷ 1.6.
6. **The Aa ruler:** centred on Aa over row 1, 50 tall, 4 × step + 60 wide (TextScaleControl's
   `sliderWidth`, StreamScreen.swift:568), with step = min(36, ((Aa's midX − 14) × 2 − 60) ÷ 4), so
   it never passes the row's leading edge: 36 on every phone, 34 at 360 pt, 28 at 320.
7. **The drawer** and **the Settings panel** both across row 1's span, from x 14 to W − 14 (Apps'
   leading edge to Settings' trailing one), from row 1's bottom + 8 to H − 16. The panel's
   transition anchor is its top-trailing corner as fractions of the container, as today
   (PortraitStreamScreen.swift:205).
8. **The dim and the tap catcher:** the container but row 1's buttons, as two rects: (0, 0, W,
   row 1's top) and (0, row 1's bottom, W, the rest).

```swift
struct PhonePortraitLayout: Equatable {          // CoreGraphics only
    static let margin: CGFloat = 8, aspect: CGFloat = 1.6, underPicture: CGFloat = 10, band: CGFloat = 6
    static let side: CGFloat = 14, bottom: CGFloat = 16, rowGap: CGFloat = 10, gap: CGFloat = 8
    static let buttonHeight: CGFloat = 50, stripHeight: CGFloat = 62, stripInset: CGFloat = 8
    static let capHeight: CGFloat = 44, minTrackpad: CGFloat = 120, panelGap: CGFloat = 8
    static let maxRulerStep: CGFloat = 36, rulerInset: CGFloat = 30      // TextScaleControl's
    enum Button: Int, CaseIterable { case apps, textSize, keyboard, desktop, settings }

    let size: CGSize
    let picture, row1, strip, keys, trackpad, ruler, drawer, settings: CGRect
    let buttons: [CGRect]            // in Button order
    let caps: [CGRect]               // esc, tab, ctrl, opt, cmd, shift
    let rulerStep: CGFloat
    let trackpadSpan: CGFloat        // what the pad's vertical motion is measured against
    let settingsAnchor: CGPoint      // the panel's top-trailing corner, as fractions of size
    let dim: [CGRect]                // everything but row 1's buttons
    init(size: CGSize)
}
```

### Detection

`DuoLayout.of` (StreamScreen.swift:56-60) is unchanged: `.outerPortrait` for a stream screen
taller than wide and narrower than 600 pt. On an iPhone that case now draws the phone arrangement:
every iPhone upright (375–440 pt wide, 320 with Display Zoom) and the Duo's outer display upright
(500×710). An iPad window narrower than 600 pt held upright (Slide Over, a narrow Split View or
Stage Manager window) is `.outerPortrait` too and keeps what it has today, the compact halves:
Noah's words were "detect iPhones", and the iPad was to stay as it is (the review; open question
1). The Duo's inner display (710×1000) and the iPad full screen stay `.innerPortrait`, today's
halves; every landscape size stays landscape. The layout reads the device's idiom in one place,
`DuoLayout.phoneArrangement`; everything else is still decided by size.

- **In code:** `PortraitMetrics` gains `phone: Bool` and a third set, `.phone`, with `.compact`'s
  styles (radii, symbol and thumbnail sizes, the badge, the fade) and `PhonePortraitLayout`'s
  paddings, gaps and heights, so each number is written once. `.compact` stays as it is for the
  iPad's compact halves, the key row's fold into two rows included. `StreamScreen`'s switch draws
  `portrait(metrics: DuoLayout.phoneArrangement ? .phone : .compact)` for `.outerPortrait`
  (StreamScreen.swift:132-133); `PortraitStreamScreen` draws `metrics.phone ? phone : halves`.
  DEBUG `-SillIdiom pad` (or `phone`) swaps the idiom, so the harness photographs an iPad window's
  arrangement on an iPhone simulator.
- **The Duo's outer display is Noah's call to reverse** (as asked). Reversing it is a width test in
  that switch: 480 pt and wider draws `.compact`, the halves (phones are at most 440).

### The picture and the viewport

- The pane is the picture's rect, holding the same `StreamView` and `InputOverlay` as today
  (PortraitStreamScreen.swift:216-233), with the same background, 12 pt corners and stroke.
- **Black bars** come from the display layer's `.resizeAspect` (HEVCDisplayView.swift:65), and the
  input overlay already maps touches through the letterbox (`videoRect`, HEVCDisplayView.swift:53).
  The pane's size depends on the container only, so nothing below it moves when the source's shape
  changes.
- **The viewport:** the pane is measured with `onGeometryChange` as today (:231) and reported
  through `onPanelSize`, so `StreamScreen.sendViewport` (StreamScreen.swift:205-218) sends 386×241
  on the Pro. The host fits a streamed window to it once Aa has been used (`fitToViewport` needs a
  scale) and the virtual display always does, so both come out 16:10. It changes only with the
  container (rotation), never with the keyboard.
- `HEVCDisplayView`, `InputOverlay`, `StreamClient+Viewport` and `StreamClient` do not change.

### Row 1 and the Aa ruler

- **Row 1** is landscape's bar in landscape's order (StreamScreen.swift:431-470): `BarButton`s at
  the rule's width and 50 pt, radius 14, a 20 pt symbol over its 11 pt label, centred. The labels
  stay on one line and may shrink to 85 % before they would wrap (with Bold Text, 320 pt wide).
  Each symbol sits in a 24 pt box, and Aa's text in the same box with the same 3 pt under it, so
  the five labels share one line (the keyboard glyph is 15 pt tall and the gear 21: without the
  box "Keyboard" rode 2.7 pt and Aa's value 1.7 pt above the other three). The row does not grow
  with the text size, so at the accessibility sizes a long press on a button shows it large (the
  Large Content Viewer), as on a tab bar; not on Aa, whose drag starts at touch-down.
- **Keyboard** is landscape's button: "keyboard", "Keyboard", lit while the keyboard is up, "Show
  the keyboard" or "Hide the keyboard", and its action `setSettings(false, false)` then
  `overlay.toggleKeyboard()` (StreamScreen.swift:452-456).
- **The ruler** is `TextScaleControl` with the button's size and `pointsPerStep: rulerStep`: it
  unfolds over row 1, centred on Aa, and Apps, Keyboard, Desktop and Settings fade out and take no
  touch until it folds (the portrait bar faded the strip, Desktop and Settings,
  PortraitStreamScreen.swift:271-289). Its live value, the only readout of the value being chosen,
  sits as it does in the 58 pt bars, 1 pt above the ruler's frame with its digits 2 pt inside:
  in a 50 pt ruler it sat 5 pt above and lost the top 2 pt of its digits to the clip, in the
  compact halves' window bar too, which the same line fixes.

### Rows 2 and 3

- **Row 2** is `WindowStrip` at the compact sizes (80×50 thumbnails, radius 8, 12 apart, pad 6,
  badge 22, fade 0.88), full width. Hold, the traffic lights, drag and reorder are as they are. On
  a phone the lights always open below the strip, over the key row, which has room on every phone
  (on the SE they reach down to the trackpad's top edge). The midpoint rule (StreamScreen.swift:889,
  the side of the thumbnail with more room) put them above it, over Apps, Aa and Keyboard, on the
  SE and at 500×710 and below it everywhere else (the review); the halves and landscape keep it.
  With the keyboard up on an SE, the menu's three lights stay above a 216 pt keyboard and their
  words go partly under it; on the Duo's outer display a phone-sized keyboard covers the strip
  itself.
- **Row 3** is `KeyRow` with a key set: `.full` (the halves: today's twelve, Spotlight only while
  the Desktop streams, one row) or `.phone` (esc, tab, ctrl, opt, cmd, shift). The caps, the latch
  and `press` are unchanged (PortraitStreamScreen.swift:383-457).
- **What goes on the phone:** the four arrows, Spotlight and the keyboard cap. Spotlight is still
  there: latch cmd, then space on the keyboard (`insertText` sends ⌘Space,
  InputOverlay.swift:299-305). Arrows come from a hardware keyboard only.

### The trackpad

- `Trackpad` at the rule's rect, as today otherwise (TrackpadView.swift:11-44).
- **Its speed.** The pad maps a finger's travel to fractions of the frame: `dx / width` and
  `dy / height`, times 1.25 for the pointer (TrackpadView.swift:212-221), and the same fractions for
  two-finger scrolling (:313-314) and its coast (:356-361). A taller pad would make vertical motion
  about 40 % slower per point on the Pros, and turn a diagonal stroke flatter. So `TrackpadSurface`
  gains `verticalSpan: CGFloat?` (nil: its height, as today) and the phone passes `trackpadSpan`,
  the width ÷ 1.6: vertical motion then matches horizontal on a 16:10 picture, whatever the pad's
  height. Per point, vertical is 6 % (Pro Max) to 14 % (Pro) under today's, horizontal is
  unchanged, and a stroke down the Pro Max's pad crosses nearly two frame heights. The halves pass
  nil (open question 3).

### The drawer, the Settings panel and the dim

- Both hang from 8 pt under row 1 (rule 7), so the button that opened them stays in view and in
  reach: row 1 stays live and undimmed while they are open, as the landscape bar does
  (StreamScreen.swift:338-373). As in landscape, Apps closes the panel and opens or closes the
  drawer, Settings closes the drawer and opens or closes the panel, and Keyboard closes the panel
  and shows or hides the keyboard.
- Both span row 1, Apps' leading edge to Settings' trailing one, on every phone, so their edges
  sit on the row's grid and nothing cut shows beside them (at 380 and 360 pt wide the drawer ended
  inside Settings and the panel began inside Apps, with slivers of thumbnails, esc and the pad's
  hint beside them). The strip hides while either is open: its first thumbnail's badge sticks out
  6 pt past the row's leading edge.
- **The dim** (the drawer's, black 0.58) and **the clear tap catcher** (the panel's) are the rule's
  two rects: a tap on the picture or below row 1 closes them and never reaches the Mac. The Settings
  panel has no dim, so the picture above stays in view while a setting changes.
- **Room:** the drawer and the panel get 317–523 pt of height on phones (227–351 today) and 302 at
  500×710. The panel's shortest room is still the compact halves' 259 pt at 500×710, now an iPad
  window that narrow (the Duo's outer display had it until now), then 275 pt on an SE on its side,
  which `HostSettingsPanel`'s three "259 pt" comments (:13, :220, :262) say.

### The keyboard

With the keyboard up, row 1 is clear of it on every phone, so Keyboard dismisses it; rows 2 and 3
clear it too on every phone but the SE, whose key row a 216 pt keyboard covers by 7 pt (open
question 5). Screen coordinates, the keyboard as the input view shows it: autocorrection is off,
so it has no suggestions bar. Measured on the iOS 27 simulators on 2026-09-27 (S2): 320 pt on the
18 Pro Max, 301 on the 18 Pro and on the 17e; the 15 Pro and the 13 mini taken as the 18 Pro's,
the SE as the classic 216. (This plan first assumed keyboards with a suggestions bar, 346, 336 and
260, which put row 3 under the keyboard on the mini and the SE.)

| Phone | Keyboard's top | Row 1 ends | Row 2 ends | Row 3 ends |
|---|---|---|---|---|
| 18 Pro Max | 636 (measured) | 409 | 487 | 541 (95 clear) |
| 18 Pro, 17 | 573 (measured) | 385 | 463 | 517 (56 clear) |
| 15 Pro | 551 | 376 | 454 | 508 (43 clear) |
| 17e | 543 (measured) | 362 | 440 | 494 (49 clear) |
| 13 mini | 511 | 356 | 434 | 488 (23 clear) |
| SE 3rd gen | 451 | 326 | 404 | 458 (7 under) |
| Duo outer (500×710, the harness) | unknown | 384 | 462 | 516 |

On the Duo's outer display (its keyboard unknown) row 1 is clear of a keyboard up to 326 pt tall,
but rows 2 and 3 only of one under 248 and 194 pt, and no iPhone keyboard is under 216: there only
row 1 stays above it (a 320 pt keyboard, the 18 Pro Max's, leaves it 6 pt), so a modifier is
latched before the keyboard comes up. A keyboard with a candidate bar (an input method's, about
44 pt more) can reach the key row on the SE, the mini and, by a point, the 15 Pro; row 1 stays
clear on every phone. A latch set before the keyboard comes up is spent by the next typed key, as
today (open question 5). The trackpad is under the keyboard on every phone. The layout never
moves for the keyboard.

### VoiceOver and larger text

- **Order:** the phone arrangement places its five parts (picture, row 1, strip, key row,
  trackpad) with a small `Layout` that puts each subview at its rule's rect, declared in reading
  order: Apps, Text size, Keyboard, Desktop, Settings; the thumbnails ("‹App› window: ‹title›",
  with their actions); Escape, Tab, Control, Option, Command, Shift; the trackpad's hint. The
  picture is no accessibility element, as today. The drawer comes after the rows; the Settings
  panel stays modal (HostSettingsPanel.swift:66-68). Labels and hints are today's.
- **With the drawer open** VoiceOver skips what its dim covers (the picture, the strip, the key
  row, the trackpad): row 1, then the drawer. Otherwise it went through the dimmed thumbnails,
  caps and hint first, and a double-tap on a dimmed cap ran its action (esc to the Mac) where a
  tap on the same spot only closes the drawer.
- **Larger text:** the rows, labels and caps have fixed sizes, as the bars and caps have today, so
  the geometry is the same at every text size. At the accessibility sizes a long press on a row 1
  button (but Aa) or a cap shows it large, the Large Content Viewer. The drawer's rows are fixed
  too. The Settings panel follows the text size up to xxLarge (HostSettingsPanel.swift:63) in its
  taller room.

---

## Files

| File | Change |
|---|---|
| `iOSClient/PhonePortraitLayout.swift` (new; pure, CoreGraphics only) | The rules above. pbxproj IDs `A1000001000000000000A501` / `…F501` (main uses A001–A01E, A101, A201; open branches A020, A301, A401–A402) |
| `iOSClient/PortraitStreamScreen.swift` | The phone arrangement; `PortraitMetrics.phone` and `.phone`, beside `.compact` (the iPad's halves); `KeyRow`'s key sets; the picture pane, the trackpad, the drawer and the panel each built once for both arrangements, which place them; row 1's icon box and large content |
| `iOSClient/TrackpadView.swift` | `verticalSpan` on `Trackpad`, `TrackpadView` and `TrackpadSurface` (three lines of arithmetic) |
| `iOSClient/StreamScreen.swift` | `DuoLayout`'s doc comment and `phoneArrangement` (the idiom, the one place the layout reads it); the lights below the strip on a phone; `TextScaleControl`'s icon box and its value inside a 50 pt ruler; the DEBUG hooks below |
| `iOSClient/ContentView.swift` | The harness: screens larger than the simulator; the contract comment |
| `iOSClient/HostSettingsPanel.swift` | Comments only (the room) |
| `iOSClient/Sill.xcodeproj/project.pbxproj` | The new file's four entries, by hand |
| `Tests/checks/phone-portrait/` (new) | `main.swift`, `run.sh`, `mutants.py` (H2) |
| `Tests/checks/README.md`, `.github/workflows/ci.yml` | The check's row; `phone-portrait` in the mutants matrix (ci.yml:122) |

Nothing in `Sources/`, `Packaging/`, `Scripts/`, `Info.plist` or `PrivacyInfo.xcprivacy`. Swift 5
language mode, iOS 17 APIs (`Layout` is iOS 16).

## DEBUG and the harness

- **Larger than the simulator:** a fake screen that fits neither upright nor turned is drawn scaled
  down to fit (`scaleEffect`; layout sizes are unchanged), and the console says so ("harness:
  710x1000 drawn at 0.62"). So the Duo's and the iPad's sizes can be photographed on the iPhone
  simulators this work may use.
- **`-SillKeyboard 1`** now makes the input view first responder once the stream screen shows, in
  the harness, under `-SillLive 1` and in the normal app with `-SillConnect`, so the software
  keyboard really comes up; until now it only lit the button (ContentView.swift:66 promised more).
  In the harness a keyboard still upsets the fake screen (CLAUDE.md, iPad host settings, "Known"),
  so keyboard photos come from the normal app (S2).
- **`-SillKeyboardToggle <s>`:** `<s>` seconds after the stream screen shows, the keyboard toggles
  as the Keyboard control does (`InputOverlayProxy.toggleKeyboard`). A stand-in for a tap; the gates
  may not drive the UI.
- **Console:** `viewport: 386×241 pt, scale none, 60 fps` for each viewport `StreamScreen` sends.
- **`-SillIdiom pad`** (the review): a screen taller than wide and narrower than 600 pt is drawn as
  an iPad draws it, the compact halves, so H4 photographs an iPad window's arrangement on an iPhone
  simulator; `-SillIdiom phone` the other way round. In the harness and the normal app.
- A software keyboard shows only where the simulator has no hardware keyboard connected (booted
  headless, or Simulator.app's I/O › Keyboard › Connect Hardware Keyboard off for that device). If
  S2's photo shows none, the gate says so and P2 covers it.

## Test gates

**Hard rules, every step:**
- Never touch `/Applications/Sill.app` or connect anything to it; never `tccutil`; never install
  anything on Noah's iPad or iPhone; never push to main.
- **Simulators:** private ones named "Sill iphone-portrait", of the iPhone 18 Pro Max, iPhone 18 Pro
  and iPhone 17e types, one at a time, each deleted when its step ends. `xcrun simctl io <udid>
  screenshot` only: never XCUITest, `recordVideo` or the Claude iOS Simulator panel.
- **Live runs:** only `swift run -c release SillHost --synthetic` on loopback, reached with
  `-SillConnect 127.0.0.1:P`; only while `Scripts/encoder-check/no-device.sh` passes, before and
  every 2 s during; each host under 60 s, killed by PID. **No input reaches a host** (a synthetic
  host posts real events on this Mac): no touches on a live simulator; the keyboard's first
  responder and the viewport send none. If the Application Firewall asks about SillHost, stop and
  say so.
- **Disk:** at least 25 GB free before any build (`df -g /System/Volumes/Data`); DerivedData under
  the session's `scratchpad/iphone-portrait/`, deleted when the step ends.

**Headless (H):**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight and base.** The disk; step 2's commit built for the simulator; H4's base photos from it | The photos exist |
| H1 | **Builds.** iOS Debug and Release for the simulator (`ARCHS=arm64 CODE_SIGNING_ALLOWED=NO`), Debug for a generic device (unsigned) | `** BUILD SUCCEEDED **`, only the known `StreamClient` capture warning |
| H2 | **The pure check**, `Tests/checks/run-all.sh phone-portrait`, at least 120 cases. Pinned: every row of the two tables above, and 320 pt wide (buttons 52, caps 42 as today's outer layout has, step 28). A grid of every width from 300 to 599 and every height from the width + 1 to 1400: all inside the container and ordered picture, row 1, strip, keys, trackpad; the gaps (24 from the picture to the buttons, 16 from them to the strip, 10, 10, 16 at the bottom); five equal buttons and six equal caps spanning 14 to W − 14, 8 apart, the caps at least 44 pt from 332 pt up; the picture exactly ⌊(W − 16) ÷ 1.6⌋ whenever the trackpad keeps 120, else the trackpad exactly 120 (down to 360 pt of height); the span the width ÷ 1.6; the ruler inside the row and centred on Aa; the panels under row 1 across its span, the anchor their corner; the dim covering all but row 1's buttons. The keyboard table as assertions. `--mutants phone-portrait`, at least 15 (step 1) | All pass; every mutant caught; `Tests/checks/run-all.sh` passes whole |
| H3 | **By grep** | `git diff origin/main --stat -- Sources Packaging Scripts iOSClient/Info.plist iOSClient/PrivacyInfo.xcprivacy` is empty; `PhonePortraitLayout.swift` imports CoreGraphics or Foundation only; the idiom read once in the layout code, in `DuoLayout.phoneArrangement` (the review: before it, none); A501 and F501 each in their places; `phone-portrait` in ci.yml's matrix |
| H4 | **Nothing else moved.** On the 18 Pro Max, base (H0) against this build: 1000x710, 710x1000 and 710x500 (scaled), 956x440 and 874x402 (turned), each plain, `-SillDrawer 1`, `-SillSettings 1`, `-SillScaleOpen 1 -SillScale 1.5` and `-SillWindowMenu 1`; 710x1000 also with `-SillActive desktop` (the Spotlight cap). Since the review also the iPads' sizes (1133x744, 744x1133, 1376x1032, 1032x1376) and 844x390 (a smaller phone on its side), and the iPad's windows narrower than 600 pt held upright (500x710, 320x820, 375x800, 590x820 with `-SillIdiom pad`), these also with `-SillActive desktop` and with the keyboard's cap lit | Pixel for pixel equal, but for the ruler's value in the compact halves' 50 pt window bar (the review's fix) |

**Simulator (S),** photographed and sheeted per size, the sheets sent to Noah:

| # | Check |
|---|---|
| S1 | **The mock at every phone container**, on the 18 Pro Max: 440x894, 402x812, 393x793, 390x797, 375x762, 375x647, and 500x710 (scaled); each plain, `-SillDrawer 1`, `-SillSettings 1`, `-SillSettings 1 -SillSettingsEnd 1`, `-SillScaleOpen 1 -SillScale 1.5`, `-SillWindowMenu 1`, `-SillActive desktop` and `-SillActive none` (56 photos). Each against the tables: the picture's pane at the top; five equal buttons whose outer edges line up with esc's and shift's; the first thumbnail under Apps; no arrow, Spotlight or keyboard cap; the trackpad to 16 pt from the bottom; the drawer and the panel 8 pt under row 1 with row 1 undimmed; the ruler inside row 1 with the other four hidden; nothing truncated |
| S2 | **Live, with the real insets and keyboard**, on the 18 Pro Max, the 18 Pro and the 17e, one at a time: the app with `-SillConnect 127.0.0.1:P -SillKeyboard 1 -SillKeyboardToggle 5` against a synthetic host. A photo at 3 s: the keyboard up, row 1 whole above it with Keyboard lit, and rows 2 and 3 above it; each margin measured and written down (the check's assumed keyboard heights follow what the simulators draw, in the same commit). A photo at 6.5 s: the keyboard gone, Keyboard unlit. The console's `viewport:` line is the table's picture (424×265, 386×241, 374×233), and the test pattern (1512×949 points, 1.59:1) fills the pane but for bars of about 1 pt at the sides |
| S3 | **Text size**, `xcrun simctl ui <udid> content_size` at `extra-extra-extra-large` and `accessibility-extra-extra-extra-large`, on the 18 Pro: the mock at 402x812 plain and `-SillSettings 1`. The rows are pixel for pixel the default size's; the panel's text stops at xxLarge and scrolls, its header and Disconnect pinned. The size set back after |

**Noah's devices (P),** handed over (no agent installs on them): the iPhone 15 Pro and the iPad
mini.

| # | Check |
|---|---|
| P1 | **The iPhone upright, a window streaming.** The picture on top, 16:10; a 16:9 window (or the Desktop of a 16:9 display) with black bars above and below; switching between the two moves nothing below the picture |
| P2 | **The keyboard.** Keyboard brings it up under the key row, with esc to shift in view; type; Keyboard takes it down. Latch cmd, then C: copy. With the Desktop streaming, cmd then space: Spotlight on the Mac. A hardware keyboard's arrows still work |
| P3 | **The trackpad.** A diagonal stroke moves the pointer at the finger's angle; one stroke down the pad crosses the picture; two-finger scrolling at about today's speed; tap, two-finger tap, hold and drag as before |
| P4 | **Aa.** The ruler over row 1, the other buttons hidden; on release the Mac window resizes to 16:10 (Sill.log: "Resized … for a 377×235 panel at …") |
| P5 | **Apps and Settings.** Each hangs under row 1, which stays live: Apps again closes the drawer, Settings swaps them; a tap on the picture closes either and clicks nothing on the Mac |
| P6 | **Rotation.** Sideways, exactly as before; upright again, the drawer, the panel, the keyboard and a latch as they were |
| P7 | **VoiceOver.** Swiping right: Apps, Text size, Keyboard, Desktop, Settings, the thumbnails, Escape to Shift, the trackpad's hint. With the drawer open: Apps ("Close the app list") to Settings, then the drawer's search field and apps, nothing dimmed. At an accessibility text size, a long press on Keyboard or on cmd shows it large |
| P8 | **The iPad mini,** upright and sideways, exactly as before; in a window narrower than 600 pt (Split View, Slide Over, Stage Manager), upright, the compact halves as before, not the phone layout (open question 1) |

## Implementation order (one commit per step; each passes its gates before the next)

1. **"iOS: the phone's portrait layout, as a pure function, and its check."** The file and its
   pbxproj entries, `Tests/checks/phone-portrait`, the README row, the CI matrix. Mutants, at
   least: 16:9 for 16:10; the picture's height rounded up; no minimum trackpad; the margin under
   the picture dropped; the strip above row 1; row 1's width without its gaps; five gaps in it; the
   caps' gap 10; seven caps; the trackpad to the edge; the span as the pad's height; the ruler's
   step never reduced; the ruler on Keyboard; the drawer over row 1; the panel at the leading edge;
   one dim over row 1; the anchor from row 1's top; the strip not widened. Gates: H1, H2, H3.
2. **"iOS harness: screens larger than the simulator, the keyboard for real, the viewport line."**
   Gates: H1; H0's base photos.
3. **"iOS: the iPhone's portrait layout."** `PortraitStreamScreen`, `TrackpadView`, the comments.
   Gates: H1, H2, H3, H4, S1, S2, S3.
4. **"docs: the iPhone's portrait layout."** Below.
5. **Review** (three lenses: the geometry and its check; the keyboard, the overlays and the state
   across rotation; the merges below), a "Review fixes" commit if needed, S2 again on the final
   build, then the PR: the Duo's outer display as Noah's reversible choice, the open questions,
   what the other branches must follow, and P1–P8.

## Other branches (what each must follow)

- **`pointer-visibility`** (the device half is still to write): `DuoLayout.isPortrait` (its §7.6)
  stays right, since phones are `.outerPortrait`. Its call sites in `PortraitStreamScreen`
  (the picture's `InputOverlay`, the `Trackpad`'s closures) are shared by both arrangements after
  this change: change each once. `TrackpadSurface.moveCursor` is edited by both (its
  `setOwnPointer`, this change's `verticalSpan` on the `cursor.y` line): keep both.
- **`first-run-walkthrough`** (a plan): on phones upright, `windows` lights Apps (row 1) and the
  strip (row 2), two rects; `bar` lights Aa, Keyboard and Desktop, as in landscape; `keyboard` is a
  target in portrait there; `keys` is the six caps, and its "keyboard key" row belongs to the halves
  only. Its layout table's 500×710 row becomes this plan's on an iPhone (the Duo's outer display)
  and stays the compact halves on an iPad (a window that narrow), so it asks
  `DuoLayout.phoneArrangement` as `StreamScreen` does; its card placement in portrait ("the
  picture's half") needs the phone's rects from `PhonePortraitLayout`: the picture is 224–302 pt
  tall at the top (188 on an SE with Display Zoom), and the drawer and the Settings panel span row
  1 from 8 pt under it.
- **`trackpad-gestures`** (a plan): the arrows are gone from phones, so ⌃ with the key row's ↑ is
  the halves' only; its thresholds are in points, so the span does not touch them, but its
  two-finger deltas follow it.
- **`home-pairing`:** `StreamScreen.swift` (three lines) and the harness in `ContentView.swift`:
  textual merges only.

## Docs to update (step 4)

- **CLAUDE.md:** the Current step entry; Layout (`PortraitStreamScreen`'s two arrangements,
  `PhonePortraitLayout.swift`, `Tests/checks/phone-portrait`); Build and run (the harness's scaling,
  `-SillKeyboard`, `-SillKeyboardToggle`, the `viewport:` line).
- **`ContentView.swift`'s contract comment** (step 2).
- **docs/DEVELOPMENT.md:** The iOS app (a paragraph on the phone upright); The iOS debug harness
  (phone sizes, the scaling, the two keyboard arguments).
- **docs/app-store-metadata.md:** no words change (the laptop layout still has "a trackpad and a
  row of keys"); the iPhone screenshots of the laptop layout (its screenshot table's rows 1 and 4)
  are taken after this lands.
- **Tests/checks/README.md:** the `phone-portrait` row (step 1).

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **Which screens.** The plan's default was the size rule (`.outerPortrait`, so iPad windows
   narrower than 600 pt held upright got the phone layout too). The review changed it: **iPhones
   only** (`.outerPortrait` on an iPhone, the Duo's outer display included), since Noah asked to
   "detect iPhones" and the approval left the iPad as it is. Such an iPad window keeps the compact
   halves and, with them, today's keyboard cap in the key row's second line, which the keyboard
   covers. The alternative, the size rule, is `DuoLayout.phoneArrangement` returning true.
2. **The Duo's outer display.** Default: **the phone layout** (the same keyboard problem). Reversing
   it: Detection.
3. **The trackpad's speed.** Default: **vertical motion against the width ÷ 1.6,** so the extra
   height is extra room. The alternative, today's arithmetic, is about 40 % slower vertically per
   point on the Pros, for scrolling too.
4. **Row 1 while the drawer or Settings is open.** Default: **live and undimmed,** as the landscape
   bar. The alternative, today's portrait: the dim and the catcher over it too.
5. **The key row under the keyboard on the smallest phones** (7 pt of the SE's under a 216 pt
   keyboard; the mini's, and the 15 Pro's by a point, under a keyboard with a candidate bar).
   Default: **accepted:** row 1 is always clear, and a latch set before the keyboard comes up still
   works. The alternative puts the keys above the strip there, against Noah's order.
6. **The picture's height.** Default: **whole points, rounded down,** so the pane is never taller
   than 16:10 and the rows sit on whole points; a 16:10 picture shows sub-point side bars at most.

---

## Review fixes (2026-09-27)

The review of the first build (d44c132) came back with ten findings (the list as relayed ends in
the middle of the tenth). Each was reproduced on the build's own photos or code before it was
fixed; the sections above now describe the result.

1. **Row 1 and everything under it sat 6 to 12 pt higher than the approved mockup,** the
   trackpads 401 and 343 pt against its 389 and 331, and the docs called that today's gaps. The
   mockup, like the compact window bar, holds row 1's 50 pt buttons in a 62 pt band: 24 pt from the
   picture to the buttons and 22 from them to the thumbnails, against the build's 18 and 16.
   `PhonePortraitLayout.band` (6) puts the band back, which gives exactly the mockup's rects on the
   Pro Max (on the screen: the picture 70–335, Apps 359–409, the thumbnails 431–481, the caps
   497–541, the trackpad 551–940) and its 331 pt trackpad on the Pro. The keyboard's margins under
   row 3 shrink by 12 pt (95, 56 and 49 on the three measured phones), and the SE's key row now
   goes 7 pt under a 216 pt keyboard, which open question 5 accepts.
2. **Row 1's labels were not on one line:** "Keyboard" rode 2.7 pt and Aa's value 1.7 pt above
   Apps, Desktop and Settings (each VStack centred at its own height). Each symbol sits in a
   24 pt box (`PortraitMetrics.phoneIconBox`), and `TextScaleControl` gives its "Aa" the same box
   and spacing (`iconBox`, nil in every other bar, which draw as before).
3. **The Aa ruler's live value was cut** by about 2 pt at the ruler's top edge in a 50 pt ruler.
   It sits where the 58 pt bars put it (`max(midY - 34, -1)`), which fixes the compact halves'
   50 pt window bar too.
4. **The drawer and the Settings panel did not line up with row 1:** 380 and 360 pt wide, the
   drawer ended inside Settings and the panel began inside Apps on the Pro Max, with cut
   thumbnails, esc and the pad's hint beside them, and slivers on the Pro, the 17e and at 500×710.
   Both span row 1 now, 14 to W − 14, and the strip hides while either is open (its first
   thumbnail's badge sticks out 6 pt past the row).
5. **VoiceOver with the drawer open** read the dimmed thumbnails, caps and the pad's hint before
   the drawer, and a double-tap on a dimmed cap reached the Mac. The picture, the strip, the key
   row and the trackpad are hidden from it while the drawer is open (from the code: VoiceOver is
   not driven here); P7 has the case.
6. **The traffic lights opened over row 1 on the SE and at 500×710** (the midpoint rule) and below
   the strip on the other phones. On a phone they always open below the strip
   (`WindowLightsMenu.alwaysBelow`, `DuoLayout.drawsPhone`); landscape and the halves keep the rule.
7. **The Duo's outer display had no keyboard row:** it is in the table and the check (row 1 clear
   of a keyboard up to 326 pt, rows 2 and 3 only of ones under 248 and 194), and the PR says that
   only row 1 stays above the keyboard there.
8. **Larger text:** row 1 and the caps stay one size, with no Large Content Viewer. Apps,
   Keyboard, Desktop, Settings and the six caps now show theirs on a long press at the
   accessibility sizes (not Aa, whose drag starts at touch-down); nothing changes at other sizes.
9. **S1's 440x894 photos ran the trackpad off the fake screen's bottom:** the harness's fake
   screen reached into the simulator's safe area (its comment already said so). Not a layout
   fault; the sheets show the Pro Max from the live app instead.
10. **An iPad window narrower than 600 pt got the phone layout,** which the approval (iPhones) did
    not cover. `DuoLayout.phoneArrangement` reads the idiom (DEBUG `-SillIdiom pad|phone`), so an
    iPad keeps the compact halves, `.compact` as on main with its two-row key fold, and the phone's
    metrics are `.phone`. Open question 1 and P8 say so.

Verified (2026-09-27, 04:40–05:10; private simulators of the iPhone 18 Pro Max, the 18 Pro and the
17e, one at a time, each deleted after; `simctl io screenshot` only):
- H2: the check, 149 cases (the mockup's rects and the Duo's keyboard among them), and 28 of 28
  mutants (four new: row 1 without its band above, the strip without it under, the fixed height
  without it, a 4 pt band).
- H3: nothing in Sources, Packaging or Scripts; `PhonePortraitLayout` imports CoreGraphics
  only; the idiom read once, in `DuoLayout.phoneArrangement`.
- H4, 81 harness photos on the Pro Max against the base build (the harness commit 85920e3 on
  main's layout): the landscape sizes, the inner portrait, the iPads' sizes, the phones on their
  side and the iPad's windows narrower than 600 pt (`-SillIdiom pad`), plain, drawer, Settings,
  ruler and lights, with the Desktop and the keyboard's cap. 56 identical at once. The ruler's
  value in the compact halves' 50 pt bar changed as intended (four photos). The rest is what
  retakes show the base doing against itself: the held thumbnail's wiggle in the 14 lights photos
  (the menu where it was), and Δ1–2 anti-aliasing in three drawers, three rulers and one Settings
  panel, each photo reproduced exactly by a retake of the other build (the Settings panel at
  710x500 renders its footnote one of two ways from either build).
- S1, 60 harness photos at 402x812, 393x793 (the 15 Pro), 390x797, 375x762, 375x647, 320x548 and
  500x710, measured by a tool compiled with `PhonePortraitLayout.swift`: every button, cap, the
  strip's first thumbnail and the trackpad within a pixel at 3x of the rule; row 1's label ink
  tops within 2 px and baselines within 1 px (the letters' own shapes; before, "Keyboard" sat 8 px
  and Aa's value 5 px high); the drawer's and the panel's edges on Apps' leading and Settings'
  trailing edges; the ruler's value 2.3 pt inside the ruler; the lights below the strip at every
  size.
- S2, the normal app against `SillHost --synthetic` on loopback behind a relay that drops input
  (no-device.sh passed before, every 2 s during and after each run; each host under 55 s, killed
  by PID). The Pro Max: the viewport 424×265 (and at 1.5× from the ruler); the rows exactly as
  above; the keyboard's top at 636 pt, 95 under row 3, Keyboard lit, and down again; the drawer
  and the panel across row 1; the ruler's value whole; row 1, the key row and the trackpad pixel
  for pixel the same with a 16:10 and a 16:9 picture (bars of 13.3 pt above and below, from a
  scratch host whose test pattern is 1600×900), with the keyboard up and at AX-XL;
  `-SillInputTest`: ⌘esc, the stroke's 40 pt down counted against 257.5 pt, the tap with ctrl and
  shift around it, the scroll, every event dropped at the relay. The 18 Pro: 386×241, the
  trackpad 374×331, the keyboard's top at 573, 56 under row 3. The 17e: 374×233, 362×324, 543,
  49. (A fresh simulator's first keyboard shows the slide-to-type tip over its keys.)
- S3 at 402x812: at xxxLarge, AX-XL and AX-XXXL the rows, the caps, the trackpad and the drawer
  pixel for pixel the default size's; the panel's text capped at xxLarge.
