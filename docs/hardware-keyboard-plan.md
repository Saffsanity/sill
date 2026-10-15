# A hardware keyboard and trackpad on the device — the plan

2026-10-14. Branch `hardware-keyboard` (worktree `/Users/noah/Downloads/winstream-hardware-keys`)
from origin/main at 985a733, PR #80; line numbers are at 985a733. Issues #67 and #68. Device app only; no
wire change, nothing on the Mac changes. The triage that led here, with file:line evidence for each
cause, is `~/Downloads/sill-handoff/triage/2026-10-13-open-items.md`.

**Noah's request (2026-10-14, as the workflow relayed it):** "Work on the keyboard and trackpad
change (#67 and #68 together)". The workflow's brief: Esc through a key command, hardware keys
forwarded whenever a keyboard is attached (a pure rule with a check), and trackpad and mouse-wheel
scrolling over the stream.

## The problem

**#67, Esc never reaches the Mac** (puckdoug: iPad Pro 13" M4, iPadOS 27.0.1, Magic Keyboard). His
own log shows 22 `in.text` and no `in.key` while he pressed Esc: the iPad never sent it. The Mac
would take it (usage 0x29 is key 53, KeyStrokes.swift:195). The device forwards Esc only from
`pressesBegan` (InputOverlay.swift:462; `ForwardedKeys.keyUsages` has 0x29, KeyChords.swift:109),
and iPadOS does not hand a hardware Escape to `pressesBegan` of a text-input first responder (the
iPadOS 27 simulator never did either: docs/remote-access-plan.md R12, commit 5468bdc). UIKit's
header says why a key command can still get it: `wantsPriorityOverSystemBehavior` "indicates
whether the key command should execute if it conflicts with focus or text-editing system
commands". Sill already uses such a command for Esc where a field has the keyboard (`EscapeKey`,
AddMacCard.swift:303). Sideways there is no on-screen esc at all (only the portrait key row has one),
and an iPad on a Magic Keyboard is always sideways.

**#68 (b), typing needs the Keyboard button.** Keys and text reach the Mac only while the stream's
input view (`InputOverlayView`, a `UIKeyInput`) is first responder (InputOverlay.swift:343, 375–394,
462–479). Only the Keyboard button, a restore after Settings, the Menus pull-down or the tour, or
DEBUG `-SillKeyboard 1` make it so. A new session, a rotation (the other layout's input view is a new
view) and Pair This iPad… all leave it down, and with nothing first responder iPadOS's own File ›
Close takes ⌘W and closes Sill's window (docs/menu-bar-plan.md, "Why the device never registers the
Mac's shortcuts as key commands": while the input view is first responder it wins every key,
⌘W included).

**#68 (a), two-finger trackpad scrolling does nothing.** A Magic Keyboard's trackpad and a mouse
wheel deliver scroll events, which only a pan recognizer with `allowedScrollTypesMask` receives. The
stream's pan is fingers-only with the mask at none (InputOverlay.swift:83–88). The pointer, clicks
and drags already work (`touchesBegan` takes `.indirectPointer` touches, InputOverlay.swift:289).
The Mac already takes both kinds of scroll: phased gestures with momentum, and bare wheel deltas
(InputInjector.swift:237–262).

## The design

### 1. Esc through a key command

- `InputOverlayView.keyCommands`: Esc (`UIKeyCommand.inputEscape`) with each of the sixteen
  combinations of ⌃, ⌥, ⇧ and ⌘, each with `wantsPriorityOverSystemBehavior = true`, no title (so
  none is listed in iPadOS's shortcut overlay or the menu bar). Only while the view is first
  responder and no `EscapeKey` is on screen in its window (the tour, the pairing overlay, the Settings
  panel, the Add a Mac card): then the key goes to that view's own Esc, as before. A leaf view is in
  the responder chain only while it is first responder, so the commands are out of the way whenever
  the overlay does not take keys; the two conditions say so again in `keyCommands` and in
  `canPerformAction`.
- **Each Sill window is its own** (the review's first finding). Every window has its own responder
  chain, so an `EscapeKey`'s command, on its window's view controller, never sees a key pressed in
  another window: Settings left open in a window behind must not take Esc from the stream in front
  (`EscapeKey.onScreen(in:)`), and Esc pressed in a window goes to the newest `EscapeKey` in that
  window only, never to another window's panel (`fire(in:)`, the window of the view controller UIKit
  hands the command to).
- The action sends the key down and up through the path a forwarded hardware key takes
  (`ForwardedKeys`), carrying the command's modifiers: down with them, up with the modifier keys down
  on the Mac. A key command gives no key-up, so the up follows the down at once (a tap; holding Esc
  repeats it, as UIKit repeats a held key's command).
- **Both channels, one key press.** A device that delivers the press to `pressesBegan` as well must
  not send Esc twice (`ForwardedKeys`, pure, checked in `key-strokes`):
  - the press came first: Esc is down on the Mac through it (`down` has it), so the key command
    sends nothing and the press's own up follows;
  - the key command came first: the press whose timestamp is not after the command's (the same key
    press; a later press has a later timestamp) is swallowed, and so is its up, never passed on to
    the text system.
- **DEBUG, which channel delivered it.** Every hardware key the overlay sees prints one line, as
  Noah needs on a device: `hwkey: usage 41 down via keyCommand (shift): to the Mac`, `hwkey: usage 41
  down via pressesBegan: to the Mac`, `hwkey: usage 4 down via pressesBegan: the text system's`,
  `hwkey: usage 41 down via pressesBegan: the key command sent it`. With `-SillKeyProbe 1` the
  GameController keyboard's own handler prints `hwkey: usage 41 down via GameController` too, so a
  key iPadOS gives to neither UIKit channel still shows (the next fix would then be a GameController
  path).
- **The Settings panel's Done** keeps `.keyboardShortcut(.cancelAction)` (⌘. and Esc where SwiftUI
  gets it) and gains `EscapeKey(action: close)`, the priority command the tour and the pairing
  overlay use (HostSettingsPanel.swift:190), since SwiftUI's shortcut does not ask for priority.
- **For the reporter**: Control-[ reaches the Mac as Control plus the [ key, which iTerm2, zsh's vi
  mode and Zed's vim mode take as Escape (untested on a device).

### 2. Keys reach the Mac whenever a hardware keyboard is attached

**The rule, `HardwareKeyboardPolicy`** (iOSClient/HardwareKeyboardPolicy.swift, pure: Foundation
only; `Tests/checks/hardware-keyboard`). A state machine the stream screen's `InputOverlayProxy` owns
(it outlives a rotation; a new session makes a new one). It knows:
- `attached`: a hardware keyboard is attached (`GCKeyboard.coalesced`, and
  `GCKeyboardDidConnect` and `DidDisconnect`; DEBUG `-SillHardwareKeyboard 1|0` overrides it);
- `takers`: what is open that takes the keyboard for itself or must keep keys from the Mac: the
  Settings panel, the pairing overlay (Pair This iPad… or an outside link), the tour, the Apps
  drawer (its search field), the Menus pull-down. The Add a Mac card is the connect screen's, where
  no input view is on screen;
- `onScreen`: the current input view is in a window (a session's stream screen);
- `hold`: who holds the keyboard now: nobody, the rule (`automatic`, for the hardware keyboard), or
  the person (`own`: the Keyboard button, or a restore of the keyboard they had up).

The automatic hold is wanted when `onScreen && attached && takers.isEmpty`. What it does, event by
event (each returns the actions the proxy performs: `take(automatic:)`, `makeOwn`, `letGo`):
- **A view joins a window** (a session starts, a rotation's other layout, a reconnect's new screen):
  the new view holds nothing yet; it takes the keyboard for the hardware keyboard if wanted. The old
  view's resignation, when it comes, is the old view's and changes nothing here.
- **The keyboard attaches**: taken if wanted. **It detaches**: an automatic hold lets go (the
  person's own keyboard stays: they asked for it).
- **A taker opens**: an automatic hold lets go. (Settings, the tour and the pairing overlay already
  take any keyboard down themselves, `setKeyboard(shown: false)`; the drawer and the Menus pull-down
  never took the person's own, and still do not.) **The last taker closes**: taken if wanted, unless
  the restore of the person's own keyboard (Settings, the tour, Menus over Settings) came first.
- **The Keyboard button**: nobody holds it: the person's own, as today (the software keyboard, or
  iPadOS's small bar when a hardware keyboard is attached). The rule holds it: it becomes the
  person's (the button lights, iPadOS's keyboard views come back). The person holds it: let go, and
  the rule takes it again at once if wanted, so the software keyboard goes and keys still reach the
  Mac.
- **Another responder takes the keyboard** (a text field the rule does not know): not fought; the
  next moment above takes it back.
- **UIKit gives it back by itself** (after a presentation): it counts as whatever this view last
  held.

**The person's own action.** Only the person's own hold is the person's: it lights the Keyboard
button and the key row's keyboard cap, it is what the tour's rule counts as "the keyboard was up"
(busy, StreamScreen.swift:565) and its changes are activity (StreamScreen.swift:321). The automatic
hold is none of these, so a person with a keyboard attached still gets the tour, and the Settings
panel and the tour put back only the person's own keyboard (`keyboardBeforeSettings`,
`tourKeyboardAfter`), the rule the hardware hold.

**No on-screen keyboard for the automatic hold.** While the rule holds the keyboard the input view's
`inputView` is an empty view and its assistant item has no groups, so iPadOS shows no keyboard and
no shortcuts bar over the stream, even if it counts the keyboard as gone (a keyboard folded behind
the iPad) a moment before GameController says so. Typing on a hardware keyboard still reaches
`insertText` and `pressesBegan` (a custom input view changes only what is drawn). The person's own
hold has the system keyboard, as today.

### 3. Trackpad and mouse-wheel scrolling over the stream

Two more pan recognizers on `InputOverlayView`, scroll-only: `maximumNumberOfTouches = 0`,
`allowedTouchTypes = [.indirectPointer]`, refusing every touch in the delegate:
- **`.continuous`** (a trackpad's two fingers, a Magic Mouse): the finger pan's path, at the
  pointer's location: `.scrollGesture(.began)`, a `.scroll` delta per change (fractions of the
  picture, natural sign), `.scrollGesture(.ended)`, then Sill's own coast from the lift's velocity.
  iPadOS hands a pan no momentum of its own (a scroll view decelerates by itself), so this is no
  double coast; if a device shows one, a new scroll gesture stops the coast at its begin, as a new
  finger does.
- **`.discrete`** (a mouse wheel): plain `.scroll` deltas, no phases and no coast, which the Mac
  posts as a wheel's.
- **A pointer scroll's first event is a delta.** A wheel's pan begins with its first notch already
  in its translation and a single notch has no change after it (measured in the simulator: began at
  3 pt, ended 0.2 s later at 3 pt), so for the trackpad and the wheel the begin's translation goes
  out, and so does any remainder at the end. The finger pan's begin is as before (its first change
  carries the movement), so a finger's events are unchanged.

The three scroll recognizers never overlap (none begins while another's scroll is open), and the
pointer ones recognize alongside the hover recognizer. Every layout that shows the picture uses this
view: sideways, the portrait halves' picture, the phone's pane, the Duo. The tour, the drawer and the
Settings panel already cover the stream for hit-testing.

## Open questions (the default is taken unless Noah says otherwise)

1. **The Keyboard button with a hardware keyboard attached.** Default: it keeps its meaning for the
   software keyboard and lights only when the person asked for it; the hardware hold leaves it dark.
   Alternative: it lights whenever keys go to the Mac, and turning it off stops them for the session.
2. **The Apps drawer.** Default: while it is open keys go nowhere (they do not go to the Mac behind
   it); its search field takes them when tapped. Alternative: with a keyboard attached the search
   field takes them as the drawer opens ("type to search").
3. **The Menus pull-down.** Default: the hardware hold lets go while it is open (the menu takes the
   arrows and Return itself); the person's own keyboard stays, as today.
4. **Which Esc combinations.** Default: all sixteen, so ⇧Esc, ⌘Esc and ⌥⌘Esc (the Mac's Force Quit
   window) go too. Alternative: Esc alone.
5. **The input view's look during the hardware hold.** Default: no keyboard and no shortcuts bar.
   Alternative: iPadOS's own small bar (with its keyboard button).
6. **The person's own software keyboard across a rotation.** Default: down, as today (only the
   hardware hold comes back). Alternative: carried to the other layout.
7. **⌘W while something else has the keyboard** (Settings, the drawer, Menus, the tour, pairing).
   Default: unchanged, the iPad's File › Close closes Sill's window (docs/menu-bar-plan.md Q8).
   Alternative: remove the iPad's File › Close while a session streams.
8. **The trackpad's coast.** Default: Sill's own, as a finger's. Alternative: none for a trackpad.
9. **The portrait on-screen trackpad.** Default: a hardware trackpad's scroll over it does nothing
   (it scrolls over the picture). Alternative: scroll there too.
10. **The GameController probe.** Default: DEBUG only, behind `-SillKeyProbe 1`.
11. **Full Keyboard Access and Switch Control** (the review's fourth finding). With a keyboard attached the
    stream's input view holds the keyboard whenever nothing is open over the stream, so Tab, Space and the
    arrows go to the Mac and Esc's commands ask for priority over the focus system; and while a keyboard is
    attached the Keyboard button never lets go for good (a second press goes back to the hold,
    `HardwareKeyboardPolicy.toggled()`). Someone who moves through Sill's bar from the keyboard may then
    not reach Settings or Disconnect while streaming. Default: the hold as for anyone, until step 13 says
    otherwise. Alternative: no automatic hold while such a technology runs. UIKit can tell Switch Control
    (`UIAccessibility.isSwitchControlRunning`) but not Full Keyboard Access (the iOS 27.1 SDK's UIKit
    headers name no such test), so for Full Keyboard Access the alternative is Q1's: the Keyboard button's
    second press stops keys for the session.

## Test plan

- **H1** `Tests/checks/hardware-keyboard` (new): `HardwareKeyboardPolicy`'s events, scenario by
  scenario (a session start, a rotation either way round, a reconnect, each taker, the keyboard
  coming and going, the button in each state, a responder taking it, UIKit giving it back), then
  random sessions against a model and the invariants (never an automatic hold with a taker open, no
  keyboard or no view; never the person's own made by the rule; every moment that should take it
  does). Mutants, every one caught; in CI's mutants matrix.
- **H2** `Tests/checks/key-strokes` extended: the key command's Esc (`ForwardedKeys.commanded`) with
  each modifier, after a forwarded ⌘, both orders of the two channels, a repeat, the swallowed press's
  up, and the random sessions with key commands among their events; mutants.
- **H3** Builds: the iOS app Debug and Release for the generic simulator and Debug for a generic
  device (`CODE_SIGNING_ALLOWED=NO`), only the known warnings; `swift build -c release` (no host
  file changes); `Tests/checks/run-all.sh`, all.
- **H4** Harness photos on a private simulator, this branch against main's build, at the Duo's and
  an iPad's sizes, landscape and portrait, with the drawer, the Settings panel and the keyboard
  button lit: identical (also with `-SillHardwareKeyboard 1`, whose hold draws nothing).
- **H5** Live against `SillHost --synthetic` on loopback (`SILL_TEST_LOOPBACK=1
  SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_INPUT_LOG=1`), a private simulator,
  `-SillLive 1`: `-SillInputTest 1` with the overlay's new half (Esc through the key command's own
  action, ⇧Esc, a trackpad scroll with its coast, a wheel), the host's `in.dry` counts and its "Test
  input" lines; with `-SillHardwareKeyboard 1` the automatic hold at the session's start and after a
  rotation (an InputScript step turns the scene), let go while Settings and the tour show (nothing
  sent then), taken again after.
- **H6** If the simulator takes one: a virtual HID keyboard and mouse inside the private simulator
  (TEST ONLY, as `Tests/duorig` posts the Duo's hinge), so UIKit's own routing runs: which channel
  delivers Esc, the automatic hold with GameController's keyboard, no on-screen keyboard, the scroll
  recognizers.
- **H7** The touch rig (`Tests/touchrig`), if it can make indirect scroll events; else say so.

## Untested, for Noah

On the iPad with a Magic Keyboard (the reporter's is an iPad Pro 13" M4 on iPadOS 27.0.1), a Debug build of
this branch (the console's `hwkey:` and `keyboard:` lines) against Sill.app built from this branch or main
(nothing on the Mac changed), streaming a window:

1. **Esc and its channel.** Press Esc in a text field on the Mac: it reaches the Mac (the Mac's app
   reacts, and Sill.log's `[1s]` line counts `in.key`; #67's log had only `in.text`). The console says
   which channel brought it: `hwkey: usage 41 down
   via pressesBegan (none): to the Mac`, or `via keyCommand`. With `-SillKeyProbe 1` a line `via
   GameController` comes too; if only that one comes, iPadOS gives the key to neither of UIKit's channels,
   and the next fix is a GameController path (say so). Note the keyboard model and whether Caps Lock is
   remapped to Escape (Settings › General › Keyboard › Hardware Keyboard).
2. **Esc in a terminal and an editor.** iTerm2 in vim (Esc leaves insert mode), zsh's vi mode, Zed's vim
   mode; then Control-[ in each (the support page says terminals take it as Esc).
3. **Typing with no Keyboard button**, at once after connecting (the Keyboard button stays dark), after
   turning the iPad, after Settings, Menus, the Apps list and Pair This iPad… close, and after a reconnect
   (Wi-Fi off and on). Shortcuts too (⌘S, ⌘Z, ⌘Tab stays iPadOS's).
4. **⌘W** reaches the Mac (its window closes) and Sill's window stays.
5. **Nothing drawn**: no on-screen keyboard and no shortcuts bar over the stream while typing on the Magic
   Keyboard; folding the keyboard away (or taking the iPad off it) brings no on-screen keyboard up over
   the stream, and the console says `keyboard: the keyboard went …; let go`.
6. **The Keyboard button** with the keyboard attached: pressed, it lights and iPadOS shows its own small
   keyboard bar (or the on-screen keyboard); pressed again, it goes dark and typing still reaches the Mac.
7. **Esc over Sill's own panels**: Settings open, Esc closes it and nothing reaches the Mac; the tour, Esc
   skips it; Pair This iPad…, Esc cancels.
8. **The tour on a fresh install** (TestFlight or a Release build, or Debug with `-SillTourState fresh`)
   with the keyboard attached: it still shows a second after the picture.
9. **Trackpad scrolling over the picture**: two fingers scroll the Mac's window under the pointer, a flick
   coasts once (watch for a double coast: the content running on twice as far, or a second stretch after
   the first ends), and the scroll stops when two fingers touch again. A mouse's wheel (a USB or Bluetooth
   mouse) scrolls in steps, one notch at a time included. Over the portrait trackpad nothing scrolls.
10. **VoiceOver** with the keyboard attached: nothing reads differently (the input view is not an element).
11. **An input method** (Japanese or Chinese on the Magic Keyboard, if used): during the hold the input view
    is empty, so iPadOS's candidate bar may not show; the Keyboard button then gives iPadOS's own keyboard
    views back. Note whether typing in one works either way.
12. **Two Sill windows** side by side (Split View, or Stage Manager), each streaming: open Settings in one,
    then press Esc in the other. Esc reaches the Mac (`hwkey: … to the Mac`), and Settings stays open in
    the first window. Then open Settings in both and press Esc in one: only that window's panel closes (the
    console: `escape: … in its window …; 1 in other windows, left alone`).
13. **Full Keyboard Access and Switch Control** (open question 11). Turn on Settings › Accessibility ›
    Keyboards › Full Keyboard Access with the Magic Keyboard attached and stream a window. Does Tab still
    move through Sill's bar (Apps, the thumbnails, Aa, Keyboard, Desktop, Settings), does Space press
    Settings and then its Disconnect, and does Esc still back out of a focus group, or does each go to the
    Mac? Then Switch Control with a key of the keyboard as its switch: does the switch still move through
    Sill's controls while the stream holds the keyboard? If either is stuck, say so: the alternative is no
    automatic hold while one runs.

## Words that wait for a device

Done on 2026-10-15: steps 1, 7 and 9 passed on the iPad through Universal Control (the Results'
"Noah's test through Universal Control"), and on Noah's word the four lines below went into README,
the support page and the App Store text, as written here.

No device has shown Esc reaching the Mac (step 1), Esc over Sill's own panels (step 7) or scrolling with a
trackpad or a mouse (step 9): in the simulator Esc came through `pressesBegan`, which #67's iPad never
used, and no real trackpad's events reached the continuous pan. So the public words leave them out for now
(the review's second finding): README's How it works, the support page, the App Store description's
keyboard bullet and the next What's New say only that a keyboard types on the Mac as soon as the picture
shows, without the Keyboard button. README.md is public as soon as this merges; the site and the App Store
text go out with the release. Once the steps pass, these lines take their places (the Esc words with steps
1 and 7, the scrolling words with step 9):

- README.md, How it works, "Your input": "A keyboard attached to your device types on your Mac as soon as
  the picture shows, Esc included, and a trackpad or a mouse scrolls the window under its pointer."
- site/support.html, `#keyboard`: the heading "Using a keyboard or trackpad with your iPhone or iPad";
  "…what you type goes to your Mac as soon as its picture shows, Esc and shortcuts included."; "…your keys
  stay with it, so Esc closes the settings or skips the tour."; and a paragraph after it: "Over the
  picture, two fingers on the trackpad scroll the window under the pointer, and so does a mouse’s scroll
  wheel."
- docs/app-store-metadata.md, the description's bullet: "• Type with the on-screen keyboard, or on a
  hardware keyboard as soon as you connect, with shortcuts and Esc. A trackpad or a mouse scrolls the window
  under the pointer." (the description 2,963 characters, local-only 2,742)
- The next What's New: "With a keyboard attached to your iPhone or iPad, what you type goes to your Mac as
  soon as its picture shows, Esc included, without the Keyboard button. Two fingers on a trackpad, or a
  mouse's scroll wheel, now scroll the window under the pointer." (247 characters)

## Results

All on this Mac, 2026-10-14, while other sessions ran their own builds and mutants (load averages up to
418): private simulators "Sill hwkeys" (iPad Pro 13-inch (M5), iOS 27.0), "Sill hwkeys phone" and "Sill
hwkeys phone2" (iPhone 18 Pro, iOS 27.0), deleted after; every host `SillHost --synthetic` on loopback with
`SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_INPUT_LOG=1` and
`SILL_TEST_POINTER_PATH` (a test host's Desktop takes no input without its scripted pointer: its
`currentSourceRect` is nil). Nothing touched Sill.app, a device, the hardware encoder or input on the Mac.

**First, what the simulator does** (H6, `Tests/keyrig`, a virtual HID keyboard and mouse inside the
simulator; its README):
- GameController's coalesced keyboard connects about 50 ms after any app launches (the simulator's own HID
  keyboard service), so every simulator run has `attached`. UIKit can disagree: a fresh iPhone simulator
  still gave a first responder the 301 pt software keyboard. After the rig's keys UIKit counts a hardware
  keyboard on that simulator for good.
- A first-responder `UIKeyInput` view with the default input view, under a hardware keyboard, leaves a
  one-pixel line at the screen's bottom edge (1,958 pixels, delta 15); with the empty input view the photo
  equals no first responder's.
- A rig Esc reaches `pressesBegan` (usage 41; characters "UIKeyInputEscape" alone, "\u{1b}" with a
  modifier); a priority Esc key command on that view fires 3 ms later only when `pressesBegan` hands the
  press to `super`, and never when it keeps it. GameController's handler sees every key beside UIKit. So
  here the press channel brings Esc, and the key command is for a device that keeps it from there.
- A wheel's notch reaches a `.discrete` pan: began at 3 pt (-3 lines), changed per later notch, ended
  0.2 s after the last. Phased scroll events, in lines or pixels, from a virtual mouse or "touch pad" reach
  the discrete pan too, never the continuous one, so the trackpad's recognizer is exercised through its own
  path instead (the input test, the script). Scroll events marked as momentum after a scroll's end never
  reached a pan: no double coast from UIKit, in the simulator.
- iPadOS 27's windowing refuses `requestGeometryUpdate`, and duorig's orientation event does not turn an
  iPad simulator; an iPhone simulator turns on request (`-SillTurnAt`).

**Found by these runs, and fixed:**
- A lone wheel notch was never sent (the pan began and ended with no change, and the begin's translation
  was dropped as a finger's is): the trackpad's and the wheel's begin and end now send their delta
  (`scrolled(to:at:)`); before the fix two notches went out as one 6 pt scroll and one as nothing, after it
  one, two and one notches gave 1, 2 and 1 scrolls at the host.
- The rule asked to take the keyboard for the button or a restore with no view in a window (the random
  sessions, 19,913 times): they now ask only while a view is in a window.

**H1** `Tests/checks/hardware-keyboard`: 51 checks; 20,000 random sessions (690,353 events) against the six
invariants; 31 of 31 mutants caught. In CI's mutants matrix.

**H2** `Tests/checks/key-strokes`: 347 checks (329 before; 18 new: Esc's key command alone, ⇧Esc, ⌘Esc,
both orders of the two channels, a later press, a repeat, a held press, `releaseAll`, `pressed` and
`released` for other keys, and the key command among the random sessions' keys); 81 of 81 mutants (72
before; 9 new).

**H3** `swift build -c release`: complete in 74 s, only the CaptureProbe warning. The iOS app, Debug and
Release for the generic simulator and Debug for a generic device (`CODE_SIGNING_ALLOWED=NO`): each
succeeded with main's warnings only (the StreamClient capture warning and appintentsmetadataprocessor's
note). The Release binary holds none of the DEBUG flags' strings (`SillHardwareKeyboard`, `SillKeyProbe`,
`SillEscViaCommand`, `SillTurnAt`, `hwkey:`, `keyboard:`), links GameController (Apple's), and
release-ios.sh's required-reason check finds SystemBootTime and UserDefaults, both declared, as before.
`Tests/checks/run-all.sh`: all 41 pass.

**H4** Harness photos, this branch against main's build (985a733) on the same simulators, compared pixel
for pixel below the status bar: 19 of 19 identical. iPad: 1000×710 plain, with the drawer, the Settings
panel, `-SillKeyboard 1`, `-SillHardwareKeyboard 0` and the Menus pull-down open (on its top level, and on
File › Open Recent); 710×1000 plain and with Settings; 500×710; the
Duo's book and laptop poses (`-SillHinge half`) and its cover. iPhone: the phone's arrangement upright
(402×780) plain, with Settings, the drawer and `-SillKeyboard 1`; sideways (780×360); the connect screen
(`-SillConnectCase methods`). In each the branch's input view held the keyboard (GameController's keyboard)
and drew nothing.

**H5** Live, the normal app with `-SillConnect` (or the harness with `-SillLive 1`), keys and wheels from
the rig:
- iPad, upright: the hold taken as the session's view joined; `-SillInputTest 1`: the key row's ⌘esc,
  the trackpad's tap and scroll, then Esc and ⇧Esc through the key command's own action (the host: key 53
  down and up, key 53 down with shift), a trackpad scroll with its coast and a wheel (98 scroll events in
  all); then the rig's Esc (key 53), "a" (typed), ⌘W (key 13 with command, Sill's window stayed) and F5
  (key 96), all with no Keyboard button.
- iPhone, `-SillTurnAt 8,14`: Esc and a letter upright, after the turn sideways (the new view took the
  hold) and after the turn back, each reaching the host; no keyboard drawn in either layout.
- A fresh iPhone (UIKit showing the software keyboard, GameController counting one), photos every second
  with `-SillKeyboardToggle 6,12`: nothing drawn under the hold, then the software keyboard and the lit
  button, then both gone; main's build gives the same pictures for the same presses.
- `-SillSettings 1`: the hold let go as the panel opened; the rig's Esc then closed the panel through its
  EscapeKey with nothing at the host; the hold came back and the next Esc and "a" reached the host.
- `-SillTourState fresh`: the tour showed 1.11 s after the picture with the keyboard attached; "a" typed
  during it reached nothing; Esc skipped it ("escape: Esc to what is on screen"), nothing at the host; the
  hold came back and the next Esc and "b" reached the host.
- The Menus pull-down (the harness's mock menus, `-SillMenusOpen 1 -SillMenusCloseAfter 4`): the hold let
  go as it opened, the pull-down stayed open (the photos above), and the hold came back as it was
  dismissed; UIKit gave the keyboard back by itself in no run.
- `-SillEscViaCommand 1`: Esc, ⇧Esc, ⌘Esc and ⌥⌘Esc through UIKit's own key-command dispatch, each key 53
  at the host with its flags and every modifier let go after.
- The harness at 1000×710 with `-SillLive 1` and the script's `keyboard detach` (3 s) and `attach` (12 s):
  the hold let go and came back; the rig's keys between reached nothing and after reached the host; the
  script's `esc`, `esc shift+command`, `scroll 0,40` and `wheel 0,-30` reached the host.

**H7** The touch rig (`Tests/touchrig`, which now compiles the rule and stands in for EscapeKey): 72
scenarios on main's surfaces and on this branch's; `compare.py` 72 of 72 (the overlay's and the
trackpad's one- and two-finger strokes give the same events as before, the gestures as before). It makes
direct touches only, not scroll events: the wheel's pan ran under the key rig instead.

**The review (2026-10-14) and its fixes.** An adversarial review of 2fc53ed re-ran every claim above and
found four things, and two claims that did not hold. Each was checked here against the code first, then
fixed in a commit of its own:

1. **Esc and `EscapeKey` across Sill's windows** (should-fix; bdc121d). `EscapeKey.onScreen` counted the
   EscapeKeys of every window, so Settings, the tour, the pairing overlay or the Add a Mac card open in one
   window took the stream's Esc key commands away in every other; on a device that gives Esc only to the
   key command (#67's), Esc then went nowhere in the window in front. And `fire()` answered with the newest
   EscapeKey in any window, so Esc in one window could close another's panel. Now `onScreen(in:)` and
   `fire(in:)` take the window (§1). On a private iPad Pro 13-inch (M5) simulator, iOS 27.0, against
   loopback `SillHost --synthetic` with keys from the key rig:
   - `-SillSecondWindow 1 -SillSettings 1 -SillEscViaCommand 1` (Settings open in the first window, behind;
     the second in front, holding the keyboard), then Esc and "a": 2fc53ed's build handed Esc on with no
     key-command line, and the host got only the "a" (key 0); this build: `hwkey: usage 41 down via
     keyCommand (none): to the Mac`, and the host got key 53 down and up, then key 0.
   - `-SillSecondWindow 1 -SillTour touch -SillTakeTourAt 5` (a tour in each window, then Settings opening
     in the one behind), Esc in the front window: this build closed the front window's tour (`escape: Esc
     to what is on screen in its window (its EscapeKey), not to the Mac; 1 in other windows, left alone`;
     the photo after it shows the front window with no tour). 2fc53ed's build closed the front window's
     tour too: the Settings panel opened in the window behind never put its EscapeKey on screen while that
     window stayed behind (2fc53ed's Esc closed a tour, not that panel; this build counted one EscapeKey in
     the other window, not two), so the newest EscapeKey anywhere was still the front window's. Showing
     `fire()`'s old mistake needs two windows side by side, or a switch from one to the other, which these
     runs could not make: Noah's step 12.
   - One window, as before the fix: with Settings open, Esc closed it through its EscapeKey with nothing at
     the host, then Esc and "a" reached the host (key 53, key 0); with `-SillTourState fresh` the tour
     showed 1.10 s after the picture with the keyboard attached, an "a" during it reached nothing, Esc
     skipped it, then Esc and "c" reached the host; with `-SillEscViaCommand 1`, Esc, ⇧Esc and ⌥⌘Esc came
     through the key command, each key 53 at the host with its flags and every modifier let go after;
     `-SillInputTest 1`: Esc and ⇧Esc through the key command, a trackpad's scroll with its coast and a
     wheel's (104 scroll events at the host); in the harness the Add a Mac card (`-SillLayout 1000x710
     -SillConnectCase addmac`) closed on Esc.
2. **Public words beyond what a device has shown** (nit; af9f13c). README.md, public as soon as this
   merges, said Esc reaches the Mac and a trackpad or a mouse scrolls, and so did the support page, the App
   Store description's bullet and the next What's New. They now keep to typing without the Keyboard
   button; "Words that wait for a device" (above) has the fuller lines. CLAUDE.md's "a pan gets no momentum
   events" is now a simulator observation.
3. **The support page's Keyboard button** (nit; af9f13c). It said the button "shows the on-screen
   keyboard"; with a keyboard attached it brings up the keyboard bar first: now "It brings up your
   device’s keyboard bar, and from there the on-screen keyboard."
4. **Full Keyboard Access and Switch Control** (nit; 7fdc902). The hold puts Tab, Space and the arrows
   on the Mac and, with a keyboard attached, the Keyboard button never lets go for good
   (`HardwareKeyboardPolicy.toggled()` answers `makeAutomatic` while the hold is wanted, read here):
   open question 11 and step 13.

The claims that did not hold: "Fixes #68" (no real trackpad's events reached the continuous pan, and the
double coast is untested): the pull request now says Towards #68. And "`run-all.sh`: all 41 pass" held for
the review only on a second run: `protocol`'s "generate: digits uniform", a p = 0.001 test of
StreamProtocol's pairing-code generator, which this branch does not touch, failed once (chi² 27.9 against
a bound of 27.9) and passed alone. Here, on 7fdc902, it passed all 41 at the first run (347 s; `protocol`
ALL PASS, hardware-keyboard 51 checks, key-strokes 347).

Verified again on 7fdc902 (the code as it stands; what follows it is docs only): the iOS app (Xcode 27.1,
27A9275), Debug and Release for the generic simulator and Debug for a generic device with
`CODE_SIGNING_ALLOWED=NO`, from new derived data: each succeeded (22, 38 and 18 s) with only the
StreamClient.swift:3430 capture warning and appintentsmetadataprocessor's note; the Release binary holds
none of the DEBUG strings (the new `escape:` lines included) and links GameController. `swift build -c
release` from `git archive` of 7fdc902: complete in 43.4 s, only the CaptureProbe warning. No pure check
compiles a file this round changed (AddMacCard.swift, InputOverlay.swift, ContentView.swift), so the
mutants were not run again: hardware-keyboard's 31 of 31 and key-strokes' 81 of 81 stand (the review's
runs). The touch rig, whose stub follows `onScreen(in:)`: 72 scenarios on main's surfaces and on this
branch's, `compare.py` 72 checks, 0 failed. No screen changed, so no harness photos were taken again. The
private simulators ("Sill hwkeys review-fixes iPad", "Sill review-fixes touchrig") and every host are
gone.

**Not verified here:** anything on a device (§ Untested); the continuous recognizer with a real trackpad's
events (the simulator gives a virtual mouse's scrolls to the discrete one), and so the double coast on a
device; what iPadOS draws for the person's own keyboard with a Magic Keyboard; Control-[ in the terminals;
`fire()`'s old cross-window mistake shown live (two windows side by side); Full Keyboard Access and Switch
Control.

### Noah's test through Universal Control (2026-10-15)

On the iPad mini with the merged build (b1bb177, Debug, its console attached through devicectl),
against a loopback synthetic host on the software encoder reached over the USB cable through a
relay (the host's input log on, a scripted pointer so its Desktop has somewhere for input to land),
with the Mac's own keyboard and trackpad reaching the iPad through Universal Control. Synthetic
input on the Mac never crosses Universal Control's edge (four edges tried, its log silent), so the
hands were Noah's; the logs are the evidence.

- GameController counted Universal Control's keyboard as attached, and the input view took the
  keyboard by itself (`keyboard: took the keyboard: none → automatic`); no Keyboard button.
- Typed letters reached the host as text (`hwkey: … via pressesBegan: the text system's`, the host's
  text events), before any button was touched.
- Esc reached the host (`hwkey: usage 41 down via pressesBegan (none): to the Mac`; the host's key
  53 down and up). The key-command channel was not needed on this keyboard.
- ⌘W reached the host (key 55's flags, key 13 down and up with command, the flags cleared, the
  tripwire armed) and Sill's window stayed.
- Two-finger scrolling over the picture gave the host 38 scroll events with phases
  (`in.scrollPhase`), the continuous pan's.
- Settings open: the hold let go (`automatic → none`), Esc closed the panel and nothing reached the
  host (`escape: Esc to what is on screen in its window (its EscapeKey), not to the Mac`), then the
  hold came back and a typed letter reached the host again.
- The Keyboard button: `automatic → own` and a letter reached the host; again, `own → automatic`
  and another did.

So steps 1, 3, 4, 6, 7 and 9 of "Untested, for Noah" pass on Universal Control's keyboard and
trackpad. Not a physical Magic Keyboard: which channel brings Esc there, the on-screen keyboard
staying away when it is folded, an input method's candidates, VoiceOver, Full Keyboard Access and
two windows (steps 2, 5, 8, 10 to 13) are still Noah's.

## Progress

- 2026-10-14: the plan (c641950); the rule, Esc's key command, the scroll pans and their checks, with the
  lone notch's and the no-view fixes the simulator runs found (f0ca916); the key rig and EscapeKey's
  DEBUG line (08635bf); the docs (73fcf77, 2f266ff); PR #80.
- 2026-10-14: CI's Build and check passed on 807c8ef (run 38489635350: `swift build -c release`, the 41
  pure checks with hardware-keyboard's 51 and key-strokes' 347, the iOS app on `Xcode_27.1_beta.app` with
  only the StreamClient capture warning). The private simulators are deleted. The pull request merges
  into main (985a733) without a conflict. With the other open pull requests it meets in the docs
  (CLAUDE.md's Current step, ci.yml's mutants matrix, Tests/checks/README.md, docs/DEVELOPMENT.md,
  docs/app-store-metadata.md) and, with #79, in StreamScreen.swift's DEBUG hooks (`-SillTurnAt` beside
  its `-SillAXDump` and `-SillLargerPictureToggle`: keep both), so whichever merges second takes main in.
- 2026-10-14: the review's findings fixed: Esc's key commands and EscapeKey keep to their own window
  (bdc121d); the public words keep to what a device has shown, and the support page's Keyboard button
  sentence (af9f13c); Full Keyboard Access and Switch Control, open question 11 and step 13 (7fdc902).
  Verified as Results' "The review and its fixes" says; the pull request says Towards #68.
