# keyrig — TEST ONLY

A hardware keyboard and a mouse for the iOS Simulator, driven from the command line: key presses,
pointer moves and wheel scrolls posted from a virtual HID service inside the simulator, so UIKit routes
them as it routes a real keyboard's and mouse's (`pressesBegan`, key commands, the text system,
GameController, hover and scroll events) with no hand on the Simulator app. It was written to check
docs/hardware-keyboard-plan.md (#67, #68) without a device.

**Private interfaces, simulator only**, as `Tests/duorig`: HID.framework's `HIDVirtualEventService` and
IOKit's `IOHIDEvent` calls through `dlopen`/`dlsym`, posting into the HID event system of the simulator it
runs in. It is never part of Sill, never built for a device, and refuses to run outside a simulator.
Nothing reaches the Mac's own HID system: it runs inside the simulator through `xcrun simctl spawn`.

```
Tests/keyrig/run.sh build                                      # .build/keyrig/keyrig (clang for the simulator)
Tests/keyrig/run.sh UDID keys 29,04,e3:down,1a,e3:up            # Esc, a, then ⌘W (HID usages in hex)
Tests/keyrig/run.sh UDID point 'move 300,200|wheel -3|wait 0.2|wheel -3'   # the pointer over a view, two notches
```

`keys` takes `USAGE[:down|:up]` steps (a bare usage is a press: down, 60 ms, up), 250 ms apart. `point`
takes `move DX,DY`, `wheel DY` (lines), `phase began|changed|ended DX,DY`, `momentum BITS DY` (the
momentum bits in hex: 2 start, 1 continue, 4 end) and `wait S`, separated by `;` or `|`. Each run makes
its own virtual device, waits `SETTLE` seconds (0.6) for the event system to take it, posts, and keeps it
`HOLD` seconds (0.3) after.

Use only a simulator of your own, made for the test and deleted after: the keys go to whatever app is in
front, and once a simulator has had keys from a keyboard, UIKit there counts a hardware keyboard as
attached, so its software keyboard stops coming up (as on a device after a keyboard is used).

## What it showed (iOS 27.0 simulators, Xcode 27.1, 2026-10-14)

- Every booted simulator lists a HID keyboard service of its own (page 1, usage 6), and GameController's
  coalesced keyboard connects about 50 ms after an app launches, so `GCKeyboard.coalesced` is set in
  every simulator run. UIKit can disagree: on a fresh iPhone 18 Pro simulator a first responder still got
  the 301 pt software keyboard. Sill's hold for a hardware keyboard draws an empty input view, so it shows
  no keyboard either way.
- A keyrig Esc reaches `pressesBegan` of a `UIKeyInput` first responder (usage 41; its characters are
  "UIKeyInputEscape" alone and "\u{1b}" with a modifier). An Esc key command on that view, with
  `wantsPriorityOverSystemBehavior`, fires only when `pressesBegan` hands the press on to `super`; kept,
  the command never fires. GameController's `keyChangedHandler` sees every key beside UIKit's presses.
  The reported iPad (#67) never sent Esc at all, so a device can differ: Sill takes both channels and
  sends one key press once.
- With the stream's input view holding the keyboard, ⌘W reaches `pressesBegan` (the iPad's File › Close
  does not take it), and so does F5.
- A wheel event over a view reaches a pan with `allowedScrollTypesMask` `.discrete`: it begins with the
  first notch already in its translation (3 pt for -3 lines), changes once per later notch and ends about
  0.2 s after the last, so a single notch has no change at all. Scroll events with phases, in lines or
  pixels, also reach the discrete pan, never a `.continuous` one: the simulator's own trackpad path is not
  reproduced here. Events marked as momentum after a scroll's end never reach a pan.
- Its pointer moves reach a `UIHoverGestureRecognizer`.
- Turning: duorig's orientation event does not turn an iPad simulator, and iPadOS 27's windowing refuses
  `requestGeometryUpdate` ("The current windowing mode does not allow for programmatic changes to
  interface orientation"); an iPhone simulator's scene turns on request (Sill's DEBUG `-SillTurnAt`).
