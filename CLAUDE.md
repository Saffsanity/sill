# winstream

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

## Current step

Milestone 2, input and window control. The phone can see the Mac; now it has to
drive it. Scope from `docs/BRIEF.md`: touch, keyboard and Pencil-as-pointer,
delivered to the Mac as CGEvents aimed at the streamed window. That needs:

- A client→host direction in `StreamProtocol` (today it is host→client only).
  Same 14-byte header, new message kinds for pointer, scroll, key and text.
- An input injector on the host (CGEvent posting, coordinates mapped from the
  streamed frame to the window's screen rect). Needs Accessibility permission
  on top of Screen Recording; the first-run prompt story matters.
- Window control: bring the target window to front on connect, follow it when
  it moves, and survive a resize (the encoder is still fixed to the launch
  size; a resize means recreating the VT session and sending new parameter
  sets).

Still owed from milestone 1: the glass-to-glass latency number. Noah judged the
stream "fast and high quality" on the iPad Mini and chose to move on; measure it
with the stopwatch-photo method in the README when convenient and record it here.

## Milestone 1 (latency spike) — done 2026-09-22

- Mac host builds and runs from `swift build -c release`: window listing,
  ScreenCaptureKit capture, VideoToolbox HEVC encode, Bonjour advertisement,
  TCP fan-out to clients.
- iOS client is a real Xcode project (`iOSClient/WinStream.xcodeproj`), builds
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
  and `WinStreamHost` (macOS CLI executable).
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  message kinds in both directions, HEVC parameter set encoding. Shared by both
  sides. Change it in one place. `Switcher.swift` — the catalog types
  (`WindowList`, `WindowInfo`, `AppInfo`, `StreamSource`) and image blob framing.
- `Sources/WinStreamHost/` — `StreamCoordinator` (main actor; owns the pipeline,
  switches sources on client request, brings the picked app forward),
  `WindowCatalog` (polls on-screen windows, thumbnails via SCScreenshotManager,
  app icons, installed apps), `WindowCapture` (ScreenCaptureKit), `HEVCEncoder`
  (VideoToolbox), `StreamServer` (Network.framework + Bonjour `_winstream._tcp`,
  both directions), `Stats` (per-second counters), `main.swift` (knobs: fps,
  scale, bitrate, prioritizeSpeed).
- `iOSClient/` — `WinStream.xcodeproj` and its sources: `StreamClient`
  (Bonjour, connection, message parsing), `StreamScreen` (top bar with live
  thumbnails + app drawer, built to the design boards), `HEVCDisplayView`,
  `ContentView` (connect screen). `Info.plist` has the local network + Bonjour
  keys. The project depends on this folder as a local package for
  `StreamProtocol`. Swift 5 language mode.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.

## Build and run

```
swift build -c release
swift run -c release WinStreamHost              # nothing streams until the iOS app picks a window
swift run -c release WinStreamHost Safari       # optional: preselect a matching window
```
Needs Xcode as the active developer directory with its license accepted; with
Command Line Tools only, add `--build-system native`.
First run prompts for Screen Recording (grant to Terminal or whatever launched it).
iOS side: open `iOSClient/WinStream.xcodeproj`, set your team, run on a real
device on the same Wi-Fi.

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
