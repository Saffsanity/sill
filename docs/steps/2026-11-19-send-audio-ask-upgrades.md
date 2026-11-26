**Send Audio: an update keeps what its user had (2026-11-19, branch `send-audio-ask-upgrades` from main at eb48ac9; issue #419).**

What: since #236 (2026-10-27) Sill.app registers Send Audio on, so every install that never saved the
`sendAudio` key got it on, including Macs updating from 0.5.x, which had no Send Audio. The first
stream after the update then played the Mac's sound on the device without its user choosing that.

Noah's rule (PR #420, 2026-11-24): an update keeps what a person had, and a fresh install starts on.
From 0.5.x: off. On 0.6.x with the switch left alone: on. Fresh install: on.

How: `HostSettings.init`, before it registers the defaults, asks
`HostConfig.sendAudioToSave(saved:settled:lastReleaseSeen:)`. No defaults key tells 0.5.x from 0.6.x
(neither writes one at launch), so the update check's `updateLatestTag` does: on by default and daily,
so a tag before 0.6.0 (`releaseBeforeSendAudio`) means this Mac has not run 0.6.x since. Then it saves
`sendAudio` off and prints one line. `sendAudioSettled` makes it once only; a saved choice always wins.

Limits: a 0.5.x Mac whose update check saw 0.6.0 or later but stayed on 0.5.x, or had update checks
off, keeps the default (on).

Verified: `swift build -c release`; `Tests/checks/away-quality/run.sh` (the rule's cases) and
`--mutants` (64 of 64, AQ45 to AQ50 this branch's); `Tests/checks/repo-rules/run.sh`. Untested for
Noah: a real update from 0.5.1 to this build (expect the Log line and Send Audio unticked).
