# Sill — latency spike

Milestone 1 of the Mac window streaming app: capture one Mac window with
ScreenCaptureKit, hardware-encode it to HEVC, push it over the local network,
and display it on an iPhone or iPad. No input, no UI, no pairing. The only
question this answers is: **what is the glass-to-glass latency and is it good
enough to build on?**

Pipeline: `SCStream (420f) → VTCompressionSession (HEVC, real time, no B-frames)
→ Network.framework TCP + Bonjour → AVSampleBufferDisplayLayer`

## Mac host (5 minutes)

### Sill.app, the menu bar host

```
cd ~/Downloads/winstream && Scripts/make-app.sh --install --open
```

That builds the `SillMenuBar` executable with SwiftPM, wraps it into
`Sill.app` (bundle ID `me.saffer.sill.mac`, the icon compiled from
`design/AppIcon.svg`), signs it with your Apple Development identity, quits a
running Sill (its streamed window goes home first), replaces
`/Applications/Sill.app` and opens it. Run the same command after every change.
Without `--install` it only builds `.build/Sill.app`. It will not replace an
`/Applications/Sill.app` that is not this app (an iPad build of the client, say).

Sill lives in the menu bar: no Dock icon, no window at launch. The menu shows
whether it is visible on the network, each connected device with its frame
rate, frame age, round trip and how it is connected ("Wired", "Wi-Fi" or
"Direct"; from away, "through Tailscale" or "over the internet"), and what is
streaming; it holds the
virtual display, frame rate, quality and resolution controls, Direct Wireless
Connection, Remote Access… and Pair iPhone or iPad… (see Remote access below),
Launch at Login, Permissions, Show Log… and Settings… (⌘,).
Changes apply at once; a change to a streaming setting restarts the current
stream for a moment. Opening Sill.app while it runs (Finder,
Spotlight) shows Settings, which is also where Quit Sill is when the menu bar
has no room for the icon.

Quality is the stream's bitrate per 60 fps (a 120 fps stream gets twice as
much): Low 4 Mbps (for a slow link away from home), Efficient 8, Balanced 15
(the default, and the command-line host's), High 25, Pro 40, Ultra 80 and
Extreme 150. Ultra and Extreme need the
USB cable or very fast Wi-Fi; if the picture lags (the device's frame age in
the menu climbs), step down. Any other value from 1 to 200 Mbps can be set by
hand (quit Sill, `defaults write me.saffer.sill.mac bitrate -int 60000000`,
open it again) and shows as Custom; a device can pick only the presets.

Permissions:

- The first launch opens Settings on Permissions. Screen Recording and
  Accessibility are granted to **Sill**, not Terminal: what Terminal has for
  the `SillHost` command-line tool does not carry over. Screen Recording takes
  effect after a relaunch (macOS offers Quit & Reopen; the pane has Relaunch
  Sill); Accessibility works at once.
- Keep one copy, in /Applications, and launch it from Finder, `open` or the
  login item. Running `Sill.app/Contents/MacOS/Sill` from Terminal makes
  Terminal the responsible process, with Terminal's permissions.
- Grants survive rebuilds because every build is signed with the same
  identity. If they ever go stale (the switch is on in System Settings but Sill
  still can't capture or click): quit Sill, run `tccutil reset ScreenCapture
  me.saffer.sill.mac` and `tccutil reset Accessibility me.saffer.sill.mac`,
  then `defaults delete me.saffer.sill.mac askedScreenRecording` and
  `defaults delete me.saffer.sill.mac askedAccessibility`, open Sill again and
  use Allow… in Settings › Permissions. The `defaults` step matters: Sill
  shows each system alert only once and remembers that it did, so without it
  Allow… only opens System Settings, where the reset has removed Sill from both
  lists. (Adding /Applications/Sill.app to both lists with + works too.)

The log: `tail -F ~/Library/Logs/Sill/Sill.log` (`-F`, not `-f`: at 10 MB the
file moves to Sill.1.log and a new one starts), or Show Log… in the menu.
Settings: `defaults read me.saffer.sill.mac`.

Direct Wireless Connection (Settings › General, and the status menu) lets an
iPhone or iPad connect when it is near the Mac but shares no Wi-Fi network with
it, the way AirDrop does: Sill then also advertises over, and accepts
connections from, peer-to-peer Wi-Fi (AWDL). It is off by default, also after
updating from a Sill that always used AWDL, because while it is on the Mac's
Wi-Fi keeps leaving its network's channel (up to ~100 ms twice a second), which
made Wi-Fi streams stutter. With it on, a device that shares a network with the
Mac still streams over the network: one that got onto AWDL anyway moves there by
itself, without dropping the stream, once the network has listed the Mac for
two seconds (and only to that same Mac, never to another of the same name).
Turning it on or off applies at once and never restarts the stream, though
turning it off disconnects a device that is still connected directly (a second
and a half later); it comes back over the network if it shares one. A device
finds a Mac this way by itself once it has seen the Mac with it on, or when you
tap Search Nearby on its connect screen; such a Mac shows as "Direct". With it
on, anyone nearby running Sill can find and connect to the Mac. Turning Wi-Fi
off in Control Center does not end a direct connection (it leaves the radio on
for AirDrop); Settings › Wi-Fi does.

A connected iPhone or iPad changes the same settings from its own Settings
panel (the gear, the last button of its bar): Quality, Resolution, Frame Rate,
Prioritize Encoding Speed, Virtual Display and Direct Wireless Connection, with
exactly the Mac's choices. Sill.app saves a device's change like a menu click,
and its Settings window and menu show it; the change applies to every connected
device, and a streaming setting restarts the stream for a moment. To put one
setting back to its default, quit Sill, run `defaults delete
me.saffer.sill.mac <key>` (`bitrate`, `maxFPS`, `captureScale`,
`prioritizeSpeed`, `virtualDisplay` or `directWireless`) and open Sill again.

Distribution (M6): `Scripts/release.sh` makes the download. It runs
`make-app.sh --release` (which refuses any signature but Developer ID), zips
the app, sends it to Apple's notary service and waits, staples the ticket,
zips it again so the download carries the ticket, checks a copy unpacked from
that zip with `stapler validate` and `spctl`, and prints the zip's path and
SHA-256. It needs `SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'`
and `SILL_NOTARY_PROFILE` (a profile saved with `xcrun notarytool
store-credentials sill-notary`), and refuses to start without them. Give
both on the release command itself, never in your shell profile: `make-app.sh`
signs every build with `SILL_SIGN_IDENTITY` when it is set, `--install`
included. `--dry-run` needs only the identity and stops before anything goes
to Apple.
The one-time setup and each release's steps are in docs/release-checklist.md.
A Developer ID signature has a different designated requirement, so
permissions are granted once more.

### The command-line host

```
cd winstream
swift run -c release SillHost Safari
swift run -c release SillHost --virtual-display   # each streamed window on its own HiDPI display; Ctrl-C restores it
swift run -c release SillHost --direct-wireless   # also over peer-to-peer Wi-Fi, for a device with no shared network
```

The argument matches an app name or window title. Leave it off to see the list
of on-screen windows.

A device can change the command-line host's settings from its Settings panel
too; `SillHost` saves nothing, so a change lasts until it quits, and the
device's panel says so. Its Virtual Display switch works only when `SillHost`
runs with `--virtual-display`. `--direct-wireless` starts it with Direct
Wireless Connection on (see Sill.app above); it is off by default here too.

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

Knobs live in `Sources/SillHost/HostConfig.swift` (`HostConfig.standard`):
maxFPS, captureScale, bitrate, prioritizeSpeed. The CLI uses them as they are;
Sill.app starts from them and changes them from its menu and Settings. Start
at the defaults, change one at a time.
The stream rate is the device's own: each client reports its panel's ceiling
(120 on ProMotion iPads and iPhones, 60 on the iPad mini) and 60 while Low
Power Mode is on; the host runs capture, encoder and the virtual display at
that rate, capped by maxFPS, and restarts when it changes. Bitrate scales
with the rate (the knob is per 60 fps, 1–200 Mbps).

## iOS client (5 minutes)

1. Open `iOSClient/Sill.xcodeproj`. It already links the local
   `StreamProtocol` package (this folder), sets Swift 5 language mode for the
   spike, and carries an `Info.plist` with `NSLocalNetworkUsageDescription`,
   `NSBonjourServices = [_sill._tcp]`, the camera text for the pairing scanner
   and the `sill` URL scheme (a pairing link always asks before it pairs).
2. Target → Signing & Capabilities → pick your team. Change the bundle
   identifier if `me.saffer.sill` collides with something.
3. Run on a real device on the same Wi-Fi (or with Direct Wireless Connection
   on in Sill on the Mac). Tap the Mac's name. Its row ends in where the device
   sees it: "Wi-Fi", "Wired" (a cable), "Direct", or nothing when it can't
   tell. A "Wired" row connects over the cable, even with Wi-Fi up (should
   that not connect within 2.5 s, over whichever link the device picks); the
   Settings panel's readout ends in the link the connection does take.

The gear at the end of the bar opens Settings: the Mac's streaming settings,
changed from the device, and Disconnect at the bottom.

The project is a plain Xcode project checked in by hand: four source files,
an asset catalog, and the package reference. Nothing else.

## Remote access (away from home)

Sill reaches your Mac from anywhere through a VPN you already run, or through a
port forward on your router. There is no Sill server: the iPhone or iPad dials
the Mac itself. It is off until you turn it on, and only devices you paired can
connect (TLS 1.3, each end pinned to the other's key).

1. On the Mac: Sill › Settings › Remote Access, turn on Remote access. Sill
   listens on TCP port 7455 (Change… picks another) and lists the addresses a
   device will use: your Tailscale address and its MagicDNS name, another VPN,
   this network's address.
2. Pair each device once, at home or away: Pair iPhone or iPad… in the Sill
   menu shows a QR code and a 12-digit code for five minutes. On the device,
   tap Add a Mac… at the bottom of the connect screen and point it at the
   code, or choose Enter Code Instead and type the address and the code the
   window shows. With Tailscale, the address is the Mac's MagicDNS name or the
   Tailscale IP address under it; otherwise it is this network's address, with
   another VPN's address under it when the Mac runs one. A device already
   connected at home can use Pair This iPad… at the end of its Settings panel
   instead; the Mac shows its code by itself.
3. Away from home the Mac is a "Remote" row about 3 s after the connect screen
   opens (the local network gets the first 3 s); tap it. After a drop the device
   reconnects by itself, first on the local network, then remotely. The
   device's Settings panel says how it is connected ("Connected through
   Tailscale · 48 ms"), and the Mac's menu shows the route of each device.

The ways in:

- **Tailscale** (the easy one): install it on the Mac and on the device, signed
  in to the same tailnet. Nothing else to set up.
- **WireGuard or another VPN into your home network** (on the router, say):
  the device reaches the Mac's home address through the tunnel. The tunnel's
  AllowedIPs on the device must include your home subnet (192.168.1.0/24, for
  example), or nothing reaches it.
- **A port forward** (Settings › Remote Access › Allow connections from the
  internet, off by default): forward TCP 7455 on the router to the Mac's
  address shown there, and reserve that address for the Mac. The pane shows
  the router's internet address when the router says it, or explains when your
  provider shares one address among many customers (CGNAT) or there are two
  routers in a row (double NAT); then a port forward cannot work and a VPN can.
  If your internet address changes, add a dynamic DNS name as the address name.
  Turning the switch off disconnects devices that came in from the internet.

If it doesn't connect:

- "didn't answer": the Mac is asleep or off, or the VPN is off on the Mac.
  While a device is connected remotely Sill keeps the Mac from going to sleep
  by itself (the display may still sleep), but it cannot wake a sleeping Mac:
  for a Mac that should stay reachable, prevent automatic sleeping in System
  Settings › Energy (or Battery).
- "Tailscale looks off on this iPad": turn it on on the device.
- Tailscale's Shields Up on the Mac blocks every incoming connection, and a
  tailnet ACL must let the device reach the Mac on port 7455.
- Testing a port forward from inside your home network can fail on routers
  without "hairpin" NAT: test over cellular.
- "no longer accepts this iPad": the device was removed on the Mac (Settings ›
  Remote Access › Paired Devices); pair it again.

Quality follows you home: the Quality setting belongs to the Mac, and Sill.app
saves it, so picking Low (4 Mbps, for a slow link) away from home leaves it at
Low at home until you change it back. Away from home through a VPN or the
internet, a device asks for 60 fps even if its screen shows 120, which halves
what the Mac sends; the panel suggests Low or Standard resolution when the
round trip stays over 250 ms.

The command-line host: `swift run -c release SillHost --remote` opens the
remote door for one run on any free port (`--remote=PORT` for a fixed one, but
not Sill.app's 7455 while it has Remote Access on), with a new identity each
run, and prints the pairing code and link in Terminal (again whenever a device
asks); `--internet` also admits paired devices from outside this Mac's networks
and VPNs; `--print-reachability` lists the addresses a device would get and
exits. A device paired with the CLI must pair again after it restarts; Sill.app
is the host to pair with for good.

To start over on the Mac: quit Sill, then `for k in remoteAccess remotePort
internetAccess remoteAddressName remoteDevicesSeen; do defaults delete
me.saffer.sill.mac $k; done`. The Mac's identity and its paired devices are in
Keychain Access › login: the key "Sill Remote Access" and the passwords of
service `me.saffer.sill.remote`; deleting them makes this Mac new to every
device, which must pair again. On the device, a paired Mac's row has Forget in
its menu (touch and hold).

## Measuring latency

Each connected device reports what it sees every second, and the host logs
every other report:
`client iPad (iPad14,1): 58 fps, frame age 9/24 ms, rtt 7/80 ms`. Frame age is
the host's encode-output timestamp to the device receiving the frame (clocks
assumed synced), taken for every frame; RTT is a ping round trip, four pings a
second. Each pair is the last second's median over the worst since the
previous line, and "–" marks a second without a sample (a still window streams
no frames). An older iOS build reports single values
(`frame age 8 ms, rtt 7 ms`). Measured 2026-09-22 on 5 GHz Wi-Fi: frame age
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
Spikes of up to ~100 ms about twice a second while streaming are AWDL taking
the Mac's radio off the channel: Direct Wireless Connection should be off, and
AirDrop, Sidecar and Universal Control can hold AWDL on too.

## What to try if it's slow

- Resolution: Standard (`captureScale: 1`, four times fewer pixels to encode).
- Prioritize encoding speed (`prioritizeSpeed: true`).
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
- Single window at a time. On the home network the stream is not encrypted
  (only this Mac's own networks may connect); away from home it runs over TLS
  1.3 to paired devices only. The device reconnects on a timer when the Mac
  drops it.
- Bonjour at home, your VPN or a port forward away (Remote access above).
  iCloud auto-pairing comes with milestone 5.

## Layout

- `Sources/`: the Swift package. `StreamProtocol` (the wire format, shared
  with the iOS app), `SillHost` (the host library), `SillHostCLI` (the
  `SillHost` command), `SillMenuBar` (Sill.app) and two probes.
- `iOSClient/`: the iPhone and iPad app, `Sill.xcodeproj`.
- `Packaging/`: Sill.app's Info.plist and entitlements.
- `Scripts/`: `make-app.sh` (builds Sill.app), `release.sh` (the notarized
  zip people download), `sillclient.py` (a wire-format test client) and
  `sillrelay.py` (a relay that slows or cuts the link, for tests).
- `site/`: the website, plain HTML for GitHub Pages: home, download, privacy
  policy and support. Preview it with
  `python3 -m http.server 8000 --directory site`.
- `docs/`: the brief, the plans, `app-store-metadata.md` (what App Store
  Connect asks for) and `release-checklist.md` (the order of work for a
  release).
- `design/`: the app icon.
