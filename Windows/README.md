# Sill for Windows (spike)

A spike, not a product: a Windows PC as a Sill client. It pairs with a Mac running
`SillHost --pairing` over the LAN (a typed 12-digit code or a pasted `sill://pair` link,
to a typed address), opens a session, and writes the first keyframe's decoded frame to a
PNG. No discovery, no live window, no input, no signing or distribution yet.

C# on .NET 10: an exception to the repository's Swift-only convention, chosen for this
spike for .NET's TLS (SslStream), crypto and Media Foundation access on Windows.

## Layout

- `src/Sill.Protocol` — the wire format, portable (no Windows API): the 14-byte header,
  and pairing's pure parts (the typed code, the proofs, the `sill://pair` link, kinds 19 and
  20, the Mac ID and SPKI fingerprint), the device's key (`DeviceIdentity`), the TLS
  connection to a Mac (`SillTls`: TLS 1.3, one ALPN, trust by the Mac's SPKI SHA-256) and one
  pairing over it (`PairingClient`), and the session (`Session.cs`: `SessionClient`, the hello,
  parameter sets, access units). The Swift side is the reference:
  `Sources/StreamProtocol/`.
- `src/Sill.Spike` — the console app: `pair`, `session`; decode to PNG next.
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
in `%LOCALAPPDATA%\Sill\spike\device.p12` (`--identity <dir>` for another), and a pairing saves
the Mac in `mac.json` beside it. Exit status: 0 paired, 1 refused, 2 usage, 3 connection or TLS.
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

It dials the Mac in `mac.json` pinned to its key, says hello, asks for the Desktop, and logs the
parameter sets, each keyframe and one line a second. `--save <dir>` writes the first keyframe as
`parameter-sets.bin`, `first-keyframe.bin` and `first-keyframe.h265` (Annex B: `ffmpeg -i
first-keyframe.h265 frame.png` decodes it). To compare, `Scripts/sillclient.py <port> 8 desktop
--tls --identity=<dir> --stats` after `--pair-code`; it needs a Python with TLS 1.3
(`/opt/homebrew/bin/python3`, not the Mac's `/usr/bin/python3`).
