# Pure checks

The parts of Sill that decide things (when the device looks for a Mac and which path a session
takes, the settings ledger, the wire format, pairing, who may use which door, how frames go into the
video encoder and when a stream gets a new encoder session, which device versions a Mac serves, how a
session ends, what the update check makes of GitHub's answer, how the Mac download's disk image lays
out its window, what the Mac sends of its menus and what the device makes of it) are plain Swift files that compile on their own. Each folder here compiles one or a
few of those files, exactly as they are in `Sources/`, `iOSClient/` and `Scripts/`, together with
its own `main.swift`, and runs the result. Nothing here needs a device, Screen Recording,
Accessibility, the video encoder or any network but loopback, so the checks run anywhere Xcode does,
and in CI (`.github/workflows/ci.yml`) on pull requests and pushes to `main`.

```
Tests/checks/run-all.sh                   # every check, about two minutes on an M-series Mac
Tests/checks/run-all.sh policy fence      # only these
Tests/checks/policy/run.sh                # one check, with its whole output
Tests/checks/run-all.sh --mutants         # also the mutants: most of an hour
```

`run-all.sh` prints one line per check and, for a failing one, its `FAIL` lines and last lines; its
exit status is the number of checks that failed. Binaries, data and logs go to
`.build/checks/<name>/`. A check prints `ok` or `FAIL` per case and exits non-zero on any failure.

## The checks

| Check | Compiles | What it checks | Cases | Mutants |
|---|---|---|---|---|
| `addresses` | `Sources/SillHost/AddressList.swift`, `PairingWindow.swift` and `OriginPolicy.swift` with `Sources/StreamProtocol` (`build.sh`) | the addresses the Mac offers for remote access, from its services and tunnels; the pairing window's proofs, tries and back-off | 41 | 15 |
| `clientlink` | `Sources/SillHost/ClientLink.swift` (`-package-name sill`) | which route a device came by, from its endpoint's scope and path, and the menu card's word for it | 89 | 14 |
| `dmg-layout` | `Scripts/dmg-layout/DSStore.swift`, `FinderAlias.swift`, `DMGLayout.swift` (with make-dmg.sh's layout arguments and `design/DMGBackground.svg`) | the `.DS_Store` of Sill.dmg's window byte by byte against Finder's own layout of the file (blocks, free lists, header), the window's bounds (the picture and macOS 27's 32-point title bar), view options and icon places; the background's alias field by field; the encoder and decoder, a two-level tree among them; the volume icon's flag; an alias for a real file where it runs; that make-dmg.sh and the SVG still give that window | 70 | 43 |
| `encoder-mailbox` | `Sources/SillHost/EncoderMailbox.swift` | HEVCEncoder's frames on their way into VideoToolbox (one inside, the one-slot mailbox, the watchdog's clock, timestamps, keyframe requests, `abandon`, the teardown) through a copy of HEVCEncoder's glue around a stand-in for VideoToolbox, in virtual time; a binary that links VideoToolbox is refused | 38,256 | 27 |
| `encoder-slowstate` | `Sources/SillHost/EncoderSlowState.swift` | when a hardware stream's session has settled in the encoder's slow state and gets a new one, and how the new one is judged: the rule at its edges, and streams in virtual time against a scripted engine; a binary that links VideoToolbox is refused | 1,207 | 29 |
| `compatibility` | `Sources/StreamProtocol/*.swift` | `SillVersion` (tags, bundles and the wire's versions, and their order), `SillProtocol`, and the update notice's payloads: kind 23's hello, kind 22's new fields with the five older goodbyes byte for byte, the window list's `hostVersion` and `protocol` | 74 | 13 |
| `device-gate` | `Sources/SillHost/DeviceGate.swift` with `Sources/StreamProtocol` (`build.sh`, `-package-name sill`) | the host's device floor: which hello it admits, the refusal's words, the Refused, count and hello lines, the shipped floor "0" | 58 | 14 |
| `fence` | `iOSClient/SessionLink.swift`, `Sources/StreamProtocol/StreamMessage.swift` | the session's fenced hand-overs, hold, adopt, unhold and a new session dropping a hand-over, against a stand-in Mac on loopback: 600 numbered inputs arrive complete and in order, whatever the machine's speed (each step waits for what it needs, not a set time) | 14 modes | 20 |
| `goodbye` | `iOSClient/GoodbyePolicy.swift` with `Sources/StreamProtocol` (`build.sh`) | how a session ends after the Mac's goodbye: today's five reasons, "update" and reasons the device does not know, the message cleaned, when it reconnects | 42 | 16 |
| `ledger` | `iOSClient/HostSettingsLedger.swift`, `Sources/StreamProtocol/HostSettings.swift` | the device's settings ledger against a model host, scenarios and 5,000 random runs | 90 | none |
| `menu-state` | `iOSClient/MacMenuState.swift` with `Sources/StreamProtocol` (`build.sh`) | the device's view of the Mac's menus (docs/menu-bar-plan.md §7.2): the top level, fetches joined, answered, refused, timed out, a new tree and a move's hand-over, choices and their refusals, stale menus, a bar menu built from an older top level asking by its title, the rows and sections; then 5,000 random sessions in which every opened menu's completion is settled exactly once | 118 and 5,000 sessions | 26 |
| `menus` | `Sources/SillHost/MenuFormat.swift` and `MenuPolicy.swift` with `Sources/StreamProtocol` (`build.sh`, `-package-name sill`) | kinds 24, 25 and 27 and MacMenu.swift's JSON; the Mac's shortcuts as it draws them (modifiers, special and function keys, glyphs); items, ids and paths; the 1 s cache and the wait after an app is brought forward; the request rates; the press decision (only a leaf whose title now is the one shown); the refusals' words and the log's path | 279 | 33 |
| `origin` | `Sources/SillHost/OriginPolicy.swift`, `InterfaceSnapshot.swift` | which door a connection may use, by source address and interface; the last cases read this Mac's own interfaces (read-only) | 66 | 10 |
| `pairing-address` | `Sources/SillMenuBar/PairingWindowAddress.swift` with `AddressList`, `OriginPolicy` and `Sources/StreamProtocol` (`build.sh`) | the address the pairing window gives to type, with 5,000 random runs | 80 | 35 |
| `policy` | `iOSClient/DiscoveryPolicy.swift` | when the device looks nearby, its rows and their words, the route word, the wired dial, reconnects, the move off AWDL, a session following the best path (the cable, Wi-Fi, Direct) and the remote rule | 286 | 70 |
| `protocol` | `Sources/StreamProtocol/*.swift`, then `crosscheck.py` | the address parser, SafeText, pairing codes and proofs, tags, the Mac ID, the certificate, kind 18's signature, framing, and TLS 1.3 with pinned keys on loopback; the cross-check repeats the certificate and signature with Python and `/usr/bin/openssl` | 188 + 8 | 20 |
| `remote-rules` | `iOSClient/DiscoveryPolicy.swift`, `RemoteDialPolicy.swift`, `SavedMacs.swift` with `Sources/StreamProtocol` (`build.sh`) | the Remote rows and automatic remote dial, the order a saved Mac's addresses are tried in, what a failure means, saved Macs | 64 | 35 |
| `update-policy` | `Sources/SillMenuBar/UpdatePolicy.swift` with `Sources/StreamProtocol` (`build.sh`) | Sill.app's update check: what each answer from GitHub's releases feed means, the offer, the schedule, the feeds and pages it accepts, every text | 124 | 18 |

The counts are those of main at 1f3072a, where every check passes and every mutant is caught; the
two encoder checks' are those of the encoder-two-in-flight branch that brought them, the four the
`update-notice` branch brought (`compatibility`, `device-gate`, `goodbye`, `update-policy`) those of
its merge with main at 32d532b, `dmg-layout`'s those of the `mac-dmg` branch that brought it, and
`menus`' and `menu-state`'s those of the `menu-bar-mirror` branch.

A mutant changes the checked file in one place and must make the check fail: `run.sh --mutants`
(or `run-all.sh --mutants`) passes only when the script's last line counts every mutant as caught.
A mutants script also stops when the text it replaces is no longer in the file ("pattern found 0
times", "NOT APPLIED"): update the pattern together with the code.

When a change makes a check fail, either the change is wrong or the check's expectation moves
with it, in the same commit.

## Where they came from

Each check was written beside the change it verifies (the plans in `docs/` and CLAUDE.md's entries
name them: H2, H3, H13 and so on) and moved here unchanged except for paths: the compile line in a
`main.swift`'s header comment, and the `policy`, `fence` and `clientlink` mutants scripts, which
named absolute paths and wrote beside themselves; they now read the repository and write to
`.build/checks/<name>/`. The others take the repository's root as their argument, as `run.sh` passes
it. `ledger`'s old mutants were whole copies of an older ledger, so it has none. `encoder-mailbox`
and `encoder-slowstate` came with encoder-two-in-flight, which had them as
`Scripts/encoder-check/mailbox` and `slowstate`; its two real-time encoder checks (`probe`, the
re-check's loop against a stand-in encoder, and `encoder`, the real HEVCEncoder against a stand-in
VideoToolbox) stay in `Scripts/encoder-check/run.sh`, which runs these two as well: their timing
bounds are tight for a shared runner. The `update-notice` branch's four came the same way at its
merge: each `main.swift` as it was (the plan's H3; only `compatibility`'s header comment names its
compile line now), and each list of mutants, a JSON file beside it there, the same mutants in a
`mutants.py`. `dmg-layout` was written for the `mac-dmg` branch, after its review: its allocator
expectations are those of a Finder-made image's `.DS_Store` (an installer image of 2023, which is
not in the repository), and its run reads make-dmg.sh's layout by sourcing the script, which then
only defines its functions. `menus` and `menu-state` were written for `menu-bar-mirror` (the plan's
H3); the menu reader and mirror, which need Accessibility and an app to read, are checked against a
fixture app by `Scripts/menu-check/run.sh`, outside CI.

## Adding a check

A folder with a `main.swift` (prints `ok` or `FAIL` per case, exits non-zero on any failure) and a
`run.sh` that sets `here`, sources `../common.sh` (which sets `root` and `out` and changes to the
root) and compiles with `swiftc` into `"$out"`. A `mutants.py` is optional; its last line must count
the mutants (`N of M mutants caught`, or `mutants caught: N of M`), and `run.sh --mutants` hands it
to `run_mutants`; add the check's name to the `mutants` matrix in `.github/workflows/ci.yml` too.
`run-all.sh` picks up every folder with a `run.sh`, and fails a check whose `run.sh` is not
executable (`chmod +x`; git keeps the bit) rather than skip it. Only pure files: nothing that needs
a permission, a device or the network, and never anything that links VideoToolbox.

## Checks that belong to open branches

- `update-notice`: it adds kind 23 (the device's hello), so `protocol/main.swift`'s case "kind 23 is
  unknown (skipped)" becomes "kind 23 is hello (update-notice), 24 unknown (skipped)" in that merge.
- `encoder-two-in-flight`: EncoderMailbox (`Sources/SillHost/EncoderMailbox.swift`, only on that
  branch) and the encoder checks built on it. The branch carries them as `Scripts/encoder-check/`
  (`mailbox` with its mutants, `probe`, `encoder`; `Scripts/encoder-check/run.sh`), which refuse to
  run any binary that links VideoToolbox. When it merges, move them here (or call that script from
  `ci.yml`).
- `home-pairing` and `remote-bundle` are plans so far, without checks.
- `pointer-visibility` (kind 26) and `trackpad-gestures` (kind 28): `protocol` expects 26 and 28 to
  read as `.unknown`, and `menus` 26; the branch that brings either flips those cases.
