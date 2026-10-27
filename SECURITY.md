# Security

Sill lets an iPhone or iPad see and control a Mac, so a flaw in it matters.
If you find one, please report it privately.

## Reporting a problem

Email support@getsill.app. Say what you found, how to reproduce it, and which
versions of Sill for Mac and of the iPhone and iPad app you tried (Sill for
Mac's is at the foot of its Settings › General). Please don't open a public
issue or pull request for it, and give a fix time to ship before you publish
anything. You can also use "Report a vulnerability" on this repository's
Security tab.

Fixes ship in the newest release: Sill for Mac from
[getsill.app](https://getsill.app/download), whose update check tells everyone
who has it, and the newest iPhone and iPad app.

## What is in scope

- The connection on the Mac's own networks, over a USB cable and with Direct
  Wireless Connection: what Sill for Mac accepts, and what a device can make
  it do.
- Remote Access's connection, and pairing, at home and away: the QR code, the
  typed code, `sill://pair` links, a USB cable's automatic pairing, Require
  pairing, and the paired devices and keys Sill for Mac keeps in the keychain.
- The update check, which asks GitHub's releases feed about once a day and
  downloads nothing.
- The website, getsill.app.

Known, and by design: with Require pairing off (Settings › Devices), any
device on the Mac's own networks, one nearby while Direct Wireless Connection
is on, and any app on the Mac itself connect without pairing, still
encrypted. With Show the pairing window to screen sharing on (Settings ›
Devices, off by default), Screen Sharing and other remote desktop apps show the
pairing window, so anyone who can see the Mac's screen remotely can read its
code. `SillHost`, the command-line host for development, keeps a plain
home door, with no pairing and no encryption, unless it runs with
`--pairing`. Sill for Mac 0.3.1 and earlier had no pairing and no encryption
at home: update to the newest release.
