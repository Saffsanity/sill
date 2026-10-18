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
| 02 | Confirm the Windows facts (build, HEVC, TLS 1.3 + ALPN, decode) | research | none | open |
| 03 | Pairing client over TLS (`sill-pair/1`) | prototype | 01, 02 | open |
| 04 | Session connection and frame parsing (`sill/1`) | prototype | 03 | open |
| 05 | Decode one frame to a PNG (Media Foundation) | prototype | 04 | open |
| 06 | Conformance run with the Mac side | task | 05 | open |

## Log

- 2026-10-17: map and tickets made; ticket 01 built: `Sill.Protocol` (the 14-byte header,
  matching the Swift serializer byte for byte), `Sill.Spike` (placeholder),
  `Sill.Protocol.Tests` (10 tests pass); `.github/workflows/windows.yml`; `Windows/**` left
  out of ci.yml. The .NET 10 SDK installed on the Mac with `brew install dotnet`.

## Next

- Ticket 02: a probe in `Windows/` to run on the PC (TLS 1.3 with ALPN, the HEVC decoder),
  plus `winver` and the HEVC Video Extensions check by hand.
- Push `windows-spike` when ready, so the Windows CI job runs and ticket 01 can close.
