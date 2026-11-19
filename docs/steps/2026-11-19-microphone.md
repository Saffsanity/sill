**The microphone, first part: an iPhone's or iPad's microphone as an input on the Mac, the wire, both ends' rules, the Mac's receiving side up to Sill Microphone, and the device's capture and switch (2026-11-19, branch `microphone` from `sill-audio` at 98f234d5, which is main at eb48ac9 with #394; pull request #415).**
Noah, 2026-11-18: "Work on … microphone passthrough to Mac with toggle", and "Any tasks that were opened by me
that are mentioned above should have an agent assigned and wip". The plan is docs/microphone-plan.md (its §0 says
what the night's overview settled over it); this is its first part: everything that needs nothing installed on a
Mac. Pull request #191 (addhumal), which played the device's microphone through the Mac's speakers, is redone (the
assessment's verdict): it gave this work kind 43's two types the other way and the name Share Microphone.

- **The wire (kind 48, Microphone.swift).** Type 1 `MicrophoneFormat`: kind 43's AudioFormat keys with `claim` and
  `pause` beside them in one JSON object (the offer; with a codec, an epoch's format too); type 2 kind 43's
  AudioPackets byte for byte, the header's stamp the capture time on the device's wall clock; type 3 the end. The
  window list's `microphone` (1, or 0: the switch off or Sill Microphone not set up) and kind 16's per-connection
  `MicrophoneState` (`off`, `notReady`, `unpaired`, `refused`, `idle`, `another`, `inUse`; `codecs`, `device`).
- **The rules (MicrophonePolicy, both ends, pure).** The device offers while its switch is on with the permission
  given, the Mac's list says 1, it is unlocked, and this window is the one used last; it records only while kind
  16 says `inUse`, in front and with no call; its first offer after the switch comes on claims; it ends when the
  switch goes off, and once when the Mac says `inUse` to a connection that does not offer. The Mac holds one device
  by its paired key: a claim takes it, an offer alone only while nobody holds it, a move or a reconnect within 10 s
  keeps it, the holder's end, removal or grace hands it to the most recent standing offer. Refused: unpaired
  devices, the switch off, Sill Microphone missing, a locked Mac (LockPolicy's new request, at its arrival and
  now); limits of 10 offers a second, 6 recordings a minute and 1.5 s of sound a second (over 2 s), each a minute's
  refusal with one line. Every word of both ends is in `MicrophonePolicy.Copy`.
- **SillAudio.** The encoder and decoder take a channel count (the device's microphone is mono at 64 kbps).
  AudioPlayout gains `Mode.microphone`: no picture's guard, a 110 ms first cover at home, and `message()`, which
  counts a message's ten packets for the floor and the cover before its first is placed. Without it a session's
  first message lost about 50 ms to a jump, since its last packet lowers the floor by 90 ms.
- **The Mac (MicrophoneReceiver, its queue `sill.mic`).** Kind 48 from the network queue straight there (after the
  revoked check, never `onMessage` or the main actor); the policy; the holder's packets through the mono decoder and
  the playout to MicrophoneOutput, the seam where Sill Microphone (the next part, an Audio Server Plug-in) takes
  the sound. In this part only a test host makes a receiver, with the TEST ONLY MicrophoneTestOutput
  (`SILL_TEST_MIC_SINK=dry|file:PATH`, `_APP`, `_SETUP`, `_LOG`): a stand-in timeline and a WAV of exactly what Sill
  Microphone would hear. No audio device is opened anywhere. The CLI never says `microphone`; Sill.app gets its
  receiver with Sill Microphone. `HostConfig.deviceMicrophone` ("Use iPhone and iPad microphones"), off in both.
- **The device.** Share Microphone (MicrophoneSwitch: off at every launch, never stored, the permission asked only
  as it is turned on) in the Settings panel after the clipboard's rows, with a Beta tag; it moves into #393's
  whole-screen pane's device part. MicrophoneCapture records through a tap on the window's sound engine in its voice
  mode (voice processing cancels what the device plays, the Mac's sound included), converts to 48 kHz when the
  route gives another rate, and MicrophoneSender makes the messages. SharedSession has two needs, playing and
  recording (`.playAndRecord`, `.voiceChat`, mixing with other audio, to the speaker, Bluetooth in call quality).
  SessionLink never queues the microphone's packets behind a fence or a hold, and keeps at most two unsent. The
  simulator records the test tone and never opens the Mac's microphone.
- **Decisions taken (each in the pull request's "Defaults taken for Noah to confirm").** The camera's state names
  for the microphone (one rule and one UI for both sensors); `claim` and `pause` in type 1 beside kind 43's keys;
  type 3 for the end; the most packets a message 40; the 110 ms first cover at home and `message()`; A192 for the
  third iOS file; the auto-lock hold left to the next part; Share Microphone's place in the current panel.
- **Seen while building, for the sound's code.** AudioPlayout: an IO buffer that grows by more than the 2 ms margin
  without a reset can hand a held tail out later than IO + 2 ms before its render (one of the first random runs of
  the microphone's mode, with such a change). AudioOutput always resets on an IO change (its route handler), so the
  device never meets it; the microphone's random runs leave that change out.

**Verified (run 1).** Outside the heavy lock, each changed check through its own run.sh: `microphone` (1,287,372
checks: 13,824 combinations of the device's inputs, the Mac's reducer at each edge, 3,000 random sessions of up to
three devices and a Mac), `mic-host` (26), `mic-send` (50: the sender and the capture on the Mac with no audio
device, taps at 16, 24 and 48 kHz, every click of the tone at its second ±2 frames), `audio-codec` (32, mono at
64 kbps), `audio-playout` (254, 5,000 sound runs unchanged and 1,000 of the microphone's), `fence` (the microphone
mode), `lock-policy` (1,465), `away-quality`, `compatibility` (169), `pointer-control` (161), `display-wake` (275),
`repo-rules` (11 of 11). The host and Sill.app's sources type-check against freshly emitted modules; the iOS app
type-checks for the simulator, Debug and Release, with only main's own weak-capture warning. The heavy hold's
results (the release build, the live gates, the mutants) are below.

**Proposed words for the release that ships it** (not published; for Noah):
- What's New (iPhone and iPad): "Share Microphone (beta): your iPhone or iPad can be a microphone for your Mac.
  Turn it on in Sill's settings, and choose Sill Microphone in a call, a recording or dictation on the Mac. It needs
  Sill for Mac with Sill Microphone set up."
- The site's privacy page, "From your iPhone or iPad to your Mac": "While Share Microphone is on in Sill's
  settings and an app on your Mac uses Sill Microphone, what the microphone hears, which your Mac plays into Sill
  Microphone and never records or saves." The device's permissions: Microphone.
- The review notes (at most 300 bytes): "Share Microphone (beta) sends the microphone to the person's own Mac only
  while an app there uses Sill Microphone and Sill is in front; it never records in the background. The demo video
  shows it, since Sill Microphone needs an administrator's install on the Mac."

**Untested, for Noah** (the pull request's numbered steps): everything on a device and on a Mac with Sill
Microphone, which this part does not install.
