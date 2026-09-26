# The Mac's sound on the device — the plan

2026-09-26. It stands alone: the implementer needs no other design document. Written from a
read-only survey of origin/main at 8b0d418 ("Merge pull request #18", update-notice), of the
`remote-pacing` branch at 3126821 ("remote pacing counts bytes") and of the plans that hold message
kinds (pointer-visibility-plan.md holds 26; the Mac menu bar sketch 24, 25 and 27). Line numbers
are at 8b0d418. Nothing was started: no host, no app, no ScreenCaptureKit call, no sound captured,
and never the Mac's video encoder. Two read-only probes ran, both in memory on a synthetic signal:
AudioToolbox's encoders and decoders on this Mac (macOS 27.0 26A428, Xcode 27.0), and the same
program inside the iOS 27.0 simulator runtime (`simctl spawn` of a command-line binary; nothing
installed). They and their output are in the session's scratch folder
`…/scratchpad/audio-plan/probe/` (`formats.swift`, `realtime.swift`, `run-realtime.txt`,
`run-realtime-sim.txt`). Apple's own account of ScreenCaptureKit's audio is WWDC22 session 10155,
"Take ScreenCaptureKit to the next level"; availability comes from the SDK headers (SCStream.h,
CATapDescription.h, AudioHardwareTapping.h, AVAudioSourceNode.h).

**Noah's request (2026-09-25, as relayed to this session):** "Another idea for the future is to
have Sill send audio back with the video." On 2026-09-26 he put it on the list to work on.

**Reading of it.**
- **What the device hears.** The sound of what streams: the picked window's app, or every app for
  the Desktop. Not a microphone, and not the device's own sounds.
- **In step with the picture.** The sound never leads the picture, and trails it by as little as
  the sound's own path allows.
- **At no cost to the picture.** No frame waits for sound, nothing restarts for it, no new
  permission, and the CLI prints nothing new unless asked.
- **v2.** BRIEF.md keeps audio out of v1 ("Out: … audio"). This is the design for after v1; nothing
  here changes v1.

---

## Decision

### What the sound is of

| Source | What the device hears | The audio stream's filter |
|---|---|---|
| A window (regular mode) | Every sound of that window's app: all its windows and tabs | `SCContentFilter(display: main, including: [app], exceptingWindows: [])` |
| A window on the virtual display | The same | The same (sound does not depend on the display) |
| The Desktop | Every app's sound but Sill's: the whole Mac | `SCContentFilter(display: main, excludingApplications: [Sill], exceptingWindows: [])`, as the Desktop's picture (StreamCoordinator.swift:961-972) |
| The test pattern (`--synthetic`) | A test tone | none: `SyntheticAudio` (§4.2) |

- **Sound is per app, always.** In WWDC22 session 10155 Apple says ScreenCaptureKit filters audio
  only at the application level: a single-window filter captures all of the owning app's sound,
  including windows that are not in the video, and excluding one window's sound means excluding
  its whole app. So there is no "just this window" sound. It also means window capture does carry
  sound: `SCContentFilter(desktopIndependentWindow:)`, today's window filter
  (StreamCoordinator.swift:934), would bring the app's. The plan takes the sound from a stream of
  its own anyway (next point), so nothing depends on either reading.
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
  explicitly. Each buffer is a `CMSampleBuffer` wrapping an audio buffer list in that format
  (SCStream.h). The host reads each buffer's `AudioStreamBasicDescription` and never assumes its
  sample format or layout. That format, how many frames a buffer holds and how long after its time
  stamp it arrives are not documented: the first buffer's log line says all three (§4.10), and P2
  records them.
- **What ScreenCaptureKit does not hear.** Sound played by system daemons rather than by an app,
  such as a FaceTime or phone call relayed from an iPhone (third-party reports), and possibly the
  system's alert sounds. Apps that play through helper processes are attributed to their app in
  Apple's own demo (Safari, whose media plays in a WebKit process); P4 checks the rest.

### Which codec: measured

The probe fed 6 s of a busy signal (noise at −24 dBFS under three tones, 48 kHz stereo float)
through each AudioToolbox encoder in capture-sized chunks, decoded every packet as soon as it
existed, and found a 4 ms burst in the output. "End to end" runs from the burst entering the
encoder to leaving the decoder, with the smallest constant playout offset that never runs dry. It
counts packetizing, the codec's own delay and the chunks' misalignment; no network, no buffer.

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
  AAC-ELD has been in AudioToolbox on both systems for many releases, and AirPlay screen mirroring
  carries its sound as AAC-ELD (the unofficial AirPlay specification; the open receivers RPiPlay
  and WinAirPlay decode it as such).

**Chosen: AAC-ELD at 128 kbps, 48 kHz stereo,** 480 frames a packet (10 ms), or 512 when the Mac's
capture buffers come in multiples of 512 frames. The packet that divides the capture chunk evenly
is 10–20 ms faster end to end (the two bold cells); the host decides from the first buffer (§4.3)
and says which in the format message.
- **Why ELD, not Opus:** the same latency, about half the encode CPU and a fifth of the decode,
  certain on both floors, and Apple's own choice for the same job. Opus stays one field away
  (`codec`, §3.2; Q2).
- **Why not AAC-LC:** its 65–75 ms alone is more than the picture's whole path.

### Where the time goes

At home, the iPad on Wi-Fi, its own speaker, a 60 Hz panel:

| Stage | Picture | Sound |
|---|---|---|
| Capture | ≤ 1 refresh (≤ 16.7 ms) | ScreenCaptureKit's buffer: not documented; P2 records it (10–25 ms assumed) |
| Encode | a few ms (hardware HEVC) | 15.0 ms (480-frame chunks) or 26.7 ms (1024-frame chunks, 512-frame packets), measured |
| The link | frame age 8–10 ms, encode included (measured 2026-09-22) | The same connection: the same few ms, plus 15–40 ms when it sits behind a keyframe |
| On the device | shown on arrival, decoded in 1–2 refreshes | the jitter buffer (20–60 ms at home: it covers the keyframe every 4 s), decode under 0.1 ms, the IO buffer (5 ms) and the speaker's own latency (5–15 ms) |
| **In all** | **40–60 ms** (estimated) | **70–140 ms** (estimated) |

- **So the sound trails.** By construction it never leads (§7.2, rule 4). In practice its own path
  is the longer one, so it trails by 30–80 ms at home, 2–5 frames at 60 fps. That is under the
  ~125 ms at which late sound is noticed (ITU-R BT.1359: detectable at 45 ms early or 125 ms late).
- **"1–2 frames behind" is the rule, not the measure.** When the sound is ready in time, the device
  plays it one frame of the stream's rate after the picture. It rarely is: the 4 s safety keyframe
  (HEVCEncoder.swift:117, `fps * 4`) puts 1–2 MB in front of the next packets every 4 s, and a
  buffer that does not cover it clicks every 4 s. A glitch is worse than 30 ms.
- **Bluetooth.** AirPods add their own 150–250 ms, which AVAudioSession's `outputLatency` reports.
  The picture is not delayed to match: latency beats quality (Q7).

### How the device keeps time

- **One clock: the host's wall clock.** Every audio packet's header carries the host wall-clock
  time (seconds since 1970) at which its first decoded sample played on the Mac. That is the clock
  the video's header already uses (StreamMessage.swift:53; the frames'
  `Date().timeIntervalSince1970` at encode, StreamCoordinator.swift:1025).
- **No clock sync, no new round trip.** The device never needs the offset between the Mac's clock
  and its own. It needs a stable reference: **the floor**, the smallest (arrival − time stamp) among
  the audio packets of the last 10 s. A packet stamped T is due at `T + floor + delay` on the
  device's monotonic clock.
- **Drift.** The two clocks drift apart by tens of ppm. The sliding minimum follows the drift, and
  the playout follows the floor by adding or dropping single frames, never by a jump (§7.2).
- **Why not the ping pairs.** The pong carries no host time: the host echoes the ping's header time
  stamp and payload unchanged (StreamServer.swift:1057), and the device reads only the payload
  (StreamClient.swift:2416-2421).
  - Adding the host's time to the payload would break the move's fence on every older device: it
    compares a pong's whole payload with its nonce (SessionLink.swift:119).
  - The pong's header time stamp could carry it, since nothing reads it, but nothing needs it: the
    host already stamps every audio packet, 100 times a second.
  - The ping pairs keep one job: their round trip tells a host clock step from network jitter
    (§7.2, rule 13).
- **The picture's lag, from the frames.** Each frame's (arrival − time stamp) against the same
  floor, the median of 2 s, plus the display's own delay (decode and the next vsync). The sound's
  delay is at least that plus one frame. A frame's stamp is its encode-out time, a few ms after
  capture, so at worst the guard keeps the sound (1 frame − ~5 ms) behind: still behind at 120 fps.

### How sound shares the link

- **At home it never counts against the picture.** The delta-drop rule drops a frame when more
  than 2 messages are unacknowledged (`inflight > 2`, StreamServer.swift:1136). Audio at 100
  messages a second counted there would drop frames all the time. Audio goes out like the tick
  (StreamServer.swift:176): not counted in `inflight`, with a cap of its own (§4.6).
- **Away, "audio first, video drops."** The remote-pacing change counts a remote client's backlog
  in bytes (`pendingBytes`, branch `remote-pacing`). Audio bytes count there, because the link
  carries them. `paceRemote` drops frames, never sound: on a link that cannot carry both, the
  picture loses frames and waits for keyframes while the sound keeps its 16 KB/s.
- **The limit.** Sound cannot overtake video already handed to the connection: one TCP stream, in
  order. Behind a remote backlog (256 KB, 512 KB behind a keyframe: 0.5–1 s at 4 Mbps) the sound
  waits as long as the picture does. They stay together, and the device's buffer follows the
  picture (§7.2, rule 4). Jumping the queue needs Sill to hold frames back from the kernel, a send
  queue with priorities that the remote bundle left out too (§14).
- **Never a delay for frames.** Audio is encoded on its own queue and handed to the network queue
  as one small message (about 190 bytes) the moment it exists. A frame never waits for sound, and
  sound never waits for a frame.

### Controls

- **Send Audio: a host setting, off by default in the first release with sound.**
  - The Mac keeps playing its own sound (ScreenCaptureKit does not silence the source). A device
    beside the Mac, the common case, would double every sound 70–140 ms late until someone mutes
    one of them.
  - The CLI's output stays byte for byte without `--audio`.
  - The pattern the virtual display and Direct Wireless set: off until Noah has tried it, then his
    call (Q1).
  - The Mac's sound leaving the Mac is something the Mac's settings should show.
  - A device can turn it on from its Settings panel, like the other stream settings, and Sill.app
    saves it (Q8).
- **Sound: a button in the device's bar,** only while the Mac sends sound. It mutes this device
  alone, at once, without asking the Mac. The Mac keeps sending (16 KB/s), so unmuting is quick too
  (about 0.1 s, while the device's audio engine starts). The device remembers it.

### Not in this step

- A quiet Mac while the device plays (the Core Audio tap: Q6, §14).
- Sound from the device to the Mac (a microphone).
- One window's sound alone (ScreenCaptureKit's policy is per app).
- Opus, other bitrates, any codec or bitrate choice in a UI (Q2, Q3).
- Delaying the picture for Bluetooth headphones (Q7).
- Priority for sound in the remote send path (§14).
- Silence suppression on the host (silent packets cost 3 KB/s with their headers).
- Sound while the app is in the background (no `UIBackgroundModes`).

---

## Final plan

### 1. Scope

**In this step:**
1. **The wire.** Kind 28 carries a format (JSON) and packets (binary) of the sound (§3). The hello
   lists what the device plays; kinds 16 and 17 gain `sendAudio`; ClientStats gains two optional
   fields.
2. **The host.** An audio-only ScreenCaptureKit stream that follows the streamed app (or a test
   tone), an AAC-ELD encoder on its own queue, and a send path that never counts against the
   picture. Send Audio (off by default), the CLI's `--audio`, and log lines only when it is on.
3. **Sill.app.** Send Audio in the status menu and in Settings › Streaming, the Permissions pane's
   words, and "sound" on the card's source row while a device gets it.
4. **The device.** A pure playout model (the floor, the jitter buffer, the picture guard, drift by
   single frames), an AAC-ELD decoder, AVAudioEngine playback through an `AVAudioPlayerNode`, the
   session's category and interruptions, the bar's Sound button and the panel's Send Audio row.
5. **Tests.** Three pure checks with mutants, new cases in two existing checks, an encoder-free
   harness with a test tone, and the CLI byte for byte.

**Not in this step:** see "Not in this step" above.

### 2. The design on one page

```
 ┌──────────────────────────── Mac (Sill.app / SillHost) ─────────────────────────────────┐
 │ main actor  StreamCoordinator.select(…) ─▶ picture pipeline (unchanged)                │
 │             its defer ─▶ AudioPipeline.follow(app | desktop | test | none)             │
 │                          the same app as now → nothing                                 │
 │ sill.audio  AudioCapture (SCStream, sound only; its 2×2, 1 fps picture thrown away)    │
 │             or SyntheticAudio (--synthetic) ─▶ PCM + host time                         │
 │             AudioPacketizer: 480/512-frame blocks, stamps, gaps → segments (pure)      │
 │             AudioEncoder: AAC-ELD, 128 kbps (AudioToolbox) ─▶ packet, wall-clock stamp │
 │ sill.net    StreamServer.broadcastAudio: devices whose hello plays "aac-eld";          │
 │             the format first; not in `inflight`; in `pendingBytes` away; a cap ────────┼─▶ kind 28
 └────────────────────────────────────────────────────────────────────────────────────────┘
 ┌──────────────────────────────── device ────────────────────────────────────────────────┐
 │ network q.  kind 28 parsed, frames' stamps: both stamped on arrival, handed on         │
 │ sill.audio  AudioPlayout (pure): floor, need, picture's lag, dedupe → late? place?     │
 │             a frame more or less? a jump?                                              │
 │             AudioDecoder (AAC-ELD → float) ─▶ fades, ±1 frame ─▶ AVAudioPlayerNode     │
 │             AVAudioEngine: player → main mixer → output; session .playback, mixes      │
 │ main        Sound button (mute, local), Send Audio row (kind 17), announcements        │
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3. Wire protocol

#### 3.1 Kind 28 (`Sources/StreamProtocol/StreamMessage.swift`, continuing the enum)

```swift
    // 23 is the device's hello (update-notice). 24, 25 and 27 are held for the Mac menu bar
    // (sketched 2026-09-25, not built) and 26 for the Mac's pointer (pointer-visibility-plan.md),
    // so the sound takes 28.
    case audio = 28          // host → device: AudioMessage (Audio.swift) — the sound of what streams: a format (JSON
                             // AudioFormat), then packets (binary). Only to a device whose hello lists the codec, and only
                             // while Send Audio is on. Older readers map it to `.unknown` and skip it
```

- **Who skips it.** Every device and test client since b67f87d (2026-09-23): `parseHeader` maps an
  unknown kind to `.unknown` (StreamMessage.swift:99), and the client's `handle` ignores it
  (StreamClient.swift:2444-2445). A device from before this step is never sent one anyway (§3.5).
- **Its size.** A format is under 1 KB and a packets message under 1 KB at 128 kbps, far under
  `maxOtherHostPayload` (4 MB); §3.2's parser caps them at 4 KB and 16 KB.
- **Nothing else changes** in kinds 0–27. If a branch has taken 28 by the time this starts, the next
  free number, and this section follows it (H0, Q12).

#### 3.2 The payloads (`Sources/StreamProtocol/Audio.swift`, new; the iOS app gets it through the package, no pbxproj entry)

A kind 28 payload's first byte says what follows. A type this build does not know is skipped.

```
type 1  format:   JSON AudioFormat
type 2  packets:  epoch UInt16 · seq UInt32 · flags UInt8 · count UInt8 · count × (length UInt16 · bytes)
                  big endian, like the header; flags bit 0 = the first packet of a segment (reset the
                  decoder); bits 1–7 zero, ignored by readers
```

```swift
/// Host → device (kind 28, type 1): how to decode what follows. Sent to each device before its first
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

/// Host → device (kind 28, type 2): one or more codec packets of one epoch, back to back.
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
- **Checked end to end** by H4 and H5: a click at a known host time lands at its stamp ±1 ms after
  the whole path.

#### 3.4 Fields added elsewhere (all optional, all additive)

| Where | Field | Meaning |
|---|---|---|
| `Hello` (Compatibility.swift:93-107) | `audio: [String]?` | The codecs this device plays, best first: `["aac-eld"]`. Nil: an older device, which gets no kind 28 |
| `StreamSettings` (HostSettings.swift:49-71) | `sendAudio: Bool?` | Send Audio. Nil: a host without sound, so the device shows no row and never sends it (the ledger's rule 9) |
| `HostSettingsChange` (HostSettings.swift:126-164) | `sendAudio: Bool?` | A device turns it on or off; `isEmpty` and `applied(to:)` include it |
| `HostSettingsState` (HostSettings.swift:92-120) | `audioNote: String?` | Why no sound comes although Send Audio is on ("couldn't capture the sound of Safari"); nil when all is well |
| `ClientStats` (Viewport.swift:38-53) | `audioBehindMs: Int?`, `audioLate: Int?` | That second's median of how far the sound trailed the picture, -1 for a second with no sound played; the packets that came too late to play. Nil from a device that has played none this session |

#### 3.5 Compatibility

| Device | Host | Result |
|---|---|---|
| Older (any build since b67f87d) | This host, Send Audio on | Its hello has no `audio`, so it is sent no kind 28 (it would skip one). It ignores `sendAudio` and `audioNote` in kind 16. Nothing changes for it |
| This device | Older host (8b0d418's Sill.app, any CLI before this) | No kind 28; `sendAudio` nil: no row, no Sound button |
| This device | This host, Send Audio off | The row shows off; no button; no kind 28 |
| This device | This host, Send Audio on | This plan |
| `sillclient.py` at 8b0d418 | This host | No hello, or one without `audio`: no kind 28. Kind 16 carries two more keys |
| A test client whose hello lists `audio` but that does not decode | This host | Gets kind 28 and may skip it |

#### 3.6 Rules for later changes

- HostSettings.swift's rules apply to `AudioFormat` and the new fields: JSON, optional, strings not
  enums, never renamed or retyped.
- The packets' layout is fixed: a change is a new type byte, never a changed type 2.
- A new codec is a new `codec` string, listed in the hello by the devices that play it. A host
  picks the first of a device's list that it can make; this host makes only "aac-eld".

### 4. Host (`SillHostCore`, folder `Sources/SillHost`), file by file

**Base.** main, after the remote-pacing branch (3126821) has merged: §4.6 builds on its
`pendingBytes`. If it has not merged, merge it first. The pointer (kind 26) and menu-bar-mirror
branches touch the same enum and the harness comment, nothing else of this.

#### 4.1 `HostConfig.swift` and `DeviceSettings.swift`

- **`HostConfig.sendAudio: Bool`,** required in `init` like every knob, so the compiler finds each
  place that builds one. `standard`: false. `validated()`: nothing to clamp. `changes(to:)`:
  "send audio off → on".
- **`streamSettings`:** `sendAudio: sendAudio`. **`applying`:** `if let v = change.sendAudio
  { c.sendAudio = v }`.
- **`DeviceSettings.accepted`:** `if let v = c.sendAudio { ok.sendAudio = v }`, from either door.
  It changes what a device hears of the Mac, not who can reach the Mac (Q8).
- **Not in `restartNeeded`** (StreamCoordinator.swift:491-501): the sound has its own stream;
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
  app is another stream.
- **Each buffer:** its ASBD (`CMSampleBufferGetFormatDescription`), `CMSampleBufferGetNumSamples`,
  its PTS in seconds; the PCM copied with `CMSampleBufferCopyPCMDataIntoAudioBufferList` into a
  reused buffer. A PTS more than 1 s from `CMClockGetTime(CMClockGetHostTimeClock())` is not on the
  host clock: logged once and replaced by the arrival time minus the buffer's duration.
- **Bounded.** `startCapture` and `stopCapture` each get 2 s, as the other ScreenCaptureKit calls
  are bounded (WindowCatalog.swift:163). A start that runs out is a failure (`audioNote`).
- **`didStopWithError`** (a window closing, the permission revoked) → `onStopped`.

**`SyntheticAudio`** (Foundation only; `--synthetic`):
- A 10 ms `DispatchSourceTimer` on `sill.audio` makes 480 frames of 440 Hz at −30 dBFS, stereo
  float, stamped with `mach_absolute_time`.
- A 4 ms windowed 2 kHz click at −6 dBFS starts at each whole second of host time, so a test client
  can check the stamps end to end.
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
  - within ±2 ms: appended as it is (clock jitter);
  - later by up to 100 ms: the gap filled with zeros, then appended (a short pause keeps the
    decoder's state);
  - later by more, or earlier by more than 2 ms: the segment ends (its last block padded with
    zeros and flushed), and a new one starts at this chunk (`segmentStart`);
  - a new format (rate, channels) ends the epoch: the pipeline makes a new encoder (§4.5).
- **The stamp of block n:** the host time of segment frame `n·F − P`, interpolated between the
  anchors (or extrapolated before the first). The pipeline turns it into wall time as it sends
  (§3.3).
- **`AudioSourceRule`** (same file, pure): what `follow` does with the current and the wanted source
  (§4.5). The same app (by pid) → keep. Another app, the Desktop, the test tone → a new stream and a
  new epoch. None → stop.

#### 4.4 `AudioEncoder.swift` (new; AudioToolbox only, so the harness links it: no CoreMedia, no AVFoundation)

- **The converter.** `AudioConverterNew` from the first chunk's PCM format (any rate or layout: the
  converter resamples and interleaves) to `kAudioFormatMPEG4AAC_ELD`, 48 kHz, 2 channels,
  `mFramesPerPacket` F; `kAudioConverterEncodeBitRate` 128,000.
- **Read back:** `kAudioConverterCurrentOutputStreamDescription` (F),
  `kAudioConverterPrimeInfo.leadingFrames` (P), `kAudioConverterCompressionMagicCookie` (the
  cookie), `kAudioConverterPropertyMaximumOutputPacketSize`.
- **Use.** `encode(block) -> Data` per block, on `sill.audio`; `reset()` (`AudioConverterReset`) at
  a segment start.
- **A failure to create it:** "Audio encoder: AAC-ELD unavailable: <status>", and no sound this run
  (`audioNote`).

#### 4.5 `AudioPipeline.swift` (new)

Owns the source, the packetizer and the encoder on `sill.audio` (serial, `.userInteractive`), the
epoch counter, and what the coordinator and the server see of them.
- **`follow(_ key: AudioKey, make: @escaping () -> AudioSource)`** (main actor; returns at once).
  The work runs in a Task, and a newer call replaces one not yet begun, as `setTarget`'s changes do.
  `AudioKey` is `.app(pid, name)`, `.desktop`, `.test` or `.none`. `make` builds the source: the
  coordinator's closure makes an `AudioCapture` with its filter, or a `SyntheticAudio`. So
  AudioPipeline never imports ScreenCaptureKit, and the harness compiles it.
  - The same app (by pid) as the running stream: nothing (a resize, a rotation, another window of
    it).
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
  `audioNote` and logs one line. The next `follow` for another source, or Send Audio off and on,
  tries again. No retry loop.
- **Status:** `HostStatus.audio` (§4.8), and `audioNote` for kind 16.

#### 4.6 `StreamServer.swift`

- **`Client`** (StreamServer.swift:42-83) gains:
  - `audioCodecs: [String]`, from the hello;
  - `audioEpochSent: Int?`, the epoch whose format it has;
  - `audioUnsent: Int`, audio messages handed to the connection and not yet taken.
- **`took(_:from:)`** (:949-956) sets `client.audioCodecs = hello.audio ?? []`. When the number of
  clients that play "aac-eld" changes (here and in `unregister`), `onAudioListenersChanged(count)`.
  The hello's own line is unchanged.
- **`broadcastAudio(format: Data, epoch: Int)`** keeps `lastAudioFormat`, as `lastParameterSets` is
  kept (:1122).
- **`broadcastAudio(packets: Data, epoch: Int)`,** for each ready client that plays "aac-eld":
  - `audioEpochSent != epoch` → the format first (never skipped), and `audioEpochSent = epoch`;
  - `audioUnsent` at its cap → this packet is skipped (`aud.drop`). The cap is a stalled link's
    safety valve, not pacing: 100 messages at home (1 s), 300 away (3 s; a remote queue can
    legitimately hold a second of stream, and the device follows the picture's lateness);
  - otherwise `sendAudio(_:to:)`: `connection.send` with its own completion, `aud.sent`.
- **What `sendAudio` counts.**
  - **Home:** never `inflight`, `inflightFrames` or the drain eviction's clock: those stay the
    picture's, byte for byte (:1119-1153, :1223-1253).
  - **Away:** added to and taken from `pendingBytes` (the remote-pacing change), and `lastSentAt`
    set, so a remote client's ticks pause while sound flows (:175), as after any message.
- **`resetForNewStream`** (:1008-1016, the picture's restarts) leaves the sound's state alone.
- **Ticks** at home: unchanged.

#### 4.7 `StreamCoordinator.swift`

- **Owns** `let audio: AudioPipeline`, built in `init` with the server and `synthetic`.
- **Where `follow` is called** (main actor):
  - **In `select`'s defer** (:804-834), on every return path, from the `active` it leaves. For
    `.window(id)`: the window's `owningApplication`, with `catalog.display` for the filter. For
    `.desktop`: a new filter of the same kind as the picture's (:961-972), or `.test` when
    synthetic. `.none` when nothing streams. The picture always starts first.
  - On `onAudioListenersChanged`.
  - In `adopt` (:504-523), when `sendAudio` changed: the same `follow`, and the one "Settings:"
    line every knob gets.
  - With `.none` in `shutdownForExit` (:1280).
- **`settingsState`** (:1610): `sendAudio: config.sendAudio` in `StreamSettings`, and
  `audioNote: audio.note`.
- **A device's change** goes through the kind 17 handler unchanged (`DeviceSettings.accepted`).

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

#### 4.10 Log lines and Stats keys (exact; none unless Send Audio is on, or a device changes it)

| When | Line |
|---|---|
| Sound starts for a window | `Audio: capturing Safari's sound (every window of it).` |
| … for the Desktop | `Audio: capturing the whole Mac's sound (every app but Sill).` |
| … on a synthetic host | `Audio: a test tone (440 Hz at -30 dBFS, a click at each second).` |
| Its first buffer | `Audio: first buffer 1024 frames, 48000 Hz, 2 channels, 32-bit float, non-interleaved, 9 ms after its time stamp.` |
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

`SILL_TEST_AUDIO_CHUNK=1024` (§4.2). Nothing else: the test tone is the test source.

### 5. CLI (`Sources/SillHostCLI/main.swift`)

- **`--audio`:** `config.sendAudio = true`, and after the startup lines (main.swift:106-109) one
  more: `Audio on for this run: devices that play sound get the streamed app's sound, or the whole
  Mac's for the Desktop.`
- **`--synthetic --audio`:** the test tone (§4.2).
- **A device's change** lasts until SillHost quits, as every setting does.
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
- **Settings › Streaming** (SettingsPanes.swift:203-244): a section after "Prioritize encoding
  speed": `Toggle("Send audio", …)` with the footer **"Devices play the sound of what you stream:
  all of the streamed window's app, or every app for the Desktop. The Mac keeps playing it too, and
  each device can mute it in its bar. Nothing is recorded."** While `snapshot.audio?.problem` is
  set, under it, the orange label: **"Sill couldn't capture the sound of Safari: <reason>. The
  picture is unaffected."**
- **Settings › Permissions** (SettingsPanes.swift:318-323): Screen Recording's explanation becomes
  **"Lets Sill capture the windows you pick on your iPhone or iPad, and their sound when Send Audio
  is on. Nothing is recorded or saved; frames and sound go straight to your devices."**
- **The card** (StatusText.swift:179-205): the source row's detail ends in **" · sound"** while
  `snapshot.audio?.devices ?? 0 > 0`. A new preview sample, `sound`, the widest source row with it
  (H10).
- **The Log window** shows §4.10's lines as it shows every line.

### 7. iOS client

#### 7.1 Files

Each new file needs its four pbxproj entries by hand. main has used A01E/F01E (GoodbyePolicy); the
open plans name A01E–A020; so A021/F021, A022/F022 and A023/F023, re-checked at H0.

| File | What | Imports |
|---|---|---|
| `AudioPlayout.swift` (new) | The playout model: floor, need, the picture's lag and the guard, dedupe, placement, frames added or dropped, fades. Pure: checked with swiftc (`audio-playout`) | Foundation |
| `AudioDecoder.swift` (new) | AAC-ELD → 48 kHz stereo float, from the format's cookie | AudioToolbox |
| `AudioOutput.swift` (new) | AVAudioEngine, the player node, a buffer pool, the session and its notifications | AVFAudio, UIKit |
| `StreamClient.swift` | Kind 28, the hello's `audio`, frames' stamps to the model, stats, resets | |
| `StreamScreen.swift`, `PortraitStreamScreen.swift` | The Sound button | |
| `HostSettingsPanel.swift`, `HostSettingsLedger.swift`, `MockCatalog.swift`, `ContentView.swift`, `DiagnosticsHUD.swift` | The row, the field, the harness, the HUD | |

**Why a player node and no render block of Sill's own.** The iOS 27 SDK adds
`AVAudioSourceNodeRenderBlockRealtimeSafe` and keeps it from Swift with the message "Swift is not
supported for use with audio realtime threads" (AVAudioSourceNode.h:48). A render block Sill wrote
would be Swift on the real-time thread. With `AVAudioPlayerNode.scheduleBuffer`, every line of
Sill's runs on ordinary queues, and the real-time code is Apple's.

#### 7.2 `AudioPlayout` (pure; Foundation only)

- **Clocks.** Device times are seconds of the monotonic clock (`CACurrentMediaTime`, the host clock
  whose ticks AVAudioTime's `hostTime` counts); host stamps are wall-clock seconds.
- **Queue.** It runs on `sill.audio`. The network queue stamps each frame and each kind 28 with its
  arrival as it reads them, and hands them over.

**Inputs:**
- `format(_:)`: a new epoch (F, P, the sample rate).
- `frame(stamp:arrival:)`: every video frame (kind 1), for the picture's lag.
- `packet(epoch:seq:stamp:arrival:segmentStart:)` → a decision (the rules below).
- `played(sampleTime:at:)`: the player's progress (`lastRenderTime`, `playerTime(forNodeTime:)`),
  read at each schedule.
- `latency(output:io:refresh:streamFPS:)`: from the session and the viewport.
- `rtt(median:)`: from the pings, once a second (rule 13).
- `reset(_:)`: a new connection (a move, a reconnect), a route change, unmuting, the engine
  restarted.

**The rules:**
1. **The floor** is the smallest (arrival − stamp) of the audio packets in the last 10 s, kept in
   1 s buckets. With no packet for 10 s it keeps its last value.
2. **The need** is the largest (arrival − stamp − floor) of those packets in the last 10 s, plus one
   packet (F / rate), plus the IO buffer: what covers the link's jitter, a keyframe in front
   included.
   - It starts at 40 ms at home and 150 ms away, until 2 s of packets have come.
   - Bounds: home 20–150 ms; away 60–600 ms.
   - It rises at once (rule 6). It falls when the window forgets its maximum, and the error that
     leaves is closed by rules 11 and 12.
3. **The picture's lag** is the median (arrival − stamp − floor) of the frames of the last 2 s, plus
   1.5 refreshes and 4 ms: decode and the next vsync, since frames are shown on arrival
   (HEVCDisplayView.swift:276-279). No frames (a still window): its last value.
4. **The delay** is max(need, the picture's lag + one frame of the stream's rate). A packet stamped
   T is due at the speaker at `T + floor + delay`, and is scheduled for `due − outputLatency`. The
   guard has no bound: on a link where the picture runs a second late, so does the sound.
5. **Placement.** The first packet of a segment, and the first after an underrun or a jump, is
   scheduled at its due time (`AVAudioTime(sampleTime:atRate:)` in the player's timeline, mapped
   from `played`). Every later packet of the segment follows the one before it, contiguous.
6. **Late.** A packet whose scheduled time is less than 2 ms away when it is decoded is dropped, and
   the need rises to cover it at once. The segment's next packet is placed by time (rule 5).
7. **Duplicates.** A packet whose (epoch, seq) is among the last 256 is dropped: a move's two
   connections both carry the stream for a moment.
8. **Missing.** A seq that skips (the host's `aud.drop`) makes a new segment on the device: the
   decoder resets, and the next packet fades in.
9. **A new segment** (the flag, a new epoch, a device's first packet, a reset): the decoder resets,
   its first P decoded frames are dropped (the codec's start), and the next 5 ms fade in. A first
   packet in the middle of a segment (a device that joined late) is decoded and dropped whole, and
   the next one fades in.
10. **The newest packet stays in hand** until the next arrives or its deadline (its scheduled time −
    2 ms) passes. Then it goes out, faded over its last 5 ms if nothing followed it. An underrun
    ends in a fade, never a click. The need's extra packet (rule 2) pays for the wait.
11. **Drift and small changes: single frames.** Once a second the model compares where the stream
    plays with where it is due: `error = (the stamp of the sample playing at t) + floor + delay − t
    − outputLatency`. It evens it out one frame at a time. Each packet scheduled may gain a frame (a
    copy at its quietest point, blended into its neighbours) when the sound runs ahead, or lose one
    when it runs behind. At most one a packet: about 2 ms a second, far more than two clocks drift
    (tens of ppm is 0.1 ms a second), and inaudible.
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
| Need | the window's largest excess + 1 packet + the IO buffer; first 40 ms at home, 150 ms away |
| Need bounds | home 20–150 ms; away 60–600 ms |
| The picture's lag | the median of 2 s of frames + 1.5 refreshes + 4 ms |
| The guard | the picture's lag + 1 frame of the stream's rate; no bound |
| Late | scheduled less than 2 ms ahead when decoded |
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
- `decode(_ packet: Data)` one packet at a time (the probe's loop), into pooled arrays; `reset()`.
- An unknown codec or a cookie it refuses: `audio: cannot play <codec>` in the DEBUG console, and
  no sound this epoch. The Sound button stays: the Mac says sound is on.

#### 7.4 `AudioOutput` (AVFAudio)

- **The graph:** `AVAudioPlayerNode` → `mainMixerNode` → output. The player's format is 48 kHz
  stereo float; the mixer converts to the route's rate.
- **Buffers:** a pool of 64 `AVAudioPCMBuffer`s of F + 1 frames (a gained frame fits); each comes
  back to the pool in its `scheduleBuffer` completion.
- **The session:** `.playback`, mode `.default`, options `[.mixWithOthers]` (Q4). It never stops the
  user's music or podcast, and it plays with the Ring/Silent switch on silent, as a video app does.
  `setPreferredSampleRate(48_000)`, `setPreferredIOBufferDuration(0.005)`. Active only while the
  engine runs; `setActive(false, options: .notifyOthersOnDeactivation)` when it stops.
- **When the engine runs:** the app in the foreground, the session carrying sound (a format has
  come), not muted, a packet within 10 s. It stops, after a 5 ms fade, on mute, on
  `didEnterBackground`, at the end of the session and after 10 s without a packet;
  `willEnterForeground` and the next packet start it again.
- **Interruptions** (`AVAudioSession.interruptionNotification`): `.began` (a call, Siri, an alarm):
  the engine has stopped, and the model resets. `.ended` with `.shouldResume`: start again; without
  it: at the next `didBecomeActive`.
- **Route changes.** `.oldDeviceUnavailable` (headphones out, AirPods taken off): mute, as a video
  app pauses, and announce **"Sound muted: headphones disconnected."** Any other reason (AirPods in,
  a speaker): read `outputLatency` and `ioBufferDuration` again and reset the model (one jump,
  rule 12).
- **`mediaServicesWereResetNotification`:** rebuild the engine and the session.
  **`AVAudioEngineConfigurationChange`:** start again and reset.
- **No `UIBackgroundModes`:** in the background the app is not heard.

#### 7.5 `StreamClient`

- **The hello** (`helloPayload`, StreamClient.swift:1015-1022) gains `audio: ["aac-eld"]`.
- **Kind 28** in `handle` (:2302): `AudioMessage.parse`, stamped with its arrival, handed to
  `sill.audio`. A format gets a new decoder; packets get the model's decision, then decode, fades,
  a frame more or less, and the schedule. Muted or in the background, the model still takes each
  packet's arrival (its floor and need stay right, so unmuting is quick) and nothing is decoded.
- **Frames** (kind 1): `frame(stamp:arrival:)` before `onFrame`.
- **Stats.** `closeWindow` (:2491) adds the model's second to `LinkStats` (`audioBehindMs`,
  `audioLate`), and `ClientStatsReporter` sends them.
- **Resets.** A new session connection (a connect, a move's hand-over, a reconnect) resets the model
  and the decoder.
- **State.** `soundMuted` (published; `UserDefaults` `Sill.soundMuted`, default false), and
  `soundAvailable` (the host's `settings.displayed?.sendAudio == true`).

#### 7.6 The Sound button (every bar)

- **Where:** after Desktop and before Settings, in the landscape top bar
  (StreamScreen.swift:416-497) and in the portrait window bar (PortraitStreamScreen.swift:258-293),
  at each layout's button size; only while `soundAvailable`.
- **Looks:** `speaker.wave.2.fill` over "Sound", or `speaker.slash.fill` over "Sound" when muted.
  Never the accent colour: it is not "open".
- **Space:** one button's width, taken from the thumbnail strip. On the outer display's portrait bar
  (500 pt) that leaves one thumbnail and part of the next instead of two (Q10).
- **VoiceOver:** label "Sound from ‹Mac›", value "On" or "Muted", the toggle trait.
- **The Aa ruler** fades it as it fades Keyboard and Desktop.

#### 7.7 The panel's Send Audio row (`HostSettingsPanel.swift`)

- **Where:** after the closing footnote "Applies to every device streaming from ‹Mac›. The stream
  restarts for a moment." (HostSettingsPanel.swift:217), before Direct Wireless: like Direct
  Wireless, it restarts nothing. Only when `shown.sendAudio` is not nil.
- **The row:** `Toggle` **"Send Audio"**,
  `binding(sendAudio) { HostSettingsChange(sendAudio: $0) }`, with `RowTitle`'s pending mark like
  the others.
- **Footer, off:** **"‹Mac› plays the sound of what streams on every connected device, and keeps
  playing it too."** **On:** **"Every device hears what streams; ‹Mac› keeps playing it too. Mute
  this ‹device› with Sound in the bar."**
- **`audioNote`:** under the row, as a warning footnote.
- **The ledger:** `SettingsField.sendAudio`, `only`, `adding`, `fields`, and rule 9
  (HostSettingsLedger.swift:100) for it: never sent to a host that did not report it.

#### 7.8 Harness, DEBUG console and HUD

- **Arguments** (the contract comment in ContentView.swift, and CLAUDE.md): `-SillSound on|muted`
  (the button in that state, no sound), `-SillSettingsCase sound|soundnote` (the row on; on with a
  note). The mock answers `sendAudio` as it answers the others.
- **DEBUG console lines:**
  - `audio: format aac-eld 48000 Hz 2 ch, 480 frames (priming 240), epoch 3, Safari`
  - `audio: engine on, Speaker, output 11 ms + IO 5 ms, delay 46 ms (need 46, picture 27 + 1 frame 17)`
  - once a second while playing: `audio: 38 ms behind the picture; need 44 ms; late 0; error +3 ms;
    frames +1 -0; jumps 0`
  - `audio: jump +52 ms (clock step)` · `audio: interrupted` · `audio: resumed` ·
    `audio: route Speaker → AirPods (+187 ms)` · `audio: muted (headphones disconnected)` ·
    `audio: idle, engine off`
- **The HUD** (`-SillHUD 1`) gains ` · sound 38` while sound plays.

### 8. Cost

| Where | What | Estimate |
|---|---|---|
| The Mac's CPU | ScreenCaptureKit's sound stream with its 2×2, 1 fps picture | not measured here (P13); small |
| | AAC-ELD encode | 0.5–0.9 % of one core (the probe; an upper bound) |
| | Sending | 100 messages a second to each device, one `send` each |
| The device's CPU | Decode | 0.07 % of an M-series core (the probe); a few times that on an A15 |
| | AVAudioEngine | what playing any sound costs |
| The link | Sound | about 16 KB/s (128 kbps) |
| | Framing | 25 bytes a packet (the 14-byte header and 11), 2.5 KB/s |
| | Silence | about 3 KB/s |
| | Against the picture | 1 % of Balanced (15 Mbps), 4 % of Low (4 Mbps) |
| Battery | The device's audio hardware while sound plays; the engine stops after 10 s of no packets | |

### 9. Timeouts and limits

| What | Value |
|---|---|
| The sound's stream, start and stop | 2 s each, then a failure (`audioNote`) |
| Following the source | after the picture's select; the same app keeps its stream |
| Packets | 480 or 512 frames (10 or 10.7 ms), one to a message (the wire allows 255) |
| A gap filled with zeros | up to 100 ms; beyond it, a new segment |
| Clock jitter accepted between chunks | ±2 ms |
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
| The streamed window closes | The sound's stream ends ("Audio capture ended: …"); the device asks for the Desktop 2 s later (today's rule) and the sound follows |
| The app has no window on screen (minimized) | Still captured: the filter is the app's (P5) |
| A window on the virtual display | The same app filter on the main display (P5) |
| Two displays, the Desktop | Every app's sound, whatever the display (per app; P5) |
| The app goes quiet | Silent packets (3 KB/s) if ScreenCaptureKit keeps delivering; if it stops, the device plays out and fades, and a chunk after 100 ms starts a new segment |
| The Mac's output device changes | ScreenCaptureKit's behaviour is not documented (P12). If the stream ends: one line and `audioNote`; Send Audio off and on starts it again |
| The Mac's volume muted | Not documented whether capture comes before the volume (P11) |
| FaceTime or a phone call on the Mac | Not heard: daemon sound (P4) |
| A keyframe in front of the sound | The need covers it (rule 2); the first one of a session may make one packet late (dropped, faded) |
| The picture drops frames and waits for a keyframe (a slow link), or restarts | The sound goes on; while no frames come, the picture's lag keeps its last value (rule 3) |
| The link stalls 2 s, then bursts | Packets past their time are dropped; playback returns to the delay by a jump (rule 12) |
| The Mac's wall clock steps | Rule 13: one jump |
| A move (AWDL → network, away → home) | Two connections for a moment: duplicates dropped (rule 7); the new connection resets the model, one jump at most |
| A device joins while sound runs | The format, then the next packet; its first packet is decoded and dropped, the next fades in |
| Two devices | Both get it; each mutes alone |
| A device muted | The Mac keeps sending; the device decodes nothing; unmuting places the next packet by time |
| Headphones pulled out of the device | Muted, and said (§7.4) |
| AirPods | The sound trails by their latency more; the console and the HUD say how much (Q7) |
| A call to the device | Interrupted, resumed after (§7.4) |
| The app goes to the background | The engine stops; back in front, the next packet starts it |
| Send Audio turned off (on the Mac or a device) | The stream stops; kind 16 says so; the button goes; the device plays out and idles |
| A device away | Its need starts at 150 ms and follows the link; frames drop first (§Decision) |
| A kind 28 of an unknown type or codec | Skipped |
| An older device, or an older host | §3.5 |

### 11. Test gates

**Hard rules for the implementing session:**
- **Never capture the Mac's sound.** No SCStream with `capturesAudio` outside Noah's P-list; the
  headless gates use the test tone and the harness. The implementing session never starts
  `Sill.app` or a host that is not synthetic.
- **Synthetic hosts and the harness only,** from `.build/release`, started from Python with
  `start_new_session=True`, killed by PID, none left running.
- **The Mac's video encoder.** The sound's gates run in the encoder-free harness (H5–H8). H2's
  parity runs use `SillHost --synthetic`, as every parity run has, and only while Sill.app has no
  device connected (`~/Library/Logs/Sill/Sill.log`, read only, has no `client ` line in the last
  minute); with `SILL_TEST_SOFTWARE_ENCODER=1` if the pointer branch has brought it.
- **The simulator plays sound on the Mac's speakers.** The test tone is quiet (−30 dBFS), and a gate
  plays at most 10 s of it. A simulator of its own, never the shared iPad Pro 13"; no `simctl io
  recordVideo`; no iOS Simulator control `attach`; screenshots with `xcrun simctl io <udid>
  screenshot`.
- **Never touch** `/Applications/Sill.app`, the `me.saffer.sill.mac` domain or Noah's iPad. App
  gates use the bare `SillMenuBar --synthetic`; `defaults delete SillMenuBar` afterwards.

**Headless (H): no permissions needed.**

| # | Check | Pass when |
|---|---|---|
| H0 | **Preflight** (no commit). Record the base. Kind 28 still free on every branch and worktree (`git grep` over every ref, and the plans' reservations); the pbxproj pairs free; the codec probe again on the build Mac | Recorded; ELD 480 and 512 give §Decision's F, P and end-to-end numbers within 1 ms |
| H1 | **Builds.** `swift build -c release`; iOS Debug and Release for the simulator | Only the known warnings |
| H2 | **The CLI byte for byte.** Base and new `SillHost --synthetic`: idle 35 s; with `sillclient.py PORT 8 desktop`; with `sillclient.py … --hello=0.6 --audio` (a hello that lists "aac-eld"); all again with `--direct-wireless`; digits masked, sorted | Identical; no `Audio` line and no `aud.` key; no kind 28 in the client's `kinds=` |
| H3 | **Pure checks, each with its mutants caught.** `audio-packetizer` (Sources/SillHost/AudioPacketizer.swift), at least 30 cases: F from the first chunk (480, 1024, 441 and 960 frames), stamps against the anchors (±1 µs), the gap rules at 1.9, 2.1, 99 and 101 ms and backwards, a format change, the flush, `AudioSourceRule`'s table; at least 10 mutants (`>` for `≥` at 100 ms, the priming's sign, a gap that starts no segment, the same pid restarting). `audio-playout` (iOSClient/AudioPlayout.swift), at least 40 scenarios on a simulated clock (a steady home link; a 40 ms burst every 4 s; ±100 ppm for an hour; host clock steps of ±1 s; a 2 s stall, then a burst; duplicates; a seq gap; a join mid-segment; a still window; a link away at 80 ± 50 ms; a picture 1 s late; AirPods +180 ms; mute and unmute) and 5,000 random runs, with the invariants: nothing plays before it arrives; no two packets overlap; the sound never leads the picture; after a disturbance under 40 ms the error falls at 1.9 ms a second or better until under 5 ms; at most one frame added or dropped a packet; at least 12 mutants (max for min in the floor, no dedupe, no guard, the late test's sign, the jump at 400 ms, no step test, no fades, the need not rising at once). Wire cases: `compatibility` (AudioFormat and the new fields round trip; `{}` decodes; unknown keys ignored; the old `Hello`, `StreamSettings` and `ClientStats` decode the new JSON) and `protocol` (type 2 serialized and parsed; every malformed payload gives nil and never traps; 1,000 random byte strings) | All pass; every mutant caught |
| H4 | **`audio-codec`** (a new check): Sources/SillHost/AudioEncoder.swift and iOSClient/AudioDecoder.swift in memory; the test tone through the encoder at F 480 and 512, each packet decoded at once | F and P as §3.2; with the first P frames dropped, each click lands at its stamp's sample ±2 frames; 5 s of the busy signal at 120–140 kbps; nothing but AudioToolbox linked |
| H5 | **The harness at home** (`Scripts/audio/`, step 4: the real StreamServer and sound files with the test tone and fake frames; no VideoToolbox, ScreenCaptureKit or CoreMedia). 60 s of Balanced-sized fake frames at 60 fps; `Scripts/audiocheck.swift` on the home door (a hello with "aac-eld"; it decodes and finds the clicks); the same run with Send Audio off | 100 ± 1 packets a second; no gap in seq; 60 clicks at whole host seconds ±1 ms; `net.dropped`, `net.sent` and the frames' age the same with and without sound, within run-to-run noise |
| H6 | **The harness away:** Scripts/pacing's `bottleneck.py` at 8 and 4 Mbps with 1.5 MB keyframes, and a 12 s dip to 0.5 Mbps | `aud.drop` 0 at 8 and 4 Mbps while `net.dropped` > 0 in the keyframe case; every packet's age at most the frames' age + 20 ms; in the dip, sound and frames arrive late together, and 2 s after it ends the packets' age is back |
| H7 | **Send Audio over the wire.** `sillclient.py --audio --set=sendAudio=1@3 --set=sendAudio=0@8 --expect=sendAudio=0` against a synthetic host started without `--audio` | The answers carry it; the first packet within 300 ms of the first answer, the last within 100 ms of the second; "Settings from sillclient: send audio off → on" and "… on → off"; no "Streaming …" line (the picture never restarted) |
| H8 | **Epochs and segments** in the harness: the tone paused for 50 ms, then for 500 ms (`SIGUSR1`), and a source change | 50 ms: the same segment, 5 packets of zeros; 500 ms: a segment start; the source change: a new epoch, its format before its first packet on every client |
| H9 | **Compatibility.** The base's `sillclient.py` against an `--audio` host; the base's StreamProtocol (swiftc) against a kind 28 header and the new kind 16; the new device decoder against the base host's messages | No kind 28 to the old client; `.unknown`; the old kind 16 decode ignores the keys; nothing new decoded |
| H10 | **Previews.** The bare app's `-SillRenderPreviews` before and after | Only the Streaming and Permissions panes, menu.txt's Send Audio and the new `sound` card sample differ |
| H11 | **Hard rules** (grep) | No `captureMicrophone`, `AudioHardwareCreateProcessTap`, `updateConfiguration` or `assumeIsolated` in Sources/SillHost; no `UIBackgroundModes` in the iOS Info.plist; `HostConfig.standard` has `sendAudio: false`; the sound's send path never calls the counting `send(_:to:isFrame:)`; no AVFoundation or CoreMedia import in AudioEncoder, AudioPacketizer, AudioPipeline or SyntheticAudio; no render block in iOSClient |
| H12 | **Cost.** The harness host's CPU (`ps`, 60 s) with and without sound | At most 1.5 percentage points more |

**The harness** (`Scripts/audio/`, step 4) is built the way Scripts/pacing/build.sh builds its host:
a throwaway package under `.build/audio` with StreamServer.swift and its neighbours, the sound's
host files (AudioPipeline, AudioPacketizer, AudioEncoder, SyntheticAudio) and a `main.swift` that
feeds fake frames and runs the test tone, both doors. Like the pacing harness, it refuses a binary
that links VideoToolbox, ScreenCaptureKit, CoreMedia or AVFoundation. `Scripts/audiocheck.swift`
is its device: StreamProtocol and iOSClient/AudioDecoder.swift, a hello with "aac-eld", every
kind 28 decoded, the clicks found, one line a second and a summary at the end.

**Simulator (S):**

| # | Check |
|---|---|
| S1 | **Photos.** `-SillSound on` and `muted` at 1000x710, 710x1000, 500x710 and 710x500, and at xxLarge text; `-SillSettingsCase sound` and `soundnote` at the four sizes. The button in every bar, the strip one button narrower, the row after the closing footnote. Send Noah the sheet |
| S2 | **Live.** `-SillLive 1 -SillConnect 127.0.0.1:P` against the harness's home door: the console's format and engine lines; within 3 s "late 0" and a steady "behind the picture". A headless tap on Sound: "engine off"; again: on, one jump. `sillclient.py --set=sendAudio=0@…` as a second client: the button goes, and "idle, engine off" 10 s later. At most 10 s of tone |
| S3 | **A move.** `-SillMoveTest 1` with sound: no double packets (the console's dedupe count), at most one jump at the hand-over |

**Noah's devices (P), handed over at the end:** the iPad mini, the Mac, headphones, an iPhone for
P6 and P14.

| # | Check |
|---|---|
| P1 | **On.** Send Audio from the Mac's menu; Music playing, its window streamed: the iPad plays it, and so does the Mac (the menu's subtitle says so). After a relaunch `defaults read me.saffer.sill.mac sendAudio` is 1 |
| P2 | **The first buffer.** Send the log's "first buffer … frames … ms after its time stamp" line and the encoder's line (480 or 512), and say whether the 2×2 picture was taken |
| P3 | **Per app.** Two Safari windows, a video playing in one; stream the other: the video's sound plays. The Desktop: every app's sound |
| P4 | **Helpers and daemons.** A YouTube video in Safari and in Chrome, Spotify, a FaceTime call (expected silent), Mail's new-mail sound: which are heard |
| P5 | **Off screen.** Music minimized while the Desktop streams; a window on the virtual display; a second display |
| P6 | **Sync.** A clapper or lip-sync test video on the Mac, streamed; film the iPad at 240 fps with the iPhone and count the frames between the flash and the click. The speaker, then AirPods; the console's "behind the picture" at the same time |
| P7 | **Restarts keep the sound.** With music: rotate, cycle Aa, switch 60 and 120 fps, change Quality, turn the virtual display on and off: no gap. Another Music window: no gap. Another app's window: a short gap and a fade in |
| P8 | **Mute.** The bar's Sound: muted at once, the Mac still playing; relaunch: still muted; unmute: sound within about 0.1 s. VoiceOver reads "Sound from ‹Mac›, On" |
| P9 | **Interruptions and routes.** A FaceTime call to the iPad, Siri, AirPods in and out (out mutes and says so), wired headphones |
| P10 | **Away.** Tailscale over the iPhone's hotspot at Low: the sound goes on while `net.dropped` counts; the `client …` line's "sound … behind" |
| P11 | **The Mac muted** (its volume): does the iPad still hear it? |
| P12 | **The Mac's output changed** mid-stream (headphones into the Mac, AirPods on the Mac): the sound goes on, or one "Audio capture ended" line, and Send Audio off and on brings it back |
| P13 | **An hour** of music: no drift (the console's error within ±5 ms and no jump after the first minute); Sill.app's CPU in Activity Monitor with sound on and off |
| P14 | **Two devices** (the iPad and the iPhone): both play; muting one leaves the other |
| P15 | **Mixed builds.** This iPad with 8b0d418's Sill.app: no row, no button, no sound. 8b0d418's iPad with this Sill.app and Send Audio on: nothing changes for it |
| P16 | **The device's silent mode and volume buttons:** it plays on silent, as a video app does (Q4); the volume buttons set Sill's volume |

### 12. Implementation order and sizing (one commit per step; each passes its gates before the next)

Commit messages end with the session's attribution lines.

| Step | Commit | Files | Gates | Size |
|---|---|---|---|---|
| 0 | Preflight (no commit) | — | H0 | 1 h |
| 1 | "Protocol: kind 28, the Mac's sound" | StreamMessage.swift, Audio.swift (new), Compatibility.swift, HostSettings.swift, Viewport.swift; the `compatibility` and `protocol` cases | H1, H3 (wire), H9 (decode) | ½ day |
| 2 | "Host: the sound's blocks and stamps" | AudioPacketizer.swift (new) with `AudioSourceRule`; `Tests/checks/audio-packetizer` | H3 | ½ day |
| 3 | "Host and device: the AAC-ELD encoder and decoder" | AudioEncoder.swift (new); iOSClient/AudioDecoder.swift (new, not yet in the Xcode project); `Tests/checks/audio-codec` | H4 | ½ day |
| 4 | "Host: Send Audio, the sound's stream and its send path" | AudioCapture, SyntheticAudio, AudioPipeline (new); StreamServer, StreamCoordinator, HostConfig, DeviceSettings, HostStatus; the CLI's `--audio`; `sillclient.py --audio` and `sendAudio`; `Scripts/audio/` and `Scripts/audiocheck.swift` | H1, H2, H5–H9, H11, H12 | 2 days |
| 5 | "Sill.app: Send Audio" | HostSettings, DebugHooks, StatusItemController, SettingsPanes, StatusText, the previews | H1, H10 | ½ day |
| 6 | "iOS: the playout model" | AudioPlayout.swift (new); `Tests/checks/audio-playout` | H3 | 1½ days |
| 7 | "iOS: the Mac's sound" | AudioOutput.swift (new) and the three pbxproj pairs; StreamClient, the bars, the panel, the ledger, MockCatalog, ContentView, DiagnosticsHUD | H1, S1–S3 | 2 days |
| 8 | "docs: the Mac's sound on the device" | This plan's Results; CLAUDE.md (the current step, Layout, Build and run, Untested for Noah: P1–P16); README (Send Audio); Tests/checks/README.md's table; `ci.yml`'s mutants matrix; BRIEF.md (audio in v2) | — | ¼ day |
| 9 | Review and hand-over | Three lenses: the sync model and its constants; the host's threads and the picture's isolation (nothing of the sound on the picture's queues or counters); the device's session, lifecycle and UI. A "Review fixes" commit if needed, then H5–H8 and S2 again; hand P1–P16 to Noah. **Stop there** | — | ½–1 day |

- **In all:** about 8–9 days of focused work, most of it the two pure models and their checks.
  Noah's P-list: about 2 hours.
- **Rough size:** the host about 900 lines (Audio.swift 150, the packetizer 200, the encoder 180,
  the capture 150, the tone 80, the pipeline 250, about 150 in existing files); Sill.app about 80;
  the device about 1,000 (the playout 400, the decoder 120, the output 350, about 150 in existing
  files); checks and harness about 1,500.
- **Rebases.** The pointer branch (kind 26, StreamServer's tick, StreamClient) and menu-bar-mirror
  (24, 25, 27) touch the enum, StreamClient and ContentView's comment. If the remote bundle's
  `MessageReader` lands first, kind 28 arrives through it; nothing else changes.

### 13. Hard rules (for every step)

- **The picture first.** Nothing of the sound runs on `sill.capture` or `sill.encode`. The sound
  never counts in `inflight`, `inflightFrames` or the drain eviction. A failure of the sound never
  stops, restarts or delays the picture. `follow` runs after the picture's select.
- **Never reconfigure a running SCStream.** The sound's stream is started and stopped whole;
  `showsCursor` stays false everywhere.
- **No new permission.** Never `captureMicrophone`, never a Core Audio tap, no
  `NSAudioCaptureUsageDescription`; no microphone and no `UIBackgroundModes` on the device.
- **Never `MainActor.assumeIsolated`** in core code. ScreenCaptureKit calls bounded (2 s).
- **The CLI's stdout byte for byte** without `--audio`, idle and streaming, whatever the devices'
  hellos.
- **Kinds 0–27 untouched.** 28 is the sound's (or the next free, H0).
- **No Swift on a real-time audio thread:** the player node schedules; Sill writes no render block.
- **Tests never capture the Mac's sound,** never touch `/Applications/Sill.app`,
  `me.saffer.sill.mac` or Noah's iPad, and never use the hardware encoder while Noah streams.
- **Apple frameworks only** (AudioToolbox, AVFAudio, ScreenCaptureKit). New iOS files need their
  four pbxproj entries by hand. Swift 5 language mode.

### 14. What comes later

- **A quiet Mac.** A Core Audio process tap (macOS 14.2 and later) with `CATapMutedWhenTapped` in
  place of ScreenCaptureKit's sound, so the Mac goes silent while a device plays; it needs its own
  permission ("System Audio Recording Only"). Then Send Audio could be on by default (Q1, Q6).
- **Sound first away, for real.** Sill holds frames back and hands the connection only a bounded
  amount, so sound overtakes queued video: the send queue the remote bundle left out too.
- **Opus** (Q2) and a lower bitrate away (Q3).
- **The picture delayed for Bluetooth** (Q7), if anyone asks.

---

## Open questions for Noah (the implementer uses the default unless Noah says otherwise)

1. **Send Audio's default.** Default: **off** in the first release with sound, on the Mac and in the
   CLI; flip it after P1–P16, as with the virtual display. The Mac keeps playing its own sound, so
   on by default doubles every sound for a device beside the Mac.
2. **The codec.** Default: **AAC-ELD** (10 ms, 128 kbps). Opus at 10 ms is as fast and royalty-free,
   costs about twice the encode CPU and five times the decode, and was not verified on macOS 14 or
   iOS 17 here. A later switch is one `codec` string.
3. **The bitrate.** Default: **128 kbps** everywhere (4 % of Low). The alternative: 96 kbps away
   from home.
4. **The session.** Default: **`.playback` with `.mixWithOthers`**: it never stops the iPad's own
   music, and plays on silent like a video app. Alternatives: `.playback` alone (Sill's sound
   pauses other audio, like a video app); `.ambient` (obeys the silent switch, like a game).
5. **Mute.** Default: **per device, local, remembered.** The alternative: per Mac.
6. **The Mac keeps playing.** Default: **say so** (the menu's subtitle, the footers), and a device
   beside the Mac is muted by its user. The alternative is §14's tap, with a permission of its own.
7. **Bluetooth headphones.** Default: **the sound trails by their latency** (150–250 ms). The
   alternative delays the picture to match, against "latency beats quality".
8. **Devices turning it on.** Default: **yes**, like the other stream settings: saved on the Mac,
   from home or away. The alternative: only the Mac's own menu and Settings.
9. **"· sound" on the Mac's card.** Default: **shown** in the source row while a device gets sound.
   The alternative: the menu's check mark only.
10. **The outer display's portrait bar.** Default: **the Sound button there too** (one thumbnail
    fewer). The alternative: every other bar, and a row in the panel there.
11. **Headphones unplugged.** Default: **mute and say so**, iOS's pause for a live feed. The
    alternative: keep playing on the speaker.
12. **The kind number.** Default: **28**, leaving 24, 25 and 27 to the Mac menu bar sketch and 26 to
    the pointer. If another branch takes it first, the next free.
13. **When.** Default: **after v1 ships** (BRIEF.md keeps audio out of v1). The alternative: now.
14. **One stream or two.** Default: **a stream of its own for the sound**, so rotation, Aa and
    settings never cut it. The alternative, `capturesAudio` on the picture's stream, is less code
    and drops the sound at every restart.
15. **Idle.** Default: **the device's engine stops after 10 s without a packet.** The alternative
    keeps it running while connected: no ~50 ms start after a long silence, more battery.
