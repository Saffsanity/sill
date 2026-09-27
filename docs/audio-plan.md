# The Mac's sound on the device — the plan

2026-09-26. It stands alone: the implementer needs no other design document. Written from a
read-only survey of origin/main at 8b0d418 ("Merge pull request #18", update-notice), of the
`remote-pacing` branch at 3126821 ("remote pacing counts bytes") and of the plans that hold message
kinds (menu-bar-plan.md holds 24, 25 and 27; pointer-visibility-plan.md 26;
trackpad-gestures-plan.md 28). Line numbers were 8b0d418's; since the refresh below they are
643af6b's. Nothing was started: no host, no app, no ScreenCaptureKit call, no sound captured, and
never the Mac's video encoder. Two read-only probes
ran, both in memory on a synthetic signal: AudioToolbox's encoders and decoders on this Mac (macOS
27.0 26A428, Xcode 27.0), and the same program inside the iOS 27.0 simulator runtime (`simctl spawn`
of a command-line binary; nothing installed). They and their output are in the session's scratch
folder `…/scratchpad/audio-plan/probe/` (`formats.swift`, `realtime.swift`, `run-realtime.txt`,
`run-realtime-sim.txt`). Apple's own account of ScreenCaptureKit's audio is WWDC22 session 10155,
"Take ScreenCaptureKit to the next level"; availability comes from the SDK headers (SCStream.h,
CATapDescription.h, AudioHardwareTapping.h, AVAudioSourceNode.h).

**Critiqued the same day** against Apple's documentation (SCStreamConfiguration's audio properties,
SCContentFilter, WWDC22 sessions 10155 and 10156, AVAudioSession, AVAudioPlayerNode and AVAudioNode,
the engine's configuration-change notification, kAudioFormatOpus), against main at 150f781 (PRs #20
and #21 since 8b0d418) and every other branch and worktree, and with a third in-memory probe of the
same kind: AAC-ELD across an `AudioConverterReset`, and a decoder that joins mid-stream
(`…/scratchpad/audio-plan/critique/`, `reset.swift`, `reset2.swift`, `join.swift`). The plan below is
written as fixed; the section "Critique" says what changed and why. Scratch folders do not
survive a restart: each probe is one AudioToolbox file, and H0 rebuilds them from their descriptions.

**Refreshed 2026-09-27** against main at 643af6b ("Merge pull request #34", remote pacing), which
since 8b0d418 has gained the Mac's pointer (#31, kind 26), the Mac's menus (#36, kinds 24, 25 and
27), remote pacing (#34), the iPhone's portrait layout (#30) and the first-run tour (#35), and
against the three open pull requests that touch the same code: #37 (pairing at home: TLS at the
home door, one `Door` behind both listeners), #38 (three-finger gestures, kind 28) and #39 (away from
home: kind 16's `away` and `link`, the move home). Every branch and worktree was read again for
message kinds and project-file IDs. Nothing was built or run. Noah moved the sound into scope the
same day (Q13). The plan below is written as refreshed; the last section, "Refresh (2026-09-27)",
says what changed and why.

**Noah's request (2026-09-25, as relayed to this session):** "Another idea for the future is to
have Sill send audio back with the video." On 2026-09-26 he put it on the list to work on. On
2026-09-27, first in the list of what he wants worked on now: "Audio: the plan is done and parked as
a v2 feature by your earlier decision."

**Reading of it.**
- **What the device hears.** The sound of what streams: the picked window's app, or every app for
  the Desktop. Not a microphone, and not the device's own sounds.
- **In step with the picture.** The sound is never noticeably ahead of the picture, and trails it
  by as little as the sound's own path allows.
- **At no cost to the picture.** No frame waits for sound, nothing restarts for it, no new
  permission, and the CLI prints nothing new unless asked.
- **Now, not after v1.** BRIEF.md keeps audio out of v1 ("Out: … audio"), and this plan was written
  for after it. Noah's word on 2026-09-27 brings it forward (Q13): it is built now, and step 8
  records the decision in BRIEF.md and CLAUDE.md. Send Audio stays off by default (Q1), so a
  release that carries it changes nothing for anyone who leaves it off.

---

## Decision

### What the sound is of

| Source | What the device hears | The audio stream's filter |
|---|---|---|
| A window (regular mode) | Every sound of that window's app: all its windows and tabs | `SCContentFilter(display: main, including: [app], exceptingWindows: [])` |
| A window on the virtual display | The same | The same (sound does not depend on the display) |
| The Desktop | Every app's sound but Sill's: the whole Mac | `SCContentFilter(display: main, excludingApplications: [Sill], exceptingWindows: [])`, as the Desktop's picture (StreamCoordinator.swift:1065-1074; the CLI, with no Sill app to leave out, excludes nothing) |
| The test pattern (`--synthetic`) | A test tone | none: `SyntheticAudio` (§4.2) |

- **Sound is per app, always.** In WWDC22 session 10155 Apple says ScreenCaptureKit filters audio
  only at the application level: a single-window filter captures all of the owning app's sound,
  including windows that are not in the video, and excluding one window's sound means excluding
  its whole app. So there is no "just this window" sound. It also means window capture does carry
  sound: `SCContentFilter(desktopIndependentWindow:)`, today's window filter
  (StreamCoordinator.swift:1035), would bring the app's. The plan takes the sound from a stream of
  its own anyway (next point), so nothing depends on either reading. WWDC22 session 10156 says the
  same ("audio capture can only be filtered at an application level"); neither session nor the
  documentation says whether a display filter hears an app none of whose windows is on that
  display (the virtual display, a minimized app, a second display). P5 checks; if it does not, the
  app's sound stream takes `SCContentFilter(desktopIndependentWindow:)` of the streamed window
  instead (all of the app's sound, per 10155) and starts again when that window closes or another
  window of the app is picked.
- **A stream of its own.** The sound comes from a second, audio-only SCStream, not from
  `capturesAudio` on the picture's stream:

| | Sound on the picture's stream | **An audio-only stream (chosen)** | Core Audio process tap |
|---|---|---|---|
| A resize, rotation, Aa step, rate or quality change, the encoder fallback | The sound stops and starts with every restart | Untouched: the app is the same | Untouched |
| Another window of the same app | The sound restarts | Untouched | Untouched |
| Send Audio on or off | A restart of the picture (a running SCStream is never reconfigured) | The sound's stream starts or stops; the picture never notices | The same |
| A failure of the sound | Can end the picture's stream | Ends only the sound | Ends only the sound |
| Extra cost | none | One more SCStream, whose 2×2, 1 fps picture is thrown away | An aggregate device and an IOProc |
| Permission | Screen Recording (Sill has it) | Screen Recording (Sill has it) | A second one, "System Audio Recording Only" (`NSAudioCaptureUsageDescription`), and macOS 14.2 (`AudioHardwareCreateProcessTap`, AudioHardwareTapping.h) |
| Can keep the Mac quiet while the device plays | No | No | Yes (`CATapMutedWhenTapped`, CATapDescription.h) |

  Rotation and Aa are everyday gestures, and music under a window that restarts must not drop
  out. The tap's one gift, a quiet Mac, costs a new permission: later (§14).
- **Sill's own sound never goes out.** `excludesCurrentProcessAudio = true` on the audio stream
  (Sill plays none today; a future alert would otherwise loop back), and the Desktop's filter
  excludes Sill's app as the picture's does.
- **The format.** `sampleRate = 48_000` and `channelCount = 2`, ScreenCaptureKit's defaults, set
  explicitly (it takes only 8, 16, 24 and 48 kHz and 1 or 2 channels; anything else silently
  becomes 48 kHz stereo: SCStreamConfiguration's documentation). Each buffer is a `CMSampleBuffer`
  wrapping an audio buffer list in that format (SCStream.h); Apple's sample code reads it as the
  standard format, 32-bit float with a buffer per channel. The host reads each buffer's
  `AudioStreamBasicDescription` and never assumes its sample format or layout. That format, how
  many frames a buffer holds and how long after its time stamp it arrives are not documented: the
  first buffer's log line says all three (§4.10), and P2 records them.
- **What ScreenCaptureKit does not hear.** Sound played by system daemons rather than by an app,
  such as a FaceTime or phone call relayed from an iPhone (third-party reports), and possibly the
  system's alert sounds. Apps that play through helper processes are attributed to their app in
  Apple's own demo (Safari, whose media plays in a WebKit process); P4 checks the rest.

### Which codec: measured

The probe fed 6 s of a busy signal (noise at −24 dBFS under three tones, 48 kHz stereo float)
through each AudioToolbox encoder in capture-sized chunks, decoded every packet as soon as it
existed, and found a 4 ms burst in the output. "End to end" runs from the burst entering the
encoder to leaving the decoder, with the smallest constant playout offset that never runs dry. It
counts the chunk's own length (the encoder gets whole chunks: ELD 512 with 1024-frame chunks is
1024 + 256 frames, 26.7 ms), packetizing, the codec's own delay and the chunks' misalignment; no
network, no buffer.

| AudioToolbox codec | Frames a packet | Codec delay (priming) | End to end, 480-frame chunks (10 ms) | End to end, 1024-frame chunks (21.3 ms) | kbps at a 128k target | at 96k | Encode / decode CPU, of one core |
|---|---|---|---|---|---|---|---|
| AAC-LC `aac ` | 1024 (21.3 ms) | 2112 | 74.7 ms | 65.3 ms | 130.4 | 100.7 | 0.49 % / 0.05 % |
| AAC-LD `aacl` | 512 (10.7 ms) | 512 | 30.7 ms | 32.0 ms | 129.3 | – | 0.52 % / 0.06 % |
| **AAC-ELD `aace`, 480** | 480 (10.0 ms) | 240 | **15.0 ms** | 35.7 ms | 129.3 | 97.2 | 0.52 % / 0.07 % |
| **AAC-ELD `aace`, 512** | 512 (10.7 ms) | 256 | 25.3 ms | **26.7 ms** | 131.1 | – | 0.51 % / 0.07 % |
| Opus `opus`, 5 ms | 240 | 312 | 16.5 ms | 32.5 ms | 131.0 | – | 0.98 % / 0.39 % |
| Opus, 10 ms | 480 | 312 | 16.5 ms | 37.2 ms | 121.6 | 91.2 | 0.95 % / 0.32 % |
| Opus, 20 ms | 960 | 312 | 26.5 ms | 46.5 ms | 97.9 | 69.9 | 1.00 % / 0.32 % |

- **Silence costs little:** AAC-ELD about 5 bytes a packet (3.9 kbps), Opus 4 (3.2 kbps).
- **Defaults, when the packet size is not asked for:** AAC-LC 1024, LD 512, ELD 512, Opus 120
  (2.5 ms). Rate control: the AAC family "long-term average", Opus "variable".
- **The iOS side.** The iOS 27.0 simulator runtime has the same encoders and decoders (`aace`,
  `aacl` and `opus` among them) and gave the same packets, delays, latencies and bitrates.
- **CPU.** Upper bounds on an M-series core: the probe copies Swift arrays around every call.
- **Not checked here:** Opus on macOS 14 or iOS 17, Sill's floors; this Mac has no such runtime.
  `kAudioFormatOpus` is documented from macOS 10.13 and iOS 11, but that is the constant, not an
  encoder at 10 ms that follows a bitrate: Apple's own forum example of AVAudioConverter encoding
  Opus (an Apple engineer, developer forums thread 763362) uses 960-frame (20 ms) packets.
  `kAudioFormatMPEG4AAC_ELD` is documented from macOS 10.7 and iOS 4, and AirPlay screen mirroring
  carries its sound as AAC-ELD (the unofficial AirPlay specification; the open receivers RPiPlay
  and WinAirPlay decode it as such).
- **Across a reset, and joining late** (the critique's probe). After `AudioConverterReset` the
  encoder starts again with the same priming (240 frames for ELD 480, 256 for 512), and a reset
  decoder, or a fresh one, finds each burst at its input frame + P again; what the encoder still
  held (at most F − 1 + P frames) is dropped. A decoder that starts in the middle of a stream gives
  noise for its first packet (−5 to −6 dB against the signal), −41 to −43 dB for the second, −64 dB
  for the third and the exact signal from the fourth (ELD's filterbank overlaps four frames).

**Chosen: AAC-ELD at 128 kbps, 48 kHz stereo,** 480 frames a packet (10 ms), or 512 when the Mac's
capture buffers come in multiples of 512 frames. The packet that divides the capture chunk evenly
is 9–10 ms faster end to end (the two bold cells); the host decides from the first buffer (§4.3)
and says which in the format message.
- **Why ELD, not Opus:** the same latency, about half the encode CPU and a fifth of the decode,
  certain on both floors, and Apple's own choice for the same job. Opus stays one field away
  (`codec`, §3.2; Q2).
- **Why not AAC-LC:** its 65–75 ms alone is more than the picture's whole path.

### Where the time goes

At home, the iPad on Wi-Fi, its own speaker, a 60 Hz panel. Each row counts once: the codec's
measured "end to end" already holds the capture buffer's length, and the need (§7.2, rule 2) holds
the device's own delays.

| Stage | Picture | Sound |
|---|---|---|
| Capture and encode | ≤ 1 refresh (≤ 16.7 ms), then a few ms of hardware HEVC | 15.0 ms (480-frame buffers, ELD 480) or 26.7 ms (1024-frame buffers, ELD 512): the buffer and the codec, measured; plus the buffer's delivery after its last frame, not documented (P2; 0–10 ms assumed) |
| The link | frame age 8–10 ms (measured 2026-09-22, from the stamp at encode-out) | the same connection: 2–5 ms at the floor |
| The worst of the link | none: a frame is shown when it arrives, late or not | the jitter cover, 20–80 ms: the 4 s safety keyframe (1–2 MB) goes out ahead of the next packets, 30–80 ms at 200–400 Mbps and more on slower Wi-Fi (this project measured 50–100 ms frame-age spikes from it, with AWDL on) |
| On the device | decoded and shown in 1–2 refreshes (17–33 ms) | one packet held (10.0–10.7 ms), the IO buffer (5.3 ms), the speaker's output latency (5–15 ms), 2 ms of margin; decode under 0.1 ms |
| **In all** | **40–60 ms** (estimated) | **60–155 ms** (estimated: 15–27 + 0–10 + 2–5 + 20–80 + 10–11 + 5 + 5–15 + 2) |

- **So the sound trails,** by 20–115 ms at home, typically about 50 ms (3 frames at 60 fps): its own
  path is the longer, and the guard (§7.2, rule 4) keeps it at least a frame behind the picture's
  arrival. That is under the ~125 ms at which late sound is noticed (ITU-R BT.1359: detectable at
  45 ms early or 125 ms late; acceptable to 90 ms early and 185 ms late). Early sound: "What the
  guard cannot see", below.
- **"1–2 frames behind" is the rule, not the measure.** When the sound is ready in time, the device
  plays it one frame of the stream's rate after the picture. It rarely is: the 4 s safety keyframe
  (HEVCEncoder.swift:168, `fps * 4`) puts 1–2 MB in front of the next
  packets every 4 s, and a buffer that does not cover it clicks every 4 s. A glitch is worse than
  30 ms.
- **Bluetooth and AirPlay.** AirPods add 150–250 ms, which AVAudioSession's `outputLatency` reports;
  the need takes it (rule 2), so the sound trails by that much more, 170–360 ms, past BT.1359's
  185 ms for the slower ones. On AirPlay, Apple's `outputLatency` documentation warns of 2 s. The
  picture is not delayed to match: latency beats quality (Q7).

### How the device keeps time

- **One clock: the host's wall clock.** Every audio packet's header carries the host wall-clock
  time (seconds since 1970) at which its first decoded sample played on the Mac. That is the clock
  the video's header already uses (StreamMessage.swift:70; the frames'
  `Date().timeIntervalSince1970` at encode, StreamCoordinator.swift:1126).
- **No clock sync, no new round trip.** The device never needs the offset between the Mac's clock
  and its own. It needs a stable reference: **the floor**, the smallest (arrival − time stamp) among
  the audio packets of the last 10 s. A packet stamped T is due at the ear at `T + floor + delay`
  on the device's monotonic clock.
- **Drift.** The two clocks drift apart by tens of ppm. The sliding minimum follows the drift, and
  the playout follows the floor by adding or dropping single frames, never by a jump (§7.2).
- **Why not the ping pairs.** The pong carries no host time: the host echoes the ping's header time
  stamp and payload unchanged (StreamServer.swift:1209-1212), and the device reads only the payload
  (StreamClient.swift:2754-2759).
  - Adding the host's time to the payload would break the move's fence on every older device: it
    compares a pong's whole payload with its nonce (SessionLink.swift:149).
  - The pong's header time stamp could carry it, since nothing reads it, but nothing needs it: the
    host already stamps every audio packet, 100 times a second.
  - The ping pairs keep one job: their round trip tells a host clock step from network jitter
    (§7.2, rule 13).
- **The picture's lag, from the frames.** Each frame's (arrival − time stamp) against the same
  floor, the median of 2 s, plus the display's own delay (decode and the next vsync). It can be
  negative, since the floor is the sound's and the sound's own path (buffer, codec) is the longer;
  it is never clamped. The sound's delay is at least that plus one frame (the guard).
- **What the guard cannot see.** A frame's stamp is taken when its encoding comes out
  (StreamCoordinator.swift:1126), the sound's at capture. So the picture's own time on the Mac, V
  (the capture's delivery, a wait in the encoder's mailbox, the encode), is invisible to the device,
  and where the guard decides, the sound can lead the glass by V − 1 frame: V is a few ms to about
  20 ms on the hardware encoder (no lead at 60 fps; up to ~15 ms at 120 fps, where a Retina frame
  takes about a refresh to encode and may wait for the one before) and one or two frames' time on
  the software encoder (up to ~30 ms of lead at its 60 fps). Both are under the 45 ms at which
  early sound is detected, and at home the guard rarely decides: the need, which covers the
  keyframe, keeps the sound 20–115 ms behind. P6 measures it; §14 has the fix (the host sends V)
  should the sound ever be early.

### How sound shares the link

- **At home it never counts against the picture.** The delta-drop rule drops a frame when more
  than 2 messages are unacknowledged (`inflight > 2`, StreamServer.swift:1291). Audio at 100
  messages a second counted there would drop frames all the time. Audio goes out as the tick and
  the Mac's pointer (kind 26) do, straight to the connection (StreamServer.swift:217, :255): not
  counted in `inflight`, with a cap of its own (§4.6).
- **Away, "audio first, video drops."** Remote pacing (PR #34, on main) counts a remote client's
  backlog in the bytes its connection has not taken yet (`pendingBytes`: everything `send` hands
  over; ticks and kind 26 go around it). Audio bytes count there, because the link carries them:
  against the budget (`remoteBacklogBudget`, 256 KB, or what the last keyframe left behind it plus
  `remoteBacklogSlack`, 128 KB), the hold behind a keyframe still being taken (`remoteHoldCap`,
  512 KB) and the idle mark (`remoteIdleBytes`, 16 KB). `paceRemote` decides for frames only: it
  drops frames, never sound. On a link that cannot carry both, the picture loses frames and waits
  for keyframes while the sound keeps its 16 KB/s.
- **The keyframe a remote client waits for** is asked for once at most `remoteIdleBytes` waits,
  about a second of sound. A link that carries the sound takes each packet as it comes, so what of
  it waits stays a few KB and the ask is not held back; only on a link too slow for the sound
  itself (under about 200 kbps with its headers) does the picture wait behind it, which is this
  rule.
- **Ticks.** A remote client skips a tick right after anything went out (StreamServer.swift:216),
  and with PR #37 every TLS client at home does too (`encrypted`; one on the USB cable gets none):
  while sound flows, a packet every 10 ms, they get none, and the sound keeps the radio awake
  instead. The plain home door (the CLI's default, development builds) keeps every tick.
- **The link report (PR #39, open)** counts the frames pacing withholds (the sound it never
  withholds) and measures what the link carried from the bytes it took, the sound's included; its
  suggestion keeps 30 % in hand, more than the sound's 200 kbps with headers against Low's 4 Mbps.
- **The limit.** Sound cannot overtake video already handed to the connection: one TCP stream, in
  order. At home that is the keyframe in front (the jitter cover above). Away, remote pacing lets
  256 KB queue (more, by the slack, after a keyframe that left more behind it), and behind a
  keyframe the link is still taking, that keyframe and up to 512 KB more: at 4 Mbps 0.5 s, and
  1–4 s behind a keyframe (a 300 KB one and a full hold is 1.6 s). The sound waits as long as the
  picture does. They stay together, and the device's buffer follows the picture (§7.2, rule 4). A
  send queue with priorities (§14) would let sound pass frames Sill has not yet handed over, never
  a keyframe already on its way; only a connection of its own could.
- **Never a delay for frames.** Audio is encoded on its own queue and handed to the network queue
  as one small message (about 190 bytes) the moment it exists. A frame never waits for sound, and
  sound never waits for a frame.

### Controls

- **Send Audio: a host setting, off by default in the first release with sound.**
  - The Mac keeps playing its own sound (ScreenCaptureKit does not silence the source). A device
    beside the Mac, the common case, would double every sound 60–155 ms late until someone mutes
    one of them.
  - The CLI's output stays byte for byte without `--audio`.
  - The pattern the virtual display and Direct Wireless set: off until Noah has tried it, then his
    call (Q1).
  - The Mac's sound leaving the Mac is something the Mac's settings should show.
  - A device can turn it on from its Settings panel, like the other stream settings, and Sill.app
    saves it (Q8).
- **Sound: a button in the device's bars,** only while the Mac sends sound: in every bar that holds
  it, and on a phone held upright at the end of the thumbnails' row, row 1's approved five kept
  (§7.6); and a switch for the same thing in the Settings panel's group for this device, on every
  layout, the only one where no bar holds the button (a Slide Over). It mutes this device alone, at
  once, without asking the Mac. The Mac keeps sending (16 KB/s), so unmuting is quick too (about
  0.1 s, while the device's audio engine starts). The device remembers it.

### Not in this step

- A quiet Mac while the device plays (the Core Audio tap: Q6, §14).
- Sound from the device to the Mac (a microphone).
- One window's sound alone (ScreenCaptureKit's policy is per app).
- Opus, other bitrates, any codec or bitrate choice in a UI (Q2, Q3).
- Delaying the picture for Bluetooth headphones (Q7).
- A path of its own for the sound, past a keyframe on the wire (§14).
- Silence suppression on the host (silent packets cost 8–12 KB/s with their headers on a still
  link, §8).
- Sound while the app is in the background (no `UIBackgroundModes`).

---

## Final plan

### 1. Scope

**In this step:**
1. **The wire.** Kind 29 carries a format (JSON) and packets (binary) of the sound (§3). The hello
   lists what the device plays; kinds 16 and 17 gain `sendAudio`; ClientStats gains two optional
   fields.
2. **The host.** An audio-only ScreenCaptureKit stream that follows the streamed app (or a test
   tone), an AAC-ELD encoder on its own queue, and a send path that never counts against the
   picture. Send Audio (off by default), the CLI's `--audio`, and log lines only when it is on.
3. **Sill.app.** Send Audio in the status menu and in Settings › Streaming, the Permissions pane's
   words, and "sound" on the card's source row while a device gets it.
4. **The device.** A pure playout model (the floor, the jitter buffer, the picture guard, drift by
   single frames), an AAC-ELD decoder, AVAudioEngine playback through an `AVAudioPlayerNode`, the
   session's category and interruptions, the Sound button in every layout's bar and the Sound
   switch in the panel's group for this device, and the panel's Send Audio row.
5. **Tests.** Three pure checks with mutants, new cases in the existing checks that name kinds and
   in the phone's layout check, an encoder-free harness with a test tone, and the CLI byte for byte.

**Not in this step:** see "Not in this step" above.

### 2. The design on one page

```
 ┌──────────────────────────── Mac (Sill.app / SillHost) ─────────────────────────────────┐
 │ main actor  StreamCoordinator.select(…) ─▶ picture pipeline (unchanged)                │
 │             `active`'s didSet (with the pointer's and the menus') ─▶ AudioPipeline     │
 │             .follow(app | desktop | test | none); the same app, running → nothing      │
 │ sill.audio  AudioCapture (SCStream, sound only; its 2×2, 1 fps picture thrown away)    │
 │             or SyntheticAudio (--synthetic) ─▶ PCM + host time                         │
 │             AudioPacketizer: 480/512-frame blocks, stamps, gaps → segments (pure)      │
 │             AudioEncoder: AAC-ELD, 128 kbps (AudioToolbox) ─▶ packet, wall-clock stamp │
 │ sill.net    StreamServer.broadcastAudio: devices whose hello plays "aac-eld";          │
 │             the format first; not in `inflight`; in `pendingBytes` away; a cap ────────┼─▶ kind 29
 └────────────────────────────────────────────────────────────────────────────────────────┘
 ┌──────────────────────────────── device ────────────────────────────────────────────────┐
 │ network q.  MessageReader; kind 29 parsed, frames: both stamped on arrival, handed on  │
 │ sill.audio  AudioPlayout (pure): floor, need, picture's lag, dedupe → late? place?     │
 │             a frame more or less? a jump?                                              │
 │             AudioDecoder (AAC-ELD → float) ─▶ fades, ±1 frame ─▶ AVAudioPlayerNode     │
 │             AVAudioEngine: player → main mixer → output; session .playback, mixes      │
 │ main        Sound (the bars, the panel: mute, local), Send Audio row (kind 17), speech │
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3. Wire protocol

#### 3.1 Kind 29 (`Sources/StreamProtocol/StreamMessage.swift`, continuing the enum)

```swift
    // The Mac's sound (Audio.swift), after the menus' 24, 25 and 27, the pointer's 26 and the trackpad
    // gesture's 28 (Gesture.swift, PR #38). Older readers map it to `.unknown` and skip it.
    case audio = 29          // host → device: AudioMessage — the sound of what streams: a format (JSON AudioFormat),
                             // then packets (binary). Only to a device whose hello lists the codec, and only while Send
                             // Audio is on
```

- **Who skips it.** Every device and test client since b67f87d (2026-09-23): `parseHeader` maps an
  unknown kind to `.unknown` (StreamMessage.swift:116), MessageReader reads it whole like any other
  kind under its cap, and the client's `handle` ignores it (StreamClient.swift:2792-2793). A device
  from before this step is never sent one anyway (§3.5).
- **Its size.** A format is under 1 KB and a packets message under 1 KB at 128 kbps, far under
  `maxOtherHostPayload` (4 MB, MessageReader's cap for anything but frames); §3.2's parser caps
  them at 4 KB and 16 KB.
- **Nothing else changes** in kinds 0–28. If a branch has taken 29 by the time this starts, the next
  free number, and this section follows it (H0, Q12). On 2026-09-27 24 to 27 are on main (PRs #31
  and #36), 28 is PR #38's `gesture`, and no branch, worktree or plan holds 29 or above.
- **The checks that name the free kinds.** On main `protocol` and `menus` say 28 reads as unknown
  and `pointer-control` that every kind from 28 to 254 does. #38 (its head 0c8d5a6, main merged in)
  moves them on to 29, and its `compatibility` says 29 is not this build's. With the sound, 29 is
  `audio` and they move on to 30. Mutants that renumber a kind onto 29 (with #38: `menus`' "the
  fetch at 29", `pointer-control`'s "kind 26 numbered 29" and `compatibility`'s "kind 28 as 29";
  on main today only the second) would no longer compile, as a kind renumbered onto a taken one
  does not: they move to numbers no plan will take (250 to 254), and `pointer-control`'s "numbered
  30" with them, so the next kind moves none of them (H3).

#### 3.2 The payloads (`Sources/StreamProtocol/Audio.swift`, new; the iOS app gets it through the package, no pbxproj entry)

A kind 29 payload's first byte says what follows. A type this build does not know is skipped.

```
type 1  format:   JSON AudioFormat
type 2  packets:  epoch UInt16 · seq UInt32 · flags UInt8 · count UInt8 · count × (length UInt16 · bytes)
                  big endian, like the header; flags bit 0 = the first packet of a segment (reset the
                  decoder); bits 1–7 zero, ignored by readers
```

```swift
/// Host → device (kind 29, type 1): how to decode what follows. Sent to each device before its first
/// packet of an epoch, and again for every new epoch (a new encoder: the app changed, Send Audio
/// came on, the capture restarted). JSON; every field optional (HostSettings.swift's rules).
public struct AudioFormat: Codable, Hashable, Sendable {
    /// "aac-eld" in this step. A device that does not play it ignores the sound.
    public var codec: String?
    public var sampleRate: Int?          // 48000
    public var channels: Int?            // 2
    public var framesPerPacket: Int?     // 480 or 512
    public var primingFrames: Int?       // 240 or 256: the decoded frames a new segment starts with that are the codec's own
    public var bitrate: Int?             // 128000, the encoder's target (display only)
    public var epoch: Int?               // the epoch of the packets this format belongs to
    public var cookie: Data?             // the codec's magic cookie (AAC-ELD: its AudioSpecificConfig); base64 in JSON
    /// What the sound is of, display only: "app" (then `app`), "desktop" or "test". A string, never an enum.
    public var source: String?
    public var app: String?              // "Safari": SafeText.label, at most 64 characters
}

/// Host → device (kind 29, type 2): one or more codec packets of one epoch, back to back.
public struct AudioPackets: Hashable, Sendable {
    public var epoch: Int                // UInt16 on the wire, wraps
    public var seq: UInt32               // the first packet's number in its epoch, from 0
    public var segmentStart: Bool        // flags bit 0
    public var packets: [Data]           // 1…255 of them; this host sends one
    public func serialized() -> Data     // the type byte included
}

public enum AudioMessage: Hashable, Sendable {
    case format(AudioFormat)
    case packets(AudioPackets)
    /// Nil for an empty payload, an unknown type, a count of 0, a length past the end, bytes left
    /// over, a format over 4 KB or packets over 16 KB. Never traps on any input.
    public static func parse(_ payload: Data) -> AudioMessage?
}
```

- **The header's time stamp** is the host wall-clock time (seconds since 1970) of the first decoded
  sample of the message's first packet (§3.3). The packets after it follow at
  `framesPerPacket / sampleRate` apart. **`isKeyframe`** is false.
- **Examples.**
  - A format: `01` then
    `{"app":"Safari","bitrate":128000,"channels":2,"codec":"aac-eld","cookie":"+AFAIAQA…","epoch":3,"framesPerPacket":480,"primingFrames":240,"sampleRate":48000,"source":"app"}`.
  - The first packet of a segment: `02 0003 00000000 01 01 00A2` and 162 bytes of AAC-ELD: 173
    bytes, 187 with the header.

#### 3.3 The time stamp: the video's clock

- **Converted when sent.** The host converts ScreenCaptureKit's presentation time (on the
  host-time clock, `CMClockGetHostTimeClock`, as the picture's frames) to the wall clock at the
  moment it sends each packet: `stamp = Date().timeIntervalSince1970 − (hostNow − hostTime)`. A
  wall-clock step on the Mac then shows in the sound and in the picture alike.
- **Which sample.** Packet n of a segment decodes, on a fresh decoder, to frames [n·F, (n+1)·F) of
  the decoded stream, which lags the input by P priming frames (F frames a packet; P =
  `primingFrames`). The probe found AudioToolbox's AAC-ELD decoder hands the priming out rather
  than trimming it. So the stamp is the host time of the segment's input frame `n·F − P`, taken
  from the capture buffers' own times (the packetizer keeps an anchor per buffer, §4.3).
- **The start of a segment.** Its first P decoded frames come before its first captured frame: the
  device drops them (§7.2, rule 9).
- **Checked end to end** by H4 and H5: a click at a known time lands at its stamp ±1 ms after the
  whole path.

#### 3.4 Fields added elsewhere (all optional, all additive)

| Where | Field | Meaning |
|---|---|---|
| `Hello` (Compatibility.swift:94-108) | `audio: [String]?` | The codecs this device plays, best first: `["aac-eld"]`. Nil: an older device, which gets no kind 29 |
| `StreamSettings` (HostSettings.swift:49-70) | `sendAudio: Bool?` | Send Audio. Nil: a host without sound, so the device shows no row and never sends it (the ledger's rule 9) |
| `HostSettingsChange` (HostSettings.swift:126-164) | `sendAudio: Bool?` | A device turns it on or off; `isEmpty` and `applied(to:)` include it |
| `HostSettingsState` (HostSettings.swift:92-120) | `audioNote: String?` | Why no sound comes although Send Audio is on ("couldn't capture the sound of Safari"); nil when all is well. The Mac's, the same for every connection (PR #39's `away` and `link` beside it are each connection's own) |
| `ClientStats` (Viewport.swift:38-53) | `audioBehindMs: Int?`, `audioLate: Int?` | That second's median of how far the sound trailed the picture as the device sees it (without the picture's time on the Mac, V: §Decision), -1 for a second with no sound played; the packets that came too late to play. Nil from a device that has played none this session |

#### 3.5 Compatibility

| Device | Host | Result |
|---|---|---|
| Older (any build since b67f87d) | This host, Send Audio on | Its hello has no `audio`, so it is sent no kind 29 (it would skip one). It ignores `sendAudio` and `audioNote` in kind 16. Nothing changes for it |
| This device | Older host (Sill for Mac 0.3.1, the public release; any CLI before this) | No kind 29; `sendAudio` nil: no row, no Sound button or switch |
| This device | This host, Send Audio off | The row shows off; no button; no kind 29 |
| This device | This host, Send Audio on | This plan |
| The base's `sillclient.py` | This host | No hello, or one without `audio`: no kind 29. Kind 16 carries two more keys |
| A test client whose hello lists `audio` but that does not decode | This host | Gets kind 29 and may skip it |

#### 3.6 Rules for later changes

- HostSettings.swift's rules apply to `AudioFormat` and the new fields: JSON, optional, strings not
  enums, never renamed or retyped.
- The packets' layout is fixed: a change is a new type byte, never a changed type 2.
- A new codec is a new `codec` string, listed in the hello by the devices that play it. A host
  picks the first of a device's list that it can make; this host makes only "aac-eld".
- The first public builds set the compatibility floor for good (CLAUDE.md). If the sound ships in
  them, kind 29's two types, `AudioFormat`'s fields, the hello's `audio`, `sendAudio` and
  `audioNote` join it: kept as they are, and a later host still sends kind 29 only to a device
  whose hello lists the codec.

### 4. Host (`SillHostCore`, folder `Sources/SillHost`), file by file

**Base.** main at 643af6b. Remote pacing (#34) is in: §4.6 builds on its `pendingBytes`, H6 on its
harness (`Scripts/pacing`: the fake encoder, bottleneck.py, its cases; `Scripts/sillrelay.py` for
the remote door's slow link), and the device reads kind 29 through its MessageReader. Since the critique (150f781) main has also gained the Mac's pointer
(#31: kind 26, sent from StreamServer's tick; `PointerTestHooks`, whose `SILL_TEST_SOFTWARE_ENCODER`
and `SILL_TEST_LOOPBACK` every test host now runs with), the menus (#36: kinds 24, 25 and 27,
`MenuMirror`, which follows the source from `active`'s didSet as the sound will), the iPhone's
portrait layout (#30) and the tour (#35). Open and touching this plan's files, each merged into
this branch as it lands (§12): #37 (pairing at home: StreamServer's doors behind one `Door`, TLS at
the home door, the hello read inside TLS by the Door's gate), #38 (gestures: kind 28, its handler
and rate in StreamCoordinator, the panel's This iPad group) and #39 (away from home: kind 16's
per-connection `away` and `link`, `LinkJudge` in StreamServer's sweep, a second quality pair in
`HostConfig`, the move home).

#### 4.1 `HostConfig.swift` and `DeviceSettings.swift`

- **`HostConfig.sendAudio: Bool`,** required in `init` like every knob, so the compiler finds each
  place that builds one. `standard`: false. `validated()`: nothing to clamp. `changes(to:)`:
  "send audio off → on".
- **`streamSettings`:** `sendAudio: sendAudio`. **`applying`:** `if let v = change.sendAudio
  { c.sendAudio = v }`.
- **`DeviceSettings.accepted`:** `if let v = c.sendAudio { ok.sendAudio = v }`, from either door.
  It changes what a device hears of the Mac, not who can reach the Mac (Q8). With PR #39 a change
  from a device away goes through `applyingAway`, which puts the quality on the away pair and
  passes every other field on to `applying`: Send Audio, one value home or away, lands the same.
- **Not in `restartNeeded`** (StreamCoordinator.swift:555-564): the sound has its own stream;
  `adopt` hands it over (§4.7).
- **Every other place** HostSettings.swift's header lists for a new setting (Sill.app's
  `HostSettings` and `DebugHooks`, the ledger, the panel, the mock, `sillclient.py`) is in §6 and
  §7.

#### 4.2 The sources: `AudioCapture.swift` (new) and `SyntheticAudio.swift` (new)

Both conform to:

```swift
protocol AudioSource: AnyObject {
    /// On `sill.audio`: PCM as delivered, its format, and the host time (mach absolute, in
    /// seconds) of its first frame.
    var onPCM: ((PCMChunk) -> Void)? { get set }
    /// It ended by itself; why, for the log. Not called by `stop()`.
    var onStopped: ((String) -> Void)? { get set }
    func start() async throws
    /// Returns once no chunk is in flight.
    func stop() async
}
```

**`AudioCapture`** (ScreenCaptureKit, CoreMedia):
- **The configuration.** `capturesAudio = true`, `sampleRate = 48_000`, `channelCount = 2`,
  `excludesCurrentProcessAudio = true`. For the picture ScreenCaptureKit always makes: `width = 2`,
  `height = 2`, `minimumFrameInterval = 1 s`, `queueDepth = 3`, `showsCursor = false`. P2 records
  whether this macOS takes 2×2; 64×64 otherwise.
- **Outputs.** `.audio` on `sill.audio`, and `.screen` on the same queue, returning at once:
  without a screen output ScreenCaptureKit logs every frame it drops.
- **The filter** is made by the coordinator (§4.7) and never changed on a running stream: another
  app is another stream. The app's `SCRunningApplication` comes from the catalog's last look, else
  from one bounded look at every application, as `resolveOwnApplication` finds Sill's
  (WindowCatalog.swift:152-157): a window staged on the virtual display can be off the on-screen
  list, and so can a minimized app's.
- **Each buffer:** its ASBD (`CMSampleBufferGetFormatDescription`), `CMSampleBufferGetNumSamples`,
  its PTS in seconds; the PCM copied with `CMSampleBufferCopyPCMDataIntoAudioBufferList` into a
  reused buffer. A PTS more than 1 s from `CMClockGetTime(CMClockGetHostTimeClock())` is not on the
  host clock: logged once and replaced by the arrival time minus the buffer's duration.
- **Bounded.** `startCapture` and `stopCapture` each get 2 s, as the other ScreenCaptureKit calls
  are bounded (WindowCatalog.swift:167). A start that runs out is a failure (`audioNote`).
- **`didStopWithError`** → `onStopped`: the permission revoked, the sound failing to start or stop
  (`SCStreamErrorFailedToStartAudioCapture` −3818, `…FailedToStopAudioCapture` −3819), the system
  stopping the stream (`SCStreamErrorSystemStoppedStream` −3821, macOS 15). A window closing ends
  nothing: the filter is the app's. The pipeline starts it again at the picture's next select
  (§4.5).
- **A minute in,** one line on the buffers' time stamps and silence (§4.10), for P2.

**`SyntheticAudio`** (Foundation only; `--synthetic`):
- A 10 ms `DispatchSourceTimer` on `sill.audio` paces 480-frame chunks of 440 Hz at −30 dBFS,
  stereo float. A chunk's host time is the first chunk's plus the frames made before it ÷ 48 kHz,
  never the timer's firing time: a late timer makes two chunks at once, never a gap, so the tone is
  gapless unless a test pauses it (§4.11).
- A 4 ms windowed 2 kHz click at −6 dBFS starts at each whole second of the wall clock, as the
  stamps will carry it (the host time ↔ wall clock mapping taken when the tone starts), so a
  checker needs only the stamps to check them end to end.
- The chunk goes the same way as ScreenCaptureKit's.
- TEST ONLY: `SILL_TEST_AUDIO_CHUNK=1024` makes 1024-frame chunks every 21.3 ms, so the 512-frame
  packets are tested headless too (§4.11).

#### 4.3 `AudioPacketizer.swift` (new; pure: Foundation only; checked with swiftc)

Turns chunks into blocks of F frames with their host time, and decides the segments.
- **The packet size,** once per epoch, from the first chunk: 512 if its frame count is a multiple
  of 512, else 480.
- **A FIFO** of planar float frames, and for each chunk an anchor: the segment frame number of its
  first frame, and its host time.
- **Continuity.** A chunk is expected at the previous chunk's end (its time + frames / rate):
  - within a quarter of a chunk (2.5 ms for 480 frames, 5.3 ms for 1024): appended as it is (time
    stamp jitter: the stamps follow the anchors, the samples never move). A lost buffer is a whole
    chunk late, so none hides in the tolerance; the minute's line (§4.10) says how close
    ScreenCaptureKit keeps to it;
  - anything else, later or earlier: the segment ends where it is, and a new one starts at this
    chunk (`segmentStart`; the encoder's `reset()`). What the encoder still holds, the partial
    block and the codec's lookahead (at most F − 1 + P frames, 15 ms), is dropped: never flushed
    and never padded or filled with zeros, since a packet made then is stamped a gap ago, would
    reach the device late by the gap and raise its need for 10 s as if the link had jittered
    (§7.2, rule 6). The device fades the segment's last packet out (rule 10) and places the next
    segment by its stamp (rule 5);
  - a new format (rate, channels) ends the epoch: the pipeline makes a new encoder (§4.5).
- **The stamp of block n:** the host time of segment frame `n·F − P`, interpolated between the
  anchors (or extrapolated before the first). The pipeline turns it into wall time as it sends
  (§3.3).
- **`AudioSourceRule`** (same file, pure): what `follow` does with the current and the wanted source
  (§4.5). The same app (by pid) with its stream running → keep. The same app whose stream ended by
  itself → start it again, at most once every 10 s. Another app, the Desktop, the test tone → a new
  stream and a new epoch. None → stop.

#### 4.4 `AudioEncoder.swift` (new; AudioToolbox only, so the harness links it: no CoreMedia, no AVFoundation)

- **The converter.** `AudioConverterNew` from the first chunk's PCM format (any rate or layout: the
  converter resamples and interleaves) to `kAudioFormatMPEG4AAC_ELD`, 48 kHz, 2 channels,
  `mFramesPerPacket` F; `kAudioConverterEncodeBitRate` 128,000.
- **Read back:** `kAudioConverterCurrentOutputStreamDescription` (F),
  `kAudioConverterPrimeInfo.leadingFrames` (P), `kAudioConverterCompressionMagicCookie` (the
  cookie), `kAudioConverterPropertyMaximumOutputPacketSize`.
- **Use.** `encode(block) -> Data` per block, on `sill.audio`; `reset()` (`AudioConverterReset`) at
  a segment start, which drops what the converter holds and starts the next packets with the same
  priming P (the critique's probe).
- **A failure to create it:** "Audio encoder: AAC-ELD unavailable: <status>", and no sound this run
  (`audioNote`).

#### 4.5 `AudioPipeline.swift` (new)

Owns the source, the packetizer and the encoder on `sill.audio` (serial, `.userInteractive`), the
epoch counter, and what the coordinator and the server see of them.
- **`follow(_ key: AudioKey, make: @escaping () async -> AudioSource?)`** (main actor; returns at
  once). The work runs in a Task, and a newer call replaces one not yet begun, as `setTarget`'s
  changes do. `AudioKey` is `.app(pid, name)`, `.desktop`, `.test` or `.none`. `make` builds the
  source: the coordinator's closure makes an `AudioCapture` with its filter (after the bounded look
  for the app, §4.2; nil when it is not found, a failure like any other), or a `SyntheticAudio`. So
  AudioPipeline never imports ScreenCaptureKit, and the harness compiles it.
  - The same app (by pid) as a running stream: nothing (a resize, a rotation, another window of
    it). As a stream that ended by itself: start it again (`AudioSourceRule`'s 10 s).
  - Otherwise: the running stream stops, one for the wanted source starts, with a new epoch.
  - `.none`: stop.
- **When it runs:** Send Audio on, a source live, at least one connected device that plays
  "aac-eld" (the server's count, §4.6), and not shutting down. The coordinator calls `follow`
  whenever any of those changes (§4.7).
- **Epochs.** A new encoder is a new epoch (UInt16, wrapping): another source, Send Audio coming
  on, a capture that restarted, or a new PCM format from the source. Its format message is built
  and handed to the server before the epoch's first packet; seq starts at 0.
- **Each block:** encoded, stamped (§3.3), and handed to `server.broadcastAudio(packets:)` as one
  packet. Stats `aud.out`.
- **Failures never touch the picture.** A source that fails to start, or stops by itself, sets
  `audioNote` and logs one line. The next `follow` tries again: the picture's next select (a pick, a
  rotation, a restart), another source, or Send Audio off and on; the same app at most once every
  10 s. No retry loop.
- **Status:** `HostStatus.audio` (§4.8), and `audioNote` for kind 16.

#### 4.6 `StreamServer.swift`

- **`Client`** (StreamServer.swift:45-106) gains:
  - `audioCodecs: [String]`, from the hello;
  - `audioEpochSent: Int?`, the epoch whose format it has;
  - `audioUnsent: Int`, audio messages handed to the connection and not yet taken.
- **`took(_:from:)`** (:1082-1089) sets `client.audioCodecs = hello.audio ?? []`. It is where every
  hello lands: the plain door's from the receive loop (:1237-1243), and with PR #37 a TLS door's
  from `serve`, once its Door's gate has read it inside TLS. When the number of clients that play
  "aac-eld" changes (here and in `unregister`, :1146-1154), `onAudioListenersChanged(count)`. The
  hello's own line is unchanged.
- **`broadcastAudio(format: Data, epoch: Int)`** keeps `lastAudioFormat`, as `lastParameterSets` is
  kept (:1277).
- **`broadcastAudio(packets: Data, epoch: Int)`,** for each ready client that plays "aac-eld":
  - `audioEpochSent != epoch` → the format first (never skipped), and `audioEpochSent = epoch`;
  - `audioUnsent` at its cap → this packet is skipped (`aud.drop`). The cap is a stalled link's
    safety valve, not pacing: 100 messages at home (1 s), 300 away (3 s; a remote queue can
    legitimately hold a second of stream, and the device follows the picture's lateness);
  - otherwise `sendAudio(_:to:)`: `connection.send` with its own completion, `aud.sent`.
- **What `sendAudio` counts.** Not `send(_:to:isFrame:isKeyframe:)` (:1417-1464), which counts
  every message in `inflight`; a send of its own, as the tick and kind 26 have (:217, :255).
  - **Every client:** `lastSentAt` set, as after any message, and never `inflight`,
    `inflightFrames` or the drain eviction's clock, which stay the picture's, byte for byte
    (:1274-1304, :1417-1464).
  - **Away** (`route.isRemote`, as the pacing is keyed): added to `pendingBytes`, and taken from it
    in its completion, so the budget, the slack, the hold and the idle mark see the bytes the link
    must carry (§Decision). Never `keyframesInFlight`, `keyframeBytesInFlight` or `backlogFloor`
    directly: those are the keyframes', and the floor follows `pendingBytes` down by itself.
    `paceRemote` (:1330-1371) is unchanged: it sees only frames.
- **Ticks** (:204-220): unchanged in code. A client skips its tick right after a send when it is
  remote (:216), and with PR #37 when it is TLS at all (`encrypted`), so while sound flows those
  get none, the sound keeping the radio awake; the plain home door keeps every tick; a TLS client
  on the cable (#37) gets none anyway. A kind 26 still stands in for a tick.
- **`resetForNewStream`** (:1158-1166, the picture's restarts) leaves the sound's state alone.
- **The remote sweep** (:1118-1142) and, with PR #39, `LinkJudge`'s second: nothing new. Frames
  withheld are frames; the sound is never withheld by pacing, only skipped at its cap on a stalled
  link, and its bytes count in what the link took.

#### 4.7 `StreamCoordinator.swift`

- **Owns** `let audio: AudioPipeline`, built in `init` with the server and `synthetic`.
- **Where `follow` is called** (main actor), one function (`audioFollow()`) computing the key: the
  source's, while Send Audio is on, a device plays "aac-eld" and Sill is not quitting; `.none`
  otherwise.
  - **In `active`'s didSet** (:143-152), after the pointer's geometry and the menus' target, which
    follow the source there since #31 and #36. `active` is set on every path of `select`: once the
    picture's pipeline has started (`startPipeline`, :1139-1140), or to `.none`; a restart of the
    same source sets it again, and the same app keeps its sound. The key from `active`, as
    `menuTarget()` finds the app (:1367-1381): a window staged on the virtual display by its
    placement's pid, any other window by the catalog's `owningApplication`; `.desktop` → `.desktop`
    (a filter of the same kind as the picture's, :1065-1074), or `.test` on a synthetic host;
    `.none` → `.none`. The picture always starts first.
  - On `onAudioListenersChanged`.
  - In `adopt` (:568-586), when `sendAudio` changed, with the one "Settings:" line every knob gets:
    at once when nothing is switching, else not (`switching`): the select committing the change
    sets `active` once its picture has started, and the didSet follows then.
  - With `.none` in `shutdownForExit` (:1520-1524), after the goodbye.
- **`settingsState`** (:1852-1861): `sendAudio: config.sendAudio` in `StreamSettings`, and
  `audioNote: audio.note`.
- **A device's change** goes through the kind 17 handler unchanged (:691-729,
  `DeviceSettings.accepted`).
- **Beside the menus and the gestures.** The sound adds no device → host kind and no per-connection
  state here (the server keeps each device's codecs and epoch), so `handle(_:from:)`,
  `onClientDisconnected` and `onClientCountChanged` gain nothing: the listener count is the
  server's (`onAudioListenersChanged`). The menus' reads on `sill.menus` (#36) and the gestures'
  chords held behind an activation (#38) never wait for the sound, nor it for them; a gesture's
  Desktop pick moves the sound to the whole Mac as any pick does.

#### 4.8 `HostStatus.swift`

`HostStatusSnapshot.audio: Audio?`, nil while no sound is captured: `source` ("Safari", "Whole
Mac", "Test Tone"), `devices` (how many get it), `problem: String?`.

#### 4.9 Threads (host)

| Queue | Sound's work |
|---|---|
| main actor | `follow`'s decisions, `adopt`, status |
| `sill.audio` | ScreenCaptureKit's sound (and its thrown-away picture), the tone's timer, the packetizer, the encoder (about 70 µs a packet), the stamps |
| `sill.net` | `broadcastAudio`: a walk over the clients and one `send` each |
| `sill.capture`, `sill.encode` | nothing: the picture's queues never see sound |
| `sill.menus`, `sill.pointer` | nothing: the menus' Accessibility reads and the pointer's window re-reads never see sound |

#### 4.10 Log lines and Stats keys (exact; none unless Send Audio is on, or a device changes it)

| When | Line |
|---|---|
| Sound starts for a window | `Audio: capturing Safari's sound (every window of it).` |
| … for the Desktop | `Audio: capturing the whole Mac's sound (every app but Sill).` |
| … on a synthetic host | `Audio: a test tone (440 Hz at -30 dBFS, a click at each second).` |
| Its first buffer | `Audio: first buffer 1024 frames, 48000 Hz, 2 channels, 32-bit float, non-interleaved, 9 ms after its time stamp.` |
| A minute after it | `Audio: first minute: 2812 buffers, time stamps at most 0.3 ms from contiguous, 0 gaps, 1406 silent.` ("silent": every sample zero) |
| The encoder, each epoch | `Audio encoder: AAC-ELD 48 kHz stereo, 512 frames a packet (10.7 ms), 128 kbps, codec delay 256 frames.` |
| It stops | `Audio stopped: nothing streams.` · `Audio stopped: no connected device plays sound.` · `Audio stopped: Send Audio is off.` · `Audio stopped: Sill is quitting.` |
| A start fails | `Audio: could not capture Safari's sound: <error>. The picture is unaffected.` |
| It ends by itself | `Audio capture ended: <error>. The picture is unaffected.` |
| A device's stats | the `client …` line gains `, sound 42 ms behind` (and `, 3 late` in a second with late packets) when the report's `audioBehindMs` is 0 or more |
| A setting | `Settings: send audio off → on` · `Settings from iPad (iPad14,1): send audio off → on` (`HostConfig.changes`) |

Stats keys, only while sound is captured: `aud.in` (chunks), `aud.out` (packets encoded), `aud.sent`
(messages sent, every device), `aud.drop` (skipped at a cap), `aud.gap` (segments begun after a
gap).

#### 4.11 TEST ONLY hooks (honoured only by synthetic hosts, which do not advertise)

`SILL_TEST_AUDIO_CHUNK=1024` (§4.2), and `SILL_TEST_AUDIO_PAUSE=S@T[,S@T…]`: the tone makes
nothing for S seconds from T seconds after it starts, then goes on from where the clock is (H8).
Nothing else: the test tone is the test source. Every test host also runs with main's
`SILL_TEST_LOOPBACK=1` (both doors on 127.0.0.1 alone) and `SILL_TEST_SOFTWARE_ENCODER=1` (never a
hardware encoder session), PointerTestHooks' since #31, honoured by a synthetic host alone; with
PR #37 the loopback one is among TestHooks' door hooks too, which a test host alone takes
(`DoorPolicy.isTestHost`) and Sill.app ignores with a line each.

### 5. CLI (`Sources/SillHostCLI/main.swift`)

- **`--audio`:** `config.sendAudio = true`, and after the startup lines (main.swift:114-117) one
  more: `Audio on for this run: devices that play sound get the streamed app's sound, or the whole
  Mac's for the Desktop.`
- **`--synthetic --audio`:** the test tone (§4.2).
- **A device's change** lasts until SillHost quits, as every setting does.
- **Whichever door** (the plain home door by default; PR #37's `--pairing` puts it behind TLS; the
  remote door with `--remote`): the sound goes to every device whose hello plays it.
- **Without `--audio`: stdout byte for byte** (H2), idle and streaming, whatever the devices'
  hellos say.

### 6. Sill.app (`Sources/SillMenuBar`)

- **`HostSettings`:** the key `sendAudio`, registered default false, loaded and saved
  (`save(changedFrom:)`) like the others; `defaults read me.saffer.sill.mac sendAudio`; the launch
  argument `-sendAudio 1` for one run.
- **`DebugHooks.apply`:** `-SillSetAfter '2 sendAudio=1'`.
- **The status menu** (StatusItemController.swift:80-97): after Resolution, the last item of the
  picture's group: **Send Audio**, checked, subtitle **"The Mac keeps playing it too"**, action
  `.setSendAudio(!config.sendAudio)` (it sets the value it showed, as Virtual Display does).
- **Settings › Streaming** (SettingsPanes.swift:203-244): a section after the picture's, after
  "Prioritize encoding speed" (and after PR #39's Away from home once it is in):
  `Toggle("Send audio", …)` with the footer **"Devices play the sound of what you stream: all of
  the streamed window's app, or every app for the Desktop. The Mac keeps playing it too, and each
  device can mute it with its Sound button. Nothing is recorded."** While
  `snapshot.audio?.problem` is set, under it, the orange label: **"Sill couldn't capture the sound
  of Safari: <reason>. The picture is unaffected."**
- **Settings › Permissions** (SettingsPanes.swift:318-321): Screen Recording's explanation becomes
  **"Lets Sill capture the windows you pick on your iPhone or iPad, and their sound when Send Audio
  is on. Nothing is recorded or saved; frames and sound go straight to your devices."**
- **The card** (StatusText.swift:179-203): the source row's detail ends in **" · sound"** while
  `snapshot.audio?.devices ?? 0 > 0`. A new preview sample, `sound`, the widest source row with it
  (H10).
- **The Log window** shows §4.10's lines as it shows every line.

### 7. iOS client

#### 7.1 Files

Each new file needs its four pbxproj entries by hand, in a block of their own: AA01/FA01,
AA02/FA02 and AA03/FA03 (the IDs end `…AA01`, `…FA01`), re-checked at H0. On 2026-09-27, over
every branch and worktree: A001–A01E and A020 (main; A020 is MessageReader.swift),
A040–A044 (the menus), A101, A201, A301 (the pointer), A401 and A402 (the tour), A501 (the phone's
layout), A601 (home pairing's StreamClient+Home.swift), A701 (the gestures' TrackpadGestures.swift)
and A801 (away's AwayCopy.swift), each with its F pair. The critique's A401–A403 went to the tour.
Blocks are taken in order, so the next branch will most likely take A901: the sound takes the one
after it. The privacy manifest
needs nothing new: the playout reads the host clock (`CACurrentMediaTime`, AVAudioTime's host
time), and a direct `mach_absolute_time` is covered by its System boot time reason, 35F9.1.

| File | What | Imports |
|---|---|---|
| `AudioPlayout.swift` (new) | The playout model: floor, need, the picture's lag and the guard, dedupe, placement, frames added or dropped, fades. Pure: checked with swiftc (`audio-playout`) | Foundation |
| `AudioDecoder.swift` (new) | AAC-ELD → 48 kHz stereo float, from the format's cookie | AudioToolbox |
| `AudioOutput.swift` (new) | AVAudioEngine, the player node, a buffer pool, the session and its notifications | AVFAudio, UIKit |
| `StreamClient.swift` | Kind 29, the hello's `audio`, frames' stamps to the model, stats, resets | |
| `StreamScreen.swift` (`TopBar`), `PortraitStreamScreen.swift` (the window bar, the phone's row 2), `MacMenuButton.swift` (`fits`, which Sound shares) | The Sound button in every bar | |
| `PhonePortraitLayout.swift` | The phone's row 2 with Sound at its end (`Tests/checks/phone-portrait`; `tour` compiles it too) | CoreGraphics |
| `HostSettingsPanel.swift`, `HostSettingsLedger.swift`, `MockCatalog.swift`, `ContentView.swift`, `DiagnosticsHUD.swift` | The Send Audio row and the Sound switch, the field, the harness, the HUD | |

**Why a player node and no render block of Sill's own.** The iOS 27 SDK adds
`AVAudioSourceNodeRenderBlockRealtimeSafe` and keeps it from Swift with the message "Swift is not
supported for use with audio realtime threads" (AVAudioSourceNode.h:48). A render block Sill wrote
would be Swift on the real-time thread. With `AVAudioPlayerNode.scheduleBuffer`, every line of
Sill's runs on ordinary queues, and the real-time code is Apple's.

#### 7.2 `AudioPlayout` (pure; Foundation only)

- **Clocks.** Device times are seconds of the monotonic clock (`CACurrentMediaTime`, the host clock
  whose ticks AVAudioTime's `hostTime` counts); host stamps are wall-clock seconds.
- **Queue.** It runs on `sill.audio`. The network queue stamps each frame and each kind 29 with its
  arrival as MessageReader delivers them whole, and hands them over. The few a move's probe read
  on its new connection before the hand-over are handled there, at the hand-over (`finishMove`
  replays them), and stamped then, a few ms late: nearly all duplicate what the old connection
  brought, and rule 7 drops a duplicate before it counts anywhere.

**Inputs:**
- `format(_:)`: a new epoch (F, P, the sample rate).
- `frame(stamp:arrival:)`: every video frame (kind 1), for the picture's lag.
- `packet(epoch:seq:stamp:arrival:segmentStart:)` → a decision (the rules below).
- `played(sampleTime:at:)`: the player's progress (`lastRenderTime`, `playerTime(forNodeTime:)`),
  read at each schedule.
- `latency(output:presentation:io:refresh:streamFPS:)`: the session's `outputLatency` and
  `ioBufferDuration` as read back once it is active (Apple: the preferred duration is only a
  request; the minimum is about 5 ms, 256 frames, the typical maximum 93 ms), the player node's
  `outputPresentationLatency`
  (the engine's own latency after the player), the panel's refresh and the stream's rate.
- `rtt(median:)`: from the pings, once a second (rule 13).
- `away(_:)`: whether this session is away from home (the remote door's route), for the jitter
  cover's start and bounds (rule 2); it changes at a move home (PR #39), which is a hand-over.
- `reset(_:)`: a reconnect (a new session connection after the old one ended), a route change,
  unmuting, the engine restarted. A move's hand-over is not one (rule 7).

**The rules:**
1. **The floor** is the smallest (arrival − stamp) of the audio packets in the last 10 s, kept in
   1 s buckets. With no packet for 10 s it keeps its last value.
2. **The need** is what a packet needs between arriving and being heard: the jitter cover, the
   largest (arrival − stamp − floor) of those packets in the last 10 s (the link's jitter, a
   keyframe in front included); plus one packet (F / rate, rule 10's wait); plus the IO buffer (the
   render runs that far ahead of the output); plus the output latency (the session's
   `outputLatency` and the player's `outputPresentationLatency`: a few ms on the speaker, 150–250 ms
   on AirPods, up to 2 s on AirPlay); plus 2 ms.
   - The jitter cover starts at 40 ms at home and 150 ms away, until 2 s of packets have come; its
     window leaves those 2 s out (a connection's catalog and first keyframe go ahead of its first
     packets, and would hold the cover at its bound for 10 s).
   - Its bounds: home 20–150 ms; away 60–600 ms. The rest has none: it is what the route costs.
     A move home (PR #39) changes the bounds at the hand-over and nothing else: the window keeps
     what it saw, under home's 150 ms, until it forgets the away link.
   - It rises at once (rule 6). It falls when the window forgets its maximum, and the error that
     leaves is closed by rules 11 and 12.
3. **The picture's lag** is the median (arrival − stamp − floor) of the frames of the last 2 s, plus
   1.5 refreshes and 4 ms: decode and the next vsync, since frames are shown on arrival
   (HEVCDisplayView.swift:306-309). No frames (a still window): its last value. It can be negative
   (the floor is the sound's, and the sound's own path is the longer); it is never clamped.
4. **The delay** is max(need, the picture's lag + one frame of the stream's rate). A packet stamped
   T is due at the ear at `T + floor + delay`, and is rendered the output latency (rule 2's)
   earlier: scheduled for `due − output latency` on the player's timeline. The guard has no bound:
   on a link where the picture runs a second late, so does the sound.
5. **Placement.** The first packet of a segment, and the first after an underrun or a jump, is
   placed by time (`AVAudioTime(sampleTime:atRate:)` in the player's timeline, mapped from `played`;
   Apple: a host time counts only when there is no sample time): its first frame played goes where
   its stamp says, which for a segment's first packet is the frame after the P it drops,
   `T + P / rate`. Every later packet of the segment follows the one before it, contiguous (`at:
   nil`).
6. **Late.** A packet whose scheduled time is less than the IO buffer + 2 ms away when it is decoded
   (the render thread has already rendered that far ahead) is decoded, for the decoder's state, and
   not played; the jitter cover rises to cover it at once, unless the lateness was not the link's
   (the engine still starting, before its first render; a packet the decoder was catching up on
   after a reset). The segment's next packet is placed by time (rule 5).
7. **Duplicates.** A packet whose (epoch, seq) is among the last 256 is dropped before it counts
   anywhere (the floor, the need, the late test): a move's two connections both carry the stream
   for a moment, and the new one's first packets, which its probe read, are handled at the
   hand-over. A move's hand-over resets nothing, neither this list nor the decoder nor the floor (a
   faster or slower path is rule 13's floor change), whichever move it is (from AWDL, to or from
   the cable, PR #39's move home), and a format for the epoch already playing, with the same
   cookie, is ignored.
8. **Missing.** A seq that skips (the host's `aud.drop`): the decoder resets, and the packet after
   the gap is a late join (rule 9).
9. **A clean start** only where the Mac's encoder started clean, a packet with the flag (a new
   segment or epoch): the decoder resets, its first P decoded frames are dropped (the codec's
   start), and the next 5 ms fade in. **Any other first packet on a reset decoder** (a device's
   first packet in the middle of a segment, the packet after a seq gap, the first after unmuting or
   any other reset) is decoded and dropped whole, and the next one fades in: decoded without its
   predecessors the first is noise (−5 dB against the signal), the second within −41 dB, the fourth
   exact (the critique's probe).
10. **The newest packet stays in hand** until the next arrives or its deadline (its scheduled time −
    the IO buffer − 2 ms) passes. Then it goes out, faded over its last 5 ms if nothing followed it.
    An underrun ends in a fade, never a click. The need's extra packet (rule 2) pays for the wait.
11. **Drift and small changes: single frames.** Once a second the model compares where the stream
    plays with where it is due: `error = (the stamp of the sample rendered at t) + floor + delay − t
    − the output latency`. It evens it out one frame at a time. Each packet scheduled may gain a
    frame (a copy at its quietest point, blended into its neighbours) when the sound runs ahead, or
    lose one when it runs behind. At most one a packet: about 2 ms a second, far more than two
    clocks drift (tens of ppm is 0.1 ms a second), and inaudible.
12. **Jumps: over 40 ms.** An error beyond 40 ms (a stall, a clock step, a route change, the engine
    restarting, the picture's lag moving fast) is closed at once, at the next packet boundary:
    packets dropped, or the next one placed later (silence), with 5 ms fades.
13. **A step.** When a second of packets all sit more than max(50 ms, 2 × the rtt median) above the
    floor, or a new floor comes 20 ms under the old one, the Mac's clock stepped or the path
    changed. The floor restarts from the last second's packets, and the difference is closed by a
    jump (rule 12's way), whatever its size.
14. **Idle.** No packet for 10 s: the engine stops (§7.4). The next packet starts it and is placed
    by time.

**Stats, each second:** the median of `delay − the picture's lag` over the packets played (how far
the sound trailed the picture, in ms; -1 for none), late packets, the need, the error, frames added
and dropped, jumps.

**Constants:**

| What | Value |
|---|---|
| Floor window | 10 s, in 1 s buckets |
| Need | the jitter cover (the window's largest excess; first 40 ms at home, 150 ms away) + 1 packet + the IO buffer + the output latency + 2 ms |
| Jitter cover bounds | home 20–150 ms; away 60–600 ms; the rest has none |
| The picture's lag | the median of 2 s of frames + 1.5 refreshes + 4 ms |
| The guard | the picture's lag + 1 frame of the stream's rate; no bound |
| Late | scheduled less than the IO buffer + 2 ms ahead when decoded |
| Frames added or dropped | at most 1 a packet |
| Jump | an error over 40 ms |
| Step | a second of packets above the floor by max(50 ms, 2 × rtt), or a floor 20 ms lower |
| Fades | 5 ms |
| Dedupe | the last 256 (epoch, seq) |
| Idle | 10 s without a packet |

#### 7.3 `AudioDecoder` (AudioToolbox)

- `AudioConverterNew` from the format's codec (AAC-ELD, F frames, 48 kHz, 2 channels), with
  `kAudioConverterDecompressionMagicCookie` set to the cookie, to 48 kHz stereo float,
  non-interleaved.
- `decode(_ packet: Data)` one packet at a time (the probe's loop), into pooled arrays; `reset()`
  (`AudioConverterReset`: the next packet decodes as on a fresh decoder, the critique's probe).
- An unknown codec or a cookie it refuses: `audio: cannot play <codec>` in the DEBUG console, and
  no sound this epoch. The Sound button and switch stay: the Mac says sound is on.

#### 7.4 `AudioOutput` (AVFAudio)

- **The graph:** `AVAudioPlayerNode` → `mainMixerNode` → output. The player's format is 48 kHz
  stereo float; the mixer converts to the route's rate.
- **Buffers:** a pool of `AVAudioPCMBuffer`s of F + 1 frames (a gained frame fits), 32 to start,
  grown on `sill.audio` when empty: the guard has no bound, and a picture a second late holds 100
  buffers in the player. Each comes back to the pool in its `scheduleBuffer` completion, which runs
  on an AVFAudio queue, not `sill.audio` (the pool takes a lock).
- **The session:** `.playback`, mode `.default`, options `[.mixWithOthers]` (Q4). It never stops the
  user's music or podcast, and it plays with the Ring/Silent switch on silent, as a video app does.
  `setPreferredSampleRate(48_000)`, `setPreferredIOBufferDuration(0.005)`, then `ioBufferDuration`
  and `outputLatency` read back once active (the preference is a request). Active only while the
  engine runs; when it stops, the engine first, then `setActive(false, options:
  .notifyOthersOnDeactivation)` (deactivating with the engine running fails as busy). Activation can
  fail, as during a phone call: no sound, one console line, and the interruption's end or the next
  `didBecomeActive` tries again.
- **When the engine runs:** the app in the foreground, the session carrying sound (a format has
  come), not muted, a packet within 10 s. It stops, after a 5 ms fade, on mute, on
  `didEnterBackground`, at the end of the session and after 10 s without a packet;
  `willEnterForeground` and the next packet start it again.
- **Interruptions** (`AVAudioSession.interruptionNotification`): `.began` (a call, Siri, an alarm):
  the engine has stopped, and the model resets. `.ended` with `.shouldResume`: start again; without
  it: at the next `didBecomeActive`.
- **Route changes.** `.oldDeviceUnavailable` (headphones out, AirPods taken off): mute, as a video
  app pauses, and announce **"Sound muted: headphones disconnected."** Any other reason (AirPods in,
  a speaker, AirPlay): read `outputLatency` and `ioBufferDuration` again and reset the model (one
  jump, rule 12). The need follows the route's latency, whatever it is (AirPlay's can be 2 s): the
  sound trails by that much more (Q7), and the console says so.
- **`mediaServicesWereResetNotification`:** rebuild the engine and the session.
  **`AVAudioEngineConfigurationChange`:** the engine has stopped and uninitialized itself, its
  nodes keep their old formats, and it must not be torn down in the handler (Apple: it can
  deadlock there). On `sill.audio`: connect the mixer to the output in the output's new format,
  start, read the latencies again and reset.
- **No `UIBackgroundModes`:** in the background the app is not heard.
- **DEBUG `-SillSoundSink manual`:** the engine in manual rendering mode
  (`enableManualRenderingMode(.offline, format:maximumFrameCount:)`): it never opens an output
  device and the session is never activated, so nothing can reach a speaker, the simulator's (the
  Mac's) included. A DEBUG timer on `sill.audio` pulls 5 ms at a time (`renderOffline`), the model
  takes a stand-in IO buffer of 5 ms and output latency of 10 ms, and the console reports each click
  of the test tone found in what was rendered, against its stamp. Every simulator gate runs with it
  (§11). **`-SillSoundVolume 0`:** the player node's volume 0 as well, a second guard.

#### 7.5 `StreamClient`

- **The hello** (`helloPayload`, StreamClient.swift:1116-1123) gains `audio: ["aac-eld"]`. It is the
  first message of every session connection (a tap's, a reconnect's, a wired dial's, every move's),
  inside TLS with PR #37.
- **Kind 29** in `handle` (:2632): `AudioMessage.parse`, stamped with its arrival, handed to
  `sill.audio`. A format for a new epoch gets a new decoder (one for the epoch already playing,
  with the same cookie, as a move's new connection sends, is ignored); packets get the model's
  decision, then decode, fades, a frame more or less, and the schedule. Muted or in the background,
  the model still takes each packet's arrival (its floor and need stay right, so unmuting is quick)
  and nothing is decoded.
- **Frames** (kind 1, :2639-2647): `frame(stamp:arrival:)` before `onFrame`, beside the frame age
  sample taken there.
- **Stats.** `closeWindow` (:2839-2861) adds the model's second to `LinkStats` (`audioBehindMs`,
  `audioLate`), and `ClientStatsReporter` (DiagnosticsHUD.swift) sends them.
- **Resets.** A new session connection after the old one ended (a connect, a reconnect) resets the
  model and the decoder, and `tearDown` (:2182) stops the engine, as it resets the menus. A move's
  hand-over (`finishMove`, :1429-1506; PR #39's move home too) does not: the stream is the same
  epoch, the dedupe drops what both connections carry, and a faster or slower path is a floor
  change (rule 13), one jump at most.
- **State.** `soundMuted` (published; `UserDefaults` `Sill.soundMuted`, default false), and
  `soundAvailable` (the host's `settings.displayed?.sendAudio == true`).

#### 7.6 The Sound button (every layout) and the Sound switch

Only while `soundAvailable`; at each layout's button size, one button's width taken from the
thumbnail strip, as the Menus button (#36) takes its own.

| Layout | Where |
|---|---|
| Landscape (`TopBar`, StreamScreen.swift:894-975): the iPad, the Duo's inner display and its outer one (710×500), a phone sideways | After Desktop, before Settings: Apps, the strip, Menus, Aa, Keyboard, Desktop, **Sound**, Settings |
| The iPad's portrait window bar (`windowBar`, PortraitStreamScreen.swift:264-302): the Duo's inner display, an iPad upright, an iPad window narrower than 600 pt (the compact halves) | After Desktop, before Settings: Apps, the strip, Menus, Aa, Desktop, **Sound**, Settings |
| A phone held upright, and the Duo's outer display upright (`phoneRow2`, PortraitStreamScreen.swift:398-413; `PhonePortraitLayout`) | Row 1 keeps the approved five (Apps, Aa, Keyboard, Desktop, Settings). **Sound** ends row 2, under Settings, as wide as row 1's buttons and as tall, centred in the strip's height, as Menus sits today; while the Mac's menus show too, Menus moves one place left, under Desktop. The strip ends 8 pt before the first of them |

- **Which bars hold it.** A bar shows it where it still holds a whole thumbnail beside it
  (`MacMenuButton.fits`, counting Sound as one more button), after Menus, which keeps the place #36
  gave it: where only one more fits, Menus stays and Sound goes to the panel. Both fit a landscape
  row of 666 pt or more (the roomy bar; 640 for the compact one, seven buttons), the regular halves
  at every width they are used at (600 pt and up), and the compact halves from a 532 pt window. An
  iPhone SE held sideways (639 pt of row) and iPad windows narrower than 532 pt upright (Split
  View, Slide Over) show Menus where it fits, and not Sound. On a phone upright both always fit:
  the strip keeps two whole thumbnails from 375 pt (the SE, the 15 Pro, the 18 Pro and Pro Max;
  three on the Duo's outer display) and one and most of the next at 320 pt (an SE with Display
  Zoom).
- **Why not in row 1.** Noah approved the phone's row 1 as five buttons; a sixth would make each as
  narrow as row 3's key caps. The row's end is where #36 put the Menus button for the same reason.
- **The switch.** In the Settings panel, the group for this device (the last one: Take the Tour's
  today, This iPad or This iPhone with #38's Three-Finger Gestures), first in it: a `Toggle`
  **"Sound from ‹Mac›"**, on unless muted, the same state as the button, with the footnote **"Mutes
  it on this ‹device› alone; ‹Mac› keeps sending it."** On every layout while `soundAvailable`: in
  a Slide Over it is the only Sound control, and for VoiceOver and Switch Control it sits with the
  Mac's Send Audio row.
- **Looks:** `speaker.wave.2.fill` over "Sound", or `speaker.slash.fill` over "Sound" when muted.
  Never the accent colour: it is not "open". On the phone the symbol sits in row 1's 24 pt box, and
  a long press at the accessibility text sizes shows it large, as the other buttons do.
- **VoiceOver:** label "Sound from ‹Mac›", value "On" or "Muted", the toggle trait.
- **The Aa ruler** fades it as it fades Keyboard, Desktop and Settings, in every bar; on the phone
  the ruler covers row 1 only, and row 2 is as it is.
- **The tour** (#35) needs no step and no words for it: it shows only while the Mac sends sound,
  which is off by default, and says what it does. It is not a tour target, and no step's lit area
  takes it in: the bar step lights the strip to Keyboard (landscape) or to Aa (the halves), both
  before Desktop, and on a phone the strip with Aa and Keyboard, whose right edge the strip no
  longer passes once Sound or Menus ends row 2. The cards follow the targets' own frames, so the
  Settings ring moves with the Settings button. `Tests/checks/tour` compiles PhonePortraitLayout
  and gains the row's end with Sound.

#### 7.7 The panel's Send Audio row (`HostSettingsPanel.swift`)

- **Where:** after the closing footnote "Applies to every device streaming from ‹Mac›. The stream
  restarts for a moment." (HostSettingsPanel.swift:219), before Direct Wireless: like Direct
  Wireless, it restarts nothing. Only when `shown.sendAudio` is not nil. PR #39's callouts and its
  header line for the away quality sit above the stream rows and do not move it; the group for this
  device (§7.6's Sound switch) stays last.
- **The row:** `Toggle` **"Send Audio"**,
  `binding(sendAudio) { HostSettingsChange(sendAudio: $0) }`, with `RowTitle`'s pending mark like
  the others.
- **Footer, off:** **"‹Mac› plays the sound of what streams on every connected device, and keeps
  playing it too."** **On:** **"Every device hears what streams; ‹Mac› keeps playing it too. Sound
  mutes it on this ‹device› alone."**
- **`audioNote`:** under the row, as a warning footnote.
- **The ledger:** `SettingsField.sendAudio`, `only`, `adding`, `fields`, and rule 9
  (HostSettingsLedger.swift:69, :99) for it: never sent to a host that did not report it.

#### 7.8 Harness, DEBUG console and HUD

- **Arguments** (the contract comment in ContentView.swift, and CLAUDE.md): `-SillSound on|muted`
  (the button and the switch in that state, no sound), `-SillSettingsCase sound|soundnote` (the row
  on; on with a note), `-SillSoundSink manual` and `-SillSoundVolume 0` (§7.4). With #36's
  `-SillMacMenu` the mock shows the Menus button too, so a photo has both at the end of the phone's
  row 2; `-SillIdiom pad` draws an iPad window's compact halves on an iPhone simulator. The mock
  answers `sendAudio` as it answers the others. No `-SillSound…` argument exists yet (checked
  2026-09-27).
- **DEBUG console lines:**
  - `audio: format aac-eld 48000 Hz 2 ch, 480 frames (priming 240), epoch 3, Safari`
  - `audio: engine on, Speaker, output 11 ms, IO 5 ms, delay 68 ms (need 68: jitter 40, packet 10,
    IO 5, output 11, margin 2; picture -4 + 1 frame 17)`
  - once a second while playing: `audio: 62 ms behind the picture; need 58 ms (jitter 30); late 0;
    error +3 ms; frames +1 -0; jumps 0`
  - `audio: jump +52 ms (clock step)` · `audio: interrupted` · `audio: resumed` ·
    `audio: route Speaker → AirPods (+187 ms)` · `audio: muted (headphones disconnected)` ·
    `audio: idle, engine off`
- **The HUD** (`-SillHUD 1`) gains ` · sound 62` while sound plays.

### 8. Cost

| Where | What | Estimate |
|---|---|---|
| The Mac's CPU | ScreenCaptureKit's sound stream with its 2×2, 1 fps picture | not measured here (P13); small |
| | AAC-ELD encode | 0.5–0.9 % of one core (the probe; an upper bound) |
| | Sending | 100 messages a second to each device, one `send` each |
| The device's CPU | Decode | 0.07 % of an M-series core (the probe); a few times that on an A15 |
| | AVAudioEngine | what playing any sound costs |
| The link | Sound | about 16 KB/s (128 kbps) |
| | Framing | 25 bytes a packet of Sill's own (the 14-byte header and 11), 2.5 KB/s. On a link with nothing else to carry, a still window's, each packet is also a TCP segment of its own: 52–72 bytes of TCP/IP headers, and a 22-byte TLS record at the remote door (at home too with PR #37, where Sill.app's home door is TLS). About 25 KB/s in all then, some 200 kbps |
| | Silence | about 3 KB/s of Sill's own, 8–12 KB/s with those headers |
| | Against the picture | 1–1.5 % of Balanced (15 Mbps), 4–5 % of Low (4 Mbps) |
| | The device's radio | 100 more small transmissions a second and about 50 acknowledgements back: it never dozes while sound flows, as the ticks already keep it while a source is live; a TLS client's ticks stop meanwhile (§4.6), so over TLS the sound's 100 records a second take the place of the ticks' 33 |
| Battery | The device's audio hardware while sound plays; the engine stops after 10 s of no packets | |

### 9. Timeouts and limits

| What | Value |
|---|---|
| The sound's stream, start and stop | 2 s each, then a failure (`audioNote`) |
| Following the source | after the picture's select; the same app keeps its stream |
| Packets | 480 or 512 frames (10 or 10.7 ms), one to a message (the wire allows 255) |
| A gap in the capture | any gap beyond the tolerance ends the segment; nothing is filled or flushed |
| Time stamp jitter accepted between chunks | a quarter of a chunk (2.5 ms for 480 frames, 5.3 ms for 1024) |
| Sound a device has not taken | 100 messages at home, 300 away, then packets are skipped (`aud.drop`) |
| Payloads | a format up to 4 KB, a packets message up to 16 KB |
| The device's playout | §7.2's constants |
| Settings changes | the existing 4 a second from each device |

### 10. Edge cases

| Case | Behaviour |
|---|---|
| Rotation, Aa, a rate or quality change, the encoder fallback | The picture restarts; the sound's stream is the same app's and goes on |
| Another window of the same app | No change to the sound |
| A window of another app | The sound's stream restarts with a new epoch: about 0.1–0.3 s of silence, then a fade in |
| The streamed window closes | The app's sound goes on (the filter is the app's, not the window's); the device asks for the Desktop 2 s later (today's rule) and the sound follows it, a new epoch |
| The app has no window on screen (minimized) | Still captured: the filter is the app's (P5) |
| A window on the virtual display | The same app filter on the main display (P5) |
| Two displays, the Desktop | Every app's sound, whatever the display (per app; P5) |
| The app goes quiet | Silent packets (8–12 KB/s with their headers) if ScreenCaptureKit keeps delivering (P2's minute line says); if it stops, the device plays out and fades, and the next chunk starts a new segment, placed by its stamp |
| The Mac's output device changes | ScreenCaptureKit's behaviour is not documented (P12). If the stream ends: one line and `audioNote`; the picture's next select, or Send Audio off and on, starts it again (§4.5) |
| The Mac locks its screen, sleeps its display or switches user | Not documented for sound (P12). If the stream ends: as above |
| The Mac's volume muted | Not documented whether capture comes before the volume (P11) |
| FaceTime or a phone call on the Mac | Not heard: daemon sound (P4) |
| A keyframe in front of the sound | The need covers it (rule 2); the first one of a session may make one packet late (dropped, faded) |
| The picture drops frames and waits for a keyframe (a slow link), or restarts | The sound goes on; while no frames come, the picture's lag keeps its last value (rule 3) |
| The link stalls 2 s, then bursts | Packets past their time are dropped; playback returns to the delay by a jump (rule 12) |
| The Mac's wall clock steps | Rule 13: one jump |
| A move (AWDL → network, to or from the cable, PR #39's move home) | Two connections for a moment: duplicates dropped (rule 7); nothing resets; a faster or slower path is one floor change, one jump at most (rule 13); coming home, the jitter cover takes home's bounds (rule 2) |
| A three-finger gesture over a window (PR #38) | The device picks the Desktop first, so the sound moves to the whole Mac's, a new epoch, as any Desktop pick does |
| A menu chosen on the device (#36) | Nothing: the app is activated and pressed through Accessibility, the source is the same |
| The link cannot carry the stream away (PR #39's report) | Frames are withheld, never the sound; the carried rate it reports counts the sound's bytes |
| A device joins while sound runs | The format, then the next packet; its first packet is decoded and dropped, the next fades in |
| Two devices | Both get it; each mutes alone |
| A device muted | The Mac keeps sending; the device decodes nothing; unmuting resets the decoder: the first packet is decoded and dropped, the next placed by time and faded in (rule 9) |
| Headphones pulled out of the device | Muted, and said (§7.4) |
| AirPods, AirPlay | The sound trails by the route's latency more (AirPods 150–250 ms, AirPlay up to 2 s); the console and the HUD say how much (Q7) |
| A call to the device | Interrupted, resumed after (§7.4) |
| The app goes to the background | The engine stops; back in front, the next packet starts it |
| Send Audio turned off (on the Mac or a device) | The stream stops; kind 16 says so; the button and the switch go (on a phone upright Menus moves back under Settings); the device plays out and idles |
| A device away | Its need starts at 150 ms and follows the link; frames drop first (§Decision) |
| A kind 29 of an unknown type or codec | Skipped |
| An older device, or an older host | §3.5 |

### 11. Test gates

**Hard rules for the implementing session** (Noah is at the Mac while it runs):
- **Never capture Noah's sound, and never make sound on his Mac.** No SCStream with
  `capturesAudio` against any real app: that is Noah's P-list. The host side is proven with the
  test tone and the encoder-free harness. The implementing session never starts `Sill.app`, never
  connects to it, never touches `/Applications/Sill.app` or the `me.saffer.sill.mac` domain, and
  runs no host that is not synthetic.
- **Synthetic hosts and the harness only,** from `.build/release`, every one with
  `SILL_TEST_LOOPBACK=1` (127.0.0.1 alone) and `SILL_TEST_SOFTWARE_ENCODER=1`, started from Python
  with `start_new_session=True`, killed by PID, none left running.
- **The Mac's video encoder.** The sound's gates run in the encoder-free harness (H5–H8), and S2
  and S3 connect to it too, never to `SillHost`, whose picture goes through an encoder. H2's parity
  runs use `SillHost --synthetic` on the software encoder, as the pointer's and the menus' did, and
  only while `Scripts/encoder-check/no-device.sh` finds no device connected to Sill.app (before,
  during, after). A run that needs the hardware encoder waits for the same.
- **Device playback makes no sound anywhere.** The simulator plays through the Mac's speakers, so
  every S gate runs with `-SillSoundSink manual` (the engine renders offline, no output device
  opened) and `-SillSoundVolume 0` besides; the playout model's checks run on a simulated clock.
  A simulator of its own named "Sill audio", never a shared one, deleted after; no `simctl io
  recordVideo`; no iOS Simulator control `attach`; screenshots only, with `xcrun simctl io <udid>
  screenshot`.
- **Nothing on Noah's devices:** no install, no `devicectl`; the P-list is his.
- **Builds:** at least 25 GB free before one; DerivedData under the session's scratch folder
  (`…/scratchpad/audio/`), never Xcode's default.
- **App gates** use the bare `SillMenuBar --synthetic`, with the same two hooks; `defaults delete
  SillMenuBar` afterwards.

**Headless (H): no permissions needed.**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record the base. The sound's number still free and 24–28 still held as §3.1 says, and which checks and mutants name 29: `git grep` over every ref, and every worktree's working tree and docs/, committed or not; the pbxproj block AA01–AA03 free the same way; which of PRs #37, #38 and #39 have landed; the codec probe, and the critique's reset and join probe, again on the build Mac | Recorded; ELD 480 and 512 give §Decision's F, P and end-to-end numbers within 1 ms, the same P after a reset, and a late join's first packet unusable, its fourth exact |
| H1 | **Builds.** `swift build -c release`; iOS Debug and Release for the simulator and Debug for a generic device | Only the known warnings |
| H2 | **The CLI byte for byte.** Base and new `SillHost --synthetic`, both with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1`: idle 35 s; with `sillclient.py PORT 8 desktop`; with `sillclient.py … --hello=0.6 --audio` (a hello that lists "aac-eld"); all again with `--direct-wireless`; digits masked, sorted | Identical; no `Audio` line and no `aud.` key; no kind 29 in the client's `kinds=` |
| H3 | **Pure checks, each with its mutants caught.** `audio-packetizer` (Sources/SillHost/AudioPacketizer.swift), at least 30 cases: F from the first chunk (480, 1024, 441 and 960 frames), stamps against the anchors (±1 µs), the continuity tolerance at a quarter chunk ± 0.1 ms, a whole chunk missing, a chunk early, a format change, a segment ended with nothing flushed, `AudioSourceRule`'s table (a running stream kept, an ended one restarted after 10 s and not before); a gap emits nothing, and each block goes out with the chunk that completes it; at least 10 mutants (`>` for `≥` at the tolerance, the priming's sign, a gap that starts no segment, zeros filled into a gap, the tail flushed, an ended stream never restarted, a running one restarted). `audio-playout` (iOSClient/AudioPlayout.swift), at least 40 scenarios on a simulated clock (a steady home link; a 40 ms burst every 4 s; ±100 ppm for an hour; host clock steps of ±1 s; a 2 s stall, then a burst; duplicates; a seq gap; a join mid-segment; a still window; a link away at 80 ± 50 ms; a picture 1 s late; output latencies of 10 ms, 180 ms (AirPods) and 2 s (AirPlay) at home; IO buffers of 5 and 23 ms; a move's hand-over, both connections carrying the same packets and the new one 30 ms faster, its first packets handled late at the hand-over; a move home, away's bounds to home's; mute and unmute) and 5,000 random runs, with the invariants: nothing plays before it arrives; no two packets overlap; the sound never leads the picture as the model sees it; nothing is scheduled less than the IO buffer + 2 ms before its render; with any output latency up to 2 s and any IO buffer, a steady link loses no packet as late after its first 2 s; a packet decoded on a reset decoder in the middle of a segment is never played; a hand-over plays no packet twice and resets nothing, and a duplicate never counts toward the floor or the need; after a disturbance under 40 ms the error falls at 1.9 ms a second or better until under 5 ms; at most one frame added or dropped a packet; at least 18 mutants (max for min in the floor, no dedupe, no guard, the late test's sign, the jump at 400 ms, no step test, no fades, the need not rising at once, and the critique's: the output latency left out of the need, the late test without the IO buffer, a segment's first packet placed without its P, the packet after a seq gap played, a hand-over resetting the dedupe; and the refresh's: a duplicate counted before it is dropped). Wire cases: `compatibility` (AudioFormat and the new fields round trip; `{}` decodes; unknown keys ignored; the old `Hello`, `StreamSettings` and `ClientStats` decode the new JSON) and `protocol` (type 2 serialized and parsed; every malformed payload gives nil and never traps; 1,000 random byte strings). The kind checks (`protocol`, `menus`, `pointer-control`, and `compatibility` once #38 is in): 29 is `audio` and 30 reads as unknown; the mutants that renumbered a kind onto 29 (and `pointer-control`'s onto 30) do so onto numbers from 250 to 254, each still caught (§3.1). `phone-portrait`: row 2 with Sound at its end, with and without Menus, at every width from 300 to 599 pt (Sound under Settings; Menus under Desktop beside it, under Settings without it; the strip ending 8 pt before the first; a whole thumbnail left at 320 pt, two from 375), with mutants (Sound under Desktop, the strip not shortened, Menus not moved aside); `tour`, which compiles the layout: its lit areas never take in Sound | All pass; every mutant caught |
| H4 | **`audio-codec`** (a new check): Sources/SillHost/AudioEncoder.swift and iOSClient/AudioDecoder.swift in memory; the test tone through the encoder at F 480 and 512, each packet decoded at once | F and P as §3.2; with the first P frames dropped, each click lands at its stamp's sample ±2 frames; 5 s of the busy signal at 120–140 kbps; nothing but AudioToolbox linked |
| H5 | **The harness at home** (`Scripts/audio/`, step 4: the real StreamServer and sound files with the test tone and fake frames; no VideoToolbox, ScreenCaptureKit or CoreMedia). 60 s of Balanced-sized fake frames at 60 fps; `Scripts/audiocheck.swift` on the home door (a hello with "aac-eld"; it decodes and finds the clicks); the same run with Send Audio off | 100 ± 1 packets a second (93.75 with `SILL_TEST_AUDIO_CHUNK=1024`); no gap in seq; 60 clicks at whole seconds of their stamps ±1 ms; `net.dropped`, `net.sent` and the frames' age the same with and without sound, within run-to-run noise |
| H6 | **The harness away:** Scripts/pacing's `bottleneck.py` (on main since #34) at 8 and 4 Mbps with 1.5 MB keyframes, and a 12 s dip to 0.5 Mbps; the remote door's slow link through `Scripts/sillrelay.py` at 2 Mbit/s and +150 ms; and the pacing harness's own gate cases (kf25m32, real24, restartkf, stillend) with sound, against the same without | `aud.drop` 0 at 8 and 4 Mbps while `net.dropped` > 0 in the keyframe case; every packet's age at most the frames' age + 20 ms; in the dip, sound and frames arrive late together, and 2 s after it ends the packets' age is back; the pacing cases' fps and drops within their run-to-run noise with sound on (the keyframe asked for while at most 16 KB waits is not held back) |
| H7 | **Send Audio over the wire.** `sillclient.py --audio --set=sendAudio=1@3 --set=sendAudio=0@8 --expect=sendAudio=0` against a synthetic host started without `--audio` | The answers carry it; the first packet within 300 ms of the first answer, the last within 100 ms of the second; "Settings from sillclient: send audio off → on" and "… on → off"; no "Streaming …" line (the picture never restarted) |
| H8 | **Epochs and segments** in the harness: the tone paused for 50 ms, then for 500 ms (`SILL_TEST_AUDIO_PAUSE=0.05@3,0.5@6`), and a source change | Each pause: nothing sent for the gap, a segment start at the resumed chunk placed at its stamp ±1 ms, no packet sent more than 40 ms after its stamp, and audiocheck's model keeps its jitter cover; the source change: a new epoch, its format before its first packet on every client |
| H9 | **Compatibility.** The base's `sillclient.py` against an `--audio` host; the base's StreamProtocol (swiftc) against a kind 29 header and the new kind 16; the new device decoder against the base host's messages | No kind 29 to the old client; `.unknown`; the old kind 16 decode ignores the keys; nothing new decoded |
| H10 | **Previews.** The bare app's `-SillRenderPreviews` before and after | Only the Streaming and Permissions panes, menu.txt's Send Audio and the new `sound` card sample differ |
| H11 | **Hard rules** (grep) | No `captureMicrophone`, `AudioHardwareCreateProcessTap`, `updateConfiguration` or `assumeIsolated` in Sources/SillHost; no `UIBackgroundModes` in the iOS Info.plist; `HostConfig.standard` has `sendAudio: false`; the sound's send path never calls the counting `send(_:to:isFrame:isKeyframe:)` and never touches `keyframesInFlight` or `backlogFloor`; no AVFoundation or CoreMedia import in AudioEncoder, AudioPacketizer, AudioPipeline or SyntheticAudio; no render block in iOSClient; `-SillSoundSink` and `-SillSoundVolume` only under `#if DEBUG` |
| H12 | **Cost.** The harness host's CPU (`ps`, 60 s) with and without sound | At most 1.5 percentage points more |

**The harness** (`Scripts/audio/`, step 4) is built the way Scripts/pacing/build.sh builds its host:
a throwaway package under `.build/audio` with StreamServer.swift and its neighbours (pacing's list:
ClientLink, DeviceGate, HostLog, InterfaceSnapshot, OriginPolicy, PointerControl, PointerWatch,
RefusalSummary, Stats; with #37 the Door's files too), the sound's host files (AudioPipeline,
AudioPacketizer, AudioEncoder, SyntheticAudio) and a `main.swift` that feeds fake frames and runs
the test tone, both doors, on 127.0.0.1 alone. Where the pacing harness's fake encoder and cases
serve, it reuses them rather than copying. Like the pacing harness, it refuses a binary that links
VideoToolbox, ScreenCaptureKit, CoreMedia or AVFoundation. `Scripts/audiocheck.swift`
is its device: StreamProtocol, iOSClient/AudioDecoder.swift and iOSClient/AudioPlayout.swift (the
model without a player: its floor, need and late decisions on real arrivals), a hello with
"aac-eld", every kind 29 decoded, the clicks found, one line a second and a summary at the end.

**Simulator (S):**

| # | Check |
|---|---|
| S1 | **Photos**, on a private simulator ("Sill audio"). `-SillSound on` and `muted`, with and without `-SillMacMenu`: at 1000x710, 710x1000 and 710x500; the phone's arrangement at 440x956, 402x874, 375x667 and 320x548 and at the Duo's 500x710; the compact halves (`-SillIdiom pad`) at 500x710 and a 320x700 Slide Over (no button: the panel's switch); at the default size and xxLarge text. `-SillSettingsCase sound` and `soundnote` at the same sizes, the panel scrolled to its end (`-SillSettingsEnd 1`) for the switch. The button in every bar that holds it, the strip one button narrower, Menus beside it on the phone, the row after the closing footnote, the switch first in the device's group; against the base build, every other photo pixel for pixel. Send Noah the sheet |
| S2 | **Live.** `-SillLive 1 -SillConnect 127.0.0.1:P` against the harness's home door, with `-SillSoundSink manual -SillSoundVolume 0`: the console's format and engine lines; within 3 s "late 0" and a steady "behind the picture"; each rendered click within 2 ms of its stamp plus the delay. A headless tap on Sound: "engine off"; again: on, one jump. The panel's switch the same. `sillclient.py --set=sendAudio=0@…` as a second client: the button and the switch go, and "idle, engine off" 10 s later |
| S3 | **A move.** `-SillMoveTest 1` with sound, against the harness, with `-SillSoundSink manual -SillSoundVolume 0`: no double packets (the console's dedupe count), nothing reset, at most one jump at the hand-over |

**Noah's devices (P), handed over at the end:** the iPad mini, the Mac, headphones, an iPhone for
P6 and P14.

| # | Check |
|---|---|
| P1 | **On.** Send Audio from the Mac's menu; Music playing, its window streamed: the iPad plays it, and so does the Mac (the menu's subtitle says so). After a relaunch `defaults read me.saffer.sill.mac sendAudio` is 1 |
| P2 | **The first buffer.** Send the log's "first buffer … frames … ms after its time stamp" line, the encoder's line (480 or 512) and the "first minute" line (pause Music for 20 s in that minute: do silent buffers keep coming?), and say whether the 2×2 picture was taken |
| P3 | **Per app.** Two Safari windows, a video playing in one; stream the other: the video's sound plays. The Desktop: every app's sound |
| P4 | **Helpers and daemons.** A YouTube video in Safari and in Chrome, Spotify, a FaceTime call (expected silent), Mail's new-mail sound: which are heard. An app whose sound comes from a helper process and is not heard (a browser's audio service, an Electron app) gets a build that adds its helpers to the filter (the running applications whose bundle identifier begins with the app's and a dot), and P4 again |
| P5 | **Off screen.** Music minimized while the Desktop streams; Music's window on the virtual display; a second display. A window on the virtual display streaming in silence moves the app's filter to `desktopIndependentWindow` (§Decision), and P5 again |
| P6 | **Sync.** A clapper or lip-sync test video on the Mac, streamed; film the iPad at 240 fps with the iPhone and count the frames between the flash and the click. The speaker, then AirPods; the console's "behind the picture" at the same time. The film minus the console is what the model cannot see (the picture's time on the Mac, the display's own): once on the hardware encoder and, if convenient, once on the software one (the CLI with `SILL_TEST_ENCODER_HANG=1` and `--audio` falls back at its first hang for about 30 s). Sound ever ahead of the flash: §14's V |
| P7 | **Restarts keep the sound.** With music: rotate, cycle Aa, switch 60 and 120 fps, change Quality, turn the virtual display on and off: no gap. Another Music window: no gap. Another app's window: a short gap and a fade in |
| P8 | **Mute.** The bar's Sound: muted at once, the Mac still playing; relaunch: still muted; unmute: sound within about 0.1 s. VoiceOver reads "Sound from ‹Mac›, On". The iPhone upright: Sound at the end of the thumbnails' row, Menus beside it. The iPad in Slide Over: no button, the Settings panel's switch mutes |
| P9 | **Interruptions and routes.** A FaceTime call to the iPad, Siri, AirPods in and out (out mutes and says so), wired headphones, AirPlay to a speaker (the console's output latency, and the sound trailing by it), and a stream started during a call (no sound and one line; sound once the call ends) |
| P10 | **Away.** Tailscale over the iPhone's hotspot at Low: the sound goes on while `net.dropped` counts; the `client …` line's "sound … behind" |
| P11 | **The Mac muted** (its volume): does the iPad still hear it? |
| P12 | **The Mac's output changed** mid-stream (headphones into the Mac, AirPods on the Mac): the sound goes on, or one "Audio capture ended" line, and the next pick, or Send Audio off and on, brings it back. The same for the Mac's lock screen and a fast user switch |
| P13 | **An hour** of music: no drift (the console's error within ±5 ms and no jump after the first minute); Sill.app's CPU in Activity Monitor with sound on and off |
| P14 | **Two devices** (the iPad and the iPhone): both play; muting one leaves the other |
| P15 | **Mixed builds.** This iPad with Sill for Mac 0.3.1, the public release: no row, no button, no sound. An iPad build from before this step that reaches this Sill.app (main's Debug; once #37 is in, a build from before pairing at home, TestFlight's 0.5 among them, reaches its home door not at all) with Send Audio on: nothing changes for it |
| P16 | **The device's silent mode and volume buttons:** it plays on silent, as a video app does (Q4); the volume buttons set Sill's volume |

### 12. Implementation order and sizing (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

| Step | Commit | Files | Gates | Size |
|---|---|---|---|---|
| 0 | Preflight (no commit) | — | H0 | 1 h |
| 1 | "Protocol: kind 29, the Mac's sound" | StreamMessage.swift, Audio.swift (new), Compatibility.swift, HostSettings.swift, Viewport.swift; the `compatibility` and `protocol` cases; the kind checks and mutants that name 29 (§3.1), and Tests/checks/README.md's paragraph on them | H1, H3 (wire), H9 (decode) | ½ day |
| 2 | "Host: the sound's blocks and stamps" | AudioPacketizer.swift (new) with `AudioSourceRule`; `Tests/checks/audio-packetizer` | H3 | ½ day |
| 3 | "Host and device: the AAC-ELD encoder and decoder" | AudioEncoder.swift (new); iOSClient/AudioDecoder.swift (new, not yet in the Xcode project); `Tests/checks/audio-codec` | H4 | ½ day |
| 4 | "Host: Send Audio, the sound's stream and its send path" | AudioCapture, SyntheticAudio, AudioPipeline (new); StreamServer, StreamCoordinator, HostConfig, DeviceSettings, HostStatus; the CLI's `--audio`; `sillclient.py --audio` and `sendAudio`; `Scripts/audio/` and `Scripts/audiocheck.swift` | H1, H2, H5–H9, H11, H12 | 2 days |
| 5 | "Sill.app: Send Audio" | HostSettings, DebugHooks, StatusItemController, SettingsPanes, StatusText, the previews | H1, H10 | ½ day |
| 6 | "iOS: the playout model" | AudioPlayout.swift (new); `Tests/checks/audio-playout` | H3 | 1½ days |
| 7 | "iOS: the Mac's sound" | AudioOutput.swift (new) and the three pbxproj pairs (AA01–AA03); StreamClient, the bars (TopBar, the window bar, the phone's row 2, `MacMenuButton.fits`), PhonePortraitLayout with `phone-portrait` and `tour`, the panel (the Send Audio row, the Sound switch), the ledger, MockCatalog, ContentView, DiagnosticsHUD | H1, H3 (the layout), S1–S3 | 2 days |
| 8 | "docs: the Mac's sound on the device" | This plan's Results; CLAUDE.md (the current step, Layout, Build and run, Untested for Noah: P1–P16, and the decisions list: audio no longer out of scope); docs/DEVELOPMENT.md (Send Audio); Tests/checks/README.md's table; `ci.yml`'s mutants matrix; BRIEF.md (audio in scope from 2026-09-27, Noah's word). For the release that carries sound, and said so in the commit: README.md's Good to know ("does not play sound from your Mac"), docs/app-store-metadata.md's description ("Sill doesn't play sound from your Mac.") and site/privacy.html (what the Mac sends, and what Screen Recording is for), in public copy's words for Apple's names ("sound from your Mac", never "your Mac's sound": app-store-metadata.md's trademark note) | — | ¼ day |
| 9 | Review and hand-over | Three lenses: the sync model and its constants; the host's threads and the picture's isolation (nothing of the sound on the picture's queues or counters); the device's session, lifecycle and UI. A "Review fixes" commit if needed, then H5–H8 and S2 again; hand P1–P16 to Noah. **Stop there** | — | ½–1 day |

- **In all:** about 8–9 days of focused work, most of it the two pure models and their checks.
  Noah's P-list: about 2 hours.
- **Rough size:** the host about 900 lines (Audio.swift 150, the packetizer 200, the encoder 180,
  the capture 150, the tone 80, the pipeline 250, about 150 in existing files); Sill.app about 80;
  the device about 1,000 (the playout 400, the decoder 120, the output 350, about 150 in existing
  files); checks and harness about 1,500.
- **Merges, never rebases.** The pointer (#31), the menus (#36) and remote pacing (#34) are on the
  base. The branch takes main again whenever one of the open ones lands, and before its pull
  request; where they meet this plan:
  - **#37, pairing at home.** StreamServer's doors behind one `Door`, every hello read inside TLS
    and handed to `took` through `serve` (§4.6: the codecs are taken there whichever door);
    `ClientRoute.home` gains its peer, and `Client` its `encrypted` and `onCable`, which the tick
    reads (§Decision, Ticks). The sound's pacing stays keyed on `route.isRemote`, and each packet
    costs a TLS record at home too (§8). The device's `DeviceTLS` carries every session: nothing of
    the sound's changes. ContentView's harness, HostSettingsPanel and StreamScreen merge by text.
  - **#38, gestures.** Kind 28 and the checks it moves (§3.1); StreamCoordinator's gesture handler,
    its rate and its held chords beside §4.7's calls; the panel's This iPad group, where §7.6's
    switch goes first; InputOverlay and TrackpadView, which the sound does not touch.
  - **#39, away from home.** Kind 16's per-connection `away` and `link` beside `sendAudio` and
    `audioNote`; `HostConfig`'s away pair and `applyingAway` (§4.1); `LinkJudge` in the sweep (§4.6);
    the move home, a hand-over for the playout (§7.2, rules 2 and 7); the panel's callouts above the
    rows, the menu's Quality subtitle and the card's device rows beside §6's.

### 13. Hard rules (for every step)

- **The picture first.** Nothing of the sound runs on `sill.capture` or `sill.encode`. The sound
  never counts in `inflight`, `inflightFrames` or the drain eviction, and pacing never drops it. A
  failure of the sound never stops, restarts or delays the picture. `follow` runs once the picture
  has started (`active`'s didSet).
- **Never reconfigure a running SCStream.** The sound's stream is started and stopped whole;
  `showsCursor` stays false everywhere.
- **No new permission.** Never `captureMicrophone`, never a Core Audio tap, no
  `NSAudioCaptureUsageDescription`; no microphone and no `UIBackgroundModes` on the device.
- **Never `MainActor.assumeIsolated`** in core code. ScreenCaptureKit calls bounded (2 s).
- **The CLI's stdout byte for byte** without `--audio`, idle and streaming, whatever the devices'
  hellos.
- **Kinds 0–28 untouched.** 29 is the sound's (or the next free, H0). Additive only: kind 29 goes
  only to a device whose hello lists the codec; every new field is optional.
- **No Swift on a real-time audio thread:** the player node schedules; Sill writes no render block.
- **Tests never capture Noah's sound and never make a sound** (§11's hard rules): the test tone,
  the harness, the engine's manual rendering on the simulator; never `/Applications/Sill.app`,
  `me.saffer.sill.mac` or Noah's devices; test hosts on loopback and the software encoder, the
  hardware encoder only while no-device.sh finds no device.
- **Row 1 of the phone's arrangement stays as Noah approved it** (five buttons), and the Menus
  button never gives way to Sound: a bar with room for one of them shows Menus (§7.6).
- **Apple frameworks only** (AudioToolbox, AVFAudio, ScreenCaptureKit). New iOS files need their
  four pbxproj entries by hand. Swift 5 language mode.

### 14. What comes later

- **A quiet Mac.** A Core Audio process tap (macOS 14.2 and later) with `CATapMutedWhenTapped` in
  place of ScreenCaptureKit's sound, so the Mac goes silent while a device plays; it needs its own
  permission ("System Audio Recording Only"). Then Send Audio could be on by default (Q1, Q6).
- **A path of its own for the sound.** A send queue with priorities (Sill hands the connection only
  a bounded amount) lets sound pass frames not yet handed over, never a keyframe already on the
  wire; a second connection for the sound (or datagrams) passes that too, at home and away, and can
  take the voice service class. It needs its own admission (pairing, the gate, a hello), so it is a
  step of its own.
- **The picture's own delay, V,** if P6 ever finds the sound ahead: HEVCEncoder passes each output's
  capture time (nil for a re-encode of a still frame, which carries its last capture's), the
  coordinator keeps the smallest (encode-out − capture) of the last second, a kind 29 type 3 carries
  it once a second (older devices skip the type), and the device adds it to the picture's lag.
- **Opus** (Q2) and a lower bitrate away (Q3).
- **The picture delayed for Bluetooth** (Q7), if anyone asks.

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

Refreshed 2026-09-27: the implementation takes every default below. Q13 is answered (now), Q10 is
rewritten for the layouts main has since #30 and #36, and Q12 says where the kinds stand.

1. **Send Audio's default.** Default: **off** in the first release with sound, on the Mac and in the
   CLI; flip it after P1–P16, as with the virtual display. The Mac keeps playing its own sound, so
   on by default doubles every sound for a device beside the Mac.
2. **The codec.** Default: **AAC-ELD** (10 ms, 128 kbps). Opus at 10 ms is as fast and royalty-free,
   costs about twice the encode CPU and five times the decode, and was not verified on macOS 14 or
   iOS 17 here (Apple documents the constant from macOS 10.13 and iOS 11; its own forum example
   encodes 20 ms packets). A later switch is one `codec` string.
3. **The bitrate.** Default: **128 kbps** everywhere (4–5 % of Low with the headers; with PR #39 an
   away session starts at Low · Standard). The alternative: 96 kbps away from home.
4. **The session.** Default: **`.playback` with `.mixWithOthers`**: it never stops the iPad's own
   music, and plays on silent like a video app. Alternatives: `.playback` alone (Sill's sound
   pauses other audio, like a video app); `.ambient` (obeys the silent switch, like a game).
5. **Mute.** Default: **per device, local, remembered.** The alternative: per Mac.
6. **The Mac keeps playing.** Default: **say so** (the menu's subtitle, the footers), and a device
   beside the Mac is muted by its user. The alternative is §14's tap, with a permission of its own.
7. **Bluetooth headphones and AirPlay.** Default: **the sound trails by the route's latency**
   (AirPods 150–250 ms; AirPlay up to 2 s, Apple says), and the console and the HUD say how much.
   The alternative delays the picture to match, against "latency beats quality"; for AirPlay,
   another is to mute past 0.5 s and say why.
8. **Devices turning it on.** Default: **yes**, like the other stream settings: saved on the Mac,
   from home or away. The alternative: only the Mac's own menu and Settings.
9. **"· sound" on the Mac's card.** Default: **shown** in the source row while a device gets sound.
   The alternative: the menu's check mark only.
10. **Where the Sound button goes.** Default (§7.6): **after Desktop in every bar that holds it
    and a whole thumbnail**, the Menus button kept first where only one fits; **on a phone upright,
    and on the Duo's outer display upright, at the end of the thumbnails' row**, under Settings,
    with Menus moving under Desktop while both show, row 1's approved five untouched; and **a Sound
    switch first in the panel's group for this device on every layout**, the only Sound control in
    a Slide Over. Alternatives: a sixth button in the phone's row 1 (each as narrow as a key cap);
    Sound kept before Menus where only one fits (an iPad has the Mac's menus in its own menu bar on
    iPadOS 26, a phone does not); the switch only where no bar holds the button.
11. **Headphones unplugged.** Default: **mute and say so**, iOS's pause for a live feed. The
    alternative: keep playing on the speaker.
12. **The kind number.** Default: **29**. 24, 25 and 27 are the Mac's menus and 26 its pointer, on
    main; 28 is the trackpad gesture of PR #38; no branch holds 29 (2026-09-27). If another branch
    takes it first, the next free.
13. **When.** Answered by Noah on 2026-09-27: **now** ("Audio: the plan is done and parked as a v2
    feature by your earlier decision", first in what he wants worked on). The plan's default was
    after v1 ships; BRIEF.md and CLAUDE.md say so until step 8 records the decision.
14. **One stream or two.** Default: **a stream of its own for the sound**, so rotation, Aa and
    settings never cut it. The alternative, `capturesAudio` on the picture's stream, is less code
    and drops the sound at every restart.
15. **Idle.** Default: **the device's engine stops after 10 s without a packet.** The alternative
    keeps it running while connected: no ~50 ms start after a long silence, more battery. If P2
    finds ScreenCaptureKit sends silent buffers while the app is quiet, the Mac never stops sending
    and the engine never idles while Send Audio is on; then the other alternative is idling after
    10 s of silent packets, at the cost of the next sound's first ~0.1 s while the engine starts.

---

## Critique (2026-09-26)

Checked against Apple's documentation, the SDK headers, the code (main at 150f781, remote-pacing at
b4b315e) and every other branch and worktree, with the in-memory probe named at the top. Fixed in
place:

1. **Kind 29, not 28.** trackpad-gestures-plan.md (branch `trackpad-gestures`, 8dd3539, a local
   branch) reserves 28 for its Tier 2 gestures (§4.2: "reserve it in the comment only"); the survey
   missed it. 29 is free on every ref and worktree. The menu bar's 24, 25 and 27 exist only
   uncommitted in its worktree, so H0 now reads working trees too.
2. **The pbxproj IDs.** A021–A023 sat next to remote-pacing's A020 and to the pair home-pairing
   must take when it lands (its StreamClient+Home.swift has A01E, GoodbyePolicy's on main): a block
   apart, A401–A403.
3. **The need left out the output latency** (§7.2, rules 2 and 4). A packet was due at the speaker
   at `T + floor + delay` and scheduled `outputLatency` earlier, but the need covered only jitter,
   a packet and the IO buffer. On AirPods (150–250 ms) every packet was late, and the 150 ms cap at
   home kept it so: no sound at all over Bluetooth at home, and late drops on the speaker until
   rule 6 had grown the need. The need now adds the output latency (the session's `outputLatency`
   and the player's `outputPresentationLatency`, which Apple defines as the render latency
   downstream of a node), unbounded; the bounds are the jitter cover's alone.
4. **"Late" ignored the render's reach** (rules 6 and 10). The render thread renders an IO buffer
   ahead, so "less than 2 ms away" let packets through that were already too late whenever the IO
   buffer passed 2 ms, and the deadline for the packet in hand had the same gap. Both now count the
   IO buffer, read back after activation: Apple documents the preferred duration as a request, with
   a minimum of about 5 ms (256 frames) and a typical maximum of 93 ms. Lateness that is not the
   link's (the engine starting, a connection's catalog burst) no longer raises the jitter cover.
5. **A packet on a reset decoder was played** (rules 8 and 9). After a seq gap the packet was faded
   in, and after any reset the first P frames were dropped as if the Mac's encoder had restarted.
   Decoded without its predecessors, such a packet is noise (the probe: −5 to −6 dB against the
   signal; the second −41 dB, the fourth exact). Only the Mac's segment flag starts clean now; any
   other first packet is decoded and dropped. A segment's first packet is placed by its first kept
   frame, `T + P / rate`, not by T.
6. **Gaps filled with zeros reached the device late** (§4.3). Zeros and a flushed tail were made
   when the late chunk arrived, stamped a gap ago, so they arrived late by the gap and raised the
   need for 10 s as if the link had jittered. A gap now ends the segment where it is, nothing made
   for it; the probe checked that `AudioConverterReset` restarts the encoder with the same priming
   (240, 256) and drops what it held (at most F − 1 + P frames). The tolerance is a quarter chunk:
   a lost buffer is a whole one, and ScreenCaptureKit's stamp jitter is unknown (P2's minute line).
7. **A move's hand-over reset the model and the decoder.** That cost a dropped packet a move and,
   if the dedupe went with it, let the slower connection's copies back in, late, raising the need.
   Now a hand-over resets nothing; a faster or slower path is rule 13's floor change.
8. **Edge cases.** A closing window ends nothing (the filter is the app's). A stream that ended by
   itself now comes back at the picture's next select (at most every 10 s), not only when Send
   Audio is toggled; the Mac's lock screen and user switch are listed. AirPlay (Apple: up to 2 s)
   joins Bluetooth. The engine's configuration change follows Apple's note (stopped, uninitialized,
   old formats kept; never torn down in the handler). The buffer pool grows (the guard has no
   bound; 64 buffers held 0.64 s). Session activation can fail during a call.
9. **The latency budget.** The probe's "end to end" includes the capture chunk (26.7 ms is 1024 +
   256 frames), so the table counted the capture buffer twice; the device row counted the IO buffer
   twice; the keyframe's cover, 15–40 ms, was below the 50–100 ms spikes this project measured from
   1–2 MB keyframes. Recomputed: the sound 60–155 ms, 20–115 ms behind the picture at home. The
   codec note's "10–20 ms faster" is 9–10 ms (15.0 against 25.3, 26.7 against 35.7).
10. **"Never leads" was more than the design gives.** A frame's stamp is its encode-out time
    (StreamCoordinator.swift:1025), the sound's its capture time, so the guard cannot see the
    picture's time on the Mac: the sound can lead the glass by that less a frame (up to ~30 ms on
    the software encoder), under BT.1359's 45 ms, and at home the need decides anyway. Said so; P6
    measures it; §14 has the fix.
11. **Remote numbers.** Behind a keyframe the link is still taking, remote pacing's 512 KB hold
    comes on top of the keyframe itself: 1–4 s at 4 Mbps, not 0.5–1 s.
12. **The cost of 100 small messages.** On a still link each packet is its own TCP segment (and a
    TLS record away): about 25 KB/s, and silence 8–12 KB/s, not 3.
13. **Tests.** Every S gate runs silent (`-SillSoundVolume 0`) and against the harness, never
    `SillHost` and its encoder; the tone is stamped by its sample count and clicks on whole seconds
    of the stamps' clock; `SILL_TEST_AUDIO_PAUSE` replaces an undefined signal; audiocheck runs the
    playout model on real arrivals; H3 gains the invariants and five mutants for 3–7; H8 checks that
    a gap sends nothing late; P2, P4, P5, P6, P9 and P12 gain what the docs leave open.
14. **Public text.** The README, the App Store description and the privacy policy each say today
    that Sill plays no sound, or list what the Mac sends without it: step 8 changes them with the
    release that carries sound.
15. **Base.** main is 150f781 (PR #20 moved the keyframe interval to HEVCEncoder.swift:168);
    remote-pacing is b4b315e, with its harness, and MessageReader still uncommitted.

**Confirmed as written.** ScreenCaptureKit filters sound per application: WWDC22 10155 says a
single-window filter captures all of the owning app's sound, even from windows not in the video,
and 10156 that audio is filtered only per application. `capturesAudio`, `sampleRate`, `channelCount` and
`excludesCurrentProcessAudio` date from macOS 13; 48 kHz stereo is the default, and an audio buffer
wraps an audio buffer list in that format (SCStream.h). The sound needs no permission beyond Screen
Recording; the process tap and `CATapMutedWhenTapped` need macOS 14.2 and their own.
AVAudioSourceNode's real-time block is unavailable from Swift (AVAudioSourceNode.h:48).
AVAudioPlayerNode reads `when` as a sample time on the player's timeline, a host time only without
one, and `nil` as right after the last buffer. `.mixWithOthers` with `.playback` interrupts no
other audio. AAC-ELD is documented from macOS 10.7 and iOS 4. In the code: the header's wall-clock
stamp (StreamMessage.swift:53), the pong's echoed and unread stamp, the fence's nonce compare
(SessionLink.swift:119), the tick's uncounted send, `inflight` counting every message but ticks
(pongs included), `noDelay` and the interactive-video service class, remote pacing's four
constants, and the hello as each session connection's first message.

**Sources** (developer.apple.com): SCStreamConfiguration `capturesAudio`, `sampleRate`,
`channelCount`, `excludesCurrentProcessAudio`; SCContentFilter and its initializers; "Capturing
screen content in macOS"; WWDC22 sessions 10155 and 10156; AVAudioSession
`setPreferredIOBufferDuration(_:)`, `ioBufferDuration`, `outputLatency`, `mixWithOthers`,
`InterruptionReason`; "Handling audio interruptions"; AVAudioPlayerNode ("Scheduling Playback
Time") and `scheduleBuffer(_:at:options:completionHandler:)`; AVAudioNode `lastRenderTime` and
`outputPresentationLatency`; `AVAudioEngineConfigurationChange`; `kAudioFormatOpus`;
`kAudioFormatMPEG4AAC_ELD`; developer forums thread 763362. The SDK headers of Xcode 27.0:
ScreenCaptureKit's SCStream.h and SCError.h, AVFAudio's AVAudioSourceNode.h, CoreAudio's
CATapDescription.h and AudioHardwareTapping.h.

---

## Refresh (2026-09-27)

Read against main at 643af6b and the three open pull requests that touch the same code, #37
(home-pairing at 7a6bf41), #38 (trackpad-gestures at 0c8d5a6, main merged in) and #39 (remote-away
at da250bc), and every other branch and worktree, the day's keychain-hardening, release-next and
spotlight-modifier-fix among them. Nothing was built or run. Changed in place:

1. **Noah's decision.** Now, not after v1 (Q13; the header, "Reading of it"); step 8 records it in
   BRIEF.md and CLAUDE.md. Every other open question takes its default.
2. **Line numbers** are 643af6b's throughout; the critique's own stay 150f781's.
3. **Kind 29, confirmed.** 24 to 27 are on main (#31, #36) and 28 is #38's `gesture`; no ref,
   worktree or plan holds 29 or above. New: the checks that name the free kinds say 29 is `audio`
   and 30 unknown, and the mutants that renumber a kind onto 29 move to 250–254 (§3.1, H3, step 1).
4. **The send path on main's StreamServer** (§Decision, §4.6). Remote pacing's names and numbers:
   the sound counts in `pendingBytes` and so in the budget, the slack, the hold and the idle mark,
   and `paceRemote` sees only frames, so it is never dropped there; the idle mark, about a second of
   sound, does not hold back the keyframe on a link that carries the sound. `sendAudio` is a send
   of its own, as the tick and kind 26 have, sets `lastSentAt` on every client and never touches
   the keyframes' bookkeeping. H6 runs the pacing harness's own cases with sound; H11 greps for it.
5. **TLS at home (#37).** Every hello reaches `took` through the Door's gate and `serve`; a TLS
   client skips its tick while sound flows (one on the cable gets none); each packet costs a TLS
   record at home too; the CLI's parity baseline stays its plain door.
6. **Following the source** (§2, §4.7, §13). `active`'s didSet, where the pointer's geometry and
   the menus' target follow the source since #31 and #36, in place of select's defer: `active` is
   set only once the picture has started. The app as `menuTarget()` finds it (a staged window by
   its placement's pid); its `SCRunningApplication` by a bounded look, so `make` is async (§4.2,
   §4.5); `adopt` leaves a change inside a select to the didSet. The menus' and the gestures'
   handlers share nothing with the sound.
7. **The Sound button on every layout** (§7.6, Q10). The phone's arrangement (#30): row 1 as
   approved, Sound at the end of row 2 under Settings, Menus moving under Desktop while both show,
   the strip keeping a whole thumbnail at 320 pt and two from 375; the bars: after Desktop, Menus
   first where only one fits; a Sound switch in the panel's group for this device on every layout,
   the only one in a Slide Over. The tour (#35) needs no step, and its lit areas never take the
   button in. `phone-portrait` and `tour` gain cases (H3); S1 photographs every layout; P8 checks
   the phone and a Slide Over.
8. **Project-file IDs** (§7.1). The critique's A401–A403 went to the tour (A401, A402); A501 is the
   phone's layout, A601 home pairing's, A701 the gestures', A801 away's. The sound takes AA01–AA03.
9. **Test rules** (§4.11, §7.4, §11, §13). Every test host on `SILL_TEST_LOOPBACK` and
   `SILL_TEST_SOFTWARE_ENCODER` (main's since #31); `Scripts/encoder-check/no-device.sh` before
   any run that could meet Noah's stream; the simulator's engine in manual rendering
   (`-SillSoundSink manual`), so no output device opens and nothing reaches a speaker, with the
   player at volume 0 besides; a private simulator, "Sill audio", screenshots only; nothing
   installed on Noah's devices; 25 GB free and DerivedData in the session's scratch folder.
10. **Away from home (#39).** `applyingAway` passes Send Audio on as `applying` does (§4.1);
    `audioNote` is the Mac's, beside each connection's `away` and `link` (§3.4); the link report
    counts the frames withheld (never the sound) and the sound's bytes in what the link carried
    (§Decision, §10);
    the move home is a hand-over, with home's jitter bounds from then (§7.2, rules 2 and 7); Q3
    notes the away quality.
11. **A move's first packets** (§7.2). The probe's messages are handled at the hand-over and
    stamped then; a duplicate is now dropped before it counts anywhere, so a move never raises the
    need (a gap the critique left; H3 gains the case and a mutant).
12. **Compatibility** (§3.5, §3.6, P15). The older host is Sill for Mac 0.3.1, the public release;
    a device build from before #37 reaches no TLS home door at all; if the sound ships in the first
    public builds, its wire joins the compatibility floor.
13. **Public copy** (step 8): in the words public copy uses for Apple's names, "sound from your
    Mac".

Left as they were: the codec and its numbers, the time stamps, the playout's rules and constants
(but for rules 2 and 7 above), the host's sources (but for the app's lookup), packetizer, encoder
and pipeline, the costs (but for TLS), and the P-list (but for P8 and P15).
