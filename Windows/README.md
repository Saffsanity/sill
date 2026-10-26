# Sill for Windows (spike)

A spike, not a product: a Windows PC as a Sill client. It pairs with a Mac running
`SillHost --pairing` over the LAN (a typed 12-digit code or a pasted `sill://pair` link,
to a typed address), opens a session, and writes the first keyframe's decoded frame to a
PNG. No discovery, no live window, no input, no signing or distribution yet.

C# on .NET 10: an exception to the repository's Swift-only convention, chosen for this
spike for .NET's TLS (SslStream), crypto and Media Foundation access on Windows
(`docs/adr/0001-windows-client-in-csharp.md`).

## Layout

- `src/Sill.Protocol` — the wire format, portable (no Windows API): the 14-byte header,
  and pairing's pure parts (the typed code, the proofs, the `sill://pair` link, kinds 19 and
  20, the Mac ID and SPKI fingerprint), the device's key (`DeviceIdentity`), the TLS
  connection to a Mac (`SillTls`: TLS 1.3, one ALPN, trust by the Mac's SPKI SHA-256) and one
  pairing over it (`PairingClient`), and the session (`Session.cs`: `SessionClient`, the hello,
  parameter sets, access units), and the picture's portable parts (`HevcSps`, `Nv12`, `Png`). The Swift side is the reference:
  `Sources/StreamProtocol/`.
- `src/Sill.Media` — Windows' media APIs (runs only on Windows): `HevcDecoder` (Media Foundation's
  HEVC decoder as a stream, in software or, given a `GpuDevice`, on the GPU), `GpuDevice` (a
  Direct3D 11 device with video support and Media Foundation's device manager), `VideoRenderer`
  (a swap chain on a window, the GPU's video processor from the decoder's NV12 texture to it) and
  `Bgra` (fast NV12 to BGRA for the software path).
- `src/Sill.Viewer` — a live window on the paired Mac's Desktop (WinForms, view only).
- `src/Sill.Spike` — the console app: `pair`, `session`, `decode` (Media Foundation's HEVC decoder to a PNG; Windows only).
- `src/Sill.Probe` — ticket 02's probe, run on the PC: the OS build, TLS 1.3 with ALPN
  (mutual, P-256), Media Foundation's HEVC decoders, and with `--host addr:port` a handshake
  to a Mac's door. `artifacts/` (gitignored) holds single-file builds of it.
- `tests/Sill.Protocol.Tests` — xUnit tests, with byte fixtures from the Swift serializer.

Status, decisions and the next step: `PROGRESS.md`.

## Build and test

Needs the .NET 10 SDK (`global.json`). On any OS:

```
dotnet build Windows/Sill.Windows.slnx -c Release
dotnet test Windows/Sill.Windows.slnx -c Release
```

CI: `.github/workflows/windows.yml`, on a Windows runner, for changes under `Windows/`.
The decoder (Media Foundation's HEVC, which needs HEVC Video Extensions) runs only on
Windows.

## The probe on the PC

Build it on any machine into one `.exe` (no .NET needed on the PC):

```
dotnet publish Windows/src/Sill.Probe -c Release -r win-x64 --self-contained \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o Windows/artifacts/probe-win-x64
```

(`win-arm64` for an ARM PC.) On the PC, from a terminal: `Sill.Probe.exe`, or
`Sill.Probe.exe --host <Mac's address>:<port>` with `SillHost --pairing` running on the Mac
(its port is in its log). It writes `probe-report.txt` beside where it ran. The `.exe` is
unsigned, so SmartScreen may ask first ("More info", "Run anyway"). .NET on macOS has no
TLS 1.3, so the TLS checks pass only on Windows.

## Pairing from the PC

With `SillHost --pairing` running on the Mac (it prints a code and a `sill://pair` link):

```
dotnet run --project Windows/src/Sill.Spike -- pair --host <Mac's address>:<port> --code "1234 5678 9012"
dotnet run --project Windows/src/Sill.Spike -- pair --link "sill://pair?…" [--host <Mac's address>:<port>]
```

The code goes in one argument (quote it if it has spaces). The device's key is made on first use
in `%LOCALAPPDATA%\Sill\device.p12`, the app's data folder (`--identity <dir>` for another), and a
pairing saves the Mac in `macs.json` beside it. Exit status: 0 paired, 1 refused, 2 usage, 3 connection or TLS.
The TLS tests (`WindowsFact`) run only on Windows.

To test from a PC without opening a port on the Mac, keep the host on loopback and forward it
through SSH: `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1
SillHost --synthetic --pairing`, then `ssh -R 47455:127.0.0.1:<its port> <pc>` and pair with
`--host 127.0.0.1:47455` on the PC.

## A session from the PC

After `pair`, with the same host still running (`SillHost --pairing` makes a new key each run):

```
dotnet run --project Windows/src/Sill.Spike -- session [--seconds 10] [--host <address>:<port>] [--save <dir>]
```

It dials the newest Mac in `macs.json` pinned to its key, says hello, asks for the Desktop, and logs the
parameter sets, each keyframe and one line a second. `--save <dir>` writes the first keyframe as
`parameter-sets.bin`, `first-keyframe.bin` and `first-keyframe.h265` (Annex B: `ffmpeg -i
first-keyframe.h265 frame.png` decodes it). To compare, `Scripts/sillclient.py <port> 8 desktop
--tls --identity=<dir> --stats` after `--pair-code`; it needs a Python with TLS 1.3
(`/opt/homebrew/bin/python3`, not the Mac's `/usr/bin/python3`).

## One frame to a PNG

On the PC (HEVC Video Extensions installed):

```
dotnet run --project Windows/src/Sill.Spike -- session --seconds 3 --png frame.png
dotnet run --project Windows/src/Sill.Spike -- decode --input <dir>/first-keyframe.h265 --out frame.png
```

The first decodes the session's first keyframe after the session; the second a keyframe saved
with `--save`. Both print the decoder used, the coded and shown sizes, the colour range and matrix.
To try colour without capturing the screen, give the test host a picture:
`SILL_TEST_PATTERN=picture:<png> SillHost --synthetic --pairing`.

## The live viewer

On the PC:

```
dotnet publish Windows/src/Sill.Viewer -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o <dir>
<dir>\Sill.Viewer.exe [--identity <dir>]   # default: %LOCALAPPDATA%\Sill
```

A shortcut needs no arguments: it opens on the connect screen, as the iPad's: the Macs Windows' own DNS-SD finds
on this network (`_sill._tcp` through dnsapi.dll, Windows 10 1809 and later, no Bonjour), each with
its word (Wired or Wi‑Fi for the Mac this PC paired with, known by its TXT tag `r`, never by name;
"Not paired"; "Update Sill" for a Mac without `p`), Add a Mac… and the site's links. A click on the
paired Mac connects at the address and port it resolved (the home door, TLS, pinned to the saved
key), then at its saved addresses; Settings › Disconnect, at the panel's foot, comes back here.

Away from home. Every session's kind 18 (the Mac's signed `MacInfo`: its name, the remote door's
port, and while Remote Access is on its addresses for afar, Tailscale's name and address among them)
is checked against the key this PC paired with and kept in `macs.json` when it is newer (an empty
list, or one from a Mac with Remote Access off, keeps the old addresses). A saved Mac this network
doesn't list is a "Remote" row after 3 s. A dial tries the Mac's row on this network first, then
the saved addresses in the iPad's order (the one that last worked, Tailscale's name, its IPv4 and
IPv6, this network's, the internet's), a second apart, the first to connect winning
(`RemoteDialPolicy`, `HappyEyeballs`); when all fail the card says why in the iPad's words. So a
router's new address for the Mac, a Sill.app relaunch (a new home door port) or a trip away change
nothing. After a loss the viewer reconnects by itself as the iPad does (`ReconnectPolicy`): at once,
then 5, 10, 20 and every 30 s, 12 at most ("Reconnecting to ‹Mac›…", after 3 "‹Mac› isn’t answering.
It may be asleep…", after 12 "Stopped trying…"); the Mac's row listed afresh, or a click on the
window, dials at once. A goodbye that forbids it (removed, Require pairing) waits for a click. TEST
ONLY: `SILL_TEST_KEEP_LOOPBACK=1` keeps a test host's 127.0.0.1 from kind 18.

`--host <address>:<port>` (repeatable; a developer's tool) dials the newest saved Mac at those
addresses first, then at its saved ones.

Pairing takes clicks and the code, as on the iPad. A click on a "Not paired" row asks the Mac to
show its code (kind 19 "ask"; the status line says what the Mac answered: showing a code, unlock
it, open Sill's Pair iPhone or iPad…, or no answer), then a card asks for it: "Enter the Code from
‹Mac›", 12 digits grouped in fours as they are typed, the check digit judged once all 12 are in, so
a typo never costs one of the Mac's five tries; a wrong code says how many tries are left. The code
goes to the address that answered, pinned to the key the ask met; paired, the viewer connects at
once. Cancel (or Esc) tells the Mac to close its code window (kind 19 "cancel"). Add a Mac… takes a
pasted `sill://pair` link (pinned to its key, at its own addresses) or an address (`host`, or
`host:port`; 7455, the remote door, by default) and a code. A Mac set up again: when every address of
a paired Mac's row answers with another key, the connect screen says "‹Mac› has a new key since this
PC paired. Click it to pair again.", its row reads "Not paired", and that pairing replaces the old
record. The saved Macs are `macs.json` beside the key (a spike's `mac.json` is taken in once and
renamed `mac.json.migrated`). Settings › This PC › Name is how a Mac lists this PC when it pairs
(`pc.json`; also in the hello), and Forget ‹Mac› (click twice) drops its key and goes back to the
list. TEST ONLY: `--service-type
_silltest._tcp` (repeatable) browses other types. No firewall rule is needed: the DNS Client
service owns UDP 5353 and Windows' built-in mDNS rules let its answers in.

Self-contained, because an apphost can't find a .NET installed only in the user's folder. It shows
the Mac's Desktop as it streams and sends the mouse and keys to it: left Ctrl is ⌘, right Ctrl ⌃,
Alt ⌥; Alt+Tab is the Mac's ⌘Tab, and the Windows key alone opens Spotlight (held with another key
it is ⌃). The bar on top is the iPad's: Apps (search and open an installed app), Desktop, a thumbnail
per Mac window (click to stream it, right-click to close, minimize or make it full screen), and
Mission Control, App Exposé, the Spaces, Show Desktop and Launchpad. F11 toggles full screen. The Mac's host needs Accessibility (System Settings › Privacy &
Security › Accessibility, for the app that started it) or the Mac drops the input. The title
has the size, pictures shown and received each second, the bitrate, the decode time and the round
trip, which path decodes (`GPU (…)` or `software`), the decode and draw times and the viewer's CPU
(100% is one core); `viewer.log` beside the key has the same line each second.

The clipboard goes both ways (kind 32, text, with a Mac whose window list says `clipboard` 1): text
copied on the Mac lands on Windows' clipboard (kept out of Windows' cloud clipboard), and text copied
on the PC goes to the Mac when it is copied with the viewer in front or when the viewer next comes to
the front, so Ctrl+V (⌘V) pastes it there. Never a copy its app marks as private
(`ExcludeClipboardContentFromMonitorProcessing`, or `CanIncludeInClipboardHistory` or
`CanUploadToCloudClipboard` 0: password managers), never what was on the clipboard when the viewer
started or the switch went on. Settings › This PC › Share Clipboard (on; kept in `window.json`)
turns it off, which tells the Mac to stop. `viewer.log` has a `Clipboard:` line per decision with
sizes, never contents.

It decodes and draws on the GPU: Media Foundation's HEVC decoder given a Direct3D 11 device (DXVA),
the picture drawn from its texture by the GPU's video processor into a swap chain, never copied
back to the CPU. `--decoder software` keeps everything on the CPU (the old path); `--adapter N` picks
DXGI's Nth GPU instead of Windows' default (on the test laptop the Intel UHD drives the display and
the RTX 3050 is the other). If the GPU path can't start, or fails mid-stream (a driver update, a
lost device), the viewer reconnects in software and the title says so. TEST ONLY:
`SILL_TEST_GPU_FAIL_AFTER=N` fails it after N pictures.

To measure decoding without a window: `Sill.Spike session --decode 1` (software) and `--decode 1
--gpu 1 [--adapter N]` (each frame timed until the GPU has finished it); both print the median,
95th and worst decode time and the CPU used. `Sill.Spike decode --input <keyframe.h265> --out
<png> --gpu 1 --compare 1` decodes a keyframe on the GPU, copies it back and compares it with the
software decoder's picture.

## Sill.exe: the release's app, installing itself and checking for updates

The release names the viewer `Sill.exe` (`-p:SillExeName=Sill`; without it the project still makes
`Sill.Viewer.exe`, so the spike's own launches are as before; the libraries keep their names) and
stamps Sill's one version (`Version` in `Directory.Build.props`, the release workflow's `-p:Version`
from the tag) and its build number (`-p:SillBuild=`, the commit count at the tag, as Sill.app's
CFBundleVersion). The hello carries both ("Client hello: ‹PC› (Windows), Sill 0.5.1 (812), protocol
1" in the Mac's log); a developer's build sends its version and no build:

```
dotnet publish Windows/src/Sill.Viewer -c Release -r win-x64 --self-contained -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true -p:SillExeName=Sill -p:SillBuild=$(git rev-list --count HEAD) -o <dir>
```

Publish it on Windows (or on the runner): only a Windows build writes the exe's version resource,
which the install offer compares. `.github/workflows/release.yml`'s windows job zips it per
architecture and attaches the zips to the Mac's GitHub Release (`docs/release-checklist.md`, "Sill
for Windows").

- Installing (`SelfInstall`, `SelfInstallPolicy`): `Sill.exe` started with no options from anywhere
  but `%LOCALAPPDATA%\Programs\Sill\Sill.exe` offers, in a task dialog, to install itself there
  with `Sill.lnk` in the user's Start menu Programs folder, then opens the installed copy; an older
  installed copy (or one with no version) is replaced, a same or newer one offered instead ("Open
  Installed Sill"). Per user, no administrator, nothing in the registry; the download's
  Zone.Identifier mark is not copied. "Don't ask again for this copy" is kept in
  `%LOCALAPPDATA%\Sill\install.json`. `SILL_NO_SELF_INSTALL=1` skips the offer. The installed copy
  has Settings › This PC › Start Menu Shortcut, which removes `Sill.lnk` or makes it again (a copy
  anywhere else doesn't show the row).
- Updates (`UpdatePolicy`, `UpdateChecker`, ported from Sill.app's; the Viewer's `AppUpdates`, one
  checker for the whole run, owned by `SillApp` whichever window shows):
  `Sill.exe` asks https://api.github.com/repos/Saffsanity/sill/releases/latest 30 s after starting
  when a check is due, then every 24 h plus up to 30 minutes, an hour after a check with no answer,
  with `User-Agent: Sill-Windows/<version>`, GitHub's Accept and API version, `Accept-Language: en`,
  If-None-Match; no cookies, cache or credentials; redirects only to api.github.com; 1 MB, 10 s. A
  newer published release shows in place, as Sill.app's menu item and General pane do, never in a
  dialog: on the connect screen "Sill 0.6 Is Available…" with "You have 0.5.1; opens its download
  page" above the footer, for as long as it is out (a click opens the release page in the browser);
  in Settings › This PC, Check for Updates Automatically, Open Release Page… while there is one,
  Check Now, the line ("Checking…", Check Now's answer, "Sill 0.6 is available.", "Last checked …")
  and the footnote saying what GitHub sees. Nothing downloads. State and the switch are in
  `%LOCALAPPDATA%\Sill\update.json`, the log lines in `update.log` beside it. The spike's
  `Sill.Viewer.exe` never checks. TEST ONLY: `SILL_TEST_UPDATE_FEED=http://127.0.0.1:P/latest` (a feed on
  this PC only: `Scripts/sillfeed.py P` on the Mac and `ssh -R P:127.0.0.1:P <pc>`; it also makes
  `Sill.Viewer.exe` check), `SILL_TEST_UPDATE_VERSION=0.4`, `SILL_TEST_UPDATE_NOW=1` (a check at
  start), `SILL_TEST_UPDATE_INTERVAL=<s>` (24 h become s seconds). Never test against GitHub: a test of
  `Sill.exe` sets `SILL_TEST_IDENTITY_DIR` (an empty folder, so it dials no paired Mac), which also
  keeps it from checking anything but a test feed and puts its `update.json` and `update.log` in
  that folder, not in `%LOCALAPPDATA%\Sill`.

- The data folder (`DataFolder`): `%LOCALAPPDATA%\Sill` holds the device's key (`device.p12`), the
  saved Macs (`macs.json`), this PC's name (`pc.json`), the window (`window.json`), the log
  (`viewer.log`), `update.json`, `update.log` and `install.json`. The spike kept the first five in
  `%LOCALAPPDATA%\Sill\spike`: the first start of a build with the data folder, before anything
  reads it, moves them up when the data folder has no key and no saved Macs yet (a file already
  there is never replaced), then renames the old folder `spike.migrated` (what else was in it, such
  as `mac.json.migrated`, stays there), with one line in `viewer.log`. Should any step fail, what was
  put in the data folder is taken out again, the run uses the spike's folder as it was, and the next
  start tries again. `SILL_TEST_IDENTITY_DIR` is the folder instead and never moves anything. TEST
  ONLY: `SILL_TEST_LOCALAPPDATA=<dir>` stands in for `%LOCALAPPDATA%` whole (the data folder, the
  install place, the update check's state), since Windows' own ignores the `LOCALAPPDATA` variable.

To start over on a PC: delete `%LOCALAPPDATA%\Programs\Sill`, `Sill.lnk` in
`%APPDATA%\Microsoft\Windows\Start Menu\Programs`, and `%LOCALAPPDATA%\Sill` (then remove the PC
in Sill's Settings › Devices on the Mac).

## With Sill.app (Wi-Fi and Tailscale)

Sill.app keeps its key, so a PC pairs with it once. With Sill.app running on the Mac:

```
Sill.Spike pair --identity <dir> --ask 1 --host <the Mac's address>:<its home door port>
```

Sill.app opens its Pair iPhone or iPad window with a code; type it on the PC (or click the Mac's
"Not paired" row in the viewer, which does the same). With Remote Access on (Settings › Remote
Access, port 7455 by default), the first session saves its addresses for afar, and the viewer with
no arguments reaches it at home and through Tailscale. The spike's old shortcut,
`--host <Wi-Fi address>:7455 --host <Tailscale name>:7455`, still works but is no longer needed.

## Security notes

**The device's certificate goes out before the Mac's key is judged (accepted, 2026-10-19).** In TLS
1.3 the client's certificate travels in its last handshake flight, encrypted to the server. SChannel
sends it there and only then hands the Mac's certificate to .NET's validation callback
(`SillTls.ConnectAsync`, `RemoteCertificateValidationCallback`), so a Mac the device has not pinned
(a link naming another key, an impostor at a saved address) learns this PC's certificate before the
handshake is refused. The test `ALinkToAnotherKeySendsNothing` pins this down: the stand-in Mac sees
the device's fingerprint and nothing else. Accepted, because:

- What it learns is a public key and the certificate's fixed fields (subject `CN=Sill for Windows`,
  a random serial, validity from the day before the key was made). A public key is not a secret: it
  proves nothing to anyone without the private key, which never leaves `device.p12`.
- The key is Sill's alone, made by Sill for this purpose (`DeviceIdentity`), so it links this PC to
  nothing outside Sill. At most an impostor can recognise the same PC trying it again.
- Nothing else is sent. The handshake fails in the callback, before any kind 19, hello or input: the
  Mac must prove the pinned key (TLS 1.3's CertificateVerify, signed with its private key) before the
  first byte of `sill/1` or `sill-pair/1`. On the typed code's path the pin is open, and the
  pairing proofs bind both keys, as on iOS.
- On the iPhone and iPad (`RemoteTLS.options`, `sec_protocol_options_set_verify_block`) Network.framework
  calls the verify block when the Mac's certificate arrives, so a refused Mac never gets the device's
  certificate. That order is not available from .NET's SslStream on SChannel; another TLS stack
  (a bundled OpenSSL, say) would buy it at the cost of a dependency, for a key that is already public.
