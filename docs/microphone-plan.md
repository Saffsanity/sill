# The device's microphone on the Mac — the plan

2026-11-18, written read-only against main at 4e00c805 (0.6.2), pull request #191 at 70a127f0 (addhumal; issues #190
and #214), the SDK headers of Xcode 27.1 and Apple's documentation pages. Built on branch `microphone` (pull request
#415), on #394's SillAudio, which was this plan's commit 1. #191, which played the device's microphone through the
Mac's speakers, is redone, not built on: what it gave is kind 43's two types the other way and the name Share
Microphone. The assessment it rests on is kept beside the plan in the handoff folder. The "Progress" section at the
end says what is built.

## 0. As settled on 2026-11-18, over this plan's first draft

The overview of the night's six plans settled where they disagreed. Where it differs, it wins, and the code follows it:
- **One rule for both sensors (the overview's decision 4).** The device records only while an app on the Mac uses
  Sill Microphone, Sill is in front (never in the background or Picture in Picture), and its switch was turned on
  since Sill last launched; the switch stays on through reconnects and moves. One device at a time, the last one
  turned on: its first offer after the switch comes on carries a `claim`. So kind 48's type 1 (kind 43's
  AudioFormat keys) carries two keys of its own beside them, `claim` and `pause`, and is the device's offer, and
  with a codec also an epoch's format; type 3 is the end (Share Microphone off). Kind 16's per-connection
  `MicrophoneState` says what the Mac does with this connection's microphone, with the camera's words where they
  mean the same: `off`, `notReady` (Sill Microphone not set up: the plan's `setup`), `unpaired`, `refused`, `idle`
  (the plan's `ready`: it may offer; no app uses Sill Microphone yet), `another` (the plan's `other`, with the
  holder's `device`), `inUse`; an unknown one read as `off`. While locked the list leaves `microphone` out and kind
  16 has none (the plan's `locked`): the device's lock words say why.
- **The window list's `microphone`** (#191's field): 1 is generation 1, 0 a Mac that has the receiving side with its
  switch off or Sill Microphone not set up; left out by older hosts, the CLI and a locked Mac. A device sends kind
  48 only while it says 1 or more (the overview's rule 1).
- **Unpaired devices are refused**, whatever Require pairing says (the camera's and files' rule, over this plan's §9).
- **The Mac's switch** is `deviceMicrophone`, "Use iPhone and iPad microphones", off in both the CLI and Sill.app (a
  switch that installs something into macOS starts off); turning it on shows Sill Microphone's setup. Its place:
  Settings › Streaming, the section "Camera and Microphone (beta)" after Send audio.
- **The device's switch** is "Share Microphone (beta)", in This ‹device› after the clipboard's rows (the overview's
  §2.2), not under Mute; it goes into the whole-screen Settings pane (#393) once that lands.
- **Kind 48** is the microphone's; 45 the pen's, 46 the camera's. The iOS project's IDs are A190–A192 with their F
  twins (A192 checked free on main and on every open pull request).
- **The device's auto-lock**, `DeviceIdlePolicy.Uses`, gains the microphone with the camera, recording and transfers
  (the overview's §2.3); not in the first part.

Noah, 2026-11-18: "Work on … microphone passthrough to Mac with toggle". He asked for it first on
2026-11-02 (sill-handoff/roadmap-1.0.md). He has not commented on #190, #214 or #191. On #328
(2026-11-10), about building transcription into Sill: "Cool app but don't think this is a space I want
**_Sill_** to operate in." So Sill carries the sound and never transcribes it.

## 1. What it is, in a user's words

"I turn on **Microphone** in Sill's settings on my iPad, and my Mac has a microphone called **Sill
Microphone** that hears what my iPad hears. In Zoom on the Mac I choose Sill Microphone, and the people
in the call hear me through my iPad, from the sofa or from another city, while Sill plays the call to me
with Send Audio. The same for a recording in QuickTime Player or dictation on the Mac. I turn it off, or
leave Sill, and nothing more leaves the iPad."

What it is not: the Mac's speakers playing the iPad (#191's behaviour), transcription (#328), several
devices mixed into one microphone, or a microphone while Sill is in the background (open question 8).

## 2. What Apple documents (checked 2026-11-18)

**The Mac: how sound from an app becomes an input other apps can choose.**

| Way | What Apple says | Cost to the person | Verdict |
|---|---|---|---|
| **Audio Server Plug-in** (HAL plug-in) | `CoreAudio/AudioServerPlugIn.h`: "The plug-in bundle is installed in /Library/Audio/Plug-Ins/HAL"; it "operates in its own process separate from the system daemon"; "the host process is sandboxed"; it may talk to other processes only through Mach services listed in its Info.plist; its IO "operations are performed on a real time thread on a deadline". The sample "Creating an Audio Server Driver Plug-in" is "Written in standard C": "Install the sample's .driver bundle to /Library/Audio/Plug-Ins/HAL and reboot your computer." | An administrator's password once; a restart of the Mac's audio server or the Mac, which interrupts every app's sound for a moment | **Chosen** |
| AudioDriverKit (a driver extension) | Its sample page: "When creating a virtual device, best practice is to use an Audio Server Driver Plug-in instead … AudioDriverKit only supports physical audio devices." It needs DriverKit entitlements that Apple grants on request (`com.apple.developer.driverkit`, `.family.audio`, `.userclient-access`) | An administrator's approval in System Settings | Not for a virtual device |
| Core Audio taps and a public aggregate device (macOS 14.2+) | "Taps can be public (visible to all users), or private"; an aggregate device can be "published to the entire system" (AudioHardware.h). But: "The first time you start recording from an aggregate device that contains a tap, the system prompts you to grant the app system audio recording permission." | Every app that records from it is asked for System Audio Recording and shown as recording the computer's sound; Sill needs that permission too | Not a microphone a person would accept |
| Play through the Mac's speakers (#191) | — | Nothing | Not what anyone asked for |

Two more facts the design rests on: a device can be hidden, "not included in the normal list of devices
… nor can it be the default device. Hidden devices can only be discovered by knowing their UID"
(`kAudioDevicePropertyIsHidden`, AudioHardwareBase.h); and a plug-in learns each client's process ID and
bundle ID (`AudioServerPlugInClientInfo`, AudioServerPlugIn.h). Restarting the audio server: vendor
documentation uses `sudo killall coreaudiod` on macOS 14.4 and later; `launchctl kickstart` of it stopped
being allowed in 14.4 (developer forums thread 748228). Not verified on macOS 27 (P0).

**The device: capturing the microphone without Swift on a real-time thread.**
- `installTap(onBus:bufferSize:format:…)`: "the requested size of the incoming buffers in sample frames.
  Supported range is [100, 400] ms" (AVAudioNode.h). So a tap delivers at least 100 ms at a time. The
  block-based variant is deprecated in the iOS 27 SDK in favour of the one with `error:`.
- `AVAudioSinkNode` receives "input audio on the audio IO thread"; its realtime-safe initializer is
  `__SWIFT_UNAVAILABLE_MSG("Swift is not supported for use with audio realtime threads")`. The project's
  rule (docs/audio-plan.md §13): no Swift on a real-time audio thread. So the tap, with its 100 ms.
- Voice processing (`AVAudioInputNode.setVoiceProcessingEnabled`, AVAudioIONode.h): "the input node does
  signal processing on the incoming audio (taking out any of the audio that is played from the device at a
  given time from the incoming audio)"; "requires both input and output nodes to be in the voice
  processing mode"; "only supported when the engine is rendering to the audio device and not in the manual
  rendering mode". It ducks "other (i.e. non-voice) audio", configurable down to `.min`.
- `.voiceChat` mode without voice processing (AVAudioSessionTypes.h): "Chat-specific signal processing
  such as echo cancellation or automatic gain correction will not be loaded", and output plays quieter.
  It "Has the side effect of setting AVAudioSessionCategoryOptionAllowBluetoothHFP".

**App Review.** 2.5.14: "Apps must request explicit user consent and provide a clear visual and/or
audible indication when recording … This includes any use of the device camera, microphone". 2.5.4:
"Multitasking apps may only use background services for their intended purposes: VoIP, audio playback,
location, task completion, local notifications, etc." 5.1.1(ii): "Ensure your purpose strings clearly and
completely describe your use of the data."

Not documented, so each is a device test (§10.4): whether voice processing in one engine cancels sound
another engine of the same app plays; how large a voice-processing tap's buffers really are; how long a
start takes; what macOS 27 needs to load a new plug-in.

## 3. Decision

### 3.0 Who decided what

- **Noah:** a microphone to the Mac, with a toggle (2026-11-18); Sill never transcribes (#328,
  2026-11-10); the sound's controls are switches in the device's Settings panel, no Sound button in a bar
  (2026-10-27); Sill never stops another app's music (his constraint for Picture in Picture).
- **Apple's documentation:** an Audio Server Plug-in for a virtual device; AudioDriverKit only for
  physical ones; taps make the recording app ask for System Audio Recording; no Swift on audio real-time
  threads (the iOS 27 SDK's message, already the project's rule).
- **This plan, each open below until Noah answers (§15):** the plug-in and its setup, C for it, the
  switches' defaults and place, the lock, the background, two devices, the auto-lock, AirPods, the delay,
  the shared code, the redo of #191, the kind number.

### 3.1 In one paragraph

Sill for Mac ships **Sill Microphone**, an Audio Server Plug-in inside Sill.app that the person sets up
once from Sill's Settings (a Terminal command with Copy, as the firewall's; an administrator's password;
a restart of the Mac's sound). It publishes one input device, "Sill Microphone", which every app on the
Mac can choose, and one hidden output device that only Sill plays into. On the device, **Microphone** is a
switch in the Settings panel right under Mute, off at every launch. With it on, while a Sill window
streams in front and the Mac takes it, the device captures its microphone with iOS's voice processing
(echo cancellation of what the device plays), encodes it as AAC-ELD mono at 64 kbps in 10 ms packets
(kind 43's codec, the other way), and sends it on a new kind. The Mac places it with kind 43's playout
model (the floor, the jitter cover, drift by single frames) and plays it into the hidden device, so Sill
Microphone hears the device about 150 ms after the person speaks. One device at a time: the one that
turned it on last. Never while the Mac is locked or another user is on it, never from a removed device,
never in the background. The Mac's **Microphones from devices** switch (on in Sill.app, once Sill
Microphone is set up) lets the Mac's user turn the whole thing off; the menu's card says which device's
microphone is in use.

### 3.2 Sill Microphone (the plug-in, `Sources/SillMicrophone/`, C)

- **Two devices, one clock.** "Sill Microphone" (UID `me.saffer.sill.microphone`): input only, one
  channel, 48 kHz Float32, visible, may be the default input. "Sill Microphone Feed" (UID
  `me.saffer.sill.microphone.feed`): output only, the same format, hidden (`kAudioDevicePropertyIsHidden`
  1). Both run on the plug-in's one zero-time-stamp clock, so the feed's writes and the microphone's reads
  never drift apart; a ring buffer of 1 s in the plug-in carries one to the other at a fixed offset (the
  IO buffer plus a safety offset of 2 ms), zeros where nothing was written.
- **Only Sill feeds it.** IO on the feed counts only from a client whose `mBundleID` is
  `me.saffer.sill.mac` (`AddDeviceClient`); any other client's writes are dropped and the microphone
  stays silent. A bundle ID can be imitated by a local process; the residual risk is named in §9.
- **Nothing else.** No Mach services, no network (`AudioServerPlugIn_Network` absent), no files, no
  custom properties but its version (`CFBundleVersion`, Sill's build). It knows nothing of devices,
  pairing or the network; Sill.app does all of that.
- **From Apple's sample**, standard C, its license file kept beside it (Apple's sample code licence,
  compatible with Apache-2.0). Never from a GPL-licensed driver. The real-time path is C, as Apple's is;
  Swift stays off real-time threads (open question 2).
- **Built** by `Scripts/make-app.sh` with clang for arm64 and x86_64 into
  `Sill.app/Contents/Library/Audio/Sill Microphone.driver` (bundle ID `me.saffer.sill.microphone`), signed
  before the app with the app's identity, notarized with it; `release.sh`'s `check_signature` reads every
  slice of it too. Where exactly nested code may sit is checked with `codesign --verify --strict --deep`
  in commit 5's gates (§12).
- **Set up** from Settings › Streaming: Sill shows the command and never runs it (it needs an
  administrator), as Settings › General does for the firewall:
  `sudo ditto "<running Sill.app>/Contents/Library/Audio/Sill Microphone.driver" "/Library/Audio/Plug-Ins/HAL/Sill Microphone.driver" && sudo killall coreaudiod`.
  Removed with `sudo rm -rf "/Library/Audio/Plug-Ins/HAL/Sill Microphone.driver" && sudo killall coreaudiod`.
  An Installer package opened from Settings is the alternative (open question 3).
- **Its state, read-only** (`SillMicrophoneDevice`): **missing** (no bundle in /Library), **not loaded**
  (the bundle there, the feed device not found: the audio server not restarted yet), **old** (its
  `CFBundleVersion` lower than the copy inside this Sill.app), **set up**. A listener on the system's
  device list notices a setup or a removal while Sill runs. Sill plays into the feed only when it is set
  up; it never plays the device's microphone anywhere else, and with no feed it plays nothing.
- **Updates.** Update Now replaces Sill.app, never /Library. The contract between them is only the two
  UIDs and the format, so an older plug-in keeps working; "old" is a note with the command, not a
  refusal.

### 3.3 The rule (`MicrophonePolicy`, pure, `Sources/StreamProtocol/MicrophonePolicy.swift`)

Both ends' rules and every word, as ClipboardPolicy holds the clipboard's; checked by
`Tests/checks/microphone`.

**On the device:**
1. **Sends** while all hold: the switch on; the permission granted; the session connected; the Mac's
   state for this connection (kind 16, §4) is `ready` or `inUse` and lists a codec the device makes; this
   window's scene foreground active (Picture in Picture does not count: open question 8); no audio
   interruption (a call); this window chosen (rule 2); not inside a move's fence or hold (rule 6).
2. **One window.** With several Sill windows (iPad), the one the person used last among those in front
   (`PictureInPicturePolicy.chosen`'s rule over DeviceIdlePolicy's last use), so two Macs never both get
   the microphone and one session never has two engines.
3. **The switch** is off at every launch and kept through reconnects and moves while Sill runs (open
   question 5); never in UserDefaults. A goodbye, Disconnect or a Mac that says `off`, `setup` or `locked`
   leaves it on but sends nothing.
4. **The permission** is asked only when the person turns the switch on while the Mac takes it; never at
   launch or at a connection. Refused: the switch goes back off, with the words and a button to Settings.
5. **Stops at once** when any of rule 1 fails: the engine leaves voice mode or stops, a type 3 end goes
   if the session is up, and the iOS indicator goes. Starts again with a new epoch when all hold.
6. **Moves.** A move's hand-over keeps the epoch: the device sends the format again as the first kind 48
   on the new connection, then goes on with the next seq (the Mac drops duplicates by epoch and seq).
   While a fence or a hold stands, microphone messages are dropped, never queued (`SessionLink`): stale
   sound is worth nothing; the next packet after carries a segment start.
7. **Never behind.** At most 200 ms of microphone audio unsent on the session's connection (counted by
   `contentProcessed` completions); past it a message is skipped and the next starts a segment.
8. **Echo.** While the microphone is on, this window's sound engine runs in voice mode (§3.5), so iOS
   takes what the device plays, the Mac's sound included, out of the microphone.
9. **Auto-lock.** While the microphone sends, the device's auto-lock hold (DeviceIdlePolicy, #230) counts
   it as use, so a call where the person only talks does not lock the device (open question 10).

**On the Mac:**
1. **Takes** a device's microphone while all hold: Microphones from devices on; Sill Microphone set up
   (or a test host's sink); the lock's reading unlocked at the message's arrival and now
   (`LockPolicy.Request.microphone`: refused at a locked screen and off console, open question 7); the
   session not revoked.
2. **One device.** A format from another connection with a new epoch takes it over (the device that
   turned it on last); the previous one's kind 16 says `other`, with the new one's name, and it stops.
   The same device's new connection after a move (the same paired key, or at a plain door the same hello
   name and model) takes over silently, keeping the epoch.
3. **Limits.** A format at most 4 KB and a packets message at most 16 KB (AudioMessage.parse's caps); at
   most 1.5 s of audio accepted per second per connection, measured over 2 s; at most 1 s of sound
   queued for the feed (past it, one jump forward); a format that does not decode, more than 6 formats a
   minute or a codec the Mac does not take: that connection's microphone refused for a minute, one line.
4. **The end**: a type 3, the connection leaving, a revocation (at once, `clientRevoked`), a lock, the
   Mac's switch off, or 2 s without a packet: the feed plays out what it holds, fades over 5 ms, and plays
   silence; the card and the log say so.
5. **Never anywhere else.** No feed device, no sound: the Mac's speakers never play a device's
   microphone, and Sill writes it nowhere (a test host's TEST ONLY file excepted).

### 3.4 The sound: kind 43's pieces, the other way

- **Codec:** AAC-ELD, 48 kHz, **mono**, 480 frames a packet (10 ms), priming 240, **64 kbps** (the
  converter's nearest, read back). Ten packets ride in one message, the tap's 100 ms (AudioPackets
  carries 1–255): ten messages a second, about 70 kbps with Sill's headers.
- **Stamps:** each packet's capture time on the device's wall clock (the tap's host time converted as it
  is sent, as the Mac's sound converts ScreenCaptureKit's); the Mac never needs the offset between the
  clocks: kind 43's floor (§7.2 of docs/audio-plan.md) does it.
- **The playout on the Mac** is `AudioPlayout` in its microphone mode: no picture guard (no frames are
  fed), the jitter cover starting at 110 ms at home (a tap buffer and a packet; 150 ms away) instead of
  40, the feed engine's IO buffer and its output latency in the need, every other rule as for the Mac's
  sound: the floor over 10 s, late packets dropped and the cover raised, drift by single frames, jumps over
  40 ms, a segment's priming dropped, dedupe of the last 256, fades.
- **Shared code** (open question 13 has the alternative): AudioEncoder, AudioDecoder, AudioPacketizer
  and AudioPlayout move into a new SwiftPM library target `SillAudio` (`Sources/SillAudio/`,
  AudioToolbox and Foundation only, public API), a product for iOS and macOS beside StreamProtocol, which
  SillHostCore and the iOS app both link. The encoder and decoder take a channel count; the playout takes
  its mode. The first commit moves them with no change in behaviour.

### 3.5 The device's audio session and engine

- **One owner.** `SharedSession` (AudioOutput.swift) holds two needs, playing (each engine, Picture in
  Picture's hold) and recording (the microphone), and sets the category from both under its lock:
  playing alone, `.playback` with `.mixWithOthers` as today; recording, `.playAndRecord`, mode
  `.voiceChat`, options `.mixWithOthers`, `.defaultToSpeaker` and `.allowBluetoothHFP` (open question 11).
  It deactivates only when nobody plays or records. `prepareCategory` (Picture in Picture) keeps a
  recording category while the microphone records. Nothing else in the app sets the category.
- **One engine per window.** `SoundEngine` gains a voice mode: voice processing on (both IO nodes), a tap
  on the input node, other audio ducked at `.min`. The window's AudioOutput builds its engine in voice mode
  while this window's microphone is on, and runs it while the Mac's sound is heard **or** the microphone is
  on; the Mac's sound plays through the same engine, which is what lets iOS cancel it from the microphone
  (rule 8). A change of mode rebuilds the engine: one jump in the Mac's sound, the playout's rule 12.
- **Manual rendering** (the simulator, DEBUG `-SillSoundSink manual`) has no voice processing and no
  input: the microphone there is the DEBUG test tone (`-SillMicSource tone`), fed to the same packetizer,
  encoder and send path. The simulator's microphone is the Mac's, which no test ever opens.
- **Interruptions, routes, the engine's configuration change, a media services reset:** AudioOutput's
  existing handling, plus: an interruption pauses the microphone (rule 1) until its end; a configuration
  change rebuilds the engine in the mode it had; headphones out keep the microphone (only the sound mutes,
  as today).

### 3.6 Where the time goes (estimates; P2 measures)

| Stage | Microphone |
|---|---|
| The tap's buffer (documented minimum) | 100 ms |
| Voice processing, conversion, AAC-ELD's priming (240 frames) | about 5–10 ms |
| The link at home | 2–10 ms |
| The Mac's playout: one packet, the IO buffer, 2 ms (the tap's spread is in the stamps) | 15–25 ms |
| The feed engine's IO buffer and the plug-in's loopback | 10–20 ms |
| **Mouth to Sill Microphone** | **about 130–170 ms** |

The meeting app adds its own path. The tap's 100 ms is the price of keeping Swift off the real-time
thread; a small real-time piece in C on the device would bring it near 20 ms (open question 12).

## 4. Protocol

**Kind 48** (proposed: 45 is held by #191 and by three Apple Pencil pull requests, #175, #381 and #382;
46 by #193's camera and #175's cursor kind; 47 is main's; 60 and 61 are #195's; 48–59 are free on every
open pull request on 2026-11-18. `next/OVERVIEW.md` assigns the number; the preflight checks every ref
again.)

```swift
    // The device's microphone (Microphone.swift), after 45 and 46, which open pull requests hold, and
    // the Desktop's 47. Older hosts map it to `.unknown` and skip it; none is ever sent one.
    case microphone = 48     // device → host: MicMessage — this device's microphone: a format (JSON
                             // AudioFormat), packets (binary AudioPackets, kind 43's layouts), or its end.
                             // Only while this connection's kind 16 says `microphone.state` "ready" or
                             // "inUse" and lists the codec
```

`Sources/StreamProtocol/Microphone.swift` (new; the iOS app gets it through the package):

```swift
/// Device → host (kind 48). The first byte says what follows; a type this build does not know is skipped.
public enum MicMessage: Hashable, Sendable {
    /// Type 1: kind 43's AudioFormat JSON: codec "aac-eld", sampleRate 48000, channels 1,
    /// framesPerPacket 480, primingFrames 240, bitrate 64000, epoch, cookie; source and app unused.
    case format(AudioFormat)
    /// Type 2: kind 43's AudioPackets layout, byte for byte (epoch, seq, the segment flag, 1–255 packets).
    case packets(AudioPackets)
    /// Type 3, the single byte 3: this device stopped its microphone.
    case end
    /// Types 1 and 2 through AudioMessage.parse (its 4 KB and 16 KB caps); type 3 only as exactly one
    /// byte; nil for anything else. Never traps.
    public static func parse(_ payload: Data) -> MicMessage?
    public func serialized() -> Data
}

/// Kind 16, per connection (HostSettingsState.microphone): what this Mac does with this device's
/// microphone. Nil from hosts before it. Strings, never enums: a value a device does not know reads as
/// "off" with the generic words.
public struct MicrophoneState: Codable, Hashable, Sendable {
    /// "ready" (takes it when it comes), "inUse" (this connection's is the one in use), "other" (another
    /// device's is), "off" (Microphones from devices off), "setup" (Sill Microphone not set up or not
    /// loaded), "locked" (the Mac locked or another user on it), "refused" (this connection's, for a minute).
    public var state: String?
    /// With "ready" and "inUse": the codecs the Mac takes, best first, `["aac-eld"]`.
    public var codecs: [String]?
    /// With "other": the device in use, SafeText.label, at most 64 characters.
    public var device: String?
}
```

- `HostSettingsState` (HostSettings.swift) gains `microphone: MicrophoneState?`, this connection's own,
  like `away`, `link` and `sessionPaired`. The Mac sends kind 16 to a connection whenever its microphone
  state changes (a takeover, a lock, the switch, a setup), at most four a second as today.
- No new field in the hello or the window list. The window list stays as it is, locked or not.
- **Compatibility.** An older device: never sees kind 48's state, sends nothing. A new device with an
  older Mac: no `microphone` in kind 16, so the row says "Update Sill on ‹Mac› to use this." and sends
  nothing. A new device with a Mac whose switch is off or that lacks Sill Microphone: the state says so.
  `sillclient.py` from before: never sends kind 48.
- **Rules for later** (join the floor once a public build carries it): kind 48's three types and their
  layouts, AudioFormat's fields as used here, `MicrophoneState`'s fields and values, the codec string;
  a new codec is a new string in `codecs`, a new layout a new type. A host sends no microphone kind ever.
- **The checks that name kinds** (`compatibility`, `protocol`, `pointer-control`, `display-wake`): 48 is
  `microphone`, 45 and 46 still unknown; the renumbering mutants land on 250–254.

## 5. Files

### 5.1 The shared target (`Sources/SillAudio/`, new; commit 1)

| File | Change |
|---|---|
| `AudioEncoder.swift` (from Sources/SillHost) | `public`; `channels` and `bitrate` at init (1 or 2; the Mac's sound keeps 2 at 128 kbps) |
| `AudioDecoder.swift` (from iOSClient) | `public`; channels from the format |
| `AudioPacketizer.swift` (from Sources/SillHost) | `public` (it already takes any channel count) |
| `AudioPlayout.swift` (from iOSClient) | `public`; `Mode.sound` (today's) and `Mode.microphone` (no picture guard, the starting cover 110/150 ms) |
| `Package.swift` | the target and a library product `SillAudio`; SillHostCore depends on it |
| `iOSClient/Sill.xcodeproj` | the product added to the package dependency; AA01 and AA02's four entries each removed |
| `Scripts/audio/build.sh`, `Scripts/audiocheck.swift`, `Tests/checks/audio-codec`, `audio-packetizer`, `audio-playout` | the new paths; behaviour and counts unchanged |

### 5.2 Wire and policy (`Sources/StreamProtocol/`)

`Microphone.swift` (new, §4), `MicrophonePolicy.swift` (new, §3.3 and §8: the device's and the Mac's
rules, the limits as constants, `Copy` with every word), `StreamMessage.swift` (kind 48),
`HostSettings.swift` (`HostSettingsState.microphone`).

### 5.3 The Mac's host (`Sources/SillHost/`)

| File | What |
|---|---|
| `MicrophoneReceiver.swift` (new) | The queue `sill.mic`: `MicGate` (a lock-protected snapshot, read on the network queue: the owner, whether the Mac takes it, the lock's reading), parse, dedupe, a seq gap's reset, the decoder, AudioPlayout in microphone mode, the 2 s silence end, the per-connection rate, Stats `mic.in`, `mic.late`, `mic.drop`, `mic.refused`, `mic.gap` |
| `MicrophoneOutput.swift` (new) | AVAudioEngine on `sill.mic` whose output unit's current device is the feed (found by UID), a player node and a buffer pool as AudioOutput has, the configuration change; `DrySink` (a test host's count, `mic.dry`) and the TEST ONLY `FileSink` (a WAV of exactly what would be played, 48 kHz mono Float32); never the default output |
| `SillMicrophoneDevice.swift` (new) | Read-only: the bundle in /Library and its version, the two devices by UID, the state (missing, not loaded, old, set up), the two commands, a listener on the device list, whether an app is using the microphone (`kAudioDevicePropertyDeviceIsRunningSomewhere`) |
| `StreamServer.swift` | Kind 48 on the network queue: after the revoked rule (which already drops it), `onMicrophone(payload, arrival, client)` straight to the receiver, never `onMessage` and never the main actor; a format from a connection that is not the owner goes to the coordinator for a decision |
| `StreamCoordinator.swift` | Owns the receiver; the owner rule; the gate updated on every change (the switch, setup, the lock, a takeover, a departure, `clientRevoked`); kind 16's per-connection `microphone`; the status; the log lines |
| `LockPolicy.swift` | `Request.microphone`, `Refusal.microphone`: refused at `screenLocked` and `offConsole` (the off-console view too), taken unlocked; `lockDecision` maps kind 48's formats; the gate refuses packets by the reading at their arrival |
| `DisplayWake.swift` | Kind 48 is never a person (a continuous stream; a call app keeps its own display awake) |
| `HostConfig.swift` | `deviceMicrophones: Bool`: `standard` false, `app` true; the Mac's alone (absent from StreamSettings, HostSettingsChange, DeviceSettings.accepted, `applying`, `restartNeeded`); applied at once; "microphones from devices on → off" |
| `HostStatus.swift` | `devices[i].microphone: Bool`; `microphoneSetup` |
| `TestHooks` | TEST ONLY, test hosts only, one "ignored" line elsewhere: `SILL_TEST_MIC_SINK=dry|file:<path>` (the host takes microphones into that sink as if Sill Microphone were set up and the switch on), `SILL_TEST_MIC_SETUP=missing|notloaded|old` |

No new CLI flag: SillHost has no bundle ID, so the plug-in would not take its feed; the CLI's stdout stays
byte for byte, and a CLI host's kind 16 carries no `microphone` unless a test sink is set.

### 5.4 Sill Microphone (`Sources/SillMicrophone/`, C, new)

`SillMicrophone.c` (from Apple's sample: the plug-in, the two devices, their streams and properties, the
clock, the ring buffer, the client check), `Info.plist` (the CFPlugIn factory, the type UUIDs, the bundle
ID, the version set by make-app.sh), `LICENSE-apple-sample.txt`, `README.md`. `Scripts/make-app.sh`
builds, places and signs it; `Scripts/release.sh` checks it.

### 5.5 Sill.app (`Sources/SillMenuBar/`)

| File | What |
|---|---|
| `HostSettings.swift` | Key `deviceMicrophones` (registered true), saved like the others; `-deviceMicrophones 0` for one run |
| `SettingsPanes.swift` | Settings › Streaming, after Send audio: `MicrophoneSection`: the switch, its footer, Sill Microphone's state line, the setup or removal command in monospace with Copy (FirewallSection's pattern) |
| `StatusText.swift` | The card's device row ends " · microphone" while that device's microphone is in use; a preview sample |
| `DebugHooks.swift` | `-SillSetAfter '<s> deviceMicrophones=0|1'`; `-SillRenderPreviews` draws the section in each state |

### 5.6 The device (`iOSClient/`)

| File | What |
|---|---|
| `MicrophoneCapture.swift` (new, pbxproj A190/F190, re-checked at the preflight) | The tap on the window's voice engine (or the DEBUG tone), each buffer copied off the tap's thread to `sill.mic`, the packetizer, the encoder (mono, 64 kbps), MicMessages of ten packets, the epoch and seq, the 200 ms unsent cap |
| `StreamClient+Microphone.swift` (new, A191/F191) | MicrophonePolicy's inputs and decisions on the main thread; the switch (app-wide, in memory); the permission; kind 16's state; start, stop, the end message; the format again after a move; the one-window choice with the hub the windows share |
| `AudioOutput.swift` | `SharedSession`'s two needs; `SoundEngine`'s voice mode; the engine runs while heard or the microphone is on |
| `SessionLink.swift` | Kind 48 never waits in `waiting` (dropped while a fence or hold stands); the unsent count |
| `HostSettingsPanel.swift` | The Microphone row right under Mute, its footnote, the Settings button when refused, `-SillSettingsScroll mic` |
| `DeviceIdlePolicy.swift` | The microphone sending holds the auto-lock (open question 10) |
| `MockCatalog.swift`, `ContentView.swift` | `-SillMicCase ready|inuse|other|off|setup|locked|older|refused|denied|interrupted|window`, `-SillMicSource tone`, `-SillMicOn 1`, `-SillMicPermission granted|denied` (DEBUG stand-in, no prompt); console `mic: …` lines |
| `Info.plist`, `Info-Debug.plist` | `NSMicrophoneUsageDescription` (§8) |
| `PrivacyInfo.xcprivacy` | Unchanged (no required-reason API); release-ios.sh's check confirms |
| `Scripts/release-ios.sh` | Refuses an .ipa without `NSMicrophoneUsageDescription` |

### 5.7 Test tools

`Scripts/sillclient.py`: `--mic=FILE@T` (replays a packets file in the tap's bursts, stamped with its own
clock; the file from `Scripts/mic-check/tone.swift`), `--mic-end@T`, `--raw48=HEX@T`, `--mic-flood@T`,
`--expect-mic=STATE`, and kind 16's `microphone` printed. `Scripts/mic-check/`: `tone.swift` (a 440 Hz
tone at −20 dBFS with a 4 ms click at every whole second, AAC-ELD mono 64 kbps through SillAudio),
`analyze.swift` (finds each click in the host's WAV against its stamp: the delay, its spread, gaps,
drift), `run.sh` (the gates of §10.2), every host on loopback.

## 6. Threads

**The Mac.**

| Queue | Work |
|---|---|
| network queue | Read kind 48; the revoked rule; `MicGate`; hand to `sill.mic` with the arrival time; count bytes |
| `sill.mic` | Parse, dedupe, decode (under 0.1 ms a packet), the playout's decisions, schedule on the player, the silence end, stats |
| main actor | The owner rule, the switch, the lock, setup; `MicGate` updates; kind 16; status; log lines. Never a packet |
| AVFAudio's | The player's completions return buffers to the pool under its lock |
| coreaudiod's driver service | The plug-in's IO, C, real-time: the loopback only |
| `sill.capture`, `sill.encode`, `sill.audio`, `sill.menus`, `sill.pointer` | Nothing of the microphone |

**The device.**

| Queue | Work |
|---|---|
| main | MicrophonePolicy; the switch, permission, kind 16 state, scene and window, interruptions → start or stop |
| `sill.audio` (AudioOutput's) | The engine's mode, start and stop; `SharedSession`'s needs |
| the tap's thread (AVFAudio) | Copy the buffer and its time, hand to `sill.mic`; nothing else |
| `sill.mic` | Packetize, encode, build messages, `link.send`, the unsent count |
| network queue | `contentProcessed` completions; the move's hand-over (the format again) |

No Swift on a real-time thread on either side. Never `MainActor.assumeIsolated` in core code.

## 7. Settings

| Where | Name | Default | Notes |
|---|---|---|---|
| The Mac: HostConfig, `me.saffer.sill.mac` | `deviceMicrophones` | on in Sill.app (`app`), off in `standard` | The Mac's alone; nothing happens until Sill Microphone is set up (open question 4) |
| The device: app-wide, in memory | Microphone | off at every launch | Never stored (open question 5); DEBUG `-SillMicOn 1` |
| The device's panel | Microphone row | under Mute | Open question 6 |

## 8. Words (MicrophonePolicy.Copy; ‹device› is iPad or iPhone, ‹Mac› the Mac's name)

**The device.**
- Permission prompt (`NSMicrophoneUsageDescription`): "Sill sends what your microphone hears to your Mac
  while Microphone is on in Sill’s settings, so apps there can use it as a microphone."
- The row: **Microphone**; VoiceOver "Send this ‹device›’s microphone to ‹Mac›".
- Footnotes:
  - off, the Mac ready: "Turn this on to use this ‹device›’s microphone on ‹Mac›: choose Sill Microphone
    there, in a call, a recording or dictation. It turns off when Sill closes."
  - on and in use: "‹Mac› hears this ‹device›’s microphone as Sill Microphone. While it’s on, sound from
    ‹Mac› plays as on a call."
  - another device's in use: "‹Mac› is using ‹Other›’s microphone. Turn this on to use this ‹device›’s
    instead."
  - the Mac's switch off: "Turn on Microphones from devices in Sill’s settings on ‹Mac› to use this."
  - not set up: "Set up Sill Microphone in Sill’s settings on ‹Mac› to use this."
  - locked: LockedMac's line for the reading (the drawer's and the panel's words).
  - an older Mac: "Update Sill on ‹Mac› to use this."
  - refused for a minute: "‹Mac› stopped taking this ‹device›’s microphone for a minute."
  - permission refused: "Sill isn’t allowed to use the microphone. You can allow it in Settings." and a
    button **Open Settings**.
  - a call on the device: "Paused during the call on this ‹device›."
  - another window: "Your other Sill window sends the microphone."
- Console (DEBUG): `mic: on (aac-eld 64 kbps, epoch 3)`, `mic: tap 4800 frames at 48000 Hz`, `mic: off
  (in the background)`, `mic: paused (interruption)`, `mic: format again after the move`, `mic: skipped 1
  (220 ms unsent)`, `mic: voice mode on`.

**The Mac.**
- Settings › Streaming, the switch: **Microphones from devices**. Footer: "An iPhone or iPad with
  Microphone on in its Sill settings sends what its microphone hears to this Mac as “Sill Microphone”:
  choose it in the app you use, as any microphone. One device at a time. Nothing is recorded or saved."
- Sill Microphone's line: set up: "Sill Microphone is set up." with **Remove…**; missing: "Sill
  Microphone isn’t set up. Setting it up takes an administrator’s password once, and restarts this Mac’s
  sound for a moment: paste this into Terminal." and the command with **Copy**; not loaded: "Sill
  Microphone is installed but not loaded yet: restart this Mac’s sound with this command, or restart the
  Mac."; old: "Sill Microphone needs updating for this version of Sill." and the command; in use: "‹iPad›
  is sending its microphone." or "An app is using Sill Microphone; no device is sending."
- The card: " · microphone" after the device's source detail.
- Log lines (exact, one each; the refusals a line a minute at most):
  `Microphone: iPad (iPad14,1) is Sill Microphone's input now (AAC-ELD 48 kHz mono, 64 kbps).` ·
  `Microphone: iPad (iPad14,1) took over from iPhone (iPhone15,2).` ·
  `Microphone: iPad (iPad14,1) stopped.` / `left.` / `went silent for 2 s.` ·
  `Microphone: refused from iPad (iPad14,1): this Mac is locked.` / `another user is on the screen.` /
  `Microphones from devices is off.` / `Sill Microphone isn't set up.` ·
  `Microphone: iPad (iPad14,1) sent 2.3 s of sound in a second: refused for a minute.` ·
  `Microphone: could not play into Sill Microphone: <error>.` ·
  `Settings: microphones from devices on → off`.

## 9. Security

- **Who.** Only a session the Mac serves: a paired device at either TLS door; at an open home door
  (Require pairing off) any device that connects, as for typing and clicking, which already control the
  Mac. A device's microphone in Sill Microphone gives it no power it lacked; it puts its sound into
  whatever app the Mac's user pointed at Sill Microphone. The Mac's user turns it all off with one switch,
  and nothing reaches any app until he set up Sill Microphone himself.
- **A removed device:** the server drops its kind 48 (revoked sessions pass only ups); `clientRevoked`
  ends its microphone at once, before its connection closes.
- **A locked Mac:** refused at a locked screen and off console, by the reading at arrival and now
  (LockPolicy's stricter rule), the gate refusing packets on the network queue from the reading's change.
  Off console matters most: Sill Microphone is system-wide, so another user's apps could hear it.
- **Limits:** §3.3, Mac rule 3: payload caps, 1.5 s of sound a second, 1 s queued, formats a minute; a
  hostile client can keep the Mac's microphone busy only while the Mac serves it, and never grow its
  memory.
- **What the Mac's user sees:** the card's " · microphone" naming the device, the log, the Settings line,
  and macOS's own indicator for any app reading Sill Microphone.
- **The plug-in** runs inside the system's audio driver service, sandboxed, with no Mach services, network
  or files: its whole surface is the HAL's property and IO calls. It takes the feed only from a client
  whose bundle ID is Sill's. **Residual:** a local process that imitates Sill's bundle ID could speak into
  Sill Microphone; such a process already runs as the user. The C is bounds-checked against the ring's
  size on every IO call, and the `mic-plugin` check exercises it.
- **The device:** the switch is the consent (asked only from it), off at every launch, the iOS indicator
  while it records, nothing in the background, one window, one Mac. Sill never saves or transcribes it.
- **Privacy:** the sound goes only to the person's own Mac: "Data Not Collected" stays true; the policy
  page says it (§11).

## 10. Tests

### 10.1 Pure checks, each with its mutants (`Tests/checks/<name>`, README per folder, CI's matrix by `mutant-checks.py`)

| Check | What |
|---|---|
| `microphone` (new) | Microphone.swift: every type round trips; `[3]` exactly is the end; empty, unknown, overlong, truncated and trailing payloads give nil; 1,000 random strings never trap; MicrophoneState's JSON, an older reader skipping it. MicrophonePolicy: the device's rule over every combination of its inputs; the Mac's over every combination of its; the limits at their edges; the words of every state; 20,000 random sessions against the invariants (never sends with a condition failing; never in the background; never from two windows; never taken while locked or off console; nothing of a revoked or departed connection reaches the sink; a takeover always tells the previous owner). At least 25 mutants |
| `audio-playout` (moved) | Today's cases unchanged, and the microphone mode: no picture guard; ten-packet bursts every 100 ms at home and away (nothing late after the first second, delay steady); the starting cover; a feed's IO buffer of 5–20 ms; a takeover's new epoch; a move's duplicates. Mutants for the mode |
| `audio-codec` (moved) | Mono 64 kbps from 4,800-frame chunks, ten packets each, every click at its stamp ±2 frames; stereo 128 kbps unchanged |
| `audio-packetizer` (moved) | Mono 4,800-frame chunks into ten blocks; a tap's gap ends a segment |
| `mic-plugin` (new, clang) | The plug-in's C with a stub host: the properties (names, UIDs, the feed hidden and output only, the microphone input only, 48 kHz mono Float32); the zero time stamps; the loopback (a write at T read back at T − the offset); a client that is not Sill reaching nothing; zeros where nothing was written; wraparound. Mutants on the C file |
| `lock-policy`, `display-wake`, `compatibility`, `protocol`, `pointer-control`, `device-idle` | The new request at each reading; kind 48 never a person and the count 35; the kind lists; the auto-lock hold |

### 10.2 Headless gates (synthetic hosts on 127.0.0.1: `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1`, plus `SILL_TEST_MIC_SINK=file:$T/mic.wav`)

| # | Gate | Pass when |
|---|---|---|
| M0 | Preflight: the kind number and pbxproj IDs free on every ref and worktree; the disk at 25 GB | Recorded |
| M1 | The CLI byte for byte without a test sink, idle and streaming, against main's | Identical; no `Microphone` line, no `mic.` key |
| M2 | `sillclient.py PORT 30 desktop --mic=$T/tone.packets@3 --mic-end@25 --expect-mic=inUse` | Every click sent (one a second) found, each at its stamp + the model's delay ±2 ms; the delay steady within ±5 ms after 2 s; no gap |
| M3 | Two clients; the second's `--mic` at 10 s | The first's kind 16 says `other` within 0.5 s; one "took over" line; the WAV switches at one epoch |
| M4 | `SILL_TEST_LOCKED_FILE`: 1 at 8 s, 0 at 14 s; then 2 | `locked` in kind 16; silence in the WAV from the lock (no packet after it played); `ready` after the unlock's settle; off console the same |
| M5 | The bare app with `-SillUnpairAfter`, a paired client sending | Silence within 0.25 s of the removal; `mic.refused` counts |
| M6 | `--mic-flood`, `--raw48` of every malformed kind, 10 formats in a minute | Refused for a minute with one line; the host's memory flat; the picture unaffected |
| M7 | A move: a second connection with the same identity carrying the same epoch, overlapping | Duplicates dropped; at most one jump; no gap over 20 ms |
| M8 | Through `sillrelay.py --delay-ms 150 --rate-mbps 2` | Nothing late after 2 s; the cover within away's bounds |
| M9 | The end, a departure, 2 s of silence | A fade, then silence; the card and the line |
| M10 | `SILL_TEST_MIC_SETUP=missing`, then the bare app's switch off | `setup`, then `off`; nothing taken |
| M11 | Cost: the host's CPU with and without a microphone, 60 s | At most 1 point of a core more |

### 10.3 Photos and the simulator

- **Sill.app:** `-SillRenderPreviews` before and after: only the Streaming pane (the section in each
  state), menu.txt and the `card-microphone` sample differ.
- **Harness photos** on the agents' simulators (`Scripts/harness-photos.sh`, never a simulator of one's
  own), each case `-SillSettings 1 -SillSettingsScroll mic -SillMicCase <state>`: ready, inuse, other,
  off, setup, locked, older, refused, denied, interrupted, window; at 1133x744 (`-SillIdiom pad`),
  669x951 and 393x852, default and accessibility-extra-large text; every photo without the row pixel for
  pixel main's.
- **Live** on the agents' iPad simulator against `SillHost --synthetic` with the file sink:
  `-SillLive 1 -SillConnect 127.0.0.1:P -SillMicOn 1 -SillMicSource tone -SillMicPermission granted
  -SillSoundSink manual -SillSoundVolume 0`: the host's WAV has the clicks; the Settings app brought to the
  front stops it (`mic: off (in the background)`, the WAV silent); back, it resumes with a new epoch; a
  move (`-SillMoveTest 1`) keeps it. The simulator's real microphone is never opened.

### 10.4 What only Noah can try (his iPad mini, iPhone 15 Pro and Mac; nothing here installs anything)

0. **Set up Sill Microphone** with the command Settings shows: "Sill Microphone" in System Settings ›
   Sound › Input and in Audio MIDI Setup; the feed device nowhere; Settings says set up; how long the
   sound stopped, and whether a call in progress survived it. If it does not appear: reboot, and say so.
1. **The switch and the permission:** the first turn-on asks; Don't Allow gives the words and Open
   Settings; Allow gives iOS's indicator and the card's " · microphone".
2. **A call:** Zoom or FaceTime on the Mac with Sill Microphone; the other side hears the device; a clap
   test for the delay against the console's numbers.
3. **Echo:** Send Audio on, Mute off, the device's speaker, the other side talking: do they hear
   themselves? Then with AirPods.
4. **Dictation** on the Mac with Sill Microphone as its source.
5. **Your music** on the device keeps playing (lower) while the microphone is on; the Mac's sound "as on
   a call"; back to normal when it is off.
6. **Leave Sill:** the microphone stops (indicator gone, card updated); back, it resumes. With Picture in
   Picture on, the same.
7. **Lock the Mac**, then fast-switch to another user: refused, the device says why; the other user's
   QuickTime hears silence from Sill Microphone.
8. **Two devices:** the iPhone takes over from the iPad; the iPad says so.
9. **A move:** plug and pull the cable during a call.
10. **Away:** Tailscale over the iPhone's hotspot; the other side still hears; the delay.
11. **A phone call** to the device: paused, then back.
12. **AirPods** in and out during a call.
13. **An hour's call:** the console's delay steady within ±5 ms; the device does not auto-lock.
14. **Remove Sill Microphone** with the command: gone from Sound; Settings and the device say not set up.
15. **Update Sill** with Update Now while Sill Microphone is set up: it still works.
16. **VoiceOver** on both sides.
17. **macOS's indicator**: which app it names while Zoom uses Sill Microphone.
18. **Mixed builds:** this device with Sill for Mac 0.6.2 ("Update Sill on ‹Mac›"); a 0.6.2 device with
    this Mac (nothing changes).
19. **iPad windows:** two windows streaming; only the one used last sends.
20. **Battery:** thirty minutes with the microphone on, against thirty without.

### 10.5 Hard rules for the implementing sessions

Never open Noah's microphone (the simulator's input is the Mac's microphone: the DEBUG tone only); never
install Sill Microphone or restart coreaudiod on Noah's Mac (his P0); never run Sill.app or touch
`/Applications/Sill.app` or `me.saffer.sill.mac`; synthetic hosts on loopback and the software encoder only,
killed by pid; the agents' shared simulators through harness-photos.sh only; nothing on Noah's devices;
builds only at 25 GB free; and while Noah streams, nothing that shares the Mac's video encoder.

## 11. Docs, site and App Store

With the work: this plan as `docs/microphone-plan.md` with its Results; `docs/steps/<date>-microphone.md`
(`Scripts/steps.sh new`); CLAUDE.md's Layout (SillAudio, Microphone.swift, MicrophonePolicy.swift, the host
files, Sources/SillMicrophone, the device files), Build and run (the test sink, sillclient's flags,
Scripts/mic-check) and the harness arguments; DEVELOPMENT.md, "Microphone from a device" (set up, remove,
test); BRIEF.md: the microphone in scope (Noah, 2026-11-02 and 2026-11-18). **For the release that ships it**
(said so in the commit): README (what it does, the one-time setup); site/privacy.html (From your iPhone or
iPad to your Mac: "While Microphone is on in Sill’s settings, what the microphone hears, which your Mac plays
into Sill Microphone and never records or saves"; the device's permissions: Microphone; On your Mac: Sill
Microphone, and removing it under Deleting your data); site/support.html (choosing Sill Microphone in Zoom,
FaceTime, QuickTime Player and dictation; removing it); docs/app-store-metadata.md (a description bullet; the
review notes: what a reviewer needs on the Mac to hear it; App Privacy still Data Not Collected, with the
microphone's bullet in its reasons; the purpose string); and the iOS build's check (release-ios.sh).

## 12. Order of commits (each passes its gates before the next; merges, never rebases)

| # | Commit | Gates |
|---|---|---|
| 0 | Preflight, no commit: the kind number from OVERVIEW, the pbxproj IDs, the disk | M0 |
| 1 | "Audio: the codec, the packetizer and the playout in SillAudio, shared" (no change in behaviour) | builds; `run-all.sh`; docs/audio-plan.md's harness gates H5–H8 and its simulator gate S2, as before |
| 2 | "Protocol: kind 48, the device's microphone" | `microphone` (wire), the kind checks, mutants |
| 3 | "Policy: MicrophonePolicy" | `microphone` (policy), mutants |
| 4 | "Host: the microphone's receive path" (server, receiver, output with the dry and file sinks, setup reading, coordinator, lock, wake, config, status, test hooks, sillclient, Scripts/mic-check) | M1–M11, `lock-policy`, `display-wake`, `audio-playout` |
| 5 | "Sill Microphone: the Audio Server Plug-in" (C, make-app.sh, release.sh) | `mic-plugin`; `codesign --verify --strict --deep` of the built app; release.sh's dry run's checks |
| 6 | "Sill.app: Microphones from devices" | the previews |
| 7 | "iOS: the microphone" (capture, the session's two needs, the voice engine, SessionLink, the panel, the harness, the plists, release-ios.sh) | the iOS builds (Debug and Release, simulator and device), only the known warning; photos; the live simulator run |
| 8 | "Docs" | `repo-rules` |
| 9 | Review in three lenses (the device's session and engine; the host's threads and limits; the plug-in's C and security), fixes, the P-list to Noah. **Stop there** | — |

Size: about 12–15 days of focused work: the shared target 1, wire and policy 2, the host 3, the plug-in 3,
the app 1, the device 3, docs and review 2. Noah's P-list: about 3 hours.

## 13. Risks

1. **The plug-in itself.** C in a system daemon; a crash there takes every app's sound. Apple's sample,
   the `mic-plugin` check and a narrow surface (two devices, a ring, no IPC) contain it. A report of a
   signed plug-in that macOS 26 never loaded (a vendor's forum, not Apple) makes P0 the first device test.
2. **The setup is a Terminal command** with an administrator's password and a sound restart. Some people
   will not do it; the Installer package (open question 3) is the friendlier route and needs a certificate.
3. **Echo** if voice processing does not cancel the Mac's sound through the shared engine (P3): then
   headphones, or Mute, until a fix.
4. **The tap's 100 ms**: the call's delay grows by it (open question 12).
5. **The app's audio session** now has two needs: the Mac's sound, Picture in Picture and the microphone
   meet in `SharedSession`; a category change mid-play is one jump; Picture in Picture with a recording
   category is untried (the microphone stops in the background by default, so they rarely meet).
6. **App Review** reads a recording app with an `audio` background mode closely (2.5.4): the microphone
   never records in the background, and the review notes say so.
7. **The kind number** while three Pencil pull requests hold 45.
8. **The shared target's move** touches the Mac's sound; commit 1 changes nothing else and runs every
   sound gate.

### Beside the other workstreams (for next/OVERVIEW.md)

- **Kind numbers:** the camera (#193) holds 46 and the Pencil pull requests 45; this plan asks for 48.
- **What Sill installs on the Mac:** a virtual camera for the camera workstream is a Camera Extension (a
  system extension the person approves); this is an Audio Server Plug-in (an administrator's copy into
  /Library). Noah's answer to open question 1 here and the camera's equivalent shape one story in Settings
  and on the support page. They stay two mechanisms: Apple documents the Audio Server Plug-in for a
  virtual audio device, and AudioDriverKit only for physical ones.
- **The device's audio session:** a camera that captures sound, or uses AVCaptureSession's automatic
  session configuration, must go through `SharedSession` too, or it undoes the category this plan sets.
- **The device's Settings panel:** this row goes under Mute; the camera's and the files' rows land in the
  same panel, so their placements are best decided together.
- **Recording the stream (#284/#303):** it records what the device receives; the microphone is not mixed
  into a recording in this plan.

## 14. What could not be determined by reading

Whether voice processing cancels sound played by the same app through the same engine when another
engine played it before (it is designed to be the same engine); the real buffer size of a tap on a
voice-processing input node; how long voice mode takes to start; whether `sudo killall coreaudiod` loads
a new plug-in on macOS 27 without a reboot; whether nested code at `Contents/Library/Audio` passes
strict validation and notarization as is; AAC-ELD's quality at 64 kbps mono for speech on a device (the
probe of docs/audio-plan.md measured stereo); whether Picture in Picture starts with a recording category;
the plug-in sample's exact licence text (in its download, not read here).

## 15. Open decisions for Noah (the work proceeds with each recommendation unless he says otherwise)

1. **Install a system audio plug-in at all?** Options: (a) Sill Microphone, an Audio Server Plug-in set
   up once with an administrator's password; (b) AudioDriverKit (Apple: physical devices only, and its
   entitlements on request); (c) Core Audio taps (each recording app asked for System Audio Recording);
   (d) the Mac's speakers, as #191 (not what was asked); (e) no microphone. **Recommendation: (a).** It is
   the only way Apple documents for a virtual device, and the only one a meeting app can use plainly.
2. **C in the repository** for the plug-in's real-time code (and nothing else)? Options: yes, from
   Apple's sample; Swift on the real-time thread (against Apple's word and the project's rule); no
   plug-in. **Recommendation: yes**, confined to `Sources/SillMicrophone/`.
3. **How Sill Microphone is set up.** (a) A Terminal command in Settings with Copy, Sill never running it
   (the firewall's way); (b) an Installer package opened from Settings, which asks for the password
   itself (needs a "Developer ID Installer" certificate and a notarized package in each release); (c) a
   separate download. **Recommendation: (a) now; (b) before the public release** if you make the
   certificate.
4. **The Mac's switch, Microphones from devices: on or off by default?** **Recommendation: on in
   Sill.app** (as Share clipboard): nothing reaches any app until you set up Sill Microphone and a device
   turns its switch on.
5. **The device's switch: off at every launch, or remembered?** **Recommendation: off at every launch**,
   kept through reconnects and moves, so a microphone never starts by itself days later.
6. **Where the switch goes.** Right under Mute (the sound's rows together), or in This iPad (#191's
   place). **Recommendation: under Mute.**
7. **A locked Mac.** Refused at a locked screen and off console, or a paired device's microphone kept at
   a locked screen (a call going on behind the lock), never off console. **Recommendation: refused at
   both.**
8. **Leaving Sill.** The microphone stops when Sill's window leaves the front, Picture in Picture
   included, or keeps going while Picture in Picture plays (a call watched in the small window).
   **Recommendation: stops**, no recording in the background in this version.
9. **Two devices.** The one that turned it on last takes over and the other is told, or the first keeps
   it. **Recommendation: the last takes over.**
10. **Auto-lock during a call.** The microphone sending holds the device's auto-lock, or it locks as
    today ten minutes after the last touch (and the microphone stops with it). **Recommendation: holds
    it.**
11. **AirPods.** Their microphone, in call quality (`.allowBluetoothHFP`), or the device's own
    microphone with AirPods playing in full quality. **Recommendation: theirs, call quality**, as a call
    app does.
12. **The delay.** Accept the tap's 100 ms in this version, or add a small real-time piece in C on the
    device for about 20 ms. **Recommendation: accept now**; revisit after P2's measured number.
13. **Shared code.** Move the codec, packetizer and playout into one target both sides link, or copy them
    into each side. **Recommendation: move** (one tested model for both directions).
14. **#191.** Redo crediting addhumal (a co-author trailer, the pull request, the site's contributors),
    or build on his commit. **Recommendation: redo**, and tell him why on #191 with thanks.
15. **The kind number.** **Recommendation: 48** unless OVERVIEW assigns another.


## Progress

**The first part (branch `microphone`, pull request #415, 2026-11-19): everything that needs nothing installed.**
Built: the wire (§4 as §0 settles it: Microphone.swift, the list's field, kind 16's state); both ends' rules and
every word (MicrophonePolicy.swift: the device's rule, its link, the window, the row; the Mac's reducer); SillAudio's
mono encoder and decoder and AudioPlayout's microphone mode (§3.4, §5.1); the Mac's receiving side up to the seam
where Sill Microphone takes the sound (MicrophoneReceiver, MicrophoneOutput, LockPolicy's request, the coordinator's
glue, `deviceMicrophone`), which only a test host has in this part (the TEST ONLY MicrophoneTestOutput: a WAV of
exactly what Sill Microphone would hear); the device's capture (the voice engine, SharedSession's two needs, the
tone in the simulator) and Share Microphone; the checks `microphone`, `mic-host` and `mic-send`, the microphone's
cases in `audio-codec`, `audio-playout`, `lock-policy`, `away-quality`, `fence`, `compatibility`, `pointer-control`
and `display-wake`; sillclient.py's `--mic` flags and Scripts/mic-check's gates. The step file
(docs/steps/2026-11-19-microphone.md) has what was verified and how.

Next: Sill Microphone itself (§3.2, §5.4: the Audio Server Plug-in in C, its `mic-plugin` check, make-app.sh and
release.sh), Sill.app's feed output into it, `SillMicrophoneDevice` (its state), the Settings section and the card
(§5.5); the device's auto-lock hold; the harness photos and a device's live run; the remaining gates (M7, M8, M11);
the docs for people (DEVELOPMENT.md, the site, the review notes) for the release that ships it.
