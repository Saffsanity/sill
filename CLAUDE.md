# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

This file stays lean (Noah, 2026-11-18): every turn of every agent reads it, so it holds rules and
pointers only. What a file, folder or type does goes in docs/LAYOUT.md; a command, test hook or
harness argument in docs/BUILD-AND-RUN.md; a rule of the wire in docs/COMPATIBILITY.md; what a piece
of work did in its step file. `Tests/checks/repo-rules` fails it past 12,000 bytes.

## Steps

What each piece of work did (a branch, a release, a finding) is in `docs/steps/`, one file each,
`<date>-<branch>.md` with the date the work began: `Scripts/steps.sh list` prints the newest first,
`Scripts/steps.sh find 349` a pull request's, `ls docs/steps/*keep-vpn*` a branch's. Before
starting, read the step file of the work you continue and the newest few.

A branch writes its notes in its own step file (`Scripts/steps.sh new` makes it), never in this
file, so no two branches edit the same lines for their notes. Until 2026-11-12 the notes were this
file's "Current step"; `docs/steps/README.md` lists them in their old order. A code comment that
cites `CLAUDE.md, "<title>"` (or "Current step") means the step file with that title:
`grep -l '<title>' docs/steps/*`. A branch opened before 2026-11-12, or one that changed this
file's Layout, Build and run or Compatibility floor before they moved to docs/, runs
`python3 Scripts/migrate-notes.py` once, right after merging main (the script's header says how).

Rules found in the steps that hold for all work (each where it is written):
- While Noah streams, nothing that shares the Mac's one video encoder: no `simctl io recordVideo`,
  SillHost stream, ReelRenderer or encoder benchmark, and no Simulator panel in the Claude app
  (docs/steps/2026-09-24-encoder-recovery.md, "Operational rule").
- Host code: `SillHostCore`'s `package` access, never `MainActor.assumeIsolated` in core code, the
  modal-loop rule, the CLI's byte-identical stdout, App Nap; TCC and the signing identity
  (docs/steps/2026-09-23-menu-bar-app.md, "Rules." and "TCC:").
- ScreenCaptureKit sends frames only when a window repaints, so a covered window freezes on the
  device (docs/steps/2026-09-22-milestone-1.md, "Learned"), and AWDL takes the Mac's radio off its
  Wi-Fi channel (docs/steps/2026-09-22-trackpad-stutter.md).
- Simulators: harness photos on the agents' own pair only, through `Scripts/harness-photos.sh`, which
  keeps the rules itself (one booted at a time, inside the heavy lock, never one Noah made, nothing
  that reaches a Mac); no agent makes or deletes a simulator of its own for photos
  (docs/steps/2026-11-12-tooling-speedup.md).

## Layout

Every file and folder, what it holds and what checks it: docs/LAYOUT.md (this section until
2026-11-18). The code: `Sources/StreamProtocol/` (the wire, shared by both sides),
`Sources/SillHost/` (the host, `SillHostCore`), `Sources/SillMenuBar/` (Sill.app),
`Sources/SillHostCLI/` (the CLI, `SillHost`) and `iOSClient/` (Sill for iPhone and iPad; a new file
needs its four pbxproj entries by hand). Where the rest is written:
- docs/BUILD-AND-RUN.md — every command, test hook (`SILL_TEST_…`) and harness argument (`-Sill…`).
- docs/COMPATIBILITY.md — the compatibility floor in full.
- docs/DEVELOPMENT.md — building, running and testing from source, for people.
- docs/BRIEF.md — product decisions, competition, scope, risks.
- docs/release-checklist.md — releases, TestFlight, nightlies, CI's secrets.
- docs/*-plan.md — each feature's plan, its results and Noah's answers.
- Tests/checks/*/README.md — what each pure check checks (`Tests/checks/list.sh` prints them all).

## Build and run

Every command, test hook and harness argument: docs/BUILD-AND-RUN.md (this section until
2026-11-18). Read it before running a host, Sill.app or a harness: its "never"s bind every test.
What every piece of work runs:

```
swift build -c release                  # the Mac side
Tests/checks/run-all.sh                 # every pure check, as CI runs them (~5 min; or name some)
Scripts/steps.sh new | list | find 349  # this branch's step file, the newest, a pull request's
```

A headless test host is `--synthetic` with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1
SILL_TEST_NO_ROUTER=1`, and `SILL_TEST_NO_SCREEN=1` unless its test needs a real window: on
127.0.0.1 alone, never the hardware encoder or the router, asking macOS for no screen recording.
Test input goes only to such a host on this Mac, and no test runs against GitHub.

## Compatibility floor

The first public builds set it for good: every later host keeps serving devices from the first
public build on, and every later device keeps working with Macs from it, or each says why. In full:
docs/COMPATIBILITY.md (this section until 2026-11-18). In short:
- Additive only: new fields optional, never renamed or retyped; kind numbers never reused; no new
  case in an enum an older peer decodes.
- Anything new (a kind, a field, a case, a generation) goes only to a peer that said it takes it, in
  its hello or its window list, unless an older peer skips it unharmed.
- A device is refused, never served wrong: kind 22 "update" before anything else.
- `SillProtocol.current` (1) rises only with a change an older peer cannot skip; every host offers
  the ALPNs `sill/1` and `sill-pair/1` for good.

## Conventions

- Swift, Apple frameworks only. No third-party dependencies unless a decision
  in `docs/BRIEF.md` says so. Zero operating costs is a hard rule.
- Threading in the spike is by hand: capture queue → VT callback thread →
  network queue. Keep it explicit and commented rather than reaching for actors
  until the design settles.
- HEVC, no B-frames, real-time mode. AV1 is out (no hardware encode on Apple
  silicon as far as we know).
- Latency beats quality. Drop frames before queuing them.
- Don't add features the current milestone doesn't need.

## Decisions already made (don't relitigate without asking Noah)

- Free app, tip jar, open source. Not paid, not subscription.
- iCloud auto-pairing (same Apple Account, Mac just appears) for milestone 5.
  Bonjour only for the spike.
- Native feel is the bar: Flighty-level polish, iOS conventions, Duo layouts.
- License: Apache-2.0, LICENSE since PR #15, kept when the repository went
  public on 2026-09-26 (paid plan is gone, so no GPL/CLA needed).
- v1 out of scope: hole punching, multi-window, layout customization. Audio is in scope since
  2026-09-27 (Noah: "Audio: the plan is done and parked as a v2 feature by your earlier decision",
  first in what he wanted worked on; docs/audio-plan.md, docs/BRIEF.md), and in, as a beta, since
  2026-10-20 (Noah, about PR #94: "merge as beta support"): Send Audio, off by default. Since
  2026-10-27 (Noah: "Sound should be a toggle in the settings menu") the Mac's menu and Settings and
  a device's Settings panel set it for every device, and each device's Mute is its own; no Sound
  button in the bar.
