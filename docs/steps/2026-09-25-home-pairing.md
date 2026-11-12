**Pairing at home (2026-09-25 to 27, branch `home-pairing` from main at
1f3072a, with main merged in at cf05a78, 2b38179 and da43f6b, not rebased,
PR #37; the plan and every step's results are in
`docs/home-pairing-plan.md`).**
Noah: "Yes please lets add a pairing process for Wi-Fi/Direct connect,
something easy to do but still secure, similar to how Tailscale is being
paired. Wired should still pair automatically." He also decided it ships
before 1.0 (the Compatibility floor below).
- The Mac: Sill.app's home door, the Bonjour port, speaks the remote door's
  TLS 1.3 with both keys pinned (the same identities, the ALPNs `sill/1` and
  `sill-pair/1`, the trust list and the pairing window), and so does
  `SillHost --pairing`; admission is one `Door` behind both listeners, its
  rules `DoorPolicy`'s. An unpaired device's tap sends one "pair me" request
  (kind 19 `ask`). Over the USB cable to an iPhone or iPad, while the Mac is
  unlocked and both ends agree the connection is the cable (the Mac: an IPv6
  link-local source under an Apple iPhone's or iPad's NCM interface in IOKit,
  never one of the Mac's own addresses; the device: its end carries only
  link-local addresses), the Mac pairs it on the spot, one key per device by
  a hash of its USB serial, with a 10 s notice that has Remove. Anywhere else
  the Mac opens its pairing window by itself, in front but without activating
  Sill or taking the keyboard, never for an ask from this Mac itself, at most
  one at a time, three in 10 minutes, and none for 10 minutes to a device
  after the Mac's Cancel or five wrong codes; the device scans the QR code or
  types the 12 digits, as it pairs for remote access, over the home door. One
  trust list serves Wi-Fi, Direct, the cable and remote access. Settings ›
  Devices (a new tab after General): Require pairing (on by default; off, any
  device at home connects without pairing, still over TLS; kept beside the
  trust list in the login keychain, its "off" signed by the Mac's key, never
  in UserDefaults), the paired devices moved from Remote Access (how each
  paired and last connected, Remove, rename) and Pair iPhone or iPad…. The
  menu: "‹device› Wants to Pair", "An iPhone or iPad Needs Sill Updated" (a
  source's third plain try in a minute) and "Devices Can’t Connect" (the
  keychain unusable: the home door stays closed). Sill.app takes no TEST ONLY
  hook that bears on the doors or pairing (TestHooks: one "ignored" line
  each). The CLI's default door stays plain (the parity baseline): `--pairing`
  opts in, `--print-cable` prints what the cable rule reads.
- The device: every connection to a Mac goes through one TLS builder
  (`DeviceTLS`), taps, reconnects, the wired dial and PR #12's moves
  included, and a session at home counts as connected at its first window
  list. Rows: a saved Mac's method word; "Not paired" (not saved, removed, or
  a Mac that lets any device in); "Wired" for an unpaired Mac over the cable,
  which pairs by itself; "Update Sill" for a plain door in Release, and for a
  Mac seen over TLS whose row lost its `p` (no downgrade). A tap on "Not
  paired" asks, then the home card (the scanner, or Enter Code Instead). A
  goodbye `removed` or `pairingRequired` ends the session with its words
  ("‹Mac› removed this ‹iPad›. Tap it to pair again.", "‹Mac› now asks
  devices to pair. Tap it to pair this ‹iPad›.") and no reconnect. A DEBUG
  build still dials a plain door (the CLI's, a Sill.app from before this
  branch) until it has seen that Mac over TLS (`-SillForgetHomeTLS 1`
  forgets); a device from before this branch can no longer connect to this
  Sill.app at home.
- Merged with main three times, not rebased. d11aa60 (cf05a78, PRs #16 to
  #28): the device gate in `Door` for both TLS doors, the hello first inside
  TLS, `DoorPolicy.afterGate`, `SillProtocol` 1 as this door's `sill/1`, the
  pure checks into `Tests/checks` and CI. 691b93e (2b38179, PRs #29 to #33):
  the tick keeps both rules (a kind 26 stands in for a device's tick; a TLS
  client skips one right after a send, and one on the cable gets none); main's
  `SILL_TEST_LOOPBACK` binds both TLS doors (`makeListener` takes the TLS
  options and the loopback flag) and is among TestHooks' door hooks; one
  `SILL_TEST_SOFTWARE_ENCODER`, main's (`PointerTestHooks`), this branch's
  copy gone; the checks' lists united (27, 26 with mutants). The third
  (da43f6b: PRs #34 remote pacing, #35 the first-run tour, #36 the Mac's
  menus, #38 the trackpad gestures; the plan's Results, "The merge with main
  after PRs #34 to #38"): #34's byte budget stays the remote door's
  (`paceRemote`, the bytes `send` counts, the remote sweep's keyframe), and a
  TLS home session keeps the home rule, as #34 left home sessions; kinds 24,
  25, 27 and 28 reach the coordinator from every door; the device reads every
  session connection, TLS at home included, with `MessageReader`; the tour's
  session starts in `markConnected` (a plain door's `.ready`, a TLS session's
  first window list), the menus subscribe after `homeSessionReady`; gestures
  stay dry, and SILL_TEST_HOTKEYS read, on every host that does not advertise
  (`synthetic`: `isTestHost` since this branch also leaves out Sill.app's own
  executable, which would have posted a chord in test pattern mode); the
  Settings panel ends with Away from home, This iPad's gestures, then Take the
  Tour; the floor names kinds 0–28 inside `sill/1`; `Scripts/pacing` builds
  against the merged StreamServer (its host set has the Door's files, and
  main.swift calls `serve` either way, `PACING_SERVE_BEFORE_HOME_PAIRING` for
  an older base); the checks' lists united (33, 32 with mutants).
- Review fixes (2026-09-27, ae2e228 to 1d95c6d, one commit per theme; the
  plan's Results, "The review fixes"). Three lenses confirmed 13 findings; a
  fourth, pairing's security, was read again from the code (one more). The
  floor: a host offers `sill/1` and `sill-pair/1` for good and refuses a 1.0
  device inside `sill/1` with "update"; it freezes the TXT keys, the pairing
  exchange, kind 19's `v` and kind 20's reasons, with an optional `message`
  for a reason a device does not know. The Mac: an expiry and a device's own
  Cancel (kind 19 "cancel") quiet nobody; "‹device› Wants to Pair" ends when
  that key pairs; "An iPhone or iPad Needs Sill Updated" waits for the third
  plain try; a device-opened window announces its first line; Require
  pairing's stored "off" is "0." and a signature by the Mac's key
  (`RequirePairingValue`), and the trust list exists from the first launch.
  The device: a tap on a tagless row under a saved Mac's Bonjour name dials
  that Mac pinned (`DiscoveryPolicy.rowMac`); an open door's row reads "Not
  paired"; kind 18 names the session's Mac only when the connection's own
  key signed it, and "removed" revokes only from a session pinned to that
  Mac; the reconnect ends at a door that now asks devices to pair; Pair This
  iPad… asks on its own `sill-pair/1` connection and says what the Mac
  answered; "Paired with ‹Mac› over the cable." stays until the session
  comes; `StreamClient+Home.swift` is A601/F601 in the project file.
- Verified (the plan's Results, step by step: H0 to H18, S1 to S7, the
  merges' and the review's gates). At the second merge:
  `Tests/checks/run-all.sh`, all 27; the mutants of the 16 checks whose
  sources it changed from both parents (StreamProtocol's), 419 of 419 caught;
  `swift build -c release` clean from `git archive`, only the CaptureProbe
  warning; iOS Debug and Release for the simulator and Debug for a device,
  only the old `StreamClient` capture warning (StreamClient.swift:2861),
  Release's Info.plist with `_sill._tcp` alone and none of the harness's
  arguments in its binary; live on the merged CLI, 23 of 23: both TLS doors
  and Direct Wireless's rebuilt listener on 127.0.0.1 alone under
  `SILL_TEST_LOOPBACK`, one software-encoder line, pairing by the link and by
  an ask and the code, the hello inside TLS, the remote door serving the key
  paired at home, input's ticks over TLS (33 a second) and on the plain door
  (34), a plain device refused; a private simulator against it, 6 of 6: an
  unsaved Mac's ask answered `shown`, the link scanned in the home card, a
  pinned session with its hello, and after a relaunch the saved Mac dialed
  pinned with no ask. Every host on the software encoder, nothing streamed.
- Verified at the third merge (the plan's Results): `swift build -c release`
  from clean, only the CaptureProbe warning; iOS Debug and Release for the
  simulator and Debug for a device, unsigned, only the old `StreamClient`
  capture warning (StreamClient.swift:2989); `Tests/checks/run-all.sh`, all
  33; the mutants of the 18 checks that compile the whole of StreamProtocol,
  497 of 497 caught; the CLI's stdout (the plain door, idle and with a client)
  identical to both parents', masked and sorted; live on the merged CLI, 25 of
  25 (the menus' subscription and two gestures, logged and not posted, over
  the TLS home door, the remote door and the plain one; a remote session and a
  TLS home one streaming on the software encoder); the pacing harness against
  main, every gate passing, home no worse (three runs of three), bigkf8 at its
  base's 59.8 fps with nothing dropped; a private simulator against it, 13 of
  13 (pairing, "menus: none" over TLS, the tour 1.06 s after the first picture
  of a TLS session, two gestures through `sendGesture`). Every host on
  127.0.0.1 alone and the software encoder.
- Noah tried PR #37 on his iPad and iPhone against its Sill.app (2026-09-27,
  before the third merge): "home pairing looks good!", and asked for it to
  merge after PRs #34 and #38. The P1–P16 list below was not reported item by
  item.
- The review of the third merge (2026-09-27, 4889e62 and the six commits after
  it; the plan's Results, "The review of the merge"): eight findings, each
  checked here and fixed, one commit per theme. The host: `serve` marks a
  session TLS by its route (`route.encrypted`), so the pacing harness's plain
  home client keeps the plain door's tick rule again (every session a Door
  admits is TLS, as before). The device: the automatic reconnect's own dial
  that is not ready 5 s after it started is let go and the reconnect looks
  again (`StreamClient.reconnectDialWait`): a row dialed as its registration
  went (Sill.app gone without a goodbye) left the Bonjour resolve waiting for
  good and held the reconnect, its remote dial included (on the branch before
  the merge; main's guard is the same). Docs: `-SillPairURL` pairs at a link's
  own addresses only; docs/app-store-metadata.md describes pairing at home
  (the download it needs, export compliance, the review notes, the
  description, the demo video, the screenshots); Pair This iPad… is in Away
  from home; the floor's kinds 19 and 20 are `sill-pair/1`'s; the mutants' 32
  jobs and their cost. Verified: `swift build -c release`; iOS Debug and
  Release for the simulator and Debug for a device, only the old
  `StreamClient` capture warning (StreamClient.swift:3011);
  `Tests/checks/run-all.sh`, all 33 (no check compiles a changed source); the
  pacing harness's `home` case 268 ticks in 8 s against its base's 267 (15 on
  the merge) and its gate passing; a TLS home session still on the TLS tick
  rule; on a private simulator the merge's build never reconnected to a host
  back under another name, nor dialed remotely with none (4 of 7), and this
  build did both (7 of 7), the tour's reconnect rule holding across the let-go
  (9 of 9).
- **Untested, for Noah:** the plan's §11, P1 to P16, on his devices, the iPad
  build first (Debug, the usual route), then Sill.app: P1 the upgrade (the
  iPad, paired for remote access on 2026-09-25, connects at home with no
  step; the log's "Home door: TLS, pairing required (1 paired)."); P2 the QR
  code over Wi-Fi (Remove it first; the window comes up in front while typing
  goes on; under 20 s); P3 the typed code; P4 the cable (Remove, plug in, tap
  the "Wired" row: no code, the Mac's notice, "over the USB cable" in
  Devices; pull and plug while streaming); P5 locked (⌃⌘Q: "Unlock Mac mini,
  then tap it again."); P6 Direct at the café (the hotspot, `%awdl0`); P7 an
  older build ("An iPhone or iPad Needs Sill Updated"; it retries, the known
  limit); P8 Remove while streaming; P9 the moves, each hop over TLS; P10 a
  stranger's taps (the Mac's Cancel, then 10 minutes of "didn’t show a
  code"); P11 the cost (rtt maxima on Wi-Fi, the cable without ticks,
  Extreme at 120 fps, Sill.app's CPU); P12 remote after a home pairing; P13
  Require pairing off, then on again; P14 VoiceOver (the rows, the card, the
  Mac's window); P15 a USB Ethernet adapter reads "Not paired"; P16 the
  iPhone's hotspot over USB gets the code window. Also: Sill.app's first
  launch makes the trust list in the login keychain when it has none, and
  Require pairing off then on again saves (the keychain store's own writes
  ran nowhere else); Pair This iPad… over an open door says "…is showing a
  code now." only when the Mac shows one, and its Cancel closes that window.
  After the third merge, which no device has run: a fresh install's tour
  after pairing at home, and its reconnect rule (the tour's P13) across a
  TLS reconnect; the Mac's menus and a three-finger gesture over a paired
  session at home; Force Quit Sill.app while the iPad streams (no goodbye),
  reopen it 10 s later: "Reconnecting to ‹Mac›…" meanwhile (the console:
  "reconnect: ‹Mac› not ready in 5.0 s …" about 5 s after the loss), and the
  session back soon after Sill is; with Remote Access on and Sill left
  closed, a remote dial about 10 s after the loss.
  When this ships: the site's words (privacy.html says connections at home
  are not encrypted, as Sill for Mac 0.3.1's are; index.html and support.html
  pair only for Remote Access), and the README's sentence on 0.3.1.
