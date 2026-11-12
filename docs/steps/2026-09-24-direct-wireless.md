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
  updated Sill.app), accepted from a device on every host (since 2026-10-29 only
  from a paired session at home: the Current step's "Direct Wireless only from a
  paired device"), and absent from `restartNeeded`: it is the listener's.
  `StreamServer` builds the listener
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
  on Wi-Fi). Until branch
  `follow-best-path` a session over the cable ended when it was pulled and came
  back over Wi-Fi, "Wi-Fi" on both ends, and plugged back in, an established
  Wi-Fi session stayed on Wi-Fi (TCP does not move) until the next connection;
  now it follows the cable (the step above). On
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
  plan's "a device sets stream quality, never network exposure": revisited
  with pairing on 2026-10-29 (the security scan's finding 8, PR #253): a
  device sets it only from a session whose key is on the Mac's trust list,
  never unpaired at an open door, at the CLI's plain door or from away. A Mac
  is known by its Bonjour name for a reconnect, so another
  Mac of the same name running Sill on the device's network would be joined
  (pairing again; the move checks the launch ID, which a reconnect cannot, as
  the host may have relaunched). The host can print "Client left" twice for a
  connection that ends with a reset, as the direct one after a move may.
