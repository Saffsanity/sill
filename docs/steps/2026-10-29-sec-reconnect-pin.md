**An open door's reconnect pinned to the key it saw (2026-10-29, branch `sec-reconnect-pin` from main at
150479b5, PR #255; the security scan's finding 3, Medium; Noah's go of 2026-10-29 for the batch).** The device's
automatic reconnect to a Mac it was connected to without pairing (Require pairing off, `p=0`) found the row by its
Bonjour name alone and took any key, so whatever advertised that name with `p=0` (another Mac renamed to it, a
stranger after a crash) got the session with no tap: what the device typed, and its clipboard (kind 32, on by
default). Device only, no wire change, nothing on the Mac.
- The rule (DiscoveryPolicy, pure): `reconnectKey(lost:)` is the key an open session's first connection saw
  (`trust(_:readyWith:)`), carried as `Reconnect.openKey` (`lostReconnect`); `reconnectTrust(_:savedPin:seen:)` is
  `sessionTrust`'s but for an unsaved open door with a seen key, `.open(seen:)`, so `Pin.key` (`reconnectIfListed`,
  `dial(_:macID:tap:seen:)`; a tap keeps `sessionTrust`). Another key answering (-9808, DeviceTLS's `onPinRefused`)
  is `HomeEnd.otherKey`: `homeSessionEnded` ends the reconnect with "‹Mac› answered with another key, so this
  ‹iPad› didn’t reconnect. Tap it to connect."; the row reads Not paired as before and a tap takes any key; a saved
  Mac's reconnect is unchanged (its saved pin). The review of #255 added two: a plain door (no `p`) under the name
  is not dialed after such a session (`reconnectTrust` gives nil for `.plain` with a seen key), where a DEBUG
  build's reconnect dialed it plain with no key to check (the reconnect looks on, as Release's does past "Update
  Sill"; a tap still dials it); and a tap during the reconnect (its words invite one) whose dial ends before its
  handshake leaves the reconnect pinned to the key the last session under that name saw
  (`reconnectKey(lost:earlier:)`, StreamClient's `openKeys` by Bonjour name, in memory, set at a session's first
  `.ready`), where it took any key. Left as it was: a tap under a name no session has seen a key under since Sill
  started (`openKeys` is memory only) whose dial ends before its handshake leaves a reconnect with any key, as the
  tap would have. DEBUG console: "reconnect: dialing ‹Mac› (dial 1 of this listing), pinned to the key its last
  session saw", "home: this device's pin refused the key that answered as ‹Mac› (-9808)", "home: the session ended:
  otherKey (-9808: bad certificate format)", "reconnect: ‹Mac› is a plain door now, and its last session saw a key
  over TLS: not dialed (a tap dials it)", "reconnect: the dial of ‹Mac› saw no key; the reconnect pins the key the
  last session under its name saw".
- Verified: `home-device` 225 checks (16 new) and 142 of 142 mutants (11 new), `home-model` 84 (8) and 28 of 28 (3),
  `policy` 477 (13, with a model of the glue: 680 reconnects over every sequence of up to four rows under the name,
  in Release and DEBUG, none to the other key, where main's rule gave it 197) and 171 of 171 (6, O1–O6); the four
  checks that compile DiscoveryPolicy.swift keep every mutant pattern; `run-all.sh`, all 56; `swift build -c
  release`, only the CaptureProbe warning; the three iOS builds, only the known `StreamClient` capture warning
  (StreamClient.swift:4120). Live on a private iPad mini simulator (iOS 27.0, deleted after), two bare `SillMenuBar
  --synthetic -requirePairing NO` hosts on 127.0.0.1 alone with identities of their own, each advertised as "Studio
  f3" (`_silltest._tcp`, `p=0`, a tag) by `dns-sd -i lo0 -R` (a test host's own registration is "Sill test ‹pid›"),
  the app with `-SillServiceType _silltest._tcp -SillTapRow "Studio f3" -SillNoAutoDesktop 1`: a tap connected to A
  with any key and A's copy reached the device; A killed (-9) with its advertisement; B under the name. Main's build
  (150479b5) reconnected to B by itself (B: "Client connected", "Client hello", "Clipboard: … shares the
  clipboard.") and B's copy was written to the device's clipboard (`simctl pbpaste`); this build dialed it pinned,
  refused B's key, ended with the words above (B logged nothing), the device's clipboard kept its sentinel, and a
  tap then connected to B with any key; A back with its own key (same identity, new port) was reconnected by itself,
  pinned, its copy arriving. Logs and photos in `~/Downloads/sill-handoff/triage/2026-10-29-security/f3-live/`.
- The review (2026-10-29; the report's "The review"): two findings, each reproduced first and fixed in a commit of
  its own. R1 (Low, DEBUG builds only), b8f0a7bb: after an open session that had seen a key, a DEBUG build's
  reconnect dialed a plain door under the lost Mac's name with no key at all (live on a private simulator against
  3e01e3c2's build: the CLI's plain door got the session, its hello and the device's clipboard; after the fix not
  dialed, A back reconnected pinned, a tap still connects). R2 (Low), 625df1b2: a tap during the reconnect (its own
  words invite one) whose dial waited for this device's own network and was let go before its handshake left a new
  reconnect that took any key (the rules walked as StreamClient chains them: B's key taken with no tap); now pinned
  to the key the last session under the name saw. Measured on loopback: a dial to a Bonjour row whose Mac does not
  answer (a dead port, a vanished name, a TLS alert in place of a certificate) stays preparing, so a tap there ends
  with "didn’t answer" and no reconnect at all; R2 needs the waiting case and was not run live. Seen in passing,
  older and not fixed here: `homeEnd` reads -9825/-9829 as the Mac refusing this device's key even before `.ready`
  (the plans: "right after `.ready`"), reachable only by an address dial at home (DEBUG's `-SillConnect`). Verified:
  `home-device` 237 checks and 147 of 147 mutants, `home-model` 87 and 30 of 30, `policy` 482 (its model of the
  glue: 1,560 reconnects with the person's tap among the looks, none to B; before the review B's plain door got the
  session in 194 and B's key after such a tap in 94, main's rule B's key in 444) and 176 of 176 mutants, at b8f0a7bb
  479 and 173 of 173; `remote-rules` 144, its 76 patterns each found once; `run-all.sh`, all 56 (512 s); `swift
  build -c release` from a `git archive` of the head, only the CaptureProbe warning; the three iOS builds, only the
  known `StreamClient` capture warning (StreamClient.swift:4134, main's 4110).
- **Untested, for Noah:** two Macs with Require pairing off on one network (the scan's own steps): connect the iPad
  to Mac A without pairing, quit Sill on A, give Mac B A's computer name (System Settings › General › Sharing) and
  open Sill on B: the iPad shows "‹A› answered with another key, so this iPad didn’t reconnect. Tap it to connect.",
  B's Sill.log has no "Client connected" for it and a copy on B never reaches the iPad; a tap connects to B. Sill
  reopened on A instead: the iPad reconnects by itself. VoiceOver reads the line once. From the review: with a Debug
  build from Xcode, the CLI's plain door (`SillHost`, no `--pairing`) or an older Sill.app given A's name after a
  session with A is not reconnected (the console's "…is a plain door now…"; a tap connects to it); during the
  reconnect to A ("…isn’t answering…"), a tap on its row while the iPad's own network changes (the tap's dial waits
  and is let go), then B under the name: no connection to B ("answered with another key"). And a decision: another
  key ends the reconnect for good, so a look-alike advertising the name for a moment while A is away turns the
  automatic reconnect off until a tap (live: A back 3 s after it went was not reconnected), and the words ask for
  the very tap that takes whatever key answers: keep it, skip that row and go on (as a saved Mac's row taken by its
  name is skipped), or change the words.
