**Send Audio stays off after an update (2026-11-19, branch `send-audio-ask-upgrades` from main at eb48ac9; issue #419).**

What: since #236 (2026-10-27) Sill.app registers Send Audio on, so every install that never saved the
`sendAudio` key got it on, including Macs updating from 0.5.x. The first stream after the update then
played the Mac's sound on the device without its user choosing that (issue #419).

Now `HostSettings.init`, before it registers the defaults, asks `HostConfig.sendAudioToSave(saved:settled:ranBefore:)`:
- `ranBefore`: a key an earlier Sill.app writes is saved (settingsTab, askedScreenRecording,
  permissionsOnboardingDismissed, maxFPS, virtualDisplay, updateLastCheck).
- No saved `sendAudio`, not yet `sendAudioSettled`, and `ranBefore`: saves `sendAudio` off and prints one line.
- `sendAudioSettled` is set at every launch, so it happens once; a fresh install keeps the default on.

Decision: a fresh install from 0.6.0 to 0.6.2 that never touched the switch counts as an update and
gets it off too. That errs on the side of not sending sound; one click in the menu turns it back on.
The rule's alternatives in #419 (ask once on the Mac, a note on the device) are left for Noah.

Verified: `swift build -c release`; `Tests/checks/away-quality/run.sh` (the rule's cases) and
`--mutants` (48 of 48, AQ45 to AQ48 new). Untested for Noah: a real update from 0.5.1 to this build
(expect "Send Audio: off after the update" in the Log and the menu's Send Audio unticked).
