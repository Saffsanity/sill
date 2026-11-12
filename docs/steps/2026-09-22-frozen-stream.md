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
