**Send Audio and Mute in the device's Settings panel (2026-10-27, branch `sound-toggle` from main at
b4caa91, main at 3b54637 (#117, #234) merged in, not rebased; PR #235; the bullet "Two switches" in the
sound's entry below and docs/audio-plan.md's last section have the details).** Noah: "I've decided the
audio setting should not be in the main button tray but instead in settings. Sound should be a toggle in
the settings menu." Two switches in the device's Settings panel: **Send Audio** (the Mac's group, its
"Beta" tag), which a device turns on and off for every device as it does Quality (the host accepts kind
17's `sendAudio` again and Sill.app saves it, no picture restart; a Mac from the beta refuses it and the
switch goes back; for a Mac without sound the row is off and disabled, "Update Sill on ‹Mac›…"), and
**Mute** right under it (`soundMuted`, the device's own, off by default; Noah, 2026-10-27: "right below
the Send Audio setting"), shown for every Mac with sound, Send Audio on or off. No Sound button in any bar.
- Merged with main at 3b54637 (2026-10-27: #117, the connect screen's tiles, and #234, the capture scale
  follow-ups; one merge commit). Only iOSClient/ContentView.swift conflicted, in SettingsScript's doc
  comment: both kept (this branch's `set … sendAudio` and #117's `disconnect` step). CLAUDE.md,
  Tests/checks/README.md (both sides' rows: #117's `connection-list` 154 and 72, #234's `capture-scale`,
  this branch's `away-quality`, `ledger`, `phone-portrait` and `tour`), DEVELOPMENT.md, MockCatalog.swift
  (#117's `tiles` connect case beside this branch's settings cases), StreamClient.swift and
  site/privacy.html (#117's Tiles items beside the Sound item, the date October 27, 2026) merged by
  themselves. Verified on the merge: `swift build -c release`; the iOS app, Debug for the generic
  simulator as CI builds it, only the known `StreamClient` capture warning (StreamClient.swift:4067);
  `run-all.sh ledger away-quality phone-portrait tour connection-list capture-scale`, all passed (100,
  89, 484, 111,189, 154 and 122 checks).
- **Untested, for Noah:** the bullet "Two switches"' list (Send Audio from the iPad's panel heard on
  the iPhone too, Mute on one device, Mute before the sound is turned on elsewhere, VoiceOver on both
  switches, this iPad against a Sill.app from the beta and against 0.5.1).
