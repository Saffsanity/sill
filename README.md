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
swift run -c release SillHost --virtual-display   # each streamed window on its own HiDPI display; Ctrl-C restores it
```

The argument matches an app name or window title. Leave it off to see the list
of on-screen windows.

`--virtual-display` (off by default, 2026-09-22) moves the picked window onto a
virtual HiDPI display created with a private CoreGraphics API and captures that
display, so the window keeps repainting whatever covers its old spot on the Mac.
It needs Screen Recording and Accessibility for the terminal that runs it. Every
failure (API missing, display never listed, Accessibility refused, window would
not move) falls back to today's real-window capture with a line in the log, and
deselecting, switching, the last client leaving, Ctrl-C, `kill` or a hangup put
the window back where it was and remove the display. Private API means the Mac
companion is Developer ID distribution, never the Mac App Store.
`swift run -c release SillHost --virtual-display-selftest` creates and destroys
one display and reports what CoreGraphics, AppKit and ScreenCaptureKit see of it. `swift build` needs Xcode selected as the developer
directory (`sudo xcode-select -s /Applications/Xcode.app`) with its license
accepted (`sudo xcodebuild -license accept`). With only the Command Line Tools
selected, the default build system fails to start; `swift build -c release
--build-system native` works there as a fallback. First run: macOS asks for Screen Recording for Terminal
(or Xcode, if you run it from there). Grant it, run again.

Knobs are at the top of `Sources/SillHost/main.swift`: maxFPS, scale,
bitrate, prioritizeSpeed. Start at the defaults, change one at a time.
The stream rate is the device's own: each client reports its panel's ceiling
(120 on ProMotion iPads and iPhones, 60 on the iPad mini) and 60 while Low
Power Mode is on; the host runs capture, encoder and the virtual display at
that rate, capped by maxFPS, and restarts when it changes. Bitrate scales
with the rate (the knob is per 60 fps).

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

If the device's round trip climbs in a 5→100→200→300 ms sawtooth while nothing
is streaming, that is its Wi-Fi radio dozing on a quiet link. The host keeps the
link lightly busy (`net.tick` in the stats line) whenever a session is live.

## What to try if it's slow

- `scale = 1` (four times fewer pixels to encode).
- `prioritizeSpeed = true`.
- Lower bitrate, or wire the phone to the Mac and repeat to isolate Wi-Fi.
- Check the Mac's Console for "dropped" from the capture; raise `queueDepth`.

## If the picture freezes

- Read the host's stats line. `cap` counting with `enc.out` stuck at zero means
  the encoder, not the capture. `cap` at zero means the window is not
  repainting (covered on the Mac, or the app is idle).
- The Mac's hardware video encoder can wedge system-wide: every new session
  accepts a frame and never returns it, in any process. `swift run -c release
  SillHost --encoder-selftest` settles it in five seconds without any
  permission. The host also probes the hardware encoder at launch and prints
  "Hardware encoder probe: no answer" when it is wedged, then streams with the
  software encoder at half scale on the CPU; if it wedges mid-stream the log
  says "switching to the software encoder" and the stream restarts by itself.
  A reboot brings the hardware encoder back for sure; once it also recovered
  by itself after about three hours.
- `swift run -c release SillHost --synthetic` streams a moving test pattern as
  the Desktop source with no Screen Recording needed: if the device shows the
  bar sweeping, the encoder, fallback and network are fine and the problem is
  capture or permissions.
- `swift run -c release CaptureProbe <window> [seconds] [--encode] [--software]
  [--synthetic]` isolates capture from encode from the network.

## Known limitations, all intentional for a spike

- TCP: one lost packet stalls everything behind it. The real transport is UDP
  or QUIC with FEC; measure before deciding.
- The encoder is fixed to one size, so a resized window restarts the pipeline
  (a brief black frame on the device).
- Single window at a time, no encryption. The device reconnects on a timer
  when the Mac drops it.
- Bonjour only. iCloud auto-pairing comes with milestone 5.
