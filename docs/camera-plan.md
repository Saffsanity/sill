# The device's camera on the Mac — the plan

2026-11-18. Written read-only against main at 4e00c805 (Sill 0.6.2) and pull request #193's head 828a273b (issue
#192, addhumal); built on branch `camera` (pull request #401: #193's head merged in as it is, so #193 shows as merged
when this lands, as #355 did for #173, our commits on top). Noah, 2026-11-18, among the next features: "camera from
iOS passed to Mac". The assessment it rests on is kept beside the plan in the handoff folder; §17 lists what reading
could not settle. The "Progress" section at the end says what is built.

## 0. As settled on 2026-11-18, over this plan's first draft

The overview of the night's six plans settled where they disagreed. Where it differs, it wins, and the code follows it:
- **The wire (§5).** A frame's capture time and keyframe flag ride the message header (`timestamp`, the device's
  wall clock at capture, converted by an elapsed time alone; `isKeyframe`): type 2 is `type · epoch · seq · data`,
  no `elapsedMs`, no flags byte. Whether the Mac wants frames, and why not, moves from type 3 to kind 16's
  per-connection `camera` (`CameraState`: `state` one of `off`, `notReady`, `unpaired`, `idle`, `another`,
  `inUse`, an unknown one read as `off`; `holder` with `another`; `app` with `inUse`); a device captures only
  while it says `inUse`. Type 3 (`CameraDemand`) keeps only `width`, `height`, `fps`, `keyframe`, `maxBitrate` and
  `token`. `WindowList.camera` 0 is a Mac that has Sill Camera with its switch off or Sill Camera not ready.
- **A locked Mac (§6.3.5, §12; Q8).** The camera is refused at a locked screen too, not kept: nothing a device sends
  acts on a locked Mac but the password typed at its lock screen. `LockPolicy.list` leaves `camera` out at any
  lock; kind 46 is a LockPolicy request refused at any lock; the demand is withheld then.
- **When the device's camera runs (Q4, Q13).** Only while an app on the Mac uses Sill Camera, Sill is in front (never
  in the background or Picture in Picture), and the device's switch was turned on since Sill last launched; the
  switch stays on through reconnects and moves. One device per sensor: the last one turned on.
- **Where the switches go (Q15).** Sill.app: Settings › Streaming, one section "Camera and Microphone (beta)" after
  Send audio, with "Use iPhone and iPad cameras", Sill Camera's status line and Remove Sill Camera…. The device:
  "Share Camera (beta)" with Camera: Front | Back, in This ‹device› after the clipboard's rows, its footnote's words
  from kind 16; the rows go into the whole-screen Settings pane (branch `settings-pane`) once it lands.
- **Kind 46** stays the camera's; #175's `cursorKind` moves to 50 (Q3). The iOS project's new IDs are A462–A467
  with their F twins. On the device, the camera's `AVCaptureSession` never configures the app's audio session
  (`automaticallyConfiguresApplicationAudioSession = false`), and its bytes count in the one uplink ledger in
  SessionLink that files builds (input first, then sound, then the picture).

## 1. What it is, in a person's words

Turn on **Share Camera** in Sill's Settings on your iPad or iPhone. On the Mac, FaceTime, Zoom, Teams, Photo Booth
or a call in Chrome or Safari can choose **Sill Camera**, and it shows what the device's front camera sees. The
device's camera turns on only while an app on the Mac is using Sill Camera, and Sill shows a Camera indicator on the
stream while it is on. So you can join the call that runs on your Mac from the iPad in another room, or from
anywhere over your own VPN: you watch the call's window on the iPad, as Sill streams it, and the far end sees you.

Once, on the Mac: Settings › Streaming › **Use iPhone and iPad cameras** (§0). Sill installs its camera, Sill Camera, and
macOS asks an administrator of the Mac to allow it in System Settings. Sill must be in the Applications folder.

Not this: a recording, a photo, a preview window on the Mac, the camera running in the background, the
microphone (workstream #191, which pairs with it), Continuity Camera's effects.

## 2. Decisions, and who made them

**Noah's.** "camera from iOS passed to Mac" (2026-11-18). No comment of his on #192 or #193.

**Standing rules that bind it** (CLAUDE.md and the memory notes): Apple frameworks only and no running costs; "Latency
beats quality. Drop frames before queuing them."; HEVC, no B-frames, real time; new features off until turned on;
the Compatibility floor (additive only, a kind never reused, a new kind only to a peer that said it takes it, a
public layout never changes); host code in `SillHostCore` with `package` access, never `MainActor.assumeIsolated`,
the CLI's stdout byte-identical, the modal-loop rule; rules as pure policy types checked with swiftc and mutants;
nothing that shares the Mac's video encoder while Noah streams; simulators only through the agents' pair and
`Scripts/harness-photos.sh`; known visible defects hold a merge until he says otherwise.

**This plan's defaults**, each an open decision in §18, taken unless Noah says otherwise: a Core Media I/O camera
extension (the only way Mac apps can pick it); the camera runs only on the Mac's demand; off on both sides; paired
sessions only; one device is the camera at a time, the last one turned on; a locked screen keeps it, another user on
the Mac stops it; HEVC; 1280×720 or 1920×1080 at 30 fps; an upright phone pillarboxed; a Beta tag.

**Beside the related work.**
- **#191, the microphone (kind 45)**: the other half of a video call. Shared with it: the device's uplink budget
  (§6.2), the time reference of the frames (`elapsedMs` from the session's start, §5), the network-queue hand-off on
  the Mac (§9), and a Mac-side virtual device's packaging and approval words. It conflicts with #193 in the same lines
  (both put their code in the clipboard's files).
- **#175, Apple Pencil pressure and tilt**: also claims kind 46 (`cursorKind`, host → device). One of the two moves
  (§18 Q3).
- **#291, Picture in Picture (merged)**: in Picture in Picture Sill runs in the background, where iOS stops the
  camera: the camera pauses (`background`) while the picture floats, and comes back with Sill.
- **#303, recording the stream**: writes the stream's samples without re-encoding, so the device's encoder stays the
  camera's.
- **#184, privacy mode**: blanks the Mac's own display while a device uses it; Sill Camera is unaffected (it is not
  the Mac's display), and a call shown on the device goes on.
- **#230 and DeviceIdlePolicy**: the camera's use holds the device awake only by Q13's rule.

## 3. The design on one page

```
iPad or iPhone: Sill in front, Share Camera on, the Mac said `camera` 1, the session paired
  │ type 1 offer (position, claim) ──────────────────────────────►  Sill.app: CameraReceiver (queue sill.camera)
  │                                                                    CameraHostPolicy: switch, paired, holder, lock
  │ ◄──────────── type 3 demand: wanted, 1280×720@30, keyframe, "FaceTime"   ▲
  │                                                                          │ an app opened Sill Camera
AVCaptureSession (front, RotationCoordinator, interruptions, system pressure)│ (custom properties, CMIO listener)
  → VTCompressionSession HEVC (the device's encoder, real time, no B-frames, keyframes on demand)
  → CameraPacing (camera bytes not yet taken ≤ budget, else drop and next frame a keyframe)
  → type 1 format (epoch, parameter sets) + type 2 frames on the session's TLS connection
                                     │
  Mac, StreamServer's network queue: revoked? the lock gate? caps and rate → CameraReceiver, in arrival order
  → VTDecompressionSession (VideoToolbox's decoder, never the encoder) → VTPixelTransferSession (fit, pillarbox)
  → CameraSink: CMSimpleQueue of Sill Camera's sink stream (CoreMediaIO C API, IOSurface-backed buffers)
                                     │
  Sill Camera (system extension, sandboxed, user _cmiodalassistants): sink → source stream
  → FaceTime, Zoom, Chrome… (each asks for camera access as for any camera); a placeholder when nothing feeds it
```

## 4. What Apple documents (checked 2026-11-18)

The assessment, §6 to §8, quotes each source. In short: camera extensions are system extensions since macOS 12.3,
and Apple planned to disable DAL plug-ins in the release after Ventura, macOS 14, Sill's floor; the extension lives
in `Contents/Library/SystemExtensions`, must be sandboxed, runs as `_cmiodalassistants`, names a Mach service
prefixed by its app group; the app needs
`com.apple.developer.system-extension.install` (a capability on the App ID, so a new Developer ID profile); "Only
apps that reside in the `/Applications` directory can activate an extension"; an administrator allows it (Privacy &
Security on macOS 13–14, General › Login Items & Extensions › Camera Extensions from 15, by third-party guides);
frames go in through a sink stream with the CoreMediaIO C API, control through custom properties (Apple DTS);
`OSSystemExtensionRequest` activates, replaces (`actionForReplacingExtension`), asks properties and deactivates; the
app's deletion uninstalls it. On iOS: no camera in the background; on iPad multitasking camera access only with
Stage Manager on an extended display (or `voip`, which Sill must not declare); `systemPressureState` for heat; App
Review 2.5.14 wants consent and "a clear visual and/or audible indication" for "any use of the device camera"; the
privacy manifest's 35F9.1 lets only elapsed times between events in the app leave the device.

## 5. The wire: kind 46, both ways

`StreamMessageKind.camera = 46` (#193's number, held by main's comment for the camera; #175's `cursorKind = 46` must
move, §18 Q3). The first byte of the payload is its type. A reader drops a message past its type's cap whole and
skips a type it does not know.

| Type | Direction | Payload | Cap |
|---|---|---|---|
| 1 | device → host | JSON `CameraFormat` | 4,096 bytes |
| 2 | device → host | binary `CameraFrame` | 12 + 262,144 bytes |
| 3 | host → device | JSON `CameraDemand` | 4,096 bytes |

**`CameraFormat`** (type 1; every field optional; #193's names kept where they were):

| Field | Type | Meaning |
|---|---|---|
| `stop` | Bool | true: Share Camera went off; this device's offer ends (#193's) |
| `position` | String | `front` or `back` (#193's); any other value read as `front` |
| `claim` | Bool | the person just turned Share Camera on: this device becomes the camera even if another is; never on a session's start, a reconnect or a move |
| `pause` | String | the offer stands but no frames come now, and why: `waiting` (no demand yet), `background`, `multitasking`, `busy` (another app or a call has the camera), `scanner` (Sill's pairing scanner), `thermal`, `denied`, `unavailable` |
| `codec` | String | `hevc`: frames of `epoch` follow (#193's); generation 1 knows no other |
| `width`, `height` | Int | the frames' size as they stand upright, even, 16…1920 (#193's) |
| `fps` | Int | 1…30 (#193's) |
| `epoch` | Int | 0…65535; a new one for any change of size, rate or parameter sets (#193's) |
| `parameterSets` | Data | `ParameterSets.encoded()` of the epoch's VPS, SPS and PPS (base64 in the JSON), at most 1,024 bytes |
| `bitrate` | Int | the encoder's target in bits per second, logged only |

A type 1 without `codec` is an offer (or its pause) and no frames; with `codec`, an epoch whose frames follow.

**`CameraFrame`** (type 2), big endian, 12-byte header, then the data:

```
type (UInt8) = 2 · epoch (UInt16) · seq (UInt32) · flags (UInt8, bit 0 keyframe, the rest 0)
· elapsedMs (UInt32: milliseconds from this session's start on the device to this frame's capture) · data
```

The data is one HEVC access unit as the stream's own kind 1 carries one: NAL units, each after its 4-byte big-endian
length (VideoToolbox's output as it is). #193's per-frame width and height go (they are the epoch's). `elapsedMs` is
an elapsed time between events in the app, which reason 35F9.1 allows to leave the device, never a raw host time; one
reference for the session (a move keeps it), so the Mac can line the camera up with the microphone's packets if kind
45 counts from the same start (§18 Q18).

**`CameraDemand`** (type 3, host → device; every field optional):

| Field | Type | Meaning |
|---|---|---|
| `wanted` | Bool | send frames now |
| `width`, `height`, `fps` | Int | what the app on the Mac chose; the device keeps its picture upright inside it |
| `keyframe` | Bool | make the next frame a keyframe (a decode failure, a new app, the end of a pause) |
| `app` | String | the app using Sill Camera, cleaned (SafeText.label, at most 40 characters) |
| `reason` | String | when not wanted: `idle` (no app uses Sill Camera), `another` (another device is the camera), `notReady` (Sill Camera not installed, allowed or running), `unpaired` |
| `holder` | String | with `another`: that device's name, cleaned |
| `maxBitrate` | Int | the Mac's ceiling (lower away from home) |
| `token` | Int | rises with every demand; the device's console line names it |

**Capability flags.**
- `Hello.camera: Int?` (kind 23): 1 from a device that sends types 1 and 2 as generation 1 and reads type 3. Nil from
  every device before: a host sends it no kind 46.
- `WindowList.camera: Int?` (kind 2, #193's field): 1 from a host that takes generation 1 (HEVC Main, 8-bit 4:2:0,
  at most 1920 a side, at most 30 fps, the layouts above) from paired sessions and answers with type 3; nil from older
  hosts, the CLI, a Mac whose switch is off, and while another user is on the Mac's screen (`LockPolicy.list`).
- `ClientStats` (kind 12), optional and additive: `cameraFps`, `cameraKbps`, `cameraDropped`, `cameraPause`, for the
  Mac's once-a-second client line.

**Rules.** A device sends kind 46 (types 1 and 2 only) only to a host whose list says `camera` 1 or more; a host sends
kind 46 (type 3 only) only to a device whose hello says `camera` 1 or more. A host takes type 2 only from the session
that holds the camera, of its current epoch, after that epoch's type 1. Generation 2 (H.264, 60 fps, more types) is
said with 2 and goes only to a peer that says 2.

**For the Compatibility floor** (CLAUDE.md, written when a public build ships it): kind 46's three types, their
layouts and caps, `CameraFormat`'s and `CameraDemand`'s fields and the reasons above, `Hello.camera`,
`WindowList.camera` and generation 1's meaning.

## 6. The rules, as pure policy types

### 6.1 The device: `CameraPolicy` (`iOSClient/CameraPolicy.swift`; Foundation only; `Tests/checks/camera`)

1. **The row** (`showsRow`): Share Camera shows in This iPad (This iPhone) while the Mac's last list says `camera` 1
   or more, as the clipboard's row does; never for an older Mac or the CLI.
2. **Offered** (`offers`): type 1 offers go while the switch is on, the Mac takes the camera, the session is
   connected and paired (kind 16's `sessionPaired`, or the remote door) and iOS has not refused the camera. The switch
   turned on sends `claim`; a session's start, a reconnect and a move send none.
3. **Capturing** (`captures`): the capture session runs only while all hold: it offers; the Mac's last demand says
   `wanted`; Sill is active with this session's window in front (scene foreground active); nothing interrupts the
   camera (background, multitasking, another app or a call, Sill's own pairing scanner); the system pressure is under
   `.shutdown`. Anything else stops it within one queue turn and says why in type 1's `pause`.
4. **The format** (`format`): the demand's size if the camera has a format at that size and rate, else 1280×720;
   upright (a phone held upright sends 720×1280 inside a 1280×720 demand: the Mac pillarboxes); the rate the demand's,
   at most 30. Away from home (a remote session) at most 1280×720.
5. **The bitrate** (`bitrate`): 1280×720 at 30 fps 2.5 Mbit/s at home, 1.2 away; 1920×1080 4 Mbit/s at home; scaled
   with the rate; at most the demand's `maxBitrate`; stepped down a third after each pacing drop in a second, back up
   a tenth every 5 s without one.
6. **Heat** (`thermal`): `.serious` 20 fps, `.critical` 15 fps and 1280×720 at most, `.shutdown` paused `thermal`
   (iOS stops the camera there anyway); back a step 30 s after the pressure falls.
7. **Keyframes** (`keyframe`): at a new epoch, at a demand's `keyframe` (at most one a second), after a pacing drop;
   otherwise none (an infinite GOP, as the Mac's stream: a periodic keyframe costs bitrate for nothing on TCP).
8. **A move** (`moved`): the new connection gets the offer again (no `claim`) and a new epoch with its keyframe once
   the Mac's demand says `wanted` on it; nothing is queued across the hand-over (§6.2).
9. **The indicator** (`chip`): "Camera" with the app's name while frames go; "Camera Paused" while wanted but paused;
   nothing otherwise. Shown in every layout, and as a camera dot alone while Full Screen hides Sill's controls (2.5.14).
10. **Auto-lock** (`countsAsUse`): each second the camera captures counts as the person's use for DeviceIdlePolicy, as
    a call keeps a phone awake (§18 Q13).
11. **The words** (`Copy`): every device sentence of §11.

### 6.2 The device's send budget: `CameraPacing` (same file and check)

Camera frames share the session's TCP connection with input, so they must never queue in front of it. A frame goes
only when no hand-over fence or hold stands (`SessionLink`) and the camera bytes the connection has not taken yet
(sent, `.contentProcessed` not yet called) are at most the budget: the larger of 16 KB and 40 ms of the rate the
connection took over the last second (the host's `pendingBytes` and `takenThisSecond`, from the device's side).
Otherwise the frame is dropped, the drop counted, and the encoder's next frame forced to be a keyframe, which itself
goes only once the backlog fits (never a P-frame after a drop before a keyframe). So an input waits behind at most the
budget and the one frame then crossing: about 40 ms plus a frame's time on the link, a keyframe's on a slow link
(keyframes come only on need, their size held by the encoder's data-rate limits). The check models it on a virtual
clock (1, 2, 5, 20 and 100 Mbit/s uplinks, taps among frames) against those properties; a device measurement (H11,
N13) confirms it. If the microphone's packets (kind 45, #191's plan) come, they count in the same bytes not yet
taken and are never dropped for the camera's sake: input first, then sound, then the picture.

### 6.3 The Mac: `CameraHostPolicy` (`Sources/SillHost/CameraHostPolicy.swift`; Foundation only; `Tests/checks/camera-host`)

1. **Taken** (`takes`): a kind 46 counts only while the Mac's switch is on, the session is paired now (the trust
   list's snapshot: Require pairing off lets an unpaired device in, never its camera), not revoked, and the lock's
   reading is not `.offConsole`. A refused offer is answered once with type 3's `reason`; frames are dropped and
   counted (`cam.refused.<why>`).
2. **The holder** (`holder`): one device is Sill Camera's at a time, by its paired key's fingerprint (a test host's by
   connection). A `claim` takes it from anyone; an offer without one takes it only while nobody holds it. The holder's
   `stop`, its device's removal, or its session ending without another of its sessions within 10 s (a move or a quick
   reconnect keeps it) frees it; then the most recent other offer takes it. The others hear `another` with the
   holder's name.
3. **The demand** (`demand`): `wanted` exactly while this device holds the camera, an app uses Sill Camera, Sill
   Camera is ready and the reading allows it; with the app's size and rate and the away ceiling
   (`AwayPolicy`); `keyframe` when the decoder failed or an app started (at most one a second per device).
4. **Caps and rates**: type 1 at most 10 a second per connection, type 2 at most 60; a frame only of the holder's
   current epoch with its format and sizes inside generation 1, at most 262,144 bytes of data; anything else dropped and
   counted (`cam.dropped`), the connection kept (the 1 MiB header cap still closes it, as today).
5. **The lock** (`LockPolicy`): a locked screen with this user on the console changes nothing (a call does not drop as
   the Mac locks; nobody else can open Sill Camera then); off console nothing reaches Sill Camera, the list drops
   `camera`, and the placeholder names nobody; back on console, after the reading's own settle, the demand comes with
   `keyframe`.
6. **The lines** (§11), each once per change, the refusals once a minute at most.
7. **Status** (`status`): per device `CameraStatus` for the menu's card (offering, holder, live, paused, the app).

### 6.4 Sill Camera: `CameraFeedPolicy` (`Sources/SillCameraExtension/CameraFeedPolicy.swift`; `Tests/checks/camera-feed`)

The formats it offers (NV12 `420v`, 1280×720 and 1920×1080, 15 to 30 fps); what goes out at each tick of the source
stream (the newest frame from the sink if under 1 s old, else the placeholder for the state Sill.app last set, or
"Open Sill on this Mac." when no sink client is connected); which sink client it takes (Sill.app's signing identifier,
`me.saffer.sill.mac`, and its code signature by pid where the sandbox allows, §17 V6; one at a time); the list of
apps using it, by signing identifier, that it publishes for Sill.app.

### 6.5 The Mac's Settings section: `CameraExtensionState` (`Sources/SillMenuBar/CameraExtensionState.swift`; checked with swiftc in `camera-host`)

From the activation request's outcome, its properties and the CMIO device's presence: `off`, `installing`,
`awaitingApproval(macOS)`, `needsApplications`, `disabledInSettings`, `forbidden` (`forbiddenBySystemPolicy`),
`unsupportedBuild` (`missingEntitlement`: a development build), `ready`, `inUse(app, device)`, `failed(code)`,
`removing`; each with its line, its button and its log line (§11).

## 7. The Mac, file by file

**StreamProtocol**
- `Camera.swift` (new): `CameraCodec` (generation 1, `hevc`, positions), `CameraFormat`, `CameraFrame`,
  `CameraDemand`, `CameraMessage` (parse and serialize with the caps; refuses rather than truncates). #193's types
  leave `Clipboard.swift`.
- `Compatibility.swift`: `Hello.camera`. `Switcher.swift`: `WindowList.camera` (#193's), its doc made exact.
  `Viewport.swift`: the four `ClientStats` fields. `StreamMessage.swift`: kind 46's comment, both ways.

**SillHostCore (`Sources/SillHost`)**
- `CameraHostPolicy.swift` (new, pure; §6.3).
- `CameraReceiver.swift` (new): its queue `sill.camera`; the policy's state (offers, holder, epochs) with its inputs
  pushed in (the switch, the trust snapshot, the lock's reading, the app's demand); a `VTDecompressionSession` per
  epoch from its parameter sets (hardware preferred, VideoToolbox's software decoder as fallback, never an encoder);
  `VTPixelTransferSession` fitting each frame into the app's size, letterboxed; the `CameraOutput` protocol it feeds
  (Sill.app's `CameraSink`, or the TEST ONLY `CameraTestOutput`: a count, or every 30th frame as a PNG in a folder);
  type 3 out through the server; state changes to the main actor for the status, never per frame.
- `StreamServer.swift`: kind 46 handed to `onCamera` on the network queue in arrival order, after the revoked check,
  with the gate's reading and the client's key fingerprint (`ClientRoute.fingerprint`, which the receiver checks
  against HostIdentity's lock-protected trust snapshot), never through `onMessage` and the main actor;
  `Client.cameraGeneration` from the hello (`took`); `sendCamera(_:to:)` refusing a client without it; type 1 and 2
  rate counters; Stats keys `cam.*`.
- `StreamCoordinator.swift`: builds the receiver, pushes its inputs; `listMessages` says `camera` (from
  `HostConfig.deviceCamera` and an output being present) through `LockPolicy.list`; `clientLeft`; `setTarget` applies
  the switch at once (no restart); #193's `HostCamera` and `case .camera` go.
- `HostClipboard.swift`: #193's `HostCamera` removed.
- `HostConfig.swift`: `deviceCamera` (the Mac's alone, like Share clipboard: absent from StreamSettings,
  HostSettingsChange, DeviceSettings.accepted, `applying` and `restartNeeded`); false in `standard` and `app`;
  `changes` names it.
- `HostStatus.swift`: `Device.camera: CameraStatus?`.
- `LockPolicy.swift`: `list` drops `camera` off console; `cameraAllowed(_ reading:)`.
- `TestHooks.swift`: `SILL_TEST_CAMERA=count|dump:<dir>`, `SILL_TEST_CAMERA_DEMAND='<s> on 640x360@30; <s> keyframe;
  <s> off'` (Sill Camera's demand, scripted), `SILL_TEST_CAMERA_LOG=1`; honoured only by a test host
  (`DoorPolicy.isTestHost`), one "ignored" line anywhere else.

**Sill.app (`Sources/SillMenuBar`)**
- `CameraExtensionManager.swift` (new, main actor): activation at launch while the switch is on and when it is turned
  on; `OSSystemExtensionRequestDelegate` (replace when the bundled build is newer; `requestNeedsUserApproval`;
  failures by code); `propertiesRequest` and, on macOS 15.1 and later, `OSSystemExtensionsWorkspace`'s observer for
  "turned off in System Settings"; deactivation for Remove Sill Camera…; never a modal of its own (macOS shows its
  alert).
- `CameraExtensionState.swift` (new, pure; §6.5).
- `CameraSink.swift` (new): the CoreMediaIO C API client: Sill Camera's device by its UID, its sink stream,
  `CMIOStreamCopyBufferQueue`, `CMIODeviceStartStream` and `Stop`, `CMSimpleQueueEnqueue` of IOSurface-backed
  `CMSampleBuffer`s stamped with this Mac's clock at arrival, the custom properties (`state` written, `demand` and
  `clients` read) and `CMIOObjectAddPropertyListenerBlock` on `sill.camera`; implements `CameraOutput`.
- `HostSettings.swift` (`deviceCamera` in `me.saffer.sill.mac`), `DevicesPane.swift` (the Camera section),
  `StatusText.swift` and `StatusCard.swift` (the card's camera line), `AppModel.swift` (owns the manager and the
  sink), `DebugHooks.swift` (previews of every state; the bare app's `-SillSetAfter '<s> deviceCamera=1'`),
  `Permissions.swift` and the Permissions pane only if §17 V2 finds Sill.app needs Camera.

**Sill Camera (new executable target `SillCameraExtension`, macOS only, no product the iOS project sees)**
- `main.swift` (`CMIOExtensionProvider.startService`, the run loop), `SillCameraProvider.swift` (the provider, the
  device "Sill Camera", its source and sink streams, the custom properties), `CameraFeedPolicy.swift` (pure, §6.4),
  `Placeholder.swift` (the still, drawn with CoreGraphics into an IOSurface-backed buffer once per state).

**Packaging and scripts**
- `Package.swift`: the target. `Packaging/CameraExtension-Info.plist` (new): `CFBundleIdentifier`
  `me.saffer.sill.mac.camera`, `CFBundlePackageType` `SYSX`, `CMIOExtension` › `CMIOExtensionMachServiceName`
  `9B2KKVM937.me.saffer.sill.mac.camera`, `NSSystemExtensionUsageDescription`, `LSMinimumSystemVersion` 14.0, the
  app's version and build. `Packaging/SillCameraExtension.entitlements` (new): `com.apple.security.app-sandbox`
  true, `com.apple.security.application-groups` [`9B2KKVM937.me.saffer.sill.mac.camera`], plus the application
  identifier and team if its profile needs them (V1). `Packaging/SillRelease.entitlements`:
  `com.apple.developer.system-extension.install` true.
- `Scripts/make-app.sh`: builds the extension (both slices with `SILL_UNIVERSAL=1`), assembles
  `Contents/Library/SystemExtensions/me.saffer.sill.mac.camera.systemextension`, embeds its profile
  (`SILL_CAMERA_PROVISION_PROFILE`, default `Packaging/camera.provisionprofile`, git-ignored) when one exists, signs
  inside out (the extension, then the app; never `--deep` to sign), runs its profile check on both, verifies
  `--strict`; a development build embeds the extension too, signed with Apple Development and without the
  profile-restricted install entitlement, so it cannot activate it (the section says "This build of Sill can’t install
  Sill Camera."). If V2 adds `com.apple.security.device.camera`, the profile check gets an explicit short list of
  hardened-runtime entitlements no profile grants.
- `Scripts/release.sh`: `check_signature` reads the extension's slices; a release without the extension, or with it
  unsigned or of another build, is refused.
- `Scripts/camera-check/package.sh` (new, P1), `Scripts/camera/make-fixture.swift` (new: the fixture, made once with
  VideoToolbox's **software** HEVC encoder), `Scripts/sillclient.py` (§13.2's flags).
- `.github/workflows/release.yml` and `nightly.yml`: the regenerated `SILL_PROVISION_PROFILE`, and
  `SILL_CAMERA_PROVISION_PROFILE` decoded beside it if V1 needs one. `ci.yml` needs nothing (`swift build` builds the
  target; `run-all.sh` and the mutants list come from the folders).

## 8. The device, file by file

- `CameraPolicy.swift` (new, pure; §6.1, §6.2). pbxproj A462/F462 (four entries by hand, as every new file).
- `CameraCapture.swift` (new; A463/F463): `AVCaptureSession` on `sill.camera.session`; the front wide camera (the back
  one by the row); the active format for the size and rate; `AVCaptureDevice.RotationCoordinator` (iOS 17) setting
  the output connection's `videoRotationAngle`, so buffers arrive upright; not mirrored (apps on the Mac mirror their
  own self-view); `centerStageControlMode = .cooperative` on iPads that have it; observers for interruptions (began,
  ended, their reasons), runtime errors and `systemPressureState`; never `isMultitaskingCameraAccessEnabled` unless
  `isMultitaskingCameraAccessSupported` (Stage Manager on an external display), and never the `voip` mode.
- `CameraEncoder.swift` (new; A464/F464): `VTCompressionSession` HEVC Main, real time, no frame reordering,
  `PrioritizeEncodingSpeedOverQuality`, average bitrate and data-rate limits from §6.1, keyframes forced only (§6.1
  7), parameter sets read from the format description; in the simulator the software encoder only (its VideoToolbox
  runs on the Mac, whose hardware encoder the stream owns), and the harness refuses otherwise.
- `CameraPattern.swift` (new, DEBUG; A465/F465): a moving test pattern with a frame counter, at 30 fps, for
  `-SillCameraSource pattern` where there is no camera (the simulator).
- `StreamClient+Camera.swift` (new; A466/F466): the camera's state for the views; the hello's `camera: 1`; the list's
  `camera` (`hostCameraChanged`); type 3 read on the network queue; offers, epochs, frames; `cameraMoved()` from
  `finishMove`; `resetCamera()` from `tearDown`; the pacing through `SessionLink`; ClientStats' fields; DeviceIdle's
  use; DEBUG console lines `camera: …`.
- `CameraChip.swift` (new; A467/F467): the indicator and its Stop.
- `SessionLink.swift`: `sendCamera(_:budget:) -> Bool`, which refuses under a fence or a hold (never appends to
  `waiting`) and over the budget, and counts the camera's bytes sent and taken under its lock.
- `StreamClient.swift` (the hooks above), `HostSettingsPanel.swift` (the rows), `StreamScreen.swift` and
  `PortraitStreamScreen.swift` (the chip's place, clear of the clipboard's chip, the link's line and the full-screen
  edge band), `DeviceIdlePolicy.swift` (`Uses.camera`), `MockCatalog.swift` and `ContentView.swift` (the harness's
  cases and their contract), `PairingOverlay.swift`/`CodeScanner.swift` (the scanner pauses the camera while it shows),
  `Info.plist` and `Info-Debug.plist` (the string).
- Not changed: `UIBackgroundModes` (no `voip`, no new mode), entitlements, `PrivacyInfo.xcprivacy` (no new
  required-reason API; 35F9.1 already declared, and only elapsed times go out).

## 9. Threading

**Mac.** StreamServer's network queue reads kind 46 and hands each one, in order, to `sill.camera` with the gate's
reading; it never waits on it and never hops to the main actor per message. `sill.camera` owns the receiver's state,
the policy, decoder creation, the fit and every CoreMediaIO call; VideoToolbox's decode callback hops back to it.
CoreMediaIO's property listeners run on `sill.camera`. Type 3 leaves through `server.sendCamera`, which hops to the
network queue. The main actor sees state changes only (the status card, the Settings section) and owns
`CameraExtensionManager`, whose delegate runs on the main queue. Under the CLI's `dispatchMain` nothing of the camera
touches AppKit (the CLI builds no sink; a test host's output is a counter or PNG files on `sill.camera`).

**Device.** `sill.camera.session`: the capture session's configuration, start and stop, its notifications and the
pressure's observer. `sill.camera.output`: the sample buffers into the encoder. VideoToolbox's callback → the serial
`sill.camera.send`: pacing, then `SessionLink.sendCamera` under its lock; the completions update the counts under the
same lock. StreamClient's network queue reads type 3 and hops to `sill.camera.session` (start, stop, format) and to
the main thread (the views). The main thread: the switch, the row, the chip, DeviceIdle.

**Sill Camera.** One serial queue for the sink's consumption, the source's timer and the properties; the placeholder
drawn once per state.

## 10. Settings: names, places, defaults

| Setting | Where | Key | Default | Notes |
|---|---|---|---|---|
| Share Camera | the device's Settings panel, This iPad (This iPhone), after Share Clipboard | `Sill.shareCamera` (#193's) | off | per device, never sent; shown while the Mac says `camera` |
| Camera (Front, Back) | under Share Camera while it is on | `Sill.cameraPosition` | `front` | sent as `position` |
| Use iPhone and iPad cameras | Sill.app, Settings › Streaming, "Camera and Microphone (beta)" (§0; Devices in the first draft) | `deviceCamera` (`me.saffer.sill.mac`) | off | the Mac's alone; installs Sill Camera when turned on; applies at once |
| Remove Sill Camera… | the same section | none | | deactivates the extension (macOS may ask for an administrator) |

DEBUG only: `-SillCameraCase off|idle|inuse|another|notready|unpaired|denied|paused|thermal|nocamera`,
`-SillCameraChip on|paused|fullscreen`, `-SillCameraSource pattern`, `-Sill.shareCamera 1`. TEST ONLY on a test host:
the three `SILL_TEST_CAMERA*` variables (§7).

## 11. Every sentence shown to a person

**The device** (`CameraPolicy.Copy`; "iPad" is the device's word, ‹Mac› the Mac's name):
- Row: "Share Camera", with a "Beta" tag as Send Audio has. Under it while on: "Camera", Front | Back.
- Footnotes:
  - off: "Lets apps on ‹Mac›, such as FaceTime or Zoom, use this iPad’s camera as “Sill Camera”. The camera turns on only while one of them uses it, and Sill shows when it’s on."
  - on, waiting: "Apps on ‹Mac› can choose “Sill Camera”. The camera turns on only while one of them uses it."
  - on, in use: "‹FaceTime› on ‹Mac› is using this iPad’s camera." (no name known: "An app on ‹Mac› is using this iPad’s camera.")
  - another: "‹iPhone› is ‹Mac›’s camera now. Turn Share Camera off and on to use this iPad instead."
  - not ready: "Sill Camera isn’t ready on ‹Mac›. In Sill’s Settings there, Devices shows what it needs."
  - unpaired: "Pair this iPad with ‹Mac› to share its camera."
  - denied: "Sill isn’t allowed to use the camera. Open Settings and turn on Camera for Sill." and a button, "Open Settings" (Sill's own page in iOS's Settings).
  - multitasking (iPad): "The camera pauses while another app shares the screen with Sill."
  - busy: "Another app is using the camera. Sill’s comes back when it’s done."
  - thermal: "The camera is paused while this iPad cools down."
  - no camera: "This iPad has no camera Sill can use."
- The chip: "Camera" over "‹FaceTime› on ‹Mac›" (or over "On"), and "Stop"; paused: "Camera Paused". VoiceOver:
  "Camera on. ‹FaceTime› on ‹Mac› is using it." / "Camera paused."; its button "Stop sharing the camera". In Full
  Screen, the camera symbol alone, read "Camera on".
- `NSCameraUsageDescription` (both plists): "Sill scans the code on your Mac to pair with it. With Share Camera on,
  apps on your Mac can use this camera through Sill."

**The Mac** (`CameraExtensionState` and Sill.app):
- Section toggle: "Use iPhone and iPad cameras". Footnote: "Apps on this Mac, such as FaceTime and Zoom, can choose
  “Sill Camera” to use the camera of a connected iPhone or iPad that has Share Camera on. Its camera turns on only
  while an app here uses it. Sill installs Sill Camera once, and an administrator allows it in System Settings."
- Lines: "Installing Sill Camera…" / "Waiting for approval: in System Settings › General › Login Items & Extensions,
  turn on Sill under Camera Extensions." (macOS 15 and later) / "Waiting for approval: in System Settings › Privacy &
  Security, click Allow for Sill." (macOS 14), each with "Open System Settings…" / "Move Sill to the Applications
  folder, open it from there, and turn this on again." / "Sill Camera is turned off in System Settings › General ›
  Login Items & Extensions." / "This Mac’s administrator doesn’t allow camera extensions from other developers." /
  "This build of Sill can’t install Sill Camera." / "Ready. Apps on this Mac can choose “Sill Camera”." / "In use by
  ‹FaceTime›, with ‹iPad›’s camera." / "Couldn’t install Sill Camera: ‹reason›." with "Try Again" / "Removing Sill
  Camera…" / "Sill Camera was removed." Button: "Remove Sill Camera…".
- The menu's device card, while in use: "Camera: ‹FaceTime›".
- Sill Camera's placeholder (drawn into the video an app shows): "Sill Camera" over one line: "Turn on Share Camera in
  Sill on your iPhone or iPad." / "‹iPad›’s camera is paused." / "Open Sill on this Mac." / off console, with no
  names: "Sill Camera isn’t available right now."
- Sill.log: "Camera: ‹iPad (iPad14,1)› offers its front camera." / "Camera: ‹FaceTime› uses Sill Camera; asked ‹iPad›
  for 1280×720 at 30 fps." / "Camera: ‹iPad›’s camera is live: 1280×720, 30 fps, HEVC, 2.5 Mbps." / "Camera: ‹iPad›
  paused its camera (background)." / "Camera: ‹iPad› stopped sharing its camera." / "Camera: ‹iPhone› took Sill
  Camera from ‹iPad›." / "Camera: refused from ‹iPad›: not paired." / "Camera: frames dropped while another user is on
  this Mac’s screen." / "Camera: a frame from ‹iPad› did not decode (‹status›); asked for a keyframe." / "Camera
  extension: activation requested." / "…waits for approval in System Settings." / "…activated (build ‹n›)." /
  "…replaced build ‹n› with ‹m›." / "…failed: ‹reason›." / "…removed." The client line gains ", camera 30 fps 2.4
  Mbps" (or ", camera paused (background)").

## 12. Security

- **Only paired sessions**, whatever Require pairing says, and only while the Mac's switch is on; the CLI takes
  nothing (no `camera` in its list); a test host only under its TEST ONLY hook.
- **Nothing a device sends reaches a parser in Sill.app beyond JSON, the frame header and the parameter sets
  CoreMedia reads to describe the format (at most 1 KB an epoch, ten epochs a second at most)**: the frames go to
  VideoToolbox's decoder (on macOS its hardware decoders run in Apple's own decoder service rather than in Sill's
  process; the software fallback's place to confirm), at most 262,144 bytes each, 60 a second,
  sizes inside generation 1; never ImageIO, never a window, never the main actor. A decode failure costs a keyframe
  request, at most one a second.
- **Removed**: StreamServer already passes nothing but key and button ups from a revoked session; the holder is freed,
  Sill Camera shows the placeholder within a second.
- **Another user on the Mac**: Sill Camera is one device for every user of the Mac, so off console nothing of this
  user's device reaches it and its placeholder names nobody; the list drops `camera`.
- **A local process feeding Sill Camera**: the extension takes a sink client only if it is Sill.app by signing
  identifier and, where its sandbox allows, by signature (V6). **Reading Sill Camera**: every app needs the person's
  camera permission, as for any camera; the extension publishes their signing identifiers so the card and the device
  can name the app.
- **The device's person**: the camera runs only with the switch on, Sill in front and a Mac app using it; Sill's chip
  names that app and stops it in one tap; iOS's green dot shows too; nothing is saved on either side (the app on the
  Mac may record, as with any camera, its own business).
- **A hostile Mac** the device connects to can turn the camera on only within those same conditions, visibly.
- **The network**: frames go inside the session's TLS 1.3 connection (the home door's or the remote door's); the CLI's
  plain door never takes a camera.
- **Logs**: device text cleaned (SafeText) before any line; no frame content is logged; the TEST ONLY dump only on a
  test host, into the folder its variable names.
- **Privacy statements**: App Privacy stays "Data Not Collected" (only to the user's own Mac), the privacy page and
  `docs/app-store-metadata.md` §4 change (§14).

## 13. Tests

### 13.1 Pure checks, each with its README.md and mutants (every one caught, CI's matrix from the folders)

- `camera-wire` (new; `Sources/StreamProtocol/*.swift`): the three types round trip; every cap at its edge; refusal,
  not truncation; unknown types and fields skipped; 20,000 random payloads never crash and never yield a value outside
  the bounds; `Hello.camera` and `WindowList.camera` additive both ways (an older type reads the new JSON, the new type
  reads the old). `compatibility` keeps #193's checks, rewritten for the new layout.
- `camera-host` (new; `CameraHostPolicy.swift`, `CameraExtensionState.swift`, `LockPolicy.swift` with what they
  need): every rule of §6.3, then 20,000 random lives of up to four devices (offers, claims, pauses, stops, moves,
  leaves, removals, locks, an app opening and closing Sill Camera) against the invariants: at most one holder; a holder
  always present, offering, paired; nothing wanted off console or without an app; a claim always wins; a move within
  10 s keeps the holder; at most one keyframe ask a second; each line once per change.
- `camera` (new; `iOSClient/CameraPolicy.swift`): `captures` over every combination of its inputs; the pause's
  priority; the format, bitrate and thermal tables; the pacing model of §6.2 on a virtual clock; the words.
- `camera-feed` (new; `CameraFeedPolicy.swift`): the formats, the frame or placeholder at each tick, the sink client's
  acceptance, the placeholder's words (none names a device off console).
- Changed: `display-wake` (kind 46 decided: not a person, frames flow by themselves; 35 kinds), `pointer-control`
  (kind 46 known), `lock-policy` (`list`'s `camera` at each reading), `device-idle` (the camera's use), `compatibility`.

### 13.2 Headless gates on loopback (H list; no encoder, no capture, no simulator)

Every host: `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1
SILL_TEST_REMOTE_DIR=$T/mac SILL_TEST_ASK_FROM_THIS_MAC=1 .build/release/SillHost --synthetic --pairing` with
`SILL_TEST_CAMERA=count` (or `dump:$T/frames`) and a `SILL_TEST_CAMERA_DEMAND` script. Only paired sessions' cameras
count, so each client pairs first (`--pair-ask --then-code=$T/code --identity=$T/a`, as the pairing gates do) and then
connects with `--tls --identity=$T/a`; H5's unpaired client comes in with Require pairing off. The device:
`Scripts/sillclient.py` with `--hello=0.7,1 --camera=FIXTURE` (offers, then sends the fixture's frames at its rate
while wanted), `--camera-claim@T`, `--camera-pause=REASON@T`, `--camera-stop@T`, `--camera-drop=N`, `--raw46=HEX@T`,
each type 3 printed on a line. The fixture: three seconds of a 640×360 test pattern at 30 fps, made once by
`Scripts/camera/make-fixture.swift` with VideoToolbox's software HEVC encoder and committed (about 150 KB).

- H1: demand on at 1 s, off at 4 s: the host decodes every frame sent between (`cam.decoded` equals the client's sent
  count) and none outside; the dump's frames 1, 30 and 60 equal the fixture's own decode.
- H2: a dropped P-frame (`--camera-drop=10`): the host asks for a keyframe within 1 s; decoding resumes at it.
- H3: two clients: A offers, B claims: A hears `another` with B's name, B `wanted`; B stops: A wanted again.
- H4: the lock (`SILL_TEST_LOCKED_FILE`): 1 keeps the camera; 2 drops `camera` from the list, the demand, every frame
  (`cam.refused.offConsole`); 0 brings the demand back with `keyframe` after the settle.
- H5: Require pairing off (`SILL_TEST_REQUIRE_PAIRING=0`), an unpaired client: `unpaired`, its frames dropped.
- H6: a paired client removed mid-stream (the bare `SillMenuBar --synthetic` with `-SillUnpairAfter`, as the remote
  access gates remove one): its frames dropped (revoked), the holder freed within 0.25 s.
- H7: caps: a 300 KB frame, frames of an old epoch, bad JSON, an unknown type, 1,000 frames a second: each dropped and
  counted, the connection kept; meanwhile `--tap` every 0.5 s lands (`in.dry`) within 50 ms (the main actor is free).
- H8: older peers: a client without `Hello.camera` gets no kind 46; the CLI without the hook lists no `camera`, and a
  kind 46 sent to it anyway is ignored.
- H9: the CLI's stdout byte for byte as main's at the same flags, without the hooks.
- H10: a move (sillclient's second connection with the same identity within 10 s): the holder kept, a new epoch decoded.
- H11: the pacing model's numbers against `Scripts/sillrelay.py --rate-mbps 2` in front of the host with a Python
  stand-in of §6.2: a tap's wait stays within the budget (the real check of the device's code is N13).

### 13.3 Harness photos and Mac previews (G list)

- G1: the Settings row in each `-SillCameraCase` (mock only, through `Scripts/harness-photos.sh` on the agents' pair):
  the Duo's 951×669, 669×951, 466×678 and 678×466, the iPad's 1133×744 and 744×1133, an iPhone's 393×852, at the
  default text size and accessibility extra large, with `-SillSettingsScroll camera`.
- G2: the chip (`-SillCameraChip on|paused|fullscreen`) in landscape, the portrait halves, a phone upright and the
  Duo's laptop pose, clear of the clipboard's chip and the link's line.
- G3: `-SillRenderPreviews` from the bare `SillMenuBar` binary: the Devices pane's Camera section in every
  `CameraExtensionState`, macOS 14's and 15's approval words; the card's camera line. Nothing is activated.

### 13.4 The packaging check (P1)

`Scripts/camera-check/package.sh` builds `.build/camera-check/Sill.app` with Sill Camera inside, signed ad hoc, and
checks: the bundle's place and name, its Info.plist keys, the Mach service name's prefix against the app group, the
extension's entitlements (sandbox, group), `codesign --verify --strict` of both, both slices with `SILL_UNIVERSAL=1`.
It never copies to /Applications, never activates, never runs the extension.

### 13.5 On Noah's devices (N list; a Developer ID build of the branch installed by Noah, after the portal steps of §15)

1. Settings › Devices › Use iPhone and iPad cameras on macOS 27: the approval's place and our words; whether Sill.app
   itself asks for the Camera (V2); "Ready".
2. FaceTime on the Mac chooses Sill Camera; the iPad, Share Camera on, streams FaceTime's window: the chip says
   FaceTime; the picture upright, not mirrored for the far end; the delay against a clap (count frames).
3. Photo Booth, QuickTime's New Movie Recording, Zoom, Teams, Meet in Chrome and in Safari: each finds Sill Camera, at
   720p and 1080p, 30 fps (V12).
4. The iPhone upright (pillarboxed), then sideways; turning it mid-call: upright within a second.
5. The back camera.
6. Stop on the chip: the switch off, the Mac's app shows the placeholder.
7. Quit FaceTime: the iPad's camera and its green dot off within a second, the chip gone.
8. Swipe home, and Picture in Picture: "paused" on the Mac; back: the picture within about a second.
9. iPad Split View and Stage Manager: paused, with the footnote; full screen again: back.
10. Lock the Mac during a call: the picture goes on; switch to another user: that user's Photo Booth shows the
    placeholder, no names; back: the picture.
11. iPhone and iPad both on: the last turned on is the camera; the other's footnote; the card.
12. Plug the cable in, then pull it, while the camera runs: at most a second's gap.
13. Away over Tailscale (or a hotspot): 720p; type in a Mac window while the camera runs: no lag beyond the usual.
14. Remove the device in Settings › Devices while it shares: the placeholder within a second.
15. Require pairing off, an unpaired device: no camera, "Pair this iPad…".
16. Thirty minutes of a call with the camera, thirty without: the battery's drop, the warmth, any `camera: thermal`
    line.
17. A 15-minute call without touching the iPad: it stays awake (Q13).
18. Update Now from this build to a later one: whether Sill Camera needs approval again (V4).
19. Remove Sill Camera…, and Sill.app to the Trash: Sill Camera leaves every app's list.
20. VoiceOver on the rows and the chip.
21. Pair This iPad… while the camera runs: the camera pauses, the scanner reads, the camera returns.
22. Camera access refused on the iPad: the footnote and Open Settings.
23. macOS's camera indicator in the menu bar while FaceTime uses Sill Camera (V5).
24. An Intel Mac, if one is at hand: the decode and Sill Camera.
25. With the microphone workstream built too: lip sync in FaceTime.

## 14. Docs, site and App Store words

In the branch: this plan as `docs/camera-plan.md`, its step file (`Scripts/steps.sh new`), CLAUDE.md's Layout
entries for every new file, DEVELOPMENT.md's "The camera" section (installing and approving, `systemextensionsctl
list`, CoreMediaIO's log, the TEST ONLY hooks, the fixture, the harness's arguments, why development builds cannot
activate it), each check's README.

Marked for the release that ships it (between `<!-- Camera -->` and `<!-- /Camera -->` where the page allows a cut):
- `README.md`: Requirements (the device's camera "and, with Share Camera on, to let apps on your Mac use it"; on the
  Mac an administrator allows Sill Camera once, Sill in Applications); How it works, one paragraph; Tips: when Apple's
  Continuity Camera is the better choice.
- `site/privacy.html`: the device's Camera bullet ("to scan the pairing code your Mac shows, and, while Share Camera
  is on and an app on your Mac uses Sill Camera, to send what the camera sees to that Mac. Nothing the camera sees is
  saved, and it goes nowhere else."); the Mac's "Sill Camera" bullet; the page's date.
- `site/support.html`: "Use your iPhone or iPad as your Mac's camera", with the approval, the Applications folder, a
  managed Mac's policy, the multitasking pause.
- `site/index.html`: one line among the features.
- `docs/app-store-metadata.md`: the description's sentence; App Privacy §4's camera sentence; the NEW IN line for the
  review notes (draft, 311 bytes, ASCII): "- Share Camera (Settings > This iPad, off by default): apps on the Mac such
  as FaceTime can use this device's camera as Sill Camera, once Sill for Mac's Settings > Devices > Use iPhone and iPad
  cameras is on and its camera extension allowed. The camera runs only while a Mac app uses it; a Camera chip shows
  it."; a camera scene in the demo video.
- `docs/release-checklist.md`: Part 1 §5 made again with the System Extension capability (with the Developer ID
  certificate's renewal due by 2027-02-01, one trip), a §5b for Sill Camera's App ID and profile, the secrets table;
  Part 2's checks (the extension in the zip and the disk image, its signature, a test install's approval).
- `SECURITY.md`: Sill Camera in scope. The Homebrew tap's README: Sill Camera needs /Applications.

## 15. The order of commits (each passes its gates before the next)

1. Merge #193's head into `camera` (13 hunks, keep both sides; display-wake 35; main's checks README).
2. The wire: `Camera.swift`, the hello and stats fields, kind 46's comment; `camera-wire`, `compatibility`,
   `display-wake`, `pointer-control`; mutants.
3. `CameraHostPolicy` and `CameraExtensionState` with `camera-host`; `LockPolicy.list` with `lock-policy`.
4. The host: `CameraReceiver`, StreamServer and the coordinator, `HostConfig`, the status, the TEST ONLY output and
   hooks; #193's panel removed; the fixture and sillclient's flags; H1–H10.
5. `CameraPolicy` and `CameraPacing` with `camera`; `DeviceIdlePolicy` with `device-idle`.
6. The device: capture, encoder, pattern, glue, `SessionLink`, the rows, the chip, the harness cases; Debug and
   Release builds for the simulator and Debug for a device; G1, G2.
7. Sill Camera: the target, `CameraFeedPolicy` with `camera-feed`, the placeholder; make-app.sh, release.sh; P1.
8. Sill.app: `CameraExtensionManager`, `CameraSink`, the Devices section, the card, previews; G3; H11.
9. The words: §14's documents (the release's parts marked), CLAUDE.md, DEVELOPMENT.md, the step file.
10. A review by an independent reader, its fixes; then Noah: the portal steps (System Extension on
    `me.saffer.sill.mac`, Sill Camera's App ID and profile if V1 needs one, the regenerated profile, the GitHub
    secrets), a Developer ID build he installs, the N list. Never merged without his word.

Steps 1 to 9 need no profile and no device; step 10's first try needs the portal steps first. Builds need the disk's
25 GB (24 GB free on 2026-11-18).

## 16. Risks

- **The Mac side is the unknown part.** Profiles, approval and activation, the sink's permissions and an update's
  replacement are each known only from documentation and third parties (V1–V4); the first real try may change the
  packaging. Mitigation: P1 before any Developer ID build; N1 and N18 early.
- **Managed Macs**: the "work Mac on another Apple Account" case is where MDM blocks third-party system extensions
  (`forbiddenBySystemPolicy`); IT can allow team 9B2KKVM937's extension by policy; the words say so.
- **Input latency on slow uplinks** depends on Network.framework's `.contentProcessed` meaning "taken" on the
  device's side as it does on the host's (V8). Fallback if N13 fails: a lower budget, or a second connection for the
  camera alone (a protocol change, its own plan).
- **iPad multitasking** pauses the camera whenever Sill shares the screen, by iPadOS's rule; people will hit it.
- **Heat and battery** on long calls (N16); the thermal steps limit, not remove, it.
- **App Review**: 2.5.14's indicator, and a reviewer unable to allow a system extension on their Mac; the notes and the
  demo video carry it.
- **Kind 46 contested** by #175; the OVERVIEW decides.
- **A virtual camera that is always listed** (once installed) may puzzle people who turned the switch off; the
  placeholder and Remove Sill Camera… answer it (Q16).
- **Apps' quirks** with virtual cameras (formats, rates, Chrome's and Teams' own handling): N3.
- **Two encoders on the Mac**: a call app encoding Sill Camera's picture beside Sill's stream on the Mac's one hardware
  encoder can push Sill's stream to its software fallback; the encoder recovery handles it, at a cost. Agents never
  run that combination while Noah streams.
- **Scope creep**: effects (Portrait, Studio Light), several cameras at once, a preview on the device, the microphone:
  all later or elsewhere.

## 17. What could not be verified by reading (V list)

- V1: whether Sill Camera needs its own Developer ID profile for a team-prefixed app group, and that the System
  Extension capability on a Developer ID profile needs no request to Apple (the docs describe a capability, no form).
- V2: whether Sill.app needs the Camera permission (TCC), `com.apple.security.device.camera` and an
  `NSCameraUsageDescription` to start Sill Camera's sink stream.
- V3: where macOS 26 and 27 ask for the approval (third-party guides say General › Login Items & Extensions › Camera
  Extensions since 15; Apple's page says Privacy & Security), and whether a standard user can approve.
- V4: whether a newer extension (Update Now, a nightly) replaces an approved one without a second approval.
- V5: whether macOS shows its camera-in-use indicator for a virtual camera.
- V6: whether the extension's sandbox lets it check a sink client's signature by pid (`CMIOExtensionClient.pid`).
- V7: HEVC with low-latency rate control on iOS (`kVTVideoEncoderSpecification_EnableLowLatencyRateControl` speaks of
  "High profiles", H.264's word); if H.264's mode is much better for calls, generation 2.
- V8: how long input waits behind camera bytes on a real uplink with the device's pacing.
- V9: the pull request's CLI crash (by reading: an `NSPanel` made off the main thread under `dispatchMain`).
- V10: Center Stage and iOS's video effects with Sill's own capture session on iPad.
- V11: the iPhone Duo's cameras in each pose (no device; the simulator has no camera).
- V12: each app's acceptance of NV12 1280×720 and 1920×1080 at 15–30 fps.
- V13: the battery and heat numbers (only estimates here).

## 18. Open decisions for Noah (each recommendation is what the work does if he says nothing)

1. **#193's history.** Merge its head into the branch so it shows as merged, then replace most of it (as #355 did with
   #173), or start fresh with `Co-authored-by: aditya dhumal`? *Recommend: merge its head.*
2. **A real camera, or not.** Sill Camera as a Core Media I/O system extension (an administrator allows it once;
   profile work; Sill in /Applications), the pull request's preview window only (no app can pick it), or no camera
   (close #192 and point to Continuity Camera)? *Recommend: the extension; the window alone is not what #192 asks.*
3. **Kind 46.** The camera keeps it (main's comment holds it for the camera) and #175's `cursorKind` moves, or the
   camera moves to the next free number? *Recommend: the camera keeps 46.*
4. **When the device's camera runs.** Only while an app on the Mac uses Sill Camera, or for the whole session whenever
   Share Camera is on (the pull request)? *Recommend: only while used.*
5. **Defaults and label.** Off on both sides, with a "Beta" tag like Send Audio's, or on? *Recommend: off on both,
   Beta.*
6. **Several devices.** One camera, the last device whose person turned Share Camera on (others told who has it), or a
   picker on the Mac? *Recommend: the last turned on.*
7. **Pairing.** Only paired devices' cameras, even with Require pairing off, or any admitted device? *Recommend:
   paired only.*
8. **A locked Mac.** The camera keeps going while the Mac's screen is locked (a call does not drop) and stops while
   another user is on its screen, or stops at any lock? *Recommend: keep at a locked screen, stop off console.*
9. **Codec.** HEVC (as the stream; generation 1), H.264 (its low-latency mode is documented for calls), or JPEG (the
   pull request; several times the bitrate)? *Recommend: HEVC, H.264 later as generation 2 if V7 shows it helps.*
10. **Size and rate.** 1280×720 or 1920×1080 at up to 30 fps as the app asks, 1280×720 at most away from home?
    *Recommend: yes.*
11. **A phone held upright.** Pillarbox its upright picture in the app's landscape frame, crop it to landscape, or
    offer a portrait format too? *Recommend: pillarbox.*
12. **Which camera.** Front by default with a Front/Back choice, or front only? *Recommend: the choice, front by
    default.*
13. **Auto-lock.** While an app on the Mac uses the camera, the device stays awake (as on a call), or the usual 10
    minutes after the last touch? *Recommend: stays awake while used and Sill is in front.*
14. **The chip's Stop.** Turns Share Camera off, or pauses it for this session only? *Recommend: turns it off.*
15. **The Mac's switch.** In Settings › Devices, or in General beside Share clipboard? *Recommend: Devices.*
16. **Sill Camera's presence.** Listed in every app once installed (showing the placeholder when idle), or only while
    Sill runs with the switch on (harder: the extension would need Sill.app to bring it back)? *Recommend: listed once
    installed; Remove Sill Camera… takes it away.*
17. **The app's name on the device.** Tell the device which Mac app uses its camera ("FaceTime on Mac mini"), or only
    that one does? *Recommend: the name.*
18. **With the microphone.** Ship the camera alone when ready, with the microphone's plan (#191) agreeing now to count
    its packets' times from the same session start as `elapsedMs`, or hold both for one "use as webcam" release?
    *Recommend: alone, the time reference agreed now.*
19. **Turning the Mac's switch off.** Leaves Sill Camera installed (its placeholder says to turn it on), removal
    separate, or removes it at once (an administrator's prompt each time)? *Recommend: leave it installed.*

## 19. Sill.app's side as built (step 8): every state a person can end in, and the way out

Settings › Streaming, "Camera and Microphone (beta)": **Use iPhone and iPad cameras**, off by default; under it one line
for the state it is in (CameraExtensionPolicy, its words below), its button, and Remove Sill Camera… when Sill Camera is
installed. The device reads only what the Mac's list and kind 16 say (CameraPolicy's footnote, §11's words).

1. **Never turned on** (the default): nothing is asked of macOS (no request, no prompt, no extension, no CoreMediaIO
   call). The list says `camera` 0, kind 16 `off`: the device's Share Camera is disabled, "Turn on Use iPhone and iPad
   cameras in Sill’s Settings on ‹Mac› to share this ‹device›’s camera with it." Way out: turn it on. (A Sill.app from
   before step 8 says no `camera`: "Update Sill on ‹Mac› to share this ‹device›’s camera with it.", which is right for
   it; the CLI says nothing, and the row hides.)
2. **Turned on, the first time**: "Installing Sill Camera…", and macOS's own alert, “Sill” would like to use a new camera
   extension (Open System Settings, OK); then "Waiting for approval: in System Settings › General › Login Items &
   Extensions, click ⓘ beside Camera Extensions and turn on Sill Camera." with Open System Settings… (macOS 14:
   "… Privacy & Security, click Allow for Sill."). Kind 16 says `notReady`: "Sill Camera isn’t ready on ‹Mac›. In
   Sill’s Settings there, Streaming shows what it needs."
3. **The alert dismissed, or Allow never clicked**: the same waiting line while Sill runs (macOS keeps the request
   pending until Sill quits); every launch with the switch on asks again. Way out: Open System Settings… and turn it on
   there; or turn the switch off (nothing more is asked; an approval given later still installs Sill Camera, unused).
4. **Allowed**: "Starting Sill Camera…" until Sill's feed reaches it, then "Ready. Apps on this Mac can choose “Sill
   Camera”."; the list says `camera` 1 and a device can share. While an app uses it: "In use by ‹FaceTime›, with
   ‹iPad›’s camera.", and the menu's card has "Camera: FaceTime" over "iPad’s camera" under that device.
5. **Sill updated** (another build of Sill Camera inside): at its first launch with the switch on, macOS asks Sill
   whether to replace the older one, and Sill replaces it ("Updating Sill Camera to this version of Sill…", the log's
   "replacing build ‹n› with ‹m›"); then Ready, or the waiting line if macOS wants the approval again (V4, N18).
6. **Sill moved out of /Applications**: "Move Sill to the Applications folder, open it from there, and turn this on
   again."; nothing is asked (macOS activates only from there). A Sill Camera installed earlier from there may still
   take Sill's feed, and then the section says Ready: it works.
7. **A build that cannot install it** (no Sill Camera inside, or no install entitlement: a development build, or a
   profile without the System Extension capability): "This build of Sill can’t install Sill Camera."; nothing asked.
8. **A managed Mac**: "This Mac’s administrator doesn’t allow camera extensions from other developers." (IT can allow
   team 9B2KKVM937's.)
9. **Turned off in System Settings** (macOS 15.1 and later say so): "Sill Camera is turned off in System Settings ›
   General › Login Items & Extensions." with Open System Settings….
10. **A restart needed**: "Restart this Mac to finish installing Sill Camera."
11. **Any other refusal**: "Couldn’t install Sill Camera: ‹reason›." (each of macOS's codes in a few words) with Try
    Again.
12. **Camera access** (V2, if macOS counts Sill's feed as using a camera and Sill is not allowed): "Sill isn’t allowed
    to use cameras, which it needs to pass a device’s camera to apps here. In System Settings › Privacy & Security ›
    Camera, turn on Sill." with Open System Settings…. Every camera build carries NSCameraUsageDescription and, with
    the install entitlement, the camera entitlement, so macOS asks rather than refusing without a word.
13. **Installed, but the feed did not start**: "Sill Camera is installed but didn’t take Sill’s pictures. Turn this off
    and on to try again." (the log has the status).
14. **The switch turned off**: Sill stops feeding at once and asks nothing; Sill Camera is left installed and unused
    (Q19: removing it would ask an administrator each time, and an app set to Sill Camera would lose its camera; on
    again asks nothing new). Apps still list it, its still saying "Open Sill on this Mac and turn on Use iPhone and
    iPad cameras in its Settings." (the extension's one line for no feeder, which covers both Sill not running and
    this). The section: "Sill Camera stays installed while this is off, and apps still list it." with Remove Sill
    Camera…; the device: as 1.
15. **Remove Sill Camera…**: the switch goes off and Sill asks macOS to remove it (an administrator may be asked):
    "Removing Sill Camera…", then "Sill Camera was removed." (nothing to remove counts as removed), or "Couldn’t remove
    Sill Camera: ‹reason›." with Remove again. Sill in the Trash takes it too (macOS).
16. **Two devices sharing**: the last one whose person turned Share Camera on is the camera; the other's footnote
    "‹iPhone› is ‹Mac›’s camera now. Turn Share Camera off and on to use this iPad instead."; the card names the one
    in use.
17. **The device going away mid-call**: a second after its last frame Sill Camera shows "Waiting for ‹iPad›’s
    camera…"; its offer stands 10 s, so a move or a quick reconnect resumes with a keyframe (H10); then "Turn on Share
    Camera in Sill on your iPhone or iPad." (or the most recent other offer takes it). The app keeps its camera.
18. **The device removed** (Settings › Devices › Remove) mid-call: its frames go at once and the camera is free within
    0.25 s (H6): "Turn on Share Camera…".
19. **The Mac locked, or another user on its screen**: refused at any lock (§0): Sill Camera shows "Sill Camera isn’t
    available right now.", naming nobody; frames are dropped and the list says no `camera`. After the unlock (its 2 s
    settle) the demand comes back with a keyframe (H4) while the device's offer stands, else the device offers again.
20. **Sill quits mid-call**: Sill Camera shows its no-feeder line; the device's session ends with it.

## Progress

**2026-11-18, the first building run** (branch `camera`, pull request #401; notes in
docs/steps/2026-11-18-camera.md). Built, on the overview's settlement of §0:
- §15 step 1: #193's head merged (its 13 hunks, both sides kept; display-wake counts 35 kinds and decides 46;
  two mutants moved off numbers now taken), then #193's preview panel, its coordinator hooks and the device's JPEG
  capture and row removed in a commit that says why.
- Step 2, the wire: `Camera.swift` (types 1 to 3, generation 1's bounds, refusal rather than truncation),
  `CameraState` in HostSettings.swift, `Hello.camera`, `WindowList.camera` made exact, ClientStats' four fields;
  the `camera-wire` check (184 cases, 47 mutants) and `compatibility` rewritten.
- Step 3: `CameraHostPolicy` with the `camera-host` check (132 cases, 20,000 random lives, 33 mutants, every one
  caught); LockPolicy's camera (request, refusal, gate, list) with `lock-policy`'s cases and six mutants.
  `CameraExtensionState` waits for step 8, with the extension.
- Step 4, the host up to Sill Camera's seam: `CameraReceiver` (`sill.camera`, VideoToolbox's decoder, the
  `CameraOutput` protocol), StreamServer's route of kind 46 and `sendCamera`, the coordinator's glue (sessions,
  the trust list, the lock, the switch, the list's `camera`, kind 16's), `HostConfig.deviceCamera`, the TEST ONLY
  `CameraTestHook` and `CameraTestOutput`; the fixture (`Scripts/camera/make-fixture.swift`, VideoToolbox's
  software encoder), sillclient.py's `--camera` flags and `Scripts/camera-check/live.py` (H1, H3 to H5, H7, H8).
  The pixel transfer into the app's size (`VTPixelTransferSession`) belongs to the sink, step 8.

- Step 5, its first part: `CameraPolicy` and `CameraPacing` (`iOSClient/CameraPolicy.swift`) with the `camera` check
  (123 cases, 34 mutants, every one caught). `CameraPacing` skips a picture before the encoder while the uplink is
  over the budget rather than dropping encoded frames (§6.2's first draft fell into a keyframe after every frame on a
  slow link). `DeviceIdlePolicy`'s camera is not done.

The closing run (after the first run's usage stop) built the release, ran the loopback gates for the first time
(H1, H3 to H5, H7, H8: every verdict after fixing three of the gates' own), every pure check (77) and the mutants of
camera-wire (45), camera (34), compatibility (42), display-wake (83) and protocol (61), every one caught, and the iOS
app as CI builds it; docs/steps/2026-11-18-camera.md has the numbers.

- The second building run (docs/steps/2026-11-18-camera.md has its numbers): step 5's rest
  (`DeviceIdlePolicy.Uses.camera`, with `device-idle`); step 6 up to the camera itself: `CameraStream` (pure, the
  `camera-stream` check), `CameraEncoder`, `CameraPattern` and `CameraCapture` behind its seam `CameraSource`,
  `StreamClient+Camera` with `DeviceCamera`, the heat's steps (`CameraPolicy.Heat`), SessionLink's `UplinkLedger` and `sendCamera` (`fence`'s `camera` mode),
  the Settings rows, the chip, the harness cases and both plists' words (pbxproj A463 to A468); the gates H2 (a frame
  that does not decode), H9 (the CLI's stdout against main's build) and H10 (a move within the grace); and
  `Scripts/camera-check/encoder.sh`, the device's stream on the Mac's software encoder and decoder.

- The third building run (its notes in docs/steps/2026-11-18-camera.md): the second run's head
  verified in a heavy hold of its own (every loopback gate, every check, the mutants of the checks it touched, the iOS
  builds; one survivor's case added), the photos in another; then step 7 up to what needs the developer portal:
  `CameraFeedPolicy` with the `camera-feed` check, in a library target of its own, `CameraFeed` (not the extension's
  folder: Sill.app's sink shares its encodings, and an executable target cannot be imported); Sill Camera's sources
  (`Sources/SillCameraExtension`: the provider, the device with its source and sink streams, the custom properties
  `state` and `demand`, the placeholder); `Packaging/CameraExtension-Info.plist` and
  `Packaging/SillCameraExtension.entitlements`; make-app.sh's `SILL_CAMERA_EXTENSION` (off by default) and
  `SILL_APP_OUT`; release.sh's check of Sill Camera's slices; P1, `Scripts/camera-check/package.sh`.

- The fourth run (2026-11-23; its notes in docs/steps/2026-11-18-camera.md): main c33d1057 (#399, #396, #402) merged
  in, its five conflicts settled keeping both sides (#402's lock switches, then `deviceCamera`, in HostConfig and its
  check), and verified in a heavy hold of its own; then main 5d062a3c (#389, #418), one conflict (the Settings panel's
  row IDs, both kept), verified by CI; no step of this plan changed.

- The fifth run (2026-11-24; its notes in docs/steps/2026-11-18-camera.md): main 644f03b8 and then 22ab5a3e (#393, the
  whole-screen Settings pane; Share Camera's rows in its device part) merged in; step 8, Sill.app's side:
  `CameraExtensionState` (`CameraExtensionPolicy`, checked by the new `camera-app` with `CameraSinkPolicy`, which lives
  in `CameraFeed` beside Sill Camera's rules), `CameraExtensionManager` (OSSystemExtensionRequest only from Sill.app in
  /Applications with Sill Camera inside and the install entitlement; a dry run in the bare binary), `CameraSink`
  (CoreMediaIO's C API; nothing of it while the switch is off; a dry run in the bare binary), the "Camera and Microphone
  (beta)" section in Settings › Streaming with "Use iPhone and iPad cameras" (off), the card's camera line, previews of
  every state (G3); §19's states and their ways out; the gates H6, H11 and H12 (Sill.app's receiver without the test
  hook). Sill.app now always has a receiver, so its lists say `camera` 0 or 1 and the device's words follow (the known
  defect of "Update Sill on ‹Mac›" gone). make-app.sh's release camera build no longer stops at its first camera line
  (plutil's dotted keys), and adds the camera words and entitlement (V2).

Not yet: Sill Camera running anywhere and Sill.app's real request, sink and approval (Noah's first try, N1 and N2, with
the profile that has the System Extension capability); Share Camera on a device in the hand; the harness photos of the
device's rows inside #393's pane (G1 again); steps 9 and 10.
