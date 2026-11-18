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
