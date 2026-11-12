**Update check and device notice (2026-09-25, branch `update-notice` from
`remote-access` at cb0ec55, PR #13, with main merged in at 1f3072a and again
at 32d532b, not rebased; the plan, its open questions with the defaults taken,
and the results are in `docs/update-notice-plan.md`).** Noah's
request: an update check in Sill.app with Apple frameworks only (GitHub's
releases feed, not Sparkle), and a host-to-device notice so a later Mac can tell
an old device to update instead of failing silently. The first public builds
set the compatibility floor for good (the section before Conventions).
- Wire (additive; `Compatibility.swift`): kind 23 `Hello {appVersion, build,
  protocol, device}`, the first message of every session connection a device
  makes (never a pairing connection; older hosts skip it); `SillVersion` (tags,
  bundles and the wire's versions: "v" dropped, the digits-and-dots prefix,
  compared part by part, "0.10" > "0.9"); `SillProtocol.current` 1. Kind 22
  gains `message`, `minimumVersion`, `reconnect` and the reason "update" (nil
  fields left out: the five goodbyes of today are byte for byte what they were).
  Window lists carry `hostVersion` (Sill.app's; nil from SillHost) and
  `protocol`.
- Host: `DeviceGate.minimumDeviceVersion` is "0": nobody is refused and nothing
  waits. Above it (only `SILL_TEST_MIN_DEVICE_VERSION` on a host that does not
  advertise, in this build), both doors hold a ready connection unregistered
  until its first message: a hello the floor admits is served; a lower version,
  no hello, another kind, the end or 2 s of silence gets kind 22 "update" ("Update
  Sill on your iPad to keep using ‹Mac›. It needs version 1.2 or later.",
  `"reconnect":false`) and this side's FIN, what it still sends is read and
  dropped until it closes (at most 1 s: cancelling at once answered its later
  messages with a reset, which can beat the notice), and it is never registered
  (no "Client connected", no "Client left", no "Remote client connected"). One Refused line per source a
  minute, then a count line; a source refused 5 times in 60 s hears it 2 s late.
  `SILL_TEST_GOODBYE` sends another kind 22 instead. A hello is logged ("Client
  hello: iPad (iPad14,1), Sill 1.0 (42), protocol 1 (…)") and names the Mac
  card's row before its stats. Pairing is never refused for age. What changed
  while the gate held a connection is judged again as it admits it: the remote
  door re-reads its trust snapshot (`serve`'s recheck, `RemoteServer.stillAdmits`:
  removed, Remote Access or internet access off, the 8-session limit, each with
  its goodbye and closeSessions' line), and at home a connection on peer-to-peer
  Wi-Fi that the peer-to-peer listener accepted is disconnected if Direct
  Wireless went off meanwhile. The remote door's refusals at admission
  (remoteOff, busy) close like the
  gate's (`closeWithGoodbye`); over TLS the close_notify and FIN go only at the
  cancel, so the device sees the end, and the notice, up to 1 s after the
  goodbye.
- Device: `GoodbyePolicy` is the one rule for how a session ends. Today's five
  reasons keep their words; "update" and any reason this build does not know
  are notices: the Mac's message (SafeText, at most 300 characters) as the status
  line, spoken, a reconnect only with `"reconnect":true`, looked at before a
  remote dial's failure rules (before, an unknown reason showed "disconnected"
  and redialled at once: a loop against a Mac that refuses). "update" adds
  "Update Sill in the App Store" under it once `SillLinks.appStoreText` holds
  the App Store address (the record's since PR #27; DEBUG `-SillAppStoreURL`). The
  hello goes out first on a tap's, a reconnect's, a wired dial's and its
  fallback's, a move's and a remote winner's connection (`-SillHelloVersion`),
  written to a home dial's connection as it is made, before it is the
  session's (a send made before `.ready` then follows it), and a tear-down
  forgets the session's viewport and a pointer re-send still waiting;
  `hostVersion`/`hostProtocol` are kept, shown nowhere. A refused home session
  shows the stream screen for a frame or two first (connected at `.ready`;
  accepted, open question 10).
- Sill.app: `UpdateChecker` (+ pure `UpdatePolicy`) asks
  https://api.github.com/repos/Saffsanity/sill/releases/latest 30 s after launch
  when due, then every 24 h plus 0–30 min, an hour after a check with no answer,
  re-armed at wake, and at Check Now: an ephemeral URLSession, `User-Agent:
  Sill/‹version›`, GitHub's Accept and API version, `Accept-Language: en` (it would
  otherwise send the Mac's languages), If-None-Match; no cookies, cache or
  credentials; redirects only to api.github.com; 1 MB, 10 s. A published release
  (not a draft or prerelease, its page on github.com) whose tag is newer than
  CFBundleShortVersionString is offered as "Sill 0.4 Is Available…" after the
  card (the glyph stays) and in Settings › General ("Check for updates
  automatically", on by default, wired to the checker from launch; Check Now's
  result until GitHub answers an automatic check, else the offer or the last
  check; Open Release Page…; Check Now); both open the page in the browser,
  nothing is downloaded. A 404 (the repository was private and without a
  release until 2026-09-26) is one log line a day and nothing else.
  `make-app.sh --release` builds only a commit tagged `v‹version›`.
- Verified (the plan's Results has every number): clean builds (only the
  CaptureProbe and `StreamClient` capture warnings); pure checks with swiftc
  and mutants: the protocol 74 (13 of 13), DeviceGate 58 (14 of 14),
  GoodbyePolicy 42 (16 of 16), UpdatePolicy 124 (18 of 18); cb0ec55's
  StreamProtocol reads the new payloads and skips kind 23; the CLI's stdout,
  idle 35 s and with a Desktop pick, masked and sorted, equals cb0ec55's;
  UpdateChecker alone against `sillfeed.py` (every answer of §6.4, the headers
  and nothing else, the timeout, the retry, Check Now joining); the bare app end
  to end (the live menu item, the pane, 304, 404 silent, off, test pattern
  mode); previews differ from cb0ec55's only in General, menu.txt's new sample
  and the new update states; the gate on the CLI (both doors, the loop
  slowdown, the count line, SILL_TEST_GOODBYE) and on StreamServer alone (no
  resets); the simulator against real hosts: the notice at home and through
  the remote door, no reconnect, redials only when asked, an older host, and
  photos at eight sizes.
- Review fixes (2026-09-25, after a85118d; the plan's "Review fixes"), in the
  bullets above: the hello written as a home dial is made, the gate's second
  look, the door's refusals with a FIN, the pane after a later check, the switch
  from launch. Checked: a stand-in with
  the real SessionLink.swift and a listener logging kinds: the hello first in 5
  of 5 each for a send right after start, after a hop to the network queue and
  200 ms into a Bonjour dial still resolving (the old order lost it in all
  three); the device against a stand-in Mac. A rig of StreamServer and
  RemoteAccess alone (no encoder): a hello held through Remove, Remote Access
  off and internet access off gets removed, remoteOff and internetOff with their
  lines (the build before served all three); 12 held sessions: 8 served, 4 busy
  (12 before); remoteOff and busy at admission with the hello 0.5 ms after the
  handshake: 30 of 30 end in a FIN (8 and 21 resets in 30 before). The real CLI
  with the en0 stand-in: a held connection is disconnected once Direct Wireless
  is off (the build before registered and served it). The checker alone: Check
  Now's result, then an automatic answer, 12 of 12 (5 failures before); the
  bare app: off at 0 s sends nothing, on at 0 s from a saved off asks (the build
  before did the reverse), the pane follows a release found after Check Now.
  H4–H6, H7 (42), UpdatePolicy (124) and H8's seven runs pass; the CLI's stdout,
  masked and sorted, equals cb0ec55's; previews equal the build before's; iOS
  Debug, Release and device builds with only the old warning.
- Merged with main (merge 104a9bd of main at 1f3072a: PRs #11 encoder recovery,
  #12 follow-best-path, #14 App Store readiness, #15 the public README). Where
  they meet: every connection the device opens says hello first, #12's moves
  included: `startMove` (from AWDL, to the cable, to Wi-Fi, a rescue's
  reconnect, each fallback) writes it as the connection is made, as
  `connect(to:)` does, and a remote winner says it in `adopt`; main's `rescue`
  reads `goodbye`. `SillLinks` is one enum (the site's addresses and the App
  Store one), once in the project file. The public README stays main's; this
  branch's Updates, tag and hello paragraphs are in docs/DEVELOPMENT.md. The
  pointer plan's Mac menu bar kinds move to 24, 25 and 27 (23 is the hello).
  Fix-ups: `release.sh --dry-run` builds an untagged commit again
  (`SILL_RELEASE_DRY_RUN=1`) while a real run names the missing tag in its
  preflight, and the checklist gains the tag and the App Store address
  (184d902); the privacy policy's Update check section, and the download page
  (05d9d3a). Verified on the merge: clean builds (only the CaptureProbe and
  `StreamClient` capture warnings; `make-app.sh` without `--install`); this
  branch's pure checks against the merged sources (the protocol 74, DeviceGate
  58, GoodbyePolicy 42, UpdatePolicy 124, their 61 mutants caught) and main's
  (the discovery policy 286 with 70 of 70 mutants, main's own 187 with the 20
  older ones, the fence in its 12 modes with 16 of 16, the remote rules 64
  with 35 of 35, the ledger 90 with 5,000 random runs and 3 of 3, the remote
  protocol 188); the hello first on the merged SessionLink (the review's check,
  and a new one for #12's hold and fenced hand-overs: the move's connection
  says hello first, one without it is caught; the source: two connections
  made, three hellos sent); the checker alone against sillfeed.py (42, and the
  stale-result check); the bare app's H8 runs 1 and 2; previews from the bundle
  against origin/main's: only General, menu.txt's `update-available` sample and
  the 20 new update states differ; the CLI's stdout against origin/main's,
  idle 35 s and with a Desktop pick, masked and sorted: identical; the gate on
  the merged CLI (H5, H6 a–h with the remote door, the slowdown and its count
  line) and origin/main's host skipping the hello; a simulator of its own
  (deleted after): at floor 99 the notice, no reconnect, no second connection
  in 60 s; at floor 0.1 admitted and streaming, and with `-SillMoveTest 1` the
  move's own connection admitted with its hello and the session moved to it;
  the update and notice cases at four sizes above main's footer.
- Review fixes after the merge (2026-09-25; the plan's "Review fixes after the
  merge"): `release.sh --publish` refuses, before building, unless origin's tag
  v‹version› names HEAD (gh would make a missing tag from the default branch's
  tip), passes gh `--verify-tag` in Saffsanity/sill, and warns when
  `SILL_RELEASE_REPO` is elsewhere, since every update check reads only
  Saffsanity/sill (the checklist's sill-site fallback publishes a download no
  Sill.app offers); the tag match is `grep -Fx`. A goodbye on a move's
  connection before its window list ends a session whose own connection has
  gone with the Mac's words (a rescue refused by a newer Mac: the notice, no
  reconnect), and a live session's move up no longer retries the listing that
  refused it. The privacy policy says the device tells the Mac its version
  "when it connects" (no VPN outside the Remote Access markers), and its short
  version names the fixed "en" and the IP address. §13 of the plan is the floor
  as written here; getsill.app and support@getsill.app read as confirmed in
  SillLinks, the checklist and the metadata. Verified: the builds; release.sh
  and make-app.sh against scratch repositories (60 checks, 13 of 13 mutants;
  d4abceb's fail 40) and `publish_release` against a fake GitHub API; the
  simulator against Python stand-ins, before and after; the site's cut gate;
  every pure check with its mutants, H7 (42) and the stale-result check (11).
- Merged with main again (2026-09-26; merge c01610b of main at 32d532b: PR
  #16, the best path's follow-ups, and PR #17, GitHub Actions; the plan's
  "Merged with main again"). No host source changed on main since 1f3072a.
  Where they met: `sessionEnded` keeps GoodbyePolicy's rule and passes #16's
  `afterQuit` after goodbye "quit" (a notice never sets it); release.sh keeps
  both sides' checks, main's `SILL_RELEASE_TAG`, `--check-tag`, icon check and
  `gh api` preflight (`gh auth status`, which the Actions token can't answer,
  is gone) and this branch's tag rule, and the release workflow
  (`GITHUB_ACTIONS` with `SILL_RELEASE_TAG`) does not ask origin for the tag
  (`in_release_workflow`: its checkout is origin's tag and keeps no
  credentials); the checklist says a pushed tag starts the release workflow,
  which publishes when `SILL_SIGN_IN_CI` is on, so `--publish` by hand then
  does not. `Tests/checks`: protocol's kind 23 case is the hello, and this
  branch's four pure checks moved in (662a70e): `compatibility` 74,
  `device-gate` 58, `goodbye` 42 and `update-policy` 124, with 61 mutants, in
  CI's mutants matrix too. Verified: a clean release build and the three iOS
  builds (only the known warnings); CI's CLI step; `Tests/checks/run-all.sh`,
  all 13, and `--mutants`, all 279 mutants caught; the hello first on the
  merged SessionLink and StreamClient; release.sh and make-app.sh in scratch
  repositories with a stub gh (101 checks, 20 of 20 mutants; the scripts
  before the merge fail 26 and 50 of them) and `publish_release` against a
  fake GitHub API; the simulator against this head's CLI (floor 99: the
  notice, no reconnect; floor 0.1: admitted and streaming, and a move's own
  connection with its hello; a goodbye "quit": its words and one connection).
- **Untested, for Noah:** the plan's V1–V7: V1 the real check while the
  repository had no release (moot since it went public with v0.3.0 on
  2026-09-26: within a minute "Update check failed: GitHub has no release of
  Sill (HTTP 404)." once, no menu item, Check Now says "Couldn’t check: GitHub
  has no release of Sill yet.", `updateLastCheck` set), V2 now that it has a
  newer release (0.3.1 for a 0.3.0 Sill.app), V3 a refusal on the iPad (its
  Debug build, `-SillConnect <this Mac>:P`, against
  `SILL_TEST_MIN_DEVICE_VERSION=99 SillHost --synthetic`; VoiceOver speaks it; no
  reconnect in 2 minutes), V4 mixed builds (PR #13's iPad build against this
  Sill.app and this iPad build against PR #13's: as before), V5 VoiceOver on the
  Mac, V6 the first two notarized builds (permissions kept across the update;
  `--release` refuses an untagged HEAD, `release.sh --dry-run` only warns,
  `--publish` refuses until the tag is pushed), V7
  the privacy policy's Update check section (site/privacy.html) on the
  published site (Saffsanity/sill-site republished with it on 2026-09-26).
