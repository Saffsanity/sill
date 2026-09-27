# The first-run walkthrough — the plan

2026-09-27. It stands alone: the implementer needs no other design document. Written from a
read-only survey of origin/main at cf05a78 (PR #28) in the worktree
`/Users/noah/Downloads/winstream-walkthrough` (branch `first-run-walkthrough`); line numbers are at
cf05a78, and every file named here is to be read again before it is changed. Nothing was built or
run for this plan. The SF Symbols it names were looked up in this Mac's symbol catalog
(`name_availability.plist` in SFSymbols.framework) for the iOS version each first shipped in: the
app targets iOS 17.0, and every symbol here is iOS 17.0 or older.

**Noah's request (2026-09-26):** "Add to feature list, app usage walkthrough first time after
pairing/connecting".

**Reading of it.**
- **What it teaches is the stream screen:** how to use the Mac from the device once connected.
  That is touch on the picture, the bar (Apps, the thumbnails, Aa, Keyboard, Desktop, Settings),
  the portrait laptop layout (the key row and the trackpad), and where Settings and Disconnect
  are. Not the Mac's setup (its Permissions pane does that), not pairing (the card and the Mac's
  window say what to do), not the connect screen.
- **"First time after pairing/connecting":** the first session on this device that shows a Mac's
  picture, however it came: a tap on a row, pairing at home once `home-pairing` lands, the cable,
  or Add a Mac… away from home. Once per device, not once per Mac.
- **A walkthrough:** steps the person goes through at their own pace, can skip, and can see
  again.

In the app it is called **the tour** ("Take the Tour"), and in code `Tour…`: shorter than
walkthrough, and a word everyone reads the same way.

---

## Decision

### In one paragraph

About a second after the first picture from a Mac, once nothing else is open and the person has
not touched anything for a second, the stream screen dims and a card points at one part of it at a
time: the picture (tap, hold, drag), the Apps button with the thumbnails, Aa with Keyboard and
Desktop, and Settings; held upright, also the key row and the trackpad. Each card says what that
part does in a line or two, in the App Store description's words, with Skip and Next. The picture
keeps moving underneath, and nothing reaches the Mac while the tour shows. Skip ends it for good on
this device and Done ends the run; a step passed stays passed if the session ends first; the
laptop layout's two steps come the first time the device is held upright after a tour in
landscape; and the Settings panel's last row, Take the Tour, shows it again. All of it is on the
device: no wire change, nothing sent, two UserDefaults keys.

### The form: coach marks over the live controls

| Criterion (0–10) | **A: coach marks over the live controls (chosen)** | B: a paged card with drawings | C: TipKit tips | D: a welcome page, then A |
|---|---|---|---|---|
| Shows where each control is | 10: the control itself, lit | 4: a picture of it | 8: a popover beside it | 10 |
| Every layout with no extra art (the Duo's four sizes, iPhone, iPad, rotation) | 9: the spotlight follows the controls | 4: art per layout, or art that matches none | 5: popovers adapt by size class | 8 |
| Fits the client's rules (no system presentation, the crease, the harness) | 9 | 8 in the view hierarchy (3 as a `.sheet`) | 3: `popoverTip` is a system popover | 9 |
| VoiceOver, Dynamic Type, Reduce Motion | 8 | 9 | 8 | 8 |
| Native feel | 8: the real control, lit, and a card in the app's own materials | 8: like the What's New screens of Apple's apps | 9: Apple's own look | 8 |
| Implementation risk (10 = lowest) | 7: targets in two layouts, placement | 9 | 5 | 6 |
| Upkeep as the bar changes | 9: nothing to redraw | 4: every bar change redraws | 8 | 7 |
| **Mean** | **8.6** | 6.6 (as a sheet: 5.9) | 6.6 | 8.0 |

**Why A.**
- It points at the real control, where it really is, in whatever layout the device is in. The
  spotlight follows the controls through rotation, the Duo's outer display and Split View, so
  there is no drawing to keep in step with a bar that is still growing (pointer visibility, the
  gestures, the menu bar mirror are all on their way).
- It stays in the view hierarchy, as every panel of the client does. HostSettingsPanel.swift:8-15
  gives the reasons, and they hold here:
  - sheets and popovers adapt by size class, which is unknown for the Duo;
  - the layout harness draws a fake Duo screen inside an iPad window, which a presentation would
    escape;
  - a tall sheet or a flipped popover could cross the half-folded crease.
- The client already does both halves of it:
  - the traffic lights are placed from a thumbnail's frame (StreamScreen.swift:149-155,
    :868-935);
  - the pairing overlay is a sibling above the layouts that takes every touch while the layouts
    take none (:136-145).

**Why not TipKit (C).** TipKit is Apple's and allowed, but for this job:
- `popoverTip` presents a system popover: the three reasons above.
- iOS 17, the deployment target, has no `TipGroup` (iOS 18). An ordered walkthrough would be built
  by hand from rules and parameters, and TipKit decides when an eligible tip displays.
- Seeing it again fits badly: an invalidated tip stays invalid in TipKit's datastore, so Take the
  Tour would need `Tips.resetDatastore()` or parameter rules.
- It adds a datastore, set up by `Tips.configure()` at launch, where two UserDefaults keys do.
- Where it could fit later: single hints after the tour, on iOS 18's TipGroup (open question 14).

**Why not a paged card (B).** It shows pictures of the controls instead of the controls. The
Duo's four layouts, the iPhone and the iPad would each need their own drawings, or get drawings
that match none, and every bar change would redraw them. As a `.sheet` it would also be a system
presentation.

**D was close.** A welcome page first ("Mac mini is on your iPad"), then the marks. The first card
carries the welcome in its subtitle instead, and one card less is one tap less.

### When it shows

- **After the first picture,** not at the connection. The picture means three things together:
  - the first window list (the Mac's name),
  - a frame size (the parameter sets),
  - a source that streams.

  At home `connected` turns true at `.ready` (StreamClient.swift:923-941), before the Mac has said
  anything. A Mac with a device floor refuses a device after `.ready`, and the stream screen shows
  for a frame or two first (docs/update-notice-plan.md, open question 10). A remote session is
  connected only at its first window list (StreamClient+Remote.swift:326-350). A Mac that cannot
  capture (Screen Recording off) sends no picture, so no tour points at a black screen.
- **A beat of 1 s** after the picture, so the person sees their Mac first.
- **A quiet moment:** no input from this device for 1 s, and nothing open: the Apps list, the
  Settings panel, a thumbnail's traffic lights, the Aa ruler, the software keyboard, the pairing
  overlay or an outside link's confirmation.
- **One chance per session and layout,** within 10 s of the picture (or, for the upright
  remainder, of the layout change). Someone who starts working at once is not interrupted half a
  minute later; the next session tries again.
- **Never on the connect screen.** The pairing card, the Mac's notices ("Update Sill…") and every
  status line live there. Never over the pairing overlay: an outside link that arrives during the
  tour puts the tour aside until the overlay has closed.

### What it teaches, per layout

| Step | Lit | Landscape (inner 1000×710, outer 710×500, iPhone and iPad sideways) | Portrait, the laptop layout (inner 710×1000, outer 500×710, iPhone and iPad upright) |
|---|---|---|---|
| `touch` | The picture | 1 of 4 | 1 of 6 |
| `windows` | Apps and the thumbnails | 2 of 4 | 2 of 6 |
| `bar` | Aa, Keyboard and Desktop; upright, Aa and Desktop (the keyboard is in the key row) | 3 of 4 | 3 of 6 |
| `settings` | Settings | 4 of 4, Done | 4 of 6 |
| `keys` | The key row | — | 5 of 6 |
| `trackpad` | The trackpad | — | 6 of 6, Done |

- **Order.** Where things are: the picture first (it matters most), then the bar from left to
  right, then down the laptop half. The spotlight travels in reading order.
- **What is folded together.** Labelled buttons that need no gesture share a card (Keyboard,
  Desktop); what a label cannot say gets its own row (hold a thumbnail, slide on Aa, the sticky
  modifiers, the two-finger right-click, Disconnect inside Settings).
- **The other layout.** The landscape tour's last card says the device can be held upright. The
  first time it is, the two steps landscape lacks (`keys`, `trackpad`) show as a short tour of
  their own. A tour taken upright covers everything, so turning the device sideways later shows
  nothing new (the Keyboard button is labelled).

### While it shows, the Mac gets nothing

- **The picture keeps moving:** the stream, the stats and the keepalive run as before, so the
  person watches their Mac while they read.
- **No touch, Pencil, trackpad, mouse or key reaches the Mac**, as asked:
  - The layouts stop hit-testing, as they do under the pairing overlay (StreamScreen.swift:136-138).
    The tour's layer is a sibling above them and takes every touch, the lit control's included.
  - The software keyboard goes down (`InputOverlayProxy.setKeyboard`, InputOverlay.swift:409-416).
    The input view forwards hardware keys only while it has the keyboard, so keys stop too, as they
    do under the Settings panel (StreamScreen.swift:258-279). It comes back at the end if it was up.
- **A tap outside the card** does nothing but nudge Next, so trying the gesture a card describes
  never clicks something on the Mac behind the dim.
- Why not let the gestures through and have the person try them: the first thing a new user does
  on their Mac would then be a click they cannot see under a card, and keys typed while reading
  would type on the Mac (open question 5).

### Skipping it, and seeing it again

- **Skip** on every card but the last ends the tour for good on this device: no automatic tour
  again, not even the upright steps.
- **Done** on the last card.
- **Keys and assistive tech:** Esc is Skip (Done on the last card), Return is Next or Done, the
  VoiceOver escape gesture is Skip, and Magic Tap is Next.
- **Settings › Take the Tour,** the last row of the Settings panel, shows the whole tour of the
  layout on screen from its first step, whatever was seen before.

---

## Final plan

### 1. Scope

**In this step:**
1. **The rules, pure** (`TourPolicy.swift`): the steps per layout, when the tour shows by itself,
   what it remembers, where it goes after a rotation, where its card goes, and every string.
   Checked with swiftc in `Tests/checks/tour`, with mutants.
2. **The overlay** (`TourOverlay.swift`): the dim and its cutouts, the card, the keys, VoiceOver,
   Dynamic Type and Reduce Motion, and the input pause.
3. **The stream screen:** the spotlight's targets in both layouts, the automatic start, and the
   tour's place above the layouts and below the pairing overlay.
4. **The Settings panel:** Take the Tour.
5. **The harness:** arguments for every step, state and scripted press; console lines.
6. **Docs:** CLAUDE.md, DEVELOPMENT.md, the App Store metadata and checklist, the privacy page.

**Not in this step:**
- anything on the Mac, the CLI or `StreamProtocol` (no kind, no field, no log line);
- a tour of the connect screen, pairing or the Mac's setup;
- "try it" steps that let a gesture reach the Mac (open question 5);
- a Back button (open question 7);
- TipKit, or hints after the tour (open question 14);
- tours for controls not on main yet: the Mac's pointer, the trackpad's three-finger gestures, the
  menu bar mirror. Each adds a topic when it lands (§17).

### 2. The design on one page

```
 ┌─── the device only: no wire change, nothing sent to the Mac ───────────────────────────────────┐
 │ StreamScreen (one per session)                                                                 │
 │   the first picture (the window list, a frame size, a source) ──▶ pictureAt                    │
 │   TourPolicy.automatic(now, pictureAt, layoutAt, lastInputAt, busy, offered, memory, enabled)  │
 │      ──▶ wait (the 1 s beat, the 1 s quiet, something open) | pass (10 s gone) | show(owed)    │
 │   Settings › Take the Tour ──▶ show(every step of the layout on screen)                        │
 │   targets, as frames in the screen's coordinate space: stream, apps, strip, textSize,          │
 │   keyboard, desktop, settings, keys, trackpad                                                  │
 │   ZStack: 1. the layouts (no hit testing while the tour shows)                                 │
 │           2. TourOverlay: the dim with its cutout and ring, then the card (TourPolicy.place)   │
 │           3. PairingOverlay (an outside link puts the tour aside until it closes)              │
 │   Next ──▶ seen += that step     Done ──▶ the same     Skip ──▶ skipped = true                 │
 │   UserDefaults: Sill.tourSeen [String], Sill.tourSkipped Bool                                  │
 └────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Two cards as they would sit (not to scale; `[…]` a bar button, `=` a thumbnail, `*` the current
step's dot; at 710×1000 the split between the halves is the Duo's crease):

```
 1000×710, step 2 of 4                            500×710, step 6 of 6
 ┌─────────────────────────────────────────────┐  ┌────────────────────────────────┐
 │ [Apps][= = = = = =] [Aa][Kbd][Desk][Set]    │  │  the picture, dimmed           │
 │ └─── lit, ringed ──┘   dimmed               │  │ ┌────────────────────────────┐ │
 │    ┌─────▲───────────────────────┐          │  │ │ Trackpad                   │ │
 │    │ Windows and Apps            │  the     │  │ │ Drag to move the pointer.  │ │
 │    │ Apps finds any window ...   │  picture,│  │ │ Tap to click. Tap with ... │ │
 │    │ Tap a thumbnail to show ... │  dimmed  │  │ │ o o o o o *           Done │ │
 │    │ Touch and hold a thumb ...  │          │  │ └────────────────────────────┘ │
 │    │ Skip      o * o o      Next │          │  ├── the split ───────────────────┤
 │    └─────────────────────────────┘          │  │ [Apps][= =][Aa][Desk][Set]     │
 │                                             │  │ esc tab ctrl opt cmd ...       │
 │                                             │  │ ┌── the trackpad, lit ───────┐ │
 │                                             │  │ │                            │ │
 │                                             │  │ └────────────────────────────┘ │
 └─────────────────────────────────────────────┘  └────────────────────────────────┘
```

### 3. The steps

#### 3.1 Topics, targets and orders

```swift
enum TourTopic: String, CaseIterable { case touch, windows, bar, settings, keys, trackpad }
enum TourLayout: Equatable { case landscape, portrait }        // DuoLayout's inner/outer landscape, inner/outer portrait
enum TourTarget: String, CaseIterable { case stream, apps, strip, textSize, keyboard, desktop, settings, keys, trackpad }

static func steps(_ layout: TourLayout) -> [TourTopic] {
    layout == .landscape ? [.touch, .windows, .bar, .settings]
                         : [.touch, .windows, .bar, .settings, .keys, .trackpad]
}

static func targets(_ topic: TourTopic, _ layout: TourLayout) -> [TourTarget] {
    switch topic {
    case .touch: return [.stream]
    case .windows: return [.apps, .strip]                          // lit as one shape: they sit side by side
    case .bar: return layout == .landscape ? [.textSize, .keyboard, .desktop] : [.textSize, .desktop]
    case .settings: return [.settings]
    case .keys: return [.keys]
    case .trackpad: return [.trackpad]
    }
}
```

Where each target is reported (a `.tourTarget(_:)` modifier, §6.1):

| Target | Landscape (`StreamScreen`) | Portrait (`PortraitStreamScreen`) | Cutout radius |
|---|---|---|---|
| `stream` | The stream `ZStack` inside `contentArea`'s 8 pt padding, where `panelSize` is measured (StreamScreen.swift:320-336) | `streamPane`, the same place (PortraitStreamScreen.swift:216-233) | 16 (the panel's 12 + 4) |
| `apps` | TopBar's Apps button (StreamScreen.swift:432-437) | `windowBar`'s Apps button (PortraitStreamScreen.swift:260-265) | 20 |
| `strip` | TopBar's `WindowStrip` (:439-443), less its vertical `pad` (the thumbnails' band; the strip's frame is as tall as the bar) | `windowBar`'s `WindowStrip` (:267-272), less `thumbPad` | 20 |
| `textSize` | `TextScaleControl` (:448-450) | `TextScaleControl` (:274-276) | 20 |
| `keyboard` | TopBar's Keyboard button (:452-456) | — (the key row's keyboard cap is part of `keys`) | 20 |
| `desktop` | TopBar's Desktop button (:458-462) | `windowBar`'s Desktop button (:278-282) | 20 |
| `settings` | TopBar's Settings button (:465-469) | `windowBar`'s Settings button (:285-289) | 20 |
| `keys` | — | `KeyRow`, one row or the two folded rows (:240-243) | 15 (the caps' 11 + 4) |
| `trackpad` | — | `Trackpad` (:244-248) | 26 (the pad's 22 + 4) |

A step's cutout is the union of its targets' frames, 4 pt larger all round, clipped to the screen.
Its ring is a 2 pt stroke in `Palette.accent` on that shape, the active thumbnail's halo
(StreamScreen.swift:969-971).

#### 3.2 A rotation or a resize during the tour

- The run is a list of steps: every step of the layout (Take the Tour), or the steps this device
  is owed there (the automatic tour). On a layout change it is recomputed for the new layout, less
  what this run has passed.
- **The step on screen** stays when the new list has it (`touch`, `windows`, `bar`, `settings`
  exist in both). Otherwise the next step not yet passed comes on. When the new layout has none
  left (a run at `keys` turned sideways), the tour ends with nothing more saved: `keys` and
  `trackpad` stay owed, and show the next time the device is held upright with a chance left
  (§4: not again in a session whose portrait chance was used).
- The dots and the count follow the new list. The cards re-place without animation while the
  screen rotates.

### 4. When it shows by itself: the rule

```swift
struct Moment {
    var now: Double                 // ProcessInfo.systemUptime
    var pictureAt: Double?          // this session's first picture (§4.1)
    var layoutAt: Double            // when the layout on screen began (portrait or landscape)
    var lastInputAt: Double?        // this device's last input to the Mac (§6.6)
    var busy: Bool                  // the Apps list, the panel, the lights, the Aa ruler, the keyboard, the overlay or a link
    var offered: Bool               // this session had its chance in this layout already
    var enabled: Bool               // Release: true; Debug: only with -SillTourState (§10)
}
enum Decision: Equatable { case show([TourTopic]), wait(until: Double?), pass }

static func automatic(_ m: Moment, _ layout: TourLayout, _ memory: TourMemory) -> Decision
```

In order:
1. Not `enabled`, `offered`, `memory.skipped`, or nothing owed here (`steps(layout)` less
   `memory.seen`): `pass`.
2. No picture yet: `wait(until: nil)` (the next change looks again).
3. `opens = max(pictureAt, layoutAt)`. Past `opens + 10`: `pass`, and the session is marked
   `offered` for this layout ("not this session").
4. `due = max(pictureAt + 1, layoutAt + 1, (lastInputAt ?? 0) + 1)`. Before `due`, or `busy`:
   `wait(until: due)` (busy clears with its own change).
5. Otherwise `show(owed)`, and the session is marked `offered` for this layout.

`StreamScreen` asks again whenever an input changes and at the time a `wait` names: one pending
`Task`, replaced on every answer.

#### 4.1 The picture

`pictureAt` is set once per `StreamScreen` (one per session: ContentView.swift:32-36 swaps it in at
`connected`) when all three hold: `client.macName` is not empty (the window list,
StreamClient.swift:2344), `client.videoSize` is not zero (the parameter sets,
HEVCDisplayView.swift:200-235), and `client.active != .none`. A move from AWDL to the network, to
the cable or to Wi-Fi keeps the same `StreamScreen` and its `pictureAt`.

#### 4.2 The upright remainder

- A tour done in landscape leaves `keys` and `trackpad` owed. The first time the layout turns
  portrait in a later moment of this session, or in any later session, `layoutAt` opens their
  chance: the 1 s beat after the turn, the quiet second, the 10 s window.
- The first card of the remainder carries its own subtitle (§7), since it starts without the
  others. The rule is plain: `keys` has the subtitle whenever it is a run's first card (a portrait
  tour cut short after `settings` resumes the same way, and the words still hold).

### 5. What it remembers

| Key (UserDefaults, the app's own) | Type | Written |
|---|---|---|
| `Sill.tourSeen` | `[String]`, topic names | When Next or Done passes a step: that step's topic |
| `Sill.tourSkipped` | `Bool` | When Skip is tapped |

- **Next** saves the step it leaves; **Done** saves the last; nothing is saved when a step merely
  shows. So a session that ends mid-tour (the Mac quits, a notice, a lost network) leaves the
  steps not yet passed owed, and the next session's tour starts at the first of them.
- **Skip** saves `skipped`: no automatic tour again. Take the Tour still works.
- **Take the Tour** saves each step passed as well (it can only add).
- **A new topic in a later build** (a new control) is owed to every device that did not skip,
  and shows once, as the upright remainder does.
- **Per device, not per Mac.** Kept in the app's own defaults, as `Sill.savedMacs` and
  `Sill.directWirelessMacs` are. A backup and restore keeps it (the person knows the app); a
  delete and reinstall resets it. The privacy manifest's UserDefaults reason (CA92.1) covers it,
  and the App Store label stays Data Not Collected.
- **No migration.** Only development and TestFlight builds exist before this one, so everyone gets
  the tour once (open question 11).

### 6. The overlay (`TourOverlay.swift`)

#### 6.1 Structure

- **Targets.** `View.tourTarget(_ t: TourTarget, inset: EdgeInsets = .init())` reports the view's
  frame in the named coordinate space `"sill.screen"` through a preference `[TourTarget: CGRect]`
  (a `GeometryReader` in a background, merged by key). `StreamScreen`'s `ZStack` names the space
  and keeps the rects with `onPreferenceChange`. Frames, not anchors, because the layer is a
  sibling drawn after the layouts, the way the pairing overlay is: over the stream's UIKit input
  view that sibling was measured to get the touches where an overlay's buttons were drawn but
  never tapped (StreamScreen.swift:139-141). A sibling cannot resolve its siblings' anchors; rects
  in a shared coordinate space need nothing more.
- **Where the layer sits,** in `StreamScreen`'s `ZStack` (:123-146): the layouts, then
  `TourOverlay` when a tour runs and no pairing overlay shows, then `PairingOverlay`. The layouts'
  `.allowsHitTesting(!overlayShown)` (:138) becomes `!overlayShown && !tourShown`.
- **The overlay:**
  ```
  ZStack {
      TourDim(cutout:, ring:)          // full screen, safe areas included; even-odd fill; the whole screen hit-tests; a tap nudges Next
      TourCard(copy:, index:, count:)  // placed by TourCardLayout (a Layout: measures the card, asks TourPolicy.place)
  }
  .background(EscapeKey(action: skipOrDone))          // AddMacCard.swift:270, as PairingOverlay.swift:73
  .accessibilityElement(children: .contain)
  .accessibilityAddTraits(.isModal)
  .accessibilityAction(.escape, skipOrDone)
  .accessibilityAction(.magicTap, nextOrDone)
  ```
- **A `Layout`, not a measure-then-place pass,** so the card lands in its place on the first frame,
  as `ColumnOverFooter` does for the connect screen (ContentView.swift:637-685).

#### 6.2 The look

- **The dim:** black at 0.58, the Apps list's dim (StreamScreen.swift:341), over the whole screen
  and its safe areas, the step's cutout clear. In the `touch` step the picture is the cutout, so it
  stays bright and only the bar (or the laptop half) dims.
- **The card:** the drawer's and the panel's material (HostSettingsPanel.swift:58-61):
  `Palette.bar`, 20 pt corners, a 1 pt white border at 10 %, the shadow (black 65 %, radius 30,
  y 24), 16 pt padding, `.tint(Palette.accent)`; dark like the rest of the app.
  - **Title:** `.headline`, `Palette.text`, a header for VoiceOver.
  - **Subtitle,** on two cards only (§7): `.footnote`, `Palette.muted`.
  - **Rows:** a symbol column 22 pt wide (`@ScaledMetric(relativeTo: .subheadline)`) in
    `Palette.accent`, then the text in `.subheadline`, `Palette.text`, the control's name
    semibold (an `AttributedString` run, not Markdown, so the Mac's name is never parsed). 10 pt
    between rows. At accessibility sizes the symbol sits above its text.
  - **Footer:** Skip (`.body`, `Palette.accent`, plain, 44 pt tall), the dots (6 pt, 6 pt apart,
    the current one `Palette.accent`, the rest `Palette.muted` at 40 %), and Next or Done
    (`.body.weight(.semibold)`, black on an accent fill, 12 pt corners, at least 88×44: the
    pairing card's Pair, PairingOverlay.swift:168-176). One line while it fits; otherwise Next over
    Skip at full width and no dots (`ViewThatFits`).
  - **Only the title and rows scroll,** when the card is taller than its room, as the panel's
    middle does (HostSettingsPanel.swift:49-55), with `scrollIndicatorsFlash(onAppear: true)`. The
    footer stays in reach.
- **The tail:** on landscape bar steps, and in portrait where §6.3 allows one. 16 pt at its base,
  7 pt tall, the card's fill and border, its tip under or over the targets' middle, never nearer
  than 28 pt to the card's corner.

#### 6.3 Where the card goes (`TourPolicy.place`, pure)

```swift
struct TourPlacement: Equatable { var card: CGRect; var tail: Tail? }     // Tail: .up or .down, and the tip's x
static func place(card: CGSize, targets: CGRect?, isStream: Bool, screen: CGSize, layout: TourLayout,
                  stream: CGRect, bottomInset: CGFloat, accessibilityText: Bool) -> TourPlacement
static func crease(_ screen: CGSize) -> CGFloat?   // screen.height / 2 at ConnectLayout.topHalf's sizes, else nil
```

- **The crease** is `ConnectLayout.topHalf`'s rule (AddMacCard.swift:19): taller than wide, 600 to
  740 pt wide and under 1100 pt tall, which is the Duo's 710×1000 whether flat or half-folded.
  There the crease is the portrait layout's own split (PortraitStreamScreen.swift:156), and a card
  or tail never crosses it.
- **Width:** 360 pt, or the screen less 32 pt where that is narrower; at accessibility text
  sizes up to 560 pt.
- **Margins:** 16 pt from the screen's edges, and above the home indicator (`bottomInset`: the
  stream screen ignores the bottom safe area, StreamScreen.swift:169).
- **Landscape:**
  - The picture's step: centered in the picture, at most its height less 32 pt.
  - A bar step: the card's top 12 pt below the targets, centered on their middle and clamped to
    the margins; its height at most what is left below; a tail up.
- **Portrait:** the card lives in the picture's half, so it never covers the laptop half it is
  about, and never crosses the crease.
  - Its region is the picture's pane (the upper half less 8 pt). At accessibility text sizes on a
    screen with no crease it is the whole screen, and the card may cover its own spotlight: at
    those sizes the words matter more than the arrow (open question 9).
  - The picture's step: centered in the region.
  - A lower step: the card's bottom 12 pt above the region's bottom, centered on the targets'
    middle and clamped.
  - A tail down only when the targets begin within 48 pt of the card and no crease lies between.
    So at 500×710 and on phones, the `windows`, `bar` and `settings` cards point at the window
    bar and the `keys` and `trackpad` cards do not; at 710×1000 none do.

The layouts' numbers, from the metrics (BarMetrics, StreamScreen.swift:403-413; PortraitMetrics,
PortraitStreamScreen.swift:111-126):

| Screen | Layout | The picture | The bar | The keys | The trackpad | The card's region at default text |
|---|---|---|---|---|---|---|
| 1000×710 (Duo inner, sideways) | landscape, regular bar | 984×608 at (8, 94) | 0–86, its buttons 10–76; the strip 566 pt | — | — | a bar step's card from 88 (12 below the buttons) to 694 |
| 710×500 (Duo outer, sideways) | landscape, compact bar | 694×406 at (8, 86) | 0–78, its buttons 10–68; the strip 302 pt | — | — | 80 to 484 |
| 710×1000 (Duo inner, upright or half-folded) | portrait, regular | 694×484 at (8, 8) | 512–590; the strip 378 pt | 600–648 | 658–978 | 8 to 492, the crease at 500 |
| 500×710 (Duo outer, upright) | portrait, compact | 484×339 at (8, 8) | 365–427; the strip 200 pt | 437–533 (two rows) | 543–694 | 8 to 347 |
| iPhone upright, iPad upright | portrait, compact or regular | the upper half | below the half | | | the upper half |
| iPhone sideways, iPad sideways | landscape, compact or regular | below the bar | | | | below the bar |

The check pins the card's frame for every step at the four Duo sizes, at default text and at an
accessibility size, and asserts the rules above at a grid of other sizes.

#### 6.4 Motion

| Moment | Default | Reduce Motion |
|---|---|---|
| The tour appears | The dim fades in (0.25 s, ease out); the card scales up from 0.94 about its tail and fades in (spring 0.25 s, bounce 0.15), as the panel does (StreamScreen.swift:273, :286-288) | Both fade in, 0.2 s |
| Next | The cutout and its ring travel to the next targets (spring 0.35 s, bounce 0.1; the dim is an `Animatable` shape); the card slides to its place and its content cross-fades; the ring grows 4 pt and back once; the rows' symbols bounce once (`symbolEffect(.bounce, value: step)`, iOS 17) | Cutout and card cross-fade, 0.2 s; no bounce (`symbolEffectsRemoved()`) |
| A tap outside the card | Next grows to 1.06 and back, 0.25 s (`phaseAnimator`) | Next's fill brightens and back, 0.25 s |
| The tour ends | The dim and the card fade out, 0.2 s | The same |
| Haptic | `.sensoryFeedback(.selection, trigger: step)` on Next (iPhone; an iPad has none) | The same |

No animation repeats: nothing moves once a card is in place.

#### 6.5 Keys, VoiceOver and the rest

| Who | What |
|---|---|
| A hardware keyboard | Return is Next or Done (`.keyboardShortcut(.defaultAction)`, as the card's Pair, AddMacCard.swift:133). Esc is Skip, or Done on the last card (`EscapeKey`, which already takes Esc ahead of the system and lets the newest overlay answer first). Nothing else is taken; with the software keyboard down, no key reaches the Mac |
| VoiceOver | The tour is modal: the dimmed screen is out of reach. Each card's title takes the focus when the card appears (`@AccessibilityFocusState`), read as "Windows and Apps, step 2 of 4", with a hint saying where the lit part is (§7). Each row is one element. The escape gesture is Skip, Magic Tap is Next. At the end a screen-changed notification lets VoiceOver read the stream screen afresh |
| Voice Control | The buttons' spoken names are their visible words: Skip, Next, Done |
| Full Keyboard Access, Switch Control | Skip and Next or Done are buttons in order |
| Dynamic Type | Every size, the accessibility sizes included: the title and rows wrap, never truncate; the rows scroll inside the card; the footer stacks; the card may widen to 560 pt; in portrait on a screen without a crease it may use the whole height (§6.3). The Settings panel stops at xxLarge (HostSettingsPanel.swift:63); the tour does not, since it is what a person reads to learn the app (open question 9) |
| Reduce Motion | §6.4 |
| Increase Contrast, Reduce Transparency | Nothing is translucent but the dim; the ring and the accent keep their contrast on the dark card |

#### 6.6 The input pause, in code

- **Start** (`startTour`): put away what could be open (the Apps list, the lights, the Aa ruler, as
  `putAwayForOverlay` does, StreamScreen.swift:250-256), remember whether the keyboard was up, and
  `overlay.setKeyboard(shown: false)`. From Take the Tour the Settings panel has already taken the
  keyboard down: take its `keyboardBeforeSettings` (:86-88) before closing the panel with
  `restoreKeyboard: false`.
- **While it shows:** the layouts do not hit-test and the tour's layer takes every touch, so
  nothing reaches `InputOverlayView` (the direct touch, the Pencil, the iPad's own trackpad and
  mouse, hover) or `TrackpadSurface`. The one exception is the end of a gesture that began before
  the tour and is still held (a trackpad drag held still for a second): UIKit keeps delivering a
  touch to the view it began in, so its lift sends the button up, and no button is ever left down
  on the Mac. The quiet second makes this rare.
- **End** (Done, Skip, a rotation with nothing left): hit testing back; the keyboard back if it was
  up.
- **`StreamClient.lastInputAt`** (main thread, systemUptime, not published): stamped in `sendInput`
  (StreamClient.swift:2196) before its hop to the network queue. Every input passes there, a coast
  after a flick included, so the quiet second waits for a coast to end.
- **The tripwire, DEBUG only:** `StreamClient.tourShowing`, set by `StreamScreen`. `sendInput`
  prints "tour: INPUT SENT WHILE THE TOUR SHOWED: …" if it is ever called while it is true. In the
  gates, where nothing touches the screen, it never prints; on a device it may name the button-up
  of the exception above, and nothing else.

### 7. Copy

‹Mac› is `client.macName` ("your Mac" if empty, which the rule never lets happen); ‹device› is
"iPad" or "iPhone" (`StreamClient.deviceWord`). The words are the App Store description's where it
has them (docs/app-store-metadata.md §5: "Tap to click. Touch and hold to right-click. Drag to
scroll."). The name in each row is semibold. The check pins every string.

| Step | Title | Subtitle | Rows (symbol · text) | Spoken where (the title's hint) |
|---|---|---|---|---|
| `touch` | Tap, Hold and Drag | What you do here happens on ‹Mac›. | `hand.tap` · **Tap** to click.<br>`contextualmenu.and.cursorarrow` · **Touch and hold** to right-click.<br>`hand.draw` · **Drag** to scroll.<br>`applepencil` · **Apple Pencil** works as a mouse. (iPad only) | Landscape: "The picture of ‹Mac› fills the screen below the bar." Portrait: "The picture of ‹Mac› fills the top half of the screen." |
| `windows` | Windows and Apps | — | `magnifyingglass` · **Apps** finds any window on ‹Mac›, or opens an app.<br>`rectangle.on.rectangle` · **Tap a thumbnail** to show that window.<br>`hand.point.up.left` · **Touch and hold** a thumbnail to close, minimize or go full screen. Keep holding and drag to move it. | Landscape: "At the left of the bar at the top." Portrait: "At the left of the bar below the picture." |
| `bar` | Landscape: Aa, Keyboard and Desktop. Portrait: Aa and Desktop | — | `textformat.size` · **Aa**: touch it and slide to make text larger or smaller.<br>`keyboard` · **Keyboard** types on ‹Mac›. A hardware keyboard works too. (landscape only)<br>`desktopcomputer` · **Desktop** shows ‹Mac›’s whole screen. | "After the thumbnails, in the bar." |
| `settings` | Settings | — | `gearshape` · **Settings** changes the picture: quality, resolution and frame rate.<br>`xmark.circle` · **Disconnect** is at the bottom of Settings.<br>`questionmark.circle` · **Take the Tour** is there too, to see this again.<br>`ipad` or `iphone` · **Hold your ‹device› upright** for a trackpad and keys. (landscape only) | "The last button in the bar." |
| `keys` | Keys | Only on the upright remainder's first card: "Upright, Sill adds keys and a trackpad." | `command` · **cmd, opt, ctrl and shift** stay on for the next key or trackpad click: tap cmd, then C, to copy.<br>`keyboard` · **The keyboard key** brings up the keyboard. A hardware keyboard works too. | "The row of keys below the bar." |
| `trackpad` | Trackpad | — | `cursorarrow` · **Drag** to move the pointer.<br>`cursorarrow.click` · **Tap** to click. Tap with two fingers to right-click.<br>`arrow.up.and.down` · **Two fingers** scroll.<br>`hand.draw` · **Touch and hold, then drag** to move a window or select text. | "The bottom of the screen." |

- **Spoken, where it differs from the screen:** the `keys` row reads "Command, Option, Control and
  Shift stay on for the next key or trackpad click: tap Command, then C, to copy.", as the key
  row's own caps are named (PortraitStreamScreen.swift:342-355).
- **Buttons:** "Skip", "Next", "Done". Skip's hint: "Ends the tour. Take the Tour in Settings shows
  it again."
- **Why each row says what it says** (checked against the code at cf05a78):
  - A tap on the picture clicks and a long press (0.45 s) right-clicks (InputOverlay.swift:61-69,
    :118-134); one or two fingers scroll with momentum (:71-76, :141-173); the Pencil is the left
    button (:219-269).
  - A thumbnail's tap selects; a 1.5 s hold opens the lights; moving more than 8 pt then lifts and
    drags it (StreamScreen.swift:714-718, :786-802).
  - Aa opens on touch and applies on release; a tap alone changes nothing (:596-618).
  - The modifiers latch until a key, a typed character or a trackpad click spends them
    (PortraitStreamScreen.swift:439-457, TrackpadView.swift:419-456). A tap on the picture does not
    spend them (InputOverlay.swift:118-124), hence "trackpad click".
  - The trackpad: a drag moves the pointer, a tap clicks, a two-finger tap right-clicks, two
    fingers scroll, a 0.45 s hold then a drag drags (TrackpadView.swift:166-203, :389-415). Its own
    hint, "Drag to move the pointer. Tap to click, two fingers to scroll." (:32), stays visible in
    the spotlight; the card adds the right-click and the drag.
  - Disconnect is the panel's pinned last row (HostSettingsPanel.swift:152-170).

### 8. The Settings panel: Take the Tour

- **Where:** the last group of the panel's scrolling rows, after Away from home (or after the Direct
  Wireless footnote when there is no Away from home group), outside the `if let state` branches,
  so it is there while settings load and for a Mac without them (HostSettingsPanel.swift:174-260).
  Last because it is this device's, not the Mac's, and the outer display's 259 pt shows the Mac's
  rows first.
- **The row:** a `Rows { Button }` like Pair This iPad… (:333-342): "Take the Tour", accent,
  leading, 44 pt. Its footnote: "A short tour of Sill’s controls on this ‹device›." Its
  accessibility hint: "Shows how to use Sill on this ‹device›."
- **What it does:** a `takeTour` closure, passed as `pairThisDevice` is (:23-25, StreamScreen.swift
  :365 and PortraitStreamScreen.swift:196), takes the panel's `keyboardBeforeSettings`, closes the
  panel without restoring the keyboard, and once the panel's 0.18 s close has run
  (StreamScreen.swift:273-274) starts every step of the layout on screen, from the first.
- **Nothing about the Mac changes:** the row sends nothing, and the panel's other rows are as they
  are. Every `-SillSettings 1` photo gains the row at the end.

### 9. Files

| File | Change |
|---|---|
| `iOSClient/TourPolicy.swift` (new; pure: Foundation and CoreGraphics; checked with swiftc) | `TourTopic`, `TourLayout`, `TourTarget`, `TourMemory`, the steps and targets (§3), the rule (§4), `passed`, `skipped` and `carry` (§3.2, §5), `place` and `crease` (§6.3), and every string (§7) as `TourCopy` values built from ‹Mac› and ‹device›. pbxproj IDs `A1000001000000000000A401` / `…F401` |
| `iOSClient/TourOverlay.swift` (new) | `TourDim`, `TourCard`, `TourCardLayout`, the `tourTarget` modifier and its preference, `TourStore` (the two keys, and Debug's `-SillTourState`), the scripted presses (§10) and the console lines. IDs `…A402` / `…F402` |
| `iOSClient/StreamScreen.swift` | The run and the rule's inputs as `@State` (`tour`, `targets`, `pictureAt`, `layoutAt`, `offered`), the coordinate space, the layer (§6.1), `startTour` and `endTour` (§6.6), an outside link putting the tour aside, the targets in TopBar and `contentArea`, and the DEBUG init's `tour:` |
| `iOSClient/PortraitStreamScreen.swift` | The targets in `streamPane`, `windowBar`, `KeyRow` and `Trackpad`; `takeTour` passed to the panel |
| `iOSClient/HostSettingsPanel.swift` | Take the Tour (§8) and its `takeTour` closure |
| `iOSClient/StreamClient.swift` | `lastInputAt` in `sendInput`; DEBUG `tourShowing` and the tripwire (§6.6) |
| `iOSClient/ContentView.swift` | The harness: `Spec` gains `tour` and passes it on; the contract comment (§10) |
| `iOSClient/Sill.xcodeproj/project.pbxproj` | The two files' four entries each, by hand: build file, file reference, group, sources phase |
| `Tests/checks/tour/` (new) | `main.swift`, `run.sh`, `mutants.py` (§13, H2) |
| `Tests/checks/README.md`, `.github/workflows/ci.yml` | The check's row; `tour` in the mutants matrix (ci.yml:122) |

- **The IDs.** Main's iOS files use A001–A01E, A101 and A201. The open branches take A01E (home
  pairing's `StreamClient+Home.swift`, renumbered at its merge with main, likely to A01F), A020
  (remote pacing's `MessageReader.swift`) and A301 (pointer visibility's `PointerPresence.swift`).
  The tour takes the A401 range, which none of them touches.
- **Swift 5 language mode,** as now. Nothing in `Sources/`, `Packaging/`, `Scripts/`,
  `Info.plist` or `PrivacyInfo.xcprivacy` changes.

The pure half, as a sketch:

```swift
struct TourMemory: Equatable { var seen: Set<TourTopic> = []; var skipped = false }

enum TourPolicy {
    static let beat = 1.0, quiet = 1.0, chance = 10.0            // seconds
    static func owed(_ layout: TourLayout, _ m: TourMemory) -> [TourTopic] {
        m.skipped ? [] : steps(layout).filter { !m.seen.contains($0) }
    }
    static func passed(_ t: TourTopic, _ m: TourMemory) -> TourMemory       // seen += t
    static func skipped(_ m: TourMemory) -> TourMemory                      // skipped = true
    /// A layout change mid-run: the step now, or nil when the new layout has none left.
    static func carry(_ current: TourTopic, run: [TourTopic], passed: Set<TourTopic>, to layout: TourLayout,
                      replay: Bool, memory: TourMemory) -> (run: [TourTopic], at: TourTopic)?
    static func copy(_ t: TourTopic, _ layout: TourLayout, mac: String, device: String,
                     firstOfRemainder: Bool) -> TourCopy
}
```

### 10. Harness and DEBUG arguments (ContentView's contract comment at :55-171, and CLAUDE.md)

- **`-SillTour touch|windows|bar|settings|keys|trackpad`:** the stream screen starts with the tour
  open at that step, as Take the Tour shows it (every step of the layout, from that one on), with
  no beat. In the mock and under `-SillLive 1`. A step the layout lacks (`trackpad` at 1000x710)
  starts at the first.
- **`-SillTourState fresh|landscape|done|skipped|saved`:** in the normal app, under `-SillLive 1`
  and in the mock:
  - it turns the automatic tour on, which a Debug build otherwise never shows (open question 10);
  - `fresh` is nothing seen, `landscape` the four landscape steps seen (so an upright size shows
    `keys` and `trackpad`), `done` everything, `skipped` Skip tapped: for this run only, never
    written back;
  - `saved` reads and writes the saved keys, as a Release build does.

  In the mock the picture counts from launch.
- **`-SillTourPress next@S|skip@S`:** Debug only, a stand-in for a tap, since the gates may not
  drive the UI: S seconds after each card appears, press Next (Done on the last), or once, Skip.
- **Without any of them the mock never shows the tour,** and neither does a Debug build of the
  normal app: every harness photo and every other feature's live test stays as it is. Release and
  TestFlight builds always follow the rule.
- **Console lines** (Debug), each printed when its event happens:

```
tour: owed here: touch, windows, bar, settings (landscape; seen: none)
tour: waiting until 1.0 s after the picture
tour: waiting: the Apps list is open
tour: showing touch (1 of 4)
tour: passed touch
tour: carried to windows (portrait → landscape)
tour: put aside for a pairing link; back at windows after it
tour: done (saved: touch, windows, bar, settings)
tour: skipped (saved)
tour: not this session: no quiet second within 10 s of the picture
tour: INPUT SENT WHILE THE TOUR SHOWED: …        (the tripwire; never expected)
```

### 11. Timeouts and limits

| What | Value |
|---|---|
| The beat after the first picture, or after the layout turned | 1.0 s |
| The quiet before it shows | 1.0 s without input from this device |
| Its chance | Within 10 s of the picture, or of the layout change for the upright remainder; once per session and layout |
| The dim | Black, 0.58 |
| The ring | 2 pt, `Palette.accent`, 4 pt outside the targets |
| The card | 360 pt wide (560 at accessibility sizes, never more than the screen less 32); 16 pt from the edges; 12 pt from its targets |
| The tail | 16 × 7 pt; only where §6.3 allows |
| Motion | In 0.25 s, a step 0.35 s, out 0.2 s; under Reduce Motion 0.2 s fades |
| Kept | `Sill.tourSeen` (six topic names at most today), `Sill.tourSkipped` |

### 12. Edge cases

| Case | Behaviour |
|---|---|
| The session ends during the tour (Sill.app quits, a notice, the network goes) | The tour goes with the stream screen. Steps passed stay passed; the next session starts at the first step owed, with its own beat and chance |
| A Mac refuses this device's version (the floor) | Never shows: no window list, no picture (§4.1) |
| The first session is remote, or over the cable | The same rule; the tour does not care how the session came |
| Pairing at home (after `home-pairing` lands) | The card on the connect screen, "Paired with Mac mini.", then the session: the tour follows its picture. Over the cable, "Paired with Mac mini over the cable." then the same |
| An outside `sill://pair` link during the tour | The tour is put aside (not closed, nothing saved); the pairing overlay shows; when it closes and the session still streams, the tour comes back at the same step |
| The person rotates, resizes (Split View, Stage Manager) or folds the Duo during the tour | §3.2 |
| Nothing is open but a coast from a flick is still sending | Every coast step passes `sendInput`, so the quiet second starts when it ends |
| The software keyboard is up when the chance opens | The automatic tour waits (busy) within its 10 s; Take the Tour takes it down and puts it back after |
| A latched modifier in the key row | Kept through the tour; spent by the next key or trackpad click after it |
| A Mac with no windows | `windows` lights the Apps button and the empty strip; the words hold |
| A Mac with an older Sill (no settings) | The `settings` card still says what Settings is for; the panel then says to update Sill on the Mac. Accepted |
| The app goes to the background during the tour | The tour is there on return, at the same step |
| The Desktop cannot stream (the Mac lacks Screen Recording) | No picture, so no tour: the black panel is the Mac's to fix |
| VoiceOver on | The same rule. The stream itself is out of VoiceOver's reach today (the picture and its input view are no accessibility elements and have no direct-touch trait), which is outside this step |
| A hardware keyboard and no touch at all | Return goes through the tour; Esc skips it |
| Two taps on Next in quick succession | Two steps; nothing is lost but the reading (Take the Tour replays) |
| Take the Tour on a layout, then a rotation | §3.2, with the run being every step of the new layout |
| The Pencil or the iPad's trackpad hovering over the dim | The layer above takes the hover; the Mac's pointer does not move (P1) |
| The Mac's own pointer (pointer visibility, once merged) | Drawn under the dim, as the picture is |

### 13. Test gates

**Hard rules for the implementing session:**
- **Disk and build folders:** at least 25 GB free before any build (`df -g /System/Volumes/Data`);
  DerivedData under the session's scratch folder, deleted at the end.
- **The simulator:** a private one named "Sill walkthrough", deleted at the end:
  - an iPad Pro 13-inch (M5) for the Duo sizes and the iPad;
  - then, the iPad one deleted, an iPhone 18 Pro Max of the same name for the iPhone rows. One at
    a time.
  - `xcrun simctl io <udid> screenshot` only: never XCUITest, never `recordVideo`, never the Claude
    iOS Simulator panel.
- **Live runs:**
  - only `SillHost --synthetic` on loopback, reached with `-SillConnect 127.0.0.1:P`;
  - only while `Scripts/encoder-check/no-device.sh` passes, before and every 2 s during (the
    synthetic host uses the hardware encoder);
  - each host under 60 s, started with `start_new_session=True`, killed by PID, none left running;
  - **no input is ever sent to a host** (a synthetic host on main posts real events on this Mac);
  - if macOS's Application Firewall asks about the new SillHost binary, the gate stops and the
    hand-off says so.
- **Never touch** `/Applications/Sill.app` or connect anything to it; never install anything on
  Noah's devices; never push to main.

**Headless (H):**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). The base is this plan's commit; build it for the simulator; H4's baseline photos from it | The photos exist; the disk rule holds |
| H1 | **Builds.** iOS Debug and Release for the simulator (`ARCHS=arm64 CODE_SIGNING_ALLOWED=NO`), Debug for a generic device (unsigned) | `** BUILD SUCCEEDED **` with only the known `StreamClient` capture warning |
| H2 | **The pure check**, `Tests/checks/run-all.sh tour`, at least 140 cases: the steps and targets per layout; `owed` for each memory; the rule at every boundary (0.99 and 1.0 s of beat and quiet, 10.0 and 10.01 s of chance, busy, `offered`, `enabled`, `skipped`, nothing owed, the remainder opening at the turn); `passed`, `skipped`, a session ending; `carry` for every step both ways, and a run with nothing left; `crease` against a copy of `ConnectLayout.topHalf` at 20 sizes; `place` pinned for every step at the four Duo sizes at default and accessibility text, and at a 400-size grid: inside the margins, inside its region, never over its targets (except `touch`, and the accessibility case §6.3 allows), never across the crease, a tail only where allowed and its tip within the card's straight edge; every string of §7 for "Mac mini" and "iPad", "iPhone" (no Pencil row), the "your Mac" fallback, the landscape-only rows, the remainder's subtitle. `--mutants tour`, at least 18 (§14 step 1) | All pass; every mutant caught; `Tests/checks/run-all.sh` passes whole |
| H3 | **Hard rules by grep** | No `.sheet(`, `.popover(`, `popoverTip`, `fullScreenCover`, `.alert(`, `import TipKit` or `Tips.` in `Tour*.swift`; no `sendInput`, `client.send`, `select(`, `launch(`, `command(` or `changeSettings` there either; `TourPolicy.swift` imports Foundation and CoreGraphics only; `git diff origin/main --stat -- Sources Packaging Scripts iOSClient/Info.plist iOSClient/PrivacyInfo.xcprivacy` is empty; A401, F401, A402, F402 each appear in their four places |
| H4 | **Nothing else changed on screen.** At 1000x710, 710x1000, 500x710 and 710x500: the mock with no argument, `-SillDrawer 1`, `-SillWindowMenu 1`, `-SillScaleOpen 1 -SillScale 1.5`, `-SillActive none`, `-SillScanOverlay 1`, `-SillConnectCase methods`, `-SillConnectCase addmac` (32 photos), base against this build | Pixel for pixel equal. `-SillSettings 1` at the four sizes differs only at the rows' end (the new row), or not at all where the end is out of view |

**Simulator (S), photographed and sheeted per size:**

| # | Check |
|---|---|
| S1 | **Every step at every size.** `-SillTour <step>` for the four landscape steps at 1000x710, 710x500, 1376x1032 (drawn turned; `sips -r 270`) and 956x440; the six portrait steps at 710x1000, 500x710, 1032x1376 and 440x956. That is 16 landscape and 24 portrait photos; the iPhone rows run on the iPhone simulator, so they read "iPhone" and have no Pencil row. Each photo: the ring on the right controls; the card in its region with its tail as §6.3 says; nothing crosses y = 500 at 710x1000; nothing is truncated. Send Noah the sheets |
| S2 | **Text size**, `xcrun simctl ui <udid> content_size`: every step at 500x710, 710x500 and 710x1000, at `extra-extra-extra-large` and `accessibility-extra-extra-extra-large` (32 photos). The title and rows wrap; the rows scroll with the footer whole and reachable; at 710x1000 the card stays in the upper half |
| S3 | **Take the Tour.** `-SillSettings 1 -SillSettingsEnd 1` at 500x710, 710x500 and 1000x710, cases `default`, `legacy` (no settings: the row is still there) and `remotepair`, at the default size and at xxLarge (the panel's cap) |
| S4 | **The rule, in the mock.** `-SillTourState fresh` at 1000x710: no tour in a photo at 0.5 s, the `touch` card at 2.5 s. `landscape` at 710x1000: at 2.5 s the `keys` card with the remainder's subtitle and two dots. `done` and `skipped`: nothing at 5 s. `fresh` with `-SillDrawer 1`: nothing at 12 s (the drawer stays open past the chance). `fresh` with `-SillScanOverlay 1`: nothing at 5 s. With `-SillTourPress next@1` at 1000x710: Done after the fourth card, the console's "tour: done (saved: …)", nothing written (`fresh`) |
| S5 | **Live**, one host at a time. (a) `-SillLive 1 -SillLayout 1000x710 -SillConnect 127.0.0.1:P -SillTourState fresh`: "tour: showing touch (1 of 4)" between 1.0 and 2.5 s after the console's `host:` line (the first window list; the picture follows it); a photo of the card over the test pattern. (b) On a fresh install (`xcrun simctl uninstall`, then `install`), the same with `saved` and `-SillTourPress next@1.5`: kill the host while the third card shows. Back on the connect screen, `plutil -p "$(xcrun simctl get_app_container "Sill walkthrough" me.saffer.sill data)/Library/Preferences/me.saffer.sill.plist"` lists `Sill.tourSeen` with touch and windows. A new host and the same launch: the tour starts at `bar`, "1 of 2". (c) A host with `SILL_TEST_MIN_DEVICE_VERSION=99` and `-SillTourState fresh`: the notice on the connect screen and no `tour:` line in 10 s. (d) The console never prints the tripwire |

**Noah's devices (P), handed over at the end:** the iPad mini and the iPhone 15 Pro. The automatic
tour needs a Release or TestFlight build on a fresh install, or the Debug build launched with
`-SillTourState fresh` (Xcode's scheme, Arguments).

| # | Check |
|---|---|
| P1 | **The first picture.** About a second after the Mac's Desktop shows, the tour dims the screen and lights the picture. While it shows: tap, hold and drag on the dimmed picture; press keys on a hardware keyboard; hover and touch with the Pencil; use a trackpad or mouse on the iPad. Nothing happens on the Mac (its pointer does not move; the host's `[1s]` lines show no `in.pointer`, `in.scroll`, `in.text` or `in.key` meanwhile), and the picture keeps moving |
| P2 | **Each step** lights the control it names, in both layouts, and Done ends it. Held upright after a tour in landscape: `keys` and `trackpad` show about a second after the turn, once |
| P3 | **Interrupted.** Quit Sill.app on the Mac at the third card; reopen it. The next session's tour starts at the first step not passed |
| P4 | **Take the Tour,** in both layouts, with the keyboard up before opening Settings: the tour runs, and the keyboard is back after Done |
| P5 | **Skip** on the first card: no tour at the next session, nor when held upright |
| P6 | **VoiceOver:** focus on the title; each row read whole; the escape gesture skips; Magic Tap goes on; after Done, the stream screen is read afresh |
| P7 | **The largest text size** (Settings › Accessibility › Display & Text Size › Larger Text): every card readable, its rows scroll, Skip and Next reachable |
| P8 | **Reduce Motion:** fades only |
| P9 | **A hardware keyboard:** Return goes on, Esc skips |
| P10 | **An outside link** (the Camera on the Mac's pairing QR code) during the tour: the tour steps aside, the confirmation shows; Cancel, and the tour is back at its step |
| P11 | **The iPhone,** upright and sideways: the cards clear the Dynamic Island and the home indicator, and read "iPhone" with no Pencil row |

### 14. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit): H0.
1. **"iOS: the tour's rules, checked on their own."** `TourPolicy.swift` with its pbxproj entries;
   `Tests/checks/tour`; the README row; the CI matrix. The mutants, at least:
   - the beat, the quiet or the busy test dropped;
   - the chance never closing;
   - `offered` ignored;
   - `skipped` ignored;
   - `enabled` inverted;
   - Next not saving;
   - Skip not saving;
   - the upright steps owed in landscape;
   - the remainder's subtitle on a card that is not the run's first;
   - `carry` going to the first step instead of the next one owed;
   - the crease ignored;
   - a tail across the crease;
   - the card not clamped;
   - a landscape card above its targets;
   - the Pencil row on iPhone;
   - the upright row in portrait;
   - one word of the copy changed.

   Gates: H1, H2.
2. **"iOS: a tour of the stream screen, once, after the first picture."** `TourOverlay.swift`; the
   targets; the layer and the rule in `StreamScreen`; the pause; `lastInputAt` and the tripwire;
   the keys and VoiceOver; the harness arguments and the contract comment. Gates: H1, H3, H4, S1,
   S2, S4, S5.
3. **"iOS: Take the Tour in the Settings panel."** Gates: H1, H4 (the panel's photos differ only
   by the row), S3.
4. **"docs: the tour."** §16, and this plan's Results. Gates: none new.
5. **Review and hand-over.** Three lenses:
   - when it shows (the rule, sessions ending, pairing, notices, rotation);
   - the pause (no touch, pointer, hover or key reaches the Mac; the keyboard's round trip);
   - the UI at every size, text size, VoiceOver and Reduce Motion.

   A "Review fixes" commit if needed, then S4 and S5 again on the final build. Hand P1–P11 to
   Noah. **Stop there.**

### 15. Hard rules (for every step)

- **Apple frameworks only:** SwiftUI and UIKit. No TipKit in this step.
- **No wire change, and nothing sent:** the tour sends nothing to the Mac, and while it shows the
  device sends no input either, but for the end of a gesture held from before it (§6.6).
  `StreamProtocol`, the host, the CLI and Sill.app are untouched.
- **No system presentation:** no sheet, popover, alert or full-screen cover. The tour is a view
  in the stream screen's hierarchy, as the Settings panel and the pairing overlay are.
- **Never over pairing or a notice:** never on the connect screen, never over the pairing overlay
  or a link's confirmation.
- **Nothing collected:** two UserDefaults keys, read and written by this app alone (the privacy
  manifest's CA92.1). No analytics of how far anyone got.
- **Every layout:** the Duo's 1000×710, 710×1000, 500×710 and 710×500; iPhone upright and
  sideways; iPad. VoiceOver, every text size, Reduce Motion.
- **iOS 17.0 APIs,** or an `#available` check with a fallback.
- **The harness and every Debug run look as before** unless a `-SillTour…` argument asks.
- **New iOS files:** four pbxproj entries each, by hand. Swift 5 language mode.
- **Tests** follow §13's rules: the private simulator, screenshots only, synthetic hosts on
  loopback while no device is connected, no input to any host.

### 16. Docs to update (step 4)

- **CLAUDE.md:** the Current step entry; Layout (`TourPolicy.swift`, `TourOverlay.swift`,
  `Tests/checks/tour`); Build and run (the harness arguments of §10).
- **`ContentView.swift`'s contract comment:** §10 (in step 2).
- **docs/DEVELOPMENT.md, The iOS app:** the tour, how to see it again, and the arguments.
- **docs/app-store-metadata.md:**
  - §4, "Kept on the device only": which steps of the tour were seen;
  - §7, the review notes' WHAT TO TRY: "The first time your Mac's picture shows, a short tour
    points out the controls. Settings › Take the Tour shows it again.";
  - §9, How to capture them, step 4: the tour shows about a second after the picture; skip it,
    or take it once, before the screenshots.
- **docs/release-checklist.md,** TestFlight §8: the same line for the screenshot session.
- **site/privacy.html,** "On your iPhone or iPad": "Which parts of the tour you have seen." The
  site reaches getsill.app with the next republish (the checklist's TestFlight §3).
- **Tests/checks/README.md:** the `tour` row.

### 17. The base, other branches, and what comes later

- **Base:** origin/main at cf05a78. Noah's queue puts this after home pairing
  (`home-pairing`, not merged). Whichever lands second takes the other's changes in:
  - `HostSettingsPanel.swift`: home pairing rewrites Away from home; Take the Tour goes after it,
    whatever its cases become;
  - `StreamScreen.swift`: three lines there;
  - `ContentView.swift`'s contract and `MockCatalog.swift`: new cases on both sides;
  - `project.pbxproj`: new files on both sides, different IDs.

  Home pairing's flows end on the connect screen before any picture, so the rule needs nothing
  from it.
- **Pointer visibility** (`pointer-visibility`) changes the call sites in `StreamScreen` and
  `PortraitStreamScreen` that the targets sit beside; a small merge either way. Its arrow is drawn
  under the dim.
- **Trackpad gestures** (`trackpad-gestures`, planned): its three- and four-finger gestures become
  rows of the `trackpad` step, or a topic of their own, owed once to everyone who did not skip
  (§5).
- **The menu bar mirror** (`menu-bar-mirror`): a new bar control is a new topic, the same way.
- **Later, not planned:** single hints after the tour (TipKit's `TipGroup` on iOS 18, or the
  same overlay with one card), and "try it" steps (open question 5).

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **The form.** Default: **coach marks over the live controls**, in the view hierarchy, one step
   at a time. The alternatives: a paged card with drawings, or TipKit tips (Decision).
2. **When it first shows.** Default: **1 s after the first picture, at the first quiet second
   within 10 s**; else at the next session's start. The alternatives: at the connection, before
   the picture; or at any quiet moment of the session, however late.
3. **What "once" means.** Default: **each step until it is passed, or all of it once skipped**; a
   session that ends mid-tour leaves the rest for the next one. The alternative counts the whole
   tour as seen once its first card has shown.
4. **The upright steps.** Default: **after a tour in landscape, `keys` and `trackpad` show the
   first time the device is held upright**, with their own chance. The alternative: only through
   Take the Tour.
5. **Input while it shows.** Default: **paused** (as asked): no touch, Pencil, pointer or key
   reaches the Mac, and the picture keeps moving. The alternative: "try it" steps that let each
   gesture through and go on once it is done.
6. **A tap outside the card.** Default: **nothing, and Next nudges.** The alternatives: it goes to
   the next step; it closes the tour, as a tip would.
7. **Back.** Default: **none;** Take the Tour replays. The alternative: a Back button beside Skip.
8. **The row's name and place.** Default: **"Take the Tour", the last row of the Settings panel's
   scrolling rows.** The alternatives: "How to Use Sill"; beside Disconnect in the pinned foot; a
   "?" button in the bar (the outer display's bar has no room for it).
9. **Text size.** Default: **every size, the accessibility sizes included;** the card scrolls, and
   upright on a screen with no crease it may cover its own spotlight at those sizes. The
   alternative: capped at xxLarge, like the Settings panel.
10. **Debug builds.** Default: **the automatic tour only with `-SillTourState`,** so no harness
    photo or other feature's live test ever gets a tour over it; Release and TestFlight always
    follow the rule. The alternative: Debug as Release, and every test run passes
    `-SillTourState done`.
11. **Existing installs.** Default: **no migration;** everyone sees it once (only development and
    TestFlight builds exist). The alternative: skip it on a device that has connected before (a
    saved window order or a saved Mac).
12. **The words.** Default: **§7's table,** in the App Store description's words; the check pins
    them, so a change is one edit there and one in the check.
13. **The Pencil row.** Default: **on iPad only.** The alternative: none; the Pencil acts as a
    mouse the moment it touches.
14. **Hints after the tour.** Default: **none in this step.** The alternative, later: single
    hints for what a person has not used after some sessions (TipKit's `TipGroup` on iOS 18, or
    this overlay with one card).
