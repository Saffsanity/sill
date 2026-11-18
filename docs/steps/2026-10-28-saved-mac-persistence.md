**A saved Mac gone after a force-quit (2026-10-28, PR #224 by addhumal, branch `saved-mac-persistence`,
main at 6c5b5d24 in it; issue #140).** ZainnQureshii (iPhone 16 Pro Max, iOS 27.0.1, Sill 0.5.1 from
the App Store, Tailscale at home and away): after pairing with the QR code and swiping Sill away, the
Mac is absent at the next launch and the code must be scanned again each time; Sill for Mac logs a
new `sill-pair/1` pairing at every relaunch. Device only, no wire change.
- The cause, from the code and a model (remote-rules' `launch.swift`): the record is written at the
  pairing (`storeSavedMacs`, before the session), and cfprefsd keeps it through a SIGKILL (a private
  iOS 27.0 simulator against a loopback `--remote --pairing` host: kept on main, killed 0.1 s and
  3 s after the pairing, the remote door's path and the home door's). The only launch path that
  empties the list is `startRemote`'s clearing, run only when the Keychain says there is no device
  key (`knownMissing`, meant for a restore from another device's backup). So on that iPhone the
  device key, made at each pairing, was not found at the next launch (never kept, or kept and not
  found by the tag query): each launch cleared the list, and the next pairing made a new key that
  the Mac trusts as one more device. Not reproduced here; the Mac's log names each pairing's key
  ("Paired ‹iPhone› (key XXXXXX…)"): a different one each time is this cause.
- #224 as submitted: a Keychain mirror of the saved Macs and `CFPreferencesAppSynchronize` (for a
  SIGKILL that loses the write: measured not to, it would lose the Mac once, never at every launch,
  and the mirror cannot stop the clearing, which runs whatever the list came from; it could also
  bring back a Mac forgotten while its write failed), `AfterFirstUnlockThisDeviceOnly` for the key
  (a security change, not the cause), `knownMissing` reading the key first (the same query), a
  read-back in `makeKey` (the one part aimed at the cause), and the scanned link's addresses on a
  record paired at home. Kept, as maintainer edits: the read-back, as rules (`DeviceKeyPolicy`,
  SavedMacs.swift, pure): a key made only when the Keychain says there is none (another failed read
  fails that pairing or dial: before, it put a second key under the tag); a key made used only once
  the Keychain gives back this very key under the tag (else one explicit add, else the pairing fails,
  "This iPhone couldn’t make its key (the Keychain didn’t keep it: ‹status›).", and the key is
  deleted again); the launch's clearing as before, through the same rules. And the link's addresses
  and port on a record paired at the home door until a verified kind 18 (`SavedMacs.applyingLink`),
  without #224's other change there: the ask's and the overlay's targets still never fall back to
  the link's addresses. The mirror, the synchronize and the accessibility change are out.
- Verified: `remote-rules` 172 (28 new: the rules case by case, a launch with each fault in turn,
  4,000 random lives) and 88 of 88 mutants (12 new, two of them the rules before this change),
  `home-records` 46 and 27 of 27, `home-model` 76 and 25 of 25; `run-all.sh`, all 55; iOS Debug for
  the simulator (CI's command), Release for the simulator and Debug for a device, only the known
  `StreamClient` capture warning; on the private simulator, this branch as main (kept after the
  SIGKILLs; the console's "device key: made 5KVZV9…, given back by the Keychain" beside the Mac's
  "Paired … (key 5KVZV9…)"), a home pairing killed at once keeping the link's five addresses and
  port 47224 (main's: none, 7455), and an unsigned build's pairing ending "This iPhone couldn’t make
  its key (the Keychain didn’t answer: -34018)." with nothing sent. The report, the drafts for the
  reporter and addhumal and the evidence: `~/Downloads/sill-handoff/triage/2026-10-20-reports/
  verdicts-2026-10-28/pr224-report.md`.
- **Untested, for Noah:** on the iPad mini (iPadOS 27.0.1, the reporter's) with a Debug build of this
  branch: once with `-SillForgetMacs 1` (the saved Macs and the device key gone; then remove it), Add a
  Mac… and the code: the console's "device key: made XXXXXX…, given back by the Keychain" and Sill.log's
  "Paired ‹iPad› (key XXXXXX…)" alike; swipe Sill away, open it: the Mac listed, its session without a
  code (this is the making path, which no device here has run on 27.0.1: a key is made once). At home,
  a tap on the row and the code, Sill swiped away at once: the Mac listed, and its Remote row dials
  through Tailscale. With the reporter: the key names in Sill.log, and this build's word at pairing.
