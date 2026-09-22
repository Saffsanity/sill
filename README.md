# winstream — latency spike

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
swift run -c release WinStreamHost Safari
```

The argument matches an app name or window title. Leave it off to see the list
of on-screen windows. First run: macOS asks for Screen Recording for Terminal
(or Xcode, if you run it from there). Grant it, run again.

Knobs are at the top of `Sources/WinStreamHost/main.swift`: fps, scale,
bitrate, prioritizeSpeed. Start at the defaults, change one at a time.

## iOS client (10 minutes)

1. Xcode → New Project → iOS App, SwiftUI. Name it `WinStream`.
2. Delete the generated `ContentView.swift` and `WinStreamApp.swift`. Drag the
   four files from `iOSClient/` into the project.
3. File → Add Package Dependencies → Add Local → pick this `winstream` folder.
   Link the `StreamProtocol` library to the app target.
4. Target → Info, add:
   - `Privacy - Local Network Usage Description` (`NSLocalNetworkUsageDescription`): "Finds your Mac on the local network."
   - `Bonjour services` (`NSBonjourServices`), array with one item: `_winstream._tcp`
5. If the project defaults to Swift 6 strict concurrency, set the target's
   Swift Language Version to Swift 5 for the spike. Thread safety here is by
   hand and documented in the comments.
6. Run on a real device on the same Wi-Fi. Tap the Mac's name.

## Measuring latency

Open a millisecond stopwatch web page in the streamed window (search "online
stopwatch milliseconds"). Photograph the Mac screen and the phone screen in
one shot; the difference is glass-to-glass latency. The "frame age" overlay is
a rough live number that relies on both clocks being NTP-synced.

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
