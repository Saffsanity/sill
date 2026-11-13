**A Mac's row keeps its TXT record when the cable goes (2026-10-27, branch `cable-unplug-row` from main
at 74d099c, PR #232).** Noah, on the iPad mini's connect screen with the iPad on the Mac's USB cable: the
row read "Wired", and from the moment the cable came out "Update Sill", for good. The console (Debug):
`discovery: Noah’s MacBook Pro: Wired, seen on anpi0 (wiredEthernet), en2 (wiredEthernet), en0 (wifi)
(p=1)`, then `…: Wired, seen on en2 (wiredEthernet), en0 (wifi) (saved Mac H6WQ… by its name
alone)`, then `…: Wi‑Fi, seen on en0 (wifi) (saved Mac … by its name alone)`: iPadOS listed the same
result on the interfaces left with no TXT record at all, so `rowMac` took the row by its name alone,
`HomeDoorTXT.door` read a plain door and `rowWord`'s no-downgrade rule said "Update Sill" for a Mac seen
over TLS (a tap dialed nothing; by the same rules the saved Mac's Remote row came beside it). Device
only, no wire change.
- The rule (`DiscoveryPolicy.rowRecords`, pure, `RowRecord`, `RowRecordKey`): a row is read with its
  result's own record (`r`, `p`), else the last one that result carried while the same browser has
  listed it without a break; a record that comes replaces it, whatever it says; a result that leaves the
  browser's results is forgotten (the browser's removal is the break, no timer). Kept records are keyed
  by the browser that delivered the result and the service's name and domain, so a browser made again
  (back from the background, after a failure: issue #69) starts afresh: its results are read with what
  it delivers itself, and the old one's records serve only the old one's results while they are shown
  beside it. A row never gains a door no record gave it; a tap and the reconnect dial by `homeDial` as
  before (pinned over TLS, never plain for a Mac seen over TLS); a Mac really back on a plain door, or
  another service under its name, reads "Update Sill" once listed afresh; a result never listed with a
  record reads as a plain door, as before. Known: within one browser's listing, a removal it never
  reports (a lost goodbye, a removal and a registration in one report) leaves any recordless service
  that then answers under the name read with the old record: as the Mac its tag names, whose Remote row
  is hidden and automatic remote dial held back while it is listed, dialed pinned (never plain), and
  marked `newKey` by a TLS answer with another key when no other row of that Mac is listed
  (`afterPinRefused`, as for a refused tag-named row).
- Glue: `StreamClient.record(of:)` (nil for metadata other than `.bonjour` and for an empty record) in
  place of `tag(of:)` and `door(of:)`; each browse result carries the number of the browser that
  delivered it (`Listing`, `browsersMade`), `recomputeMacs` keeps one `rowRecordMemory` by
  `RowRecordKey` and reads every row (by the result it is built from) and the `homeTLS` marking through
  it; the DEBUG test rows (browser 0) carry a record of their own. The `discovery:` line adds "(TXT
  record kept: this result carries none)" or "(no TXT record)", and a plain door's word, "(no p, Update
  Sill)".
- The review of #232 (2026-10-27, after 6eb6602; main at b4caa91 merged in by then): a kept record
  survived a browser made again (the old results kept beside the new one's, the records keyed by name
  alone), so a service that took M's name with no record while Sill was in the background read as M by
  its old tag (M's Remote row hidden, its remote dial held back, a refusal of the pinned dial marking M
  `newKey`) where main reads "Update Sill"; now keyed by browser as above. A name in two domains was one
  record for two results; now each result has its own. The checks' two comments naming `door(of:)`.
  Left as main has it (read from the code, not run): back from the background the automatic reconnect
  dials at once from the old browser's last results, trusting their own records (issue #69's settle), so
  a TLS service with another key that took M's name meanwhile can still mark M `newKey` in that moment.
- Verified (after the review's fix; main at 3c25748 (#117) and 3b54637 (#234) then merged in, which changed
  none of the files the four checks of DiscoveryPolicy.swift compile): `home-device` 209 checks and 131 of
  131 mutants, `home-model` 76 and 25 of 25, `policy` 464 (`records.swift`) and 165 of 165,
  `remote-rules` 144 and 76 of 76, one mutant run at a time; on the merged head `run-all.sh`, all 55,
  `swift build -c release` (only the CaptureProbe warning) and the three iOS builds on Xcode 27.1 (Debug
  for the generic simulator as CI builds it, Release for the simulator, Debug for a generic device), only
  the known `StreamClient` capture warning. Live on private iPad mini simulators
  (iOS 27.0, deleted after) against `SillHost --synthetic --pairing` under `_silltest._tcp` on loopback,
  paired at the home door. The cable's shape: `dns-sd -R` of the host's name was renamed "(2)", so a bare
  PTR record of it (a scratch `DNSServiceRegisterRecord` tool, lo0, no SRV or TXT) kept the name listed
  once the host was killed, without a record (the simulator's browser lists a new name only once its TXT
  record answers, and keeps a listed one whose record went): origin/main's build `(saved Mac … by its
  name alone)`, "Update Sill", "… runs an older Sill…", the Remote row beside it, nothing dialed; this
  branch `(p=1) (TXT record kept: this result carries none)`, the row as before, no Remote row, the
  reconnect dialing over TLS, pinned (failing there, never plain), and once the name went and a plain
  registration of it came (`dns-sd -i lo0 -R` to a plain host), "Update Sill", nothing dialed, before
  and after the review's fix. The review's case: `-SillBrowserFail 1` (the network browser reported
  failed, cancelled, made again a second later), and meanwhile the TLS host killed and its name
  registered with no TXT record for a plain host: 5c69075e's build read it as M (`(p=1)` kept, no word,
  no Remote row); this one `(… by its name alone) (no p, Update Sill) (no TXT record)`, "Update Sill",
  M's Remote row, nothing dialed. Not live: a tap then (no UI input here; the checks have it).
- **Untested, for Noah:** a Debug build on the iPad mini, Sill.app on the Mac, the connect screen with the
  cable in, then unplugged: the `discovery:` lines keep `(p=1)` with "(TXT record kept: this result carries
  none)", the row reads "Wi‑Fi" (no "Update Sill", no Remote row) and a tap connects; plugged in again,
  "Wired"; the same while streaming over the cable. And a plain CLI host under the saved Mac's name: quit
  Sill.app and run `swift run -c release SillHost` (no `--pairing`) on that Mac: the row reads "Update
  Sill" and a tap dials nothing; the same with the switch made while Sill is in the background on the
  iPad (the console's "browser: rebuilt the network browser (back from the background)"): back, the row
  reads "Update Sill" with the Mac's Remote row beside it.
