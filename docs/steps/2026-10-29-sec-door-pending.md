**The door's waiting places (2026-10-29, branch `sec-door-pending` from main at 150479b5, PR #252; finding 9 of the
security scan of 2026-10-18, Low; Noah's go of 2026-10-29).** A TLS door (the remote one, and the home one of
Sill.app and `SillHost --pairing`) held 8 connections waiting for admission, 2 per address, 10 s each, and backed an
address off only for its own refusals: four addresses closing each connection at 9.9 s kept every place full for good
and a paired device got "limit". Host only, no wire change. `DoorPolicy.Places` (pure) owns the places, `Door` runs
it on a monotonic clock: a connection that ends unadmitted, and a pairing connection's kind 19, costs its address a
tenth of a failure, a tenth for each second it waited at least, one more for every 2 s beyond the first 2 (counted to
its deadline at most), at least one when refused (5 in 60 s: 300 s, as before; a paired key at `.ready` clears its
address); the TLS handshake has 4 s (Network.framework does not say when a ClientHello arrives, so the whole
handshake rather than its first bytes; 10 s from a known address), a pairing connection's kind 19 4 s after `.ready`,
10 s in all; an IPv6 address answers for its /64 too (a link-local one's on its interface): 2 waiting places per /64
for addresses not known, and 12 failures in 300 s from those back the /64 off, an address counting 6 at most (so it
takes two); 2 places beyond the 8 for addresses that proved a paired key within a day (known: never refused for nor
charged to their /64, and they pay for what they hold as an address not known does, so someone at a paired device's
address is backed off with it within 30 s: nothing tells them apart before TLS). One line a minute per door, "Home
door backed off 10.128.0.34 for 300 s: its connections waited without being admitted, or were refused."
`AskLimits.quietKey`: the quiet after the Mac's Cancel or a stop covers the asker's IPv6 /64. Checks: `door-policy`
254 (the scan's attack modelled against the rule before and this one: before, every place held and the paired device
refused at all 60 tries in 2 minutes; now the four backed off 12 s in, the paired device admitted at every try, one
not yet known in at 13 s; closing at 1.9 s, 26.6 s; IPv6 churn in a /64, the /64 at 61 s, holding one place at 120 s)
and 109 of 109 mutants; `ask-limits` 43 and 24 of 24. Live on loopback synthetic `--pairing` hosts (sources
127.0.0.1, en0's 10.128.0.34, en13's 10.128.0.148 and en14's 169.254.219.184, whose connections to 127.0.0.1 stay on
lo0; 127.0.0.2–5 cannot be bound without a root alias): main's build refused the paired client at all 30 tries in 90
s ("… 27 over the limit."), backing nobody off; this one cut the four at 4.2 s and backed them off at 12.6 s ("Home
door backed off 10.128.0.34 for 300 s: …", the client at 127.0.0.1 with them); a scratch build with 6 shared places
(three addresses filling them as four fill 8) served a known client at all 20 tries and an unknown one from 13 s; one
address cycling at 1.9 s held 2 places for good on main and was backed off at 47.9 s here. Plan's "What stays open"
updated (an address keeps about 4/5 of a place, so ten IPv4 addresses taking turns fill the shared places; the
co-located address; a device not yet paired in a backed-off /64, which a stranger in it keeps backed off with a dozen
refused handshakes as each 5 minutes end; a routed IPv6 prefix from the internet at the remote door).
- The review (2026-10-29; the report's "The review", f9-pending-slots-report.md in sill-handoff's
  triage/2026-10-29-security): three findings, each reproduced live on 7929c539 first and fixed in a commit of its own.
  A kind 19 left its place for nothing, and the home door's verify block takes `sill-pair/1` with any key: a holder
  doing TLS on it 3 s in and a kind 19 (`v` 2, answered `closed`, nothing shown) 3.5 s later held all 8 places for
  90 s from four addresses (112 kind 19s), nobody backed off, an unknown paired client refused at all 30 tries; now
  `Places.End.request` pays as a connection that ended then (fd0a58c5): the same holder backed off at 13.07 s. The
  wait counted from accept on CLOCK_MONOTONIC, which runs on through a sleep while the deadline's timer does not: one
  connection waiting across a 20 s SIGSTOP of the host (a sleep's stand-in) backed 127.0.0.1 off at the continue and
  the known client was refused at all 13 tries; now a wait counts to its place's deadline at most (0b457e48): no
  backoff, 13 of 13 served. A known address was charged for all of its 10 s (a cut 4.1, its device's own let-go at
  5 s 1.6, where main charged 1 and nothing): a known device's reconnect whose dials stalled was backed off at 40.06 s
  and refused at all 6 tries after; now it pays as an address not known (1.1 at most for a handshake, 3.1 for a
  pairing connection; 8e0148a0): no backoff, 6 of 6 served. Docs: the plans' limits tables, sillclient's `--pair-hold`
  note, DEVELOPMENT.md, and the /64 trade-off (a check: the /64 open 1.8 s of 15 minutes).
- The review's second pass (2026-10-29, resumed after the session's limit stopped the first before it pushed; the
  report's "The review"): three more findings, each reproduced first and fixed in a commit of its own. A mutant's
  pattern still named the line 0b457e48 replaced, so `run.sh --mutants` said "NOT APPLIED" and 103 of 104 (bda128ba).
  An end within 2 s cost a tenth however long it held its place, so one connection at a time closed at 2 s cost an
  address 3 a minute, under its 5: eight addresses held every shared place for good (the model, 600 s: nobody backed
  off, a device not yet known refused at all 300 tries; live, one address 120 s: no "backed off" line; a scratch
  build of 3 shared places: three addresses held them 120 s, a paired client not yet known refused at all 40 tries);
  now each second held costs a tenth at least, `DoorPolicy.waitCost` (8b51058d): live, "[51.54] Home door backed off
  10.128.0.34 for 300 s: …", and with 3 places the three backed off at 51.5 s (27 connections each) and the client,
  refused at all 17 tries before, served at all 23 after; an address keeps about 4/5 of a place (ten taking turns
  could fill the 8). The /64's 12 was said to need two addresses, true only for a burst: paced under its own 5, one
  address backed its /64 off (an older Sill's plain try every 2 s on its link-local address backed off its whole link
  at 238 s; a refusal every 16 s, at 176 s); now an address counts for 6 at most, `DoorPolicy.groupShare` (c0e70ab6;
  the model only: the test listener is IPv4). door-policy 254 checks and 109 of 109 mutants, ask-limits 24 of 24,
  home-model 25 of 25, addresses 16 of 16; `run-all.sh` all 56 (513 s); `swift build -c release` from a clean
  `.build`, only the CaptureProbe warning; `Scripts/pacing/build.sh` builds both sides. The first pass's live runs
  again on the final build: the kind 19 holder backed off at 13.18 s, the 20 s stop no backoff and 13 of 13 served,
  the known device's stalled dials no backoff and 7 of 7, the scan's attack backed off by 12.63 s.
**Untested, for Noah:** a week of ordinary use at home and away (Wi-Fi, cable, Tailscale, the hotspot) with no
"backed off" line in Sill.log (note any, with what the device did); a new pairing over the hotspot through Tailscale
(its handshake inside 4 s); an iPad back after a night asleep; from the review, the Mac's lid closed while the iPad
reconnects, then opened: the iPad back at once, no "backed off" line; the iPad sent to the background mid-dial a few
times, or walked out of Wi-Fi range while it redials: no "backed off" line for its address; from its second pass, a
device whose dial tries the Mac's addresses 1 s apart (through Tailscale), away and back a few times: no "backed off"
line (its losers now cost up to 0.2 each).
