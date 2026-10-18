# Windows client spike: progress

Read this first when picking up the Windows work. Keep it current: update it in the same
commit as the work it describes (the status line, the ticket's row, a dated log entry, Next).

## Status (2026-10-18)

Tickets 01 to 03 are built and committed on `windows-spike`, which has not been pushed. Ticket 02
is answered from the PC (`msi`, reached over SSH: `~/fleet/hosts/msi.md`): Windows 11 25H2, build
26200, SChannel does TLS 1.3 with ALPN, HEVC Video Extensions is installed. Ticket 03 is done: the
spike pairs with `SillHost --pairing` by typed code and by link, and a wrong code is refused. Waiting
on: a push so the Windows CI job runs (ticket 01). Next: ticket 04, the session.

| Commit | What |
|---|---|
| `5d4acda` | The .NET skeleton, its CI job, this file, the agent-skills setup (`docs/agents/`, CLAUDE.md) |
| `82a4924` | Ticket 02's probe, `src/Sill.Probe`, and its README section |
| `d3a00b3` | Ticket 03's pure half: `Identity.cs`, `Pairing.cs`, `PairLink.cs`, `PairMessages.cs`, `SafeText.cs`, 57 tests |

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
| 10 | Windows PC | HEVC Video Extensions installed, Windows 11 or 10 22H2: `msi`, Windows 11 25H2 build 26200.9457 |
| 11 | Mac capture | Screen Recording granted to Terminal, then `SillHost --pairing` |

Out of scope: the Windows host, a Mac client, discovery, camera QR, signing and
distribution, input, menus, gestures, clipboard.

## Tickets

| # | Ticket | Type | Blocked by | Status |
|---|---|---|---|---|
| 01 | Windows solution skeleton and CI job | task | none | claimed: done locally, CI not run (needs a push) |
| 02 | Confirm the Windows facts (build, HEVC, TLS 1.3 + ALPN, decode) | research | none | done (decoding a frame moved to 05) |
| 03 | Pairing client over TLS (`sill-pair/1`) | prototype | 01, 02 | done |
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

- 2026-10-18: this file gained the status section and the open questions.

- 2026-10-18: ticket 03's pure half in `Sill.Protocol`: `Base64Url`, `Spki` (equal to .NET's own
  `ExportSubjectPublicKeyInfo`), `MacId`, `PairingCode` (Damm), `PairingProof` (PBKDF2 600k,
  HMAC proofs), `PairLink`, `SafeText`, `PairRequest`/`PairResult` (nulls left out, as Swift),
  `PairingExchange` (the kind 19 to send; a kind 20 judged as the iOS device judges it, with its
  words) and `MessageStream.ReadAsync`. The plan's vectors (docs/remote-access-plan.md §3.4, §3.6)
  match exactly; a link made with Python as `PairLink.url` escapes it parses. 67 tests pass on the
  Mac. Simplification: a link's `a` addresses are kept as text, as sillclient.py does (the Swift
  address parser isn't ported; the spike dials a typed address).

## Open questions

- Should an ADR record the C# exception to the Swift-only rule? Only if it meets all three of
  the ADR criteria (`docs/agents/domain.md`). Not decided yet.
- Glossary terms (Door, pairing code, pairing link, `sill/1`, `sill-pair/1`, SPKI pin): added
  lazily when a ticket first needs them settled.

- 2026-10-18: ticket 02 answered on the PC (`msi`, over SSH; the .NET 10.0.402 SDK installed in
  the user's folder with `dotnet-install.ps1`, the branch copied as a git bundle). 67 tests pass
  there. The probe: Windows 11 Home 25H2, build 26200.9457, x64; TLS 1.3 with `sill-pair/1` on
  loopback (mutual P-256) and to `SillHost --synthetic --pairing` on the Mac, whose key matched its
  own link's `k`. The host stayed on loopback (`SILL_TEST_LOOPBACK`), reached through an SSH reverse
  forward (`ssh -R 47455:127.0.0.1:<port> msi`), so no port opened on the Mac. HEVC Video
  Extensions 2.5.33 is installed and the PC has Intel UHD and an RTX 3050, yet Media Foundation
  listed 1 HEVC decoder, 0 in hardware: probably because SSH is not the console's session; ticket
  05 counts again from the desktop.

- 2026-10-18: ticket 03's TLS half. `DeviceIdentity` (a P-256 key in a self-signed certificate,
  `device.p12` in a directory, loaded through PKCS #12 because SChannel can't use an in-memory key),
  `SillTls.ConnectAsync` (TLS 1.3, one ALPN, the device's certificate, trust by the Mac's SPKI
  SHA-256 in the validation callback: any P-256 key on the typed path, the link's `k` on the link's;
  `PinMismatchException`), `PairingClient` (one kind 19, one kind 20 within 15 s, judged by
  `PairingExchange`), and `Sill.Spike pair` (`--code` with `--host`, or `--link` with an optional
  `--host`; saves the Mac in `mac.json` for ticket 04). Six new tests, five of them TLS against a
  stand-in Mac on loopback that run only on Windows (`WindowsFact`): 73 pass on the PC, 68 with 5
  skipped on the Mac. Live on the PC against `SillHost --synthetic --pairing` (through the reverse
  forward): a wrong code refused ("4 tries left", the host's "a wrong code … (4 tries left)"), the
  right code then refused `busy` until the host's spacing after a wrong code ran out, then paired
  ("Paired MSI (Windows) … with the code"), and a second identity paired by link ("… with the QR
  code"); each checked proof_M and the Mac ID, and the saved fingerprint is the link's `k`.
  Found: SChannel's TLS 1.3 sends the device's certificate before .NET's validation callback judges
  the Mac's key, so a Mac the link does not name learns the device's public key (nothing else: no
  proof, no request). iOS's verify block runs before its certificate goes out. A test pins this down
  (`ALinkToAnotherKeySendsNothing`). Fixed on the way: the console's code page turned the Mac's
  typographic words into `?`; the spike now writes UTF-8.


## Next

- Push `windows-spike` when ready (only with the go-ahead), so the Windows CI job runs and ticket
  01 can close.
- Ticket 04: the session (`sill/1`) to the paired Mac from `mac.json`, pinned to its saved key:
  the hello (kind 23) first inside TLS, then the window list, a Desktop pick and the frames' headers
  parsed. Test on the PC as above (`SillHost --synthetic --pairing` on loopback, the reverse
  forward), pairing first in the same host run, since `--pairing` makes a throwaway identity.
- Decide whether the device certificate going to an unpinned key on Windows matters (it is public;
  hiding it needs the validation before the client's flight, which SslStream doesn't offer).
