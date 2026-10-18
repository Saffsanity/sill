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
