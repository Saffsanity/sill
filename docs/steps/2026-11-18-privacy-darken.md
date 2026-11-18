**Privacy, part 2: this Mac's screens dark while a device uses it, built up to the one place that darkens them and waiting for Noah's probe (2026-11-18, branch `privacy-darken` from `privacy-lock` at 4d6a470, which is main at 8dbbb50 with #184 and part 1).**

docs/privacy-mode-plan.md (part 2: rules 2–5, 7–9, 11–14; G0) and docs/privacy-mode-assessment.md. Part 1, the lock when
the last device leaves, is the branch `privacy-lock` underneath this one.

- **G0, the probe** (`Scripts/privacy-probe/`, TEST ONLY, Noah's to run: it darkens the screen in spells of at most
  10 s, each under a hard 12 s kill from the shell). `run.sh` builds `probe.swift` (AppKit and ScreenCaptureKit, no
  encoder) and `window.swift` (the test window's app, me.saffer.sill.privacyprobe), then: step 1, the test window, a
  Safari video and an Electron window captured uncovered and under S1 (opaque, .screenSaver, #184's), S2 (not opaque,
  .screenSaver), S3 (opaque, shielding) and S4 (opaque, 1500); step 2, the window server's list while Noah locks, gets
  a notification, presses the volume keys, ⌘Space, F3, ⌥⌘⎋ and moves the pointer; step 3, kill -9 and a stopped
  probe; step 4, a tagged and an untagged posted event and Noah's own through NSEvent's global monitor; step 5, black
  on every screen. His answers go into the report with the measurements. Only `check` (read-only) and `gone` were run
  here; `--build-only` compiles both without running anything.
