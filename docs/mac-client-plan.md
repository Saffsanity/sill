# Sill Viewer: a Mac controlling another Mac

Goal (2026-10-11): a Mac app that connects to another Mac's Sill (Sill.app or `SillHost`), shows its
low-latency HEVC stream and sends mouse, keyboard and trackpad input back, with Apple frameworks
only, no servers, the host and its protocol unchanged, and the iOS app's session code reused rather
than copied.

## What it is

- **The host gains one thing: the middle button.** `PointerAction.middleDown` and `.middleUp`, and
  `WindowList.middleButton` true from a host that takes them. A device sends them only to such a
  host, since a host from before cannot decode a kind 8 carrying them. Otherwise Sill.app and
  `SillHost` serve Sill Viewer as one more client. It says hello as `"<Mac name> (Mac14,6)"` with
  version 0.5.1, pairs like an iPhone does (the trust list, Settings › Devices, Remove), and is
  judged by the same device floor. Nothing on the wire is new.
- **The session is the iOS app's, compiled for macOS.** `Sources/MacClient/Shared/` holds symlinks
  to `iOSClient`'s `StreamClient` (and `+Home`, `+Remote`, `+Viewport`), `DiscoveryPolicy`,
  `SessionLink`, `MessageReader`, `RemoteConnector`, `RemoteDialPolicy`, `SavedMacs`,
  `DeviceIdentity`, `GoodbyePolicy`, `HostSettingsLedger`, `KeyChords`, `PointerPresence`,
  `MacMenuState`, `TrackpadGestures`, `TourPolicy`, `PhonePortraitLayout`, `DuoPosture`,
  `AwayCopy`, `SillLinks`, `DiagnosticsHUD` (`ClientStatsReporter`), and two new shared files:
  - `ClientPlatform.swift`: the platform calls the session code makes (the device's name and word,
    its model, the foreground notification, the refusal's haptic and announcement, the screen's
    maximum rate), with `PlatformImage` (UIImage or NSImage).
  - `HEVCSampleFeed.swift`: the decoding half of the old `HEVCDisplayView` (parameter sets to a
    format description, frames to sample buffers shown at once, waiting for a keyframe, the
    letterbox rect, the arrow). The iOS view and the Mac view each wrap it.

  This is the same pattern as `VirtualDisplayProbe`'s symlink. One source of truth; the iOS
  project and the pure checks keep their paths. The iOS-only DEBUG harness hooks in
  `StreamClient` (`InputScript`, `SettingsScript`, the mock menus) are behind
  `#if canImport(UIKit)`.
- **Everything else is the Mac's own** (`Sources/MacClient/`):
  - `SillClientApp`: one window, the Control menu, `sill://` links.
  - `ConnectView`: the rows with their words; Add a Mac by address and code or a pasted link; the
    home card for a Mac's code; Forget and Connect Remotely.
  - `SessionView`: the toolbar's Windows picker (Desktop, thumbnails with close, minimize and full
    screen, and Apps to open), Desktop, Menus, Text Size (the viewport's scale), Settings (the
    host's quality, resolution, frame rate, encoding speed, virtual display and Direct Wireless)
    and Disconnect.
  - `StreamInputView`: the input.
  - `HEVCDisplayView`: an NSView over the shared feed.
  - `MacMenus`: the other Mac's app menus as a pull-down, each read as it opens.
  - `SystemKeyTap` and `MacKeyMap`.

## Input

| This Mac | On the wire | Notes |
|---|---|---|
| Move over the picture | `pointer(.move)` at a fraction of the frame | Coalesced to 125 Hz by `StreamClient`. While the pointer is over the picture, this Mac's cursor takes the other Mac's shape (kind 14), so it moves at local speed. The sprite shows only when the other Mac's own pointer moves. |
| Left and right buttons, drags | `leftDown/Up`, `rightDown/Up`, moves while held | A drag past the edge is clamped to the frame. The host counts double and triple clicks itself. |
| Middle button | `middleDown/Up`, moves while held (`otherMouseDragged` on the host) | Only to a host whose window list says `middleButton` (2026-10-12 and later); against an older host nothing is sent. Other buttons (back, forward) have no place on the wire. |
| Trackpad scroll | `scrollGesture(.began)`, deltas, `.ended`, then `.momentumBegan`, deltas, `.momentumEnded` | macOS's own phases and momentum. Deltas are a fraction of the picture as shown, in AppKit's sign, which is the wire's. |
| Mouse wheel | bare deltas | One line is about 12 pt. |
| Keys | `key(hidUsage:down:modifiers:)` | Taken by a local monitor before the menus, so ⌘W and ⌘Q go to the other Mac. Modifier keys come from flagsChanged. Caps Lock is sent as a press. ⌃⌥⌘⎋ hands the keyboard back to this app. |
| ⌘Tab, ⌘Space, ⌃→ and other system shortcuts | the same | Only with Control › Capture System Shortcuts: a session event tap that needs Accessibility, installed only while the stream has the keyboard. |
| Three-finger gestures | kind 28 by name | macOS keeps three-finger swipes for itself, so the Control menu sends Mission Control, App Exposé, the Spaces, Show Desktop and Show Apps by name. A swipe macOS does hand the app is sent too. |

When the window loses the keyboard, or the session ends, every key and button this view holds
goes up: keys first, then modifiers.

The keycode table is the exact inverse of the host's `KeyStrokes.virtualKeys`. `Tests/checks/mac-keys`
holds the two to that (695 checks, 7 mutants), so they cannot drift apart. The host's table stays
where its own mutants expect it.

## Keychain

`DeviceIdentity`, unchanged, stores the device key in the login keychain on macOS (tag
`me.saffer.sill.device-key`; no data-protection entitlement), with the access of the app's
signature. `Scripts/make-client-app.sh` signs with the Apple Development identity, so rebuilds keep
access without a prompt. Saved Macs are in UserDefaults (`me.saffer.sill.client`, `Sill.savedMacs`),
as on iOS. The other Mac's key is pinned through the saved record, as on iOS.

## Build and run

```
Scripts/make-client-app.sh [--debug] [--open]   # .build/Sill Viewer.app, bundle ID me.saffer.sill.client
swift run SillClient                            # the bare binary (no bundle: no version in its hello)
```

DEBUG launch arguments, from the shared client: `-SillConnect host:port`, `-SillHomeDoor paired`,
`-SillHomeCode <digits>`, `-SillPairURL <link>`, `-SillDialSaved 1`, `-SillRemoteRoute vpn`.
The Mac client's own:

- `-SillInputTest 1`: synthetic NSEvents through the view's own handlers, to a loopback test host
  only.
- `-SillMenuTest 1|press`: the pull-down's first menu opened, and with `press` its first item
  pressed.

## Verified (2026-10-12, this Mac, synthetic hosts on 127.0.0.1, software encoder, nothing posted)

- `swift build -c release` (only the CaptureProbe warning). `Tests/checks/run-all.sh`, all 41.
- iOS with Xcode 27.0 (this Mac has no 27.1): the same errors as `main`, all in the 27.1-only
  `DuoPostureReader`, so the shared edits add none. CI builds with 27.1.
- Plain home door: the hello `Sill 0.5.1 (585)`; the Desktop picked by itself; 53–60 fps decoded,
  frame age 0–1 ms. The window was captured showing the letterboxed test pattern and the toolbar.
- Input (`-SillInputTest 1` with `SILL_TEST_INPUT_LOG=1`), each the right host event:
  - move, click, double click, right click
  - a drag clamped at the edge
  - trackpad scroll with momentum, and a wheel line
  - ⌘C (key 55 flags, key 8 down and up)
  - shift-a let go by `letGo`
  - Mission Control (`shortcut 108`)
- TLS home door with pairing required: ask, the home code, "Paired … with the code", a TLS
  session. After a relaunch, a pinned dial with no ask. The device key is in the login keychain.
- Remote door (`--remote`, the VPN origin): pairing from the link ("with the QR code"), "Remote
  client connected … through your VPN", the away quality, and the saved Mac dialed again after a
  relaunch.
- Menus against `Scripts/menufixture.swift` (`SILL_TEST_MENU_PID`): the top level, a menu read,
  and "About menufixture" pressed in the fixture.

## Two Macs (2026-10-12)

Sill Viewer was built (ad hoc, Debug) on the laptop (a MacBook Pro, a 120 Hz screen, on Wi-Fi). A
`SillHost --synthetic --pairing` ran on this Mac with the hardware encoder, listening on the LAN.
The laptop's first LAN connection waited on macOS's Local Network prompt on its screen, with nobody
there to answer it, so the session ran through an SSH reverse tunnel (the client dialled its own
loopback; SSH carried it across the LAN; the session's TLS inside):

- pairing at the TLS home door with the code ("Paired the laptop (a MacBook Pro) … with the code");
- the hello "Sill 0.5.1, protocol 1";
- the stream at 3024×1898, asked for at 120 fps by the laptop, decoded at 70–120 fps, with a round
  trip of 5–6 ms median;
- every input of `-SillInputTest 1` as the right host event: the middle button's included, the
  keys let go;
- after a relaunch, a pinned dial with no new pairing.

Then directly over the LAN, once the laptop's Local Network prompt was allowed: paired from
the laptop's LAN address with the code, 72–111 fps, rtt 6 ms median, `-SillInputTest 1` complete. Then real
hands on the laptop: clicks, right clicks, middle clicks and middle drags (a mouse), drags, hover,
two-finger scrolling (211 scroll events), typing ("abcdefg") and ⌘W, which went to the host (key 13
with command) rather than closing the viewer. Hover was missing in the first round: the view's
tracking area was made only when AppKit asked (`updateTrackingAreas`), which it did not at first
display; the view now makes it as it joins its window. A rebuild with a new ad hoc signature asked
again on the laptop (Local Network or the key's access): a signed build keeps both.

A third and fourth round, with real hands on the laptop:

- The toolbar: Windows (a pick, and Desktop again), Settings (Quality to Extreme, Prioritize Encoding
  Speed, Direct Wireless off and on, each "Settings from the laptop"), the Control menu's
  gestures, and Menus (the fixture's menus read, `menu.read`).
- Clicks in a picked window, reported as "→ the streamed window".
- ⌘W to the host. ⌃⌥⌘⎋ gave the keyboard back, its Escape never sent.
- ⌘Tab with Capture System Shortcuts: four presses reached the host as ⌘Tab through the tap.
  The first try failed: the tap was installed only when the stream took the keyboard, not once
  Accessibility was granted or the app came back. Now the switch, the app becoming active and a
  click on the picture each look again.
- A test host's window picks are real: picking a browser and a Wine window on this Mac resized them
  to the viewer's panel. Use the Desktop (the test pattern) with a synthetic host, or a Mac whose
  windows may move.

The new client against `main`'s host (no `middleButton`) sent no middle button and caused no decode
error, and everything else went as before.

## Untested

- The Bonjour row on one subnet, Direct Wireless over AWDL (Search Nearby found the test host, but
  the connection went over Wi-Fi's link-local address, en0), Tailscale and the cable.
- The cursor taking the other Mac's shape, and its hotspot: a test host never moves its own pointer,
  so the shape it sends stays the arrow. It needs a real host (Sill.app with its permissions).
- A menu item chosen from Menus (the fixture had quit), a swipe event, and VoiceOver.
- Pairing at home from a real Sill.app: its window opens for this Mac's ask, but only from another
  Mac, since an ask from this Mac itself is refused.

## Left out on purpose

- A "Share a window…" system picker on the host: it only helps someone sitting at the host.
- The other Mac's menus in this Mac's own menu bar: SwiftUI rebuilds the main menu, so they live in
  the toolbar's Menus button.
- The iOS tour and the Duo layouts.
