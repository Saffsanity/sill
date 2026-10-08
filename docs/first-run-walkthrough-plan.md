# The first-run walkthrough — the plan

2026-09-27. It stands alone: the implementer needs no other design document. Written from a
read-only survey of origin/main at cf05a78 (PR #28) in the worktree
`/Users/noah/Downloads/winstream-walkthrough` (branch `first-run-walkthrough`); line numbers are at
cf05a78, and every file named here is to be read again before it is changed. Revised the same day
by an adversarial critique against the code and Apple's Human Interface Guidelines (Onboarding,
Offering help, Modality, Gestures, VoiceOver, Typography, Accessibility, Launching and Popovers,
read on developer.apple.com on 2026-09-27): §18 lists what it found and what changed. Nothing was
built or run for either pass. The SF Symbols named here were looked up in this Mac's symbol catalog
(`name_availability.plist` in SFSymbols.framework) for the iOS version each first shipped in: the
app targets iOS 17.0, and every symbol here is iOS 17.0 or older.

**Noah's request (2026-09-26):** "Add to feature list, app usage walkthrough first time after
pairing/connecting".

**Reading of it.**
- **What it teaches is the stream screen:** how to use the Mac from the device once connected.
  That is touch on the picture, the bar (the thumbnails, Aa, Keyboard, Settings), the portrait
  laptop layout (the key row and the trackpad), and where Disconnect is. Not the Mac's setup (its
  Permissions pane does that), not pairing (the card and the Mac's window say what to do), not the
  connect screen.
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

A second after the first picture from a Mac, if nothing has happened since (no touch anywhere on
the screen, nothing sent to the Mac, nothing open), the stream screen dims and a card points at one
part of it at a time: the picture (tap, hold, drag), the thumbnails with Aa (sideways, Keyboard
too), and Settings; held upright, also the keys and the trackpad. Three cards sideways and four
upright, each a few short rows in the App Store description's words, with Skip and Next. Someone
who touched anything in that second is left alone for the session. The picture keeps moving
underneath, and nothing reaches the Mac while the tour shows. Skip ends it for good on this device
(in Take the Tour it only closes it) and Done ends the run; a step passed stays passed if the session ends first; after a tour taken
sideways, the upright card comes the first time the device is held upright and left alone for a
second; and the Settings panel's last row, Take the Tour, shows it again. All of it is on the
device: no wire change, nothing sent, two UserDefaults keys.

### The form: coach marks over the live controls

| Criterion (0–10) | **A: coach marks over the live controls (chosen)** | B: a paged card with drawings | C: TipKit tips | D: a welcome page, then A |
|---|---|---|---|---|
| Shows where each control is | 10: the control itself, lit | 4: a picture of it | 8: a popover beside it | 10 |
| Every layout with no extra art (the Duo's four sizes, iPhone, iPad, rotation) | 9: the spotlight follows the controls | 4: art per layout, or art that matches none | 5: popovers adapt by size class | 8 |
| Fits the client's rules (no system presentation, the crease, the harness) | 9 | 8 in the view hierarchy (3 as a `.sheet`) | 3: `popoverTip` is a system popover, and a `TipView` holds one hint | 9 |
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

**Why not TipKit (C).** TipKit is Apple's and allowed, and the HIG's first advice on help is its
kind: tips in context rather than one flow. For this job:
- `popoverTip` presents a system popover: the three reasons above.
- An inline `TipView` stays in the hierarchy, but its layout is TipKit's (an image, a title, a
  message, actions, and a close button that invalidates that one tip): one hint, not a card of
  rows with a step count and a Skip for the whole tour.
- iOS 17, the deployment target, has no `TipGroup` (iOS 18). An ordered walkthrough would be built
  by hand from rules and parameters, and TipKit decides when an eligible tip displays.
- Seeing it again fits badly: an invalidated tip stays invalid in TipKit's datastore, so Take the
  Tour would need `Tips.resetDatastore()` or parameter rules.
- It adds a datastore, set up by `Tips.configure()` at launch, where two UserDefaults keys do.
- Where it could fit later: single hints after the tour, on iOS 18's TipGroup (open question 14).

**Why a flow at all.** The HIG prefers tips in context and teaching by doing. Noah asked for a
walkthrough, and the only thing to try here is a click on the person's own Mac, which is not the
safe test the HIG has in mind (open question 5). So it is a flow, held to the HIG's other rules for
one: brief, optional, gone for good once skipped, and easy to find again in Settings.

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
- **One decision, a second later.** 1 s after the picture the tour shows if nothing has happened
  since the picture: no touch anywhere on the screen (a watcher on the window sees the bar, the
  picture, the thumbnail strip's scrolling, the Pencil and the iPad's trackpad or mouse, §6.6), no
  input sent to the Mac (a hover, a key or a coast included), no touch still down, and nothing
  open (the Apps list, the Settings panel, a thumbnail's traffic lights, the Aa ruler, the software
  keyboard, the pairing overlay or an outside link's confirmation), with the app active. Otherwise
  the session passes. Someone who starts at once is never interrupted, not a second later and not
  at their first pause; the next session asks again, and the start of a session is a natural pause.
- **A turn.** After that decision, the first time the session's layout changes, the same test runs
  a second after the new layout is on screen, for the steps only that layout has (upright:
  `laptop`), never for the shared ones: someone who turns the device mid-work is not walked through
  the picture again.
- **Never on the connect screen.** The pairing card, the Mac's notices ("Update Sill…") and every
  status line live there. Never over the pairing overlay: an outside link that arrives during the
  tour puts the tour aside until the overlay has closed.

### What it teaches, per layout

| Step | Lit | Landscape (inner 1000×710, outer 710×500, iPhone and iPad sideways) | Portrait, the laptop layout (inner 710×1000, outer 500×710, iPhone and iPad upright) |
|---|---|---|---|
| `touch` | The picture | 1 of 3 | 1 of 4 |
| `bar` | The thumbnails and Aa; sideways also Keyboard (upright the keyboard is a cap in the key row) | 2 of 3 | 2 of 4 |
| `settings` | Settings | 3 of 3, Done | 3 of 4 |
| `laptop` | The key row and the trackpad | — | 4 of 4, Done |

- **Order.** Where things are: the picture first (it matters most), then the bar from left to
  right, then down the laptop half. The spotlight travels in reading order.
- **What gets a row.** Only what a label cannot say: hold a thumbnail, slide on Aa, Keyboard (a
  hardware keyboard types on the Mac only once it is tapped: the input view forwards keys only
  while it is first responder, InputOverlay.swift:403-416, and nothing but Keyboard and the key
  row's keyboard cap makes it one), Disconnect inside Settings, the sticky modifiers, and the
  trackpad's two-finger tap and its hold, then drag. Labelled buttons that need no gesture (Apps,
  Desktop, the Settings button itself) and what the trackpad's own hint says (TrackpadView.swift:32)
  get none: the HIG asks help not to explain standard components.
- **The other layout.** The landscape tour's last card says the device can be held upright. The
  first time it is, `laptop` shows as a one-card run of its own (§4.2). A tour taken upright covers
  everything, so turning the device sideways later shows nothing new (the Keyboard button is
  labelled, and the `laptop` card named the keyboard key).
- **Under VoiceOver,** what teaches raw touch goes: `touch`, and the trackpad's rows of `laptop`.
  VoiceOver takes those gestures for itself, and neither the picture nor the trackpad is an
  accessibility element. They stay owed, for a run without VoiceOver. The other rows are spoken
  the VoiceOver way (§7).

### While it shows, the Mac gets nothing

- **The picture keeps moving:** the stream, the stats and the keepalive run as before, so the
  person watches their Mac while they read.
- **No touch, Pencil, trackpad, mouse or key reaches the Mac**, as asked:
  - The layouts stop hit-testing, as they do under the pairing overlay (StreamScreen.swift:136-138).
    The tour's layer is a sibling above them and takes every touch, the lit control's included.
  - The software keyboard goes down (`InputOverlayProxy.setKeyboard`, InputOverlay.swift:409-416).
    The input view forwards hardware keys only while it has the keyboard, so keys stop too, as they
    do under the Settings panel (StreamScreen.swift:258-279). It comes back at the end if it was up.
  - Nothing is in flight when it starts: the automatic tour needs no touch down and nothing sent in
    the second before it (§4), and Take the Tour starts from a button's lift with the keyboard
    already down (§8). No button or key is ever left down on the Mac.
- **A tap outside the card** does nothing but nudge Next, so trying the gesture a card describes
  never clicks something on the Mac behind the dim. The dim's tap area leaves out the card (§6.1).
- Why not let the gestures through and have the person try them: the first thing a new user does
  on their Mac would then be a click they cannot see under a card, and keys typed while reading
  would type on the Mac (open question 5).

### Skipping it, and seeing it again

- **Skip** on every card but the last ends the tour for good on this device: no automatic tour
  again, not even the upright card. In Take the Tour, which the person asked for, Skip only closes
  it (review fix: it saved the permanent skip there too).
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
   Dynamic Type and Reduce Motion, the input pause and the touch watcher.
3. **The stream screen:** the spotlight's targets in both layouts, the automatic start, and the
   tour's place above the layouts and below the pairing overlay.
4. **The Settings panel:** Take the Tour.
5. **The harness:** arguments for every step, state, scripted press and stand-in touch; console
   lines.
6. **Docs:** CLAUDE.md, DEVELOPMENT.md, the App Store metadata and checklist, the privacy page.

**Not in this step:**
- anything on the Mac, the CLI or `StreamProtocol` (no kind, no field, no log line);
- a tour of the connect screen, pairing or the Mac's setup;
- "try it" steps that let a gesture reach the Mac (open question 5);
- a Back button (open question 7);
- TipKit, or hints after the tour (open question 14);
- VoiceOver for the picture and the trackpad themselves (the tour leaves their steps out under
  VoiceOver);
- tours for controls not on main yet: the Mac's pointer, the trackpad's three-finger gestures, the
  menu bar mirror. Each adds a topic when it lands (§17).

### 2. The design on one page

```
 ┌─── the device only: no wire change, nothing sent to the Mac ───────────────────────────────────┐
 │ StreamScreen (one per session)                                                                 │
 │   the first picture (the window list, a frame size, a source) ──▶ pictureAt                    │
 │   TouchWatcher (every touch in the window) and sendInput ──▶ lastActivityAt, touchesDown       │
 │   TourPolicy.automatic(moment, layout, memory), 1 s after the picture or a turn                │
 │      ──▶ wait (the beat) | pass (something happened, or is open) | show(the steps owed)        │
 │   Settings › Take the Tour ──▶ show(every step of the layout on screen)                        │
 │   targets, as frames in the screen's coordinate space: stream, strip, textSize, keyboard,      │
 │   settings, keys, trackpad                                                                     │
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
 1000×710, step 2 of 3                            500×710, step 4 of 4
 ┌─────────────────────────────────────────────┐  ┌────────────────────────────────┐
 │ [Apps][= = = = = =][Aa][Kbd] [Desk][Set]    │  │  the picture, dimmed           │
 │       └──── lit, ringed ──────┘  dimmed     │  │ ┌────────────────────────────┐ │
 │    ┌─────────▲───────────────────┐          │  │ │ Keys and Trackpad          │ │
 │    │ Windows and Text Size       │  the     │  │ │ cmd, opt, ctrl and shif... │ │
 │    │ Touch and hold a window ... │  picture,│  │ │ The keyboard key types ... │ │
 │    │ Aa: touch it and slide ...  │  dimmed  │  │ │ Tap with two fingers ...   │ │
 │    │ Keyboard types on Mac mi... │          │  │ │ o o o *               Done │ │
 │    │ Skip        o * o      Next │          │  │ └────────────────────────────┘ │
 │    └─────────────────────────────┘          │  ├── the split ───────────────────┤
 │                                             │  │ [Apps][= =][Aa][Desk][Set]     │
 │                                             │  │ ┌── the keys, lit ───────────┐ │
 │                                             │  │ │ esc tab ctrl opt cmd ...   │ │
 │                                             │  │ │ the trackpad, lit          │ │
 │                                             │  │ └────────────────────────────┘ │
 └─────────────────────────────────────────────┘  └────────────────────────────────┘
```

### 3. The steps

#### 3.1 Topics, targets and orders

```swift
enum TourTopic: String, CaseIterable { case touch, bar, settings, laptop }
enum TourLayout: Equatable { case landscape, portrait }        // DuoLayout's inner/outer landscape, inner/outer portrait
enum TourTarget: String, CaseIterable { case stream, strip, textSize, keyboard, settings, keys, trackpad }

/// Under VoiceOver what teaches raw touch goes (§6.5); `laptop` keeps its keys rows (§7).
static func steps(_ layout: TourLayout, voiceOver: Bool) -> [TourTopic] {
    let all: [TourTopic] = layout == .landscape ? [.touch, .bar, .settings] : [.touch, .bar, .settings, .laptop]
    return voiceOver ? all.filter { $0 != .touch } : all
}

/// The steps only this layout has: all a turn offers (§4.2). Portrait: [.laptop]; landscape: [].
static func only(_ layout: TourLayout) -> [TourTopic]

static func targets(_ topic: TourTopic, _ layout: TourLayout) -> [TourTarget] {
    switch topic {
    case .touch: return [.stream]
    case .bar: return layout == .landscape ? [.strip, .textSize, .keyboard] : [.strip, .textSize]  // side by side
    case .settings: return [.settings]
    case .laptop: return [.keys, .trackpad]                                                        // one above the other
    }
}
```

Where each target is reported (a `.tourTarget(_:)` modifier, §6.1):

| Target | Landscape (`StreamScreen`) | Portrait (`PortraitStreamScreen`) |
|---|---|---|
| `stream` | The stream `ZStack` inside `contentArea`'s 8 pt padding, where `panelSize` is measured (StreamScreen.swift:320-336) | `streamPane`, the same place (PortraitStreamScreen.swift:216-233) |
| `strip` | TopBar's `WindowStrip` (:439-443), less its vertical `pad` (the thumbnails' band; the strip's frame is as tall as the bar) | `windowBar`'s `WindowStrip` (:267-272), less `thumbPad` |
| `textSize` | `TextScaleControl` (:448-450) | `TextScaleControl` (:274-276) |
| `keyboard` | TopBar's Keyboard button (:452-456) | — (the key row's keyboard cap is part of `keys`) |
| `settings` | TopBar's Settings button (:465-469) | `windowBar`'s Settings button (:285-289) |
| `keys` | — | `KeyRow`, one row or the two folded rows (:240-243) |
| `trackpad` | — | `Trackpad` (:244-248) |

**A phone held upright** (main's PR #30, merged after this plan: `PhonePortraitLayout`, the picture
in a 16:10 pane at the top, then row 1 with Apps, Aa, Keyboard, Desktop and Settings, row 2 the
thumbnails, row 3 six caps, and the trackpad) is a third layout, `TourLayout.phone`, with the halves'
four steps: `stream` is the pane, `bar` lights the strip (row 2) with Aa and Keyboard (row 1), as
sideways, since its Keyboard is a button there; `settings` row 1's Settings; `laptop` the six caps
and the trackpad. An iPad window as narrow keeps the compact halves (`DuoLayout.drawsPhone`).

A step's cutout is the union of its targets' frames as one rounded rectangle, 4 pt larger all
round and clipped to the screen, with the radius of its step: `touch` 16 (the panel's 12 + 4),
`bar` and `settings` 20, `laptop` 20 (between the caps' 15 and the pad's 26). Its ring is a 2 pt
stroke in `Palette.accent` on that shape, the active thumbnail's halo (StreamScreen.swift:969-971).

#### 3.2 A rotation or a resize during the tour

- The run is a list of steps: every step of the layout (Take the Tour), or the steps this device
  is owed there (the automatic tour). On a layout change it is recomputed for the new layout, less
  what this run has passed.
- **The step on screen** stays when the new list has it (`touch`, `bar` and `settings` exist in
  both). Otherwise the next step not yet passed comes on. When the new layout has none left (a run
  at `laptop` turned sideways), the tour ends with nothing more saved: `laptop` stays owed, and
  shows at a later turn upright with its decision left (§4.2: one per session and layout).
- The dots and the count follow the new list. The cards re-place without animation while the
  screen rotates.

### 4. When it shows by itself: the rule

```swift
struct Moment {
    var now: Double                 // ProcessInfo.systemUptime
    var pictureAt: Double?          // this session's first picture (§4.1)
    var layoutAt: Double            // when the layout on screen began (portrait or landscape)
    var decided: Bool               // this session's picture has had its decision
    var lastActivityAt: Double?     // the last touch anywhere on the screen, or input sent to the Mac (§6.6)
    var touchesDown: Int            // touches on the screen now (§6.6)
    var busy: Bool                  // something open (the Apps list, the panel, the lights, the Aa ruler, the keyboard,
                                    // the pairing overlay or a link), or the app not active
    var offered: Bool               // this session has had its decision in this layout
    var voiceOver: Bool
    var enabled: Bool               // Release: true; Debug: only with -SillTourState (§10)
}
enum Reason: Equatable { case nothingOwed, used, busy }          // for the console line
enum Decision: Equatable { case show([TourTopic]), wait(until: Double?), pass(Reason) }

static func automatic(_ m: Moment, _ layout: TourLayout, _ memory: TourMemory) -> Decision
```

In order:
1. Not `enabled`, or `offered`: `pass(.nothingOwed)`.
2. No picture yet: `wait(until: nil)` (the next change looks again).
3. The list and when it opens. Before `decided`: every step owed in this layout
   (`owed(layout, voiceOver:, memory)`), from `opens = max(pictureAt, layoutAt)`, so a rotation
   during the beat starts it again. After it, a turn: the steps owed that only this layout has
   (`only(layout)`), from `opens = layoutAt`. An empty list: `pass(.nothingOwed)`.
4. `lastActivityAt >= opens`: `pass(.used)`.
5. Before `opens + 1`: `wait(until: opens + 1)`.
6. `touchesDown > 0` or `busy`: `pass(.busy)`.
7. Otherwise `show(list)`.

`lastActivityAt` is the latest of a touch the window's watcher saw, input sent to the Mac, and a
control used by any means (review fix: VoiceOver's double tap, Switch Control, Voice Control and
Full Keyboard Access activate with no touch; a pick, a launch, a window's command or place in the
bar, a settings change, or the bar's own buttons, `StreamClient.lastActionAt`). VoiceOver's swipes
that only move its focus are reading, as a look is, and do not count; VoiceOver also moves its focus
by itself as a screen or a layout comes. `opens` is the later of the picture and the layout's start
in both cases (a session that went on with an earlier one's decision opens at its own picture).

A decision (a `show`, or a `pass` at step 3, 4 or 6) marks the session `offered` in this layout,
and the first one `decided`. What a session decided (`TourSession`) lives on StreamClient: the
automatic reconnect's session goes on with it (review fix: every reconnect used to decide afresh
and could dim the screen over someone at work when the picture came back), unless the last session
ended before its decision or in the middle of a run; a session the person starts decides afresh
(`TourPolicy.nextSession`). Each layout gets one decision per session: no second chance later in
it, and no ten-second window of pauses to catch. `StreamScreen` asks at the picture, at a layout
change, whenever an input of the rule changes, and at the time a `wait` names: one pending `Task`,
replaced on every answer.

#### 4.1 The picture

`pictureAt` is set once per `StreamScreen` (one per session: ContentView.swift:32-36 swaps it in at
`connected`) when all three hold: `client.macName` is not empty (the window list,
StreamClient.swift:2344), `client.videoSize` is not zero (the parameter sets,
HEVCDisplayView.swift:200-235), and `client.active != .none`. A move from AWDL to the network, to
the cable or to Wi-Fi keeps the same `StreamScreen` and its `pictureAt`.

#### 4.2 A turn, and the upright card

- A tour taken sideways leaves `laptop` owed. The first time the layout turns upright in a session
  whose picture has had its decision, `layoutAt` opens the turn's decision: a second after the
  turn, if nothing happened since it and nothing is open, the one card shows. A session whose
  picture passed offers only `laptop` at a turn too: the shared steps wait for a later session's
  picture.
- Folding the Duo from flat (1000×710) into its laptop posture (710×1000) is such a turn: the card
  about the keys and the trackpad comes as the laptop half appears.
- The card carries its own subtitle when it is a run's first (§7), since it starts without the
  others; a portrait tour cut short after `settings` resumes the same way, and the words still
  hold.

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
- **A new topic in a later build** (a new control) is owed to every device that did not skip, and
  shows once: at a session's first picture, or at a turn when only that layout has it.
- **Per device, not per Mac.** Kept in the app's own defaults, as `Sill.savedMacs` and
  `Sill.directWirelessMacs` are. A backup and restore keeps it (the person knows the app); a
  delete and reinstall resets it. The privacy manifest's UserDefaults reason (CA92.1) covers it,
  and the App Store label stays Data Not Collected.
- **No migration.** Only development and TestFlight builds exist before this one, so everyone gets
  the tour once (open question 11). A topic name a later build no longer has is ignored.

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
- **The dim draws in its own frame.** It covers the whole screen, safe areas included: the stream
  screen keeps the top and side safe areas outside its frame (it ignores only the bottom one,
  StreamScreen.swift:169), so a phone upright has about 60 pt above it and a phone sideways its
  Dynamic Island's side, and on an iPad with a status bar the bar's colour runs under it (:475).
  The targets are measured in `sill.screen`, whose origin is inside those insets, so the dim reads
  its own frame in `sill.screen` (a `GeometryReader`) and moves the cutout by minus that origin.
  Unmoved, the ring would sit an inset away from its controls on every phone, which the harness
  never shows: its fake screen has no insets (ContentView.swift:167-171). S1's live photos do.
- **The dim's touch area leaves out the card.** Its tap (the nudge, §6.4) is on the screen less
  the card's frame (an even-odd shape, as the cutout), because in the pairing overlay a tap gesture
  on the backdrop took the taps meant for the buttons in front of it (PairingOverlay.swift:43-45,
  measured on the simulator). If S1's taps still lose one to the dim, the nudge goes: a touch on
  the dim then does nothing, and nothing under it hit-tests anyway.
- **The overlay:**
  ```
  ZStack {
      TourDim(cutout:, ring:)          // the whole screen and its safe areas, in its own frame; even-odd; hidden
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
  y 24), 14 pt padding as the panel's, `.tint(Palette.accent)`; dark like the rest of the app.
  - **Title:** `.headline`, `Palette.text`, a header for VoiceOver.
  - **Subtitle,** on two cards only (§7): `.footnote`, `Palette.muted`.
  - **Rows:** a symbol column 22 pt wide (`@ScaledMetric(relativeTo: .subheadline)`) in
    `Palette.accent`, then the text in `.subheadline`, `Palette.text`, the control's name
    semibold (an `AttributedString` run, not Markdown, so the Mac's name is never parsed). 10 pt
    between rows. At accessibility sizes the symbol sits above its text. The symbols are
    decorative: hidden from VoiceOver, and each row is one element read as its words.
  - **Footer:** Skip (`.body`, `Palette.accent`, plain, 44 pt tall), the dots (6 pt, 6 pt apart,
    the current one `Palette.accent`, the rest `Palette.muted` at 40 %; hidden from VoiceOver, since
    the title says the count, and none on a one-step run), and Next or Done
    (`.body.weight(.semibold)`, black on an accent fill, 12 pt corners, at least 88×44: the
    pairing card's Pair, PairingOverlay.swift:168-176). One line while it fits, which at 560 pt it
    should at every text size (S2 looks); otherwise Next over Skip at full width and no dots
    (`ViewThatFits`).
  - **Only the title and rows scroll,** when the card is taller than its room (§6.3), as the
    panel's middle does (HostSettingsPanel.swift:49-55), with `scrollIndicatorsFlash(onAppear:
    true)`. The footer stays in reach.
- **The tail:** on landscape bar steps, and in portrait where §6.3 allows one; never on a card that
  overlaps its targets. 16 pt at its base, 7 pt tall, the card's fill and border, its tip under or
  over the targets' middle, never nearer than 28 pt to the card's corner.

#### 6.3 Where the card goes (`TourPolicy.place`, pure)

```swift
struct TourPlacement: Equatable { var card: CGRect; var tail: Tail? }     // Tail: .up or .down, and the tip's x
static func place(card: CGSize, targets: CGRect?, isStream: Bool, screen: CGSize, layout: TourLayout,
                  stream: CGRect, bottomInset: CGFloat) -> TourPlacement
static func crease(_ screen: CGSize) -> CGFloat?   // screen.height / 2 at ConnectLayout.topHalf's sizes, else nil
static func width(screen: CGSize, layout: TourLayout, accessibilityText: Bool) -> CGFloat
```

- **The crease** is `ConnectLayout.topHalf`'s rule (AddMacCard.swift:19): taller than wide, 600 to
  740 pt wide and under 1100 pt tall, which is the Duo's 710×1000 whether flat or half-folded (an
  iPad mini upright, 744 pt wide, has none). There the crease is the portrait layout's own split
  (PortraitStreamScreen.swift:156), and a card or tail never crosses it.
- **Width** (`TourPolicy.width`): 360 pt; 480 pt on a screen held sideways that is under 520 pt
  tall (a phone, the Duo's outer display: `ConnectLayout.short`), where height is what runs out;
  560 pt at accessibility text sizes; never more than the screen less 32 pt. `TourCardLayout` asks
  it and measures the card at it (`card` is that size).
- **Margins:** 16 pt from the screen's edges, and above the home indicator (`bottomInset`, the
  geometry's bottom inset: the stream screen runs under it, StreamScreen.swift:169).
- **Its preferred place.**
  - Landscape, the picture's step: centered in the picture.
  - Landscape, a bar step: its top 12 pt below the targets, centered on their middle and clamped
    to the margins; a tail up.
  - Portrait: in the picture's half, so it never covers the laptop half it is about and never
    crosses the crease. The picture's step centered there; a lower step with its bottom 12 pt above
    the picture's bottom, centered on the targets' middle and clamped. A tail down only when the
    targets begin within 48 pt of the card and no crease lies between: at 500×710 and on phones the
    `bar` and `settings` cards point at the window bar and `laptop` does not; at 710×1000 none do.
- **Too tall for it** (as revised by the review: a card grown over its own targets hid the very
  control it lit, with slivers of its ring beside it, at accessibility sizes on phones and the Duo's
  outer display). A card never covers its own step's targets: sideways it stays 12 pt under the bar,
  as tall as the room to the bottom margin, its tail up, and its words scroll there; upright it
  grows from the picture's half toward the top margin, then down to 12 pt above its targets (never
  past a crease), with the same tail rule, its words scrolling past that. On a phone held upright,
  whose rows sit in the middle under a short picture, a card too tall for the picture's pane stands
  12 pt above its targets, and one that does not fit above them goes 12 pt under them when it fits
  there, or when that room is the larger, with a tail up. Only a room under 200 pt beside its
  targets (`minimumRoom`: a tiny window, no real screen) makes a card cover them, and then the dim
  has no cutout or ring (`coversTargets`). The picture's card sits inside the picture and grows as
  before.

The layouts' numbers, from the metrics (BarMetrics, StreamScreen.swift:403-413; PortraitMetrics,
PortraitStreamScreen.swift:111-126). A phone's stream screen is the phone's screen less its top
and side safe areas, not the whole screen:

| Screen | Layout | The picture | The bar | The keys | The trackpad | A lower card's room before it grows |
|---|---|---|---|---|---|---|
| 1000×710 (Duo inner, sideways) | landscape, regular bar | 984×608 at (8, 94) | 0–86, its buttons 10–76; the strip 566 pt | — | — | 88 to 694 |
| 710×500 (Duo outer, sideways) | landscape, compact bar | 694×406 at (8, 86) | 0–78, its buttons 10–68; the strip 302 pt | — | — | 80 to 484 |
| 710×1000 (Duo inner, upright or half-folded) | portrait, regular | 694×484 at (8, 8) | 512–590; the strip 378 pt | 600–648 | 658–978 | 8 to 492, the crease at 500 |
| 500×710 (Duo outer, upright) | portrait, compact | 484×339 at (8, 8) | 365–427; the strip 200 pt | 437–533 (two rows) | 543–694 | 8 to 347 |
| 667×375 (iPhone SE, sideways; no insets) | landscape, compact bar | 651×281 at (8, 86) | 0–78; the strip 259 pt | — | — | 80 to 359 |
| 375×667 (iPhone SE, upright) | portrait, compact | 359×318 at (8, 8) | 344–406; the strip 75 pt | 416–512 (two rows) | 522–651 | 8 to 326 |
| About 832×440 (a 440×956 iPhone sideways, less its side insets) | landscape, compact bar | 816×346 at (8, 86) | 0–78; the strip 424 pt | — | — | 80 to 404 (its home indicator's 20) |
| About 440×894 (the same upright, less its top inset) | portrait, compact | 424×431 at (8, 8) | 457–519; the strip 140 pt | 529–625 (two rows) | 635–878 | 8 to 439 |
| iPad sideways, iPad upright (1376×1032, 1032×1376 on a 13-inch) | landscape or portrait, regular | below the bar, or the upper half | | | | as the Duo's inner sizes, without a crease |

The tightest is a 375 pt tall phone held sideways: an iPhone mini keeps about 258 pt below the bar
for a bar step's card (80 to 338, above its 21 pt home indicator). At 480 pt wide the landscape
`bar` card fits there at the default text size (about 230 pt tall; at 360 pt wide about 270), and
from about xxLarge it grows over the bar. These heights are estimates, the card's words set with
Core Text in the system font on this Mac; S1 checks the first at 667x375. Upright, the tallest card,
`laptop` with its subtitle (about 330 pt), grows past the picture's half by about 13 pt on the Duo's
outer display and 34 pt on the iPhone SE (to y = 348, 4 pt over its window bar), never onto its own
keys. The check pins the card's frame for every step at the four Duo sizes and the iPhone SE's two,
with a short and a tall card, and asserts the rules above at a grid of other sizes.

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
| VoiceOver | The tour is modal: the dimmed screen is out of reach. The run leaves out `touch` and the trackpad's rows (§3.1): VoiceOver takes those gestures for itself, and neither the picture nor the trackpad is an accessibility element (InputOverlay.swift and TrackpadView.swift have none), so they stay owed for a run without it. The other rows are spoken the VoiceOver way (§7): a thumbnail's named actions (StreamScreen.swift:956-964) and Aa's adjustable action (:620-630). Focus follows the step: `@AccessibilityFocusState` keyed by topic puts it on each card's title as the card appears, read as "Windows and Text Size, step 2 of 3", with a hint saying where the lit part is (§7), and each step change posts a layout-changed notification. The reading order is the card's own, top to bottom and leading to trailing: the title, the subtitle, each row as one element (its symbol hidden), Skip, then Next or Done; the dots and the dim are hidden. The escape gesture is Skip, Magic Tap is Next. At the end a screen-changed notification lets VoiceOver read the stream screen afresh |
| Voice Control | The buttons' spoken names are their visible words: Skip, Next, Done |
| Full Keyboard Access, Switch Control | Skip and Next or Done are buttons in order |
| Dynamic Type | Every size, the accessibility sizes included, as the HIG's Typography page asks: the title and rows wrap, never truncate; the symbols sit above their rows at accessibility sizes; the footer stays one line while it fits; the card may widen to 560 pt, and grows toward the top (and, upright without a crease, over its own targets) before its rows scroll (§6.3). The Settings panel stops at xxLarge (HostSettingsPanel.swift:63); the tour does not, since it is what a person reads to learn the app (open question 9) |
| Reduce Motion | §6.4 |
| Increase Contrast, Reduce Transparency | Nothing is translucent but the dim; the ring and the accent keep their contrast on the dark card |

#### 6.6 The input pause, and what counts as something happening

- **Start** (`startTour`): put away what could be open (the Apps list, the lights, the Aa ruler, as
  `putAwayForOverlay` does, StreamScreen.swift:250-256), remember whether the keyboard was up, and
  `overlay.setKeyboard(shown: false)`. From Take the Tour the Settings panel has already taken the
  keyboard down: take its `keyboardBeforeSettings` (:86-88) before closing the panel with
  `restoreKeyboard: false`.
- **While it shows:** the layouts do not hit-test and the tour's layer takes every touch, so
  nothing reaches `InputOverlayView` (the direct touch, the Pencil, the iPad's own trackpad and
  mouse, hover) or `TrackpadSurface`. Nothing is in flight when it starts (the rule wants no touch
  down and nothing sent in the second before), so no button or key is left down on the Mac.
- **End** (Done, Skip, a rotation with nothing left): hit testing back; the keyboard back if it was
  up.
- **`TouchWatcher`** (TourOverlay.swift): a `UIGestureRecognizer` subclass that a zero-size
  `UIViewRepresentable` in the stream screen adds to its window when it joins one and removes when
  it leaves (the way `EscapeKey` finds its view controller, AddMacCard.swift:270-328). Its
  `touchesBegan`, `touchesEnded` and `touchesCancelled` keep `touchesDown` and stamp `lastTouchAt`
  (systemUptime, main thread). It never recognizes (it fails when its last touch ends), sets
  `cancelsTouchesInView`, `delaysTouchesBegan`, `delaysTouchesEnded` and
  `requiresExclusiveTouchType` to false, answers `canPrevent` and `canBePrevented` with false and is
  simultaneous with every recognizer through its delegate, so no gesture of the stream, the bar or
  SwiftUI waits for it or loses a touch to it, and a finger and the Pencil together both count.
  It sees fingers, the Pencil and the iPad's trackpad or mouse clicks (indirect pointer touches);
  a hover is no touch, but it sends input.
- **`StreamClient.lastInputAt`** (main thread, systemUptime, not published): stamped in `sendInput`
  (StreamClient.swift:2196) before its hop to the network queue. Every input passes there, a hover
  and a coast after a flick included. `lastActivityAt` is the later of it and `lastTouchAt`.
- **The device's own input** (review fix): a new frame size (another source, an Aa resize, a window
  refitted after a turn) moves the drawn pointer to the middle and the Mac's cursor with it. While a
  card shows that move waits for the tour's end (`StreamClient.inputPaused`, `recentrePointer`), so
  nothing reaches the Mac then.
- **The tripwire, DEBUG only:** `StreamClient.inputPaused` (it was `tourShowing`), set by `StreamScreen`. `sendInput`
  prints "tour: INPUT SENT WHILE THE TOUR SHOWED: …" if it is ever called while it is true. It is
  not expected on a device either, but for one case: Take the Tour chosen within two seconds of a
  flick, whose coast (InputOverlay.swift:473-477) may send its last scrolls under the tour.

### 7. Copy

‹Mac› is `client.macName` ("your Mac" if empty, which the rule never lets happen); ‹device› is
"iPad" or "iPhone" (`StreamClient.deviceWord`). The words are the App Store description's where it
has them (docs/app-store-metadata.md §5: "Tap to click. Touch and hold to right-click. Drag to
scroll."). The name in each row is semibold. The check pins every string.

| Step | Title | Subtitle | Rows (symbol · text) | Spoken where (the title's hint) |
|---|---|---|---|---|
| `touch` | Tap, Hold and Drag | What you do here happens on ‹Mac›. | `hand.tap` · **Tap** to click.<br>`contextualmenu.and.cursorarrow` · **Touch and hold** to right-click.<br>`hand.draw` · **Drag** to scroll.<br>`applepencil` · **Apple Pencil** works as a mouse. (iPad only) | Landscape: "The picture of ‹Mac› fills the screen below the bar." Portrait: "The picture of ‹Mac› fills the top half of the screen." |
| `bar` | Windows and Text Size | — | `hand.point.up.left` · **Touch and hold** a window to close, minimize or go full screen. Keep holding and drag to move it.<br>`textformat.size` · **Aa**: touch it and slide to make a window’s text larger or smaller.<br>`keyboard` · **Keyboard** types on ‹Mac›, on screen or with a hardware keyboard. (landscape and a phone upright) | Landscape: "In the bar at the top, after Apps." Portrait: "In the bar below the picture, after Apps." A phone upright: "Under the picture: Aa and Keyboard in the first row, the windows in the second." |
| `settings` | Settings | — | `xmark.circle` · **Disconnect** is at the bottom of Settings.<br>`questionmark.circle` · **Take the Tour** is there too, to see this again.<br>`ipad` or `iphone` · **Hold your ‹device› upright** for a trackpad and keys. (landscape only) | "The last button in the bar." |
| `laptop` | Keys and Trackpad | Only as a run's first card: "Upright, Sill adds keys and a trackpad." | `command` · **cmd, opt, ctrl and shift** stay on for the next key or trackpad click: tap cmd, then C, to copy.<br>`keyboard` · **The keyboard key** types on ‹Mac›, on screen or with a hardware keyboard.<br>`cursorarrow.click.2` · **Tap with two fingers** on the trackpad to right-click.<br>`hand.draw` · **Touch and hold** the trackpad, **then drag**, to move a window or select text. | "Below the bar: the row of keys, then the trackpad." |

- **A phone held upright** (§3.1): the picture's hint "The picture of ‹Mac› is at the top of the
  screen."; Settings' "The last button in the row under the picture."; the laptop card has no
  keyboard key row (a phone's keyboard is row 1's button, which the bar card names) and the hint
  "Under the windows: the row of keys, then the trackpad."
- **Aa sizes a window** (review fix): the Mac ignores a viewport's scale for the Desktop, and the
  first picture is the Desktop, so the row says whose text it is.
- **Spoken, where it differs from the screen:** `laptop`'s first row reads "Command, Option,
  Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.", as
  the key row's own caps are named (PortraitStreamScreen.swift:342-355).
- **Under VoiceOver** (the run leaves out `touch` and `laptop`'s trackpad rows, §6.5), the rows
  that name a gesture say VoiceOver's instead, and none says tap, touch and hold, slide or drag:
  - `bar`: "Each window has actions: close, minimize, full screen, and move left or right. Swipe up
    or down to hear them." and "Text size makes a window’s text on ‹Mac› larger or smaller. Swipe up
    or down on it."; the Keyboard row as written.
  - `laptop`: "Command, Option, Control and Shift stay on for the next key: Command, then C,
    copies." and the keyboard key's row as written.
- **Buttons:** "Skip", "Next", "Done". Skip's hint: "Ends the tour. Take the Tour in Settings shows
  it again."
- **Why each row says what it says** (checked against the code at cf05a78):
  - A tap on the picture clicks and a long press (0.45 s) right-clicks (InputOverlay.swift:61-69,
    :118-134); one or two fingers scroll with momentum (:71-76, :141-173); the Pencil is the left
    button (:219-269).
  - A thumbnail's tap selects, which needs no card; a 1.5 s hold opens the lights; moving more than
    8 pt then lifts and drags it (StreamScreen.swift:714-718, :786-802).
  - Aa opens on touch and applies on release; a tap alone changes nothing (:596-618), which is
    why it has a row.
  - Keyboard makes the input view first responder, and only then do the software keyboard and a
    hardware one type on the Mac (InputOverlay.swift:403-416; nothing else calls
    `becomeFirstResponder` but the key row's keyboard cap and the panel's restore).
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
  (StreamScreen.swift:273-274) starts every step of the layout on screen, from the first (under
  VoiceOver, less what §3.1 leaves out).
- **Nothing about the Mac changes:** the row sends nothing, and the panel's other rows are as they
  are. Every `-SillSettings 1` photo gains the row at the end.

### 9. Files

| File | Change |
|---|---|
| `iOSClient/TourPolicy.swift` (new; pure: Foundation and CoreGraphics; checked with swiftc) | `TourTopic`, `TourLayout`, `TourTarget`, `TourMemory`, the steps and targets (§3), the rule (§4), `passed`, `skipped` and `carry` (§3.2, §5), `place` and `crease` (§6.3), and every string (§7) as `TourCopy` values built from ‹Mac›, ‹device› and VoiceOver. pbxproj IDs `A1000001000000000000A401` / `…F401` |
| `iOSClient/TourOverlay.swift` (new) | `TourDim`, `TourCard`, `TourCardLayout`, the `tourTarget` modifier and its preference, `TouchWatcher`, `TourStore` (the two keys, and Debug's `-SillTourState`), the stand-ins (§10) and the console lines. IDs `…A402` / `…F402` |
| `iOSClient/StreamScreen.swift` | The run and the rule's inputs as `@State` (`tour`, `targets`, `pictureAt`, `layoutAt`, `decided`, `offered`), the coordinate space, the watcher, the layer (§6.1), `startTour` and `endTour` (§6.6), an outside link putting the tour aside, the targets in TopBar and `contentArea`, and the DEBUG init's `tour:` |
| `iOSClient/PortraitStreamScreen.swift` | The targets in `streamPane`, `windowBar`, `KeyRow` and `Trackpad`; `takeTour` passed to the panel |
| `iOSClient/HostSettingsPanel.swift` | Take the Tour (§8) and its `takeTour` closure |
| `iOSClient/StreamClient.swift` | `lastInputAt` in `sendInput`; DEBUG `tourShowing` and the tripwire (§6.6) |
| `iOSClient/ContentView.swift` | The harness: `Spec` gains `tour` and passes it on; DEBUG `-SillOrientation` in the normal app; the contract comment (§10) |
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
    static let beat = 1.0                                                   // seconds
    static func owed(_ layout: TourLayout, voiceOver: Bool, _ m: TourMemory) -> [TourTopic] {
        m.skipped ? [] : steps(layout, voiceOver: voiceOver).filter { !m.seen.contains($0) }
    }
    static func passed(_ t: TourTopic, _ m: TourMemory) -> TourMemory       // seen += t
    static func skipped(_ m: TourMemory) -> TourMemory                      // skipped = true
    /// A layout change mid-run: the step now, or nil when the new layout has none left.
    static func carry(_ current: TourTopic, run: [TourTopic], passed: Set<TourTopic>, to layout: TourLayout,
                      replay: Bool, voiceOver: Bool, memory: TourMemory) -> (run: [TourTopic], at: TourTopic)?
    static func copy(_ t: TourTopic, _ layout: TourLayout, mac: String, device: String,
                     voiceOver: Bool, firstOfRun: Bool) -> TourCopy
}
```

### 10. Harness and DEBUG arguments (ContentView's contract comment at :55-171, and CLAUDE.md)

- **`-SillTour touch|bar|settings|laptop`:** the stream screen starts the tour at that step, as
  Take the Tour shows it (every step of the layout, from that one on), with no beat: in the mock at
  once, and under `-SillLive 1` and in the normal app at the first picture. A step the layout lacks
  (`laptop` at 1000x710) starts at the first.
- **`-SillTourState fresh|landscape|done|skipped|saved`:** in the normal app, under `-SillLive 1`
  and in the mock:
  - it turns the automatic tour on, which a Debug build otherwise never shows (open question 10);
  - `fresh` is nothing seen, `landscape` the three landscape steps seen (so an upright size shows
    `laptop`), `done` everything, `skipped` Skip tapped: for this run only, never written back;
  - `saved` reads and writes the saved keys, as a Release build does.

  In the mock the picture counts from launch.
- **`-SillTourPress next@S|skip@S`:** Debug only, a stand-in for a tap, since the gates may not
  drive the UI: S seconds after each card appears, press Next (Done on the last), or once, Skip.
- **`-SillTourActivityAt S`:** Debug only, a stand-in for a touch S seconds after the picture, for
  the rule's pass (the gates may not touch the screen).
- **`-SillTourVoiceOver 1`:** Debug only, the run and its words as under VoiceOver, for photos
  (VoiceOver cannot be turned on from the command line here).
- **`-SillOrientation landscape|portrait`:** Debug, in the normal app: asks the window scene for
  that orientation at launch (`UIWindowScene.requestGeometryUpdate`, iOS 16), so a phone simulator
  shows the real layout sideways, its insets included, with no hand on the simulator. Unverified:
  if the simulator does not turn, S1 says what replaces it.
- **Without any of them the mock never shows the tour,** and neither does a Debug build of the
  normal app: every harness photo and every other feature's live test stays as it is. Release and
  TestFlight builds always follow the rule.
- **Console lines** (Debug), each printed when its event happens:

```
tour: owed here: touch, bar, settings (landscape; seen: none)
tour: waiting until 1.0 s after the picture
tour: showing touch (1 of 3)
tour: screen 1000×710 (landscape); card 320,88 360×262, tail up at 505
tour: passed touch
tour: carried to bar (portrait → landscape)
tour: put aside for a pairing link; back at bar after it
tour: done (saved: touch, bar, settings)
tour: skipped (saved)
tour: closed (Take the Tour; nothing more saved)          (Skip in Take the Tour, review fix)
tour: the automatic reconnect's session keeps the last one's decision (decided in: landscape)
tour: not this session: used within a second of the picture
tour: not this session: the Apps list was open
tour: INPUT SENT WHILE THE TOUR SHOWED: …        (the tripwire; see §6.6)
```

### 11. Timeouts and limits

| What | Value |
|---|---|
| The beat after the first picture, or after a turn | 1.0 s, with nothing happening in it |
| Its chance | One decision per session and layout, at the end of the beat |
| The dim | Black, 0.58 |
| The ring | 2 pt, `Palette.accent`, 4 pt outside the targets |
| The card | 360 pt wide (480 sideways under 520 pt tall, 560 at accessibility sizes, never more than the screen less 32); 14 pt padding; 16 pt from the edges; 12 pt from its targets while it fits beside them |
| The tail | 16 × 7 pt; only where §6.3 allows |
| Motion | In 0.25 s, a step 0.35 s, out 0.2 s; under Reduce Motion 0.2 s fades |
| Kept | `Sill.tourSeen` (four topic names at most today), `Sill.tourSkipped` |

### 12. Edge cases

| Case | Behaviour |
|---|---|
| The session ends during the tour (Sill.app quits, a notice, the network goes) | The tour goes with the stream screen. Steps passed stay passed; the next session starts at the first step owed, with its own beat and decision (the automatic reconnect's too, since a run was on screen) |
| The session ends after its decision, and the automatic reconnect brings the picture back (a Wi-Fi drop, the Mac waking, an eviction after 4 s in another app, Sill.app relaunched) | The reconnect's session goes on with the last one's decision: no tour where it was decided; in a layout it never decided in, only what that layout has alone, a beat after the new picture. A session the person starts decides afresh |
| A Mac refuses this device's version (the floor) | Never shows: no window list, no picture (§4.1) |
| The first session is remote, or over the cable | The same rule; the tour does not care how the session came |
| Pairing at home (after `home-pairing` lands) | The card on the connect screen, "Paired with Mac mini.", then the session: the tour follows its picture. Over the cable, "Paired with Mac mini over the cable." then the same |
| An outside `sill://pair` link during the tour | The tour is put aside (not closed, nothing saved); the pairing overlay shows; when it closes and the session still streams, the tour comes back at the same step. If a turn ends it meanwhile (nothing of it in the new layout), the keyboard stays down under the overlay |
| An outside link in the beat | The overlay is open at the decision: not this session |
| The person rotates, resizes (Split View, Stage Manager) or folds the Duo during the tour | §3.2 |
| The person rotates or folds within the beat | The beat starts again in the new layout, with every step owed there (§4) |
| A finger resting on the screen when the picture comes; a Pencil or trackpad drag held still; a scroll of the thumbnail strip | A touch down, or a touch since the picture: not this session |
| Typing on a hardware keyboard before Keyboard is tapped | Nothing reaches the Mac (the input view is not first responder), and nothing counts as happening: the tour shows, and its `bar` card says what Keyboard does |
| The software keyboard is up at the decision | Something open: not this session. Take the Tour takes it down and puts it back after |
| A latched modifier in the key row | Kept through the tour; spent by the next key or trackpad click after it |
| A Mac with no windows | `bar` lights the empty strip, Aa and Keyboard; the words hold |
| A Mac with an older Sill (no settings) | The `settings` card's rows hold: Disconnect is there whatever the Mac |
| The app goes to the background during the tour | Back within 4 s: the tour is there, at the same step. Longer: the Mac evicts a suspended device after 4 s, the stream screen goes with the session, and the next session's tour starts at the first step not passed |
| The app goes to the background in the beat | Not active at the decision: not this session |
| The Desktop cannot stream (the Mac lacks Screen Recording) | No picture, so no tour: the black panel is the Mac's to fix |
| VoiceOver on | The same rule; the run leaves out `touch` and the trackpad's rows (§6.5). The stream itself is out of VoiceOver's reach today (the picture and its input view are no accessibility elements and have no direct-touch trait), which is outside this step |
| A hardware keyboard and no touch at all | Return goes through the tour; Esc skips it |
| Two taps on Next in quick succession | Two steps; nothing is lost but the reading (Take the Tour replays) |
| Take the Tour on a layout, then a rotation | §3.2, with the run being every step of the new layout |
| Take the Tour within two seconds of a flick | The flick's coast may send its last scrolls under the tour: the tripwire names them, and nothing else |
| The Pencil or the iPad's trackpad hovering over the dim | The layer above takes the hover; the Mac's pointer does not move (P1) |
| The Mac's own pointer (pointer visibility, once merged) | Drawn under the dim, as the picture is |
| An iPhone held sideways | The stream screen keeps the side insets (the Dynamic Island's side), so the card and the ring stay inside them; the home indicator's inset is the bottom margin; a bar step's card, 480 pt wide there, fits below the bar at the default text size (as little as 258 pt of room on an iPhone mini) and grows over it at larger text |

### 13. Test gates

**Hard rules for the implementing session:**
- **Disk and build folders:** at least 25 GB free before any build (`df -g /System/Volumes/Data`);
  DerivedData under the session's scratch folder, deleted at the end.
- **The simulator:** a private one named "Sill walkthrough", deleted at the end:
  - an iPad Pro 13-inch (M5) for the Duo sizes and the iPad;
  - then, the iPad one deleted, an iPhone SE (3rd generation) of the same name, the smallest screen
    the app runs on;
  - then, that one deleted, an iPhone 18 Pro Max of the same name, for the Dynamic Island's insets.
    One at a time.
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
| H2 | **The pure check**, `Tests/checks/run-all.sh tour`, at least 150 cases: the steps and targets per layout, with and without VoiceOver; `owed` for each memory; `only`; the rule at every boundary (0.99 and 1.0 s of beat; activity at `opens` − 0.01 and at `opens`; a touch down; `busy`; `offered`; `decided` false and true, a turn offering only `laptop`; `enabled`; `skipped`; nothing owed; the beat starting again when the layout changes before the decision); `passed`, `skipped`, a session ending; `carry` for every step both ways, with and without VoiceOver, and a run with nothing left; `crease` against a copy of `ConnectLayout.topHalf` at 20 sizes; `width` at every size of §6.3's table and at accessibility text; `place` pinned for every step at the four Duo sizes and the iPhone SE's two, with a short and a tall card, and at a 400-size grid of screens by card heights: inside the margins, never across the crease, beside its targets (not over them) whenever it fits there, growing toward the top first and over its targets only when it must, a tail only where allowed and never on an overlapping card, its tip within the card's straight edge; every string of §7 for "Mac mini" and "iPad", "iPhone" (no Pencil row), the "your Mac" fallback, the landscape-only rows, the upright card's subtitle, and under VoiceOver no "tap", "touch and hold", "slide" or "drag" in a spoken row. `--mutants tour`, at least 26 (§14 step 1) | All pass; every mutant caught; `Tests/checks/run-all.sh` passes whole |
| H3 | **Hard rules by grep** | No `.sheet(`, `.popover(`, `popoverTip`, `fullScreenCover`, `.alert(`, `import TipKit` or `Tips.` in `Tour*.swift`; no `sendInput`, `client.send`, `select(`, `launch(`, `command(` or `changeSettings` there either; `TourPolicy.swift` imports Foundation and CoreGraphics only; `requestGeometryUpdate` only inside `#if DEBUG`; `git diff origin/main --stat -- Sources Packaging Scripts iOSClient/Info.plist iOSClient/PrivacyInfo.xcprivacy` is empty; A401, F401, A402, F402 each appear in their four places |
| H4 | **Nothing else changed on screen.** At 1000x710, 710x1000, 500x710 and 710x500: the mock with no argument, `-SillDrawer 1`, `-SillWindowMenu 1`, `-SillScaleOpen 1 -SillScale 1.5`, `-SillActive none`, `-SillScanOverlay 1`, `-SillConnectCase methods`, `-SillConnectCase addmac` (32 photos), base against this build | Pixel for pixel equal. `-SillSettings 1` at the four sizes differs only at the rows' end (the new row), or not at all where the end is out of view |

**Simulator (S), photographed and sheeted per size:**

| # | Check |
|---|---|
| S1 | **Every step at every size.** On the iPad simulator, `-SillTour <step>` for the three landscape steps at 1000x710, 710x500 and 1376x1032 (drawn turned; `sips -r 270`), and the four portrait steps at 710x1000, 500x710 and 1032x1376: 21 photos. On the iPhone SE, the same at 667x375 (turned) and 375x667: 7. On the iPhone 18 Pro Max, the normal app connected to a synthetic host (`-SillConnect`, `-SillTour <step>`), upright: 4 photos with the phone's real insets (the console's `tour: screen` line gives the stream screen's size); then with `-SillOrientation landscape`: 3, rotated back. If the interface does not turn, those 3 come from the harness at 832x440, and the Dynamic Island's side is left to P11. With `-SillTourVoiceOver 1`, at 1000x710 and 500x710: 5. Each photo: the ring on its controls within a point (in the live photos an offset by an inset is the fault to look for, §6.1); the card where §6.3 puts it, with its tail; nothing crosses y = 500 at 710x1000; at 667x375 the `bar` card sits below the bar, not over it; nothing truncated; the iPhone photos read "iPhone", with no Pencil row. Send Noah the sheets |
| S2 | **Text size**, `xcrun simctl ui <udid> content_size`: every step at 710x500, 500x710 and 710x1000 on the iPad simulator and at 667x375 on the iPhone SE, at `extra-extra-extra-large` and `accessibility-extra-extra-extra-large` (28 photos). The title and rows wrap; a card too tall for its room grows toward the top (over the bar at 667x375) before its rows scroll, with the footer whole and reachable; at 710x1000 the card stays in the upper half |
| S3 | **Take the Tour.** `-SillSettings 1 -SillSettingsEnd 1` at 500x710, 710x500 and 1000x710, cases `default`, `legacy` (no settings: the row is still there) and `remotepair`, at the default size and at xxLarge (the panel's cap) |
| S4 | **The rule, in the mock.** `-SillTourState fresh` at 1000x710: no tour in a photo at 0.5 s, the `touch` card (1 of 3) at 2 s. `landscape` at 710x1000: at 2 s the `laptop` card with its subtitle and no dots. `done` and `skipped`: nothing at 3 s. `fresh` with `-SillDrawer 1`: nothing at 3 s, and the console's "not this session: the Apps list was open". `fresh` with `-SillTourActivityAt 0.5`: nothing at 3 s ("not this session: used within a second of the picture"). `fresh` with `-SillScanOverlay 1`: nothing at 3 s. With `-SillTourPress next@1` at 1000x710: Done after the third card, the console's "tour: done (saved: …)", nothing written (`fresh`) |
| S5 | **Live**, one host at a time. (a) `-SillLive 1 -SillLayout 1000x710 -SillConnect 127.0.0.1:P -SillTourState fresh`: "tour: showing touch (1 of 3)" between 1.0 and 2.5 s after the console's `host:` line (the first window list; the picture follows it); a photo of the card over the test pattern. (b) On a fresh install (`xcrun simctl uninstall`, then `install`), the same with `saved` and `-SillTourPress next@1.5`: kill the host while the third card shows. Back on the connect screen, `plutil -p "$(xcrun simctl get_app_container "Sill walkthrough" me.saffer.sill data)/Library/Preferences/me.saffer.sill.plist"` lists `Sill.tourSeen` with touch and bar. A new host and the same launch: the tour starts at `settings`, with no dots and Done. (c) A host with `SILL_TEST_MIN_DEVICE_VERSION=99` and `-SillTourState fresh`: the notice on the connect screen and no `tour:` line in 10 s. (d) The console never prints the tripwire |

**Noah's devices (P), handed over at the end:** the iPad mini and the iPhone 15 Pro. The automatic
tour needs a Release or TestFlight build on a fresh install, or the Debug build launched with
`-SillTourState fresh` (Xcode's scheme, Arguments).

| # | Check |
|---|---|
| P1 | **The first picture.** About a second after the Mac's Desktop shows, with nothing touched meanwhile, the tour dims the screen and lights the picture. While it shows: tap, hold and drag on the dimmed picture; press keys on a hardware keyboard; hover and touch with the Pencil; use a trackpad or mouse on the iPad. Nothing happens on the Mac (its pointer does not move; the host's `[1s]` lines show no `in.pointer`, `in.scroll`, `in.text` or `in.key` meanwhile), and the picture keeps moving. Then, fresh again: touch the picture within the first second, and no tour comes this session |
| P2 | **Each step** lights the control it names, in both layouts, and Done ends it. Held upright after a tour in landscape and left alone: the `laptop` card about a second after the turn, once |
| P3 | **Interrupted.** Quit Sill.app on the Mac at the third card; reopen it. The next session's tour starts at the first step not passed |
| P4 | **Take the Tour,** in both layouts, with the keyboard up before opening Settings: the tour runs, and the keyboard is back after Done |
| P5 | **Skip** on the first card: no tour at the next session, nor when held upright |
| P6 | **VoiceOver:** no `touch` card and no trackpad rows; focus on each card's title as it comes; each row read whole, with no symbol names; the `bar` rows say to swipe up or down; the escape gesture skips; Magic Tap goes on; after Done, the stream screen is read afresh |
| P7 | **The largest text size** (Settings › Accessibility › Display & Text Size › Larger Text): every card readable; sideways a card grows over the bar before its rows scroll; Skip and Next reachable |
| P8 | **Reduce Motion:** fades only |
| P9 | **A hardware keyboard:** Return goes on, Esc skips |
| P10 | **An outside link** (the Camera on the Mac's pairing QR code) during the tour: the tour steps aside, the confirmation shows; Cancel, and the tour is back at its step |
| P11 | **The iPhone,** upright and sideways: each ring on its controls, not an inset away; the cards clear the Dynamic Island and the home indicator, and read "iPhone" with no Pencil row |

### 14. Implementation order (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

0. **Preflight** (no commit): H0.
1. **"iOS: the tour's rules, checked on their own."** `TourPolicy.swift` with its pbxproj entries;
   `Tests/checks/tour`; the README row; the CI matrix. The mutants, at least:
   - the beat dropped;
   - activity since the picture ignored;
   - activity measured from the picture instead of `opens` (a turn);
   - a touch down ignored;
   - `busy` ignored;
   - `offered` ignored;
   - `skipped` ignored;
   - `enabled` inverted;
   - a turn offering every owed step instead of its layout's own;
   - `touch` kept under VoiceOver;
   - Next not saving;
   - Skip not saving;
   - `laptop` owed in landscape;
   - `laptop`'s subtitle on a card that is not the run's first;
   - `carry` going to the first step instead of the next one owed;
   - the crease ignored;
   - a tail across the crease;
   - a tail on a card over its targets;
   - the card not clamped;
   - the card 360 pt wide on a short screen held sideways;
   - a landscape card above its targets while it fits below;
   - a card that never grows (it runs off the screen);
   - the Pencil row on iPhone;
   - the upright row in portrait;
   - a gesture word in a VoiceOver row;
   - one word of the copy changed.

   Gates: H1, H2.
2. **"iOS: a tour of the stream screen, once, after the first picture."** `TourOverlay.swift`; the
   targets; the layer and the rule in `StreamScreen`; the watcher; the pause; `lastInputAt` and the
   tripwire; the keys and VoiceOver; the harness arguments and the contract comment. Gates: H1,
   H3, H4, S1, S2, S4, S5.
3. **"iOS: Take the Tour in the Settings panel."** Gates: H1, H4 (the panel's photos differ only
   by the row), S3.
4. **"docs: the tour."** §16, and this plan's Results. Gates: none new.
5. **Review and hand-over.** Three lenses:
   - when it shows (the rule, the watcher, sessions ending, pairing, notices, rotation);
   - the pause (no touch, pointer, hover or key reaches the Mac; the keyboard's round trip);
   - the UI at every size, text size, VoiceOver and Reduce Motion.

   A "Review fixes" commit if needed, then S4 and S5 again on the final build. Hand P1–P11 to
   Noah. **Stop there.**

### 15. Hard rules (for every step)

- **Apple frameworks only:** SwiftUI and UIKit. No TipKit in this step.
- **No wire change, and nothing sent:** the tour sends nothing to the Mac, and while it shows the
  device sends no input either (§6.6). `StreamProtocol`, the host, the CLI and Sill.app are
  untouched.
- **No system presentation:** no sheet, popover, alert or full-screen cover. The tour is a view
  in the stream screen's hierarchy, as the Settings panel and the pairing overlay are.
- **Never over pairing or a notice:** never on the connect screen, never over the pairing overlay
  or a link's confirmation.
- **Never over someone at work:** it shows only when nothing has happened since the picture, or
  since a turn (§4).
- **Nothing collected:** two UserDefaults keys, read and written by this app alone (the privacy
  manifest's CA92.1). No analytics of how far anyone got.
- **Every layout:** the Duo's 1000×710, 710×1000, 500×710 and 710×500; iPhone upright and
  sideways, down to the iPhone SE; iPad. VoiceOver, every text size, Reduce Motion.
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
  - §9, How to capture them, step 4: the tour shows about a second after the picture if nothing is
    touched; touch the picture at once to go without it, or take it once, before the screenshots.
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
  rows of the `laptop` step, or a topic of their own, owed once to everyone who did not skip (§5).
- **The menu bar mirror** (`menu-bar-mirror`): a new bar control is a new topic, the same way.
- **`iphone-portrait`** (a worktree at cf05a78 with no commit yet): if it changes the iPhone's
  upright layout, the targets follow what it builds, and §6.3's table gains its numbers.
- **Aa alone** (seen in this critique, outside this step): a tap on Aa does nothing
  (StreamScreen.swift:615), and the HIG asks a custom gesture to supplement a standard one, not to
  replace it. The tour teaches the slide; a tap that opened the ruler until the next tap would be a
  change to the control itself.
- **Later, not planned:** single hints after the tour (TipKit's `TipGroup` on iOS 18, or the
  same overlay with one card), and "try it" steps (open question 5).

### 18. The critique (2026-09-27)

An adversarial pass over the first version of this plan (411ed27), against the code at cf05a78 and
the HIG pages named at the top. What it found, and what changed:

1. **Too long.** Sideways the tour was four cards and 14 rows, upright six cards and 18. The HIG
   wants a flow brief enough that nobody has to memorize much, warns that teaching too much
   overwhelms, keeps a tip to a sentence or two, and asks help not to explain standard components.
   Now three cards and 9 or 10 rows sideways, four cards and 12 rows upright. Rows for labelled
   buttons that need no gesture went (Apps, Desktop, the Settings button's own); `windows` and
   `bar` became `bar`; `keys` and `trackpad` became `laptop`, which leaves to the pad's own hint
   what it already says.
2. **It came in over people who had started.** The quiet second (no input for 1 s, any time in the
   10 s after the picture) caught whoever paused in those ten seconds, which is when a new user
   pauses, and it counted only what reached the Mac: a finger resting after a right-click with the
   Mac's menu open, a Pencil or trackpad drag held still, a scroll of the thumbnail strip, all sent
   nothing, and the tour could arrive in the middle of them (the first plan's own exception in
   §6.6). The HIG asks that help be easy to avoid for whoever does not need it. Now there is one
   decision, 1 s after the picture: the tour shows only if nothing at all has happened since, as a
   watcher on the window sees every touch; otherwise not this session. No gesture can then be in
   flight when it appears, so the exception is gone.
3. **A turn brought back the whole tour.** After a first picture that passed in landscape, the
   first upright moment offered all six upright steps to someone already at work. Now a turn
   offers only the steps its layout has alone (`laptop`); the shared ones wait for a later
   session's picture.
4. **VoiceOver was taught gestures it cannot make.** The picture and the trackpad are no
   accessibility elements; under VoiceOver a thumbnail's hold is a set of named actions and Aa is
   adjustable (StreamScreen.swift:620-630, :956-964). The run now leaves out `touch` and the
   trackpad's rows under VoiceOver (they stay owed), and the other rows say VoiceOver's way. Also:
   the row symbols, the dots and the dim hidden (decorative), focus moved to each new card's title
   with a layout-changed notification, as the HIG's VoiceOver page asks for a change on screen.
5. **Large text, and short screens, broke the card.** Sideways a bar step's card had only the room
   below the bar: 404 pt on the Duo's outer display, about 258 on an iPhone mini. At the largest
   size, once its footer and padding were placed, a mini left the title and rows about 130 pt: the
   title and a line of the first row. Even at the default size the old four-row `settings` card,
   360 pt wide, needed about 280 (§6.3's estimates). The HIG's Typography page asks every layout to
   adapt to every size, so there is still no cap: a card taller than its room now grows toward the
   top of the screen, over its own targets if it must, before its rows scroll, and on a short screen
   held sideways it is 480 pt wide, so at the default size it fits below the bar (§6.3).
6. **The phone was never photographed as it is.** The harness draws a fake screen with no insets,
   and S1's phone sizes (956x440 and 440x956) are sizes the stream screen never has: it keeps the
   top and side safe areas (StreamScreen.swift:169). Now the phone photos come from the normal app
   against a synthetic host (`-SillOrientation landscape` turns it), and the smallest screen the
   app runs on, the iPhone SE's 667×375 and 375×667, joins every size check.
7. **The cutout could miss its controls by an inset.** The dim was to cover the safe areas while
   the targets are measured in a space that starts inside them: on a phone upright the ring would
   have sat about 60 pt above its controls, with nothing wrong in the harness. The dim now moves
   the cutout into its own frame (§6.1).
8. **A tap gesture on the dim can take the card's taps.** PairingOverlay.swift:43-45 records it
   for a backdrop. The dim's tap area now leaves out the card, and the nudge goes if S1 still sees
   a lost tap.
9. **A hardware keyboard does nothing until Keyboard is tapped** (InputOverlay.swift:403-416), and
   the first plan's Keyboard row ("types on ‹Mac›. A hardware keyboard works too.") did not say
   so. The row now says it types on the Mac on screen or with a hardware keyboard, and it is the
   row the landscape `bar` card keeps.
10. **The background.** "The tour is there on return" held only for a trip of under 4 s: the Mac
    evicts a suspended device after that, and the next session resumes at the first step not
    passed (§12).
11. Smaller: TipKit's inline `TipView` considered as well as `popoverTip`; the card's padding the
    panel's 14 pt; no dots on a one-step run; `-SillTour` in the normal app; the stand-ins
    `-SillTourActivityAt` and `-SillTourVoiceOver`; the tripwire's one expected case (a coast after
    a flick, under Take the Tour).

Kept as it was, against the HIG's preference for tips in context and teaching by doing: the flow
(Noah asked for a walkthrough) and the paused input (a click on someone's own Mac is not a safe
test), both open questions for Noah. Kept too: the form (coach marks in the view hierarchy), the
two keys, Skip for good, Take the Tour last in Settings, and the Debug rule.

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **The form.** Default: **coach marks over the live controls**, in the view hierarchy, one step
   at a time. The alternatives: a paged card with drawings, or TipKit tips (Decision).
2. **When it first shows.** Default: **1 s after the first picture, if nothing was touched, sent
   or opened since; otherwise not this session.** The alternatives: at the first quiet second
   within 10 s (the first version: it caught people at their first pause); at the connection,
   before the picture; or at any quiet moment of the session, however late.
3. **What "once" means.** Default: **each step until it is passed, or all of it once skipped**; a
   session that ends mid-tour leaves the rest for the next one. The alternative counts the whole
   tour as seen once its first card has shown.
4. **The upright card.** Default: **after a tour in landscape, `laptop` shows the first time the
   device is held upright and left alone for a second**; a turn never offers the shared steps. The
   alternative: only through Take the Tour.
5. **Input while it shows.** Default: **paused** (as asked): no touch, Pencil, pointer or key
   reaches the Mac, and the picture keeps moving. The alternative: "try it" steps that let each
   gesture through and go on once it is done.
6. **A tap outside the card.** Default: **nothing, and Next nudges** (unless S1 finds a tap lost to
   the dim, §6.1: then nothing at all). The alternatives: it goes to the next step; it closes the
   tour, as a tip would.
7. **Back.** Default: **none;** Take the Tour replays. The alternative: a Back button beside Skip.
8. **The row's name and place.** Default: **"Take the Tour", the last row of the Settings panel's
   scrolling rows.** The alternatives: "How to Use Sill"; beside Disconnect in the pinned foot; a
   "?" button in the bar (the outer display's bar has no room for it).
9. **Text size.** Default: **every size, the accessibility sizes included;** a card too tall for
   its room grows toward the top, over its own targets if it must, then scrolls. The alternatives:
   capped at accessibility-3 (235 % of the default size, past the 200 % the HIG's Accessibility
   page asks for), or at xxLarge like the Settings panel.
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
15. **Three and four cards.** Default: **§3's cards,** cut by the critique from four and six. The
    alternatives: Apps and Desktop back on the `bar` card; `keys` and `trackpad` as two cards
    again.
16. **VoiceOver.** Default: **the run leaves out what teaches raw touch** (`touch`, the trackpad's
    rows) and speaks the rest VoiceOver's way. The alternative: keep `touch`, teaching VoiceOver's
    pass-through (double-tap and hold, then the gesture), which has not been tried on the stream's
    input view.
17. **What counts as someone starting, under assistive technology** (the review). Default: **any
    control used by any means** (VoiceOver's double tap, Switch Control, Voice Control, Full
    Keyboard Access), **not VoiceOver's swipes that only move its focus**: those are reading, like a
    look around the screen, and VoiceOver moves its focus by itself as the stream screen or a layout
    comes, which would pass the tour for no one's action. The alternative: count every focus move
    too (UIAccessibility's element-focused notification), as the review suggested; then a VoiceOver
    user who explores the bar in the first second never gets the tour, and a turn's own refocus may
    pass the upright card.
18. **A card at large text on a small screen** (the review). Default: **beside its targets, its
    words scrolling there**, so the lit control and its ring stay in view (only a room under 200 pt
    makes it cover them, and then without a ring). The alternative, the plan's first rule: grow over
    its targets, showing more words at once but hiding the control it is about.
19. **Take the Tour's Skip.** Default: **"Skip" as in the automatic tour, closing the run** without
    turning the automatic tour off. The alternative: label it "Close" in Take the Tour.
20. **The automatic reconnect** (the review). Default: **it goes on with the last session's
    decision** for the app's run, and a run cut short comes back at its picture. The alternative:
    every connection decides afresh (as built first), which can dim the screen over someone at work
    a second after their picture comes back.
21. **A phone held upright** (main's new layout, merged after this plan). Default: **`bar` lights the
    thumbnails with Aa and Keyboard, as sideways**; since the strip spans the row, the cutout takes in
    rows 1 and 2 whole (Apps, Desktop and Settings too). A bar or Settings card that does not fit
    above the rows goes under them. The alternative: a cutout of several shapes (only the three
    controls), which the dim does not draw yet.

---

## Results (2026-09-27, the build)

Built on `first-run-walkthrough` as §14 orders it, one commit per step (the rules and their check;
the overlay and the stream screen; Take the Tour; then fixes and docs). Every open question took its
default.

### Where the build departs from the plan, and why

- **The count goes on across a rotation.** §3.2 recomputed a run "less what this run has passed",
  which would restart the dots ("Settings, step 1 of 2" after two cards). `TourPolicy.carry` gives
  the new layout's steps (Take the Tour: all of them; the automatic tour: those owed and those this
  run passed), so the card on screen keeps its place ("3 of 4"). A step the new layout lacks gives
  way to the next one after it not yet passed, and with none after it the run ends (a run at
  `laptop` turned sideways), nothing more saved.
- **A `laptop` card passed under VoiceOver counts as seen.** §6.5 kept the trackpad's rows owed for
  a run without VoiceOver; memory is per topic, and keeping `laptop` owed would bring the keys card
  back at every upright session of a VoiceOver user. `touch` stays owed, as planned.
- **"Not active" is UIKit's `applicationState`.** SwiftUI's `scenePhase` read inactive for an app
  that was active and on screen in a headless simulator (every decision passed as "the app was not
  active"); `UIApplication.shared.applicationState` read active.
- **The strip's lit band** is its thumbnails' band with the active halo's 5 pt above and the app
  badge's 6 pt below (`WindowStrip.tourBand`), so the cutout never cuts a badge; sideways the ring
  then runs along the bar's top and bottom.
- **The tail and the card's frame come from its laid-out height.** A `GeometryReader` in the card
  reported frames scaled by the appear animation (0.94 to 1 over a quarter second), which hid the
  tail until the end and changed the report every frame. Placed again at the height it was given, a
  card lands where the layout put it; the check asserts that over its whole grid.
- **The Settings row's group** has 10 pt above it when it follows a row, not a footnote (while
  settings load, and for a Mac without them).
- **Added:** `-SillTakeTourAt S` (the gates may not tap Take the Tour), and "S s after the picture"
  on the console's `showing` lines. The scrolling words fade out over 16 pt above the footer instead
  of being cut mid-line; Next and Done get 4 pt more height at large sizes.

### Found and fixed while building

- On the iPhone SE at accessibility-extra-large text the laptop card's Done wrapped to two lines:
  the footer's line was measured with its buttons' words free to wrap. They are fixed size now, and
  the line gives way to the stack when it would squeeze them (photographed at 375x667 at the default
  size, accessibility-extra-large and the largest size).
- A run carried into the other layout did not mark it offered, so a later turn back could offer the
  laptop card again in the same session.

### Verified

- **H1:** iOS Debug and Release for the simulator and Debug for a generic device (unsigned):
  `** BUILD SUCCEEDED **` with only the known `StreamClient` capture warning; the state of each
  commit builds.
- **H2:** `Tests/checks/tour`, 34,059 checks (the rule at every boundary, runs, carry both ways with
  and without VoiceOver, the crease against `ConnectLayout.topHalf` at 20 sizes, the width, the
  placements pinned at the Duo's four sizes and the iPhone SE's two against an oracle written from
  §6.3's words, a grid of 400 screens by six card heights, both text regimes and two insets with
  its properties, every string); 35 of 35 mutants caught (§14's 26 and nine more); in CI's mutants
  matrix; `Tests/checks/run-all.sh` passes whole.
- **H3:** no sheet, popover, alert, full-screen cover or TipKit, and nothing sent, in `Tour*.swift`;
  `TourPolicy.swift` imports Foundation and CoreGraphics; `requestGeometryUpdate` only under DEBUG;
  nothing in `Sources`, `Packaging`, `Scripts`, `Info.plist` or `PrivacyInfo.xcprivacy` changed;
  A401, F401, A402 and F402 in their four places.
- **H4:** the mock with no argument, the drawer, the held thumbnail's lights, the Aa ruler,
  nothing active, the pairing overlay, the connect screen's methods and Add a Mac, at the four Duo
  sizes, this build against the base (this plan's commit, built from `git archive`): 28 of 32 equal
  pixel for pixel; the four held-thumbnail photos differ where it wiggles, as two photos of the base
  do. `-SillSettings 1` equal at the four sizes; with `-SillSettingsEnd 1` the rows end in the new
  row.
- **S1, S2:** every step at 1000x710, 710x500, 710x1000, 500x710, the iPad Pro 13-inch's
  1376x1032 and 1032x1376, and the iPhone SE's 667x375 and 375x667, at the default text size and at
  accessibility-extra-large; the largest size at 710x500, 500x710, 710x1000 and 667x375; the
  VoiceOver run at 1000x710 and 500x710. Every card's frame and tail, from the console's
  `tour: screen …` lines, is what the check's model of the layouts gives. Sideways the bar's cards
  sit 12 pt under the bar with a tail up; at 710x1000 nothing crosses the crease and no tail
  points across it; at 500x710 and on the iPhone SE the bar and Settings cards point down at the
  window bar; at larger sizes a card grows toward the top, over its targets if it must, and its
  words scroll under a fade with the footer whole.
- **S3:** Take the Tour at the end of the panel's rows at 500x710, 710x500 and 1000x710, for a Mac
  with settings, one without (legacy) and one offering Pair This iPad…, at the default size and
  xxLarge.
- **S4:** in the mock: `fresh` no tour in the first second and the touch card at 1.07–1.17 s;
  `landscape` at 710x1000 the laptop card alone, with its subtitle and no dots; `done` and
  `skipped` nothing ("nothing owed here"); the Apps list open, a stand-in touch at 0.5 s and the
  pairing overlay each "not this session" with the reason; `-SillTourPress next@1` through Done,
  "done (saved: touch, bar, settings; this run only)".
- **The saved keys, in the mock** (a fresh install, `-SillTourState saved`): the first session
  showed the tour and saved each step as Next and Done passed it; the second said "nothing owed
  here"; Take the Tour from the Settings panel (`-SillTakeTourAt 2`) showed it again from the
  first step; the app's plist held `Sill.tourSeen` touch, bar, settings and `Sill.tourSkipped`
  false.
- **S5, live** (03:28–03:40, once Noah's iPad had left Sill.app: it streamed from 01:17 on, and
  `Scripts/encoder-check/no-device.sh` blocked every try until then). The normal app on an iPhone
  18 Pro Max against `SillHost --synthetic` on loopback (`-SillConnect`), one host at a time, the
  guard before each and a watchdog on Sill.log during, each host under 40 s, none left running:
  - (a, b) on a fresh install with `-SillTourState saved`, the first connection showed the touch
    card 1.06 s after the picture (1.10 s in the first run) and, `-SillTourPress next@2` pressing
    through, saved touch, bar, settings and laptop; the second connection said "nothing owed here
    (portrait; seen: touch, bar, settings, laptop)"; the third, with `-SillTakeTourAt 2`, opened
    Settings and its Take the Tour showed the tour from the first step, 3.37 s after the picture.
  - A session cut at the third card (the host killed; the stand-in had just passed that card) went
    on at the next connection with what was left: the laptop card alone, 1 of 1, with its
    subtitle.
  - (c) a host with `SILL_TEST_MIN_DEVICE_VERSION=99`: the connect screen's update notice, and no
    `tour:` line.
  - The phone's real safe areas: every step upright (the stream screen 440x894 under the Dynamic
    Island) and sideways (`-SillOrientation landscape` turns the normal app; 832x440 between its
    insets), at the default size and at accessibility-extra-large: each ring on its controls, not
    an inset away (the critique's §18 item 7), the cards clear of the Dynamic Island and the home
    indicator, "iPhone" and no Pencil row.
  - (d) The tripwire never printed.
- **Found there and fixed:** upright on that 3x screen the Settings card faded its second row as
  if its words scrolled: offered exactly their height, the words missed their fit test by a
  rounding. The card is now measured with a point of slack (reproduced in the mock at 440x956 on
  the same simulator, and gone after). The iPad and iPhone SE photos above were taken one commit
  before it, on 2x screens, which never showed it; the slack moves a card by under 2 pt.

### Review fixes (2026-09-27)

A review of the build (its findings came with probes: an injected library turning the accessibility
runtime on, scrolling a card or activating a control as VoiceOver does, and pure replays against
TourPolicy) found eight things. Each was checked here before it was fixed, one commit each:

1. **Next kept the last card's scroll** (Reduce Motion off: the card keeps its identity as it
   slides, and so did its scroll view): at a size where the words scroll, a card scrolled to its end
   opened the next mid-text (offset 486 of 974.5 at 710x500, the largest size). Each step scrolls
   the words to their top and flashes the indicators. The same probe after it: 0 of 974.5 on the
   iPad at 710x500, and 0 of 574 on an iPhone upright after a bar card scrolled to 847.
2. **Skip in Take the Tour saved the permanent skip,** so the upright card and every later topic
   were lost for someone who only closed a tour they had asked for. `TourPolicy.skip`: in Take the
   Tour it closes the run and saves nothing (open question 19). In the mock: the automatic tour
   through Done, Take the Tour and Skip ("closed (Take the Tour; nothing more saved)"), then upright
   the laptop card still came; the automatic tour's Skip still saves it.
3. **Assistive technology's actions did not count as someone starting:** an accessibility
   activation of a thumbnail 0.8 s into the beat picked it, and the tour came over it at 1.15 s.
   `StreamClient.lastActionAt` (a person's pick, launch, window command or move in the bar, a
   settings change, and the bar's own buttons, whatever drove them) now counts; the device's own
   Desktop request does not; VoiceOver's focus moves do not (open question 17). The probe after it:
   a thumbnail, and Desktop, activated in the beat give "not this session: used within a second of
   the picture"; with accessibility on and nothing activated the tour still comes.
4. **Every automatic reconnect decided afresh,** so someone at work got the dim a second after a
   dropped picture came back. What a session decided (`TourSession`) lives on StreamClient and the
   automatic reconnect's session goes on with it (open question 20), unless the last one ended
   before its decision or mid-run. Live, on loopback through the remote door (`SillHost --synthetic
   --remote=PORT` with its identity kept in a scratch folder, the app paired at launch; the first
   host killed, a second on the same port and identity, the app's own automatic redial 4.1–4.2 s
   after the loss): a first session that passed (a stand-in touch), the reconnect's session kept
   the decision and showed nothing; a first session cut at its second card, the reconnect's
   session showed the tour again from the first step not passed, 1.02 s after its picture; a first
   session through Done with fresh memory, the reconnect's session showed nothing, where the build
   before (f8bf1ec, the same run) showed the tour again 1.07 s after its picture.
5. **The bar card taught Aa over the Desktop,** which Aa does not resize (the Mac fits only a
   window to a viewport's scale): the row says a window's text now (§7).
6. **At accessibility sizes a card covered the controls it lit,** with slivers of its ring beside
   it (500x710 and phones upright). A card now stays beside its targets and its words scroll there
   (§6.3, open question 18); only a room under 200 pt makes it cover them, without a cutout or ring.
7. **A put-aside run ended by a turn put the keyboard back up under a link's confirmation,** where
   hardware keys reach the Mac. It now stays down under the overlay.
8. **A new frame size sent a pointer move under Take the Tour,** once the Pencil or the trackpad
   had shown the drawn pointer. The move waits for the tour's end (`StreamClient.inputPaused`).

Found while verifying them: the tour's delayed work (the beat's wait, Take the Tour's start, the
DEBUG stand-ins) acted on a stream screen that had gone with its session; in the live run a
stand-in pressed Next on a gone card and saved its step. It now goes ahead only in the session it
began in. The DEBUG `-SillTourActivityAt` touches in the app run's first session only, so a live run
can show a reconnect keeping its decision.

### Merged with main at 5c6a850 (PRs #29, the disk image, and #30, the iPhone's portrait layout)

PR #30 gives a phone held upright its own arrangement (§3.1). The merge put the targets on its
views; `TourLayout.phone` gives the tour its rules there: `bar` lights the strip with Aa and
Keyboard, and its card has the Keyboard row; the laptop card has no keyboard key row; the hints say
where the rows are (§7); a card too tall for the short picture pane stands 12 pt over its targets,
and a bar or Settings card that does not fit above the rows goes under them (§6.3; open question 21).
At the default size on an 18 Pro Max the bar card (273 pt, 269 of room above the rows) sits under
the thumbnails. `Tests/checks/tour` compiles `PhonePortraitLayout.swift` and places cards against
its rects.

### Merged with main at 2b38179 (PRs #31, the Mac's pointer on the device, #32 and #33)

The Mac's pointer replaced `StreamClient.localPointer` with `PointerPresence` and its feed; a new
frame size now goes through `pointerFrameChanged`, which holds the Mac's move while a card shows
(the eighth fix, carried onto it) and sends it at the pause's end only if this device still has the
pointer and its own still shows. The Mac's arrow is drawn in the display view, under the dim. The
tour's photos on the iPhone were the same before and after this merge (card frames and pixels).

### Verified after the review and the merges

- `Tests/checks/tour`: 43,784 checks (34,059 before: Skip, sessions, the carried decision, the
  phone's steps, copy and carry, cards beside their targets, phone pins at 440x894, 402x812, 375x647
  and 500x710, and the grid over every phone size), 63 of 63 mutants (35 before); `run-all.sh`,
  all 18 checks after the first merge and all 21 after the second.
- iOS Debug and Release for the simulator and Debug for a generic device (unsigned), each commit's
  state building, only the known StreamClient capture warning; `swift build -c release`.
- Harness photos on a private iPad Pro 13-inch, before the merge: every step at the four Duo sizes
  and the iPad's two at the default size, pixel for pixel the build before's (the same simulator)
  but the bar card's new words and what differs between two runs of either build (the home
  indicator, a thumbnail strip's end); the largest size and accessibility-extra-large at 500x710,
  710x500, 710x1000 and 1000x710, every bar, Settings and laptop card beside its targets with its
  tail. After it: the phone's arrangement (`-SillIdiom phone`) at 440x894, 402x812, 375x647 and
  500x710, and at two larger sizes; the harness's other states (no tour) against main's build,
  equal but the Settings panel's last row and its scroll indicator, and what differs between two
  runs of main's own build; and, on the iPhone simulator, the halves (710x1000, and 500x710 as an
  iPad draws it, `-SillIdiom pad`) and both landscape sizes, each card anchored and tailed where it
  was before the merge (its height differs only by the 3x screen's rounding and the iPhone's
  words).
- On a private iPhone 18 Pro Max: the harness at 440x894 and 956x440 with the iPhone's words (no
  Pencil row), and live against `SillHost --synthetic` (the guard before each host, a watchdog on
  Sill.log during, each host under 30 s, none left running): every step upright (440x894 under the
  Dynamic Island) and sideways (832x440), at the default size and accessibility-extra-large, each
  ring on its controls under the real safe areas. After the second merge, again live on the
  iPhone (the hosts on loopback and the software encoder, `SILL_TEST_LOOPBACK`,
  `SILL_TEST_SOFTWARE_ENCODER`): the reconnect after a session that passed showed nothing, the one
  after a run cut at its second card showed the tour from the step not passed, and the phone's
  cards sat where they did before. The tripwire never fired in any live run.

### Untested, for Noah

§13's P1–P11 on the iPad mini and the iPhone 15 Pro, and the taps themselves: no tap could be made
here, so Next, Skip, Done, a tap on the dim (the nudge, and whether any tap is lost to it: §6.1's
fallback) and the touch watcher on a device (a touch in the first second leaves the session
alone) are for the devices. After the review, also: P12 on the iPhone upright, the new arrangement's
cards (the bar card under the thumbnails, the laptop card standing on the keys); P13 start at once,
then let the connection drop (Wi-Fi off and on, or the Mac asleep and awake): no tour when the
picture comes back; and with the tour on screen at the drop, it comes back; P14 with VoiceOver on,
double-tap a thumbnail within the first second: no tour this session; P15 Settings › Take the
Tour, Skip at its first card, then hold the device upright: the laptop card still comes; P16 at
the largest text size, each bar, Settings and laptop card beside the controls it lights, their
ring whole, the words scrolling.

