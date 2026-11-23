# Recording the stream: the plan

2026-11-18. Issue #284, Noah's: record the stream to a movie, with the Mac's sound, into Files › Sill Recordings.
Noah, 2026-11-18, among the next workstreams: "screen recording". The plan starts from PR #303 (addhumal, one commit,
488fce43), merged as it is and finished here (its review, the assessment, is in the handoff folder beside the plan:
`sill-handoff/next/recording/assessment.md`).

- **Branch:** `recording` from `sill-audio` (#394, the shared sound library, at 98f234d5 on main's eb48ac9f), draft pull
  request #407.
- **Both apps change:** most of the work is the device's. The Mac gains two optional wire fields and the words
  that say a device is recording.
- **Status:** in progress; Progress, at the end, says which of the commits are done.

## What it is, in a person's words

In Sill's Settings, under This iPad (This iPhone), I tap **Start Recording**. Settings closes, 3, 2, 1 counts over the
picture, and a red light comes on with the time and the size: "● 0:07 · 21 MB".

What my Mac shows in the stream is saved as a movie:

- the window or the Desktop at the stream's quality, without Sill's buttons;
- with my Mac's sound when Send Audio and Record Sound are on, even if I muted it on this iPad.

Stopping:

- While it records, a Stop button sits at the top of Settings. I stop it there.
- It also stops when I disconnect, when Sill leaves the screen, or when the iPad is nearly full.

Afterwards:

- I'm told where it went: Files › On My iPad › Sill › Sill Recordings.
- While it records, Sill's menu on my Mac says that my iPad is recording.
- If the picture changes size (I turn the iPad, change Aa, pick another window), Sill saves what it has and starts a
  second movie beside it.
- If space runs low, the light says how many minutes are left.

## Decided, and by whom

- **Noah, #284 (2026-11-02), his request:** "I'd start it from Settings: a 3, 2, 1 count happens, a recording light
  turns on, and then I stop the recording from Settings again. A toggle decides whether the sound is captured too.
  The movie lands in the Files app, in a folder called Sill Recordings."
- **#284's implementation notes, on his issue:**
  - Record on the device from the received stream, "without re-encoding".
  - "starts at a keyframe the device asks the Mac for".
  - "finished cleanly at stop, when the session ends, and when Sill goes to the background".
  - "The sound toggle depends on Send Audio being on".
  - "plain AAC re-encoded on the device may be worth it".
  - "the app's own folder (On My iPhone › Sill) … No iCloud container".
  - "Show the elapsed time and the size while recording, and warn when space runs low".
  - A new size "either closes one file and starts the next, or holds the size": open (decision 3).
  - "the Mac's Sill menu says when a device is recording".
  - "the lock screen and typed passwords included".
- **Noah, 2026-11-18:**
  - This workstream, done with subagents (Opus 5.5 Max).
  - Settings becomes a whole-screen pane (`next/settings-pane`), and "Anything that it would make sense to add a
    toggle to you should add a toggle". The recording's rows go into whichever Settings is on main when this lands.
- **Noah, 2026-11-12 (docs/picture-in-picture-plan.md, question 10):** the Mac's cursor drawn into the stream for
  Picture in Picture was dropped as "too complicated and immersion breaking". Decision 8 follows that.
- **The project's rules** (CLAUDE.md and the docs it points to):
  - the compatibility floor (additive only, no kind reused, a new kind only to a peer that takes it);
  - rules as pure policy types checked with mutants;
  - explicit threading;
  - Apple frameworks only;
  - latency before quality;
  - never the hardware encoder in a test while Noah streams;
  - simulators only through `Scripts/harness-photos.sh`.
- **This plan's defaults:** "Open decisions for Noah" at the end. Each is what the work proceeds with if he says
  nothing.

## The design on one page

```
Settings › This iPad › Start Recording        RecordingPolicy.startAllowed: connected, a picture streams, ≥ 1.5 GB free
  ▼
Settings closes; 3 … 2 … 1 over the picture   VoiceOver: "Recording in 3", "2", "1"
  │ at "1": one kind 44, kept ≥ 1 s from any other ask (RecordingPolicy.keyframeAsk), or the
  │ picture recovery's ask awaited
  │ sill.net keeps the newest keyframe from then on and every frame after it (the pre-roll, ≤ 32 MB)
  ▼
the light (RecordingPolicy.start)
  a keyframe since the ask      ─► the movie's 0:00 is the light; the pre-roll written before it, not shown
  the session's last keyframe,
  and nothing since (still)     ─► the same, from that keyframe
  neither                       ─► "Starting…" until the next keyframe (asked again at the recovery's wait);
                                   10 s, then give up with words
  ▼
sill.net taps (StreamClient.handle, before the display) ─► sill.recorder (StreamRecorder)
  kind 0   its own format description; a different one ends the part, the next part at the next keyframe
  kind 1   RecordingClock: the Mac's stamp → movie time ─► a sample, NotSync on deltas ─► AVAssetWriter, hvc1
  kind 43  its own AudioDecoder ─► RecordedSound (segments, joins, silence) ─► PCM ─► AVAssetWriter, AAC 160 kbps
  every 5 s: RecordingPolicy.space ── low: "· 4 min left" ── under 1 GB: stop
  ▼
Stop (top of Settings) · the session's end · Sill leaving the screen · the device's lock · space · the writer failing
  ▼
endSession(at: the stop's movie time); finishWriting in a background task; the writer's status read; the note
ClientStats.recording (once a second) ─► the Mac: the menu's subtitle, the device's row, Sill.log
```

## Where this starts: building on #303

1. **The branch.** `recording` from main; then `git merge 488fce43`, the contributor's head as it is, so #303 shows as
   merged when this lands (as #355 did for #173).
2. **The four conflicts** (assessment §4), each resolved by keeping both sides:
   - `HostSettingsPanel.swift`: Shake to Show Controls' `@AppStorage`, then Record Sound's.
   - `StreamClient.tearDown`: Picture in Picture's `end(.sessionEnded, …)` first, then `stopRecording()`.
   - `StreamScreen.swift` and `PortraitStreamScreen.swift`: main's `LinkLineView(text:lines:)` and
     `HiddenPictureElement`, with the light added after `LockedMacShade`.
   - The merge commit must build: CI's iOS build.
3. **Kept from #303:**
   - StreamRecorder.swift's name and its four pbxproj entries, AE90/FE90 (rewritten in place);
   - `RecordingBadge`, becoming `RecordingLight.swift`;
   - the key `Sill.recordSound` and its default, on;
   - `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`;
   - `Documents/Sill Recordings`;
   - `stopRecording()` in `tearDown`;
   - DEBUG `-SillRecordFor`;
   - the background task at the end;
   - the count's shape.
4. **Undone from #303:**
   - the taps in `HEVCDisplayView.enqueue` and `AudioOutput.schedule`, both back to main's lines;
   - the rows' place in the Mac's group;
   - the clipboard's note used for the recording's words;
   - stamping by the device's clock on the recorder's queue;
   - the unspaced kind 44.

## The rule

Pure files, Foundation only:

- `iOSClient/RecordingPolicy.swift`: rules 1–3, 5, 6 and 8–11, and `Copy`.
- `iOSClient/RecordingClock.swift`: rule 4.
- `iOSClient/RecordedSound.swift`: rule 7.

All three are checked by `Tests/checks/recording` with mutants. `DeviceIdlePolicy` (rule 12) keeps its own check.
Times are seconds: the Mac's stamps are its wall clock (the header's `timestamp`); device times are `systemUptime`.

### 1. Offered (`startAllowed`, `soundRow`, `recordsSound`)

- **Start is enabled while all of these hold:**
  - the session is connected;
  - a source streams (`active != .none`) and its picture has come (`videoSize != .zero`);
  - nothing is counting or recording in this window;
  - free space is at least `startFloor` (1.5 GB).
- **Otherwise Start is dimmed and says why.** With too little space, a tap shows the space note.
- **Allowed in every other state:**
  - a locked Mac (it records the lock screen, or black off console);
  - away from home;
  - an unpaired session at an open door;
  - a Mac without kind 16, which #303 left without rows.
- **Record Sound** (`soundRow(macHasSound:sendAudio:)`):
  - shown and working while the Mac has sound and Send Audio is on;
  - dimmed, showing off rather than its stored value, with its reason in the footnote, while Send Audio is off;
  - hidden for a Mac without sound.
- **Whether the movie has sound** (`recordsSound(switchOn:sendAudio:)`) is fixed at the light: the switch on and
  Send Audio on.

### 2. The count and the keyframe ask (`countFrom`, `keyframeAsk`)

- **The count.** 3, 2, 1, a second each. Start closes Settings and the count shows over the picture. While it runs,
  Settings' row reads Cancel Recording. The session's end or Sill leaving the screen cancels it.
- **The ask at "1".** Recorded frames start from a keyframe. A still window sends none by itself, and the Mac's
  encoder otherwise makes one only every 4 × fps encoded frames.
- **The ask's spacing.** The host takes one kind 44 a second per connection and drops the rest silently
  (StreamCoordinator.swift:267, 1303). So `keyframeAsk(sinceLastAsk:askOut:)` says:
  - `.awaitRecovery` while the picture recovery's ask is out and inside its wait: its keyframe serves both, as
    Disconnect's fresh picture does (ConnectionList.freshPicture);
  - `.at(last + 1 s)` within `hostSpacing` (1 s) of the last ask by anyone on this connection: the recovery's, the
    fresh picture's or the recording's own;
  - `.now` otherwise.
- **KeyframeRecovery is left as it is.** If its own ask falls inside the host's second after the recording's, the
  host drops it, and the recovery asks again after its wait (4 s), as for any unanswered ask. The recording's
  keyframe usually ends the interruption first, as any keyframe does.
- **While "Starting…"** (rule 3) the ask repeats after `KeyframeRecovery.answerWait(worstRttMs:)` (4 s, or four round
  trips), at most `startAsks` (3) times.

### 3. Where the movie starts (`start`)

At the light, from what `sill.net` has kept since the ask:

- **`.atLight(.sinceAsk)`.** A keyframe came after the ask. The movie's 0:00 is the light. That keyframe and every frame
  after it are written with earlier times. Apple, `startSession(atSourceTime:)`: "The writer adds samples with
  timestamps earlier than the start time to the output file, but they don't display during playback." So the first
  picture is the Mac's picture at the light, decoded from its keyframe.
- **`.atLight(.lastKeyframe)`.** None came, but no frame has come since the session's last keyframe: the client
  already keeps it with its parameter sets for the tile (`lastKeyframe`), and gains a count of frames since it. The
  picture is still, and that keyframe is it. Same start. This also serves a Mac from before kind 44 (Sill for Mac
  0.5.1) whose window is still.
- **`.atNextKeyframe`.** Neither. The light says "Starting…" until the next keyframe, whose time is the movie's 0:00.
  The asks repeat (rule 2). After `startGiveUp` (10 s) without one, nothing is kept and the words say why.
- **The pre-roll** is at most `prerollLimit` (32 MB). Past it, only the newest keyframe and what follows are kept.

### 4. The clock (`RecordingClock`)

Every frame and sound packet has the Mac's stamp S (the header's, wall clock) and its arrival A on the device. The
two tracks share one anchor, so they keep the sync they had on the Mac:

- the picture's stamp is taken as the encoder hands a frame over (StreamCoordinator.swift:2429);
- the sound's is its first sample's capture (AudioPipeline.swift:324–326);
- the picture therefore trails by its encode time, a few ms.

The rule:

1. **The floor.** O is the smallest A − S of the last `floorWindow` (10 s), as AudioPlayout's rule 1.
2. **The anchor.** `.atLight` uses the light's moment on the Mac's clock, A_light − O. `.atNextKeyframe` uses that
   keyframe's S.
3. **Movie time** is T = S + correction − anchor.
4. **A step of the Mac's clock.** Either `stepFrames` (3) frames in a row lie more than `stepLimit` (1 s) above O, or
   one lies more than `stepLimit` below it. The correction then changes so that T goes on where the arrivals say,
   without a jump, and the floor starts again.
5. **Duplicates.** The video's T must come after the last video sample written. A frame that does not is a duplicate
   (a move's hand-over can deliver one twice) and is dropped. It was written already, so the chain stays whole.
6. **The stop's time** is A_stop − O + correction − anchor, never before the last sample written. So a still window's
   last picture lasts until Stop.
7. **Timescales.** Video times use 90,000; the sound uses 48,000, sample-exact.

### 5. The picture's samples (`frame`)

- **What is written.** Every kind 1 is taken on `sill.net` before the display sees it, as the Picture in Picture
  plan's note on #284 foresaw. So the display's own waits do not apply:
  - Picture in Picture's pause (`HEVCDisplayView.setFrozen`);
  - a flushed layer waiting for its keyframe;
  - a locked Mac's blank.
- **Its fate:**
  - `write`: a keyframe, or a delta while the chain is whole.
  - `waitForKeyframe`: after any frame not written (the writer not ready, `pendingLimit` exceeded, a sample that
    could not be made), every delta is dropped until the next keyframe. One ask goes out (rule 2) and the drop is
    counted.
  - `duplicate`: rule 4.5.
- **The sample.**
  - It is made by the recorder, from the frame's bytes and its own format description (made from the parameter sets
    as `HEVCDisplayView.apply` does), never from the display's sample.
  - A delta carries `kCMSampleAttachmentKey_NotSync = true` and `DependsOnOthers = true`; a keyframe carries neither.
    Apple: samples "are assumed to be sync samples by default", and the attachment "is read from and written to media
    files".
  - PTS = T. DTS is invalid: no B-frames, `AllowFrameReordering` is off on the Mac. Duration is invalid: the next
    sample's time gives it, and the stop's for the last (rule 4.6).
- **The bound.** `pendingLimit` is 32 MB of frames waiting on `sill.recorder`. Latency before quality: a frame is
  dropped before it queues without bound.

### 6. Parts (`newPart`, `fileName`)

- **What ends a part.** A kind 0 whose sets differ from the part's (the display's own test) ends it at its arrival:
  `endSession` there.
- **Why this happens:**
  - a rotation or an Aa step resizing the window;
  - another window or the Desktop at another size;
  - the Desktop stepping to a display of another size;
  - the Mac locking (its lock screen at the display's size), or another user (the black placeholder);
  - the encoder falling back to software.
- **The next part** starts at the next keyframe, which is its 0:00. The light keeps counting the whole recording, and
  the size counts every part.
- **Names:**
  - "Sill 2026-11-18 at 14.03.12.mov", from the light's moment on the device's clock (Gregorian, POSIX digits,
    24-hour, whatever the person's calendar and clock settings);
  - its parts "Sill 2026-11-18 at 14.03.12 (2).mov", "(3)" and so on, so they sort together;
  - a name already taken (two windows recording, a clock gone back) gets the next free number.

### 7. The sound (`RecordedSound`)

Only when the movie records sound (rule 1). Its own decoder (`AudioDecoder`, one per epoch) on `sill.recorder`. The
playout, the engine, Mute, Picture in Picture and a call change nothing.

- **Packets ignored:** those of an epoch without a format, and duplicate (epoch, seq) pairs.
- **A segment start.** Reset the decoder, drop the format's `primingFrames`, fade in 5 ms. Placed by its stamp, plus
  priming ÷ 48,000.
- **The next seq of the epoch.** Placed right after the last, sample-exact. If its stamp puts it more than
  `driftLimit` (20 ms) away, it is placed by stamp with a fade instead.
- **A skipped seq.** Reset, decode and drop it whole; place the next by stamp and fade it in (AudioDecoder's join: the
  first packet after a gap decodes to noise).
- **Gaps and overlaps.** Silence fills every gap between the track's end and the next placement. A packet that would
  overlap the track's end loses its overlapping frames, or is dropped if all of them overlap.
- **The track follows the picture.** At each video sample at T, silence fills up to T − `soundLag` (0.5 s) if nothing
  has come that far: Send Audio turned off mid-recording, or a Mac that sends no sound for a while. So neither track
  waits on the other.
- **At the stop**, silence to the stop's time.
- **The output:** AAC, 48 kHz stereo, 160 kbps (`AVFormatIDKey` MPEG4AAC, an explicit stereo `AVChannelLayoutKey`),
  as #303 and #284's R8.

### 8. What ends it (`Ending`)

| Ending | What happens |
|---|---|
| Stop (top of Settings); Cancel during the count | the movie closes; the note |
| The session's end (`tearDown`: Disconnect, a goodbye, a loss no move carries) | the same; the note on the connect screen |
| Sill leaves the screen: the app to the background, or this window's scene to the background, Picture in Picture or not (decision 4) | finished in a background task (with an expiration handler that finishes what it can); the note when Sill comes back |
| The device's lock | it reaches Sill as the background; `protectedDataWillBecomeUnavailable` as a second word |
| Space under `stopFloor` | the movie closes; the space note |
| The writer fails | what was written is kept (fragments, below); the words name the reason |
| The start gives up (rule 3) | nothing kept; the words |

**Never an end:**

- a move to another path (cable, Wi-Fi, home);
- a locked Mac or another user on it;
- a new size (a part);
- the link falling behind;
- Send Audio turned off;
- Mute;
- the Settings pane covering the picture (decision 2).

**Movie fragments.** Every movie is written with `movieFragmentInterval` 4 s. Apple: fragments let you "open and play
a partially written movie in the event that an unexpected error or interruption occurs". So a crash, a force quit
or a full disk loses at most the last seconds, not the recording.

### 9. Space (`space`)

- **When it looks.** Every 5 s, at `volumeAvailableCapacityForImportantUsage` of the folder's volume, with the rate
  over the last 10 s of bytes written.
- **What it says:**
  - `.stop` below `stopFloor` (1 GB);
  - `.low(minutesLeft)` below `warnFloor` (3 GB), or when (free − stopFloor) ÷ rate is under `warnMinutes` (5);
    minutes left = ⌊(free − stopFloor) ÷ rate ÷ 60⌋, at least 1;
  - `.fine` otherwise.
- **The start** is refused below `startFloor` (1.5 GB).
- **Where the numbers live:** one place (decision 11). The rig passes smaller ones.
- **Privacy manifest:** this needs `NSPrivacyAccessedAPICategoryDiskSpace`. Its reasons are E174.1 ("check whether
  there is sufficient disk space to write files") and 85F4.1 ("display disk space information … units of time
  combined with a media type"). The value never leaves the device.

### 10. The light (`light`)

- **Its words:** "0:42 · 126 MB", "1:02:03 · 1.4 GB". While low, "· 4 min left" is added. Before the first frame,
  "Starting…".
- **Spoken:** "Recording, 42 seconds, 126 megabytes", with ", space for about 4 minutes" while low.
- **Time** is the newest sample's movie time, never the wall clock, so the light and the movie agree.
- **Bytes** are the frames' bytes written, plus the sound's 20 kB a second, plus 1% for the container. MB below
  1,000 MB, GB with one decimal above.

### 11. The Mac is told (device side)

- **What the device sends:** `ClientStats.recording` is true in every report from the light ("Starting…" included)
  until the movie is closed, and left out otherwise (`recordingField`).
- **What the device says about it:** the footnote words the Mac's side by `WindowList.recordings`.
  - 1: "While it records, Sill’s menu on ‹Mac› says so."
  - None: "‹Mac› runs an older Sill, so its menu won’t say that this iPad is recording." Recording is still allowed
    (decision 7).

### 12. Auto-lock (`DeviceIdlePolicy`)

- **The change:** `Uses.recording` is the last moment this window recorded; `lastUse` takes it into account.
- **The effect:** while it records (in the foreground: rule 8), the device does not lock itself. After the stop the
  usual 10 minutes run.
- **This is decision 9:** a long recording nobody touches would otherwise end when the device locked, 10 minutes plus
  its Auto-Lock after the last touch.

## The wire (additive)

| Where | Field | Who sends it, and to whom |
|---|---|---|
| `ClientStats` (kind 12, device → host, once a second) | `recording: Bool?` | true while this device records the stream, left out otherwise. Every host may get it: an older one ignores the key (`Wire.decode` is a plain JSONDecoder). Display only: a host shows it and acts on nothing. |
| `WindowList` (kind 2, host → device) | `recordings: Int?` | 1 (`RecordingNotice.generation`): this host shows in its menu and its log when a device records. Set after the initializer, as `keyRepeat`, in every list, locked ones too. Nil from every host before; an older device ignores it. |

- **No new kind.**
  - Kind 44 is used as today, through the device's spacing (rule 2).
  - 29–31 and 33–42 stay PR #66's.
  - 45 and 46 stay with #191 (microphone) and #193 (camera).
- **No enum and no renamed field.**
- **Mixed builds:**
  - a new device and an older Mac: it records; the footnote says that Mac won't show it; the Mac ignores the field;
  - an older device and a new Mac: nothing changes;
  - SillHost says `recordings` 1 too, and prints the lines.
- **The compatibility floor** (docs/COMPATIBILITY.md) gains both, once a public build carries them: a later device keeps sending
  `recording` while it records, and a later host keeps showing it.

## The Mac

- **`Sources/SillHost/RecordingNotice.swift`** (new, pure, `package`):
  - `generation` (1).
  - `Lines`: the log's line at each change, at most one per connection every `lineSpacing` (10 s); changes in between
    are counted in the next line. A connection that closes while recording gets "left while recording".
  - Checked by `Tests/checks/recording-notice`, with mutants.
- **`HostStatus.swift`:** `Device.recording: Bool` (false).
- **`StreamCoordinator.swift`:**
  - every window list gets `recordings = RecordingNotice.generation`;
  - `server.onClientStats` sets `devices[i].recording = stats.recording == true` and prints a line on a change;
  - a connection closing while recording gets its line.
  - No other state, nothing kept past the connection.
- **`Sources/SillMenuBar/StatusText.swift`** (all status copy):
  - **the headline's subtitle** while any device records: "‹iPad› is recording the stream." or "‹n› devices are
    recording the stream.". It goes first, before whatever else the subtitle says (the off-console view's line, test
    pattern mode's, Screen Recording off's), and in place of "Pick a window…".
  - **the device's row:** its detail starts "Recording · ".
  - **the status item's glyph** is unchanged (decision 6).
- **`DebugHooks.swift`:** samples `recording` (one device) and `recording-two` (two devices, one recording), as cards
  and in menu.txt.
- **`Scripts/sillclient.py`:** `--recording@T` and `--recording-off@T` set the field in its stats; each list line
  prints `recordings=`.
- **Nothing else.** No permission, entitlement, driver, system extension or private interface. Recording changes
  nothing about what the Mac streams or captures.

## Files

**Device, new** (pbxproj: four entries each, A…A284/F284 to A…A288/F288, free on main and on #184, #189, #191, #193
and #200):

- `iOSClient/RecordingPolicy.swift`: rules 1–3, 5, 6, 8–11, and every sentence (`Copy`). Pure.
- `iOSClient/RecordingClock.swift`: rule 4. Pure.
- `iOSClient/RecordedSound.swift`: rule 7. Pure.
- `iOSClient/StreamClient+Recording.swift`, on the main thread:
  - start, cancel, stop;
  - the count;
  - the asks (with KeyframeRecovery and Disconnect's fresh picture);
  - the endings (app and scene background, the device's lock, the session's end);
  - the space results;
  - the note;
  - `ClientStats.recording`;
  - the folder (`Documents/Sill Recordings`, made with `FileProtectionType.completeUnlessOpen`: readable only while
    the device is unlocked; a movie still open at the lock is finished).
- `iOSClient/RecordingLight.swift` (SwiftUI):
  - the count and the light over the picture;
  - the Stop row at the top of Settings;
  - the note view (its own, not the clipboard's).

**Device, rewritten from #303:** `iOSClient/StreamRecorder.swift`.

- Imports AVFoundation, CoreMedia and AudioToolbox only, never UIKit, so the rig compiles it on the Mac. It takes its
  folder from its caller.
- Holds the writer per part, its own format descriptions, the samples (rule 5), the clock, the decoder and
  RecordedSound, AAC input settings, fragments, `startSession` at the anchor, and `endSession` at the stop.
- Checks `status` before `markAsFinished` and `finishWriting`, and reads `error` for the words.
- Keeps the pending bound and the space timer.
- Pbxproj AE90/FE90, #303's.

**Device, changed:**

- `StreamClient.swift`:
  - `recordingTap` on `queue`, set and cleared there;
  - in `handle`: kind 0 to the tap; kind 1 with `header.timestamp`, `isKeyframe` and `CACurrentMediaTime()` before
    `onFrame`; `framesSinceKeyframe` beside `lastKeyframe`;
  - `tearDown`'s stop after Picture in Picture's end;
  - the scene's and the app's background observers for rule 8;
  - `protectedDataWillBecomeUnavailable`.
- `StreamClient+Audio.swift`: `receiveAudio` hands the parsed message and its stamp to the tap too.
- `HEVCDisplayView.swift`, `AudioOutput.swift`: #303's taps removed.
- `DiagnosticsHUD.swift` (`ClientStatsReporter.report`): `recording`.
- `HostSettingsPanel.swift`, or the settings-pane's pane, whichever is on main:
  - the recording group first in This iPad (This iPhone);
  - the Stop row pinned at the top while counting or recording;
  - `-SillSettingsScroll recording`.
- `StreamScreen.swift`, `PortraitStreamScreen.swift`:
  - the light over the picture, its corner by the link's line;
  - the note in the clipboard chip's corner rules (`ClipboardPolicy.chipCorner`), never at the same time as the chip.
- `ContentView.swift`:
  - the note on the connect screen after a session ended while recording;
  - the harness contract: `-SillRecording`, `-SillRecordFor`, `-SillRecordingSpace`, `-SillRecordingFail`.
- `MockCatalog.swift`: the mock's states; `recordings` 1 in the mock Mac's lists except the `legacy` case.
- `DeviceIdlePolicy.swift`, and StreamScreen's `DeviceIdleTimer`: `Uses.recording`.
- `Info.plist`, `Info-Debug.plist`: the two keys (#303's).
- `PrivacyInfo.xcprivacy`: DiskSpace, E174.1 and 85F4.1.
- `Sill.xcodeproj/project.pbxproj`.

**Wire:**

- `Sources/StreamProtocol/Viewport.swift` (`ClientStats.recording`, init parameter last, default nil);
- `Sources/StreamProtocol/Switcher.swift` (`WindowList.recordings`).

**Mac:** RecordingNotice (new), HostStatus, StreamCoordinator, StatusText, DebugHooks.

**Scripts:**

- `Scripts/sillclient.py`;
- `Scripts/recording-check/` (new: `build.sh`, `run.sh`, `recordcheck.swift`, `moviecheck.swift`; the rig,
  described under Tests);
- `Scripts/harness-photos/recording.cases` (new);
- `Scripts/release-ios.sh`: the .ipa check gains the two Files keys.

**Checks:**

- `Tests/checks/recording` (new);
- `Tests/checks/recording-notice` (new);
- `compatibility` (ClientStats and WindowList, new and old decoders);
- `device-idle` (with its mutants).

**Docs:**

- `docs/recording-plan.md` (this plan);
- `docs/steps/<date>-recording.md` (`Scripts/steps.sh new`);
- docs/LAYOUT.md (the files, the wire's fields), docs/BUILD-AND-RUN.md (the commands, the harness arguments) and
  docs/COMPATIBILITY.md (the floor, once public); CLAUDE.md stays as it is;
- `docs/DEVELOPMENT.md`;
- README, `site/support.html`, `site/privacy.html` and the App Store texts, marked for the release;
- `site/contribute.html`: Aditya Dhumal's #303.

## Threading

- **`sill.net`** (StreamClient's `queue`):
  - The taps read `recordingTap` (set and cleared on this queue) and call `take`, which appends to the recorder's
    pending list under its lock.
  - `take` counts bytes. It never copies a payload (Data is shared) and never waits. Past `pendingLimit` it marks
    "wait for a keyframe".
  - The pre-roll during the count lives here.
- **`sill.recorder`** (StreamRecorder's own serial queue, `.userInitiated`):
  - the clock;
  - format descriptions and sample buffers;
  - the AudioDecoder;
  - RecordedSound;
  - every AVAssetWriter call;
  - the space timer (a DispatchSourceTimer on this queue);
  - the writer's status.
  - Results go to the main thread by `DispatchQueue.main.async`.
- **Main:**
  - StreamClient+Recording's state, published for the views;
  - the count's timer;
  - the asks (KeyframeRecovery lives here);
  - the endings' notifications and the background task;
  - DeviceIdleTimer;
  - the note.
- **AVAssetWriter's `finishWriting` completion** runs on any thread. It hops to `sill.recorder`, then to main.
- **`sill.audio`** is untouched. The recorder never touches the playout, its engine or the audio session.

## Settings: names, places, defaults

| Setting | Where | Default | Sent |
|---|---|---|---|
| `Sill.recordSound` (#303's key) | Settings › This iPad (This iPhone) › Record Sound | on | never |

Start Recording, Cancel Recording and Stop Recording are actions, not settings. Nothing on the Mac. The space numbers
and the fragment interval are constants in RecordingPolicy, not settings.

## Every sentence shown to a person

All of them live in `RecordingPolicy.Copy` (device) and `StatusText` and `RecordingNotice` (Mac). "‹iPad›" is "iPad" or
"iPhone"; "‹Mac›" is the Mac's name, or "the Mac".

**Settings, This iPad (This iPhone), first group:**

- **The button:**
  - "Start Recording".
  - During the count: "Cancel Recording".
  - Dimmed while nothing streams, with the hint "Pick a window or the Desktop first.".
- **The switch:** "Record Sound".
- **The footnote** (sentences joined as they apply): "Saves what ‹Mac› shows as a movie in Files › On My ‹iPad› ›
  Sill › Sill Recordings, without Sill’s controls or ‹Mac›’s pointer, until you delete it or Sill. Everything on the
  screen is recorded, its lock screen and what you type included."
  - Then one of: "While it records, Sill’s menu on ‹Mac› says so." or "‹Mac› runs an older Sill, so its menu won’t
    say that this ‹iPad› is recording."
  - With Send Audio off: "Turn on Send Audio above to record ‹Mac›’s sound."
- **The row at the top of Settings while recording:** "Stop Recording", with "Recording · 1:42 · 230 MB" under it.
  VoiceOver reads "Stop Recording. Recording, 1 minute 42 seconds, 230 megabytes.".

**Over the picture:**

- **The count:** "3", "2", "1". VoiceOver: "Recording in 3", "2", "1".
- **The light:**
  - "Starting…" (VoiceOver: "Starting the recording");
  - then "0:42 · 126 MB";
  - while low, "0:42 · 126 MB · 4 min left", and once, spoken: "Space for about 4 more minutes of recording.".
  - At the start VoiceOver hears "Recording".

**The notes** (over the stream, in the chip's corner, 4 s; on the connect screen after a session ended; in Settings'
top row when Stop was tapped there):

- "Saved to Files › Sill Recordings."
- "Saved 3 movies to Files › Sill Recordings, one for each picture size."
- "Your recording was saved when Sill left the screen. It’s in Files › Sill Recordings."
- "Recording stopped: this ‹iPad› is almost out of space. What was recorded is in Files › Sill Recordings."
- "There isn’t enough space on this ‹iPad› to record. Free up some space first."
- "Recording stopped: ‹the writer’s reason›. What was recorded is in Files › Sill Recordings."
- "Couldn’t save the recording: ‹the writer’s reason›."
- "Couldn’t start recording: ‹Mac› didn’t send a full picture." When the Mac is older than kind 44 (`hostVersion`
  nil or 0.5.1 and before), " Update Sill on ‹Mac›, then try again." is added.

**The Mac:**

- **Menu subtitle:** "‹iPad› is recording the stream." / "‹n› devices are recording the stream."
- **Device row:** "Recording · 118 fps · frame age 9 ms · RTT 7 ms · Wi‑Fi".
- **Sill.log:**
  - "Recording: ‹iPad (iPad14,1)› started recording the stream." (every feature's line starts with its name:
    the overview's §2.1)
  - "Recording: ‹iPad (iPad14,1)› stopped recording the stream."
  - "Recording: ‹iPad (iPad14,1)› left while recording the stream."
  - Changes the limiter held back: "(3 more changes since the last line)".

## Security

- **Who starts it.** Only the person at the device: Start in Settings, then a 3-second count, then the light.
  - Nothing the Mac or the network sends starts or stops a recording.
  - `-SillRecordFor` and the other `-SillRecording…` arguments are Debug only (StreamScreen's `runLaunchArguments` and
    MockCatalog are inside `#if DEBUG`).
  - App Review 2.5.14 ("explicit user consent and … a clear visual and/or audible indication when recording … screen
    recordings") is met by the button, the count and a light that is on screen whenever a recording runs (rule 8,
    decision 4).
- **The Mac's notice is a courtesy, not a control.** A device that wants to record without saying so can use iOS's
  own recording, a camera, or a modified build. Sill's builds always say so, and the words never claim more.
  - The field is display only.
  - The device's name was already cleaned (`SafeText.label`: one line, at most 64 characters).
  - The log's lines are limited to one per connection every 10 s, so a device flipping the field cannot flood
    Sill.log.
  - Nothing survives the connection.
- **Paired, unpaired, removed:**
  - A paired device records what it sees. An unpaired one at a door that lets it in (Require pairing off) does the
    same.
  - A removed device is cut off: its session ends, and so does its recording. It keeps the movies it made, as it
    keeps what it saw.
- **A locked Mac.** Recording changes nothing about what the Mac streams.
  - With its screen locked: the lock screen (`lockScreenStreams`), with what is typed shown as the Mac shows it.
  - Off console: the black placeholder.
  - The device's covers are never in the movie.
  - The menu says "recording" once the Mac is unlocked and someone looks.
- **A hostile or broken Mac.** It can fill a recording as fast as the link carries. Bounded by:
  - the space floor;
  - `pendingLimit`;
  - `StreamMessage.maxFramePayload` (32 MB);
  - the parameter sets and sound formats taken as the display and the playout take them (the decoder is the
    playout's AudioDecoder).
- **The files:**
  - `UIFileSharingEnabled` shows all of Documents in Files and in Finder over the cable. A source rule in
    `Tests/checks/recording` fails if any iOSClient file but `StreamClient+Recording.swift` names
    `documentsDirectory` or `.documentDirectory` (StreamRecorder takes its folder from it), so the device key, saved
    Macs or pictures can never land there by a later change.
  - The folder is `completeUnlessOpen`.
  - While the whole-screen Settings covers the picture, its top row ("Recording · 1:42 · 230 MB") is the light.
  - The movies are in the device's backups like any document, deleted with Sill, and the words say both
    (decision 10).
- **Privacy page:** what travels (the field), what stays (the movies, Record Sound), what the Mac's log keeps (which
  devices recorded and when). The App Privacy answers stay "no data collected".

## Tests

### Pure checks, with mutants (every mutant caught; CI's matrix reads the folders)

- **`Tests/checks/recording`.** Compiles RecordingPolicy.swift, RecordingClock.swift, RecordedSound.swift and
  KeyframeRecovery.swift (for `answerWait`) with its `main.swift`. It checks:
  - **the rules:**
    - each rule's cases;
    - the start's three ways;
    - the asks against a recovery's ask at every age;
    - parts and names (calendars, a taken name);
    - the endings table;
    - space at its edges;
    - the light's words in both units;
  - **20,000 random recordings against invariants:**
    - each track's times strictly increase;
    - a Mac clock step never makes a jump;
    - the stop is never before the last sample;
    - the sound's track has no gap and no overlap, with silence wherever nothing came;
    - no delta follows an unwritten frame before a keyframe;
    - the start never waits without an ask due;
  - **the source rules** (Documents, no UIKit in StreamRecorder).
  - About 45 mutants, one per constant and per comparison that matters (rule 2's 1 s, rule 4's step, rule 5's wait,
    rule 9's floors, rule 7's drift and lag).
- **`Tests/checks/recording-notice`:** RecordingNotice.swift. The limiter, the left-while-recording line, and its
  mutants.
- **`Tests/checks/compatibility`:** ClientStats with and without `recording`, and an old decoder taking a new report;
  WindowList with `recordings` and an old decoder.
- **`Tests/checks/device-idle`:** `Uses.recording`, and its mutants.

### Headless gates

All on loopback synthetic hosts: `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1
SILL_TEST_NO_SCREEN=1`, never the hardware encoder.

| Gate | What |
|---|---|
| G1 | The two new checks and the two changed ones, each with `--mutants` |
| G2 | The Mac. `swift build -c release`. `sillclient.py PORT 20 desktop --recording@2 --recording-off@13`: Sill's lines at 2 s and 13 s (a stop within 10 s of the start waits for the spacing, or for the close), and on a second connection a flood (`--recording@3`, `--recording-off@3.2` …) in two lines, the second with its count. The bare SillMenuBar (never a bundle) `--synthetic -SillLogFile … -SillMenuAfter '4; 10'` with that client: the subtitle and the row while it records, gone after. `-SillRenderPreviews`: the two new samples, every other card byte for byte as main's. |
| G3 | The rig, `Scripts/recording-check/run.sh` (next) |
| G4 | The iOS app, Debug and Release for the simulator and Debug for a device. Only the known StreamClient capture warning: the iOS 27 SDK deprecates `AVAssetWriterInput.append` and the real-time flags, which must not warn at the iOS 17 target. The built Info.plists carry both Files keys, the built privacy manifest carries DiskSpace, and `release-ios.sh`'s check finds DiskSpace declared. |
| G5 | Harness photos (below) |
| G6 | `Tests/checks/run-all.sh`: all pass |

### The rig (`Scripts/recording-check/`)

The device's recorder without a device.

- **`build.sh`** compiles two binaries:
  - `recordcheck`: `recordcheck.swift` with Sources/StreamProtocol (import stripped), AudioDecoder.swift,
    KeyframeRecovery.swift, the three pure files and StreamRecorder.swift, as one module. It refuses a binary that
    imports any `VTCompressionSession` symbol: passthrough writing never encodes video.
  - `moviecheck`: AVFoundation reading only. It never decodes video.
- **`recordcheck`** acts as a device:
  - a hello listing aac-eld;
  - pings and stats with `recording`;
  - the start rule and asks, as StreamClient+Recording does them;
  - movies written into `.build/recording-check/<case>/`, the anchor and every sample's stamp beside them.
- **`moviecheck`** reads each movie:
  - its tracks (`hvc1`, `aac`) and duration;
  - its edit list's start;
  - every video sample's time and its NotSync attachment (AVAssetReader passthrough);
  - the sound decoded to PCM, and each of the test tone's clicks (TestTone: one at each whole second of the Mac's
    stamps) found against its stamp's movie time.
- **The cases, each under a minute:**
  - `plain`: 20 s with the tone. Two tracks; the length is the stop's ±0.1 s; the keyframes are the sync samples and
    nothing else; each frame's time is its stamp − anchor within one tick; each click within 5 ms of its stamp's
    time.
  - `still` (`SILL_TEST_STILL_AFTER=3`): the movie lasts to the stop and ends on its last picture. This settles
    whether AVFoundation gives the last sample the session's end, as rule 4.6 needs. If it does not, the recorder
    holds the newest frame back until the next one, or the stop, gives its duration.
  - `still-sound`: the same with the tone. The sound runs on while the picture is still, and neither input stalls
    the other (AVAssetWriter's interleaving of a still track is not documented).
  - `preroll`: the ask at "1", the light 1 s later. The edit list starts at the light, and the first sample before it
    is the keyframe.
  - `parts` (`SILL_TEST_DISPLAYS` with two stops of different sizes, a kind 47 at 6 s): two movies, "(2)" from a
    keyframe.
  - `lock` (`SILL_TEST_LOCKED_FILE`: 2 at 5 s, 0 at 10 s): the placeholder in a part of its own, then the Desktop
    again.
  - `oldmac` (`SILL_TEST_KEYFRAME_IGNORE=1000`): with `SILL_TEST_STILL_AFTER=1` it starts from the last keyframe;
    without it, it starts from the next one; asks repeat at the recovery's spacing.
  - `kill`: the rig killed with SIGKILL at 12 s. The movie opens, at least 7 s long (fragments every 4 s).
  - `full`: the folder on a 64 MB disk image (`hdiutil create`, mounted `-nobrowse` in `$TMPDIR`), the floors passed
    small (`--stop-floor 8m --warn-floor 16m`), `SILL_TEST_PATTERN=noise`. The low line, then the stop, with words.
    With `--no-space-rule`: the writer fails; the words, no "Saved"; the movie opens.
  - `move`: a second connection to the same host takes over mid-recording (the rig's `--reconnect-at`). This only
    approximates a move's fenced hand-over: it has no SessionLink. No duplicate written; the clock continuous.

### Harness photo cases (`Scripts/harness-photos/recording.cases`, against main's)

Every case has `-SillLayout`. None dials a host.

- The Settings group:
  - default;
  - Send Audio off (`-SillSettingsCase soundoff`);
  - an older Mac (`legacy`);
  - nothing streaming (`-SillActive none`).
- The Stop row at the top (`-SillRecording on -SillSettings 1`).
- `-SillRecording count` (the "3").
- `-SillRecording starting`.
- `-SillRecording on` (the light with time and size) in each layout:
  - the Duo's 951×669 and 669×951 (`-SillHinge flat`, `half`);
  - its cover, 466×678;
  - the iPad's 1133×744 and 744×1133 (`-SillIdiom pad`);
  - an iPhone's 393×852 upright with and without `-Sill.largerPicture 1`.
- The light beside the link's line (`-SillLinkLine behind`).
- `-SillRecording low`.
- The notes: `saved`, `parts`, `space`, `failed`, `gaveup`, on the stream and on the connect screen.
- Accessibility extra large text for the panel and the light.

A live simulator run is not planned. `harness-photos.sh` refuses `-SillLive`, and no agent makes a simulator of its
own; the rig stands in for it, and Noah's devices for the rest.

### For Noah, on his devices (a Debug build of the branch, Sill.app from the branch, `tail -F ~/Library/Logs/Sill/Sill.log`)

1. **The rows.** Settings › This iPad: Start Recording first, Record Sound under it, and the footnote whole.
   - With Send Audio off, Record Sound is dimmed and the footnote says to turn on Send Audio.
   - With nothing streaming, Start is dimmed.
2. **A minute of a video.** A video playing on the Mac (QuickTime Player), Send Audio on, Record Sound on: Start.
   - Settings closes, 3, 2, 1, the light with time and size.
   - After a minute, open Settings: Stop at the top with the time; tap it: "Saved to Files › Sill Recordings." there.
   - In Files › On My iPad › Sill › Sill Recordings: the movie plays in Files' preview with its sound in step with
     the picture (clap on camera if you can), and lasts the light's time. The size Files shows is near the light's.
3. **The Mac's menu.** While it records: "iPad is recording the stream." under the menu's headline, and the iPad's
   row starting "Recording". Sill.log's two lines, at start and at stop.
4. **Mute.** Mute on in Settings during a recording: the movie still has the sound.
5. **A still window.** Terminal idle, sound off, 30 s: the movie lasts 30 s, showing the window throughout.
6. **Scrubbing.** Drag through P2's movie in QuickTime Player on the Mac (AirDrop it), and trim it in Photos after
   Save Video: no smeared or grey pictures anywhere.
7. **A new size.** Turn the iPad (or change Aa) mid-recording: "Saved 2 movies…", "… (2).mov" from the turn on, both
   playing.
8. **The Mac locks.** ⌃⌘Q mid-recording, unlock after 10 s:
   - the lock screen in its own movie; nothing of the cover's words in it;
   - the Mac's menu after the unlock: still "recording".
9. **Leaving Sill.** Swipe home mid-recording (Picture in Picture off): the movie ends whole there. Back in Sill:
   "Your recording was saved when Sill left the screen…".
10. **Picture in Picture on.** The same: the recording ends as the picture floats (decision 4). Say whether you would
    rather it went on.
11. **Disconnect mid-recording.** The connect screen says "Your recording was saved…", and the movie is whole.
12. **The Mac quits Sill mid-recording.** The same.
13. **The device's lock.** The top button mid-recording: the movie is whole.
14. **Untouched for 15 minutes** while recording: the iPad did not lock itself (decision 9).
15. **Space.** With less than 3 GB free, or DEBUG `-SillRecordingSpace 2900000000`:
    - the light's "· N min left" and its one spoken line;
    - at 1 GB it stops by itself with the words, and the movie plays.
16. **Force quit mid-recording** (the app switcher): the movie plays up to a few seconds before the quit.
17. **Away from home** (Tailscale): 30 s plays, smaller.
18. **Two Sill windows** (iPad): each records its own; two movies, both named.
19. **VoiceOver.**
    - The count is spoken.
    - The light reads "Recording, … seconds, … megabytes".
    - Stop reads its time.
    - The notes are spoken.
20. **An older Mac** (Sill for Mac 0.6.2, the release before this): the footnote's older-Sill sentence; the
    recording works; the menu says nothing.
21. **Off the device.**
    - Files › Sill shows before the first recording, or only after it: note which.
    - Deleting a movie in Files works.
    - The movie plays on the Mac and, if one is at hand, on Windows or VLC (AAC).
22. **A protected video.** A trailer in the TV app on the Mac: whether it records black, as the Mac's own screen
    recordings show it. This is for App Review's notes.
23. **The iPhone** upright and sideways, Larger Picture on and off: the light's place, the count's, the notes'.

## Docs, site and App Store words (marked for the release that ships it)

- **`docs/recording-plan.md`:** this plan, kept current (progress, results, the review), as the PiP plan was.
- **`docs/steps/<date>-recording.md`:** what was done, by `Scripts/steps.sh new`.
- **docs/LAYOUT.md, docs/BUILD-AND-RUN.md, docs/COMPATIBILITY.md** (CLAUDE.md since 2026-11-18 holds rules and pointers
  only):
  - Layout's entries: the five device files, RecordingNotice, the two fields in StreamProtocol's paragraph, the rig
    in Scripts;
  - Build and run: the rig, the `sillclient.py` flags;
  - the harness arguments;
  - the floor's bullet, once a public build carries the fields.
- **`docs/DEVELOPMENT.md`:** Recording: the rig and the arguments.
- **README:** a line in what Sill does (inside a marker until the release).
- **`site/support.html`**, "Recording what you stream", between `<!-- Recording` and `<!-- /Recording -->`:
  - In Sill's Settings › This iPad, tap Start Recording. After a 3, 2, 1 count, a red light with the time and size
    shows over the picture. Tap Stop Recording at the top of Settings to finish.
  - The movie is in the Files app, in On My iPad › Sill › Sill Recordings. It is the picture your Mac sent, without
    Sill's controls or the pointer, with your Mac's sound when Send Audio and Record Sound are on.
  - A new picture size starts a new movie.
  - The recording ends when you leave Sill, disconnect, or the device is almost full.
  - Sill on your Mac shows in its menu that a device is recording.
  - Deleting Sill deletes the folder: move what you keep to Photos or iCloud Drive.
- **`site/privacy.html`** (one marked paragraph each; the page dated the day it goes out):
  - **what travels to the Mac:** "Whether the device is recording the stream, once a second with its other numbers,
    so Sill for Mac can say so in its menu.";
  - **what stays on the device:** the movies (in backups like other files, deleted with Sill, readable only while
    unlocked) and Record Sound;
  - **what the Mac's log keeps:** which devices recorded the stream, and when;
  - **Deleting your data:** the folder.
- **App Store:**
  - What's New: "Record what you stream: Settings › This iPad › Start Recording saves your Mac's picture, and its
    sound, as a movie in the Files app."
  - The review notes' "NEW IN" paragraph, about 450 bytes: "Settings › This iPad › Start Recording saves the
    Mac's picture (and, with Send Audio on, its sound) as a movie in Files › On My iPad › Sill › Sill Recordings. It
    starts only from that button, after a 3-second count; a red light with the time shows over the picture while it
    records; Sill for Mac shows in its menu that a device records; the movies stay on the device." The notes were
    3,988 of 4,000 bytes for 0.6.2, so something older comes out.
  - The App Privacy answers are unchanged.
- **`site/contribute.html`:** Aditya Dhumal for #303 (refreshed with each release, as the checklist says).

## The order of commits

1. **The merge of 488fce43** as it is. The four conflicts are resolved by keeping both sides (above). It builds, and
   behaves as #303 does.
2. **The wire:** `ClientStats.recording`, `WindowList.recordings`, and `compatibility`'s cases.
3. **The Mac:** RecordingNotice and its check; HostStatus, StreamCoordinator, StatusText, DebugHooks;
   `sillclient.py`. Gate G2.
4. **The device's rules:** RecordingPolicy, RecordingClock, RecordedSound, and `Tests/checks/recording`, with
   mutants. Gate G1.
5. **The recorder:** StreamRecorder rewritten; #303's taps in HEVCDisplayView and AudioOutput removed; the rig.
   Gate G3.
6. **The client:**
   - StreamClient+Recording;
   - the taps in `handle` and `receiveAudio`;
   - the endings, the asks and space;
   - `ClientStatsReporter`;
   - DeviceIdlePolicy and its check.
7. **The views:** RecordingLight, the Settings group and its top row, the two stream screens, the connect screen's
   note, MockCatalog, ContentView's contract; `recording.cases`. Gate G5.
8. **The plists, the privacy manifest, `release-ios.sh`.** Gate G4.
9. **The words:** step file, docs/LAYOUT.md, docs/BUILD-AND-RUN.md, DEVELOPMENT.md; README, support, privacy and the App Store texts inside their
   markers.
10. **An independent read-only review** of the branch before any device test, its findings fixed. Then a draft pull
    request, and Noah's devices (the list above).

## Risks

- **AVFoundation's behaviour where its documentation is silent:**
  - interleaving one input that stops (a still window) while the other goes on;
  - the last sample's duration at `endSession`;
  - pre-roll in passthrough HEVC;
  - `finishWriting` on a failed writer.
  - The rig's `still`, `still-sound`, `preroll` and `full` cases settle each, and the plan names each fallback.
- **Several movies per recording** may puzzle people (decision 3). The note says why.
- **Storage.** Pro is about 300 MB a minute at full motion (40 Mbps); Extreme about 1.1 GB. Deleting Sill deletes
  every recording. The words say so; the support page says to move the keepers.
- **App Review.**
  - 2.5.14 is met only while the light is always on screen (decision 4).
  - 5.2.3 forbids helping to save "media from third-party sources": the review notes say it records the person's own
    Mac. P22 tells whether protected video records black.
- **Each start costs every device on that Mac one keyframe**, as a device joining does.
- **The iOS 27 SDK deprecates `AVAssetWriterInput.append` and its real-time flags.** `SampleBufferReceiver` (iOS 26+)
  replaces them, so the recorder moves once the floor reaches iOS 26.
- **Battery.** Recording costs little (passthrough, a small AAC encode); the screen held on costs more (decision 9).
- **Other workstreams in the same files:**
  - the settings pane (the panel);
  - the microphone and camera (Settings rows, StreamClient);
  - files (#189: kinds 34 and 35, inside #66's range: theirs to fix);
  - the Virtual Desktop (WindowList fields).
  - Whichever lands second merges; no field name clashes (`recording`, `recordings` are free everywhere read).
- **The contributor's branch.** We do not push to `stream-recording`; our pull request carries his commit, and #303
  closes as merged.

## What reading could not settle

- Whether #303's movies really carry sound: its record says only "sound aac", and its sound path is the playout's.
- Every AVFoundation point under Risks.
- Whether iOS's automatic Picture in Picture start comes before or after the app's `didEnterBackground`. It matters
  only if decision 4 goes to (b), which then needs a short grace before ending.
- Whether Files lists Sill's folder before the first recording (P21).
- Whether ScreenCaptureKit records protected video as black (P22).
- Whether the iOS 27.1 SDK warns on the deprecated append at the iOS 17 target (G4).
- Real file sizes and the time from Start to the light's first frame on Noah's devices and links.

## Open decisions for Noah

Each recommendation is what the work proceeds with if he says nothing.

1. **Build on #303?**
   - (a) Our branch merges 488fce43 as it is, our commits on top; #303 closes as merged, credit kept.
   - (b) Ask addhumal to rework #303 to this plan.
   - (c) Redo without his commit.
   - **Recommended: (a)**, as #355 did with #173.
2. **Where Start and Stop live.**
   - (a) The first rows of This iPad (This iPhone), and while it counts or records a Stop row at the top of Settings.
   - (b) #303's place, under Send Audio in the Mac's group.
   - (c) Also a button on the bar.
   - **Recommended: (a).** It is this device's action, not the Mac's setting, and Stop is never a scroll away.
3. **A new picture size mid-recording** (a turn, Aa, another window, the Mac locking).
   - (a) A new movie for each size, numbered, saved together (#303's).
   - (b) Hold this device's viewport while it records, so turning and Aa don't change the size (a pick or a lock
     still do).
   - (c) One movie that changes size (not shown to work in AVFoundation; players differ).
   - **Recommended: (a).**
4. **Picture in Picture.**
   - (a) The recording ends when Sill leaves the screen, Picture in Picture or not. That is #284's "when Sill goes to
     the background", and the light is then always visible while it records, as App Review 2.5.14 asks.
   - (b) It goes on while the picture plays in Picture in Picture, with no light on the device.
   - **Recommended: (a).**
5. **Sound with this device's Mute on.**
   - (a) Record Sound records the Mac's sound whenever the Mac sends it, whatever this device plays (Mute, a call).
   - (b) Only what this device plays, which records nothing while muted.
   - **Recommended: (a).**
6. **How the Mac says it.**
   - (a) The menu's subtitle and the device's row say "Recording", and Sill.log has a line at each start and stop.
   - (b) (a) plus a mark on the menu bar icon.
   - (c) (a) plus a macOS notification (Sill would ask for notification permission).
   - **Recommended: (a).** Noah's words name the menu.
7. **A Mac whose older Sill can't say it.**
   - (a) Record anyway; the footnote says that Mac won't show it.
   - (b) Refuse until the Mac is updated.
   - **Recommended: (a).**
8. **The Mac's pointer.**
   - (a) Not in the movie. The picture is as streamed, and the footnote says so.
   - (b) Drawn in on the device: a decode and a re-encode, against "without re-encoding".
   - (c) The Mac draws its cursor into the stream while a device records: every device sees it, with a restart each
     way, as Noah dropped for Picture in Picture.
   - **Recommended: (a).**
9. **Auto-lock while recording.**
   - (a) The device stays awake while it records; space and Stop still end it.
   - (b) The usual 10 minutes after the last touch, so a long untouched recording ends when the device locks.
   - **Recommended: (a).**
10. **Backups and deleting Sill.**
    - (a) The movies are ordinary documents: in backups, deleted with Sill, and the words say both.
    - (b) Left out of backups.
    - **Recommended: (a).**
11. **The space numbers.**
    - (a) Warn under 3 GB free or 5 minutes left, stop at 1 GB, refuse to start under 1.5 GB.
    - (b) Other numbers.
    - **Recommended: (a).**
12. **The sound's codec.**
    - (a) AAC 160 kbps, re-encoded on the device from the decoded sound (#284's note, #303).
    - (b) The AAC-ELD packets as they came: no re-encode, but it may not play off Apple's players, and its setup changes
      with each epoch.
    - **Recommended: (a).**
13. **Can the Mac forbid it?**
    - (a) No. The Mac shows it, and does not forbid it: a device can always use iOS's own recording.
    - (b) A switch in Sill's Settings › Devices that Sill's builds obey.
    - **Recommended: (a).**

## Progress

Each group of commits is built, checked with its mutants, pushed and noted here and in the step file
(docs/steps/2026-11-18-recording.md).

1. Done: the merge of 488fce43 (d94e51b9), the four conflicts keeping both sides, and StreamRecorder.swift importing
   SillAudio, where AudioDecoder lives since #394.
2. Done: the wire, `ClientStats.recording` and `WindowList.recordings`, with `compatibility`'s cases and mutants.
3. Done: the Mac, RecordingNotice and `Tests/checks/recording-notice`; HostStatus, StreamCoordinator, StatusText,
   DebugHooks; `sillclient.py`. Gate G2, with a locked Mac's list keeping `recordings` (`lock-policy`'s case for it
   came in run 2, with its mutant). The menu says a device
   records whatever else its headline says (test pattern mode included), not only where the plan put it.
4. Done (run 2): the device's rules, RecordingPolicy, RecordingClock (with RecordingTimeline, the recorder's order of
   things as a pure type, so the random recordings run the recorder's own decisions) and RecordedSound, and
   `Tests/checks/recording` (20,000 random recordings; 84 mutants); SillDocuments, the one owner of Documents
   (overview §2.3); lock-policy's case that a locked list keeps `recordings`.
5. to 7. Done (run 2): StreamRecorder rewritten on the timeline, #303's taps removed, the rig
   (`Scripts/recording-check`, ten cases); StreamClient+Recording, the taps in `handle` and `receiveAudio`, every
   ending, the asks, space, `ClientStats.recording`, DeviceIdlePolicy's `Uses.recording`; RecordingLight, the
   Settings rows and the pinned Stop row, both stream screens, the connect screen's note, MockCatalog,
   ContentView's contract, `recording.cases`.
8. Done (run 2): the privacy manifest's DiskSpace (E174.1, 85F4.1); release-ios.sh checks the two Files keys.
   Gates in run 2: G1 (`recording` 83 of 83 mutants, `device-idle` 18 of 18, lock-policy's new one), G3 (the rig's
   ten cases, every gate, after its first run found the still window's 0.067 s movie: AVAssetWriter does not give a
   last sample the session's end, so each picture is held until the next gives its duration, as Risks foresaw), G4
   (the iOS app Debug and Release for the simulator and Debug for a device), G5 (28 photos of `recording.cases`, none
   blank), G6 (76 of 76).
9. Partly: docs/LAYOUT.md, docs/BUILD-AND-RUN.md and the step file; the proposed words for README, the support and
   privacy pages and the App Store are in the step file, not yet in their pages.
10. Not started: an independent read-only review of the branch, then Noah's devices.

