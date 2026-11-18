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
