**Away from home through a relay on the Mac (2026-11-09, branch `away-through-relay` from main at f224323,
PR #339; issue #326, Ti800; the code read, the fixes weighed, eight open questions with their defaults and
the results are in `docs/away-through-relay-plan.md`).** A remote connection that reached Sill through
something on the Mac that relays it locally (a userspace Tailscale or WireGuard node, a proxy or VPN app
running one in-process, an SSH tunnel, `socat`, a reverse proxy, a Cloudflare Tunnel connector) came in from
127.0.0.1, counted as at home ("by address") and streamed the home quality over cellular (the report: round
trips of 2 to 4 s, then a drop). Host only: no wire change, no device change, nothing stored.
- The rule (OriginPolicy, pure): at the remote door a source that is this Mac itself, loopback or one of
  its own addresses (`isThisMac`, from `Interfaces.owner`), is a new origin, `relay` (`atRemoteDoor`, in
  `StreamServer.arrival`); a tunnel's origin stays `vpn`. Admitted there as loopback was, internet access on
  or off; never named at the home door (loopback there is a client on this Mac). Labelled "through a relay
  on this Mac" (the log's "Remote client connected", the Mac's card, the Devices pane's last connected).
  Away from home as a VPN is (`AwayPolicy.isAway`): the away quality while every device is away, until the
  device comes home and moves to the home door; Connect Remotely through the relay at home stays away, as
  through kernel Tailscale. The firewall's re-ask takes a relay as loopback.
- Weighed (Noah had not chosen; he was told the clean fix lets the device say it is away): (a) host only,
  taken, the smallest sound one, every device at once; (b) the hello says how the device dialled: the
  remote door already tells the Mac that (it is dialled only by the device's saved remote addresses), and
  what a relay hides is the device's path; "always" would make Connect Remotely at home by the LAN address
  away, "only when the address tells nothing" is (a) for updated devices only, and a device's word could be
  trusted only toward away; (c) both. Open: (b) for a relay off the Mac (a router whose port forward rewrites
  the source), the words, own addresses, the summaries unchanged, every relayed device sharing 127.0.0.1's
  places and backoff, the site.
- TEST ONLY: `SILL_TEST_REMOTE_ORIGIN` also takes `lan` (a loopback client at the remote door at home, "by
  address", as every one was before); without a hook a loopback test client at the remote door is a relay,
  away (the simulator's remote dials on loopback too).
- Verified (the plan's Results): `origin` 95 checks and 19 of 19 mutants, `away-quality` 145 and 41 of 41,
  `door-policy` 264 and 113 of 113; `run-all.sh`, all 63; `swift build -c release`, only the
  CaptureProbe warning; live on loopback against main's build: a relayed device away (the stream at 4 Mbps,
  "through a relay on this Mac"; main: at home, 15 Mbps, "by address"), the same from this Mac's own en0
  address, `lan` at home, `vpn` the same on both, a relayed device and one at the home door (home quality,
  then away again as it left); the CLI masked and sorted identical idle, with a plain client and through
  `vpn`.
- **Untested, for Noah:** with Sill.app from this branch and the reporter's kind of setup (a userspace
  Tailscale node, or `ssh -L 7455:127.0.0.1:7455` from another machine as a stand-in), the iPhone on
  cellular: Sill.log "Remote client connected: … through a relay on this Mac (127.0.0.1:…)" and "Away from
  home: …", the device's panel "Away: Low · Standard", the Mac's card "through a relay on this Mac"; home
  again on Wi-Fi: the move home, "Home quality again"; Connect Remotely at home through the relay: away for
  the session.
