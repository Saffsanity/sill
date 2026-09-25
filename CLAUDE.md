# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

## Current step

**Remote access (2026-09-24/25, branch `remote-access` from `a9cc248`; the plan,
its open questions and the results are in `docs/remote-access-plan.md`).** Bring
your own VPN (Tailscale, WireGuard into the home network) or, behind a switch
of its own, a port forward: a device paired once reaches the Mac from anywhere.
Every open question took its default. Steps 1–8 are committed; step 9 (the
review) is next.
- Two doors. The home door (today's plain TCP listener, Bonjour, unchanged for
  old iOS builds) now admits only this Mac's own networks, loopback and Direct
  Wireless (`OriginPolicy`), with caps (1 MiB messages, 4 kind-17 changes a
  second, a clean device name). The remote door (`RemoteServer`, port 7455) is
  TLS 1.3 only, both ends self-signed P-256 keys pinned by SPKI SHA-256, ALPN
  `sill/1` for a paired key, `sill-pair/1` only while a pairing window is
  open; pre-auth caps (8 pending, 2 per source, backoff after 5 of its own
  refusals), 8 sessions, remote clients evicted after 8 s of silence, forced
  keyframes at least 2 s apart. Kinds 18 (the signed MacInfo: Mac ID, name,
  addresses), 19/20 (one pairing request and its answer), 21 (Pair This iPad…,
  home door only) and 22 (goodbye) are skipped by older readers; the TXT record
  carries a recognition tag (`r`) only paired devices can read.
- Pairing: the Mac's window shows a QR code (`sill://pair?…`, pinned to the
  Mac's key) and a 12-digit code (Damm check digit; PBKDF2 600k), 5 minutes,
  single use, five wrong tries. Sill.app: Settings › Remote Access (a fifth
  tab: the switch, the addresses, the port, paired devices, the internet
  switch with the router's answer, the address name, sleep), the menu's Remote
  Access… and Pair iPhone or iPad…, identity in the login keychain
  (`KeychainIdentityStore`; label "Sill Remote Access", service
  `me.saffer.sill.remote`), idle sleep held off while a device is connected
  remotely. The CLI's `--remote` uses a throwaway identity per run.
- iOS: `DeviceIdentity` (a Keychain key, this device only), `SavedMacs`,
  `RemoteDialPolicy` + `RemoteConnector` (the dial order, happy-eyeballs 1 s
  apart, every failure's words), Remote rows after the network's 3 s, the
  reconnect order after a loss, liveness on every route; the connect screen's
  "Add a Mac…" card (the VisionKit scanner or the typed address and code),
  `sill://pair` links only ever confirmed, Pair This iPad… as an overlay over
  the stream, the panel's route line ("Connected through Tailscale · 48 ms"),
  its Away from home group and the slow-link callout; the Low preset (4 Mbps,
  first on both sides) and 60 fps away from home.
- Verified without Noah's devices: the plan's H1–H24 headless (the CLI's
  output byte for byte, the pure checks with mutants, the doors' refusals and
  caps, no plaintext on the wire, no code or secret in any log, a 2 Mbps
  +150 ms relay with no eviction and the base's keyframe rate), the app's
  persistence and previews, and on the simulator S1–S8: about 200 photos at
  the Duo sizes, phones and larger text, taps and accessibility as XCUITests,
  live pairing (QR, typed, an outside link confirmed first), reconnects,
  every failure's words, an older host, and a slow link (60 fps through a VPN
  route; the callout at +300 ms).
- **Untested, for Noah (R0–R13; the plan's Results say exactly what):** R0 the
  probes (the Secure Enclave key, the login keychain identity with your OK, the
  router probe, the scanner on the iPad); R1 Tailscale setup and pairing,
  timed; R2 away on the hotspot; R3 leaving home mid-stream; R4 Wi‑Fi to
  cellular; R5 Tailscale off at either end; R6 sleep; R7 removing the iPad
  while it streams; R8 a rebuild keeps port, Mac ID and pairing; R9 Pair This
  iPad… at home; R10 the port forward; R11 Direct Wireless at the café; R12
  VoiceOver and a hardware keyboard (Esc never reaches an app in the iPadOS 27
  simulator; only ⌘. was tested); R13 mixed builds.
- Known: origin/main gained PRs #6–#8 after this branch began (a rebase will
  meet the quality presets of #8); the simulator iPad Pro 13" is shared with
  other work, so a test that installs the app there can replace someone
  else's build (the iPad Pro 11" was used for S8); an unsigned simulator build
  cannot use the keychain on a fresh simulator (-34018): build it ad hoc
  signed (`CODE_SIGN_IDENTITY=-`).

**Direct Wireless Connection (2026-09-24, branch `direct-wireless` from
`ipad-host-settings` at 35a1238; the plan and its measurements are in
`docs/direct-wireless-plan.md`).** Noah's decision: AWDL off by default on both
ends, and an opt-in host setting named Direct Wireless Connection in the Mac's
Settings and menu and in the device's panel. `includePeerToPeer` on the host's
NWListener made its Bonjour registration include AWDL, which the kernel counts
as an AWDL service ("Enabling AWDL due to Mdns"); the Mac's one radio then left
its Wi-Fi channel up to ~97 ms every 524 ms (see the trackpad-stutter section).
- Wire: `StreamSettings.directWireless` and `HostSettingsChange.directWireless`,
  optional: nil is a host without the setting, which gets no row, and the
  device ledger's rule 9 never sends a field the host did not report. Kinds
  16/17 stay compatible both ways (old device: ignores the key; old host: the
  device sees nil).
- Host: `HostConfig.directWireless`, off in `standard` (the CLI and a fresh or
  updated Sill.app), accepted from a device on every host, and absent from
  `restartNeeded`: it is the listener's. `StreamServer` builds the listener
  with `makeListener(peerToPeer:port:)`, with the setting when it is given
  before `start()`; after that `setPeerToPeer` replaces the listener live on
  its queue: cancel, wait for `.cancelled`, bind the same port at once with no
  service, advertise 1.5 s later (re-registering the same name within
  milliseconds of dropping an AWDL registration orphaned the awdl0 record for
  minutes; 0.25 s and more never did). Accepted connections are independent of
  the listener, so streaming devices never notice; one line per applied change
  ("Direct wireless on: listening on port P again, advertised again.").
  Requests coalesce (newest wins), and late callbacks of a replaced listener are
  inert. No `.cancelled` within 1 s or the same port refused: any port, with a
  line; both refused: the existing listener-failure rule (the app shows "Not
  Visible on the Network" and keeps running, the CLI exits 1), and the next
  toggle retries. CLI: `--direct-wireless` prints one startup line; without it
  the output is the branch point's byte for byte (masked and sorted).
- Sill.app: Settings › General "Direct wireless connection" right after
  "Visible on your network as", and a "Direct Wireless Connection" item at the
  top of the status menu's second group, absolute like Virtual Display. Saved
  under `directWireless`; an existing install has no key, so it comes up off.
- iOS: the network browser and connections to the Macs it lists never use
  peer-to-peer. A nearby (peer-to-peer) browser runs only while not connected,
  and only when a Mac this device last saw with the setting on
  (`Sill.directWirelessMacs`, from each state, keyed by the Bonjour name the
  connection was made to, which is what the browsers list: the window list's
  "Mac" stays "Mac" when Bonjour renames a clash "Mac (2)"; a connection by
  address teaches nothing) is missing from the network 3 s after the connect
  screen began looking, or after Search Nearby (offered when nothing is listed
  after 3 s; once it runs, a muted "Also looking nearby" of the button's height
  takes the button's place whatever the status line says, VoiceOver announces
  it, and the idle status adds "and nearby" only when no hint shows); once
  started it runs until a connection is ready (`DiscoveryPolicy`, pure, checked
  with swiftc). A Mac seen only over awdl/llw is a "Direct" row, the one kind
  connected with peer-to-peer; a Mac the network lists is always a network row,
  so at home nothing takes AWDL. Reconnects match the name exactly ("MacBook
  Pro" and "MacBook Pro (2)" are two Macs) and take the network row at once, a
  Direct row only once it has stayed Direct for 3 s: a Mac back on the shared
  network (Sill relaunched, the Mac awake) registers there and on AWDL
  together, and the nearby browser can report awdl0 first. A tap is never held
  back. Local Network access denied (the network browser waits with
  PolicyDenied): the status says "To find your Mac, allow Local Network for
  Sill in Settings.", with no hint and no nearby search. The panel's last group
  is the row (never disabled), after the closing footer, with "Connected
  directly" in the header while this device's own connection runs over AWDL,
  and then, while the switch shows on, a warning in its footer and hint. The
  connect screen's column is anchored leading now, so its title no longer jumps
  sideways when a row or the hint appears; it is still centred vertically, so
  it moves up by half of what they add.
- Verified without permissions (the plan's H0–H15 and S1–S4): the kernel's
  AWDL service count (ValidSvc, baseline 2 from Noah's PR #4 Sill.app) rises by
  2 exactly for a registration made with the AWDL flag: `dns-sd -includeAWDL -R`
  and `SillHost --synthetic --direct-wireless` (test type) both 2 → 4, while
  `dns-sd -R`, the suffix form `dns-sd -R … -includeAWDL` (a TXT record, no
  flag) and the default host stay at 2; off, the test registration never
  appears on awdl0 (index 16), on it does 1.1 s after launch and leaves no
  orphan; live on and off under a streaming client: the same port throughout,
  frames every second, no restart, the awdl0 record added 2.6 s after on and
  removed 1.3 s after off; 55 connections across a replacement all accepted;
  five toggles in 0.4 s give one replacement; mixed with a bitrate change, one
  restart and one replacement; the fallbacks (SILL_TEST_SWAP_FAIL); the bare
  app saves it from -SillSetAfter and from a device and relaunches with it on;
  previews: only the General pane and menu.txt changed (one unchecked item per
  sample); the ledger check (43 checks, 5,000 random runs, 1,227 against a host
  without the field, three mutants caught) and the policy check (40); iOS
  Debug and Release with only the old warning; photos of the connect screen
  (looking, hint, nearby) and the panel (default, direct, directlink,
  nodirect, cli; scrolled) at the four Duo sizes and larger text; taps (Search
  Nearby, the switch); live by address against both synthetic hosts (the
  device's change: three host lines, same port, frames keep coming; a Mac-side
  change shows in the open panel; the app saves 1 then 0); the normal app on
  the simulator: no nearby search without memory, and with a remembered Mac
  that is missing it starts 3.8 s after launch (ValidSvc +1 until it quits)
  while the real Mac on the network stays a plain row. Review (one pass by the
  implementer, three lenses: wire and hard rules, the replacement's
  concurrency, the device UI), then adversarial re-runs of H2–H8 on the final
  build plus: a burst that ends where it started never turns AWDL on (ValidSvc
  constant, no awdl0 row) while 139 of 139 connections across two replacements
  are served; after a total listener failure the next toggle retries; the
  device toggling on then off while streaming (two replacements, same port,
  frames throughout, ends off on both sides). A second review's fixes (the
  plan's "Review fixes"), verified: clean builds; the CLI identical again;
  previews differ from the step before only in the Permissions panes; the
  policy check at 68 (the home race, the café case, denied; six mutants
  caught) and a replay of the status rule (13 states); photos of the connect
  cases (looking, hint, nearby, denied) and of Search Nearby tapped at the four
  sizes (the title does not move); the panel's warning goes when its switch
  is tapped off; an address connection to a host with it on writes no memory.
- **Untested, for Noah (the plan's W1–W9):** W1 the payoff: both builds
  installed, `/usr/bin/log stream --style compact --predicate 'process ==
  "kernel" AND (eventMessage CONTAINS "abling AWDL" OR eventMessage CONTAINS
  "ValidSvc")'` shows "Disabling AWDL due to no services and no active
  sockets" once the old Sill is gone (unless AirDrop, Sidecar or Universal
  Control hold it), and five minutes on a still window with trackpad strokes
  keep the `rtt m/M` maxima near the LAN's, with no ~100 ms spikes. W2 on from
  the iPad panel while streaming: no restart, one "listening on port N again"
  (same N), the Mac's Settings and menu follow, `defaults read
  me.saffer.sill.mac directWireless` is 1, "Enabling AWDL due to Mdns" and the
  maxima rise; off from the menu two minutes later and they fall back. W3 with
  it on, the iPad on the iPhone's hotspot and the Mac at home: within 3–5 s a
  "Direct" row; connected, the host logs `%awdl0` and the header says
  "Connected directly" (note frame age and rtt). W4 first use (reinstall, café
  conditions): the hint and Search Nearby after 3 s, then "Also looking
  nearby", the Mac as Direct; a relaunch there searches nearby by itself; once
  with Don't Allow on the Local Network alert: the status asks for Local
  Network and no hint shows, and allowing it in Settings brings the list back.
  W5 turned off from the Mac while connected directly: does the stream
  continue while the socket is active, and for how long? Then fix the footer's
  "can disconnect" to match. W6 home → café while streaming with it on:
  reconnects directly within ~8 s without a tap (3 s for the network, then the
  Direct row's own 3 s); and back home, relaunching Sill.app, the iPad
  reconnects over the network (the host logs no `%awdl0`). W7 relaunch
  Sill.app with it on: `dns-sd -t 3 -includeAWDL -B _sill._tcp local` lists
  one instance on awdl0, no "(2)". W8 the CLI with and without
  `--direct-wireless`. W9 mixed builds (PR #4 iPad with this host, this iPad
  with PR #4's Sill.app: both connect on the LAN, the latter with no row) and
  VoiceOver ("Mac mini, Direct", the hint, Search Nearby and its announcement,
  the row).
- Known, not fixed here: the simulator's browsers run in the Mac's
  mDNSResponder, so a nearby search on the simulator turns the Mac's AWDL on:
  never measure latency with a simulator sitting on the connect screen.
  Security: with it on, anyone within radio range running Sill can
  find and connect to the Mac until pairing (M5); the host-settings plan's §9
  payload cap and a kind 17 rate limit matter more with it on. It is the first
  device-writable setting that widens who can reach the Mac, against that
  plan's "a device sets stream quality, never network exposure": revisit it
  with pairing.

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

**Sill.app, the menu bar host (2026-09-23, branch `menu-bar-app`; the plan and
its background are in `docs/menu-bar-app-plan.md`).** The same host as the CLI,
as an LSUIElement app. A status item whose glyph (drawn from AppIcon.svg:
idle, connected, streaming, attention) and menu card show the network, each
device with its fps, frame age and RTT, and the stream; a menu with Virtual
Display, Frame Rate, Quality, Resolution, Launch at Login (SMAppService),
Permissions, Show Log…, Settings… and Quit. Settings is an AppKit window with
four SwiftUI panes (General, Streaming, Virtual Display, Permissions), kept off
the virtual display; the Log window shows HostLog's last 5,000 lines, and
`~/Library/Logs/Sill/Sill.log` has them all. SwiftPM builds the `SillMenuBar`
executable; `Scripts/make-app.sh` wraps it (Packaging/Info.plist, an icon
compiled by actool from design/AppIcon.svg), signs it with the Apple Development
identity and, with `--install`, replaces /Applications/Sill.app. Bundle ID
`me.saffer.sill.mac`. Settings persist (`defaults read me.saffer.sill.mac`)
and apply live: `StreamCoordinator.setTarget` hands a new `HostConfig` to the next
`select`, which takes it between pipelines; a change restarts the stream once,
or not at all when nothing running depends on it (the virtual display toggle
restarts only a window stream, and sends a staged window home first). Virtual
display off by default in both the CLI and the app.
- Rules. Host code is the `SillHostCore` library (folder `Sources/SillHost`),
  reached with `package` access; make it `public` only if an Xcode target ever
  needs it (M5 CloudKit). Never `MainActor.assumeIsolated` in core code: under
  the CLI's dispatchMain the main queue drains on a worker thread and it traps;
  hop with `Task { @MainActor }`. The modal-loop rule (AppDelegate's doc
  comment): never start NSMenu.popUp, a runModal or a terminate that can answer
  .terminateLater from a Task, an async continuation or a main-queue block, only
  from AppKit target/action, SwiftUI Button actions or a run-loop Timer; errors
  show inline, never in alerts. The CLI's stdout stays byte-identical: core
  `print`s go through the shadow in HostLog.swift, which records nothing until
  the app configures it. App Nap: while a device is connected the app holds a
  latency-critical activity (napping would coalesce the 30 ms keepalive ticks).
- TCC: a grant belongs to the bundle ID plus the designated requirement
  (identifier + Apple anchor + the certificate's CN), so rebuilds signed with
  the same Apple Development identity keep it; ad hoc would lose it on every
  rebuild. Terminal's grants for the CLI don't carry over, and running
  Contents/MacOS/Sill from Terminal makes Terminal responsible. The app asks
  for nothing at launch (no Accessibility alert, no window list before Screen
  Recording is granted); Settings opens on Permissions until both are allowed
  or the user closes it. Allow… shows each system alert once
  (`askedScreenRecording`/`askedAccessibility` in the defaults), then opens
  System Settings, so recovering from a `tccutil reset` also deletes those two
  keys (README, Permissions).
- Build facts. SwiftPM's default build system links without SDKROOT, so its
  executables record the deployment target as their SDK (`xcrun vtool
  -show-build`: sdk 14.0), and macOS 26+ draws such an app in the pre-26 look.
  make-app.sh writes the bundle's executable with vtool, recording the SDK in
  use (27.0 here) as Xcode would; the CLI and the bare SillMenuBar keep 14.0.
  It signs by the identity's SHA-1 hash (a renewed certificate with the same
  name makes the name ambiguous to codesign), and `--release` refuses anything
  but a Developer ID Application signature. NSTabViewController selects its
  first tab while `NSWindow(contentViewController:)` builds the window, so the
  Settings tab is saved only from an on-screen selection and from `show`.
- In the app only: regular mode trusts `NSWorkspace.frontmostApplication` (the
  AppKit loop runs), and turning the virtual display off brings the returning
  window forward (a product call).
- Verified without permissions: clean build (only the old CaptureProbe
  warning); the CLI's output matches the pre-change baseline line for line
  (sorted, digits masked) at 60 fps, exits 130/143 on the flag path; the bare
  app streams the test pattern at 60 fps, each `-SillSetAfter` change gives one
  "Settings:" line and at most one restart (virtual display on while the
  Desktop streams: none), Quit exits 0 through `releaseForQuit`, a saved setting
  survives a relaunch, idle CPU 0.0 %; the Settings and Log windows open and
  render; make-app.sh signs with the Apple Development identity, the designated
  requirement survives a rebuild, the icon renders as a native squircle, and
  the signed bundle streams and creates a virtual display under the hardened
  runtime. After the SDK fix the bundle (sdk 27.0) still streams at 60 fps,
  exits 143 on SIGTERM and creates and removes a virtual display, and its
  panes render in the macOS 26 look (the Streaming pane matches the design
  draft); `--release` refuses a missing, ad hoc or Apple Development identity;
  a stub harness showed the Settings tab now survives a relaunch.
- **Untested, for Noah:** N1–N12 in the plan: first run and the grants, the
  menu's live rows with the iPad, every control while streaming a real window
  (virtual display on and off, also full screen), Settings placement, Launch
  at Login, quitting with a staged window, App Nap and latency against the CLI,
  regular-mode input, revoking Screen Recording, the Log window, the CLI and
  the app side by side. Also the live menu and Settings window in the macOS 26
  look that the SDK fix turned on (only offscreen renders were checked), and
  Settings reopening on the last tab after a relaunch.
- Known, not fixed here: the CLI's synthetic mode still prints "Advertising
  _sill._tcp" although it no longer advertises.

Milestone 3, scaling and the virtual display. Two paths exist; adopt the second.

- **Fallback (shipped):** the Aa control, in every bar since 2026-09-22, is a
  button that unfolds into a linear slider while touched (camera-zoom style):
  five detents, 0.5× to 1.5× in 0.25 steps, neighbours fade, the value is
  applied once on release. The client sends its stream-panel size and wanted
  scale (`Viewport`); the host resizes the real Mac window through
  Accessibility (`WindowSizer`) to panel ÷ scale points, so text renders at
  that scale on the device. Until the slider is first touched the scale is nil
  and the Mac window is left alone (the control shows 1×). Harness:
  `-SillScaleOpen 1` photographs the unfolded state.
- **Virtual display (implemented 2026-09-22 behind `--virtual-display`, off by
  default; Noah flips the default after trying it).** With the flag, SillHost
  runs `NSApplication.run()` (activation policy `.prohibited`: no Dock icon,
  never activatable) instead of `dispatchMain()`, because only under the AppKit
  loop does the creating process see the display's modes. `select(.window)`
  asks `VirtualStage` to create one `CGVirtualDisplay` ("Sill", 2×, at the
  stream's rate),
  move the window onto it with Accessibility (`WindowSizer.placement/move/
  restore`; AX writes never activate or raise anything), and capture it with
  `SCContentFilter(display:including:[app])` cropped by `sourceRect` to the
  window's rectangle, so the device sees the window plus the app's own menus,
  popovers and sheets (separate windows, invisible to window capture) and
  nothing else. Deselect,
  switch, last client leaving, display lost, Ctrl-C/kill/hangup
  (`HostShutdown`) and `atexit` put the window back at its original frame and
  destroy the display. Any failure logs "Virtual display fallback …" and
  streams the real window as before.
  Full screen (2026-09-23): a staged window that enters a full-screen Space
  fills the display and refuses moves, so `prepare` detects it (AXFullScreen
  or ≥98 % coverage), captures the display cropped to the panel's aspect
  around its middle (where apps letterbox video), and holds that until the
  catalog's next poll sees the window leave full screen. "Still full screen" is
  AppKit's AXFullScreen flag (the frame sits short of the display mid-Space);
  a window leaving full screen is off every list for ~1 s, so the catalog
  gives it three polls and `prepare` waits 1.5 s before calling it gone; a
  switch away first takes the window out of full screen
  (`leaveFullScreenIfNeeded`) so it can go home. The band is encoded at the
  panel's size, not the display's. Entering and leaving each take up to one
  2 s poll to show.
  Geometry (pure functions in `VirtualStage`): window = panel ÷ Aa scale in Mac
  points (Off counts as 1.0; no viewport → the window's own size). The display
  is an *envelope*, a square of the panel's longer edge ÷ 0.5 plus the menu
  bar, reused while the wanted window fits, so rotation and Aa steps re-place
  the window and restart the pipeline without recreating the display; the
  device always gets exactly the window's rectangle. Deviation from the
  "sized to the panel" brief; `VirtualStage.envelope` returning `windowSize`
  restores the literal behaviour.
  Verified without permissions: default path byte-for-byte unchanged (~55 fps
  synthetic, plain SIGINT death); flag path streams the synthetic Desktop at
  ~55 fps under the AppKit loop and exits 130/143/129 with the window restored;
  `--virtual-display-selftest` creates a 1000×700@2× display in ~150 ms,
  online after ~250 ms, destroyed in ~60 ms, no permission needed for the
  display itself. Three review lenses plus adversarial verification found and
  fixed: a stale display reference after the grow path, placement recorded
  only after the first move (a Ctrl-C mid-staging lost the window), a failed
  pipeline start leaving the stage staged, a last-client-left during a switch
  being dropped, and `.cannotComplete` mistaken for "window gone".
  Learned: without Screen Recording, `SCShareableContent` never returns while
  a virtual display exists, so every SCK call on these paths is bounded
  (`WindowCatalog.shareableContent(…timeout:)`) and `prepare` refuses to make
  a display without the permission.
  Learned (2026-09-23): the window list shows an AX move only once the app
  commits it, a few to tens of ms after the AX writes return (more for an app
  slow to lay out); the AX frame reads the new frame at once. So the eviction
  scan right after a switch found the window just sent home still listed on
  the display, matched no AX window to that frame and printed "A System
  Settings window sits on the virtual display and could not be matched…"
  (twice, both false alarms: the window went home). Fixed: `releaseWindow`
  keeps the element (`lastReleased`) and the scan judges that window by its
  live AX frame: home, skipped; still overlapping (Messages kept a wider
  frame, a 24 pt strip), evicted and centred by its live size. The warning now
  names the window ID and listed frame. Probe on its own off-screen window,
  scan at once: the old logic warned in 21 of 30 scans, the new in none, and
  picked the overlapping window for eviction 20 of 20. Not yet run with real
  windows.
  Fixed (2026-09-23): `prepare`'s settle loop read only the window list and
  stopped after three identical reads 20 ms apart, counted from the frame
  before the move, so a pure resize the app commits late (1Password, Electron:
  between 45 ms and ~0.45 s) looked settled at once and the old frame became
  the crop until the catalog's next poll re-selected (~0.4 s of wrong crop).
  Now it reads the AX frame once after the writes. A new size there means
  stillness counts only once the listed size has left the old one, the list
  showing AX's frame ends the wait, and the deadline is 1 s; the old size (a
  refusal) counts stillness at once within 0.5 s, as before. A wait that runs
  out appends "; not settled by the deadline" to "Moved …", whose "from" is
  now the frame before the move (it printed the home frame). A restart that
  asks for the same rectangle as the last placement (the request fitted to the
  usable area, so a Dock arriving on the display still gets the window
  re-fitted) finds a clamped window where it was left and skips the move.
  Step (6) run verbatim in a harness: a probe window whose commit trails its
  frame by 80/150/300 ms was cropped at the old frame every time before, at
  the new one in 104/181/341 ms now; a refusal still settles in ~50 ms; a
  clamped restart takes 0 ms and no move; simulated, a Dock arriving between
  two restarts still gets the window re-fitted. Known limit: an app whose AX
  frame lags too (it applies the size after answering the write) still reads
  as a refusal, and its old frame stays the crop until a catalog poll (2 s;
  one that lands mid-switch is ignored) re-selects.
  **Untested, for Noah** (Screen Recording + Accessibility on the terminal):
  (a) `swift run -c release SillHost --virtual-display`, pick a window: the
  log shows "Virtual display … created", "Moved …", "Capturing … of virtual
  display", and the frame fills the panel edge to edge at Aa 1× with the title
  bar as the top edge; System Settings › Displays shows one "Sill" display.
  (b) Cover the window's old spot, switch Spaces, open Mission Control: the
  device keeps updating. (c) Deselect, pick Desktop, quit the iOS app, Ctrl-C
  mid-stream: each prints "Restored …" then "Removed virtual display", the
  window is back within 2 pt, no "Sill" display remains. (d) Rotate and cycle
  Aa while staged: one "Capture started" per change, no new display created.
  (e) The 1Password Aa step that showed the stale crop (staged at Aa 0.5,
  then 1×): the first "Moved … to" shows the asked 1117×610 and "Capture
  started" reads 2234×1220, with no second capture ~0.4 s later.
  If the picture is offset or black, the escape hatch is the last line of
  `VirtualStage.prepare`: return the `desktopIndependentWindow` filter with a
  nil `sourceRect` (window capture on the virtual display ran at 59 fps in the
  probe).

**Bar controls (2026-09-23).** Press and hold a thumbnail: macOS's three lights
appear over it (close, minimize, full screen → `.windowCommand` = kind 15, JSON
`WindowCommand`; the host presses the window's own buttons through
Accessibility, using the staged element on the virtual display). Keep holding
and move: the lights go, the thumbnail lifts and drags into a new slot, Home
Screen style; the arrangement is the device's own (`StreamClient.windowOrder`,
persisted per Mac, host order for the rest). A "Leave" button disconnected
(since the host settings step the last slot is Settings, with Disconnect in its
panel's foot). The device asks for the Desktop whenever the host reports nothing
streaming (at most every 10 s), so a fresh connection starts on the Desktop and
the drawer no longer opens by itself. When the watched window has closed it
waits 2 s first, and asks for nothing if the user picked or launched something
meanwhile (the host cannot tell that request from a Desktop tap). Harness:
`-SillWindowMenu 1` keeps the first thumbnail's lights open.

**Frame rate follows the device (2026-09-22).** `Viewport.fps` carries the
device's wanted rate: `UIScreen.maximumFramesPerSecond` (120 on ProMotion, 60
on the iPad mini), or 60 while Low Power Mode is on; the client re-sends on
`NSProcessInfoPowerStateDidChange` and `UIScreen.modeDidChangeNotification`.
The host keeps each client's rate (`clientFPS`, cleared on disconnect) and runs
the stream at the highest, capped by `maxFPS` and by 60 on the software
encoder; `fps` is re-read at every select;
a changed rate restarts the pipeline (capture interval, encoder session and
the virtual display's refresh all follow it), and bitrate scales with it.
Verified synthetically: 120 → "120 fps, 30 Mbps", drop to 60 mid-stream
restarts at 60 within a frame; `--virtual-display-selftest 120` comes online
at 120 Hz. Not yet measured on a ProMotion device or with the hardware encoder
(the software encoder manages ~22 fps at 1512×948 when asked for 120, which is
why it exists only as a fallback). `CADisableMinimumFrameDurationOnPhone` is
set so ProMotion iPhones render above 60.

**Trackpad stutter (fixed 2026-09-22), three causes, all measured:**
1. The device's Wi-Fi radio dozes when the downlink goes quiet, and every next
   packet then waits up to ~300 ms (iPad ping RTT sawtooth 5→100→200→300 ms with
   nothing streaming; the loopback simulator stays at 0). A trackpad stroke over a
   static window starts from a dozing link, so its first frames bunch up. The host
   now sends an empty `.tick` every 30 ms (~0.5 KB/s) while a source is live or a
   client sent input in the last 3 s, and both ends use the `.interactiveVideo`
   service class. Verified: RTT flat at 6–11 ms over 20 s with a static window.
2. A periodic IDR every 4 s (1–2 MB at 3024×1898) showed as a 50–100 ms
   RTT/frame-age spike every 4 s. Keyframes are on demand (connect, dropped
   delta, switch); the periodic safety interval is 4 s (`fps * 4`); a 30 s try was reverted while bisecting the freeze.
3. The only pointer the user could see was the Mac cursor baked into the video,
   so it moved as unevenly as the video arrived. The client now draws its own
   arrow sprite (`HEVCDisplayView`, a CALayer, no implicit animation, fed by
   `StreamClient.localPointer`, not @Published) for the trackpad and Pencil
   hover; the host leaves the Mac cursor out of the video for good
   (`showsCursor` false at capture start; reconfiguring a running SCStream
   wedged it) and streams its shape as `.cursorShape`. The trackpad also lost UIKit's ~10 pt start-of-
   stroke dead zone (a zero-duration long-press tracker drives the first
   movement) and gained Force-Touch-style haptics on click/drag (iPhone only:
   iPads have no Taptic Engine).
Dead-client eviction is time-based (no frame drained for 4 s, none in the first
8 s after connect): the frame-count rule evicted the simulator at full Retina.
A client evicted while the Mac is still advertised now retries on a timer.
Learned (2026-09-23; this replaces the caveat on (1)): the RTT spikes left with
ticks flowing come from AWDL, and Sill turns AWDL on itself. `includePeerToPeer
= true` on the host's NWListener (`StreamServer`) and the iPad's NWBrowser and
NWConnection (`StreamClient`), there since the first commit, makes the kernel
enable AWDL as `_sill._tcp` registers ("Enabling AWDL due to Mdns"; off ~3 s
after Sill quits). The Mac's one radio then leaves the Wi-Fi channel on a
512 TU schedule (kernel: infra 72 % while streaming, 48 % or 0 % around
switches). A 20 Hz ping from the Mac to its gateway stalls up to ~97 ms once
every 524 ms (p90 48 ms, 17 % over 10 ms; with AWDL off, p90 4 ms and max
13 ms). The same Bonjour service registered with the AWDL flag gave p90
67.5 ms with 32 % of pings delayed, against 3.9 ms without the flag. An rtt
sample that lands in a stall reads baseline plus 0–100 ms. AWDL carries none
of Sill's data (the connection is on en0). Ticks keep the radio awake but not
on the channel, and every earlier RTT reading, those in (1) and (2) included,
ran with AWDL on. The fix is applied (2026-09-24, Direct Wireless Connection
in the current step): `includePeerToPeer` is off by default on both sides and
comes back only for a Mac whose owner turns the setting on, and on the device
during a nearby search (Search Nearby, or a Mac last seen with the setting on
missing from the network), which stops once connected; the iPad side still
needs a device run. Secondary: `inflight > 2` counts only what
Network.framework has not handed to the socket, so after a switch the socket
buffer (autotuned up to 4 MB) can hold ~200 ms of frames ahead of pongs (frame
age 188–229 ms, no `net.dropped`). Client measurement, reworked 2026-09-23
(it sampled frame age every 15th frame and repeated the last value in a
slower second, sent one rtt sample per report, and ran its fps and ping
timers in the main run loop's default mode, so both stopped while a scroll
tracked): the client now takes the age of every frame and pings every 0.25 s
(stamped with the monotonic clock), both on dispatch timers on its network
queue, and closes a one-second window each second. Each report carries that
second's median in the old `ClientStats` fields, -1 for a second without a
sample (a still window streams no frames), and its max in two new optional
fields. The host still logs every other report, now as
`frame age 9/24 ms, rtt 7/80 ms` (the last second's median over the worst
since the previous line, "–" for no sample; an older client prints one
value), and the menu's device row and the HUD show "–" the same way.

**Frozen stream, 2026-09-22 evening — the Mac's hardware video encoder wedged.**
Every new HEVC session (and later H.264) accepted one frame and never returned
it, even from a fresh process with synthetic frames (`SillHost
--encoder-selftest`, `CaptureProbe --synthetic`). The old encoder called
VideoToolbox synchronously on the capture queue, so the stuck call froze
ScreenCaptureKit, then `stopCapture`, then the coordinator's `switching` flag,
and every later selection was silently ignored. The wedge held for about
three hours and then cleared on its own at ~22:30 (a fresh hardware session
encoded again while the orphaned sessions in the old encoder-service process
were still logging their 4 s timeouts), so a reboot is the sure fix, not the
only one. Protections now in the host:
- At launch the host pushes one 256×256 frame through a hardware session
  (`EncoderProbe`, ~100 ms when healthy, 1 s deadline). No answer means the
  host starts on the software encoder at once and says so, instead of hanging
  the first stream for 1.5 s and restarting it.
- `HEVCEncoder` is a one-slot mailbox: the capture queue never waits; one frame
  at a time is inside VideoToolbox on its own queue; a watchdog on a separate
  queue declares the session hung after 1.5 s and calls `onHung`.
- The coordinator then restarts the source on the software encoder at half
  scale (slow, ~10 fps under load, but live) and says so in the log; three
  software hangs stop the stream instead of looping.
- Presentation timestamps are forced monotonic; a keyframe request re-encodes
  the last frame only when the window is static.
- Never reconfigure a running SCStream (`updateConfiguration` also wedged it);
  the Mac cursor is left out of the video for good and the device draws it,
  with the Mac's live cursor shape streamed as `.cursorShape`.
- Regular mode raises the picked window on select (2026-09-23, Noah: the Mac
  must show the picked window): app activated, window raised and made key,
  before capture starts. Picks only (switcher, command line, an app launched
  from the device); the host's own restarts (resize, rate change, encoder
  fallback) leave focus alone. The virtual display never touches Mac focus on
  select; a pick that falls back to the real window counts as regular mode.
  Interacting works like a real click in both modes: a click, keystroke or
  typed text activates the app through Accessibility only
  (`NSRunningApplication.activate` is refused from a background process, and
  a Launch Services "open" of a running app counts as opening it, which
  switched on Noah's Work Focus automation, so it is never used; an app that
  refuses AX simply stays back), input held until it is up (at most 0.6 s) so
  the first click lands; on the regular path a window covered at the click or
  scroll point is also raised. Input that arrives mid-switch is delivered but raises nothing
  (`active` still names the old window, and raising it would cover the pick).
  Ghost "LayerProbeParent" windows that SwiftUI apps spawn per new display
  are filtered from the catalog.
Verified 2026-09-22 with `--synthetic` against the still-wedged encoder: hang
detected at 1.5 s, software restart, 55–59 fps out, the iPad decoding it fine.
Diagnosis tools: `swift run -c release CaptureProbe <window> [s] [--encode]
[--synthetic] [--software] [--h264] [--lowres]` (capture vs encode, hardware vs
software) and `sample <pid> 2` (a wedged encode shows as
VTCompressionSessionEncodeFrameWithOutputHandler → RemoteVideoEncoder).

Still open: the unexplained one-off stall where new clients received no catalog
(2026-09-22, hardened since, never reproduced). Keep the connect-path logging.
Known: a streamed window covered by another window on the Mac freezes on the
device (macOS stops repainting it) until the device picks it again or clicks
or scrolls in it, which raises it. `--virtual-display` removes the freeze for
good.

## Milestone 2 (input and window control) — done 2026-09-22

- Client → host input: tap/click, finger pan → scroll with trackpad gesture
  phases and client-generated momentum (host sets CGEvent scroll/momentum
  phases so apps rubber-band and fling), long-press right-click, Pencil as the
  mouse with hover, software keyboard as Unicode text, hardware keys and
  ⌘/⌃/⌥ chords as HID usages. Portrait laptop layout: stream on top, key row
  (esc, tab, latching modifiers, arrows, keyboard; Spotlight = ⌘Space only while
  the Desktop is the source, since Spotlight's panel is its own window) and a
  relative trackpad. Picked app is brought forward; window follows moves;
  resize restarts the pipeline.
- Latency, measured 2026-09-22 on 5 GHz Wi-Fi to the iPad mini via the client
  stats the host logs: frame age (host encode → device receive) 8–10 ms,
  ping RTT 6–9 ms with rare spikes. Adding capture (≤1 refresh), encode and
  decode+display (1–2 refreshes) puts glass-to-glass at roughly 40–60 ms,
  within the v1 bar. Not photographed with the stopwatch method yet.
- Host footprint (release build, `ps`): idle with no client 0.0 % CPU, 36 MB,
  one heartbeat line per 30 s and no ScreenCaptureKit calls; connected with
  nothing selected 0.0–0.1 %; streaming a Retina window ~3 %. Capture stops when
  the last client leaves.
- Diagnostics: `-SillHUD 1` (DEBUG) overlays fps · frame age · rtt · frame size
  on the device; the client reports the same to the host every second and the
  host prints `client <device>: …`.
- Learned: `_AXUIElementGetWindow` is private, so AX windows are matched by
  title then frame; apps enforce minimum sizes, the host streams what it got.

## Milestone 1 (latency spike) — done 2026-09-22

- Mac host builds and runs from `swift build -c release`: window listing,
  ScreenCaptureKit capture, VideoToolbox HEVC encode, Bonjour advertisement,
  TCP fan-out to clients.
- iOS client is a real Xcode project (`iOSClient/Sill.xcodeproj`), builds
  clean, runs on Noah's iPad Mini (the test device: iPad scalability plus a
  Duo-like aspect ratio).
- End to end verified on Wi-Fi: ~58 fps captured, encoded and sent with zero
  drops at 3024×1898 (Retina capture of a 1512×949 window), 15 Mbps.
- Bugs found and fixed along the way: SCStream aborting with `CGS_REQUIRE_INIT`
  when set up off the main thread in a CLI tool; the whole pipeline being
  released when the startup Task finished (one frame, then silence); clients
  that connected to a static window never receiving a keyframe.
- Host prints a per-second stats line (captured/encoded/sent/dropped) so a
  stalled stage is visible without a debugger.
- Toolchain on Noah's Mac: Xcode 27 selected as developer dir, license
  accepted, first-launch packages installed. No signing identities existed;
  Noah signs with his own team in Xcode.
- Learned: ScreenCaptureKit delivers frames only when the window repaints, and
  macOS stops repainting fully covered windows, so a streamed window buried
  behind others on the Mac freezes on the device. Inherent to window capture;
  the virtual-display plan in milestone 3 sidesteps it.
- Not measured: the latency number itself (see above).

## Layout

- `Package.swift` — SwiftPM. Products: `StreamProtocol` (shared wire format,
  iOS + macOS), `SillHost` (the CLI, target `SillHostCLI`) and `SillMenuBar`
  (Sill.app's executable). `SillHostCore` (the host, folder `Sources/SillHost`)
  is a library target with no product, so the iOS project never sees it.
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  message kinds in both directions, HEVC parameter set encoding. Shared by both
  sides. Change it in one place. `Switcher.swift` — the catalog types
  (`WindowList`, `WindowInfo`, `AppInfo`, `StreamSource`) and image blob framing.
  `HostSettings.swift` — the host settings a device sees and changes (kinds 16
  and 17): `StreamSettings`, `RunningStream`, `HostSettingsState`,
  `HostSettingsChange`, `SettingsChoices` (the Mac menu's values) and
  `QualityPreset` (Low, Efficient, Balanced, High, Maximum). Remote access:
  `Remote.swift` (kinds 18–22's payloads: `MacAddress`, `MacInfo`,
  `SignedMacInfo`, `PairRequest`, `PairResult`, `Goodbye`), `RemoteTLS.swift`
  (the one TLS 1.3 builder for both doors' ends and the tests),
  `RemoteIdentity.swift` (SPKI fingerprints, the Mac ID, the hand-built
  certificate, keys), `Pairing.swift` (`PairingCode`, `PairingProof`,
  `RecognitionTag`, `PairLink`), `AddressParser.swift`, `SafeText.swift`.
- `Sources/SillHost/` — the `SillHostCore` library. `StreamCoordinator` (main
  actor; owns the pipeline, switches sources on client request, raises the
  picked window in regular mode (never on the virtual display), applies
  viewports, falls back to the software encoder on a hang, stops capture when
  the last client leaves, takes live settings between pipelines (`setTarget`,
  from the app and from devices' kind 17, answered and published as kind 16;
  a pick made during a restart runs after it) and writes `HostStatus`), `HostConfig` (the knobs: maxFPS, captureScale, bitrate
  per 60 fps, prioritizeSpeed, virtualDisplay, directWireless; `standard` is the
  CLI's values and the app's defaults), `HostStatus` (the snapshot the app shows, pushed on
  events; `onChange` publishes the devices' settings state), `DeviceSettings`
  (what a device may set, `HostConfig` ↔ wire), `HostLog` (the print shadow,
  the app's ring and log file),
  `WindowCatalog` (polls windows and thumbnails only while a client is
  connected; icons; installed apps in the background),
  `WindowCapture` (ScreenCaptureKit), `SyntheticCapture` (test pattern for
  `--synthetic`), `HEVCEncoder` (VideoToolbox behind a one-slot mailbox with a
  hang watchdog; hardware or software), `EncoderSelfTest`
  (`--encoder-selftest`), `CursorShapeWatcher` (NSCursor.currentSystem →
  `.cursorShape`), `StreamServer` (Network.framework + Bonjour `_sill._tcp`, both
  directions, keepalive, dead-client eviction, ping echo, client-stats print;
  the listener built with or without peer-to-peer and replaced live when Direct
  Wireless changes; the test-only SILL_TEST_SERVICE_TYPE and SILL_TEST_SWAP_FAIL),
  `InputInjector` (CGEvents: pointer, scroll with phases, text with modifier
  flags cleared explicitly (a ⌘Space before typing otherwise tainted the text
  events and Spotlight ignored them), HID keys),
  `WindowSizer` (Accessibility resize for the Aa scale; `placement/move/
  restore` for the virtual display), `VirtualDisplay` (private-API wrapper),
  `VirtualStage` (`--virtual-display`: owns the display and the moved window,
  geometry, prepare/release, emergency restore), `HostShutdown` (signal
  sources + atexit, installed only with the flag in the CLI, always in the app;
  `releaseForQuit` for the app's Quit), `VirtualDisplaySelfTest`
  (`--virtual-display-selftest`), `Stats` (1 s lines while active, 30 s
  heartbeat when idle). Remote access: `OriginPolicy` + `InterfaceSnapshot`
  (who may use which door; pure), `RefusalSummary` (one refusal line a minute),
  `HostIdentity` (the `IdentityStore` protocol, `MemoryIdentityStore`, the TEST
  ONLY `FileIdentityStore`, `PairedDevice`, the lock-protected trust snapshot
  the door reads on the network queue), `KeychainIdentityStore` (Sill.app's),
  `PairingWindow` (pure), `RemoteServer` (the remote door), `Reachability`,
  `AddressList` (pure) and `RouterAddress` (read-only NAT-PMP/PCP),
  `RemoteAccess` (main actor; ties them together, signs kind 18).
- `Sources/SillHostCLI/main.swift` — the CLI: flags, `dispatchMain` vs
  `NSApplication.run`, the Terminal permission hint.
- `Sources/SillMenuBar/` — the app: `main.swift` (AppKit lifecycle, accessory
  policy), `AppDelegate` (launch order, Quit, the modal-loop rule), `AppModel`
  (owns the coordinator, presentation, App Nap guard, onboarding),
  `HostSettings` (UserDefaults, quality presets), `StatusItemController`
  (+ `MenuBuilder`), `StatusText` (all status copy), `StatusCard`,
  `StatusGlyph`, `SettingsWindow` + `SettingsPanes`, `Permissions`,
  `LoginItem`, `LogWindow`, `MainMenu` (key equivalents), `DebugHooks`,
  `AppLog` (its print shadow), `RemoteAccessPane` (Settings › Remote Access),
  `PairDeviceWindow` (the QR code and the typed code).
- `Packaging/` — Sill.app's `Info.plist` and the development entitlements
  (get-task-allow only). `Scripts/make-app.sh` builds, iconizes, signs and
  installs the bundle; `Scripts/sillclient.py` is the wire-format test client
  (timed `--set=K=V[,K=V]@T` kind 17 changes with tokens 1, 2, 3…,
  `--raw17=JSON@T`, `--pick=none|desktop|window:ID@T`, `--stats`,
  `--expect=K=V[,…]` against the last kind 16, which it prints one per line;
  `--host`, `--device`, `--big-payload`, `--flood`, `--stop-ping@T`,
  `--stop-read@T`, `--pairing-wanted@T`; the remote door with `--tls
  --identity=DIR`, `--pair-url`, `--pair-code`, `--pin=FP|none` and
  `--expect-tls-fail`, printing kinds 18, 20 and 22; every argument is checked
  before it connects, and a bad one exits 2). `Scripts/sillrelay.py` is a
  shaping passthrough relay (`--listen 0 --to HOST:PORT [--delay-ms N]
  [--rate-mbps R] [--blackhole-after S] [--record PREFIX]`; TLS passes
  through).
- `Sources/VirtualDisplayProbe/` — CLI experiment for milestone 3; run it from
  Terminal (needs Screen Recording + Accessibility): `.build/release/VirtualDisplayProbe "Activity Monitor" --seconds 20`.
- `iOSClient/` — `Sill.xcodeproj` and its sources: `StreamClient` (Bonjour: a
  network browser and, when `DiscoveryPolicy` says, a nearby peer-to-peer one;
  `FoundMac` rows; connection, parsing, reconnect, ping, generic `send`),
  `DiscoveryPolicy` (when to look nearby, the rows, when a reconnect may take
  a Direct row, the memory of Macs with Direct Wireless on; pure, checked with
  swiftc), `StreamScreen`
  (landscape: top bar, thumbnails, drawer, Aa, Keyboard, Desktop; layout
  selection by size incl. Duo outer display), `PortraitStreamScreen` (laptop
  layout: stream, compact bar, key rows, trackpad), `InputOverlay` (direct touch,
  Pencil, keyboard, scroll momentum), `TrackpadView`, `HEVCDisplayView` (shared
  display view + DEBUG HUD), `DiagnosticsHUD` (client stats reporter),
  `StreamClient+Viewport`, `ContentView` (connect screen with Direct rows, the
  hint and Search Nearby, + DEBUG harness),
  `MockCatalog` (harness data and the settings cases), `HostSettingsLedger`
  (the Mac's settings with this device's unanswered picks; pure logic, checked
  with swiftc), `HostSettingsPanel` (the Settings panel; the route line, Away
  from home, the slow-link callout). Remote access: `DeviceIdentity`,
  `SavedMacs` (pure), `RemoteDialPolicy` (pure), `RemoteConnector`,
  `StreamClient+Remote` (pairing, remote dials, the reconnect order, links),
  `AddMacCard` (the card, the fields, `EscapeKey`), `CodeScanner` (VisionKit),
  `PairingOverlay` (Pair This iPad…). New files need their four pbxproj
  entries by hand. Swift 5 language mode.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.

## Build and run

```
swift build -c release
swift run -c release SillHost              # nothing streams until the iOS app picks a window
swift run -c release SillHost Safari       # optional: preselect a matching window
swift run -c release SillHost --synthetic  # Desktop streams a test pattern; no Screen Recording needed
swift run -c release SillHost --encoder-selftest   # is the hardware encoder alive? 5 s, exits
swift run -c release SillHost --virtual-display   # picked windows stream from their own HiDPI display (off by default)
swift run -c release SillHost --virtual-display-selftest   # create/destroy one display, report what sees it
swift run -c release SillHost --direct-wireless   # also over peer-to-peer Wi-Fi (AWDL): devices without a shared network (off by default)
swift run -c release SillHost --remote      # the remote door for this run on any free port (--remote=PORT), a throwaway identity; the code and link print here
swift run -c release SillHost --remote --internet   # also admit paired devices from outside this Mac's networks and VPNs
swift run -c release SillHost --print-reachability  # the addresses a device would get away from home, then exit
python3 Scripts/sillclient.py PORT 8 desktop --set=bitrate=25000000@3 --expect=bitrate=25000000   # a device's settings change
Scripts/make-app.sh                     # .build/Sill.app, signed with the Apple Development identity (~2 s unchanged)
Scripts/make-app.sh --install --open    # Noah: replace /Applications/Sill.app (a running one quits first), launch it
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' Scripts/make-app.sh --release   # M6
```
Needs Xcode as the active developer directory with its license accepted; with
Command Line Tools only, add `--build-system native`.
First run prompts for Screen Recording: the CLI's belongs to Terminal (or
whatever launched it), Sill.app's to Sill itself.
Sill.app: the log is `~/Library/Logs/Sill/Sill.log` (`tail -F`, not `-f`: at
10 MB it moves to Sill.1.log; Show Log… in the menu); settings are `defaults
read me.saffer.sill.mac` (maxFPS, captureScale, bitrate, prioritizeSpeed,
virtualDisplay, directWireless), and a launch argument such as `-maxFPS 60`
overrides one for one run. A device's change from its Settings panel is saved there too, like a
menu click; the CLI keeps a device's change until SillHost quits. Test arguments for the bare binary (`.build/release/SillMenuBar`,
defaults domain `SillMenuBar`; delete it after): `--synthetic` (test pattern,
off Bonjour; the port is in the "Status: Test Pattern Mode" line),
`-SillLogFile <path>`, `-SillSetAfter '<s> key=value[,key=value][; <s> …]'`,
`-SillQuitAfter <s>`, `-SillRenderPreviews <dir>` (panes, cards, glyphs,
menu.txt; no permission needed). Render previews from
`.build/Sill.app/Contents/MacOS/Sill` to see what Sill.app looks like: only the
bundle's copy records the real SDK (make-app.sh sets it with vtool; see Current
step), and the bare binary draws the pre-26 look. `--encoder-selftest` and
`--virtual-display-selftest` work in the app too.
iOS side: open `iOSClient/Sill.xcodeproj`, set your team, run on a real
device on the same Wi-Fi (or with the Mac's Direct Wireless Connection on).
AWDL, headless and without touching a running Sill.app: the synthetic hosts do
not advertise, but `SILL_TEST_SERVICE_TYPE=_silltest._tcp` registers them as
"Sill test ‹pid›" under that test type (never `_sill._tcp`, so no device sees
them) with the listener's own peer-to-peer flag, and prints which one it got;
`SILL_TEST_SWAP_FAIL=port|all` makes a replacement's same-port (and any-port)
bind fail; both are honoured only by a host that does not advertise. `dns-sd -t 3 -includeAWDL -B _silltest._tcp local` lists a
registration that includes AWDL a second time on awdl0's index (`python3 -c
'import socket; print(socket.if_nametoindex("awdl0"))'`, 16 here). dns-sd
options go before the command: `dns-sd -R … -includeAWDL` registers a TXT
record "-includeAWDL" and sets no flag. The kernel's count of AWDL services:
`/usr/bin/log show --last 1m --style compact --predicate 'process == "kernel"
AND eventMessage CONTAINS "BonJourTrig"'` ("ValidSvc N" once a second; a
registration with AWDL adds 2, a peer-to-peer browse 1); `log` is a zsh
builtin, hence `/usr/bin/log`, and `process == "kernel"` keeps the log tool's
own line out. Enable and disable lines ("Enabling AWDL due to Mdns") show only
when nothing else holds AWDL. Keep AWDL-on tests under 20 s and on test types.
Remote access, headless: TEST ONLY variables, honoured only by a host that
does not advertise: `SILL_TEST_REMOTE_DIR=<dir>` (the identity and trust list
in a 0700 directory instead of memory or the keychain; the bare app's
`-SillPairAfter <s>` leaves `pairing.url` and `pairing.code` there, 0600, never
printed), `SILL_TEST_PAIRING_TTL=<s>`, `SILL_TEST_BACKOFF_SECONDS=<s>`,
`SILL_TEST_ORIGIN=vpn|internet` (loopback counts as that origin) and
`SILL_TEST_NO_ROUTER=1` (never ask the router; set it on every headless host).
The bare app takes `-remoteAccess 1 -remotePort P`, `-SillSetAfter '3
remotePort=P2'`, `-SillPairAfter <s>` and `-SillUnpairAfter <s>`; its
`-SillRenderPreviews` adds the Remote Access pane's states and the pairing
window's. A session through a shaped link: `python3 Scripts/sillrelay.py
--listen 0 --to 127.0.0.1:P --delay-ms 150 --rate-mbps 2`, then
`sillclient.py RELAYPORT 90 desktop --tls --identity=$T/a --stats` after
`--pair-url=URL` once. Never let a test binary take a connection from another
machine: the Application Firewall prompts. Reset the app's remote settings with
`for k in remoteAccess remotePort internetAccess remoteAddressName
remoteDevicesSeen; do defaults delete me.saffer.sill.mac $k; done`.
Debug harness (simulator, no Duo simulator exists yet): launch arguments
`-SillLayout 1000x710` (inner landscape) / `710x1000` / `500x710` / `710x500`
(outer), `-SillLive 1` (real client inside the frame), `-SillDrawer 1`,
`-SillActive none|desktop|<windowID>` (mock), `-SillHUD 1` (diagnostics overlay),
`-SillSettings 1` (the Settings panel open), `-SillSettingsCase
default|cli|software|custom|vdproblem|vdstream|legacy|pending|timeout|direct|
directlink|nodirect` (the mock Mac's settings; it answers a pick after 0.35 s),
`-SillConnectCase looking|hint|nearby|denied` (the connect screen in a discovery state;
the mock never browses) and remote access's `remote|addmac|addcode|addcodeerror|
pairing|remotedial|remotefail|camera|externalpair` (`-SillRemoteFailure
vpnoff|timeout|timeoutip|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|
remoteoff` picks remotefail's words), the settings cases `remote|remoteinternet|
remoteslow|remotepair|remoteoff|noremote`, `-SillSettingsEnd 1` (the panel
scrolled to its end), `-SillScanOverlay 1` (Pair This iPad…'s overlay), and in
the normal app `-SillPairURL '<sill://pair…>'` (pair at launch, no
confirmation), `-SillPairCode <12 digits> -SillPairAddress host:port`,
`-SillDialSaved 1`, `-SillForgetMacs 1`, `-Sill.savedMacs '<JSON>'` (one run;
`'[]'` empties), `-SillRemoteRoute vpn|internet` (a loopback session counts as
that route), `-SillScreenFPS 120` (a 120 Hz screen) and `-SillDeviceKeySE 1`
(a Secure Enclave device key, R0-a); `xcrun simctl openurl <udid>
'sill://pair…'` shows the link's confirmation after the system's "Open in
Sill?". `-Sill.directWirelessMacs '("Mac mini")'` (seeds the
device's memory of Macs with Direct Wireless on for one run; `'()'` empties it),
`-SillConnect 127.0.0.1:PORT`
(connect by address, also in the normal app: the only way to reach the
off-Bonjour synthetic hosts from the simulator). A fake screen wider than the
simulator but fitting on its side (1133x744 on an upright iPad Pro 13") is
drawn a quarter turn clockwise; `sips -r 270` the screenshot.

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
- License: Apache-2.0 or MPL-2.0 (paid plan is gone, so no GPL/CLA needed).
- v1 out of scope: hole punching, multi-window, layout customization, audio.
