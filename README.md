# Sill — latency spike

Milestone 1 of the Mac window streaming app: capture one Mac window with
ScreenCaptureKit, hardware-encode it to HEVC, push it over the local network,
and display it on an iPhone or iPad. No input, no UI, no pairing. The only
question this answers is: **what is the glass-to-glass latency and is it good
enough to build on?**

Pipeline: `SCStream (420f) → VTCompressionSession (HEVC, real time, no B-frames)
→ Network.framework TCP + Bonjour → AVSampleBufferDisplayLayer`

## Mac host (5 minutes)

```
cd winstream
swift run -c release SillHost Safari
```

The argument matches an app name or window title. Leave it off to see the list
of on-screen windows. `swift build` needs Xcode selected as the developer
directory (`sudo xcode-select -s /Applications/Xcode.app`) with its license
accepted (`sudo xcodebuild -license accept`). With only the Command Line Tools
selected, the default build system fails to start; `swift build -c release
--build-system native` works there as a fallback. First run: macOS asks for Screen Recording for Terminal
(or Xcode, if you run it from there). Grant it, run again.

Knobs are at the top of `Sources/SillHost/main.swift`: fps, scale,
bitrate, prioritizeSpeed. Start at the defaults, change one at a time.

## iOS client (5 minutes)

1. Open `iOSClient/Sill.xcodeproj`. It already links the local
   `StreamProtocol` package (this folder), sets Swift 5 language mode for the
   spike, and carries an `Info.plist` with `NSLocalNetworkUsageDescription` and
   `NSBonjourServices = [_sill._tcp]`.
2. Target → Signing & Capabilities → pick your team. Change the bundle
   identifier if `me.saffer.sill` collides with something.
3. Run on a real device on the same Wi-Fi. Tap the Mac's name.

The project is a plain Xcode project checked in by hand: four source files,
an asset catalog, and the package reference. Nothing else.

## Measuring latency

The host logs what each connected device sees, once a second:
`client iPad (iPad14,1): 53 fps, frame age 8 ms, rtt 7 ms`. Frame age is the
host's encode-output timestamp to the device receiving the frame (clocks assumed
synced); RTT is a ping round trip. Measured 2026-09-22 on 5 GHz Wi-Fi: frame age
8–10 ms, RTT 6–9 ms. Capture, encode, decode and display add roughly 30–50 ms
more, so glass-to-glass is about 40–60 ms.

For the true glass-to-glass number, open a millisecond stopwatch page in the
streamed window, photograph the Mac and the device in one shot, and subtract.
In a DEBUG build, `-SillHUD 1` overlays fps, frame age, RTT and frame size on
the device.

Targets: under 60 ms on 5 GHz Wi-Fi is the v1 bar. Under 40 ms is Mirage-class.

## What to try if it's slow

- `scale = 1` (four times fewer pixels to encode).
- `prioritizeSpeed = true`.
- Lower bitrate, or wire the phone to the Mac and repeat to isolate Wi-Fi.
- Check the Mac's Console for "dropped" from the capture; raise `queueDepth`.

## Known limitations, all intentional for a spike

- TCP: one lost packet stalls everything behind it. The real transport is UDP
  or QUIC with FEC; measure before deciding.
- The encoder is fixed to the window's size at launch. Resize = garbage frames.
- Single window, single client tested, no input, no encryption, no reconnect.
- Bonjour only. iCloud auto-pairing comes with milestone 5.
