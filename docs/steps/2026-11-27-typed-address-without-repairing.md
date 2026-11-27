**Add an address to a saved Mac without pairing again (2026-11-27, branch `typed-address-without-repairing` from main at 22ab5a3e).**
A saved Mac's menu offers **Add an Address…**: one field, no code. Why: a route the Mac's own list
never names — a router port-forward, a VPN address past its 90 days, an address name — could until
now be dialed only by pairing again, which also burns one of the Mac's five tries on a typo and
makes a new record where one already served. Nothing is trusted for being typed: every dial stays
pinned to the record's key (`RemoteDialPolicy`), so a wrong address or another machine there only
fails to connect, never a wrong-Mac verdict.

- The rule (`SavedMacs.addingTyped`, pure, `TypedAdd`): appended to `typedAddresses`, the record in
  place, the address last; one destination (host at `address.port ?? remotePort`) once, across the
  Mac's own list, the typed ones and the remembered addresses still within `rememberFor` (the host's
  case folded); `keepable` decides what is never saved; at most `typedCap` (8) typed addresses; no
  record with that Mac ID (Forgotten while the card was up) is `missing`. The record's encoding, a
  kind 18's refresh, Forget, `superseding` and `replacingNewKey` treat it exactly as a typed pairing's
  address (kept on refresh, gone with the record).
- The client (`StreamClient.addTypedAddress`, `AddressProblem`): the typed path's address and zone
  words, then one for each refusal: not keepable, already dialed, full, missing.
- The card (`AddressCard`, pbxproj A0FE/F0FE): the connect screen's column, the Add a Mac card's
  field and inline problems; on Add, the checkmark line "Added ‹address› to ‹Mac›. It's tried after
  ‹Mac›'s own addresses." and Cancel reading Done; Esc and the escape gesture fold it
  (`foldAddress`). The menu item sits under Connect / Connect Remotely on every saved Mac's row and
  tile. `MockCatalog`'s `addaddress` case photographs it (`-SillLayout … -SillConnectCase
  addaddress`).
- The check (`Tests/checks/remote-rules/typedadd.swift`): what is added and refused, one destination
  once (the Mac's list, the typed ones, the remembered in and past their season, the host's case and
  port), never one `keepable` refuses, the cap, another record untouched, the encoding, the refresh
  after it, the dial's order; 13 mutants in `mutants.py`.
- **Copilot's review (2026-11-27), all four fixed.** Typed addresses are the person's word, not the
  Mac's: `RemoteDialPolicy.order` now takes them as `typed`, a group of its own after the Mac's own
  list and before the remembered ones (they used to be kind-sorted into the Mac's group, so a typed
  VPN name could run before the Mac's own internet address, against the card's words), and at one
  only the Mac's own answers and silence count (`classify`, as at a remembered address) and no other
  saved Mac's key is taken (`successors`), so another key or a stale name there never retires a
  record nor stops the automatic redials. The harness's mock client no longer writes its made-up
  record over the device's saved Macs (`addTypedAddress` casts `persistSavedMacs` aside when
  `mockDiscovery`), and opening the card cancels a tap's ask still in flight (`unfoldAddress`, as
  Add a Mac's unfold does), whose reply would otherwise take the card's place. New checks for the
  order and the three rules; four mutants more.
