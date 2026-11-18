# A connection that ends before its TLS handshake: the plan

2026-11-09. Branch `stalled-handshake` (worktree `/Users/noah/Downloads/wt-314`, PR #342) from origin/main at f224323;
line numbers are at f224323. Issue #314 (oliverames, Sill 0.6.0 (1276) on macOS 27.3 beta 26C5035r and an
iPhone on iOS 27.3 beta 1): "Connections to Sill stall for 4 s and reset when the macOS firewall is on". Noah
to the reporter (2026-11-09): "a connection that never sends a TLS hello shouldn't be counted as an unpaired
refusal and back your phone off for five minutes." Host only: no wire change, nothing on the device, nothing
stored.

## What happened, read from the report and the code

- With the firewall on, every connection to both doors over the Mac's LAN address was accepted at TCP and
  then held; Network.framework logged `flow:connect_stalled @2.0s`, the content filter's extension timed
  out, and at about 4.25 s the client saw a reset (errno 54). With the firewall off the phone paired and
  streamed at once. The firewall's rule allowed Sill; a plain `python3` listener answered. So the filter of
  that beta held Sill's flows. Sill cannot fix the filter.
- What Sill made of it. Each such connection reached `Door.accept` and took a waiting place
  (Door.swift:183, 207). Its TLS handshake never finished, so its deadline, 4 s from an address not known
  (`DoorPolicy.handshakeDeadline`, DoorPolicy.swift:241; 10 s from a known one), passed:
  `deadlinePassed` (Door.swift:486-491) called `refuse(id, "unpaired")` and cancelled it. The cancel is the
  4.25 s reset the reporter measured.
- `refuse` counted it "unpaired" in the minute's line ("Home door refused 6 connections in the last minute:
  6 unpaired, …"), and its end cost its address `charge(held: 4, refused: true)` = 1.1 failures
  (DoorPolicy.swift:288-290, `Places.leave` :467-468). Five in 60 s back the address off for 300 s:
  "Remote access backed off 192.168.x.x for 300 s: its connections waited without being admitted, or were
  refused." The phone then could not even reach the handshake for 5 minutes, whatever the filter did.
- As addhumal noted on the issue, the label and the backoff are two things. The backoff is finding 9's
  rule (the security scan of 2026-10-18; PR #252): holding a waiting place costs its source, since four
  addresses whose connections sent nothing kept every place full and a paired device got "limit". A
  connection the filter holds and one a holder holds look the same before TLS: Network.framework says
  nothing between accept and `.ready` (no callback when a ClientHello arrives).
- How a connection that ends before any key is seen is classified at f224323, each in
  `endedBeforeAdmission` (Door.swift:504-521):
  - the door's deadline before `.ready`: a refusal, "unpaired", 1.1 at 4 s (at least one);
  - the other end closes or resets it first (a TLS status that is not a refusal: -9816, a reset, -9825):
    nothing in any line, and what it held (`charge(held:refused: false)`: 0.1 within 2 s, 1.05 at 3.9 s);
  - plain bytes (-9836) at home: "older" (an older Sill), what it held; at the remote door, and an HTTP
    request (-9858) at either, "unpaired", one at least;
  - a key the verify block refused (-9808): "unpaired", one at least.

## The rule

A connection whose TLS handshake never finished showed no key, so it is not a refusal: its own outcome.

1. **The deadline before `.ready` is a timeout, never a refusal.** `Places.End.timedOut`, beside `.refused`
   and `.ended`. Not counted "unpaired". A pairing connection that reached `.ready` and sent no kind 19 by
   its deadline did show a key: still refused, as since the review of finding 9.
2. **What it costs.** Every end before `.ready`, timed out or gone by itself, costs `endCost`, a tenth of a
   failure, while the door had a place for every newcomer; its hold (`charge(held:refused: false)`: 1.1 at
   4 s) only when every shared place was held at some moment while it waited
   (`DoorPolicy.chargeBeforeKey`). `Places` marks every waiting connection whenever the eighth shared place
   is taken, or a newcomer is turned away for want of one (`Entry.contended`). A source refused for its own
   two places marks nothing: those are its own connections (a device's stalled dials meet that limit by
   themselves). The reserved places of known addresses don't count as shared.
   - The reporter's phone: two waiting at most per address, never eight, so a tenth per stalled dial: 19 a
     minute is 1.9, never 5. The filter gone, its next dial gets in.
   - Finding 9's attack: holders that keep every shared place full are charged as before and backed off in
     the same time (the check's model: the scan's four addresses within 13 s; closing at 1.9, 3.9, 0.5 or
     0.05 s; eight addresses one place each; the pairing ALPN's holders).
   - The tenth stays on every end, so one address opening connections and closing them at once is still
     backed off at 50 a minute, as before.
3. **Its own line.** A third summary per door, beside the refusals' and the backoffs', the same
   RefusalSummary (the first at once, then at most one a minute): "Home door: 5 connections in the last
   minute never finished their TLS handshake (4 timed out, 1 closed by the other end after waiting), so no
   key was checked and none counts as a refusal. A firewall or a content filter on this Mac may be holding
   them." Counted: every timeout, and every close by the other end after waiting 2 s or more (a device that
   gave up on a stalled dial, `DoorPolicy.stall`). A close sooner (a dial's loser, a port check) is counted
   nowhere, as before. Never an older Sill's plain try (still "older") or a refusal. The remote door's line
   starts "Remote access:".
4. **A counter.** `door.stalled` in the `[1s]` stats lines for each connection the line counts.
5. **The caps are unchanged**: 8 shared places, 2 more for known addresses, 2 per source (an IPv6 /64 for
   addresses not known), 4 s and 10 s deadlines, 5 failures in 60 s and 12 in 300 s for a /64, 300 s. A
   flood is bounded exactly as before; only who pays for a held place while places are free changes.

## What it gives back, and what stays

- An address can now keep its two places for good while the door has room for everyone, paying a tenth
  per connection: before, a place held without a break cost 6 a minute and its address was backed off
  within 50 s. With room, nobody is kept out, which is why the charge existed. As soon as the shared places
  are all held, every wait pays as it did, so holders can no longer fill the door for free. Four addresses
  can hold seven of the eight shared places for nothing while nobody needs the eighth; the eighth taken,
  by anyone, charges all seven.
- Someone at a paired device's own address (its NAT, a carrier NAT from the internet with internet access
  on) can hold that address's two places while the door has room, and the device there is refused for its
  address's limit meanwhile ("over the limit"). Before #314 both were backed off within 30 s, the device
  refused as much: nothing tells them apart before TLS.
- An IPv6 host taking a new address of its /64 for every connection holds the /64's two places and pays
  the tenths: its /64 is backed off in about two minutes (114 s closing each at 1.9 s; 62 s before), four
  holding one place (240 s; 121 s before).
- A household whose every device stalls (four dialling at once) fills the places and pays as holders do.

## Sill.app

The menu's "Devices Can’t Connect" (FirewallRule) speaks of the firewall's rules for Sill's executable,
which socketfilterfw reports. A stall says nothing so certain: Sill cannot tell a filter on the Mac from a
peer that sends nothing, or from a device that gave up. Default: the log line and the counter, no notice
(open question 3).

## Open questions, with the default taken

1. **How a timeout costs.** Default: the tenth while the door has room, its hold when every shared place
   was held (above). The literal reading of the report, never charging it, reopens finding 9: four holders
   keep every place for good and a device not yet known is refused throughout (`door-policy`'s mutant
   "no wait before a key pays its hold" fails the check's attack). The other way, a shorter backoff for an
   address whose every failure was a timeout (addhumal's option 3), still backs the phone off.
2. **Contention when the last shared place is taken, or only when a newcomer is turned away.** Default:
   the first: holders pay whenever they fill the door, whether a device tried at that moment or not. Only
   a refusal would let holders that empty one place now and then keep the rest for good unless a device
   happened to try then.
3. **A notice in Sill.app**, like "Devices Can’t Connect": "Devices' connections stall before Sill sees
   them. A firewall or content filter on this Mac may be holding them." Default: none for now. If wanted,
   only for timeouts from this Mac's own networks (not the internet, not a VPN), several in a minute, and
   gone after a minute without one; it needs copy and previews, and it would also show for a stranger on
   the LAN who sends nothing.
4. **The other end's close after 2 s or more counted on the line.** Default: yes ("closed by the other end
   after waiting"): a device that gives up on a stalled dial (its reconnect lets go at 5 s) shows the same
   symptom. Sooner, nothing, as before, so a dial's losers and port checks print nothing.
5. **Garbage at the remote door** (plain bytes, -9836, or an HTTP request) is still "unpaired", a refusal.
   It is a peer speaking something that isn't Sill's TLS, not a stall; a word of its own there ("not TLS",
   as the home door's "older") would change the remote door's line for everyone. Default: unchanged.
6. **The words**: "never finished their TLS handshake … no key was checked … A firewall or a content
   filter on this Mac may be holding them." "Content filter" is macOS's own name for what held the
   reporter's flows (Network Extension); "network filter" would be plainer.

## Verification

Planned, on this branch against origin/main at f224323:
- `Tests/checks/door-policy`: the cost (`chargeBeforeKey`), the line (`stall`, `stallLine`), contention
  (the eighth place, a newcomer turned away, a source's own limit, known devices in reserved places,
  marks that stay), the reporter's phone against the rule before (a `Before314` stand-in: the deadline a
  refusal), and every finding 9 case the model ran, reworked where the rule now differs; its mutants;
  `run-all.sh`, all.
- `swift build -c release`.
- The CLI against main's, masked and sorted: idle, and with a paired client at both TLS doors (no stalls:
  identical).
- Loopback runs on a synthetic `--pairing --remote` host (loopback only, the software encoder, no router):
  a client that connects and sends nothing, one that sends garbage, one that resets after 3 s, one that
  resets at once, and a real unpaired key; at both doors; 20 stalls from one address in a minute (no
  backoff here; main backs it off); every shared place held by stalls from four of this Mac's addresses
  (backed off as before).

## Results

On this Mac (macOS 27.2, an M2 Pro; its firewall's own settings untouched), 2026-11-09, this branch against
origin/main at f224323 (its `SillHost` built from `git archive`); evidence (masked: no address, name or path
of this Mac) in sill-handoff's `triage/2026-11-09/doors/evidence-314/`. The reporter's filter was not
reproduced: a client that connects and sends nothing is what Sill saw of it.

- **Checks.** `door-policy` 288 (261 on main): `chargeBeforeKey`, `stall`, `stallLine`, contention (the
  eighth place marks every waiting one, those before it too; a mark stays once places free; one arriving
  after the places freed is not marked; a newcomer turned away; a source's own limit marks nothing; known
  devices in reserved places marked only when the shared places are full), the reporter's phone (19 stalled
  dials a minute for 10 minutes, 190 dials: never backed off, in at once when the filter goes; the rule
  before: backed off at 16.64 s and in only at 640 s), dialling every 1.5 s (133 of 400 refused for its
  own two places: never backed off), by three addresses at once (never), four devices stalling together
  (they fill the places: backed off at 13.0 s), and every finding 9 case: the scan's attack and its
  variants backed off as before (the four within 13 s), the reworked trade-offs above. Mutants: 131 (113 on
  main), each pattern applying once; their run did not happen here (the shared build lock was held by other agents' long jobs until this session had to stop): `Tests/checks/run-all.sh --mutants door-policy` runs them. `run-all.sh`, all 63 passed.
- **Build.** `swift build -c release`, everything: 47.8 s, only the CaptureProbe warning.
- **Loopback runs** (`--synthetic --remote --pairing`, a fresh host for each, both doors on 127.0.0.1):

  | Client | This branch | main's build |
  |---|---|---|
  | connects and sends nothing (cut at 4 s) | "Home door: 1 connection in the last minute never finished its TLS handshake (1 timed out, 0 closed by the other end after waiting), …"; `door.stalled 1` | "Home door refused 1 connection …: 1 unpaired, …" |
  | the same at the remote door | "Remote access: 1 connection … (1 timed out, …)" | "Remote access refused 1 connection …: 1 unpaired, …" |
  | resets after 3 s | "… (0 timed out, 1 closed by the other end after waiting) …", both doors | nothing printed |
  | resets after 0.2 s | nothing printed | nothing printed |
  | 64 bytes that are not TLS | home "1 from an older Sill (not TLS)", remote "1 unpaired" | the same |
  | an HTTP request | "1 unpaired" at both | the same |
  | a real unpaired key (a fresh test identity, sill/1) | "refused … 1 unpaired" at both | the same |
  | 20 stalls from 127.0.0.1, one at a time (80 s) | stall lines (1, then 14), no backoff | "… unpaired" and "Home door backed off 127.0.0.1 for 300 s" |
  | one address keeping its two places for 120 s (cut at 4 s, at once again) | 58 connections, no backoff | backed off at its fifth, then 1,036 refused at accept |
  | three addresses, two places each, 30 s (two places left free) | 16 connections each, no backoff | backed off |
  | four addresses, two each (every shared place held), 30 s | all four backed off between 12 and 13 s | the same, between 12 and 13 s |

- **The CLI against main's**, masked and sorted, where nothing stalls: the plain door idle 12 s and a
  client 6 s, and the TLS doors with a device paired by the link and a session at each: identical but for
  one `[1s]` line's counters (the encoder's timing) and the test device's key in its pairing line (a new
  key each run).
