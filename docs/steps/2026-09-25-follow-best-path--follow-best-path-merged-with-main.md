**Follow-best-path merged with main after remote access (2026-09-25, branch
`follow-best-path`: merge of main at ba91136, PR #13, into 8e1e4e3, PR #12,
then main at b50e224, PR #11, merged at f863c74; neither a rebase; PR #12 is
main's cea195c).** A session at home follows the best path as the next entry
says; remote access works as its entries say. Where the two meet:
- A remote session (a saved Mac dialed through the remote door,
  `Session.route` `.remote`) is no candidate for the moves:
  `DiscoveryPolicy.PathInput.remote` (StreamClient sets it from the session's
  route) makes `pathPlan` keep it where it is whatever its path and the
  browser say, as it keeps a Direct session ("path: kept: a remote session
  moves only by the remote reconnect", `Keep.remote`). Its route word stays
  nil (#13), its end is never carried on by a move (`rescue` asks the plan),
  and it still never moves home to the network (a later step).
- The end of a session: `endSession` hands over to #13's `sessionEnded` (the
  words, `reconnect` by Mac ID or Bonjour name, the remote dial), which
  replaced `reconnectTo`. `connectionLost` first lets a move carry the session
  on (`rescue`: the stream screen stays), except after a goodbye (kind 22,
  "quit" at home: the session ends at once with its words, not after a
  rescue's dial to a Mac that is going; the reconnect waits too, see the
  review fixes below) and when this device closed the connection itself
  (`end`: a message no Sill sends). #13's `reconnectIfListed` never runs
  beside a move (`moveUnderWay`: a move, or a session one carries on, which
  stays `connected` until the move takes over or ends it). #13's liveness (no
  byte for 6 s) now ends a stranded cable connection too; the rescue then
  decides as for any other end. A connection already closed sends no pings
  (the fix-up after the merge): while a move carried its session on, it was
  still the session's, and its liveness reported it lost four times a second
  until the move ended (log lines, and `connectionLost` calls that did nothing).
- Dials: one row dial, #13's `dial(_:macID:)`, which carries prefer-cable's
  wired dial and its fallback; the moves keep theirs (`startMove` with
  `wiredDial`, or this branch's `wifiDial`), both for network rows only now
  that a row has a route (a Remote row is not Direct either) and an optional
  endpoint. `FoundMac.wifi` joined #13's initializer; `adopt` (a remote dial's
  winner) forgets the path state as `connect` does; `-SillPathTest`'s
  addresses go through #13's address parser first, then the split at the last
  colon.
- `SessionLink` is this branch's (hold, adopt, unhold, the chained fences):
  main had not changed it since 76366e8. `DiscoveryPolicy` is the union, plus
  the remote rule.
- Verified without devices: iOS Debug and Release for the simulator and Debug
  for the iPad (build only, not installed), only the old `StreamClient`
  capture warning; `swift build -c release`, and clean, only the CaptureProbe
  warning (Sources, Package.swift and Scripts were ba91136's byte for byte).
  Pure checks against the merged files:
  this branch's policy check 277 of 277 and its 61 mutants; main's 187 of 187,
  its 25 mutants (D1's text made unique: `wifiInterface` has the same guard)
  and the 20 older ones; the remote rule's 9 checks on top of the 277 (286:
  a 12,288-case grid, a model) and 9 mutants of it, 70 of 70 with the 61;
  remote access's rules check 64 of 64 and 35 of 35; the fence check's 12
  modes and 16 of 16 mutants. On a simulator of its own against the merged
  `SillHost --synthetic`, one host at a time (21 hosts, the longest 49 s):
  this branch's 18 scenarios as before the merge (refused-cable's other
  launch now a Python stand-in, so one real host suffices); remote access's
  pairing by link, a remote session by address that the plan keeps where it
  is (its "path: kept: a remote session…", no route word, no move) and, its
  host gone and back, the ordinary end and an automatic remote redial, no
  rescue; and close-slow (the connection closed over the cable, the cable's
  dial never answering, the row as listed never sending a list: the session
  ends 7.5 s later with #13's words), 66 of 66 checks. close-slow on the merge
  commit's own build printed "connection silent for 6 s: lost" seven times,
  0.25 s apart, until the move ended; with the fix-up, never. The first run
  stopped after four scenarios when Noah's iPad connected to Sill.app: that
  host had passed the check before it started and ran 24 s beside his stream,
  so the runner (`scratchpad/integrate-12/sim/simmerge.py`) now also kills its
  host the moment Sill.log shows a device connecting.
- Then main at b50e224 (PR #11, encoder recovery) merged at f863c74. Only
  CLAUDE.md conflicted: both Current-step entries kept, the best-path ones
  first; README merged by itself. Sources, Package.swift, Scripts and
  `HostSettingsPanel.swift` (its software-encoder callout) are b50e224's byte
  for byte, every other iOS file ed6b378's. Verified on f863c74's tree (the
  review's runs): iOS Debug for the simulator, only the old `StreamClient`
  capture warning; 70 harness photos at 1000x710 equal to b50e224's but for
  two spinners (connect-pairing, settings-pending: 176 and 178 px); the policy
  check 286 of 286 and 70 of 70 mutants, main's 187 of 187 and 25 of 25, the
  20 older mutants; remote access's rules check 64 of 64 and 35 of 35; the
  fence check's modes and 19 of 19 mutants. Not run on it: Release and device
  builds, and the simulator scenarios against its `SillHost --synthetic`,
  which now has b50e224's encoder recovery (the 21 hosts above ran ba91136's).
- Review fixes after the merges. After goodbye "quit" the reconnect no longer
  dials the Mac's row at once. The row outlives the goodbye by about a second
  (a receiver keeps a record 1 s past its goodbye, RFC 6762 §10.1; a stand-in
  for Sill.app's Quit, browsed on this Mac: gone 1.05–1.22 s after the
  connection ended, 11 of 11), and `sessionEnded` ran `reconnectIfListed` in
  the same main-queue turn, which took it (over the cable for a Wired row):
  "Reconnecting to ‹Mac›…" replaced "‹Mac› quit Sill." before it was drawn,
  and the dial waited on a Mac that was going (#13 alone did the same at
  home). Now a row listed since before the goodbye is left alone for 3 s
  (`DiscoveryPolicy.quitWait`; `reconnectRow`'s `quitAt` and `networkSince`,
  from `Reconnect.afterQuit` and `sightings`): the words stay; the row listed
  again (Sill is back) is taken at once by the usual rules (a Direct row after
  its own 6 s), and one still listed at 3 s (Sill relaunched within that
  second, a lost goodbye packet) is taken then. Any other end is as before.
  Verified: the policy check 310 of 310 (the merge's 286, and 24 for the
  rule: its cases, a grid of 17,820 against the old rule, a model of the
  glue) and the rule's 10 mutants; iOS Debug for the simulator, only the old
  `StreamClient` capture warning. No simulator scenario can show it: the
  synthetic hosts do not advertise, so no row lingers after their goodbye,
  and a session by address has no Bonjour name to reconnect by. DEBUG:
  `-SillMoveTest to:HOST:PORT` split HOST:PORT at its last colon itself, so
  `to:[::1]:P` listed the name "[::1]", which never connected (each try given
  up after 5 s); it now reads it as `-SillConnect` does (`address(_:)`: the
  address parser, then the split), and Build and run below names `other:PORT`
  and `-SillWiredTest` too. Verified on a simulator of its own against
  `SillHost --synthetic` built from the same tree (b50e224's host code), one
  host at a time (9 hosts, the longest 18 s;
  `scratchpad/integrate-12/apply-fixes/sim/simapply.py`): `to:[::1]:P`,
  `to:::1:P` and `to:fe80::…%en0:P` from 127.0.0.1 each list the address and
  move (the host sees the second connection; the scoped one reads its route
  again at the hand-over), and, as before, `-SillMoveTest 1`, a move's wired
  test, a plain session, close-slow (#13's words) and remote access's host
  gone and back (the session's end and the remote redial, which the quit fix
  runs through): 32 of 32 checks. The runner's app is signed to run locally:
  unsigned, the simulator gives it no keychain, and pairing stops at the
  device key (-34018) before it prints anything. Comments and docs: the
  harness contract in `ContentView` names `-SillSettingsEnd 1`,
  `-SillDeviceKeySE 1` and `-Sill.directWirelessMacs`, says the pairing
  arguments run under `-SillLive 1` too, and which remote settings cases are
  away from home (no route word) and which at home (Wi-Fi); `-SillWiredTest`'s
  comment says network rows (a Remote row is not Direct either);
  `address(argument:)` no longer repeats `address(_:)`'s paragraph. Left as
  it is here: README's "four source files", which main's PR #15 replaced
  (docs/DEVELOPMENT.md there says "its source files"). Verified on the last
  tree, comments only since the simulator run: iOS Debug and Release for the
  simulator and Debug for a device (generic, unsigned), only the old
  `StreamClient` capture warning; `swift build -c release`, only the
  CaptureProbe warning; on the same DiscoveryPolicy, SessionLink,
  RemoteDialPolicy, SavedMacs and StreamProtocol: the policy check 310 of 310
  and 80 of 80 mutants, main's 187 of 187 and 25 of 25, the 20 older mutants,
  remote access's rules check 64 of 64 and 35 of 35, the fence check's 14
  modes and 19 of 19 mutants. The branch still merges into main (1f3072a,
  after PRs #14 and #15) without a conflict.
- **Untested, for Noah:** the entries below on the merged build, and: a remote
  session at home with the cable plugged in stays remote (the console's "path:
  kept: a remote session…", the card's "through Tailscale"); Sill.app's Quit
  while the iPad streams over the cable gives "‹Mac› quit Sill." at once and
  keeps it, with no "dialing ‹Mac› on anpi0 (wired)" on the console before
  the row is listed again or 3 s have passed, and reopening Sill reconnects
  over the cable.
