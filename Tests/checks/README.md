# Pure checks

The parts of Sill that decide things (when the device looks for a Mac and which path a session
takes, the settings ledger, the wire format, pairing, who may use which door, which device versions a
Mac serves, how a session ends, what the update check makes of GitHub's answer, how frames go into
the video encoder and when a stream gets a new encoder session, and pairing at home: who each door
admits, what counts as the USB cable, the device's home rows and dials) are plain Swift files that
compile on their own. Each folder here compiles one or a few of those files, exactly as they are in
`Sources/` and `iOSClient/`, together with its own `main.swift`, and runs the result. Nothing here
needs a device, Screen Recording, Accessibility, the video encoder or any network but loopback, so
the checks run anywhere Xcode does, and in CI (`.github/workflows/ci.yml`) on pull requests and
pushes to `main`.

```
Tests/checks/run-all.sh                   # every check, about three minutes on an M-series Mac
Tests/checks/run-all.sh policy fence      # only these
Tests/checks/policy/run.sh                # one check, with its whole output
Tests/checks/run-all.sh --mutants         # also the mutants: well over an hour
```

`run-all.sh` prints one line per check and, for a failing one, its `FAIL` lines and last lines; its
exit status is the number of checks that failed. Binaries, data and logs go to
`.build/checks/<name>/`. A check prints `ok` or `FAIL` per case and exits non-zero on any failure.

## The checks

| Check | Compiles | What it checks | Cases | Mutants |
|---|---|---|---|---|
| `addresses` | `Sources/SillHost/AddressList.swift`, `PairingWindow.swift` and `OriginPolicy.swift` with `Sources/StreamProtocol` (`build.sh`) | the addresses the Mac offers for remote access, from its services and tunnels; the pairing window's proofs, tries and back-off | 41 | 15 |
| `ask-limits` | `Sources/SillHost/PairingWindow.swift` with `Sources/StreamProtocol` (`module.txt`) | the limits on a device's asks to pair at home: 10 minutes of quiet by key and by address, 3 device-opened windows in any 10 minutes, the test override | 27 | 15 |
| `cable-link` | `Sources/SillHost/CableLink.swift` and `OriginPolicy.swift` with `Sources/StreamProtocol` (`module.txt`) | what counts as the USB cable to an iPhone or iPad, from this Mac's own IOKit readings with an iPad on the cable; the device ID; the test stand-in | 40 | 20 |
| `clientlink` | `Sources/SillHost/ClientLink.swift` (`-package-name sill`) | which route a device came by, from its endpoint's scope and path, and the menu card's word for it | 89 | 14 |
| `compatibility` | `Sources/StreamProtocol/*.swift` | `SillVersion` (tags, bundles and the wire's versions, and their order), `SillProtocol`, and the update notice's payloads: kind 23's hello, kind 22's new fields with the five older goodbyes byte for byte, the window list's `hostVersion` and `protocol` | 75 | 13 |
| `device-gate` | `Sources/SillHost/DeviceGate.swift` with `Sources/StreamProtocol` (`build.sh`, `-package-name sill`) | the host's device floor: which hello it admits, the refusal's words, the Refused, count and hello lines, the shipped floor "0" | 58 | 14 |
| `door-policy` | `Sources/SillHost/DoorPolicy.swift`, `OriginPolicy.swift` and `PairingWindow.swift` with `Sources/StreamProtocol` (`module.txt`) | who each door admits: both doors, each origin, each application protocol, Require pairing on and off, paired or not, a window or not; the ask rule's six steps in order; what a session the device gate held is judged by as the gate admits it (`afterGate`); which hosts take the test hooks; a kind 19 of another generation answered `closed`, no try counted | 118 | 51 |
| `encoder-mailbox` | `Sources/SillHost/EncoderMailbox.swift` | HEVCEncoder's frames on their way into VideoToolbox (one inside, the one-slot mailbox, the watchdog's clock, timestamps, keyframe requests, `abandon`, the teardown) through a copy of HEVCEncoder's glue around a stand-in for VideoToolbox, in virtual time; a binary that links VideoToolbox is refused | 38,256 | 27 |
| `encoder-slowstate` | `Sources/SillHost/EncoderSlowState.swift` | when a hardware stream's session has settled in the encoder's slow state and gets a new one, and how the new one is judged: the rule at its edges, and streams in virtual time against a scripted engine; a binary that links VideoToolbox is refused | 1,207 | 29 |
| `fence` | `iOSClient/SessionLink.swift`, `Sources/StreamProtocol/StreamMessage.swift` | the session's fenced hand-overs, hold, adopt, unhold and a new session dropping a hand-over, against a stand-in Mac on loopback: 600 numbered inputs arrive complete and in order, whatever the machine's speed (each step waits for what it needs, not a set time) | 14 modes | 20 |
| `goodbye` | `iOSClient/GoodbyePolicy.swift` with `Sources/StreamProtocol` (`build.sh`) | how a session ends after the Mac's goodbye: the five older reasons and "pairingRequired", "update" and reasons the device does not know, the message cleaned, when it reconnects | 45 | 18 |
| `home-device` | `iOSClient/DiscoveryPolicy.swift` (`module.txt`) | the device's home rules: every row's word and what a tap dials, DEBUG and Release, `homeTLS` and `revoked`; the device's cable check; the rows' VoiceOver labels and hints | 128 | 79 |
| `home-model` | `iOSClient/DiscoveryPolicy.swift` and `SavedMacs.swift` with `Sources/StreamProtocol` (`module.txt`) | the home rules against the wire's own values (its strings, a real kind 20, a real TXT tag), then pairing at home walked end to end as StreamClient chains the rules | 34 | 11 |
| `home-records` | `Sources/SillHost/HostIdentity.swift`, `CableLink.swift` and `OriginPolicy.swift` and `iOSClient/SavedMacs.swift` with `Sources/StreamProtocol` (`module.txt`, `-package-name sill`) | the records pairing at home adds to (the Mac's `cableDevice` and "cable", the device's `homeTLS` and `revoked`): older records decode, lists encode byte for byte as before, an older reader reads the new ones | 30 | 16 |
| `home-txt` | `Sources/StreamProtocol/*.swift` (`module.txt`) | pairing at home's wire values: the TXT record's `p` (HomeDoorTXT), kinds 19, 20 and 22 as the plan shows them on the wire, kind 20's `message` and the reasons a device words itself, the RemoteTLS parameters for the home door | 49 | 24 |
| `ledger` | `iOSClient/HostSettingsLedger.swift`, `Sources/StreamProtocol/HostSettings.swift` | the device's settings ledger against a model host, scenarios and 5,000 random runs | 90 | none |
| `origin` | `Sources/SillHost/OriginPolicy.swift`, `InterfaceSnapshot.swift` | which door a connection may use, by source address and interface; the last cases read this Mac's own interfaces (read-only) | 66 | 10 |
| `pairing-address` | `Sources/SillMenuBar/PairingWindowAddress.swift` with `AddressList`, `OriginPolicy` and `Sources/StreamProtocol` (`build.sh`) | the address the pairing window gives to type, with 5,000 random runs | 80 | 35 |
| `policy` | `iOSClient/DiscoveryPolicy.swift`, with `main.swift` and `home.swift` | when the device looks nearby, its rows and their words, the route word, the wired dial, reconnects, the move off AWDL, a session following the best path (the cable, Wi-Fi, Direct) and the remote rule; pairing at home's session rules (`home.swift`: the pin, the trust a dial starts, how a session at home ends, the ask's answer, the words) | 336 | 105 |
| `protocol` | `Sources/StreamProtocol/*.swift`, then `crosscheck.py` | the address parser, SafeText, pairing codes and proofs, tags, the Mac ID, the certificate, kind 18's signature, framing, and TLS 1.3 with pinned keys on loopback, the two ALPNs every host offers for good among them; the cross-check repeats the certificate and signature with Python and `/usr/bin/openssl` | 190 + 8 | 23 |
| `remote-rules` | `iOSClient/DiscoveryPolicy.swift`, `RemoteDialPolicy.swift`, `SavedMacs.swift` with `Sources/StreamProtocol` (`build.sh`), with `main.swift` and `home.swift` | the Remote rows and automatic remote dial, the order a saved Mac's addresses are tried in, what a failure means, saved Macs; pairing at home's model and the saved Macs' home fields (`home.swift`) | 102 | 52 |
| `update-policy` | `Sources/SillMenuBar/UpdatePolicy.swift` with `Sources/StreamProtocol` (`build.sh`) | Sill.app's update check: what each answer from GitHub's releases feed means, the offer, the schedule, the feeds and pages it accepts, every text | 124 | 18 |

The counts are those of the `home-pairing` branch's merge with main at cf05a78, where every check
passes and every mutant is caught (docs/home-pairing-plan.md, Results, "The merge with main").

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
it. `ledger`'s old mutants were whole copies of an older ledger, so it has none. The `update-notice`
branch's four came the same way at its merge: each `main.swift` as it was (the plan's H3; only
`compatibility`'s header comment names its compile line now), and each list of mutants, a JSON file
beside it there, the same mutants in a `mutants.py`. `encoder-mailbox` and `encoder-slowstate` came
with encoder-two-in-flight, which had them as `Scripts/encoder-check/mailbox` and `slowstate`; its
two real-time encoder checks (`probe`, the re-check's loop against a stand-in encoder, and
`encoder`, the real HEVCEncoder against a stand-in VideoToolbox) stay in
`Scripts/encoder-check/run.sh`, which runs these two as well: their timing bounds are tight for a
shared runner.

Pairing at home's came with the `home-pairing` branch, from its own scratch folder, at its merge
with main: `door`, `cable`, `asklimits`, `records`, `device`, `hometxt` and `home` there are
`door-policy`, `cable-link`, `ask-limits`, `home-records`, `home-device`, `home-txt` and
`home-model` here, each `main.swift` and list of mutants as it was but for its name, and the helper
that built them (`lib.py` there) is `module.py`, which compiles the files a check's `module.txt`
lists as one module. Its additions to `policy` and `remote-rules` (`step4.swift` there) are each
folder's `home.swift`. `door-policy` gained the cases and mutants of `afterGate`, which the merge
added, and `goodbye` its "pairingRequired" cases: it and `compatibility` had used that reason as
one the device does not know, which is "pairAgain" in both now.

## Adding a check

A folder with a `main.swift` (prints `ok` or `FAIL` per case, exits non-zero on any failure) and a
`run.sh` that sets `here`, sources `../common.sh` (which sets `root` and `out` and changes to the
root) and compiles with `swiftc` into `"$out"`; or, for files that compile as one module with
StreamProtocol's sources, a `module.txt` naming them and a `run.sh` that hands the check to
`../module.py`, as `door-policy/run.sh` does. A `mutants.py` is optional; its last line must count
the mutants (`N of M mutants caught`, or `mutants caught: N of M`), and `run.sh --mutants` hands it
to `run_mutants`; add the check's name to the `mutants` matrix in `.github/workflows/ci.yml` too.
`run-all.sh` picks up every folder with a `run.sh`, and fails a check whose `run.sh` is not
executable (`chmod +x`; git keeps the bit) rather than skip it. Only pure files: nothing that needs
a permission, a device or the network, and never anything that links VideoToolbox.

## Checks that belong to open branches

- `remote-bundle` is a plan so far, without checks.
