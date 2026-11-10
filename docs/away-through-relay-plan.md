# Away from home through a relay on the Mac: the plan

2026-11-09. Branch `away-through-relay` (worktree `/Users/noah/Downloads/wt-326`, PR #339) from origin/main at
f224323; line numbers are at f224323. Issue #326 (Ti800, Sill 0.6.0 (1276) on macOS 27.3 and an iPhone):
"Away from home quality isn't used when a remote connection reaches Sill via loopback (userspace VPN,
tunnels, proxies)". Host only: no wire change, nothing on the device, nothing stored.

## The problem, read from the code

The Mac decides who is away from where a connection came in, and a relay on the Mac hides that.

- `AwayPolicy.isAway` (AwayPolicy.swift:14-15): away is the remote door from a VPN or the internet
  (`origin == .vpn || origin == .internet`). The remote door from this Mac's own networks or
  loopback ("by address") is at home: "a device dialling the Mac's LAN address through the remote
  door is in the house" (docs/remote-bundle-plan.md §5.1).
- `OriginPolicy.classify` (OriginPolicy.swift:62) makes 127/8 and ::1 `.loopback` before anything
  else, and a source that is one of this Mac's own addresses `.lan` (its own on-link prefix);
  `label` (:114) calls both "by address". The remote door takes its origin from `StreamServer.arrival`
  (StreamServer.swift:603-606) and builds the route with it (Door.swift:330, 350-351).
- A relay on the Mac ends the device's path there and opens a new connection to port 7455 from the
  Mac itself: a userspace Tailscale or WireGuard node (no `utun` with the tailnet address: the node
  lives in a process and forwards locally), a proxy or VPN app that runs such a node in-process, an
  SSH tunnel (`ssh -L`, `ssh -R`), `socat`, a reverse proxy, a Cloudflare Tunnel connector. The door
  sees 127.0.0.1, or the Mac's own LAN address when the relay forwards to that.
- So the reporter's iPhone on cellular, through a userspace tailnet node, was "Remote client
  connected: iPhone (iPhone18,3) by address (127.0.0.1:54211)", at home, and streamed the home
  quality (Balanced, Retina) where it should have had Low at Standard: round trips of 2 to 4 s, then
  a drop and a reconnect.
- What else reads the origin of a remote route: the remote door's admission (`remoteAdmits`, the
  internet switch's cut, `afterGate`, `stillServes`), all of which take loopback and this network
  alike; the firewall's re-ask (`FirewallRule.asksAgain(fromLoopback:)`, StreamCoordinator.swift:526);
  the Mac's card and the Devices pane's "last connected" (the label). Nothing else: `ClientRoute.isAway`
  (StreamCoordinator.swift:3481) feeds the quality alone (`routesChanged`, :922, at registration
  before the catalog; a device's Quality pick, :1332). Exposure rules go by the door, never by away
  (`DeviceSettings.accepted(fromRemote:)`, Direct Wireless never from the remote door).

## The fixes weighed

**(a) The host alone.** At the remote door, a connection whose source is this Mac itself, loopback
or one of the Mac's own addresses, can only be a relay on the Mac or a client running on it (the
Simulator, a test client). Name it: a new origin, `relay`, away as a VPN is, labelled "through a
relay on this Mac". It works with the device app people have today, the reporter's 0.6.0 included.

**(b) The device says.** An optional field in the hello (kind 23) saying how the device dialled,
and the Mac counts a device that dialled remotely as away, either only when the source address tells
it nothing (the source is this Mac) or always.

**(c) Both.**

What the code says about (b):
- How a device dialled is already known to the Mac: the remote door is dialled only by the device's
  remote path (`dialSaved`, its saved addresses on the remote port, StreamClient+Remote.swift:401-482),
  never by a Bonjour row, and the move home goes to the home door. "Dialled remotely" is "came in at
  the remote door". What a relay hides is the device's path, not how it dialled: the device knows
  that path (`remoteWinner`, :496: through a tunnel of its own, "through Tailscale", or to an
  internet or LAN address), the Mac does not.
- "Only when the address tells nothing" covers exactly the connections (a) names, and only from
  devices updated to send the field: (a) gives the same answer to every device now.
- "Always" would make the remote door from this network away too: Connect Remotely at home by the
  Mac's LAN address, or a device whose Bonjour row was late, would stream the away quality in the
  house, against §5.1.
- With the device floor at "0" (every build so far) the gate reads no hello before registration
  (StreamServer.swift:1146-1147), so the hello arrives after `routesChanged` decided: the Mac would
  decide a second time, its catalog and first kind 16 sent at the first answer.
- A device's word can be trusted only one way: toward away. Away goes to the away pair only while
  every connected device is away, so a false "away" changes nothing while another device is at home,
  and alone it lowers the liar's own quality (or sets the pair its own Quality pick sets anyway: a
  paired device already sets either pair with kind 17). A false "home" from a device away would
  give every device away the home quality, so the field could never move a device toward home.
- What (b) would add over (a): the device's own route word on the Mac's card ("through Tailscale"
  rather than "through a relay on this Mac"), and relays that are not on this Mac (a router whose
  port forward rewrites the source, a reverse proxy on another computer), which show this network's
  address and stay at home under (a). Neither is #326's case.

**Taken: (a).** The smallest sound one: host only, one origin and one line of the away rule, no wire
change, every device at once. (b) and (c) are open questions 1 and 2.

## The design

### The rule (OriginPolicy, pure)

- `Origin.relay`: the remote door only.
- `isThisMac(_:interfaces:)`: loopback, or one of the Mac's own addresses (`Interfaces.owner`, the
  same table `classify` reads; a link-local source compared without the kernel's embedded scope, an
  IPv4-mapped one as its IPv4 address).
- `atRemoteDoor(_:remote:interfaces:)`: `classify`'s origin, but `loopback` is `relay`, and `lan`
  from one of the Mac's own addresses is `relay`. `vpn` stays `vpn` whoever sent it (a relay that
  forwards to the Mac's own Tailscale address arrives on `utun` and is away already, named by its
  service); `internet` and `direct` never come from the Mac itself.
- `remoteAdmits(.relay)`: true, internet access on or off, as loopback was. `homeAdmits(.relay)`:
  false; the home door never names a relay (loopback there is a client on this Mac, at home), so
  nothing reaches it, and were it to, a relay can carry anyone.
- `label(.relay)`: "through a relay on this Mac".

### Where it applies

- `StreamServer.arrival(remote:scope:local:remoteDoor:)`: after `classify`, at the remote door,
  `atRemoteDoor`. On a test host a TEST ONLY origin hook that rewrote loopback is taken instead
  (below).
- `AwayPolicy.isAway`: `remoteDoor && (origin == .vpn || origin == .internet || origin == .relay)`.
- The firewall's re-ask treats a relay as loopback: it came from this Mac, which says nothing of
  whether the firewall lets the network in.
- Nothing else changes: the remote door admits the same connections, Remote Access and the internet
  switch cut the same sessions, the refusal and backoff lines are the same, and the home door is as
  it was.

### What the Mac and the device show

- Sill.log: "Remote client connected: iPhone (iPhone18,3) through a relay on this Mac
  (127.0.0.1:54211)", then, with no device at home, "Away from home: every connected device is away;
  streaming at Low · Standard (4 Mbps per 60 fps, points). The home quality stays Balanced · Retina."
- The Mac's card and the Devices pane's "last connected": "through a relay on this Mac".
- The device's Settings panel: its kind 16 says it is away ("Away: Low · Standard"), and its own
  route line is the device's as before ("Connected through Tailscale · 2104 ms": the device knows its
  tunnel). No device change.

### Cases

| Case | Before | Now |
|---|---|---|
| A userspace tailnet node, SSH tunnel or proxy on the Mac, device on cellular | at home, home quality, "by address" | away, the away quality, "through a relay on this Mac" |
| A relay that forwards to the Mac's own LAN address | at home ("by address", a `lan` origin) | away, the same |
| A relay at home (the device at home, through the tailnet node) | at home | away until the move home brings it to the home door, as a kernel Tailscale (`utun`) session at home is today |
| Connect Remotely at home through the relay | at home | away for the session (Connect Remotely never moves home), as through kernel Tailscale today |
| Connect Remotely at home by the Mac's LAN address | at home | at home (unchanged: the device's own address, `lan`) |
| Kernel Tailscale, WireGuard (`utun`), the internet | away | away (unchanged) |
| A device at home through the home door, loopback included | at home | at home (unchanged) |
| A relayed device and one at home | home quality | home quality (any device at home brings it back) |
| The Simulator or a test client dialling the remote door on loopback | at home | away (a client on this Mac looks like a relay; `SILL_TEST_REMOTE_ORIGIN=lan` for "at home") |

### Tests' hooks

`SILL_TEST_REMOTE_ORIGIN` (TEST ONLY, a host that does not advertise) takes `lan` beside `vpn` and
`internet`: a loopback client at the remote door is then this network, at home ("by address"), as
every loopback client there was before. Without a hook a loopback test client at the remote door is a
relay on this Mac, away. `SILL_TEST_ORIGIN` (both doors) is unchanged. A hook that rewrote loopback
wins over the relay; the relay applies only to an origin no hook touched.

## Open questions, with the default taken

1. **(a), (b) or (c).** Default (a), above. (b) would need both apps updated, a second decision after
   registration and trust in a claim, to cover what (a) already covers for every device; its one gain
   is a relay off the Mac (question 2).
2. **A relay that is not on this Mac** (a router's port forward that rewrites the source, a reverse
   proxy on another computer at home): the door sees this network's address and counts the device at
   home. Default: unchanged (#326 is the relay on the Mac). A later (b), the device's own route word
   in its hello, taken only toward away, would cover it.
3. **The words.** Default "through a relay on this Mac" (the card, the Devices pane, the log). Others:
   "through this Mac", "through a tunnel on this Mac", "relayed by this Mac".
4. **The Mac's own addresses, not only loopback.** Default: both, so a relay that forwards to the
   Mac's LAN address counts too; a client on this Mac that dials its own LAN address is a relay as well.
5. **A relay at home counts as away until the move home**, and Connect Remotely through it for the
   whole session. Default: as a kernel VPN does today, so the two kinds of Tailscale agree.
6. **The refusal and backoff summaries.** The reporter noted that they count relayed connections as
   neither "through a VPN" nor "from the internet". Default: unchanged; they count why connections
   were refused (unpaired, over the limit, the internet switch), and a relay's are refused for the
   same reasons. A count of relayed connections there would change the remote door's line for
   everyone.
7. **Every device through one relay shares one source** at the remote door (127.0.0.1): two waiting
   places, one backoff (DoorPolicy.Places). A stranger who reaches the relay and fails five times in a
   minute backs off every device that comes through it for 300 s, and the address becomes "known" for
   all of them once one proves a paired key. Default: unchanged, written down: the door cannot see
   past a relay (a router that rewrites sources does the same).
8. **The support page and the site.** Their words stay true (away from home, through your VPN, Sill
   starts lower). Default: README's Away from home bullet names the relay; the site unchanged until
   Noah says (a republish).

## Verification

Planned, each on this branch against origin/main at f224323:
- `Tests/checks/origin` (the relay cases, live ones on this Mac's own addresses), `away-quality`
  (a relay away at the remote door, at home at the home door) and `door-policy` (the relay among every
  origin: admitted at the remote door whatever the internet switch, never at home; `afterGate` and
  `stillServes`), with their mutants; `run-all.sh`, all.
- `swift build -c release`.
- The CLI against main's, masked and sorted: idle; a client at the home door; a client at the remote
  door with `SILL_TEST_REMOTE_ORIGIN=vpn` (away on both) and `=lan` (at home on both; main ignores
  "lan" with a line). Identical where nothing is relayed.
- Loopback runs on a synthetic `--remote --pairing` host (loopback only, the software encoder, no
  router): a paired test client at the remote door with no hook (a relay: away, the away pair, "through
  a relay on this Mac"); the same from this Mac's own LAN address; `=lan` (at home, the home pair); a
  relayed client and one at the home door together (the home pair), then the home one leaving (the
  away pair); main's build on the relayed client (at home, "by address").

## Results

On this Mac (macOS 27.2, an M2 Pro), 2026-11-09, this branch against origin/main at f224323 (its
`SillHost` built from `git archive`); evidence (masked: no address, name or path of this Mac) in
sill-handoff's `triage/2026-11-09/doors/evidence-326/`.

- **Checks.** `origin` 95 (65 on main: 30 new, the remote door's mapping, `isThisMac`, the doors and the
  label, two live ones on this Mac's own addresses) and 19 of 19 mutants (9 new: loopback stays loopback,
  the Mac's own LAN address not a relay, every LAN source a relay, a tunnel from this Mac a relay, own
  addresses compared with the kernel's scope bytes, loopback not this Mac, a relay refused with internet
  access off, the home door admitting a relay, a relay labelled "by address"); `away-quality` 145 (143)
  and 41 of 41 mutants (AQ11 and AQ12's patterns follow the new line; AQ40, a relay at home, the rule
  before #326; AQ41, loopback away too); `door-policy` 264 (261) and 113 of 113 mutants (2,047 s);
  `run-all.sh`, all 63 passed.
- **Build.** `swift build -c release`, everything: 45.6 s, only the CaptureProbe warning.
- **Loopback runs** (`--synthetic --remote --pairing`, two test devices paired once at the remote door
  with the link, the same test identity for both builds):

  | Run | This branch | main's build |
  |---|---|---|
  | A paired device at the remote door from 127.0.0.1 (a relay on this Mac), the Desktop | "Remote client connected: … through a relay on this Mac (127.0.0.1:…)", "Away from home: every connected device is away; streaming at Low · Standard (4 Mbps per 60 fps, points). The home quality stays Balanced · Retina.", the stream at 4 Mbps; kind 16 `this=1, run=1` | "… by address (127.0.0.1:…)", no away line, the stream at 15 Mbps; `this=0, run=0` (the report) |
  | The same from this Mac's own en0 address (a relay forwarding to the LAN address) | "through a relay on this Mac", away, `this=1, run=1` | "by address", `this=0, run=0` |
  | `SILL_TEST_REMOTE_ORIGIN=lan` (a device at home through the remote door) | "by address", at home, `this=0, run=0` | the same, after "SILL_TEST_REMOTE_ORIGIN=lan ignored: vpn or internet." |
  | `SILL_TEST_REMOTE_ORIGIN=vpn` | "through your VPN", away, `this=1, run=1` | the same |
  | A relayed device, a paired one at the home door from 4 s to 10 s | away; "Home quality again: a device connected at home (127.0.0.1:…)" as it joins (the relayed device's kind 16 `run=0`), "Away from home: …" again as it leaves (`run=1`) | (not run) |

- **The CLI against main's**, masked (digits, the pairing link, this Mac's address) and sorted: the
  default host idle 12 s then a plain client 6 s, identical (24 lines each); the remote door with
  `SILL_TEST_REMOTE_ORIGIN=vpn`, identical (32 lines each); with `=lan`, main's "ignored" line and one
  `[1s]` line's counters (`cap.complete` in one second, the encoder's timing); the relayed runs, the label
  and the away line alone.
