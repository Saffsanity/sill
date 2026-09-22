# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

## Current step

Milestone 3, scaling and the virtual display. Two paths exist; adopt the second.

- **Fallback (shipped):** the Aa button in the landscape bar cycles Off → 1.0× →
  1.25× → 1.5× → 0.8×. The client sends its stream-panel size and wanted scale
  (`Viewport`); the host resizes the real Mac window through Accessibility
  (`WindowSizer`) to panel ÷ scale points, so text renders at that scale on the
  device. Off leaves the Mac window alone and never restores.
- **Virtual display (probed, not adopted):** `VirtualDisplayProbe` proved on
  macOS 27.0 that the private `CGVirtualDisplay` API creates a HiDPI display,
  ScreenCaptureKit lists and captures it, a window moved there by Accessibility
  keeps repainting (59 fps while off the real screen), and destroy is clean.
  `Sources/SillHost/VirtualDisplay.swift` is the wrapper, unused so far. To adopt:
  SillHost must run an `NSApplication` event loop (not `dispatchMain`) or the
  creating process never sees the display's modes; create one display per
  device at the device's point size at 2×; move the picked window onto it; capture
  the display with `SCContentFilter(display:including:)`; move the window back on
  deselect. This removes the occlusion freeze and unblocks two-window mode.
  Private API: the Mac companion is Developer ID distribution, never Mac App
  Store (Accessibility input already rules that out).

Still open: the unexplained one-off stall where new clients received no catalog
(2026-09-22, hardened since, never reproduced). Keep the connect-path logging.

## Milestone 2 (input and window control) — done 2026-09-22

- Client → host input: tap/click, finger pan → scroll with trackpad gesture
  phases and client-generated momentum (host sets CGEvent scroll/momentum
  phases so apps rubber-band and fling), long-press right-click, Pencil as the
  mouse with hover, software keyboard as Unicode text, hardware keys and
  ⌘/⌃/⌥ chords as HID usages. Portrait laptop layout: stream on top, key row
  (esc, tab, latching modifiers, arrows, keyboard; Spotlight = ⌘Space only while
  the Desktop is the source, since Spotlight's panel is its own window) and a
  relative trackpad. Picked app is brought forward; window follows moves;
  resize restarts the pipeline.
- Latency, measured 2026-09-22 on 5 GHz Wi-Fi to the iPad mini via the client
  stats the host logs: frame age (host encode → device receive) 8–10 ms,
  ping RTT 6–9 ms with rare spikes. Adding capture (≤1 refresh), encode and
  decode+display (1–2 refreshes) puts glass-to-glass at roughly 40–60 ms,
  within the v1 bar. Not photographed with the stopwatch method yet.
- Host footprint (release build, `ps`): idle with no client 0.0 % CPU, 36 MB,
  one heartbeat line per 30 s and no ScreenCaptureKit calls; connected with
  nothing selected 0.0–0.1 %; streaming a Retina window ~3 %. Capture stops when
  the last client leaves.
- Diagnostics: `-SillHUD 1` (DEBUG) overlays fps · frame age · rtt · frame size
  on the device; the client reports the same to the host every second and the
  host prints `client <device>: …`.
- Learned: `_AXUIElementGetWindow` is private, so AX windows are matched by
  title then frame; apps enforce minimum sizes, the host streams what it got.

## Milestone 1 (latency spike) — done 2026-09-22

- Mac host builds and runs from `swift build -c release`: window listing,
  ScreenCaptureKit capture, VideoToolbox HEVC encode, Bonjour advertisement,
  TCP fan-out to clients.
- iOS client is a real Xcode project (`iOSClient/Sill.xcodeproj`), builds
  clean, runs on Noah's iPad Mini (the test device: iPad scalability plus a
  Duo-like aspect ratio).
- End to end verified on Wi-Fi: ~58 fps captured, encoded and sent with zero
  drops at 3024×1898 (Retina capture of a 1512×949 window), 15 Mbps.
- Bugs found and fixed along the way: SCStream aborting with `CGS_REQUIRE_INIT`
  when set up off the main thread in a CLI tool; the whole pipeline being
  released when the startup Task finished (one frame, then silence); clients
  that connected to a static window never receiving a keyframe.
- Host prints a per-second stats line (captured/encoded/sent/dropped) so a
  stalled stage is visible without a debugger.
- Toolchain on Noah's Mac: Xcode 27 selected as developer dir, license
  accepted, first-launch packages installed. No signing identities existed;
  Noah signs with his own team in Xcode.
- Learned: ScreenCaptureKit delivers frames only when the window repaints, and
  macOS stops repainting fully covered windows, so a streamed window buried
  behind others on the Mac freezes on the device. Inherent to window capture;
  the virtual-display plan in milestone 3 sidesteps it.
- Not measured: the latency number itself (see above).

## Layout

- `Package.swift` — SwiftPM. `StreamProtocol` (shared wire format, iOS + macOS)
  and `SillHost` (macOS CLI executable).
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  message kinds in both directions, HEVC parameter set encoding. Shared by both
  sides. Change it in one place. `Switcher.swift` — the catalog types
  (`WindowList`, `WindowInfo`, `AppInfo`, `StreamSource`) and image blob framing.
- `Sources/SillHost/` — `StreamCoordinator` (main actor; owns the pipeline,
  switches sources on client request, brings the picked app forward, applies
  viewports, stops capture when the last client leaves), `WindowCatalog` (polls
  windows and thumbnails only while a client is connected; icons; installed
  apps in the background), `WindowCapture` (ScreenCaptureKit), `HEVCEncoder`
  (VideoToolbox), `StreamServer` (Network.framework + Bonjour `_sill._tcp`, both
  directions, keepalive, dead-client eviction, ping echo, client-stats print),
  `InputInjector` (CGEvents: pointer, scroll with phases, text, HID keys),
  `WindowSizer` (Accessibility resize for the Aa scale), `VirtualDisplay`
  (private-API wrapper, unused yet), `Stats` (1 s lines while active, 30 s
  heartbeat when idle), `main.swift` (knobs).
- `Sources/VirtualDisplayProbe/` — CLI experiment for milestone 3; run it from
  Terminal (needs Screen Recording + Accessibility): `.build/release/VirtualDisplayProbe "Activity Monitor" --seconds 20`.
- `iOSClient/` — `Sill.xcodeproj` and its sources: `StreamClient` (Bonjour,
  connection, parsing, reconnect, ping, generic `send`), `StreamScreen`
  (landscape: top bar, thumbnails, drawer, Aa, Keyboard, Desktop; layout
  selection by size incl. Duo outer display), `PortraitStreamScreen` (laptop
  layout: stream, compact bar, key rows, trackpad), `InputOverlay` (direct touch,
  Pencil, keyboard, scroll momentum), `TrackpadView`, `HEVCDisplayView` (shared
  display view + DEBUG HUD), `DiagnosticsHUD` (client stats reporter),
  `StreamClient+Viewport`, `ContentView` (connect screen + DEBUG harness),
  `MockCatalog` (harness data). Swift 5 language mode.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.

## Build and run

```
swift build -c release
swift run -c release SillHost              # nothing streams until the iOS app picks a window
swift run -c release SillHost Safari       # optional: preselect a matching window
```
Needs Xcode as the active developer directory with its license accepted; with
Command Line Tools only, add `--build-system native`.
First run prompts for Screen Recording (grant to Terminal or whatever launched it).
iOS side: open `iOSClient/Sill.xcodeproj`, set your team, run on a real
device on the same Wi-Fi.
Debug harness (simulator, no Duo simulator exists yet): launch arguments
`-SillLayout 1000x710` (inner landscape) / `710x1000` / `500x710` / `710x500`
(outer), `-SillLive 1` (real client inside the frame), `-SillDrawer 1`,
`-SillActive none|desktop|<windowID>` (mock), `-SillHUD 1` (diagnostics overlay).

## Conventions

- Swift, Apple frameworks only. No third-party dependencies unless a decision
  in `docs/BRIEF.md` says so. Zero operating costs is a hard rule.
- Threading in the spike is by hand: capture queue → VT callback thread →
  network queue. Keep it explicit and commented rather than reaching for actors
  until the design settles.
- HEVC, no B-frames, real-time mode. AV1 is out (no hardware encode on Apple
  silicon as far as we know).
- Latency beats quality. Drop frames before queuing them.
- Don't add features the current milestone doesn't need.

## Decisions already made (don't relitigate without asking Noah)

- Free app, tip jar, open source. Not paid, not subscription.
- iCloud auto-pairing (same Apple Account, Mac just appears) for milestone 5.
  Bonjour only for the spike.
- Native feel is the bar: Flighty-level polish, iOS conventions, Duo layouts.
- License: Apache-2.0 or MPL-2.0 (paid plan is gone, so no GPL/CLA needed).
- v1 out of scope: hole punching, multi-window, layout customization, audio.
