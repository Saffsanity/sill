# Sill

Any window from your Mac, on your iPhone and iPad.

Sill shows a window from your Mac, or the whole desktop, on your iPhone or
iPad. You use it there with touch, a trackpad, a keyboard or Apple Pencil.
Sill for Mac captures the window, encodes it as HEVC video and sends it to the
Sill app on your device. Your taps, clicks, scrolls and keys go back to your
Mac. Your Mac and your device connect on the same network, over a USB cable,
with Direct Wireless Connection when they share no network, or through your
own VPN, such as Tailscale, with Remote Access. There is no account and no
server in between.

**[getsill.app](https://getsill.app)** ·
[Download for Mac](https://getsill.app/download) ·
[Support](https://getsill.app/support) ·
[Privacy](https://getsill.app/privacy)

[![CI](https://github.com/Saffsanity/sill/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Saffsanity/sill/actions/workflows/ci.yml)

<!-- App Store: once the iPhone and iPad app is listed, put Apple's "Download on
     the App Store" badge here, linked to the listing, and delete the sentence
     below. -->

Sill for Mac is a free, notarized download from
[getsill.app](https://getsill.app/download). The iPhone and iPad app is not on
the App Store yet; until it is, you can build it from source (below).

## Requirements

- A Mac with Apple silicon, on macOS 14 or later.
- An iPhone or iPad with iOS 17 or iPadOS 17 or later.
- On your Mac, Sill asks for Screen Recording, to show your windows, and
  Accessibility, to click, scroll and type for you and to move and size the
  window it shows. On macOS 15 or later, also allow Local Network. On your
  iPhone or iPad, Sill asks for Local Network, to find your Mac.
- Your Mac and your device on the same network, joined by a USB cable, or near
  each other with Direct Wireless Connection on. Away from home, your own VPN,
  such as Tailscale, with Remote Access on.

## How it works

- **Sill for Mac** lives in the menu bar. When your device picks a window, or
  the whole desktop, Sill captures it with ScreenCaptureKit and encodes it as
  HEVC with VideoToolbox, on the hardware video encoder in your Mac (or, while
  that is busy, in software). It captures nothing while no device is connected.
- **The picture** goes over an encrypted connection (TLS 1.3) straight to the
  Sill app on your iPhone or iPad, which decodes and shows it. When the
  encoder or the link falls behind, Sill drops frames rather than queue them,
  so the picture stays current.
- **Your input** goes back the same way: taps and clicks, scrolls with
  momentum, the on-screen trackpad, keys and typed text, and Apple Pencil as
  the pointer. Sill for Mac turns it into mouse and keyboard events, which
  needs Accessibility. Three fingers swipe and pinch as on a Mac's trackpad:
  Mission Control, App Exposé, the Spaces, Apps and Show Desktop, through the
  keyboard shortcuts your Mac has for them.
- **The menus** of the app you use reach your device too: in the iPad's own
  menu bar on iPadOS 26 or later, and behind the Menus button in Sill's bar.
  Sill for Mac reads each menu from the app as you open it and chooses the
  item you pick, through Accessibility. When someone moves the mouse at your
  Mac, your device shows the pointer where it is.
- **Nearby**, your device finds your Mac with Bonjour on your local network.
  Over a USB cable, your Mac shows as Wired and the connection uses the cable.
  With no shared network, Direct Wireless Connection (off by default) connects
  over peer-to-peer Wi-Fi, the way AirDrop does.
- **Pairing**: you pair each iPhone or iPad with your Mac once. Tap your Mac on
  the device, and your Mac shows a code: scan it, or type its 12 digits. Over
  a USB cable the device pairs by itself. From then on each end knows the
  other's key, and every connection, nearby or away, is pinned to those keys.
  In Sill's Settings on your Mac, Devices lists the devices you paired, and
  you can remove any of them there.
- **Away from home**, Remote Access (off by default) lets the devices you
  paired reach your Mac through your own VPN or a port you forward on your
  router; a device learns how the next time it connects at home with Remote
  Access on. A device away from home gets a quality of its own, Low at Standard
  resolution until you pick another there or in Sill's settings, so a slow
  connection never starts at your home quality; your home quality comes back
  as soon as a device at home connects. When your device comes home and your
  network lists your Mac, the session moves to your network by itself.
- **When the link can't keep up**, Sill for Mac notices that it is holding
  frames back and tells your device, which says so over the picture and, in
  its Settings, offers a quality the link can carry.
- **The virtual display** (off by default) moves a window you stream onto a
  display of its own on your Mac, so it keeps updating when other windows
  cover it. It uses a private macOS API, which is one reason Sill for Mac comes
  from the website and not from the Mac App Store.

Good to know: Sill shows one window, or the whole desktop, at a time, and it
does not play sound from your Mac. Only the iPhones and iPads you paired can
connect, unless you turn off Require pairing in Settings › Devices; then any
device on your network can, still encrypted. Pairing at home came with Sill
for Mac 0.4.0 and Sill for iPhone and iPad 0.5 (2), and each needs the other:
the iPhone and iPad app shows an older Sill for Mac as "Update Sill", and an
older iPhone and iPad app can't connect to Sill for Mac 0.4.0 or later at
home. Since 0.5.1 the two apps share one version number for each release. With
Sill for Mac 0.3.1 or earlier, connections on your local network, over the
cable and over Direct Wireless Connection are not encrypted, and any iPhone or
iPad with Sill on the same network, or nearby while Direct Wireless Connection
is on, can connect to your Mac: update it.

## Tips

Sill is free, with no ads, no tracking and no subscription. If it is useful to
you, a tip through [GitHub Sponsors](https://github.com/sponsors/Saffsanity)
helps pay for the developer account. A tip unlocks nothing: every feature is
free.

## Building from source

You need a Mac with Xcode (Sill is built with Xcode 27), selected as the
active developer directory, with its license accepted.

Sill for Mac, from the repository's folder:

```
Scripts/make-app.sh --install --open
```

This builds Sill.app with SwiftPM, signs it with your Apple Development
identity, replaces /Applications/Sill.app and opens it. Without `--install` it
only builds `.build/Sill.app`. With no Apple Development identity it signs ad
hoc, and then Screen Recording and Accessibility have to be granted again
after every build. For work on the host itself, `swift run -c release
SillHost` runs the same host on the command line, and with `--synthetic` it
streams a test pattern with no Screen Recording needed.

The iPhone and iPad app:

1. Open `iOSClient/Sill.xcodeproj`.
2. In the Sill target's Signing & Capabilities, pick your team, and change the
   bundle identifier `me.saffer.sill` to one of your own.
3. Run it on an iPhone or iPad on the same network as your Mac, and tap your
   Mac. The first time, a Sill for Mac built from this repository asks you to
   pair: scan the code it shows, or connect the device with a USB cable.

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) has the rest: every command-line
flag, the test tools and the simulator harness, permissions and how to reset
them, Remote Access, troubleshooting and releases.

## Contributing

Issues are welcome: bug reports, questions and ideas. For a pull request, keep
to the conventions and decisions in [CLAUDE.md](CLAUDE.md): Swift and Apple
frameworks only, no third-party dependencies, nothing that needs a server, and
latency before picture quality. Open an issue before starting anything large.
Before a pull request, `Tests/checks/run-all.sh` runs the same pure checks as
CI, in about five minutes and with no device.
Contributions are accepted under the project's license. Please report a
security problem privately, as [SECURITY.md](SECURITY.md) says, not in a
public issue.

## License

Sill is licensed under the [Apache License 2.0](LICENSE).
Copyright 2026 Noah Saffer.
