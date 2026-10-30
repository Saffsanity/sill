# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

## Current step

**The door's waiting places (2026-10-29, branch `sec-door-pending` from main at 150479b5, PR #252; finding 9 of the
security scan of 2026-10-18, Low; Noah's go of 2026-10-29).** A TLS door (the remote one, and the home one of
Sill.app and `SillHost --pairing`) held 8 connections waiting for admission, 2 per address, 10 s each, and backed an
address off only for its own refusals: four addresses closing each connection at 9.9 s kept every place full for good
and a paired device got "limit". Host only, no wire change. `DoorPolicy.Places` (pure) owns the places, `Door` runs
it on a monotonic clock: a connection that ends unadmitted, and a pairing connection's kind 19, costs its address a
tenth of a failure, a tenth for each second it waited at least, one more for every 2 s beyond the first 2 (counted to
its deadline at most), at least one when refused (5 in 60 s: 300 s, as before; a paired key at `.ready` clears its
address); the TLS handshake has 4 s (Network.framework does not say when a ClientHello arrives, so the whole
handshake rather than its first bytes; 10 s from a known address), a pairing connection's kind 19 4 s after `.ready`,
10 s in all; an IPv6 address answers for its /64 too (a link-local one's on its interface): 2 waiting places per /64
for addresses not known, and 12 failures in 300 s from those back the /64 off, an address counting 6 at most (so it
takes two); 2 places beyond the 8 for addresses that proved a paired key within a day (known: never refused for nor
charged to their /64, and they pay for what they hold as an address not known does, so someone at a paired device's
address is backed off with it within 30 s: nothing tells them apart before TLS). One line a minute per door, "Home
door backed off 10.128.0.34 for 300 s: its connections waited without being admitted, or were refused."
`AskLimits.quietKey`: the quiet after the Mac's Cancel or a stop covers the asker's IPv6 /64. Checks: `door-policy`
254 (the scan's attack modelled against the rule before and this one: before, every place held and the paired device
refused at all 60 tries in 2 minutes; now the four backed off 12 s in, the paired device admitted at every try, one
not yet known in at 13 s; closing at 1.9 s, 26.6 s; IPv6 churn in a /64, the /64 at 61 s, holding one place at 120 s)
and 109 of 109 mutants; `ask-limits` 43 and 24 of 24. Live on loopback synthetic `--pairing` hosts (sources
127.0.0.1, en0's 10.128.0.34, en13's 10.128.0.148 and en14's 169.254.219.184, whose connections to 127.0.0.1 stay on
lo0; 127.0.0.2–5 cannot be bound without a root alias): main's build refused the paired client at all 30 tries in 90
s ("… 27 over the limit."), backing nobody off; this one cut the four at 4.2 s and backed them off at 12.6 s ("Home
door backed off 10.128.0.34 for 300 s: …", the client at 127.0.0.1 with them); a scratch build with 6 shared places
(three addresses filling them as four fill 8) served a known client at all 20 tries and an unknown one from 13 s; one
address cycling at 1.9 s held 2 places for good on main and was backed off at 47.9 s here. Plan's "What stays open"
updated (an address keeps about 4/5 of a place, so ten IPv4 addresses taking turns fill the shared places; the
co-located address; a device not yet paired in a backed-off /64, which a stranger in it keeps backed off with a dozen
refused handshakes as each 5 minutes end; a routed IPv6 prefix from the internet at the remote door).
- The review (2026-10-29; the report's "The review", f9-pending-slots-report.md in sill-handoff's
  triage/2026-10-29-security): three findings, each reproduced live on 7929c539 first and fixed in a commit of its own.
  A kind 19 left its place for nothing, and the home door's verify block takes `sill-pair/1` with any key: a holder
  doing TLS on it 3 s in and a kind 19 (`v` 2, answered `closed`, nothing shown) 3.5 s later held all 8 places for
  90 s from four addresses (112 kind 19s), nobody backed off, an unknown paired client refused at all 30 tries; now
  `Places.End.request` pays as a connection that ended then (fd0a58c5): the same holder backed off at 13.07 s. The
  wait counted from accept on CLOCK_MONOTONIC, which runs on through a sleep while the deadline's timer does not: one
  connection waiting across a 20 s SIGSTOP of the host (a sleep's stand-in) backed 127.0.0.1 off at the continue and
  the known client was refused at all 13 tries; now a wait counts to its place's deadline at most (0b457e48): no
  backoff, 13 of 13 served. A known address was charged for all of its 10 s (a cut 4.1, its device's own let-go at
  5 s 1.6, where main charged 1 and nothing): a known device's reconnect whose dials stalled was backed off at 40.06 s
  and refused at all 6 tries after; now it pays as an address not known (1.1 at most for a handshake, 3.1 for a
  pairing connection; 8e0148a0): no backoff, 6 of 6 served. Docs: the plans' limits tables, sillclient's `--pair-hold`
  note, DEVELOPMENT.md, and the /64 trade-off (a check: the /64 open 1.8 s of 15 minutes).
- The review's second pass (2026-10-29, resumed after the session's limit stopped the first before it pushed; the
  report's "The review"): three more findings, each reproduced first and fixed in a commit of its own. A mutant's
  pattern still named the line 0b457e48 replaced, so `run.sh --mutants` said "NOT APPLIED" and 103 of 104 (bda128ba).
  An end within 2 s cost a tenth however long it held its place, so one connection at a time closed at 2 s cost an
  address 3 a minute, under its 5: eight addresses held every shared place for good (the model, 600 s: nobody backed
  off, a device not yet known refused at all 300 tries; live, one address 120 s: no "backed off" line; a scratch
  build of 3 shared places: three addresses held them 120 s, a paired client not yet known refused at all 40 tries);
  now each second held costs a tenth at least, `DoorPolicy.waitCost` (8b51058d): live, "[51.54] Home door backed off
  10.128.0.34 for 300 s: …", and with 3 places the three backed off at 51.5 s (27 connections each) and the client,
  refused at all 17 tries before, served at all 23 after; an address keeps about 4/5 of a place (ten taking turns
  could fill the 8). The /64's 12 was said to need two addresses, true only for a burst: paced under its own 5, one
  address backed its /64 off (an older Sill's plain try every 2 s on its link-local address backed off its whole link
  at 238 s; a refusal every 16 s, at 176 s); now an address counts for 6 at most, `DoorPolicy.groupShare` (c0e70ab6;
  the model only: the test listener is IPv4). door-policy 254 checks and 109 of 109 mutants, ask-limits 24 of 24,
  home-model 25 of 25, addresses 16 of 16; `run-all.sh` all 56 (513 s); `swift build -c release` from a clean
  `.build`, only the CaptureProbe warning; `Scripts/pacing/build.sh` builds both sides. The first pass's live runs
  again on the final build: the kind 19 holder backed off at 13.18 s, the 20 s stop no backoff and 13 of 13 served,
  the known device's stalled dials no backoff and 7 of 7, the scan's attack backed off by 12.63 s.
**Untested, for Noah:** a week of ordinary use at home and away (Wi-Fi, cable, Tailscale, the hotspot) with no
"backed off" line in Sill.log (note any, with what the device did); a new pairing over the hotspot through Tailscale
(its handshake inside 4 s); an iPad back after a night asleep; from the review, the Mac's lid closed while the iPad
reconnects, then opened: the iPad back at once, no "backed off" line; the iPad sent to the background mid-dial a few
times, or walked out of Wi-Fi range while it redials: no "backed off" line for its address; from its second pass, a
device whose dial tries the Mac's addresses 1 s apart (through Tailscale), away and back a few times: no "backed off"
line (its losers now cost up to 0.2 each).
**A device the Mac stops serving lands no more input (2026-10-29, branch `sec-revoked-input` from main at
150479b5, PR #254; security scan finding 10, Low; Noah's go of 2026-10-29 for the security batch).** Remove,
Require pairing turned on, and Remote Access or internet access turned off said goodbye and closed the device's
connection once the goodbye was handed to the network, or 0.25 s later; meanwhile its input kept landing, and
input held for it while an app came forward (up to 0.6 s) was replayed, also once it had left. Host only; no
wire change, nothing on the device.
- The coordinator marks the device as the Mac decides (`RemoteAccess.onCutOff`, on the main actor: every
  connection whose route the change names, before any of its messages already waiting there; since the review),
  and a session the door admitted while the Mac decided, whose registration waited behind the decision, as it
  registers (`RemoteAccess.stillServes`, `DoorPolicy.stillServes`, pure: as `afterGate` judges a session the
  gate held; since the resumed review), and `StreamServer.closeSessions` marks its session revoked as it says
  goodbye (`Client.revoked`, on the network queue) and tells the coordinator in the same queue turn
  (`onClientRevoked`): its receive loop then hands on only a key's or a button's up (`RevokedInput.mayLetGo`),
  no pong, no stats, no pointer control, and counts the rest (`in.revoked`). The coordinator keeps the revoked
  set until the device leaves and posts of it only the up of a key or a button that device pressed and the Mac
  still has down (`RevokedInput.stillGoes`, KeyStrokes.swift, pure; `InputInjector.releasesWhatItHolds`, with
  each button's owner), a button's where the pointer is; nothing else it sends acts (a pick, a window's buttons,
  a launch, settings, menus, the clipboard), and a menu choice or fetch of it still waiting for its turn is
  neither made nor read (`MenuMirror.clientRevoked`; a departed device's choice is still made, as a move counts
  on it). The replay of held input, a switch's drop of it and gestures waiting for a switch judge a revoked
  device, and one that left while it waited (`gone`), the same way, and drop their shortcuts. Its keys still
  down when it leaves go up as before, and its buttons now too (`RevokedInput.buttonsLetGo`; an unremoved
  device's stay down as before: its session may go on over a move's connection). TEST ONLY: with
  `SILL_TEST_INPUT_LOG` a synthetic host prints where a revoked device's input stops landing;
  `sillclient.py --key=USAGE,HOLD@T` holds a key. The pacing and sound harnesses compile KeyStrokes beside
  StreamServer.
- The review (2026-10-29, at cf230ed9; three findings, each reproduced on loopback first, then fixed in a
  commit of its own). (1) A cut-off device's mouse button stayed down after it left (departures let go of
  keys only): a paired client pressed the left button and was removed before its up; after "Client left"
  another device's three moves were posted as "left mouse drag", the up only at Quit. Now
  "left mouse up (none) at 529,332" as it leaves and the moves plain (8399498f). (2) The coordinator learned
  of the cut only from the server's mark, which reached the main actor behind the device's messages already
  waiting there (read while the Mac saved the change: the keychain's write, or a locked login keychain's
  prompt): with the test store's save made to take 150 ms (a scratch build), 25 events (moves, key downs,
  their ups) landed at +154 ms, after "Removed …", 2 runs of 2; with the decision's mark none, `in.revoked`
  20 (9c518d13). (3) A menu choice or fetch made before the cut and waiting behind a slow menu read (up to
  its device's 4 s wait) was still made or read, its app brought forward first; checked with a scratch
  harness of the real MenuMirror on a stub reader (no Accessibility in that session): the branch's made B's
  choice and read E's menu after their cut, this one neither, and a departed C's choice is still made
  (6d7dfb89). Scripts/menu-check/mirror.swift gains the case against the fixture: it compiles, not run there.
- The review, resumed (2026-10-29, at 14f09529; one finding, reproduced on loopback first, fixed in a commit
  of its own). A session of the cut-off key that the door admitted while the Mac was deciding (saving the
  change: a keychain write or its prompt; or the main actor held up, as by a hung app's Accessibility call)
  registered on the main actor only behind the decision, so `onCutOff` could not name it, and everything it
  sent until the server's own mark landed after the decision: with a scratch build whose test store's save
  took 1 s, a second connection of the removed device admitted 0.29–0.33 s into the save landed 58 and 62
  events (moves, key downs, their ups) at +1,016 to +1,029 ms, after "Removed …; closed 2 connections.", 2
  runs of 2, and one that sent and left before the save ended still landed 41. Now the coordinator asks, as it
  registers a session, whether the Mac still serves it (`RemoteAccess.stillServes`, `DoorPolicy.stillServes`:
  `afterGate`'s judgement from what it was admitted as and the trust as it is now; a plain session never cut
  off, the remote door's limit no cut), and marks it before any of its messages; such a session neither wakes
  the display nor counts as the paired device's last connection. With the same save: 0 events after the
  decision, 3 runs of 3 (`in.revoked` 56 to 76), and 0 for the one that left first.
- Verified: `key-strokes` 395 checks (42 new on the branch: the rule, the buttons as a cut-off device leaves,
  the glue modelled with what waits for the main actor, removals, holds, switches, gestures, departures and
  busy spells, one ending with the decision: 3,000 random sessions; marked by the server alone 1,097 and as
  it was before 2,789 of 3,000 landed input after the cut) and 98 of 98 mutants (15 new); `run-all.sh`, all
  56; `swift build -c release`, only the CaptureProbe warning; the pacing and sound harnesses build; no iOS
  file changed. Live on loopback (a `--synthetic` bare app with `SILL_TEST_INPUT_LOG`, a paired `sillclient`
  pressing a key every 25 ms, each held 0.6 s, and moving, tapping, typing and pressing F-keys across the
  cut, not reading, so its connection lasts the whole 0.25 s): between "Removed sec10-client (sillclient);
  closed 1 connection." and "Client left" main's build posted 48 and 57 events (key downs, moves, clicks,
  typed text, key ups) up to +253 ms, and 56 after Require pairing's line; the branch's builds only key ups
  of keys down at the cut (10 to 11), then at "Client left" the keys it still held; on the final build the same
  for Remove (11, Client left +260 ms, `in.revoked` 44), Require pairing (10, +255 ms, 37), Remote Access off
  and internet access off through the remote door (16 ups in all each, +256 and +252 ms, 24 and 23), and a
  device removed mid-drag lets go of the button as it leaves ("left mouse up (none) at 529,332"). After the
  resumed review (8a29d178): `door-policy` 135 checks (7 new: `stillServes` against `afterGate`'s oracle over
  5,120 combinations, and the four cuts by name) and 62 of 62 mutants (4 new); `key-strokes` 402 (7 new: the
  model registers a session ahead of its messages; in 1,181 of 3,000 random sessions a second connection of
  the removed key admitted while the Mac decides lands nothing after the decision, where without the check at
  registration 391 of 1,187 landed it) and 98 of 98 mutants (KeyStrokes.swift unchanged); `run-all.sh`, all
  56; `swift build -c release` from `git archive`, only the CaptureProbe warning; the pacing and sound
  harnesses build. Live on its build:
  Remove 10 key ups (`Client left` +262 ms, `in.revoked` 39), Require pairing 11 (+250 ms, 38), Remote Access
  off and internet access off 16 each (+252 and +253 ms, 22 and 23), each an up of a key down at the cut; the
  mid-drag removal's up as it leaves and plain moves after; the CLI's plain door, alone and beside `--remote`,
  a test client's move, key and tap landing as before; the menu stub harness 5 of 5.
- Not done: a pick already under way, or queued behind a restart, when the cut comes still brings its window
  forward (not input); frames, the clipboard and pointer reports sent after the goodbye queue behind it and go
  with the connection.
- **Untested, for Noah:** with this Sill.app and the iPad's Magic Keyboard streaming TextEdit, type steadily
  (or hold a key) and click Remove in Settings › Devices: nothing typed after the click lands, and no key
  stays down on the Mac (Sill.log: "Removed …", then "Client left", the `[1s]` line's `in.revoked`); pair
  again and it works. The same with Require pairing turned on while an unpaired iPad types. From the review:
  drag a window with the iPad's trackpad and click Remove mid-drag: the drag ends, and another device's
  pointer then moves without dragging; choose a menu item from the iPad's Menus in a slow app and click
  Remove at once: the item is not chosen (Sill.log: "Menu from … refused: …: the Mac no longer serves it").
**The macOS firewall that blocks Sill's executable (2026-10-29, branch `firewall-executable-block` from main
at 150479b5; PR #250; the security batch, Noah's go of 2026-10-29).** A user's report: the firewall keeps a
rule per path, and a Mac held `/Applications/Sill.app` allowed and `…/Contents/MacOS/Sill` blocked
(`socketfilterfw --listapps`): nothing reached Sill from the network, System Settings showed it allowed, and
`--getappblocked` on the bundle said "permitted"; `sudo socketfilterfw --unblockapp` on the executable fixed it.
No wire change.
- `FirewallCheck` asks `/usr/libexec/ApplicationFirewall/socketfilterfw` `--getglobalstate`, then only while it is
  on (`asksRules`) `--getblockall`, `--getappblocked` for the running executable (`proc_pidpath`) and its bundle,
  and `--listapps`: a process each with 2 s (then SIGTERM, SIGKILL a second later), read-only, no privileges
  (macOS 27.0.1: 4–8 ms each, no prompt, no Full Disk Access needed; asked in one run the tool is killed, 137,
  when `--getstealthmode` or `--getallowsigned` follows `--getappblocked`, or `--listapps` follows it with a
  bundle's path; no `com.apple.alf.plist` there). At launch, when the listener comes up, when Sill.app's status
  menu opens (the glyph at once, its item from the next opening), when its General opens or Sill becomes active
  over it, and when a device gets in from the network while the verdict says none can (`asksAgain`); never on a
  timer.
- `FirewallRule` (pure, `Tests/checks/firewall`, 390 checks, 69 mutants): off, allows (only once `--listapps`
  was read), `blocks(executable:bundle:)` (its own answer or its rule in the list, either enough), `blocksAll`,
  unknown (with why, in the log).
  While it blocks: General's line in the Permissions style with `sudo …/socketfilterfw --unblockapp <the running
  executable's path>` (a line per option; Copy copies one line), for Block all where to turn it off; the menu's
  "Devices Can’t Connect — The macOS firewall blocks Sill’s executable." (opens General); one log line per change
  ("Firewall: …"; none for a first verdict that blocks nothing). Sill never runs the command. support.html's
  "Your Mac isn’t listed" gains the case (Sill's own line marked `<!-- Firewall`). TEST ONLY
  `SILL_TEST_FIREWALL=executable|bundle|both|all|off|allowed|unreadable` or a file holding one, test hosts only;
  the previews are the rule's verdicts on those answers; `-SillPrintMenuAfter` prints General's line.
- Verified: the check and mutants; `run-all.sh`, all 57; a clean release build (the CaptureProbe warning
  only); main's CLI output identical masked and sorted, idle and with a client; previews main's but the 16 new
  files, menu.txt's two samples and General's path; live on loopback, blocked → allowed → Block all →
  unreadable, a VPN-origin client clearing a stale verdict, the bare app's menu and line, this Mac's real
  firewall "none (allows)". Not built: an Unblock button with the admin password (`osascript` off the main
  thread, or a privileged helper), Noah's call.
- The review (2026-10-29, three lenses; each finding reproduced first, then fixed in a commit of its own;
  sill-handoff's `triage/2026-10-29-security/firewall-line-report.md`, "The review"): a block that came after
  launch (a Deny in the firewall's own prompt, Block all turned on) went unsaid until General opened or the
  listener was replaced, as `asksAgain` can only clear one (on loopback, the canned answer blocked from 2 s: a
  client at 3.6 s and the bare app's menu at 4 and 7 s said nothing): the status menu asks again as it opens
  (bd18d96b); with `--listapps` unread the verdict took the executable's own "permitted" for allowed and dropped
  why: unknown, with why, unless an answer blocks (3d10ea95); the check's usage stand-in had no "apps", so a
  reading that took any mention of apps for a list passed (56d3f3a3); the docs had the tool die whenever
  `--listapps` followed `--getappblocked` in one run (the docs commit, af3283d1; the second review measured which
  options do, below). Re-run: the check 340 and 67 of 67 mutants (64 of 64 before; two extra mutants had
  survived); `run-all.sh`, all 57; the release build, the CaptureProbe warning only; main's CLI masked and sorted,
  idle (8 lines) and with a client (three passes, as main against main); previews 162 files; on loopback a device
  in from a VPN re-asking without clearing a block that holds, and clearing a stale one.
- The second review (2026-10-29, after af3283d1; the report's "The second review"): two findings, each reproduced
  first and fixed in a commit of its own. The first review's correction of when the tool dies was wrong both ways
  (read-only, as noah, 3 runs of 3 each): `--getstealthmode` or `--getallowsigned` after `--getappblocked` kill it
  whatever the path, `--listapps` only after a bundle's, and `--getglobalstate`, `--getblockall` or another
  `--getappblocked` after it answer (78685c9a, docs). A tool that never answered was asked all five questions, and
  one that ignored SIGTERM was left running, a thread blocked on its pipe, after each (FirewallCheck's own code
  against a stand-in: 10.04 s a check; 20.11 s and 5 processes left; the state on and the rest deaf, 16.16 s and
  4), which the menu's re-asking at every opening would add up: nothing more is asked once the state decides
  (`asksRules`: off, Block all, a state that doesn't read) and an unanswered question is killed a second after
  SIGTERM (2.01, 3.01 and 12.06 s, none left; 6d836d1f). Re-run: the check 390 and 69 of 69 mutants; `run-all.sh`,
  all 57; a release build from an empty `.build`, the CaptureProbe warning only; this Mac's firewall through the
  fixed check, 19–22.5 ms for Sill.app's five questions, allows; previews 162 files; on loopback a Block all held
  against a device in from a VPN, then blocked, cleared and unreadable as the canned answer changed.
- **Untested, for Noah:** the report's state by hand (`sudo …/socketfilterfw --add …/Contents/MacOS/Sill`, then
  `--blockapp`; `--remove` after): the device's tap failing, the menu item and log line, General's line and
  Copy, the command in Terminal, then both gone without a relaunch; Block all on and off, also with Sill running
  and its menu opened twice (the glyph turns at the first, Devices Can’t Connect at the second); VoiceOver;
  macOS 14 or 15 (answers that don't read log "Firewall: couldn’t read …" once and show nothing).
**A password manager's copies go to the devices (2026-10-29, branch `clipboard-concealed` from main at
6c5b5d24).** Noah, with the clipboard on his iPad: "Copy paste works, including password apps. I think its
fine to copy password apps. Remove the code that tries to make password copies never arrive." So
`ClipboardPolicy` no longer skips an item marked `org.nspasteboard.ConcealedType`, `TransientType`,
`AutoGeneratedType`, the older transient type or 1Password's own (`markerTypes` and `HostSkip.marked` are
gone); Universal Clipboard's items (`com.apple.is-remote-clipboard`) and the host's own writes are still
never sent, and the types are still judged before any data is read. Words: Settings › General's footnote
(`ClipboardPolicy.Copy.macFootnote`), README's Good to know, support.html, privacy.html (dated October 29,
2026), DEVELOPMENT.md, docs/clipboard-plan.md's last section; `Tests/checks/clipboard` (the marked items now
sent, the footnote, the model). No wire change.
**A Desktop after a spell with no device (2026-10-28, branch `idle-display-refresh` from main at 6c5b5d24,
PR #239; the diagnosis is sill-handoff's `triage/2026-10-20-reports/verdicts-2026-10-27/glitch-wired-black-2026-10-28.md`,
the report `verdicts-2026-10-28/idle-display-report.md`).** Noah, 2026-10-28 18:15 on the iPad mini over the cable
with a fresh Debug build: connected, black, left after 7.4 s; the Wi‑Fi tap 25 s later "worked flawlessly". Sill.app
had sat 36.5 hours with no device while the dock's two displays came back under new IDs through ~290 sleeps; the
catalog looks only while a device is connected ("idle means idle"), so it still held display 21 (the displays were
53 and 52). The first pick built the Desktop's filter on 21's SCDisplay, read before an await during which the
poll's first look had already replaced it; ScreenCaptureKit refused it ("Start stream failed … The stream is nil",
CoreGraphicsErrorDomain 1003); the host printed it, sent "nothing streams" and never tried again; the device had
just asked, its next lists (0.18 and 0.25 s) came within the 10 s spacing, and no list came after: black until
left. Any second pick would have streamed. Not a regression (the Desktop's cached display dates from 2026-09-22).
No wire change.
- The host (CatalogLook, pure, `Tests/checks/catalog-look`): before any window or Desktop capture (never the test
  pattern) the catalog looks again (one ScreenCaptureKit call, about 50 ms) when its last look's display is not
  among `CGGetActiveDisplayList`'s (gone, or asleep: harmless), it had none while macOS has one, there was no look,
  or the look is older than two poll intervals (4 s) on the clock that counts sleep (`WindowCatalog.lookedAt`,
  `lookAge`; an empty list of displays leaves it to the age). A look the poll keeps fresh needs none, so a pick
  mid-session is as before. The Desktop reads its display after its last await (`desktopCapture`: Sill's own app
  looked up, then the display and the app from the newest look), and says "Desktop: display 21 → 53 (the displays
  changed since the last look, 36 h ago)." when the look changed it. A Desktop start that fails looks again and
  tries once more with one line, "Could not start streaming the whole desktop: ‹error›. Looked at the displays
  again: trying once more on display 53." (`startDesktopAgain`; the test pattern tries the same start again,
  "… Trying once more."); a second failure is the old line, nothing streams.
- The device (`DiscoveryPolicy.autoDesktop`, `autoDesktopRecheck`, StreamClient's `askForDesktopByItself` and
  `recheckDesktop`): within the 10 s spacing after its own Desktop request, a list that says nothing streams
  (watching nothing, or the Desktop the Mac stopped) and no choice of the person's since that request (a pick, a
  launch, a pick made again after a move: `choicesAtLastAuto`) sets one re-check when the spacing ends (`askIn`;
  a clock set back waits the spacing, never longer); due, it asks only while nothing streams still, nobody chose
  and no other automatic request went out. So a Desktop that failed is asked for again 10 s after, a Mac that
  keeps failing every 10 s, never faster, and a Desktop the Mac stopped within the spacing is asked for when it
  ends (issue #69's re-ask was held back there). A window that closes within the spacing is left as before. The
  re-check is cancelled by the next automatic request, at a session's end and at a move. DEBUG console:
  `session: nothing streams after this device's Desktop request; asking again in 9.8 s, when the 10 s spacing
  ends`, `session: still nothing streams 10 s after this device's Desktop request; asking for it again`. Against
  Sill for Mac 0.5.1 (the stale display unfixed there) the second ask should stream too: the diagnosis found the
  first session's own look had replaced the display 0.1 s in, so any second pick streamed (read, not run).
- TEST ONLY `SILL_TEST_DESKTOP_FAIL=<n>`, honoured only by a `--synthetic` host ("Test Desktop: …" at start;
  otherwise one "ignored" line): the first n Desktop starts fail where the capture would start, as on 2026-10-28.
  With 1 the host's one more try streams; with 2 nothing streams and a device's second ask does.
- Not done (the report's items 3, 4 and 6, for Noah): the first catalog sent only after the first fresh look (a
  device shows a list up to a day old for about 50 ms); a display reconfiguration callback marking the look stale
  while idle; dropping a client whose path goes unsatisfied before its 8 s grace (the dead cable connection the Mac
  served for 7.6 s). Nor the pair dialog of the same evening (the diagnosis leaves it open: Add a Mac's card or an
  iPadOS alert; the iPad's console or a screenshot would settle it).
- Verified: `swift build -c release` (only the CaptureProbe warning); `catalog-look` 64 checks and 25 of 25
  mutants (in CI's matrix); `policy` 486 (22 new) and 176 of 176 mutants (N24–N28 follow the new code, N29–N39
  the re-check); the patterns of the other three checks that compile DiscoveryPolicy.swift (`home-device` 131,
  `home-model` 14, `remote-rules` 17) each still found once, their mutants not run again (none calls `autoDesktop`);
  `run-all.sh`, all 56; the three iOS builds on Xcode 27.1 (Debug for the generic simulator as CI builds it, Release
  for the simulator, Debug for a generic device), only the known `StreamClient` capture warning (now line 4162);
  H2: the CLI from `git archive` of 6c5b5d24 against this branch's, `--synthetic` test hosts on loopback with the
  software encoder and no screen, idle 35 s identical masked and sorted, with a test client picking the Desktop for
  12 s identical (twice; main's own second run differed from its first only in the stats line of the second the
  client left). Live on a private iPad mini (A17 Pro) simulator (iOS 27.0, deleted after) dialling such a host with
  `-SillConnect` (a plain door): with `SILL_TEST_DESKTOP_FAIL=2` the host's start and its one more try failed 0.23 s
  after the connection, the device said it would ask again in 9.5 s and did 10.2 s after its first request, and the
  stream came within 10 ms (29–57 fps after); with 1 the one more try streamed in the same pick and the device never asked
  again; with 50 (a Mac that never starts it) the device asked at +0.85, 10.99, 21.24, 31.49 and 41.49 s, 10.0 to
  10.25 s apart. Not run: the real Desktop path (`desktopCapture`, the look before it, the "display 21 → 53" line,
  the one more try with a new look), since every test host here stays off ScreenCaptureKit (`SILL_TEST_NO_SCREEN`)
  and never captures this Mac's displays; nor a device, nor main's iOS build beside this one (the model has the rule
  before: one ask, then black).
- **Untested, for Noah:** with Sill.app from this branch and the iPad on a Debug build: leave Sill.app
  with no device while the dock's displays sleep and wake (or `pmset displaysleepnow`, a key, and a look with
  `system_profiler SPDisplaysDataType` or a `CGGetActiveDisplayList` probe that their IDs changed), then connect: the
  Desktop at once over any route, and Sill.log's "Desktop: display ‹old› → ‹new› (the displays changed since the last
  look, … ago)."; picks while connected exactly as before (no such line, no delay); the Desktop with Virtual Display
  on, and a window picked first after the spell. The device's part against Sill for Mac 0.5.1 (the host's fix not in
  it), after the same spell: black for about 10 s, then the Desktop by itself (the console's `session: still nothing
  streams 10 s after …; asking for it again`); a monitor unplugged while the Desktop streams (ScreenCaptureKit stops
  the capture): the Desktop back within 10 s; VoiceOver unchanged (nothing new is drawn or said).
**Held keys repeat, as on the Mac (2026-10-28, branch `key-repeat` from main at 6c5b5d2; issue #162; PR #240).**
Noah, 2026-10-27: "#162 should expand to make holding down keys work on all keys when held, same as a
regular keyboard, wait times and all, where non-command keys wait a second before starting their
repeating. Same as desktop." An event posted from a CGEventSource never repeats (the HID system repeats
only the keyboards it reads), so a held arrow, ⌥← or ⌘Z reached the Mac once. The host repeats it, so
every device gets it from a Mac with this build (no wire change for that; the window lists' additive
`keyRepeat` came with a hardware keyboard's letters, below). Supersedes addhumal's #163 (the device
repeating at its own 0.4 s and 20 a second), which this branch leaves alone.
- Host (`KeyRepeat`, pure; `Tests/checks/key-repeat`): InputInjector tells it each keyboard event it
  posts and steps it at the times it names (a Task on the main actor); a key held down repeats after
  the Mac's own Delay Until Repeat and at its Key Repeat Rate (NSEvent's keyRepeatDelay and
  keyRepeatInterval, read at each key's down: 0.5 s and 1/30 s on this Mac), each repeat the key's
  down again with the autorepeat flag (kCGKeyboardEventAutorepeat) and the flags in force (what the
  down carried less a modifier let go since, and what the modifier keys down hold now: ⇧ pressed while
  → repeats selects, ⌥ let go turns word jumps into steps). Every key but the modifiers, Caps Lock,
  fn and the media keys; one key at a time, the last pressed (an earlier one still held never takes
  over again). It stops at its up (any device's), another key's down, typed text, a gesture's chord,
  its device leaving and the host's end (every key let go), and input with nowhere to land (the
  coordinator's `keyRepeatLanding`, `currentSourceRect` nil, and select's drop point); it waits while
  input is held for an activation (a repeat never overtakes it), and while its device has been quiet
  half a second (`StreamServer.lastHeard`, every message's header; a device pings every 0.25 s), then
  starts over after the delay: a stalled link can hold the key's up back for the 4 to 8 s before the
  Mac drops the device. Its first repeat (after the press, and after a quiet spell) waits for a word
  from its device heard after the press and no earlier than `KeyRepeat.firstWord` (0.3 s) before it is
  due (the review of the held letters): the link keeps the device's messages in order, so a key only
  tapped (a letter, a Delete) whose up a stall holds back never repeats, and a key held has its ping in
  time. A late wake posts once, the next at least half an interval on. Off (a delay
  or an interval of a minute or more) and nonsense repeat nothing; a delay under 0.1 s and an
  interval under 15 ms count as those. `in.keyRepeat` on a host that posts; a `--synthetic` host
  counts `in.dry`, and with SILL_TEST_INPUT_LOG=1 prints "Test input: key 123 repeats after 0.50 s,
  every 0.033 s" at each press and "Test input: key 123 repeat (none)" for each repeat.
- Device (`HeldCap` in KeyChords.swift, checked in `key-strokes`): the portrait key row's esc, tab and
  arrows go down at a finger's touch and up at its release (a ButtonStyle's isPressed; `KeyChord.down`
  and `up`, `press` = both), what is latched going down with the key and spent at the touch; one cap at
  a time; the Button's own action after a touch sends nothing, or the up of a press whose end
  isPressed had not told yet (the action comes with the release: a missed end never leaves a key down
  repeating), an activation with no touch (VoiceOver, Switch Control, Voice Control, a keyboard) the
  whole press as before; the latch is spent when a key goes down with it (`spendsLatch`); the row
  leaving the screen lets a held cap up. A phone's esc and tab stay taps at the accessibility text sizes, where a long press
  shows the cap large (`capsHold`). The latching modifiers, Keyboard and Spotlight are taps as before.
  A hardware keyboard's characters: the next bullet (they were thought to keep iPadOS's own repeat).
- Held letters (2026-10-29; Noah on the iPad mini with a Bluetooth keyboard and through Universal Control:
  "hold p didnt work … When I held down e it showed the keyboard options for Spanish characters"). The text
  system's keys never reached the Mac as held keys: in the iPad simulator with `Tests/keyrig` (`wait:S` holds
  a key) against a loopback synthetic host, 4504a96c's build typed a held P once (one `pressesBegan` handed
  to the text system, one `insertText "p"`, nothing more in 2.3 s), a held E once and then iPadOS's
  press-and-hold accent popover (è é ê ë ě ẽ ē ė ę, still up after the release), and repeated Delete and
  Space itself (the first after about 0.4 s, then every 0.105 s: 20 separate presses each in 2.3 s, iPadOS's
  timing, not the Mac's). Now `KeyTyping` (TextComposition.swift, pure, checked in `text-composition`) says
  at each key's down who types a hardware keyboard's characters: the Mac, as keys, while it says it repeats a
  held key (`WindowList.keyRepeat` 1, additive, nil from every host before: `KeyRepeat.generation`, set in
  every window list; the device's `StreamClient.hostKeyRepeat`), the keyboard selected on the iPad types the
  Latin alphabet directly (its primary language's likely script is Latn, and its input method does not
  compose: `composingLatin`, Vietnamese and Hawaiian, whose input managers say they compose text in the iOS
  27.0 runtime's TextInput bundles), nothing is composed and nothing is latched on the key row (with no
  keyboard selected, only if every keyboard set up would); else iPadOS's text system, as before (a Sill for
  Mac from before key repeat, which would type each key once where iPadOS repeats Delete and Space itself; an
  input method's keyboard, Chinese, Cantonese, Japanese, Korean, Vietnamese, Hawaiian or a transliteration
  one; another script's, Russian, Greek, Arabic, Hindi…; a latch, whose shortcut `insertText` makes), and
  while marked text is open every key is the input method's. While the Mac types,
  `ForwardedKeys.characterUsages` (the letters, digits, Return, Delete, Tab, Space, the punctuation keys
  `` - = [ ] \ ; ' ` , . / `` and Shift's two keys, each a key every Sill for Mac answers to) go down and up
  as keys, so the host repeats them at the Mac's timing, the Mac's own layout and dead keys make the
  characters (⌥E then E is é), Shift is a key the Mac hears (the repeats follow it; a click with it held is a
  shift-click) and no accent popover comes; Caps Lock stays the iPad's (its key the text system's) and a
  letter typed with it on and no ⌘, ⌃ or ⌥ carries Shift (`ForwardedKeys.carried`). The keypad and the ISO
  keyboards' Non-US `\` and # stay the text system's (no Sill for Mac before has them as keys). Unchanged:
  the ⌃Space rule (#138), the on-screen keyboard (`insertText`), dictation, Esc's key command, every key that
  already went as a key, the host's repeat; the wire but for the additive `keyRepeat`. DEBUG: each hardware
  key's down line ends in who types it, and so do textinput's first-responder and keyboard-switch lines:
  `hwkey: usage 19 down via pressesBegan (none): to the Mac; the Mac types: en-US`,
  `…: the text system's; iPadOS types: zh-Hant`,
  `…; iPadOS types: the Mac repeats no key (a Sill for Mac before key repeat)`; `-SillInputScript`'s
  `type TEXT` hands the input view text as the on-screen keyboard does. Defaults taken
  (docs/hardware-keyboard-plan.md, open question 12): the Latin alphabet only, as a keyboard chosen in
  another script says which characters are meant and, with two keyboards, ⌃Space is iPadOS's (alternative:
  every keyboard that does not compose); Hawaiian left to iPadOS with Vietnamese (its input manager says it
  composes; whether it marks text for a hardware keyboard is a device's to show); the Latin keyboards that
  compose a letter with its accents (`UIKeyboardComposesText`: Czech, Slovak, Faroese, Navajo, Guarani…) the
  Mac's, as a hardware keyboard's dead keys make those and the Mac's input source has its own. Known: the
  iPad's hardware keyboard layout and Key Repeat settings no longer apply to the Mac's keys (the Mac's input
  source does); letters typed through iPadOS still never repeat. Verified: `key-strokes` 440 checks (55 new)
  and 115 of 115 mutants (16 new); `text-composition` 193 (15 new) and 102 of 102 (15 new); `key-repeat` 106
  (6 new: P held, P then E, ⇧A with ⇧ let go, A with Caps Lock, `KeyRepeat.generation`) and 37 of 37 (1 new);
  `compatibility` 145 (5 new: `keyRepeat` in the JSON, left out when nil, nil from an older host,
  round-tripped, skipped by an older reader) and 34 of 34; `run-all.sh`, all 57 (one at a time on the final
  code, each started under a load of 20; 2,720 s); `swift build -c release`, only the CaptureProbe warning;
  the iOS sources typechecked with and without DEBUG, and Debug and Release for the simulator and Debug for a
  device, only the StreamClient warning, the Release binary none of the DEBUG lines (the three builds on
  4bb51fb2; the last two commits typechecked both ways and built by CI); CI's "Build and check" green on
  4bb51fb2 and on f534be17; live on a private iPad mini simulator (iOS 27.0) against loopback synthetic hosts
  with the input log, keys from the rig: P held 2.3 s (key 35 down, "key 35 repeats after 0.50 s, every 0.033
  s", 55 repeats from 0.49 s at 30.6 a second, its up, no `insertText`), E held 3.3 s (85 repeats, no popover
  in the photo), ⇧A with ⇧ let go mid-hold (40 repeats with shift, then 40 without), Delete and Space (55 and
  56 repeats at the Mac's 0.5 s and 30 a second), A with Caps Lock on (25 repeats with caps lock and shift; 1
  with caps lock alone), ⌥E then E, Return, Tab, ⇧Return and ⇧Tab (Shift's own key around them); ⌘S, ⌘Z, Esc
  and ⌃Space with one keyboard the base build's events exactly; Zhuyin (ㄋㄧˇ, Return: 你 once) and Japanese
  Romaji (に) composing on the iPad as before; ⌃Space with Zhuyin and English iPadOS's switch, then P
  repeating on the Mac with English and composing ㄣ with Zhuyin; Russian's з typed once through iPadOS; the
  on-screen keyboard's `insertText "pe"` as text; a held P let up on the Mac when Sill went to the background
  (UIKit's `pressesEnded` at the switch) and when the keyboard went (the hold let go); and the gate: against
  this branch's host P went as a key (54 repeats), against 4504a96c's (no `keyRepeat`) P was typed once
  through iPadOS and Delete repeated by iPadOS, 20 separate presses, as before. The Mac's own press and hold
  applies as to its own keyboard (the repeats carry the autorepeat flag): in TextEdit or Notes with macOS's
  default a held E shows the Mac's accent menu and a held P types once; Terminal, iTerm2 and apps with
  `ApplePressAndHoldEnabled` off repeat. **Untested, for Noah** (Sill for Mac from this branch, the iPad with
  a Bluetooth keyboard and through Universal Control), in Terminal (or with the Mac's press and hold off):
  hold P (ppp… after the Mac's delay, at its rate), hold E (eee…, no accents on the iPad), ⌥E then E (é), ⇧
  held over a letter and let go (capitals, then small letters), Caps Lock, Space and Delete held; in
  TextEdit, a held E shows the Mac's accent menu, as the Mac's own keyboard does; a Chinese keyboard on the
  iPad (composes as before; ⌃Space switches); a keyboard layout on the iPad other than the Mac's (the Mac's
  wins).
- The review of the held letters (2026-10-29, after 79ace754; the report's "The review", sill-handoff's
  `triage/2026-10-20-reports/verdicts-2026-10-29/key-repeat-letters-report.md`). A letter typed or a Delete
  (a key held a tenth of a second) whose up a stalled link held back more than 0.4 s was typed again one to
  three times when a ping had come during the press, the host repeating while the device was heard in the
  last half second: on loopback against a synthetic host with a stand-in device (letters at nine phases of
  the pings, the up and what followed it held back), 12 of 27 at 0.45, 0.6 and 1 s, the four phases with a
  ping in the press. Now a key's first repeat waits for a word heard after the press and no earlier than
  `KeyRepeat.firstWord` (0.3 s) before it is due (0288e6cb): none of 45, a key held still first repeated at
  0.50 s; key-repeat 114 checks (8 new) and 42 of 42 mutants (5 new). Kept from an earlier attempt at the
  review, stopped at the usage limit: iPadOS's ⌃Space switch (two languages) let the keys held on the Mac go
  on repeating, as ⌃P, so they now come up at the Space (fbcf4b69, `ForwardedKeys.keyboardSwitch`; key-strokes
  450 and 118 of 118), and the Mac's `keyRepeat` is read in one checked place (a66a7fbc, `KeyTyping.macRepeats`;
  text-composition 194 and 105 of 105). The switch's DEBUG note is made only in Debug (f7374b10). For Noah: a
  key held and let go during a stall repeats on for up to half a second (measured: 3, 6, 8 and 11 more for an
  up held back 0.1, 0.2, 0.3 and 0.6 s), as the arrows always did, now Delete too; with two Latin keyboards
  ⌃Space stays the iPad's though the Mac types; a hardware letter ends what dictation can revise. run-all.sh
  57 of 57 (55 one at a time on 0288e6cb, key-strokes and text-composition with their mutants); CI green on
  0288e6cb and f7374b10. No simulator this time (the free disk stayed under the rules' 25 GB, other sessions'
  work): each of the first run's live runs replayed against the final host, its device events as its app logged
  them put through the real `ForwardedKeys`, gave the first run's numbers (P held 55 repeats, E 85, ⇧A 40 and 40,
  Delete 55, Space 56, Caps Lock's A 25 with caps lock and shift, ⌘Z 25, Esc 25, each first at 0.49 to 0.51 s).
- sillclient.py: `--key=USAGE,HOLD@T` (a key held, pinging four a second meanwhile, as a device) and
  `--ping=S`.
- Defaults taken (docs/hardware-keyboard-plan.md, open question 12): modifiers mid-hold change the
  repeats, never stop them; the silence pause; the floors; the accessibility-size taps. Known: while
  iPadOS types the characters, ⇧ let go while a hardware ⇧→ is held keeps selecting until → comes up (the
  text system keeps ⇧'s own key; while the Mac types them, ⇧ is a key it hears).
- Verified: `key-repeat` 100 checks (2,400 random sessions, 600 held to the exact cadence) and 36 of 36
  mutants (in CI's matrix); `key-strokes` 385 (32 new) and 99 of 99 (16 new, two retargeted to `press`'s
  new body); `run-all.sh`, all 56; `swift build -c release`, only the CaptureProbe warning; the iOS app
  Debug and Release for the simulator and Debug for a device, only the known StreamClient warning
  (StreamClient.swift:4110); H2 against origin/main's CLI from `git archive`: idle identical masked and
  sorted, with a client identical but for which seconds count the software encoder's
  `enc.mailboxDrop`; live on loopback synthetic hosts with the input log, eleven runs: ← held 1.2 s
  (the down, 21 repeats from 0.48 s at 29.7 a second, the up), a tap and a 0.3 s hold (none), ⌥←
  with ⌥ let go mid-hold (option, then none), ⇧ pressed mid-hold (shift, then none), ⌘Z (command),
  → over ← (← stops, → repeats), text (stops), pings stopped (repeats end half a second after the
  last), the client leaving (its key up, nothing after), a pick of none (stops; the up still goes),
  Esc. Not run: the key row's caps pressed on a screen. A scratch rig (the cap's SwiftUI Button and
  HeldCapStyle with HeldCap, pressed by Tests/touchrig's TouchSynth on a private iOS 27.0 simulator,
  deleted after) reached no SwiftUI control at all, through `sendEvent` or UIKit's HID entry point (iOS
  27 has no `UITouch setGestureView:`), so the press's report is untested; if SwiftUI never reports it
  the caps are taps as before, and a missed end is ended by the action.
- **Untested, for Noah** (a Mac build of this branch and the iPad with a Magic Keyboard): hold ←, →,
  ⌥←, ⌘→, Forward Delete and ⌘Z in TextEdit and a terminal: the first repeat after this Mac's delay
  and then at its rate, as the Mac's own keyboard (System Settings › Keyboard changes both), and
  nothing after the release; ⇧ pressed while → repeats selects; letters held repeat at iPadOS's own
  rate as before; Esc held in vim. Upright on the iPad mini and iPhone, hold the key row's esc, tab
  and arrows (repeats until the finger lifts; with ⌥ latched, word jumps), slide off a cap (it stops),
  turn the device while holding one (it stops), VoiceOver's double tap (one press), an accessibility
  text size's long press on esc (the large cap, one Esc). Wi-Fi off while holding a key: the repeats
  stop within about half a second. Sill.log's `[1s]` lines count `in.keyRepeat`.
**Nightly builds (2026-10-29, branch `nightly-builds` from main at 35a9c47c, PR #246; issue #134;
the brief and its Progress are in ~/Downloads/sill-handoff/nightly-plan.md, the procedure in
docs/release-checklist.md, "Nightlies").** Noah: "Setup the nightly build strategy" (the nine secrets set
2026-10-29), then, before the build: "hold off on giving the testflight build to public beta until I try it
out in Insiders first tomorrow". Merge "Version 0.5.5 for both apps" (PR #244, branch `version-0.6.0`) first.
- `.github/workflows/nightly.yml`: 09:17 UTC while the repository variable `SILL_NIGHTLY` is `true`, and by
  hand (`verify_only` forces the ad hoc, no-upload path); a scheduled night whose main is the sha at the end
  of the pre-release's notes builds nothing; only main publishes. decide writes the night's words once
  (`Scripts/nightly-notes.sh`: the pull requests merged since the newest `v<version>` tag) and fixes the
  date and build number (the commit count). Sill for Mac: the pure checks, then with `SILL_SIGN_IN_CI`
  release.yml's keychain and notary steps, the profile decoded from `SILL_PROVISION_PROFILE`, and
  `release.sh --nightly --publish` (built and checked as a release, but universal: `SILL_UNIVERSAL=1`, as the
  first nightly by hand and #62's word on the next version; no tag rule, the profile required) as
  `Sill-nightly-<yyyymmdd>-<sha7>.dmg` and `.zip` with their `.sha256` on the rolling pre-release
  `nightly` (never latest; its tag moved to the commit; the seven newest kept; the commit's sha last in its
  notes); else ad hoc artifacts. Sill for iPhone and iPad: `release-ios.sh --build-number <commit count>`
  (unsigned, export or upload as testflight.yml; with the key, `asc.swift groups` first, reads only, the
  real group names in the summary; an upload App Store Connect has already is skipped), then
  `Scripts/asc.swift distribute`: waits up to 90 minutes for processing, What to Test, every internal
  TestFlight group, and the public beta group (the external group with the public link) only while
  `SILL_NIGHTLY_PUBLIC_BETA` is `true`, with Beta App Review right after; asc.swift refuses `--public-beta`
  unless its environment says that too. Unset at first, on Noah's word.
- A nightly is 0.5.5 (N), N the commit count on both apps, never committed (the store release will be 0.6.0). The update check never offers
  one (`UpdatePolicy.feed` is /releases/latest, which lists no pre-release; `UpdatePolicy.release` refuses
  `prerelease: true`; "nightly" is no version), and offers a nightly nothing until a release newer than its
  version exists. A nightly reads the release's data-protection keychain items (same team, bundle ID and
  profile), so a device paired with one stays paired with the other.
- Also: release.yml's publish job decodes `SILL_PROVISION_PROFILE` too (the nightly turns on
  `SILL_SIGN_IN_CI`, which arms it; without the profile a CI release would have moved every Mac to the
  login keychain); testflight.yml takes the commit count as its build number; `release-ios.sh
  --whats-new FILE` (with `--upload`, `--api-key`) sets What to Test after an upload; make-app.sh's
  `SILL_RELEASE_NIGHTLY=1`; README's Good to know and site/download.html one line each.
- Verified (the plan's Progress has every number): asc.swift against a stand-in App Store Connect on
  127.0.0.1 with a throwaway P-256 key (each token's ES256 signature checked with openssl; header, claims,
  exp − iat 900 s), 114 of 114 checks over 21 scenarios and 23 of 23 mutants, the token in no output;
  release.sh's nightly mode and nightly-notes.sh against a stand-in gh in a synthetic repository, 103 of
  103 (the release path's 15 preflight cases and publish_release identical to origin/main's in words, exit
  statuses and gh calls); release-ios.sh against a stand-in xcodebuild playing run 40843967209's real
  .ipa, 48 of 48 (its App Store path identical to origin/main's); 30 of 30 mutants of the new shell paths caught (15 in release.sh's nightly mode and its release path, 7 in nightly-notes.sh, 8 in release-ios.sh's flags); the workflows: 5 files
  parse (PyYAML), 46 run blocks under /bin/bash -n, 200 structural checks (actions pinned by the commits
  already used, no expression in a run script, secrets only in env, the gates); nightly.yml's run blocks executed under /bin/bash 3.2 -eo pipefail with GitHub's output, env and summary files and the stand-ins, 44 of 44 (decide's skip rule on a schedule only, publishing only from main and not verify only, the notes through the outputs, the Mac's and the iOS mode matrices, `--public-beta` only for exactly `true`), and 8 of 8 mutants of its gates caught; a 12-minute real-time wait (the build listed after 11.5 min, a look a minute): 20 requests, every token valid, renewed once at 600 s; on GitHub
  `gh workflow run testflight.yml --ref nightly-builds` with `SILL_TESTFLIGHT_IN_CI` unset (`gh variable
  list` empty) → run 40843967209 passed: Xcode_27.1.app 27A9275, archived with CURRENT_PROJECT_VERSION=987,
  exported through the key; the downloaded .ipa says 0.5.1 (987) while the project says 4, signed "Apple
  Distribution: NOAH WILLIAM SAFFER (9B2KKVM937)", the App Store profile, get-task-allow false; nothing
  uploaded. Tonight's real notes: 36 pull requests since v0.5.1, What to Test 3,179 bytes. nightly.yml
  itself runs only once it is on main.
- The review (2026-10-29, after ba85e191; the plan's "The review"): seven findings, each reproduced, then
  fixed in a commit of its own. testflight.yml uploaded from any branch with the commit count, so a branch
  four commits ahead of main had the count of a later nightly, which took the branch's build for its own
  and gave it to TestFlight's groups (both workflows' run blocks in a synthetic repository): uploads only
  from main's first-parent line now, other branches export (7c62d6c1; the mode step 12 of 12, 9 before).
  The first nightly, published by hand that morning (0.5.5 (987), tag `nightly` at 150479b5), is universal
  and its notes give the TestFlight public beta link: the workflow's Mac job builds with `SILL_UNIVERSAL=1`
  (598d68be) and `nightly_testflight_link` keeps the link in every night's notes (0458239d; the hand-made
  pre-release taken over with the stand-in gh, 8 of 8, 7 before). A malformed .p12 or notary key ended at
  security's or notarytool's words with the file left until the cleanup: named errors in nightly.yml and
  release.yml (2623acee; 16 of 16, 4 before). The distribute step's 100 minutes equalled asc.swift's 90 +
  10 (measured: 300 s of processing, then 601 s for the review state): 110 (86e59547). Docs: the privacy
  manifest's ActiveKeyboards is PR #243's, on main (e3dbf133); part 2 contradicted Nightlies on the iOS
  build number, and a release must move main to the next version before the next night (df11fb07).
  Re-run, all passing: asc.swift 114 and the review's 9, 23 of 23 mutants, a 13-minute token wait (20
  requests, renewed at 600 s); release.sh and the notes 104 (a link check added); release-ios.sh 48; 31 of
  31 shell mutants; the workflows 204 structural checks and 46 blocks under bash -n, 44 of 44 run blocks
  executed; the signing run's artifact rechecked (0.5.1 (987), Apple Distribution, get-task-allow false).
  Not changed here, for the session that talks to Noah: the version (the handoff records his 08:55 UTC
  decision that pre-release builds say 0.5.5 and the release 0.6: #244 and these docs say 0.5.5 since the main session's fix-up of 2026-10-29) and the hour (09:17 UTC, applied the same way); PR #247's README and download-page words repeat this one's.
- The environments (2026-10-29, the security batch's item for the scan's findings 5 and 6; Noah: "the
  environments as a checklist step before SILL_SIGN_IN_CI goes on"): the nine secrets were repository
  secrets, which reach a run on any branch or tag, and release.yml and testflight.yml run by hand from
  any ref with that ref's scripts. release.yml's publish job now runs in the environment `release` (only
  `v*` tags; Noah its required reviewer, so a release waits for his click), nightly.yml's Mac and iOS
  jobs and testflight.yml's job in `nightly` (only main; no reviewer, so a night runs unattended). An
  environment without its secrets gives empty strings, so each job names the environment and what is
  missing when the run needs it: release.yml's first step, before the checkout (it also stops a run by
  hand that didn't start from the tag it releases); the nightly mode steps as before, in the
  environment's words, a notice when the iOS key is absent. decide builds nothing off main; testflight.yml
  runs from main only (its first-parent check kept). docs/release-checklist.md, "Secrets and variables":
  the step before the variables (the two environments with `gh api` PUT and their branch and tag
  policies, written from GitHub's REST reference and not run: nothing may be created here; the check
  with `gh api` GETs; the secrets with `--env`; the nine repository secrets deleted), and Nightlies'
  first run gains it as step 4; DEVELOPMENT.md's three paragraphs. Verified: the workflows' structural
  check 245 of 245 (its stale 03:17 rule moved to 09:17, 41 new for the environments; 25 problems on
  984d7f0c), 46 run blocks under /bin/bash -n; nightly.yml's run blocks executed 52 of 52 (9 failing on
  984d7f0c); the environments' run blocks 19 of 19 (16 failing on 984d7f0c); testflight.yml's mode 12
  of 12; the keychain steps 16 of 16; 15 of 15 mutants of the environment rules caught; the look's jq
  filters against the documented response shapes, on the live endpoint (read-only: no environment
  exists yet) and, when the work resumed after a usage stop, on other public repositories' real
  environments (a tag rule with a required reviewer, a `main` branch rule), the REST reference read
  again (the PUT's fields; the POST's `name` and `type`, 404 without `custom_branch_policies`, 303 for a
  rule already there); actionlint 1.7.12 with the `xcode-27` label declared: only the 17 shellcheck
  notes 984d7f0c has too; CI's Build and check on 5d2bb590 (run 40865615093). The checklist's
  TestFlight key line names the Admin key's own file, not the notary key's. The review (2026-10-29;
  four findings, all in the docs, each fixed in commits of its own; the report's "The review"): "What
  the environments don't do" understated the route through main: `nightly` holds the same Developer ID
  and notary keys as `release`, and the Admin key, so a commit on main reaches them, and the nightly
  Mac job's token that can publish any release, at the next run from main with no approval, and a
  ruleset requiring pull requests closes that only with a required approval, and then only against
  someone else's write access (78248187, 2596e910; a loopback run of the workflows' own steps on main,
  GitHub's rule emulated with Ruby's File.fnmatch, handed an attacker's release.sh the signing
  identity, the notary profile and the token, and release-ios.sh the key file); any `v*` tag waits on
  the approval alone, so What a tag does says to approve only the tag you pushed, on the commit you
  tagged (a7c6787e); testflight.yml no longer "exports other branches" (732c374f); steps 2 and 3 and
  the two variable lines lost their inline comments, which zsh as it starts hands to `gh` as arguments
  (39b9ecfd: pasted into `zsh -f -i`, 7 of 29 calls broken before, none after). The harness again on
  the head's workflows, unchanged by the review: 245, 52, 19, 12 and 16 of the same, 15 of 15 mutants.
  The second review (2026-10-29, on edda6b6e; the report's "The second review"): one finding, in the
  workflow. The approval is the tag route's gate, but the publish job checked out the tag by name, and
  given a ref actions/checkout v7.0.1 checks nothing against github.sha, so a tag force-moved after
  the run began (or right after the approval) built and signed another commit while Noah's look still
  matched (his local tag never moves). Reproduced on loopback (tag-move.py in nightly/tests: git
  daemon on 127.0.0.1, checkout's git sequence from its source, the job's own steps with stand-ins):
  the moved commit's release.sh got the identity, the notary profile and the token, a pushed tag, by
  hand and annotated alike. Now the checkout is `${{ github.sha }}` and the tag check stops the run,
  before the keychain and any build, when HEAD or the tag is not that commit (e6545f2b, with the
  checklist's What a tag does, a tag ruleset's part, DEVELOPMENT.md and release.sh's comment): the
  moved cases refused, the unmoved ones on. The harness on it: check.py 257 (12 new; 3 problems on
  edda6b6e), run.py 52, env-steps.py 26 (7 new; 4 failing on edda6b6e), tf-mode.py 12, kc-steps.py 16,
  rel-test 104, 21 of 21 mutants (6 new), zsh-paste 36 calls exact, actionlint's 17 notes as before.
- **Untested, for Noah (docs/release-checklist.md, "Nightlies", "The first run"):** the privacy
  manifest's ActiveKeyboards (#147's `UITextInputMode.activeInputModes`, ITMS-91053) is declared on main
  since PR #243 (54BD.1; release-ios.sh's check of run 40843967209's binary against main's manifest: every
  API declared). Merge #244, then this; the environments `release` and `nightly` with their rules, the
  secrets in each, the nine repository secrets deleted ("Secrets and variables", steps 1 to 3: the `gh api`
  calls were never run); `gh workflow run nightly.yml -f verify_only=true` and its artifacts (the iOS key
  from `nightly`); the first release through the environment `release` (its tag check passes on the
  run's own commit, which the run's page shows);
  `SILL_SIGN_IN_CI` and `SILL_TESTFLIGHT_IN_CI` true; a run by hand: the pre-release, the notarized dmg on
  a second Mac (quarantined: opens, drags, opens, the iPad still paired), TestFlight's groups (the real
  names: the step lists them) and What to Test; `SILL_NIGHTLY` true; after his Insiders test,
  `SILL_NIGHTLY_PUBLIC_BETA` true (Test Information filled in; the first build of a version reviewed in full).
**A copy of Sill.app takes no test hook, from this build on (2026-10-29, branch `sec-test-host-identity` from main
at 150479b5, PR #249; the security scan of 2026-10-18, finding 1, Medium; the security batch of 2026-10-29; the
report in sill-handoff's `triage/2026-10-29-security/f1-test-host-report.md`).** `AppModel.bundled`, the one gate
on every TEST ONLY hook that bears on who gets in (`SILL_TEST_REMOTE_DIR`'s trust list, `-requirePairing`, the
`-Sill…After` hooks, the doors' `SILL_TEST_*`: docs/home-pairing-plan.md §4.3), was
`Bundle.main.bundleURL.pathExtension == "app"`, the folder's name: Sill.app copied to a folder named Sill.bin, or
its executable started through a symlink or a hard link (Foundation then finds no bundle), read as the bare binary
and took them all, keeping Sill's grants (TCC keys them to the bundle ID and designated requirement; the scan's
premise, not tried). Now `bundled` is `AppIdentity.isSillApp` (Sources/SillMenuBar/AppIdentity.swift, pure but for
its reader) of four facts read once at launch: Sill.app when the running code's signing identifier is
`me.saffer.sill.mac` (the kernel's, SecTaskCopySigningIdentifier: every copy that can hold Sill's grants carries
it, and a file replaced after launch does not change it), when it is signed with any certificate or its signature
can't be read (fail closed), when its bundle's CFBundleIdentifier is Sill's, or, as before, in a `.app`. The one
test host is the bare binary as `swift build` makes it (identifier `SillMenuBar`, `adhoc,linker-signed`, no
Info.plist). Sill.app's code outside a `.app` says why first: "Running from …, which is not a .app, as Sill.app
itself (signed me.saffer.sill.mac): it takes no test hook." No wire change; the CLI unchanged. Builds from before
keep the old rule: 0.4.0, 0.5.1 and the nightly 0.5.5 (987) take every hook from a renamed copy or a link
(SECURITY.md names them; what that leaves open is the review's R1, for Noah, in the report).
- Verified: `swift build -c release`, only the CaptureProbe warning; `Tests/checks/test-host` (new, in CI's
  mutants matrix) 133 checks (1,344 combinations against an oracle; the reader for real on ad hoc copies of
  its own binary under `sandbox-exec`: signed again as Sill, a Sill.bin bundle, a hard link, a symlink, a file
  replaced after launch) and 22 of 22 mutants; `door-policy` 128, `keychain` and its 7 mutants; `run-all.sh`
  all 57. Live: the bare binary on loopback took `-requirePairing NO` (an unpaired TLS client admitted),
  `-SillSetAfter 'requirePairing=1'` (the next refused) and the `SILL_TEST_*`; the bare binary in a scratch
  Sill.bin with Sill's Info.plist, run only under `sandbox-exec` (no network, no LaunchServices database
  write, no TCC, no preference write, nothing written in the home folder), also signed ad hoc and through a
  symlink: the line, every hook "ignored", "Home door: TLS, pairing required (0 paired)."; origin/main's build
  in that bundle took every hook. Sill's real preferences byte for byte; LaunchServices' 43 records of Sill's
  ID the same before and after.
- The review (2026-10-29, after b0d9b03b; the report's "The review"), three lenses, four findings, each reproduced
  first, the fixes in commits of their own: R1, the fix holds for Sill.app built from it on, and a build from
  before keeps its rule: the nightly 0.5.5 (987)'s own Developer ID build, renamed Sill.bin under the same
  sandbox, took every hook ("Home door: TLS, pairing not required.", "Settings: require pairing off → on"), so
  SECURITY.md, the plan's §4.3 and this entry now say which builds (f562b4c3) and what that leaves open is Noah's,
  in the report; R2, out of the finding's scope, for Noah, in the report; R3, the reader's two fail-closed answers
  (a read that failed, an identifier with neither a certificate nor the ad hoc flag) were unchecked, three mutants
  turning them into a test host surviving: `signature(read:)`, pure, 12 checks and 2 mutants (7ce5874c); R4, two
  comments with the old rule, DebugHooks' header and the plan's §13 (b16d66c7). Tried and holding: this branch's
  build signed as Sill in a Sill.bin, every hook "ignored", "pairing required (0 paired)"; `CFProcessPath` and
  argv[0] do not move `Bundle.main` (a symlink does, and the kernel's identifier answers it). Verified after:
  `test-host` 145 checks and 24 of 24 mutants; `run-all.sh` all 57 (9 min 58 s); `swift build -c release`, only
  the CaptureProbe warning; the bare binary on loopback took `-requirePairing NO` (an unpaired TLS client
  admitted), `-SillSetAfter 'requirePairing=1'` (the next refused: "certificate unknown") and the `SILL_TEST_*`;
  previews 146; Sill's preferences, LaunchServices' 43 records and Sill.log untouched by the sandboxed runs. No
  iOS file and no wire changed, so the three iOS builds were not run.
- **Untested, for Noah:** a certificate-signed build reading itself (signing needs the keychain): with Sill.app
  from this branch installed as usual, Sill.log has no "Running from …" line and Settings › Devices and Remote
  Access work as before. Don't run a copy of Sill.app outside /Applications to see the refusal: a launched copy
  can register with LaunchServices for Sill's ID and take the login item (2026-10-20). Seen, not changed:
  LaunchServices lists 43 copies under Sill's ID (old worktrees' `.build/Sill.app`, `wt-mod157` among them, the
  Trash, scratch folders).
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
**A device's viewport held to what a host takes (2026-10-29, branch `sec-viewport-bounds` from main at
150479b5, PR #251; the security scan's finding 4, Low; Noah's go of 2026-10-29 for the batch).** Kind 9 carried
the panel and Aa's scale as Doubles with no bounds and the host took any number above 0: a viewport of 1e300 points
(or a scale of 1e-300) from any device a Mac admitted reached the window's fit (`fitToViewport`), whose "Resized …"
line made an Int of it, which traps, so Sill died with every device's session (the scan's chain with finding 3: its
Bonjour name then free for an impostor); with the virtual display `VirtualStage.windowSize` was unheld and the
"insists on …" line trapped the same way (a full-screen window's crop of an infinite panel was NaN, which
`evenPixels` traps on). No wire change.
- `ViewportBounds` (StreamProtocol's Viewport.swift, pure, `Tests/checks/viewport-bounds`): each side 1 to 16384
  points, a text scale 0.25 to 4 or none. The host refuses any other viewport whole at kind 9, and one that does not
  decode (JSON carries no NaN or infinity): the last viewport stands and nothing of the message is taken, its rate
  neither; one line naming the device, at most one a second per connection ("Viewport from sillclient refused: width
  1e+300 (1 to 16384 points), height 1e+300 (1 to 16384 points)"), `vp.refused` in the `[1s]` lines counting every
  one. Every device build's viewport is within them (the compatibility floor's new line), and a device holds what it
  sends to them (`held`, in `sendViewport`). The two lines print through `ViewportBounds.whole` (Int()'s number,
  toward zero, without its trap); no other host line prints a device's number through Int() (a click's point is held
  to the source by InputLanding, the rest are the Mac's own).
- The window's size on the virtual display held to 1…65536 points a side, the most a host takes (16384 points at
  0.25; `VirtualDisplaySize.windowSize`, `Tests/checks/capture-scale`): every viewport a host takes is asked as before
  (a side under half a point 1, not 0), the placement fits it to the display, and a full-screen window's crop keeps
  the panel's shape (the review's second finding: held at the display's 4096 it did not).
- `sillclient.py --raw9=JSON@T` sends a literal viewport.
- Verified: `viewport-bounds` 79 checks and 26 of 26 mutants (18,566 of its 200,000 random viewports main's guard
  took and its line trapped on, none taken now), `capture-scale` 172 and 48 of 48; `run-all.sh`, all 57; `swift
  build -c release` from `git archive`, only the CaptureProbe warning; the three iOS builds, only the known
  `StreamClient` capture warning; live, a loopback synthetic host streaming the test pattern: 1e300, -1, NaN,
  Infinity and a scale of 1e-300 each refused with its line (NaN and Infinity: "it does not decode as a viewport"),
  three in 0.4 s one line and `vp.refused 3`, 16384 points at 0.25 taken, the stream going throughout (47–58 frames
  a second). main's own lines (the handler, the fit's guard, target and line, the stage's window size and line, cut
  from 150479b5 and compiled with its Viewport.swift) trap on the scan's payload and on a scale of 1e-300 (exit
  133); the branch's refuse and go on. Not live on main's host: only a real window resized through Accessibility
  reaches that line, which no test host lists.
- The review (2026-10-29, after a02c1afe; the report's "The review"): two findings, each reproduced first and fixed in
  a commit of its own. (1) f664a04d: a device's ClientStats `audioLate` was added to the stats line's count with a
  plain `+` (StreamServer, from the audio work, after the scanned commit), so two reports of Int.max within the line's
  1.5 s trapped: a loopback host built from a02c1afe died at the third report (exit 133), and lived with 1000; now
  `ClientStats.lateSince` (Viewport.swift, pure: nothing for a missing or negative count, the sum stopping at
  Int.max), and the rebuilt host took ten reports of Int.max and printed "9223372036854775807 late". (2) 972e2b87: the
  window's size on the virtual display held at 4096 changed a full-screen window's crop for a panel past the display
  (from the commits' own lines, a 2560×1400 panel at 0.5x: main 4096×2240, 1.829:1, the panel's shape; a02c1afe
  4096×2800, 1.463:1, black bars on the device); now 65536, every row as main's. Re-verified: `viewport-bounds` 87
  checks and 30 of 30 mutants, `capture-scale` 175 and 50 of 50; `run-all.sh`, all 57 (8 min 16 s); `swift build -c
  release` from `git archive`, only the CaptureProbe warning; the three iOS builds, only the known `StreamClient`
  capture warning; live on one loopback host, every kind 9 above refused again with its line, and the review's tries
  (1.7976931348623157e308 refused, as -0 and 5e-324 were in a run on a02c1afe; 1e999 and a rate of 1e300 "does not
  decode"; a duplicate key and a rate of Int.max taken, the rate held by `wantedFPS`; a rate of Int.min, on a02c1afe,
  a restart at 24 fps), beside them a second client's ten stats reports of Int.max: the host alive throughout.
- A second review (2026-10-29, after 37e47e68; scripts and logs in sill-handoff's
  `triage/2026-10-29-security/f4-live/review2/`): one docs fix, e057acaf (DEVELOPMENT.md gave the refusal line's
  limit per device; it is per connection: one device on two connections got two lines 0.11 s apart). No bypass: 92
  hostile payloads of every kind a device sends but 19 and 32, on a loopback host with a scripted pointer, every ping
  and kind 17 answered; 2,178 viewports a host takes in 15 s from two devices (236 restarts), the host streaming
  after. Re-run: `viewport-bounds` 87 and 30 of 30 (five more mutants of the reviewer's caught), `capture-scale` 175
  and 50 of 50, `compatibility`'s mutants 34 of 34 (one of Viewport.swift); `run-all.sh`, all 57 (8 min 28 s);
  `swift build -c release`, only the CaptureProbe warning; the three iOS builds, only the known `StreamClient`
  capture warning. Built, as the first review had not: the pacing harness from origin/main and this tree (`home`:
  60.0 fps both, every gate), the audio harness and the restore probe's driver (not run).
- **Untested, for Noah:** nothing should change on a device: Aa's steps and none, a rotation and the virtual display
  as before on the iPad and iPhone, and Sill.log without a "Viewport from … refused" line; if an iPad with Stage
  Manager on a large external display is at hand, a full-screen window (a video) on the virtual display at Aa 0.5x
  fills the panel as on main.
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
**Aa's Off, and Aa only for a window (2026-10-29, ArfiArfath21's PR #181 with maintainer edits, branch
`aa-off`; issue #179, taschaub).** Noah's decisions of 2026-10-29: the Off detent ("off makes more sense
than 1x"), and Aa not selectable while the Desktop streams ("misleading"). `TextScale` (pure,
StreamProtocol; `Tests/checks/protocol`) holds Aa's detents: Off, one step left of 0.5×, is no scale (the
Mac leaves the window alone) and an untouched Aa reads Off; no Off while the window streams on the Mac's virtual
display (`offersOff`: no scale is 1× there, so an untouched Aa reads 1×), judged by the running stream's
`onVirtualDisplay` while a window streams (the review: Virtual Display on with the window streaming in place has
Off), else by the setting; Aa usable only while a window streams
(`selectable`): over the Desktop or nothing every bar (sideways, the halves, a phone's row 1, the Duo's)
dims it to 35 %, its ruler never opens, a ruler open when the window stops streaming folds without
applying, VoiceOver hears "Text size, Off, dimmed, adjustable, Available for a window." and a swipe changes
nothing (one view and one element whatever streams, as a disabled slider: the review); the value stays for
the next window. The ruler's frame shows two detents each side of the thumb whatever the
detents (`TextScaleControl.detentsEachSide`): every bar's ruler keeps main's width, a phone's row 1 its
room (the contributor's grew a step and ran past the phone's row). Host: a device's viewport going from a
scale to none (`TextScale.endsFit`, per connection, `fitScales`) puts the windows Sill sized back at once
(`restoreFits`: whole, its own size where it was moved, left if resized on the Mac) and looks at the
catalog again, so the stream restarts at the window's own size; `win.fitOff` in the `[1s]` lines. Sill for
Mac 0.5.1 takes Off only as a stop to the fitting: it never puts a window back (#57 came after it). The tour's
rows say when: "Aa: while a window shows, touch it and slide …" (the review) and VoiceOver's "Swipe up or
down on it while a window shows." DEBUG: `-SillScaleScript '<s> <scale|off>[; …]'`, the AX dump's value,
hint and traits. The review (2026-10-29; its report has each finding, how it was reproduced and the
re-run): Off by where the window streams (`efcf9177`), 0.5.1 never puts a window back (`2cc12973`), the
tour's sighted row (`00efae53`), the Desktop's stream never deciding, in `TextScale` and checked
(`a9e4b458`), Aa one view and one VoiceOver element (`95e9e794`: a conditional adjustable action made a new
one at every change of what streams), the docs (`26206e0d` and the next). Verified: protocol 272 + 8 checks
and 61 of 61 mutants (19 TextScale's), window-restore 41,936 (the model's Off from one of two devices: each stop where the
person expects it) and 95 of 95, tour 84 of 84, run-all 56; the
three iOS builds (only the StreamClient capture warning) and `swift build -c release` (clean, only CaptureProbe's);
harness photos in every bar (iPad and phone sizes on 27.0, the Duo's six poses on an iPhone Duo on 27.1, 17 cases
each) at the default and accessibility-extra-large sizes against main's build: Aa closed at 1×, at 1.25× with its
ruler, and on Sill's virtual display closed and with its ruler pixel for pixel main's, the ruler at 1× (and at
1.25× on a 320 pt phone) main's but for the track's faint left end, the strip's fading end as noisy as main's
against itself; live against a synthetic host: Aa dimmed over its Desktop, VoiceOver's words, viewports 1 → off
→ 1.25 → off, `win.fitOff 1` at each Off. Untested, for Noah: on the iPad with Virtual Display off, Aa on a window to 1.25×, then Off: the window
back to its own size at once (Sill.log's "Restored …"), and a later pick of it not resized; Aa dimmed over
the Desktop, VoiceOver too (with its focus on Aa, the window closed on the Mac: the focus stays on Aa); the
ruler's six detents in each bar; with Virtual Display on, no Off and 1× untouched (Off while a window streams
in place, the Settings panel's note saying why); two devices (only the one whose scale it was ends the fit
by Off); with Sill for Mac 0.5.1, Off only stops the resizing.
**The hold before a thumbnail's lights (2026-10-29, branch `thumbnail-hold-stepper` from main at 35a9c47, PR #248; issue #113,
promised on the issue as "lower the time … and have it be user adjustable").** Noah, 2026-10-29: "The hold time should
be patched and editable with a slider in settings (one of those fancy ones with the +/- buttons that increment by 0.1
seconds, ideally the timer can go from 0.2s to 3s or something like that." Device only: no wire change, never sent.
- `ThumbnailHold` (pure, `Tests/checks/thumbnail-hold`, 82 checks and 32 mutants, in CI's matrix): 0.2 to 2 s in
  tenths, 0.5 s unless changed (it was a fixed 1.5 s; iOS's own long press, which the reporter cites), counted in whole
  tenths so no sum of steps drifts; `Sill.thumbnailHold` (a Double; `-Sill.thumbnailHold 0.3`'s string too); the words.
- WindowStrip reads it at launch and on each change (every bar: sideways, an iPad's window bar, a phone's row 2), and
  HoldDragOverlay gives the long press already on screen the new length; the drag to another slot starts from the
  same hold. Its 12 pt (a scroll before the hold) and 8 pt (the lift after it), and the picture's 0.45 s right click,
  are unchanged. DEBUG: the console's `thumbnails: hold 0.5 s` at the first read and each change.
- Settings › This iPad (or iPhone), after Reverse Scrolling: Hold to Show Window Controls, its length ("0.5 s") and
  the system's stepper (− dimmed at 0.2, + at 3), the title beside them while it has room for its three lines with
  every word whole (`ThumbnailHold.titleLines`; ViewThatFits and a small Layout, `WrappingTitle`), else over them, and
  the row never wider than the panel offers it; one adjustable VoiceOver element,
  "Hold to show window controls, 0.5 seconds" (iOS 27's stepper alone is two buttons read with the whole label), its
  footnote next. `-SillSettingsScroll hold`. Site words (support's section, privacy's item) marked `<!-- Thumbnail
  hold`; the next What's New's paragraph. Not taken from the branch `thumbnail-hold` (2026-10-20, 1 to 5 s, never a
  pull request): its pressed state from touch-down and its fix of the lights' VoiceOver labels; #164 (addhumal, a
  picker of five lengths) predates Noah's stepper.
- Verified: the three iOS builds and `swift build -c release`, only the known warnings; `run-all.sh`, all 57; on a
  private iPhone Duo simulator (iOS 27.1, the cover display: the harness draws 1000x710 at 0.65, turned), with a driver
  injected into the Debug app (the touch rig's synthesized touches; the scratchpad's, not committed): a press at the
  default began the hold 0.505 s after touch-down and showed the lights, 0.35 s was a tap; at 0.2 s 0.205 and a 0.1 s
  tap; at 3 s 3.008 and nothing at 2.75; main's build 1.510 and nothing at 1.3; a change while the strip showed (1.2
  s) reached the thumbnails at once; drags to another slot at 0.5 and 0.2 s; a swipe across the strip still scrolls at
  both; VoiceOver's swipe up and down a tenth each way, held at 0.2 and 3 s. Photos at 1000x710, 710x1000 and 500x710,
  default and accessibility-extra-large: the bars and the panel's top main's to the pixel but one switch's knob edge
  (9 px at Δ1), the panel above the new row within Δ1. Live against a loopback synthetic host (no screen, software
  encoder): the row changed five times, nothing reached the host.
- The review (2026-10-29; the report's "The review"; an earlier pass, cut off after its first two commits, then this
  one): three findings, each reproduced on a private iPhone Duo simulator (iOS 27.1) against ae3d412's and main's
  builds and fixed in a commit of its own. In a narrow panel the title squeezed beside the stepper (an iPad window as
  narrow as Slide Over, 320x951, and a 320 pt iPhone, 320x693: four lines at the default size, seven at xxLarge with
  "Win-dow" and "Con-trols"; the cover on its side at xxLarge: four); it stacks now (eb56ca7; the check's 82 and 32
  with it). On the cover upright at xxLarge the row came to 298.333 pt in 298 (its lines rounded to the pixel at the
  edge of fitting) and `rowFrame`'s frame, a maximum alone, passed that on: every row of the panel and its edge a
  third of a point over, the panel's top 17,442 px from main's (accessibility frames 298.333 against 298); the row's
  frame now takes what it is offered (3152061). A comment still said 1.5 s (661624a). Re-run on the final code: the
  three iOS builds clean, only the known warning; `run-all.sh`, all 57 (493 s); the check 82 and 32 of 32 mutants;
  `swift build -c release`, only the CaptureProbe warning; photos in the Duo's six poses against main's build (the
  bars, the panel's top and the panel above the new row main's, but for Δ1–2 that retakes show as noise or as 148 px
  at Δ1 on the halves' switch, as before), the narrow panels stacked, the row elsewhere ae3d412's to the pixel but for
  the cover upright at xxLarge, its panel's edge main's again; the rig on every bar (sideways, the halves, a 320 pt
  iPad window's sliver of a thumbnail, the laptop and book poses, the cover upright and on its side): the hold began
  0.505–0.507 s into the press, 0.205 at 0.2 s, 3.009 at 3 s, main 1.505; VoiceOver's steps and ends, the stepper's
  taps, a relaunch keeping 0.6 s, a Mac without kind 16; live through a recording relay, the row changed seven times
  and the device sent only pings and its stats meanwhile.
- **Untested, for Noah:** on the iPad and iPhone, a thumbnail's lights at half a second and the drag after them;
  Settings › This iPad's stepper from 0.2 to 2 s and a hold at each end; a swipe across the strip at 0.2 s (no lights);
  VoiceOver's reading and its swipes; the row at the largest text sizes (the panel stops at xxLarge: the title in three
  lines beside the stepper, over it in a narrow panel, an iPad window in Slide Over or a phone with Display Zoom); Voice
  Control, Switch Control and Full Keyboard Access on the row (one adjustable element: its − and + are no elements of
  their own); a Magic Keyboard trackpad's or a mouse's click and hold on a thumbnail.

**Pinch to zoom (2026-10-28/29, addhumal's PR #196 with maintainer edits; issue #65).** Noah's decisions of
2026-10-19/20: pinch to zoom, not a slider; Photos-like, centred on the point between the fingers, the Mac's cursor
not involved; a slight pinch out stays zoomed and only a pinch all the way out (or a lift within 2 % of it) gives the
whole picture back; cap 5×. `StreamZoom` (pure, `Tests/checks/stream-zoom`, 105 checks and 30 mutants) owns the zoom
and the two-finger stroke; InputOverlay maps every touch and scroll through it so taps, clicks, the Pencil, hover and
scrolls land on what shows under the finger; `ZoomedStreamView` scales the picture; three fingers stay the Mac's
gestures and undo a zoom they interrupt; a turn or another layout keeps the zoom, another source resets it; nothing
is sent. Harness: `-SillZoom`, `-SillHitTest`, the input script's `pinch` and `touch`; the touch rig's zoom strokes
(`RIG_ONLY=zoom`). Verified (the verdict in the handoff): the check and mutants, run-all 56, the touch rig 72 of 72
against main, photos at 1×, 2.5×, 5× and after a full pinch out. Untested, for Noah: on the iPad and iPhone, the pinch
following the fingers, a two-finger scroll at 1×, moving a zoomed picture, taps and the Pencil landing under the
finger, three-finger gestures over a zoomed picture, a turn, Larger Picture, ProMotion smoothness, VoiceOver.
**Trackpad and wheel scrolls stay under the pointer (2026-10-28, PR #217 from andrewgribben's
`trackpad-scroll`, maintainer edits on it, main at 6c5b5d24 merged in; issue #130; the findings in
docs/hardware-keyboard-plan.md, "#130 and PR #217").** #217 read each scroll pan's reading as that event's
own movement on a Magic Keyboard, so that main's diff of a running total (#80) "sent almost nothing", and
added three stats keys. Checked on a private iPad simulator (iOS 27.0) with keyrig, a probe app of pans
side by side and Sill's own build against a loopback synthetic host with `SILL_TEST_INPUT_LOG=1`: the
translation is a running total, as a finger's (a wheel's notches 3, 6, 9 pt), and main's build and #217's
posted the same wheel scroll event for event. The issue's reports were of 0.5.1, whose finger pan had no
scroll mask (a pan's default is 0, read there): no trackpad scroll reached it at all. Device only but for
a TEST ONLY log line; no wire change.
- What was wrong: UIKit moves a scroll pan's location on by its translation while the pointer stays put
  (the pointer at y 308.8, the pan at 311.8, 314.8, 317.8), and InputOverlayView posted the scroll, its
  end and its coast at that location: on the host ten notches walked from y 447 to 497 of the test
  pattern's 949 and a phased scroll from 459 to 636, so the Mac scrolled the window under the pointer at
  first, then whatever the point reached. `PointerScroll` (pure, in HardwareKeyboardPolicy.swift): every
  event of a trackpad's or a wheel's scroll goes where the pointer was as it began, the pan's first
  location less its first reading (on the host at y 442 throughout, the amounts unchanged). A finger's
  pan is as it was.
- Kept from #217: each reading taken and the pan's translation zeroed (the movement since the last event
  whether UIKit adds them up or not); `PointerScroll.total` adds the readings up for the scroll path's
  diff, so the shared path, the DEBUG input script and `scriptScroll` are main's. Gone:
  `minimumNumberOfTouches = 0` (the trackpad's pan began without it through Universal Control on
  2026-10-15), `in.scrollMiss` (could not count for a Sill device: both ends hold a scroll inside the
  picture), `in.scroll0` (every coast's sub-point tail), `in.scrollY` (a sum among counts, for amounts that
  were never lost) and `Stats.add`.
- TEST ONLY: the input log's scroll line says where it lands ("Test input: scroll dy 6 dx 0, wheel (none)
  at 833,442"). DEBUG: one `scroll:` console line a pointer scroll: how far, where, and how far UIKit's own
  location for the pan had run from there ("scroll: wheel ended by 0.0,102.7 pt at 450.8,268.8; the pan's
  own location ended 0.0,102.7 pt from it").
- Verified: `hardware-keyboard` 62 checks (11 new) and 37 of 37 mutants (6 new); the touch rig 72 of 72
  against main; `run-all.sh`, all 55; `swift build -c release`, only the CaptureProbe warning; the
  iOS app Debug and Release for the simulator and Debug for a device, only the known `StreamClient`
  capture warning. Not seen: a real trackpad's events in the continuous pan (none reached it in the
  simulator: keyrig's mouse and its phased events go to the discrete pan, and a virtual touch pad's
  digitizer frames came as touch events).
- **Untested, for Noah** (the iPad with the Magic Keyboard, a Debug build from the branch): two fingers on
  the trackpad scroll a window and the Desktop the whole way, under the pointer (a long scroll down and up
  in Safari and in Finder's list); a flick coasts once (note a double coast: the content running on twice
  as far, or a second stretch after the first ends); a mouse's wheel, one notch and a spin; the console's
  `scroll:` lines say whether the pan's own location runs on there too.
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

**Tiles, Virtual Display and Send Audio on by default (2026-10-27, branch `defaults-tiles-vd` from main at
3c257485, fast-forwarded to 3b546374 (#234) before its first commit; PR #236).** Noah, 2026-10-27:
"make tiles not list the default behavior of the app. Also have Virtual Desktop on by default. Of
course, if a user changes a setting remember their choice for future sessions as you do now. Make
this a separate PR after #117 merges." Later that morning, testing #235: "Send Audio should be on
by default, and mute should be off by default." No wire change.
- Sill.app's Send Audio is on by default too (`HostConfig.app.sendAudio`; the CLI's `--audio` still
  opts in; a saved `sendAudio` wins, so a Mac whose user turned it off stays off): the menu's
  checkmark and Settings › Streaming's switch start on; README's Good to know, support.html's Sound
  section and privacy.html say so. Mute on the device was off by default already (#235).
- The device: the connect screen shows tiles unless its person chose the list
  (`ConnectionList.defaultStyle`, `storedStyle`: a stored `Sill.connectionStyle`, "list" or "tiles",
  always wins; nothing stored, or a value no build writes, reads as tiles). ConnectScreen keeps the
  key optional (`@AppStorage … String?`), so the rule alone decides, as StreamClient's
  `connectionStyle` already did. So a picture of each saved Mac's screen is kept by default
  (`takesPreview`, unchanged: only with tiles), and Disconnect asks for its fresh keyframe by default
  (300 ms at most before the connect screen with Sill for Mac 0.5.1, which skips kind 44). The switch
  beside the title always shows, whichever style is on and whether or not a Mac is listed (Noah,
  2026-10-27: "The list/tiles switch should always show"; #117 showed it for tiles alone, which with
  tiles the default took it away under the finger of someone with no saved Mac who chose the list).
  DEBUG: `-SillStyleToggleAt <s>[,<s>…]` toggles the style as
  the switch does (`toggleStyle`); the console's `connect:` lines.
- The Mac: Sill.app registers `HostConfig.app` (HostSettings), the CLI's `standard` with the virtual
  display on. Registered, never written: a `virtualDisplay` key set from the menu, Settings ›
  Virtual Display or a device always wins (a Mac that turned it off stays off; this Mac's own keys read 1 for
  both on 2026-10-27, set by hand, so nothing changes here), and `-virtualDisplay 0` turns it off for one run. The CLI keeps `standard`: `--virtual-display`
  opt-in, its stdout byte for byte. The menu's checkmark and the pane's switch follow `config`; no
  pane names the default.
- The virtual display at 1x, the caveat of that decision: not in the session of 2026-10-26/27.
  Beside the 2560×1440 display at 1x every staged capture that night read "scale 2.0" (`filter
  (1456.0, 1486.0)`, `(2560.0, 1486.0)`, `(2560.0, 2264.0)`); its "scale 1.0" captures were real
  windows and the Desktop on that display (#233's case). Sill.log's 1x displays were five earlier
  ones (2026-09-26, 09-28, 10-08 twice, 10-15), each asked with both sides under 800 points, 754×784
  or 762×792: an iPhone held upright (its 377- or 381-point picture doubled for Aa's smallest step)
  and the menu bar, beside the Mac's own Retina display too, so the main display's scale played no
  part. macOS listed the 2x mode asked for, `selectRequestedMode` asked for it every half second,
  and the display stayed at 800×832 points at 1x until the stage's 3 s wait ran out ("online 3312
  ms"): the pick waited 3 s more, and the staged window was captured at 2x from a 1x display (eleven
  captures `filter (800.0, 832.0) scale 1.0`). Every display with a side of 800 points or more came
  up at 2x (754×979, 838×792, 900×800, 1000×784, 848×878 and larger). The fix, `VirtualDisplaySize`
  (pure, in CaptureScale.swift, checked by `Tests/checks/capture-scale`): every side 800 to 4096
  points, so an iPhone upright gets 800×830; VirtualStage's `envelope` and `ensureDisplay` use it.
  The creation line prints the mode the display came up at (`VirtualDisplay.currentScale`; it said
  "@2×" whatever came up), and `--virtual-display-selftest [Hz] [WxH]` makes another size.
- Words: README (How it works: the connect screen's tiles, On iPhone, Text size and the virtual
  display with it on by default; Good to know), site/support.html (a section, "A window left your
  Mac’s screen", whose sentence on the default is marked `<!-- Virtual Display` for its release; "It
  says Not paired"), site/privacy.html (the tiles' items: kept unless the list is chosen; "touch and
  hold it"; dated October 27, 2026; the virtual display needs no word there, Accessibility "so Sill
  can move and size the window it shows" says it already), docs/release-checklist.md (the marker,
  its perl line and grep), docs/app-store-metadata.md (the description's "Your Mac shows up.", 3,032
  characters; the next What's New's tiles paragraph, 232, the draft 1,805), docs/DEVELOPMENT.md, the
  checks README.
- Verified: `swift build -c release`, only the CaptureProbe warning; `Tests/checks/run-all.sh`, all
  55 (562 s); mutants: connection-list 162 checks and 76 of 76, capture-scale 148 and 39 of 39,
  away-quality 96 and 30 of 30 (after #235's merge: its acceptance mutants and the app defaults'), virtual-display-api (VirtualDisplay.swift changed) 17 of 17; H2
  against main at 3b546374 from `git archive`, `--synthetic` on loopback (software encoder, no
  router, no screen): idle 35 s identical masked and sorted (8 lines), with `sillclient.py PORT 8
  desktop` identical (23 lines; a first pair differed only in which counters three stats lines
  listed, `cursor.shape` among them); the bare SillMenuBar `--synthetic` (domain deleted before and
  after): no key, "Virtual display: private CGVirtualDisplay API present…" and "✓ Virtual Display";
  `-SillSetAfter '2 virtualDisplay=0'`, one "Settings: virtual display on → off" and the key 0; a
  relaunch, off; `-virtualDisplay 1`, on for the run, the key still 0; main's binary with no key,
  off; previews from both bare binaries at one path, 146 files each, only `menu.txt` (the
  update-available sample's ✓ Virtual Display and ✓ Send Audio (Beta)), `pane-virtualDisplay-light.png`,
  `-dark.png`, `pane-streaming-light.png` and `-dark.png` differ, each pane only in its switch; the iOS app
  with Xcode 27.1 (27A9275), Debug for the generic simulator as CI builds it, Release for the
  simulator, Debug for a device, only the known StreamClient capture warning
  (StreamClient.swift:4110); on a private iPhone Duo simulator on iOS 27.1 (its cover display), the
  29 connect cases at 466×678 and 951×669 against main's Debug build: this build with nothing stored
  and main's with tiles stored, 57 of 58 pixel for pixel (the 58th the pairing case's spinner, which
  differs from itself); this build with the list stored and main's with nothing stored, 44 of 58, the
  rest the switch beside the title, which this build always shows (the verifier's photos of 04c9f226;
  the author's, before 70423d1a, had the switch only with a saved Mac listed); the normal app, a fresh install against a synthetic host
  registered as `_silltest._tcp`: tiles, toggled to the list (stored "list"), a relaunch the list,
  toggled back (stored "tiles"), a relaunch tiles, the key read from the app's container plist
  (`simctl spawn … defaults read <container>/Library/Preferences/me.saffer.sill.plist`; the domain by
  name reads elsewhere); `SillHost --virtual-display-selftest 60 800x830` once, at 05:05 with this
  Mac idle 601 s and no device connected: online at the requested mode in 446 ms, 1600×1660 px @2×,
  a 30-point menu bar, gone 158 ms after (its HID move reset the idle time). Not run: Sill.app,
  anything with a device, a staged window on 800×830.
- **Untested, for Noah:** on the iPad with this build, a fresh install (Sill deleted first) shows
  tiles; once a Mac is paired the switch beside the title shows; to the list, quit Sill from the app
  switcher and reopen: the list; back to tiles, reopen: tiles; an install that chose the list keeps it.
  On a Mac whose `virtualDisplay` was never set (another Mac or user account, or, with Sill quit,
  `defaults delete me.saffer.sill.mac virtualDisplay sendAudio`; this Mac's read 1, set by hand, so it
  is on here already): the menu shows ✓ Virtual Display and ✓ Send Audio (Beta), a device hears the
  Mac's sound at once (beside the Mac it doubles every sound a moment late until Mute), a window
  picked moves onto the virtual display (Sill.log "Virtual
  display … @2× id …: created", "Moved …", "Capturing … of virtual display") and comes back at
  Disconnect; the switch turned off stays off after a relaunch. With the iPhone 15 Pro upright and
  the virtual display on, a pick's display is "Virtual display 800×830 pt @2×" with no "online but not
  at" line, and the window's text crisp.
**Send Audio and Mute in the device's Settings panel (2026-10-27, branch `sound-toggle` from main at
b4caa91, main at 3b54637 (#117, #234) merged in, not rebased; PR #235; the bullet "Two switches" in the
sound's entry below and docs/audio-plan.md's last section have the details).** Noah: "I've decided the
audio setting should not be in the main button tray but instead in settings. Sound should be a toggle in
the settings menu." Two switches in the device's Settings panel: **Send Audio** (the Mac's group, its
"Beta" tag), which a device turns on and off for every device as it does Quality (the host accepts kind
17's `sendAudio` again and Sill.app saves it, no picture restart; a Mac from the beta refuses it and the
switch goes back; for a Mac without sound the row is off and disabled, "Update Sill on ‹Mac›…"), and
**Mute** right under it (`soundMuted`, the device's own, off by default; Noah, 2026-10-27: "right below
the Send Audio setting"), shown for every Mac with sound, Send Audio on or off. No Sound button in any bar.
- Merged with main at 3b54637 (2026-10-27: #117, the connect screen's tiles, and #234, the capture scale
  follow-ups; one merge commit). Only iOSClient/ContentView.swift conflicted, in SettingsScript's doc
  comment: both kept (this branch's `set … sendAudio` and #117's `disconnect` step). CLAUDE.md,
  Tests/checks/README.md (both sides' rows: #117's `connection-list` 154 and 72, #234's `capture-scale`,
  this branch's `away-quality`, `ledger`, `phone-portrait` and `tour`), DEVELOPMENT.md, MockCatalog.swift
  (#117's `tiles` connect case beside this branch's settings cases), StreamClient.swift and
  site/privacy.html (#117's Tiles items beside the Sound item, the date October 27, 2026) merged by
  themselves. Verified on the merge: `swift build -c release`; the iOS app, Debug for the generic
  simulator as CI builds it, only the known `StreamClient` capture warning (StreamClient.swift:4067);
  `run-all.sh ledger away-quality phone-portrait tour connection-list capture-scale`, all passed (100,
  89, 484, 111,189, 154 and 122 checks).
- **Untested, for Noah:** the bullet "Two switches"' list (Send Audio from the iPad's panel heard on
  the iPhone too, Mute on one device, Mute before the sound is turned on elsewhere, VoiceOver on both
  switches, this iPad against a Sill.app from the beta and against 0.5.1).
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

**Capture scale follow-ups (2026-10-27, branch `capture-scale-followups` from main at b4caa910; PR #234).**
The post-merge verification of #233 (sill-handoff's
`triage/2026-10-20-reports/verdicts-2026-10-26/pr233-verdict.md`) left small follow-ups, all taken here.
Host only: no wire change, no device file.
- A window's odd side, drawn whole (`CaptureScale.windowPixels`, `windowSize`, `windowNeedsRestart`,
  pure): on a 1x display a 1117×610-point window was asked 1116×610 (`evenPixels`, down to even), and
  ScreenCaptureKit, which only scales a window down (`scalesToFit` left false), shrank its 1117 columns
  into 1116: up to half a pixel of blur mid-picture, where a text stem is one pixel wide. A window
  captured at its display's own scale is drawn 1:1 at the buffer's top-left, so an odd side now rounds
  up to even: 1118×610, one black column past the window (Sill.log's 818×565, 728×535 and 377×235:
  818×566, 728×536, 378×236); a half point on a 2x display the same; Standard on a 2x display (scaled
  down anyway), the Desktop, a staged crop and the test pattern as before. Chosen over asking even
  points in the Aa fit (`fitToViewport`), which would reach only windows Sill sizes and that take the
  size, not one sized by hand, one with Aa unset or an app that keeps its own steps. The device draws
  the frame aspect-fit on black (HEVCDisplayView): the column joins a letterbox beside it, or is a black
  hairline (a frame's pixel) at the picture's right edge where the frame fills its panel; the viewport
  it sends is the panel or the room, never the frame's shape, so nothing feeds back into a fit. A
  device's position lands as the same fraction of the window (InputLanding), and the Mac's arrow is
  drawn at its fraction of the frame: at most a pixel apart from the picture, at the far side, the far
  edges still landing on the window's last pixel row and column. `select` (and the real window after a
  failed stage) sizes a window with `windowSize`; `windowsChanged` asks `windowNeedsRestart`, the same
  rule, so a rounded-up window never restarts at every poll (the old comparison would have: 1116 against
  an encoder at 1118) and 1117 to 1118 points needs no restart; `catalogPolled` still compares only the
  scale.
- The words, true on a 1x display too (Retina and Standard capture the same there, and the software
  encoder runs at the hardware's size): the status menu's Resolution › Standard, "On a Retina display, a
  quarter of the pixels to encode" (it was "A quarter of the pixels; much lighter to encode"); the
  fallback's two lines, "switching to the software encoder, capturing at 1x, until …" (CaptureScale.words
  of the software knob; it was "at half scale"); the coordinator's comments and DEVELOPMENT.md's "restarts
  at half resolution on the CPU".
- Verified: `swift build -c release` from `git archive` of 70e3d171 (the code; the commits after it are
  docs) and of main at b4caa910, only the CaptureProbe warning; `Tests/checks/capture-scale` 122 checks
  and 30 of 30 mutants (eleven new: the window rule's ten, `evenPixels`' one; in CI's mutants matrix);
  `Tests/checks/run-all.sh`, all 54 (473 s); H2 against main's CLI, both from `git archive`,
  `--synthetic` on loopback (the software encoder, no router, no screen; Noah's iPad streamed from
  Sill.app over the cable meanwhile, and nothing here touched the hardware encoder): idle 35 s identical
  masked and sorted (8 lines), and with `sillclient.py PORT 8 desktop` every host line but the stats
  lines, and every client line but the count of kinds received, identical masked and sorted (the test
  pattern keeps `evenPixels`, 1512×948, and SILL_TEST_SOFTWARE_ENCODER prints no fallback line, so no
  new words reach H2), the stats lines and the count of cursor shapes differing as main's from itself in
  a second run (`cursor.shape` follows the Mac's own cursor; the second the client leaves in); the
  previews from the two bare SillMenuBar binaries, run from one path: identical but menu.txt's Standard
  line, in each of its 25 samples. Not run: any capture of this Mac's screen or windows, the hardware
  encoder, input to this Mac, `--virtual-display-selftest`, Sill.app.
- **Untested, for Noah** (Sill.app from this branch, release-signed with the embedded profile; the iPad,
  the 2560×1440 display at 1x): a window with an odd width at Aa 1x (Sill.log: "Capture started: 1118×610
  … filter (1117.0, 610.0) scale 1.0, capturing at 1x, the display's own (2x asked)") shows its text as
  sharp as the Desktop's, with at most a black hairline at the picture's right edge; the window made a
  point wider on the Mac (1117 to 1118): no second "Capture started"; Resolution › Standard's new line.

**Capture at the display's own pixel scale (2026-10-27, branch `capture-scale` from main at
74d099c2, main at 76bc100 (#157) and 48a4ef3 (#147) merged in; PR #233).** Noah, tonight, Sill.app from 74d099c2 on
this Mac with its lid closed, an external 2560×1440 display at 1x as the main one and a 1920×1080 at
1x to its left (CGDisplayBounds (-1920, 214); read, nothing captured): a window picked showed in the
top-left quarter of the iPad's picture, black around it, Aa changing nothing, while the Desktop
looked right; and a drag to the bottom of the Desktop's picture never brought up the auto-hidden
Dock. Host only: no wire change, no device file, VirtualStage and VirtualDisplay untouched.
- The cause (Sill.log): `Capture started: 5120×2880 … filter (2560.0, 1440.0) scale 1.0` for the
  Desktop, `2234×1220 … filter (1117.0, 610.0) scale 1.0` for the window (and 4468×2440, 3024×1898,
  2912×2140, 1960×1200 of others since 2026-10-26): the points times the Resolution knob
  (`captureScale` 2), while ScreenCaptureKit draws a window at its display's own scale into the
  top-left of a larger buffer, never scaling it up, and scales a display up to fill one (four times
  the pixels: the encoder's 1–2 fps there).
- The rule (`CaptureScale.effective(knob:displayScale:)`, pure, `Sources/SillHost/CaptureScale.swift`):
  the lesser of the knob and the display's own scale, ScreenCaptureKit's for the filter being
  captured (`pointPixelScale`, the capture line's "scale"; not CGDisplayMode's pixel width ÷ point
  width: only the filter's is the scale it draws that content at, a window across two displays
  held to the one it picks, so no rule of Sill's can disagree). On a 1x display Retina and Standard
  both capture at 1x (2560×1440, that window 1116×610 at the merge, 1118×610 since its follow-ups (#234):
  an odd side rounded up, drawn whole); a 2x display as before; the test pattern
  1512×949 × the knob; a window staged on Sill's 2x virtual display at the knob. The same scale
  sizes a window's restart on a resize, each catalog poll restarts a window that moved onto a
  display of another scale (`catalogPolled`: the list never changes for it), the away pair goes
  through it, and the link's suggestion and the re-check's test size follow it; `restartNeeded`
  still compares the knob (a Resolution change on a 1x display restarts once, to the same size).
  The line: "Capture started: 2560×1440 @60 fps, cursor out, filter (2560.0, 1440.0) scale 1.0,
  capturing at 1x, the display's own (2x asked)".
- The Dock (`InputLanding.point`, the same file): a device's bottom edge is y = 1 (PadCursor clamps
  to 0…1 with 1 in; the iPad's pointer, a Pencil and a drag past the picture are held to it), which
  InputInjector posted at `minY + 1 × height`: 1440.0 on a 1440-point display, not short of the last
  row but the row past it (1439 is the last), off the display by CGRect's containment and by
  PointerControl's own inside test. Where the window server puts that move, and whether the Dock's
  trigger takes it, is not known here. Now a fraction is held to 0…1 and lands at most at
  `maxX − 1/scale`, `maxY − 1/scale` (1439 at 1x, 981.5 at 2x, a point in for the test pattern), where
  a pointer pinned at the edge is; elsewhere where it did. Not changed, the next suspect if the Dock
  still does not come: Sill's moves carry no mouse deltas, and macOS moves the Dock to another
  display only for a push against the edge (a Dock last shown on the 1920×1080 display).
- Verified: `swift build -c release` from `git archive` of b2bb428 and of main at 76bc100, only the
  CaptureProbe warning; `Tests/checks/capture-scale` 79 checks and 19 of 19 mutants (the first
  commit alone 42 and 9 of 9), in CI's mutants matrix; `Tests/checks/run-all.sh`, all 53 at b2bb428
  (454 s; 54 since the merge of 48a4ef3 brought `text-composition`: all 54 on the follow-ups' branch,
  473 s);
  H2 against main's CLI at 76bc100, both from `git archive`, `--synthetic` on loopback (the software
  encoder, no router, no screen): idle 35 s identical masked and sorted (8 lines), and with
  `sillclient.py PORT 8 desktop` identical masked and sorted but for the stats lines of the seconds
  the client leaves in, the same kinds reaching the client (the test pattern has no capture line,
  so no new words); a dry run of input there (SILL_TEST_INPUT_LOG, a scripted pointer, nothing
  posted): a tap at the pattern's far corner went to 1512,949 on main, to 1511,948 here, its middle
  (756,475) and origin as before. A second round was refused by no-device.sh (Noah's iPad connected
  at 01:50). Not run: `--virtual-display-selftest`, which warps this Mac's cursor, posts a HID move
  and makes a display (its sources, VirtualDisplay's and VirtualStage's are untouched); any capture
  of this Mac's displays or windows; Sill.app.
- **Untested, for Noah** (Sill.app from this branch, release-signed with the embedded profile; the
  iPad): on the 2560×1440 display a window picked fills the picture (Sill.log: "…, capturing at 1x,
  the display's own (2x asked)") and Aa still fits it; the Desktop captures at 2560×1440 and runs at
  60 fps (`enc.out` near `cap.complete`); with the Dock auto-hidden and the Desktop streaming, a drag
  to the picture's bottom edge (the portrait trackpad, the Magic Keyboard's trackpad) brings up the
  Dock (if not, note which display it was last on); a window dragged between the two 1x displays
  streams on with no restart; with Virtual Display on, a picked window still at 2x.
- From the post-merge verification, for Noah (no code; the verdict, in the entry above): a drag-select
  past a text window's bottom or right edge may no longer creep-scroll. A device's far edge now lands on
  the window's last pixel row or column (InputLanding), where main's landed one pixel outside the
  window, and AppKit autoscrolls a text view only while the pointer is outside the view: in a window
  whose text reaches its edge, the last row is still inside it. A hypothesis, not tried: if a selection
  dragged to the picture's edge stops scrolling the text, that is why, and a drag alone could land a
  pixel outside again. And the Desktop reads its display's scale once, at `select` (its filter's
  `pointPixelScale`); nothing reads it again while it streams (a window's is looked at each catalog
  poll, `catalogPolled`), so a display misreported at the moment of a pick (the verification saw one, a
  display going away as the lid closed) keeps that capture size until the next restart (a pick, a
  settings change, the encoder's fallback).

**Chinese input and dictation reach the Mac (2026-10-19 to 27, PR #147 from cinminori's `zhuyin-input`,
finished on it, with main at 76bc100 in it; issue #138).** Noah: "Chinese input and dictation if polished
then merge (detects user language set in iOS settings). Once testflight is enabled, ask users to test."
Device only: no wire change, nothing on the Mac, no Sill setting: the keyboards and dictation languages
set up in the device's Settings decide.
- The PR (kept): the stream's input view (`InputOverlayView`) is a `UITextInput`, not only a
  `UIKeyInput`, so an input method's composition (Zhuyin, Pinyin, Japanese…) stays on the device, drawn
  at the top middle of the picture, and only what is chosen goes to the Mac as text; dictation's text and
  its corrections go as backspaces back to the first difference, then the rest typed; while it composes
  every key is the input method's (pressesBegan hands them all on; Esc's key commands stand down, and a
  shortcut such as ⌘S goes to it too); spell checking and inline predictions off.
- The triage's four changes (2026-10-19), in commits of their own: ⌃Space is iPadOS's switch only
  with keyboards in two languages or more (`TextInputRules.isKeyboardSwitch`: Emoji and dictation aside, a
  language counted once, judged at the press; ⌃⇧, ⌃⌥ and ⌃⌘Space always the Mac's), else the Mac's as on
  main (the PR gave every ⌃Space to iPadOS); Scribble declined (a `UIScribbleInteraction` refusing every
  start: the Pencil is the Mac's mouse); the dictation tail: what was typed kept whole while the text
  system may revise it (the PR cut it to 200 characters inside every edit, unseen by the text system, so a
  correction past 200 landed at the end and typed its words twice), trimmed past 4,000 to the last 1,000
  between edits with the text system told, forgotten wherever the Mac's caret may move (a click or a key
  from any view, a pick, a launch, a window's button, a menu item, a gesture:
  `StreamClient.onCaretMayMove`, before it goes out, the pick and the rest now behind queued input,
  `sendAfterInput`), a correction taken before a forget or a trim sending nothing (`generation`), and a
  composition still in progress then, or when the input view resigns or leaves its window, sent first, as
  it stands; and mutants for its check.
- Also: Korean (2-Set selects the syllables it rebuilds and types them again: `TextComposition.selection`;
  한글 reached a simulator Mac as 한한한글 before); VoiceOver (the input view stays no element); Writing
  Tools, math results and grammar checking off; Debug `textinput:` lines; #110's latched-shift Return and
  Tab behind `!composition.isComposing` (Noah's conflict comment). Docs: docs/DEVELOPMENT.md, "Other
  languages and dictation"; README's How it works; site/support.html's paragraph inside `<!-- Other
  languages` markers (docs/release-checklist.md part 1 §3's perl line); the next What's New
  (docs/app-store-metadata.md); docs/hardware-keyboard-plan.md's item 11 answered.
- The verification (2026-10-26, fix-first: sill-handoff's
  `triage/2026-10-20-reports/verdicts-2026-10-26/pr147-verdict.md`), one commit per theme: a Return or a
  Tab typed as text ("\n", "\r" or "\t", alone or anywhere in it: a hardware one without shift, the
  on-screen return key, dictation's "new line") counted as the Mac's caret moving
  (`TextInputRules.movesCaret`, `carriesReturnOrTab`): it went whole, then all of what was typed was
  forgotten (`onCaretMayMove`, `forgetTyped`, the text system told), so a correction dictation made later
  of the phrase before it, taken before it, sent nothing (it sent 15 backspaces and "Send the build.\n":
  the message sent twice, the command run twice), a forget the second verification replaced with the
  fence (below); a finger's tap or long press on the letterbox mid-composition sends nothing (its forget after the guard
  that drops it, as touchesBegan's, where it sent the composition as it stood with no click);
  and DEVELOPMENT.md says the keyboard's name shows over the picture at any switch while the input view
  holds the keyboard, the on-screen keyboard's Globe key included (`inputModeChanged`), not only with a
  hardware keyboard.
- Verified (2026-10-26, on the tree merged with main at 36e7212): `Tests/checks/text-composition` 99
  checks and 60 of 60 mutants (in CI's matrix; 119 and 65 of 65 since the verification's fix, above);
  key-strokes 353; `swift build -c release`; the iOS app
  Debug and Release for the simulator and Debug for a device, only the known StreamClient capture
  warning; the touch rig, 72 scenarios; a private iPad simulator (iOS 27.0) against a loopback synthetic
  host (software encoder, `SILL_TEST_INPUT_LOG`, a scripted pointer), keys from `Tests/keyrig`: Zhuyin
  (ㄋㄧˇㄏㄠˇ, Return), Pinyin (nihao, Space), Japanese (nihonn, Return) and Korean (2-Set's g k s r m f)
  each reached the host once (你好, 你好, 日本, 한글); a scripted tap mid-composition sent 好 first, then
  the click; ⌃Space stayed on the device with keyboards in two languages and reached the host (key 49
  with control) with one; letters as text, ⌘S and Esc as keys, ⌘S mid-composition nowhere;
  `-SillInputTest 1` as before. The simulator takes a language's keyboards from `-AppleLanguages` and
  `-AppleLocale`, not from its `AppleKeyboards` preference.
- Verified after the verification's fixes (2026-10-26, on the tree merged with main at c215514, #159):
  text-composition 119 checks and 65 of 65 mutants; key-strokes 353; `run-all.sh`, all 49; the iOS app
  Debug and Release for the simulator and Debug for a device on Xcode 27.1, only the known StreamClient
  capture warning; the touch rig 72 of 72 against main's; a private iPad simulator (iOS 27.0) against a
  loopback synthetic host, keys from `Tests/keyrig`, the device's bytes recorded by `sillrelay.py`:
  "send the build", Return, "ok", Backspace, ⌘S and Esc went as the 14 letters, "\n" (then "forgot the
  15 characters typed"), "o", "k", one backspace, ⌘S's keys and Esc's; `-SillInputTest 1` as before;
  mid-composition (Zhuyin's 你) a scripted tap on the letterbox sent nothing, one on the picture the
  move, 你, then the click; with an uncommitted DEBUG step standing in for dictation (`insertText`,
  then `replace` with the range it held), a correction after a hardware Return sent nothing (2dc6c75's
  build with the same step: 15 backspaces and "Send the build.\n") and one with no Return went as before.
- The second verification (2026-10-26, fix-first: `pr147-verdict-2.md` beside it): forgetting at a typed
  Return was wrong for dictation's own "new line" said mid-utterance. The document empty after it, the
  phrase's last pass through the range from where it began (offset 0, never past an empty document's
  end, so not stale) was typed again at the caret, Return included (the Mac with the phrase twice, a
  chat a second, garbled message), and in other models of how iPadOS sends the rest of an utterance the
  words after the Return never arrived, or went three times (the verifier's harness, S1–S12). Now the
  fence (`TextComposition.fence`): a Return or a Tab typed as text keeps the document and its
  generation, goes whole, and makes what was sent up to just after its last Return or Tab final; a
  correction whose first change falls before it sends nothing (`refusal`'s `.final`), wherever its
  range starts, so an utterance sent again whole from its start that only adds words after the Return
  goes; a selection wholly before it is not kept, so the next edit goes at the end ("send the bill⏎ok"
  typed, "bill" selected, then "build": "okbuild" on the new line; select, backspace and "build", as
  Korean rebuilds: "obuild", the backspace deleting the last character; acceptable, as no input method
  has been seen selecting wholly before a Return: Korean's selections cross it, the person's backspace
  selects one character); an edit's backspaces stop at it (the difference looked for after it, so a CR
  and an LF typed later cost no backspace over the CR); the person's own backspace (text, from the
  on-screen keyboard and from a hardware one without ⌘, ⌃ or ⌥) goes back across it and takes it back to
  what is left, which stays final; a second Return moves it to just after itself; a forget puts it at 0
  and a trim moves it with the text it keeps (to 0 when the cut passes it); a composition follows what
  was sent, after it; the 4,000-character cap stays, reached across Returns now.
  `TextInputRules.movesCaret` is false for all text again (`endOfReturnOrTab` says where the fence
  goes); clicks, keys (⇧Return and ⇧Tab among them), picks, gestures and menu items keep the full
  forget. Decided here: the fence goes just after the last Return or Tab, not at the end of the text
  that brought it (the verifier's variant), as what follows the Return went where the caret went: the
  verifier's own text with only "deploy it " corrected after is sent, and a hypothesis that revises a
  word after the Return as it adds more keeps its new words (the harness's S13: the variant lost " it").
  Known (the third verification, 2026-10-27: `pr147-verdict-3.md` beside it): a correction that changes
  the line before a Return sends nothing, the words it adds after the Return with it, and dictation that
  sends its whole utterance again with each update carries a word revised there into every later update,
  each sending nothing too, so the rest of the utterance never reaches the Mac (the verifier's harness:
  "send the bill", "send the bill⏎deploy", "send the build⏎deploy it", "send the build⏎deploy it now",
  "Send the build.⏎Deploy it now." leave it "send the bill⏎deploy", " it now" never arriving, in an
  editor too). Nothing is sent twice, and where new words come at the caret and each revision is a
  replace of its own, every word arrives (the revision left out). The testers' "new line" step would
  show which way iPadOS goes; a possible follow-up applies such an update's text after its k-th Return
  or Tab (k: the Returns and Tabs in what is final) instead of refusing it whole. Docs: DEVELOPMENT.md's
  "Other languages and dictation" (the fence, and plainly: after a click, a key or a pick a correction
  through a range built again from offsets kept, starting where what was typed began, is typed again at
  the caret, as before; after a Return or a Tab it sends nothing), the checks README. Found live and
  fixed in a commit of its own: Korean's 2-Set rebuilds the character before its syllable together with
  it, so right after a Return it selected "\nㅎ", deleted it and typed "\n" and "하" again, and with that
  selection refused (the verifier's variant did the same: its harness's S18) the Mac got a second Return
  at each of the first syllable's letters. A selection that reaches back across the fence from after it
  is now kept: its deletion deletes only what follows the fence and leaves the rest in place as
  `retype`, which the text typed next does not type again (in pieces too; text that starts otherwise
  would change what is final, and sends nothing, so "\nㅎ" selected and deleted, then "하" typed alone,
  loses the syllable: check J4, a nit of the third verification's, which Korean did not do live; a new
  selection, or any other edit, ends it); text typed over it goes only while it keeps what is final; a
  composition over it deletes only after the fence, nothing held back; one wholly before the fence is
  still not kept (the text system selects the character a backspace deletes, so the person's backspace
  right after a Return deletes that Return). Telling the text system at a Return (an experiment) did not
  change what the input method selects.
- Verified after the second verification's fix (2026-10-27, on 3187d56, the tree with main at c215514 in
  it): text-composition 178 checks and 87 of 87 mutants (F1–F14 the fence's, J1–J8 the crossing
  selection's; in CI's matrix); the verifier's harness, S1–S12, against its fence variant: the same output
  in every scenario; five more (S13–S17) where the two differ only in S13 and S14 (the variant drops the
  words a hypothesis adds as it revises one after the Return, and a correction of only the words after the
  Return in the same text), and S18, Korean's rebuild across a Return, where the variant sends a second
  Return at each letter and this rule none; key-strokes 353; `swift build -c release` from `git archive`
  (only the CaptureProbe warning); the iOS app Debug and Release for the simulator and Debug for a device
  on Xcode 27.1, only the known StreamClient capture warning; the touch rig 72 of 72 against main's
  (74d099c); a private iPad simulator (iOS 27.0) against a loopback synthetic host (software encoder, no
  router, no ScreenCaptureKit, `SILL_TEST_INPUT_LOG`, a scripted pointer), keys from `Tests/keyrig`, the
  device's bytes recorded by `sillrelay.py`: with an uncommitted DEBUG step standing in for dictation
  (`insertText`, then `replace` through the range from where the text began), "send the build", the
  hardware Return's "\n", nothing for the phrase's correction after it, "send the build\ndeploy it "
  whole, nothing for its whole-phrase pass, 10 backspaces and "Deploy it. " for the words after its
  Return, "hello there" corrected as before; a b c Return d e f as letters and one "\n"; ⌘S and Esc as
  keys; Korean 2-Set's 한글⏎한글⏎한 once (before the crossing fix 한글⏎⏎⏎한글⏎); Zhuyin's ㄋㄧˇ⏎⏎ㄋㄧˇ⏎⏎
  as 你⏎你⏎ once; a Backspace right after a Return deleted that Return; `-SillInputTest 1` as before.
- **Untested, for Noah and #138's testers (TestFlight):** Zhuyin and Pinyin on the on-screen keyboard and
  on a Magic Keyboard (the candidates beside the composition), Japanese, Korean, dictation in Chinese and
  in English with its corrections and punctuation (nothing typed twice), Return right after dictating in
  Messages, Slack or Terminal (the line goes once), dictation with "new line" said in the middle of a
  sentence, talking on, in TextEdit and in Messages or Slack, in English and in Chinese (every word
  arrives once, nothing is sent twice), ⌃Space with one keyboard and
  with two, the Globe key, Caps Lock's switch to and from ABC, a tap mid-composition, a shortcut
  mid-composition, an Apple Pencil over the picture (no handwriting), VoiceOver.
  If dictation corrects a word before the "new line" while you keep talking, the words after it may not
  reach the Mac; nothing is sent twice either way. Say which words were missing and in which app.

**The pairing window to screen sharing (2026-10-19, PR #157 by scripsweave, branch
`fix/remote-desktop-qr-code` on their fork, from main at 5c323e6; issue #108, #137 closed as its
duplicate).** The pairing window's `sharingType = .none` keeps it out of Screen Sharing, Apple
Remote Desktop and VNC apps (Screens), so a Mac used only through them (a headless Mac mini) could
pair a device over the USB cable alone. Noah (2026-10-19, answering the triage): the pairing code
only, as a toggle, and no other hidden dialog shown. Sill.app only: no wire change, nothing on the
device, the CLI untouched (`--pairing` prints its code on stdout).
- Settings › Devices, after Require pairing: **Show the pairing window to screen sharing**
  (`HostSettings.showPairingWindowToScreenSharing`, UserDefaults, off by default; a launch argument
  for one run; `-SillSetAfter '<s> showPairingWindowToScreenSharing=1'` in the bare app). On, the
  pairing window is `.readOnly` (AppKit's default) instead of `.none`, whoever opened it, the Mac's
  user or a device's ask (`PairingWindowSharing`, pure, `Tests/checks/pairing-sharing`); applied as
  the window is made, as each offer shows, and at once on a change to a window already made
  (`PairDeviceWindowController.applySharing`, the app delegate's `onPairingWindowSharingChange`).
  Footnote: "…While it’s on, anyone who can see this Mac’s screen remotely can read the code.
  Devices streaming this Mac never show the window." Sill.log: "Pairing window: shown to screen
  sharing (Settings › Devices); …" at each change and at launch while on, "… hidden …" when it goes
  off. The cable notice and every other window keep AppKit's default, as on main; Sill's own streams
  leave Sill's windows out whatever it says.
- From the PR, kept: the switch, off by default, applied live. Changed: the name (was "Display QR
  code on remote desktops", `displayQRCodeOnRemoteDesktops`); the rule a pure type with a check in
  place of an XCTest target and a `swift test` CI step (both gone, with AppModel's `init(defaults:)`);
  the footnote; the docs (README's Pairing, docs/DEVELOPMENT.md's Pairing at home, support.html's
  "If it doesn’t work" item marked `<!-- Pairing window` for the release, the checklist's republish
  cut, SECURITY.md's known-by-design paragraph, docs/home-pairing-plan.md's open risk).
- Open for Noah: the 2026-10-19 triage suggested keeping a window a device's ask opened hidden; the
  task as relayed covers both openers, since a device's tap is how a Mac seen over Screen Sharing
  pairs. One line in `PairingWindowSharing.pairingWindow` and two of the check's cases change it.
- Verified: `pairing-sharing` 16 checks and 8 of 8 mutants; `Tests/checks/run-all.sh`, all 45;
  `swift build -c release` (only the CaptureProbe warning); `Scripts/make-app.sh` without `--install`;
  the bare binary's previews against main's, both run from one path: only the Devices pane's eight
  differ, two new (`screensharing`), `menu.txt` and the rest byte for byte; live on a test host
  (`--synthetic`, loopback, the software encoder) with a scratch build whose pairing window was
  transparent and click-through, opened by a test client's ask: the window server's
  `kCGWindowSharingState`, sampled 2 s after each change, 0 with the switch off, 1 once
  `-SillSetAfter` turned it on, 0 off, 1 on, the same open window throughout; 1 from the first look
  with it saved on (the launch line logged) and with `-showPairingWindowToScreenSharing 1` (nothing
  saved).
- The verifier's findings (2026-10-20, after fa57c2f), each fixed in a commit of its own: the
  window's `NSWindow.SharingType` for each answer (`.none` hidden, `.readOnly` shown), which no check
  compiled, moved from PairDeviceWindowController into `PairingWindowSharing.swift` under
  `#if canImport(AppKit)`, and the check (AppKit imported for that enum alone, no window) asserts
  both: 18 checks, 11 of 11 mutants (new: the two cases swapped, hidden told `.readOnly`, shown told
  `.none`); the footnote's and README's example is the Mac's ("…or another remote desktop app, as
  you would a Mac without a display"; it read as an app without a display); docs/remote-access-plan.md
  §6.2, the window's spec, names the switch; docs/DEVELOPMENT.md says what the switch changes, what
  Screen Sharing, Apple Remote Desktop and VNC viewers see, and that a screen recording or a call's
  shared screen may show the code either way (ScreenCaptureKit is reported to ignore `.none` from
  macOS 15). Main merged in at d1fa97e (no conflict), at 4d990e9 (ci.yml's mutants matrix alone:
  both sides kept, sorted) and at 74d099c (#94, #159, #227, #93, #151: six files, both sides kept in
  each; #94's `sendAudio` beside this switch in HostSettings' keys and registered defaults, as Noah's
  comment of 2026-10-19 asked of whichever landed second). Verified again on the last merge:
  `swift build -c release` from a clean `git archive` (only the CaptureProbe warning); the iOS app
  for the generic simulator as CI builds it (only the StreamClient capture warning);
  `pairing-sharing` 18 checks and 11 of 11 mutants; `Tests/checks/run-all.sh`, all 52; the previews
  against main's (74d099c), both run from one path: the Devices pane's eight differ, two new, the
  other 136 byte for byte (`menu.txt` among them); the bare binary on loopback with
  `-SillSetAfter '2 showPairingWindowToScreenSharing=1'`: one line for the change, the key saved;
  live, on a trial merge of the same code, a test host as above (a scratch copy, its pairing window
  alone transparent and click-through, opened by a test client's ask), `kCGWindowSharingState`
  sampled every 0.1 s: 0 with the switch off, then 1, 0 and 1 within half a second of each
  `-SillSetAfter` change, one window throughout, off screen after the Cancel; relaunched with it
  saved on, 1 from the window's first look and the launch line once; with
  `-showPairingWindowToScreenSharing 1`, 1 and nothing saved.
- **Untested, for Noah:** with Sill.app from this branch, through Screen Sharing from another Mac
  (or Screens, or Apple Remote Desktop) to a Mac: Pair iPhone or iPad… shows nothing remotely with
  the switch off, the window and its code with it on, and flipping it with the window open shows or
  hides it at once; a tap on the Mac's "Not paired" row on the iPad does the same; a device pairs
  with the code read remotely. (#121's author saw `.readOnly` show the code through Screen Sharing on
  a headless M4 Mac mini and paired with it.)

**The Mac's sound on the device: the wire, the host and Sill.app (2026-09-27,
branch `audio` from main at 643af6b with the plan merged in from `audio-plan`
(1fb9b71, 6e852ef) and refreshed (51520dd), main at da43f6b (PR #38) merged in
at 2b114e1, then main at 985a733 (PRs #37, #39 to #56: pairing at home, away
from home, the iPhone Duo with the iOS 27.1 SDK, the 0.5.1 release) merged in on
2026-10-13, then main at 5c323e6 (PRs #74, #75, #77, #78, #79, #80, #85, #98)
merged in on 2026-10-18, never rebased; the plan, its critique, the refresh and the results
are in `docs/audio-plan.md`; PR #94 by Code-Tomato, who finished it from 9288aa6; in, as a beta,
since 2026-10-20: the bullet "A beta").** Noah (2026-09-27), first in what he wants
worked on: "Audio: the plan is done and parked as a v2 feature by your earlier
decision". So the sound is in scope now (docs/BRIEF.md, the decisions below),
and every open question takes its default (Send Audio off by default, AAC-ELD
at 128 kbps, per device mute, and so on). Built here: the plan's steps 1 to 7,
the device's playout model (6878c11), its output (aefe477) and the Sound button
and the panel's rows (5f7b1ac) after the host's. The workflow stopped there
(9288aa6, WIP); on 2026-10-13 the device's steps were reviewed against the plan,
fixed (5126215 to 8bbbe52, below) and verified in the simulator
(docs/audio-plan.md, "Results: the device").
- Wire (additive; `Audio.swift`): kind 43, host → device (29 until 2026-10-14,
  when PR #66's 29–42 were found: docs/audio-plan.md, "Kind 43"). Type 1 is a
  JSON `AudioFormat`: codec "aac-eld", 48 kHz stereo, 480 or 512 frames a packet,
  the priming, the bitrate, the epoch, the cookie and what the sound is of.
  Type 2 is `AudioPackets`: epoch, seq, the segment flag and 1–255
  length-prefixed packets, with the header's stamp on the wall clock of the
  first decoded sample. A host sends it only to a device whose hello lists a
  codec it makes (`Hello.audio`; `AudioCodec.choose` takes the first of the
  device's list). Kinds 16 and 17 gain `sendAudio` (nil from a host without
  sound), the state gains `audioNote`, and ClientStats gains `audioBehindMs`
  and `audioLate`. `SillProtocol` stays 1.
- Host: Send Audio (`HostConfig.sendAudio`) is off in `standard` and, since
  the beta, the Mac's alone (its menu and Settings, the CLI's `--audio`): a
  device's kind 17 `sendAudio` is refused from either door (the plan's Q8).
  Since 2026-10-27 a device's again (the bullet "Two switches").
  It is not in `restartNeeded`, so the picture never restarts for it.
  - `AudioPipeline` follows the source from `active`'s didSet, where the
    pointer and the menus follow it. The same app keeps its stream through
    every restart of the picture. Another app, the Desktop or the test tone is
    a new stream and epoch. One that ended or failed is tried again at most
    every 10 s. A failure prints one line and sets the note; the picture never
    notices.
  - `AudioCapture` is a second, audio-only SCStream per app (the Desktop: every
    app but Sill's) at 48 kHz stereo with `excludesCurrentProcessAudio`. Its 2×2
    picture is thrown away, start and stop are bounded to 2 s, and each
    buffer's layout is read, never assumed. No test runs it.
  - `SyntheticAudio` (`--synthetic`) plays the test tone: 440 Hz at −30 dBFS
    with a 4 ms 2 kHz click at each whole second of the stamps' clock. A
    synthetic host never captures a real window's sound.
  - The packetizer makes blocks stamped at input frame n·F − P from each
    chunk's anchor. A gap ends a segment, with nothing flushed or filled.
  - The encoder is AAC-ELD at 128 kbps, AudioToolbox only.
  - StreamServer keeps each device's codec from its hello and sends the
    epoch's format before the epoch's first packet. The sound has a send path
    of its own: never `inflight`, the drain eviction or the keyframes'
    bookkeeping. Its bytes count in `pendingBytes` and, once taken, in
    `takenThisSecond`, as every message's do since away from home (#39), so
    each device's link judge sees them; `paceRemote` still drops only frames. It sets `lastSentAt`, so remote ticks
    pause while it flows. A packet is skipped only past 1 s untaken at home,
    or 15 s away (the drain backstop). The plan's 3 s skipped a fifth of the
    sound at 4 Mbit/s with 1.5 MB keyframes, where remote pacing already held
    the picture 5–7 s behind.
  - Log lines and the `aud.*` stats appear only while Send Audio is on (the
    plan's §4.10).
- The CLI's `--audio` adds one startup line; without it the output is main's.
- Sill.app: Send Audio in the status menu after Resolution ("The Mac keeps
  playing it too") and in Settings › Streaming, with its footer and an orange
  line while it fails. Also the Permissions pane's words, " · sound" on the
  card's source row, `-SillSetAfter sendAudio=1`, and the `sound` preview.
- The device: AudioDecoder, AudioPlayout (pure, `Tests/checks/audio-playout`),
  AudioOutput and StreamClient+Audio, in the Xcode project as AA01–AA04; the
  Sound button in every bar and the panel's rows (5f7b1ac; the button gone since
  2026-10-27, the bullet "Two switches"). AudioDecoder also
  serves the `audio-codec` check and the harness's device.
  - The playout (§7.2): the floor, the need (the jitter cover from 40 ms at home
    and 150 ms away, a packet, the IO buffer, the output latency), the picture's
    lag as a guard, placement by time then packet after packet, each packet's
    last 5 ms held for a fade, drift closed a frame a packet, jumps over 40 ms,
    clock steps; a move's hand-over resets nothing, and its copies are dropped.
  - AudioOutput: AVAudioEngine with a player node (no render block of Sill's),
    `.playback` mixing with others, active only while the engine runs; the
    engine stops on mute, in the background and at a session's end after the
    mixer's 25 ms ramp to volume 0 (measured), and after 10 s without a packet;
    a configuration change (an output at another rate) stops it and the next
    packet builds one; nothing is decoded while muted, in the background or
    refused during a call, each packet still counting for the floor and the
    cover. Headphones out mute it and say so. The simulator renders offline
    (manual rendering) in every build: nothing opens an output.
  - Until 2026-10-27 (the bullet "Two switches"), the Sound button counted
    Menus whether or not it showed: where only one fits (an iPhone SE
    sideways, iPad windows under 532 pt upright) Menus kept its place and
    Sound was the panel's switch alone, as in the iPhone Duo's book
    pose and, since the beta, with Larger Picture on every phone (row 1 as
    Noah approved it: the plan's Q10). A remote session by address takes
    home's cover, as the Mac counts it.
  - The review's fixes (2026-10-13): 5126215 (the configuration change, nothing
    decoded while silent, a start's reset, unmute retrying a refused session, a
    DEBUG leak), fca4c80 (the fades), 46cc7e4 (the console's "audio: jump -870
    ms (off by over 40 ms)"), 8a7dc30 (by address), dd9e6fc (Sound and Menus),
    25767ef and 720d21e (checks and harness), 8bbbe52 (the DEBUG click finder).
- Checks:
  - `audio-packetizer`: 89 checks, 27 of 27 mutants.
  - `audio-codec`: 21 checks, 9 of 9 mutants. Each click lands at its whole
    second, 0 frames off, at 480 and 512 frames a packet and across gaps. A
    busy signal runs at 130.2 kbps.
  - `compatibility`: 130 checks, 31 of 31 mutants. `protocol`: 218 + 8, 30 of
    30 (on 2b114e1; on 985a733 131 and 220 + 8, 31 of 31 and 33 of 33).
  - The kind checks say 28 gesture, 32 the clipboard (#78, since the merge with
    main at 5c323e6), 43 audio, and 29 to 31, 33 to 42 and 44 unknown. The
    mutants this branch added that renumber a kind use 250–254; the
    clipboard's use 30, 31 and 33.
  - H0 again on this Mac: ELD 480 and 512 have 240 and 256 frames of priming,
    the same after a reset. They take 15.0 and 25.3 ms end to end. A late
    join's fourth packet decodes exactly.
- The harness (`Scripts/audio/run.sh`) on 2b114e1 (main at da43f6b) passed
  every gate but H12 (what follows ran there, not on 985a733):
  - At home: 100.02 packets a second, no seq gap, and 60 of 60 clicks within
    1 ms of their second. The picture's net.sent, net.dropped and frame age
    were as without sound. With 1024-frame chunks: 93.84 a second.
  - Pauses and a source change on two devices: segments at their stamps, each
    epoch's format first, nothing over 40 ms late.
  - Away through 8 and 4 Mbit/s with 1.5 MB keyframes: no packet skipped while
    frames were, and packets never later than the frames + 20 ms. In a dip to
    0.5 Mbit/s they were late with the picture and back in the same second.
  - Through the relay at 2 Mbit/s and +150 ms: no eviction.
  - The pacing harness's own gate cases with sound (`Scripts/pacing/run.sh
    --sound`) passed, with fps and drops as without. In stillend, a stream far
    past its link, the median of each second's slowest pong was 102–700 ms
    against 75–86 without.
  - H7: a device turned Send Audio on and off. The first packet came 23 ms
    after the answer, the last before the second answer, and the picture
    never restarted.
  - H9: main's client and StreamProtocol read or skip everything new, and
    this branch's client gets no sound from main's host.
  - H10: only the Streaming and Permissions panes, menu.txt and the new card
    differ from main's previews.
  - The iOS app builds (on 2b114e1: Debug and Release for the simulator, Debug
    for a device) with only the known warning.
  - H2: the CLI's stdout (digits masked) against main's, idle, picking the
    Desktop, and with a hello that lists the codec, with and without
    `--direct-wireless`, twice each: every run printed the same lines. 4 of the
    12 differed only in how many once-a-second stats lines came before the host
    was stopped. There was no `Audio` line, no `aud.` key and no kind 29 (the
    sound's number then; 43 since 2026-10-14).
  - H12 was not met. The harness host used +2.1 to +3.1 points of a core with
    sound, against the plan's 1.5. AAC-ELD itself takes about 1 point on the
    test tone (82–101 µs a packet; 53 on a busy signal), and each packet's
    own send on loopback about 1. Codec quality Low would save 0.6 points but
    lose 3–9 dB of SNR on tonal sound, so it was not taken; the plan's Results
    leave it to Noah.
- On 985a733 (2026-10-13): `swift build -c release`; `Tests/checks/run-all.sh`,
  all 43 (`compatibility` 131, `protocol` 220 + 8); the iOS app (Debug for the
  generic simulator) only from a scratch copy with the iOS 27.1 SDK's names
  stubbed (Xcode 27.0 here: `DuoPostureReader` alone fails), only the known
  warning, so a build with Xcode 27.1 (CI's) is owed, and Debug for a device;
  the sound and pacing harnesses build, not run: the pacing harness's
  `--sound` cases and link verdicts are owed, the sound now counting in
  `pendingBytes` and `takenThisSecond` at home too. No mutants, H2 or
  previews.
- On the merge and the review's fixes (2026-10-13 and 14; docs/audio-plan.md,
  "Results: the device"): `swift build -c release` from `git archive`; the iOS
  app from a scratch copy with the 27.1 names stubbed, Debug and Release for the
  simulator and Debug for a device, only the known warning (Xcode 27.1's build,
  CI's, owed); `audio-playout` 214, `phone-portrait` 169, `tour`, `ledger`,
  `duo`; the mutants of the 31 checks whose compiled files differ from main's,
  925, every one caught (`audio-playout` 36, `phone-portrait` 35, `tour` 72,
  `ledger` 12, new: it had none), then `run-all.sh`, all 43; the sound harness, every gate but H12 (now +3.9 to +4.4
  points of a core: open question 16); the pacing harness with sound (every
  gate but over8's "≥ its base fps", 4.8 against 4.9: the sound is 1.9 % of
  that overfilled 8 Mbit/s link) and without it against main (every gate);
  H2 (4 of 6 identical, the rest the stop's timing); H10 (only the sound's
  panes, menu.txt and its two cards); S2 and S3 against `SillHost --synthetic
  --audio` on loopback and the software encoder, the engine rendering offline
  at volume 0 (every click within 0.2 ms of its place; mute, the switch, the
  background, Send Audio off from a second client, a move with its duplicate
  dropped); S1's photos of every bar against main's build.
- The review (2026-10-14; docs/audio-plan.md, "The review"): seven verified
  findings fixed, one commit each (e6bc0a0 to 3760b01: the hand's deadline
  before a late packet, the engine's own wait out of the cover, the host's
  source callbacks and AAC-ELD's failure, one session for every window's
  engine, headphones out without an engine, a window in the background);
  `audio-playout` 218 and 38 of 38 mutants, S2 again, `run-all.sh`, all 43.
- Merged with main at 5c323e6 (2026-10-18; one merge commit, not a rebase;
  docs/audio-plan.md, "Merged with main at 5c323e6"): PRs #74, #75, #77 to #80,
  #85 and #98. Where they meet: kind 32 (#78's clipboard) beside 43, 29–31 and
  33–42 free (#66's); `sendAudio` beside `shareClipboard` in HostConfig and the
  CLI; with Larger Picture (#79) the Sound button joined row 1 before Settings
  (Apps, Menus, Aa, Keyboard, Desktop, Sound, Settings) only from 384 pt
  (`PhonePortraitLayout.row1Beside`), narrower the panel's switch alone, a
  question for Noah (the plan's Q10; the beta took it out again: the panel's
  switch alone there); and #75's regular-mode window that streams
  on through three looks off the catalog's list keeps its sound (`select` keeps
  its app, `streamedPID`, which `audioKey` falls back to; before, a follow then
  stopped it). Verified: `swift build -c release`; the iOS app from a scratch
  copy with the 27.1 names stubbed, Debug and Release for the generic
  simulator, only the known `StreamClient` capture warning (Xcode 27.1's build,
  CI's, owed); CI's CLI step; `run-all.sh`, all 47 (`compatibility` 140,
  `pointer-control` 158, `phone-portrait` 501, `tour` 111,192, `clipboard`
  259); the mutants of the 25 checks that compile a file both sides changed
  (StreamProtocol's StreamMessage and Compatibility, HostConfig,
  PhonePortraitLayout), 936, every one caught (`compatibility` 34,
  `protocol` 34, `pointer-control` 33, `phone-portrait` 81, `tour` 84,
  `clipboard` 72). No harness, H2 or previews.
- **A beta (2026-10-20; Noah, about PR #94: "merge as beta support"; docs/audio-plan.md, "The
  beta").** On the contributor's branch, one commit each, never a rebase: Send Audio the Mac's alone
  (Q8, fdf78ff: `DeviceSettings.accepted` refuses a device's `sendAudio` from either door and names
  it, "Settings from ‹device› refused: send audio (set on this Mac only)"; the device's row
  read-only; `away-quality` 83 and AQ20–AQ24); the labels (e42f1a3: "Send Audio (Beta)" in the menu,
  "Send audio (beta)" and a footnote starting "Beta." in Settings › Streaming, the CLI's "(beta)", a
  "Beta" tag on the device's row, "Send Audio, beta" to VoiceOver; none on the Sound button or This
  iPad's switch); no Sound button in Larger Picture's row 1 (Q10, 6effec7: row 1 as Noah approved
  it, the panel's switch alone there; `phone-portrait` 495 and A1–A3, `tour` 111,191); the
  pre-review's small defects (b813164 `AudioCapture`'s stream under a lock; 2e65f06 and 9104023 no
  frame handed to the sound's queue before the session's first format, the last 32 kept for the
  guard; 86de992 the refresh from `screenMaximumFPS`, not `UIScreen.main`; e8ab324 AudioOutput's
  observers removed; f448c46 a freed engine gives the app's session back; 6503bc5 AAC-ELD loaded in
  the background when Send Audio turns on); the public words (README; site/privacy.html and
  support.html inside `<!-- Sound` markers, with their perl line in docs/release-checklist.md;
  docs/app-store-metadata.md's next version, "beta" on the feature, never the app; the compatibility
  floor's reader caps below). Q4 (plays on silent) and Q5 (starts unmuted) kept; Q16, codec quality
  Medium, with H12 unmet (+4.0 points of a core in the harness, against 1.5), accepted while it is
  off by default; packets while muted or in the background still feed the cover (§7.5, Noah's).
  Merged with main at d1fa97e, 9a8e30c, 4d990e9 and 7b4c313 (#153, #142, #136, #110, #87, #88,
  #151: `display-wake` counts kind 43 among the kinds that never declare, 193 checks and M61).
  Verified (2026-10-20, this Mac at a load average of 300 to 900 from other work all along):
  `swift build -c release` from `git archive`, only the CaptureProbe warning; the iOS app with Xcode
  27.1, Debug and Release for the generic simulator and Debug for a generic device, only the known
  `StreamClient` warning; `run-all.sh`, all 49; the mutants of `away-quality` (24), `audio-codec`
  (9), `audio-packetizer` (27), `ledger` (12), `away-wire` (9), `audio-playout` (38) and `tour`
  (84), every one caught (the last two finished on 2026-10-26, after a pause had stopped them at
  21 and 14, none missed); H2, main's CLI and this one identical masked and sorted (idle, a Desktop
  client, one whose hello plays sound) but for the stop's timing; H7 (a device's Send Audio refused;
  the CLI's `--audio` tone with no seq gap and its stop; a second client's off refused while the
  first kept its sound); the sound harness's home, home-off, home1024, segments and relay2, every
  gate but H12 once home and segments ran again (the first round stalled by the load), H12 +4.0
  points; H10, only the sound's panes, menu.txt and its two cards; S1 to S3 on a private iPad
  simulator on iOS 27.0 (the 27.1 runtime here runs only the iPhone Duo): the mock's photos pixel
  for pixel main's without sound and with Larger Picture, the Sound button where it goes, the
  read-only Beta row; live, 35 clicks within 0.1 ms of their places, the Sound button off and on, a
  second client's off refused while the sound played on; a move with its copies dropped, no reset or
  jump. Again on the merge with 7b4c313 (2026-10-26): `swift build -c release` from `git archive`,
  only the CaptureProbe warning; `run-all.sh`, all 50; `display-wake`'s mutants, 61 of 61; H2
  against main's CLI at 7b4c313, the host's output identical masked and sorted in all three modes;
  H7 as above (979 packets, no seq gap); the iOS app's sources and StreamProtocol 9104023's, and
  none of the files the merge changed in the sound harness.
- **Two switches in the device's Settings panel (2026-10-27, branch `sound-toggle` from main at
  b4caa91, PR #235; docs/audio-plan.md, "Two switches in the device's Settings panel", and Q8 and Q10
  revised).** Noah: "I've decided the audio setting should not be in the main button tray but instead
  in settings. Sound should be a toggle in the settings menu." (He had asked why the iPad's row was
  greyed out: read-only since the beta.) The host takes a device's kind 17 `sendAudio` again, on or
  off, from either door (`DeviceSettings.accepted`; `sendAudioRefusal` gone), Sill.app saves it as a
  menu click (`applying`, `applyingAway`), never a restart ("Settings from ‹device›: send audio off →
  on"), and Settings › Streaming's footnote says a device can turn it on and mute itself (the Mac's
  menu, Settings switch and `--audio` as they were). On the device, the Mac's group's **Send Audio**
  is a switch through the ledger (the "Beta" tag kept; off and disabled with "Update Sill on ‹Mac›…"
  for a Mac without sound; a Mac from the beta refuses it: the switch goes back with the warning
  haptic), and **Mute**, right under it (`soundMuted`, kept, off by default), shows for every Mac with sound, on or off
  (`macHasSound`), so a device can stay silent before any device turns the sound on. No Sound button
  in any bar: PortraitStreamScreen.swift, PhonePortraitLayout.swift and MacMenuButton.swift, and the
  checks `phone-portrait` and `tour`, are c215514's again. The mock's `default` is a Mac with sound,
  Send Audio off; `nosound` is one without. Verified (on a6576808, this Mac's load 7 to 352, heavy
  steps paused over 20): `swift build -c release` and the iOS app with Xcode 27.1 (Debug and Release
  for the generic simulator, Debug for a generic device; and the second commit's state), only the
  known warnings; `run-all.sh`, all 54 (`message-reader` on its own after a pause broke its timed
  case; `away-quality` 89 and 26 of 26 mutants, `ledger` 100 and 12 of 12, `phone-portrait` 484 and 73
  of 73, `tour` 111,189 and 84 of 84); H2 against main's CLI, idle identical masked and sorted, a
  Desktop client and one whose hello plays sound but for a second or two of `cursor.shape`; H7, a
  device's Send Audio on and off ("Settings from sillclient: send audio off → on", 500 packets with no
  seq gap, "Audio stopped: Send Audio is off.", a second client's kind 16 and packets the same, no
  restart); the bare app's previews, only Settings › Streaming's footnote; harness photos on a private
  iPad simulator (deleted after), every bar with the Mac sending sound pixel for pixel main's with it
  off (landscape, the iPad's portrait bar, a phone at 393 and 375 pt, the Duo's five poses), the panel
  at 1000×710 and 710×1000 at both text sizes; live against `SillHost --synthetic`, the device's
  switch turning the sound on and off on the host, Mute's "engine off (muted)" and "unmuted", every
  click within 0.1 ms, and main's CLI (a beta host) refusing it, the switch back off. **Untested, for
  Noah:** on the iPad and iPhone with this Sill.app, Send Audio from the iPad's panel (the iPhone
  hears it too, Sill.app's menu and Settings show it, `defaults read me.saffer.sill.mac sendAudio` is
  1), Mute on one device while the other plays, Mute before Send Audio is turned on elsewhere,
  VoiceOver on both switches, and this iPad against a Sill.app from the beta (the switch goes back)
  and against 0.5.1 (the row disabled, "Update Sill…").
- **Untested, for Noah:** everything on the devices, the plan's P1–P16, which end the beta with H12
  met or accepted (P13, Sill.app's CPU with sound on and off), P5 answered (Virtual Display, a
  minimized app) and P6 measured (the sync, filmed). Sill.app's menu and Settings rows can be looked
  at (previews), and `defaults read me.saffer.sill.mac sendAudio` is absent until it is first
  set, which reads as on in Sill.app since 2026-10-27 (#236).

**The Close timeout and the interrupted picture (2026-10-19 and 20, PR #93 from addhumal, finished on
its branch `audit-fixes`, which has main at 4d990e9 in it; issue #101).** The triage of 2026-10-16 and
2026-10-19 (sill-handoff/triage): the close half ready; the re-pick, the broken harness and the
throttle to change. Host, device and one additive kind (44).
- Close (the contributor's, kept): the button `kAXCloseButtonAttribute` gives is a new element on the
  system's default timeout, pressed on the host's main actor, so an app whose close asks about unsaved
  changes in an alert of its own, or a hung one, held input, picks and settings for every device that
  long. It is type-checked (CFGetTypeID, then the cast, as MenuReader does) and given 1 s.
  `WindowSizer.perform` says what came of a light (`CommandOutcome`, its words per action): "Window
  104 close: no answer in time (the app is busy, or asking about unsaved changes); it may still act"
  where it said "refused"; a minimize or full screen with no answer says only that the app is busy
  and that the window may still minimize, or go in or out of full screen. The contributor's harness
  (`Scripts/menu-check/run.sh close`, the fixture's Slow Close window) builds again (since #75
  WindowSizer needs WindowRestore.swift), and checks the words of every action too.
- The interrupted picture, replaced: the PR picked the source again (kind 6) every 2 s, which
  restarted every device's stream and raised the window in regular mode, for ever if a layer kept
  failing. Now the device asks for a keyframe: kind 44 `keyframeRequest`, device → host, empty. The
  host answers with `HEVCEncoder.requestKeyframe` (a still window's last frame encoded again; every
  device gets it, as when one joins), at most one a second per connection ("Keyframe for ‹device›:
  its picture was interrupted."; the rest one line a minute), nothing while nothing streams, never a
  restart or a raise. A host from before skips it without a line, and the picture waits for the
  stream's next keyframe, as it did: the encoder makes one every fps × 4 encoded frames (no time
  limit: none while the window stays still), when a device joins and when the stream restarts, never
  because the window changed (its delta is dropped while the device waits). There was no
  device-to-host keyframe request before: the host asked its encoder only for a joining device and a
  dropped delta.
- Device: HEVCDisplayView's `checkLayer` (network queue) flushes a layer that failed (`status`,
  `error`), could not decode a frame (`failedToDecodeNotification`; one posted before the picture last
  came back is ignored) or needs a flush to decode again (`requiresFlushToResumeDecoding`, and its
  notification): at each frame, at each notification and when the picture's window becomes active.
  It says so (`onNeedsKeyframe`), and a keyframe that ends the wait says the picture is back
  (`onPictureBack`); a keyframe the flush throws away (the layer still read failed when it came) says
  both, back first. The rule, `KeyframeRecovery` (pure, main thread): one ask per interruption while
  its keyframe is due; an ask whose keyframe has not come within `answerWait` (max(4 s, 4 × the worst
  round trip of the last second that measured one), the settings timeout's and the clipboard
  receipt's measure) is owed again as a repeat, so a Mac that never answers is asked after 4, 8 and
  16 s, then every 32 s, which costs a Mac from before kind 44 nothing; only while the picture's
  window scene is foreground active (each Sill window has its own client) and something streams;
  2 s apart at least; a picture that fails again within 10 s of its keyframe, Sill active throughout,
  or an unanswered ask doubles the spacing (4, 8, 16, then 32 s); a trip away owes an ask that was
  out again and starts the spacing at 2 s again; a keyframe that comes while Sill is away never makes
  the next interruption a repeat; 10 s back ends a streak. The Mac sends its parameter sets before
  every keyframe and each sample carries the format, so nothing else is sent again. DEBUG lines
  "display: …" and "keyframe: …" ("no keyframe 4.0 s after the last ask; asked again");
  `-SillLayerFail <s>[,<s>…]` (a frame that cannot decode, enqueued) and `-SillKeyframeLost <n>` (the
  first n keyframes that end a wait thrown away by the flush); TEST ONLY `SILL_TEST_STILL_AFTER=<s>` (a
  synthetic Desktop still from then on), `SILL_TEST_KEYFRAME_IGNORE=<n>` (a synthetic host ignores
  the first n keyframe requests, as a Mac from before kind 44 ignores every one) and `sillclient.py
  --keyframe@T`. site/privacy.html's list of what a device sends its Mac gains the request ("When the
  picture on your device was interrupted, … a request to send the picture again."), between
  `<!-- Keyframe` and `<!-- /Keyframe -->` for the release that ships it (docs/release-checklist.md
  part 1 §3 has the perl line that cuts it for a republish before that release), and its date is
  October 20. No words for the release yet (the next What's New, README, support.html): as #80's
  did, they wait for Noah's device run of the trip to the background, the issue's own case, which no
  simulator shows.
- With #107 (on hold): its renderer already calls the same `onNeedsKeyframe`. It should drop its own
  throttle (`PictureSmoothing.DecoderRecovery`) and its re-pick, and call `onPictureBack` where its
  renderer takes a keyframe, so one rule serves both (Noah on #93, 2026-10-15: "One recovery mechanism
  should serve all of them"). #66 compiles StreamClient.swift for its Mac client: the new UIScene and
  UIApplication observers need its platform layer there.
- Kind 44 is this pull request's (posted on #81, 2026-10-19: 43 is #94's sound, 44 this keyframe
  request, 45 the Pencil's), but three open pull requests' checks still read 44 as free, and whichever
  lands second renumbers (a check's assertion or a mutant, never kind 44): #94's `compatibility` check
  asserts `StreamMessageKind(rawValue: 44) == nil` (its main.swift:258); #66's, #72's and #73's
  `pointer-control` mutant "kind 26 numbered 44" renumbers onto 44 (with 44 taken that mutant no
  longer compiles, which their mutants.py counts as not caught, so the mutants job fails: a free
  number instead, not 45); and #94, #66 and
  #158 each rewrite `pointer-control`'s "every other kind …" line around 44 (a textual conflict:
  keep 44 among the known kinds). #128 (Sill Viewer for Mac, left untouched by Noah's decision of
  2026-10-19) compiles iOSClient/StreamClient.swift with MacClient/HEVCDisplayView.swift, which has
  no `renderQueue`, `onNeedsKeyframe`, `onPictureBack` or `checkLayer`, its PlatformShims.swift no
  `UIScene.willDeactivateNotification`, `windowScene` or `activationState`, and its target no
  KeyframeRecovery.swift: whichever of the two lands second gives the Mac viewer those or keeps the
  recovery out of its build.
- Verified (2026-10-19): `keyframe-recovery` 51 checks and 20,000 random sessions against a model of
  the event history, 28 of 28 mutants (on the way it found a real fault: an ask held back until
  `last + spacing` was held again at that very time by rounding); `pointer-control` takes kind 44
  into its kind table (158 checks, its mutants again); `swift build -c release`; the iOS app for the
  simulator (CI's command), only the known StreamClient warning; `run-all.sh`, all 45; the menu checks
  against the fixture: reader 40, budget 4, mirror 69 (it failed 7 once while the screen was locked:
  nothing presses a menu under the login window), close 4 (back in 1.01 s, as no answer, the close
  delivered, the front app unchanged). Live on a private iPad simulator (iOS 27.0) against a loopback
  synthetic host on the software encoder, its Desktop still from 3 s: `-SillLayerFail 6` gave the
  layer's own -11821, one ask, one host line, the picture back 75 to 125 ms after, and one "Synthetic
  capture" line (no re-pick); `-SillLayerFail 6,6.6,12` asked at once, then 4.0 to 4.2 and 8.1 to
  8.3 s after the ask before (spacing 2, 4, 8), three host lines, twice; a trip to the background
  (Settings for 2 s): the simulator's layer never stops, nothing asked, the picture as it was;
  `sillclient.py --keyframe@3 --keyframe@3.2 --keyframe@3.4 --keyframe@5.5`: keyframes 50 to 60 ms
  after the two taken, one "ignored" line, and nothing for a request while nothing streams.
- The verifier's findings (2026-10-20, on 09549b3; each taken, one commit per theme): a keyframe
  the layer's own flush threw away left its interruption open with its ask out for good while Sill
  stayed active (now the picture back and lost again, and every ask has its wait); a trip to the
  background kept a streak's spacing (24 s more of a frozen picture after the return in its probe),
  and keyframes shown while away built one (now the trip starts the spacing at 2 s, and a keyframe
  shown while away keeps the trip); DEVELOPMENT.md said a Mac from before kind 44 brings the picture
  back when the window next changes (it waits for the stream's next keyframe; shown live against
  0.5.1); the minimize and full screen words; Noah's TextEdit step and 0.5.1 step; these merge notes.
- Verified after the fixes (2026-10-20, on the merge with main at 4d990e9, a machine shared with
  other agents and its load average in the hundreds, so every time here is slow):
  `keyframe-recovery` 95 checks and 20,000 random sessions against the model (never stuck while
  open, active and streaming; a re-ask only once its last ask's keyframe was overdue; no two asks
  less than 2 s apart, so the host's one a second never refuses a device's own ask), 39 of 39
  mutants, three of them each finding put back (an ask out never asked again; a trip away keeping
  the spacing; a keyframe shown while away ending the trip); `pointer-control` 158 checks and 33 of
  33 mutants; `run-all.sh`, all 47 (main's new `virtual-display-api` among them); `swift build -c
  release` on the merged tree, complete with no new warning; the iOS app for the simulator from
  clean derived data (CI's command, Xcode 27.1 27A9275), only the known StreamClient warning
  (StreamClient.swift:3819); `Scripts/menu-check/run.sh close`, 9 checks: back in 1.01 s as no
  answer, the close delivered, every action's words, the front app unchanged. The host alone
  (`sillclient.py`, loopback, software encoder): with `SILL_TEST_KEYFRAME_IGNORE=1`, requests at 4
  and 6 s: the first ignored with its line, the second answered (its keyframe 0.09 s later); the
  hook refuses `abc`, `0` and `-2` with its line. Live on a private iPad simulator (iOS 27.0)
  against loopback synthetic hosts on the software encoder, their Desktop still from 3 s, one
  "Synthetic capture" line a run (no re-pick): `-SillLayerFail 6`: the layer's own -11821, one ask,
  one host line, the picture back 1.2 s after; with `SILL_TEST_KEYFRAME_IGNORE=1` on the host: the
  first ask ignored with its line, then "keyframe: no keyframe 4.0 s after the last ask; asked the
  Mac for a keyframe (spacing 4 s)" 4.2 s after it, the host's "Keyframe for …", the picture back
  0.15 s later; `-SillKeyframeLost 1`: the keyframe that ended the wait thrown away ("flushed with
  the keyframe it waited for"), the next ask 4.06 s after the first (a repeat's spacing), two host
  lines, the picture back 0.08 s after it; `-SillLayerFail 6,9,13,21.5,37.5`: asks 4.05, 8.1 and
  16.0 s apart (spacing 2, 4, 8, 16), the fifth interruption held 28.5 s by a 32 s spacing, then
  Settings in front for 2 s and Sill back: asked at once ("spacing 2 s"), 21 s before the hold would
  have let it, five host lines and one "Synthetic capture" line in all. This build against Sill for
  Mac 0.5.1's host (`git archive v0.5.1`, its Desktop moving) with `-SillLayerFail 6`: asks at +0,
  +4.1 and +12.3 s, no line on the host and no disconnect, its pongs and frames throughout, and the
  picture back 15.2 s after the interruption with the stream's periodic keyframe.
- **Untested, for Noah:** on the iPad (and the iPhone) with this build and a Sill.app from this
  branch: a still window (TextEdit, nothing changing), Sill sent to the background for 2 s and back:
  the console's "display: the picture was interrupted …", one "Keyframe for …" in Sill.log, the
  picture at once, no "Capture started" and the window not raised; ten quick trips (a line each, and
  each ask at once, never one held for 4 s or more after a trip); a video playing in Split View beside
  Sill; two Sill windows, one swapped out and back; Close on a TextEdit window with unsaved changes:
  its sheet on the Mac, input and picks unaffected meanwhile, and in Sill.log most likely "Window N
  close: done" (a document's sheet returns at once; an app that asks in an alert of its own, or a
  hung one, gives "no answer in time …" after 1 s: either is fine); this iPad against Sill for Mac
  0.5.1: the device sends kind 44, which 0.5.1 skips with no line and no disconnect, the console's
  asks again after 4, 8 and 16 s, then every 32 s, and the picture back only with the stream's next
  keyframe (a still window's never, as before).
**A sleeping display wakes for a device (2026-10-19, PR #151 from acalatrava's
`fix/keep-display-awake`, reworked on top of its 2b8be47; issue #134).** Noah: "Modify the black
windows pull request to implement it properly (user activity when a device connects as you said)."
Host only: no wire change, nothing on the device, no setting. Towards #134, not Fixes: the device
test is Noah's.
- The rule (`DisplayWake`, pure, with StreamMessage.swift and Input.swift; `Tests/checks/display-wake`,
  190 checks and 60 of 60 mutants, in CI's matrix): user activity is declared on the Mac as a key
  press would declare it (`IOPMAssertionDeclareUserActivity`, `kIOPMUserActiveLocal`:
  `DisplayActivity`, on a queue of its own) for a person at a device: its session connecting (every
  connection), and an app opened (kind 7), input (8), a window's button (15), a menu item (25) or a
  gesture (28), each only 5 s or more after the last declaration. Never what the device sends by
  itself: a pick (kind 6: its own Desktop requests at a connection's start, after a capture stop and
  once a watched window closed, and its re-pick after a move), the viewport (9), settings (17), "show
  your pairing code" (21), a menu fetch (27), the clipboard (32), any other kind, input that does not
  decode, nor a bare pointer move within 2 s after the host's own stream restart or new frame size
  (`streamChanged`: a stream's first parameter sets and any that differ, the coordinator's
  `parameterSetsSent`; the device's `pointerFrameChanged` re-centre). `handle` forwards every message
  to the rule once (`deviceActive`), the connect from the client-connected path. Nothing is held: the
  display sleeps again by the Mac's own setting, counted from the last declaration.
- The lines (`DisplayWake.Report`, on DisplayActivity's queue): the main display read just before a
  declaration and again 0.5 s later on the same queue (`secondLook`); "Woke the display for iPad
  (iPad14,1), which connected." only when it read asleep then on, once for one wake (two connects in
  a second share it); else "Declared activity for …, which sent input." (", but the display read
  asleep 0.5 s later." when it did) at most once a minute, a woke line counting as that minute's;
  `disp.wake` in the stats line. A test host (`--synthetic`, as `injector.dryRun`) declares nothing and
  counts `disp.wakeDry`. TEST ONLY `SILL_TEST_USER_ACTIVE=remote` (every real host, Sill.app included,
  with a "TEST:" line) declares `kIOPMUserActiveRemote` instead. docs/DEVELOPMENT.md, "A sleeping
  display"; site/support.html, "The picture is black" (its Sill paragraph inside `<!-- Display wake`
  markers, cut by docs/release-checklist.md part 1 §3's perl line for a republish before the release).
- Changed from the PR as opened: its PreventUserIdleDisplaySleep assertion, held for every session
  (the panel lit all session long, against #133's privacy mode, and at home the Mac kept from idle
  sleep), and its single `kIOPMUserActiveRemote` declaration at the first device are gone; nothing
  runs on test hosts; no NSLog. Its device change (the idle timer off while the stream screen shows)
  is dropped: one window's stream screen leaving put auto-lock back while another window's session
  went on, a window closed mid-session may never run its onDisappear, and a device kept lit beside a
  Mac whose display now sleeps by itself shows black; it is its own decision, for its own PR.
- The verifier's findings (2026-10-20), fixed: the support page's line; DEVELOPMENT.md's claims (counted
  from the last declaration, the CLI's plain door, a pointer move or modifier key rather than a tap);
  the device's own Desktop requests and re-centre no longer wake the display; which kinds count moved
  from the coordinator's switch into the rule, checked; the woke line only once the display reads on,
  never twice for one wake; the Untested list below.
- Verified (2026-10-20, merged with main at 9a8e30c): `swift build -c release`, no new warning (the
  real call never ran here); the check and its 60 mutants; `run-all.sh`, all 46; a loopback synthetic
  host on the software encoder with two stand-in devices (a scratch client that, as
  `pointerFrameChanged` does, moves its own pointer to the middle as a restarted stream's parameter
  sets arrive; the software encoder's test pattern never changes size, so a restart stood in for a
  new size): `disp.wakeDry` at both connects (1.3 s apart), a tap, a move 8 s after a restart and a
  gesture; none for the Desktop asked for by itself (twice, each restarting the stream), the
  stand-in's own move as the restarted stream's parameter sets arrived (6 s after the last
  declaration), the other device's tap 1.3 s after the first's, a key 2 s after a move, or a pick of
  nothing; no `disp.wake`, no line, `pmset -g assertions` nothing of the host's; Sill.app's previews
  (140 files) identical to main's, rendered from one path. Again on the tree merged with main at
  4d990e9 (#110, #87, #88; only lists conflicted, kept whole): `swift build -c release`, no warning;
  the check (190); its mutants re-run until a pause stopped them, 54 of 60 caught and none missed (the
  rule, its check and the two wire files are byte for byte those of the 60 of 60 run); `run-all.sh`,
  all 47; the previews (140) identical; loopback runs with two stand-in devices and with two
  `sillclient.py` devices: `disp.wakeDry` at both connects, a tap, a person's move 3.3 s after a
  restart, a gesture and ⌘ alone; none for a second device's tap 2 s after the first, a pick of
  nothing, the Desktop picked again, the device's own re-centres (5.8 to 8.2 s after the last
  declaration), the viewport, a settings change, the clipboard, a menu fetch or input that does not
  decode.
- Known: a connection the device opens by itself counts as a connect (its reconnect after a dropped
  connection, a move to the cable, to Wi-Fi or home), and so does its re-centre when it reaches the Mac
  more than 2 s after the new stream's first parameter sets left (a slow remote link): either can wake
  a sleeping display once with nobody at the device (docs/DEVELOPMENT.md, A sleeping display). Telling
  them apart would need the device to say so, a wire change.
- **Untested, for Noah,** with Sill.app from this branch (release-signed with the embedded profile):
  `pmset displaysleepnow`, then connect the iPad at home and through Tailscale: the picture, not black
  windows, and Sill.log's "Woke the display for …, which connected."; `pmset -g assertions` lists
  `UserIsActive named: "Sill: a device is using this Mac"`, its timeout the display-sleep setting; with
  the iPad left connected and untouched the display sleeps by its own setting and stays asleep (no
  "Woke" line without a touch, also after "Capture stopped: …"), and a pointer move on the trackpad or
  ⌘ alone on the Magic Keyboard wakes it (Shift alone goes to the device's text system and the key
  row's modifiers only latch, so neither sends anything); a locked Mac (⌃⌘Q, the display asleep): its
  lock screen on the iPad. Then:
  whether `kIOPMUserActiveRemote` also wakes the panel, or keeps the picture live with the panel dark
  (#133): quit Sill, `open --env SILL_TEST_USER_ACTIVE=remote /Applications/Sill.app` (Sill.log's
  "TEST: user activity is declared as remote …"), `pmset displaysleepnow`, connect; Virtual Display
  on, a window streaming from Sill's own CGVirtualDisplay with the panel asleep: whether its picture
  needs the panel woken at all (if not, those sessions light the panel needlessly); and a laptop with
  its lid closed on power (Sill.log's "…, but the display read asleep 0.5 s later." and no "Woke"
  line; with an external display, that display).

**The clipboard both ways (2026-10-14, branch `clipboard` from main at 985a733; issue #64; PR #78;
the plan, its open questions with the default taken for each, the results and the review's fixes are
in `docs/clipboard-plan.md`).** Noah: work on the clipboard (after #67/#68, #69, #59, #57, #58), text
first. Wire, host and device; additive.
- Wire: kind 32 `clipboard`, both ways, JSON `Clipboard {text, image, stop}` (Clipboard.swift): pull
  request #66's number and shape (`image` reserved for a later generation; `stop`, a device's switch
  going off, is this change's); `WindowList.clipboard: Int?` (1: text), so #66's `Bool` becomes an
  Int as it rebases (a Bool does not decode). A device sends kind 32 only to a host that says 1 or
  more; any kind 32 subscribes, and `{}` is text alone: a host sends `image` only to a subscription
  that says it takes images (the floor; #66's host sends one to every subscriber). Text at most
  256 KB of UTF-8, the JSON at most 1 MiB either way. Kinds 29–31 stay free (#66's; the sound, once planned at 29, is 43).
- Rules, pure, both ends: `ClipboardPolicy` (StreamProtocol). Never sent: one from another device through Universal Clipboard
  (`com.apple.is-remote-clipboard`: reading it fetches it from there, found while building), the
  host's own write; types are judged before any data is read. A device's subscriptions and texts are
  rated 4 a second, its stop never (`hostReceives`).
- Host: `HostClipboard` (main actor; the pasteboard read and written on a queue of its own,
  `Board`, so a slow read never holds up input): the look at the change count four times a second
  while a device subscribes (Task.sleep, not a RunLoop timer), and only while macOS allows every read
  (`MacClipboard.access`, NSPasteboard's `accessBehavior`, macOS 15.4 and later: while it would ask,
  an alert at every copy, or denies, nothing is read, nothing copied meanwhile is sent, one line when
  that changes); an empty pasteboard waits up to a second for its contents (`hostWaits`: found live,
  9 of 12 slow copies lost before, none now); what was on the clipboard when the first subscribed is
  never sent; a device's text written `.currentHostOnly` with this launch's marker and passed to the
  other subscribers; one line per subscription or stop ("Clipboard: iPad (iPad14,1) shares the
  clipboard."), none per copy, never contents; `clip.sent`/`clip.recv`. `HostConfig.shareClipboard`
  (on): Settings › General's `ClipboardSection`, "Share clipboard with devices" (`shareClipboard`),
  and while macOS asks or denies, why and "Allow in System Settings…" (Paste from Other Apps,
  `Privacy_Pasteboard`; one read on that click first while macOS has not asked about Sill, so it is
  listed); the CLI's `--no-clipboard`; the Mac's alone, applied at once by `setTarget`. A synthetic
  host shares a pasteboard of its own (TEST ONLY `SILL_TEST_PASTEBOARD`, `SILL_TEST_CLIPBOARD_LOG=1`,
  `SILL_TEST_CLIPBOARD_ACCESS`), never this Mac's clipboard.
- Device: `StreamClient+Clipboard` (subscription, `stop`, the Mac's text written `.localOnly` with a
  10-minute expiration, the handled change count `Sill.clipboardHandled`) and `ClipboardChip`: when
  Sill becomes active (or a session starts within 15 s after) with new text on the clipboard
  (`changeCount`, `hasStrings`: no prompt), "Paste on ‹Mac›" / "Then press ⌘V there." with the
  system's Paste control (`PasteButton`, UIPasteControl) and Dismiss; its 20 s run only while it
  shows with Sill active, never under VoiceOver, which is told when it first shows (`chipCounts`);
  under the bar sideways (bottom corner while the link's line shows), above the window bar or row 1
  upright. A Paste is "Sent to ‹Mac›’s clipboard" only once a ping sent after the text comes back (a
  16-byte random payload, the receipt; none in max(4 s, 4 × the worst round trip): "Didn’t reach
  ‹Mac›. Try Paste again." and the chip again). Settings › This iPad: Share Clipboard
  (`Sill.shareClipboard`, on) and Paste on ‹Mac›, while the Mac says it. Harness:
  `-SillClipboardChip 1`, `-SillClipboardNote sent|long|notsent`; live, `-SillSettingsScript '<t> paste
  TEXT'` and `-SillSettingsCloseAt <s>`.
- The review (2026-10-14, eight findings, all taken; the plan's "The review"): the stop lost to the rate
  and macOS's paste privacy (the two should-fixes), the floor's image rule, "Sent" before the Mac had it,
  the chip unannounced and running out unseen, the Mac's footnote and the support page's sentence, the
  site's words marked `<!-- Clipboard` for the release (docs/release-checklist.md part 1 §3 cuts them
  for a republish before it), and on-by-default's effect on the device's clipboard left to Noah (open
  question 1).
- Verified (the plan's Results): `Tests/checks/clipboard` 259 checks and 72 of 72 mutants (in CI's matrix);
  `Tests/checks/run-all.sh` all 41; `swift build -c release` from `git archive` (only the CaptureProbe
  warning); the iOS app Debug and Release for the simulator and Debug for a device (only the
  StreamClient capture warning); H2 against origin/main (idle identical masked and sorted; a client that
  never subscribes, no new line); live on loopback (the review's stop sequence: the copy went to the
  client against 7e6468a, not against this build; the rate on texts; macOS's four answers through a
  file, copies made while it asked or denied never sent, one made after reads came back sent); on a
  private iPad simulator, the receipt and its absence through a relay that stops forwarding, the chip
  waiting under the Settings panel, through an app switch and under VoiceOver's stand-in, harness photos
  byte for byte the reviewed build's but the new note. Earlier (7e6468a): the XCUITest tap on the
  chip's Paste, two devices, every marker, the bare app's switch. This Mac's own clipboard was never
  read or written.
- **Untested, for Noah:** on the iPad and iPhone with this Sill.app, at home and through Tailscale:
  copy in TextEdit, paste on the device; copy in Notes, back to Sill, Paste on the chip, ⌘V on the
  Mac; a password copied in 1Password and in the Passwords app arrives like any copy since 2026-10-29 (it never did before; Sill.log has no
  line for it); Universal Clipboard on (same Apple Account): the chip may come once for the Mac's own
  copy (known), an iPhone copy is not passed on; Settings › General's switch live; VoiceOver on the
  chip (its announcement, no time limit); Split View (the chip waits for Sill's next activation; the
  panel's Paste works). From the review: macOS's paste alert through `defaults write
  me.saffer.sill.mac EnablePasteboardPrivacyDeveloperPreview -bool yes` (the plan's step 9: the
  orange line, Allow in System Settings…, Allow and Deny, then `defaults delete` it); Paste right
  after 10 s away from Sill ("Sent" only when ⌘V pastes it); on by default replacing a photo on the
  device's clipboard, and that clipboard empty 10 minutes later (say whether either should change).
- **Paste right away (2026-10-29, branch `clipboard-autopaste` from main at 35a9c47, PR #242; the
  plan's "Paste right away").** Noah, trying #241: "still doesn't automatically Cmd+V is that coming
  later?". No wire change; the device's alone but for one change on the Mac since the review (below):
  with Settings › This iPad's "Paste on ‹Mac› Right Away" on (under Share Clipboard;
  `Sill.pasteRightAway`, on by default, never sent), a Paste's receipt also presses ⌘V on the Mac
  (`ClipboardPolicy.pastesOnReceipt`: only a receipt in time, only while something streams, only while
  the Mac's last list says it shares its clipboard, never while the tour shows; `KeyChord.paste`, ⌘'s
  own key around V, through `sendFromKeyRow`), 50 ms after the receipt (`pasteDelay`: the host
  writes the text on its Board queue while it echoes the ping at once; on loopback a ⌘V right behind
  the receipt came before the write in 99 of 100 of a test client's pastes and 21 of 25 of the app's,
  up to 14 ms early, and with 50 ms in none of 125); then "Pasted on ‹Mac›.", without ⌘V today's
  words; the chip "Where the cursor is.". The other way stays the person's (no iOS app pastes into
  another). Harness:
  `-SillClipboardNote pasted`, `-Sill.pasteRightAway 0`, DEBUG `-SillPasteDelay <s>`. Verified:
  `Tests/checks/clipboard` 285 checks and 91 of 91 mutants, `key-strokes` 359 (`KeyChord.paste` leaves
  nothing held) and 86 of 86; `run-all.sh` all 56; the three iOS builds and `swift build -c
  release`, only the known warnings; live on a private iPad simulator against a loopback synthetic host:
  the write, then "key 55 flags changed (command)", "key 9 down (command)", "key 9 up (command)", "key
  55 flags changed (none)"; the switch off, the write and no key; through a relay that stops
  forwarding, neither and "Didn’t reach"; harness photos in
  `~/Downloads/sill-handoff/device-tests/2026-10-29/autopaste/`; CI's Build and check passed on
  89f2c21.
- The review (2026-10-29, the plan's "The review"; six findings, each reproduced, then fixed in a commit
  of its own): a Mac whose Share clipboard with devices went off while a Paste was on its way dropped
  the text but echoed the receipt, and ⌘V pasted what it held before (a scratch host turning the
  switch off on a signal, a relay adding 1 s): the rule takes the Mac's last list (`hostClipboard`,
  2d9428a); the tour's hold, only in the glue and unchecked, is the rule's (`tourShows`, d435e8c); the
  chip "Where the cursor is." ("It goes where the cursor is." was cut short on 375 and 393 pt iPhones at
  xLarge text, 1ddadb9); under the Dvorak layout Paste presses ⌘K (V's place; the layouts' own data):
  Known, the support page, open question 16 (3dc8596); `-SillSettingsScroll clipboard` for the Paste row
  and footnote at 500x710 (734825d); and the Mac's one change, `HostClipboard`'s Board writes a device's
  text before `received` returns (1d8cf03): a main actor busy as the text arrived (a host's first
  stream start held it 70 to 150 ms) took the text and the keys back to back, and V came within half
  a millisecond of the write's end, before it in 4 of 25, now never. Re-run: `clipboard` 285 and 91 of
  91 at the head, 342 and 94 of 94 after; `key-strokes` 359 and 86 of 86; `run-all.sh` all 56 after;
  the three iOS builds, `swift build -c release` (from `git archive` of the head: 46.7 s, the
  CaptureProbe warning), the PR's live runs, the race (the app at 50 ms 0 of 25, at 0 ms 15 of 25), 11
  of the 12 photos byte for byte; the review's photos in `review/`; CI's Build and check on 694d600.
  **Untested, for Noah** (the plan's ten): a paste into TextEdit, Notes and a Terminal at their
  cursor, the switch off, a paste with no text field in front, VoiceOver's words, Universal Clipboard
  on, through Tailscale, the Settings panel's Paste row, a Paste as soon as the chip shows after Sill
  comes back and right after a pick, a Mac with the Dvorak layout (⌘K; open question 16 is Noah's
  call). The PR's description predates the review.

**A hardware keyboard and trackpad on the device (2026-10-14, branch `hardware-keyboard` from main at
985a733, PR #80; issues #67 and #68; the plan, its eleven open questions with the defaults taken, and the
results are in `docs/hardware-keyboard-plan.md`).** Noah: "Work on the keyboard and trackpad change (#67
and #68 together)". Device only: no wire change, nothing on the Mac changed.
- Esc (#67: an iPad Pro M4's Magic Keyboard sent none, 22 `in.text` and no `in.key`):
  `InputOverlayView.keyCommands` adds Esc with each of the sixteen ⌃⌥⇧⌘ combinations
  (`wantsPriorityOverSystemBehavior`, no title) while the view is first responder and no `EscapeKey` is on
  screen in its window (`EscapeKey.onScreen(in:)`; an EscapeKey's own Esc goes to the newest one in the
  window it was pressed in, `fire(in:)`: each Sill window is its own); the action goes through
  `ForwardedKeys.commanded` (down and up, the command's modifiers). One key press is sent once whichever
  channel brings it (`pressed`: a press no later than a command is swallowed with its up; `commanded`:
  nothing while the press holds it down). The Settings panel gains `EscapeKey(action: close)` (Done keeps
  `.cancelAction` for ⌘.). DEBUG: an `hwkey:` line for every hardware key and its channel, `escape:` when
  an EscapeKey takes Esc, `-SillKeyProbe 1` (GameController's view of each key), `-SillEscViaCommand 1`.
  For the reporter: Control-[ is Esc in a terminal.
- Keys without the Keyboard button (#68): `HardwareKeyboardPolicy` (pure, `Tests/checks/hardware-keyboard`),
  owned by `InputOverlayProxy` (one per stream screen; it outlives a rotation). With a hardware keyboard
  (`HardwareKeyboardMonitor`, GameController's coalesced keyboard; DEBUG `-SillHardwareKeyboard 1|0`) the
  input view takes the keyboard by itself when a view joins a window (a session's start, a rotation, a
  reconnect), a keyboard attaches or the last taker closes (`StreamScreen.keyboardTakers`: Settings,
  pairing, the tour, the Apps drawer, Menus), and lets go when a taker opens or the keyboard goes; another
  responder's keyboard is not fought. Never the person's own: `keyboardShown` (the Keyboard button, the key
  row's cap, the tour's busy and activity tests) is only the person's (`onOwnChange`), so keyboard users get
  the tour. The button: over the hold, the person's (`makeOwn`: iPadOS's keyboard views back); again, the
  hardware keyboard's (`makeAutomatic`). During the hold the input view is an empty view with no assistant
  groups: nothing drawn, even where UIKit and GameController disagree.
- Trackpad and wheel (#68): two scroll-only pans (`.continuous`, a phased gesture with the finger's coast;
  `.discrete`, plain deltas), `maximumNumberOfTouches = 0`, `[.indirectPointer]`, touches refused, beside
  the hover; one path with the finger pan (`scroll(_:at:translation:velocity:from:)`), one scroll gesture
  at a time; a pointer scroll's first event and a lone notch are deltas (`scrolled(to:at:)`).
- Defaults taken: the button keeps its software-keyboard meaning; the drawer and Menus are takers; all
  sixteen Esc combinations; nothing drawn during the hold; the person's keyboard across a rotation and ⌘W
  with a taker open as before; Sill's own coast for a trackpad; no scrolling over the on-screen trackpad;
  the hold also under Full Keyboard Access and Switch Control until Noah's step 13 says otherwise (UIKit
  can tell Switch Control, not Full Keyboard Access).
- Verified (the plan's Results): hardware-keyboard 51 checks, 20,000 random sessions, 31 of 31 mutants (in
  CI's matrix); key-strokes 347 (18 new) and 81 of 81 mutants (9 new); `run-all.sh` all 41; the iOS app
  Debug and Release for the simulator and Debug for a device, and `swift build -c release`, with the known
  warnings only; 19 harness photos identical to main's (the Menus pull-down open among them, the hold let
  go under it); live on private simulators against `SillHost --synthetic`, with `Tests/keyrig` (new, TEST
  ONLY: a virtual HID keyboard and mouse inside the simulator, as duorig): keys and ⌘W with no Keyboard
  button, after two turns too (an iPhone, `-SillTurnAt`); Esc, ⇧Esc, ⌘Esc and ⌥⌘Esc through both channels;
  Esc closing Settings and skipping the tour with nothing sent; the tour shown with a keyboard attached; a
  keyboard going and coming; the button's two states on a fresh iPhone; wheel notches; the touch rig 72 of
  72 against main's. Found there and fixed: a lone wheel notch was never sent; the rule asked with no view
  in a window. Learned in the simulator: its GameController always counts its own keyboard, UIKit counts
  one once keys arrive, iPadOS 27 refuses programmatic turns, and scroll events marked as momentum reached
  no pan there (no real trackpad's events reached the continuous pan, so a device decides whether iPadOS
  coasts too). CI's Build and check passed on 807c8ef. With the other open pull requests it meets in the
  docs and, with #79, in StreamScreen.swift's DEBUG hooks (keep both): the plan's Progress.
- The review (2026-10-14; the plan's Results, "The review and its fixes"): four findings, each checked
  here first and fixed in a commit of its own. Esc's key commands and EscapeKey keep to their own window
  (`onScreen(in:)`, `fire(in:)`): Settings open in a window behind took the stream's Esc key commands in
  front (a private simulator, `-SillSecondWindow 1 -SillSettings 1 -SillEscViaCommand 1`: 2fc53ed's build
  sent no key 53 to the host, this one did), and Esc could close another window's panel. README, the
  support page, the App Store bullet and the next What's New kept Esc and trackpad scrolling out until
  Noah's steps 1, 7 and 9 passed, through Universal Control on 2026-10-15 (the plan's "Words that wait
  for a device", and the Results' "Noah's test through Universal Control"), and then took them; the support page's Keyboard
  button sentence; Full Keyboard Access and Switch Control (open question 11, step 13). Towards #68, not
  Fixes. Again on 7fdc902: the three iOS builds and a clean `swift build -c release`, the known warnings
  only; `run-all.sh` all 41 at the first run; the touch rig 72 of 72; Esc in one window and in two, live; no check
  compiles a file the review changed, so no mutants again.
- **Untested, for Noah (the plan's 1–13, on the iPad with the Magic Keyboard, a Debug build):** which
  channel brings Esc (`hwkey:`; `-SillKeyProbe 1`), Esc in iTerm2's vim, zsh's vi mode and Zed, and
  Control-[; typing right after connecting and after a turn; ⌘W closing the Mac's window, not Sill's;
  nothing drawn, and nothing popping up when the keyboard is taken away; the Keyboard button's two states;
  Esc over Settings, the tour and pairing; the tour on a fresh install with the keyboard attached;
  two-finger scrolling (any double coast) and a mouse's wheel; VoiceOver; an input method's candidates
  (none drawn during the hold: the Keyboard button brings iPadOS's views back); two Sill windows side by
  side (Settings open in one leaves Esc to the other; Esc closes only its own window's panel); Full
  Keyboard Access and Switch Control (Tab, Space and Esc through Sill's bar while the stream holds the
  keyboard).

**Larger Picture on an iPhone held upright (2026-10-14, branch `larger-picture` from main at 985a733,
PR #79; issue #58, promised to rosstex; docs/larger-picture-plan.md has the rule, the numbers, the
open questions with their defaults, the results and the review's fixes).** "The menu and touchpad
take up more than half of the vertical space." Device only: no wire change, nothing on the host.
Since Noah's test on his iPhone 15 Pro (2026-10-15: "when in Desktop mode, there is negative space
on the bottom, seemingly because of the Mac aspect ratio. Can we disable this feature when Desktop
mode is active?") it applies only while a window streams (the bullet "Only while a window streams").
- Settings › This iPhone: **Larger Picture** (off by default; `Sill.largerPicture`,
  `StreamClient.largerPictureKey`, never sent; offered only on an iPhone without a hinge whose
  picture it makes larger: the environment's `largerPictureOffered`, from
  `PhonePortraitLayout.offersLargerPicture(screen:)`, judged upright whichever way the phone is
  held). With it on, a phone held upright (`PhonePortraitLayout(size:keyboard:)`) has, while a
  window streams, no thumbnails' row; the picture's room is every point that keeps the key row
  10 pt above the software keyboard (H − K − 152: 18 Pro Max 424×265 → 424×422, 15 Pro 377×235 →
  377×340, SE 359×224 → 359×262); the trackpad is the keyboard's footprint, so nothing moves when it comes up;
  row 1 takes the Menus button after Apps while the Mac sent menus (`buttonsBesideMenus`); the pane
  is the picture's own shape at the top of the room (`pane(video:)`), the viewport the whole room
  (one new viewport per switch: the Mac fits a window to it once Aa is set, or on the virtual
  display), the trackpad's span the picture's shape (`trackpadSpan(video:)`). Windows come from Apps
  (an open app again shows its next window) and Menus › Window. The Apps drawer opens above row 1,
  over the room (`drawer`), so no keyboard covers it, the Mac's or its search field's, and VoiceOver
  reads it after row 1 (PortraitStreamScreen's `AfterRow1`). A change of the switch shows when the
  Settings panel closes (`StreamScreen.largerPictureHeld`), so the panel never moves under the
  finger. Sideways, on an iPad and switched off, everything is main's.
- Only while a window streams (Noah's test, 2026-10-15; the plan's rule 12, open questions 12 to 14,
  Results "The Desktop keeps the standard arrangement"): one pure function of the switch and of
  what streams, `PhonePortraitLayout.largerPicture(switchOn:streaming:)` (`Streaming`: nothing,
  desktop, window; StreamScreen maps `client.active` and computes `largerPictureNow`), put in front
  of `keyboard(for:largerPicture:foldable:)`, so the arrangement, its viewport and the tour's
  targets, words and room all follow it. The Desktop keeps the standard arrangement (Aa never
  resizes it: on the 15 Pro its 377×244 frame left 96 pt of the 377×340 room black, on the Pro Max
  147 of 422), and so does nothing streaming (connecting; a window closed, until the Desktop the
  device asks for; a pick that failed), so the Desktop's first picture never arrives into a layout
  that then flips; the Mac never reports nothing between two windows. The Settings panel holds the
  arrangement (Larger Picture in effect when it opened), so a change of what streams while it is
  open waits for it to close too; its footnote: "Held upright, a window’s picture takes the place of
  the window thumbnails and reaches down to where the keyboard comes up. The Desktop keeps the
  thumbnails. … A change applies when you close Settings." A switch between the Desktop and a window
  sends a new viewport (twice, the source change's repeat and the arrangement's, the second a no-op
  on the Mac): with Aa set the Mac fits a window picked from the Desktop to the 16:10 pane, then to
  the room, one restart at most, as a rotation's. A thumbnail's lights close when the arrangement
  changes under them (they hang from the strip). The Duo's cover as before. Verified: `phone-portrait`
  484 checks and 73 of 73 mutants (5 of the rule), `tour` 111,189 and 84 of 84 (4 of the rule, in
  PhonePortraitLayout.swift); the three iOS builds, only the known `StreamClient` warning
  (StreamClient.swift:3436); `run-all.sh`, all 40; on a private 18 Pro Max simulator, harness photos
  at its own stream screen and the 15 Pro's: the Desktop and nothing with the switch on pixel for
  pixel the switch off (plain, drawer, ruler, the tour's bar card; Settings but the switch), a window
  pixel for pixel the branch's before the change (Settings but the footnote); live against a
  synthetic host with a test client switching between the Desktop and a test window of the agent's
  own: `viewport: 424×422 pt` with the window, `424×265` with the Desktop, one restart on the first
  pick with Aa at 1× (none on the second, none back to the Desktop), none without Aa.
- Only where it is larger (`largerPictureGains`: the room taller than today's picture and row 1's
  six buttons 44 pt or more, `minButtonWidth`): Display Zoom's 320 pt (an SE, a mini, a 6.1-inch
  iPhone; a 6.1-inch one's room would be 304×173 against today's 304×190) keeps today's layout and
  has no switch; the zoomed 6.7-inch and 6.9-inch phones take it with the estimate (unmeasured).
- The keyboard K, measured on every iPhone size the iOS 27 simulators have and estimated from the
  stream screen's shape and width (`keyboardHeight(for:)`): 233 with a Home button; with Face ID 320
  from 414 pt wide, 301 from 390, 310 from 375 (the minis; the 11 Pro's is 301), 320 narrower. The
  portrait plan's SE (216) was wrong: its keyboard is 233, so the usual arrangement's SE key row is
  24 pt under it (the plan said 7). On the iPhone Duo none (`keyboard(for:largerPicture:foldable:)`,
  a hinge): the switch hidden, the cover as it was (its keyboard never measured).
- The tour: `TourTarget.apps` (row 1's Apps); without thumbnails (`thumbnails:` on `targets` and
  `copy`) the bar card lights Apps, Aa and Keyboard and its first row is about Apps; upright cards
  are placed against the picture's room (`TourPolicy.place`'s `room`, TourOverlay's), so a card
  stands under a short picture with its tail at row 1. TourLayout stays `.phone` (switching is no
  turn). DEBUG: `-Sill.largerPicture 1`, `-SillVideoSize WxH`, `-SillLargerPictureToggle`,
  `-SillDrawerSearch <text>`, `-SillAXDump` (the accessibility tree's order; a private simulator's
  `ApplicationAccessibilityEnabled` first), the console's `trackpad:` and `keyboard:` lines.
- The review (2026-10-14; five findings, all holding, one commit per theme): the drawer, under row
  1, kept only its search field above a keyboard (62 pt on every phone): now above row 1 (77abae3,
  d6322a9); Display Zoom made the picture smaller: now rule 10 (0e9aa0e); six 42 pt buttons at
  320 pt: gone with it; the switch moved 118 to 157 pt from under the finger: now it applies as
  Settings closes (0cbe883); docs. Not done: a Large Content Viewer on row 1's Menus button, a
  UIKit pull-down in every bar on main too (needs a device).
- Verified (the plan's Results): the three iOS builds, only the known `StreamClient` warning;
  `swift build -c release`; `run-all.sh`, all 40; `phone-portrait` 401 checks and 68 of 68
  mutants, `tour` 111,079 and 80 of 80; before the review, harness photos with the switch off
  against main's build (25 of 33 identical, the rest the lights' wiggle and the panel's new row),
  59 with it on (the bare layout within 1 px at 3x), live on 14 iPhone simulators against a
  synthetic host (the key row 10 pt above the real keyboard, one viewport per switch); after it,
  13 harness photos against main's (10 identical, 2 the simulator's home indicator, 1 the panel's
  scroll indicator: Display Zoom's 320 pt, the Duo's cover, sideways and the switch off as main's),
  live on the 18 Pro Max, the 15 Pro and the SE the whole drawer above the Mac's keyboard and its
  search field's, to the pixel, the switch flipped with Settings open moving nothing until it
  closed (then one viewport), and VoiceOver's order with the drawer open: row 1, then the drawer.
  Photos in `~/Downloads/sill-handoff/larger-picture/` (`review-fixes/` for the review's).
- **Untested, for Noah (the plan's P list), on the iPhone 15 Pro with this build:** with the switch
  on, the Desktop as with it off (no black under it), a window picked: Larger Picture as it appears
  (with Aa set the window grows into the room a moment later), the Desktop again: the thumbnails
  back, a window closed on the Mac: the thumbnails back, then the Desktop; Settings ›
  This iPhone › Larger Picture on and off with Notes and Chrome streaming (the change as Settings
  closes; a 16:10 window keeps its shape, black under it; Aa, then any size, fits it to the taller
  picture; a window taller than 16:10 gains at once); the keyboard up and down (esc to shift 10 pt
  above it, nothing moves, row 1's Keyboard takes it down; with a Debug build Xcode's console
  prints `keyboard: up, 301 pt tall …`); windows from Apps (an open app twice) and from Menus ›
  Window; Apps with the keyboard up, and a search in it (the whole list above the keyboard);
  rotation both ways; the tour on a fresh install with the switch on; VoiceOver's order, the drawer
  open too; an input method's keyboard (a candidate bar can cover the key row, never row 1); Display
  Zoom on (Settings › Display & Brightness › Display Zoom): no switch on a 6.1-inch iPhone; the
  Menus button in row 1 at an accessibility text size (a long press: no Large Content Viewer yet).
  On iOS 17 or 18, if an iPhone with one is at hand, the keyboard's height (every height here is
  iOS 27's). On a Duo from October 23: no switch, the cover as before.

**A window Sill sized goes back (2026-10-14, branch `restore-window-frames` from main at 985a733,
PR #75; docs/restore-window-frames-plan.md has the rule, the open questions with the defaults taken,
the review, the results and Noah's steps).** Issue #57 (rosstex): "disconnecting on the iOS app doesn't revert
apps back to their original shape/size on Mac". In regular mode (Virtual Display off) Aa resized the
real window (`StreamCoordinator.fitToViewport`) and nothing put it back, on purpose until now. Host
only; no wire change, nothing on the device, nothing stored.
- The rule (`WindowRestore`, pure; `Tests/checks/window-restore`): each fit's record (`original`,
  the AX frame before Sill first touched it; `set`, the frame read back; `asked`; `moved`, noted at
  a later fit by `movedSince`: at Sill's size its top-left corner elsewhere, at another size both
  edges of an axis gone the same way from where Sill left it, at either of Sill's sizes, so a resize
  from any edge or corner, or with Option, is no move; 2 pt tolerance) and, when the window stops
  streaming, `decide`: gone (nothing), full screen (left, a line), home (nothing), `settle` (Sill
  asked another size and the read-back never showed it: an app that applies a size late, stopped
  first; the original written again, no line), resized on the Mac after Sill's last fit (left
  entirely, a line), unmoved (the whole original frame), moved (its own size where it is, kept on its
  display by `keep`). Lines in the stage's style: "Restored ‹app› — ‹title› to (x,y,w×h)", "…, its
  own size where it was moved", "Left … at (…): it was resized on the Mac", "Left … as it is: it is
  full screen", "Could not restore …", "…: it is not answering Accessibility"; `win.restored` in the
  `[1s]` lines.
- The sequences (WindowRestore's since the review, generic over `WindowRestore.Access`, which
  `WindowSizer.AXWindows` answers through Accessibility, an isolated `@MainActor` conformance, and the
  check's stand-in Mac in the model): `fit`, WindowSizer.resize's (nothing for a window in full
  screen; the frame before, the nudge, the size; a refusal puts the nudge back and records nothing; a
  size gone unanswered, `Write.timedOut` from cannotComplete, puts it back and is recorded from where
  the window was; no read-back: recorded as not yet shown, its old size where Sill put it; the second
  nudge); `stop`, one window's way back (one read: no frame and listed is not answering, left with a
  line; not listed, gone; else `decide` and `put` through `WindowSizer.restore`); `stageHome`;
  `Ledger.restore` (every window that stops but the staged one); `keepsStreaming` and
  `coversDisplay` (below).
- Where: `fitToViewport` records every resize the app took or left unanswered (`WindowSizer.resize`
  returns `Fit`; no fit once `shuttingDown`); `select` restores every fitted window but the next
  source's once the old pipeline has stopped (a pick, the Desktop, `.none` when the last device
  leaves or the stream stops), and its defer every one when nothing streams; `shutdownForExit`
  (Quit, the signals under `HostShutdown.install`) and `releaseKeysForExit` (the CLI's default path
  at a signal) restore every one. `windowsChanged` (the review): a regular-mode window missing from
  the on-screen list keeps streaming through three looks, as a staged full-screen one does, when it
  was full screen when last listed or picked (`listedFullScreen`, `coversDisplay`: the stage's 98 %
  rule) or, fitted, Accessibility says it is full screen (`keepsStreaming`; `missingPolls` reset when
  another source is picked), so a window entering or leaving full screen keeps streaming and its way
  back waits for the real stop; the stream no longer ends there (the device was left on an empty
  panel). Virtual Display turned on while a fitted window streams: `VirtualStage.prepare(…, home:)`
  keeps the frame it would have gone back to (`stageHome`) and the record is handed over
  (`Ledger.take`) only once staged; `restoreFits` skips the staged window (Quit mid-`prepare`).
- Defaults taken (the plan's 19): the CLI's Ctrl-C restores too (a line only when a window was
  sized, the same exit status); full screen at the stop left (it keeps Sill's size when it leaves
  full screen; support.html says so); resized left, position included; moved keeps its place, also
  after a re-fit; a resize a re-fit undid is forgotten, from any edge or corner; a move and a resize
  between two fits judged as the edges show them; a failed restore tried once; nothing after a crash
  or `kill -9` (memory only); a window in full screen never fitted ("… is full screen; not
  resizing."); an unanswered size and a failed read-back recorded; the App Store text unchanged.
- The review (2026-10-14: two should-fix, four nits, each checked against the code, fixed in a
  commit of its own): 1, a window leaving full screen was stopped at the catalog's first miss and its
  way back decided mid-change (cb3045b); 2, a fit of a full-screen window was recorded if AppKit
  answered success (65c6645); 3, a resize from the left or top edge counted as a move (4beb02c; the
  review's simpler rule, no move once the size changed, would forget a move made before a later
  resize); 4, an unanswered size or a failed read-back went unrecorded (913deef; recorded as not yet
  shown, not the size asked, which the model showed wrong for late apps); 5, the check's model was a
  hand-written copy (ecd141a: the sequences are WindowRestore's and the check runs them; the glue
  around them, select, the poll and the stage, is still a copy, and the docs say so); 6, Noah's list
  and the public copy (the docs commit).
- Verified (after the review's fixes; the plan's Results): `swift build -c release` from clean copies of
  origin/main and of this branch, only the CaptureProbe warning; `Tests/checks/run-all.sh`, all 41
  (6 min 5 s on the final code); `window-restore` 41,499 checks (208 cases; the model's 5,000 sessions with windows
  that cannot be resized, full-screen writes answered either way, slow and flaky apps, resizes from
  every edge, and windows off the list on their way into or out of full screen: 214 looks kept
  streaming, 36 windows that left full screen while streaming went back) and 95 of 95 mutants
  (in CI's matrix; the first full run caught 94, F1's pattern gone stale, 299557c); H2 against 985a733: idle identical masked and sorted, a Desktop client identical
  but for the seconds where it comes and goes, as base against base; the restore probe live, 20 of 20
  (the screen unlocked, Noah idle, no device on Sill.app): step 13, the app stopped during a fit, its
  size unanswered then taken late (667×473), put back whole; step 14, the left edge dragged in before
  a re-fit, back whole. No iOS file changed; no screen changed.
- Not verified: Sill.app with a device; anything in full screen live (a full-screen Space would
  take over Noah's screen); the virtual display with a fitted window; the coordinator's glue live (a
  synthetic host picking a window would capture Noah's windows). Known: a pick, Disconnect or Quit
  within the second a window takes to enter or leave full screen may still leave it at Aa's size.
- **Untested, for Noah** (the plan's twelve, with Sill.app from this branch, the iPad, Virtual
  Display off, Aa at 1.5×): pick another window, Disconnect, Quit: back each time ("Restored …");
  moved on the Mac then disconnect: its size where it is; resized from the bottom-right then
  disconnect within 2 s: left; the left or top edge dragged, 2 s, disconnect: back whole at its old
  place; Virtual Display on, then deselect or Quit: back at its old frame; full screen and out again
  from the lights (and the green button) while it streams: the stream goes on, then disconnect: back;
  full screen, disconnect: left in full screen; a window already full screen when picked: never the
  display's size; two devices: only the last to leave restores; a second display unplugged while it
  streams; Terminal, an Electron app, System Settings; the probe again after any change.

**Finding the Mac again after hours idle (2026-10-14, branch `reconnect-after-sleep` from main at
985a733, PR #77, issue #69; the plan, the causes with line numbers, the decisions, the results and the
review's fixes are in `docs/reconnect-after-sleep-plan.md`).** The report: after a few hours dormant
nothing reconnected until the Mac was logged in to and Sill relaunched on the iPad. Device code, the
support page and the docs; no wire change, nothing on the Mac.
- The browsers: iOS makes a suspended app's connection to mDNSResponder defunct (-65569), and the
  Bonjour browser was made once (`startBrowsing`), so after hours in the background the rows were
  what it saw then, and a failed browse only said "Browse failed: …". Now the network browser, and
  the nearby one if it runs, is made again on the return from the background
  (`StreamClient.cameForward`: willEnterForeground after didEnterBackground) and after a failure, 1,
  2, 4, 8, 16, then 30 s later and in the foreground only (`DiscoveryPolicy.rebuildBrowser`,
  `browserFailures`: one that ran 30 s is the first again). The old results stay beside the new
  browser's for 3 s (`browserResults`, `rebuildSettle` = `networkFirst`), and a failed browser's rows
  stay as they are until it is made again, so a Mac that stays listed keeps its sightings by name.
  Its interfaces are the new browser's; the return stamps the session's pong as it resets liveness
  (`resetLiveness`), so a cable session whose new browser first lists the Mac on Wi-Fi alone stays
  on the cable. No line for a failed browse.
- The reconnect: a listed row was dialled at once, a dial not ready in 5 s was let go and nothing
  looked again (`tearDown` never does, whatever the comment said), and the retry chain ended at its
  first dial: two dials, then "Reconnecting…" for good, also under a Bonjour Sleep Proxy's record of
  a sleeping Mac. A dial that waited or failed began a new `Reconnect` and dialled at once (every 5 s
  for good to a stale row). Now `reconnectIfListed` dials a listing of the row at once, then 5, 10,
  20 and every 30 s after the last started, 12 at most, in the foreground only
  (`DiscoveryPolicy.redialRow`; `Reconnect.rowListing`, `rowDials`, `lastRowDialAt`); the row listed
  afresh, the return from the background, or a tap starts again. The line (`reconnectLine`):
  "Reconnecting to ‹Mac›…", after 3 "‹Mac› isn’t answering. It may be asleep. Sill keeps trying, or
  tap it to try now.", after 12 "Stopped trying to reach ‹Mac›. Tap it to try again.". The let-go
  looks again; a reconnect dial that ends without a goodbye before it connects is one dial
  (`sessionEnded`); "Waiting for ‹Mac›…" is a tap's line only; the retry chain lives while a
  reconnect is wanted, one at a time.
- A Desktop the Mac stopped (its capture stopped, so the host selects nothing) is asked for again
  at once, under the old 10 s spacing (`DiscoveryPolicy.autoDesktop`); 0.5.1 asks only with the
  Mac's next window list, sent when a window opens, closes or changes.
- DEBUG `-SillBrowserFail N` (each of the first N network browsers reported failed with -65569 half
  a second after it starts) and `-SillConnectCase asleep`. The support page's "Your Mac isn’t listed"
  gains a sleeping Mac (Sill may not be able to wake it, so keep it awake: Energy, or Battery) and a
  restarted one (Sill opens after a login, with Launch at Login); README's Good to know, the next
  What's New (docs/app-store-metadata.md), DEVELOPMENT.md.
- The review (2026-10-14, after 1c4b921), four findings, each fixed in a commit of its own: the
  home-side words said Sill can't wake a sleeping Mac, at odds with the bound's own reason (a dial
  through a sleep proxy may wake it) and neither verified: now "may not be able to" (1798232); a
  rebuild keeps a Mac by name, not by interface, so a working cable session back from a short trip
  could move to Wi-Fi and back on its pong from before the trip: the stamp above, a model in
  `sleep.swift` (f39b875); "0.5.1 never does" ask for a stopped Desktop: it does, with the Mac's
  next window list (37ed3de); "both browsers" made again: the nearby one only while it runs
  (0e8a098). Its own runs agreed with the ones below and ran `sessionEnded`'s new branch live (a
  TLS stand-in that never sends a window list: dials at +0, 7.2, 17.2, 37.3, 67.4 s; main's build
  dialled about every 6 s).
- Verified (the plan's Results): on a private simulator against `SillHost --synthetic --pairing` as a
  `_silltest._tcp` row, the host stopped for 20 s: main's build dialled at +0 and +6.3 s after the
  loss and then nothing for the minute after the host came back; this branch dialled at +0, 5.3, 15.3
  and 35.3 s and the session came back without a tap. Stopped for 300 s: 12 dials at the rule's times,
  the quiet line at +20.5 s, "Stopped trying…" at +281.8 s and no dial after it; back from the
  background, a dial at once and the session in 40 ms. `-SillBrowserFail 3`: made again 1.05, 2.12 and
  4.21 s after each failure, the row listed throughout. The Desktop: asked for again 10 ms after a
  stand-in Mac said nothing streams. Photos of `asleep` at the Duo's four sizes and 744×1133, default
  and accessibility-extra-large; `homerows` pixel for pixel main's. After the review's fixes: four
  trips to the background (2.3, 2.3, 2.3, 15 s) on a private simulator, the browser made again each
  time, settled 3.05 to 3.13 s later, one host connection throughout; `Tests/checks/policy` 446 cases
  (models of a host stopped, a sleep proxy, a new listing, the background and a cable session across a
  rebuild) and 158 of 158 mutants (28 new); `home-device` 182, `home-model` 62, `remote-rules` 123,
  their mutant patterns as on main; `run-all.sh`, all 40; iOS Debug for the simulator (CI's command),
  Release for the simulator and Debug for a device, only the known `StreamClient` capture warning;
  `swift build -c release`, only the CaptureProbe one; CI green on 0e8a098.
- **Untested, for Noah:** the real overnight case on the iPad mini (Sill left streaming or on the
  connect screen for hours, the iPad locked; back: the console's "browser: rebuilt the network
  browser (back from the background)", the Mac's row as it is now, and the session back by itself if
  the Mac is awake with Sill open); a Mac asleep behind an Apple TV or HomePod (`dns-sd -B
  _sleep-proxy._udp` lists one; the Mac's "Wake for network access" on): the row stays, dials every
  5, 10, 20, 30 s, the quiet line, and whether a dial wakes the Mac and connects, which settles the
  support page's words (the plan's §4 has them for a yes); R6, whether macOS stops a capture when the
  display sleeps or the Mac locks (Sill.app streaming the Desktop, then `pmset displaysleepnow` or
  ⌃⌘Q: whether Sill.log says "Capture stopped: …", and whether the picture comes back by itself once
  the Mac is woken and unlocked: this build asks at once, 0.5.1 with the Mac's next window list); the
  nearby browser made again (Direct Wireless on, the iPad on the iPhone's hotspot, Sill sent to the
  background and back: the console's "browser: rebuilt the nearby browser (back from the
  background)", the Direct row kept), which no headless run here could do without turning on this
  Mac's AWDL; a session over the USB cable across a short trip to the background (streaming over the
  cable, Sill sent away for 2 s and back: no "path: the cable went away" on the console, no second
  "Client connected" in Sill.log), which no test host on loopback can show.

**The Settings window on a small screen (2026-10-14, branch `settings-window-height` from main at
985a733, PR #74; issue #59; the probe, the plan and the results are in
`docs/settings-window-plan.md`).** rosstex, a 14-inch MacBook Pro on macOS 26.6.2 with Sill 0.5.1:
"The Remote Access settings on Mac are too tall and cannot be resized." Mac app only: no wire change,
nothing on the iOS side, the CLI untouched.
- Cause (a scratch probe of the same setup on macOS 27.0.1): AppKit gives the selected pane's view a
  constraint named `NSViewController.preferredContentSize.height` (the hosting controller's
  preferredContentSize, SwiftUI's whole Form) at priority 501, just over the window's own 500, and
  lays the window out to it, keeping its top-left; the window is not resizable, so nothing shortens
  it (a 50-row pane made a 2,028 pt window). The constraint follows growth and every tab switch; in
  the probe it did not follow a pane that got shorter, but Sill's Remote Access pane shrank the
  window with it (909 → 734 pt). Sill's window adds 80 pt of title bar and toolbar. Remote Access
  with the internet switch on (909 to 983 pt) and rosstex's 951 pt window fit a 14-inch only at More
  Space (1,800 × 1,169); General (727) fits at the default scaling, Dock or not, but not at the
  larger-text scalings with the Dock (`Tests/checks/settings-window` has each case).
- Fix: `SettingsWindowController.heightCap`, the content view's height at most
  `SettingsWindowFit.contentLimit` (the screen's visible frame less the chrome and 12 pt above and
  below, whole points, at least 200) at priority 750; the Forms scroll. Set at show, on every tab
  switch (`SettingsTabController.onSelect`), on `NSApplication.didChangeScreenParametersNotification`
  and `windowDidChangeScreen`; a new cap lays a window on screen out at once. `place()` (after
  `windowDidResize` and `refit`) moves the window back inside the visible frame, 12 pt clear of the
  edge it ran past, when Sill's own changes leave it partly outside; never sideways, never while a
  mouse button is down (then once all are up, `placeOnRelease`), and never a window that fits where
  it is: a saved frame sets only the window's top-left, and AppKit orders a window that ran off the
  bottom while hidden back in at the screen's bottom, so a capped window can sit flush with the menu
  bar or the screen's bottom, the 24 pt on the other side. Sill's virtual display is never the screen
  (`SettingsWindowFit.screenIndex`). Rejected in the probe: an NSHostingController subclass clamping
  preferredContentSize (SwiftUI never calls its setter) and a SwiftUI `.frame(maxHeight:)` on the
  pane (lowered while a pane showed, it left the window tall: the probe's 501 constraint did not
  follow it down).
- `SettingsWindowFit` (pure, CoreGraphics): `Tests/checks/settings-window`, 307,709 checks (the
  issue's screens, an external 4K display, screens above and beside, windows partly off the screen,
  the virtual display, the test height, then 20,000 seeded random cases) and 27 of 27 mutants, in
  CI's mutants matrix.
- TEST ONLY, the bare binary; Sill.app ignores each with one line: `-SillSettingsAfter '<s>
  <tab>|close|report|end|height=<points>; …'` (opens Settings as the menu does and prints the window's
  frame, the pane's whole height and how much shows), `-SillTestScreenHeight <points>`,
  `-SillSettingsShot <dir>` (docs/DEVELOPMENT.md).
- Verified (the plan's Results; this Mac, a 14-inch at its default scaling, 949 pt under the menu
  bar; the bare binary on `--synthetic` on loopback, only while no device was connected, Sill.app
  untouched): `swift build -c release` clean from `git archive`, only the CaptureProbe warning;
  `run-all.sh`, all 41; the previews (130 files) identical to 985a733's; every tab at its natural
  height (limit 845) but Remote Access with the internet switch on (909: shows 845, scrolls, 12 pt
  from both edges, Sill having moved it); `-SillTestScreenHeight 700`: General (727) and Remote
  Access (909) capped at 596 and scrolling; the screen changing under the tall pane (`height=`, the
  notification's path): 845, 596, 396, 845, the window shrinking and growing; a pane growing past
  the cap, and a tab switch to it, with the window low: moved up to 12 pt over the bottom; a window
  opened at rosstex's saved frame (951 pt, its top at the menu bar; a saved frame sets only the
  top-left) capped at 925, 0 pt under the menu bar and 24 over the bottom, and a 70 and a 140 pt
  Dock under it, 855 and 785, its top kept; a pane grown while Settings was closed, reopened by
  AppKit at the screen's bottom, 24 pt under the menu bar; General and Streaming scrolled to their
  ends inside a 600 pt screen (231 and 72 pt); Sill.app's ignore lines, from the binary in a scratch
  bundle under `sandbox-exec` with binds denied; CI's "Build and check" on c2339e2 and, after the
  review's fixes, 1865ada. Photos without personal details in
  `~/Downloads/sill-handoff/settings-window/`.
- Review (2026-10-14, at bb2451e; it re-ran everything above with the same numbers): three findings,
  each fixed in a commit of its own (the plan's "The review"). Should fix: the untested lists left
  out macOS 26, the reporter's, and Sill's virtual display (now U6 and U7). Nits: "the 501
  constraint never shrinks" and "General does not fit a 14-inch with the Dock" (corrected above,
  with 20 checks for which pane fits which scaling); U1, U2 and the PR's steps promised 12 pt above
  and below (now: 12 pt only on a side Sill moved the window away from). Re-run after the fixes:
  `swift build -c release` clean from `git archive`, only the CaptureProbe warning; `run-all.sh`,
  all 41; `settings-window` 27 of 27 mutants; where a capped window sits, with a scratch build whose
  window was invisible and never activated (the screen unlocked, nobody at it).
- **Untested, for Noah** (the plan's U1 to U8, with Sill.app from this branch on the 14-inch): at
  the scaling at the far left with the Dock showing, every tab fits between the menu bar and the
  Dock (12 pt clear only on a side Sill moved it away from), General scrolls to Quit Sill and Remote
  Access (Remote Access and "Allow connections from the internet" on) to Sleep; with Settings open,
  change the scaling and the Dock's size and hiding: it follows each time (note a Dock change that
  shows only at the next tab click); drag it to a smaller external display and let go low: it moves
  up once the button is up, and grows back on the larger one; a held click on a tab never moves it;
  VoiceOver reaches Quit Sill in a capped General; macOS 26, the reporter's (everything was
  measured on 27.0.1, and merging closes #59): U1 on a Mac with 26, or a build for rosstex; with
  Sill's virtual display there (Virtual Display on, a window streaming), every tab shows on the
  built-in display and fits it, also once Virtual Display is turned off with Settings open; macOS 14
  or 15 if at hand.

**Release 0.5.1 (2026-10-09, branch `release-0.5.1` from main at 05f2bb8, main merged in again
at e3ce043 after PR #47; PR #48; Noah's go the same day: "When #47 passes the CI, merge it, then
once that is merged do #48. Then run the release procedure").** Noah: "I want the release in the GitHub to line up with the app version, I want
all versions to be 0.5.1." One release, and one version for both apps from now on: Sill for Mac
0.5.1 (after 0.4.0; there is no 0.4.1; the tag will be v0.5.1) with Sill for iPhone and iPad 0.5.1
(4) (`MARKETING_VERSION` 0.5.1 and `CURRENT_PROJECT_VERSION` 4 in both configurations: the build
numbers keep counting across versions). docs/release-checklist.md has the rule (part 2's first
item) and the release's order ("The away release").
- In it since v0.4.0: PR #39, away from home (the entry below), PR #46, a Mac set up again (its
  old saved record retires itself), and PR #47, the iPhone Duo with the iOS 27.1 SDK (the entry
  below; the status bar hidden on the stream screen in every pose of the inner display, Noah's
  pick of 2026-10-09); PRs #44 and #45 went to TestFlight as 0.5 (3). Neither half
  strands the other (read from the code): Sill for Mac 0.5.1 serves 0.5 (2) and (3), and 0.5.1 (4)
  works with Sill for Mac 0.4.0, without the away quality and the link's notice, which are the Mac's.
- The words: support.html's and index.html's away sentences (inside the Remote Access markers) and
  privacy.html's date (October 9, 2026: the day the site goes out, if later); README's Good to know
  (0.4.0 or later; one version number); the metadata (the description's Away bullet, 2,603
  characters; the review notes' REMOTE ACCESS sentence, 3,995 bytes of 4,000, and the same sentence
  for App Store Connect's own notes; the version 0.5.1 (4) and its What's New; App Store Connect
  adds a version only once the current one is Ready for Distribution). README's How it works and
  privacy.html's link-report line came with #39. In sill-handoff's `release-051/`: the release
  notes (`notes-0.5.1.md`: a WAITS FOR comment to settle, then `fill-notes.sh` after `--publish`),
  What to Test for 0.5.1 (4) (`testflight-0.5.1-4.md`, 1,462 characters), and STATUS.md with every
  command's result.
- Verified on 336adc0 (STATUS.md): `swift build -c release`, only the CaptureProbe warning;
  `Tests/checks/run-all.sh`, all 39 (`policy` 392); the iOS app for the generic simulator as CI
  builds it, only the StreamClient capture warning; `release.sh --dry-run`: "Built .build/Sill.app,
  version 0.5.1 (535)", "identity keychain: data-protection keychain (access group
  9B2KKVM937.me.saffer.sill.mac)", Sill-0.5.1.zip 3.2 MB and Sill-0.5.1.dmg 3.3 MB, signed, not
  notarized ("Unnotarized Developer ID"); `release-ios.sh` without `--upload`: 0.5.1 (4), Sill.ipa
  2.8 MB, Apple Distribution, the App Store profile, `ITSAppUsesNonExemptEncryption` NO, both
  required-reason APIs declared. Nothing uploaded, tagged or published; only the branch pushed.
- Shipping (Noah's go of 2026-10-09 lifted the TestFlight hold of 2026-10-08): PR #47 merged
  (e3ce043), main merged into this branch (CLAUDE.md alone conflicted, both adding an entry at the
  top of Current step: both kept, this one first), the Duo in the words (a bullet of the notes, What
  to Test, the description and What's New, README's How it works, index.html), then the pull
  request's steps: merge, tag v0.5.1 on the merge commit, `release-ios.sh --upload` and What to
  Test, `release.sh --publish` from the tag, the notes (`fill-notes.sh`, `gh release edit`), the
  site republished, the check signed out; the results in sill-handoff's `release-051/STATUS.md`.
  Still open, and shipped without them on Noah's call: his device tests of away from home (P4–P13
  below) and of the iPhone Duo (the Duo entry's P1–P13, on a Duo from October 23); on the App
  Store, 0.5 went live on 2026-10-08 and 0.5.1 (4) on 2026-10-10, approved within hours
  (https://apps.apple.com/app/id6816359860; the large-display iPhone screenshots follow as a
  standalone Asset Library submission). The site and README name the listing since PR #49.

**The iPhone Duo with the iOS 27.1 SDK (2026-10-08, branch `duo-layout` from main at e6b3265,
main at 05f2bb8 (PR #39) merged in at 7bd7c41, not rebased; docs/iphone-duo-plan.md has the probe's
facts, the decisions, the review, the results and what Noah tests).** Noah: research the iOS 27.1
SDK for iPhone Duo, then "adapt the app to use this SDK, then use the simulator with iPhone Duo, make
sure it works properly, then take screenshots of all poses", with PR #39's merge kept cheap.
Approved from mockups: (a) the book pose, one stream across the fold and nothing you touch on it;
(b1) the laptop pose split at the fold's real frame; (b2) open flat upright, the picture at the
window's own shape and the trackpad the rest; (c1) the cover upright, the phone's arrangement beside
the camera's strip; (c2) on its side, the compact landscape bar. Device only, no wire change (a TEST
ONLY host picture aside).
- `DuoPosture` (pure) and `DuoPostureReader`: `onHingeChange` at the app's root (SillApp) into the
  environment; the fold's `.division` region (`.includeInactive`) from each screen's own
  GeometryReader, in its space, and before the hinge's first report the region alone (active: partly
  open; inactive: flat); nothing before iOS 27.1, and a device without a hinge or fold reads
  `unknown`, so every layout there is what it was (the inferred crease included). The fold is in the
  way while the hinge is partly open.
- Decisions (the plan's "The build: decisions", revised after the review; the status bar Noah's
  pick of 2026-10-09, option 1 of the three the mock canvas drew): the stream screen hides the
  status bar on the inner display in every pose (upright the picture keeps the 82 pt above the
  fold; sideways Sill has all 951 pt), and every other screen keeps it in every pose, the cover its
  strip; at 951 pt the book pose's bar keeps its regular size, its group beginning at 551, past the
  fold's 455.5–495.5, the strip ending 12 pt short of it (at 867 pt, the status bar shown, it would
  take the approved step to the compact width, Menus at 497); the laptop pose splits at 455 and
  496; open flat the pane takes the picture's
  own shape, 16:10 while the Mac fits a window to it (Aa, the virtual display); in the book pose the
  connect column, the pairing overlay, the window lights and PR #39's link line keep to a page, and
  a tour card to its targets' page (355.5 pt beside Settings); upright the connect column scrolls
  in the room above the fold, Add a Mac side by side there; the tour on the inner display says
  "Turn your iPhone on its side" for the keys and trackpad. The cover needed nothing.
- Hooks, a few lines each: StreamScreen (also `duoStatusBar` and LinkLineView), PortraitStreamScreen,
  AddMacCard (`ConnectLayout`), ContentView (the connect screen's room; the harness), PairingOverlay,
  TourPolicy and TourOverlay, SillApp; pbxproj AB01/FB01, AB02/FB02. The harness: `-SillLayout
  951x669`, `669x951`, `466x678`, `678x466` with the displays' safe areas as this build has them,
  `-SillHinge closed|half|flat`. CI: the Mac side on Xcode 27 (not a beta), the iOS app alone on
  27.1 (select-xcode's `allow-beta`: the image has only `Xcode_27.1_beta.app`, 27A9269); release-ios.sh
  refuses an Xcode before 27.1 and an app not built with the iOS 27.1 SDK, so TestFlight from
  GitHub Actions waits for a 27.1 release there. `SILL_TEST_PATTERN=picture:<path>` (TEST ONLY): a
  synthetic host's Desktop a still picture.
- The review (2026-10-08, two lenses): eleven findings, two of them the same (the status bar).
  Eight fixed, one commit per theme (5c2188a the status bar and the fold before the report, 7db22a3
  the connect column, 8906024 the tour, 9e4f36c CI; the checklist and README with the docs), and
  the plan's own leftover too (e75ea48 #39's link line); one tested here and given to Noah (the 27.1
  SDK off the Duo: P9; folds while away: P10, fine on the simulator); one older than the branch and
  left (an unlabeled VoiceOver element on the phone row's Menus button). c70a04c is the test picture.
- Checks: `duo` 252,557 and 67 of 67 mutants; `tour` 51,840 and 72 of 72; `run-all.sh`, all 40;
  each fix commit builds and passes both. Builds: iOS Debug for the Duo simulator, Release for the
  simulator, Debug for a device, `swift build -c release`, only the known warnings.
- Verified on a private simulator ("Sill duo", iOS 27.1, deleted after) folded by Tests/duorig
  against `SillHost --synthetic` on loopback (software encoder, a Weather picture as the Desktop):
  the stream, connect and Settings screens in all six poses, the tour's cards, folds and turns
  while Sill was in the background (six, each layout right on return, one connection) and slow
  folds mid-stream (180→90→180→120→0→90); the harness's mock in every pose with the drawer, lights,
  pairing, Add a Mac, eight Macs, the link line and the Menus pull-down. Photos at App Store
  Connect's Duo sizes in `~/Downloads/sill-handoff/duo/final/` (INDEX.md; `live/` private: this
  Mac's windows and name). The harness at 46 earlier cases against main's build (05f2bb8): 39
  identical, 7 differing only as main's build differs from itself. The branch contains main: the
  pull request merges without a conflict. CI run by hand on the branch (37835771799): green, the
  Mac side on Xcode 27.0, the iOS app on `Xcode_27.1_beta.app` (27A9269).
- **Untested, for Noah (on an iPhone Duo from Oct 23, a build from Xcode 27.1; TestFlight 0.5 (3),
  from Xcode 27.0, runs there in an 871×669 compatibility window, sideways only):** the plan's
  P1–P13: every pose, folding mid-stream by hand, the keyboard on the cover, 120 Hz on each display,
  Split View if iOS offers it, VoiceOver in the book pose, the iPad mini and iPhone 15 Pro on a 27.1
  build (P9), folds while away (P10), and the status bar decision. Left: (d) TestFlight 0.5.1 waits
  for the Duo's release.

**Away from home (2026-09-27, branch `remote-away` from `remote-pacing` at
c564142, PR #39, stacked on PR #34, which merged during its review; main at
e6b3265 merged in on 2026-10-08, one merge commit, not rebased, so the pull
request goes to main; PR B of docs/remote-bundle-plan.md, whose "Results: PR B",
"Merged with main" and "The merge's review" have every number).** Items 2–4 of the away-from-home
bundle, on PR A's pacing: an away session starts low, the Mac says when the
link cannot carry the quality, and a session away comes home by itself. Home
sessions are as they were (H2: the CLI's output and kind 16 unchanged).
- Wire (additive; HostSettings.swift): kind 16 gains `away` (`AwayQuality`: the
  home and away pairs, whether this connection is away, whether the away pair
  runs) and `link` (`LinkReport`: "behind" or "stalled", frames withheld, the
  running bitrate, the carried rate, a suggestion), optional and per
  connection; `QualityPreset.name(forBitrate:)` and `shortTitle(bitrate:
  captureScale:)` ("Low · Standard"). Kind 17 and `HostSettingsChange` as
  they were.
- Host: `HostConfig` has a second pair, `awayBitrate` and `awayCaptureScale`
  (`standard`: Low · Standard), and `effective(away:)`. `AwayPolicy` (pure): a
  device is away when the remote door admitted it from a VPN or the internet
  ("by address" is home); the away pair runs while at least one device is
  connected and every one is away, and the flag stays while nobody is. "Away
  from home: every connected device is away; streaming at Low · Standard (4
  Mbps per 60 fps, points). The home quality stays Pro · Retina." or "Home
  quality again: a device connected at home (…); streaming at …", one restart
  each, a join's flip waiting for that device's first viewport (1 s at most).
  A device away sets the away pair (`applyingAway`); kind 16 is per connection.
- The link (`LinkJudge`, pure; StreamServer's sweep closes every client's
  second, at home too; the home branch only counts): short = ≥ 3 frames
  withheld and ≥ a tenth; behind at 3 short of 5, fine after 5 clean, stalled
  after 3 s with bytes waiting, none taken and nothing heard; a restart at
  another quality (bitrate, rate, resolution), or none, resets it (no line),
  and one that keeps it (a window picked, a rotation) keeps it; the carried rate is the mean over seconds ending with ≥ 16 KB
  waiting (3 needed), reported again when it moves 25 %; the suggestion is the
  highest preset under 70 % of it at the stream's fps (Low when none fits, one
  step down without a measure, Standard with Low from Retina). The
  coordinator's lines: "Link to iPad (iPad14,1): cannot carry Pro (withheld 52
  of 58 frames in the last second; the link carried about 6.4 Mbps);
  suggesting Low · Standard.", "… nothing has got through for 3 s …", "…
  keeping up again." A report about a bitrate a pick has just replaced is left
  out of kind 16. No Stats key.
- Sill.app: Settings › Streaming's "Away from home" section (saved as
  `awayBitrate`, `awayCaptureScale`); the menu's Quality subtitle "Away from
  home now: Low · Standard"; a device's card row "3 fps, the link can’t carry
  Pro · RTT 531 ms · through Tailscale" or "Nothing is getting through".
- Device (`AwayCopy`, `LinkLine`, pure): the panel's header "Away: Low ·
  Standard" or "Home quality: Pro · Retina (a device at home is connected)",
  a footnote, the link's callout with its button ("The link can’t carry Pro.
  Low · Standard is recommended." / "Use Low · Standard", 44 pt), nothing for
  stalled, the old round-trip callout only for a Mac without `away`; a line
  over the stream while nothing is open over it ("The link can’t keep up with
  Pro. Lower it in Settings."), gone 2 s after the report clears (at once when
  it clears while something is open over it), announced once a spell.
- The move home (`DiscoveryPolicy.moveHome`, StreamClient on PR #12's moves,
  `MoveKind.fromRemote`): a remote session (not Connect Remotely) whose saved
  Mac the network lists by Mac ID for 2 s moves to the home door: the home
  viewport first on the new connection, the probe (another launch refused at
  its window list; kind 18 signed by the saved key, at least as new as the
  session's), the fenced hand-over, the remote connection closed after;
  retries 10, 20, 40, then 60 s; a remote connection that dies meanwhile is
  carried by the move (held, adopted; picks not sent).
- TEST ONLY and DEBUG (Build and run): SILL_TEST_REMOTE_ORIGIN (the remote
  door alone counts loopback as a VPN or the internet), SILL_TEST_PATTERN=noise
  (a square of noise, so a test stream's size follows its quality),
  `-SillSettingsScript`, `-SillMoveHomeTest`, `-SillDialSaved remotely`,
  `-SillLinkLine behind` and seven settings cases; `sillclient.py`'s `away=`,
  `link=` and `--expect` keys; the pacing harness's link verdicts and cases.
- Verified (the plan's Results): every pure check (25), the new ones' mutants
  (away-wire 9, away-quality 16, link-judge 26, away-copy 17) and policy's
  (76, with H15's) and fence's (32 over 17 modes); H2 against origin/main's
  CLI; the pacing matrix against origin/main (every pacing gate, and the
  link's with the dip's and the stopped downlink's measured from the host's
  first second withholding frames); H7, H8, H9 on the bare app, H12 end to
  end, H16 previews, H17; the iOS app, Debug and Release; S1 (144 photos),
  S3 (the callout and the line live), S4 and S5 (the move home live, its
  retries, another launch refused once, Connect Remotely staying).
- Found, and left for Noah (the plan's open question 14): behind needs 3
  short seconds of 5, and under PR A's pacing a link only a little too slow
  loses frames in rounds (drop, drain, keyframe, deltas), which can leave fewer
  than 3 short in any 5: at 1.8 times over the link, 8 s to report (the gate
  was 6); on a milder one maybe never. The carried rate often goes unmeasured
  then, and the suggestion is one step down.
- Adversarial review (2026-09-27, after the pull request; the plan's "The
  adversarial review"), on a move home that races a loss, a Mac that
  relaunches, two Macs with one name, the away pair never reaching the saved
  home one, the notice's hysteresis, VoiceOver and copy. Two fixes, each with
  a check that fails without it: a restart that keeps the quality keeps the
  link's judgement (f882291: every window picked or rotation cleared the report
  and it came back 2.5–3 s later, after the line's 2 s linger, so the line
  returned and was spoken again; the pacing harness's `linkrestart` and an end
  to end run through a relay showed it; `LinkJudge.judgedAfresh`,
  `StreamServer.resetLinks`, the coordinator's `judgeLinks`); and a line whose
  report cleared off screen never comes back (a67dc48: the callout's button,
  then Done within 2 s, brought the cleared line up and VoiceOver said it). A
  new simulator run of a move home whose remote path dies 0.5 s in, with a
  panel pick meanwhile: carried over the move, no connect screen, the pick not
  sent, the host never changing a setting (9 of 9). Left, in the plan: the
  move home's kind 18 floor against a broadcast in the same milliseconds, the
  callout's "·" for VoiceOver (P8), and open question 15 (a still window counts
  as keeping up, so the line goes and comes back between reading and
  scrolling). Every gate again on the final build (the plan's numbers): H1,
  the 25 pure checks and the two changed checks' mutants, H2 14 of 14, the full
  pacing matrix (ext60 once one drop in its last second, then 3 of 3 clean),
  H7, H8, H9, H12, H16, H17, S3 at 2 Mbit/s 18 of 18 (at the plan's 3 Mbit/s it
  failed while another checkout's mutant run loaded the Mac and the software
  encoder kept 3 to 7 frames a second), S4 and S5 but the check the software
  encoder's watchdog restarts broke under that load, and S1 at two sizes.
- Merged with main at e6b3265 (2026-10-08; one merge commit; the plan's "Merged
  with main"): 21 files conflicted, each settled keeping both sides whole. Where
  they meet: the move home dials the TLS home door pinned to the saved Mac's key
  (`DiscoveryPolicy.moveHomeTrust`, new, pure: exactly when a tap's dial of
  that row would be pinned; a plain door, a Mac that removed this device or one
  with a new key keeps the session remote; never a plain dial, DEBUG or not),
  its hello first inside TLS, only to a row whose tag names the session's saved
  Mac (#44's `rowMac`), the session taking the move's trust and row at the
  hand-over (`session.home`, `session.row`; `homeTLS` marked); a pin refused on
  the move home refuses that row (never #44's `newKey`: the session holds
  the Mac's key through the remote door); the kind 18 floor taken as the move
  starts (`DiscoveryPolicy.HomeMoveInfo`), which fixes the review's broadcast race. Host:
  SILL_TEST_REMOTE_ORIGIN reaches `Door` (`remoteDoor: kind == .remote`) and
  TestHooks; StreamCoordinator, StreamServer and HostConfig keep both sides;
  the pacing harness defines LINK_JUDGE by what its StreamServer has. Device:
  the link's line also stays away under the tour's card; `awayhome` is a TLS
  session at home. Verified (the plan's numbers): the builds on Xcode 27.1
  (the App Store replaced 27.0 mid-run), only the known warnings; all 39 pure
  checks (`policy` 360); the mutants of the 27 checks whose files the merge
  changed, 952, every one caught (`policy`'s five new); H2 against main's CLI;
  H7 and H8 over the TLS doors, 16 of 16; on a private simulator against
  `SillHost --synthetic --remote --pairing`, 28 of 28: S4 (moved over the TLS
  home door, one restart at the home quality), `refused`'s back-off, another
  key refused by the pin once, another launch once, S5, and S4race (the
  remote path cut mid-move: carried, the pick not sent); the pacing harness
  against main, every gate passing with main's figures and the link's
  verdicts; Sill.app's previews main's but for the away section and the new
  cards; photos of the panel and the stream's line, the phone's included.
- The merge's review (2026-10-08; the plan's "The merge's review"): seven
  findings, two the same, each verified here and fixed in a commit of its own.
  The move home chose by the Mac's listing: a look-alike replaying the Mac's
  public tag at another key, listed first, had its pin refused and the refusal
  held the Mac's own row back while any row of it stayed listed (52 s on a
  private simulator), and a row with the tag and no `p` listed first stopped
  the move. Now by row (`DiscoveryPolicy.moveHomeRow`, `HomeRows`, pure): not
  refused, at a door a pinned dial takes, the fewest tries first; a row's
  refusal and tries forgotten once it is no longer listed; `moveHome` lost
  `refusedListing`. The kind 18 floor is a pure rule (`HomeMoveInfo`), checked:
  the broadcast race among `policy`'s cases, and mutant K1 the rule before the
  fix. Docs: kind 16's `away` comes from a host with an identity (SillHost
  `--pairing` alone sends it, nobody ever away); the plan's §4.4, §7.3, §10,
  P13 and open question 10 say the move home goes only to a TLS home door (a
  plain one: no move, the session stays remote). The fence check's move home
  is TLS to TLS. site/privacy.html names the link report (the 0.4.1 drafts'
  line). Verified: the builds (only the known warnings); `run-all.sh`, all 39
  (`policy` 392); the mutants of `policy` (130), `remote-rules` (72),
  `home-device` (124), `home-model` (21), `fence` (32) and `away-wire` (9),
  388, every one caught; on a private simulator 29 of 29 by row (a look-alike
  refused at its pin, then the Mac's own row moving home 70 ms after it was
  listed; a plain row first, three launches; a row that never answers first,
  twice) and the merge's S4 to S4race again, 28 of 28; the kind 18 race staged
  live (the bare SillMenuBar binary broadcasting a kind 18 every 0.25 s, the
  home door 0.8 s away): this build moved home 2 of 2, the rule before the fix
  refused the Mac's own row 2 of 2; CI's "Build and check" passed on the
  fixes' head (ea4de23).
- **Untested, for Noah (the plan's P4–P13; P1–P3 and P14 are PR A's and
  still open):** with Sill.app built from this branch on the Mac and this
  build on the iPad mini, away on the iPhone 15 Pro's hotspot through
  Tailscale, then home:
  - P4, away starts on Low and Standard: at home set Pro · Retina in the Mac's
    menu, then leave for the hotspot. The session through Tailscale starts at
    Low · Standard: Sill.log "Away from home: every connected device is away;
    streaming at Low · Standard (4 Mbps per 60 fps, points). The home quality
    stays Pro · Retina.", the iPad's panel "Away: Low · Standard", and
    `defaults read me.saffer.sill.mac bitrate` still 40000000.
  - P5, the away choice: pick Balanced away: one restart at 15 Mbps,
    `awayBitrate` 15000000, the home bitrate unchanged; the next away session
    starts at Balanced.
  - P6, mixed: with the iPad away, connect the iPhone at home on Wi‑Fi: one
    restart, the iPad's header "Home quality: Pro · Retina (a device at home is
    connected)"; disconnect the iPhone: the away quality again, one restart.
  - P7, the Mac: Settings › Streaming shows both sections; the away pickers
    restart once while the iPad is away; the menu's Quality subtitle "Away
    from home now: …".
  - P8, the can't-keep-up message: away at Extreme on the hotspot, within
    about 5 s the panel's callout ("The link can’t carry Extreme. … is
    recommended.", its button "Use …"), the line over the stream ("The link
    can’t keep up with Extreme. Lower it in Settings."), one VoiceOver
    announcement, and the Mac's card "the link can’t carry Extreme"; the
    button: one restart, the callout and the line go. With the line up, pick
    another window and rotate: it stays, not spoken again; the button, then
    Done at once: no line, nothing spoken; how VoiceOver reads "Low ·
    Standard".
  - P9, a dip: cover the iPhone, or walk away from it, for 15 s: the line
    comes, then goes about 5 s after the link recovers; no reconnect.
  - P10, coming home: streaming away through Tailscale, join the home Wi‑Fi.
    Within about 5 s of the network listing the Mac the session moves back by
    itself over the Mac's TLS home door, pinned to its key: Sill.log "Client
    connected: …%en0" (never "Home door refused", no pairing asked), "Home
    quality again", then "Client left" for the Tailscale address; the route
    line gives way to "Wi‑Fi", one restart; drag and type through it (no button
    stays down, no letters swap); the Mac's card shows the iPad once. At the
    edge of the home Wi‑Fi, note how often it goes back and forth.
  - P11, coming home by the cable: an away session, then at home plug the
    cable in: the move goes to the cable ("Wired"; the Mac logs `%en14` or
    `%anri0`).
  - P12: Connect Remotely at home stays remote.
  - P13, mixed builds: PR #13's iPad against this Sill.app, away: Low ·
    Standard, its Quality Low, no header line. This iPad against Sill for Mac
    0.4.0 (main's: a TLS home door, no away quality): no header line, no
    callout, and the move home works, pinned; against 0.3.1 (a plain home
    door) the session stays remote.
  It merged (05f2bb8, 2026-10-08) and ships as Sill for Mac 0.5.1 with Sill for
  iPhone and iPad 0.5.1 (4), one version for both (the entry above; there is no
  Sill for Mac 0.4.1): the release drafts' lines held back for it (sill-handoff's
  `release-next/drafts/for-0.4.1.md`: the notes, What to Test, the site's support
  and index lines, the privacy page's date, the metadata) are on the release's
  branch, `release-0.5.1` (its privacy line was in since the merge's review).

**A Mac set up again: the old saved record retires itself (2026-09-28, branch `stale-duplicate-fix`
from main at 72d8d1d).** Noah: "When using Tailscale, it shows Noah's MacBook Pro and Noah's MacBook
Pro (2) and only 2 works." Sill for Mac 0.4.0's new key made the device pair again (#44), and the old
record stayed (#44's known gap): away from home both were Remote rows, the old one's pin refused.
Device only, no wire change:
- A remote dial of a saved Mac also takes, at one address, the key of another saved record that
  `RemoteDialPolicy.successors` names: the same name, not revoked or `newKey`, paired after the old
  one was last reached (`lastConnectedAt ?? pairedAt`), at an address that names one machine
  (Tailscale's shapes, an internet address or name; loopback in DEBUG only). A private, `.local` or
  other VPN's address never counts: another network's Mac can hold it (home and office). The key is
  taken in the verify block (`DeviceTLS.options(alsoAccept:)`, RemoteConnector's `successors` by
  candidate); once the handshake completes with it (TLS 1.3: the Mac holds that key), the old record
  is removed (`SavedMacs.superseding`: the newer takes its typed addresses, `homeTLS`, and the
  proving address as `lastWorked`) and the session goes on as the newer record. Never on the name
  alone; a record reached since the other was paired stays (two Macs in use).
- The Remote rows list one name's records together, newest first (`SavedMacs.remoteOrder`), so the
  one that works leads until the old one is tried.
- Checks: remote-rules 123 (16 new) and 72 of 72 mutants (20 new; CI's mutants matrix has it already).
- Verified on a private simulator ("Sill dupfix", deleted after) against loopback synthetic hosts
  (software encoder, `--pairing --remote=47455`, `SILL_TEST_REMOTE_DIR` per identity): paired with
  identity A, then B at the same address and port, both saved as on Noah's devices ("Noah's MacBook
  Pro (2)"); `-SillDialSaved 1` dials A as its Remote row does. Before (main's build): -9808 at
  127.0.0.1, both kept. After: "answered with the key of B …: A superseded", connected, one record,
  named without "(2)". Negatives: A and B at different ports, both running: A's dial reaches A, both
  kept; A reached after B was paired, then B at A's address: -9808, both kept. iOS Debug for the
  simulator and Release for a generic device (only the known `StreamClient` warning);
  `Tests/checks/run-all.sh` all passed.
- **Untested, for Noah:** on the iPad and iPhone with this build, away from home on Tailscale: tap
  the old "Noah's MacBook Pro" row: it connects (to the Mac's new key) and the "(2)" row is gone,
  the survivor named plainly. At home over the LAN alone the old row still says it is not the Mac
  paired with (a private address proves nothing); with Tailscale on at home it cleans up too.

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

**Sill for Mac 0.4.0 with Sill for iPhone and iPad 0.5 (2) (2026-09-27, branch `release-next` from
main at 643af6b, main merged in once PRs #37, #38, #42 and #43 were on it; #39, away from home, deferred to 0.4.1;
PR #41).** Noah: "Once all are
merged I want to try the latest build", then the go. The first release that needs both apps at
once: pairing at home (#37) made the home door TLS 1.3 with pairing, so a device from before it
cannot connect to 0.4.0 at home (a plain dial, a failed handshake, and a redial at once while the
Mac is listed, so a flicker that can come several times a second; the Mac's menu says "An iPhone
or iPad Needs Sill Updated"), and 0.5 (2), a Release build, dials no plain door
(Sill for Mac 0.3.1 and earlier: "Update Sill", nothing dialed). docs/release-checklist.md, "The
pairing release", has the order: the device build uploaded first, its What to Test as it shows,
one device on it against a Mac with the release's code once it is processed, the site staged, the
Mac release, the site pushed at once, and no external group or App Review before 0.4.0 is the
download.
- Versions: Sill for Mac 0.4.0 (the build number the commit count at the tag), Sill for iPhone and
  iPad 0.5 (2) (0.5 was never submitted, so it stays the App Store's first version; App Store
  Connect takes each build number once per version), both in the release's pull request, so the
  annotated tag v0.4.0 names the commit both came from.
- Docs (true on main at 643af6b, committed before the merges): the checklist brought up to date (the
  record "Sill – Mac Streaming", Apple ID 6816359860; 0.5 (1) from b37f47a; the dmg page move and the
  first release done; notes over `--publish`'s one-line body; the check of what was published; What
  to Test per build; one device trying a device build before the Mac release it goes with; the
  site republished right after the release it describes, and hosted by GitHub itself since
  2026-09-27, Cloudflare's proxy off), the App Store
  metadata with the tour, the menus and the Mac's pointer, the privacy policy with the menus and the
  pointer. At release time, what waited for #37, #38, #42 and #43: the privacy policy (pairing records,
  the device key, TLS everywhere, Require pairing), support's Pairing, the home, download and Remote
  Access paragraphs, the README's How it works and Good to know, the metadata's pairing (the review
  notes' CONNECT AND PAIR, 3,948 bytes of 4,000), every device pairing once more after the Mac
  updates (#42: a new key in the data-protection keychain, no migration), the Spotlight fix (#43), the checklist's "The pairing release". A review of
  the drafts against the code (2026-09-27) corrected them before they went in: a device paired at
  home learns the Mac's addresses for afar only in a session at home with Remote Access on (the
  review notes, shot 11, support, index, the README and the notes say so; until then its Remote
  row says only "didn’t answer"); with Require pairing off a device takes any Mac key, so the key
  check is between paired ends; the Mac sends its addresses only with Remote Access on; the cable's
  code keeps a second key of one device from pairing by itself; the log names the gestures; no
  gesture claim for macOS 14 or 15 (never tried there); the liveness fix is the device's.
- Rehearsed on main at 643af6b (2026-09-27): `release.sh --dry-run` 54 s (0.3.1 (391), the zip and
  the image 3.0 MB each, spctl "Unnotarized Developer ID"), `release-ios.sh` 46 s (0.5 (1), Sill.ipa
  2.5 MB, Apple Distribution, the App Store profile, both required-reason APIs declared).
- **Untested, for Noah:** the published pair on his devices (TestFlight's 0.5 (2) first, then Sill
  for Mac 0.4.0 from the download on another Mac or user account: the iPad paired for Remote Access
  pairs once more, as the iPhone does, with the code or over the cable), and the open
  device tests of #31, #35, #36, #37, #38, #42 and #43 that the App Store's claims wait for.

**The stuck command after Spotlight (2026-09-27, branch `spotlight-modifier-fix`
from main at 643af6b, with main at da43f6b (PR #38) merged in; not pushed).**
Noah: "The stuck command after Spotlight", found by PR #38's review. The
Spotlight key sent ⌘Space as one key down and up, each carrying command, and
the host posted both as they came; every keyboard event posted leaves its flags
in the HID state table its source reads (CGEventSource.h), and pointer and
scroll events start from them, so the next tap was a ⌘-click until something
was typed. The key row, a latched ⌘, ⌃ or ⌥ on the software keyboard and a
hardware keyboard's ⌘ did the same. Inferred, not observed: nothing may be
posted while this is built.
- Host (`KeyStrokes`, pure): a key's down carries its device's modifiers and
  what the modifier keys down hold, its up only what they hold; a modifier's
  own key is a flags-changed event with what is held; a key or text that no
  longer says a modifier lets go of that key first; a device that leaves, and
  the host at its end (Sill.app's Quit, a Ctrl-C, kill or hangup; the CLI
  without --virtual-display then dies of the signal as before,
  `HostShutdown.installKeyRelease`), let go of every key and button. Input
  with nowhere to land (nothing streams, or a switch drops held input) is
  dropped but for the up of a key or a button the Mac has down
  (`DroppedInput`), a button's where the pointer is.
- The tripwire (`KeyUpCheck`, pure): a quarter of a second after every key's
  up whose down put a modifier in the table (a modifier key's own, a
  shortcut's key, the ups KeyStrokes makes), the table is read again; a
  modifier the up should have taken out and the table still holds, that no
  key down holds and no key since carried, is counted, `in.keyModifiersLeft`,
  and said once with the key ("Keys: a quarter of a second after a device's
  key 55 came up, …"). TEST ONLY `SILL_TEST_INPUT_LOG=1` (Build and run)
  prints what a `--synthetic` host would post and each check it arms.
- Device (`KeyChords`, pure): a shortcut goes out as a keyboard sends it, its
  modifiers' own keys around it (`KeyChord.press`: the Spotlight key, the key
  row, a latched ⌘S), so Sill.app 0.3.x is left nothing held either; a
  hardware key's up follows its down (`ForwardedKeys`), a cancelled press
  comes up, and the overlay lets go of its keys when it stops taking them.
- `Tests/checks/key-strokes` (329 checks, 72 mutants; CI and its mutants
  matrix): every path's exact events on this Mac and on one from before, the
  tripwire armed for each path and reporting on Macs that keep their table
  through a modifier key's up or another key's, input with nowhere to land,
  and random sessions of two older devices (3,000, and 1,000 on each such Mac)
  and of this device (2,000, and 500 each). Against main's rules, 205 of the
  279 checks before the review failed.
- Review (2026-09-27; each reproduced first, then fixed in a commit of its
  own): the tripwire was armed for none of this device's paths; the CLI's
  default path died of a signal with a device's modifier down; the drag guard
  this branch had added to `TrackpadSurface.didMoveToWindow` never ran (UIKit
  cancels the long press first, and its end lets the button and the modifiers
  up and spends the latch: a rig on a private simulator) and is gone; and,
  older than the branch, a button's up with nowhere to land was dropped,
  leaving the Mac's button down and every later move a drag.
- Verified: `swift build -c release`; iOS Debug for the simulator (CI's
  command), only the StreamClient warning; `run-all.sh`, all 27; the dry run on
  a synthetic host against 84ddd9c's (this device's Spotlight key arms a check
  for command at key 55's up; a drag whose stream stops ends "left mouse up
  (none) at 454,285" and the moves after are moves, where 84ddd9c's are
  drags); SIGINT, SIGTERM and SIGHUP with ⌘ and the button held let go of both
  and end with 84ddd9c's wait status; the app's `-SillInputTest` against that host, a
  rotation rig and the touch rig (72 of 72 against main's) on a private
  simulator, deleted after.
- **Untested, for Noah:** with this Sill.app and this iPad build, the Spotlight
  key and then a tap on a file in Finder selects it (not a ⌘-click), and the
  same after the key row's ⌘esc, a latched ⌘S and a hardware ⌘C; a latched
  ⌘-click stays a ⌘-click and the next tap is plain; ⌘ held while Wi-Fi drops,
  and Quit Sill.app while holding it: plain clicks after; a drag held on the
  trackpad while the window is closed on the Mac (⌘W there), let go, then
  another window picked: the pointer moves there, nothing drags. Sill.log
  should have no "Keys: … came up, this Mac's modifier keys still read" line;
  if it has, note the key (55 is ⌘). With this iPad build against Sill.app
  0.3.1, the Spotlight key then a tap is a plain click.

**Keychain hardening (2026-09-27, branch `keychain-hardening` from
`home-pairing` (PR #37, not yet merged), PR #42 (a draft); the assessment, the
decision, what was implemented and its proof with the real profile are in
`docs/keychain-plan.md`).** Noah's pre-1.0 question: move Sill.app's
remote-access identity (the Mac's key, recognition key, trust list and Require
pairing) from the legacy login keychain, which does not authenticate who made
an item (a process running before Sill's first launch can pre-create every item
and Sill adopts it — the home-pairing security review), to the data-protection
keychain, which no other process can pre-create or read. Reproduced the risk
and settled the cost with test items of own names in throwaway keychains only
(never the login keychain, never Sill's real items): the legacy keychain's
creator and ACL are attacker-set, so Sill's verbatim lookups adopt a planted
key (and a planted key signs a verifying require-pairing-off record); and the
data-protection path needs a `keychain-access-groups` entitlement — a Developer
ID binary that carries it without a provisioning profile is AMFI-killed at
launch (exit 137, codesign still valid), while an ad-hoc build without it gets
`-34018`. So the strong keychain is profile-or-the-app-won't-launch, and only
Sill.app is affected (the CLI is memory, iOS is already data-protection).
- Implemented (the recommended path): `IdentityStorePlan` (pure,
  `Tests/checks/keychain`, 13 cases, 7 mutants, in CI's matrix) chooses the
  store from four launch facts — an entitled real Sill.app uses the
  data-protection keychain and **never** the legacy one beside it (so no
  planted legacy item is adopted), an unentitled real Sill.app uses the login
  keychain (the safe, profile-free fallback), a test host uses memory or the
  test directory. `AppModel.entitledKeychainAccessGroup()` reads the running
  binary's own `keychain-access-groups` (`SecTaskCopyValueForEntitlement`);
  measured nil for every ad-hoc/dev build, so only a profile-embedded Developer
  ID build takes the strong path. `KeychainIdentityStore(accessGroup:)` is
  parameterised — nil is the legacy keychain byte-for-byte, a group adds
  `kSecUseDataProtectionKeychain` + the access group to every query.
  `Packaging/SillRelease.entitlements` and `make-app.sh --release`: with a
  profile at `Packaging/embedded.provisionprofile` (gitignored) it verifies the
  profile authorises the access group and is not expired (refusing either, which
  would AMFI-kill or fail to launch the app), embeds it and signs with the
  entitlements; without one it signs as before (login keychain) and says so;
  every build's last line names the identity keychain. `release.sh`'s
  `check_signature` confirms the state. The CLI and the bare binary are
  unchanged.
- **Review (2026-09-27, `docs/keychain-plan.md` §9a), four findings verified
  and fixed:** (1) **Auto-migration reopened the pre-creation hole — removed.**
  The first draft adopted the login keychain's items on the first entitled
  launch (to keep the Mac ID and pairings), but the login keychain cannot
  authenticate a maker, so the adoption code (no maker check, no gate) would
  have promoted a *planted* key into the strong keychain as the Mac's identity
  — the very attack this closes, only relocated. There is no sound legacy-side
  gate, so migration is dropped: the store now never reads the login keychain,
  and Noah's own dev Macs (the only Macs with legacy items before the first
  public build) do a documented one-time reset (a fresh key, a new Mac ID,
  re-pair). This also resolves the draft's leaving the exportable legacy key in
  the weak keychain. (2) **The identity key set no accessibility — fixed:** the
  data-protection default is `WhenUnlocked`, so remote access would have failed
  while the Mac was locked and its owner away; every item is now
  `AfterFirstUnlockThisDeviceOnly` (readable after first unlock, never off this
  Mac). (3) **The release path could not build the hardened app at all —
  fixed:** `SillRelease.entitlements` carried an XML comment, which codesign's
  AMFI parser rejects for a restricted-entitlement file, so `--release` with a
  valid profile failed at signing (the draft's rehearsal had no valid profile
  to reach that step); the comment is removed (its rationale moved into
  make-app.sh; `SillDebug.entitlements` keeps its comment — get-task-allow alone
  does not trip AMFI's parser, verified). (4) **make-app.sh did not check the
  profile's expiry — fixed:** Gatekeeper checks a Developer ID profile at every
  launch, so an expired embedded profile stops the app launching; make-app.sh
  now refuses an expired profile (and warns within 30 days) before signing.
- Verified before the profile existed (no notarization, no device; every keychain touch
  used throwaway keychains and test service names, never the login keychain or
  Sill's real items): `swift build` clean; `Tests/checks/run-all.sh` all 28
  pass, keychain's 7 mutants caught. The four `make-app.sh` paths, driven with
  throwaway CMS profiles and a real Developer ID signature into `.build` (the
  bundle deleted after, never installed or launched): default (Apple
  Development) → login-keychain note; profile-less `--release` → login-keychain
  fallback, no keychain groups, `codesign --verify --strict` clean; a valid
  (future-dated, right app-id) profile → the app builds, embeds the profile,
  carries the three entitlements, verifies strict, prints the data-protection
  note; a garbage, wrong-app-id, or expired profile refused (exit 1) before any
  AMFI-killable app is written. Confirmed with a throwaway-signed test binary
  that the entitlements comment broke codesign and that stripping it signs and
  reads the entitlements back.
- **Proved with the real profile (2026-09-27, `docs/keychain-plan.md` §9b).**
  Noah registered the App ID `me.saffer.sill.mac` and made the Developer ID
  profile "Sill Developer ID" (UUID 18e9509f-5498-4533-ba59-293461a61a0d,
  macOS, team 9B2KKVM937, `keychain-access-groups` `9B2KKVM937.*`, only the
  Developer ID certificate 42424F38…, until 2044-09-22), at
  `Packaging/embedded.provisionprofile` (git-ignored; copies in
  ~/Library/Developer/Xcode/UserData/Provisioning Profiles/ and ~/Downloads).
  Two findings with it, either of which stopped the hardened release, fixed: the
  draft keyed the application identifier as iOS's `application-identifier`, so
  make-app.sh refused the real profile (a Mac profile says
  `com.apple.application-identifier`) and, worse, `SillRelease.entitlements`
  with that key had the app killed at every launch (a probe signed so: exit
  137, taskgated "Unsatisfied entitlements: application-identifier", AMFI "No
  matching profile found"). Now the entitlements use
  `com.apple.application-identifier`; make-app.sh checks what taskgated checks
  (every entitlement the file holds granted by the profile, the group by name or
  `TEAM.*`, the signing certificate among the profile's — an Apple
  Development-signed probe with this profile was killed too — and not expired)
  and embeds the profile's bytes alone (`cat`); `check_signature` requires
  `com.apple.application-identifier`.
  Proven: `make-app.sh --release` prints the data-protection line, embeds the
  profile byte for byte, carries exactly the three entitlements, the hardened
  runtime and a timestamp, and verifies `--deep --strict`; `release.sh
  --dry-run` exit 0 (check_signature, the zip, the signed image); the built
  app's executable run only with `-SillRenderPreviews` exits 0 with 124
  previews, taskgated "allowing entitlement(s) … due to provisioning profile",
  no AMFI denial and no keychain call (then unregistered from LaunchServices and
  removed); a probe app (bundle ID `me.saffer.sill.mac`, the same profile and
  entitlements, Developer ID, hardened) reads its group, makes a generic
  password and a P-256 key exactly as `KeychainIdentityStore` does (the group,
  `pdmn` `cku`, `sync` 0), a scratch copy of `KeychainIdentityStore` with only
  its three name constants changed makes all four items, and a rebuilt probe
  finds the same key (a rebuild keeps the Mac ID); the same probe ad hoc, or
  Developer ID without entitlements, gets -34018 and can plant nothing; every
  test item deleted and confirmed gone, nothing of Sill's own touched, no
  prompt. Refusals checked with throwaway profiles (the iOS key, another app
  ID, team, group or certificate, none, a malformed one, expired, garbage) and
  the draft's entitlements against the real profile; the development build and
  the profile-free release as before; `Tests/checks/run-all.sh` all 28.
  Also corrected: "two teams" (both certificates are team 9B2KKVM937;
  HG877AGTQ7 is the Apple Development certificate's member ID).
- **The adversarial pass (2026-09-27, §9b's last part):** all of the above
  re-run from the commit, and more. The probe with the release's entitlements
  and no embedded profile is killed at launch though the profile sits in
  Xcode's folder here (the launch rests on the embedded copy). A new probe built
  from the branch's own store, plan and entitlement reader, with user
  interaction disallowed: as the release, its four items land in the group
  (`cku`, `sync` 0) and a query pinned to the login keychain and `security
  find-generic-password` find none (a control item there is found); ad hoc,
  Developer ID without entitlements and the development build's shape are
  refused (-34018) reading, adding, updating and deleting in the group; the
  development shape's store writes the login keychain, and with those
  same-named items there the release-shaped store loads its own (no adoption);
  the group held no item of any class before and after, and no test name is in
  either keychain. Two fixes: make-app.sh checked only the entitlements it knew
  (an added `com.apple.developer.icloud-services` was signed in, and a probe so
  signed was killed at launch; now every key is checked), and `cp -X`'s copy of
  the quarantined download kept the quarantine flag, which ditto carries into
  the zip and the image (now `cat`, none). Rechecked after: the build, `release.sh
  --dry-run` (13 s, "Unnotarized Developer ID"), the launch, and the refusals
  (the proof's eleven profiles as before, plus the extra entitlement, the iOS
  key, get-task-allow, an empty list, a dictionary, another team and its group).
- **For Noah (still device work, `docs/keychain-plan.md` §10,
  release-checklist.md Part 1 §5):** remote access with the Mac locked and you
  away (the items are `AfterFirstUnlockThisDeviceOnly`, proved `cku`, but never
  read while locked here); the first hardened launch on a Mac that ran a
  legacy-store build makes a fresh Mac ID (re-pair once; the one-time reset is
  in the checklist), then the same Mac ID across relaunches and rebuilds; a
  notarized download on a second Mac (notarization with the profile embedded,
  the first launch from quarantine, Remote Access making the identity). Also:
  by 2027-02-01 a new Developer ID certificate and the profile made again with
  it (make-app.sh refuses a profile that doesn't list the signing certificate);
  releases from GitHub Actions have no profile (git-ignored), so they ship on
  the login keychain until the release workflow gets one (a secret, or the file
  committed: it holds no secret). Land it with home pairing, before the first
  public build (off the wire, so not a floor blocker). The base is
  `home-pairing` until #37 merges; then merge main in.

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

**Three-finger trackpad gestures (2026-09-27, branch `trackpad-gestures` from
main at 8b0d418, with main merged in at 5c6a850 (6678ca3), at 2b38179, PR #31
the Mac's pointer among it (5e6ddaa), and at 643af6b, PRs #35 the tour, #36
the Mac's menus and #34 remote pacing, never rebased, PR #38; the plan, its
§12 defaults, the results, the review's fixes and the last merge are in
`docs/trackpad-gestures-plan.md`, §15).** Noah: "I also want to be able to use
full macos gestures on the touchpad, so far only 1 or 2 finger gestures are
working" (2026-09-23), and "Work on 5-12 as well please" (2026-09-26). Built
and reviewed overnight while he slept, every default of the plan's §12 taken.
Tier 2 (tracking gestures through private IOHID events) is not built and
§10's probe was not run: nothing was posted to the Mac.
- Wire: kind 28 `gesture`, device → host, JSON `TrackpadGesture`
  (`Gesture.swift`): a name (`swipeUp`, `swipeDown`, `swipeLeft`, `swipeRight`,
  `pinch`, `spread`) and `fingers` (3 or 4). `WindowList.gestures` 1 says a
  host takes them; nil from every host before, which is sent none.
- Mac: `GestureChords` (pure) turns a name into the Mac's own shortcut for
  its action, read from its Keyboard Shortcuts at that moment
  (`SymbolicHotKeys`, SkyLight's two getters, read-only): the first of the
  action's that is on and bound, with its stored modifiers' device-independent
  bits (fn included). Mission Control 108 (the Mission Control key, 160) then
  32 (⌃↑); App Exposé 115 then 33; the Spaces 81 and 79 (⌃→, ⌃←); Apps 173
  (the Launchpad key, 131) then 160 (Show Apps); Show Desktop 36 (F11) then
  110. None on: nothing, never another action's. It remembers the view its
  last gesture opened: the opposite gesture closes it with the same shortcut,
  the same gesture again does nothing and, made once more straight after,
  opens it again (it was closed on the Mac itself), the Spaces leave it open.
  A device's click, key or text forgets it (`input`; a move, a scroll or a
  button or key coming up does not), and so do a window picked, an app
  launched, a window's button and the last device leaving (`forget`). The
  coordinator takes four a second per connection (the rest one line a
  minute), waits for a switch in flight (at most 2 s: a gesture over a window
  comes right after the device's Desktop pick), queues the chord behind input
  held for an activation, raises nothing, and logs one line: "Gesture from
  iPad (iPad14,1): swipe up → Mission Control (shortcut 108: key 160, fn)".
  `InputInjector.chord` posts the key down with the shortcut's flags and the
  key up with the flags the HID state table held before, so no control or fn
  is left for the next click or scroll to start from; a quarter of a second
  later a read of the table counts `in.gestureModifiersLeft` and says once
  "Gestures: after a gesture's shortcut this Mac's modifier keys still read …"
  if they are. A host that does not advertise posts none: "(not posted: a
  test host)" and `in.gestureDry`; TEST ONLY `SILL_TEST_HOTKEYS` gives it a
  table of its own.
- Device: `TrackpadGestures` (pure). A stroke goes silent once three fingers
  are down before any finger moved 24 pt, with no button held, however slowly
  they came and whatever rests on the glass, until the next stroke's first
  touch; it arms when the three that landed last came down within 0.15 s of
  each other (so a resting thumb is not one of them). The first lift of one
  of the three decides: a swipe at 40 pt, or 20 pt at 500 pt/s over the last
  50 ms, with one axis 1.3 times the other and the fingers moving together
  (each of the three half the centroid's travel or more, no other finger that
  moved half of it the other way: a pinch led by the thumb is no swipe); else
  a pinch or spread at 25 %, of the three and any other finger that moved;
  else nothing. Another finger's lift only leaves the stroke; `fingers`
  counts the three and the others that moved (4 at most); a fifth finger, or
  a cancel (iPadOS taking four fingers), decides nothing. `StrokeObserver`
  (InputOverlay.swift) feeds it every direct touch on both surfaces, and each
  existing finger handler's only change is a first line, `guard
  !strokes.silent`; a scroll the stroke had begun is closed as it goes silent,
  with no coast. `StreamClient.sendGesture` sends it (the switch on, the Mac's
  `gestures` 1; the Desktop first while a window streams; a light tick on an
  iPhone's trackpad). The stream's overlay turns off iPadOS's three-finger
  editing gestures. Settings' This iPad (or iPhone) group, after the Mac's and
  before Take the Tour since the merge: Three-Finger Gestures
  (`Sill.trackpadGestures`, on by default, never sent), the five
  mappings while the Mac takes them, and a footnote; with VoiceOver on (which
  keeps three fingers) the footnote says the rows do the gestures, and each row
  is an accessibility action doing its gesture (the Spaces row one each way).
- Verified (§15): gestures 156 checks and 45 of 45 mutants; gesture-chords 141
  and 33 of 33; compatibility 92 and 19 of 19; `Tests/checks/run-all.sh`, all
  22; swift build -c release and the three iOS builds with only the known
  warnings; the CLI idle and with a Desktop client against main's, masked and
  sorted: identical; the app's 100 previews against main's: identical but the
  General pane's "Running from" path; the merge commit's StreamProtocol reads
  kind 28 as unknown and the new list; the touch rig on an iPad's and an
  iPhone's simulator (one- and two-finger strokes unchanged, also right after
  a gesture; every stroke of three to five fingers, placed slowly, beside a
  resting thumb, led by the thumb or with a brief extra contact, one gesture
  or nothing; the review's HEAD fails 18 of those checks); dry runs on
  loopback synthetic hosts (every gesture, the reversal, a scroll before the
  reverse gesture, a second session, the third try, fallbacks, bad payloads,
  the rate cap); the app in a private simulator against such a host; photos
  of the group at the Duo's, an iPad mini's and an iPhone's sizes, at Large
  and accessibility-extra-large, and of its VoiceOver footnote.
- Merged with main at 643af6b (2026-09-27, one merge commit; the plan's §15,
  "Merged with main after PRs #34, #35 and #36"). Where the features meet:
  kinds 24, 25 and 27 (the menus), 26 (the pointer) and 28 (the gesture) side
  by side, and the compatibility floor below keeps 0–28; the coordinator
  dispatches both (kind 8 feeds `GestureChords.input`, then the menus'
  `desktopInputMayActivate`; kind 28 its four a second; 25 and 27 the mirror
  and its rates), and a menu item chosen from a device (kind 25) now forgets
  the view a gesture opened, as a click does; the Settings panel ends with This
  iPad's gestures, then Take the Tour (whose row no longer pads itself while
  the Mac's settings load); the portrait trackpad keeps `sendGesture` and the
  tour's target; sillclient.py both sides' flags; the checks that read 28 as
  unknown (`protocol`, `menus`, `pointer-control`) or 27 as free
  (`compatibility`) now read the gesture and the fetch, and four mutants that
  renumbered a kind onto one now taken (so they no longer compiled) use free
  numbers; CI's mutants matrix lists all 25. Remote pacing (#34: the host's
  send side, the device's MessageReader, A020/F020) met the gestures only in
  the documents, CI's matrix and the checks' README. Verified: `swift build -c
  release` from clean, only the CaptureProbe warning; iOS Debug and Release
  for the simulator and Debug for a generic device, unsigned, only the old
  `StreamClient` capture warning; `Tests/checks/run-all.sh`, all 26; the
  mutants of the 15 checks that compile a file the merge changed, every one
  caught; on a loopback synthetic host on the software encoder, nothing
  posted: sillclient's menus subscription and choice beside the gestures (a
  swipe up, a kind 25, a swipe down gives App Exposé, not "closes Mission
  Control"), and the app in a private simulator (deleted after) sending four
  gestures through `sendGesture` beside its menus subscription; photos of the
  panel's end at 1000×710, an older Mac's, the phone's and the tour's laptop
  step lighting the keys and the trackpad.
- Noah tried PR #38 on his devices (2026-09-27): "The gestures work amazing.
  Please merge that code." The P1–P13 list below was not reported item by item.
- **Left:** the republish of `site/privacy.html` (it names gestures now) after
  the merge; the §10 probe before any Tier 2.
- **Untested, for Noah (the plan's P1–P13, beyond "the gestures work"):** new
  with the merge, a swipe up, then an item chosen from the Menus button, then
  a swipe down: App Exposé (with no choice in between, the swipe down closes
  Mission Control). On the iPad and iPhone with this Sill.app: each gesture
  in portrait and landscape, with the Desktop and while a window streams (the
  Desktop first); which shortcut works (P2: that key 160 opens Mission
  Control and 131 Apps when posted, that ⌃→ switches Spaces
  rather than tiling the front window, and no "modifier keys still read"
  line: right after a swipe left, right or down a tap selects with no
  context menu and a two-finger scroll scrolls); no stray click, drag or
  pointer jump with three fingers, placed slowly or beside a resting thumb,
  and one- and two-finger strokes as before; a pinch led by the thumb is a
  pinch; the reversal pairs, after a scroll too, and Mission Control closed
  with the Mac's Esc coming back at the second swipe up; with the keyboard
  up, no iPadOS undo or paste; the virtual display; the switch and a
  relaunch; the Magic Keyboard trackpad (unchanged); remote; four fingers with
  iPadOS's gestures on and off; this iPad against main's Sill.app (the update
  note, nothing sent); VoiceOver (the footnote, the rows as actions).

**Remote pacing (2026-09-27, branch `remote-pacing` from main at 150f781, with
main at cf05a78, 676b362 and 2b38179 merged in, PR #34; PR A of
docs/remote-bundle-plan.md, whose "Results: PR A" has every number).** Item 1
of the away-from-home bundle Noah decided on 2026-09-25 ("a proven keyframe
livelock"), its own PR ahead of items 2–4 (the away quality, the link report,
the move home: PR B, the entry above).
- The livelock (Sill.log 2026-09-25 14:13–14:36, the iPad on the iPhone's
  hotspot through Tailscale at Extreme, then Pro · Retina): `paceRemote`
  dropped any frame while more than two messages were unacknowledged, so a
  keyframe the hotspot took in about half a second counted against the deltas
  right behind it. One or two went out, the next was dropped, and every later
  delta waited for a keyframe asked for 2 s later, which blocked its own
  followers the same way: 1.5–1.9 fps with the link idle in between.
- Host (StreamServer.swift, remote clients only): what a remote client has
  queued is counted in bytes its connection has not taken (`pendingBytes`,
  every message but ticks). Behind the keyframes still being taken
  (`keyframesInFlight`: a restart's first keyframe can follow another), frames
  go out until more than `remoteHoldCap` (512 KB) waits beyond them; otherwise
  a frame is dropped only when the backlog is over both `remoteBacklogBudget`
  (256 KB) and what the last keyframe left behind it plus `remoteBacklogSlack`
  (128 KB). A client that lost a frame asks for a keyframe only once at most
  `remoteIdleBytes` (16 KB) waits, so the keyframe leads the queue: when a
  later frame comes, or at the remote sweep once the window has gone still.
  The spacing (2 s alone, 4 s beside a home client) is unchanged, and the
  keyframe it waits for goes out once the backlog fits the budget (the first
  one at once). The home branch of `broadcast`, eviction, the wire and every
  print are unchanged; no Stats key.
- Device (`MessageReader`, new; Layout): each header, then the payload in pieces
  of at most 256 KB, every piece stamping `lastReceivedAt`, so liveness is "no
  byte for max(6 s, 4 × the worst rtt)" as remote-access-plan §7.6 says (it
  was "no complete message", and a 1.6 MB keyframe on 2 Mbit/s ended a live
  session every ~10 s). The caps and the "closing: the host announced …" and
  "read error" lines as before; an end that comes with a message's last bytes
  is a clean end (the old reader then printed ENODATA as a read error),
  reported only while the connection is still read; the move's probe keeps its
  own reads. `Tests/checks/message-reader` (46 checks, 17 mutants; CI runs
  both).
- `Scripts/pacing/` (Layout, Build and run): the plan's encoder-free harness,
  base against new: the real StreamServer.swift fed fake frames, a shaped path
  (bottleneck.py, or Scripts/sillrelay.py for the remote door's slow link), a
  device stand-in and a table with each case's gate, all on 127.0.0.1. Not a
  pure check: it runs for minutes and waits while the Mac is busy.
- Verified before the merge, on it and after the review (the plan's Results
  has the tables): the harness against origin/main, every gate passing each
  time. After the review (a933a4f against 676b362): the livelock on main's
  pacing and gone on this one (kf25m32, 2.5 MB keyframes on 32 Mbit/s:
  1.3–1.5 fps against 58.2–60.1, three runs each; real24, the hotspot's loop
  at Retina size: 45.1–53.9 fps with 2.9–5.9 drops a minute against 59.3 and
  none, where the merge's base ran at 7.7–31.3; bigkf8 18.2–24.5 against
  59.8–59.9), ext120 at 120.0 fps with nothing dropped (main 5.7 drops a
  minute), the review's restartkf (1.6 against 60.1 fps) and stillend (the
  last frame shown in 0 against 3 of 3 still spells), the remote door's slow
  link (sillrelay.py at 2 Mbit/s and +150 ms for 90 s: no loss, eviction or
  frameless second; a blackhole dropped 13.1 s after connecting on both
  builds), slowkfB's liveness by bytes (64.8 fps, no loss, where the old rule
  lost slowkf 5 times on either host), and home, low, switch and fastbig no
  worse; S2 on a private iPad mini simulator against the harness's host
  through 2 Mbit/s: main's app lost the session 7.2–7.3 s after connecting
  ("connection silent for 6 s") while 1.8 MB came through, this branch's
  never (60 s before the review, 57 s after: 59–60 fps at a 40–46 ms frame age
  once the 1.7 MB keyframe had crossed); clean builds (the Swift package, and
  the iOS app for the simulator, Debug and Release: only the known warnings);
  every pure check (16, and 17 once main brought `dmg-layout`); the reader's
  17 mutants. On the merge with main at 2b38179 (dc471fa), again: the builds,
  all 21 pure checks, the harness's gate cases and home (every gate passing)
  and S2 (no loss in 60 s).
- Review fixes (2026-09-27; the plan's "Review": an adversarial pass over the
  pacing's arithmetic and edge cases, starvation and bufferbloat, home
  sessions and the reader). Two faults, each with a harness case that fails on
  the build before its fix:
  - A stream restarted while a keyframe was still being taken (a pick, a
    rotation, a settings change) forgot that keyframe, whose bytes then
    counted against the new stream's first deltas: on a slow link the first
    was dropped and the device kept the new keyframe's picture until a third.
    `keyframesInFlight` keeps every keyframe still being taken, and the hold
    cap counts what waits beyond all of them. restartkf (2.5 MB keyframes, 4
    KB deltas, 32 Mbit/s, three restarts 0.1 s after a keyframe): a drop at 9
    of 9 restarts before, none now (60.0–60.1 fps).
  - A remote device that lost a frame asked for its keyframe only when a
    later frame came, so one whose window went still right after the drop
    (the end of a scroll, the last letters typed) kept the picture from before
    the drop until the window next changed. Main has the same rule; a home
    device asks at the drop. The remote sweep asks too, once a second on the
    same terms, and the encoder encodes the still window's last frame again.
    stillend (frames bigger than a 16 Mbit/s link, the window still for 8 s
    three times): the older picture through 9 of 9 spells before, the last
    frame within 2.2 s of each spell's start now, 9 of 9.
  - Left as they are, with the reasons in the plan: the byte counts, the
    floor and what a client can queue, starvation, the home path (nothing
    changed outside `paceRemote`, an `if remote` or the remote sweep) and the
    reader. bottleneck.py's comment on its 64 KB receive buffer was wrong
    (macOS keeps loopback buffers at 340–590 KB whatever SO_RCVBUF says) and
    now says so; the relay is unchanged.
- H2 and H4 (the plan's Results): until main brought `SILL_TEST_LOOPBACK` and
  `SILL_TEST_SOFTWARE_ENCODER` (PR #31) no synthetic host could run here (its
  doors listened on every interface, its stream shared the hardware encoder
  with Sill.app), so H4 ran in the harness. H2 ran on the merge with both
  hooks: main's CLI against this branch's, idle 35 s and with a test client,
  identical masked and sorted. PR B's gates can use the same two hooks.
- The pull request's first CI run failed the reader check's slow case on
  GitHub's runner (its stand-in paced each write off a timer that fired late
  there); its writers now keep to the clock (4ca5124).
- **Untested, for Noah:** the plan's P1 (on the hotspot through Tailscale, Pro
  and then Extreme · Retina on a busy window, two minutes each: Sill.log has no
  "net.dropped 1 net.sent 3 net.waitKey 5x" every 2 s, and the `client iPad`
  lines stay near what the hotspot carries), P2 (Network Link Conditioner on
  the iPad at 1 Mbit/s and 100 ms, Connect Remotely at Pro · Retina: slow
  frames, never "connection silent for 6 s"), P3 (home Wi‑Fi at Extreme:
  `net.dropped` and frame age as before) and P14 (Extreme · Retina through the
  remote door on Tailscale's LAN path: no `net.dropped`, 60 fps; from a 120 Hz
  device by address, 120). From the review, on the hotspot too: a scroll that
  stops settles on where it stopped within a few seconds, never on a picture
  from mid-scroll; a pick or a rotation while it scrolls keeps moving from the
  new stream's first picture, with no second-long freeze.

**The Mac's menus on the device (2026-09-26/27, branch `menu-bar-mirror` from
main at 150f781, main merged in at cf05a78, 676b362, ed7f8c6 (PRs #30–#32) and
2b38179 (#33), never rebased, PR #36; the plan, its critique, the review and
every result are in `docs/menu-bar-plan.md`, "Results").** Noah: "For apps used
in Window mode, how can we access the menu bar options? Is there a way we can
add that menu and submenu?" (2026-09-25), item 10 of "Work on 5-12 as well
please" (2026-09-26). The streamed app's menu bar (the Desktop's: the frontmost
app's, as the Mac's own bar shows) reaches the device: on an iPad with
iPadOS 26 in the iPad's own menu bar, and behind a Menus button in the bar.
Each menu is read from the Mac when it opens, and an item chosen there is
pressed on the Mac through Accessibility. The Mac's shortcuts show as text,
never as key commands (⌘S typed still reaches the Mac as a key). Never the
Apple menu, never Sill's own. Built, reviewed (eleven findings, all fixed) and
checked; PR #36 merged (59c4ec8), and Noah's device tests below are still open.
- Wire (additive; `MacMenu.swift`; the compatibility floor below): kind 24
  `macMenu` (host → device: a top level, or the answer to one request), 25
  `pressMenuItem`, 27 `fetchMenu` (one menu's items; without an id, the
  subscription to the top level), around the pointer's 26. An id is a path
  ("2.9": Accessibility's child indexes below the bar, separators counted) that
  names one item for every device within one tree version; the version is the
  host's, +1 when the app, its top level or a submenu at its place changes, and
  when the last subscriber leaves. A fetch and a choice carry the title the
  device showed, and the host acts only while the item there still has it. A
  device's tokens come back in `answering`. Only a connection that sent the
  subscription is served (older devices and test clients cost the Mac
  nothing); an older host skips 25 and 27, and no button shows.
- Host (`MenuFormat`, `MenuPolicy`, `MenuReader`, `MenuMirror`,
  `MenuSelfTest`; Layout): Accessibility on its own queue (`sill.menus`), a 1 s
  timeout on each element, 1.5 s and 500 items a menu; one request at a time,
  and one that could no longer be answered in time for its device (its wait,
  from the connection's round trip) is not read, a choice that late refused; a
  menu read less than a second ago answered from that read (AppKit validates a
  menu at most once a second); the top level read at a pick, when the app
  changes, and with a fetch at most once a second while nothing waits behind
  it, never on a timer. A window source's app is made active and its window key
  first, as a device's click does (the states are then the Mac's own); never
  for the Desktop or on a synthetic host. Only a leaf the device was shown is
  pressed: two parts or more, no children, its title now the one shown,
  enabled. 20 fetches and 4 presses a second per connection. The Desktop
  follows the frontmost app after a device's click, under the AppKit loop at
  once (NSWorkspace), else at the catalog's poll. One line per press, "Menu
  from ‹device›: menufixture › Probe › Set Label A", and a line for a refusal,
  an app that stops or starts answering again, or a device over its rate;
  nothing else prints, and `menu.*` stats keys only while menus are used.
- Device (`MacMenuState`, `MacMenuElements`, `MacMenuHub`, `SillAppDelegate`,
  `MacMenuButton`; Layout): the subscription at a connection's first window
  list and on a move's new connection; each menu an uncached deferred element
  (UIKit's placeholder while the Mac answers), its completion settled exactly
  once (the answer, a new tree, the timeout max(4 s, 4 × the worst recent round
  trip), a move, the end); leaves are `UIAction`s with the shortcut as the
  subtitle, and no `UIKeyCommand` or `UICommand` anywhere (a clash drops the
  whole inserted menu, a duplicate throws: the plan's probe). The iPad's bar
  (iPadOS 26): the menus of the app's one window's session right after the
  iPad's View, inserted once per build next to an anchor looked up first; with
  two or more windows none (every window is key in its own scene, so nothing
  says whose session the bar would act on). The button: between the window
  strip and Aa in the landscape bar and an iPad's portrait window bar, where
  the bar holds it and still a whole thumbnail (not in a 320 pt Slide Over),
  and on a phone held upright at the end of the thumbnails' row, under
  Settings; a UIKit pull-down over the bar's look, the Mac's order top to
  bottom whichever way it opens, faded under the Aa ruler; opened over the
  Settings panel, it puts back the keyboard the panel took down when it goes.
  A refused choice: the warning haptic (iPhone) and a VoiceOver announcement,
  nothing on screen.
- Sill.app: nothing on its screen changes (no setting, no menu item); its
  coordinator is the CLI's; `--menu-selftest` works in the bundle, and the
  "Menu from" lines are in Show Log….
- Observed: iOS 27 rebuilds the main menu lazily, as the plan measured on 26:
  a top level that arrived after the window became key was in the bar only
  after a focus change (opening the pull-down, or the stream screen going), so
  each bar menu asks by the title it was built with (§7.2 rule 11).
- The review (2026-09-27, the plan's "The review and its fixes"): a fetch
  never checked against the menu the device opened (after an app inserted an
  item above a submenu in place, the device's "600 Items" listed 300 Items'
  items and a choice among them ran there); a queue with no deadline and a
  top-level read per fetch (a slow app's fourth menu answered after the device
  gave up); the compatibility floor without 24, 25 and 27; non-subscribers
  served and a departed device's fetch still read; two windows' bar acting on
  the other session; the button pushing narrow bars off the window and leaving
  a phone's strip less than a thumbnail; the keyboard left down after Menus
  over Settings; rule 11 across sessions; the stale note like a dimmed menu;
  the harness choosing on any Mac. Each reproduced, then fixed (992229f the
  host, 9dfa45a the device).
- Verified after the fixes (2026-09-27; the plan's Results have every number):
  `Tests/checks/run-all.sh`, all 22; mutants: menus 43 of 43 (309 checks),
  menu-state 29 of 29 (5,122), phone-portrait 31 of 31 (152), pointer-control
  33 of 33 (155), protocol 20 of 20; `Scripts/menu-check/run.sh`, reader 40,
  budget 4 and mirror 69 (the shift, the walks, only subscribers, the
  deadline, a sweep's one top-level read); through synthetic hosts on loopback
  with the fixture, one at a time, no device on Sill.app and the front never
  changing: H2 against main at 2b38179 (the CLI byte for byte, masked and
  sorted, idle and with a client, with and without `--direct-wireless`), and
  H4–H11, H14 (the tree changed in place) and H15 (only subscribers), 99
  checks; an app busy 500 ms a call, swept menu by menu: the four answered by
  3.6 s with one top-level read (5.6 s and four reads before); iOS Debug and
  Release for the simulator and Debug for a device, only the old
  `StreamClient` capture warning; `swift build -c release` from `git archive`,
  only the CaptureProbe warning; `make-app.sh` without `--install`, and the
  bundle's `--menu-selftest` against the fixture; in a private simulator,
  screenshots only: no button at 320x700 and 460x400, the phone's row at five
  widths, the note's own section, the bar empty with two windows, the
  keyboard's console lines, and `-SillMacMenu none` pixel for pixel main's
  build at the Duo's four sizes and the phone's 393x793; live against the
  fixture through a synthetic host (Probe asked by its title, Set Label A
  chosen), and a renamed copy of it refused by `-SillMenuPress` and
  `-SillMenusOpen`.
- Known: an app busier still (700 ms a call) answered the fourth menu at
  4.25 s, after the device's 4 s: the deadline is kept between Accessibility
  calls, not inside one. H12 (TextEdit through a host) was not run: TextEdit
  was not open, and none is started.
- **For Noah:** the plan's open questions took their defaults (Q1 the Mac's
  menus after the iPad's View, Sill's own kept; Q2 the button in every bar that
  holds it; Q3 shortcuts as subtitles; Q4 no Apple menu; Q5 the app activated
  when a menu opens; Q6 Option alternates as rows of their own; Q7 the
  Desktop's frontmost app; Q8 ⌘W unchanged; Q9 no banner; Q10 no setting; Q11
  kinds 24, 25, 27; Q12 no timer). Two placements are the review's defaults
  (Q2): on a phone the button ends the thumbnails' row (row 1's five kept; the
  key row is the other place), and a window too narrow for it leaves it out,
  so before iPadOS 26 a Slide Over has no menus.
- For the other branches: kind 28 (`trackpad-gestures`, merged since: PR #38)
  flipped `Tests/checks/protocol`'s, `menus`' and `pointer-control`'s "28
  unknown", and the three mutants that renumber a kind onto 28 or 29 moved to
  free numbers (Tests/checks/README.md); the pbxproj block A040–A044/F040–F044;
  StreamClient's `handle` gains `.macMenu`, its first window list the
  subscription, a move's `finishMove` `menusMoved()` and `tearDown`
  `resetMenus()`; `TopBar`, the portrait `windowBar` and the phone's
  thumbnails' row (`PhonePortraitLayout.menus`) the button; `SillApp` the
  adaptor.
- **Untested, for Noah (the plan's P1–P13, and the review's):** VS Code (its
  ten menus, Copy enabled with a selection, Themes, New Text File, "F5"),
  Weather (a ✓ toggled), Bambu Studio, Blender's two menus, the Desktop
  following the frontmost app (at once in Sill.app), the virtual display (Save
  As…'s sheet), ⌘S through a hardware keyboard with the menu showing it as
  text, the iPadOS 26 bar itself (a pointer at the top edge or a swipe down:
  the subtitles, the placeholder, ten or more menus, the lazy rebuild after a
  thumbnail tap), an app that stops answering, mixed builds, VoiceOver ("Code
  menus"), five minutes of use (frame age and rtt unchanged), an iPhone (the
  button at the end of the thumbnails' row); two Sill windows (the bar shows
  none of the Mac's menus, each window's button its own); a Slide Over (no
  button); Menus over the Settings panel with a hardware keyboard (keys reach
  the Mac again once the pull-down goes); a menu whose parent changes while it
  is open ("The menus changed…" once, then the new items); Blender's Window
  menu while the iPad's bar is swept (no answer later than the iPad waits).

**First-run tour (2026-09-27, branch `first-run-walkthrough` from main at
cf05a78, merged with main at 5c6a850 and 2b38179, not rebased, PR #35; the
plan, its critique and the results are in
`docs/first-run-walkthrough-plan.md`).** Noah (2026-09-26): "Add to feature
list, app usage walkthrough first time after pairing/connecting". The device
only: no wire change, nothing sent to the Mac, two UserDefaults keys.
- What it does: a second after the first picture from a Mac (the window list,
  a frame size, a source), if nothing was touched anywhere on the screen, sent
  to the Mac, used or opened since (a recognizer on the window that takes
  nothing counts every touch; `StreamClient.lastInputAt` every input;
  `lastActionAt` a control used by any means, VoiceOver's double tap, Switch
  Control, Voice Control or Full Keyboard Access included), the stream
  screen dims (black 0.58 over the whole screen, safe areas included) and a
  card points at one part at a time, cut out of the dim and ringed in the
  accent: `touch` (the picture: tap, hold, drag; Apple Pencil on iPad), `bar`
  (hold a thumbnail, slide on Aa for a window's text; sideways and on a phone
  upright Keyboard), `settings` (Disconnect
  and Take the Tour live there; sideways "Hold your iPad upright"), upright
  `laptop` (the sticky modifiers, the keyboard key, the trackpad's two-finger
  tap and hold-then-drag). Three cards sideways, four upright. Whoever touched
  anything in that second is left alone for the session; one decision per
  session and layout, and a turn after it offers only what its layout has
  alone (the laptop card). The automatic reconnect's session goes on with the
  last one's decision (`StreamClient.tourSession`), unless that one ended
  before it or mid-run. Next and Done save each step (`Sill.tourSeen`), so
  an ended session resumes at the first step not passed; Skip ends it for good
  (`Sill.tourSkipped`), but in Take the Tour only closes it; the Settings
  panel's last row, Take the Tour, shows every step of the layout again. While it shows the layouts take no touch and
  the keyboard is down (back after, but never under a pairing link), so no
  touch, Pencil, hover or key reaches the Mac, and the device's own pointer
  move for a new frame size waits (`inputPaused`); an outside pairing link
  puts it aside. Esc skips (Done on the last
  card), Return goes on. VoiceOver: no touch card and no trackpad rows, the
  rest in VoiceOver's words (swipe up or down for a thumbnail's actions and
  Aa), focus on each title with "step N of M" and where the lit part is, the
  escape gesture skips, Magic Tap goes on. Every text size: the card widens to
  560 pt at accessibility sizes and stays beside the controls it lights
  (sideways under the bar; upright from the picture's half toward the top,
  then down to 12 pt above its targets, never across the Duo's crease; on a
  phone upright standing on its targets, or under the rows when it does not
  fit above them), its words scrolling there under a fade with the footer in
  reach; only a room under 200 pt (a tiny window) makes it cover them, without
  a cutout or ring. Each step's words start at their top. Reduce Motion
  cross-fades. On a phone held upright (main's PR #30) `TourLayout.phone`:
  `bar` lights the thumbnails with Aa and row 1's Keyboard, the laptop card
  has no keyboard key row, the hints say where the rows are.
- Files (Layout): `TourPolicy.swift` (pure), `TourOverlay.swift`, targets in
  StreamScreen, TopBar and PortraitStreamScreen, the row in
  HostSettingsPanel, `lastInputAt`, `lastActionAt`, `inputPaused`,
  `tourSession` and a DEBUG tripwire in StreamClient, the harness's arguments
  and `-SillOrientation` in ContentView; `Tests/checks/tour` (compiles
  PhonePortraitLayout.swift too; in CI's mutants matrix). pbxproj A401/F401,
  A402/F402.
- Beyond the plan (its Results say why): the count goes on across a rotation
  (the plan restarted it); a laptop card passed under VoiceOver counts as seen;
  "not active" is UIKit's applicationState (SwiftUI's scenePhase read inactive
  for an active app in a headless simulator, so every decision passed); the
  strip's lit band takes in the active halo and the badge; the card's tail and
  frame come from its laid-out height (a GeometryReader in it saw the appear
  animation's scale); `-SillTakeTourAt`. Found and fixed: Done wrapping to two
  lines on the iPhone SE at accessibility-extra-large (the footer's line was
  measured with its words free to wrap); a run carried into the other layout
  left that layout's decision open; a card on a 3x screen fading its last
  row (below).
- Verified (the plan's Results): Debug and Release for the simulator and Debug
  for a device, only the known StreamClient warning, and each commit's state
  builds; `Tests/checks/tour` 34,059 checks and 35 of 35 mutants, `run-all.sh`
  whole (16 checks); the hard-rule greps (no presentation or TipKit, nothing
  sent from the tour's files, nothing outside the app changed); 32 harness
  photos against the base, pixel for pixel equal but the held thumbnail's
  wiggle (which differs base against base); the Settings panel's photos differ
  only by the new row at the end; every step photographed at 1000x710,
  710x500, 710x1000, 500x710, the iPad Pro 13-inch's two sizes and the iPhone
  SE's 667x375 and 375x667, at default and accessibility-extra-large text,
  the largest size at the tightest four, and the VoiceOver run, each card's
  frame and tail (the console's `tour: screen …` lines) as the check's model
  of the layouts; the rule in the mock (fresh, landscape, done, skipped, the
  Apps list, a stand-in touch, the pairing overlay, Next through Done); with
  the real keys in the mock, shown, then "nothing owed", then back from
  Settings. Live (03:28–03:40, once Noah's iPad had left Sill.app, which it
  streamed from until then; `SillHost --synthetic` on loopback, the guard
  before each host and a watchdog on Sill.log during, each host under 40 s,
  none left running; the normal app on an iPhone 18 Pro Max with
  `-SillConnect`): on a fresh install the first connection showed the touch
  card 1.06 s after the picture and, the stand-in pressing Next, saved all
  four steps; the second connection said "nothing owed here"; the Settings
  panel's Take the Tour (`-SillTakeTourAt 2`) showed it again from the first
  step; a session cut at the third card went on next time with what was left
  (the laptop card alone, with its subtitle); a host refusing this version
  (`SILL_TEST_MIN_DEVICE_VERSION=99`) gave its notice and no tour; every step
  upright and sideways (`-SillOrientation landscape` turns the normal app) at
  the default size and accessibility-extra-large, each ring on its controls
  under the real safe areas; the tripwire never fired. Found there and fixed:
  upright on that 3x screen the Settings card faded its second row as if it
  scrolled (its words missed their fit test by a rounding); the card is
  measured with a point of slack.
- Review fixes (2026-09-27; the plan's Results, "Review fixes", one commit
  each): Next kept the last card's scroll (Reduce Motion off); Skip in Take the
  Tour saved the permanent skip; an assistive technology's action did not count
  as starting; every automatic reconnect decided afresh (the dim over someone
  at work when a dropped picture came back); the bar card taught Aa over the
  Desktop, which Aa does not resize; at accessibility sizes a card covered the
  controls it lit, slivers of its ring beside it; a put-aside run ended by a
  turn put the keyboard back under a link's confirmation; a new frame size sent
  a pointer move under the tour. Found while verifying: the tour's delayed work
  acted on a gone stream screen (it now keeps to its session); DEBUG
  `-SillTourActivityAt` touches in the first session only. Then main at
  5c6a850 merged in (PRs #29 and #30; ci.yml, CLAUDE.md, DEVELOPMENT.md,
  HostSettingsPanel and PortraitStreamScreen conflicted; the targets on the
  views both arrangements share), and the phone's arrangement got its rules;
  then main at 2b38179 (PRs #31–#33): the Mac's pointer's `pointerFrameChanged`
  now holds its move while a card shows (the eighth fix, carried over).
  Verified: `Tests/checks/tour` 43,784 checks and 63 of 63 mutants,
  `run-all.sh` all 21 on the last merge; iOS Debug and Release for the simulator and Debug for a
  device, each commit's state building, only the known warning; `swift build
  -c release`; the review's probes before and after (the scroll after Next
  486 → 0; an accessibility activation in the beat: the tour came, now "not
  this session"); Take the Tour's Skip leaving the upright card owed (the
  mock); live through the remote door on loopback (a second host on the same
  port and identity, the app's own automatic redial): a session that passed,
  the reconnect's showed nothing; one cut mid-run, the reconnect's showed the
  tour from the step not passed; the build before showed the tour again after
  a reconnect; harness photos of every layout, text size and the phone's
  arrangement (four phone sizes); live on an iPhone 18 Pro Max, every step
  upright (the phone's arrangement) and sideways at two text sizes under the
  real safe areas; the tripwire never fired.
- **Untested, for Noah (the plan's P1–P16, on the iPad mini and the iPhone 15
  Pro):** the automatic tour needs a Release or TestFlight build on a fresh
  install, or Debug with `-SillTourState fresh` (Xcode's scheme). P1 a second
  after the Desktop shows, untouched: the tour; while it shows tap, hold and
  drag on the picture, type on a hardware keyboard, hover and touch with the
  Pencil, use a trackpad or mouse: nothing reaches the Mac (no `in.` counters
  in the host's `[1s]` lines) and the picture keeps moving; fresh again,
  touch the picture within the first second: no tour this session. P2 each
  step lights what it names in both layouts; held upright after a tour
  sideways and left alone: the laptop card once. P3 quit Sill.app at the
  third card, reopen: the next session starts at the first step not passed.
  P4 Take the Tour in both layouts with the keyboard up before Settings: the
  keyboard back after Done. P5 Skip on the first card: no tour at the next
  session, nor upright. P6 VoiceOver (no touch card, no trackpad rows, focus
  on each title, rows read whole, swipe up or down in the bar rows, the
  escape gesture skips, Magic Tap goes on, the stream screen read afresh
  after Done). P7 the largest text size. P8 Reduce Motion (fades only). P9 a
  hardware keyboard (Return on, Esc skips). P10 an outside link (the Camera on
  the Mac's pairing code) during the tour: it steps aside, Cancel, it is back
  at its step. P11 the iPhone upright and sideways: each ring on its
  controls, the cards clear of the Dynamic Island and the home indicator,
  "iPhone" and no Pencil row. Also the taps themselves: Next, Skip and Done
  under a finger, and a tap on the dim nudging Next (no tap could be made
  here; if one is lost to the dim, the plan's §6.1 drops the nudge). After the
  review: P12 the iPhone upright (the bar card under the thumbnails, the
  laptop card standing on the keys); P13 start at once, then drop the
  connection (Wi-Fi off and on, the Mac asleep and awake): no tour when the
  picture returns, and a tour on screen at the drop comes back; P14 VoiceOver,
  double-tap a thumbnail in the first second: no tour; P15 Take the Tour, Skip,
  then upright: the laptop card still comes; P16 the largest text size, every
  card beside its controls with its ring whole.

**The Mac's pointer on the device (2026-09-26/27, branch `pointer-visibility`
from main at 8b0d418, merged with main at cf05a78 in b6f57d0, at 676b362 in
e7307e6 and at 5c6a850 (PR #30, the iPhone's portrait layout) in e21ce1c, not
rebased, PR #31; the plan and the results, host, device and the review's
fixes, are in `docs/pointer-visibility-plan.md`).** Noah: "When the
Mac is controlling the mouse pointer, it should show the real mouse pointer
on the desktop on Sill. When Sill is controlling the Mac, continue to hide
the real pointer and only render the client side one in portrait mode when
the trackpad is used" (2026-09-25); the plan's defaults, but Q4: the pointer
is sampled at the stream's frame rate while it moves. Built, reviewed and
checked; PR #31 merged (35f7cde), and Noah's device tests (P1–P12, below) are
still open.
- Wire: kind 26 `macPointer`, host → device, JSON `MacPointer`
  (`Pointer.swift`): where the Mac's pointer is in the streamed frame (`x`,
  `y` as fractions to 4 places, left out off the stream), `inside`, and `seen`,
  the input messages (kind 8) the host had read on that connection, so a device
  drops a report built before the host read its latest input. Every field
  optional; older readers skip 26. 24, 25 and 27 are the Mac's menus (PR #36).
- Host: one controller, the Mac or the device whose input the host read last
  (`PointerControl`, pure). Any kind 8 hands the pointer to its device; a
  pointer or scroll input, and Sill's own post or warp (noted just before it),
  open a 0.25 s settle; a read 0.5 pt or more from the last position that
  counted, outside the settle, is the Mac's (a slow drag adds up, jitter never
  does); a read more than 0.25 s after the one before starts afresh.
  `PointerWatch` reads `CGEvent(source: nil).location` (no permission; a
  sample takes about 0.2 µs) at each 30 ms link tick, and at the stream's frame
  rate while the pointer moves over the source and some device is sent it,
  when that is more often than the tick (`PointerWatch.samplerInterval`: off
  the source every device hears the same `inside: false`, and at 33 fps and
  below the tick samples as often); it judges the read against the streamed
  source (the Desktop's display, a staged window's crop or full-screen band, a
  regular-mode window's bounds and on-screen flag, re-read on `sill.pointer` at
  most every 0.1 s after a move while some device is sent the pointer, and
  every 2 s anyway), inside meaning 0 ≤ x < 1 and 0 ≤ y < 1 (the far edges are
  the next display's), and reads nothing while nothing streams. StreamServer
  sends kind 26, only when it changed, to every device but the one driving, as
  it sends ticks (not counted in `inflight`; it stands in for that device's
  tick). No line prints; `ptr.sent` and `ptr.mac` join the `[1s]` lines when
  they happen. A synthetic host never reads the real pointer and never posts
  input (`in.dry` instead, InputInjector's dry run, and no activation or
  raise), and has a pointer only with the TEST ONLY `SILL_TEST_POINTER_PATH`;
  `SILL_TEST_SOFTWARE_ENCODER=1` keeps a synthetic host off the hardware
  encoder for good, and `SILL_TEST_LOOPBACK=1` puts both its doors on
  127.0.0.1 alone (Build and run).
- Device: one sprite (`HEVCDisplayView.setPointer`, in the Mac's shape from
  kind 14) shows what `PointerPresence` (pure) says. Kind 26 is judged on the
  network queue, where input is sent and counted (`PointerFeed`): stale when
  its `seen` is below SessionLink's `inputsOnSession` or a coalesced move
  waits; during a hand-over's carry-over (a move to a new connection while
  this device had the pointer, until its first input there) a report of this
  device's own position is dropped; else the Mac has the pointer, and its
  arrow shows where the report says, in every layout, drawn whatever
  connection carries the session by then. Every input this device sends gives
  the pointer back to it: its own arrow then shows only for the portrait
  trackpad (`setOwnPointer(_:from: .trackpad)`), never in landscape, never for
  a finger, typing, a key or the iPad's own pointer, and not for the Pencil
  unless Q2's flip (`pencilShowsPointer`). A key of the portrait key row keeps
  what shows (`sendFromKeyRow`: the Mac's arrow stays where it is, as this
  device's own). The pad's cursor is `PadCursor`: a stroke's first finger
  starts at the anchor (the newer of the Mac's last position and this device's
  last pointer event), and before any move, click, long press or scroll it
  carries on from the anchor again whenever the Mac or another device took the
  pointer, or moved it on, since the pad last looked (`reseeds`), so a finger
  resting while the Mac's mouse moves carries on from the Mac's pointer
  whichever of the two had it when the finger landed. The layout reaches the
  client (`DuoLayout.isPortrait`); nothing shows while nothing streams. Q1's
  linger timer is built and idle. DEBUG `-SillInputScript` runs only against
  a test host on this Mac (a loopback address and no `hostVersion`).
- Review (2026-09-27, the plan's "Review fixes"): eight findings, each
  reproduced before it was fixed (the seventh, a race, from the code and the
  pure model): the frame-rate sampler ran with the pointer off the source (120
  reads and 140 wakeups a second at 120 fps, nothing sent) and, below 33 fps,
  sampled less often than the tick; a regular-mode window was re-read 8.6
  times a second while one device drove alone; the column at maxX and the row
  at maxY read as inside; a finger that landed while the Mac had the pointer
  and rested while it moved on pulled it back to where it landed (P3's second
  order); a report landing just before a move's hand-over was never drawn;
  `-SillInputScript` would have sent input to any host a session reached,
  Sill.app included; a stale comment.
- Verified (the plan's Results and "Review fixes"): `swift build -c release`;
  iOS Debug and Release for the simulator and Debug for a device (only the old
  `StreamClient` capture warning); `Tests/checks/run-all.sh`, all 19 on the
  merge, and the pointer checks' mutants (pointer-control 152 checks and 33 of
  33, pointer-presence 165 and 43 of 43, pointer-watch 132 and 40 of 40; the
  452 of the device step's run before the review); the review's harness (the
  real StreamServer and PointerWatch, loopback only, a scripted pointer) against
  98d2860's: off the source 33 reads a second instead of 120, back over it the
  first report within a tick (2.7–24 ms), 30 ms apart at 24 and 30 fps, 0.6
  window re-reads a second with one device driving and 8.6 with a watcher, and
  three integration mutants of StreamServer's call each bringing one back; the
  host's synthetic gates on loopback-only hosts (H4–H9, H13, the remote door,
  new ones for the edge and for 24 and 30 fps) and, with no device connected
  to Sill.app, H2 against the host step's base logs and the sampler at 120 fps
  (8.0 ms apart); S1's 40 photos; live on a simulator of its own, 51 of 51 on
  the merge: S2–S7 as before (S5 across the move from AWDL) and S2b and S2c
  (the finger landing while the Mac has the pointer, the Mac's mouse moving it
  on, then a move and a click from where it went) and S8 (the input script
  refused against a host that says it is Sill, run by 127.0.0.1, ::1 and
  localhost against one that does not); H12, the bare app's 100 previews
  identical to main's. On the merge with PR #30 again: all 20 checks, the
  three iOS builds, S2–S8 (51 of 51), S9 (the phone's arrangement: the pad
  starts at the Mac's arrow, and 50 pt down moves the pointer by the pad's
  width ÷ 1.6, 0.243 of the frame), S1, and the pointer's states photographed
  in the phone's arrangement. Not run: S5's moves to the cable and back to Wi-Fi
  (they need a host on this Mac's own Wi-Fi and cable addresses, and test hosts
  listen on loopback only now), the hand-over race live, anything on a device.
- **Untested, for Noah:** everything on the devices, the plan's P1–P12: the
  Desktop in landscape (move the Mac's mouse: the arrow on the iPad where it
  is, in its shape, following within about a tick; stop: it stays; tap the
  iPad: gone; move again: back; to another display and back: gone at the
  edge, back within a tick); a window in regular mode (shown over it, gone off
  it, still over a window covering it, gone minimized); portrait (the
  trackpad's arrow starts where the Mac's was, no jump on the Mac; lift: it
  stays; the Mac's mouse: the arrow jumps to it; a finger resting on the pad
  while the Mac's mouse moves, then moving or tapping: it carries on from the
  Mac's pointer, both when the finger came down after the iPad drove and when
  it came down while the Mac already had the pointer); rotation (the pad's
  arrow gone in landscape, the Mac's shown in both); typing and hardware keys
  hide the portrait arrow, the key row does not; the Pencil draws none; the
  virtual display (the arrow over the staged window, a full-screen video's
  band); remote (the arrow trails by about the round trip, `net.dropped` no
  higher while the mouse moves); two devices (the iPhone shows the arrow the
  iPad's trackpad moves); mixed builds (this iPad against PR #13's Sill.app: no
  Mac arrow; PR #13's iPad against this Sill.app: as before); five minutes on
  a still window (Sill.app's CPU as before, frame age and rtt unchanged,
  `ptr.sent` only in seconds the mouse moved over the stream, the arrow never
  choppy enough to want Q4 undone); moves keep the device's control
  (streaming in landscape, tap, plug the cable in and later pull it: no arrow
  at either move; move the Mac's mouse: it shows).

**The iPhone's portrait layout (2026-09-27, branch `iphone-portrait` from main
at cf05a78, PR #30; the plan, its open questions with the defaults taken, its
gates and the review's fixes are in `docs/iphone-portrait-plan.md`).** Noah: on an iPhone
held upright the software keyboard covered the key row's keyboard cap, so
nothing on screen could take it down, and the picture's half left black bars
around a 16:9 or 16:10 window. Approved (2026-09-27): the picture in a fixed
16:10 pane at the top (a 16:9 window gets black bars above and below; nothing
below the pane ever moves), then row 1, Apps, Aa, Keyboard, Desktop and
Settings, widened to the row with the key row's 8 pt between them; row 2, the
thumbnails; row 3, esc, tab, ctrl, opt, cmd and shift (no arrows, no Spotlight
cap); the trackpad in the rest. Landscape, the iPad and the Duo's inner
display unchanged; no wire change.
- `PhonePortraitLayout` (pure, CoreGraphics only; `Tests/checks/phone-portrait`,
  149 cases and 28 of 28 mutants, in CI's mutants matrix): every rect from the
  stream screen's size, the screen less its top inset (the bottom inset and
  the keyboard are ignored, so nothing moves for them). The picture 8 pt from
  the edges, ⌊(W − 16) ÷ 1.6⌋ tall (424×265 on an 18 Pro Max, 386×241 on an
  18 Pro), giving way only where the trackpad would drop under 120 pt (an SE
  with Display Zoom, by 2 pt); row 1's five buttons (W − 60) ÷ 5 wide (76,
  68.4) and 50 tall, centred in a 62 pt band as the compact window bar holds
  its own, so 24 pt under the picture and 22 over the thumbnails (the approved
  mockup's rhythm); the strip 62 tall from 6 to W − 6, its first thumbnail at
  14 with Apps and esc; six caps (W − 68) ÷ 6 wide and 44 tall; the trackpad to
  16 pt above the bottom (412×389 on the Pro Max, 374×331 on the Pro, the
  mockup's; 243 and 202 tall before); the Aa ruler centred on Aa and inside the
  row (36 pt a detent on every phone); the drawer and the Settings panel 8 pt
  under row 1 and across it, Apps' leading edge to Settings' trailing one (523
  and 465 pt of room; 351 and 310 before); the dim and the tap catcher
  everything but row 1's buttons.
- Detection: `DuoLayout.outerPortrait`, unchanged (taller than wide, narrower
  than 600 pt), draws the phone's arrangement on an iPhone: every iPhone
  upright and the Duo's outer display (500×710), which has the same keyboard
  problem, a choice Noah can reverse (`DuoLayout`'s doc says how). An iPad
  window that narrow keeps the compact halves as on main, the key row's fold
  into two rows included: the idiom, read once in `DuoLayout.phoneArrangement`
  (DEBUG `-SillIdiom pad|phone` swaps it). `PortraitMetrics.phone` (`.phone`)
  draws the phone's arrangement, `.compact` and `.regular` the halves.
- `PortraitStreamScreen`: the picture pane, key row, trackpad, drawer and panel
  are built once for both arrangements; the phone's are placed by a small
  `Layout` in reading order (picture, row 1, strip, keys, trackpad). Row 1 is
  the landscape bar's five in its order (Keyboard lit while the keyboard is up,
  "Show the keyboard"/"Hide the keyboard"), each symbol and Aa's text in a
  24 pt box so the five labels share one line; at the accessibility text sizes
  a long press shows a button or cap large (not Aa). The Aa ruler unfolds over
  row 1, its value inside it, and the other four fade and take no touch. The
  drawer and the Settings panel hang under row 1, which stays live and
  undimmed as the landscape bar does (Apps, Settings and Keyboard behave as
  there); the strip hides while either is open, and while the drawer is,
  VoiceOver skips what it dims. A held thumbnail's lights open below the
  strip. The viewport sends the 16:10 pane, so Aa and the virtual display
  shape Mac windows to 16:10. `TrackpadSurface.verticalSpan`: the phone's pad
  measures pointer motion, two-finger scrolling and its coast against its width
  ÷ 1.6, so the extra height is room, not a slower pointer (today's arithmetic
  would be about 40 % slower vertically on the Pros). `KeyRow` has two sets,
  `.full` (the halves' twelve) and `.phone` (six); each cap's action is
  `tap(key)`.
- DEBUG (ContentView's contract): the harness draws a fake screen larger than
  the simulator scaled down, laid out at its own size (the Duo's and the iPad's
  sizes on iPhone simulators); `-SillKeyboard 1` raises the keyboard for real
  in a live session; `-SillKeyboardToggle <s>[,<s>…]` toggles it as the
  Keyboard button does; `-SillDrawer`, `-SillSettings` and `-SillScaleOpen`
  open theirs 1.5 s into a live session; `viewport: 386×241 pt, scale off,
  60 fps` on the console; `-SillInputTest 1` (loopback only) runs the key
  row's and the trackpad's own code once; `-SillIdiom pad` draws an iPad
  window's arrangement on an iPhone simulator.
- Verified at the first build (2026-09-27, 01:05–02:15, d44c132, on private
  simulators of the iPhone 18 Pro Max, 18 Pro and 17e, deleted after; `simctl
  io screenshot` only): the check (141 cases, 24 of 24 mutants) and
  `Tests/checks/run-all.sh`, all 16; iOS Debug and Release for the simulator
  and Debug for a generic device, only the known `StreamClient` capture
  warning; 52 harness photos of the other layouts pixel for pixel the base
  build's but for what the base shows against itself; the phone layout at
  every phone's stream screen in eight states, measured against the rule; the
  normal app on each phone against a stand-in Mac: the viewport, the keyboard
  from row 1 up and down (its top at 636, 573 and 543 pt: 320 and 301 pt tall,
  no suggestions bar, which the check's table uses), the drawer, the panel,
  the ruler, AX-XL, `-SillInputTest`; a 16:10 picture filling the pane and a
  16:9 one with bars of 13.2, 11.9 and 11.3 pt above and below, everything
  under the picture the same for both. Not run then: `SillHost --synthetic`,
  which no-device.sh blocked from 01:00 to 02:48 (Noah's iPad mini streaming).
- Review fixes (2026-09-27, after d44c132; the plan's "Review fixes"): row 1
  back in the mockup's band (it sat 6 pt high and everything under it 12, the
  trackpads 401 and 343); the labels on one line; the ruler's value inside the
  ruler (also in the compact halves' 50 pt window bar); the drawer and the
  panel across row 1 (at 380 and 360 pt they left cut slivers beside them) with
  the strip hidden under them; VoiceOver skipping what the drawer dims; the
  lights below the strip on every phone (over row 1 on the SE and at 500×710
  before); the Duo's keyboard in the table; the Large Content Viewer; an iPad
  window narrower than 600 pt back on the compact halves (the approval was for
  iPhones). Verified (04:40–05:10, the same simulators, one at a time, deleted
  after): the check 149 cases and 28 of 28 mutants; 81 harness photos of every
  other layout, the iPad's narrow windows included (`-SillIdiom pad`), against
  the base: 56 identical at once, the compact halves' ruler value changed as
  intended, the rest the held thumbnail's wiggle and Δ1–2 anti-aliasing that
  retakes reproduce; 60 harness photos of the phone layout at seven sizes
  measured against the rule (rows within a pixel at 3x, label tops within
  2 px, the panels' edges on row 1's, the ruler's value 2.3 pt inside, the
  lights below the strip); the normal app against `SillHost --synthetic` behind
  a relay that drops input, no-device.sh passing before, during and after, each
  host under 55 s: on the Pro Max the viewport 424×265, Apps at 359–409 pt and
  the trackpad 412×389, the keyboard's top 95 pt under row 3, the panels, the
  ruler, a 16:9 picture's 13.3 pt bars with row 1, the keys and the pad pixel
  for pixel the same as at 16:10, with the keyboard up and at AX-XL,
  `-SillInputTest` (every event dropped at the relay); on the 18 Pro 386×241,
  374×331 and 56 pt; on the 17e 374×233, 362×324 and 49 pt; S3's text sizes.
  Merged with main at 676b362 (PR #29, the disk image; merge e73f231): only
  ci.yml's mutants matrix and CLAUDE.md conflicted. After it
  `Tests/checks/run-all.sh`, all 17; `swift build -c release` (only the
  CaptureProbe warning); iOS Debug and Release for the simulator and Debug for
  a generic device, from clean (only the `StreamClient` capture warning).
- For the other branches (`pointer-visibility`, `first-run-walkthrough` and
  `trackpad-gestures` have merged this since, PRs #31, #35 and #38):
  `pointer-visibility` changes the picture pane's
  `InputOverlay` and the `Trackpad`'s closures once (both arrangements share
  them now) and keeps both edits to `TrackpadSurface.moveCursor` (its
  `setOwnPointer`, this branch's `ySpan` on the `cursor.y` line);
  `DuoLayout.isPortrait` stays right. `first-run-walkthrough`: on phones
  upright `windows` lights Apps (row 1) and the strip (row 2), `bar` lights
  Aa, Keyboard and Desktop as in landscape, `keyboard` is row 1's button, and
  `keys` the six caps (its "keyboard key" row belongs to the halves only); its
  500×710 row takes `PhonePortraitLayout`'s rects on an iPhone and the compact
  halves on an iPad (`DuoLayout.phoneArrangement`, as `StreamScreen` asks),
  and its card placement in portrait the phone's rects (the picture 224–302 pt
  tall at the top, the drawer and the panel across row 1). `trackpad-gestures`:
  the arrows are gone from phones (⌃ with the key row's ↑ is the halves'
  only); its two-finger deltas follow the span. `home-pairing`: textual merges
  in `StreamScreen.swift` and the harness.
- **Untested, for Noah (the plan's P1–P8, on the iPhone 15 Pro and the iPad
  mini):** a 16:10 and a 16:9 window upright (bars above and below, nothing
  below the picture moves when switching); the keyboard from row 1 (up with
  esc to shift in view on the 15 Pro, typing, down again), cmd-latch then C,
  cmd then space for Spotlight with the Desktop streaming, a hardware
  keyboard's arrows; the trackpad (a diagonal at the finger's angle, one
  stroke down crossing the picture, two-finger scrolling at about today's
  speed, tap, two-finger tap, hold and drag); Aa (the ruler over row 1; on
  release the Mac window resizes to 16:10, Sill.log's "Resized … for a 377×235
  panel"); the drawer and Settings under a live row 1, as wide as it (Apps
  again closes, a tap on the picture closes and clicks nothing); a held
  thumbnail's lights below the strip; rotation both ways with the drawer, the
  panel, the keyboard and a latch; VoiceOver's order (Apps, Text size,
  Keyboard, Desktop, Settings, the thumbnails, Escape to Shift, the trackpad's
  hint; with the drawer open, row 1 then the drawer); a long press on a button
  or cap at an accessibility text size; the iPad mini upright and sideways as
  before, and in a window narrower than 600 pt upright, the compact halves as
  before.

**The Mac download in a disk image (2026-09-27, branch `mac-dmg` from main at
cf05a78, PR #29).** Noah: "Sill should open in a .dmg and be draggable into
applications folder like regular apps". `Scripts/release.sh` now makes
`Sill.dmg` beside `Sill.zip`, from the same notarized, stapled app. Nothing was
notarized, published or tagged here; Sill 0.3.1 (PR #32, 2026-09-27) is the
first release with the image, and the download page links it (PR #33).
- The image (`Scripts/make-dmg.sh`, Layout): Sill.app, a link to
  /Applications, a white background with an arrow from one to the other
  (`design/DMGBackground.svg`, 660 x 400 points, the arrow in the app icon's
  greys, "To install Sill, drag it to Applications." under them), and the
  app's icon as the volume's. Its window: 660 x 432 points at (200, 120), the
  picture and macOS 27's 32-point title bar, icon view, no toolbar, sidebar,
  path or status bar, 128-point icons at (170, 180) and (490, 180). HFS+ and
  ULFO (LZFSE, read-only): the script's header says why, and why not APFS.
  The window is a `.DS_Store` that `Scripts/dmg-layout` (Swift: Foundation,
  ImageIO) writes with no Finder and no AppleScript, in Finder's own layout:
  re-encoding the records of a Finder-made installer image's `.DS_Store`
  (2023) gives its header, DSDB's five words, its leaf and the used part of
  its root block byte for byte (only the stale bytes Finder leaves in unused
  space differ, the 12 after DSDB's five words among them), and Claude's image
  of September 2026 has the same blocks, free lists and header. The
  background's alias is Finder's form (tags 0, 16, 17, 1, 2, 14, 15, 18 and
  19; tag 20, the build folder's image, left out), and CoreFoundation
  resolves it to the picture on the mounted image. `Tests/checks/dmg-layout`
  checks the writer (Layout).
- release.sh: `make-dmg.sh --prepare` right after the build (the layout tool
  and the background, so a problem with either stops the run before anything
  goes to Apple); a real run, after the zip's checks, makes the image of the
  stapled app, signs it with the same identity, sends it to Apple on its own
  (`notarize`, the zip's code as a function; its answer and log
  `.build/Sill-<version>-dmg-notary*`), staples it and checks it
  (`check_disk_image`: hdiutil verify, stapler validate, spctl's open context
  as "Notarized Developer ID", mounted `-nobrowse` in `$TMPDIR` with the
  Sill.app inside through `check_gatekeeper`, detached on failure too); it
  prints both SHA-256s, and `--publish` uploads Sill.dmg, Sill.dmg.sha256,
  Sill.zip and Sill.zip.sha256, the notes naming both hashes. A dry run makes
  the image from the app before stapling, signed with the identity.
- The zip stays in every release for now, for older links; the download page
  moved to the image once a release carried it, as docs/release-checklist.md,
  part 2, says (the release first, the link checked, then the page, then the
  site republished): Sill 0.3.1, then PR #33 and sill-site on 2026-09-27. The
  release workflow's verify job makes
  `Sill-<version>-adhoc.dmg` (`make-dmg.sh --sign -`) and keeps it as a second
  artifact; the publish job keeps both submissions' answers and logs as the
  artifact `notary-v<version>`.
- Review fixes (2026-09-27; one review of the branch, each finding checked
  here before it was fixed):
  - The window was 4 points too short on macOS 27. Its WindowBounds was
    {{200, 120}, {660, 428}}, 400 and a 28-point title bar, but AppKit on this
    Mac (macOS 27.0, 26A428; Finder records the same SDK) gives a titled
    window a 32-point bar: `NSWindow.frameRect(forContentRect:)` makes 660 x
    400 a 660 x 432 frame, and a 428-point frame keeps 396 points. (Another
    project, on macOS 27, captured Finder opening a 660 x 432 WindowBounds as
    a 660 x 432 frame, the picture anchored at the top.) Now 432
    (`DMGLayout.titleBar` 32). Under macOS 14's and 15's 28-point bar (not
    measured here) that leaves 4 points below the picture, so the picture is
    white to every edge (it faded to #f2f3f5 at the bottom) and so is the
    view's backgroundColor (make-dmg.sh's `edge`). DMGLayout's comment had
    Finder-made images adding the title bar; the Finder-made one of 2023 has
    WindowBounds 512 x 400 for its 512 x 400 picture (Claude.dmg's tool adds
    22, the bar before macOS 11: 444 for a 422 picture).
  - The publish job's notary logs were never kept. The pinned upload-artifact
    (v7.0.1) skips every file and folder whose name starts with a dot, the
    search's root included, unless `include-hidden-files` is true, so
    `.build/Sill-*-notary*` found nothing and the step passed without an
    artifact, on main as well (the zip's log). Now `include-hidden-files:
    true` and `if-no-files-found: warn`. Checked with the action's own
    `dist/upload/index.js` under node, the step's inputs read from the YAML,
    in a workspace holding the four notary files beside the zip and the
    image: before, "No files were found"; now "there will be 4 files
    uploaded", and a warning when there are none. The verify job's two
    uploads name their file and were always found.
  - The writer's checks lived in the session's scratchpad: now
    `Tests/checks/dmg-layout` (Layout), 70 checks and 43 of 43 mutants (the
    28-point bar among them), in `run-all.sh`, CI and CI's mutants matrix
    (fifteen jobs). It holds the allocator to the Finder-made file (its
    10,244 bytes, header bytes, blocks and free lists, compared again here
    with the scratch tests' own reader), and fails when make-dmg.sh's layout
    arguments (the script sourced) or the SVG's size and white fill move
    without it.
- Verified after the fixes (2026-09-27, 03:13-03:17): the rehearsal again,
  `SILL_SIGN_IDENTITY='Developer ID Application: NOAH WILLIAM SAFFER
  (9B2KKVM937)' Scripts/release.sh --dry-run`, exit 0 in 17 s (the build
  cached, the layout tool compiled) with no keychain prompt: Sill-0.3.0.dmg
  2.9 MB (the zip 2.8 MB, the app 6.0 MB), UDIF read-only compressed (lzfse),
  its CRC32 valid, signed by that identity with a timestamp, identifier
  me.saffer.sill.dmg; `spctl -a -vv -t open --context
  context:primary-signature` rejects it as "Unnotarized Developer ID", which
  notarization changes. Mounted: an HFS+ volume "Sill", 21.0 MB with 6.3 MB
  used, exactly the five items, Applications a link to /Applications, the
  custom-icon flag, .VolumeIcon.icns the app's, the TIFF 660x400 at 72 dpi
  and 1320x800 at 144, white at every corner and edge in both, the
  `.DS_Store` read back by the tool and by the scratch tests' own decoder
  (10,244 bytes in Finder's blocks, bounds {{200, 120}, {660, 432}}, the
  view's colour white, the icons' places, the alias's IDs the folder's and
  the file's), the alias resolving to the picture on that mount, and Sill.app
  byte for byte `.build/Sill.app`, passing codesign --deep --strict (the
  image stays there for Noah's look). `Tests/checks/run-all.sh`, all 16
  (130 s), and `dmg-layout --mutants`, 43 of 43. In the session's scratchpad
  (`mac-dmg/tests`, removed at the end): make-dmg.sh for real (hdiutil,
  codesign ad hoc) against a fake app, 101 checks (the build's 97 with the
  edges' white and the view's colour) and 26 of 26 mutants (the build's 24,
  now the 28-point bar where it had 22, and a grey edge and a grey picture),
  no image left attached; release.sh's 169 checks and publish_release's 13
  again (release.sh has not changed since the build); both workflows parse,
  their actions pinned, every run block parsing under /bin/bash 3.2.
  Earlier, the build's run before the review: release.sh against stand-ins,
  169 checks (PR #18's 101 and 68 for the image: every step's order, the image
  made once from the stapled app, both submissions, the four assets with their
  checksum files, every failure stopping before anything is published, the
  mount detached, also when it holds no HFS+ volume, a busy attach tried
  again) and 38 of 38 mutants; publish_release with the real gh against a
  stand-in GitHub API (the four uploads with their names and sizes, the
  notes), 13 checks.
- **Untested, for Noah:** the `notary-v<version>` artifact on a signed run
  (0.3.1 was released by hand with `release.sh --publish`: the image signed,
  notarized and stapled, the four assets; its verify job ran on GitHub and
  kept `Sill-0.3.1-adhoc.dmg`; the page moved, PR #33); the window in the Finder
  on macOS 27 (the whole picture, a scroll settles back, the names under the
  icons readable in Dark Mode on the white picture, the volume icon): the
  checklist's part 1 §2 has the look; on macOS 14 or 15, the 4 points of white
  below the picture; the image on another Mac (downloaded, so quarantined: it
  opens, the drag, Sill opens, also offline).
- Known: files written from a Claude session carry `com.apple.provenance`,
  which `xattr -d` can't remove, so the rehearsal image's files carry it
  (Claude.dmg's have none); the zip has always carried the same attributes in
  its AppleDouble entries. Not changed here.

**TestFlight tooling (2026-09-26, branch `testflight-tooling` from main at
150f781).** Noah: "help me do the 4 opens for TestFlight" (the App Store
Connect record, screenshots, the 0.5 archive and upload, the placeholder and
the site). This branch makes those minutes of work: the upload tooling and
the record field by field. Nothing was uploaded and no record was created
here; on 2026-09-26 the record was made ("Sill – Mac Streaming", Apple ID
6816359860, PR #27), and 0.5 (1), built from b37f47a, was uploaded.
- `Scripts/release-ios.sh` (Layout): archive (Release, generic/platform=iOS,
  automatic signing, `-allowProvisioningUpdates`), export with
  `Packaging/ExportOptions-appstore.plist` (app-store-connect, team
  9B2KKVM937, automatic, destination export, `manageAppVersionAndBuildNumber`
  NO), the .ipa unpacked and checked, and with `--upload` a second export
  whose destination is upload. `--bump` (a clean tree; `CURRENT_PROJECT_VERSION`
  + 1 in both configurations, committed alone), `--api-key`/`--api-issuer`
  (`--api-key-id`; an App Store Connect key instead of Xcode's account,
  refused inside the repository, only its path given to xcodebuild),
  `--sign-at-export` (the archive unsigned, the export signs), `--unsigned`
  (CI without the key), `--print-version`, `--privacy-report` (xcodebuild
  has no command for the report: the manifests, the required-reason APIs the
  binary imports or calls, and the Organizer's way to the PDF). Refuses any
  Xcode but 27; one line per step, xcodebuild's output in `.build/ios/*.log`.
- Signing, as the rehearsal found it (2026-09-26): the first export made a
  cloud-managed Apple Distribution certificate (a POST for
  DISTRIBUTION_MANAGED; "Apple Distribution: NOAH WILLIAM SAFFER
  (9B2KKVM937)", until 2027-09-26; no private key in the keychain) and the
  profile "iOS Team Store Provisioning Profile: me.saffer.sill" (until
  2027-09-26); the App ID is Xcode's "XC me saffer sill". An archive made
  with `CODE_SIGNING_ALLOWED=NO` exports the same way with the same
  entitlements, so CI needs no certificate or profile, only an App Store
  Connect key with the Admin role (cloud signing refuses others). Uploading
  takes Account Holder, Admin, App Manager or Developer, but every export
  signs, so the notary key (Developer) can't run the script.
- `.github/workflows/testflight.yml` (Layout): by hand only. Without the key
  `--unsigned` and that .ipa as the artifact; with the secrets
  `SILL_TESTFLIGHT_KEY_ID`, `SILL_TESTFLIGHT_ISSUER_ID` and
  `SILL_TESTFLIGHT_KEY_P8`, `--sign-at-export` and the signed .ipa; with the
  variable `SILL_TESTFLIGHT_IN_CI` true too, `--upload`.
- docs/release-checklist.md, "TestFlight": the record field by field (§1),
  the App Store address (§2), the site (§3: sill-site holds main's `site/`
  but for download.html, kept at "being prepared" on purpose, so TestFlight
  needs no republish; a later one leaves out download.html, `.nojekyll` and
  `.github`), the build (§4),
  internal testers (§5), Test Information with a beta description (§6),
  external testers and Beta App Review (§7), the screenshot session (§8,
  metadata §9) and TestFlight from GitHub Actions. docs/app-store-metadata.md:
  the version record says 0.5 (App Store Connect proposes 1.0).
- Verified: the rehearsal on this Mac, archive and export in 49 s (the plan's
  numbers are in the checklist's §4), Sill.ipa 2.0 MB, App Store profile,
  `beta-reports-active` true, get-task-allow false, 0.5 (1),
  `ITSAppUsesNonExemptEncryption` false, the Local Network and camera
  strings, `PrivacyInfo.xcprivacy`, no keychain or Apple Account prompt (no
  SecurityAgent line in the unified log); the unsigned archive's export with
  the same signature and entitlements; the script offline against a
  stand-in xcodebuild playing the rehearsal's archive and .ipa (123 checks,
  27 of 27 mutants caught; in the session's scratchpad, `testflight/tests`);
  the workflow's YAML (every action pinned, no expression in a run script,
  bash 3.2 parses each run block) and its shell steps with fake inputs.
- Review fixes (2026-09-26): `--upload` refuses uncommitted changes as
  `--bump` does (a build that stays here only warns), and both count new
  files in iOSClient and Sources/StreamProtocol, which reach the build
  unlisted (the local StreamProtocol package, the asset catalog); an
  `appStoreText` that is neither the placeholder nor an App Store address
  stops the build; `--api-key` refuses a file that isn't a .p8 key, and a
  relative `--api-key` or `--privacy-report` path is the caller's, not the
  repository's; an expired Xcode sign-in, and a failure after `--bump` (its
  commit, then run again without it), are named. Roles, from Apple's pages:
  uploading takes Developer or above and signing through a key Admin (the
  docs had App Manager, and a notary key that could do neither). The
  workflow's key step names a secret that isn't base64 (it ended at
  base64's own complaint). The checklist's republish (§3, and part 1 §3's)
  deleted sill-site's own `.nojekyll` and `.github/FUNDING.yml` (tried with
  this Mac's openrsync on a copy), part 2's first release pointed at the
  rsync below, which leaves out download.html, and §3 said the published
  pages lacked the email_off comments (Cloudflare strips them; sill-site
  has them). Verified: the offline checks, 150 (123 and 27 new), and 39 of
  39 mutants (27 and 12 new); the key step under bash 3.2 with a good, a
  raw, a garbled and an empty secret; the export options against Xcode
  27.0's `xcodebuild -help`.
- **Untested, for Noah:** TestFlight on the devices, any run on GitHub
  (unsigned first, then with the key), signing through an API key, and the
  Organizer's privacy report PDF. The record and the upload are done (above).

**Before going public (2026-09-26, branch `public-sweep` from main at 150f781,
with main at a550e27 merged in, PR #24).** Noah's four steps for the first Mac
release end with making Saffsanity/sill public, which publishes its whole
history, so a sweep read the tree, every branch's history, the v0.3.0 release
and the repository's settings first. The branch fixes what the tree can:
docs/menu-bar-app-plan.md without the Apple Account's address (in the Apple
Development identity's name) or the name in that certificate's O field; made-up
Tailscale values in place of this Mac's in DebugHooks' long-name preview
(compiled into Sill.app: a person's Mac on the real tailnet), three comments,
the addresses, pairing-address and origin checks and the remote access plan; the
README and the site say the Mac download is out and the iPhone and iPad app is
on its way to the App Store (the site's steps sent visitors to a listing that
does not exist); the license is Apache-2.0 unless Noah says otherwise (final
once the repository is public); .gitignore leaves out signing keys, profiles,
keychains and design/reel/, and the checklist's `gh secret set` commands read
the keys from outside the repository; release docs after v0.3.0 and with
immutable releases (a deleted immutable release's tag can never be used again);
SECURITY.md and issue forms; the ledger check's fix, which main's PR #22 also
made (the merge keeps main's lines). Verified: a clean `swift build -c release`,
whose SillMenuBar holds none of the old values; `Tests/checks/run-all.sh`, all
15; the three changed checks' output equal to main's once the replaced values
are masked; the four address checks' mutants, 74 of 74; the preview name 291.5
pt wide with its port against 291.6.
- **For Noah, before the repository goes public:** what history, the other
  branches, the tag v0.3.0 and the 0.3.0 binary still carry (the sweep's report
  lists it): accept it, or publish a fresh repository; whether Apache-2.0 stays;
  immutable releases and the Actions allow-list (both possible while private).
  Right after: secret scanning and push protection, private vulnerability
  reporting, rulesets for main and the v* tags, the site republished, then the
  edits the comments hold back (the README's CI badge, index.html's "Free and
  open source", support.html's issues link, the checklist's private-repository
  lines). The sweep's report has the commands. Since: public on 2026-09-26
  with its history as it is (Noah), Apache-2.0 kept, and PR #26 made the
  held-back edits (sill-site republished with them). On 2026-09-27 the
  repository has secret scanning, push protection, private vulnerability
  reporting and the Actions allow-list (selected actions, pinned by SHA) on;
  still open: rulesets for main and the v* tags (none yet) and immutable
  releases (off).

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

**GitHub Actions (2026-09-25, branch `github-actions` from main at 1f3072a).**
Noah: the download link still fails; a new release should be checked by
GitHub, and does that cost money. The link fails twice over: there is no
release (`release.sh --publish` has never run; `gh release list` is empty), and
Saffsanity/sill is private, so its release files are a 404 to anyone not signed
in with access (docs/release-checklist.md, "Releasing from GitHub Actions",
has both ways out: go public, or publish in sill-site; it went public on
2026-09-26, and v0.3.0 and v0.3.1 are published there). Added:
- `.github/workflows/ci.yml` (Layout): pull requests and pushes to main that
  touch more than documents, the site or design files, and by hand; one job on
  `xcode-27`, 30 minutes, cancelling an older run of the same event and ref.
  Runner: the newest image GitHub offers and the only one with Xcode 27 (macOS
  27.0 26A428 with Xcode 27.0 27A266a as the default, 27.1 installed as
  `Xcode_27.1_beta.app` and a 27.2 beta; a public preview, issue 14404);
  `macos-latest` is macOS 26 with Xcode 26.6 at most, `macos-15` Xcode 16.4
  and 26.3, never tried with this code. `.github/actions/select-xcode` takes
  the newest Xcode 27 whose folder is not a beta (27.0 there, the same build
  as this Mac) and prints `xcodebuild -version`. The `.build` cache is keyed
  on that toolchain and Package.swift (there is no Package.resolved),
  `.build/checks` left out. The iOS build is arm64 only and not `-quiet`:
  Xcode 27's -quiet heads a compile that only warned with "error: the
  following command failed with exit code 0". The CLI runs only where it exits
  before the host starts: `--internet` alone (exit 2) and
  `--print-reachability`. Mutants only by hand, a job per check. Actions
  pinned by commit (checkout v7.0.1, cache v6.1.0, upload-artifact v7.0.1, the
  newest on 2026-09-25).
- `.github/workflows/release.yml`: a pushed tag `v*` or by hand with a tag
  (`SILL_RELEASE_TAG`); checkout with the whole history (make-app.sh's build
  number is the commit count). Repository variable `SILL_SIGN_IN_CI` not
  `true`: verify (the tag, the checks, `make-app.sh` signed ad hoc, the icon
  there, `Sill-<version>-adhoc.zip` as an artifact for 14 days). `true`:
  the checks, a check that the five secrets are set, the .p12 into
  `$RUNNER_TEMP/sill-release.keychain-db` (random password, masked; first in
  the search list and the default keychain, where notarytool keeps profiles),
  `notarytool store-credentials sill-notary --keychain` (validates the key),
  `release.sh --publish` with `GH_TOKEN` (the run's token, `contents: write`,
  or `SILL_RELEASE_TOKEN` for `SILL_RELEASE_REPO`), the notary log as an
  artifact, and an always() step that deletes the keychain and key files.
- `Scripts/release.sh`: `SILL_RELEASE_TAG` in the preflight (the tag must be
  `v<CFBundleShortVersionString>` and, when it is here, name HEAD);
  `--check-tag` checks only that. It refuses a build without Assets.car and
  AppIcon.icns (make-app.sh only warns when Quick Look or actool fail). Publish
  asks `gh api repos/<repo>` instead of `gh auth status`, which asks GET /user,
  and Actions' token can't answer that.
- `Tests/checks/` (Layout): the pure checks from this session's scratch
  folders, the newest of each, the ones run against the sources main now has,
  unchanged but for paths (the compile line in six `main.swift` headers; the
  policy, fence and clientlink mutants scripts read the repository and write
  to `.build/checks/<name>/`): policy 286 (integrate-12's merged check, 70
  mutants), fence 14 modes (review-moves-b's, 19), ledger 90 (ledger-union,
  no mutants), clientlink 89 (14), remote-rules 64 (rf2, 35), origin 66 (10),
  protocol 188 plus crosscheck.py's 8 (20), addresses 41 (step 3, 15),
  pairing-address 80 (pairing-address/fixes, 35). Not here then:
  EncoderMailbox's (only on encoder-two-in-flight, which carried it as
  Scripts/encoder-check; since that branch merged main at 32d532b,
  `encoder-mailbox` and `encoder-slowstate` are here and in CI: "A new
  session for the slow state"), and update-notice's one-line change to
  protocol's kind 23 case.
- Verified here, nothing pushed and no Actions run: `Tests/checks/run-all.sh`
  passes (all nine, 132 s); every mutant caught (`run-all.sh --mutants`, about
  44 minutes here: policy 70, fence 19, remote-rules 35, pairing-address 35,
  protocol 20, addresses 15, clientlink 14, origin 10); `swift build -c
  release` (28 s, only the CaptureProbe warning); the iOS command (only the
  StreamClient warning; both simulator slices); the CLI step under `bash -eo
  pipefail`; the three YAML files parse (PyYAML) and pass a structural check
  (every action pinned by hash, no expression inside a run script);
  release.sh's `--check-tag` on a match, a mismatch, unset, a tag on another
  commit and an annotated tag (a scratch clone), and a dry run with a wrong
  tag stopping before it builds; the Xcode rule on two fake image layouts; `gh
  api repos/Saffsanity/sill` answers.
- Review fixes (one pass: triggers and permissions, secrets, the Xcode step,
  the cache, injected failures, costs, docs):
  - The Xcode step would have failed every job: the image's `bash` is 3.2 (its
    README), which ends a `$(` at a `case` pattern's `)`, so the loop listing
    the Xcodes stopped short and `sudo xcode-select --switch` was handed the
    rest of the script as a path (reproduced with `/bin/bash`; zsh parses it).
    The loop is a function now. The step takes `version` (27 in both
    workflows: the newest 27.x that is not a beta, compared as text, as awk
    finds 27.10 equal to 27.1) and `fallback` (CI: a warning and the newest
    Xcode there; release.yml: `false`, the job fails); the old message said
    the default stayed selected and exited 1. 13 fake layouts under
    `/bin/bash` with stubbed sudo, xcodebuild and swift; every `run:` block
    parses with `/bin/bash -n`.
  - The cache's `!.build/checks` excluded nothing: actions/cache 6.1.0 globs
    with implicitDescendants off and tars each listed path whole (its
    dist/save/index.js), so `.build` took `.build/checks`; now `.build/*` with
    the exclusion. `.build` is 196 MB here, 135 of it the SDK's precompiled
    modules, module cache and stat caches.
  - `run-all.sh` skipped a check whose `run.sh` had lost its exec bit (seven
    of nine skipped: "All passed.", exit 0) and died on an unbound array with
    none: now every folder with a `run.sh` is a check, a non-executable one
    fails, none at all is an error.
  - Failures injected in a scratch copy: a behaviour mutant for each of the
    nine (the ledger's made by hand), a compile error for each build style
    (swiftc in run.sh; build.sh without `set -e`; with `|| true`), a failing
    cross-check, two broken checks under `bash -eo pipefail` (exit 2), a
    no-op mutant (`--mutants` fails on 14 of 15): every one fails as it
    should.
  - CI's concurrency group has the event, so a push to main no longer cancels
    a mutants run started by hand, nor the other way round.
  - The iOS step builds arm64 only (`ARCHS=arm64`; the generic simulator
    destination also compiled every file for x86_64): 61 compiles, 43 s of CPU
    here, `** BUILD SUCCEEDED **`, only the StreamClient warning.
  - `release.sh --publish` asks gh in its preflight whether it reaches the
    repository and whether the release exists, before building; both used to
    surface only after notarization (a stub gh: exists, missing, no access,
    no gh; `--dry-run` and `--check-tag` make no gh call).
  - The checklist's costs, against the fetched pages: they print no multiplier
    table any more (the prices' ratio is still ten), a budget stops usage
    only with "Stop usage when budget limit is reached" where offered, 15 to
    20 CI runs a month fit in Free's included minutes, the mutants take about
    an hour and a half (some 900 included minutes).
- **Untested, for Noah:** every run on GitHub (the first will be this
  branch's pull request: a draft counts too). The keychain and notary steps
  never ran (they change the keychain search list and the default keychain,
  which is not for this Mac), nor make-app.sh's Quick Look icon, spctl or
  notarytool on a runner. The steps: decide public or sill-site; set the secrets
  (`gh secret set`, the checklist); push a tag with the variable unset and
  try the artifact; then set `SILL_SIGN_IN_CI` and push the next tag. Costs:
  free once public; private, about 10 minutes a CI run against roughly 200
  included macOS minutes a month on GitHub Free (a macOS minute counts ten),
  then $0.062 a minute with a payment method on file, and nothing without one.
  Since (2026-09-27): CI runs on pull requests and pushes to main, and the
  release workflow's verify job ran for v0.3.0 and v0.3.1 (make-app.sh's Quick
  Look icon on the runner included); the repository is public, so the runs
  cost nothing. The sign job never ran (no secrets are set, and
  `SILL_SIGN_IN_CI` is not), so both releases were published by hand with
  `release.sh --publish`.

**Public README (2026-09-25, branch `public-readme` from main at b50e224,
PR #15, merged at 1f3072a).** For the repository going public at launch: `README.md` is the
public front page, everything the old README said is in `docs/DEVELOPMENT.md`
(word for word but for local paths, cross-references and two notes on the iOS
project, plus the two cable sentences main's README gained from
follow-best-path, PR #12, after this branch began), `LICENSE` is the Apache
License 2.0 as apache.org publishes it with "Copyright 2026 Noah Saffer" in
its appendix, and `.github/FUNDING.yml` names GitHub Sponsors (Saffsanity)
only, until there is a Ko-fi handle (see Layout for all four). The README
claims only what the site and this file back: Apple silicon and macOS 14, iOS
17, no latency figures, and the home connection's lack of encryption said
plainly.
- **For Noah:** Sponsorships turned on in the repository's settings (General,
  Features), or GitHub shows no Sponsor button (github.com/sponsors/Saffsanity
  is live since 2026-09-25); a Ko-fi handle, if wanted, goes in two places, a
  `ko_fi:` line in FUNDING.yml and a link in the README's Tips; the license
  stays Apache-2.0 (the repository went public with it on 2026-09-26); the App
  Store badge and the sentence under the README's links, once the listing is
  out (the sentence names the notarized Mac download since PR #24).
- Merging (done: PR #15 merged at 1f3072a, and every branch named here has
  merged since): main gained follow-best-path (PR #12, cea195c) after this branch
  began, so PR #15 conflicts in README.md and CLAUDE.md: take this branch's
  README.md (DEVELOPMENT.md's step 3 of The iOS app already has PR #12's
  cable sentences) and keep both Current step entries. The open branches that
  edit the old README put that text in docs/DEVELOPMENT.md:
  app-store-readiness's release paragraph under Releasing (its Layout list
  fits the Overview), encoder-two-in-flight's stats-line bullet and its
  Resolution note under What to try if it's slow, and update-notice's (local,
  not pushed) Updates paragraph under Sill.app, the menu bar host, its
  Distribution text under Releasing and its device-hello paragraph after the
  gear paragraph of The iOS app. A change the public README describes (pairing
  at home, say) also updates README.md's How it works and Good to know.

**App Store readiness (2026-09-25, branch `app-store-readiness` from main at
76366e8; main at ba91136, PR #13 remote access, merged in, not rebased).** What
a first upload of the iOS app and the first Developer ID download of Sill.app
need, after the App Store audit. `docs/app-store-metadata.md` has the reasons,
Apple's sources and every text to paste into App Store Connect;
`docs/release-checklist.md` the order of work, once and on every release.
- Adds: the privacy manifest, `iOSClient/PrivacyInfo.xcprivacy`, a resource of
  the target (UserDefaults CA92.1 and `systemUptime` 35F9.1, no tracking,
  nothing collected; remote access uses no required-reason API outside those
  two); `ITSAppUsesNonExemptEncryption` NO in `iOSClient/Info.plist`, which the
  build merges with the generated keys (the home connection is plain TCP, and
  remote access's TLS 1.3, CryptoKit and CommonCrypto are Apple's, which needs
  no documentation; the plist key, never also the build setting); the connect
  screen's footer (Layout, `ContentView`), for guidelines 1.5, 2.1 and
  5.1.1(i); the website in `site/` and `Scripts/release.sh` (Layout); the two
  docs, with the Remote Access switch (the cuts for a 1.0 without it).
- Confirmed by Noah on 2026-09-25 (the site is live): the site at `https://getsill.app`
  (`site/CNAME`, `SillLinks.swift`, both docs), the contact address
  `support@getsill.app` (the privacy and support pages, the README and the
  metadata; Cloudflare Email Routing forwards it to Noah), and the Mac download
  at `/download` (`site/download.html`, which links the newest GitHub Release's
  `Sill.dmg`, `Sill.zip` until 0.3.1, and is never edited per release). The
  checklist's Placeholders table has the commands that change each everywhere.
- The merge: the footer sits under main's connect screen (Add a Mac…, the
  Remote rows, the card, the leading anchor, the Duo's top half, the column at
  the top while a field has the keyboard). The branch drew the column twice,
  under a ViewThatFits of a form that fits and one that scrolls; with main's
  card that meant two cards, each with its camera and fields, and a new one
  whenever the fit changed (the card folds its words while a field has the
  keyboard). Now one scroll view holds the one column whatever the fit
  (`ColumnOverFooter`, measuring a hidden copy of the footer), and a scrolling
  column fades over 12 pt with 12 pt clear before the footer (the branch: 24
  and 12), both inside the 24 pt gap that a column that fits keeps. At 710×1000
  the column stays in main's top half, the footer along the bottom. README
  and CLAUDE.md keep both sides.
- Verified on the merge: iOS Debug and Release for the simulator and Debug for
  a device, only the StreamClient capture warning; no package source differs
  from ba91136; both built Info.plists read `"ITSAppUsesNonExemptEncryption" =>
  false` (Xcode's ProcessInfoPlistFile takes `iOSClient/Info.plist`), with
  `PrivacyInfo.xcprivacy` at the bundle root. Harness photos of the merge and
  of main's own build, compared pixel by pixel: 1000x710, 710x1000, 500x710 and
  710x500 on an iPad, 440x956 and 956x440 on an iPhone 17 Pro Max, default and
  accessibility-extra-large text, the cases looking, methods, denied, remote
  and addmac. In 54 of the 60 the title is where main puts it and only the
  footer's pixels differ. The six others follow the rule: methods at 710x500
  and at 956x440 scroll above the footer (the column 16 pt from the top), and
  remote at 956x440 rises 17 pt (27 at the larger text). The title's x never
  changes, and nothing overlaps the footer.
- Verified before the merge (the commits say how): Release builds with the key
  in the built Info.plist beside the manifest; the footer's photos against its
  parent commit (the column never moved), an accessibility dump (three links,
  the dots hidden) and Support opening its page; the site's static checks
  (tags, links, CSP, headings, the Remote Access markers and their cut gate);
  release.sh's refusals and its functions (33 checks, a fake keychain), never a
  real run; the placeholder commands on a scratch copy.
- After the merge, review findings fixed: every page's brand and Home links
  were `./`, which opens nothing from the folder (WebKit from file://: 8 of
  the 28 header and footer links dead; with `index.html`, all 28 land on their
  page, and each answers 200 from `python3 -m http.server`). A column that
  rose to keep the gap could reach the very top, while one that scrolls has
  16 pt above it, so at the switch it jumped: methods at 710 wide scrolled with
  its title 19.5 pt down at 510 pt tall and, one point taller, rose flush (the
  title 4 pt down). Now it rises no higher than 16 pt from the top, the same
  as scrolling: photographed at every height from 500 to 540, the title stays
  19.5 pt down up to 526 and then moves 1 pt a point (at the larger text, up
  to 535); the 60 photos above are pixel for pixel the merge's. The export
  compliance key needed no change: the target generates its Info.plist from
  `iOSClient/Info.plist` plus the build settings (GENERATE_INFOPLIST_FILE with
  INFOPLIST_FILE), and clean Debug and Release builds of the result, for the
  simulator and for a device, all carry `ITSAppUsesNonExemptEncryption` false
  and `PrivacyInfo.xcprivacy` at the bundle root, with only the StreamClient
  capture warning; `swift build -c release` builds, and again is a no-op. The
  real app on the iPhone simulator (Bonjour listed this Mac; nothing
  connected): the footer above the home indicator, at both text sizes.
- Main moved on while this ran: PR #11 (encoder recovery) is b50e224, not
  merged here then (the branch took it with main at cea195c in 11e01cd, and PR #14
  merged at 2df7ad6); it overlaps this branch only in CLAUDE.md and README.md.
- **Untested, for Noah:** the decisions: the domain, the contact address, and
  whether 1.0 keeps Remote Access, which main has had since ba91136 (the
  audit advised a 1.0 without it before it merged; the metadata's switch lists
  the cuts). On a device: the footer's links open Safari (the site: live since
  2026-09-25), VoiceOver reads the footer once, after the rows (its measuring
  copy is hidden from it), the card's fields with a hardware keyboard (the
  column at the top, the footer in view) and the software one (the footer
  under it), and a phone held sideways, which only the harness drew here
  (956x440). The release: the Developer ID
  certificate, notary credentials, release.sh for real, a first launch on a
  Mac that never had Sill, the site on GitHub Pages with its DNS record, the
  App Store Connect record (the checklist's part 1). The description's claims
  not yet seen on a device: the cable on an iPhone, Pencil hover, 120 fps.
  Done since: the domain and the address (2026-09-25), the site at getsill.app,
  the Developer ID certificate, the notary credentials and release.sh for real
  (v0.3.0 and v0.3.1), and the App Store Connect record (2026-09-26).

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

**The session follows the best path (2026-09-25, branch `follow-best-path` from
main at 76366e8, after PRs #9 and #10).** Noah's tests: plugging the cable in
left a Wi-Fi session on Wi-Fi until he reconnected (a TCP connection keeps its
interface), and pulling it hung the session a while, then the connect screen,
then Wi-Fi. A live session now follows the best path its Mac is reachable on,
the cable over Wi-Fi over Direct (`DiscoveryPolicy.pathPlan`, pure;
`StreamClient.followBestPath`), by the move from AWDL's make-before-break
hand-over (the new connection's first window list must carry the same
`launchID`). Up: once the network browser has listed the session's Mac on a
wired interface for 2 s (`cableSettle`, counted again after a move off it),
the Mac is dialled on it beside the Wi-Fi session (the wired dial; not ready in
2.5 s, or waiting or failing, and the session stays on Wi-Fi) and handed over
with the fence, and the readout says Wired. Down: when the cable's path is
gone (iOS says so: the connection not viable, back to waiting, or a path
update that is not satisfied and names the Mac's address; or the browser has
dropped the cable and either an unsatisfied update names only the service or
no pong has come back for 1 s, `pongSilence`), the Mac is dialled at once on
the Wi-Fi interface it is listed on, or was within 5 s (`wifiFresh`; the row as
listed after 2.5 s), what the device sends waits meanwhile
(`SessionLink.hold`) and goes out first on the new connection with no fence
(`adopt`), and the old connection is force-cancelled so nothing of it lands
late; a path that comes back calls the move off (`unhold`). A connection
already dead over the cable is made again at once (`reconnectNow`): over the
cable when the browser still lists it and iOS said nothing of its path (the
Mac closed it), as a tap on its Wired row dials it (the row as listed after
2.5 s), else over Wi-Fi the same way; the stream screen stays, no retry timer,
and if the Mac stopped the stream meanwhile (zero devices) the new
connection's first list picks the source again (the Desktop for a window that
went). Never Wi-Fi to Wi-Fi, never off a working cable (a browser blink alone
never moves it: its pongs keep coming), never off a Direct session but to the
network, at most one move per 5 s each way (`pathHysteresis`; up, 10, 20, 40,
then 60 s after moves to the cable that did not complete, `upWait`, and never
again to a listing of the cable that reached another Mac or launch until it is
listed afresh); with no Wi-Fi to go to, the ordinary end and reconnect.
DEBUG console: "path: the cable appeared: moving the session to anpi0", "path:
the cable went away: moving to Wi-Fi on en0", "path: the cable went away with
the connection: reconnecting over Wi-Fi on en0 now", "path: kept: …", and what
iOS said ("path: the session's connection is not viable…", "path: iOS says the
session's path is unsatisfied…"); `-SillPathTest` drives it in the simulator
(ContentView's contract). Verified: the policy check at 253 (187 plus 66: the
plan at every boundary, a 20,480-case grid, a model of plugs, pulls, blinks,
silence and a loose cable), 48 of 48 mutants caught (25 plus 23); the fence
check's eight modes (new: hold, holdclosed, unhold, adoptfence), six mutants of
the new SessionLink code caught; in the simulator against `SillHost
--synthetic`, dialling this Mac's own `fe80::…%en0` ("Wi-Fi") and
`fe80::…%en14` (the USB cable to the iPad, "Wired"): the cable listed at 3 s,
moved about 2 s later with the fence down in 1–2 ms; the path reported gone,
on Wi-Fi 10–20 ms later without a fence; the connection cut, carried on over
Wi-Fi in 10–20 ms with no connect screen and the Desktop picked again; the
cable dropped with pongs silent, moved at the 1 s mark, with pongs flowing,
kept; a loose cable moved up at 3.7, 8.9, 13.9 s and down at 4.6, 9.6, 14.6 s;
no Wi-Fi, the ordinary end; the move from AWDL and PR #10's wired-dial
fallbacks unchanged. **Untested, for Noah:** the real plug and pull on the
iPad while streaming. Plugged in: a few seconds later "path: the cable
appeared", the readout's Wired, and the host's "Client connected: …%anri0" (or
`%en14`) then "Client left" for the Wi-Fi one. Pulled: within about a second
the readout's Wi-Fi with no connect screen and the host's "Client connected"
over Wi-Fi (`%en0`, or the iPad's Wi-Fi IPv4 address; the cable's connection
leaves by itself, at the latest by eviction 4 s on); and which signal iOS gave
first (the console's "path:" lines), since a pull's own signals have never
been seen on a device. And on the cable, another app for over 4 s (the Mac
evicts the suspended iPad), then back to Sill: "path: the connection went
away, the cable did not", the host's "Client connected" over the cable again,
and no hop to Wi-Fi.

Review fixes (2026-09-25). A connection over the cable that dies while the
browser still lists the cable and iOS said nothing of its path was closed by
the Mac (it evicts a device that stops reading, an iPad suspended in the
background for 4 s): it is made again over the cable, where before it went to
Wi-Fi and came back to the cable 2 s later. A move to the cable could land
while the move from AWDL's fence was still up (that move can take 7.5 s, and
the next move up counts from its start), and its hand-over replaced the first
fence: what the first fence held was lost (a release sent then left the
button down), its AWDL connection was never closed, and `hold` was refused
while a fence stood. `SessionLink` now keeps a list of fences and a hold apart
from them: what waits goes out only once no fence and no hold stands, a hold
taken during a fence outlasts it (a cable pulled right after a move landed on
it), and each old connection is handed back for closing only once what waited
has gone out, its viewport first (`Released.close`), so the Mac never counts
only devices without one. A move up keeps its fence even when iOS has said
the old connection's path is gone (a report can pass; the 3 s timeout covers
a dead path), and a connection ready again after waiting clears `waiting` and
starts no second read loop. A listing of the cable that reached another Mac
or launch is not tried again while it lasts (`refusedCable`), and moves up
that do not complete wait 10, 20, 40, then 60 s (`upWait`), where before they
went every 5 s for as long as the cable stayed in. `-SillPathTest` gained
`close` (the connection closed, the row as it is) and `direct` (the session
counts as one over AWDL). Verified: the policy check at 277 (the 253, whose
grid now also spans refused listings and failed moves up, plus 24: the
reconnect over the cable, the refused listing, `upWait`, models of an
eviction on the cable and of moves up failing each way), 61 of 61 mutants
caught (48 plus 13); the fence check's twelve modes (new: twofences,
twomoves, holdfence, holdadopt; the `SessionLink` before the fixes fails
three: 27 inputs lost with 41 inversions, and two holds refused), 16 of 16
mutants of the new code caught; iOS Debug for the simulator and the iPad
(build only) and Release for the simulator, only the old `StreamClient`
warning; in a simulator of its own (another agent's UI tests had the shared
one) against `SillHost --synthetic`: the connection closed over the cable,
reconnected over the cable in 10 ms with no Wi-Fi hop; the cable's dial never
answering, on Wi-Fi 2.5 s later, then moves up 5, 15 and 35 s after, each
given up; a cable that connects but sends no list, and one refused at once,
the same back-off; a cable that reaches another launch, one try, and one more
once listed afresh; behind delay proxies (2 s and 3.5 s each way), the move to
the cable landing 1.5 s before the move from "AWDL"'s fence was down, the two
fences down by their timeouts, then everything that waited out on the cable
and both old connections closed; the earlier scenarios unchanged.

**The 33 fps plateau (2026-09-25, branch `encoder-two-in-flight` from
`encoder-recovery` at 4fe37d4, with main at 32d532b merged in and the review's
fixes after it: the next section's last bullets).** A Retina Desktop stream
(3024×1964, hardware encoder) sat at 30–36 fps in a third of the logged seconds
of Noah's home streams at 40 Mbps (7,445 of 22,081 seconds with 50 or more
frames captured and none idle), and nearly always over Tailscale at 4 and 15
Mbps; every such second read like
`cap.complete 56 enc.mailboxDrop 24 enc.out 33 net.sent 33`. An investigation
and a verifier (read-only: Sill.log and the kernel's AppleAVE2 log) found:
- The network held nothing back (`net.dropped` 0, `net.sent` = `enc.out`);
  nothing after the encoder waits. The whole loss was the mailbox.
- The hardware encoder falls into a slow state, often after a few seconds of
  fewer frames (a mostly still screen; once while scrolling at 38 fps) and at
  any bitrate (4, 15, 40 and 150 Mbps): a frame takes 29–30 ms from submit to
  output, and the HeartBeat's C/F (read as the engine's time per frame) 14–15
  ms, against 9 at 57 fps. Sessions started fast (7.5–9 ms a frame in their
  first windows, one at 12.3); 1512×982 never plateaued (6 ms a frame). With
  one frame inside VideoToolbox the output rate is one over the turnaround:
  33 fps.
- The HeartBeat needs `--predicate 'sender == "AppleAVE2"'` with `--info
  --debug`; `eventMessage CONTAINS "AppleAVE2"` returns only firmware lines.
  Per session and 5 s window it gives frames submitted | completed and three
  cumulative counters (C/F: the third's delta over frames;
  `Scripts/encoder-check/hbparse.py` prints it).
- 33 = 1000/30 matching the 30 ms tick timer is a coincidence (`net.tick` 33
  beside `enc.out` 55 on the cable).

The branch first let two frames into the hardware encoder at once, on the
reading that part of the 29 ms might overlap, then only under a test switch
after review (its commits 63a365b–e68408f have the design, the review and runs
on an engine shared with the Claude app's iOS Simulator panel, where two inside
gained nothing: 35.7 against 35.6 fps, capture to output 36 → 64 ms). Sharing
alone reads like the slow state in the stats line: in those runs a synthetic
Retina stream with one inside, beside the panel alone (15:43:39–15:44:09),
read ~32 fps with ~27 drops a second, and Noah's Retina Desktop beside it
33–36 fps (the operational rule in "The hardware encoder: busy, not stuck").
The HeartBeat tells them apart: it lists the panel's session beside Sill's,
and its C/F, the engine's figure, read 9.5–10.6 ms there against 14.0 for the
slow state alone. The deciding run had the engine alone:

Measured alone (2026-09-25, 20:16–21:04; no device connected, and each kept
run's HeartBeat lists only its own session): the CLI host built from e68408f
streaming the real Desktop at 3024×1964, 60 fps and 40 Mbps (Pro) to a loopback
test client, on this M2 Pro (Mac14,9, one encode engine) on AC power. Motion
came from a scratch window scrolling text-like content 6 pt a frame over a
static backdrop (57–60 frames captured a second; still, the menu bar clock
gives about one), each frame's encode call and output were timed by an
interposer on `VTCompressionSessionEncodeFrameWithOutputHandler`
(`DYLD_INSERT_LIBRARIES`), and C/F came from the HeartBeat. Schedules: 4 s of
motion, then 5, 10 or 20 s still (or 15 s with a step every 0.3 s), then 35 s
of motion (90 s once), for the slow state; 35 s of motion from the start for
the fast state. One and two frames inside (the switch,
`SILL_TEST_ENCODER_IN_FLIGHT=2`), in alternating pairs.
- What the slow state is. A fresh session's turnaround (submit to output) is
  8.7–9.2 ms for its first ~4 s, then ~16.2 ms at the same 57 fps, just under
  the frame interval, with C/F 9.0 throughout. About a second into a quiet
  phase an isolated frame takes 29 ms instead of 16 (the last 16 ms frame
  0.6–1.4 s in, the first 29 ms one 1.0–2.4 s in; in all 16 runs), and once
  motion resumes every frame does: 28.8–29.0 ms (median; p95 29.0–29.6), C/F
  14.0, 34.3–34.7 fps out of 57 captured with ~23 `enc.mailboxDrop` a second, in
  every second (35 of 35 s; 90 of 90 s in the long run). Motion from the start
  never went slow (57.3–57.5 fps, no drops). Capture to output
  (ScreenCaptureKit's timestamp to the output handler): median 39.7 ms (p95 51)
  slow, 17.6 ms (25) fast. C/F is weak evidence of a slower clock on its own:
  its counter grew 481–485 a second in the slow runs and 516 in the fast ones,
  so C/F moves with the frame rate.
- What two inside did. In the slow state 35.5–44.3 fps (mean 42.1, against 34.5
  with one), never above 49 in any second and never back to the fast state, in
  35 s or in 90 s. VideoToolbox served the second frame only after the first:
  it waited inside for a whole service time (22–28 ms) and came out that long
  after it, in order (0 of 40,774 outputs reordered); at the slow level two
  inside served one frame per 28.2 ms against 28.9 with one. The only gain was
  the engine stepping up once, 3.4–4.4 s into the motion, from 28.2 to 23–25.5
  ms a frame (40–45 fps), in 6 of 8 runs (one was on the faster step from its
  first second, one never stepped: 35.5 fps), which one inside never did. It
  cost 17–27 ms from capture to output per pair (median 39.7 → 59.4 ms, p95 51
  → 68.5; the turnaround 28.9 → 45–56 ms), which Sill's frame age, taken after
  the encoder, cannot show. In the fast state it gained and lost nothing
  (57.3–57.5 fps either way, +0.2 ms at the median). The harness (the real
  `HEVCEncoder` with synthetic frames, no ScreenCaptureKit: 3 s at 60 fps, 6 s
  of a frame every 0.3 s, 20 s at 60 fps) agreed: one inside 34–35 fps and a
  latency median of 35–38 ms, two inside 37–38 fps and 62–65 ms, no step in
  20 s.
- Dropped (the bar set before the run was ~55 fps, and ~8 fps for ~20 ms of
  latency is the wrong trade: latency beats quality). The switch and every
  path that served a second frame are gone: the mailbox's second place, the
  gate that kept a second frame out until the session had let go of one, the
  watchdog's clock restarted behind a returned frame, the re-check's test
  keeping two inside, the capture's reasoning about three surfaces. The
  re-check's test sends one frame at a time again, as a stream does.
- Observed, not verified as mechanisms: with one inside the slow state is a
  stable equilibrium (the engine is fed exactly what it completes; 90 s of
  motion never moved it); the engine paces itself to the rate it sees (9 → 16
  ms at 57 fps with C/F unchanged); at the slow levels the turnaround is about
  twice C/F. In two runs discarded for sharing, another agent's independent
  3024×1904 session on the engine lifted Sill's one-inside session to 49–57
  fps at C/F ~6 ms, and it fell back to ~34 when that load paused: load, not a
  second frame of the same stream, moves the engine. Next to try: the engine's
  power state or rate control (`EnableLowLatencyRateControl`, "The hardware
  encoder: busy, not stuck" below), not pipelining. Tried first instead, and
  kept: a new session (below). Resolution: Standard avoids the plateau too
  (57 fps with no drops at 1512×982).
- Not measured: Sill.app (the CLI only), 120 fps, other bitrates, a device,
  other chips (a Max has two encode engines), real content beyond the
  scrolling window.

What the branch keeps:
- `EncoderMailbox` (pure; Foundation and CoreMedia): `HEVCEncoder`'s
  bookkeeping as one type under its lock, one frame inside for every session:
  the frame inside (its id, its watchdog clock, whether `submit` has handed it
  over), the one-slot mailbox, `dead`, the timestamp fix and the keyframe flag
  (at 4fe37d4 eight variables). Behaviour as at 4fe37d4, edge cases included:
  `abandon` and the teardown count only a frame handed over (`outstandingID`
  then), so a frame let in and still on `encodeQueue` when the session dies,
  which never goes in, is not reported stalled, and a live session with one
  drains, as `inFlight` did.
- The order fix: a frame let in is queued on `encodeQueue` before the lock that
  let it in is released, and `requestKeyframe` sets the flag, decides whether
  the window is still and admits its re-encode in one hold. At 4fe37d4 those
  were two holds, and a repaint landing between them went into VideoToolbox
  ahead of the stale re-encode, so the device kept the older picture until the
  next repaint and `lastFrame` fell back to it (a reviewer saw it in about one
  in five coincidences of a request and a repaint, with nothing forced; the
  encoder check forces it by holding the requesting thread 4 ms after its first
  unlock: the older picture last in 10 of 10 trials before the fix, 0 now).
- The keyframe's second look: a keyframe asked for within 50 ms of the last
  repaint of a window that then stays still is looked at again
  (`keyframeCheck`, on the watchdog's queue, 60 ms after that repaint): the
  last frame is re-encoded if the flag is still set, the session is live, no
  frame is on its way to carry the flag (`EncoderMailbox.frameOnItsWay`:
  waiting in the mailbox, or let in and still on `encodeQueue`) and the window
  has not repainted. At 4fe37d4 such a request only set the flag: a device
  joining (`onClientConnected`) waited on black, and one whose delta was
  dropped (`net.dropped`, then `onKeyframeNeeded`) on a stale picture, until
  the window next repainted. On the hardware
  (`Scripts/encoder-check/verify-hardware.sh keyframe`: 6 sessions at
  3024×1964 and 40 Mbps, a request 5, 20 or 40 ms after a burst's last frame,
  then still): 4fe37d4 answered none, this branch all six, the keyframe out
  70–73 ms after the last frame (19:52–19:54) and, after the rework, 76–78 ms
  (22:02–22:03, the engine alone).
- The checks. `Scripts/encoder-check/run.sh` runs those that never touch an
  encoder (it refuses any binary that links VideoToolbox): the mailbox check,
  the real `EncoderMailbox.swift` against a stand-in VideoToolbox in virtual
  time through a copy of `HEVCEncoder`'s glue (S1–S17: 9 ms a frame 60 fps;
  30 ms 33.3 fps with 26.7 mailbox drops a second and a latency median of
  36.7 ms; 40 ms 25 fps; random turnarounds with refusals, second notices,
  rate-control drops and keyframe requests, every frame settled once; a stuck
  frame, `SILL_TEST_ENCODER_HANG`, slow and blocked encode calls, `abandon`,
  the teardown, keyframes and timestamps), and its mutants (`mutants.py`, each
  must fail it); the probe check, the real `EncoderProbe.swift` against a
  stand-in encoder in real time (one frame inside at most, 33 fps at 30 ms a
  frame, a stuck frame counted and reported back, `SILL_TEST_PROBE_HOLD=0.08`
  ~11 fps); the encoder check, the real `HEVCEncoder.swift` against
  `encoder/FakeVT.swift` in real time (every kind of session holds one frame at
  most and prints nothing when made, what a stuck encoder keeps, the order
  race, the keyframe's second look). `verify-hardware.sh` runs the hardware
  steps (parity, stream, harness, probe, keyframe) against 4fe37d4 built from
  `git archive`, each only while `no-device.sh` finds no device connected to
  Sill.app.
- Verified after the two-inside paths were removed (2026-09-25, 21:30–22:05):
  a clean `swift build -c release` from `git archive` (only the old
  CaptureProbe warning); the mailbox check, 38,256 checks, and 27 of 27 mutants
  caught; the probe check (19 checks and the hold) and the encoder check (75);
  a differential check (scratch, not in the repository) of `EncoderMailbox`
  against a transcription of 4fe37d4's bookkeeping, through 100,000 random
  sequences of the glue's events (admissions, hand-overs, outputs and
  refusals, second notices, watchdog ticks, keyframe requests, `abandon`),
  every outcome equal in 56,082,887 comparisons, while the type as it was
  before (a frame on `encodeQueue` counted as inside) failed it; the keyframe
  step above; the CLI against origin/main (1f3072a) and against this branch
  merged into it (`git merge-tree`: only CLAUDE.md and README.md conflict),
  each built from `git archive`, no device connected, each run's HeartBeat
  listing only the host's own sessions: `--synthetic` idle for 35 s identical
  masked and sorted (7 lines; in order too), and with a loopback client
  streaming the synthetic Desktop for 22 s identical (40 lines) but for one
  `enc.mailboxDrop` in the first streaming second of one of origin/main's two
  runs.
- **Untested, for Noah:** a device joining a still window gets its picture
  within about 0.1 s (the keyframe's second look has run only in the checks and
  the hardware harness).

**A new session for the slow state (2026-09-25, 22:24–22:39; c27d6df,
b3042de, dd0dc15).** The solo measurement read the slow state as a session's,
not the engine's: every fresh session started fast, and the slow state set in
only after about a second of sparse frames into an existing one. So a stream
whose session has settled in it gets a new session in place, on by default
(`HEVCEncoder.replacesSlowSessions`):
- The rule (`EncoderSlowState`, pure, Foundation only): a session that has run
  fast (a frame back in under 25 ms; turnaround is hand-over to output, by the
  mailbox's own clock) and now, over the last 2 s, gets at least 45 frames a
  second from the capture in each half of that window while the median
  turnaround of what came back is at least 25 ms and at least 1.5 times the
  fastest frame the session has returned, is replaced, at most once per 10 s
  (a new session that could not be made counts too). The new session is timed
  on its frames after its first (a keyframe) while the motion that set off the
  swap lasts: a frame counts only if the capture before its hand-over came
  within 0.1 s of the one before that and 45 came in the second before it, and
  the first frame without motion ends the timing. The verdict comes at 30
  timed frames, when the timing ends, or at the first frame back 2 s after the
  swap: their median if at least 5, else none (the picture went still). One no
  faster (its median at least 0.8 of the replaced session's: then the engine
  is slow, as beside another app) ends the replacing for that stream. A
  session that never ran fast (a size the engine is simply slow at) is never
  replaced; probes and the software encoder never are.
- The swap (`HEVCEncoder`): the new session is made with the stream's settings
  on a queue of its own while the old one goes on (the kernel opened it 39–42
  ms before it took over); `submit` hands it the next frame with a forced
  keyframe, whose parameter sets go out with it; the old one holds no frame by
  then (one inside at a time). `submit` completes it before the new session's
  first frame goes in, which waits for its last output handler to return, so
  that frame reaches `onEncoded` before the new keyframe (each session calls
  back on its own queue, and that handler lets the next frame in before it
  hands its own frame on: a callback thread descheduled for longer than the
  keyframe takes would put an old delta after it on the device), then
  invalidates it off the queue.
  The mailbox, its ids, the watchdog and the capture carry on. One line once
  the new session's first frames are back, e.g. "Encoder (hardware HEVC
  3024×1964): frames took 29 ms each (31 fps out of 51 captured); a new
  session takes 9 ms (a 329 kB keyframe, 28 ms between frames).", or "…
  takes 28 ms, no faster, so this stream keeps it and gets no other (…)".
  Nothing else prints and no counter changes.
- With encoder-recovery: a frame's clock starts at its hand-over, as before,
  so making a session counts against no frame, and the watchdog, `onHung`,
  the software fallback and the re-check never see a swap (the encoder check's
  E7: no `onHung`, no `enc.hung`, no hang or stalled line; none in the
  hardware runs either). A new session that hangs is a hang like any other:
  the watchdog gives up on it 1.5–2 s after the swap and the stream falls
  back, and the old session, retired holding nothing, is not reported
  stalled. A waiting new session is dropped when the stream's session dies
  (the watchdog, `abandon`), with the encoder, or when it is made after the
  encoder went.
- `SILL_TEST_ENCODER_RECYCLE=1` or `0` overrides the constant for one process
  (an A/B from one binary; a "TEST:" line says so).

Measured alone on the engine with the solo measurement's method (its scripts,
guards and motion window, copied): the CLI built from c27d6df by `git
archive`, the real Desktop at 3024×1964, 60 fps and 40 Mbps to a loopback
test client, this M2 Pro on AC power. No device connected (Sill.log's last
connect 18:50:52; the guard before and after every run), no user input
(HIDIdleTime rising through every run), and each run's HeartBeat listing only
its own sessions (the stream's and, switched on, its replacement, both
3024×1968 at 40 Mbps and priority 0) besides one-frame 256×256 launch probes.
Schedule: 4 s of motion, 10 s still, 35 s of motion, the switch on and off
alternating, three runs each; the fast state: 35 s of motion from the start,
two runs each. Figures are the resumed motion less its first 2 s:

| | fps out (min–max) | drops/s | turnaround med / p95 ms | capture→output med / p95 ms | C/F ms |
|---|---|---|---|---|---|
| on | 57.3, 57.3, 57.2 (55–59) | 0 | 16.3–16.6 / 16.7–17.4 | 17.4–17.6 / 25.0–25.5 | 8.7–9.0 |
| off | 34.5, 34.5, 34.2 (33–36) | 22.7–23.2 | 29.0–29.1 / 29.2–29.8 | 39.5–39.8 / 51.1–51.7 | 13.9–14.0 |
| fast, on | 57.2, 57.0 (54–59) | 0, 0.2 | 16.3 / 16.7–17.4 | 18.5 / 25.1–28.2 | 9.0 |
| fast, off | 57.3, 57.2 (55–59) | 0 | 16.3–16.4 / 16.7 | 17.5–17.7 / 25.1–25.2 | 9.0 |

- Each run switched on replaced its session once, 1.80, 1.83 and 1.85 s into
  the motion. The new session's first frame, a forced keyframe of 247, 322 and
  369 KiB (the stream's first keyframe was 280–372 KiB, the 4 s safety
  keyframes 437–772 KiB, a delta frame ~30 KiB), came out 30.2, 27.8 and
  27.5 ms after the old session's last frame: the slow state's own spacing
  just before (29.6, 29.1, 29.0 ms), so no frame waits longer than a slow one
  did. Its next 30 frames took 9.5, 9.3 and 9.0 ms (median), then ~16 ms paced
  to the capture, as a fresh session does. The second holding the swap put
  out 46–54 frames, every later one 55–59. The parameter sets were byte for
  byte the stream's first ones (one hash across 11–12 sets), so a device's
  display layer has nothing to flush.
- Motion from the start never set it off (one session in each fast run).
  "fast, on" run b's 1–2 drops a second over four seconds came with the
  loopback ping's maxima at 6–8 ms and the turnaround steady at 16 ms: the
  host, not the encoder.
- One more run switched on, with two still spells (4 s motion, 10 s still,
  15 s motion, 10 s still, 15 s motion): replaced twice, 1.8 s into each
  resumed motion and 25 s apart, keyframes of 261 and 324 KiB, 26 ms between
  frames each time, then 9.0 and 9.8 ms a frame and 55–59 fps.
- Kept, on by default: the slow state is a session's, a new session starts
  fast, and the price is one keyframe smaller than the 4 s safety one with no
  wait beyond the slow state's own.
- The checks: `run.sh slowstate` (798 checks: the rule at its edges, and
  streams in virtual time through a stand-in for the glue) and
  `mutants-slowstate` (20 of 20 caught); the encoder check's E7, the real
  `HEVCEncoder` against FakeVT (97 checks switched on, 12 off); the rest as
  before (the mailbox 38,256 and 27 of 27 mutants, the probe 19 and the hold).
  The CLI against origin/main (1f3072a), each built from `git archive`
  (dd0dc15 here), no device connected, each run's HeartBeat only its own
  sessions: `--synthetic` idle for 35 s identical masked and sorted (7 lines;
  in order too but for where the installed-apps line lands). With a loopback
  client streaming the synthetic Desktop for 22 s (origin/main four times,
  this branch six, alternating as another session's hosts allowed): no new
  kind of line, no new stats key, no "Encoder" or "TEST:" line, and one
  stream session each (nothing replaced). Which counters a second lists
  varies from run to run in both builds: with the first streaming second and
  the client's last left out, origin/main's four runs and three of this
  branch's six are identical; the other three differ by 6 and 2 mailbox drops
  in the seconds after a start that fell 80 ms before a stats tick, by one
  mailbox drop, and by `cursor.shape` in two seconds (the Mac's cursor
  changed).
- Not measured: Sill.app (the CLI only; the same core), a device (the keyframe
  over Wi-Fi, its decode), 120 fps, other bitrates, a shared engine (a new
  session there should be judged no faster and kept: the checks only), a size
  the engine is slow at (never replaced: the checks only; since the review
  fixes, one hardware run at 6880×2880, below), other chips, other content
  than the scrolling window.
- Merged with main at 32d532b (2026-09-26; one merge commit, not a rebase):
  since 4fe37d4 main gained remote access (#13), encoder-recovery itself
  (#11), follow-best-path (#12, #16), App Store readiness (#14), the public
  README (#15) and GitHub Actions (#17). Git stopped only on CLAUDE.md and
  README.md; the sources merged by themselves (this branch changed only a
  comment in `StreamCoordinator`, which main also changed). README.md is
  main's, the public front page; this branch's slow-stream bullet and its
  Resolution note moved to `docs/DEVELOPMENT.md`, "What to try if it's
  slow", as the Public README entry asks. CLAUDE.md keeps main's newer copy
  of "The hardware encoder: busy, not stuck", with this branch's sentence on
  the Simulator panel in its operational rule, and these two sections moved
  from after it to just before it; the Layout and Build and run keep both
  sides.
- Review fixes (2026-09-26, after the merge; 78f0459, d1d673c, 5217f55,
  0138d6a):
  - The order at the swap: `submit` completes the old session before the new
    one's first frame goes in ("The swap" above). The review found the old
    session's last delta reaching `onEncoded` after the new keyframe whenever
    its callback thread was held about as long as the keyframe took: with
    FakeVT, and on this Mac's hardware with the handler held on purpose (at
    20 ms and more at 1280×800, 40 ms and more at 3024×1964); a Mac decoder
    given that order failed every frame until the next keyframe. With the
    wait the order held 8 of 8 on the hardware, the wait ending 0.07–0.13 ms
    after the handler. E7 now holds the old session's handlers 20 and 40 ms:
    the order holds, and a copy without the wait fails at both, 3 runs of 3.
  - The rule ("The rule" above): slow against the session's own fastest
    frame, no faster against the session replaced, only frames in motion
    timed, the input per second as documented. The review's hardware runs of
    62f2c16: at 6880×2880 and 60 fps (the Desktop of a 3440×1440 display at
    scale 2; 24.65 ms at best, 25.5 at the median) the session was replaced
    2.02 s in for nothing in both runs (a keyframe, a 52–59 ms wait, "no
    faster"); at 3024×1964, with the motion stopping at the swap and 4
    repaints a second after, the new session was judged "no faster" on sparse
    frames (29–30 ms from 0.56 s on) though it ran 15 ms a frame once motion
    came back, and the stream then stayed at 34 fps for good. The review
    suggested twice the fastest frame; it is 1.5, since the slow state is only
    1.8 times the paced fast state (29 ms against 16), and a session whose
    best frames came paced or sparse would never be replaced at twice.
  - The mailbox and slow-state checks moved to `Tests/checks`
    (`encoder-mailbox`, `encoder-slowstate`), which CI runs, their mutants in
    its mutants matrix; `Scripts/encoder-check/run.sh` runs them as before,
    with the real-time probe and encoder checks, which stay out of CI.
  - Verified (2026-09-26, 00:20–01:03), without the hardware: the mailbox
    check 38,256 and 27 of 27 mutants; the probe check 19 and the hold; the
    encoder check with FakeVT 111 switched on and 12 off; the slow-state check
    1,207 (798 before; 62f2c16's rule fails 77 of the new cases) and 29 of 29
    mutants; `Tests/checks/run-all.sh`, all eleven (112 s); a clean `swift
    build -c release` of 0138d6a from `git archive` (only the CaptureProbe
    warning). With the hardware, no device connected (the guard before, every
    2 s during and after each run) and each run's HeartBeat listing only its
    own sessions: the CLI against origin/main (32d532b), both from `git
    archive`, idle 35 s identical masked and sorted (7 lines), and with a
    loopback client streaming the synthetic Desktop for 22 s identical (40
    lines; nothing replaced). The harness with 0138d6a's `HEVCEncoder` and
    synthetic moving bars: the review's schedule at 3024×1964 and 40 Mbps (3 s
    motion, 6 s of a frame every 0.3 s, motion until the swap, 3 s at 4 frames
    a second, 3 s motion, 6 s at one every 0.3 s, 7 s motion) swapped 1.77 s
    into the motion and said at once "… and the picture went still before it
    could be timed."; the motion after ran 15.1 ms a frame (56 fps); after the
    second still spell 29 ms for 2 s, then a second swap 13.78 s after the
    first ("a new session takes 9 ms") and 59–61 fps. At 6880×2880 and 15
    Mbps, 12 s of motion from the start: no replace (24.64 ms at best, 32.8 at
    the median, the engine slowing to ~33 ms after about 4.5 s, as the review
    saw).
  - Not measured: the order fix or the new rule in Sill.app or SillHost with
    ScreenCaptureKit and real content, the iPad's decoder at a swap, other
    sizes, rates and bitrates.
- **Untested, for Noah:** stream the Retina Desktop from Sill.app to the iPad,
  leave the screen still for a few seconds, then scroll: about 2 s into the
  scroll the log shows one "Encoder (hardware HEVC …): frames took 29 ms each
  …; a new session takes 9 ms …" line and `enc.out` climbs back to
  `cap.complete` with no `enc.mailboxDrop`; on the iPad the picture does not
  flash or go black at that moment and the frame age does not jump. A scroll
  that stops about 2 s in, as that line would come, gives "… the picture went
  still before it could be timed." instead, and the next scroll after a still
  spell gets another new session. Beside the Simulator panel (another app
  encoding), at most one "no faster" line per stream.

**The hardware encoder: busy, not stuck (2026-09-24; fixed 2026-09-25, branch
`encoder-recovery` from main at 76366e8, with main at ba91136 merged in: the
bullet before the last).** Sill.app's watchdog fired twice on 2026-09-24 and
both times the host stayed on the software encoder until it relaunched, which
was Noah's poor frame rate (~3 h at 1512×982, 46–55 fps with motion, 6–46 fps
at the end, through 18 settings changes the fallback's caps made useless). The
kernel's AppleAVE2 log (every hardware session's open with its size, bitrate
and firmware "Priority", and a HeartBeat every 5 s listing each session's
frames submitted | completed) shows neither was a wedge:
- 19:00:21 (40 Mbps, the Retina desktop at 60 fps, a 61 s old session): the
  iOS Simulator's screen recorder (SimRenderServer, what `simctl io
  recordVideo` drives: H.264 2064×2752 of the iPad Pro 13" simulator, 38 Mbps,
  priority 80) shared the one encoder engine with Sill and an agent's `SillHost
  --synthetic` (both priority 0). Sill fell to 7–8 fps, then its frame waited
  ~8.6 s; the invalidate blocked 7.06 s, off-thread, and the frame completed
  0.3 s after the other SillHost process died. A fresh 256×256 probe answered
  within 270 ms with the recorder still running, while the next stream-size
  sessions stalled again (0.3–9.5 s).
- 23:30:04 (150 Mbps, a 36 s old session, running 57–58 fps alone): the
  recorder opened a session at 23:29:45.2 and Sill fell from 58 to 22 fps in
  that second, then ran 13–45 fps; a frame waited ~1.8 s and completed (the
  invalidate took 0.17 s). A near miss at 23:27:54 (57 → 2–34 fps) came from
  the same recorder. The render and the benchmarks named at the time ran later.
- 424 hardware HEVC sessions from 17:40 to 02:30: 47 overlapped a recorder
  session and 7 of those stalled (median 39 fps); the other 377 had no stall
  (median 60), including a priority-0 H.264 2064×2752 benchmark beside HEVC
  3024×1968 at 40–150 Mbps (both 28–46 fps, a fair share). Ruled out: the
  bitrate (hang 1 was at 40 Mbps), 120 fps (both at 60), session churn (22
  bitrate restarts ran clean) and invalidating with a frame inside (both
  frames completed). No "Frame POC timed out" line, the 2026-09-22 signature,
  anywhere in the period (the log store no longer has 09-22's AppleAVE2 lines).
- Priorities, measured with one 256×256 frame per configuration: real-time
  HEVC and H.264 0, not real-time 0, `EnableLowLatencyRateControl` 60 (RCMode
  20), the recorder 80. No public key sets it. One engine on this M2 Pro:
  unthrottled HEVC 3024×1968 runs ~105–115 fps (~650 MP/s), so the Retina
  desktop at 60 fps takes 55–65 % of it and any other encode costs Sill frames
  without a hang (a 3024×1904 test beside Noah's 1512×982 desktop: both at
  57–60 fps for ~4 s, then both at ~50, 2026-09-25). A Retina desktop at 120 fps
  (~713 MP/s) exceeds it alone (untested).
- A bitrate change still needs a new session (measured 2026-09-25, 1512×948 at
  60 fps, blocky noise): VideoToolbox takes AverageBitRate and DataRateLimits
  on a live session and reads them back, but the hardware HEVC rate control
  does not follow: raised 8 → 40 Mbps the output stayed at 9.6 Mbps for 5 s,
  across an IDR and a forced keyframe (a session made at 40: 28 Mbps); lowered
  40 → 8 it dropped 41 of the next 60 frames. Hardware H.264 the same. The
  software encoder follows (7.9 → 19.5 Mbps in 2 s) and so does low-latency
  rate control (8 → 38 Mbps within 1 s). `restartNeeded` keeps the bitrate.
- `VTCompressionSessionInvalidate` waits for a frame still inside (17 ms for a
  3024×1898 frame in flight, whose output handler runs first).

What the host does now:
- The fallback is temporary. `enterSoftwareFallback` (a hardware hang, or the
  launch probe) says "… (busy or stuck); switching to the software encoder,
  capturing at 1x, until the hardware keeps up again (next check in 30 s)." While a
  device is connected (an idle host opens no session; the task ends with the
  last device) `recheckLoop` tests the hardware at the size the stream would
  have on it (the running one's at full scale, else the Desktop's):
  `EncoderProbe.throughput` sends a moving pattern through a quiet session (no
  line, no counter: the stats line's `enc.out` is the menu's fps), one frame
  at a time like a stream, on a user-initiated GCD thread, and measures the
  rate the last 7 of 10 frames come back at; its 3 frames are drawn before
  the session opens and reused, and the first pass over them is left out
  (~110 ms at 3024×1904 when the engine is free, ~120 fps; ~290 ms at
  6016×3384, ~39 fps). At the rate a return needs or more
  (`EncoderProbe.returnBar`: 0.75 of the stream's rate, 60 at most, the
  software encoder's cap, so 45 fps; but never more than 0.75 of what the
  engine does alone at the test's size, from the best pixel rate any test
  measured this run, 400 MP/s until one has) `hardwareIsBack` waits out a
  switch, clears the flag and restarts a running stream on the hardware, like
  a settings change (no focus change): "Hardware encoder is back (121 fps at
  3024×1896 in a test, 45 needed); restarting the stream on it." (or "the
  next stream uses it"). Slower: "Hardware encoder answers but is busy (8 fps
  at 3024×1896 in a test, under the 45 fps a return needs; another app is
  using it); next check in 60 s". No frame in 1 s: "Hardware encoder still
  not answering after N ms; next check in 60 s". Either doubles the interval,
  up to 300 s; so does a hang within 5 min of a return; a return that lasted
  10 min resets it to 30 s. The first device after none gets a check at once
  when the last is 30 s old, so its stream starts on the hardware (a software
  start ~20 ms before is replaced). A hang reported by an encoder no newer
  than the last return (`HEVCEncoder.serial`) is stale and ignored. One loop
  and one test at a time: `stopRecheck` only cancels, and the task clears
  `recheckTask` once its loop has ended, so a device that connects during a
  test gets no second loop beside it (the ending task's tail starts one); a
  test that ends with no device left is dropped without a line or a backoff.
- Why a rate at the stream's size and not one small frame: at 03:26 on
  2026-09-25, with another agent's Simulator recording (priority 80) and a
  second SillHost on the engine, a 256×256 frame answered in 72 ms, the
  stream went back to the hardware and ran at 12 fps there (it had run at ~57
  on the software encoder), and no watchdog fires for a slow stream. Noah's
  own Sill.app sat at 8–18 fps in the same minutes, and at 03:32:02 it fell
  back once more (16, then 2 fps, then the watchdog), which the old build
  keeps until it relaunches.
- Why the bar follows the size (review, 2026-09-25): a fixed 45 fps asked more
  than a free engine gives a large frame. Measured with the engine free (Noah's
  Sill.app on the software encoder), as the probe was (frames drawn inside the
  timing, utility QoS) and as it is: 6016×3384, a Retina 6K Desktop, 37 and
  39 fps; 5120×2880 50 and 53; 3024×1904 115 and 121. So a host streaming a 6K
  Desktop read "busy" at every check and stayed on the software encoder for
  good. Now the first check there needs 15 fps (400 MP/s assumed) and, learned
  from its test, the next 29; a starved session got a sixth of the free rate
  or less, so busy still reads busy.
- The session given up on reports on its way out: "Encoder (hardware HEVC
  3024×1898): the stalled frame came back after 3.0 s; the encoder was busy,
  not stuck." A stuck one never lets go, so it never prints.
- Probes whose frame never comes back each hold a blocked thread; with 8 out
  (`maxStuckProbes`, after 22–28 min of failed checks) the re-check stops
  probing and says once that the encoder is stuck and a restart of the Mac
  fixes it, and the menu shows "Hardware Encoder Stuck". A late frame counts
  out again (`EncoderProbe.onStalledProbeBack`): under 8, the host says "a
  check's frame came back after N s, so it is not stuck; checks resume",
  clears the menu's line at once (a device connected or not) and, with a
  device connected, checks at once instead of when the held-back loop wakes
  (300 s).
- Copy: the menu's "Hardware Encoder Busy — Streaming with the software
  encoder, up to 60 fps, until it is free again." (one line, 373 pt: a menu
  item's subtitle does not wrap, the old one was 422 pt) or "Hardware Encoder
  Stuck — … Restarting the Mac fixes this."; the Streaming pane says the same
  at length; `HostSettingsState.softwareEncoder`'s doc. The device's callout
  says "‹Mac›’s hardware encoder is busy or not responding, so for now streams
  run at up to 60 fps at Standard." (it said "until the Mac restarts"; it
  promises neither now, as hosts before this change keep the fallback until
  they relaunch), and goes away by itself when the host clears the flag.
- Test hooks, read once and inert without them: `SILL_TEST_ENCODER_HANG=N`
  (the first N hardware stream sessions hold frame 90 for 3 s before it goes
  in: a busy engine; it prints a "TEST:" line), `SILL_TEST_PROBE_HOLD=S` (every
  frame of every probe waits S s: 0.08 a starved engine, 2 a busy one, a huge
  S a stuck one), `SILL_TEST_RECHECK_SECONDS=N` (intervals N to 10 N instead
  of 30 to 300) and `SILL_TEST_PROBE_SIZE=WxH` (the re-check tests that size,
  as for a Retina 5K or 6K Desktop on a smaller screen).
- Diagnosis: `/usr/bin/log show --start '2026-09-24 18:55' --end '2026-09-24
  19:05' --style compact --predicate 'sender == "AppleAVE2" AND (eventMessage
  CONTAINS "HeartBeat" OR eventMessage CONTAINS "Resolution:" OR eventMessage
  CONTAINS "AVE : open" OR eventMessage CONTAINS "AVE : close")'` (a session
  whose completed count stops while its submitted one is ahead is starved;
  "Priority: 80" beside it is the recorder), plus `process ==
  "VTEncoderXPCService" AND eventMessage CONTAINS "videoencoder.peer"` to map
  sessions (the next "AVE : open") to client PIDs.
- Operational rule, from the same logs: while Noah streams, agents do not run
  `simctl io recordVideo`, SillHost streams, ReelRenderer or encoder benchmarks;
  each shares the one engine, and the recorder outranks Sill. The Claude app's
  iOS Simulator panel counts too: `claude-ios-sim` encodes the simulator's
  screen at priority 60 (~62 fps at 2064×2752), and Noah's Retina Desktop fell
  from 57 to 33–36 fps beside it (33–34 for its first 40 s), and to 11–18 fps
  while another agent's priority-80 recording of that simulator ran as well
  (8–17 with a SillHost besides; 2026-09-25, 15:14–15:24).
- Not in this change: `EnableLowLatencyRateControl` would put Sill at priority
  60 (above every default session, still below the recorder's 80) and follows
  live bitrate changes, but it changes the bitstream and rate control (frames
  dropped at 8 Mbps in the rate test): a flagged experiment with iPad tests.
Verified headless (the synthetic host; hardware runs kept to seconds, Noah's
Sill.app streaming beside them): clean build (only the old CaptureProbe
warning); the CLI against 76366e8 built from `git archive`, masked and
sorted: idle identical, and with a client and a bitrate change identical but
for `enc.mailboxDrop` counts, which follow the other encoder users of the
moment (either build had them); `SILL_TEST_ENCODER_HANG=1` with a client: the
hang at 1.5 s, the fallback, 1512×948, "came back after 3.0 s", back 30.0 s
later (114 fps in the test) and 3024×1898 on the hardware at 60 fps for 67 s,
the client getting frames every second but the hang's; `=2`, while another
agent's Simulator recording and SillHost came and went: the check at 30 s
"busy (25 fps …); next check in 60 s", back 60 s later at 114 fps, the
second hang 3 s after the return and "next check in 120 s"; with
`SILL_TEST_PROBE_HOLD=0.08` while the recorder and another SillHost really
shared the engine (the test's own hardware stream ran at 16 fps): "busy
(7 fps …)" at 30 s and "(8 fps …)" 60 s later, no return; the client leaving
during a fallback: no session from the host in the kernel log for 40–45 s
(the next check was due after 30), then a client again: the test at the
Desktop's size (112 fps) and back ~100 ms after its stream started on the
software encoder; `SILL_TEST_PROBE_HOLD=100000 SILL_TEST_RECHECK_SECONDS=1`
with a client picking nothing: the launch fallback, then checks 1, 2, 4, 8,
10, 10 and 10 s apart, all unanswered, and the stuck line after the 8th
unanswered probe (the launch one and 7 checks); `SILL_TEST_PROBE_HOLD=2`:
unanswered probes, each back 2 s later, never stuck; previews against
76366e8: only menu.txt (the copy and a new `software-encoder-stuck` sample,
its cards equal to the busy one's) and the General pane's "Running from" path
differ.
Review fixes (2026-09-25), verified headless: the host builds with no warning,
iOS Debug with only the old `StreamClient` one; `returnBar` checked on its own
(swiftc, 100,011 checks: 45 at Retina laptop sizes, also at 120 fps, 15 and 29
at 6K, a free engine always passes, always the lower of the two shares), four
mutants caught (the fixed 45, the engine term without its share, no 60 fps
cap, an assumed rate above this engine); the CLI against 76366e8 (`git
archive`), masked and sorted: idle identical, with a client and a bitrate
change identical (a first pair differed by one `enc.mailboxDrop` in the
base's first second); `SILL_TEST_ENCODER_HANG=1`: back 30.1 s after the
fallback ("121 fps at 3024×1896 in a test, 45 needed"), the client getting
frames every second but the hang's (40–57 fps on the software encoder, 60 on
the hardware); `=2` with `SILL_TEST_PROBE_SIZE=6016x3384
SILL_TEST_RECHECK_SECONDS=5`: "39 fps at 6016×3384 in a test, 15 needed", the
second hang and "next check in 10 s", then "39 fps …, 29 needed"; the
verifier's overlap run (`SILL_TEST_PROBE_HOLD=1000
SILL_TEST_RECHECK_SECONDS=4`, a device leaving during a test and another
arriving): one line, "next check in 8 s" (it was two, 8 then 16 s), none when
nobody comes back, and the second device's own check 8 s later;
`SILL_TEST_PROBE_HOLD=70 SILL_TEST_RECHECK_SECONDS=1`: the stuck line at
65.0 s, the launch probe's frame back at 70.2 s, "a check's frame came back
after 70.0 s, so it is not stuck; checks resume" and a check at once; with
the device gone by then, the same line at 70.2 s and the next device checked
the moment it connected.
- Merged with main at ba91136 (2026-09-25: PR #13, remote access; one merge
  commit, not a rebase). Git stopped only on `Scripts/sillclient.py`, and both
  sides stay: main's remote-door flags and LINK line, this branch's `kB=` each
  second. Checked by hand in every file both sides changed: `StreamCoordinator`
  has main's routes, kind 21, the kind 17 cap, Sill's own windows kept off the
  Desktop and the goodbye at quit beside the fallback and the re-check; the
  re-check runs while any device is connected, at home or through the remote
  door (both register in `StreamServer.clients`, which `onClientCountChanged`
  counts), and a return restarts the stream through `select` like any other
  restart (`switching` is set before main's new wait for Sill's own app). The
  menu lists the encoder's item (Busy or Stuck) before main's "Remote Access
  Can’t Start"; `HostStatus`, `HostSettings.swift` (the `softwareEncoder` doc
  beside the seven presets), `SettingsPanes`, `DebugHooks` (both sides'
  samples), README and the device's panel (this branch's callout beside main's
  route line and slow-link callout) keep both sides' changes. Verified: a clean
  `swift build -c release` (only the CaptureProbe warning); iOS Debug for the
  simulator and for a device (generic, signed, not installed; only the
  StreamClient capture warning); `make-app.sh` without `--install`; the
  return-bar check on the merged `EncoderProbe`, 100,011 checks, its four
  mutants caught; previews from the bundle against main's (built from `git
  archive`, both run from one path): identical but menu.txt (Busy for Not
  Responding, and the `software-encoder-stuck` sample) and that sample's two
  cards, equal to the busy one's. Not run at the merge: the CLI's output
  against main's (idle 35 s and a Desktop pick, masked and sorted) and the
  `SILL_TEST_ENCODER_HANG=1` run (the fallback, the stalled-frame line, the
  return ~30 s later), both kept off the hardware encoder because Noah's iPad
  was streaming from Sill.app the whole time.
- **Untested, for Noah:** a build of this branch in /Applications
  (`Scripts/make-app.sh --install --open` from this branch, which now carries
  remote access too, or from main, which has it since b50e224; only a new
  build comes back by itself). Then, with the iPad streaming the Desktop,
  `xcrun simctl io booted recordVideo /tmp/x.mov` on a booted iPad Pro 13"
  simulator: the frame rate drops, and within a minute or so "switching to the
  software encoder" and "the stalled frame came back" (the menu: "Hardware
  Encoder Busy"); while it records, "answers but is busy" at each check, 30,
  60, 120 s apart; stop the recording (Ctrl-C) and at the next check "Hardware
  encoder is back" and the full resolution on the iPad. Also a window stream
  and the virtual display through a return, and a 120 fps stream (the test
  asks for 45 fps at its size). On a Mac with a Retina 5K or 6K display, a
  return while the Desktop streams ("… in a test, N needed", N under 45 at
  6K). New with the merge: the iPad through the remote door (Tailscale) through
  a fallback and a return, the re-check running for it as for a device at home.

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

**Remote access (2026-09-24/25, branch `remote-access` from `a9cc248`; the plan,
its open questions and the results are in `docs/remote-access-plan.md`).** Bring
your own VPN (Tailscale, WireGuard into the home network) or, behind a switch
of its own, a port forward: a device paired once reaches the Mac from anywhere.
Every open question took its default. Steps 1–8 are committed, and so are the
fixes of step 9's first review round (below); the branch merged as PR #13
(ba91136), with its merge and review in the entry above.
- Two doors. The home door (today's plain TCP listener, Bonjour, unchanged for
  old iOS builds) now admits only this Mac's own networks, loopback and Direct
  Wireless (`OriginPolicy`), with caps (1 MiB messages, 4 kind-17 changes a
  second, a clean device name). The remote door (`RemoteServer`, port 7455) is
  TLS 1.3 only, both ends self-signed P-256 keys pinned by SPKI SHA-256, ALPN
  `sill/1` for a paired key, `sill-pair/1` only while a pairing window is
  open; pre-auth caps (8 pending, 2 per source, backoff after 5 of its own
  refusals), 8 sessions, remote clients evicted after 8 s of silence, forced
  keyframes at least 2 s apart. Kinds 18 (the signed MacInfo: Mac ID, name,
  addresses), 19/20 (one pairing request and its answer), 21 (Pair This iPad…,
  home door only) and 22 (goodbye) are skipped by older readers; the TXT record
  carries a recognition tag (`r`) only paired devices can read.
- Pairing: the Mac's window shows a QR code (`sill://pair?…`, pinned to the
  Mac's key) and a 12-digit code (Damm check digit; PBKDF2 600k), 5 minutes,
  single use, five wrong tries, and the address to type with the code:
  Tailscale's MagicDNS name and its IPv4 under it ("or 100.101.102.103"), else a
  Tailscale IP (100.64/10, else fd7a:115c:a1e0::/48), else this network's
  address with any other VPN's IP under it ("or 10.8.0.6"). Another VPN never
  takes this network's place, since NordVPN's or WARP's address answers from
  nowhere; which of the two goes first is Noah's call. `PairingWindowAddress`
  decides, pure (Noah, 2026-09-25: from an iPhone's hotspot this network's
  address answered nothing, the Tailscale name and address both paired;
  checked with swiftc, 80 checks and 35 of 35 mutants, and photographed as the
  previews' `pairing-novpn`, `pairing-othervpn` and `pairing-longname`).
  Sill.app: Settings › Remote Access (a fifth tab: the switch, the addresses,
  the port, paired devices, the internet switch with the router's answer, the
  address name, sleep), the menu's Remote Access… and Pair iPhone or iPad…,
  identity in the login keychain (`KeychainIdentityStore`; label "Sill Remote
  Access", service `me.saffer.sill.remote`), idle sleep held off while a
  device is connected remotely. The CLI's `--remote` uses a throwaway identity
  per run.
- iOS: `DeviceIdentity` (a Keychain key, this device only), `SavedMacs`,
  `RemoteDialPolicy` + `RemoteConnector` (the dial order, happy-eyeballs 1 s
  apart, every failure's words), Remote rows after the network's 3 s, the
  reconnect order after a loss, liveness on every route; the connect screen's
  "Add a Mac…" card (the VisionKit scanner or the typed address and code),
  `sill://pair` links only ever confirmed, Pair This iPad… as an overlay over
  the stream, the panel's route line ("Connected through Tailscale · 48 ms"),
  its Away from home group and the slow-link callout; the Low preset (4 Mbps,
  first of the seven on both sides) and 60 fps away from home.
- Verified without Noah's devices: the plan's H1–H24 headless (the CLI's
  output byte for byte, the pure checks with mutants, the doors' refusals and
  caps, no plaintext on the wire, no code or secret in any log, a 2 Mbps
  +150 ms relay with no eviction and the base's keyframe rate), the app's
  persistence and previews, and on the simulator S1–S8: about 200 photos at
  the Duo sizes, phones and larger text, taps and accessibility as XCUITests,
  live pairing (QR, typed, an outside link confirmed first), reconnects,
  every failure's words, an older host, and a slow link (60 fps through a VPN
  route; the callout at +300 ms).
- Review fixes (step 9, the plan's "Review fixes (step 9)"): a pick never
  streams Sill's own windows (the virtual display's lookup skips them; the
  Desktop looks for Sill among every window when the on-screen look missed it);
  the internet switch counts only while Remote Access is on; Remove changes
  nothing when the keychain cannot be written, and the pane says so; a spent
  code shows no QR; kind 18 lists no addresses before the Mac's first look,
  and a device keeps its saved ones on an empty or Remote-Access-off kind 18;
  an overlay pairing ties the session only to the same Mac (by its signed kind
  18) and takes that kind 18's addresses; the scanner never restarts a pairing
  by itself (after a failure, the same code only from a tap); a link confirmed
  over the stream keeps the overlay for its outcome; the overlay's typed path
  says "Enter the Code from ‹Mac›" and moves up while typing; the status line
  is announced; saved Macs are cleared only when no device key exists at all.
  Checked headless, on the simulator with three new XCUITests against live
  hosts, and against the pre-fix build (which fails them).
- **Untested, for Noah (R0–R13; the plan's Results say exactly what):** R0 the
  probes (the Secure Enclave key, the login keychain identity with your OK, the
  router probe, the scanner on the iPad, with a failed pairing's code held
  until tapped); R1 Tailscale setup and pairing,
  timed; R2 away on the hotspot; R3 leaving home mid-stream; R4 Wi‑Fi to
  cellular; R5 Tailscale off at either end; R6 sleep; R7 removing the iPad
  while it streams; R8 a rebuild keeps port, Mac ID and pairing; R9 Pair This
  iPad… at home; R10 the port forward; R11 Direct Wireless at the café; R12
  VoiceOver and a hardware keyboard (Esc never reaches an app in the iPadOS 27
  simulator; only ⌘. was tested); R13 mixed builds. Also the pairing window's
  Address row, live (only its offscreen previews were seen): with this build's
  Sill.app, Pair iPhone or iPad… reads this Mac's MagicDNS name with "or" and
  its Tailscale IPv4 muted under it (what `SillHost --print-reachability`
  lists); with the window open, Tailscale off on the Mac gives 10.128.0.34
  alone and a window 18 pt shorter, and back on the name and the "or" line
  return (the IPv4 alone for a few seconds, until MagicDNS answers, is
  expected; note it if it stays); each line selects without "or" and pastes
  (Universal Clipboard) or types into Enter Code Instead (a code works once:
  New Code, or reopen the window, for a second try); VoiceOver reads the "or"
  line as one element. And a decision: beside a VPN that is not
  Tailscale (NordVPN, WARP, a work VPN, your own WireGuard) the window shows
  this network's address with that VPN's IP under it; the other order, or
  this network's address alone, is one line in `PairingWindowAddress.choose`.
- Known: the simulator iPad Pro 13" is shared with other work, so a test that
  installs the app there can replace someone else's build (the iPad Pro 11"
  was used for S8); an unsigned simulator build cannot use the keychain on a
  fresh simulator (-34018): build it ad hoc signed (`CODE_SIGN_IDENTITY=-`).

**Quality presets (2026-09-24, branch `quality-presets` from main at
ad7fba2).** Noah's decisions: Maximum is renamed Pro; two presets above it,
Ultra (80 Mbps) and Extreme (150 Mbps), for the USB cable or very fast Wi-Fi;
the bitrate knob's cap goes from 100 to 200 Mbps per 60 fps (a 120 fps stream
still gets double, so Extreme at 120 fps is 300 Mbps); no Unlimited.
- `QualityPreset` (StreamProtocol's HostSettings.swift): Efficient 8,
  Balanced 15, High 25, Pro 40, Ultra 80, Extreme 150 Mbps per 60 fps,
  declared in ascending order, which is the order of the status menu's Quality
  submenu, Settings › Streaming and the device's Quality menu (all build from
  `allCases`). The raw values are the bitrates, so the rename changes nothing
  stored or sent: a Mac on 40 Mbps shows Pro. `QualityPreset.fastLinkNote` is
  the one sentence both ends add to their Quality footers ("Ultra and Extreme
  need the USB cable or very fast Wi-Fi; if the picture lags, step down."); the
  menu's Quality subtitle is unchanged.
- `HostConfig.validated()` clamps to 1–200 Mbps, so a launch argument or a
  hand-set default above that runs at 200 ("Custom — 200 Mbps"). A device still
  sets only presets: `DeviceSettings.accepted` checks `SettingsChoices`, which
  follows the presets, so it takes 80 and 150 unchanged, and refuses 200 or
  250 from a test client rather than clamping them. Kinds 16/17 unchanged.
- Mixed builds: a host from before this change refuses Ultra and Extreme from
  a newer device (the row goes back; VoiceOver hears "‹Mac› kept its
  setting"); an older device shows a newer Mac's 80 or 150 Mbps as "Custom —
  N Mbps", read-only, and 40 as "Maximum — 40 Mbps".
- Verified without a device: clean builds (only the old CaptureProbe and
  `StreamClient` warnings); the CLI's synthetic output, idle and with a client,
  equals ad7fba2's (masked and sorted; unmasked only timings and ports
  differ); a test client's Extreme then Ultra restart the stream at 150 and 80
  Mbps ("Settings from sillclient: bitrate 15 → 150 Mbps per 60 fps"), Extreme
  at 120 fps runs at 300 Mbps, and 200 and 250 Mbps are refused with the value
  unchanged in the answer; the bare app runs `-SillSetAfter` and `-bitrate`
  250 Mbps at 200 ("Settings: bitrate 15 → 200 Mbps per 60 fps", devices told
  200) and saves a device's Extreme across a relaunch; the hardware encoder
  takes and reads back AverageBitRate up to 400 Mbps at 3024×1898; previews
  against ad7fba2 differ only in menu.txt's Quality rows and the Streaming
  pane's footer; the ledger check (H2) with the six raw values and 5,000
  random runs; the panel in the simulator at 1000×710 and 500×710 (also at
  xxLarge text), menu open and closed, picking Extreme, and live against this
  host (a restart at 150 Mbps) and against ad7fba2's (refused, back to
  Balanced); the harness's `vdstream` case, now Extreme at 120 fps (300 Mbps,
  the longest readout), at all four sizes and at xLarge and xxLarge text: the
  readout wraps at xxLarge, and at 710×500 already at xLarge; the header and
  Disconnect stay put and the rows scroll.
- **Untested, for Noah:** Ultra and Extreme on the iPad over the USB cable and
  over Wi-Fi, streaming a busy window (the synthetic pattern compresses to
  under 1 Mbps whatever the target): watch the frame age in the host's
  `client …` lines and the menu's device row, and step down if it climbs.

**Direct Wireless Connection (2026-09-24, branch `direct-wireless` from
`ipad-host-settings` at 35a1238; the plan and its measurements are in
`docs/direct-wireless-plan.md`).** Noah's decision: AWDL off by default on both
ends, and an opt-in host setting named Direct Wireless Connection in the Mac's
Settings and menu and in the device's panel. `includePeerToPeer` on the host's
NWListener made its Bonjour registration include AWDL, which the kernel counts
as an AWDL service ("Enabling AWDL due to Mdns"); the Mac's one radio then left
its Wi-Fi channel up to ~97 ms every 524 ms (see the trackpad-stutter section).
- Wire: `StreamSettings.directWireless` and `HostSettingsChange.directWireless`,
  optional: nil is a host without the setting, which gets no row, and the
  device ledger's rule 9 never sends a field the host did not report. Kinds
  16/17 stay compatible both ways (old device: ignores the key; old host: the
  device sees nil).
- Host: `HostConfig.directWireless`, off in `standard` (the CLI and a fresh or
  updated Sill.app), accepted from a device on every host (since 2026-10-29 only
  from a paired session at home: the Current step's "Direct Wireless only from a
  paired device"), and absent from `restartNeeded`: it is the listener's.
  `StreamServer` builds the listener
  with `makeListener(peerToPeer:port:)`, with the setting when it is given
  before `start()`; after that `setPeerToPeer` replaces the listener live on
  its queue: cancel, wait for `.cancelled`, bind the same port at once with no
  service, advertise 1.5 s later (re-registering the same name within
  milliseconds of dropping an AWDL registration orphaned the awdl0 record for
  minutes; 0.25 s and more never did). Accepted connections are independent of
  the listener, so streaming devices never notice; one line per applied change
  ("Direct wireless on: listening on port P again, advertised again."). Except
  when it turns off: once that replacement is advertised (or has failed for
  good), every device still on peer-to-peer Wi-Fi is disconnected, one line
  each ("Direct wireless off: disconnecting iPad (…) at fe80::…%awdl0.N, which
  was connected over peer-to-peer Wi-Fi; it can reconnect over the network."),
  because an open awdl0 socket keeps the kernel's AWDL up (Noah's sessions,
  2026-09-24: off changed nothing while the iPad was on awdl0). `ClientLink`
  reads the route from the endpoint's scope (`%awdl0`/`%llw0`; AWDL has only
  link-local addresses); other clients are untouched, and a burst that ends on
  disconnects nobody. Requests coalesce (newest wins), and late callbacks of a
  replaced listener are inert. No `.cancelled` within 1 s or the same port
  refused: any port, with a line; both refused: the existing listener-failure
  rule (the app shows "Not Visible on the Network" and keeps running, the CLI
  exits 1), and the next toggle retries. CLI: `--direct-wireless` prints one
  startup line; without it the output is the branch point's byte for byte
  (masked and sorted).
- Sill.app: Settings › General "Direct wireless connection" right after
  "Visible on your network as", and a "Direct Wireless Connection" item at the
  top of the status menu's second group, absolute like Virtual Display. Saved
  under `directWireless`; an existing install has no key, so it comes up off.
  The status menu's card ends each device's row in how it reaches this Mac
  (Noah, 2026-09-24, branch `connection-route-in-settings`: "next to bitrate"),
  and while exactly one device is connected the source row too, after the Mbps:
  "Wired" (the cable's anri0, or any wired Ethernet interface), "Wi-Fi" or
  "Direct" (awdl0, llw0), else no word (loopback, a VPN, a path that says two
  things). `ClientLink.route` reads this Mac's side of the device's own
  connection, by the witnesses `runsPeerToPeer` uses (so Direct is exactly what
  turning Direct Wireless off disconnects): the address's scope, typed by the
  address itself, else the path's interfaces when they all agree (a connection
  to this Mac's own address lists en0 and lo0: no word). Read when the client is
  ready and on each path update, shown only (`HostStatusSnapshot.Device.route`);
  no wire change. Each end names its own link, so an iPad on Wi-Fi streaming
  from a Mac on Ethernet says "Wi-Fi" while the card says "Wired". A still
  picture's rate reads "120 fps, still", as wide as a one-digit count ("5 of
  120 fps"): "120 fps, nothing changing" (the plan's copy) plus the word
  wrapped the row only while still, and the open menu, which resizes the card
  on every change, jumped a line each time a window stopped or started
  changing. The wording is Noah's call. Over 405 layouts (three sizes, 60 and
  120 fps, 8 to 200 Mbps, each word or none, each suffix, the real StatusCard)
  a row's line count never changes between still and changing unless the
  count's own digits change it (16 layouts, all without a word; with "nothing
  changing" 198 did); the `still-window` preview is the widest case the menu
  offers. Verified: the link check at 89 (PR #6's 40 plus 49;
  `swiftc -package-name sill`), 14 mutants caught; the real host in a scratch
  package (loopback, `fe80::1%lo0` and `::1` clients: no word; with the lo0
  stand-in, Direct on the device rows and on the source row only while one is
  connected); previews: only the five cards with a device, the new
  `still-window` and their menu.txt lines differ from a1484f9; the CLI
  identical to a1484f9 (masked).
- iOS: the network browser and connections to the Macs it lists never use
  peer-to-peer. A nearby (peer-to-peer) browser runs only while not connected,
  and only when a Mac this device last saw with the setting on
  (`Sill.directWirelessMacs`, from each state, keyed by the Bonjour name the
  connection was made to, which is what the browsers list: the window list's
  "Mac" stays "Mac" when Bonjour renames a clash "Mac (2)"; a connection by
  address teaches nothing) is missing from the network 3 s after the connect
  screen began looking, or after Search Nearby (offered when nothing is listed
  after 3 s; once it runs, a muted "Also looking nearby" of the button's height
  takes the button's place whatever the status line says, VoiceOver announces
  it, and the idle status adds "and nearby" only when no hint shows); once
  started it runs until a connection is ready (`DiscoveryPolicy`, pure, checked
  with swiftc). A Mac seen only over awdl/llw is a "Direct" row, the one kind
  connected with peer-to-peer; a Mac the network lists is always a network row,
  so at home nothing takes AWDL. Each row ends in where the device sees its
  Mac (`DiscoveryPolicy.method`; Noah, 2026-09-24, branch
  `connection-method-labels`): "Wired" if the network browser saw it on a wired
  Ethernet interface, else "Wi-Fi" on a Wi-Fi one that is not peer-to-peer,
  "Direct" for a Direct row, else no word; never the Wi-Fi network's name,
  which needs the Access Wi-Fi Information entitlement and Location access,
  and Sill asks for neither. The word follows the browser as interfaces come
  and go (the cable in or out), and the DEBUG console says what it was read
  from ("discovery: <Mac>: Wired, seen on …"). A row that says "Wired" is
  dialled over the cable (Noah, 2026-09-25, branch `prefer-cable`: unpinned,
  with Wi-Fi and the cable both up, the same tap reached the Mac over `%en0`
  at 7 ms one time and over `%en14` at 1 ms another): a tap, an automatic
  reconnect and a move from AWDL resolve its Bonjour service on the first
  wired interface the browser saw it on (`DiscoveryPolicy.dialInterface`;
  anpi0 on the iPad, which the Mac logs as `%anri0`, 1–2 ms; en2 gives
  `%en14`), and a dial not ready within 2.5 s (`wiredWait`), or failing or
  waiting (at once), gives way to the row as listed, unconstrained, once,
  which can take Wi-Fi (DEBUG console: "dialing <Mac> on anpi0 (wired)",
  "wired dial did not connect in 2.5 s; dialing unconstrained";
  `-SillWiredTest HOST:PORT` runs that fallback in the simulator). The route
  is the Settings panel's (branch
  `connection-route-in-settings`): its readout ends in how this session's own
  connection reaches the Mac, "… · 15 Mbps · Wi-Fi", "Wired" or "Direct"
  (`DiscoveryPolicy.route`, `StreamClient.route`): the interface the Mac's
  address is scoped to (the cable and AWDL carry only link-local addresses),
  else the one this device's own address is on (an IPv4 connection's remote
  address has no scope), else the path's interfaces when they all agree, else
  no word (the simulator's path to its own Mac is lo0 alone). Read at
  `.ready`, again at a move's hand-over, and on those path updates of the
  session connection that describe it, satisfied and naming the Mac's IP
  address (`DiscoveryPolicy.describesFlow`, `sessionRoute`); any other update
  keeps the word. A connection to a Bonjour row also gets updates for the
  service's resolution, which name the service instead of an address and list
  "en0 (wifi), en0 (wifi)", the device's default route, whatever link carries
  the connection: on 2026-09-25, on the cable with Wi-Fi on, they turned a
  session's right "Wired" into "Wi-Fi" while its connection stayed on en2 (the
  Mac saw it on `%en14` at 1–3 ms throughout). The DEBUG console prints
  "session: <word>, read from …" and, for each update it skips, "session: kept
  <word>; ignored a path update without an address (for <service>): …".
  "Direct" there replaced the
  header's "Connected directly" line (the footer's warning and the switch's
  hint stay), and a no-break space before each "·" makes a wrap at larger
  text fall after one. The Mac's card names its own side the same way (see
  Sill.app above), so the two can differ (an iPad on Wi-Fi, a Mac on
  Ethernet). Verified: the policy check at 155 (138 plus 17 for the route),
  eight mutants of it caught; photos of the panel cases `default` (Wi-Fi),
  `wired`, `directlink` (Direct), `noroute` and `vdstream` at 1000x710 and
  500x710, and at accessibility-extra-large also at 710x500 (the readout wraps
  after a "·", never truncates, never splits "Wi-Fi"); live against a
  synthetic host: by 127.0.0.1 no word, by this Mac's `fe80::…%en0` "Wi-Fi",
  and `-SillMoveTest to:` from the first to the second gains "Wi-Fi" at the
  hand-over. What each end calls the cable (2026-09-25): iPadOS names its ends
  anpi0 and en2 and types both as wired Ethernet (the connect screen's row
  says "Wired", seen on anpi0, en2 and en0, and a session over it reads the
  Mac's address on en2); macOS names its end en14 (anri0 on other days; both
  up that night), wired Ethernet too (the simulator's browser saw both).
  The fix for the updates above, verified on the iPad: the policy check at 174
  (155 plus 19), 18 mutants caught (the route's 8 plus 10); "session: Wired,
  read from the Mac's address on en2" at `.ready` (a row resolved on en2 and
  tapped by a scratch build, and `-SillConnect` to the Mac's en14 address) and
  at a move's hand-over from awdl0, the host on `%en14` each time; a row's
  unscoped updates after
  `.ready` logged as ignored with the word kept (that session ran over Wi-Fi,
  `%en0` on the host: with Wi-Fi healthy the race took en0 in all three
  unscoped tries, and the night's cable session came right after an eviction
  on Wi-Fi). Until branch
  `follow-best-path` a session over the cable ended when it was pulled and came
  back over Wi-Fi, "Wi-Fi" on both ends, and plugged back in, an established
  Wi-Fi session stayed on Wi-Fi (TCP does not move) until the next connection;
  now it follows the cable (the step above). On
  the device, also compare each word with the host's "Client connected:
  fe80::…%anri0" line (`%anri0` or `%enN`: the cable; `%en0`: this Mac's
  Wi-Fi). Verified on the simulator: the policy check at 138, eight mutants
  caught; the `methods` and `nearby` cases at 1000x710 and 500x710; the rows'
  VoiceOver labels ("Mac Studio, Wired"); the live row for this Mac, "Wi-Fi"
  (lo0 loopback, en0 wifi). Reconnects match the name exactly ("MacBook
  Pro" and "MacBook Pro (2)" are two Macs) and take the network row at once, a
  Direct row only once it has stayed Direct for 6 s and the network last listed
  that Mac 10 s ago or more (`NetworkSightings`): a listener swap makes the
  network row blink for a few seconds, a Mac back on the shared network (Sill
  relaunched, the Mac awake) registers there and on AWDL together and the
  nearby browser can report awdl0 first, and mDNS is lost to radios that leave
  the channel. A tap is never held back. A session over AWDL moves to the
  network once the network browser (it keeps running while connected) has
  listed the same Mac for 2 s without a break: a network connection opens beside
  the direct one, and once its first window list names the same host it takes
  the session over (make before break: the Mac never drops to zero devices, so
  the stream and a staged window stay; the ledger, the Desktop rule and the
  panel's two seconds start afresh as on any connection, and the viewport goes
  out on the new one before the old closes); one that fails or has not shown its
  host in 5 s changes nothing, and the next try waits 10 s
  (`DiscoveryPolicy.moveToNetwork`, `StreamClient.moveToNetworkIfListed`). The
  same host: `WindowList.launchID`, a random ID each host launch puts in every
  window list (optional; hosts without it on both ends go by the name, as
  before), because a Bonjour name can belong to two Macs that share no link;
  a listing found to be another Mac is not tried again while it lasts
  (`sameHost`, `refusedListing`). The hand-over keeps what the device sends in
  order (`SessionLink`): the Mac never orders one connection against another,
  and a release sent on the fast one could overtake its press still in flight
  on AWDL (the button stays down, every later move drags), so the network
  connection is read at once but nothing goes out until a fence ping sent on
  the direct one after everything else comes back (the Mac echoes a ping only
  after reading all before it); messages wait in order meanwhile, one direct
  round trip, at most 3 s, or until the direct connection closes.
  On 2026-09-24 the iPad twice reconnected over AWDL at home (15:37:25,
  15:43:17) after an eviction on en0 and stayed there for minutes at rtt maxima
  ~265 ms. Local Network access denied (the network browser waits with
  PolicyDenied): the status says "To find your Mac, allow Local Network for
  Sill in Settings.", with no hint and no nearby search. The panel's last group
  is the row (never disabled), after the closing footer, with "Direct" ending
  the header's readout while this device's own connection runs over AWDL,
  and then, while the switch shows on, a warning in its footer and hint
  ("turning this off disconnects it"). The connect screen's column is anchored
  leading now, so its title no longer jumps
  sideways when a row or the hint appears; it is still centred vertically, so
  it moves up by half of what they add.
- Verified without permissions (the plan's H0–H15 and S1–S4): the kernel's
  AWDL service count (ValidSvc, baseline 2 from Noah's PR #4 Sill.app) rises by
  2 exactly for a registration made with the AWDL flag: `dns-sd -includeAWDL -R`
  and `SillHost --synthetic --direct-wireless` (test type) both 2 → 4, while
  `dns-sd -R`, the suffix form `dns-sd -R … -includeAWDL` (a TXT record, no
  flag) and the default host stay at 2; off, the test registration never
  appears on awdl0 (index 16), on it does 1.1 s after launch and leaves no
  orphan; live on and off under a streaming client: the same port throughout,
  frames every second, no restart, the awdl0 record added 2.6 s after on and
  removed 1.3 s after off; 55 connections across a replacement all accepted;
  five toggles in 0.4 s give one replacement; mixed with a bitrate change, one
  restart and one replacement; the fallbacks (SILL_TEST_SWAP_FAIL); the bare
  app saves it from -SillSetAfter and from a device and relaunches with it on;
  previews: only the General pane and menu.txt changed (one unchecked item per
  sample); the ledger check (43 checks, 5,000 random runs, 1,227 against a host
  without the field, three mutants caught) and the policy check (40); iOS
  Debug and Release with only the old warning; photos of the connect screen
  (looking, hint, nearby) and the panel (default, direct, directlink,
  nodirect, cli; scrolled) at the four Duo sizes and larger text; taps (Search
  Nearby, the switch); live by address against both synthetic hosts (the
  device's change: three host lines, same port, frames keep coming; a Mac-side
  change shows in the open panel; the app saves 1 then 0); the normal app on
  the simulator: no nearby search without memory, and with a remembered Mac
  that is missing it starts 3.8 s after launch (ValidSvc +1 until it quits)
  while the real Mac on the network stays a plain row. Review (one pass by the
  implementer, three lenses: wire and hard rules, the replacement's
  concurrency, the device UI), then adversarial re-runs of H2–H8 on the final
  build plus: a burst that ends where it started never turns AWDL on (ValidSvc
  constant, no awdl0 row) while 139 of 139 connections across two replacements
  are served; after a total listener failure the next toggle retries; the
  device toggling on then off while streaming (two replacements, same port,
  frames throughout, ends off on both sides). A second review's fixes (the
  plan's "Review fixes"), verified: clean builds; the CLI identical again;
  previews differ from the step before only in the Permissions panes; the
  policy check at 68 (the home race, the café case, denied; six mutants
  caught) and a replay of the status rule (13 states); photos of the connect
  cases (looking, hint, nearby, denied) and of Search Nearby tapped at the four
  sizes (the title does not move); the panel's warning goes when its switch
  is tapped off; an address connection to a host with it on writes no memory.
- Fixes after Noah's first sessions (2026-09-24, branch `direct-wireless-fixes`
  from a9cc248; the plan's last section has the log, the causes with line
  numbers and every check). W5 is answered: off never ended a direct session
  (its open awdl0 socket kept AWDL up), and now the host disconnects it; the
  reconnect and the move above keep a Mac on the network off AWDL; Control
  Center's Wi-Fi switch leaves the radio on for AirDrop, so a direct session
  survives it (only Settings › Wi-Fi or another network ends the shared
  route). Verified headless: the CLI identical to 22209db; `ClientLink` 40
  checks, five mutants caught; end to end with a link-local en0 client standing
  in for awdl0 (`SILL_TEST_PEER_TO_PEER_INTERFACE`): disconnected 1.5 s after
  off with one line, the loopback client streaming on, untouched without the
  variable, nobody disconnected by an off-on burst, disconnected also when the
  app's replacement fails; the policy check at 98 (blinks of 1.5, 4 and 7 s
  never take Direct, absent 10 s takes it at 10.0 s, the move at exactly 2 s,
  the café at 6 s, a 15:43 replay), seven mutants caught; on the simulator
  (`-SillMoveTest 1|refused`) the move hands over with the host streaming
  throughout (1 → 2 → 1 clients, no Desktop restart), a panel change after it
  is answered, and a refused network row leaves the session direct. Review
  fixes (the plan's "Review fixes of the move"): the hand-over fenced
  (`SessionLink`), the host checked by launch ID, and a move given up at 5 s
  ends before its connection is cancelled, so a late `.ready` cannot adopt it.
  Verified: the CLI identical again; the fence against a stand-in Mac whose
  first connection lags 120 ms (600 inputs from two threads, in order and
  complete; the old hand-over reordered 64; released by timeout and by the old
  connection closing), five mutants caught; the policy check at 111, five
  mutants caught; on the simulator the move behind a 150 ms delay proxy waits
  301 ms for its fence, then rtt 302 → 1 ms; `other:PORT` (another synthetic
  host) is refused at its first list and not tried again, the session streaming
  on; the panel shows the Mac's state after a move.
- **Untested, for Noah (the plan's W1–W9):** W1 the payoff: both builds
  installed, `/usr/bin/log stream --style compact --predicate 'process ==
  "kernel" AND (eventMessage CONTAINS "abling AWDL" OR eventMessage CONTAINS
  "ValidSvc")'` shows "Disabling AWDL due to no services and no active
  sockets" once the old Sill is gone (unless AirDrop, Sidecar or Universal
  Control hold it), and five minutes on a still window with trackpad strokes
  keep the `rtt m/M` maxima near the LAN's, with no ~100 ms spikes. W2 on from
  the iPad panel while streaming: no restart, one "listening on port N again"
  (same N), the Mac's Settings and menu follow, `defaults read
  me.saffer.sill.mac directWireless` is 1, "Enabling AWDL due to Mdns" and the
  maxima rise; off from the menu two minutes later and they fall back. W3 with
  it on, the iPad on the iPhone's hotspot and the Mac at home: within 3–5 s a
  "Direct" row; connected, the host logs `%awdl0`, and the panel's readout
  and the iPad's row on the Mac's card both end in "Direct" (the plan still
  says the header's "Connected directly"); note frame age and rtt. W4
  first use (reinstall, café
  conditions): the hint and Search Nearby after 3 s, then "Also looking
  nearby", the Mac as Direct; a relaunch there searches nearby by itself; once
  with Don't Allow on the Local Network alert: the status asks for Local
  Network and no hint shows, and allowing it in Settings brings the list back.
  W5 again (answered from the sessions; now with the fix): connected directly
  (the iPad on the iPhone's hotspot, the Mac at home), off from the Mac or the
  panel gives the "disconnecting … %awdl0" line within ~2 s, the iPad on its
  connect screen, and "Disabling AWDL" about 30 s later. W6 home → café while
  streaming with it on: reconnects directly within ~10 s without a tap (10 s
  since the network last listed the Mac); café → home (rejoin the home Wi-Fi
  while streaming directly): a second "Client connected" on `%en0`, then
  "Client left" for the `%awdl0` one, the picture never stops, the panel's
  readout goes from "Direct" to "Wi-Fi" (the plan: the header loses "Connected
  directly"), and the Mac's card shows the iPad twice for a moment (Direct,
  Wi-Fi), then once, Wi-Fi (drag and type through the move: no button stays
  down, no letters swap); and relaunching Sill.app at home, the iPad
  reconnects over the network (the host logs no `%awdl0`). The blink: at home
  with it on and the iPad streaming, quit and reopen Sill.app a few times, at
  once and after 15 s: the iPad comes back on `%en0` (on `%awdl0` only if the
  network takes over 6 s to list the Mac, and then it moves to `%en0` ~2 s
  after it does). Control Center: connected directly with its Wi-Fi switch
  off, the session goes on; off on the Mac then ends it. W7 relaunch Sill.app
  with it on: `dns-sd -t 3 -includeAWDL -B _sill._tcp local` lists one
  instance on awdl0, no "(2)". W8 the CLI with and without
  `--direct-wireless`. W9 mixed builds (PR #4 iPad with this host, this iPad
  with PR #4's Sill.app: both connect on the LAN, the latter with no row) and
  VoiceOver ("Mac mini, Direct", the hint, Search Nearby and its announcement,
  the row).
- Known, not fixed here: the simulator's browsers run in the Mac's
  mDNSResponder, so a nearby search on the simulator turns the Mac's AWDL on:
  never measure latency with a simulator sitting on the connect screen.
  Security: with it on, anyone within radio range running Sill can
  find and connect to the Mac until pairing (M5); the host-settings plan's §9
  payload cap and a kind 17 rate limit matter more with it on. It is the first
  device-writable setting that widens who can reach the Mac, against that
  plan's "a device sets stream quality, never network exposure": revisited
  with pairing on 2026-10-29 (the security scan's finding 8, PR #253): a
  device sets it only from a session whose key is on the Mac's trust list,
  never unpaired at an open door, at the CLI's plain door or from away. A Mac
  is known by its Bonjour name for a reconnect, so another
  Mac of the same name running Sill on the device's network would be joined
  (pairing again; the move checks the launch ID, which a reconnect cannot, as
  the host may have relaunched). The host can print "Client left" twice for a
  connection that ends with a reset, as the direct one after a move may.

**iPad host settings (2026-09-23, branch `ipad-host-settings` from
`menu-bar-app`, rebased onto its e89add6; the plan and its reasoning are in
`docs/ipad-host-settings-plan.md`).** A device changes the Mac's five streaming
settings the way the Sill menu does: Quality (bitrate), Resolution (capture
scale), Frame Rate limit, Prioritize Speed, Virtual Display. Defaults taken for
the plan's open questions: Settings replaces Leave in every bar's last slot and
Disconnect moves to the panel's pinned foot (Q1); Sill.app saves a device's
change like a menu click (Q2); the virtual display has full menu parity, so
turning it off from a device brings the window home and forward (Q3).
- Wire: kind 16 `.hostSettings` (host → device, JSON `HostSettingsState`: the
  target settings, `persistent`, `virtualDisplayAvailable`,
  `virtualDisplayNote`, `softwareEncoder`, the running `stream`, and
  `answering` in the reply to one change) and kind 17 `.changeSettings` (device
  → host, JSON `HostSettingsChange`: only the fields one control changed,
  absolute values, a token strictly increasing per device process). Types,
  `SettingsChoices` and `QualityPreset` (moved from the app) are in
  `Sources/StreamProtocol/HostSettings.swift`. No ack, refresh or version
  kinds: a kind 16 on this connection means the host supports settings. Fields
  added later must be optional, never renamed or retyped, no enums.
- Host: `StreamCoordinator.setTarget` (synchronous; replaced `apply`)
  validates, forces the virtual display off without the AppKit loop, compares
  with the target (`pendingConfig ?? config`), publishes, and schedules the
  pipeline work in a Task, so a burst is one restart. The `.changeSettings`
  handler has no await: it keeps exactly the Mac menu's values
  (`DeviceSettings.accepted`; the virtual display on only under the AppKit
  loop, off always), logs "Settings from ‹device›: …" and "… refused: …", and
  answers that device alone. The state is a pure function of the target and
  the `HostStatus` snapshot, and both publish (`setTarget`,
  `HostStatus.onChange`), deduplicated, so the once-a-second stats send
  nothing; every device also gets it right after its window list. Nothing new
  prints unless a device sends kind 17 (the CLI's output is unchanged). A pick
  that lands during a restart of the active source now runs after it
  (`pickArrivedWhileSwitching`, newest wins, the restarted source itself
  dropped); during a switch to another source it is still dropped (the device's
  automatic Desktop request must not override a pick).
- Sill.app: `HostSettings.onChange` calls `setTarget` synchronously, so the
  target equals `settings.config` at every main-actor turn, and
  `onDeviceSettingsChange` lays a device's change over `settings.config`: saved
  (only the keys it changed), shown live in Settings and in the menu when it
  next opens. The CLI sets no hook: a device's change lasts until SillHost quits
  (`persistent: false` says so on the device).
- iOS: `HostSettingsLedger` (pure logic) holds the Mac's last state on this
  connection with this device's unanswered picks over it: a pick sends only what
  changes what is shown, nothing before the first state; an answer clears only
  the picks carrying its token (60 → 120 → 60 never shows 120); a refused pick
  goes back with the warning haptic and an announcement; a pick unanswered after
  max(4 s, 4 × RTT) goes back with "‹Mac› didn’t answer. Try again."; reset on
  tear-down, never persisted. `HostSettingsPanel` mirrors the Apps drawer on the
  trailing edge, lined up with the Settings button: 360 pt under the landscape
  bar (340 on the outer display), in portrait wholly in the lower half under the
  window bar; no dim (a clear catcher closes it without clicking the Mac);
  pinned header (the Mac's name, what runs, Done with Esc/⌘.) and Disconnect
  foot, the middle scrolling when short. Opening it takes the keyboard down
  (`InputOverlayProxy.setKeyboard`, so no key reaches the Mac) and closing puts
  it back. Only a control's action ever sends (`StreamClient.changeSettings`).
- Verified without permissions (the plan's H0–H21, S1, S2, S5, S6): clean
  builds (only the old CaptureProbe warning; iOS Debug and Release only the old
  `StreamClient` capture warning); the CLI's output masked and sorted equals
  the branch point and its idle stdout is unchanged; `sillclient.py` shows one
  kind 16 after the first window list and one when the Desktop starts, accept /
  no-op / refusals / partial / a burst of three (one restart) / two clients /
  rapid pairs 0–300 ms (at most two restarts) / reconnect / malformed and
  tokenless changes / 20 s idle (two states, CPU as before) / the toggle on the
  `--virtual-display` host (no restart); the bare app saves a device's change,
  keeps it across a relaunch, sends a `-SillSetAfter` change to the device,
  lets the device and the Mac change different keys at once, and every
  `-SillSetAfter` change still gives one "Settings:" and at most one restart;
  previews byte-identical; the ledger check (28 scenarios, 5,000 random runs
  with two mutants caught); the queued pick with a race client that sends the
  pick while the restart runs (before: 8 of 8 picks lost; now 24 of 24 stop the
  stream after one restart); 38 simulator photos of the panel (four Duo sizes
  × eight cases, iPad mini and iPhone sizes, accessibility-extra-large); taps
  through the harness; live by address against both synthetic hosts (the
  device's change logged, one restart, saved by the app; a Mac-side change
  shown; Disconnect); against the branch-point host the panel says to update
  and the client sends no kind 17.
- Review fixes (2026-09-23, after the rebase onto e89add6): the pick timeout
  reads the new `linkStats` (the worst round trip of the last second that
  measured one, kept through seconds without a pong); a pick queued behind a
  restart goes through the same rule as a fresh one (`handlePick`), so a
  restart that starts before its Task runs no longer drops it; a staged window
  that the virtual display turning off sends home comes forward whichever
  select commits that change (`cameHome`); the device holds back its automatic
  Desktop request when the user picked or launched something while it waited
  out a closed window (the race that remains, older devices and a pick sent
  before the device heard of the close, is written down at `handlePick`); the
  status menu's Virtual Display item sets the value it showed instead of
  toggling, so a click on a menu left open while a device changed it never
  undoes that change; in the panel the readout wraps instead of cutting off and
  "On the virtual display" is a line of its own, Done's tap area is 44 pt tall,
  and the speed switch is "Prioritize Encoding Speed" (the Mac's name) in its
  own group under the Mac's explanation; `sillclient.py` checks every argument
  before connecting; HostSettings.swift lists every place a new setting must
  go. Verified: the CLI's output against e89add6's (masked; idle, 35 s idle,
  the Desktop, `--virtual-display`); H4–H21 again, previews byte-identical;
  the race that lost 5 of 6 queued picks to a rate-change restart now loses 0
  of 10; 46 photos (a new `vdstream` case at every size and at larger text);
  iOS Debug and Release with only the old warning; taps 7 pt above and
  8 pt below Done close the panel; in portrait the header stays put while the
  panel opens (the Quality value moves 2 pt; it slid 32); against a fake host
  that never answers, a pick times out after 4.3 s with prompt pongs and 8.3 s
  with pongs held 2 s; against one that closes the watched window, the Desktop
  request follows 2 s later unless the user picks, and then never comes.
- **Untested, for Noah:** D1–D11 (the plan's §7.4): the panel's values
  against the Mac's menu and status card with a real window; every control from
  the iPad (one restart each; the Mac's Settings window follows; saved in
  `me.saffer.sill.mac` and after a relaunch); the virtual display on and off
  from the iPad, also full screen; a Mac-menu change showing in the open panel;
  two devices at once; `SillHost` without and with `--virtual-display`;
  reconnecting after a change made while away; the 60 fps note and Low Power
  Mode on the iPad mini; a Magic Keyboard (keys stop while the panel is open,
  Esc closes it and does not reach the Mac, keys come back); VoiceOver (modal,
  focus on the Mac's name, the escape gesture); a pick right after a change,
  and five minutes with the panel closed (frame age and RTT unchanged). Also
  rotating with the panel open and Reduce Motion (fade only), which the
  harness cannot drive; not run here: S3 (no Accessibility Inspector) and S4
  (no way to press a hardware Esc in the simulator from here). Also the Mac
  menu's Virtual Display item clicked after the iPad changed it while the menu
  was open (it should do what the item showed), and turning the virtual
  display off while another change is restarting a staged window (the window
  should still come forward).
- Known, not fixed here: in the layout harness, bringing up the software
  keyboard flips the fake screen into the portrait layout (the same at the
  branch point; the harness only). A Mac menu that is already open keeps its
  old checkmarks until reopened (every item sets the value it shows, so a
  click there never inverts a device's change).

**Sill.app, the menu bar host (2026-09-23, branch `menu-bar-app`; the plan and
its background are in `docs/menu-bar-app-plan.md`).** The same host as the CLI,
as an LSUIElement app. A status item whose glyph (drawn from AppIcon.svg:
idle, connected, streaming, attention) and menu card show the network, each
device with its fps, frame age and RTT, and the stream; a menu with Virtual
Display, Frame Rate, Quality, Resolution, Launch at Login (SMAppService),
Permissions, Show Log…, Settings… and Quit. Settings is an AppKit window with
four SwiftUI panes (General, Streaming, Virtual Display, Permissions), kept off
the virtual display; the Log window shows HostLog's last 5,000 lines, and
`~/Library/Logs/Sill/Sill.log` has them all. SwiftPM builds the `SillMenuBar`
executable; `Scripts/make-app.sh` wraps it (Packaging/Info.plist, an icon
compiled by actool from design/AppIcon.svg), signs it with the Apple Development
identity and, with `--install`, replaces /Applications/Sill.app. Bundle ID
`me.saffer.sill.mac`. Settings persist (`defaults read me.saffer.sill.mac`)
and apply live: `StreamCoordinator.setTarget` hands a new `HostConfig` to the next
`select`, which takes it between pipelines; a change restarts the stream once,
or not at all when nothing running depends on it (the virtual display toggle
restarts only a window stream, and sends a staged window home first). Virtual
display off by default in the CLI; in the app off until 2026-10-27 and on since
(`HostConfig.app`, registered, so a saved key still wins; Current step, "Tiles and
Virtual Display on by default").
- Rules. Host code is the `SillHostCore` library (folder `Sources/SillHost`),
  reached with `package` access; make it `public` only if an Xcode target ever
  needs it (M5 CloudKit). Never `MainActor.assumeIsolated` in core code: under
  the CLI's dispatchMain the main queue drains on a worker thread and it traps;
  hop with `Task { @MainActor }`. The modal-loop rule (AppDelegate's doc
  comment): never start NSMenu.popUp, a runModal or a terminate that can answer
  .terminateLater from a Task, an async continuation or a main-queue block, only
  from AppKit target/action, SwiftUI Button actions or a run-loop Timer; errors
  show inline, never in alerts. The CLI's stdout stays byte-identical: core
  `print`s go through the shadow in HostLog.swift, which records nothing until
  the app configures it. App Nap: while a device is connected the app holds a
  latency-critical activity (napping would coalesce the 30 ms keepalive ticks).
- TCC: a grant belongs to the bundle ID plus the designated requirement
  (identifier + Apple anchor + the certificate's CN), so rebuilds signed with
  the same Apple Development identity keep it; ad hoc would lose it on every
  rebuild. Terminal's grants for the CLI don't carry over, and running
  Contents/MacOS/Sill from Terminal makes Terminal responsible. The app asks
  for nothing at launch (no Accessibility alert, no window list before Screen
  Recording is granted); Settings opens on Permissions until both are allowed
  or the user closes it. Allow… shows each system alert once
  (`askedScreenRecording`/`askedAccessibility` in the defaults), then opens
  System Settings, so recovering from a `tccutil reset` also deletes those two
  keys (docs/DEVELOPMENT.md, Permissions).
- Build facts. SwiftPM's default build system links without SDKROOT, so its
  executables record the deployment target as their SDK (`xcrun vtool
  -show-build`: sdk 14.0), and macOS 26+ draws such an app in the pre-26 look.
  make-app.sh writes the bundle's executable with vtool, recording the SDK in
  use (27.0 here) as Xcode would; the CLI and the bare SillMenuBar keep 14.0.
  It signs by the identity's SHA-1 hash (a renewed certificate with the same
  name makes the name ambiguous to codesign), and `--release` refuses anything
  but a Developer ID Application signature. NSTabViewController selects its
  first tab while `NSWindow(contentViewController:)` builds the window, so the
  Settings tab is saved only from an on-screen selection and from `show`.
- In the app only: regular mode trusts `NSWorkspace.frontmostApplication` (the
  AppKit loop runs), and turning the virtual display off brings the returning
  window forward (a product call).
- Verified without permissions: clean build (only the old CaptureProbe
  warning); the CLI's output matches the pre-change baseline line for line
  (sorted, digits masked) at 60 fps, exits 130/143 on the flag path; the bare
  app streams the test pattern at 60 fps, each `-SillSetAfter` change gives one
  "Settings:" line and at most one restart (virtual display on while the
  Desktop streams: none), Quit exits 0 through `releaseForQuit`, a saved setting
  survives a relaunch, idle CPU 0.0 %; the Settings and Log windows open and
  render; make-app.sh signs with the Apple Development identity, the designated
  requirement survives a rebuild, the icon renders as a native squircle, and
  the signed bundle streams and creates a virtual display under the hardened
  runtime. After the SDK fix the bundle (sdk 27.0) still streams at 60 fps,
  exits 143 on SIGTERM and creates and removes a virtual display, and its
  panes render in the macOS 26 look (the Streaming pane matches the design
  draft); `--release` refuses a missing, ad hoc or Apple Development identity;
  a stub harness showed the Settings tab now survives a relaunch.
- **Untested, for Noah:** N1–N12 in the plan: first run and the grants, the
  menu's live rows with the iPad, every control while streaming a real window
  (virtual display on and off, also full screen), Settings placement, Launch
  at Login, quitting with a staged window, App Nap and latency against the CLI,
  regular-mode input, revoking Screen Recording, the Log window, the CLI and
  the app side by side. Also the live menu and Settings window in the macOS 26
  look that the SDK fix turned on (only offscreen renders were checked), and
  Settings reopening on the last tab after a relaunch.
- Known, not fixed here: the CLI's synthetic mode still prints "Advertising
  _sill._tcp" although it no longer advertises.

Milestone 3, scaling and the virtual display. Two paths exist; adopt the second.

- **Fallback (shipped):** the Aa control, in every bar since 2026-09-22, is a
  button that unfolds into a linear slider while touched (camera-zoom style):
  five detents, 0.5× to 1.5× in 0.25 steps, neighbours fade, the value is
  applied once on release. The client sends its stream-panel size and wanted
  scale (`Viewport`); the host resizes the real Mac window through
  Accessibility (`WindowSizer`) to panel ÷ scale points, so text renders at
  that scale on the device. Until the slider is first touched the scale is nil
  and the Mac window is left alone (the control shows 1×; since PR #181 it
  shows Off, a sixth detent left of 0.5×, and Off again puts a window Sill
  sized back at once; no Off with the virtual display on; Aa dimmed unless a
  window streams: Current step, "Aa's Off"). Since 2026-10-14
  (issue #57) the window goes back to its own frame when it stops streaming
  (`WindowRestore`; Current step, "A window Sill sized goes back"). Harness:
  `-SillScaleOpen 1` photographs the unfolded state.
- **Virtual display (implemented 2026-09-22 behind `--virtual-display`, off by
  default; on by default in Sill.app since 2026-10-27, Noah's call, the CLI's
  flag still opt-in).** With the flag, SillHost
  runs `NSApplication.run()` (activation policy `.prohibited`: no Dock icon,
  never activatable) instead of `dispatchMain()`, because only under the AppKit
  loop does the creating process see the display's modes. `select(.window)`
  asks `VirtualStage` to create one `CGVirtualDisplay` ("Sill", 2×, at the
  stream's rate),
  move the window onto it with Accessibility (`WindowSizer.placement/move/
  restore`; AX writes never activate or raise anything), and capture it with
  `SCContentFilter(display:including:[app])` cropped by `sourceRect` to the
  window's rectangle, so the device sees the window plus the app's own menus,
  popovers and sheets (separate windows, invisible to window capture) and
  nothing else. Deselect,
  switch, last client leaving, display lost, Ctrl-C/kill/hangup
  (`HostShutdown`) and `atexit` put the window back at its original frame and
  destroy the display. Any failure logs "Virtual display fallback …" and
  streams the real window as before.
  Full screen (2026-09-23): a staged window that enters a full-screen Space
  fills the display and refuses moves, so `prepare` detects it (AXFullScreen
  or ≥98 % coverage), captures the display cropped to the panel's aspect
  around its middle (where apps letterbox video), and holds that until the
  catalog's next poll sees the window leave full screen. "Still full screen" is
  AppKit's AXFullScreen flag (the frame sits short of the display mid-Space);
  a window leaving full screen is off every list for ~1 s, so the catalog
  gives it three polls and `prepare` waits 1.5 s before calling it gone; a
  switch away first takes the window out of full screen
  (`leaveFullScreenIfNeeded`) so it can go home. The band is encoded at the
  panel's size, not the display's. Entering and leaving each take up to one
  2 s poll to show.
  Geometry (pure functions in `VirtualStage`): window = panel ÷ Aa scale in Mac
  points (Off counts as 1.0; no viewport → the window's own size). The display
  is an *envelope*, a square of the panel's longer edge ÷ 0.5 plus the menu
  bar, reused while the wanted window fits, so rotation and Aa steps re-place
  the window and restart the pipeline without recreating the display; the
  device always gets exactly the window's rectangle. Deviation from the
  "sized to the panel" brief; `VirtualStage.envelope` returning `windowSize`
  restores the literal behaviour.
  Verified without permissions: default path byte-for-byte unchanged (~55 fps
  synthetic, plain SIGINT death); flag path streams the synthetic Desktop at
  ~55 fps under the AppKit loop and exits 130/143/129 with the window restored;
  `--virtual-display-selftest` creates a 1000×700@2× display in ~150 ms,
  online after ~250 ms, destroyed in ~60 ms, no permission needed for the
  display itself. Three review lenses plus adversarial verification found and
  fixed: a stale display reference after the grow path, placement recorded
  only after the first move (a Ctrl-C mid-staging lost the window), a failed
  pipeline start leaving the stage staged, a last-client-left during a switch
  being dropped, and `.cannotComplete` mistaken for "window gone".
  Learned: without Screen Recording, `SCShareableContent` never returns while
  a virtual display exists, so every SCK call on these paths is bounded
  (`WindowCatalog.shareableContent(…timeout:)`) and `prepare` refuses to make
  a display without the permission.
  Learned (2026-09-23): the window list shows an AX move only once the app
  commits it, a few to tens of ms after the AX writes return (more for an app
  slow to lay out); the AX frame reads the new frame at once. So the eviction
  scan right after a switch found the window just sent home still listed on
  the display, matched no AX window to that frame and printed "A System
  Settings window sits on the virtual display and could not be matched…"
  (twice, both false alarms: the window went home). Fixed: `releaseWindow`
  keeps the element (`lastReleased`) and the scan judges that window by its
  live AX frame: home, skipped; still overlapping (Messages kept a wider
  frame, a 24 pt strip), evicted and centred by its live size. The warning now
  names the window ID and listed frame. Probe on its own off-screen window,
  scan at once: the old logic warned in 21 of 30 scans, the new in none, and
  picked the overlapping window for eviction 20 of 20. Not yet run with real
  windows.
  Fixed (2026-09-23): `prepare`'s settle loop read only the window list and
  stopped after three identical reads 20 ms apart, counted from the frame
  before the move, so a pure resize the app commits late (1Password, Electron:
  between 45 ms and ~0.45 s) looked settled at once and the old frame became
  the crop until the catalog's next poll re-selected (~0.4 s of wrong crop).
  Now it reads the AX frame once after the writes. A new size there means
  stillness counts only once the listed size has left the old one, the list
  showing AX's frame ends the wait, and the deadline is 1 s; the old size (a
  refusal) counts stillness at once within 0.5 s, as before. A wait that runs
  out appends "; not settled by the deadline" to "Moved …", whose "from" is
  now the frame before the move (it printed the home frame). A restart that
  asks for the same rectangle as the last placement (the request fitted to the
  usable area, so a Dock arriving on the display still gets the window
  re-fitted) finds a clamped window where it was left and skips the move.
  Step (6) run verbatim in a harness: a probe window whose commit trails its
  frame by 80/150/300 ms was cropped at the old frame every time before, at
  the new one in 104/181/341 ms now; a refusal still settles in ~50 ms; a
  clamped restart takes 0 ms and no move; simulated, a Dock arriving between
  two restarts still gets the window re-fitted. Known limit: an app whose AX
  frame lags too (it applies the size after answering the write) still reads
  as a refusal, and its old frame stays the crop until a catalog poll (2 s;
  one that lands mid-switch is ignored) re-selects.
  **Untested, for Noah** (Screen Recording + Accessibility on the terminal):
  (a) `swift run -c release SillHost --virtual-display`, pick a window: the
  log shows "Virtual display … created", "Moved …", "Capturing … of virtual
  display", and the frame fills the panel edge to edge at Aa 1× with the title
  bar as the top edge; System Settings › Displays shows one "Sill" display.
  (b) Cover the window's old spot, switch Spaces, open Mission Control: the
  device keeps updating. (c) Deselect, pick Desktop, quit the iOS app, Ctrl-C
  mid-stream: each prints "Restored …" then "Removed virtual display", the
  window is back within 2 pt, no "Sill" display remains. (d) Rotate and cycle
  Aa while staged: one "Capture started" per change, no new display created.
  (e) The 1Password Aa step that showed the stale crop (staged at Aa 0.5,
  then 1×): the first "Moved … to" shows the asked 1117×610 and "Capture
  started" reads 2234×1220, with no second capture ~0.4 s later.
  If the picture is offset or black, the escape hatch is the last line of
  `VirtualStage.prepare`: return the `desktopIndependentWindow` filter with a
  nil `sourceRect` (window capture on the virtual display ran at 59 fps in the
  probe).

**Bar controls (2026-09-23).** Press and hold a thumbnail (0.5 s unless changed in
Settings › This iPad, 0.2 to 2 s; issue #113, `ThumbnailHold`): macOS's three lights
appear over it (close, minimize, full screen → `.windowCommand` = kind 15, JSON
`WindowCommand`; the host presses the window's own buttons through
Accessibility, using the staged element on the virtual display). Keep holding
and move: the lights go, the thumbnail lifts and drags into a new slot, Home
Screen style; the arrangement is the device's own (`StreamClient.windowOrder`,
persisted per Mac, host order for the rest). A "Leave" button disconnected
(since the host settings step the last slot is Settings, with Disconnect in its
panel's foot). The device asks for the Desktop whenever the host reports nothing
streaming (at most every 10 s, and once more when those 10 s end if its own
request brought nothing: 2026-10-28), so a fresh connection starts on the Desktop and
the drawer no longer opens by itself. When the watched window has closed it
waits 2 s first, and asks for nothing if the user picked or launched something
meanwhile (the host cannot tell that request from a Desktop tap). Harness:
`-SillWindowMenu 1` keeps the first thumbnail's lights open.

**Frame rate follows the device (2026-09-22).** `Viewport.fps` carries the
device's wanted rate: `UIScreen.maximumFramesPerSecond` (120 on ProMotion, 60
on the iPad mini), or 60 while Low Power Mode is on; the client re-sends on
`NSProcessInfoPowerStateDidChange` and `UIScreen.modeDidChangeNotification`.
The host keeps each client's rate (`clientFPS`, cleared on disconnect) and runs
the stream at the highest, capped by `maxFPS` and by 60 on the software
encoder; `fps` is re-read at every select;
a changed rate restarts the pipeline (capture interval, encoder session and
the virtual display's refresh all follow it), and bitrate scales with it.
Verified synthetically: 120 → "120 fps, 30 Mbps", drop to 60 mid-stream
restarts at 60 within a frame; `--virtual-display-selftest 120` comes online
at 120 Hz. Not yet measured on a ProMotion device or with the hardware encoder
(the software encoder manages ~22 fps at 1512×948 when asked for 120, which is
why it exists only as a fallback). `CADisableMinimumFrameDurationOnPhone` is
set so ProMotion iPhones render above 60.

**Trackpad stutter (fixed 2026-09-22), three causes, all measured:**
1. The device's Wi-Fi radio dozes when the downlink goes quiet, and every next
   packet then waits up to ~300 ms (iPad ping RTT sawtooth 5→100→200→300 ms with
   nothing streaming; the loopback simulator stays at 0). A trackpad stroke over a
   static window starts from a dozing link, so its first frames bunch up. The host
   now sends an empty `.tick` every 30 ms (~0.5 KB/s) while a source is live or a
   client sent input in the last 3 s, and both ends use the `.interactiveVideo`
   service class. Verified: RTT flat at 6–11 ms over 20 s with a static window.
2. A periodic IDR every 4 s (1–2 MB at 3024×1898) showed as a 50–100 ms
   RTT/frame-age spike every 4 s. Keyframes are on demand (connect, dropped
   delta, switch); the periodic safety interval is 4 s (`fps * 4`); a 30 s try was reverted while bisecting the freeze.
3. The only pointer the user could see was the Mac cursor baked into the video,
   so it moved as unevenly as the video arrived. The client now draws its own
   arrow sprite (`HEVCDisplayView`, a CALayer, no implicit animation, fed by
   `StreamClient.renderPointer`, not @Published) for the trackpad and Pencil
   hover; the host leaves the Mac cursor out of the video for good
   (`showsCursor` false at capture start; reconfiguring a running SCStream
   wedged it) and streams its shape as `.cursorShape`. Since 2026-09-27
   (branch `pointer-visibility`) the sprite also shows the Mac's own pointer
   while the Mac, or another device, moves it (kind 26, at the tick or the
   stream's rate), and this device's own only for the portrait trackpad (the
   Pencil's with Q2's flip). The trackpad also lost UIKit's ~10 pt start-of-
   stroke dead zone (a zero-duration long-press tracker drives the first
   movement) and gained Force-Touch-style haptics on click/drag (iPhone only:
   iPads have no Taptic Engine).
Dead-client eviction is time-based (no frame drained for 4 s, none in the first
8 s after connect): the frame-count rule evicted the simulator at full Retina.
A client evicted while the Mac is still advertised now retries on a timer.
Learned (2026-09-23; this replaces the caveat on (1)): the RTT spikes left with
ticks flowing come from AWDL, and Sill turns AWDL on itself. `includePeerToPeer
= true` on the host's NWListener (`StreamServer`) and the iPad's NWBrowser and
NWConnection (`StreamClient`), there since the first commit, makes the kernel
enable AWDL as `_sill._tcp` registers ("Enabling AWDL due to Mdns"; off ~3 s
after Sill quits). The Mac's one radio then leaves the Wi-Fi channel on a
512 TU schedule (kernel: infra 72 % while streaming, 48 % or 0 % around
switches). A 20 Hz ping from the Mac to its gateway stalls up to ~97 ms once
every 524 ms (p90 48 ms, 17 % over 10 ms; with AWDL off, p90 4 ms and max
13 ms). The same Bonjour service registered with the AWDL flag gave p90
67.5 ms with 32 % of pings delayed, against 3.9 ms without the flag. An rtt
sample that lands in a stall reads baseline plus 0–100 ms. AWDL carries none
of Sill's data (the connection is on en0). Ticks keep the radio awake but not
on the channel, and every earlier RTT reading, those in (1) and (2) included,
ran with AWDL on. The fix is applied (2026-09-24, Direct Wireless Connection
in the current step): `includePeerToPeer` is off by default on both sides and
comes back only for a Mac whose owner turns the setting on, and on the device
during a nearby search (Search Nearby, or a Mac last seen with the setting on
missing from the network), which stops once connected; the iPad side still
needs a device run. Secondary: `inflight > 2` counts only what
Network.framework has not handed to the socket, so after a switch the socket
buffer (autotuned up to 4 MB) can hold ~200 ms of frames ahead of pongs (frame
age 188–229 ms, no `net.dropped`). Client measurement, reworked 2026-09-23
(it sampled frame age every 15th frame and repeated the last value in a
slower second, sent one rtt sample per report, and ran its fps and ping
timers in the main run loop's default mode, so both stopped while a scroll
tracked): the client now takes the age of every frame and pings every 0.25 s
(stamped with the monotonic clock), both on dispatch timers on its network
queue, and closes a one-second window each second. Each report carries that
second's median in the old `ClientStats` fields, -1 for a second without a
sample (a still window streams no frames), and its max in two new optional
fields. The host still logs every other report, now as
`frame age 9/24 ms, rtt 7/80 ms` (the last second's median over the worst
since the previous line, "–" for no sample; an older client prints one
value), and the menu's device row and the HUD show "–" the same way.

**Frozen stream, 2026-09-22 evening — the Mac's hardware video encoder wedged.**
Every new HEVC session (and later H.264) accepted one frame and never returned
it, even from a fresh process with synthetic frames (`SillHost
--encoder-selftest`, `CaptureProbe --synthetic`). The old encoder called
VideoToolbox synchronously on the capture queue, so the stuck call froze
ScreenCaptureKit, then `stopCapture`, then the coordinator's `switching` flag,
and every later selection was silently ignored. The wedge held for about
three hours and then cleared on its own at ~22:30 (a fresh hardware session
encoded again while the orphaned sessions in the old encoder-service process
were still logging their 4 s timeouts), so a reboot is the sure fix, not the
only one. Protections now in the host:
- At launch the host pushes one 256×256 frame through a hardware session
  (`EncoderProbe`, ~100 ms when healthy, 1 s deadline). No answer means the
  host starts on the software encoder at once and says so, instead of hanging
  the first stream for 1.5 s and restarting it.
- `HEVCEncoder` feeds VideoToolbox from its own queue behind a one-slot
  mailbox (`EncoderMailbox`): the capture queue never waits; one frame at a
  time is inside VideoToolbox (two at once was measured and dropped: Current
  step, "The 33 fps plateau"); a watchdog on a separate queue declares the
  session hung after 1.5 s and calls `onHung`. A stream whose session settles
  in the hardware's slow state gets a new session in place
  (`EncoderSlowState`; Current step, "A new session for the slow state").
- The coordinator then restarts the source on the software encoder, capturing
  at 1x (half scale on a Retina display, the display's own on a 1x one; slow,
  ~10 fps under load, but live) and says so in the log; three
  software hangs stop the stream instead of looping. Since 2026-09-25 that
  lasts only until a re-check finds the hardware keeping up (Current step,
  "The hardware encoder: busy, not stuck"); before, it lasted until the host
  relaunched.
- Presentation timestamps are forced monotonic; a keyframe request re-encodes
  the last frame only when the window is static.
- Never reconfigure a running SCStream (`updateConfiguration` also wedged it);
  the Mac cursor is left out of the video for good and the device draws it,
  with the Mac's live cursor shape streamed as `.cursorShape`.
- Regular mode raises the picked window on select (2026-09-23, Noah: the Mac
  must show the picked window): app activated, window raised and made key,
  before capture starts. Picks only (switcher, command line, an app launched
  from the device); the host's own restarts (resize, rate change, encoder
  fallback) leave focus alone. The virtual display never touches Mac focus on
  select; a pick that falls back to the real window counts as regular mode.
  Interacting works like a real click in both modes: a click, keystroke or
  typed text activates the app through Accessibility only
  (`NSRunningApplication.activate` is refused from a background process, and
  a Launch Services "open" of a running app counts as opening it, which
  switched on Noah's Work Focus automation, so it is never used; an app that
  refuses AX simply stays back), input held until it is up (at most 0.6 s) so
  the first click lands; on the regular path a window covered at the click or
  scroll point is also raised. Input that arrives mid-switch is delivered but raises nothing
  (`active` still names the old window, and raising it would cover the pick).
  Ghost "LayerProbeParent" windows that SwiftUI apps spawn per new display
  are filtered from the catalog.
Verified 2026-09-22 with `--synthetic` against the still-wedged encoder: hang
detected at 1.5 s, software restart, 55–59 fps out, the iPad decoding it fine.
Diagnosis tools: `swift run -c release CaptureProbe <window> [s] [--encode]
[--synthetic] [--software] [--h264] [--lowres]` (capture vs encode, hardware vs
software) and `sample <pid> 2` (a wedged encode shows as
VTCompressionSessionEncodeFrameWithOutputHandler → RemoteVideoEncoder).

Still open: the unexplained one-off stall where new clients received no catalog
(2026-09-22, hardened since, never reproduced). Keep the connect-path logging.
Known: a streamed window covered by another window on the Mac freezes on the
device (macOS stops repainting it) until the device picks it again or clicks
or scrolls in it, which raises it. `--virtual-display` removes the freeze for
good.

## Milestone 2 (input and window control) — done 2026-09-22

- Client → host input: tap/click, finger pan → scroll with trackpad gesture
  phases and client-generated momentum (host sets CGEvent scroll/momentum
  phases so apps rubber-band and fling), long-press right-click, Pencil as the
  mouse with hover, software keyboard as Unicode text, hardware keys and
  ⌘/⌃/⌥ chords as HID usages. Portrait laptop layout: stream on top, key row
  (esc, tab, latching modifiers, arrows, keyboard; Spotlight = ⌘Space only while
  the Desktop is the source, since Spotlight's panel is its own window) and a
  relative trackpad. Picked app is brought forward; window follows moves;
  resize restarts the pipeline.
- Latency, measured 2026-09-22 on 5 GHz Wi-Fi to the iPad mini via the client
  stats the host logs: frame age (host encode → device receive) 8–10 ms,
  ping RTT 6–9 ms with rare spikes. Adding capture (≤1 refresh), encode and
  decode+display (1–2 refreshes) puts glass-to-glass at roughly 40–60 ms,
  within the v1 bar. Not photographed with the stopwatch method yet.
- Host footprint (release build, `ps`): idle with no client 0.0 % CPU, 36 MB,
  one heartbeat line per 30 s and no ScreenCaptureKit calls; connected with
  nothing selected 0.0–0.1 %; streaming a Retina window ~3 %. Capture stops when
  the last client leaves.
- Diagnostics: `-SillHUD 1` (DEBUG) overlays fps · frame age · rtt · frame size
  on the device; the client reports the same to the host every second and the
  host prints `client <device>: …`.
- Learned: `_AXUIElementGetWindow` is private, so AX windows are matched by
  title then frame; apps enforce minimum sizes, the host streams what it got.

## Milestone 1 (latency spike) — done 2026-09-22

- Mac host builds and runs from `swift build -c release`: window listing,
  ScreenCaptureKit capture, VideoToolbox HEVC encode, Bonjour advertisement,
  TCP fan-out to clients.
- iOS client is a real Xcode project (`iOSClient/Sill.xcodeproj`), builds
  clean, runs on Noah's iPad Mini (the test device: iPad scalability plus a
  Duo-like aspect ratio).
- End to end verified on Wi-Fi: ~58 fps captured, encoded and sent with zero
  drops at 3024×1898 (Retina capture of a 1512×949 window), 15 Mbps.
- Bugs found and fixed along the way: SCStream aborting with `CGS_REQUIRE_INIT`
  when set up off the main thread in a CLI tool; the whole pipeline being
  released when the startup Task finished (one frame, then silence); clients
  that connected to a static window never receiving a keyframe.
- Host prints a per-second stats line (captured/encoded/sent/dropped) so a
  stalled stage is visible without a debugger.
- Toolchain on Noah's Mac: Xcode 27 selected as developer dir, license
  accepted, first-launch packages installed. No signing identities existed;
  Noah signs with his own team in Xcode.
- Learned: ScreenCaptureKit delivers frames only when the window repaints, and
  macOS stops repainting fully covered windows, so a streamed window buried
  behind others on the Mac freezes on the device. Inherent to window capture;
  the virtual-display plan in milestone 3 sidesteps it.
- Not measured: the latency number itself (see above).

## Layout

- `Package.swift` — SwiftPM. Products: `StreamProtocol` (shared wire format,
  iOS + macOS), `SillHost` (the CLI, target `SillHostCLI`) and `SillMenuBar`
  (Sill.app's executable). `SillHostCore` (the host, folder `Sources/SillHost`)
  is a library target with no product, so the iOS project never sees it.
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  message kinds in both directions, HEVC parameter set encoding. Shared by both
  sides. Change it in one place. `Switcher.swift` — the catalog types
  (`WindowList`, with the host's per-launch `launchID`; `WindowInfo`,
  `AppInfo`, `StreamSource`) and image blob framing. `Viewport.swift` —
  `Viewport` (kind 9: the device's panel, Aa's scale and its rate),
  `ClientStats` (with `lateSince`, a host's count of a device's late sound
  packets, which never traps), `CursorShapeBlob`, and `ViewportBounds` (what a
  host takes of a viewport: each side 1 to 16384 points, a scale 0.25 to 4 or
  none, any other refused; what a device sends, `held`; and `whole`, a number
  for a log line as Int() printed it, without its trap; pure,
  `Tests/checks/viewport-bounds`).
  (`WindowList`, with the host's per-launch `launchID` and what it takes and does:
  `gestures`, `clipboard`, `keyRepeat`; `WindowInfo`, `AppInfo`, `StreamSource`) and
  image blob framing.
  `HostSettings.swift` — the host settings a device sees and changes (kinds 16
  and 17): `StreamSettings`, `RunningStream`, `HostSettingsState`,
  `HostSettingsChange`, `SettingsChoices` (the Mac menu's values) and
  `QualityPreset` (Low, Efficient, Balanced, High, Pro, Ultra, Extreme). Remote access:
  `Remote.swift` (kinds 18–22's payloads: `MacAddress`, `MacInfo`,
  `SignedMacInfo`, `PairRequest` (with pairing at home's methods `ask` and
  `cancel`, `cable` and `v`), `PairResult` (its `method`, the ask's reasons
  `shown`, `openOnMac` and `locked`, and `message`), `Goodbye` (with
  `pairingRequired`)), `RemoteTLS.swift` (the one TLS 1.3 builder for both
  doors' ends and the tests; `serverALPNs`, the two a host offers for good),
  `RemoteIdentity.swift` (SPKI fingerprints, the Mac ID, the hand-built
  certificate, keys), `Pairing.swift` (`PairingCode`, `PairingProof`,
  `RecognitionTag`, `PairLink`, and `HomeDoorTXT`, the home door's TXT key
  `p`), `AddressParser.swift`, `SafeText.swift`.
  `Compatibility.swift` — `SillProtocol.current` (1), `SillVersion` (tags,
  bundles and the wire's versions, compared part by part) and `Hello` (kind 23,
  the device's first message); `Goodbye` (Remote.swift) carries `message`,
  `minimumVersion` and `reconnect` too, and `WindowList` the host's
  `hostVersion` and `protocol`. `MacMenu.swift` — the Mac's menus (kinds 24,
  25 and 27): `MacMenu` (a top level, or the answer to one fetch or press),
  `MacMenuItem`, `FetchMenu` (with the title the device showed for the menu)
  and `PressMenuItem`. `Pointer.swift` —
  `MacPointer` (kind 26, host → device: where the Mac's pointer is in the
  streamed frame while this device is not moving it, and `seen`, the input
  messages the host had read on the connection). `Gesture.swift` —
  `TrackpadGesture` (kind 28, device → host: a three- or four-finger gesture
  by name, and its fingers), sent only to a host whose `WindowList.gestures`
  is 1 or more. `Clipboard.swift` — `Clipboard` (kind 32, both ways: `text`,
  `image` reserved for a later generation, a device's `stop`) and its 256 KB
  cap; `ClipboardPolicy.swift` — the clipboard's rules for both ends (what a
  device's message asks of the host and the rate, which a stop never meets;
  which change of the Mac's pasteboard the host sends and to whom, and only
  while macOS allows every read (`MacAccess`); the device's subscription,
  which text from the Mac it writes, a Paste's receipt, the chip and its time,
  every word; pure, `Tests/checks/clipboard`). `Audio.swift` — the Mac's sound
  (kind 43, host → device; 29 to 31 and 33 to 42 are PR #66's):
  `AudioMessage`, type 1 a JSON `AudioFormat` (codec, rate, channels, packet
  size, priming, bitrate, epoch, cookie, what it is of), type 2 binary
  `AudioPackets` (epoch, seq, the segment flag, 1–255 packets); `AudioCodec`
  ("aac-eld", and `choose`: the first of a device's `Hello.audio` the host
  makes); only to a device whose hello lists one. `ScrollDirection.swift` —
  which way a scroll on the device moves the Mac's content: the device's
  Reverse Scrolling (issue #143, `Sill.reverseScroll`, never sent) turns a
  finger's drag over the picture and two fingers on the on-screen trackpad
  around, their coast too, never a connected trackpad's or mouse's scroll
  events (iPadOS's own Natural Scrolling set those); pure,
  `Tests/checks/protocol`. Kind 44, `keyframeRequest` (device → host, no
  payload: this device's picture was interrupted and waits for a keyframe;
  issue #101), has no type of its own.
- `Sources/SillHost/` — the `SillHostCore` library. `StreamCoordinator` (main
  actor; owns the pipeline, switches sources on client request, raises the
  picked window in regular mode (never on the virtual display), applies
  viewports, falls back to the software encoder on a hang and re-checks the
  hardware until it can go back (`recheckLoop`), stops capture when the last
  client leaves, takes live settings between pipelines (`setTarget`, from the
  app and from devices' kind 17, at most four a second per connection,
  answered and published as kind 16; a pick made during a restart runs after
  it), keeps each connection's route (home or the remote door's: kind 21 only
  from near the Mac, Direct Wireless never from away), sends kind 18 with the
  catalog, says goodbye (kind 22) at quit, sends the streamed app's menus to
  the devices that ask (`MenuMirror`; a window source's app made active and
  its window key first, as a click does: `focusForMenus`), answers a device's
  keyframe request (kind 44) with `HEVCEncoder.requestKeyframe`, at most one a
  second per connection, never a restart (a synthetic host ignores the first n
  with the TEST ONLY SILL_TEST_KEYFRAME_IGNORE=<n>, as a Mac from before kind 44
  ignores every one), and writes `HostStatus`),
  `HostConfig` (the knobs: maxFPS, captureScale, bitrate per 60 fps, the
  away pair awayBitrate and awayCaptureScale, prioritizeSpeed, virtualDisplay,
  directWireless, remoteAccess, remotePort, internetAccess, requirePairing,
  sendAudio, shareClipboard; `standard` is the CLI's values, `app` Sill.app's
  defaults, the same with the virtual display and Send Audio on (2026-10-27); `effective(away:)`), `HostClipboard` (the clipboard's host side: who
  subscribed, the look at the pasteboard's change count four times a second
  while one has and macOS allows every read, a device's text written
  `.currentHostOnly` with this launch's marker and passed to the others, one
  line a subscription and none per copy; a synthetic host's own pasteboard,
  the TEST ONLY SILL_TEST_PASTEBOARD, SILL_TEST_CLIPBOARD_LOG and
  SILL_TEST_CLIPBOARD_ACCESS; `MacClipboard`, macOS's paste privacy for the
  look and for Settings › General's `ClipboardSection`),
  `AwayPolicy` (who counts as away, when the away quality is the target, its
  two lines; pure, `Tests/checks/away-quality`), `LinkJudge` (each device's
  link judged once a second from the sweep: fine, behind, stalled, the carried
  rate, the suggestion, the host's lines, and which restarts judge afresh
  (`judgedAfresh`); pure, `Tests/checks/link-judge`),
  `HostStatus` (the snapshot the app shows, pushed on events; `onChange`
  publishes the devices' settings state; `firewall`, the macOS firewall's
  verdict), `FirewallRule` (what the macOS firewall's read-only answers mean
  for this host: a rule that blocks the running executable or its bundle, or
  Block all incoming connections, keeps devices out; Settings › General's
  line with the Terminal command that unblocks it, the menu's subtitle, the
  log's lines; the TEST ONLY SILL_TEST_FIREWALL's canned answers; pure,
  `Tests/checks/firewall`) and `FirewallCheck` (asks `socketfilterfw` five
  read-only questions, a process each, no privileges: at launch, when the
  listener comes up, when Sill.app's status menu or General opens, when a
  device gets in while the verdict says none can), `DeviceSettings` (what a device may
  set, `HostConfig` ↔ wire), `HostLog` (the print shadow, the app's ring and
  log file),
  `WindowCatalog` (polls windows and thumbnails only while a client is
  connected; icons; installed apps in the background; when its last look
  landed, `lookAge`), `CatalogLook` (whether a capture may be built from that
  look or the catalog looks again first: its display no longer active, none, no
  look, or older than two polls; the Desktop's lines and its one more try's;
  pure, `Tests/checks/catalog-look`; the black screen of 2026-10-28), `InstalledApps`
  (where those are found: each applications folder and the folders inside it,
  at any depth (#135's), never inside a bundle, another package or a
  framework, and never through a link inside a scanned folder (one given that
  is itself a link is followed), #76; pure, `Tests/checks/installed-apps`),
  `WindowCapture` (ScreenCaptureKit; its line names the scale it captures at),
  `CaptureScale` (the pixel scale a capture runs at: the Resolution knob held to
  the display's own, ScreenCaptureKit's `pointPixelScale` for the filter, so a
  window on a 1x display fills its picture and nothing is upscaled; and
  `InputLanding`, where a device's position lands on the Mac: at most the
  source's last pixel row and column at its display's scale; and
  `VirtualDisplaySize`, the size of Sill's virtual display, no side under 800
  points, which macOS kept at 2x (an iPhone's 754×784 came up at 1x), and of
  the window on it, 1 to 65536 points a side, the most a host takes, so a
  full-screen window's crop keeps the panel's shape (`windowSize`); pure,
  `Tests/checks/capture-scale`), `SyntheticCapture` (test pattern for
  `--synthetic`; SILL_TEST_PATTERN=noise adds a square of noise,
  SILL_TEST_PATTERN=picture:<path> shows a still picture instead,
  SILL_TEST_STILL_AFTER=<s> sends no frame from s seconds on, as a window that
  stopped changing), `HEVCEncoder` (VideoToolbox with one frame inside, a
  one-slot mailbox behind it and a hang watchdog; hardware or software; says
  whether a stalled frame came back; gives a stream whose session settled in
  the slow state a new one), `EncoderSlowState` (when that is, and whether the
  new session ran faster; pure, `Tests/checks/encoder-slowstate`),
  `EncoderMailbox` (its bookkeeping: the frame inside with its watchdog
  clock, the mailbox, the watchdog's test, timestamps and keyframe requests;
  pure, `Tests/checks/encoder-mailbox`), `EncoderProbe` (one small frame
  through a hardware session at launch; for the re-check a short quiet run at
  the stream's size, one frame at a time like a stream, the rate it keeps and
  the rate a return needs), `EncoderSelfTest`
  (`--encoder-selftest`), `CursorShapeWatcher` (NSCursor.currentSystem →
  `.cursorShape`), `StreamServer` (Network.framework + Bonjour `_sill._tcp`, both
  directions, keepalive, dead-client eviction, ping echo, client-stats print;
  a remote client's frames paced by the bytes its connection has not taken
  (`paceRemote`, docs/remote-bundle-plan.md §3); one sweep a second closing
  every client's second into its LinkJudge (`onClientLinkChanged`), the judges
  reset only at another quality (`resetLinks`, apart from `resetForNewStream`);
  `send(each:)`, kind 16 per connection; a session `closeSessions` cuts off
  marked revoked as it is told goodbye, its receive loop then handing on only a
  key's or a button's up (`onClientRevoked`, RevokedInput); the test-only
  SILL_TEST_REMOTE_ORIGIN;
  the listener built with or without peer-to-peer and replaced live when Direct
  Wireless changes, and turned off, the devices on peer-to-peer Wi-Fi
  disconnected; the test-only SILL_TEST_SERVICE_TYPE, SILL_TEST_SWAP_FAIL,
  SILL_TEST_PEER_TO_PEER_INTERFACE and SILL_TEST_LOOPBACK), `ClientLink`
  (which route a client came by, from its endpoint's scope, and the menu card's
  word for it: Wired, Wi-Fi, Direct or none; pure, checked on its own with
  `swiftc -package-name sill`, which its `package` access needs),
  `InputInjector` (CGEvents: pointer and scroll where InputLanding lands them, scroll with phases, text with modifier
  flags cleared explicitly (a ⌘Space before typing otherwise tainted the text
  events and Spotlight ignored them), HID keys as KeyStrokes gives them, each
  device's keys let go when it leaves (and a cut-off device's buttons) and every
  key and button at the host's end, the check after each key's up, a button's
  up with nowhere to land where the pointer is; the TEST ONLY input log),
  `KeyStrokes` (a device's key as the
  device's keys let go when it leaves and every key and button at the host's
  end, the check after each key's up, a button's up with nowhere to land where
  the pointer is; a held key's repeats, as KeyRepeat steps them (a Task on the
  main actor), each a key down with the autorepeat flag; the TEST ONLY input
  log), `KeyRepeat` (a device's key held down repeated as the Mac's own keyboard
  repeats a key, #162: after NSEvent's keyRepeatDelay, at its keyRepeatInterval,
  every key but the modifiers, Caps Lock, fn and the media keys, the last key
  pressed alone, the flags in force at each repeat, stopped at its up, another
  key, text, a gesture's shortcut, the device leaving, the host's end and input
  with nowhere to land, waiting while input is held for an activation and while
  the device is quiet half a second (StreamServer.lastHeard), its first repeat
  only once the device is heard no earlier than `firstWord` (0.3 s) before it
  (a key only tapped whose up a stall holds back never repeats); `generation`, said
  in every window list as `keyRepeat`, so a device sends a hardware keyboard's
  characters as keys; pure, `Tests/checks/key-repeat`), `KeyStrokes` (a device's key as the
  Mac's: its virtual key, and the flags each event carries from the modifier
  keys the devices hold down, so a key's up leaves only what is held;
  `KeyUpCheck`, whether an up took its modifiers out of the HID state table;
  `DroppedInput`, what of input with nowhere to land still goes;
  `RevokedInput`, what still goes of a device the Mac no longer serves, or of
  one that left while its input was held: the up of what it holds down, and
  the buttons a cut-off device holds as it leaves (`buttonsLetGo`); pure,
  `Tests/checks/key-strokes`),
  `WindowSizer` (Accessibility resize for the Aa scale, returning what it did,
  `Fit`; `placement/move/restore` for the virtual display; `AXWindows`,
  WindowRestore's reads and writes through Accessibility; `perform`, a window's
  lights (kind 15), each element with a timeout, Close's button 1 s, and what
  came of it, `CommandOutcome`: done, refused or no answer in time, its words
  per action), `WindowRestore` (a
  window Sill sized for a device goes back when it stops streaming: each fit's
  record and `movedSince`, the decision at the stop, the sequences that fit a
  window and put it back over `WindowRestore.Access` (`fit`, `stop`,
  `stageHome`), `keepsStreaming` and `coversDisplay` for a window off the list
  on its way into or out of full screen, the ledger, the lines; pure,
  `Tests/checks/window-restore`), `VirtualDisplay` (private-API wrapper; its
  `TypeEncoding` says which type encodings the runtime may report for each method
  it calls, a `BOOL` return spelled "B" or "c" (#87, #62); pure,
  `Tests/checks/virtual-display-api`, which also runs `Runtime.method`'s decision
  and the `applySettings:` call, through `methodProblem` and `applySettings(_:to:)`,
  on classes it makes at run time),
  `VirtualStage` (`--virtual-display`: owns the display and the moved window,
  geometry, prepare/release, emergency restore), `HostShutdown` (signal
  sources + atexit, installed only with the flag in the CLI, always in the app;
  `releaseForQuit` for the app's Quit; `installKeyRelease` for the CLI's
  default path: a device's keys let go and a sized window goes back, then the
  signal's own end),
  `VirtualDisplaySelfTest`
  (`--virtual-display-selftest`), `Stats` (1 s lines while active, 30 s
  heartbeat when idle). Remote access: `OriginPolicy` + `InterfaceSnapshot`
  (who may use which door; pure), `RefusalSummary` (one refusal line a minute),
  `HostIdentity` (the `IdentityStore` protocol, `MemoryIdentityStore`, the TEST
  ONLY `FileIdentityStore`, `PairedDevice`, the lock-protected trust snapshot
  the door reads on the network queue), `KeychainIdentityStore` (Sill.app's),
  `PairingWindow` (pure), `RemoteServer` (the remote door), `Reachability`,
  `AddressList` (pure) and `RouterAddress` (read-only NAT-PMP/PCP),
  `RemoteAccess` (main actor; ties them together, signs kind 18; owns
  pairing for both doors: the ask, the cable's devices, Require pairing,
  Remove at both doors). Pairing at home (docs/home-pairing-plan.md): `Door`
  (admission at a TLS door, one class behind both listeners: the places
  waiting for admission and their deadlines, the backoff and its line, the
  verify block, the device gate, one pairing request per `sill-pair/1`
  connection; `RemoteServer` keeps the remote door's listener), `DoorPolicy`
  (who each door admits, the ask rule's six steps, `afterGate`,
  `isTestHost`: a host that does not advertise and is not Sill.app's own
  executable; `Places`, what waiting for admission costs an address and its
  IPv6 /64, and the places kept for addresses that proved a paired key; pure,
  `Tests/checks/door-policy`), `CableLink`
  Remove at both doors; names the sessions each cut-off closes to the
  coordinator as it decides, `onCutOff`, and says whether a session that
  registers later is still served, `stillServes`). Pairing at home (docs/home-pairing-plan.md): `Door`
  (admission at a TLS door, one class behind both listeners: the pending
  caps, the backoff, the verify block, the device gate, one pairing request
  per `sill-pair/1` connection; `RemoteServer` keeps the remote door's
  listener), `DoorPolicy` (who each door admits, the ask rule's six steps,
  `afterGate`, `stillServes` (a session registered behind a change that cut
  it off), `isTestHost`: a host that does not advertise and is not
  Sill.app's own executable; pure, `Tests/checks/door-policy`), `CableLink`
  (whether a connection came over the USB cable to an iPhone or iPad, from
  InterfaceSnapshot's IOKit reading, and the device's ID; pure,
  `Tests/checks/cable-link`), `CableReport` (`--print-cable`), `SessionLock`
  (an unlocked console), `TestHooks` (the door and pairing hooks a host that
  is not a test host ignores, one line each), `AskLimits` (PairingWindow.swift:
  one device-opened window at a time, three in 10 minutes, the quiet after
  the Mac's Cancel or a stop, an IPv6 asker's by its /64; `Tests/checks/ask-limits`) and
  `RequirePairingValue` (HostIdentity.swift: Require pairing's record, off
  only with the Mac's own signature). StreamServer's home door is plain (the
  CLI without --pairing), TLS (`Door(.home)`, `p` in its TXT record) or
  closed (no identity: fail closed), `HomeDoorMode`.
  `DeviceGate` (the device floor, "0" in every build so far, and a refusal's
  words and log lines; pure, checked with swiftc; the gate itself, which runs
  only above "0", is StreamServer's, with the TEST ONLY
  SILL_TEST_MIN_DEVICE_VERSION and SILL_TEST_GOODBYE).
  The Mac's menus (docs/menu-bar-plan.md): `MenuFormat` (a shortcut as the
  Mac draws it, "⇧⌘S", "fn ⌃F"; an item and a top-level menu as sent; pure),
  `MenuPolicy` (`MenuPath`, the ids; `MenuCache`, a menu's read kept 1 s,
  answering only under the title it was read under; `ShownTitle`;
  `RequestRate`; `RequestDeadline`, when a request can no longer be answered
  in time for its device; `SubmenuRecord`, the submenus a version has read at
  their places; `PressDecision`, only a leaf whose title now is the one shown;
  `TopLevel`; the refusals' words and log lines; pure; both checked by
  `Tests/checks/menus`), `MenuReader` (every Accessibility call for menus, on
  its own queue `sill.menus`: the top level, one menu's items under the title
  shown, walks checked against the version's record, a press; a 1 s timeout
  per element, 1.5 s a menu, and no item begun that would end past the
  request's deadline), `MenuMirror` (main actor: the target, the version, the
  subscribers (only they are served), one request at a time with its
  deadline, the cache and the kept elements; a cut-off device's waiting
  requests neither read nor made, `clientRevoked`; the TEST ONLY
  SILL_TEST_MENU_PID, honoured only by a synthetic host, makes a process's
  menus the test pattern's) and `MenuSelfTest` (`--menu-selftest[=APP]`,
  read-only).
  The Mac's pointer: `PointerControl` (who moves it, the Mac or the device
  whose input the host read last, with the settle for Sill's own motion; the
  fraction kind 26 carries; pure, `Tests/checks/pointer-control`) and
  `PointerWatch` (the host's sampling of it: PointerControl under a lock, the
  streamed source's rectangle, a regular-mode window's bounds re-read on
  `sill.pointer`, the TEST ONLY scripted pointer `TestPointerPath` and
  `PointerTestHooks`; `Tests/checks/pointer-watch`). StreamServer samples it at
  each tick, and at the stream's frame rate while it moves over the source and
  some device is sent it (`PointerWatch.samplerInterval`), and sends kind 26
  to every device not moving it; InputInjector notes each pointer and scroll
  post just before it and, on a synthetic host, posts nothing (`in.dry`).
  Trackpad gestures: `GestureChords` (kind 28's gesture as the Mac's own
  shortcut for its action, the first of its shortcuts that is on; the view
  Sill's last gesture opened, which the opposite gesture closes; the log line;
  the TEST ONLY `SILL_TEST_HOTKEYS` table; pure, `Tests/checks/gesture-chords`)
  and `SymbolicHotKeys` (the Mac's Keyboard Shortcuts read through SkyLight's
  two getters at each gesture, read-only); the coordinator takes four a second
  per connection, waits for a switch in flight, queues the chord behind held
  input, and on a host that does not advertise posts none (`in.gestureDry`);
  `InputInjector.chord` posts it (`in.gesture`), its key up with the HID
  state table's flags from before it (`KeyStrokes.chord`;
  `in.gestureModifiersLeft` if some stay).
  The Mac's sound (docs/audio-plan.md; a beta since 2026-10-20): `AudioPipeline` (the source it follows
  from `active`'s didSet, one transition at a time; on `sill.audio` the
  packetizer, the encoder, the epochs and the stamps; the status and kind 16's
  note; `prepare`, AAC-ELD's codec loaded once off `sill.audio` when Send Audio
  is on), `AudioCapture` (ScreenCaptureKit's audio-only stream of one app, or of
  every app but Sill's, bounded start and stop, the running stream under a
  lock; never run by a test),
  `SyntheticAudio` (a synthetic host's test tone; the TEST ONLY
  `SILL_TEST_AUDIO_CHUNK` and `SILL_TEST_AUDIO_PAUSE`), `TestTone` (440 Hz and a
  click at each whole second of the stamps' clock; pure), `AudioPacketizer`
  (blocks, stamps and segments, `AudioSourceRule`, `PCMLayout`,
  `AudioBufferTally`; pure, `Tests/checks/audio-packetizer`) and `AudioEncoder`
  (AAC-ELD, AudioToolbox only; `Tests/checks/audio-codec`). StreamServer sends
  kind 43 to the devices that play it on a send path of its own
  (`broadcastAudio`: never `inflight`; its bytes in every client's `pendingBytes`
  and `takenThisSecond`, so each device's LinkJudge sees them; `paceRemote`
  drops only frames).
  A sleeping display (issue #134): `DisplayWake` (which of a device's messages
  are a person at it, so the host declares user activity on the Mac for it, as
  a key press would: a session's connect every time, kinds 7, 8, 15, 25 and 28
  only 5 s or more after the last declaration, never a pick or any other kind,
  nor a bare pointer move within 2 s after the host's own stream restart or new
  frame size (`streamChanged`); a test host counts `disp.wakeDry` instead; what
  DisplayActivity says, `Report`: "Woke the display for …" only when the
  display read asleep before and on 0.5 s after, once for one wake, else
  "Declared activity for …" once a minute at most, and the refusal's, once; the
  TEST ONLY `SILL_TEST_USER_ACTIVE`; pure, with StreamMessage.swift and
  Input.swift, `Tests/checks/display-wake`) and `DisplayActivity`
  (IOPMAssertionDeclareUserActivity with kIOPMUserActiveLocal, or Remote under
  the TEST ONLY switch, on its own queue, the main display's sleep state read
  just before it and 0.5 s after, `disp.wake`; nothing held: the display sleeps
  again by the Mac's own setting); the coordinator's `handle` forwards every
  message to the rule (`deviceActive`), and `parameterSetsSent` its stream
  changes.
- `Sources/SillHostCLI/main.swift` — the CLI: flags, `dispatchMain` vs
  `NSApplication.run`, the Terminal permission hint; `--pairing` (the home
  door's TLS with pairing required, a throwaway identity, the code and link
  on its own stdout), `--print-cable` and `--no-clipboard`.
- `Sources/SillMenuBar/` — the app: `main.swift` (AppKit lifecycle, accessory
  policy), `AppDelegate` (launch order, Quit, the modal-loop rule), `AppModel`
  (owns the coordinator, presentation, App Nap guard, onboarding), `AppIdentity`
  (whether this launch is Sill.app itself, by its signing identifier, signature and bundle
  wherever it runs from, or the bare binary, the one test host; pure but for its reader,
  `Tests/checks/test-host`),
  `HostSettings` (UserDefaults; the presets are StreamProtocol's
  `QualityPreset`), `StatusItemController` (+ `MenuBuilder`), `StatusText`
  (all status copy), `StatusCard`, `StatusGlyph`, `SettingsWindow` (its
  height capped to the screen, issue #59) + `SettingsPanes`,
  `SettingsWindowFit` (how tall Settings may be on its screen and where it
  goes; pure, `Tests/checks/settings-window`), `Permissions`, `LoginItem`,
  `LogWindow`, `MainMenu` (key
  equivalents), `DebugHooks`, `AppLog` (its print shadow), `DevicesPane`
  (Settings › Devices: Require pairing, Show the pairing window to screen
  sharing, the paired devices, Remove and rename), `RemoteAccessPane`
  (Settings › Remote Access), `PairDeviceWindow` (the QR code and the typed
  code; the window a device's ask opens, and the cable notice),
  `PairingWindowSharing` (whether screen sharing shows that window: hidden
  unless Settings › Devices' switch is on, whoever opened it, and the
  window's `NSWindow.SharingType` for each, `.none` or `.readOnly`; issue #108;
  pure, `Tests/checks/pairing-sharing`), `PairingWindowAddress` (the address that window gives to type:
  Tailscale's name and IPv4 first, another VPN's IP only under this network's
  address; pure, checked with swiftc), `UpdatePolicy` (the update check's rules
  and words; pure, checked with swiftc) and `UpdateChecker` (main actor; asks
  GitHub's releases feed and times the checks; compiles on its own with swiftc).
- `Packaging/` — Sill.app's `Info.plist` and the development entitlements
  (get-task-allow only), the release's (`SillRelease.entitlements`:
  `com.apple.application-identifier`, the team and the keychain group, signed
  in only with `embedded.provisionprofile`, the Developer ID profile, which is
  git-ignored; docs/keychain-plan.md), and `ExportOptions-appstore.plist`, how
  the iOS app's archive is exported for App Store Connect. `Scripts/release-ios.sh`
  makes the iOS app's build: the Release archive (automatic signing on team
  9B2KKVM937, or none with `--sign-at-export` and `--unsigned`), the export
  (destination export; `--upload` adds a second one whose destination is
  upload), the .ipa checked (version and build, the export compliance key,
  the Local Network, Bonjour and camera entries, the privacy manifest, an
  Apple Distribution signature, an App Store profile, no get-task-allow, the
  required-reason APIs against the manifest), `--bump`, `--api-key`,
  `--print-version`, `--privacy-report`, `--build-number N` (xcodebuild's
  `CURRENT_PROJECT_VERSION=N` for the run, never written to the project: the
  nightly's and testflight.yml's commit count) and `--whats-new FILE` (with
  `--upload` and `--api-key`, What to Test once processed, through
  `Scripts/asc.swift`); it refuses any Xcode before 27.1
  or after 27 (the iOS 27.1 SDK the iPhone Duo's layouts need; the app it
  checks must say DTPlatformVersion 27.1 or later),
  with `--bump` or `--upload` a working tree with changes (new files in
  iOSClient and Sources/StreamProtocol count), and an App Store address in
  `SillLinks.swift` that isn't one, and sourced it only defines its
  functions (docs/release-checklist.md, TestFlight). `Scripts/make-app.sh`
  builds, iconizes, signs and installs the bundle (with `SILL_UNIVERSAL=1`
  arm64 and x86_64, each in its own scratch path under `.build/universal`,
  joined with lipo, for an Intel tester, #62; off by default, so releases
  stay arm64, and `release.sh`'s `check_signature` reads every slice);
  `Scripts/release.sh`
  (M6) makes the downloads from it:
  `make-app.sh --release`, `make-dmg.sh --prepare` (the image's tool and
  background, before anything goes to Apple), a zip (`ditto -c -k
  --keepParent`), Apple's notary service (`notarytool submit --wait`, the
  profile in `SILL_NOTARY_PROFILE`), the ticket stapled, the zip made again
  with the ticket inside, and a copy unpacked from it checked with `stapler
  validate` and `spctl` ("Notarized Developer ID"); then the disk image of the
  stapled app (`make-dmg.sh --sign`), notarized on its own, stapled, and
  checked (`hdiutil verify`, `stapler validate`, `spctl -t open --context
  context:primary-signature` as "Notarized Developer ID", mounted `-nobrowse`
  in `$TMPDIR` and the Sill.app inside checked as the zip's copy); it prints
  `.build/Sill-<version>.dmg` and `.zip` with their SHA-256. A dry run makes
  the image too, from the app before stapling, signed with the same identity.
  It refuses to start, before building, without a
  Developer ID Application identity (`SILL_SIGN_IDENTITY`, checked against the
  keychain) or the profile, or on a HEAD without the tag v‹version› (the
  update check's), or with `SILL_RELEASE_TAG` (the release workflow sets it)
  not `v<CFBundleShortVersionString>` or naming another commit (`--check-tag`
  checks only that), and `--dry-run` stops before notarytool (the profile and
  the tag only warned about: it sets `SILL_RELEASE_DRY_RUN=1`, with which
  `make-app.sh --release` builds an untagged commit); it refuses a build
  without Assets.car and AppIcon.icns. `--publish` makes the GitHub Release in
  `SILL_RELEASE_REPO` (default Saffsanity/sill, the only repository the update
  check reads), asks `gh api repos/<repo>` whether it can reach the repository
  (`gh auth status` asks GET /user, which the Actions token can't answer), and
  refuses to start unless origin's tag v‹version› names HEAD (gh would make a
  missing tag from the default branch's tip; not asked in the release
  workflow, whose checkout is the run's own commit with every tag, stopping
  when its tag moved, and keeps no credentials); in
  Saffsanity/sill it passes gh `--verify-tag`, anywhere else it warns that no
  Sill.app will offer the release. It uploads `Sill.dmg`, `Sill.dmg.sha256`,
  `Sill.zip` and `Sill.zip.sha256` (the zip kept for older links: the download
  page names the image since 0.3.1). Sourced, it only defines its functions.
  `release.sh --nightly [--dry-run | --publish]` (docs/release-checklist.md,
  "Nightlies"): main's head built, signed, notarized and checked as a release,
  without the tag rule (make-app.sh's `SILL_RELEASE_NIGHTLY=1`) and only with
  the Developer ID profile, as `.build/Sill-nightly-<yyyymmdd>-<sha7>.dmg` and
  `.zip` (`SILL_NIGHTLY_DATE`, UTC); `--publish` puts them and their `.sha256`
  on the rolling pre-release `nightly` (made when missing, its tag moved to
  the commit, never latest, `SILL_NIGHTLY_KEEP` newest nightlies kept, its notes
  `SILL_NIGHTLY_NOTES` or nightly-notes.sh's, ending in the commit's sha in a
  comment that `nightly_last_sha` reads for the skip rule).
  `Scripts/nightly-notes.sh --markdown F --whats-new F`: a night's words for both
  apps, the pull requests merged on main's first-parent line since the newest
  tag `v<version>` (titles from `gh pr list`, else the commits), Markdown without
  @mentions for the pre-release, What to Test within 4,000 bytes.
  `Scripts/asc.swift` (Foundation and CryptoKit; compiled with swiftc or run as a
  script): App Store Connect's API for TestFlight with an ES256 token from the
  .p8 key (`groups`, `build-state`, `whats-new`, `distribute`: wait for
  processing up to 90 minutes, What to Test, every internal group, the public
  beta group only with `--public-beta` and `SILL_NIGHTLY_PUBLIC_BETA=true` in its
  environment, Beta App Review only right after that); the token goes only to
  api.appstoreconnect.apple.com (or a stand-in on 127.0.0.1 in tests) and is
  never printed.
  `Scripts/make-dmg.sh --sign IDENTITY APP DMG` (`-` for ad hoc) makes the
  image: an HFS+ volume "Sill" (not APFS: Finder names the background by an
  HFS+ alias record, and Finder-made and current third-party images are
  HFS+) with the app (`ditto`), a link to /Applications, `.background/`
  (design/DMGBackground.svg rendered by Quick Look at 1x and 2x, cropped,
  joined by tiffutil into one TIFF; cached in `.build/dmg`) and
  `.VolumeIcon.icns` (the app's AppIcon.icns, with the root's custom-icon
  flag); its window laid out by a `.DS_Store` that `Scripts/dmg-layout`
  (Swift, compiled into `.build/dmg`; DSStore.swift, FinderAlias.swift,
  DMGLayout.swift) writes without Finder and reads back (`check`): 660 x 432
  points, the picture's 400 and macOS 27's 32-point title bar
  (`DMGLayout.titleBar`; `Tests/checks/dmg-layout` checks the writer); converted
  to ULFO (LZFSE, read-only), signed (identifier `me.saffer.sill.dmg`, a
  timestamp unless ad hoc) and checked mounted (exactly five items at the
  root, the link, the layout, the app byte for byte). Mounts are `-nobrowse`
  in a new folder in `$TMPDIR`: mounted under the home folder, fseventsd
  writes `.fseventsd` onto the image as it unmounts. `--prepare` only builds
  the tool and the background. Sourced, it only defines its functions.
  `Scripts/sillclient.py` is the wire-format test client
  (timed `--set=K=V[,K=V]@T` kind 17 changes with tokens 1, 2, 3…,
  `--raw17=JSON@T`, `--raw9=JSON@T` (a literal viewport, kind 9),
  `--pick=none|desktop|window:ID@T`, `--stats`,
  `--expect=K=V[,…]` against the last kind 16, which it prints one per line,
  and each second's frames with their kB (the encoder's output);
  `--host`, `--device`, `--big-payload`, `--flood`, `--stop-ping@T`,
  `--stop-read@T`, `--pairing-wanted@T`, `--keyframe@T` (kind 44); the remote door with `--tls
  --identity=DIR`, `--pair-url`, `--pair-code`, `--pin=FP|none` and
  `--expect-tls-fail`, printing kinds 18, 20 and 22; pairing at home with
  `--pair-ask[=cable]`, `--then-code=FILE`, `--pair-hold=S`, `--pair-cancel`,
  `--pair-v=N` and `--expect-pair=R`; the Mac's pointer with
  `--pointer` (each kind 26), `--move=X,Y@T`, `--tap=X,Y@T`, `--key=USAGE[,HOLD]@T`
  and `--input=JSON@T` (a literal kind 8), the input flags only to a
  `--synthetic` host on this Mac (lsof and ps); trackpad gestures with
  `--gesture=NAME[,FINGERS]@T` and `--raw28=JSON@T` (kind 28), likewise only to
  a `--synthetic` host on this Mac; the Mac's menus with
  `--menus` (the subscription; each kind 24 on one line),
  `--fetch=ID[xN][,TITLE]@T` (the title the menu was shown under, by default
  the one listed for the id), `--press=ID[,TITLE]@T`, `--raw25=JSON@T`,
  `--raw27=JSON@T` and
  `--expect-menus=TITLE[,…]`, the fetches and presses only with
  SILL_TEST_MENU_PID in its own environment (against any other host they
  would open and choose the menus of whatever app is in front); every
  argument is checked before it connects, and a bad one exits 2).
  `Scripts/menufixture.swift` (TEST ONLY) is the menu gates' app: an AppKit
  menu bar of known menus (Probe's marks, shortcuts, a disabled item, a
  retitled one, a slow action, Deep three levels, 300 and 600 items), the
  prohibited policy so it can never take the front, its windows off every
  display (the label's, and Slow Close, whose close holds its main thread 4 s
  and keeps it open, as a close asking about unsaved changes does), every
  delegate call and action logged (an action also as "PRESS
  'item' in 'menu'"), SIGUSR1 and SIGUSR2 giving Probe › Rebuilt a new NSMenu,
  SIGHUP inserting an item at the top of Probe in place and SIGALRM giving
  Probe a new NSMenu; `menufixture label PID` reads its label over
  Accessibility. `Scripts/menu-check/run.sh` runs the real MenuReader and
  MenuMirror against it with no host and no encoder (safe while Sill.app
  streams; it needs Accessibility for whatever runs it, and an unlocked screen),
  and its `close` step WindowSizer's Close (with WindowRestore.swift, which
  WindowSizer needs since #75) against Slow Close: back within 1 s, as no answer.
  `Scripts/audio/` is the
  encoder-free sound harness (docs/audio-plan.md H5, H6, H8): `build.sh` makes
  `.build/audio/host` (the working tree's StreamServer and the sound's host
  files with `main.swift`: fake frames, the test tone, both doors on
  127.0.0.1) and `.build/audio/audiocheck` (`Scripts/audiocheck.swift`, the
  harness's device: every kind 43 decoded with iOSClient/AudioDecoder.swift and
  each click found at its stamp), refusing a binary that links a media
  framework but AudioToolbox; `run.sh [--cases a,b]` runs the gate cases and
  `summarize.py` judges them.
  `Scripts/restore-probe/run.sh` (TEST ONLY; issue #57) drives the real
  `WindowSizer.resize` and a fitted window's way back (WindowRestore's `fit`
  and `stop` through `WindowSizer.AXWindows`) against a window of its own
  (`owner.swift`, built into a bundle that never activates and ordered behind
  every window), frames before, during and after, fourteen steps (its app
  stopped with SIGSTOP at a fit and at a stop among them); the front app must
  not change. It needs Accessibility, Screen Recording and an unlocked screen,
  and exits 2 saying which is missing. `Scripts/sillrelay.py` is a
  shaping passthrough relay (`--listen 0 --to HOST:PORT [--delay-ms N]
  [--rate-mbps R] [--blackhole-after S] [--record PREFIX]`; TLS passes
  through). `Scripts/pacing/` is the remote pacing harness
  (docs/remote-bundle-plan.md §3 and §11): `build.sh [BASE]` makes two
  throwaway packages under `.build/pacing`, BASE's StreamServer.swift (default
  origin/main) and the working tree's, each with its neighbours (the Door's
  files too since pairing at home, and `PACING_SERVE_BEFORE_HOME_PAIRING` for a
  BASE from before it, whose `serve` takes no hello) and fed fake
  frames by `main.swift` (no encoder: a binary that links a media framework is
  refused; on cue, new sizes, a still window or a restart); `run.sh [--full]
  [--cases a,b] [--repeat N] [--base REF] [--list]`
  runs each case on both, host → `bottleneck.py` (a downlink rate on a virtual
  clock, a delay, a finite queue, rate changes) or `Scripts/sillrelay.py` →
  `device.py` (the device's reader, pings, stats and liveness;
  `--liveness-bytes` for MessageReader's rule), everything on 127.0.0.1 and
  each run only while the load average is under 20; `summarize.py` prints the
  table and each case's gate.
  `Scripts/encoder-check/` holds the encoder's checks ("The 33 fps plateau"):
  `run.sh` builds and runs those that never touch an encoder (the probe and
  encoder checks, which run in real time with tight bounds and so stay out of
  CI, and through `Tests/checks/encoder-mailbox` and `encoder-slowstate` the
  mailbox and slow-state checks and their mutants; it refuses any binary that
  links VideoToolbox), and `verify-hardware.sh` the hardware runs against a
  base commit built from `git archive` (parity, stream, harness, probe,
  keyframe), each only while `no-device.sh` finds no device connected to
  Sill.app; outputs go to `.build/encoder-check/`.
  `sillclient.py --hello=VER[,PROTO]` (or `none`) sends a device's hello
  first (`--hello-delay=S` S seconds after the connection is up, for a change
  made while a host's device gate holds it), and kind 22's new fields are
  printed. `Scripts/sillfeed.py PORT`
  is a fake GitHub releases feed for the update check's tests (`--tag`,
  `--status`, `--etag`, `--draft`, `--prerelease`, `--html-url`, `--body`,
  `--big`, `--slow`, `--reset`, `--redirect`, `--set-cookie`,
  `--all-headers`; `GET /__control?key=value` changes them while it runs).
- `site/` — the website, for GitHub Pages at the domain in `site/CNAME`:
  `index.html`, `download.html` (links the newest GitHub Release's `Sill.dmg`
  and `Sill.dmg.sha256`; never edited per release), `privacy.html` (the policy
  App Store Connect and the app link to), `support.html`, `terms.html` (the terms of service: the
  Apache license, Apple's EULA for the App Store copy, no warranty, no fees;
  linked in every footer), `style.css` (system
  fonts, light and dark) `icon.svg` (a copy of design/AppIcon.svg) and `preview.jpg` (the
  1200 × 630 share image that the Open Graph and Twitter card tags in every
  page's head name). No
  scripts and nothing loaded from elsewhere: every page's
  Content-Security-Policy is `default-src 'none'`. Links are relative and
  name a file (`download.html`; Home is `index.html`, since `./` opens nothing
  from the folder), so it renders from the folder; GitHub Pages also serves
  each page without `.html`, the form the app and App Store Connect use
  (`/download`, `/privacy`, `/support`). Remote Access paragraphs sit between
  `<!-- Remote Access` and `<!-- /Remote Access -->`, to cut for a release
  without it. `docs/release-checklist.md` is the order of work: the one-time
  setup (Developer ID, notary credentials, hosting and DNS, the App Store
  Connect record) and every release's steps.
- `Sources/VirtualDisplayProbe/` — CLI experiment for milestone 3; run it from
  Terminal (needs Screen Recording + Accessibility): `.build/release/VirtualDisplayProbe "Activity Monitor" --seconds 20`.
- `iOSClient/` — `Sill.xcodeproj` and its sources: `StreamClient` (Bonjour: a
  network browser and, when `DiscoveryPolicy` says, a nearby peer-to-peer one,
  each made again after the background and after a failure (`cameForward`,
  `rebuildBrowser`); `FoundMac` rows; connection, parsing, reconnect, the move of a session over
  AWDL to the network, a live session following the best path
  (`followBestPath`: to the cable, to Wi-Fi, made again over either), a remote
  session's move home (`moveHomeIfListed`, `MoveKind.fromRemote`), ping,
  generic `send`, and the pointer: kind 26 judged on its queue, `renderPointer`,
  `setOwnPointer`, `sendFromKeyRow`, a hand-over's carry-over),
  `SessionLink` (the session's connection and the one door out
  to the Mac; the moves' fenced hand-overs, which chain, and the hold of a move
  off a lost path: `handOver`, `hold`, `adopt`, `unhold`; the input messages
  counted for the session's connection, `inputsOnSession`, which a kind 26's
  `seen` is judged against; Foundation and Network only, checked with swiftc),
  `MessageReader` (the session's reader: each header, then the payload in
  pieces of at most 256 KB, every piece a sign of life for the liveness check;
  Network and StreamProtocol only, checked with swiftc),
  `DiscoveryPolicy` (when to look nearby, the rows and the word each ends in,
  the session's route word for the Settings panel,
  when a reconnect may take a Direct row, when a session over AWDL moves to
  the network, when a live session at home moves to the cable or to Wi-Fi or is
  made again (`pathPlan`, `upWait`; a remote one only home: `moveHome`, over
  TLS pinned to the saved Mac's key: `moveHomeTrust`, to a row chosen and
  refused by row: `moveHomeRow`, `HomeRows`, its kind 18 held to the floor taken
  as the move starts: `HomeMoveInfo`), the memory of Macs with
  Direct Wireless on, the Remote rows and when a lost saved Mac is dialed away
  from home; when a browser is made again and what the rows show meanwhile
  (`rebuildBrowser`, `browserFailures`, `browserResults`), when the automatic
  reconnect dials a row that stays listed and its line (`redialRow`,
  `reconnectLine`), and when the device asks for the Desktop by itself
  (`autoDesktop`; issue #69); pairing at home's rows and words, a tap's dial, the device's
  cable check and how a session at home ends: `rowWord`, `homeDial`,
  `onCable`, `rowMac`, `reconnectEnd`, `macInfoNamesSession`,
  `removalRevokes`; the TXT record each row is read with, its result's own or else the last one that
  result carried while the same browser lists it, forgotten once it leaves and when a browser is made
  again (`rowRecords`, `RowRecordKey`: the cable pulled, 2026-10-27); pure, checked with swiftc),
  `StreamScreen`
  (landscape: top bar, thumbnails, drawer, Aa, Keyboard, Desktop; layout
  selection by size incl. Duo outer display, and `DuoLayout.phoneArrangement`,
  the idiom: which arrangement `.outerPortrait` draws; `DuoLayout.isPortrait`,
  the laptop layouts, where the trackpad's pointer shows), `PortraitStreamScreen`
  (portrait in two arrangements: the halves, the picture over the window bar,
  the key row and the trackpad, at the inner display's size and, for an iPad
  window narrower than 600 pt, the compact one with the key row in two lines;
  and a phone held upright, from `PhonePortraitLayout`; the key row's two sets,
  twelve and six), `PhonePortraitLayout` (a phone upright, `.outerPortrait` on
  an iPhone, as rects from the stream screen's size: the picture's fixed 16:10
  pane, row 1's five buttons in their band, the strip, six caps, the trackpad
  and its vertical span, the Aa ruler, the drawer and the Settings panel across
  row 1, and the dim, and the Menus button ending the strip's row (`menus`,
  `stripBesideMenus`; no Sound button anywhere since 2026-10-27); with Larger
  Picture's keyboard (`keyboard`, from
  `keyboardHeight(for:)`, only while a window streams: `largerPicture(switchOn:
  streaming:)` and `Streaming`, and only where it is larger: `largerPictureGains`,
  `offersLargerPicture(screen:)`) no strip, the room over the keyboard, Menus in
  row 1 (`buttonsBesideMenus`), the drawer above row 1, the pane at the
  picture's shape (`pane(video:)`) and its span (`trackpadSpan(video:)`); pure,
  `Tests/checks/phone-portrait`), `DuoPosture`
  (the iPhone Duo's posture and the rules that follow from it, docs/iphone-duo-plan.md:
  `FoldInfo`, inferred before iOS 27.1 or the fold's band; the laptop pose's
  split at the real fold and open flat's at the picture's shape, the book
  pose's bar, one page for a card (on its targets' page), the connect column
  and the room above the laptop pose's fold, the pairing overlay and the
  window lights; the stream screen's status bar (hidden on the inner display
  in every pose); the hinge from the fold before its first report; the
  harness's stand-in and the displays' safe areas; pure, `Tests/checks/duo`;
  pbxproj AB01/FB01), `DuoPostureReader` (iOS 27.1: `onHingeChange` at the
  app's root into `\.duoEnvironment`, `DuoPosture.read`, the `.division`
  region as a screen's own GeometryReader sees it; StreamScreen hands it to
  its layouts as `\.duoFold` and hides the status bar with `duoStatusBar`;
  AB02/FB02),
  `InputOverlay` (direct touch, Pencil, keyboard, scroll momentum; each input
  says what drew this device's pointer; hardware keys through `ForwardedKeys`,
  the characters too while `KeyTyping` says the Mac types them, let go when the
  overlay stops taking keys; Esc's key commands; the iPad's
  trackpad's and a wheel's scroll pans beside the finger pan, one scroll path
  (`scroll(_:at:translation:velocity:from:)`, a finger's drag in Reverse
  Scrolling's direction, `ScrollDirection`); a `UITextInput` since #138: an
  input method's composition over the picture, sent once chosen, dictation and
  its corrections, ⌃Space to iPadOS with keyboards in two languages, Scribble
  declined, what is composed sent first and what was typed forgotten when the
  Mac's caret may move (`forgetTyped`, from `StreamClient.onCaretMayMove`, before
  it goes out: a pick, a launch, a window's button and a menu item follow the
  queued input, `sendAfterInput`), and what came before a Return or a Tab it types
  made final (`TextComposition.fence`), what was typed kept;
  `InputOverlayProxy`, who holds
  the keyboard, carrying out `HardwareKeyboardPolicy`; `HardwareKeyboardMonitor`,
  GameController's keyboard), `TextComposition` (what the input view holds for
  iPadOS's text system: the composition, what was typed since the Mac's caret
  last moved, corrections as backspaces and text, none from a range taken before
  a forget or a trim (`generation`) and none that would change what went before
  a Return or a Tab typed (`fence`, `refusal`), what the text system selects of it
  replaced by its next edit (`selection`: Korean's syllables built again);
  `TextInputRules`, which input
  moves the Mac's caret (no typed text, a Return or a Tab among it), where a
  Return or a Tab typed ends (`endOfReturnOrTab`) and whose ⌃Space it is;
  `KeyTyping`, who types a hardware keyboard's characters: the Mac, as keys,
  when it says `keyRepeat`, for a keyboard in the Latin alphabet whose input
  method composes nothing (`composingLatin`: Vietnamese, Hawaiian) with
  nothing composed or latched, else iPadOS's text system (#162's letters); pure,
  `Tests/checks/text-composition`; pbxproj AC0138/FC0138), `HardwareKeyboardPolicy` (when the stream's input
  view holds the keyboard for a hardware keyboard and when it is the person's
  own; and `PointerScroll`, where a trackpad's or a wheel's scroll goes, the
  pointer's place as it began, and its readings added up; pure,
  `Tests/checks/hardware-keyboard`; pbxproj AC01/FC01), `KeyChords`
  (`KeyModifiers`; a
  shortcut with its modifiers' own keys pressed around it, the Spotlight key's
  ⌘Space, the trackpad's modifier keys around a click; `ForwardedKeys`, a
  hardware key's up after its down, its way (a key, or the text system's)
  decided at the down by `KeyTyping` (`characterUsages`; a letter with Caps Lock
  on carries Shift, `carried`), and Esc's key command sent once beside
  pressesBegan; `HeldCap`, the portrait key row's esc, tab and arrows down from
  a finger's touch to its release, so the Mac repeats them (#162); pure,
  `Tests/checks/key-strokes` with the
  host's KeyStrokes), `TrackpadView` (the relative pad: its
  cursor a `PadCursor`, from the anchor; a recognizer that only counts fingers;
  `verticalSpan`, a phone's width ÷ 1.6; its two-finger scroll and coast in
  Reverse Scrolling's direction, `ScrollDirection`; and the DEBUG input test), `StreamZoom` (pinch to zoom on
  the picture, 1× to 5× around the point between the fingers, Photos-like, and `StreamZoom.Stroke`, which two
  fingers belong to; pure, `Tests/checks/stream-zoom`; `StreamZoomModel` and `ZoomedStreamView` in
  HEVCDisplayView.swift scale the picture inside the pane's clip; StrokeObserver's `onTouch` feeds it; every
  touch and scroll lands through it: PR #196, issue #65), `ThumbnailHold` (how long a window's thumbnail is
  held before its lights show and its drag can start: 0.2 to 2 s in tenths, 0.5 s unless changed, the words
  of the Settings panel's stepper; pure, `Tests/checks/thumbnail-hold`; WindowStrip and HoldDragOverlay
  in StreamScreen.swift take it, issue #113),
  `HEVCDisplayView` (shared display view, the one pointer sprite + DEBUG HUD;
  the picture's interruptions on the network queue: `checkLayer` flushes a layer
  that failed, could not decode a frame or needs a flush to decode again, at each
  frame, at its notifications and when the window becomes active, and says so,
  `onNeedsKeyframe`, then `onPictureBack`, both, back first, for a keyframe the
  flush throws away; DEBUG `-SillLayerFail` and `-SillKeyframeLost`),
  `KeyframeRecovery` (when the device asks the Mac for a keyframe, kind 44,
  after its picture was interrupted: one ask per interruption while its keyframe
  is due, again when none came within `answerWait`, max(4 s, 4 round trips);
  only while the picture's window is active and something streams; 2 s apart,
  4 to 32 s for a picture that keeps failing or a Mac that never answers, 2 s
  again after a trip away; pure, `Tests/checks/keyframe-recovery`; pbxproj
  AC11/FC11),
  `DiagnosticsHUD` (client stats reporter),
  `StreamClient+Viewport`, `ContentView` (connect screen with rows ending in
  Wired, Wi-Fi, Direct or Remote, the hint and Search Nearby, Add a Mac…, and
  a footer along the bottom, "Needs the free Sill app on your Mac." with links
  to the download, support and the privacy policy, which open in Safari (one
  line while they fit, else the download link over the other two, as wide as
  the column); the column stays where it would be without the footer
  (centred; in the top half on the Duo's 710×1000, the footer still along the
  bottom; at the top while a field has the keyboard), rises only to keep 24 pt
  clear of the footer, never closer than 16 pt to the top, and scrolls above
  it, 16 pt from the top, when even that does not fit (a 12 pt fade, then
  12 pt clear, both inside the gap); one scroll view
  whatever the fit (`ColumnOverFooter`, measuring a hidden copy of the
  footer), so a fit that changes never builds the card anew (its fields, the
  camera); + DEBUG harness, and `InputScript`, `-SillInputScript`'s steps),
  `SillLinks`
  (the site's addresses, written once; getsill.app is live since 2026-09-25;
  and the App Store address for a Mac's update notice, the App Store Connect
  record's since PR #27),
  `MockCatalog` (harness data and the settings cases), `HostSettingsLedger`
  (the Mac's settings with this device's unanswered picks; pure logic, checked
  with swiftc), `HostSettingsPanel` (the Settings panel; the route line, Away
  from home, the away line in the header, the link's callout and its button,
  the footnote, the slow-link callout for older Macs), `AwayCopy` (every
  string of away from home and the link on the device, which callout shows,
  and `LinkLine`, the stream screen's line over time; pure,
  `Tests/checks/away-copy`; pbxproj A801/F801). Remote access: `DeviceIdentity`
  (the device key in the Keychain, carrying out `DeviceKeyPolicy`),
  `SavedMacs` (pure; `homeTLS` and `revoked` for pairing at home; with
  `DeviceKeyPolicy`, the device key's rules: when the launch clears the saved
  Macs, when a key is made, when a key made is used; `Tests/checks/remote-rules`'
  `launch.swift`, #140),
  `RemoteDialPolicy` (pure), `RemoteConnector`, `StreamClient+Remote`
  (pairing, remote dials, the reconnect order, links), `StreamClient+Home`
  (pairing at home: `DeviceTLS`, the one TLS builder for every connection to
  a Mac, the session gate at the first window list, the ask, the cable's
  proof-less ok, the proofs sent to a row, how a session at home ends;
  pbxproj A601/F601), `AddMacCard` (the card, the fields, `EscapeKey`; the
  home card for a row), `CodeScanner` (VisionKit),
  `PairingOverlay` (Pair This iPad…), `GoodbyePolicy` (the words and the
  reconnect after a session ends, a Mac's notice included; pure, checked with
  swiftc). The Mac's menus (docs/menu-bar-plan.md §7): `MacMenuState` (one
  connection's view: the top level, the menus asked for and the choices sent,
  each opened menu's completion settled exactly once, the rows and sections;
  pure, `Tests/checks/menu-state`), `MacMenuElements` (the one builder of
  `UIMenuElement`s for the iPad's bar and the button: uncached deferred
  elements, `UIAction` leaves with the Mac's shortcut as the subtitle, never a
  `UIKeyCommand` or `UICommand`), `SillAppDelegate` (`SillApp`'s
  `@UIApplicationDelegateAdaptor`; only `buildMenu(with:)`) with `MacMenuBar`
  (where the Mac's menus go in the iPadOS 26 bar, once per build, every
  anchor looked up first), `MacMenuHub` (whose session the bar shows: the
  app's one window's while exactly one window scene is connected, none with
  two or more; from each scene's `WindowSessionObserver`; asks for a rebuild)
  and `MacMenuButton` (the bars' Menus button: the bar's look, and
  `MacMenuTrigger`'s clear UIButton with the pull-down over it; `fits`, where
  a bar holds it and still a whole thumbnail).
  `PointerPresence` (the rules of the one pointer sprite: the Mac's
  arrow while the Mac or another device moved it last, this device's own only
  for the portrait trackpad; a kind 26's freshness; the network queue's feed
  with a hand-over's carry-over; the key row keeping what shows; the portrait
  pad's cursor; pure, `Tests/checks/pointer-presence`; pbxproj A301/F301),
  `TrackpadGestures` (which stroke on the glass goes silent and which arms,
  the gesture decided as one of its three fingers lifts, and whether it goes
  to the Mac; pure, `Tests/checks/gestures`; pbxproj A701/F701) and, in
  InputOverlay.swift, `StrokeObserver` (the recognizer on both surfaces that
  feeds it every direct touch and takes none). The clipboard:
  `StreamClient+Clipboard` (the subscription at the first window list that
  says `clipboard` and on a move's new connection, `stop` when the switch goes
  off, the Mac's text written `.localOnly` for 10 minutes, the chip's look when
  Sill becomes active and its time while it shows, Paste's send and its
  receipt, a ping whose pong says the Mac read it; pbxproj AC64/FC64) and `ClipboardChip`
  (the chip and `ClipboardPasteButton`, the system's Paste control;
  AD64/FD64); StreamScreen places the chip, the Settings panel's This iPad
  group has Share Clipboard and Paste on ‹Mac›. The
  first-run tour: `TourPolicy` (its steps and targets per layout, the halves,
  a phone's rows and sideways; when it shows by itself, what it remembers,
  what a session decided and the reconnect's, a rotation mid-run, the crease,
  where the card goes, every word; pure, Foundation and CoreGraphics,
  `Tests/checks/tour`) and `TourOverlay` (the dim with the lit cutout and its
  ring, the card placed by a Layout, the targets' preference in the stream
  screen's named space `sill.screen`, `TourStore` for `Sill.tourSeen` and
  `Sill.tourSkipped`, `TouchWatcher`, a recognizer on the window that counts
  every touch and takes none, and DEBUG `TourDebug`); StreamScreen runs it
  (targets, the rule's inputs, the layer above the layouts and under the
  pairing overlay, Take the Tour from the Settings panel's last row). The
  connect screen's tiles and groups (issue #116, PR #117): `ConnectionList`
  (rows or tiles, `Sill.connectionStyle`, tiles by default since 2026-10-27
  (`defaultStyle`; a stored choice always wins); when a session's
  end keeps a picture, `takesPreview`: only with tiles, from the session's own
  window in front, for a saved Mac; the saved Mac a row stands for, `tileMac`:
  its tag's or record's, else the one it is taken for by name, so every row
  of one Mac (Wired, Wi-Fi, Direct, Remote) shows its one picture and is listed
  under its group; what a launch or a change of style does,
  `previewPlan`: the list hides the pictures and keeps their files, tiles show
  them again, only the files of Macs no longer saved go; the picture's size,
  `previewPixels`, 640 pixels wide at most, and `looksBlack`;
  `keepsDecodedPicture`; whether Disconnect asks the Mac for a keyframe
  first, `freshPicture`, every Mac whatever version it says; group names,
  `Sill.macGroups`, and the sections' order; a superseded record's group; the
  pictures' file names; pure, with KeyframeRecovery's spacing,
  `Tests/checks/connection-list`; pbxproj AF01/FF01). ConnectScreen draws them
  (the switch beside the title, the tiles, a saved Mac's Group menu and New
  Group…), StreamClient+Remote keeps them (`savePreview` with complete file
  protection in Library/Caches/SillPreviews, `syncPreviews` at launch and at a
  change of style; only Remove Preview Picture and Forget delete a Mac's),
  and StreamClient takes the picture: the session's last keyframe with its
  parameter sets (`lastKeyframe`, on the network queue, one frame, dropped at
  `tearDown`), decoded at the session's end by `KeyframePicture` (a
  VTDecompressionSession of its own, off the main thread, 1 s at most;
  pbxproj AF02/FF02), never a snapshot of the screen, which a device draws
  black where the video is; Disconnect waits up to 300 ms for a fresh keyframe
  first (kind 44, every Mac; one that skips it, Sill for Mac 0.5.1, costs that
  pause, its picture the keyframe kept).
  `AudioDecoder` (AAC-ELD to a buffer per channel, one packet at a time;
  AudioToolbox only), `AudioPlayout` (the sound's timing; pure,
  `Tests/checks/audio-playout`), `AudioOutput` (its queue, the decoder and the
  engine; no video frame handed to its queue before the session's first format, the last 32 kept
  for the guard) and `StreamClient+Audio` (this device's mute, `soundMuted`, the Settings panel's
  Mute; `macHasSound`, whether it shows): pbxproj AA01–AA04; the host's `audio-codec` check and
  the sound harness's device compile AudioDecoder too. The Settings panel (`HostSettingsPanel`)
  holds the sound's two switches: the Mac's group's Send Audio (for every device, with a "Beta"
  tag) and Mute right under it; no bar has a Sound button (Noah, 2026-10-27).
  `Info-Debug.plist` is the Debug configuration's Info.plist: Info.plist's
  keys, with `_silltest._tcp` beside `_sill._tcp` for the harness's
  `-SillServiceType` (Release declares `_sill._tcp` alone).
  `PrivacyInfo.xcprivacy`, a resource of the target, is the privacy manifest:
  it declares UserDefaults (CA92.1), `systemUptime` (35F9.1) and the active
  keyboards (54BD.1: `UITextInputMode.activeInputModes`, which decides whether ⌃Space is
  iPadOS's keyboard switch or the Mac's, #138; found by release-ios.sh's check on 2026-10-29,
  which refuses an export App Store Connect would refuse, ITMS-91053), and any new use of a
  required-reason API (file dates, disk space, `mach_absolute_time`) must add its category
  and reason there before the next upload. New files need their four pbxproj entries by hand.
  Swift 5 language mode.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.
- `docs/DEVELOPMENT.md` — building, running and testing from source; the
  README's developer material until 2026-09-25, so a plan's "README" means a
  section there: the toolchain, make-app.sh, Sill.app's menu and Quality, the
  CLI's flags, the iOS project, Permissions (the TCC reset), settings from a
  device, Direct Wireless, pairing at home (the cable, Require pairing, older
  builds, starting over), remote access (setup, troubleshooting, reset), the
  test tools in brief (Build and run below has them all), measuring latency,
  troubleshooting (slow, frozen, the encoder), releasing, known limitations.
- `README.md` — the public front page: the site's lede, links to getsill.app
  and its download, support, privacy and terms pages, the App Store badge
  (live since 2026-10-10), requirements, how it works, tips, building from
  source in brief,
  contributing, the license. `LICENSE` — the Apache License 2.0.
  `design/screenshots/` — the README's screenshots: the App Store's iPad set at
  half size. Their raw URLs go to open-source app lists: keep the names.
  `.github/FUNDING.yml` — the Sponsor button: GitHub Sponsors (a `ko_fi:`
  line joins it once there is a Ko-fi handle). Tip links live there, in the
  README's Tips and on the site, never in the iOS app. `SECURITY.md` — how to
  report a vulnerability (support@getsill.app, never a public issue) and what
  is in scope. `.github/ISSUE_TEMPLATE/` — issue forms: a bug report, an idea,
  a question, no blank issue. `.gitignore` also leaves out signing keys,
  profiles, keychains and design/reel/.
- `.github/workflows/` — GitHub Actions on the `xcode-27` runner (macOS 27
  with Xcode 27, a public preview; the only image with Xcode 27). `ci.yml`:
  pull requests and pushes to main that touch more than documents or the site
  (`design/` counts: `dmg-layout` reads its SVG), and by hand; `swift build -c release`,
  `Tests/checks/run-all.sh`, the iOS app for the generic simulator (Debug,
  arm64, `CODE_SIGNING_ALLOWED=NO`; with Xcode 27.1, its beta while the image
  has no 27.1 release), and the CLI's paths that exit before the
  host starts (`--internet` alone, exit 2; `--print-reachability`); by hand
  with "mutants", each check's mutants in a job of its own. `release.yml`: a
  pushed tag `v*`, or by hand with one; verify only (the tag, the checks,
  `make-app.sh` signed ad hoc, zipped, and `make-dmg.sh`'s image of it, ad hoc
  too, as two artifacts) unless the repository
  variable `SILL_SIGN_IN_CI` is `true`, then, in the environment `release`
  (only `v*` tags, Noah its required reviewer; its first step names a missing
  secret and refuses a run by hand not started from its tag; it checks out
  the run's own commit, `github.sha`, and stops when the tag no longer names
  it), the Developer
  ID .p12 into a temporary keychain, the notary key stored as a profile in it, the Developer ID
  profile decoded from `SILL_PROVISION_PROFILE` into
  `Packaging/embedded.provisionprofile` (since the nightlies), `release.sh
  --publish`, Apple's notary logs kept as an artifact (`include-hidden-files:
  true`: upload-artifact skips whatever is under a folder whose name starts
  with a dot, `.build` included), and the keychain deleted in an always()
  step. Secrets,
  variables, rotation and costs: docs/release-checklist.md, "Releasing from
  GitHub Actions". `testflight.yml`: by hand from main only (the environment
  `nightly`); `release-ios.sh
  --unsigned` without an App Store Connect key, `--sign-at-export` with one
  (the secrets `SILL_TESTFLIGHT_KEY_ID`, `SILL_TESTFLIGHT_ISSUER_ID`,
  `SILL_TESTFLIGHT_KEY_P8`, an Admin key: cloud signing, no certificate or
  profile stored), and `--upload` too when the variable `SILL_TESTFLIGHT_IN_CI`
  is `true` and the commit is on main's first-parent line (another branch's
  count can be a later nightly's), the build number the commit count
  (`--build-number`); the .ipa is
  the artifact for 14 days (docs/release-checklist.md, "TestFlight from GitHub
  Actions"). `nightly.yml`: 09:17 UTC while the variable `SILL_NIGHTLY` is
  `true`, and by hand (`verify_only`); decide (the skip rule against the
  pre-release's sha, the date, the build number, the notes once), Sill for Mac
  (`release.sh --nightly --publish` with `SILL_SIGN_IN_CI`, else ad hoc
  artifacts), Sill for iPhone and iPad (`release-ios.sh --build-number`, the
  upload with `SILL_TESTFLIGHT_IN_CI`, then `asc.swift distribute`: every
  internal group, the public beta group only while `SILL_NIGHTLY_PUBLIC_BETA` is
  `true`); only main builds: both jobs run in the environment `nightly` (only
  main, no reviewer), which holds the nine secrets, none of them a repository
  secret (docs/release-checklist.md, "Nightlies", "Secrets and variables").
  `.github/actions/select-xcode` —
  selects the newest Xcode of the `version` asked for (27; CI's build 27.1)
  whose folder is not a beta and prints `xcodebuild -version`; with
  `allow-beta: 'true'` (CI's build alone, never a build for App Store
  Connect), a version with no release yet takes its newest release candidate
  or beta; without one, CI warns and takes the newest Xcode there and a
  release (`fallback: false`) fails (CI only: it runs `sudo xcode-select`). The runner's `bash` is 3.2: try `run:`
  steps with `/bin/bash`. Actions are pinned by commit hash.
- `Tests/checks/` — the pure checks, a folder each: `main.swift`, `run.sh`
  (compiles the app's files it names with swiftc into `.build/checks/<name>/`
  and runs; `--mutants` runs `mutants.py`, passing only when every mutant is
  caught), and `build.sh` where a check compiles a module (StreamProtocol's
  sources with `import StreamProtocol` stripped), or a `module.txt` naming the
  files `module.py` compiles as one module (pairing at home's checks):
  `addresses`, `ask-limits`, `audio-codec` (the host's AAC-ELD encoder,
  packetizer and tone with the device's decoder, in memory; AudioToolbox only),
  `audio-packetizer`, `audio-playout` (iOSClient's AudioPlayout on a simulated
  clock), `away-copy`, `away-quality`, `away-wire`, `cable-link`, `capture-scale`, `catalog-look`, `clientlink`,
  `clipboard`, `compatibility`,
  `connection-list`, `device-gate`, `display-wake`, `dmg-layout` (Scripts/dmg-layout's `.DS_Store` and alias
  writer, against Finder's own layout of the file, make-dmg.sh's layout
  arguments and the SVG's size and edge), `door-policy`, `duo` (DuoPosture;
  `tour` and `phone-portrait` take the Duo's real sizes too), `encoder-mailbox`,
  `encoder-slowstate`, `fence`, `firewall` (FirewallRule), `gesture-chords`, `gestures`, `goodbye`,
  `hardware-keyboard` (iOSClient's HardwareKeyboardPolicy),
  `encoder-slowstate`, `fence`, `gesture-chords`, `gestures`, `goodbye`,
  `hardware-keyboard` (iOSClient's HardwareKeyboardPolicy and PointerScroll),
  `home-device`, `home-model`, `home-records`, `home-txt`, `installed-apps`
  (InstalledApps on a fake applications folder), `key-repeat` (the host's
  KeyRepeat with KeyStrokes, against a model of InputInjector's glue and a
  clock), `key-strokes` (the
  host's KeyStrokes and the device's KeyChords, against a model of the Mac's
  HID state table and of a Mac from before), `keychain`, `keyframe-recovery` (iOSClient's
  KeyframeRecovery, against a model of the event history), `ledger`, `link-judge`,
  `menu-state` (iOSClient's MacMenuState), `menus` (the host's MenuFormat and
  MenuPolicy, and MacMenu.swift's JSON), `message-reader`, `origin`,
  `pairing-address`, `pairing-sharing` (Sill.app's `PairingWindowSharing`),
  `phone-portrait`, `pointer-control`, `pointer-presence`,
  `pointer-watch`, `policy` (with its `home.swift`), `protocol`,
  `remote-rules` (with its `home.swift`), `settings-window` (Sill.app's
  `SettingsWindowFit`), `stream-zoom` (iOSClient's StreamZoom), `test-host` (Sill.app's AppIdentity with
  IdentityStorePlan), `text-composition` (iOSClient's TextComposition with
  StreamProtocol's Input.swift), `tour`, `update-policy`, `virtual-display-api`
  `SettingsWindowFit`), `stream-zoom` (iOSClient's StreamZoom), `text-composition` (iOSClient's TextComposition with
  StreamProtocol's Input.swift), `thumbnail-hold` (iOSClient's ThumbnailHold), `tour`, `update-policy`, `virtual-display-api`
  (VirtualDisplay.swift whole, as VirtualDisplayProbe compiles it: its surface,
  `SettingsWindowFit`), `stream-zoom` (iOSClient's StreamZoom), `text-composition` (iOSClient's TextComposition with
  StreamProtocol's Input.swift), `tour`, `update-policy`, `viewport-bounds`
  (StreamProtocol's ViewportBounds: what a host takes of a device's viewport; and
  ClientStats.lateSince),
  `virtual-display-api` (VirtualDisplay.swift whole, as VirtualDisplayProbe compiles it: its surface,
  TypeEncoding and Runtime.method's decision, on classes made at run time, against
  the encodings measured on Apple silicon and reported from Intel machines),
  `window-restore` (WindowRestore's rule and sequences against a stand-in Mac,
  with a copy of the coordinator's glue around them) (the two encoder checks refuse a binary that links
  VideoToolbox). `run-all.sh
  [--mutants] [-v] [name…]` runs them and exits
  with the number that failed (a folder whose `run.sh` is not executable
  fails); `common.sh` is sourced by each `run.sh`; `README.md` lists what each
  compiles and the checks that belong to open branches. A change to a checked
  file updates its check (and a mutant's pattern) in the same commit.
- `Tests/touchrig/` — the touch rig (docs/trackpad-gestures-plan.md §9.2): the
  real `TrackpadView.swift` and `InputOverlay.swift` in a scratch simulator
  app, driven with synthesized touches (`TouchSynth`, private UIKit calls, test
  only, never in the app), every event logged; `run.sh [--rev REV] [--switch
  off] NAME` builds and runs it on a simulator of its own
  (`SILL_TOUCHRIG_SIM`), `compare.py` judges a run against the surfaces
  before, and a stroke made right after a gesture against the same stroke
  made fresh.
- `Tests/duorig/` — TEST ONLY, private interfaces, simulator only: folds and
  turns the iPhone Duo simulator with Device Hub's own events (usage page
  0xFF61, usage 0x5B, an IOCFSerialize dictionary from
  `com.apple.Virtualization.VirtualMachines`), posted from a virtual HID
  service inside the simulator (`xcrun simctl spawn`); `run.sh build`, `run.sh
  UDID pose <closed-upright|closed-side|flat-portrait|flat-landscape|laptop|book>`,
  `run.sh UDID shot <pose> FILE.png`, `hinge`, `orient`, `watch`; only a
  booted iPhone Duo simulator, by UDID (its README).
- `Tests/keyrig/` — TEST ONLY, private interfaces, simulator only: a hardware
  keyboard and a mouse for the iOS Simulator, key presses, pointer moves and
  wheel scrolls posted from a virtual HID device inside the simulator (`xcrun
  simctl spawn`, as duorig), which UIKit routes as a real one's
  (pressesBegan, key commands, the text system, GameController, hover, scroll
  pans); `run.sh build`, `run.sh UDID keys SPEC` (`wait:S` among its steps holds
  a key: `13:down,wait:2,13:up`), `run.sh UDID point SCRIPT`;
  only a booted simulator of your own, by UDID (its README has what it showed:
  after its keys UIKit there counts a hardware keyboard for good).

## Build and run

```
swift build -c release
swift run -c release SillHost              # nothing streams until the iOS app picks a window
swift run -c release SillHost Safari       # optional: preselect a matching window
swift run -c release SillHost --synthetic  # Desktop streams a test pattern; no Screen Recording needed
swift run -c release SillHost --encoder-selftest   # is the hardware encoder alive? 5 s, exits
swift run -c release SillHost --virtual-display   # picked windows stream from their own HiDPI display (off by default in the CLI; on in Sill.app)
swift run -c release SillHost --virtual-display-selftest   # create/destroy one display, report what sees it ([Hz] [WxH] after it: `60 800x830`)
swift run -c release SillHost --direct-wireless   # also over peer-to-peer Wi-Fi (AWDL): devices without a shared network (off by default)
swift run -c release SillHost --audio       # Send Audio (a beta) for this run: the streamed app's sound to devices that play it (with --synthetic, a test tone; off by default; a device's Settings panel turns it on or off too)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 .build/release/SillHost --synthetic --audio   # the test tone on loopback; sillclient.py PORT 8 desktop --hello=0.6 --audio counts it
Scripts/audio/run.sh                        # the encoder-free sound harness and its gates (~7 min; no encoder, capture, speaker or device)
swift run -c release SillHost --remote      # the remote door for this run on any free port (--remote=PORT), a throwaway identity; the code and link print here
swift run -c release SillHost --remote --internet   # also admit paired devices from outside this Mac's networks and VPNs
swift run -c release SillHost --print-reachability  # the addresses a device would get away from home, then exit
swift run -c release SillHost --pairing     # the home door speaks TLS, pairing required, a throwaway identity; the code and link print here (with --remote, one pairing for both doors)
swift run -c release SillHost --print-cable # what the cable rule reads on each interface, and whether the console is unlocked; read-only, then exit
swift run -c release SillHost --menu-selftest=TextEdit   # the menus a device would be sent for that app (a pid, or the start of its name), read once; read-only
python3 Scripts/sillclient.py PORT 5 none --pair-ask --then-code=$T/code --identity=$T/a   # a device's ask at a TLS home door, then the code the host printed (saved in $T/code)
python3 Scripts/sillclient.py PORT 8 desktop --set=bitrate=25000000@3 --expect=bitrate=25000000   # a device's settings change
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_STILL_AFTER=3 .build/release/SillHost --synthetic   # the Desktop still from 3 s on: a device's picture comes back only through its keyframe request
python3 Scripts/sillclient.py PORT 8 desktop --keyframe@3   # kind 44: "Keyframe for …" on the host, and the summary's "keyframes at" shows the one it brought
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_STILL_AFTER=3 SILL_TEST_KEYFRAME_IGNORE=1 .build/release/SillHost --synthetic   # the first keyframe request ignored, as a Mac from before kind 44 ignores every one: the device asks again 4 s later
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1 SILL_TEST_DESKTOP_FAIL=2 .build/release/SillHost --synthetic   # the first 2 Desktop starts fail, as ScreenCaptureKit's did on 2026-10-28 (1: the host's one more try streams; 2: a device asks again 10 s later)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic   # a scripted pointer on the test pattern, on 127.0.0.1 alone, never the hardware encoder
python3 Scripts/sillclient.py PORT 6 desktop --pointer --move=0.25,0.25@3   # each kind 26 as it arrives; input goes only to a --synthetic host
SILL_TEST_INPUT_LOG=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic   # prints each event a dry run would post ("Test input: key 49 up (none)")
python3 Scripts/sillclient.py PORT 3 desktop --input='{"key":{"hidUsage":44,"down":true,"modifiers":1048576}}@1' --input='{"key":{"hidUsage":44,"down":false,"modifiers":1048576}}@1.05' --tap=0.5,0.5@1.5   # an older device's Spotlight key, then a tap
python3 Scripts/sillclient.py PORT 6 desktop --key=80,1.2@2   # ← held 1.2 s (pinging four a second, as a device): with the input log, "Test input: key 123 down (none)", repeats from 0.5 s on ("… repeat (none)", 30 a second on this Mac), then its up
python3 Scripts/sillclient.py PORT 8 none --gesture=swipeUp@3 --gesture=swipeDown@4   # a synthetic host logs "Gesture from …: swipe up → Mission Control (shortcut 108: key 160, fn) (not posted: a test host)"
SILL_TEST_LOOPBACK=1 SILL_TEST_HOTKEYS='108=off,173=off' .build/release/SillHost --synthetic   # TEST ONLY: the gestures read this table (over macOS 27's own; `defaults` alone) instead of this Mac's shortcuts
swift run -c release SillHost --no-clipboard  # share nothing of the clipboard with devices (on by default, as in Sill.app)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_PASTEBOARD=me.saffer.sill.test.x SILL_TEST_CLIPBOARD_LOG=1 .build/release/SillHost --synthetic   # the clipboard on a pasteboard of its own (never this Mac's), each decision printed with sizes
SILL_TEST_NO_SCREEN=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 .build/release/SillHost --synthetic   # TEST ONLY: ScreenCaptureKit never asked (no window list, no thumbnails), so a host an agent runs asks macOS for no screen recording
SILL_TEST_FIREWALL=executable SILL_TEST_NO_SCREEN=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 .build/release/SillHost --synthetic   # TEST ONLY: the macOS firewall's answers canned (executable|bundle|both|all|off|allowed|unreadable, or a file holding one, read at each check): "Firewall: the macOS firewall blocks Sill’s executable, …"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate; …/socketfilterfw --listapps; …/socketfilterfw --getappblocked PATH   # the firewall, read-only as any user; never --unblockapp, --add, --remove or --set* (they change it, with sudo)
python3 Scripts/sillclient.py PORT 6 none --clipboard --copy=hello@2 --expect=clipboard=none   # subscribe, send text as a device's Paste does; each kind 32 printed
SILL_TOUCHRIG_SIM='Sill touchrig' Tests/touchrig/run.sh new && Tests/touchrig/run.sh --rev origin/main base && Tests/touchrig/compare.py .build/touchrig/base.log .build/touchrig/new.log   # the surfaces under synthesized touches
Tests/checks/run-all.sh                 # every pure check, as CI runs them (~5 min; --mutants adds the mutants, well over an hour)
Scripts/pacing/run.sh                   # remote pacing and the link's judge, this tree against origin/main, no encoder, all on loopback (~25 min; --full ~45; --list)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_ORIGIN=vpn SILL_TEST_PATTERN=noise .build/release/SillHost --synthetic --remote   # an away session whose stream follows its quality
Scripts/make-app.sh                     # .build/Sill.app, signed with the Apple Development identity (~2 s unchanged)
Scripts/make-app.sh --install --open    # Noah: replace /Applications/Sill.app (a running one quits first), launch it
SILL_UNIVERSAL=1 Scripts/make-app.sh    # .build/Sill.app for Apple silicon and Intel (arm64 and x86_64) for an Intel tester (#62): twice the build time; the x86_64 slice has not streamed on an Intel Mac
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' Scripts/make-app.sh --release   # M6
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' SILL_NOTARY_PROFILE=sill-notary Scripts/release.sh [--dry-run]   # M6: the notarized download (docs/release-checklist.md)
Scripts/release-ios.sh                  # the iOS app for App Store Connect: archive, export .build/ios/export/Sill.ipa, check it; uploads nothing
Scripts/release-ios.sh --bump --upload  # Noah: the next build to TestFlight (docs/release-checklist.md, TestFlight; --privacy-report, --print-version)
Scripts/make-dmg.sh --sign - .build/Sill.app .build/Sill.dmg   # the download's disk image of any build, ad hoc (release.sh makes the real one)
python3 -m http.server 8000 --directory site   # the website at http://localhost:8000
Scripts/encoder-check/run.sh            # the encoder checks that never touch an encoder (safe while Sill.app streams)
Scripts/menu-check/run.sh               # the menus' reader and mirror against Scripts/menufixture.swift, no host, no encoder (needs Accessibility)
Scripts/restore-probe/run.sh            # TEST ONLY: a window Sill sized goes back, against a window of its own (needs Accessibility, Screen Recording, an unlocked screen)
Tests/duorig/run.sh UDID pose book && Tests/duorig/run.sh UDID shot book book.png   # TEST ONLY: fold and photograph an iPhone Duo simulator (laptop, flat-portrait, flat-landscape, closed-upright, closed-side)
Tests/keyrig/run.sh UDID keys 29,04,e3:down,1a,e3:up && Tests/keyrig/run.sh UDID point 'move 300,200|wheel -3'   # TEST ONLY: Esc, a and ⌘W from a hardware keyboard, then a wheel's notch, inside a simulator of your own
SILL_TEST_ENCODER_RECYCLE=0 swift run -c release SillHost   # =0 keeps every hardware session, =1 replaces one in the slow state, as by default (A/B on the real Desktop: --synthetic moves every frame and never reaches the slow state)
Scripts/encoder-check/verify-hardware.sh harness   # USES THE HARDWARE ENCODER; skips each run while a device is connected
```
Needs Xcode as the active developer directory with its license accepted; with
Command Line Tools only, add `--build-system native`.
First run prompts for Screen Recording: the CLI's belongs to Terminal (or
whatever launched it), Sill.app's to Sill itself.
Sill.app: the log is `~/Library/Logs/Sill/Sill.log` (`tail -F`, not `-f`: at
10 MB it moves to Sill.1.log; Show Log… in the menu); settings are `defaults
read me.saffer.sill.mac` (maxFPS, captureScale, bitrate, prioritizeSpeed,
virtualDisplay, directWireless, sendAudio, shareClipboard, updateCheck,
showPairingWindowToScreenSharing; the update check keeps
updateLastCheck, updateETag, updateLatestTag and updateLatestURL), and a launch
argument such as `-maxFPS 60` or `-updateCheck 0` overrides one for one run. A device's change from its Settings panel is saved there too, like a
menu click; the CLI keeps a device's change until SillHost quits. Test arguments for the bare binary (`.build/release/SillMenuBar`,
defaults domain `SillMenuBar`; delete it after): `--synthetic` (test pattern,
off Bonjour; the port is in the "Status: Test Pattern Mode" line),
`-SillLogFile <path>`, `-SillSetAfter '<s> key=value[,key=value][; <s> …]'`,
`-SillQuitAfter <s>`, `-SillRenderPreviews <dir>` (panes, cards, glyphs,
menu.txt; no permission needed), and for the Settings window's height
`-SillSettingsAfter '<s> <tab>|close|report|end|height=<points>[; …]'` (opens it,
then prints its frame, the pane's whole height and how much shows),
`-SillTestScreenHeight <points>` and `-SillSettingsShot <dir>`
(docs/DEVELOPMENT.md, Test arguments for the bare app). The update check, in the bare binary (which
has no version and never checks without these) and the app: `-SillUpdateFeed
http://127.0.0.1:P/latest` (a feed on this Mac only: 127.0.0.1, ::1 or
localhost; `Scripts/sillfeed.py P` serves one; test pattern mode checks only
such a feed), `-SillUpdateVersion 0.3.0`, `-SillUpdateNow 1` (one check at
start, as Check Now), `-SillUpdateInterval <s>` (24 h become s seconds, the
retry s/24), `-SillPrintMenuAfter <s>` (the status menu as it would open, and
Settings › General's update line, in the log), `-SillSetAfter '<s>
updateCheck=0'`. Never run a test against GitHub. To make Sill.app check again at
its next launch: `for k in updateLastCheck updateETag updateLatestTag
updateLatestURL; do defaults delete me.saffer.sill.mac $k; done`. Render previews from
`.build/Sill.app/Contents/MacOS/Sill` to see what Sill.app looks like: only the
bundle's copy records the real SDK (make-app.sh sets it with vtool; see Current
step), and the bare binary draws the pre-26 look. `--encoder-selftest` and
`--virtual-display-selftest` work in the app too.
iOS side: open `iOSClient/Sill.xcodeproj`, set your team, run on a real
device on the same Wi-Fi (or with the Mac's Direct Wireless Connection on).
AWDL, headless and without touching a running Sill.app: the synthetic hosts do
not advertise, but `SILL_TEST_SERVICE_TYPE=_silltest._tcp` registers them as
"Sill test ‹pid›" under that test type (never `_sill._tcp`, so no device sees
them) with the listener's own peer-to-peer flag, and prints which one it got;
`SILL_TEST_SWAP_FAIL=port|all` makes a replacement's same-port (and any-port)
bind fail; `SILL_TEST_PEER_TO_PEER_INTERFACE=en0` counts a client scoped to that
interface as one on peer-to-peer Wi-Fi, so a test client on the Mac's own en0
link-local address (`ifconfig en0`, `fe80::…%en0`; Python's socket takes it)
stands in for a device on awdl0 when Direct Wireless turns off (a local
connection to the Mac's own awdl0 address never became ready, so awdl0 cannot
be tested headless); all three are honoured only by a host that does not
advertise. `dns-sd -t 3 -includeAWDL -B _silltest._tcp local` lists a
registration that includes AWDL a second time on awdl0's index (`python3 -c
'import socket; print(socket.if_nametoindex("awdl0"))'`, 16 here). dns-sd
options go before the command: `dns-sd -R … -includeAWDL` registers a TXT
record "-includeAWDL" and sets no flag. The kernel's count of AWDL services:
`/usr/bin/log show --last 1m --style compact --predicate 'process == "kernel"
AND eventMessage CONTAINS "BonJourTrig"'` ("ValidSvc N" once a second; a
registration with AWDL adds 2, a peer-to-peer browse 1); `log` is a zsh
builtin, hence `/usr/bin/log`, and `process == "kernel"` keeps the log tool's
own line out. Enable and disable lines ("Enabling AWDL due to Mdns") show only
when nothing else holds AWDL. Keep AWDL-on tests under 20 s and on test types.
Remote access, headless: TEST ONLY variables, honoured only by a host that
does not advertise: `SILL_TEST_REMOTE_DIR=<dir>` (the identity and trust list
in a 0700 directory instead of memory or the keychain; the bare app's
`-SillPairAfter <s>` leaves `pairing.url` and `pairing.code` there, 0600, never
printed), `SILL_TEST_PAIRING_TTL=<s>`, `SILL_TEST_BACKOFF_SECONDS=<s>` (the backoff a TLS door
gives an address whose connections waited unadmitted or were refused, five failures in a minute:
a test client's `--pair-hold`s, refused handshakes or connections it keeps closing, from 127.0.0.1,
meet it, "Home door backed off 127.0.0.1 for 300 s: …"), `SILL_TEST_ORIGIN=vpn|internet` (loopback
counts as that origin),
`SILL_TEST_REMOTE_ORIGIN=vpn|internet` (the same at the remote door alone, so
one loopback host serves a device away and one at home: away from home's
H8 and S4) and `SILL_TEST_NO_ROUTER=1` (never ask the router; set it on every
headless host). Away from home and the link, headless (docs/remote-bundle-
plan.md, PR B): `SILL_TEST_PATTERN=picture:<path>` gives a synthetic host a
still picture for its Desktop (any image ImageIO reads, filling the frame:
photographs of a device, docs/iphone-duo-plan.md); `SILL_TEST_PATTERN=noise`
gives it a square of noise, so its stream follows the quality (on the software encoder about 14
frames a second, 3.6 Mbit/s at Low and 10.6 at Balanced), for a test of the
link through `sillrelay.py --rate-mbps 5`; `sillclient.py` prints `away=` and
`link=` on each kind 16, and `--expect` knows `awayBitrate`,
`awayCaptureScale`, `homeBitrate`, `homeCaptureScale`, `thisConnectionAway`,
`awayRunning` and `linkState`.
The Mac's pointer, headless: every synthetic host is a dry run (its input is
counted as `in.dry`, never posted, and activates or raises nothing) and never
reads the real pointer. TEST ONLY, honoured only by a synthetic host (anywhere else one
line says it is ignored): `SILL_TEST_POINTER_PATH=<file>` is a scripted
pointer on the test pattern, lines `T X Y` (seconds since the stream's first
sample, points in the 1512×949 pattern, outside allowed; `#` comments; at most
10,000 steps and 1 MiB, a bad file refused whole with one line): the test
pattern then has a pointer, a test client's input lands in the pattern's space
and a dry-run pointer event moves the scripted pointer (the newer of it and a
step wins); `SILL_TEST_NO_SCREEN=1` makes the window catalog leave ScreenCaptureKit alone (an empty
window list, no thumbnails, no display lookup), so a test host with a client connected asks
macOS for no screen recording: every ScreenCaptureKit call counts against the responsible app's
grant (Claude's, for a host an agent runs), and macOS reminds the person once a month and after
every rebuilt binary; set it on every headless host whose test needs no real window.
`SILL_TEST_SOFTWARE_ENCODER=1` starts on the software encoder, with
no launch probe and no re-check, so a test never touches the hardware encoder
(60 fps at most: a 120 fps sampler test needs the hardware, and so the
no-device check); `SILL_TEST_INPUT_LOG=1` prints each event the dry run would
post, "Test input: key 49 down (command)" with the flags it was made with, and
a pointer or scroll event with those the last keyboard event would have left
in the HID state table, a button's with where it goes ("Test input: left mouse
down (none) at 756,474"), a scroll's with its point deltas, phase and place
("Test input: scroll dy -12 dx 0, gesture changed (none) at 833,442": positive
dy moves the content down, so the sign shows which way a device's scroll went,
and every event of one scroll lands at one place), and each
check a key's up arms ("Test input: key 55
up: the table read again in 0.25 s for command"): what a device's keys and
buttons leave for its next click (KeyStrokes), without posting anything; and
where a device the Mac stops serving stops landing input ("Test input: iPad is
no longer served: only the up of a key or a button it holds down goes from
here on.", RevokedInput).
A sleeping display, headless: a test host declares no user activity and counts
`disp.wakeDry` where a real one would declare (`sillclient.py`'s connect, a tap,
a key; never a pick, nor a move right after a restart). TEST ONLY
`SILL_TEST_USER_ACTIVE=remote`, taken by every real host and Sill.app too
(`open --env SILL_TEST_USER_ACTIVE=remote /Applications/Sill.app`, Sill quit
first), declares `kIOPMUserActiveRemote` instead of Local; it acts on this Mac's
display, so it is Noah's to try (docs/DEVELOPMENT.md, A sleeping display).
The device floor, headless: `SILL_TEST_MIN_DEVICE_VERSION=1.2` raises the floor
of a host that does not advertise (a device below it, or one that sends no
hello, gets kind 22 "update" and is closed; a value that does not parse is
ignored with one line), and `SILL_TEST_GOODBYE='<JSON Goodbye>'` makes its
refusals send that payload instead (a reason the device does not know).
Pairing at home, headless: `SillHost --synthetic --pairing` (the bare app's
home door always speaks TLS, as Sill.app's does) with `SILL_TEST_REMOTE_DIR`,
`SILL_TEST_NO_ROUTER=1`, `SILL_TEST_SOFTWARE_ENCODER=1` and
`SILL_TEST_LOOPBACK=1`; the CLI prints its code and link, and again after each
ask. The door and pairing hooks are TEST ONLY and honoured only by a test host
(DoorPolicy.isTestHost: one that does not advertise and is not Sill.app's own
executable; anywhere else TestHooks prints one "ignored" line for each set),
and so are the ones above (SILL_TEST_SERVICE_TYPE and the rest):
`SILL_TEST_CABLE_INTERFACE=<if>` counts a client scoped to that interface as
one on the cable to an "iPad" (serial TEST) and lets this Mac's own address
there through, so a client at this Mac's link-local address on it
(`sillclient.py --host=fe80::…%<if> --pair-ask=cable`) stands in for a device
on the cable, and the simulator's `-SillCableTest 1` for the device's side
(lo0's `fe80::1%lo0` keeps such a test on this Mac; it needs a listener there,
which SILL_TEST_LOOPBACK's 127.0.0.1 alone is not); `SILL_TEST_LOCKED=1` makes
the Mac locked; `SILL_TEST_ASK_QUIET=<s>` shortens the 10 minutes of quiet
after the Mac's Cancel or a stop; `SILL_TEST_ASK_FROM_THIS_MAC=1` skips the
ask rule's step for an ask from this Mac itself (answered `openOnMac` unless a
window is open, and lighting no menu item), so a test client on this Mac opens
windows; `SILL_TEST_REQUIRE_PAIRING=0` (the CLI's) turns Require pairing off
at `--pairing`'s door for the run, so an unpaired device's session can be
tried (`sillclient.py --tls --identity=DIR --pin=none`). The bare app takes
`-requirePairing NO`, `-SillSetAfter '<s> requirePairing=0|1'`,
`-SillCancelPairingAfter '<s>[; <s> …]'` (the window closed as its Cancel
does), `-SillCableNoticeAfter <s>` (the cable notice for a sample device) and
`-SillMenuAfter '<s>[; <s> …]'` (the status menu in the
log, line by line). Sill.app itself ignores every `-Sill…After` hook,
`-requirePairing` and `SILL_TEST_REMOTE_DIR` with one line each (any process
can start it with arguments and its grants); `-SillRenderPreviews`,
`-SillLogFile` and the encoder's variables still work there. Require pairing
and the trust list live in the login keychain (service
`me.saffer.sill.remote`, accounts `paired-devices` and `require-pairing`,
beside the key "Sill Remote Access"), never in UserDefaults; Settings ›
Devices' Remove forgets one device, and deleting those items makes this Mac
new to every device. Two hosts under one Bonjour name (a Mac that took
another's name, the security scan's finding 3): run each without
SILL_TEST_SERVICE_TYPE (whose registration is "Sill test ‹pid›") and advertise
it in turn with `dns-sd -i lo0 -R "Studio f3" _silltest._tcp local PORT
r=<16 base64url characters> p=0`, on lo0 alone (on every interface the
simulator dials this Mac's other addresses first, which a loopback host never
answers); the bare `SillMenuBar --synthetic -requirePairing NO`, under a name
of its own and with `-SillLogFile`, is an open door.
The Mac's menus, headless: `swiftc -O Scripts/menufixture.swift -o
$T/menufixture -framework AppKit`, then `$T/menufixture serve $T/fixture.log
60` (it exits by itself, 120 s at most, and can never take the front) and a
synthetic host with `SILL_TEST_MENU_PID=<its pid>` (honoured only by a host
that does not advertise; "Test menus: …" at start): the test pattern's menus
are then the fixture's, read and pressed without activating it. `python3
Scripts/sillclient.py PORT 20 desktop --menus --fetch=4@3 --press=4.0@5` (with
SILL_TEST_MENU_PID in the client's environment too) prints each kind 24 on a
line, and `$T/menufixture label PID` what the last press set ("A"); `kill
-HUP` inserts an item at the top of Probe in place (the ids below it move: the
host's next read of a moved place moves the version), `-ALRM` gives Probe a
new menu, and `-USR1`/`-USR2` give Probe › Rebuilt one.
`--menu-selftest=menufixture` reads it. Presses go only to the fixture, and a
real app's menus are read only with `--menu-selftest=TextEdit`, never a bare
`--menu-selftest` (the frontmost app); the plan's §10 has the gates.
The bare app takes `-remoteAccess 1 -remotePort P`, `-SillSetAfter '3
remotePort=P2'`, `-SillPairAfter <s>` and `-SillUnpairAfter <s>`; its
`-SillRenderPreviews` adds the Remote Access pane's states and the pairing
window's. A session through a shaped link: `python3 Scripts/sillrelay.py
--listen 0 --to 127.0.0.1:P --delay-ms 150 --rate-mbps 2`, then
`sillclient.py RELAYPORT 90 desktop --tls --identity=$T/a --stats` after
`--pair-url=URL` once. Never let a test binary take a connection from another
machine: the Application Firewall prompts. `SILL_TEST_LOOPBACK=1`, honoured only
by a host that does not advertise, makes both doors of a test host listen on
127.0.0.1 alone ("Test listener: loopback only …"; `lsof` lists
`127.0.0.1:PORT`); a device on this Mac, the simulator included, and the test
clients reach it by 127.0.0.1. Reset the app's remote settings with
`for k in remoteAccess remotePort internetAccess remoteAddressName
remoteDevicesSeen; do defaults delete me.saffer.sill.mac $k; done`.
Debug harness (simulator; the iPhone Duo's from the iOS 27.1 runtime, folded
by Tests/duorig): launch arguments `-SillLayout 951x669` (inner landscape) /
`669x951` / `466x678` / `678x466` (the cover), each with the safe area its
display gives Sill, the status bar's strip included but on the stream screen
upright with `-SillHinge half` or `flat` (`-SillSafeArea T,L,B,R` sets
another; the first guesses, `1000x710` / `710x1000` / `500x710` / `710x500`,
have none), `-SillHinge
closed|half|flat` (the hinge and a 40 pt fold across the middle of the longer
side; without it the harness knows no hinge, even on the Duo's simulator),
`-SillLive 1` (real client inside the frame), `-SillDrawer 1`,
`-SillActive none|desktop|<windowID>` (mock), `-SillHUD 1` (diagnostics overlay),
`-SillSettings 1` (the Settings panel open), `-SillMacMenu
code|blender|long|stale|noaccess|none|slow|timeout|refuse` (the mock Mac's
menus; `code` by default, VS Code's ten), `-SillMenusOpen 1` (the Menus
pull-down opens after launch) or `-SillMenusOpen 'File/Open Recent'` (opens
on that menu, each level fetched on the way), `-SillMenuPress 'File/Save'`
(chooses that item once the menus are in; both live too, but only on the test
app's menus through a test host: `-SillConnect` to a loopback address, no host
version, menufixture's top level; anything else prints "refused"),
`-SillMenusAt <s>` and `-SillMenusCloseAfter <s>` (when the pull-down opens,
and closes after it), and on an iPad `-SillMenuBarLayout perMenu|replace|one`,
`-SillMenuDump 1` (the main menu's root after each build, on the console),
`-SillMenuBuildTwice 1` and `-SillMenuNoView 1` (the insertion's guards),
`-SillSecondWindow 1` (a second window 2 s after launch: the bar then gets
none of the Mac's menus; the console's "menus: …" and "menubar: …" lines say
what happened), `-SillSettingsCase
default|cli|software|custom|vdproblem|vdstream|legacy|pending|timeout|direct|
directlink|nodirect|wired|noroute` (the mock Mac's settings; it answers a pick
after 0.35 s; the readout's route is Wi-Fi except `directlink` Direct, `wired`
Wired, `noroute` none, and `remote`, `remoteinternet` and `remoteslow` none,
where the route line says how), away from home's and the link's settings cases
`away|awaymixed|awayhome|linkbehind|linkmixed|linklow|linkstalled` (the header's
away line, the footnote, the callout; `linkstalled` shows none) and
`-SillLinkLine behind` (the mock reports the link behind: the stream's line),
the Mac's sound's `-SillSound on|muted` (the mock Mac sends it, Send Audio on:
Mute off or on; the mock plays nothing) and settings cases
`sound|soundoff|soundnote|nosound` (the Send Audio switch on, off, on with the
Mac's note, or a Mac without sound: the switch off and disabled, "Update
Sill…", no Mute; `default` is Send Audio off with Mute), `-SillSettingsScroll
sound|mute` (the panel at the Send Audio row, or at the Mute row under it), and in
the normal app and under `-SillLive 1` `-SillSoundSink manual|device` (manual
rendering, no output device: the simulator's default in every build; `device`
plays through the Mac's speakers, never in a gate) with `-SillSoundVolume 0`,
`-SillSoundToggle <s>[,<s>…]` (Mute flipped at those seconds),
`-SillSoundSwitchAt <s>` (Mute on, then off a second later) and
`-SillSettingsScript`'s `set sendAudio=1|0` (the device's Send Audio switch); the
console's "audio: …" lines say what happened (the format, the engine and its
latencies, a line a second, each jump with its size and cause, and in manual
rendering where each click of a synthetic host's test tone was heard),
`-SillSettingsScript '<t> set K=V[,K=V] | suggestion | disconnect; …'` (a live
session to a synthetic host on loopback: the panel's controls, the link
callout's button and Disconnect, t seconds after the first window list), `-SillMoveHomeTest to:HOST:PORT|refused|
other:PORT` (with `-SillDialSaved 1`: the saved Mac listed as a network row a
second into the remote session at a door that speaks TLS, so the move home
runs against a synthetic `--remote --pairing` host with SILL_TEST_REMOTE_ORIGIN
and SILL_TEST_REMOTE_DIR, dialed pinned to the saved Mac's key), `-SillDialSaved
remotely` (as Connect Remotely: never moves home),
`-SillConnectCase looking|hint|nearby|methods|denied|update|notice` (the connect screen in a discovery
state; `methods` has a row ending in each word, none, and long names; `update` a
Mac's refusal with "Update Sill in the App Store" when `-SillAppStoreURL
https://apps.apple.com/app/id000000000` gives it an address, `notice` a goodbye
reason the device does not know; the mock never browses) and remote access's `remote|addmac|addcode|addcodeerror|
pairing|remotedial|remotefail|camera|externalpair` (`-SillRemoteFailure
vpnoff|timeout|timeoutip|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|
remoteoff` picks remotefail's words), the settings cases `remote|remoteinternet|
remoteslow|remotepair|remoteoff|noremote`, `-SillSettingsEnd 1` (the panel
scrolled to its end), `-SillSettingsScroll gestures` (the panel scrolled to its
This iPad group; the mock Mac takes gestures in every case but `legacy`; `reverse`
to its Reverse Scrolling switch; `hold` to its Hold to Show Window Controls stepper),
`-Sill.trackpadGestures 0` (the device's Three-Finger Gestures off for one run,
in the normal app too), `-Sill.reverseScroll 1` (its Reverse Scrolling on for one
run, in the normal app too), `-Sill.thumbnailHold 0.3` (the thumbnails' hold at 0.3 s
for one run, in the normal app too; the console's `thumbnails: hold 0.3 s` when a bar
first reads it and at each change), `-Sill.largerPicture 1` (its Larger Picture on for one run,
in effect while a window streams, as the mock does but with `-SillActive desktop|none`;
the console's `larger picture: …` line says what the rule made of it;
`-SillVideoSize WxH` the mock's frame, `-SillLargerPictureToggle <s>[,<s>…]` the
switch at those seconds), `-SillVoiceOver 1` (that group as with VoiceOver on:
its footnote says the rows do the gestures), `-SillScanOverlay 1` (Pair This
iPad…'s overlay; `-SillOverlayLine asking|shown|openonmac|locked|noanswer` the
line its ask's answer sets; under `-SillLive 1` it opens over the live session
and asks), pairing at home's connect cases `homerows|homeasking|homecard|homecode|
homecodeerror|homelocked|homeopenonmac|homerevoked|homecabledone|homeolder|
pairingrequired` and settings cases `paired|pairedoff|openpair`, the connect
case `asleep` (issue #69: a saved Mac's row listed, the reconnect's line after
three dials of it that did not connect), `-SillBrowserFail N` (the normal app
and `-SillLive 1`: each of the first N network browsers is reported failed with
-65569, as iOS reports a suspended app's, half a second after it starts, so it
is made again after 1, 2, 4… s; the console's "browser: …" lines, and the
reconnect's "reconnect: …"), `-SillLayerFail <s>[,<s>…]` (the normal app and
`-SillLive 1`: at each of these seconds after the launch's first picture a frame
that cannot decode goes onto the display layer, so the picture's recovery runs
for real, issue #101; the console's "display: …" and "keyframe: …" lines; against
a host with SILL_TEST_STILL_AFTER the picture comes back only through the ask, and
with SILL_TEST_KEYFRAME_IGNORE=<n> the first n asks go unanswered and are made
again), `-SillKeyframeLost <n>` (with `-SillLayerFail`: the first n keyframes
that end a wait are thrown away by the layer's flush, as though it still read
failed, so the picture counts as back and lost again and the next ask waits a
repeat's 4 s),
`-SillPointer mac@X,Y|device@X,Y|hidden|pencil@X,Y` (the pointer sprite in one
of docs/pointer-visibility-plan.md's states over the mock's frame, which it
draws as a dim rectangle; `-SillPencilPointer 1` is Q2's flip),
`-SillClipboardChip 1` and `-SillClipboardNote sent|long|notsent` (the clipboard's
chip and a Paste's note on the mock's stream, docs/clipboard-plan.md; the mock Mac
shares its clipboard in every settings case but `legacy`; live, `-SillSettingsScript
'<t> paste TEXT'` sends TEXT as the Paste control hands it over, and
`-SillSettingsCloseAt <s>` closes the panel `-SillSettings 1` opened), and in
the normal app and under `-SillLive 1` `-SillPairURL '<sill://pair…>'` (pair
at launch, no confirmation, at the link's own addresses only: a confirmed link
tries the home rows first, which `-SillTapRow` and `-SillHomeLink` below reach),
`-SillPairCode <12 digits> -SillPairAddress host:port`,
`-SillDialSaved 1`, `-SillForgetMacs 1`, `-Sill.savedMacs '<JSON>'` (one run;
`'[]'` empties), `-SillRemoteRoute vpn|internet` (a loopback session counts as
that route), `-SillHelloVersion <v>` (the version the hello gives, against a
host's floor), `-SillScreenFPS 120` (a 120 Hz screen) and `-SillDeviceKeySE 1`
(a Secure Enclave device key, R0-a); for pairing at home (the normal app and
`-SillLive 1`), `-SillServiceType _silltest._tcp` (the browsers look for the
test type, so a test host registered with SILL_TEST_SERVICE_TYPE is a real
row with its TXT record and no real Mac is; only the Debug build's
Info-Debug.plist declares it), `-SillHomeDoor paired|open|plain` (what a
`-SillConnect` address counts as, since an address has no TXT record:
`plain`, the default, dials it plainly as before; `paired` pins the one saved
Mac, else asks; `open` an open door), `-SillCableTest 1` (this device's path
counts as the cable), `-SillForgetHomeTLS 1` (forget which Macs were seen over
TLS, to dial another branch's older Sill.app plainly), `-SillTapRow <name
prefix>` (tap that row once it is listed), `-SillHomeCode <digits>` and
`-SillHomeLink <sill://pair…>` (the home card's code or scan once the Mac
answers `shown`), `-SillOverlayCode <digits>` (Pair This iPad…'s ask, then
that code, on a TLS session at home) and `-SillNoAutoDesktop 1` (the device
never picks the Desktop by itself: a live gate streams nothing); `xcrun
simctl openurl <udid> 'sill://pair…'` shows the link's confirmation after the
system's "Open in Sill?". `-Sill.directWirelessMacs '("Mac mini")'` (seeds the
device's memory of Macs with Direct Wireless on for one run; `'()'` empties it),
`-SillConnect 127.0.0.1:PORT`
(connect by address, also in the normal app: the only way to reach the
off-Bonjour synthetic hosts from the simulator), `-SillMoveTest
1|refused|other:PORT|to:HOST:PORT` (with `-SillConnect`: that session counts as
direct and a second later the same address, or its port 1, or its port PORT, or
HOST:PORT, is listed as the Mac's network row, so the move to the network runs
against a synthetic host; `other:` with a second synthetic host on PORT is
another launch, refused at its first window list and not tried again, and with
`-SillConnect` through a delay proxy to the first host's own PORT the fence
waits out the proxy's round trip; `to:` reads HOST:PORT as `-SillConnect` does,
`[::1]:P` too, and this Mac's `fe80::…%en0` address from `127.0.0.1` shows the
panel's route word change at the hand-over; the console's "discovery: …" and
"session: …" lines, `xcrun simctl launch --console-pty`, say what happened),
`-SillWiredTest HOST:PORT` (a wired dial's fallback under test:
`-SillConnect`'s dial, a network row's and a move's go to HOST:PORT first,
`192.0.2.1:9` giving way after 2.5 s and `127.0.0.1:1` at once), `-SillPathTest
'<spec>'` (with `-SillConnect`: the session's Mac listed as a network row whose
cable and Wi-Fi come and go on cue, so the session follows the best path for
real; the spec is ContentView's contract, the console's "path: …" lines say
what happened), `-SillInputScript '<t> <step>; …'` (with `-SillLive 1`: input
with no finger, t seconds after the session's first window list: `down`, `pad
DX,DY`, `lift` and `click` on the portrait pad, `padscroll DX,DY` two fingers
scrolling it with their coast, `tap X,Y` on the stream at a frame fraction,
`drag DX,DY` a finger dragged over it (a scroll, with its coast), `key USAGE` a
hardware key, `type TEXT` the on-screen keyboard's typing (TEXT handed to the input
view as `insertText`), `row USAGE` a key of the portrait
key row, `gesture NAME[,FINGERS]` a three-finger gesture through
`StreamClient.sendGesture`, `esc [MODS]` Esc through the stream's key command
(only while the input view takes Esc), `scroll DX,DY` a connected trackpad's
two-finger scroll with its coast, `wheel DX,DY` a wheel's plain deltas, `keyboard
attach|detach` a hardware keyboard coming or going, `orient landscape|portrait`
the scene turned (an iPhone's); the console's "input script: …" and "pointer: …" lines say what
happened; it runs only when the session was dialled by `-SillConnect` to a
loopback address, `127.0.0.1:P`, `::1:P` or `localhost:P`, and the host's first
window list has no version: Sill.app's always has, and would post the input to
this Mac, so the console says "input script: refused: …" and nothing is sent;
point it only at `--synthetic` hosts; `[::1]:P` works too: the argument domain
drops a launch argument that starts with `[`, and StreamClient.init registers
`-SillConnect`'s, `-SillWiredTest`'s and `-SillPairAddress`'s from the command
line). The first-run tour, in the mock, under `-SillLive 1` and in
the normal app: `-SillTourState fresh|landscape|done|skipped|saved` turns the
automatic tour on (a Debug build never shows it by itself otherwise; `saved`
reads and writes `Sill.tourSeen` and `Sill.tourSkipped`, the others last one
run), `-SillTour touch|bar|settings|laptop` starts it at that step, and the
stand-ins `-SillTourPress next@S|skip@S`, `-SillTourActivityAt S` (the app
run's first session only), `-SillTakeTourAt S` (Settings, then its Take the
Tour) and
`-SillTourVoiceOver 1`; `-SillOrientation landscape|portrait` asks the normal
app's scene for that orientation (a phone simulator sideways with its real
safe areas); the console's "tour: …" lines say what happened, and a card's
line gives its frame and tail. `xcrun simctl launch --console-pty` streams the
console; `--stdout=PATH` writes inside the simulated device's own file system.
A fake screen wider than the
simulator but fitting on its side (1133x744 on an upright iPad Pro 13") is
drawn a quarter turn clockwise; `sips -r 270` the screenshot. One that fits
neither way (the Duo's or an iPad's size on an iPhone simulator) is drawn
scaled down and laid out at its own size ("harness: 710x1000 drawn at 0.62");
a phone's whole stream screen on that phone (440x894 on an 18 Pro Max, 402x812
on an 18 Pro) reaches into the simulator's safe area and runs its trackpad past
its bottom edge: photograph it on a larger simulator, or in the normal app.
`-SillKeyboard 1` raises the software keyboard for real in a live session (the
mock only lights the button), `-SillKeyboardToggle <s>[,<s>…]` toggles it at
those seconds as the Keyboard button does, and in a live session (the normal
app with `-SillConnect`, or `-SillLive 1`) `-SillDrawer 1`, `-SillSettings 1`
and `-SillScaleOpen 1` open theirs 1.5 s after the stream starts
(`-SillDrawerSearch <text>`: the open drawer searches with its field's keyboard
up; the Aa ruler only while a window streams: over a synthetic host's Desktop
Aa is dimmed and the console says the ruler stays closed;
`-SillScaleScript '<s> <scale|off>[; …]'` sets Aa's value at those seconds as
the ruler's release does, whatever streams, so a synthetic host's `[1s]` lines
show `win.fitOff` for a scale then Off). The console
prints `viewport: 386×241 pt, scale off, 60 fps` for each viewport sent, and on
a phone upright `trackpad: …, vertical span …` and, once the keyboard has moved,
`keyboard: up, 301 pt tall, its top at …; the key row ends 10 pt above it`.
`-SillAXDump <s>` lists the stream screen's accessibility elements in the
tree's order (VoiceOver's), on a private simulator once `xcrun simctl spawn
UDID defaults write com.apple.Accessibility ApplicationAccessibilityEnabled
-bool true`.
A hardware keyboard (docs/hardware-keyboard-plan.md): a simulator's GameController
always counts the simulator's own keyboard, so the stream's input view takes the
keyboard by itself there (an empty input view: nothing drawn); `-SillHardwareKeyboard
1|0` says a keyboard is attached or not for the run instead. The console prints
`keyboard: …` for what HardwareKeyboardPolicy does and `hwkey: usage 41 down via
pressesBegan (none): to the Mac` (or `keyCommand`) for every hardware key the input
view sees; `-SillKeyProbe 1` adds GameController's own view of each key,
`-SillEscViaCommand 1` hands Esc on from pressesBegan so its key commands take it,
and `-SillTurnAt <s>[,<s>…]` turns an iPhone's scene mid-session (iPadOS's windowing
refuses). `Tests/keyrig` presses real keys (and holds them, `wait:S`) and turns a
wheel inside the simulator; after its keys UIKit there counts a hardware keyboard,
so a fresh simulator is the one that shows the software keyboard. Each hardware
key's down line ends in who types its characters (`; the Mac types: en-US`, `;
iPadOS types: zh-Hant`: KeyTyping), and the simulator takes another language's
keyboards from `-AppleLanguages '(zh-Hant-TW, en-US)' -AppleLocale zh_TW` (or
ja-JP, ru-RU…), not from its `AppleKeyboards` preference. A test host's Desktop takes input only with
`SILL_TEST_POINTER_PATH` (else it has nowhere to land).
`-SillIdiom pad` draws a screen taller than wide and narrower than 600 pt as
an iPad does (the compact halves) rather than as a phone, so an iPhone
simulator photographs it (`phone` the other way round; the normal app too).
`-SillInputTest 1`, with `-SillConnect` on this Mac's loopback: once, the
portrait key row taps cmd, esc, shift and ctrl through its caps' action, then
the trackpad checks that a touch at its centre lands on it, strokes, taps with
the latched keys held and scrolls, through its own code, and in every layout
the stream's input view sends Esc and ⇧Esc through its key command, a
trackpad's scroll with its coast and a wheel's ("input test: …"); a
synthetic host counts what it gets as `in.dry` and posts nothing, but a real
host (Sill.app, SillHost without `--synthetic`) posts it on this Mac and the
test does not look at which host it reached, so point it only at a synthetic
host, or put a relay in front that reads the device's frames (the 14-byte
header: kind, then the payload's length at bytes 10–13) and drops kind 8
(`sillrelay.py` passes everything).

## Compatibility floor

The first public builds (Sill for iPhone and iPad from the App Store, Sill.app from GitHub) set it
for good. Sill.app changes only when its user downloads a new version (its update check only points
at one), and a device can stay on an old version (automatic updates off, an iOS the next version
dropped). So every later host keeps serving devices from the first public build on, and every later
device keeps working with Macs from the first public build on, or each says why
(docs/update-notice-plan.md):
- Kept as they are: the home door as Sill.app 1.0 ships it, TLS with pairing at home
  (docs/home-pairing-plan.md, branch `home-pairing`; it ships before 1.0, Noah 2026-09-25), not
  the plain-TCP `_sill._tcp` door, which only development builds and the CLI without `--pairing`
  keep; the ALPNs `sill/1` and `sill-pair/1`, which every host offers for good at both doors
  (`RemoteTLS.serverALPNs`: a later generation's `sill/2` only ever goes beside them); the 14-byte
  header; kinds 0–28, 32 and 44 and their payloads (HEVC with ParameterSets; the JSON of Switcher,
  Input, Viewport, HostSettings, Remote, Compatibility, Pointer, MacMenu, Gesture and Clipboard;
  44, a device's keyframe request after its picture was interrupted, empty, which a host from
  before skips; 29 to 31 and 33 to 42 stay free, pull request #66's, and 43 is the Mac's sound's,
  below), inside `sill/1` at both doors (19 and 20 on their own `sill-pair/1` connection, the
  next bullet); the ping echo; a viewport (kind 9) within `ViewportBounds`, each side 1 to
  16384 points and a text scale 0.25 to 4 or none: every device build's is, a host from
  2026-10-29 on refuses any other whole (security scan, finding 4), so a later device keeps
  within them; a
  kind 16 within 2 s of the first window list, one per connection since Sill for Mac 0.5.1 (away
  from home, docs/remote-bundle-plan.md §4): its `settings` the pair that connection's controls
  set (the away quality for a device away), and its optional `away` (AwayQuality, from a host with
  an identity: Sill.app, SillHost --remote or --pairing) and `link` (LinkReport, only while a link
  does not keep up; its `state` a string,
  which a device reads as keeping up when it does not know it); kind 22's `reason`, `message` and
  `reconnect`; the
  Mac's menus as MacMenu.swift has them (docs/menu-bar-plan.md §3):
  a kind 27 without an id is the device's subscription, and only a subscriber is served (another
  connection's fetches and choices are answered "The menus changed…", nothing read or pressed); an
  id is a path of child indexes that names one item for every device within one version, and a
  request of another version is answered with that note and never acted on; a fetch and a choice
  carry the title the device showed, and the host reads or presses only while the item there still
  has it; a device's tokens come back in `answering`; the fields as they are (MacMenu's `version`,
  `app`, `bundleID`, `menus`, `answering`, `menu`, `items`, `more`, `pressed`, `stale`, `note`;
  MacMenuItem's `id`, `title`, `separator`, `enabled`, `mark`, `key`, `submenu`; FetchMenu's and
  PressMenuItem's `version`, `id`, `title`, `token`); a trackpad gesture (kind 28, Gesture.swift)
  goes only to a host whose window list says `gestures` 1 or more, as one of its six names with
  `fingers`, and a later generation of gestures says 2 and goes only to a host that says so; the
  clipboard (kind 32, Clipboard.swift, docs/clipboard-plan.md) goes from a device only to a host
  whose window list says `clipboard` 1 or more (an Int: 1 is text, a later generation with images
  says 2), and from a host only to a connection that sent a kind 32 and no `stop` since: any kind
  32 subscribes, `{"stop":true}` ends it, `text` (at most 256 KB, the JSON at most 1 MiB) becomes
  the receiver's clipboard, `image` is reserved for that later generation; a subscription says what
  the device takes, `{}` being text alone, so a host sends `image` only to a connection whose
  subscription carries a later field saying it takes images (`"accepts":2`, say), never to one that
  sent `{}`; a hardware keyboard's characters (letters, digits, Space, Delete…) go to a host as keys
  only when its window list says `keyRepeat` 1 or more (it repeats a key held between its down and its
  up, #162), to any other through iPadOS's text system as they always did; the Mac's sound (kind 43, Audio.swift), once a public build ships it, a beta or not:
  its two types (a JSON AudioFormat, then packets whose layout never changes: a new layout is a new
  type), AudioFormat's fields, the hello's `audio`, `sendAudio` and `audioNote`, kind 43 only to a
  device whose hello lists a codec the host makes, and the reader's caps, which a later host keeps
  within (a device drops a message past them whole): a format at most 4 KB, a packets message at
  most 16 KB (`AudioMessage.parse`), so a host that batches packets never puts more than 16 KB in
  one message.
- Pairing as 1.0 does it (docs/home-pairing-plan.md §3): the Bonjour TXT keys `r` (the recognition
  tag) and `p` ("1" pairing required, "0" open, no `p` a plain door, any other value read as "1");
  a `sill-pair/1` connection is exactly one kind 19, with no hello (the device gate judges sessions
  only), and one kind 20, then the Mac closes it; kind 19's methods `qr`, `code` and, at the home
  door, `ask` and `cancel` (the remote door answers both `closed`), at `v` 1: a host answers any other `v`
  `closed` without counting a try, so a later method or proof format comes with a later `v`, never
  as a new method at 1, which a 1.0 host counts as a wrong code; kind 20's reasons `code`,
  `closed`, `expired`, `stopped`, `busy` and, after an ask, `shown`, `openOnMac` and `locked`, with
  their meanings (`PairResult.knownReasons`: a later reason comes with its `message`, which 1.0
  devices show as it is); an ok without a proof only as `method` "cable", to an ask that claimed
  the cable; and pairing is never refused for the device's age.
- Additive only (HostSettings.swift's rules): new fields optional, never renamed or retyped; kind
  numbers never reused; no new case in an enum an older peer decodes. `StreamSource` keeps its
  three cases (a new source goes in an optional field, with `active` still one of the three). A new
  `InputEvent` case, scroll phase or window command goes only to a host that said it takes it (a
  kind or a field only newer hosts send), and a gesture ends with a scroll phase the first build
  knows.
- A device is refused, never served wrong. A host that can no longer serve older devices raises
  `DeviceGate.minimumDeviceVersion` ("0" today) by the plan's §4.6, and they get kind 22 "update"
  before anything else. A device from 2026-09-25 on that receives it shows the host's message word
  for word, with its App Store link, and does not reconnect; older development builds cannot. At
  the TLS home door only devices from home pairing on receive it (Decided, below). Kind 22 reaches
  a 1.0 device only inside a `sill/1` session, so such a host still completes that device's
  `sill/1` handshake and reads its hello through the gate before refusing it: a host that stopped
  offering `sill/1` would leave it a failed handshake (-9838), "disconnected" and a redial every
  few seconds, for ever.
- Every device says hello first (kind 23: its version, build, protocol and name), and every host's
  window list gives its version and protocol (`hostVersion`, nil from SillHost and from Macs
  before 2026-09-25). A later device facing an older Mac tells what it lacks from these and from
  which kinds and fields arrive, and says "Update Sill on ‹Mac›", as the Settings panel already
  does for a Mac without kind 16.
- `SillProtocol.current` (1) rises only with a change an older peer cannot skip, and the floor
  rises with it.
- Decided (Noah, 2026-09-25; the plan's open question 14): home pairing ships before 1.0, so the
  floor is the TLS home door with pairing, and no 1.0 device speaks plain TCP to Sill.app.
  Settled at the merge of main into `home-pairing` (2026-09-27, d11aa60; home pairing landed
  second): the hello goes first inside TLS at both doors, and the device gate runs in `Door`, once
  the key is admitted, one place for both TLS doors (`StreamServer.gate`; the CLI's plain door
  without `--pairing` runs it at `.ready`); what changed while it held a session (the key removed,
  Require pairing on, Remote Access or internet access off, the session limit, Direct Wireless
  off) is judged again by `DoorPolicy.afterGate`, with the goodbye and the line that change's own
  close gives. 1.0's TLS home door is `SillProtocol` 1 with ALPN `sill/1`, as the remote door is:
  pairing on the home door is part of protocol 1, no longer an example of what raises it
  (Compatibility.swift, docs/update-notice-plan.md §3.2 and §4.6), and a later generation raises
  both: `sill/2` is offered beside `sill/1` and `sill-pair/1`, never instead of them (the first
  bullet). Builds from before home
  pairing dial plain TCP and say hello in plaintext: at the TLS door they get a failed handshake
  and EOF, never kind 22 "update", and redial. Only development and TestFlight builds are that
  old, so no plaintext path or sniffer answers them.

## Conventions

- Swift, Apple frameworks only. No third-party dependencies unless a decision
  in `docs/BRIEF.md` says so. Zero operating costs is a hard rule.
- Threading in the spike is by hand: capture queue → VT callback thread →
  network queue. Keep it explicit and commented rather than reaching for actors
  until the design settles.
- HEVC, no B-frames, real-time mode. AV1 is out (no hardware encode on Apple
  silicon as far as we know).
- Latency beats quality. Drop frames before queuing them.
- Don't add features the current milestone doesn't need.

## Decisions already made (don't relitigate without asking Noah)

- Free app, tip jar, open source. Not paid, not subscription.
- iCloud auto-pairing (same Apple Account, Mac just appears) for milestone 5.
  Bonjour only for the spike.
- Native feel is the bar: Flighty-level polish, iOS conventions, Duo layouts.
- License: Apache-2.0, LICENSE since PR #15, kept when the repository went
  public on 2026-09-26 (paid plan is gone, so no GPL/CLA needed).
- v1 out of scope: hole punching, multi-window, layout customization. Audio is in scope since
  2026-09-27 (Noah: "Audio: the plan is done and parked as a v2 feature by your earlier decision",
  first in what he wanted worked on; docs/audio-plan.md, docs/BRIEF.md), and in, as a beta, since
  2026-10-20 (Noah, about PR #94: "merge as beta support"): Send Audio, off by default. Since
  2026-10-27 (Noah: "Sound should be a toggle in the settings menu") the Mac's menu and Settings and
  a device's Settings panel set it for every device, and each device's Mute is its own; no Sound
  button in the bar.
