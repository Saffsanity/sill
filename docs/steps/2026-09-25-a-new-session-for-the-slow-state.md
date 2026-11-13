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
