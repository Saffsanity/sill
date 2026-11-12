**A saved Mac keeps its VPN addresses (2026-11-11, branch `keep-vpn-addresses` from main at 9ea2e41, PR
#349; the rule, its why and the results are in docs/remote-access-plan.md §7.2 ("Remembered VPN
addresses"), §7.5, §9 and its Results' last section).** Noah's night: Tailscale was off on his Mac for about
ten minutes while his iPad connected at home; that session's kind 18 listed the Mac's Wi‑Fi address alone,
`SavedMacs.refreshed` replaced the saved list with it, and away on a hotspot the iPad had nothing it could
reach, Tailscale on again or not, and said "‹Mac› didn’t answer. It may be asleep." (#309's hint needs a VPN
address in the record); one session at home with Tailscale on repaired it. Noah: "Create a new pr to fix the
weakness as well." Device only, no wire change.
- The rule (`SavedMacs.remembering`, pure): a list that replaces the saved one keeps the VPN addresses
  (kind "vpn", the Mac's own word: Tailscale's name and addresses, another VPN's; never a LAN, router or
  internet address) the old one had and it lacks, in `SavedMac.rememberedAddresses` (optional), each with
  when the Mac last listed it by this device's clock: when the kind 18 that set the old list was taken
  (`addressesListedAt`, optional, set by every replacing refresh), for a record no such kind 18 has set
  (from before, or just paired with its link's addresses) the later of its kind 18's time and its
  pairing's; a time after now read as now. For 90 days after the Mac last listed it (`rememberFor`: a VPN
  keeps a machine's addresses while it stays in it, so a VPN off on the Mac between trips still finds it;
  a VPN the Mac left, or a name it no longer has, stops being dialed within a season), at most four
  (`rememberCap`: Tailscale's three and one more), newest first. A list that has one again takes it back
  (its time refreshed); a list kept as it is (empty, Remote Access off) only ages them. `adding` (a new
  pairing of the same Mac ID) carries what the old record had and the new list lacks, aged against the
  pairing's time; `superseding`, `replacingNewKey` and Forget drop them with the record (another key's).
  An older record decodes and is written back byte for byte; an older build reads a newer record.
- The dial (`RemoteDialPolicy.order(_:remembered:…)`, `SavedMacs.remembered(_:now:)`): the Mac's list and
  the typed addresses as before, then the remembered ones as a second group in the same order (the address
  that last worked first among them), marked (`Candidate.remembered`), never before the Mac's list; one in
  both dialed once, in the first. At a remembered address `classify` counts only the Mac's own answers
  (our key refused after the pin, a goodbye, its door's refusal) and silence: another key (-9808), a TLS
  that isn't Sill's and a name lookup count for nothing (a stale address may be another machine's; a
  wrong-Mac verdict would also stop the automatic redials, a renamed Mac's old name would read "Tailscale
  looks off…"); `successors` takes no other key there. `RemoteDialPolicy.failed` is RemoteConnector's
  verdict, now pure; `RemoteCopy.vpnName` names the VPN from every address the dial had, so the hint ("…or
  Tailscale may be off on the Mac") works with remembered ones. The Remote rows needed nothing (they never
  read addresses). DEBUG console: "(remembered)" in the dial's list, "VPN addresses remembered: …" when a
  refresh changes them, and the failure's words.
- The cost: a remembered address starts a second (the stagger) after each address of the Mac's list that
  neither answers nor fails at once; when the list answers, none starts; when nothing answers, each adds
  about a second before the dial gives up, never past its 20 s.
- Verified (on the branch merged with main at c3382ee): remote-rules 249 checks (70 new in `vpnmemory.swift`:
  Noah's night as a model, the rule's edges, the dial, every failure's words with only remembered addresses,
  the records, a build from before reading a newer record, and 2,000 random lives against an independent
  bookkeeping of when each address was last listed) and 124 of 124 mutants (34 new; three older patterns
  follow the moved text; the check's output is line-buffered now, so a mutant that crashes it still shows its
  FAIL lines); home-records 46 checks and 27 of 27 mutants, home-model 87 and 30 of 30 (they compile
  SavedMacs.swift on its own); `run-all.sh` all 66 passed (remote-rules 248 then; 249 on its own once the
  random model was added); iOS Debug for the generic simulator (CI's command) and Release for the simulator,
  only the known StreamClient capture warning; nothing in the Swift package changed. Live on a simulator of
  the agent's own (an iPhone Duo on iOS 27.1, the only device type that runtime has here; deleted after; the
  app ad hoc signed) against `SillHost --synthetic --remote` on 127.0.0.1 (`no-device.sh` before each host and
  every 5 s during, launch arguments only, Sill.log untouched), a vpn-kind `localhost` behind a loopback relay
  standing in for a Tailscale address: a real kind 18 that lacked it moved it into memory with the old list's
  time; with the Mac's list answering nothing the remembered address won 4.2 s into the dial (four staggers)
  and connected, pinned; with the list answering it never started; every address silent: "Tailscale looks off
  on this iPhone or on ‹Mac›…" (loopback has no tunnel), nothing remembered: "‹Mac› didn’t answer. It may be
  asleep."; the remembered address leading to another test host's key: -9808, counted for nothing, and "‹Mac›
  didn’t answer. It may be asleep, or Tailscale may be off on the Mac." (the same address in the Mac's list:
  "This isn’t the ‹Mac›…"). The live runs, masked, are in sill-handoff's
  `triage/2026-11-11/vpn-memory/PROGRESS.md`.
- **Untested, for Noah:** on the iPad with this build, at home with Tailscale off on the Mac, connect once
  (Xcode's console: "VPN addresses remembered: ‹name› (Tailscale, …)"); then Tailscale on again on the Mac
  and away on the hotspot, tap the Mac's Remote row: it connects through Tailscale without another session
  at home (the dial's list ends "… (remembered)"); with Tailscale still off on the Mac: "‹Mac› didn’t
  answer. It may be asleep, or Tailscale may be off on the Mac."; a TestFlight build over this build's
  saved record keeps working.
