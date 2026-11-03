# devicerig — TEST ONLY

Drives the Sill already installed on a physical iPad or iPhone from the command line, by its bundle
identifier, through a script of steps: taps, holds of a given length, a finger's drags and flicks, a
pinch, the iPad's pointer, typed text and keys, screenshots and the accessibility tree. It is for the
tests nobody can make by hand headless: a drag over the picture (the scroll's direction), a hold on a
thumbnail (the window's lights), a pinch, typing, and photographs of what followed. `Tests/keyrig` and
`Tests/touchrig` do the like in a simulator; this one is for glass.

It is an Xcode project with one UI testing bundle and no host app (`DeviceRig.xcodeproj`):
`XCUIApplication(bundleIdentifier: "me.saffer.sill")` drives whatever Sill the device has, so the rig
never builds, installs or removes Sill. xcodebuild installs only the runner,
`me.saffer.sill.devicerig.xctrunner`, signed by automatic signing on team 9B2KKVM937 with the Apple
Development identity and the team's wildcard profile, and leaves it on the device (`xcrun devicectl
device uninstall app --device UDID me.saffer.sill.devicerig.xctrunner` removes it). Public XCTest API
only; it is never part of Sill.

```
Tests/devicerig/run.sh build                                   # the runner, for devices and for the simulator
Tests/devicerig/run.sh UDID '<script>' [Sill's launch arguments…]
Tests/devicerig/run.sh 00008110-0016793226E0401E 'launch; wait 4; shot first; drag 560,300 560,500 0.1; wait 2; hold 156,79 1.5; shot lights; terminate' \
    -SillConnect 169.254.71.35:60606
```

UDID is a paired device's (`xcrun devicectl list devices`), or a booted simulator of your own, made for
the test and deleted after, to try a script first (never a shared one). Each run leaves
`.build/devicerig/NAME/` (NAME is `RIG_NAME`, or the time): `run.log` (xcodebuild's output), `rig.log`
(the rig's own lines, which run.sh also prints), `NAME.xcresult`, and `shots/` with every `shot` as
`NAME.png` and every `tree` as `tree-N.txt`. They come out of the result bundle with

```
xcrun xcresulttool export attachments --path NAME.xcresult --output-path attachments
```

which writes each attachment beside `manifest.json`; run.sh names each copy from the manifest's
`suggestedHumanReadableName` ("NAME_0_‹UUID›.png"). Environment: `RIG_APP` (another bundle identifier),
`RIG_NAME`, `RIG_TREE_LINES` (how much of the tree `tree` prints, 300), `RIG_TIMEOUT` (600 s),
`RIG_DERIVED` (the runner's DerivedData, `.build/devicerig/DerivedData`). run.sh hands the script, the
launch arguments and these to the runner as xcodebuild's `TEST_RUNNER_RIG_SCRIPT`,
`TEST_RUNNER_RIG_LAUNCH_ARGS`, `TEST_RUNNER_RIG_APP` and `TEST_RUNNER_RIG_TREE_LINES`, which reach it
without their prefix.

## The steps

Steps are separated by `;` or newlines; a line that starts with `#` is a comment, and a backslash keeps
the next character (`type a\;b`). Coordinates are points in the app's first window from its top-left
corner (`XCUICoordinate` at the window's normalized offset 0, plus the points). On an iPad mini held
sideways the window is 1133×744, the stream's panel 8,126 1117×610 under the bar (a 1512×948 picture
fills x 80–1053 of it; a tap on the black bars clicks nothing), and the first thumbnail 100,42 113×74:
`tree` and `find` give any element's frame.

| step | what it does |
|---|---|
| `launch` | starts the app afresh with the launch arguments (a running copy is ended first) and prints its window |
| `activate` | brings a running app forward without starting it again (one launched with its console, below) |
| `terminate` | ends the app |
| `wait S` | S seconds |
| `tap X,Y` | a finger's tap |
| `hold X,Y S` | a finger pressed S seconds, then lifted |
| `drag X1,Y1 X2,Y2 S [V [H]]` | a finger pressed S seconds, moved to the second point at V (XCUITest's `XCUIGestureVelocity`, pixels per second by its header; its default when left out) and held there H seconds (none when left out) before it lifts. On the picture keep S under Sill's 0.45 s long press, or it is a right click |
| `swipe X1,Y1 X2,Y2 [V]` | the same motion with no press before it and no hold after it, at V (2000 when left out): a flick, which Sill coasts |
| `pinch SCALE V` | two fingers at the middle of the window, in (under 1) or out (over 1), V the speed in scale per second (its sign follows the scale) |
| `type TEXT` | `typeText`: the characters reach the app's text input (Sill's `insertText`, which sends them as text), with no key presses. `\n` Return, `\t` Tab, `\s` a space, `\\` a backslash. Something in the app must have the keyboard's focus |
| `key NAME [MODS]` | `typeKey`: one key pressed as a hardware keyboard presses it (Sill's `pressesBegan`; a plain character then goes on to the text system): a character, or escape, return, enter, tab, space, delete, forwarddelete, up, down, left, right, home, end, pageup, pagedown, f1–f12, command, shift, option, control, capslock; MODS cmd, shift, opt, ctrl, fn, caps joined by `+` |
| `hover X,Y`, `click X,Y`, `rightclick X,Y` | the iPad's pointer, a trackpad's or a mouse's, not a finger |
| `wheel X,Y DX,DY` | a scroll with that pointer over the point (`scrollByDeltaX:deltaY:`) |
| `orient portrait\|upsidedown\|landscapeleft\|landscaperight` | turns the device (`XCUIDevice`) and waits a second for the turn; turn it back before the script ends (a simulator stays turned) |
| `shot NAME` | a screenshot of the whole screen, attached to the result (kept) and copied to `shots/NAME.png` |
| `find TEXT` | whether an element has that label or identifier: how many, and the first one's type and frame; else how many labels contain it |
| `waitfor TEXT S` | waits up to S seconds for such an element |
| `tree` | the app's accessibility tree (`debugDescription`): its first `RIG_TREE_LINES` lines, and the whole of it attached as `tree-N.txt` |

A step XCTest cannot do (no keyboard focus, no such element, a frame of no window) is recorded as an
issue, printed as `rig: issue: …`, and the script goes on, so the photographs after it still show what
happened. xcodebuild then exits 65.

## The device: Touch ID for UI Automation

A device does not let XCTest drive it until its owner says so: the runner installs and launches, and
iPadOS shows "Enable UI Automation — Touch ID to continue with XCTest." until the owner touches the
sensor (Face ID on an iPhone) or cancels. The rig cannot answer it, and must not: it guards a device against being driven by
a computer. Unanswered, xcodebuild fails after 60 s with "The test runner failed to initialize for UI
testing. (Underlying Error: Timed out while enabling automation mode.)". Once the owner has allowed it
(the prompt, or Settings › Developer › Enable UI Automation), the same command runs; whether the device
asks again later, after a restart say, was not seen here. The device must also be
unlocked, paired, in Developer Mode, and reachable by xcodebuild (`xcrun devicectl list devices`
says "available (paired)").

## A test host through the USB cable

A device can stream from a synthetic host on this Mac, which posts nothing (its input is a dry run)
and never touches the hardware encoder. The host listens on loopback alone, so `lanrelay.py` (TEST
ONLY) relays the cable's address to it:

```
echo "0 756 474" > $T/pointer.path       # a scripted pointer: the Desktop then takes the device's input
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_INPUT_LOG=1 \
    SILL_TEST_POINTER_PATH=$T/pointer.path .build/release/SillHost --synthetic > $T/host.log &
/usr/sbin/lsof -nP -a -p $! -iTCP -sTCP:LISTEN      # its port, on 127.0.0.1
ifconfig en14                                        # the cable's interface: the one with an inet 169.254.x.y
python3 Tests/devicerig/lanrelay.py --listen 169.254.71.35:0 --to 127.0.0.1:PORT > $T/relay.log &
Tests/devicerig/run.sh UDID 'launch; wait 4; …; terminate' -SillConnect 169.254.71.35:RELAYPORT
```

The relay binds only the address it is given, takes connections only from link-local addresses (or
those `--allow` names), relays only to loopback, and refuses a TLS session (SillHost `--pairing`),
which it could not read. It prints what the device sends: its hello, viewports, the Desktop picks,
taps, keys and text, and one line for each scroll's finger part and each coast, with the number of
events and the sums of dx and dy as fractions of the picture (dy > 0 moves the content down);
`--each` prints every delta. The host's `SILL_TEST_INPUT_LOG` lines say what it would post, a
`Test input: scroll (none)` for each delta and one for each end of a finger part or a coast, but no
delta, so a scroll's sign is read from the relay.

The guard: a synthetic host lists this Mac's real windows and apps, so a tap on a thumbnail (kind 6, a
window's pick) would capture a real window, a press of the lights (kind 15) would close, minimize or
full-screen it, and a launch from the Apps drawer (kind 7) would open an app. The relay drops those
three with a line each. For the same reason a tree or a screenshot shows this Mac's window titles and
thumbnails: keep them out of pull requests and reports.

End a script with `terminate`, and stop the relay and the host after the run: Sill left running looks
for its Mac again once the test host has gone, and a Sill.app on this Mac is a Mac it may find.

## The console

XCUITest's log has none of Sill's own lines (its stdout goes nowhere when XCUITest launches it). For
the console, start Sill with devicectl in another shell and drive the copy that runs, with a script
that starts with `activate` instead of `launch`:

```
xcrun devicectl device process launch --console --terminate-existing --device UDID me.saffer.sill \
    -- -SillConnect 169.254.71.35:RELAYPORT > $T/console.log &
Tests/devicerig/run.sh UDID 'activate; wait 1; …; terminate'
```

A Ctrl-C to devicectl reaches the app and ends it ("App terminated due to signal 2"). A Debug build of Sill prints the
console's lines (`session:`, `hwkey:`, `viewport:`, …) and takes the harness's launch arguments
(`-SillConnect`, ContentView's contract); a Release or TestFlight build is driven the same way but
takes none of them and prints nothing, so it reaches only the Macs it lists.

## What it showed (2026-10-20, Xcode 27.1)

On a private iPad mini (A17 Pro) simulator (iOS 27.0) with a Debug build of main, against a synthetic
host through the relay:

- `drag 560,300 560,500 0.1` was one scroll: 21 finger deltas summing dy +0.29 of the picture (the
  content down, the natural sign; the first 20 pt or so go to the pan's start), then a coast of 72
  (dy +0.22). The host printed 95 `Test input: scroll` lines, the 93 deltas and the 2 ends.
  `swipe 560,500 560,300` went the other way: 3 finger deltas (dy −0.18) and a coast of 117 (dy −1.46).
- `hold 156,79 1.5`, exactly Sill's hold (`holdToOpen`), showed the lights over the first thumbnail.
  All three lights read "‹App› window actions" in the accessibility tree (the menu's label covers
  their own "Close window", "Minimize window" and "Full Screen window"); their texts read Close,
  Minimize and Full Screen, so `find Minimize` finds them.
- `tap` was a move, a left down and a left up; `click` the same through the pointer; `pinch 0.5 1` on
  the picture a two-finger scroll; `wheel 600,400 0,-60` a trackpad scroll with a coast; `hover` and
  `wheel` took about 5 s each.
- `type hello\n` arrived as six `text` events and no key presses (no `hwkey:` line on the console);
  `key a` went through `pressesBegan` to the text system ("hwkey: usage 4 … the text system's") and
  arrived as text, `key a cmd` and `key up` as key events (⌘ with it); `key escape` reached nothing at
  all, not even `pressesBegan` (`key escape cmd` only the ⌘), so Esc is not tested this way.

On the iPad mini (6th generation, iPadOS 27.0.1): the runner built, installed and started, and the
run stopped at the Touch ID prompt above, twice. Sill launched with devicectl's `--console` reached
the synthetic host through the relay on the cable (169.254.x.y on both ends) and streamed at 53–58 fps
with a round trip of 1 ms; the console showed "session: Wired, read from path en2 (wiredEthernet)".

## Limits

- No Apple Pencil (XCUITest has no stylus), no input method or dictation, no fingers beyond the two of
  a pinch (no three-finger gestures), and the pinch only at the middle of the window.
- XCUITest waits for the app to settle before most steps, and the timings it reaches are its own: a
  hold is a hold of at least S seconds as XCUITest drives it, not a measured touch.
- One device at a time; the window's coordinates are the first window's (in Split View or Stage
  Manager, Sill's own window).
- Sill's console only through devicectl (above); the result bundle has the runner's lines alone.
- The scheme keeps no screen recording (`preferredScreenCaptureFormat` "screenshots",
  `systemAttachmentLifetime` "keepNever"): only the `shot` steps' screenshots are kept, and xcodebuild
  collects no diagnostics (`-collect-test-diagnostics never`).
