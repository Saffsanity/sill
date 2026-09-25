# Developing Sill

How to build, run and test Sill from this repository. For help with using
Sill, see the [Support](https://getsill.app/support) page on
[getsill.app](https://getsill.app).

Until 2026-09-25 this was the README, so where a plan in `docs/` mentions "the
README", it means a section here. `CLAUDE.md` has the rest: the work in
progress, the decisions already made, and every test hook.

## Overview

Pipeline: `SCStream (420f) → VTCompressionSession (HEVC, real time, no B-frames)
→ Network.framework TCP + Bonjour → AVSampleBufferDisplayLayer`

- `Sources/StreamProtocol/`: the wire format, shared by both sides. The iOS
  project links this package for it.
- `Sources/SillHost/`: the host itself (the `SillHostCore` library): capture,
  encode, network, input, the virtual display and remote access.
- `Sources/SillMenuBar/`: Sill.app, the menu bar host. `Sources/SillHostCLI/`:
  `SillHost`, the same host on the command line.
- `Sources/CaptureProbe/` and `Sources/VirtualDisplayProbe/`: tools for
  diagnosis and experiments, not shipped.
- `iOSClient/`: the iPhone and iPad app, `Sill.xcodeproj`.
- `Packaging/`: Sill.app's `Info.plist` and development entitlements.
  `Scripts/`: `make-app.sh`, and the test tools below. `design/`: the icon (see
  its README). `docs/`: the brief and the plans.

`CLAUDE.md`, Layout, goes through the code file by file.

## Build and run

### Toolchain

`swift build` needs Xcode selected as the developer
directory (`sudo xcode-select -s /Applications/Xcode.app`) with its license
accepted (`sudo xcodebuild -license accept`). With only the Command Line Tools
selected, the default build system fails to start; `swift build -c release
--build-system native` works there as a fallback.

Sill is built with Xcode 27, for macOS 14 or later and iOS 17 or later (the
deployment targets).

### Sill.app, the menu bar host

```
Scripts/make-app.sh --install --open
```

That builds the `SillMenuBar` executable with SwiftPM, wraps it into
`Sill.app` (bundle ID `me.saffer.sill.mac`, the icon compiled from
`design/AppIcon.svg`), signs it with your Apple Development identity, quits a
running Sill (its streamed window goes home first), replaces
`/Applications/Sill.app` and opens it. Run the same command after every change.
Without `--install` it only builds `.build/Sill.app`. It will not replace an
`/Applications/Sill.app` that is not this app (an iPad build of the client, say).
`SILL_INSTALL_DIR=~/Applications Scripts/make-app.sh --install` installs it in
another folder. With no Apple Development identity in the keychain it signs ad
hoc and says so, and then Screen Recording and Accessibility have to be granted
again after every rebuild (see Permissions).

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

The log: `tail -F ~/Library/Logs/Sill/Sill.log` (`-F`, not `-f`: at 10 MB the
file moves to Sill.1.log and a new one starts), or Show Log… in the menu.
Settings: `defaults read me.saffer.sill.mac`.

### The command-line host

```
swift run -c release SillHost                        # nothing streams until a device picks a window
swift run -c release SillHost Safari                 # optional: preselect a matching window
swift run -c release SillHost --virtual-display      # each streamed window on its own HiDPI display; Ctrl-C restores it
swift run -c release SillHost --direct-wireless      # also over peer-to-peer Wi-Fi, for a device with no shared network
swift run -c release SillHost --synthetic            # the Desktop streams a test pattern; no Screen Recording needed
swift run -c release SillHost --remote               # the remote door for this run, on any free port (--remote=PORT)
swift run -c release SillHost --remote --internet    # also admit paired devices from the internet
swift run -c release SillHost --print-reachability   # the addresses a device would get away from home, then exit
swift run -c release SillHost --encoder-selftest     # is the hardware encoder alive? 5 s, then it exits
swift run -c release SillHost --virtual-display-selftest   # create and destroy one display, report what sees it
```

The argument matches an app name or window title. Leave it off to see the list
of on-screen windows.

A device can change the command-line host's settings from its Settings panel
too; `SillHost` saves nothing, so a change lasts until it quits, and the
device's panel says so. Its Virtual Display switch works only when `SillHost`
runs with `--virtual-display`. `--direct-wireless` starts it with Direct
Wireless Connection on (see Direct Wireless Connection below); it is off by
default here too.

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
one display and reports what CoreGraphics, AppKit and ScreenCaptureKit see of it.

First run: macOS asks for Screen Recording for Terminal
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

### The iOS app

1. Open `iOSClient/Sill.xcodeproj`. It already links the local
   `StreamProtocol` package (this folder), sets Swift 5 language mode for the
   spike, and carries an `Info.plist` with `NSLocalNetworkUsageDescription`,
   `NSBonjourServices = [_sill._tcp]`, the camera text for the pairing scanner
   and the `sill` URL scheme (a pairing link always asks before it pairs).
2. Target → Signing & Capabilities → pick your team. Change the bundle
   identifier if `me.saffer.sill` collides with something (it does on any team
   but the project's own).
3. Run on a real device on the same Wi-Fi (or with Direct Wireless Connection
   on in Sill on the Mac). Tap the Mac's name. Its row ends in where the device
   sees it: "Wi-Fi", "Wired" (a cable), "Direct", or nothing when it can't
   tell. A "Wired" row connects over the cable, even with Wi-Fi up (should
   that not connect within 2.5 s, over whichever link the device picks); the
   Settings panel's readout ends in the link the connection does take. At
   home a session follows the cable: plugged in, it moves there about 2 s
   later; pulled, it moves to Wi-Fi at once, without the connect screen;
   dropped by the Mac while the cable stays in (Sill away in the background,
   say), it reconnects over the cable. A session from away (Remote access,
   below) keeps its way in until it ends.

The gear at the end of the bar opens Settings: the Mac's streaming settings,
changed from the device, and Disconnect at the bottom.

The project is a plain Xcode project checked in by hand: its source files, an
asset catalog, and the package reference. Nothing else. A new source file
needs its four `project.pbxproj` entries added by hand.

## Permissions

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

## Settings from a device

A connected iPhone or iPad changes the same settings from its own Settings
panel (the gear, the last button of its bar): Quality, Resolution, Frame Rate,
Prioritize Encoding Speed, Virtual Display and Direct Wireless Connection, with
exactly the Mac's choices. Sill.app saves a device's change like a menu click,
and its Settings window and menu show it; the change applies to every connected
device, and a streaming setting restarts the stream for a moment. To put one
setting back to its default, quit Sill, run `defaults delete
me.saffer.sill.mac <key>` (`bitrate`, `maxFPS`, `captureScale`,
`prioritizeSpeed`, `virtualDisplay` or `directWireless`) and open Sill again.

## Direct Wireless Connection

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

## Test tools

None of these needs a device. `CLAUDE.md`, Build and run, has the complete
list, with the test-only environment variables and the recipes for headless
tests of Direct Wireless Connection and remote access.

### The test client and the relay

`Scripts/sillclient.py PORT [seconds] [desktop|none|window:ID] [flags…]` speaks
the wire format as a device would, and prints what the host sends. For
example, a device's settings change, checked against the host's answer:

```
python3 Scripts/sillclient.py PORT 8 desktop --set=bitrate=25000000@3 --expect=bitrate=25000000
```

Its docstring lists every flag: timed changes and picks, stats as a named
device, the remote door with pairing, and more. It checks every argument
before it connects, and a bad one exits 2. The synthetic hosts do not
advertise over Bonjour, so this client, or the simulator's `-SillConnect`, is
how to reach them; `lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>` finds the port.

`Scripts/sillrelay.py --listen 0 --to HOST:PORT [--delay-ms N] [--rate-mbps R]
[--blackhole-after S] [--record PREFIX]` sits between a client and a host, and
slows or cuts the link. TLS passes through.

### Test arguments for the bare app

`.build/release/SillMenuBar` is Sill.app without its bundle. It keeps its
settings in the defaults domain `SillMenuBar` (delete it after), and takes:

- `--synthetic`: the test pattern, off Bonjour; the port is in the "Status:
  Test Pattern Mode" line.
- `-SillLogFile <path>`, `-SillSetAfter '<s> key=value[,key=value][; <s> …]'`
  and `-SillQuitAfter <s>`.
- `-SillRenderPreviews <dir>`: the Settings panes, the menu's cards, the
  glyphs and `menu.txt`, with no permission needed. Render them from
  `.build/Sill.app/Contents/MacOS/Sill` to see what Sill.app looks like: only
  the bundle's copy records the real SDK, and the bare binary draws the pre-26
  look.
- A setting as a launch argument, such as `-maxFPS 60`, for one run. Sill.app
  takes these too.

`--encoder-selftest` and `--virtual-display-selftest` work in the app too.

### The iOS debug harness

Debug builds of the iOS app take launch arguments that set up a screen in the
simulator:

- `-SillLayout 1000x710` or `710x1000` (the inner display of iPhone Duo, in
  landscape and portrait), `500x710` or `710x500` (its outer display): a fake
  screen of that size.
- `-SillLive 1`: a real client inside that frame. Otherwise the Mac is a mock,
  and `-SillActive none|desktop|<windowID>` picks what it streams.
- `-SillDrawer 1`, `-SillSettings 1` (with `-SillSettingsCase …` for the
  settings of the mock Mac) and `-SillConnectCase …`: the drawer, the Settings
  panel or the connect screen in a given state.
- `-SillHUD 1`: fps, frame age, round trip and frame size over the stream.
- `-SillConnect 127.0.0.1:PORT`: connect by address, also in the normal app.

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

## Troubleshooting

### What to try if it's slow

- Resolution: Standard (`captureScale: 1`, four times fewer pixels to encode).
- Prioritize encoding speed (`prioritizeSpeed: true`).
- Lower bitrate, or wire the phone to the Mac and repeat to isolate Wi-Fi.
- Check the Mac's Console for "dropped" from the capture; raise `queueDepth`.

### If the picture freezes

- Read the host's stats line. `cap` counting with `enc.out` stuck at zero means
  the encoder, not the capture. `cap` at zero means the window is not
  repainting (covered on the Mac, or the app is idle).
- The Mac has one hardware video encoder, shared by every app. When it keeps
  a frame for 1.5 s the log says "switching to the software encoder" and the
  stream restarts at half resolution on the CPU, up to 60 fps (a launch probe
  with no answer, "Hardware encoder probe: no answer", starts there). Almost
  always the encoder is busy, not broken: the iOS Simulator's screen recorder
  (`xcrun simctl io … recordVideo`) runs at a higher priority in the encoder
  and held Sill's frames for 1.8 s and 8.6 s on 2026-09-24, and any other big
  encode at the same time (a video export, a render, a second SillHost) costs
  Sill frames too. The host then tests the hardware at the stream's size every
  30 s while a device is connected (longer while it stays busy) and goes back
  to it by itself once it keeps up ("Hardware encoder is back"): 45 fps in the
  test, or for a frame too big for that even on a free engine (a Retina 6K
  desktop), most of what the engine does alone at that size; "answers but
  is busy" means another app still holds it, and "the stalled frame came back
  after N s; the encoder was busy, not stuck" confirms it was busy. A
  stuck encoder is rarer (2026-09-22: every new session in every process took
  a frame and never returned it, for about three hours): `swift run -c release
  SillHost --encoder-selftest` settles it in five seconds without any
  permission, and a reboot fixes it. After 8 checks whose frames never came
  back the host stops checking and says so, and the menu shows "Hardware
  Encoder Stuck" until one of those frames does come back ("so it is not
  stuck; checks resume").
- `swift run -c release SillHost --synthetic` streams a moving test pattern as
  the Desktop source with no Screen Recording needed: if the device shows the
  bar sweeping, the encoder, fallback and network are fine and the problem is
  capture or permissions.
- `swift run -c release CaptureProbe <window> [seconds] [--encode] [--software]
  [--synthetic]` isolates capture from encode from the network.

## Releasing

Distribution (M6): `SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'
Scripts/make-app.sh --release` (it refuses to finish with any other kind of
signature, which notarization would reject), then `ditto -c -k --keepParent
.build/Sill.app .build/Sill.zip`, `xcrun notarytool submit .build/Sill.zip --keychain-profile
sill-notary --wait` and `xcrun stapler staple .build/Sill.app`. Store the
notary credentials in the keychain profile yourself first
(`xcrun notarytool store-credentials sill-notary`). A Developer ID signature
has a different designated requirement, so permissions are granted once more.

## Known limitations

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
