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
