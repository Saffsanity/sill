# Sill for Windows (spike)

A spike, not a product: a Windows PC as a Sill client. It pairs with a Mac running
`SillHost --pairing` over the LAN (a typed 12-digit code or a pasted `sill://pair` link,
to a typed address), opens a session, and writes the first keyframe's decoded frame to a
PNG. No discovery, no live window, no input, no signing or distribution yet.

C# on .NET 10: an exception to the repository's Swift-only convention, chosen for this
spike for .NET's TLS (SslStream), crypto and Media Foundation access on Windows.

## Layout

- `src/Sill.Protocol` — the wire format, portable (no Windows API): the 14-byte header
  today; pairing and the session's messages next. The Swift side is the reference:
  `Sources/StreamProtocol/`.
- `src/Sill.Spike` — the console app (pairing, session, decode to PNG, as the tickets land).
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
