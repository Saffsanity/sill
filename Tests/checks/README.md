# Pure checks

The parts of Sill that decide things (the rules, not the views: when the device looks for a Mac and
which path a session takes, what goes on the wire, who may use which door, what a host takes of a
device's input, where the layouts put things, and so on) are plain Swift files that compile on their
own. Each folder here compiles one or a few of those files, exactly as they are in `Sources/`,
`iOSClient/` and `Scripts/`, together with its own `main.swift`, and runs the result. Nothing here
needs a device, Screen Recording, Accessibility, the video encoder or any network but loopback, so
the checks run anywhere Xcode does, and in CI (`.github/workflows/ci.yml`) on pull requests and
pushes to `main`.

Each check says what it checks and what it compiles in its own folder's `README.md`, and
`Tests/checks/list.sh` prints them all; no list or table of the checks is kept by hand anywhere, so
a branch that adds or changes a check edits only its own folder. No count is written down either:
a check prints its own cases when it runs, and `run.sh --mutants` its mutants caught. The table
this file kept until 2026-11-12, with its counts and their history, is in `HISTORY.md`, frozen.

```
Tests/checks/run-all.sh                   # every check, about five minutes on an M-series Mac
Tests/checks/run-all.sh policy fence      # only these
Tests/checks/policy/run.sh                # one check, with its whole output
Tests/checks/run-all.sh --mutants         # also the mutants: well over an hour
Tests/checks/list.sh                      # every check and what it checks, from its README.md
```

`run-all.sh` prints one line per check and, for a failing one, its `FAIL` lines and last lines; its
exit status is the number of checks that failed. Binaries, data and logs go to
`.build/checks/<name>/`. A check prints `ok` or `FAIL` per case and exits non-zero on any failure.

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
it. `ledger`'s old mutants were whole copies of an older ledger, so it had none until the `audio`
branch wrote one-line ones (its rules 2, 4 to 7 and 9, and the sound's seventh field). The `update-notice`
branch's four came the same way at its merge: each `main.swift` as it was (the plan's H3; only
`compatibility`'s header comment names its compile line now), and each list of mutants, a JSON file
beside it there, the same mutants in a `mutants.py`. `encoder-mailbox` and `encoder-slowstate` came
with encoder-two-in-flight, which had them as `Scripts/encoder-check/mailbox` and `slowstate`; its
two real-time encoder checks (`probe`, the re-check's loop against a stand-in encoder, and
`encoder`, the real HEVCEncoder against a stand-in VideoToolbox) stay in
`Scripts/encoder-check/run.sh`, which runs these two as well: their timing bounds are tight for a
shared runner. `dmg-layout` was written for the `mac-dmg` branch, after its review: its allocator
expectations are those of a Finder-made image's `.DS_Store` (an installer image of 2023, which is
not in the repository), and its run reads make-dmg.sh's layout by sourcing the script, which then
only defines its functions. `menus` and `menu-state` were written for `menu-bar-mirror` (the plan's
H3); the menu reader and mirror, which need Accessibility and an app to read, are checked against a
fixture app by `Scripts/menu-check/run.sh`, outside CI. `asc` came from the nightly's harness of
2026-10-29 (PR #246, kept outside the repository until the What to Test fix of 2026-11-09): its 114
checks and 23 mutants as they were but for paths, the review's extra checks, What to Test's cases and
13 mutants, the sandbox, and a stand-in that no longer looks up 127.0.0.1's name when it binds (35 s on
a Mac whose DNS was slow that day). Its real-time wait for Beta App Review's state (about 15 minutes)
stays out.

Pairing at home's came with the `home-pairing` branch, from its own scratch folder, at its merge
with main: `door`, `cable`, `asklimits`, `records`, `device`, `hometxt` and `home` there are
`door-policy`, `cable-link`, `ask-limits`, `home-records`, `home-device`, `home-txt` and
`home-model` here, each `main.swift` and list of mutants as it was but for its name, and the helper
that built them (`lib.py` there) is `module.py`, which compiles the files a check's `module.txt`
lists as one module. Its additions to `policy` and `remote-rules` (`step4.swift` there) are each
folder's `home.swift`. `door-policy` gained the cases and mutants of `afterGate`, which the merge
added, and `goodbye` its "pairingRequired" cases: it and `compatibility` had used that reason as
one the device does not know, which is "pairAgain" in both now. `door-policy` gained `stillServes`'
cases and mutants with the `sec-revoked-input` branch's resumed review (security scan finding 10).

`text-composition` came with #147 (issue #138), its random sequences seeded since its polish, which also
gave it its mutants and `TextInputRules`; its Return and Tab cases, and their mutants, came with the
verification's fix (2026-10-26), and the fence that replaced that fix's forget at a Return, with its
chat, its cases and mutants F1 to F14 and J1 to J8 (Korean's rebuild across it, found live), with the
second verification's (the same day).

## Adding a check

A folder with a `README.md`, a `main.swift` (prints `ok` or `FAIL` per case, exits non-zero on any
failure) and a `run.sh` that sets `here`, sources `../common.sh` (which sets `root` and `out` and
changes to the root) and compiles with `swiftc` into `"$out"`; or, for files that compile as one
module with StreamProtocol's sources, a `module.txt` naming them and a `run.sh` that hands the check
to `../module.py`, as `door-policy/run.sh` does. The `README.md` starts with the check's name as a
heading (``# `door-policy` ``), then a `**Checks:**` paragraph (what it checks, in a sentence or a
few) and a `**Compiles:**` paragraph (the files it compiles and how): `list.sh` reads those two, and
`repo-rules` fails a check folder without them. A `mutants.py` is optional; its last line must
count the mutants (`N of M mutants caught`, or `mutants caught: N of M`), and `run.sh --mutants`
hands it to `run_mutants`. CI's
mutants matrix finds it by itself: `mutant-checks.py` lists every folder with a `mutants.py`, and
the run fails before any mutant starts if that list leaves one out. `run-all.sh` picks up every
folder with a `run.sh`, and fails a check whose `run.sh` is not executable (`chmod +x`; git keeps
the bit) rather than skip it. Only pure files: nothing that needs a permission, a device or the
network, and never anything that links VideoToolbox.

## Checks that belong to open branches

- `audio` (kind 43, the Mac's sound; docs/audio-plan.md): `protocol`, `pointer-control` and
  `compatibility` expect 28 to be the trackpad gesture, 32 the clipboard (#78, merged), 43 the
  sound, 44 the keyframe request (#93, merged), and the rest of 29 to 42 (PR #66's) and 45 and up
  to read as `.unknown` (`menus`: 28, 43 and 44, and 29 unknown). The audio mutants that renumber
  a kind do so onto numbers no plan will take, 250 to 254 (`menus`' "the fetch at 250",
  `pointer-control`'s "kind 26 numbered 251" and "… 252", `compatibility`'s "kind 28 as 250" and
  "kind 43 as 253", `protocol`'s "kind 43 as 254"), since a kind renumbered onto a taken one no
  longer compiles: the next kind moves none of them. The clipboard's renumber kind 32 onto 31
  (`compatibility`), 30 (`protocol`) and 33 (`clipboard`), which move if #66 takes those.

`remote-bundle`'s pacing (item 1) and the link's judgement (item 3), which merged with PR #39, are
also measured on the host's side by the pacing harness (`Scripts/pacing/run.sh`), which needs no
encoder but runs for minutes and on loopback at up to 600 Mbit/s, so it is not a pure check; their
pure parts are `message-reader`, `link-judge`, `away-wire`, `away-quality`, `away-copy` and the move
home's cases in `policy` and `fence`.
