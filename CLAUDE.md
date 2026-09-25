# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

## Current step

**Quality presets (2026-09-24, branch `quality-presets` from main at
ad7fba2).** Noah's decisions: Maximum is renamed Pro; two presets above it,
Ultra (80 Mbps) and Extreme (150 Mbps), for the USB cable or very fast Wi-Fi;
the bitrate knob's cap goes from 100 to 200 Mbps per 60 fps (a 120 fps stream
still gets double, so Extreme at 120 fps is 300 Mbps); no Unlimited.
- `QualityPreset` (StreamProtocol's HostSettings.swift): Efficient 8,
  Balanced 15, High 25, Pro 40, Ultra 80, Extreme 150 Mbps per 60 fps,
  declared in ascending order, which is the order of the status menu's Quality
  submenu, Settings › Streaming and the device's Quality menu (all build from
  `allCases`). The raw values are the bitrates, so the rename changes nothing
  stored or sent: a Mac on 40 Mbps shows Pro. `QualityPreset.fastLinkNote` is
  the one sentence both ends add to their Quality footers ("Ultra and Extreme
  need the USB cable or very fast Wi-Fi; if the picture lags, step down."); the
  menu's Quality subtitle is unchanged.
- `HostConfig.validated()` clamps to 1–200 Mbps, so a launch argument or a
  hand-set default above that runs at 200 ("Custom — 200 Mbps"). A device still
  sets only presets: `DeviceSettings.accepted` checks `SettingsChoices`, which
  follows the presets, so it takes 80 and 150 unchanged, and refuses 200 or
  250 from a test client rather than clamping them. Kinds 16/17 unchanged.
- Mixed builds: a host from before this change refuses Ultra and Extreme from
  a newer device (the row goes back; VoiceOver hears "‹Mac› kept its
  setting"); an older device shows a newer Mac's 80 or 150 Mbps as "Custom —
  N Mbps", read-only, and 40 as "Maximum — 40 Mbps".
- Verified without a device: clean builds (only the old CaptureProbe and
  `StreamClient` warnings); the CLI's synthetic output, idle and with a client,
  equals ad7fba2's (masked and sorted; unmasked only timings and ports
  differ); a test client's Extreme then Ultra restart the stream at 150 and 80
  Mbps ("Settings from sillclient: bitrate 15 → 150 Mbps per 60 fps"), Extreme
  at 120 fps runs at 300 Mbps, and 200 and 250 Mbps are refused with the value
  unchanged in the answer; the bare app runs `-SillSetAfter` and `-bitrate`
  250 Mbps at 200 ("Settings: bitrate 15 → 200 Mbps per 60 fps", devices told
  200) and saves a device's Extreme across a relaunch; the hardware encoder
  takes and reads back AverageBitRate up to 400 Mbps at 3024×1898; previews
  against ad7fba2 differ only in menu.txt's Quality rows and the Streaming
  pane's footer; the ledger check (H2) with the six raw values and 5,000
  random runs; the panel in the simulator at 1000×710 and 500×710 (also at
  xxLarge text), menu open and closed, picking Extreme, and live against this
  host (a restart at 150 Mbps) and against ad7fba2's (refused, back to
  Balanced); the harness's `vdstream` case, now Extreme at 120 fps (300 Mbps,
  the longest readout), at all four sizes and at xLarge and xxLarge text: the
  readout wraps at xxLarge, and at 710×500 already at xLarge; the header and
  Disconnect stay put and the rows scroll.
- **Untested, for Noah:** Ultra and Extreme on the iPad over the USB cable and
  over Wi-Fi, streaming a busy window (the synthetic pattern compresses to
  under 1 Mbps whatever the target): watch the frame age in the host's
  `client …` lines and the menu's device row, and step down if it climbs.

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
  ("Direct wireless on: listening on port P again, advertised again."). Except
  when it turns off: once that replacement is advertised (or has failed for
  good), every device still on peer-to-peer Wi-Fi is disconnected, one line
  each ("Direct wireless off: disconnecting iPad (…) at fe80::…%awdl0.N, which
  was connected over peer-to-peer Wi-Fi; it can reconnect over the network."),
  because an open awdl0 socket keeps the kernel's AWDL up (Noah's sessions,
  2026-09-24: off changed nothing while the iPad was on awdl0). `ClientLink`
  reads the route from the endpoint's scope (`%awdl0`/`%llw0`; AWDL has only
  link-local addresses); other clients are untouched, and a burst that ends on
  disconnects nobody. Requests coalesce (newest wins), and late callbacks of a
  replaced listener are inert. No `.cancelled` within 1 s or the same port
  refused: any port, with a line; both refused: the existing listener-failure
  rule (the app shows "Not Visible on the Network" and keeps running, the CLI
  exits 1), and the next toggle retries. CLI: `--direct-wireless` prints one
  startup line; without it the output is the branch point's byte for byte
  (masked and sorted).
- Sill.app: Settings › General "Direct wireless connection" right after
  "Visible on your network as", and a "Direct Wireless Connection" item at the
  top of the status menu's second group, absolute like Virtual Display. Saved
  under `directWireless`; an existing install has no key, so it comes up off.
  The status menu's card ends each device's row in how it reaches this Mac
  (Noah, 2026-09-24, branch `connection-route-in-settings`: "next to bitrate"),
  and while exactly one device is connected the source row too, after the Mbps:
  "Wired" (the cable's anri0, or any wired Ethernet interface), "Wi-Fi" or
  "Direct" (awdl0, llw0), else no word (loopback, a VPN, a path that says two
  things). `ClientLink.route` reads this Mac's side of the device's own
  connection, by the witnesses `runsPeerToPeer` uses (so Direct is exactly what
  turning Direct Wireless off disconnects): the address's scope, typed by the
  address itself, else the path's interfaces when they all agree (a connection
  to this Mac's own address lists en0 and lo0: no word). Read when the client is
  ready and on each path update, shown only (`HostStatusSnapshot.Device.route`);
  no wire change. Each end names its own link, so an iPad on Wi-Fi streaming
  from a Mac on Ethernet says "Wi-Fi" while the card says "Wired". A still
  picture's rate reads "120 fps, still", as wide as a one-digit count ("5 of
  120 fps"): "120 fps, nothing changing" (the plan's copy) plus the word
  wrapped the row only while still, and the open menu, which resizes the card
  on every change, jumped a line each time a window stopped or started
  changing. The wording is Noah's call. Over 405 layouts (three sizes, 60 and
  120 fps, 8 to 200 Mbps, each word or none, each suffix, the real StatusCard)
  a row's line count never changes between still and changing unless the
  count's own digits change it (16 layouts, all without a word; with "nothing
  changing" 198 did); the `still-window` preview is the widest case the menu
  offers. Verified: the link check at 89 (PR #6's 40 plus 49;
  `swiftc -package-name sill`), 14 mutants caught; the real host in a scratch
  package (loopback, `fe80::1%lo0` and `::1` clients: no word; with the lo0
  stand-in, Direct on the device rows and on the source row only while one is
  connected); previews: only the five cards with a device, the new
  `still-window` and their menu.txt lines differ from a1484f9; the CLI
  identical to a1484f9 (masked).
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
  so at home nothing takes AWDL. Each row ends in where the device sees its
  Mac (`DiscoveryPolicy.method`; Noah, 2026-09-24, branch
  `connection-method-labels`): "Wired" if the network browser saw it on a wired
  Ethernet interface, else "Wi-Fi" on a Wi-Fi one that is not peer-to-peer,
  "Direct" for a Direct row, else no word; never the Wi-Fi network's name,
  which needs the Access Wi-Fi Information entitlement and Location access,
  and Sill asks for neither. The word follows the browser as interfaces come
  and go (the cable in or out), and the DEBUG console says what it was read
  from ("discovery: <Mac>: Wired, seen on …"). A row that says "Wired" is
  dialled over the cable (Noah, 2026-09-25, branch `prefer-cable`: unpinned,
  with Wi-Fi and the cable both up, the same tap reached the Mac over `%en0`
  at 7 ms one time and over `%en14` at 1 ms another): a tap, an automatic
  reconnect and a move from AWDL resolve its Bonjour service on the first
  wired interface the browser saw it on (`DiscoveryPolicy.dialInterface`;
  anpi0 on the iPad, which the Mac logs as `%anri0`, 1–2 ms; en2 gives
  `%en14`), and a dial not ready within 2.5 s (`wiredWait`), or failing or
  waiting (at once), gives way to the row as listed, unconstrained, once,
  which can take Wi-Fi (DEBUG console: "dialing <Mac> on anpi0 (wired)",
  "wired dial did not connect in 2.5 s; dialing unconstrained";
  `-SillWiredTest HOST:PORT` runs that fallback in the simulator). The route
  is the Settings panel's (branch
  `connection-route-in-settings`): its readout ends in how this session's own
  connection reaches the Mac, "… · 15 Mbps · Wi-Fi", "Wired" or "Direct"
  (`DiscoveryPolicy.route`, `StreamClient.route`): the interface the Mac's
  address is scoped to (the cable and AWDL carry only link-local addresses),
  else the one this device's own address is on (an IPv4 connection's remote
  address has no scope), else the path's interfaces when they all agree, else
  no word (the simulator's path to its own Mac is lo0 alone). Read at
  `.ready`, again at a move's hand-over, and on those path updates of the
  session connection that describe it, satisfied and naming the Mac's IP
  address (`DiscoveryPolicy.describesFlow`, `sessionRoute`); any other update
  keeps the word. A connection to a Bonjour row also gets updates for the
  service's resolution, which name the service instead of an address and list
  "en0 (wifi), en0 (wifi)", the device's default route, whatever link carries
  the connection: on 2026-09-25, on the cable with Wi-Fi on, they turned a
  session's right "Wired" into "Wi-Fi" while its connection stayed on en2 (the
  Mac saw it on `%en14` at 1–3 ms throughout). The DEBUG console prints
  "session: <word>, read from …" and, for each update it skips, "session: kept
  <word>; ignored a path update without an address (for <service>): …".
  "Direct" there replaced the
  header's "Connected directly" line (the footer's warning and the switch's
  hint stay), and a no-break space before each "·" makes a wrap at larger
  text fall after one. The Mac's card names its own side the same way (see
  Sill.app above), so the two can differ (an iPad on Wi-Fi, a Mac on
  Ethernet). Verified: the policy check at 155 (138 plus 17 for the route),
  eight mutants of it caught; photos of the panel cases `default` (Wi-Fi),
  `wired`, `directlink` (Direct), `noroute` and `vdstream` at 1000x710 and
  500x710, and at accessibility-extra-large also at 710x500 (the readout wraps
  after a "·", never truncates, never splits "Wi-Fi"); live against a
  synthetic host: by 127.0.0.1 no word, by this Mac's `fe80::…%en0` "Wi-Fi",
  and `-SillMoveTest to:` from the first to the second gains "Wi-Fi" at the
  hand-over. What each end calls the cable (2026-09-25): iPadOS names its ends
  anpi0 and en2 and types both as wired Ethernet (the connect screen's row
  says "Wired", seen on anpi0, en2 and en0, and a session over it reads the
  Mac's address on en2); macOS names its end en14 (anri0 on other days; both
  up that night), wired Ethernet too (the simulator's browser saw both).
  The fix for the updates above, verified on the iPad: the policy check at 174
  (155 plus 19), 18 mutants caught (the route's 8 plus 10); "session: Wired,
  read from the Mac's address on en2" at `.ready` (a row resolved on en2 and
  tapped by a scratch build, and `-SillConnect` to the Mac's en14 address) and
  at a move's hand-over from awdl0, the host on `%en14` each time; a row's
  unscoped updates after
  `.ready` logged as ignored with the word kept (that session ran over Wi-Fi,
  `%en0` on the host: with Wi-Fi healthy the race took en0 in all three
  unscoped tries, and the night's cable session came right after an eviction
  on Wi-Fi). A session over
  the cable ends when it is pulled and comes back over Wi-Fi, "Wi-Fi" on both
  ends; plugged back in, an established Wi-Fi session stays on Wi-Fi (TCP does
  not move) until the next connection. On
  the device, also compare each word with the host's "Client connected:
  fe80::…%anri0" line (`%anri0` or `%enN`: the cable; `%en0`: this Mac's
  Wi-Fi). Verified on the simulator: the policy check at 138, eight mutants
  caught; the `methods` and `nearby` cases at 1000x710 and 500x710; the rows'
  VoiceOver labels ("Mac Studio, Wired"); the live row for this Mac, "Wi-Fi"
  (lo0 loopback, en0 wifi). Reconnects match the name exactly ("MacBook
  Pro" and "MacBook Pro (2)" are two Macs) and take the network row at once, a
  Direct row only once it has stayed Direct for 6 s and the network last listed
  that Mac 10 s ago or more (`NetworkSightings`): a listener swap makes the
  network row blink for a few seconds, a Mac back on the shared network (Sill
  relaunched, the Mac awake) registers there and on AWDL together and the
  nearby browser can report awdl0 first, and mDNS is lost to radios that leave
  the channel. A tap is never held back. A session over AWDL moves to the
  network once the network browser (it keeps running while connected) has
  listed the same Mac for 2 s without a break: a network connection opens beside
  the direct one, and once its first window list names the same host it takes
  the session over (make before break: the Mac never drops to zero devices, so
  the stream and a staged window stay; the ledger, the Desktop rule and the
  panel's two seconds start afresh as on any connection, and the viewport goes
  out on the new one before the old closes); one that fails or has not shown its
  host in 5 s changes nothing, and the next try waits 10 s
  (`DiscoveryPolicy.moveToNetwork`, `StreamClient.moveToNetworkIfListed`). The
  same host: `WindowList.launchID`, a random ID each host launch puts in every
  window list (optional; hosts without it on both ends go by the name, as
  before), because a Bonjour name can belong to two Macs that share no link;
  a listing found to be another Mac is not tried again while it lasts
  (`sameHost`, `refusedListing`). The hand-over keeps what the device sends in
  order (`SessionLink`): the Mac never orders one connection against another,
  and a release sent on the fast one could overtake its press still in flight
  on AWDL (the button stays down, every later move drags), so the network
  connection is read at once but nothing goes out until a fence ping sent on
  the direct one after everything else comes back (the Mac echoes a ping only
  after reading all before it); messages wait in order meanwhile, one direct
  round trip, at most 3 s, or until the direct connection closes.
  On 2026-09-24 the iPad twice reconnected over AWDL at home (15:37:25,
  15:43:17) after an eviction on en0 and stayed there for minutes at rtt maxima
  ~265 ms. Local Network access denied (the network browser waits with
  PolicyDenied): the status says "To find your Mac, allow Local Network for
  Sill in Settings.", with no hint and no nearby search. The panel's last group
  is the row (never disabled), after the closing footer, with "Direct" ending
  the header's readout while this device's own connection runs over AWDL,
  and then, while the switch shows on, a warning in its footer and hint
  ("turning this off disconnects it"). The connect screen's column is anchored
  leading now, so its title no longer jumps
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
- Fixes after Noah's first sessions (2026-09-24, branch `direct-wireless-fixes`
  from a9cc248; the plan's last section has the log, the causes with line
  numbers and every check). W5 is answered: off never ended a direct session
  (its open awdl0 socket kept AWDL up), and now the host disconnects it; the
  reconnect and the move above keep a Mac on the network off AWDL; Control
  Center's Wi-Fi switch leaves the radio on for AirDrop, so a direct session
  survives it (only Settings › Wi-Fi or another network ends the shared
  route). Verified headless: the CLI identical to 22209db; `ClientLink` 40
  checks, five mutants caught; end to end with a link-local en0 client standing
  in for awdl0 (`SILL_TEST_PEER_TO_PEER_INTERFACE`): disconnected 1.5 s after
  off with one line, the loopback client streaming on, untouched without the
  variable, nobody disconnected by an off-on burst, disconnected also when the
  app's replacement fails; the policy check at 98 (blinks of 1.5, 4 and 7 s
  never take Direct, absent 10 s takes it at 10.0 s, the move at exactly 2 s,
  the café at 6 s, a 15:43 replay), seven mutants caught; on the simulator
  (`-SillMoveTest 1|refused`) the move hands over with the host streaming
  throughout (1 → 2 → 1 clients, no Desktop restart), a panel change after it
  is answered, and a refused network row leaves the session direct. Review
  fixes (the plan's "Review fixes of the move"): the hand-over fenced
  (`SessionLink`), the host checked by launch ID, and a move given up at 5 s
  ends before its connection is cancelled, so a late `.ready` cannot adopt it.
  Verified: the CLI identical again; the fence against a stand-in Mac whose
  first connection lags 120 ms (600 inputs from two threads, in order and
  complete; the old hand-over reordered 64; released by timeout and by the old
  connection closing), five mutants caught; the policy check at 111, five
  mutants caught; on the simulator the move behind a 150 ms delay proxy waits
  301 ms for its fence, then rtt 302 → 1 ms; `other:PORT` (another synthetic
  host) is refused at its first list and not tried again, the session streaming
  on; the panel shows the Mac's state after a move.
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
  "Direct" row; connected, the host logs `%awdl0`, and the panel's readout
  and the iPad's row on the Mac's card both end in "Direct" (the plan still
  says the header's "Connected directly"); note frame age and rtt. W4
  first use (reinstall, café
  conditions): the hint and Search Nearby after 3 s, then "Also looking
  nearby", the Mac as Direct; a relaunch there searches nearby by itself; once
  with Don't Allow on the Local Network alert: the status asks for Local
  Network and no hint shows, and allowing it in Settings brings the list back.
  W5 again (answered from the sessions; now with the fix): connected directly
  (the iPad on the iPhone's hotspot, the Mac at home), off from the Mac or the
  panel gives the "disconnecting … %awdl0" line within ~2 s, the iPad on its
  connect screen, and "Disabling AWDL" about 30 s later. W6 home → café while
  streaming with it on: reconnects directly within ~10 s without a tap (10 s
  since the network last listed the Mac); café → home (rejoin the home Wi-Fi
  while streaming directly): a second "Client connected" on `%en0`, then
  "Client left" for the `%awdl0` one, the picture never stops, the panel's
  readout goes from "Direct" to "Wi-Fi" (the plan: the header loses "Connected
  directly"), and the Mac's card shows the iPad twice for a moment (Direct,
  Wi-Fi), then once, Wi-Fi (drag and type through the move: no button stays
  down, no letters swap); and relaunching Sill.app at home, the iPad
  reconnects over the network (the host logs no `%awdl0`). The blink: at home
  with it on and the iPad streaming, quit and reopen Sill.app a few times, at
  once and after 15 s: the iPad comes back on `%en0` (on `%awdl0` only if the
  network takes over 6 s to list the Mac, and then it moves to `%en0` ~2 s
  after it does). Control Center: connected directly with its Wi-Fi switch
  off, the session goes on; off on the Mac then ends it. W7 relaunch Sill.app
  with it on: `dns-sd -t 3 -includeAWDL -B _sill._tcp local` lists one
  instance on awdl0, no "(2)". W8 the CLI with and without
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
  with pairing. A Mac is known by its Bonjour name for a reconnect, so another
  Mac of the same name running Sill on the device's network would be joined
  (pairing again; the move checks the launch ID, which a reconnect cannot, as
  the host may have relaunched). The host can print "Client left" twice for a
  connection that ends with a reset, as the direct one after a move may.

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
- `HEVCEncoder` feeds VideoToolbox from its own queue behind a one-slot
  mailbox: the capture queue never waits; two frames at a time are inside
  VideoToolbox on the hardware encoder, one on the software encoder (one on
  both until 2026-09-25: "The 33 fps plateau" below); a watchdog on a separate
  queue declares the session hung when the frame inside longest has been there
  1.5 s, and calls `onHung`.
- The coordinator then restarts the source on the software encoder at half
  scale (slow, ~10 fps under load, but live) and says so in the log; three
  software hangs stop the stream instead of looping. Since 2026-09-25 that
  lasts only until a re-check finds the hardware keeping up (below); before,
  it lasted until the host relaunched.
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

**Busy, not stuck (2026-09-24; fixed 2026-09-25, branch `encoder-recovery`
from main at 76366e8).** Sill.app's watchdog fired twice on 2026-09-24 and
both times the host stayed on the software encoder until it relaunched, which
was Noah's poor frame rate (~3 h at 1512×982, 46–55 fps with motion, 6–46 fps
at the end, through 18 settings changes the fallback's caps made useless). The
kernel's AppleAVE2 log (every hardware session's open with its size, bitrate
and firmware "Priority", and a HeartBeat every 5 s listing each session's
frames submitted | completed) shows neither was a wedge:
- 19:00:21 (40 Mbps, the Retina desktop at 60 fps, a 61 s old session): the
  iOS Simulator's screen recorder (SimRenderServer, what `simctl io
  recordVideo` drives: H.264 2064×2752 of the iPad Pro 13" simulator, 38 Mbps,
  priority 80) shared the one encoder engine with Sill and an agent's `SillHost
  --synthetic` (both priority 0). Sill fell to 7–8 fps, then its frame waited
  ~8.6 s; the invalidate blocked 7.06 s, off-thread, and the frame completed
  0.3 s after the other SillHost process died. A fresh 256×256 probe answered
  within 270 ms with the recorder still running, while the next stream-size
  sessions stalled again (0.3–9.5 s).
- 23:30:04 (150 Mbps, a 36 s old session, running 57–58 fps alone): the
  recorder opened a session at 23:29:45.2 and Sill fell from 58 to 22 fps in
  that second, then ran 13–45 fps; a frame waited ~1.8 s and completed (the
  invalidate took 0.17 s). A near miss at 23:27:54 (57 → 2–34 fps) came from
  the same recorder. The render and the benchmarks named at the time ran later.
- 424 hardware HEVC sessions from 17:40 to 02:30: 47 overlapped a recorder
  session and 7 of those stalled (median 39 fps); the other 377 had no stall
  (median 60), including a priority-0 H.264 2064×2752 benchmark beside HEVC
  3024×1968 at 40–150 Mbps (both 28–46 fps, a fair share). Ruled out: the
  bitrate (hang 1 was at 40 Mbps), 120 fps (both at 60), session churn (22
  bitrate restarts ran clean) and invalidating with a frame inside (both
  frames completed). No "Frame POC timed out" line, the 2026-09-22 signature,
  anywhere in the period (the log store no longer has 09-22's AppleAVE2 lines).
- Priorities, measured with one 256×256 frame per configuration: real-time
  HEVC and H.264 0, not real-time 0, `EnableLowLatencyRateControl` 60 (RCMode
  20), the recorder 80. No public key sets it. One engine on this M2 Pro:
  unthrottled HEVC 3024×1968 runs ~105–115 fps (~650 MP/s), so the Retina
  desktop at 60 fps takes 55–65 % of it and any other encode costs Sill frames
  without a hang (a 3024×1904 test beside Noah's 1512×982 desktop: both at
  57–60 fps for ~4 s, then both at ~50, 2026-09-25). A Retina desktop at 120 fps
  (~713 MP/s) exceeds it alone (untested).
- A bitrate change still needs a new session (measured 2026-09-25, 1512×948 at
  60 fps, blocky noise): VideoToolbox takes AverageBitRate and DataRateLimits
  on a live session and reads them back, but the hardware HEVC rate control
  does not follow: raised 8 → 40 Mbps the output stayed at 9.6 Mbps for 5 s,
  across an IDR and a forced keyframe (a session made at 40: 28 Mbps); lowered
  40 → 8 it dropped 41 of the next 60 frames. Hardware H.264 the same. The
  software encoder follows (7.9 → 19.5 Mbps in 2 s) and so does low-latency
  rate control (8 → 38 Mbps within 1 s). `restartNeeded` keeps the bitrate.
- `VTCompressionSessionInvalidate` waits for a frame still inside (17 ms for a
  3024×1898 frame in flight, whose output handler runs first).

What the host does now:
- The fallback is temporary. `enterSoftwareFallback` (a hardware hang, or the
  launch probe) says "… (busy or stuck); switching to the software encoder at
  half scale until the hardware keeps up again (next check in 30 s)." While a
  device is connected (an idle host opens no session; the task ends with the
  last device) `recheckLoop` tests the hardware at the size the stream would
  have on it (the running one's at full scale, else the Desktop's):
  `EncoderProbe.throughput` sends a moving pattern through a quiet session (no
  line, no counter: the stats line's `enc.out` is the menu's fps), as many
  frames inside at once as a stream keeps (one at a time until 2026-09-25, two
  since: "The 33 fps plateau" below), on a user-initiated GCD thread, and
  measures the rate the last 7 of 10 frames come back at; its 3 frames are
  drawn before the session opens and reused, and the first pass over them is
  left out (one at a time: ~110 ms at 3024×1904 when the engine is free, ~120
  fps; ~290 ms at 6016×3384, ~39 fps). At the rate a return needs or more
  (`EncoderProbe.returnBar`: 0.75 of the stream's rate, 60 at most, the
  software encoder's cap, so 45 fps; but never more than 0.75 of what the
  engine does alone at the test's size, from the best pixel rate any test
  measured this run, 400 MP/s until one has) `hardwareIsBack` waits out a
  switch, clears the flag and restarts a running stream on the hardware, like
  a settings change (no focus change): "Hardware encoder is back (121 fps at
  3024×1896 in a test, 45 needed); restarting the stream on it." (or "the
  next stream uses it"). Slower: "Hardware encoder answers but is busy (8 fps
  at 3024×1896 in a test, under the 45 fps a return needs; another app is
  using it); next check in 60 s". No frame in 1 s: "Hardware encoder still
  not answering after N ms; next check in 60 s". Either doubles the interval,
  up to 300 s; so does a hang within 5 min of a return; a return that lasted
  10 min resets it to 30 s. The first device after none gets a check at once
  when the last is 30 s old, so its stream starts on the hardware (a software
  start ~20 ms before is replaced). A hang reported by an encoder no newer
  than the last return (`HEVCEncoder.serial`) is stale and ignored. One loop
  and one test at a time: `stopRecheck` only cancels, and the task clears
  `recheckTask` once its loop has ended, so a device that connects during a
  test gets no second loop beside it (the ending task's tail starts one); a
  test that ends with no device left is dropped without a line or a backoff.
- Why a rate at the stream's size and not one small frame: at 03:26 on
  2026-09-25, with another agent's Simulator recording (priority 80) and a
  second SillHost on the engine, a 256×256 frame answered in 72 ms, the
  stream went back to the hardware and ran at 12 fps there (it had run at ~57
  on the software encoder), and no watchdog fires for a slow stream. Noah's
  own Sill.app sat at 8–18 fps in the same minutes, and at 03:32:02 it fell
  back once more (16, then 2 fps, then the watchdog), which the old build
  keeps until it relaunches.
- Why the bar follows the size (review, 2026-09-25): a fixed 45 fps asked more
  than a free engine gives a large frame. Measured with the engine free (Noah's
  Sill.app on the software encoder), as the probe was (frames drawn inside the
  timing, utility QoS) and as it is: 6016×3384, a Retina 6K Desktop, 37 and
  39 fps; 5120×2880 50 and 53; 3024×1904 115 and 121. So a host streaming a 6K
  Desktop read "busy" at every check and stayed on the software encoder for
  good. Now the first check there needs 15 fps (400 MP/s assumed) and, learned
  from its test, the next 29; a starved session got a sixth of the free rate
  or less, so busy still reads busy.
- The session given up on reports on its way out: "Encoder (hardware HEVC
  3024×1898): the stalled frame came back after 3.0 s; the encoder was busy,
  not stuck." A stuck one never lets go, so it never prints.
- Probes whose frame never comes back each hold a blocked thread; with 8 out
  (`maxStuckProbes`, after 22–28 min of failed checks) the re-check stops
  probing and says once that the encoder is stuck and a restart of the Mac
  fixes it, and the menu shows "Hardware Encoder Stuck". A late frame counts
  out again (`EncoderProbe.onStalledProbeBack`): under 8, the host says "a
  check's frame came back after N s, so it is not stuck; checks resume",
  clears the menu's line at once (a device connected or not) and, with a
  device connected, checks at once instead of when the held-back loop wakes
  (300 s).
- Copy: the menu's "Hardware Encoder Busy — Streaming with the software
  encoder, up to 60 fps, until it is free again." (one line, 373 pt: a menu
  item's subtitle does not wrap, the old one was 422 pt) or "Hardware Encoder
  Stuck — … Restarting the Mac fixes this."; the Streaming pane says the same
  at length; `HostSettingsState.softwareEncoder`'s doc. The device's callout
  says "‹Mac›’s hardware encoder is busy or not responding, so for now streams
  run at up to 60 fps at Standard." (it said "until the Mac restarts"; it
  promises neither now, as hosts before this change keep the fallback until
  they relaunch), and goes away by itself when the host clears the flag.
- Test hooks, read once and inert without them: `SILL_TEST_ENCODER_HANG=N`
  (the first N hardware stream sessions hold frame 90 for 3 s before it goes
  in: a busy engine; it prints a "TEST:" line), `SILL_TEST_PROBE_HOLD=S` (every
  frame of every probe waits S s: 0.08 a starved engine, 2 a busy one, a huge
  S a stuck one), `SILL_TEST_RECHECK_SECONDS=N` (intervals N to 10 N instead
  of 30 to 300) and `SILL_TEST_PROBE_SIZE=WxH` (the re-check tests that size,
  as for a Retina 5K or 6K Desktop on a smaller screen).
- Diagnosis: `/usr/bin/log show --start '2026-09-24 18:55' --end '2026-09-24
  19:05' --style compact --predicate 'sender == "AppleAVE2" AND (eventMessage
  CONTAINS "HeartBeat" OR eventMessage CONTAINS "Resolution:" OR eventMessage
  CONTAINS "AVE : open" OR eventMessage CONTAINS "AVE : close")'` (a session
  whose completed count stops while its submitted one is ahead is starved;
  "Priority: 80" beside it is the recorder), plus `process ==
  "VTEncoderXPCService" AND eventMessage CONTAINS "videoencoder.peer"` to map
  sessions (the next "AVE : open") to client PIDs.
- Operational rule, from the same logs: while Noah streams, agents do not run
  `simctl io recordVideo`, SillHost streams, ReelRenderer or encoder benchmarks;
  each shares the one engine, and the recorder outranks Sill.
- Not in this change: `EnableLowLatencyRateControl` would put Sill at priority
  60 (above every default session, still below the recorder's 80) and follows
  live bitrate changes, but it changes the bitstream and rate control (frames
  dropped at 8 Mbps in the rate test): a flagged experiment with iPad tests.
Verified headless (the synthetic host; hardware runs kept to seconds, Noah's
Sill.app streaming beside them): clean build (only the old CaptureProbe
warning); the CLI against 76366e8 built from `git archive`, masked and
sorted: idle identical, and with a client and a bitrate change identical but
for `enc.mailboxDrop` counts, which follow the other encoder users of the
moment (either build had them); `SILL_TEST_ENCODER_HANG=1` with a client: the
hang at 1.5 s, the fallback, 1512×948, "came back after 3.0 s", back 30.0 s
later (114 fps in the test) and 3024×1898 on the hardware at 60 fps for 67 s,
the client getting frames every second but the hang's; `=2`, while another
agent's Simulator recording and SillHost came and went: the check at 30 s
"busy (25 fps …); next check in 60 s", back 60 s later at 114 fps, the
second hang 3 s after the return and "next check in 120 s"; with
`SILL_TEST_PROBE_HOLD=0.08` while the recorder and another SillHost really
shared the engine (the test's own hardware stream ran at 16 fps): "busy
(7 fps …)" at 30 s and "(8 fps …)" 60 s later, no return; the client leaving
during a fallback: no session from the host in the kernel log for 40–45 s
(the next check was due after 30), then a client again: the test at the
Desktop's size (112 fps) and back ~100 ms after its stream started on the
software encoder; `SILL_TEST_PROBE_HOLD=100000 SILL_TEST_RECHECK_SECONDS=1`
with a client picking nothing: the launch fallback, then checks 1, 2, 4, 8,
10, 10 and 10 s apart, all unanswered, and the stuck line after the 8th
unanswered probe (the launch one and 7 checks); `SILL_TEST_PROBE_HOLD=2`:
unanswered probes, each back 2 s later, never stuck; previews against
76366e8: only menu.txt (the copy and a new `software-encoder-stuck` sample,
its cards equal to the busy one's) and the General pane's "Running from" path
differ.
Review fixes (2026-09-25), verified headless: the host builds with no warning,
iOS Debug with only the old `StreamClient` one; `returnBar` checked on its own
(swiftc, 100,011 checks: 45 at Retina laptop sizes, also at 120 fps, 15 and 29
at 6K, a free engine always passes, always the lower of the two shares), four
mutants caught (the fixed 45, the engine term without its share, no 60 fps
cap, an assumed rate above this engine); the CLI against 76366e8 (`git
archive`), masked and sorted: idle identical, with a client and a bitrate
change identical (a first pair differed by one `enc.mailboxDrop` in the
base's first second); `SILL_TEST_ENCODER_HANG=1`: back 30.1 s after the
fallback ("121 fps at 3024×1896 in a test, 45 needed"), the client getting
frames every second but the hang's (40–57 fps on the software encoder, 60 on
the hardware); `=2` with `SILL_TEST_PROBE_SIZE=6016x3384
SILL_TEST_RECHECK_SECONDS=5`: "39 fps at 6016×3384 in a test, 15 needed", the
second hang and "next check in 10 s", then "39 fps …, 29 needed"; the
verifier's overlap run (`SILL_TEST_PROBE_HOLD=1000
SILL_TEST_RECHECK_SECONDS=4`, a device leaving during a test and another
arriving): one line, "next check in 8 s" (it was two, 8 then 16 s), none when
nobody comes back, and the second device's own check 8 s later;
`SILL_TEST_PROBE_HOLD=70 SILL_TEST_RECHECK_SECONDS=1`: the stuck line at
65.0 s, the launch probe's frame back at 70.2 s, "a check's frame came back
after 70.0 s, so it is not stuck; checks resume" and a check at once; with
the device gone by then, the same line at 70.2 s and the next device checked
the moment it connected.
- **Untested, for Noah:** a build of this branch in /Applications
  (`Scripts/make-app.sh --install --open` after the merge; only a new build
  comes back by itself). Then, with the iPad streaming the Desktop, `xcrun
  simctl io booted recordVideo /tmp/x.mov` on a booted iPad Pro 13"
  simulator: the frame rate drops, and within a minute or so "switching to the
  software encoder" and "the stalled frame came back" (the menu: "Hardware
  Encoder Busy"); while it records, "answers but is busy" at each check, 30,
  60, 120 s apart; stop the recording (Ctrl-C) and at the next check "Hardware
  encoder is back" and the full resolution on the iPad. Also a window stream
  and the virtual display through a return, and a 120 fps stream (the test
  asks for 45 fps at its size). On a Mac with a Retina 5K or 6K display, a
  return while the Desktop streams ("… in a test, N needed", N under 45 at
  6K).

**The 33 fps plateau (2026-09-25, branch `encoder-two-in-flight` from
`encoder-recovery` at 4fe37d4).** A Retina Desktop stream (3024×1964, hardware
encoder) sat at 30–36 fps in a third of the logged seconds of Noah's home
streams at 40 Mbps (7,445 of 22,081 seconds with 50 or more frames captured and
none idle), and nearly always over Tailscale at 4 and 15 Mbps; every such
second read like `cap.complete 56 enc.mailboxDrop 24 enc.out 33 net.sent 33`.
An investigation and a verifier (read-only: Sill.log and the kernel's AppleAVE2
log) found:
- The network held nothing back (`net.dropped` 0, `net.sent` = `enc.out`);
  nothing after the encoder waits. The whole loss was the mailbox.
- The hardware encoder falls into a slow state, often after a few seconds of
  fewer frames (a mostly still screen; once while scrolling at 38 fps) and at
  any bitrate (4, 15, 40 and 150 Mbps): a frame takes 29–30 ms from submit to
  output, and the HeartBeat's time per frame (C/F) reads 15 ms, against 9 ms
  at 57 fps (and 15 ms while frames are sparse). Sessions started fast (7.5–9
  ms a frame in their first windows, one at 12.3); 1512×982 never plateaued
  (6 ms a frame). With one frame inside VideoToolbox, the output rate was one
  over the turnaround: 33 fps.
- It stays slow: the first counter grows by ~460 a second in both states, so
  with one frame inside the encoder never sees more work than it is doing
  (inferred, like the reason it slows).
- The HeartBeat needs `--predicate 'sender == "AppleAVE2"'` with `--info
  --debug`; `eventMessage CONTAINS "AppleAVE2"` returns only firmware lines.
  Per session and 5 s window it gives frames submitted | completed and three
  cumulative counters (per-frame time: counter delta over frames).
- 33 = 1000/30 matching the 30 ms tick timer is a coincidence (`net.tick` 33
  beside `enc.out` 55 on the cable).

The change: two frames inside the hardware encoder at once. A frame goes in
while fewer than two are inside, else waits in the one-slot mailbox (the newer
frame wins, `enc.mailboxDrop` as before), and a frame coming back lets the
waiting one in. The software encoder keeps one (it is bound by the CPU, and a
second frame would wait a whole encode inside). The bookkeeping moved out of
`HEVCEncoder` into `EncoderMailbox` (pure: the frames inside by id with the
time each went in, the mailbox, `dead`, the timestamp fix and the keyframe
flag), kept under the encoder's lock; `submit` stays serial on `encodeQueue`,
so timestamps only go forward and a keyframe request goes with the next frame
handed over; VideoToolbox returns outputs in decode order. The watchdog fires
on the frame inside longest: `SILL_TEST_ENCODER_HANG`'s frame 90 is still
timed from when it went in, and the frame let in behind it never goes in. A
session given up on reports the oldest frame's wait ("the stalled frame came
back after N s"), and `abandon` is true while any frame is inside. The
re-check's test keeps two inside too, as a stream does, so the return bar
holds the rate a stream would get (one at a time measured the turnaround;
`SILL_TEST_PROBE_HOLD`'s hold is still serial, 0.08 still ~12 fps). The
capture's queue depth stays 5: the encoder holds up to three surfaces (two
inside, one waiting; its last frame is one of them), which leaves two for
ScreenCaptureKit, the margin its default depth of 3 leaves an app holding one,
and a wedge's two last only until the watchdog and the restart. No new Stats
key or line. While the encoder keeps up (9 ms a frame against 16.7 between
frames at 60 fps) a frame seldom finds another inside and nothing changes; the
cost is at most one frame waiting inside VideoToolbox instead of in the
mailbox. Commits: 63a365b (the bookkeeping moved, still one inside), ec93e09
(two inside), 47f0cc1 (the test).

Verified without the hardware encoder (a device was connected to Noah's
Sill.app all session: the operational rule above): clean builds at each commit
(only the old CaptureProbe warning); the encoder-free check, the real
`EncoderMailbox.swift` compiled with a stand-in for VideoToolbox that returns
frames after programmable delays, in any order, in virtual time, driven at 60
fps through a copy of HEVCEncoder's glue (scratchpad
`two-in-flight/mailboxcheck/`: `swiftc -O EncoderMailbox.swift main.swift -o
check && ./check`, 63,778 checks, and `python3 mutants.py`):
- 30 ms a frame: 60.0 fps, no drops, latency 30 ms with two inside; 33.3 fps,
  26.7 drops a second, latency median 36.7 ms with one (the old pipeline, which
  63a365b still has: its run reads the same). 9 ms: 60 either way. 40 ms: 50
  fps, 10 drops.
- Returns out of order (4–45 ms), refusals, a duplicate notice after some,
  rate-control drops and keyframe requests: every frame settles exactly once,
  the frames the mailbox counts inside are exactly those on the queue or in
  the stand-in, never more than the limit, timestamps strictly increasing.
- A frame stuck for good fires the watchdog within 1.5–2.0 s of going in,
  whether the other place keeps flowing or everything waits behind it in
  decode order; nothing is forwarded, handed over or let in after; the
  teardown is stalled since that frame. `SILL_TEST_ENCODER_HANG` the same, on
  both encoders. An encode call that blocks the queue after its frame came
  back: the frames let in behind it are timed from when they were let in, and
  their clock starts again at the hand-over. No false alarm at 1.2 s a frame,
  at 1.4 s behind one engine doing 0.7 s a frame, or with frames 2 s apart.
- `abandon` with two inside and with none; a live teardown with two inside
  drains; keyframes: each request's flag goes with the first frame handed over
  after it, and a re-encode stamped behind a frame let in before it is fixed.
- 17 mutants, all caught: limit 1, the watchdog on the newest frame, the
  waiting frame going in without a place (a decrement on the pending path), a
  frame back left inside (the set not cleared), no duplicate guard, late
  output forwarded, the older waiting frame kept, a dead session drained, no
  timestamp fix, the keyframe flag never cleared, a hand-over or admission
  after death, the watchdog at 3 s, the waiting frame kept at death or never
  taken, no clock restart at the hand-over, a new frame's clock taken from an
  older one.
- The throughput test's loop, the real `EncoderProbe.swift` and `Stats.swift`
  against a stand-in `HEVCEncoder` whose frames come back in real time and in
  decode order (scratchpad `two-in-flight/probecheck/`, 18 checks and a
  `SILL_TEST_PROBE_HOLD=0.08` run): at 30 ms a frame, each on its own, 68 fps
  with two inside where 4fe37d4's test reads 30; one engine at 30 ms a frame,
  33 either way; never more frames inside than the encoder lets in, nor a
  surface inside twice; a frame that never comes back: no answer after ~1.03
  s, counted stuck, never reported back; one 1.5 s late: reported back once
  after ~1.5 s and the count back down; the hold still reads 12 fps.
- What the change assumes, from the same stand-in: with 15 ms on the chip and
  the rest overlapping, two inside give 60 fps at a 30 ms turnaround; if the
  encoder did the whole 30 ms one frame at a time, two inside would still give
  33 fps and add ~30 ms (latency median 66.7 against 36.7 ms). The HeartBeat
  cannot tell which, and Sill's frame age starts after the encoder.
- **Untested, for Noah (the hardware encoder; only with no device
  connected):** the scratchpad's `two-in-flight/verify-hardware.sh`: the CLI's
  idle stdout against 4fe37d4 (masked and sorted), SillHost `--synthetic` with
  a test client (enc.out, mailboxDrop, HeartBeat), the real HEVCEncoder of
  each build at 3024×1964 and 40 Mbps (3 s at 60 fps, 6 s of a frame every 0.3
  s to provoke the slow state, 20 s at 60 fps; per second enc.out,
  mailboxDrop, capture-to-output latency, the HeartBeat's C/F), and each
  build's throughput test. Expected with one inside once slow: ~33 fps, ~24
  drops, C/F ~15; with two: ~57–60 and latency no higher. If two still read
  ~33, or the latency rises, revert ec93e09 and 47f0cc1 (63a365b alone
  changes nothing); the next thing to try is
  `EnableLowLatencyRateControl`. Then the iPad on the Retina Desktop at 40
  Mbps: a still screen for 10 s, then scrolling; the menu's encoded fps should
  stay near 57 where it read 33. Resolution: Standard avoids the plateau
  meanwhile (57 fps with no drops at 1512×982).

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
  (`WindowList`, with the host's per-launch `launchID`; `WindowInfo`,
  `AppInfo`, `StreamSource`) and image blob framing.
  `HostSettings.swift` — the host settings a device sees and changes (kinds 16
  and 17): `StreamSettings`, `RunningStream`, `HostSettingsState`,
  `HostSettingsChange`, `SettingsChoices` (the Mac menu's values) and
  `QualityPreset`.
- `Sources/SillHost/` — the `SillHostCore` library. `StreamCoordinator` (main
  actor; owns the pipeline, switches sources on client request, raises the
  picked window in regular mode (never on the virtual display), applies
  viewports, falls back to the software encoder on a hang and re-checks the
  hardware until it can go back (`recheckLoop`), stops capture when
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
  `--synthetic`), `HEVCEncoder` (VideoToolbox with two frames inside on the
  hardware, one on the software encoder, a one-slot mailbox behind them and a
  hang watchdog; says whether a stalled frame came back), `EncoderMailbox`
  (its bookkeeping: the frames inside with the time each went in, the
  mailbox, the watchdog's test, timestamps and keyframe requests; pure,
  checked with swiftc), `EncoderProbe` (one small frame through a hardware
  session at launch; for the re-check a short quiet run at the stream's size
  with two frames inside, the rate it keeps and the rate a return needs),
  `EncoderSelfTest`
  (`--encoder-selftest`), `CursorShapeWatcher` (NSCursor.currentSystem →
  `.cursorShape`), `StreamServer` (Network.framework + Bonjour `_sill._tcp`, both
  directions, keepalive, dead-client eviction, ping echo, client-stats print;
  the listener built with or without peer-to-peer and replaced live when Direct
  Wireless changes, and turned off, the devices on peer-to-peer Wi-Fi
  disconnected; the test-only SILL_TEST_SERVICE_TYPE, SILL_TEST_SWAP_FAIL and
  SILL_TEST_PEER_TO_PEER_INTERFACE), `ClientLink` (which route a client came
  by, from its endpoint's scope, and the menu card's word for it: Wired, Wi-Fi,
  Direct or none; pure, checked on its own with `swiftc -package-name sill`,
  which its `package` access needs),
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
  heartbeat when idle).
- `Sources/SillHostCLI/main.swift` — the CLI: flags, `dispatchMain` vs
  `NSApplication.run`, the Terminal permission hint.
- `Sources/SillMenuBar/` — the app: `main.swift` (AppKit lifecycle, accessory
  policy), `AppDelegate` (launch order, Quit, the modal-loop rule), `AppModel`
  (owns the coordinator, presentation, App Nap guard, onboarding),
  `HostSettings` (UserDefaults; the presets are StreamProtocol's
  `QualityPreset`), `StatusItemController` (+ `MenuBuilder`), `StatusText`
  (all status copy), `StatusCard`, `StatusGlyph`, `SettingsWindow` +
  `SettingsPanes`, `Permissions`, `LoginItem`, `LogWindow`, `MainMenu` (key
  equivalents), `DebugHooks`, `AppLog` (its print shadow).
- `Packaging/` — Sill.app's `Info.plist` and the development entitlements
  (get-task-allow only). `Scripts/make-app.sh` builds, iconizes, signs and
  installs the bundle; `Scripts/sillclient.py` is the wire-format test client
  (timed `--set=K=V[,K=V]@T` kind 17 changes with tokens 1, 2, 3…,
  `--raw17=JSON@T`, `--pick=none|desktop|window:ID@T`, `--stats`,
  `--expect=K=V[,…]` against the last kind 16, which it prints one per line;
  every argument is checked before it connects, and a bad one exits 2).
- `Sources/VirtualDisplayProbe/` — CLI experiment for milestone 3; run it from
  Terminal (needs Screen Recording + Accessibility): `.build/release/VirtualDisplayProbe "Activity Monitor" --seconds 20`.
- `iOSClient/` — `Sill.xcodeproj` and its sources: `StreamClient` (Bonjour: a
  network browser and, when `DiscoveryPolicy` says, a nearby peer-to-peer one;
  `FoundMac` rows; connection, parsing, reconnect, the move of a session over
  AWDL to the network, ping, generic `send`), `SessionLink` (the session's
  connection and the one door out to the Mac; the move's fenced hand-over;
  Foundation and Network only, checked with swiftc),
  `DiscoveryPolicy` (when to look nearby, the rows and the word each ends in,
  the session's route word for the Settings panel,
  when a reconnect may take a Direct row, when a session over AWDL moves to
  the network, the memory of Macs with Direct Wireless on; pure, checked with
  swiftc), `StreamScreen`
  (landscape: top bar, thumbnails, drawer, Aa, Keyboard, Desktop; layout
  selection by size incl. Duo outer display), `PortraitStreamScreen` (laptop
  layout: stream, compact bar, key rows, trackpad), `InputOverlay` (direct touch,
  Pencil, keyboard, scroll momentum), `TrackpadView`, `HEVCDisplayView` (shared
  display view + DEBUG HUD), `DiagnosticsHUD` (client stats reporter),
  `StreamClient+Viewport`, `ContentView` (connect screen with rows ending in
  Wired, Wi-Fi or Direct, the hint and Search Nearby, + DEBUG harness),
  `MockCatalog` (harness data and the settings cases), `HostSettingsLedger`
  (the Mac's settings with this device's unanswered picks; pure logic, checked
  with swiftc), `HostSettingsPanel` (the Settings panel). New files need their
  four pbxproj entries by hand. Swift 5 language mode.
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
bind fail; `SILL_TEST_PEER_TO_PEER_INTERFACE=en0` counts a client scoped to that
interface as one on peer-to-peer Wi-Fi, so a test client on the Mac's own en0
link-local address (`ifconfig en0`, `fe80::…%en0`; Python's socket takes it)
stands in for a device on awdl0 when Direct Wireless turns off (a local
connection to the Mac's own awdl0 address never became ready, so awdl0 cannot
be tested headless); all three are honoured only by a host that does not
advertise. `dns-sd -t 3 -includeAWDL -B _silltest._tcp local` lists a
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
Debug harness (simulator, no Duo simulator exists yet): launch arguments
`-SillLayout 1000x710` (inner landscape) / `710x1000` / `500x710` / `710x500`
(outer), `-SillLive 1` (real client inside the frame), `-SillDrawer 1`,
`-SillActive none|desktop|<windowID>` (mock), `-SillHUD 1` (diagnostics overlay),
`-SillSettings 1` (the Settings panel open), `-SillSettingsCase
default|cli|software|custom|vdproblem|vdstream|legacy|pending|timeout|direct|
directlink|nodirect|wired|noroute` (the mock Mac's settings; it answers a pick
after 0.35 s; the readout's route is Wi-Fi except `directlink` Direct, `wired`
Wired and `noroute` none),
`-SillConnectCase looking|hint|nearby|methods|denied` (the connect screen in a discovery
state; `methods` has a row ending in each word, none, and long names; the mock never
browses), `-Sill.directWirelessMacs '("Mac mini")'` (seeds the
device's memory of Macs with Direct Wireless on for one run; `'()'` empties it),
`-SillConnect 127.0.0.1:PORT`
(connect by address, also in the normal app: the only way to reach the
off-Bonjour synthetic hosts from the simulator), `-SillMoveTest 1|refused|to:HOST:PORT`
(with `-SillConnect`: that session counts as direct and a second later the same
address, or its port 1, or HOST:PORT, is listed as the Mac's network row, so the
move to the network runs against a synthetic host; `to:` this Mac's
`fe80::…%en0` address from `127.0.0.1` shows the panel's route word change at
the hand-over; the console's "discovery: …" and "session: …" lines,
`xcrun simctl launch --console-pty`, say what happened). A fake screen wider than the
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
