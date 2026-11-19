**Direct Wireless only from a paired device (2026-10-29, branch `sec-direct-wireless-paired` from main at
150479b5, PR #253; the security scan's finding 8, Low; Noah's go of 2026-10-29 for the batch).** Any session at
the home door could turn Direct Wireless Connection on or off from its Settings panel, an unpaired device at a door
that lets any device in (Require pairing off) and any device at SillHost's plain door included, and Sill.app saved
it: the door advertised and accepting over AWDL, radio range, on a stranger's word. Additive wire, host and device.
- Host: `DeviceSettings.accepted(_:virtualDisplayAvailable:fromRemote:paired:)` (no default arguments now) takes
  `directWireless`, on or off, only from a paired session at home; otherwise refused and named, "Settings from
  ‹device› refused: direct wireless (only a paired device)" (away from home the old "(not from a remote
  connection)" first), the rest of the change applied whoever sent it. Paired (`DeviceSettings.paired(key:trusted:)`,
  the coordinator's `sessionPaired`): the session's key (`ClientRoute.fingerprint`, proved in its TLS handshake;
  none at the plain door) on the Mac's trust list as the status snapshot lists it now (`remote.paired`, which
  RemoteAccess publishes with every change of the list). The route already kept the admission (`peer.name`, nil
  for an unpaired key); the live list adds a device paired during its session (Pair This iPad… at an open door)
  and drops one removed before its session closes. Turning it off is refused too: an unpaired device would
  disconnect the paired ones connected over it.
- Wire: kind 16's `sessionPaired` (`HostSettingsState`, optional, the connection's own like `away` and `link`):
  true for a key on the list (the remote door's too), false for an unpaired key at an open door and at a plain
  door; nil from hosts before, which took it from any session at home; re-published when the list changes.
- Device: the ledger's rule 10 (`HostSettingsState.takesDirectWireless`, `sessionPaired != false`) never sends
  it on a session the Mac says is not paired; the panel disables the switch there, its footnote "Change this on
  ‹Mac›, or from a device paired with it." (away from home as before, "…, or from a device near it."). The mock:
  `default` paired, `cli` and `openpair` not, the older Macs' cases silent.
- CLI: TEST ONLY `SILL_TEST_REQUIRE_PAIRING=0` (a `--synthetic` host; TestHooks' list) turns Require pairing off
  at `--pairing`'s TLS door for the run ("Home door: TLS, pairing not required."); sillclient prints `paired=` and
  `--expect` takes `sessionPaired`. Closes the Direct Wireless entry's "revisit it with pairing" (below) and
  docs/direct-wireless-plan.md's; SECURITY.md's known list, DEVELOPMENT.md and support.html say who changes it.
- Verified: `away-quality` 143 checks and 39 of 39 mutants (96 and 30 before), `compatibility` 146 and
  36 of 36 (140, 34), `ledger` 116 and 16 of 16 (100, 12; 5,000 random runs: Direct Wireless taken from a paired
  session 1,579 times, refused from an unpaired one 521, rule 10 holding back 943 picks, 1,209 devices paired
  during a session, 899 runs against a host from before); `run-all.sh`, all 56 (621 s); a clean `swift build -c release`
  from `git archive` of 52ad232c, only the CaptureProbe warning; the iOS app Debug and Release for the simulator
  and Debug for a device, only the known `StreamClient` capture warning (StreamClient.swift:4110). Live on
  loopback synthetic CLI hosts (software encoder, no router, no screen): at `--pairing`'s door a paired identity
  turned it on and off (`dw=1 paired=1`, "Settings from paired-a: direct wireless off → on", "Direct wireless
  on: listening on port … again."); at the open door (`SILL_TEST_REQUIRE_PAIRING=0`, "Home door: TLS, pairing
  not required.") an unpaired identity's on and off refused (`dw=0 paired=0`, "Settings from unpaired-b
  refused: direct wireless (only a paired device)") while a paired one beside it turned it on and off, and an
  identity paired by a second connection during its session heard `paired=1` 5.0 s in and was then taken; the
  plain door refused it (`paired=0`); the remote door refused it as before (`paired=1`, "(not from a remote
  connection)"); no "Enabling AWDL" in the kernel log meanwhile. H2 against 150479b5 (`--synthetic` idle, then a
  test client on the Desktop): identical masked and sorted (27 lines) but for the second the client left
  (which counters it listed). Harness photos on a private iPad mini simulator (deleted after), 710×1000 and
  1000×710: `openpair` and `cli` the switch dimmed with the new footnote, `default` as before (sill-handoff's
  `triage/2026-10-29-security/f8-photos/`).
- The review (2026-10-29, after 73f4892f; sill-handoff's `triage/2026-10-29-security/f8-direct-wireless-report.md`,
  "The review"): the rule holds (the key from the TLS handshake at `.ready`, the list the status publishes with every
  change of it before anything else runs, `accepted`'s `ok` the only way a device's change reaches the config). The
  scan's own command took it at origin/main's plain door (`dw=1`, "Direct wireless on: listening on port … again.")
  and is refused here (EXPECT FAIL). Every bypass tried on loopback was refused: at the open door a kind 17 forging
  `sessionPaired`, an Int, duplicate keys, six at once and a paired device's name; a pairing window open after kind
  21; the plain door; the remote door. What remains is by design or another finding's: a session that controls the
  Mac's input can still turn it on in Sill's own menu or Settings (blind: Sill streams none of its windows), any
  paired device can, and the cable's automatic pairing is finding 2. Two docs findings fixed: the plan's host rule
  and the gates that change it at the plain door (91b83561), DEVELOPMENT.md's command-line host (881ac12f).
  Re-run: `away-quality` 143 and 39 of 39 mutants, `compatibility` 146 and 36 of 36, `ledger` 116 and 16 of 16;
  `run-all.sh`, all 56 (483 s); `swift build -c release`, only the CaptureProbe warning; the three iOS builds
  (Xcode 27.1), only the known `StreamClient` capture warning; H2 against 150479b5, identical masked and sorted but
  for one stats line as the client left.
- A second pass (2026-10-29, after a66cd93a; the report's "The review, second pass"): no code to fix; one docs nit,
  support.html's new sentence promised a paired device the switch through Remote Access too, which the Mac refuses
  (`dw=0 paired=1`, "(not from a remote connection)"): now "but not while it's connected through Remote Access",
  inside the Remote Access markers (e012ab81). It tried what the rule and all of pairing rest on, a paired device's
  key used without its private key. Apple's APIs cannot make such a client (SecIdentityCreate refuses a certificate
  with another key; `sec_identity_create_with_certificates` still sends the identity's own certificate first, which
  the open door admits as unpaired and refuses Direct Wireless). A TLS 1.3 client of its own (CryptoKit;
  sill-handoff's `triage/2026-10-29-security/f8-review2/tls13forge.swift`) sending paired a's certificate with a
  CertificateVerify signed by another key got a `decrypt_error` alert before any Sill message, at `--pairing`'s door
  and at the open door, and the host logged no "Client connected"; the same client signing with a's own key was
  admitted as paired-a and turned it on. Re-run: `away-quality` 143 and 39 of 39 mutants, `ledger` 116 and 16 of 16,
  `compatibility` 146 and 36 of 36; `swift build -c release`, only the CaptureProbe warning.
- **Untested, for Noah:** with this branch's Sill.app (release-signed with the profile) and this iPad
  build: a paired device's switch at home, on and off, Sill.app's menu and General pane following and
  `defaults read me.saffer.sill.mac directWireless` saved; Require pairing off and a device the Mac has not
  paired (one never paired, or one removed in Settings › Devices): its switch dimmed with "Change this on ‹Mac›,
  or from a device paired with it.", then Pair This iPad… from that panel: the switch comes back without
  reconnecting; away through Tailscale:
  dimmed with "…, or from a device near it." as before; VoiceOver on the dimmed switch (read as dimmed, then the
  footnote); mixed builds: this iPad against Sill for Mac 0.5.1 (no `sessionPaired`: the switch works, 0.5.1
  takes it from any session at home), and the 0.5.1 (4) iPad, unpaired at an open door, against this Sill.app
  (its switch goes back, "‹Mac› kept its setting").
