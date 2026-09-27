# Security

Sill lets an iPhone or iPad see and control a Mac, so a flaw in it matters.
If you find one, please report it privately.

## Reporting a problem

Email support@getsill.app. Say what you found, how to reproduce it, and which
versions of Sill for Mac and of the iPhone and iPad app you tried (Sill for
Mac's is at the foot of its Settings › General). Please don't open a public
issue or pull request for it, and give a fix time to ship before you publish
anything. Once this repository's Security tab offers "Report a
vulnerability", that works too.

Fixes ship in the newest release: Sill for Mac from
[getsill.app](https://getsill.app/download), whose update check tells everyone
who has it, and the newest iPhone and iPad app.

## What is in scope

- The connection on the Mac's own networks, over a USB cable and with Direct
  Wireless Connection: what Sill for Mac accepts, and what a device can make
  it do.
- Remote Access: its TLS connection, pairing (the QR code, the typed code and
  `sill://pair` links) and the paired devices it keeps.
- The update check, which asks GitHub's releases feed about once a day and
  downloads nothing.
- The website, getsill.app.

Known, and said in the README's "Good to know": until pairing at home ships,
any iPhone or iPad running Sill on the Mac's own networks can connect while
Sill runs, and so can one nearby while Direct Wireless Connection is on; that
connection is not encrypted.
