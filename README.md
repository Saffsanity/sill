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

<!-- CI badge: uncomment once the repository is public (a private repository's badge shows
     visitors nothing).
[![CI](https://github.com/Saffsanity/sill/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Saffsanity/sill/actions/workflows/ci.yml)
-->

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
- **The picture** goes over a TCP connection straight to the Sill app on your
  iPhone or iPad, which decodes and shows it. When the encoder or the link
  falls behind, Sill drops frames rather than queue them, so the picture stays
  current.
- **Your input** goes back the same way: taps and clicks, scrolls with
  momentum, the on-screen trackpad, keys and typed text, and Apple Pencil as
  the pointer. Sill for Mac turns it into mouse and keyboard events, which
  needs Accessibility.
- **Nearby**, your device finds your Mac with Bonjour on your local network.
  Over a USB cable, your Mac shows as Wired and the connection uses the cable.
  With no shared network, Direct Wireless Connection (off by default) connects
  over peer-to-peer Wi-Fi, the way AirDrop does.
- **Away from home**, Remote Access (off by default) lets in only the devices
  you pair, through your own VPN or a port you forward on your router. Those
  connections use TLS 1.3, with each end pinned to the other's key.
- **The virtual display** (off by default) moves a window you stream onto a
  display of its own on your Mac, so it keeps updating when other windows
  cover it. It uses a private macOS API, which is one reason Sill for Mac comes
  from the website and not from the Mac App Store.

Good to know: Sill shows one window, or the whole desktop, at a time, and it
does not play sound from your Mac. On your local network, over the cable and
over Direct Wireless Connection, the connection is not encrypted. While Sill
runs, any iPhone or iPad with Sill on the same network can connect to your
Mac, and so can one nearby while Direct Wireless Connection is on. Use it on
networks you trust.

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
   Mac.

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) has the rest: every command-line
flag, the test tools and the simulator harness, permissions and how to reset
them, Remote Access, troubleshooting and releases.

## Contributing

Issues are welcome: bug reports, questions and ideas. For a pull request, keep
to the conventions and decisions in [CLAUDE.md](CLAUDE.md): Swift and Apple
frameworks only, no third-party dependencies, nothing that needs a server, and
latency before picture quality. Open an issue before starting anything large.
Before a pull request, `Tests/checks/run-all.sh` runs the same pure checks as
CI, in about two minutes and with no device.
Contributions are accepted under the project's license. Please report a
security problem privately, as [SECURITY.md](SECURITY.md) says, not in a
public issue.

## License

Sill is licensed under the [Apache License 2.0](LICENSE).
Copyright 2026 Noah Saffer.
