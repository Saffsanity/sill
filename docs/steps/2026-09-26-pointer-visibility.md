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
