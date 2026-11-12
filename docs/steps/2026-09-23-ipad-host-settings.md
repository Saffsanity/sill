**iPad host settings (2026-09-23, branch `ipad-host-settings` from
`menu-bar-app`, rebased onto its e89add6; the plan and its reasoning are in
`docs/ipad-host-settings-plan.md`).** A device changes the Mac's five streaming
settings the way the Sill menu does: Quality (bitrate), Resolution (capture
scale), Frame Rate limit, Prioritize Speed, Virtual Display. Defaults taken for
the plan's open questions: Settings replaces Leave in every bar's last slot and
Disconnect moves to the panel's pinned foot (Q1); Sill.app saves a device's
change like a menu click (Q2); the virtual display has full menu parity, so
turning it off from a device brings the window home and forward (Q3).
- Wire: kind 16 `.hostSettings` (host → device, JSON `HostSettingsState`: the
  target settings, `persistent`, `virtualDisplayAvailable`,
  `virtualDisplayNote`, `softwareEncoder`, the running `stream`, and
  `answering` in the reply to one change) and kind 17 `.changeSettings` (device
  → host, JSON `HostSettingsChange`: only the fields one control changed,
  absolute values, a token strictly increasing per device process). Types,
  `SettingsChoices` and `QualityPreset` (moved from the app) are in
  `Sources/StreamProtocol/HostSettings.swift`. No ack, refresh or version
  kinds: a kind 16 on this connection means the host supports settings. Fields
  added later must be optional, never renamed or retyped, no enums.
- Host: `StreamCoordinator.setTarget` (synchronous; replaced `apply`)
  validates, forces the virtual display off without the AppKit loop, compares
  with the target (`pendingConfig ?? config`), publishes, and schedules the
  pipeline work in a Task, so a burst is one restart. The `.changeSettings`
  handler has no await: it keeps exactly the Mac menu's values
  (`DeviceSettings.accepted`; the virtual display on only under the AppKit
  loop, off always), logs "Settings from ‹device›: …" and "… refused: …", and
  answers that device alone. The state is a pure function of the target and
  the `HostStatus` snapshot, and both publish (`setTarget`,
  `HostStatus.onChange`), deduplicated, so the once-a-second stats send
  nothing; every device also gets it right after its window list. Nothing new
  prints unless a device sends kind 17 (the CLI's output is unchanged). A pick
  that lands during a restart of the active source now runs after it
  (`pickArrivedWhileSwitching`, newest wins, the restarted source itself
  dropped); during a switch to another source it is still dropped (the device's
  automatic Desktop request must not override a pick).
- Sill.app: `HostSettings.onChange` calls `setTarget` synchronously, so the
  target equals `settings.config` at every main-actor turn, and
  `onDeviceSettingsChange` lays a device's change over `settings.config`: saved
  (only the keys it changed), shown live in Settings and in the menu when it
  next opens. The CLI sets no hook: a device's change lasts until SillHost quits
  (`persistent: false` says so on the device).
- iOS: `HostSettingsLedger` (pure logic) holds the Mac's last state on this
  connection with this device's unanswered picks over it: a pick sends only what
  changes what is shown, nothing before the first state; an answer clears only
  the picks carrying its token (60 → 120 → 60 never shows 120); a refused pick
  goes back with the warning haptic and an announcement; a pick unanswered after
  max(4 s, 4 × RTT) goes back with "‹Mac› didn’t answer. Try again."; reset on
  tear-down, never persisted. `HostSettingsPanel` mirrors the Apps drawer on the
  trailing edge, lined up with the Settings button: 360 pt under the landscape
  bar (340 on the outer display), in portrait wholly in the lower half under the
  window bar; no dim (a clear catcher closes it without clicking the Mac);
  pinned header (the Mac's name, what runs, Done with Esc/⌘.) and Disconnect
  foot, the middle scrolling when short. Opening it takes the keyboard down
  (`InputOverlayProxy.setKeyboard`, so no key reaches the Mac) and closing puts
  it back. Only a control's action ever sends (`StreamClient.changeSettings`).
- Verified without permissions (the plan's H0–H21, S1, S2, S5, S6): clean
  builds (only the old CaptureProbe warning; iOS Debug and Release only the old
  `StreamClient` capture warning); the CLI's output masked and sorted equals
  the branch point and its idle stdout is unchanged; `sillclient.py` shows one
  kind 16 after the first window list and one when the Desktop starts, accept /
  no-op / refusals / partial / a burst of three (one restart) / two clients /
  rapid pairs 0–300 ms (at most two restarts) / reconnect / malformed and
  tokenless changes / 20 s idle (two states, CPU as before) / the toggle on the
  `--virtual-display` host (no restart); the bare app saves a device's change,
  keeps it across a relaunch, sends a `-SillSetAfter` change to the device,
  lets the device and the Mac change different keys at once, and every
  `-SillSetAfter` change still gives one "Settings:" and at most one restart;
  previews byte-identical; the ledger check (28 scenarios, 5,000 random runs
  with two mutants caught); the queued pick with a race client that sends the
  pick while the restart runs (before: 8 of 8 picks lost; now 24 of 24 stop the
  stream after one restart); 38 simulator photos of the panel (four Duo sizes
  × eight cases, iPad mini and iPhone sizes, accessibility-extra-large); taps
  through the harness; live by address against both synthetic hosts (the
  device's change logged, one restart, saved by the app; a Mac-side change
  shown; Disconnect); against the branch-point host the panel says to update
  and the client sends no kind 17.
- Review fixes (2026-09-23, after the rebase onto e89add6): the pick timeout
  reads the new `linkStats` (the worst round trip of the last second that
  measured one, kept through seconds without a pong); a pick queued behind a
  restart goes through the same rule as a fresh one (`handlePick`), so a
  restart that starts before its Task runs no longer drops it; a staged window
  that the virtual display turning off sends home comes forward whichever
  select commits that change (`cameHome`); the device holds back its automatic
  Desktop request when the user picked or launched something while it waited
  out a closed window (the race that remains, older devices and a pick sent
  before the device heard of the close, is written down at `handlePick`); the
  status menu's Virtual Display item sets the value it showed instead of
  toggling, so a click on a menu left open while a device changed it never
  undoes that change; in the panel the readout wraps instead of cutting off and
  "On the virtual display" is a line of its own, Done's tap area is 44 pt tall,
  and the speed switch is "Prioritize Encoding Speed" (the Mac's name) in its
  own group under the Mac's explanation; `sillclient.py` checks every argument
  before connecting; HostSettings.swift lists every place a new setting must
  go. Verified: the CLI's output against e89add6's (masked; idle, 35 s idle,
  the Desktop, `--virtual-display`); H4–H21 again, previews byte-identical;
  the race that lost 5 of 6 queued picks to a rate-change restart now loses 0
  of 10; 46 photos (a new `vdstream` case at every size and at larger text);
  iOS Debug and Release with only the old warning; taps 7 pt above and
  8 pt below Done close the panel; in portrait the header stays put while the
  panel opens (the Quality value moves 2 pt; it slid 32); against a fake host
  that never answers, a pick times out after 4.3 s with prompt pongs and 8.3 s
  with pongs held 2 s; against one that closes the watched window, the Desktop
  request follows 2 s later unless the user picks, and then never comes.
- **Untested, for Noah:** D1–D11 (the plan's §7.4): the panel's values
  against the Mac's menu and status card with a real window; every control from
  the iPad (one restart each; the Mac's Settings window follows; saved in
  `me.saffer.sill.mac` and after a relaunch); the virtual display on and off
  from the iPad, also full screen; a Mac-menu change showing in the open panel;
  two devices at once; `SillHost` without and with `--virtual-display`;
  reconnecting after a change made while away; the 60 fps note and Low Power
  Mode on the iPad mini; a Magic Keyboard (keys stop while the panel is open,
  Esc closes it and does not reach the Mac, keys come back); VoiceOver (modal,
  focus on the Mac's name, the escape gesture); a pick right after a change,
  and five minutes with the panel closed (frame age and RTT unchanged). Also
  rotating with the panel open and Reduce Motion (fade only), which the
  harness cannot drive; not run here: S3 (no Accessibility Inspector) and S4
  (no way to press a hardware Esc in the simulator from here). Also the Mac
  menu's Virtual Display item clicked after the iPad changed it while the menu
  was open (it should do what the item showed), and turning the virtual
  display off while another change is restarting a staged window (the window
  should still come forward).
- Known, not fixed here: in the layout harness, bringing up the software
  keyboard flips the fake screen into the portrait layout (the same at the
  branch point; the harness only). A Mac menu that is already open keeps its
  old checkmarks until reopened (every item sets the value it shows, so a
  click there never inverts a device's change).
