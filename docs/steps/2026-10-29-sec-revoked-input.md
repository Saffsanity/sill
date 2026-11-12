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
