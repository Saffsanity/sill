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

Updates: once a day (and when you click Check Now in Settings › General),
Sill asks GitHub (api.github.com) whether a newer Sill has been released, and
when one has, the menu offers "Sill 0.4 Is Available…" and Settings › General
says so; either opens the release's page on GitHub, where you download it.
Sill never downloads or installs anything by itself, and a failed check is one
line in the log and in Settings, never an alert. The request carries the Mac's
IP address (like any visit to a website), Sill's version in its User-Agent
("Sill/0.3.0"), a fixed `Accept-Language: en` (URLSession would otherwise send
the Mac's languages) and, after a first answer, GitHub's own ETag back
(If-None-Match); nothing else about the Mac or you: no identifier, no cookie,
nothing about your devices. "Check for updates automatically" turns the daily
check off (what an earlier check found stays in the menu); the check needs a
published GitHub release, so while the repository has none it logs "GitHub has
no release of Sill (HTTP 404)" once a day. It keeps `updateLastCheck`,
`updateETag`, `updateLatestTag` and `updateLatestURL` in `me.saffer.sill.mac`;
to make the next launch check again after 30 s: `for k in updateLastCheck
updateETag updateLatestTag updateLatestURL; do defaults delete
me.saffer.sill.mac $k; done` (`defaults delete` takes one key at a time).

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
swift run -c release SillHost --menu-selftest=TextEdit     # the menus a device would get for an app (a pid, or its name), read once
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

On a phone held upright (and on the Duo's outer display) the picture sits in
a fixed 16:10 pane at the top: a 16:9 window gets black bars above and below
it, and nothing under it moves. Under it come Apps, Aa, Keyboard, Desktop and
Settings, as wide as the row; the window thumbnails; esc, tab, ctrl, opt, cmd
and shift; and the trackpad in the rest. The Keyboard button stays above the
software keyboard, so it always takes it down. There are no arrow keys or
Spotlight key there: Spotlight is cmd, then space on the keyboard. The
trackpad counts a stroke down it as far as the same stroke across a 16:10
picture, however tall it is. On its side, and on an iPad (a narrow window
included), everything is as it was.

The first time a Mac's picture shows on a device, and nothing is touched, sent,
used (by any means, VoiceOver's double tap included) or opened in the second
after it, a short tour dims the screen and lights one part at a time: the
picture (tap, hold, drag), the thumbnails with Aa (and Keyboard, sideways and
on a phone upright), Settings, and upright the key row and the trackpad. A card
stays beside what it lights at every text size, its words scrolling there. Skip
ends it for good on that device (in Take the Tour it only closes it); a step
passed stays passed; the automatic reconnect's session keeps the decision the
last one made; after a tour taken sideways, the upright card comes the first
time the device is held upright and left alone for a second. Settings › Take
the Tour, the panel's last row, shows it again. Nothing reaches the Mac while it shows, and it sends
nothing. What it remembers is two keys in the app's own defaults,
`Sill.tourSeen` and `Sill.tourSkipped` (delete the app, or `xcrun simctl
uninstall`, to see it afresh). Debug builds show it by themselves only with
`-SillTourState` (the harness below). docs/first-run-walkthrough-plan.md has
the rules; `iOSClient/TourPolicy.swift` is them, checked in `Tests/checks/tour`.

Every connection starts with the device's hello (its Sill version, build and
name, sent only to the Mac it connects to). A later Mac that needs a newer Sill
on the device answers with a notice instead of a stream: the connect screen
shows the Mac's words ("Update Sill on your iPad to keep using Mac mini. It
needs version 1.2 or later."), with "Update Sill in the App Store" under them
once the app has its App Store address, and the device does not reconnect by
itself. Today's Macs refuse no device.

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

## The Mac's menus on the device

The app a device streams keeps its menu bar on the Mac, and the device shows
it: on an iPad with iPadOS 26 or later in the iPad's own menu bar (move the
pointer to the top edge, or swipe down from it), and behind the Menus button in
Sill's bar, between the window thumbnails and Aa (on a phone held upright, at
the end of the thumbnails' row). A window too narrow for the button and a whole
thumbnail beside it (a Slide Over) leaves the button out. With two Sill windows
open, the iPad's menu bar shows none of the Mac's menus, since nothing says
which window's session a choice there would reach; each window's Menus button
still has its own. With the Desktop streaming, the menus are the frontmost
app's, as the Mac's own menu bar shows. Each menu is read from the Mac as it
opens, so what is checked, dimmed or listed (Open Recent, the Window menu) is
what the Mac shows then; an item chosen on the device is chosen on the Mac, as
if clicked there. The Mac's keyboard shortcuts show under the items, as text:
typed on a hardware keyboard they reach the Mac as keys, as before, never the
device's menus. The Apple menu and Sill's own are never shown.

It needs Accessibility for Sill on the Mac, as the device's clicks do; without
it the button shows where to allow it. Opening a menu of a window streamed on
its own makes its app active on the Mac, as a click from the device does, since
an app's menus read differently while it is in the background (Copy, Close and
Minimize dimmed). A Mac from before this change sends no menus, and the device
then shows no Menus button; a device from before it never asks, and the Mac
reads nothing for it. An app that draws its menus in its own window (Blender's
File and Edit) has there only what its menu bar lists; tap the rest in the
picture.

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

### The pure checks

`Tests/checks/run-all.sh` compiles the files that decide things (discovery and
the session's path, the settings ledger, the wire format, pairing, who may use
which door, how frames go into the video encoder and when a stream gets a new
encoder session, the device floor, how a session ends, the update check, the
disk image's window, where everything goes on a phone held upright, the Mac's
menus on both ends) on their own with a check each, and runs them: about two
minutes, no device, permission or encoder. `--mutants` also checks that each
check fails when its file is changed in one place (most of an hour).
`Tests/checks/README.md` lists them. CI (`.github/workflows/ci.yml`) runs them
on every pull request and push to `main`, with `swift build -c release` and the
iOS app's build for the simulator.

### The test client and the relay

`Scripts/sillclient.py PORT [seconds] [desktop|none|window:ID] [flags…]` speaks
the wire format as a device would, and prints what the host sends. For
example, a device's settings change, checked against the host's answer:

```
python3 Scripts/sillclient.py PORT 8 desktop --set=bitrate=25000000@3 --expect=bitrate=25000000
```

Its docstring lists every flag: timed changes and picks, stats as a named
device, the remote door with pairing, the Mac's menus (`--menus`, `--fetch`,
`--press`), and more. It checks every argument
before it connects, and a bad one exits 2. The synthetic hosts do not
advertise over Bonjour, so this client, or the simulator's `-SillConnect`, is
how to reach them; `lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>` finds the port.

`Scripts/sillrelay.py --listen 0 --to HOST:PORT [--delay-ms N] [--rate-mbps R]
[--blackhole-after S] [--record PREFIX]` sits between a client and a host, and
slows or cuts the link. TLS passes through.

### The menus' test app

`Scripts/menufixture.swift` is a small AppKit app with menus of known contents
(marks, shortcuts, a dimmed item, one retitled at every look, a slow action,
submenus three deep, 300 and 600 items) that can never come to the front, and
whose one window is off every display. Signals change its menus the way apps
do: SIGUSR1 and SIGUSR2 give Probe › Rebuilt a new menu, SIGHUP inserts an item
at the top of Probe in place, and SIGALRM gives Probe itself a new menu. A
synthetic host started with `SILL_TEST_MENU_PID=<its pid>` streams the test
pattern with the fixture's menus, so the menus are read and chosen without
touching a real app; the fetches and choices of `sillclient.py` refuse to run
without that variable (a fetch carries the title its menu was shown under, as a
device's does: the host reads a menu only under that title).
`Scripts/menu-check/run.sh` runs the host's menu reader and mirror against the
fixture without a host (it needs Accessibility for whatever runs it). The
file's header says how to build and run it.

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
  landscape and portrait), `500x710` or `710x500` (its outer display), or a
  phone's stream screen (its screen less the status bar: `402x812` for an
  iPhone 18 Pro upright, `440x894` for a Pro Max): a fake screen of that
  size. One larger than the simulator is drawn scaled down to fit, laid out
  at its own size. One that reaches into the simulator's own safe area (a
  phone's whole size on that phone) runs its trackpad past its bottom edge:
  photograph it on a larger simulator, or in the normal app.
- `-SillLive 1`: a real client inside that frame. Otherwise the Mac is a mock,
  and `-SillActive none|desktop|<windowID>` picks what it streams.
- `-SillDrawer 1`, `-SillSettings 1` (with `-SillSettingsCase …` for the
  settings of the mock Mac) and `-SillConnectCase …`: the drawer, the Settings
  panel or the connect screen in a given state.
- `-SillHUD 1`: fps, frame age, round trip and frame size over the stream.
- `-SillConnect 127.0.0.1:PORT`: connect by address, also in the normal app.
  There, and under `-SillLive 1`, `-SillDrawer 1`, `-SillSettings 1` and
  `-SillScaleOpen 1` open theirs 1.5 s after the stream starts.
- `-SillKeyboard 1` brings the software keyboard up in a live session (in the
  mock it only lights the button), and `-SillKeyboardToggle 5,8.5` toggles it
  at those seconds as the Keyboard button does. A simulator shows it only
  with no hardware keyboard connected to it.
- `-SillInputTest 1`, with `-SillConnect` on this Mac's loopback: the portrait
  key row taps cmd, esc, shift and ctrl and the trackpad strokes, taps and
  scrolls, through their own code, once. A synthetic host posts nothing (it
  counts input as `in.dry`), but a real host, Sill.app included, posts it on
  this Mac: point it only at a synthetic host, or put a relay that drops
  input in front of the host.
- The console prints `viewport: 386×241 pt, scale none, 60 fps` for each
  viewport the stream screen sends the Mac.
- `-SillIdiom pad`: a screen taller than wide and narrower than 600 pt is
  drawn as an iPad draws such a window (the compact halves), not as a phone
  does, so an iPhone simulator can photograph it; `phone` the other way
  round.
- `-SillMacMenu code|blender|long|stale|noaccess|none|slow|timeout|refuse`: the
  mock Mac's menus. `-SillMenusOpen 1` opens the Menus pull-down after launch,
  `-SillMenusOpen 'File/Open Recent'` opens it on that menu, and
  `-SillMenuPress 'File/Save'` chooses that item. Live, both act only on the
  test app's menus through a test host (dialled by `-SillConnect` to a loopback
  address, no host version, menufixture's top level) and print "refused"
  otherwise. `-SillMenusAt <s>` opens the pull-down `s` seconds after the
  button shows, and `-SillMenusCloseAfter <s>` closes it `s` seconds later. On
  an iPad, `-SillMenuDump 1` prints the main menu after each build,
  `-SillMenuBarLayout perMenu|replace|one` moves the Mac's menus in it, and
  `-SillSecondWindow 1` opens a second window 2 s after launch (the bar then
  gets none of the Mac's menus).
- The first-run tour, in the mock, under `-SillLive 1` and in the normal app:
  `-SillTourState fresh|landscape|done|skipped|saved` turns the automatic tour
  on (a Debug build never shows it by itself otherwise; `saved` reads and
  writes the real keys, the others last one run), `-SillTour
  touch|bar|settings|laptop` starts it at that step, and the stand-ins
  `-SillTourPress next@S|skip@S`, `-SillTourActivityAt S`, `-SillTakeTourAt S`
  and `-SillTourVoiceOver 1` press, touch, take it from Settings and speak as
  VoiceOver would. `-SillOrientation landscape` turns the normal app sideways
  in a phone simulator. The console's `tour:` lines say what happened;
  ContentView's comment has the whole contract.

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

- Read the host's stats line. `enc.mailboxDrop` counts captured frames the
  encoder had no room for, so `enc.out` well under `cap.complete` with the
  difference in `enc.mailboxDrop` means the encoder takes longer than a frame
  interval. At the Retina Desktop's size that is either its slow state (about
  30 ms a frame, so 33 fps with ~24 drops a second; it can set in after a few
  seconds of few frames, at any bitrate) or another app encoding at the same
  time (a screen recording, the Simulator's recorder, or the Claude app's iOS
  Simulator panel, beside which a Retina Desktop ran at 33–36 fps). The stats
  line can read alike for both: a test-pattern Retina stream beside that panel
  alone read about 32 fps with about 27 drops a second. The kernel's encoder
  log tells them apart (`Scripts/encoder-check/hbparse.py` reads it; its
  header says how to fetch it): while another app shares the encoder, it lists
  that app's session beside Sill's, and hbparse.py marks those windows
  "(shared)"; in the slow state Sill's session is alone. Its C/F column is the
  engine's figure, not Sill's time per frame, and moves with how many frames
  the engine completes in all: about 14 ms in the slow state alone, about 10
  beside the Simulator panel. The host gives a stream in the slow state a new
  encoder session about 2 s into the motion, which runs at the full rate
  again, and says so in its log ("Encoder (hardware HEVC …): frames took 29
  ms each …; a new session takes 9 ms …"); if a new session is no faster
  (another app sharing the encoder, say), the log says that and the stream
  keeps it.
- Resolution: Standard (`captureScale: 1`, four times fewer pixels to encode;
  it never hit the slow state).
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

Distribution (M6): a release is a commit tagged `v` + Packaging/Info.plist's
CFBundleShortVersionString (`v0.4.0` for 0.4.0: bump the version, commit, `git
tag v0.4.0`, `git push origin v0.4.0`), and its GitHub release in
Saffsanity/sill is published (not a draft, not a prerelease) with the
notarized disk image and zip attached; every Sill.app's update check reads
that repository's releases alone and compares the tag with the version it
runs.
`Scripts/release.sh` makes the downloads. It runs `make-app.sh --release`
(which refuses a HEAD without that tag, and any signature but Developer ID),
zips the app, sends it to Apple's notary service and waits, staples the
ticket, zips it again so the download carries the ticket, checks a copy
unpacked from that zip with `stapler validate` and `spctl`, then puts the
stapled app in the disk image (`Scripts/make-dmg.sh`: Sill.app beside a link
to Applications over a background with an arrow, the window laid out by a
`.DS_Store` that `Scripts/dmg-layout` writes without Finder), signs it, has
Apple notarize it too, staples and checks it (`hdiutil verify`, `stapler
validate`, `spctl -t open --context context:primary-signature`, the app
inside), and prints both files' paths and SHA-256. With `--publish` it then
makes the GitHub Release (Sill.dmg, Sill.zip and their `.sha256` files),
and refuses to start unless origin has the tag and it names HEAD (gh would
otherwise make the tag from the default branch); a `SILL_RELEASE_REPO` other
than Saffsanity/sill gets a warning, since no Sill.app offers a release
published there. It needs
`SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'` and
`SILL_NOTARY_PROFILE` (a profile saved with `xcrun notarytool
store-credentials sill-notary`), and refuses to start without them. Give
both on the release command itself, never in your shell profile: `make-app.sh`
signs every build with `SILL_SIGN_IDENTITY` when it is set, `--install`
included. `--dry-run` needs only the identity, makes the zip and a disk image
signed with it, and stops before anything goes to Apple; it builds any
commit, and only warns that HEAD lacks the tag.
`Scripts/make-dmg.sh --sign - .build/Sill.app /tmp/Sill.dmg` makes an ad hoc
image of any build, to look at its window. The window is 660 x 432 points: its
picture (`design/DMGBackground.svg`, 660 x 400, white to every edge) and
macOS 27's 32-point title bar, so the whole picture shows there, with a strip
of white below it under macOS 14's and 15's 28-point bar;
`Tests/checks/dmg-layout` checks the `.DS_Store` and the background's alias
that the layout tool writes.
The one-time setup and each release's steps are in docs/release-checklist.md.
A Developer ID signature has a different designated requirement, so
permissions are granted once more.
The release workflow (`.github/workflows/release.yml`) runs on a pushed tag
`v<version>`: it checks and builds, and with the repository variable
`SILL_SIGN_IN_CI` set to `true` it also signs, notarizes and publishes with
`release.sh --publish` (docs/release-checklist.md, "Releasing from GitHub
Actions"). Its checkout is that tag, so there `--publish` checks the local
tag (`SILL_RELEASE_TAG`) rather than ask origin. Pushing the tag, which a
`--publish` from your Mac needs first, starts it too: with `SILL_SIGN_IN_CI`
on, let that run publish instead. Apple's answers and logs for both
submissions are the run's artifact `notary-v<version>` for 30 days: when the
job's log says a notary log lists issues, read them there.

The iOS app goes to App Store Connect (TestFlight, then the App Store) from
`Scripts/release-ios.sh`: a Release archive signed by Xcode's automatic
signing on team 9B2KKVM937, exported as `.build/ios/export/Sill.ipa` and
checked (the version and build, the export compliance key, the Local Network
and camera strings, the privacy manifest, an App Store signature and
profile), and with `--upload` uploaded. `--bump` gives each upload of a
version the next build number, alone in a commit; both refuse uncommitted
changes, so every uploaded build is a commit's. It signs and uploads
through the Apple Account in Xcode › Settings › Accounts, or through an App
Store Connect API key with the Admin role (`--api-key`, `--api-issuer`),
and it needs Xcode 27.
`--privacy-report` lists what the archive's privacy manifest declares and the
required-reason APIs its binary uses. The TestFlight workflow
(`.github/workflows/testflight.yml`) runs it on GitHub, by hand only.
docs/release-checklist.md, "TestFlight", has the App Store Connect side, the
record field by field.

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

## Layout

- `Sources/`: the Swift package. `StreamProtocol` (the wire format, shared
  with the iOS app), `SillHost` (the host library), `SillHostCLI` (the
  `SillHost` command), `SillMenuBar` (Sill.app) and two probes.
- `iOSClient/`: the iPhone and iPad app, `Sill.xcodeproj`.
- `Packaging/`: Sill.app's Info.plist and entitlements, and the iOS app's
  export options for App Store Connect.
- `Scripts/`: `make-app.sh` (builds Sill.app), `release.sh` (the notarized
  disk image and zip people download), `make-dmg.sh` and `dmg-layout/` (the
  disk image, and the tool that lays out its window), `release-ios.sh` (the
  iOS app's build for App Store Connect and TestFlight), `sillclient.py` (a
  wire-format test client), `sillrelay.py` (a relay that slows or cuts the
  link, for tests), `sillfeed.py` (a stand-in for GitHub's releases feed,
  for the update check's tests), and `menufixture.swift` and `menu-check/`
  (the menus' test app, and the menu reader's checks against it).
- `Tests/checks/`: the pure checks (above). `.github/`: the CI, release and
  TestFlight workflows, and the Sponsor button.
- `site/`: the website, plain HTML for GitHub Pages: home, download, privacy
  policy and support. Preview it with
  `python3 -m http.server 8000 --directory site`.
- `docs/`: the brief, the plans, `app-store-metadata.md` (what App Store
  Connect asks for) and `release-checklist.md` (the order of work for a
  release).
- `design/`: the app icon.
