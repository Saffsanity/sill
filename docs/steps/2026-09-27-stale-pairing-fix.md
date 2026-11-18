**A Mac set up again: pairing again, not "Connecting…" for ever (2026-09-27, branch
`stale-pairing-fix` from main at d30fca8).** Noah, right after 0.4.0: "First pairing doesn't seem to
work. When I click Wi-Fi, it says Connecting to Noah's MacBook Pro... and never updates. It does
work when I click Add a Mac... manually". Sill for Mac 0.4.0 made the Mac a new key and a new
recognition key (the data-protection keychain, no migration, #42). The iPad's row carried a tag no
saved record resolves, under the saved Mac's Bonjour name, so `rowMac` took it as that Mac by name:
it read "Wi-Fi" and a tap dialed pinned to the old key. The pin refused the new key, and a
connection to a Bonjour service whose pin fails is never reported: it goes back to preparing and
tries again, with no `.waiting` or `.failed`, and the Mac logs nothing (reproduced in a simulator
against a loopback synthetic host set up again, 50 s of "Connecting…"). Device only, no wire change:
- `rowMac(tagged:carriesTag:…)`: the name rule only for a row with no tag at all (a Mac with an
  identity always advertises one, whatever Require pairing, Remote Access or its paired devices);
  a row whose tag names no saved Mac is not one. Under a saved Mac's name (`otherTagUnderSavedName`)
  it is dialed as a door that requires pairing (`rowDoor`: p=0 too), so a tap asks and the Mac proves
  itself with its code, never any key (a look-alike could make up a tag to shed the name rule). The
  reconnect never takes such a row for a saved Mac (`reconnectMatches`).
- `DeviceTLS.options(onPinRefused:)`: the verify block says when the pin refused a key; a session
  dial and the ask's `HomeDialer` end there as at `.waiting(-9808)`. With no other row of the saved
  Mac (`afterPinRefused`), it is paired again: `SavedMac.newKey`, "‹Mac› has a new key since this
  ‹iPad› paired. Tap it to pair again.", no reconnect, its rows "Not paired", a tap asks with any key
  (`homeDial`'s `newKey`), and the pairing replaces the old record (`SavedMacs.replacingNewKey`). The
  reconnect's row taken by its name alone is only skipped, as before. A pinned ask that meets
  another key does the same.
- Every dial that is not the automatic reconnect's (a tap, the session after a pairing,
  `-SillConnect`) ends after `DiscoveryPolicy.tapDialDeadline` (10 s) with `HomeCopy.noAnswer`'s words;
  the reconnect keeps its 5 s.
- Checks: `home-device` 182 and 124 of 124 mutants, `home-model` 62 and 21 of 21 (the mutants whose
  lines moved follow them, in remote-rules too).
- Verified on a private simulator ("Sill stalepair", deleted after) against `SillHost --synthetic
  --pairing --remote` on loopback (software encoder, `SILL_TEST_SERVICE_TYPE=_silltest._tcp`, the
  identity in `SILL_TEST_REMOTE_DIR`): paired at the home door, then a second host with a fresh
  identity and the saved record's Bonjour name set to its name (`-SillTapRow`). Before: "Connecting
  to…" for 50 s, nothing on the host. After: the row "Not paired", a tap asks, the host's pairing
  window opens. With the record's recognition key set to the new host's (a tag-named row, the old
  pin): the pin refused at once, the new-key words; the next tap asks, the code pairs, the old record
  is gone. `-SillConnect 192.0.2.1:9`: "didn't answer" at 10 s.
- **Untested, for Noah:** on the iPad with 0.5 (3): the Mac's row reads "Not paired" while the old
  record is saved, a tap brings the pairing window up on the Mac, the code pairs and connects. Known:
  that pairing starts from an unsaved row, so the old record stays until it is forgotten (its Remote
  row says it is not the Mac this iPad paired with); only a re-pairing from a row marked `newKey`
  replaces the record it came from.
