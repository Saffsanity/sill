# Developing Sill

How to build, run and test Sill from this repository. For help with using
Sill, see the [Support](https://getsill.app/support) page on
[getsill.app](https://getsill.app).

Until 2026-09-25 this was the README, so where a plan in `docs/` mentions "the
README", it means a section here. `CLAUDE.md` has the rest: the work in
progress, the decisions already made, and every test hook.

## Overview

Pipeline: `SCStream (420f) → VTCompressionSession (HEVC, real time, no B-frames)
→ Network.framework TLS 1.3 over TCP + Bonjour → AVSampleBufferDisplayLayer`

- `Sources/StreamProtocol/`: the wire format, shared by both sides. The iOS
  project links this package for it.
- `Sources/SillHost/`: the host itself (the `SillHostCore` library): capture,
  encode, network, input, the virtual display, pairing and remote access.
- `Sources/SillMenuBar/`: Sill.app, the menu bar host. `Sources/SillHostCLI/`:
  `SillHost`, the same host on the command line.
- `Sources/CaptureProbe/` and `Sources/VirtualDisplayProbe/`: tools for
  diagnosis and experiments, not shipped.
- `iOSClient/`: the iPhone and iPad app, `Sill.xcodeproj`.
- `Packaging/`: Sill.app's `Info.plist`, its development and release
  entitlements, and the iOS app's export options for App Store Connect.
  `Scripts/`: `make-app.sh`, and the test tools below. `design/`: the icon, the
  disk image's background and the App Store screenshots (see its README).
  `docs/`: the brief and the plans.

`CLAUDE.md`, Layout, goes through the code file by file.

## Build and run

### Toolchain

`swift build` needs Xcode selected as the developer
directory (`sudo xcode-select -s /Applications/Xcode.app`) with its license
accepted (`sudo xcodebuild -license accept`). With only the Command Line Tools
selected, the default build system fails to start; `swift build -c release
--build-system native` works there as a fallback.

Sill is built with Xcode 27, for macOS 14 or later and iOS 17 or later (the
deployment targets). The iOS app needs Xcode 27.1 or a later 27: it reads the
iPhone Duo's hinge and fold through the iOS 27.1 SDK (`if #available(iOS
27.1, *)`, so it still runs on iOS 17), and built with the 27.0 SDK it would
run on the Duo in a compatibility window, 871×669 and sideways only.

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

`SILL_UNIVERSAL=1 Scripts/make-app.sh` builds a universal Sill.app, arm64 and
x86_64, for someone testing on an Intel Mac (#62): one build per architecture,
each in its own scratch path under `.build/universal`, joined with `lipo`, then
stamped, iconized and signed as usual. It takes about twice as long, and
`.build/release/SillMenuBar` is not refreshed, so it is off by default; unset,
the build is for this Mac's architecture alone. The x86_64 slice has never
streamed on an Intel Mac: until it has, README, the site, the App Store text
and the Homebrew cask's `depends_on arch: :arm64` stay Apple silicon, and
releases stay arm64 (`release.sh` names the architectures it built and checks
every slice's signature). On the Intel Mac, `Sill.app/Contents/MacOS/Sill
--virtual-display-selftest` checks the virtual display (moving the pointer onto
it for a moment) and `--encoder-selftest` the video encoder.

Sill lives in the menu bar: no Dock icon, no window at launch. The menu shows
whether it is visible on the network, each connected device with its frame
rate, frame age, round trip and how it is connected ("Wired", "Wi-Fi" or
"Direct"; from away, "through Tailscale" or "over the internet"), and what is
streaming; it holds the
virtual display, frame rate, quality and resolution controls, Direct Wireless
Connection, Remote Access… and Pair iPhone or iPad… (see Pairing at home and
Remote access below), Launch at Login, Permissions, Show Log… and Settings…
(⌘,). Settings › Devices lists the paired devices, with Require pairing.
Changes apply at once; a change to a streaming setting restarts the current
stream for a moment. Opening Sill.app while it runs (Finder,
Spotlight) shows Settings, which is also where Quit Sill is when the menu bar
has no room for the icon. Settings is as tall as its tab needs, up to its
screen's height between the menu bar and the Dock less 24 pt; a taller tab
scrolls, and a window Sill's own resizing leaves partly off the screen is
moved back on, 12 pt clear of the edge it ran past (issue #59,
docs/settings-window-plan.md: one constraint in `SettingsWindowController`,
its arithmetic in `SettingsWindowFit`, checked by
`Tests/checks/settings-window`).

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
when one has, the menu offers "Sill 0.6 Is Available…" and Settings › General
says so; either opens the release's page on GitHub, where you download it.
Sill never downloads or installs anything by itself, and a failed check is one
line in the log and in Settings, never an alert. The request carries the Mac's
IP address (like any visit to a website), Sill's version in its User-Agent
("Sill/0.5.1"), a fixed `Accept-Language: en` (URLSession would otherwise send
the Mac's languages) and, after a first answer, GitHub's own ETag back
(If-None-Match); nothing else about the Mac or you: no identifier, no cookie,
nothing about your devices. "Check for updates automatically" turns the daily
check off (what an earlier check found stays in the menu); the check reads only
the latest published release of Saffsanity/sill (`UpdatePolicy.feed`),
whichever repository a build came from; should GitHub answer 404 there (no
release, as before v0.3.0), it logs "Update check failed: GitHub has no
release of Sill (HTTP 404)." once a day. It keeps `updateLastCheck`,
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
swift run -c release SillHost --no-clipboard         # share nothing of the clipboard with devices (on by default, as in Sill.app)
swift run -c release SillHost --synthetic            # the Desktop streams a test pattern; no Screen Recording needed
SILL_TEST_PATTERN=picture:/path/to.jpg swift run -c release SillHost --synthetic   # the Desktop a still picture instead (TEST ONLY)
swift run -c release SillHost --remote               # the remote door for this run, on any free port (--remote=PORT)
swift run -c release SillHost --remote --internet    # also admit paired devices from the internet
swift run -c release SillHost --print-reachability   # the addresses a device would get away from home, then exit
swift run -c release SillHost --pairing              # the home door speaks TLS with pairing required, as Sill.app's does
swift run -c release SillHost --print-cable          # what the USB cable rule reads on this Mac, then exit
swift run -c release SillHost --encoder-selftest     # is the hardware encoder alive? 5 s, then it exits
swift run -c release SillHost --virtual-display-selftest   # create and destroy one display, report what sees it
swift run -c release SillHost --menu-selftest=TextEdit     # the menus a device would get for an app (a pid, or its name), read once
```

The argument streams the first on-screen window whose app name or title
contains it (ignoring case), as if a device had picked it; without it nothing
streams until a device picks a window, and the host prints only how many
windows are on screen.

Its home door stays as it always was, plain TCP with no pairing: any device
on your network can connect to `SillHost`, without encryption, so use it only
while developing Sill. `--pairing` gives it Sill.app's door (Pairing at home,
below) with a new identity each run.

A device can change the command-line host's settings from its Settings panel
too; `SillHost` saves nothing, so a change lasts until it quits, and the
device's panel says so. Its Virtual Display switch works only when `SillHost`
runs with `--virtual-display`. `--direct-wireless` starts it with Direct
Wireless Connection on (see Direct Wireless Connection below); it is off by
default here too. The clipboard is shared as in Sill.app (The clipboard,
below); `--no-clipboard` turns it off for the run.

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
Before anything else it checks each private class and selector the display needs,
with its type encoding, against `VirtualDisplay.privateAPISurface`; one missing or
changed fails it, and makes the host stream real windows ("Virtual display
unavailable: …" in the log). The `BOOL` that `applySettings:` returns passes
spelled "B" or "c". An Intel Mac mini with macOS 15.7.3 printed "c" (#87). "B"
on Intel is inferred, not printed: an x86_64 build that took "B" alone passed the
self test on an OpenCore machine with macOS 26.7.1 (#62). Apple silicon with
macOS 27.0.1 reads "B", and "c" under Rosetta.

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
   `StreamProtocol` package (this folder), sets Swift 5 language mode, and
   carries an `Info.plist` with `NSLocalNetworkUsageDescription`,
   `NSBonjourServices = [_sill._tcp]`, the camera text for the pairing scanner
   and the `sill` URL scheme (a pairing link always asks before it pairs).
2. Target → Signing & Capabilities → pick your team. Change the bundle
   identifier if `me.saffer.sill` collides with something (it does on any team
   but the project's own).
3. Run on a real device on the same Wi-Fi (or with Direct Wireless Connection
   on in Sill on the Mac). Tap the Mac's name; the first time, pair it (Pairing
   at home, below). Its row ends in where the device sees it: "Wi-Fi", "Wired"
   (a cable), "Direct", or nothing when it can't tell; "Not paired" before a
   pairing, and "Update Sill" for a Mac whose Sill is too old for this build. A
   "Wired" row connects over the cable, even with Wi-Fi up (should that not
   connect within 2.5 s, over whichever link the device picks); the Settings
   panel's readout ends in the link the connection does take. At home a session
   follows the cable: plugged in, it moves there about 2 s later; pulled, it
   moves to Wi-Fi at once, without the connect screen; dropped by the Mac while
   the cable stays in (Sill away in the background, say), it reconnects over
   the cable. A session from away (Remote access, below) keeps its way in until
   it ends.

When a session ends by itself, the device reconnects: the Mac's row at once,
then, while that row stays listed and nothing answers (a sleeping Mac whose
record an Apple TV or HomePod keeps up as a Bonjour Sleep Proxy, or a Mac whose
Sill is stuck), again 5, 10, 20 and every 30 s after, 12 times at most and only
while Sill is in front. After the third the status line says the Mac may be
asleep, and after the twelfth that it stopped trying. The row listed afresh
(the Mac's Sill relaunched), Sill back from the background, or a tap starts
again. Back from the background the device also makes its Bonjour browser again
(and the nearby one, if it runs), since iOS cuts a suspended app's connection
to mDNSResponder and a browser made before then lists what it saw then; the
rows it had stay up for the new browser's first 3 s, so a Mac that stays listed
never blinks. A Desktop stream that the Mac stops (its capture stopped) is
asked for again by itself, at most once every 10 s.
docs/reconnect-after-sleep-plan.md has the rules;
`iOSClient/DiscoveryPolicy.swift` is them, checked in `Tests/checks/policy`.

The gear at the end of the bar opens Settings: the Mac's streaming settings,
changed from the device, and Disconnect at the bottom. After the Mac's settings
come the device's own: This iPad (or iPhone), with Larger Picture on an iPhone
(below; off unless turned on) and Three-Finger Gestures (below, Trackpad
gestures; on unless turned off), neither ever sent to the Mac, and last Take
the Tour.

On the iPhone Duo (docs/iphone-duo-plan.md) the layout follows the hinge,
which iOS 27.1 reports with the fold's place. Open, Sill is on the inner
display (951×669 sideways, 669×951 upright); while streaming the status bar
hides in every pose, so the picture has the top upright and the full width
sideways; every other screen keeps it. Half folded sideways, the
book pose, the picture runs across the fold, but nothing you touch sits on
it: the thumbnails end short of it, the bar's buttons begin past it, and
the Settings panel, the tour's cards, the window lights, the link's line and
the connect screen stay on one side. Half folded upright, the laptop pose, the picture is above the fold and the bar, the keys
and the trackpad below it, and the connect screen's list scrolls above the
fold; open flat upright, the picture takes its own shape across the width and
the trackpad the rest. Closed, the cover is a phone (below) beside its
camera's strip. Folding moves the session to the other display, and every
layout is what it was on any other device.

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

Larger Picture (Settings › This iPhone, off by default; issue #58,
docs/larger-picture-plan.md) gives a phone held upright more picture while a
window streams: the thumbnails go, and the picture gets every point that keeps
the key row 10 pt above the software keyboard (a room of 424×422 pt on an 18
Pro Max against 424×265; 377×340 on a 15 Pro). The Desktop keeps the usual
arrangement, since Aa never resizes it and the extra height could only be black
under it, and so does the moment nothing streams (Noah's test of 2026-10-15;
`PhonePortraitLayout.largerPicture(switchOn:streaming:)`, from the window
list's source), so a switch between the Desktop and a window changes the
arrangement and sends a new viewport, as a rotation does. The trackpad is then exactly the keyboard's
footprint, so nothing moves when the keyboard comes up. The picture's frame
takes the picture's own shape at the top of that room: a 16:10 window looks as
it did until the Mac fits it to the room (Aa set, or the virtual display),
since the viewport is the whole room. Windows come from Apps (an open app,
tapped again, shows its next window) and from the Mac's Window menu, behind
Menus, which joins row 1 after Apps. The keyboard's height is measured, not
read: `PhonePortraitLayout.keyboardHeight(for:)` gives it from the stream
screen's shape and width (233 pt with a Home button; with Face ID 320 from 414
pt wide, 301 from 390, 310 from 375). The iPhone Duo has no switch: its cover's
keyboard was never measured, so the cover stays as it is. Nor does an iPhone
where it would not make the picture larger: Display Zoom makes an SE, a mini or
a 6.1-inch iPhone 320 pt wide, where the room above the keyboard is shorter
than today's picture and row 1's six buttons would be under 44 pt
(`PhonePortraitLayout.largerPictureGains`). The Apps drawer opens above row 1,
over the picture's room, so neither keyboard covers it, the Mac's or the one
its search field brings. A change of the switch, or of what streams, shows when
the Settings panel closes, so the panel never moves under the finger.

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
needs version 1.2 or later."), with "Update Sill in the App Store" under them,
and the device does not reconnect by itself. Today's Macs refuse no device.

The project is a plain Xcode project checked in by hand: its source files, an
asset catalog, two Info.plists (Info.plist, and Info-Debug.plist for Debug
with the test service type), the privacy manifest `PrivacyInfo.xcprivacy`, and
the package reference. Nothing else. A new source file needs its four
`project.pbxproj` entries added by hand.

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
device, and a streaming setting restarts the stream for a moment. A device away
from home sets the away quality instead (Remote access, below). To put one
setting back to its default, quit Sill, run `defaults delete
me.saffer.sill.mac <key>` (`bitrate`, `maxFPS`, `captureScale`, `awayBitrate`,
`awayCaptureScale`, `prioritizeSpeed`, `virtualDisplay` or `directWireless`)
and open Sill again.

## Windows sized for a device

Without the virtual display, Aa (text size) on the device resizes the window
it streams on the Mac itself, through Accessibility, to the device's panel at
that scale (nothing happens until Aa is first touched; a window in full screen
is not resized: "Window sizing: ‹app› — ‹title› is full screen; not
resizing."). The window goes back to its own frame when it stops streaming:
another window or the Desktop picked, the last device disconnecting (with
several connected, the first to leave changes nothing), the stream stopping
(the window closed, a stream that failed to start), and Sill quitting (Quit,
logout, a `kill` or hangup, and Ctrl-C of `SillHost`). Moved on the Mac
meanwhile, it gets its own size back where it is now, kept on its display;
resized on the Mac after Sill last sized it, or full screen, it is left as it
is (full screen, it keeps the size Sill gave it when it leaves full screen). A
resize on the Mac while it streams, from any edge or corner, is undone by the
next fit within about two seconds, so it does not count, and the window still
goes back to its old place; a move and a resize both made before that fit are
taken as the window's edges show them. A window that enters or leaves full
screen while it streams is off the window list for a second or two: it keeps
streaming through three of the catalog's looks, as a window on the virtual
display does, and goes back at the stop like any other (a pick, Disconnect or
Quit within that second can still leave it at the size Sill gave it). A busy
app that does not answer the size in time is still recorded ("… did not answer
the size in time; if it takes it later, it still goes back."). Turning the
virtual display on while such a window streams stages it with that frame as its
way home. Each window acted on gets one line in the log: "Restored Safari —
Apple Developer to (212,95,1280×800)", "…, its own size where it was moved",
"Left … at (…): it was resized on the Mac", "Left … as it is: it is full
screen", or "Could not restore …" (an app that does not answer Accessibility is
left where it is rather than wait out a second for each write). The frames are
kept in memory only: after a crash or `kill -9` the window stays at the size
Sill gave it. `Sources/SillHost/WindowRestore.swift` is the rule and the
sequences that fit a window and put it back (over `WindowRestore.Access`, which
`WindowSizer.AXWindows` answers through Accessibility), checked in
`Tests/checks/window-restore` against a stand-in Mac;
docs/restore-window-frames-plan.md has the reasons, and The restore probe
(below) checks it against a real window.

## Trackpad gestures

Three fingers on the device's glass, on the portrait trackpad or over the
stream, are the Mac's own trackpad gestures: swipe up for Mission Control, down
for App Exposé, left or right for the Space beside (the content follows the
fingers, as on a Mac), pinch for Apps (Launchpad before macOS 26) and spread for
Show Desktop. The device decides the gesture when one of the three fingers
lifts, from how far they travelled together since they came down (a pinch or a
spread led by the thumb is no swipe, however far the thumb goes), and sends only
its name (kind 28). From the moment three fingers are down, before any has
moved, a stroke clicks, drags and scrolls nothing, however slowly they came and
with a thumb resting on the glass too; three fingers that take longer than
0.15 s to come down decide nothing, and a thumb resting there is not one of
the three.
One- and two-finger strokes are what they always were. The Mac presses its own
keyboard shortcut for that action, as System Settings › Keyboard › Keyboard
Shortcuts has it at that moment (Mission Control, and Launchpad & Dock), so a
shortcut changed there is followed and one turned off does nothing. While a
window streams, a gesture shows the Desktop first, since none of these views is
in a window's picture; the opposite gesture closes what one opened (a swipe
down after Mission Control, a pinch after Show Desktop), until a click, a key or
text from a device, a window picked, an app launched or one of the Mac's menu
items chosen from one, or the last device leaving; a view closed with the Mac's
own keyboard comes back with the same gesture made twice more. Four fingers do
the same where iPadOS lets them through (Settings › Multitasking & Gestures); a
Magic Keyboard trackpad's own three- and four-finger gestures stay with iPadOS.
VoiceOver keeps three-finger gestures for itself, so with it on the rows of
Settings › This iPad do them instead (each row is an accessibility action, for
Voice Control and Switch Control too).

Sill's log names what each gesture did: "Gesture from iPad (iPad14,1): swipe up
→ Mission Control (shortcut 108: key 160, fn)", or "… pinch → nothing: no
shortcut for Show Apps is on in Keyboard Shortcuts", which says which shortcut
to turn on. A Mac from before them gets no gesture, and the device's group says
to update Sill on it. Should a gesture's shortcut leave its modifiers set on
the Mac (a tap after it would be a control-click), the log says "Gestures: after
a gesture's shortcut this Mac's modifier keys still read …" once. A synthetic
host (`SillHost --synthetic`) posts none: it
logs the shortcut it would post with "(not posted: a test host)", so
`python3 Scripts/sillclient.py PORT 8 none --gesture=swipeUp@3` tests the wire
without touching the Mac, and `SILL_TEST_HOTKEYS=108=off` (or `defaults`) gives
such a host a table of its own instead of this Mac's shortcuts.

## A hardware keyboard and trackpad on the device

With a keyboard attached to the iPhone or iPad (a Magic Keyboard, a Smart
Keyboard, a Bluetooth keyboard: whatever GameController counts as one), what is
typed goes to the Mac as soon as the picture shows, without the Keyboard
button: the stream's input view takes the keyboard by itself at a session's
start, after a rotation or a reconnect, and again when the Settings panel, Pair
This iPad…, the first-run tour, the Apps list or the Menus pull-down closes.
While one of those is open its own keys win: Esc closes Settings, skips the tour
or cancels pairing, and nothing reaches the Mac. Each Sill window is its own:
Settings open in one window leaves Esc to the stream in another, and Esc closes
only the panel of the window it was pressed in. When the keyboard goes, the
input view lets go. It draws nothing meanwhile (an empty input view, no
shortcuts bar), so no on-screen keyboard comes up over the stream even where
iPadOS and GameController disagree about the keyboard. The Keyboard button
keeps its meaning for the software keyboard: it lights only when you asked for
it; with a keyboard attached, pressing it brings back iPadOS's own keyboard
views (its small bar, from which the on-screen keyboard can be shown), and
pressing it again takes them down while keys still reach the Mac. That
automatic hold is not yours, so the first-run tour still shows to someone with
a keyboard. `iOSClient/HardwareKeyboardPolicy.swift` is the rule, checked in
`Tests/checks/hardware-keyboard`; docs/hardware-keyboard-plan.md has the rest.

Esc reaches the Mac from `pressesBegan`, as every other key, and also through key
commands for Esc with each combination of ⌃, ⌥, ⇧ and ⌘ that ask for priority
over iPadOS's text and focus systems, since an iPad has been seen keeping a
hardware Escape from `pressesBegan` (#67). One key press goes out once,
whichever channel brings it (`ForwardedKeys`). Debug builds print a line for
every hardware key the input view sees and how it came, `hwkey: usage 41 down
via keyCommand (shift): to the Mac`, and `-SillKeyProbe 1` adds GameController's
own view of each key. Control-[ reaches the Mac as Control plus the [ key,
which iTerm2, zsh's vi mode and Zed's vim mode take as Escape. Return and Tab
with Shift held reach the Mac as keys carrying it, so Shift-Return starts a new
line in a chat box that sends on Return, and Shift-Tab moves focus back
(`ForwardedKeys.shiftedKeyUsages`); alone they go through iPadOS's text system,
as every typed character does. The key row's shift, latched, does the same for
the on-screen keyboard's return and tab.

Over the picture, two fingers on a Magic Keyboard's trackpad (or a Magic
Trackpad or Magic Mouse) scroll the window under the pointer as a finger does,
with the same coast after a flick, and a mouse's wheel scrolls it in plain
steps. Clicks and drags with the trackpad were already the pointer's. Over the
portrait layout's on-screen trackpad a hardware trackpad's scroll does nothing.

On a device so far: the iPad mini with the Mac's keyboard and trackpad reaching
it through Universal Control (2026-10-15, the plan's Results): the automatic
hold, letters, Esc (through `pressesBegan`), ⌘W and two-finger scrolling all
reached the Mac, and Esc closed Settings without reaching it. A Magic Keyboard
itself, and which channel brings its Esc, are still untested.

## The clipboard

Text goes both ways between the Mac and a device (kind 32; the plan and its
results are in docs/clipboard-plan.md). On the Mac, Settings › General's "Share
clipboard with devices" (saved as `shareClipboard`, on by default, applied at
once; `-SillSetAfter '<s> shareClipboard=0'` in the bare app) and the CLI's
`--no-clipboard`; on the device, Settings › This iPad's Share Clipboard
(`Sill.shareClipboard`, on by default), shown while the Mac's window list says
`clipboard` 1. With both on, the device subscribes with an empty kind 32 and
the Mac sends it the text copied on the Mac while it is subscribed, four looks
a second at the pasteboard's change count. What was on the clipboard when the
first device subscribed is never sent, nor anything a password manager or
another app marks `org.nspasteboard.ConcealedType` or
`org.nspasteboard.TransientType` (or three older markers: ClipboardPolicy's
`markerTypes`), nor what came from another device through Universal Clipboard
(`com.apple.is-remote-clipboard`: reading it would fetch it from there), nor
the Mac's own write; a pasteboard with no items yet is looked at again for up
to a second (an app clears it, then writes, and only the clear moves the
count). The host reads and writes the pasteboard on a queue of its own, never
on the main actor. The device writes the Mac's text with
`.localOnly` and a 10-minute expiration. The other way, Sill never reads the
device's clipboard by itself (iOS would ask "Allow Paste?"): when it becomes
active and the clipboard's change count is new while it holds text, a chip
near the bar offers "Paste on ‹Mac›" with the system's Paste control
(UIPasteControl), whose tap reads it without asking; the Settings group has the
same button. The Mac writes it for this Mac only (`.currentHostOnly`), marked
with its launch ID so it never sends it back, and passes it to its other
subscribers; the person presses ⌘V. The device says "Sent to ‹Mac›’s
clipboard" only once the Mac has read it: a ping with a 16-byte random payload
goes after the text through the same door, and its pong is the receipt (the Mac
echoes a ping only after reading all before it); none within max(4 s, 4 × the
worst round trip) says "Didn’t reach ‹Mac›. Try Paste again." and offers the
chip again. The chip's 20 s run only while it is on screen with Sill active,
never under VoiceOver, and VoiceOver is told when it first shows. Text is capped
at 256 KB. A device's subscriptions and texts are limited to four a second; its
stop never is. The log says "Clipboard: iPad (iPad14,1) shares the clipboard."
and "… stopped sharing the clipboard." and nothing per copy, never what was
copied; the stats line has `clip.sent` and `clip.recv` in seconds they happen.

macOS 15.4 and later can ask before an app reads the clipboard on its own
(NSPasteboard's `accessBehavior`; System Settings › Privacy & Security › Paste
from Other Apps). Sill for Mac reads the pasteboard only while macOS allows
every read: while it would ask (its alert at every copy) or denies, the look
reads nothing, what is copied meanwhile is never sent, the log says so once,
and Settings › General says why under the switch, with "Allow in System
Settings…" (which, while macOS has not asked about Sill yet, makes one read on
that click so macOS asks and lists Sill there). A device's text is still
written. To try it with Sill.app: `defaults write me.saffer.sill.mac
EnablePasteboardPrivacyDeveloperPreview -bool yes`, relaunch Sill, and
`defaults delete me.saffer.sill.mac EnablePasteboardPrivacyDeveloperPreview`
after.

A synthetic host never touches this Mac's clipboard: it shares a pasteboard of
its own, `me.saffer.sill.test.<pid>`, or the one TEST ONLY
`SILL_TEST_PASTEBOARD=<name>` names, which a test writes and reads with
`NSPasteboard(name:)`; `SILL_TEST_CLIPBOARD_LOG=1` prints each decision ("change
4 not sent (marked)") with sizes, never text; `SILL_TEST_CLIPBOARD_ACCESS` gives
its pasteboard macOS's answer (`allowed`, `notAsked`, `asks`, `denied`, or the
path of a file holding one, read at each look). `sillclient.py --clipboard`
subscribes and prints each kind 32, `--copy=TEXT@T` (or `--copy-bytes=N@T`)
sends text as a device's Paste does, `--raw32='{"stop":true}@T'` stops, and
`--expect=clipboard=TEXT` (or `none`) checks the last one at exit. In the
harness, `-SillClipboardChip 1` puts the chip on the mock's stream and
`-SillClipboardNote sent|long|notsent` its note; `-Sill.shareClipboard 0` turns
the device's switch off for one run. Live against a synthetic host on loopback,
`-SillSettingsScript '3 paste TEXT'` sends TEXT as the Paste control hands it
over (the receipt and its note included; through `sillrelay.py
--blackhole-after S` it never comes), and `-SillSettings 1 -SillSettingsCloseAt
<s>` holds the Settings panel over the chip until then; the console's
"clipboard: …" lines say what happened.

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
on, anyone nearby running Sill can find the Mac and ask to pair, which opens
its pairing window (at most three times in ten minutes); only devices you
paired connect, unless Require pairing is off (Pairing at home, below).
Turning Wi-Fi off in Control Center does not end a direct connection (it
leaves the radio on for AirDrop); Settings › Wi-Fi does.

## Pairing at home

Sill.app's home door speaks TLS 1.3 with each end pinned to the other's key,
as Remote Access does, and one list of paired devices serves both: a device
paired at home connects nearby and, with Remote Access on, from away, and one
paired for Remote Access connects at home with no further step.

- **On the same network, or nearby with Direct Wireless Connection:** a Mac
  this device has not paired with reads "Not paired". Tap it: the Mac opens
  its pairing window by itself, in front of what you are doing but without
  taking the keyboard, and the device opens its camera. Point it at the QR
  code, or choose Enter Code Instead and type the 12 digits. Cancel on the Mac
  closes a window you did not ask for. A Mac opens at most three such windows
  in ten minutes, and none for ten minutes to a device after you click Cancel
  on the Mac or after five wrong codes; the device then says to choose Pair
  iPhone or iPad… in the Sill menu, which always works. A locked Mac shows no
  code ("Unlock Mac mini, then tap it again."), and an ask from the Mac itself
  (the Simulator, another app) never opens a window: pair those with Pair
  iPhone or iPad….
- **Over the USB cable:** an unpaired iPhone or iPad on the Mac's cable reads
  "Wired". Tap it, and while the Mac is unlocked it pairs by itself, with no
  code; the Mac shows a notice with Remove for ten seconds. Both ends check
  that the connection really is the cable (the Mac: an IPv6 link-local source
  under the iPhone's or iPad's own USB interface, never an address of the Mac
  itself; the device: an interface with nothing but link-local addresses), so
  a USB Ethernet adapter, or an iPhone sharing its connection over USB, gets
  the code window instead. One key per iPhone or iPad pairs this way: another
  key of the same device (another app, say) gets the code window until the
  first is removed.
- **Settings › Devices** on the Mac lists the paired devices, how each paired
  and when and how it last connected, with Remove (the device can no longer
  connect: "Mac mini removed this iPad. Tap it to pair again.") and rename
  (double-click). **Require pairing** is on by default. Off, any device at
  home, and any app on the Mac, connects without pairing, still encrypted;
  turned on again, it disconnects the devices that are not paired ("Mac mini
  now asks devices to pair."). Sill keeps it beside the paired devices in the
  keychain, not in its defaults: in the data-protection keychain in the Sill
  for Mac you download (0.4.0 and later), and in the login keychain in a
  Sill.app you build yourself without the Developer ID provisioning profile.
- **Older builds:** a device from before pairing at home dials the home door
  without TLS and can no longer connect to this Sill.app; the menu says "An
  iPhone or iPad Needs Sill Updated". Update the device first, then the Mac. A
  Release build of the iPhone and iPad app never connects without TLS ("Update
  Sill" on the row of a Mac with an older Sill); a Debug build still dials an
  older Sill.app's plain door until it has seen that Mac speak TLS (launch it
  once with `-SillForgetHomeTLS 1` to forget).
- **The command-line host** keeps its plain, open door (The command-line host,
  above). With `--pairing` it prints its code and link in Terminal, and again
  after each device's ask; `--print-cable` prints what the cable rule reads on
  each interface and exits.
- **To start over:** remove the device in Settings › Devices, or on the device
  touch and hold the Mac's row and choose Forget. The Sill for Mac you download
  (0.4.0 and later) keeps the paired devices, Require pairing's setting and the
  Mac's key in the data-protection keychain, under its own access group, not in
  the login keychain; remove devices in Settings › Devices. A Sill.app you build
  yourself without the Developer ID provisioning profile keeps them in Keychain
  Access › login (the key "Sill Remote Access" and the passwords of service
  `me.saffer.sill.remote`); deleting those makes that build new to every
  device, and every device pairs again. The two keychains are separate, so
  switching between the download and a build of your own also changes the
  Mac's key.

## Remote access (away from home)

Sill reaches your Mac from anywhere through a VPN you already run, or through a
port forward on your router. There is no Sill server: the iPhone or iPad dials
the Mac itself. It is off until you turn it on, and only devices you paired can
connect (TLS 1.3, each end pinned to the other's key).

1. On the Mac: Sill › Settings › Remote Access, turn on Remote access. Sill
   listens on TCP port 7455 (Change… picks another) and lists the addresses a
   device will use: your Tailscale address and its MagicDNS name, another VPN,
   this network's address.
2. Pair each device once, at home or away (a device already paired at home is
   paired for this too): Pair iPhone or iPad… in the Sill menu shows a QR code
   and a 12-digit code for five minutes. On the device, tap Add a Mac… at the
   bottom of the connect screen and point it at the code, or choose Enter Code
   Instead and type the address and the code the window shows. With Tailscale,
   the address is the Mac's MagicDNS name or the Tailscale IP address under it;
   otherwise it is this network's address, with another VPN's address under it
   when the Mac runs one. A device connected at home without pairing (Require
   pairing off) can use Pair This iPad… in the Away from home group of its
   Settings panel instead: it asks the Mac for a code, as a tap on a "Not
   paired" row does.
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
  Devices); pair it again.

Away from home has its own quality (docs/remote-bundle-plan.md). While every
connected device is away, through a VPN or over the internet, the Mac streams
at the away quality, Low at Standard resolution until you change it, and its
log says "Away from home: …"; a device at home connected at the same time
brings the home quality back for every device ("Home quality again: …"). A
device away that picks a Quality or Resolution sets the away pair, never the
home one; Sill.app saves both (`awayBitrate` and `awayCaptureScale` beside
`bitrate` and `captureScale`), Settings › Streaming shows both, and the menu's
Quality says "Away from home now: …" while the away pair runs. The device's
Settings panel says which runs ("Away: Low · Standard"). A device away also
asks for 60 fps even if its screen shows 120, which halves what the Mac sends.

When the link cannot carry the quality (the Mac held frames back in three
seconds of five), the Mac says so in its log ("Link to iPad …: cannot carry Pro
…") and on the device's row in its menu, and tells the device, whose Settings
panel offers a quality that fits in 70 % of what the link carried, with a
button; a line over the picture says the same while the panel is closed. Every
device is judged, at home too. From a Mac too old to judge the link, the panel
suggests Low or Standard resolution when the round trip stays over 250 ms, as
before.

Coming home: a session through the remote door moves to the home network by
itself about 2 s after the network lists the Mac, by the same make-before-break
hand-over as a move off Direct Wireless, and the Mac goes back to the home
quality in one restart. It dials the home door over TLS, pinned to the Mac's
key the session already trusts, never plain: a Mac whose home door is plain (a
Sill for Mac from before 0.4.0, the CLI without `--pairing`), one that removed
this device or one to pair with again keeps the session remote. It chooses
among the rows carrying the Mac's tag one by one: a row that turns out not to
be the Mac (another key, another launch) is not dialed again while it is
listed, and the Mac's own row is still tried. A session made with Connect
Remotely stays remote.

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
me.saffer.sill.mac $k; done`. The downloaded Sill for Mac (0.4.0 and later)
keeps the Mac's identity, its paired devices and Require pairing in the
data-protection keychain, not the login keychain: remove devices in Settings ›
Devices. A Sill.app you build yourself without the Developer ID provisioning
profile keeps them in Keychain Access › login: the key "Sill Remote Access" and
the passwords of service `me.saffer.sill.remote`. Deleting those makes that
build new to every device, which must pair again. On the device, a paired
Mac's row has Forget in its menu (touch and hold).

## Test tools

None of these needs a device. `CLAUDE.md`, Build and run, has the complete
list, with the test-only environment variables and the recipes for headless
tests of Direct Wireless Connection and remote access.

### The pure checks

`Tests/checks/run-all.sh` compiles the files that decide things (discovery and
the session's path, the settings ledger, the wire format, pairing, who may use
which door, how frames go into the video encoder and when a stream gets a new
encoder session, the device floor, how a session ends, how the device reads the
Mac's messages, the update check, the disk image's window, where everything goes
on a phone held upright, who moves the Mac's pointer, the Mac's menus on both
ends, which three-finger strokes are gestures and what the Mac does with one,
which modifiers a device's keys leave set on the Mac,
the first-run tour, pairing at home (the doors, the cable, the device's rows),
which keychain Sill.app keeps its identity in, the away quality and the link's
judgement, the iPhone Duo's layouts, what of the clipboard goes between the Mac
and a device, and which type encodings the virtual display's private API may
report) on their own with a check each, and
runs them: about five minutes, no device, permission or encoder. `--mutants`
also checks that each check fails when its file is changed in one place (well
over an hour).
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

Input (`--move`, `--tap`, `--key`, `--input`) goes only to a `--synthetic` host
on this Mac, which posts nothing. With `SILL_TEST_INPUT_LOG=1` such a host
prints each event it would have posted, a key with its flags and a click with
the modifiers the last key would have left for it and where it goes, and the
check each key's up arms (`KeyUpCheck`, read on a real host a quarter of a
second later), so what a device's keys and buttons leave behind (the Spotlight
key's ⌘, a modifier held when a device leaves or the host stops, a button
whose stream stopped under a drag) can be seen without touching the Mac:

```
SILL_TEST_INPUT_LOG=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic
python3 Scripts/sillclient.py PORT 3 desktop --input='{"key":{"hidUsage":44,"down":true,"modifiers":1048576}}@1' \
    --input='{"key":{"hidUsage":44,"down":false,"modifiers":1048576}}@1.05' --tap=0.5,0.5@1.5
```

(`$T/path` holds one line, `0 756 474`: the scripted pointer gives the test
pattern a place for input to land.) `--gesture=NAME[,FINGERS]@T` sends a
trackpad gesture (kind 28), and, like the input flags, only to a `--synthetic`
host on this Mac, which posts nothing. The clipboard's flags (`--clipboard`,
`--copy`, `--copy-bytes`, `--raw32`, `--expect=clipboard=`) are under The
clipboard, above: with `SILL_TEST_PASTEBOARD` the host's pasteboard is a
private one, never this Mac's clipboard.

`Scripts/sillrelay.py --listen 0 --to HOST:PORT [--delay-ms N] [--rate-mbps R]
[--blackhole-after S] [--record PREFIX]` sits between a client and a host, and
slows or cuts the link. TLS passes through.

### The pacing harness

`Scripts/pacing/run.sh` measures how the host paces a session away from home,
this tree's StreamServer.swift against origin/main's (`--base REF` for
another), with no encoder, Screen Recording or device: the host fed fake frames
of chosen sizes, a shaped path (a rate, a delay, a queue, a dip, a dead path)
and a stand-in device that reads, pings and judges liveness as the app does,
all on 127.0.0.1. It prints each case against its gate
(docs/remote-bundle-plan.md §11), and the link's gates from what this tree's
host judged of each device's link ("Link: behind …" in its log): about 25
minutes, `--full` about 45, and it waits while the Mac is busy (a load average
of 20 or more), since a busy Mac makes a stalled path of any link. `--list`
shows the cases.

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

### The restore probe

`Scripts/restore-probe/run.sh` checks that a window Sill sized goes back, with
the real `WindowSizer.resize` and the restore the host runs, against a window
of its own (`owner.swift`, in a bundle that never comes to the front, at the
lower left behind every other window): fourteen steps (a stop, a rotation's
re-fit, moved, moved then re-fitted, resized, an app's minimum, a window that
closes, the nudge at a display's edge, a window that cannot be resized, an app
that does not answer, the virtual display's way home worked out without a
display, two windows, an app stopped with `SIGSTOP` during a fit so its size
goes unanswered and lands once it runs again, and the left edge dragged in
before a re-fit), each frame before, during and after, in about 35 s. It
touches no other window, posts no input and makes no virtual display, and the
front app must not change. It needs Accessibility and Screen Recording for the
terminal, and an unlocked screen: while the screen is locked the window server
shows a new window transformed and Accessibility lists none, so it says so and
exits 2.

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
- The Settings window on a short screen (issue #59):
  `-SillSettingsAfter '<s> <tab>[; <s> <tab> …]'` opens Settings on that tab
  (its name or the start of one: `remote`, `general`, `virtual`) s seconds
  after launch, as the menu does, and 0.6 s later prints the window's frame,
  the pane's whole height and how much of it shows ("shows 596 of 909,
  scrolls"), the visible frame it fits in and the cap. A step can also be
  `close`, `report` (print the window as it stands), `end` (scroll the pane
  to its last row) or `height=<points>`
  (as `-SillTestScreenHeight`, `0` for the screen's own, then the screens'
  change is posted as the Dock or a display would). `-SillTestScreenHeight
  <points>` makes the window fit the top `<points>` of the screen's visible
  frame, as if the screen were that short with the Dock at its bottom, and
  `-SillSettingsShot <dir>` writes each step's window (title bar, toolbar and
  pane) to `<dir>/settings-<s>s-<tab>.png`. The window's frame is saved in
  the `SillMenuBar` domain (`NSWindow Frame SillSettings`); a launch argument
  of that name places it for one run. For example:

  ```
  SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 \
    .build/release/SillMenuBar --synthetic -SillTestScreenHeight 700 \
    -SillSettingsAfter '2 general; 4 remote; 6 height=500; 8 height=0' -SillQuitAfter 10
  ```

Sill.app itself ignores every `-Sill…After` argument, `-SillTestScreenHeight`,
`-SillSettingsShot` and `-requirePairing`, with one line each.

`--encoder-selftest` and `--virtual-display-selftest` work in the app too.

### The iOS debug harness

Debug builds of the iOS app take launch arguments that set up a screen in the
simulator:

- `-SillLayout 951x669` or `669x951` (the inner display of iPhone Duo, in
  landscape and portrait), `466x678` or `678x466` (its cover), or a phone's
  stream screen (its screen less the status bar: `402x812` for an iPhone 18
  Pro upright, `440x894` for a Pro Max): a fake screen of that size. The
  Duo's four sizes have the safe area that display gives Sill (the home
  indicator's 34; on the inner display the status bar's strip, 84 pt at the
  right sideways and 82 at the top upright, but on the stream screen with
  `-SillHinge half` or `flat`, upright or sideways, which hides it; on the
  cover its camera's 84 pt strip, at the right upright and the left on its
  side);
  `-SillSafeArea T,L,B,R` sets another.
  The first guesses, `1000x710`, `710x1000`, `500x710` and `710x500`, still
  work, with none. One larger than the simulator is drawn scaled down to fit,
  laid out at its own size. One that reaches into the simulator's own safe
  area (a phone's whole size on that phone) runs its trackpad past its bottom
  edge: photograph it on a larger simulator, or in the normal app.
- `-SillHinge half|flat|closed` stands in for the Duo's hinge and fold (a
  40 pt band across the middle of the fake screen's longer side): `half` is
  the book pose sideways and the laptop pose upright. Without it the harness
  knows no hinge, even on the Duo's simulator. To fold and turn that
  simulator itself, `Tests/duorig/run.sh UDID pose book` (or `laptop`,
  `flat-portrait`, `flat-landscape`, `closed-upright`, `closed-side`) and
  `run.sh UDID shot <pose> FILE.png` (TEST ONLY: Device Hub's own events,
  posted inside the simulator; its README).
- `-SillLive 1`: a real client inside that frame. Otherwise the Mac is a mock,
  and `-SillActive none|desktop|<windowID>` picks what it streams.
- `-SillDrawer 1`, `-SillSettings 1` (with `-SillSettingsCase …` for the
  settings of the mock Mac) and `-SillConnectCase …`: the drawer, the Settings
  panel or the connect screen in a given state.
- `-SillHUD 1`: fps, frame age, round trip and frame size over the stream.
- `-SillBrowserFail N` (the normal app and `-SillLive 1`): each of the first N
  network browsers is reported failed as iOS reports a suspended app's
  (-65569), so the device makes it again after 1, 2, 4… s; the simulator's
  browsers use this Mac's own mDNSResponder, which never cuts them. Sending the
  app to the background and back (`xcrun simctl launch <udid>
  com.apple.Preferences`, then `xcrun simctl launch <udid> me.saffer.sill`)
  makes the network browser again, and the nearby one if it runs. The console
  says "browser: …", and the automatic reconnect's dials "reconnect: …".
  `-SillConnectCase asleep` shows the connect screen's line after three dials
  that did not connect.
- `-SillConnect 127.0.0.1:PORT`: connect by address, also in the normal app.
  There, and under `-SillLive 1`, `-SillDrawer 1`, `-SillSettings 1` and
  `-SillScaleOpen 1` open theirs 1.5 s after the stream starts.
  `-SillDrawerSearch <text>` makes the open drawer search for that text with
  the keyboard up for its field.
- `-SillKeyboard 1` brings the software keyboard up in a live session (in the
  mock it only lights the button), and `-SillKeyboardToggle 5,8.5` toggles it
  at those seconds as the Keyboard button does. A simulator shows it only
  while UIKit there counts no hardware keyboard: a fresh one (keys from
  `Tests/keyrig` make it count one for good).
- `-SillHardwareKeyboard 1` or `0`: a hardware keyboard attached, or not, for
  the run, whatever GameController says. A simulator's GameController always
  counts the simulator's own keyboard, so the input view takes the keyboard by
  itself there unless this says `0` (it draws nothing either way). The console
  prints `keyboard: …` for what the rule does and `hwkey: …` for every key.
  `-SillKeyProbe 1` adds GameController's own view of each key,
  `-SillEscViaCommand 1` hands Esc on from `pressesBegan` so its key commands
  take it, and `-SillTurnAt 6,12` turns an iPhone's scene at those seconds.
- `-SillInputTest 1`, with `-SillConnect` on this Mac's loopback: the portrait
  key row taps cmd, esc, shift and ctrl and the trackpad strokes, taps and
  scrolls, through their own code, once; in every layout the stream's input
  view then sends Esc and ⇧Esc through its key command, a trackpad's scroll
  with its coast and a wheel's. A synthetic host posts nothing (it
  counts input as `in.dry`), but a real host, Sill.app included, posts it on
  this Mac: point it only at a synthetic host, or put a relay that drops
  input in front of the host.
- The console prints `viewport: 386×241 pt, scale none, 60 fps` for each
  viewport the stream screen sends the Mac, and on a phone held upright
  `trackpad: 412×389 pt, vertical span 257.5 pt` when the pad or its span
  changes and `keyboard: up, 320 pt tall, its top at 574 pt in the stream
  screen; the key row ends 10 pt above it, …` once the keyboard has moved.
- Larger Picture: `-Sill.largerPicture 1` turns the device's switch on for
  one run (in the normal app too); it acts while a window streams, which the
  mock does unless `-SillActive desktop` (or `none`) says otherwise, and the
  console's `larger picture: the switch on, the Desktop streams: the standard
  arrangement` says what the rule made of the switch and the source;
  `-SillVideoSize 848x844` gives the mock's
  frame another shape, so the harness draws a window the Mac fitted to the
  picture's room (2800x1800 otherwise); `-SillLargerPictureToggle 4,8`
  switches it at those seconds as the panel's switch does (leave out
  `-Sill.largerPicture`, which would hold it).
- `-SillAXDump <s>`: `s` seconds after the stream screen shows, the console
  lists its accessibility elements in the order the tree hands them to
  VoiceOver. SwiftUI builds that tree only for an assistive technology, so on
  a private simulator first `xcrun simctl spawn UDID defaults write
  com.apple.Accessibility ApplicationAccessibilityEnabled -bool true`.
- `-SillIdiom pad`: a screen taller than wide and narrower than 600 pt is
  drawn as an iPad draws such a window (the compact halves), not as a phone
  does, so an iPhone simulator can photograph it; `phone` the other way
  round.
- Pairing at home: `-SillServiceType _silltest._tcp` (only test hosts
  registered under that type are rows), `-SillHomeDoor paired|open|plain`
  (what a `-SillConnect` address counts as), `-SillCableTest 1` (this
  device's path counts as the cable) and the connect screen's `home…` cases;
  `CLAUDE.md`, Build and run, has them all.
- `-Sill.trackpadGestures 0` turns the device's Three-Finger Gestures off for
  one run, `-SillSettingsScroll gestures` opens the Settings panel at that
  group, and `-SillVoiceOver 1` shows it as with VoiceOver on. Under `-SillLive 1`, `-SillInputScript '3 gesture swipeUp'` sends a
  gesture through the app's own path, only to a test host on this Mac.
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
- Away from home and the link: `-SillSettingsCase away`, `awaymixed`,
  `awayhome`, `linkbehind`, `linkmixed`, `linklow` or `linkstalled` (the
  Settings panel's header, callout and footnote in each case), and
  `-SillLinkLine behind` (the line over the stream). In a live session,
  `-SillSettingsScript '3 set bitrate=15000000; 20 suggestion'` changes a
  setting, or takes the link callout's button, at those seconds after the
  first window list, only against a synthetic host on this Mac's loopback;
  `-SillMoveHomeTest to:HOST:PORT` (with `-SillDialSaved 1`) lists the saved
  Mac on the network a second into a remote session, at a home door that
  speaks TLS, so the move home runs against a synthetic host with `--remote
  --pairing` (dialed pinned to the saved Mac's key, never plain), and
  `-SillDialSaved remotely` dials it as Connect Remotely does. `CLAUDE.md`,
  Build and run, has the host side (`SILL_TEST_REMOTE_ORIGIN`,
  `SILL_TEST_PATTERN=noise`).

### The touch rig

`Tests/touchrig/run.sh NAME` compiles the real `TrackpadView.swift` and
`InputOverlay.swift` into a scratch app for the iOS simulator, drives both
surfaces with synthesized one- to five-finger touches, and logs every event
each would send the Mac (nothing leaves the app). `--rev REV` builds the
surfaces as they are at REV, and `Tests/touchrig/compare.py BASE.log NEW.log
[OFF.log]` checks that one- and two-finger strokes send what they sent before
(and the same right after a gesture as made fresh) and that each stroke of three
or more fingers, placed slowly, beside a resting thumb or with a brief extra
contact too, sends its one gesture, or nothing, and nothing else. It runs on
a simulator of its own (`SILL_TOUCHRIG_SIM`, made and deleted when missing),
never XCUITest or a recording.

### The key rig

`Tests/keyrig/run.sh UDID keys 29,04,e3:down,1a,e3:up` presses Esc, A and ⌘W on
a hardware keyboard inside a simulator, and `run.sh UDID point 'move
300,200|wheel -3'` moves a mouse's pointer and turns its wheel (TEST ONLY:
private interfaces, posted inside the simulator from a virtual HID device of its
own, as the Duo rig does; never on the Mac). UIKit routes them as a real
keyboard's and mouse's, so the stream's input view, its key commands, the
tour's and the Settings panel's Esc and the wheel's pan run as on a device.
With `SillHost --synthetic` and `SILL_TEST_INPUT_LOG=1` (and
`SILL_TEST_POINTER_PATH`, without which a test host's Desktop takes no input)
the host prints what each key would post. Only on a simulator of your own:
after its keys, UIKit there counts a hardware keyboard for good. Its README
has what it showed.

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

Distribution: a release is a commit tagged `v` + the version both apps carry,
set together since 0.5.1 (Packaging/Info.plist's CFBundleShortVersionString
and the iOS project's MARKETING_VERSION in both configurations; `v0.5.1` for
0.5.1: bump both, commit, `git tag v0.5.1`, `git push origin v0.5.1`), and its
GitHub release in Saffsanity/sill is published (not a draft, not a prerelease)
with the notarized disk image and zip attached; every Sill.app's update check
reads that repository's releases alone and compares the tag with the version
it runs.
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
`make-app.sh --release` embeds `Packaging/embedded.provisionprofile` (the
Developer ID provisioning profile, git-ignored) and signs with
`Packaging/SillRelease.entitlements`, so Sill keeps its key and paired devices
in the data-protection keychain, as 0.4.0 and later do; without the profile it
builds on the login keychain and says so, and a Mac updating from 0.4.0 or
later would get a new key and pair every device again
(docs/release-checklist.md, Part 1 §5).
The release workflow (`.github/workflows/release.yml`) runs on a pushed tag
`v<version>`: it checks and builds, and with the repository variable
`SILL_SIGN_IN_CI` set to `true` it also signs, notarizes and publishes with
`release.sh --publish` (docs/release-checklist.md, "Releasing from GitHub
Actions"). Its checkout is that tag, so there `--publish` checks the local
tag (`SILL_RELEASE_TAG`) rather than ask origin. Pushing the tag, which a
`--publish` from your Mac needs first, starts it too. The release workflow has
no profile yet, so publish from your Mac with `release.sh --publish` and leave
`SILL_SIGN_IN_CI` off until the workflow gets one. Apple's answers and logs for
both submissions are the run's artifact `notary-v<version>` for 30 days: when
the job's log says a notary log lists issues, read them there.

Homebrew: Sill for Mac is also the cask `sill` in Sill's own tap,
[Saffsanity/homebrew-sill](https://github.com/Saffsanity/homebrew-sill), so
`brew install --cask saffsanity/sill/sill` installs it (that command taps
the repository and trusts the one cask, which Homebrew 6 and later need for a
tap that isn't Homebrew's own). The cask names the release's `Sill.dmg` by
its version and SHA-256, so each release bumps it once it is published
(docs/release-checklist.md, part 2), and the tap's `brew test-bot` workflow
checks every pull request, downloading the image. It moves to Homebrew's main
repository once it qualifies (docs/release-checklist.md, part 1 §6). On a Mac
where Sill.app runs from /Applications, try the cask only with `brew install
--cask --appdir=<a scratch folder>`, and never `brew uninstall --zap`, which
trashes the running Sill's settings and log.

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
and it needs Xcode 27.1 or a later 27 (the iOS 27.1 SDK the iPhone Duo's
layouts need: the app it checks must say it was built with it).
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
- A window Sill sized for a device goes back when it stops streaming, but not
  after a crash or `kill -9`: the frames are kept in memory only.
- Single window at a time. Every connection runs over TLS 1.3 to paired
  devices only (with Require pairing off, to any device at home, still
  encrypted); only the command-line host without `--pairing` keeps a plain,
  open home door. The device reconnects by itself when the Mac drops it (The
  iOS app, above). Whether its dials wake a Mac asleep behind a Bonjour Sleep
  Proxy (an Apple TV or HomePod, with Wake for network access on) is
  untested; from away they cannot (Remote access, above).
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
  for the update check's tests), `pacing/` (the pacing harness, above),
  `menufixture.swift` and `menu-check/` (the menus' test app, and the menu
  reader's checks against it), and `restore-probe/` (a window Sill sized goes
  back, against a window of its own, above).
- `Tests/checks/`: the pure checks (above). `Tests/touchrig/`: the touch rig
  (above). `Tests/duorig/`: folds and turns the iPhone Duo simulator (TEST
  ONLY, above). `Tests/keyrig/`: a hardware keyboard and mouse for the
  simulator (TEST ONLY, above). `.github/`: the CI, release and TestFlight workflows, and the
  Sponsor button.
- `site/`: the website, plain HTML for GitHub Pages: home, download, privacy
  policy, terms of service and support, with the App Store badge
  (`app-store-badge.svg`) and the image link previews show (`preview.jpg`).
  Preview it with `python3 -m http.server 8000 --directory site`.
- `docs/`: the brief, the plans, `app-store-metadata.md` (what App Store
  Connect asks for) and `release-checklist.md` (the order of work for a
  release).
- `design/`: the app icon, the disk image's background, and the iPad App
  Store screenshots the README shows (`screenshots/`).
