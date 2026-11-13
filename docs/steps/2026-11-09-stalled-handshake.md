**A connection that ends before its TLS handshake is not an unpaired refusal (2026-11-09, branch
`stalled-handshake` from main at f224323, PR #342; issue #314, oliverames; addhumal's comment on it; the
code read, the rule, six open questions with their defaults and the results are in
`docs/stalled-handshake-plan.md`).** On a macOS 27.3 beta with the firewall on, every connection to Sill's
doors over the Mac's LAN address was accepted at TCP and held until the door's 4 s handshake deadline cut it
(the client's errno 54 at 4.25 s); the door counted each "unpaired" and backed the phone's addresses off for
300 s, so a filter on the Mac read as a pairing problem and kept the phone out after it went. Noah to the
reporter: "a connection that never sends a TLS hello shouldn't be counted as an unpaired refusal and back
your phone off for five minutes." Host only, no wire change.
- The rule (DoorPolicy, pure; Door runs it): the deadline before `.ready` is `Places.End.timedOut`, never a
  refusal (a pairing connection that reached `.ready` without its kind 19 showed a key: still refused). Every
  end before `.ready`, timed out or gone by itself, costs `endCost` (a tenth) while the door had a place for
  every newcomer, and its hold as since finding 9 (`charge(held:refused: false)`, 1.1 at 4 s) when every
  shared place was held at some moment while it waited (`chargeBeforeKey`; `Places` marks every waiting
  connection, `Entry.contended`, whenever the eighth shared place is taken or a newcomer is turned away for
  want of one; a source's own two places mark nothing; known devices in the reserved places don't count).
  The caps are unchanged. A phone's own stalled dials, two at a time per address, never fill the eight
  places: 19 a minute cost 1.9, never 5. Finding 9's holders still fill them and pay as before (the model's
  every case of the scan's attack: backed off within 13 s). Given back: an address keeps its two places for
  good while the door has room (a tenth per connection); someone at a paired device's own address can hold
  that address's two places then (before, both were backed off); an IPv6 churner's /64 in about 2 minutes
  (114 s; 62 s before).
- Its own line, a third RefusalSummary per door, at most once a minute (`DoorPolicy.stall`, `stallLine`):
  "Home door: 5 connections in the last minute never finished their TLS handshake (4 timed out, 1 closed by
  the other end after waiting), so no key was checked and none counts as a refusal. A firewall or a content
  filter on this Mac may be holding them." ("Remote access: …"): every timeout, and a close by the other
  end after 2 s or more; a quicker close (a dial's loser, a port check) counted nowhere, as before; an older
  Sill's plain try still "older", garbage at the remote door and an unpaired key still "unpaired". And
  `door.stalled` in the `[1s]` lines. No notice in Sill.app (open question 3).
- Verified (the plan's Results): `door-policy` 288 checks (261 on main; the reporter's phone never backed
  off where the rule before backed it off at 16.64 s, every finding 9 case as before) and 131 mutants
  (each pattern applying once; not run yet: `run-all.sh --mutants door-policy`); `run-all.sh`, all 63; `swift build -c release`, only the CaptureProbe warning; live on
  loopback against main's build, both doors: a client that sends nothing gets the new line and
  `door.stalled` (main: "unpaired"), a reset after 3 s "closed by the other end", garbage, an HTTP request
  and a real unpaired key as before; 20 stalls, one address keeping two places 120 s, or three addresses
  keeping six: no backoff (main: backed off); four keeping all eight: backed off at 12–13 s on both; the CLI
  masked and sorted as main's where nothing stalls.
- **Untested, for Noah:** on a Mac with a macOS 27.3 beta (or whichever release brings the reporter's
  firewall behaviour), firewall on, Sill.app from this branch: the device's dials fail as before (the
  filter), Sill.log has the "never finished their TLS handshake … timed out" line and no "unpaired" or
  "backed off" line for them, and the moment the firewall goes off the device connects at once (no 5-minute
  wait). On any Mac, `nc 127.0.0.1 <home door port>` left open for 5 s (it sends nothing) gives one
  "timed out" line and no refusal.
