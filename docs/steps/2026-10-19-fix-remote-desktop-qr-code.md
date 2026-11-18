**The pairing window to screen sharing (2026-10-19, PR #157 by scripsweave, branch
`fix/remote-desktop-qr-code` on their fork, from main at 5c323e6; issue #108, #137 closed as its
duplicate).** The pairing window's `sharingType = .none` keeps it out of Screen Sharing, Apple
Remote Desktop and VNC apps (Screens), so a Mac used only through them (a headless Mac mini) could
pair a device over the USB cable alone. Noah (2026-10-19, answering the triage): the pairing code
only, as a toggle, and no other hidden dialog shown. Sill.app only: no wire change, nothing on the
device, the CLI untouched (`--pairing` prints its code on stdout).
- Settings › Devices, after Require pairing: **Show the pairing window to screen sharing**
  (`HostSettings.showPairingWindowToScreenSharing`, UserDefaults, off by default; a launch argument
  for one run; `-SillSetAfter '<s> showPairingWindowToScreenSharing=1'` in the bare app). On, the
  pairing window is `.readOnly` (AppKit's default) instead of `.none`, whoever opened it, the Mac's
  user or a device's ask (`PairingWindowSharing`, pure, `Tests/checks/pairing-sharing`); applied as
  the window is made, as each offer shows, and at once on a change to a window already made
  (`PairDeviceWindowController.applySharing`, the app delegate's `onPairingWindowSharingChange`).
  Footnote: "…While it’s on, anyone who can see this Mac’s screen remotely can read the code.
  Devices streaming this Mac never show the window." Sill.log: "Pairing window: shown to screen
  sharing (Settings › Devices); …" at each change and at launch while on, "… hidden …" when it goes
  off. The cable notice and every other window keep AppKit's default, as on main; Sill's own streams
  leave Sill's windows out whatever it says.
- From the PR, kept: the switch, off by default, applied live. Changed: the name (was "Display QR
  code on remote desktops", `displayQRCodeOnRemoteDesktops`); the rule a pure type with a check in
  place of an XCTest target and a `swift test` CI step (both gone, with AppModel's `init(defaults:)`);
  the footnote; the docs (README's Pairing, docs/DEVELOPMENT.md's Pairing at home, support.html's
  "If it doesn’t work" item marked `<!-- Pairing window` for the release, the checklist's republish
  cut, SECURITY.md's known-by-design paragraph, docs/home-pairing-plan.md's open risk).
- Open for Noah: the 2026-10-19 triage suggested keeping a window a device's ask opened hidden; the
  task as relayed covers both openers, since a device's tap is how a Mac seen over Screen Sharing
  pairs. One line in `PairingWindowSharing.pairingWindow` and two of the check's cases change it.
- Verified: `pairing-sharing` 16 checks and 8 of 8 mutants; `Tests/checks/run-all.sh`, all 45;
  `swift build -c release` (only the CaptureProbe warning); `Scripts/make-app.sh` without `--install`;
  the bare binary's previews against main's, both run from one path: only the Devices pane's eight
  differ, two new (`screensharing`), `menu.txt` and the rest byte for byte; live on a test host
  (`--synthetic`, loopback, the software encoder) with a scratch build whose pairing window was
  transparent and click-through, opened by a test client's ask: the window server's
  `kCGWindowSharingState`, sampled 2 s after each change, 0 with the switch off, 1 once
  `-SillSetAfter` turned it on, 0 off, 1 on, the same open window throughout; 1 from the first look
  with it saved on (the launch line logged) and with `-showPairingWindowToScreenSharing 1` (nothing
  saved).
- The verifier's findings (2026-10-20, after fa57c2f), each fixed in a commit of its own: the
  window's `NSWindow.SharingType` for each answer (`.none` hidden, `.readOnly` shown), which no check
  compiled, moved from PairDeviceWindowController into `PairingWindowSharing.swift` under
  `#if canImport(AppKit)`, and the check (AppKit imported for that enum alone, no window) asserts
  both: 18 checks, 11 of 11 mutants (new: the two cases swapped, hidden told `.readOnly`, shown told
  `.none`); the footnote's and README's example is the Mac's ("…or another remote desktop app, as
  you would a Mac without a display"; it read as an app without a display); docs/remote-access-plan.md
  §6.2, the window's spec, names the switch; docs/DEVELOPMENT.md says what the switch changes, what
  Screen Sharing, Apple Remote Desktop and VNC viewers see, and that a screen recording or a call's
  shared screen may show the code either way (ScreenCaptureKit is reported to ignore `.none` from
  macOS 15). Main merged in at d1fa97e (no conflict), at 4d990e9 (ci.yml's mutants matrix alone:
  both sides kept, sorted) and at 74d099c (#94, #159, #227, #93, #151: six files, both sides kept in
  each; #94's `sendAudio` beside this switch in HostSettings' keys and registered defaults, as Noah's
  comment of 2026-10-19 asked of whichever landed second). Verified again on the last merge:
  `swift build -c release` from a clean `git archive` (only the CaptureProbe warning); the iOS app
  for the generic simulator as CI builds it (only the StreamClient capture warning);
  `pairing-sharing` 18 checks and 11 of 11 mutants; `Tests/checks/run-all.sh`, all 52; the previews
  against main's (74d099c), both run from one path: the Devices pane's eight differ, two new, the
  other 136 byte for byte (`menu.txt` among them); the bare binary on loopback with
  `-SillSetAfter '2 showPairingWindowToScreenSharing=1'`: one line for the change, the key saved;
  live, on a trial merge of the same code, a test host as above (a scratch copy, its pairing window
  alone transparent and click-through, opened by a test client's ask), `kCGWindowSharingState`
  sampled every 0.1 s: 0 with the switch off, then 1, 0 and 1 within half a second of each
  `-SillSetAfter` change, one window throughout, off screen after the Cancel; relaunched with it
  saved on, 1 from the window's first look and the launch line once; with
  `-showPairingWindowToScreenSharing 1`, 1 and nothing saved.
- **Untested, for Noah:** with Sill.app from this branch, through Screen Sharing from another Mac
  (or Screens, or Apple Remote Desktop) to a Mac: Pair iPhone or iPad… shows nothing remotely with
  the switch off, the window and its code with it on, and flipping it with the window open shows or
  hides it at once; a tap on the Mac's "Not paired" row on the iPad does the same; a device pairs
  with the code read remotely. (#121's author saw `.readOnly` show the code through Screen Sharing on
  a headless M4 Mac mini and paired with it.)
