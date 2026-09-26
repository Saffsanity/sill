# Pure checks

The parts of Sill that decide things (when the device looks for a Mac and which path a session
takes, the settings ledger, the wire format, pairing, who may use which door) are plain Swift files
that compile on their own. Each folder here compiles one or a few of those files, exactly as they
are in `Sources/` and `iOSClient/`, together with its own `main.swift`, and runs the result. Nothing
here needs a device, Screen Recording, Accessibility, the video encoder or any network but
loopback, so the checks run anywhere Xcode does, and in CI (`.github/workflows/ci.yml`) on pull
requests and pushes to `main`.

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
| `fence` | `iOSClient/SessionLink.swift`, `Sources/StreamProtocol/StreamMessage.swift` | the session's fenced hand-overs, hold, adopt, unhold and a new session dropping a hand-over, against a stand-in Mac on loopback: 600 numbered inputs arrive complete and in order | 14 modes | 19 |
| `ledger` | `iOSClient/HostSettingsLedger.swift`, `Sources/StreamProtocol/HostSettings.swift` | the device's settings ledger against a model host, scenarios and 5,000 random runs | 90 | none |
| `origin` | `Sources/SillHost/OriginPolicy.swift`, `InterfaceSnapshot.swift` | which door a connection may use, by source address and interface; the last cases read this Mac's own interfaces (read-only) | 66 | 10 |
| `pairing-address` | `Sources/SillMenuBar/PairingWindowAddress.swift` with `AddressList`, `OriginPolicy` and `Sources/StreamProtocol` (`build.sh`) | the address the pairing window gives to type, with 5,000 random runs | 80 | 35 |
| `policy` | `iOSClient/DiscoveryPolicy.swift` | when the device looks nearby, its rows and their words, the route word, the wired dial, reconnects, the move off AWDL, a session following the best path (the cable, Wi-Fi, Direct) and the remote rule | 286 | 70 |
| `protocol` | `Sources/StreamProtocol/*.swift`, then `crosscheck.py` | the address parser, SafeText, pairing codes and proofs, tags, the Mac ID, the certificate, kind 18's signature, framing, and TLS 1.3 with pinned keys on loopback; the cross-check repeats the certificate and signature with Python and `/usr/bin/openssl` | 188 + 8 | 20 |
| `remote-rules` | `iOSClient/DiscoveryPolicy.swift`, `RemoteDialPolicy.swift`, `SavedMacs.swift` with `Sources/StreamProtocol` (`build.sh`) | the Remote rows and automatic remote dial, the order a saved Mac's addresses are tried in, what a failure means, saved Macs | 64 | 35 |

The counts are those of main at 1f3072a, where every check passes and every mutant is caught.

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
it. `ledger`'s old mutants were whole copies of an older ledger, so it has none.

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

- `encoder-two-in-flight`: EncoderMailbox (`Sources/SillHost/EncoderMailbox.swift`, only on that
  branch) and the encoder checks built on it. The branch carries them as `Scripts/encoder-check/`
  (`mailbox` with its mutants, `probe`, `encoder`; `Scripts/encoder-check/run.sh`), which refuse to
  run any binary that links VideoToolbox. When it merges, move them here (or call that script from
  `ci.yml`).
- `update-notice`: it adds kind 23 (the device's hello), so `protocol/main.swift`'s case "kind 23 is
  unknown (skipped)" becomes "kind 23 is hello (update-notice), 24 unknown (skipped)" in that merge.
- `home-pairing` and `remote-bundle` are plans so far, without checks.
