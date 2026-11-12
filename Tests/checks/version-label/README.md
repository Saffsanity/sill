# `version-label`

**Checks:** the app's version and build at the bottom of the connect screen and of the Settings panel (Noah, 2026-11-11; docs/version-label-plan.md): "Sill 0.6.2 (1400)" shown and copied, "Sill version 0.6.2, build 1400" spoken, from CFBundleShortVersionString and CFBundleVersion and no other key; without a build, without a version, without either (no label); the odd inputs: a build that is not a number, white space around and inside (one space, Unicode's White_Space, so a zero-width space is none), control and format characters gone, numbers where a string belongs, Booleans and other types none, a long value whole; 20,000 seeded random values against the invariants

**Compiles:** `iOSClient/VersionLabel.swift`
