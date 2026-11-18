**Remote access merged with main (2026-09-25, branch `remote-access`: merge
0f7f50d of main at 76366e8 into 7f5f19d, not a rebase; the fix-up after it is
ee922db, the review's fixes 7200334–e8c7490).** Main's PRs #6–#10 (the Direct
Wireless fixes, the connect screen's Wired/Wi-Fi/Direct, the quality presets,
the route in Settings, prefer-cable) now sit beside remote access. Where the
two meet:
- Presets: seven, ascending, Low (4 Mbps) first, then Efficient 8, Balanced 15,
  High 25, Pro 40, Ultra 80, Extreme 150; main's 200 Mbps cap. A device may pick
  all seven (`SettingsChoices`); a host from before either change refuses the
  new ones and an older device shows them as Custom.
- The Mac card: `HostStatusSnapshot.Device.route` is main's home link
  (ClientLink: Wired, Wi-Fi, Direct) and `remoteRoute` the remote door's label
  ("through Tailscale", "over the internet", "by address"). `StatusText.routeWord`
  is the one place the card picks the word: the remote label first (its link
  would read Wi-Fi for a session over the internet), on the device's row and,
  while it is the only device, the source row after the Mbps, with no-break
  spaces so a wrap never splits it. `remoteDeviceCount` counts `remoteRoute`.
- StreamServer: the remote door's register-at-ready and origin gate carry main's
  link, read at registration and on path updates (a remote session gets none);
  Direct Wireless off disconnects only home clients on peer-to-peer Wi-Fi (the
  remote door never listens there, and who reaches it is Remote Access's).
- The device: `FoundMac` has the remote branch's route (network, direct,
  remote) and Mac ID with main's `method` and `wired`; a row ends in "Remote" or
  its method word (`FoundMac.word`, also for VoiceOver). `StreamClient.route`
  stays main's link word (the readout); a remote session's way in is
  `remoteRoute` (the route line, the 60 fps request, the slow-link callout), and
  it has no link word. The reconnect is the remote branch's (`reconnect`, saved
  Macs by Mac ID, then remote dials) with main's Direct-row rule (`directWait`,
  and `networkGrace` from the sightings; a remote dial's `networkGrace` counts
  from the same moment, the saved Mac's row going, in `savedSightings`, the
  sightings by Mac ID); every row dial, a tap's or the reconnect's, goes
  through `dial`, so a "Wired" row dials the cable first. The move to the
  network keeps its SessionLink fence and sets the session's route to network.
  `-SillConnect` takes `[::1]:P` (the address parser) and
  `fe80::…%en0:P` (split at the last colon). In the project file main's
  SessionLink keeps A015/F015 and DeviceIdentity moved to A01D/F01D.
- Verified without devices: `swift build` (only the CaptureProbe warning), iOS
  Debug and Release for the simulator and Debug for the iPad (only the
  StreamClient capture warning), `make-app.sh` without `--install`. Pure checks
  against the merged files: main's policy check 187 of 187 (main's own count
  at 76366e8) with 45 of 45 mutants (its 25, and the 20 older ones re-applied as
  text); the remote rules, RemoteDialPolicy and SavedMacs 60 of 60, 33 of 33;
  AddressList and PairingWindow 41, 15 of 15; OriginPolicy 66, 10 of 10; the
  protocol 188 and its 8 openssl cross-checks, 20 of 20; ClientLink 89, 14 of
  14; the SessionLink fence in its four modes, 5 of 5; the ledger check
  extended to seven presets (Low's own block, and an older host refusing Low,
  Ultra and Extreme in the random model) 90 with 5,000 runs, 3 of 3; the wire
  read and written across a9cc248, main, 7f5f19d and the merge, 16 of 16. The
  CLI's output, idle 35 s and with one client, masked and sorted, is main's and
  7f5f19d's. Previews against main differ only in the remote branch's own
  (36 files, and menu.txt's Low, Remote Access… and Pair iPhone or iPad…);
  against 7f5f19d only in main's (the route words, "still", the Streaming
  footer, the presets, the still-window card) and the remote-device card's
  source row, which now ends in "through Tailscale". Live on loopback: Extreme
  restarts at 150 Mbps and 200 is refused; Direct Wireless on and off keeps the
  port; pairing, a paired session and an unpaired key refused at the remote
  door; both doors at once, where Direct Wireless off (the en0 stand-in)
  disconnects a home client on this Mac's en0 link-local address and not a
  remote session from the same address, and the remote door's port never
  changes (a build without the remote-session guard fails this); the home
  door's caps and origin gate; the bare app's `-SillSetAfter` bitrate, Direct
  Wireless and Remote Access (one Settings line each, one restart in all),
  saved across a relaunch. On a simulator of its own: by address, the route
  word read; `-SillMoveTest 1` moved and fenced; `-SillPairURL` pairing and a
  remote session; the host gone and back, redialled remotely.
- Review of the merge (2026-09-25, after 3a7b501). Fixed: a lost saved Mac's
  automatic remote dial counts `networkGrace` from the moment its network row
  went (`StreamClient.savedSightings`, DiscoveryPolicy.sightings by Mac ID); it
  read `networkLastListed`, the last browser change while the Mac was listed
  (often the connect), so a Mac that blinked off the network at home was dialled
  through the remote door 3 s after the loss, and a remote session that wins
  that race is never moved home (the bug was on 7f5f19d already). The move's
  probe (main's `probeMove`) takes §3.7's caps (frames 32 MiB, anything else
  4 MiB: it closes, which ends the move) and, like `readPayload`, never keeps a
  message cut short. The panel's route line keeps its route whole when it wraps,
  as ee922db does on the card: at xxLarge on the 340 pt panels "Connected" /
  "through Tailscale · 48 ms", where the merge's no-break space before the "·"
  alone gave "Connected through" / "Tailscale · 48 ms". Two stale doc comments.
  Verified: a clean release build of the result (only the CaptureProbe warning),
  iOS Debug for the simulator (only the capture warning); the remote rules check
  64 of 64 (four new: the sightings by Mac ID, and the dial after an hour
  listed) with 35 of 35 mutants (two new, on the leave), main's policy check 187
  with its 25 and the 20 old mutants; an event model of the reconnect on these
  files: with the row gone at the loss the first remote dial moves from +3.2 s
  to +10.0 s (Sill quitting: +8.0 to +11.0 s), what the by-name sightings give;
  the probe copied verbatim into a loopback harness: Sill's traffic probed as
  before, an SSH banner and a 1.7 GB frame header closed at once (before, both
  held the move until its 5 s ran out, the second with the harness at 534 MB), a
  window list cut short and then the stream's end no longer taken as the Mac's;
  the CLI's output idle and with a client, masked and sorted, main's; on a
  simulator of its own `-SillMoveTest 1` and `to:` this Mac's `fe80::…%en0`
  (moved and fenced, the second gaining "Wi-Fi" at the hand-over),
  `-SillPairURL` pairing, a remote session and its automatic redial; 63 photos
  of the route line (seven layouts, three text sizes) identical to 3a7b501's but
  for the six at xxLarge on the 340 pt panels, and long VPN names wrap at the
  route's words, never inside one. The review's reruns on 3a7b501, none failing:
  on the simulator S4 and S5 13 of 13, S7 against a9cc248's host, S8 in short
  host runs (typed pairing through the relay, 60 fps through a VPN route and 120
  by address, the 300 ms callout), testS3OutsideLink and the three RF2 UI tests
  (the link test's Mac A a stand-in, not a second host), `-SillConnect` by this
  Mac's `fe80::…%en0` ("Wi-Fi") and `-SillMoveTest to:` it; the host gates
  H7–H12, H10(f) on the bare app, H15, H17 and a variant with `--remote` through
  Direct Wireless off (a fresh tag, only the scoped home client disconnected,
  the remote session streaming on), H18 and H19, and H14 (no base run), H16 and
  H20 shortened to keep each host under 60 s; main's Direct Wireless gates
  nohook, burst and appfail (the app's failed replacement disconnects the en0
  stand-in and keeps a paired remote session from the same address; a build
  without the guard fails it).
- **Untested, for Noah:** everything the entries below leave for the devices,
  now on the merged build, and in particular a remote session's card on the
  real menu (the label on the source row is a merge decision), a "Wired" row's
  reconnect after a loss (it goes through `dial` now), and the move to the
  network with remote access on. The grace: at home with a paired Mac and
  Remote Access on, quit Sill.app while the iPad streams and reopen it 7–10 s
  later; the iPad should come back on the home door (the host logs no remote
  client).
