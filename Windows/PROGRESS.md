# Windows client spike: progress

Read this first when picking up the Windows work. Keep it current: update it in the same
commit as the work it describes.

## Where things are

- Code: `Windows/` on branch `windows-spike` (not pushed). Build and test: `Windows/README.md`.
- Plan: the wayfinder map at `.scratch/windows-integration/map.md`, tickets in
  `.scratch/windows-integration/issues/` (local only: `.scratch/` is gitignored, see
  `docs/agents/issue-tracker.md`). This file repeats what an agent without `.scratch/` needs.
- Wire reference: `Sources/StreamProtocol/` (Swift). Test client: `Scripts/sillclient.py`.

## Goal

A Windows PC pairs with a Mac running `SillHost --pairing` over the LAN (a typed 12-digit
code or a pasted `sill://pair` link, to a typed address), opens a session, and writes the
first keyframe's decoded frame to a PNG. Windows as client only.

## Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Destination | A working spike, not a spec |
| 2 | Hardware | A physical Windows PC |
| 3 | Language | C# on .NET 10 (an exception to the Swift-only convention) |
| 4 | Mac target | `SillHost --pairing`, real window capture, LAN |
| 5 | Discovery | Typed address only, no mDNS |
| 6 | Pairing | Typed code and pasted link; camera QR later |
| 7 | Success | One decoded frame to a PNG from the first keyframe |
| 8 | Tracker | Local markdown under `.scratch/`, gitignored |
| 9 | Location | `Windows/` at the repo root, its own solution and CI job |
| 10 | Windows PC | HEVC Video Extensions installed, Windows 11 or 10 22H2 (build number to record) |
| 11 | Mac capture | Screen Recording granted to Terminal, then `SillHost --pairing` |

Out of scope: the Windows host, a Mac client, discovery, camera QR, signing and
distribution, input, menus, gestures, clipboard.

## Tickets

| # | Ticket | Type | Blocked by | Status |
|---|---|---|---|---|
| 01 | Windows solution skeleton and CI job | task | none | claimed: done locally, CI not run (needs a push) |
| 02 | Confirm the Windows facts (build, HEVC, TLS 1.3 + ALPN, decode) | research | none | claimed: probe built, waiting for the PC's report |
| 03 | Pairing client over TLS (`sill-pair/1`) | prototype | 01, 02 | open |
| 04 | Session connection and frame parsing (`sill/1`) | prototype | 03 | open |
| 05 | Decode one frame to a PNG (Media Foundation) | prototype | 04 | open |
| 06 | Conformance run with the Mac side | task | 05 | open |

## Log

- 2026-10-17: map and tickets made; ticket 01 built: `Sill.Protocol` (the 14-byte header,
  matching the Swift serializer byte for byte), `Sill.Spike` (placeholder),
  `Sill.Protocol.Tests` (10 tests pass); `.github/workflows/windows.yml`; `Windows/**` left
  out of ci.yml. The .NET 10 SDK installed on the Mac with `brew install dotnet`.

- 2026-10-17: ticket 02's probe, `src/Sill.Probe` (OS build, loopback TLS 1.3 with ALPN
  and mutual P-256 keys, MF HEVC decoder count, optional handshake to a Mac). Built and run on
  the Mac: everything but TLS works there (.NET on macOS has no TLS 1.3: "The requested
  security protocol is not supported"). Single-file `win-x64` and `win-arm64` builds in
  `Windows/artifacts/`. The Windows CI job runs it too (informational).

## Next

- Ticket 02: run `Sill.Probe.exe` on the PC (README, "The probe on the PC"), once alone and
  once with `--host` against `SillHost --pairing`, and paste `probe-report.txt` into the
  ticket. Its decode check only counts decoders; decoding a real frame is ticket 05.
- Push `windows-spike` when ready, so the Windows CI job runs and ticket 01 can close.
