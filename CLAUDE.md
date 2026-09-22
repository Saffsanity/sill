# winstream

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

## Current step

Milestone 1, the latency spike. Get the Mac host and iOS client building, run
them, and measure glass-to-glass latency. Nothing else until that number exists.
Everything in this repo was written without a compiler; expect small API-level
build errors in the CoreMedia/VideoToolbox calls and just fix them.

## Layout

- `Package.swift` — SwiftPM. `StreamProtocol` (shared wire format, iOS + macOS)
  and `WinStreamHost` (macOS CLI executable).
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  HEVC parameter set encoding. Shared by both sides. Change it in one place.
- `Sources/WinStreamHost/` — `WindowCapture` (ScreenCaptureKit), `HEVCEncoder`
  (VideoToolbox), `StreamServer` (Network.framework + Bonjour `_winstream._tcp`),
  `main.swift` (knobs: fps, scale, bitrate, prioritizeSpeed).
- `iOSClient/` — files to drop into an Xcode iOS App project (see README).
  Not yet an Xcode project; creating one is a fine first task.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.

## Build and run

```
swift build -c release
swift run -c release WinStreamHost <app name or window title>
```
First run prompts for Screen Recording (grant to Terminal or whatever launched it).
iOS side: Xcode, real device, same Wi-Fi. Info.plist needs
`NSLocalNetworkUsageDescription` and `NSBonjourServices = [_winstream._tcp]`.

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
