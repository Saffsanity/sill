# Picture in Picture — the plan

2026-11-11. Branch `picture-in-picture` (worktree `~/Downloads/wt-pip`) from origin/main at dd6ea6a (0.6.1
released, then #339). Issue #291, Noah's: "I want the Mac's picture to keep playing when I leave Sill.
Swipe home or to another app, and the window I'm streaming keeps going in iOS's Picture in Picture
window, so I can watch a build, a render or a video while I do something else on the iPad or iPhone. A
switch in Settings › This iPad (This iPhone on a phone) turns it on or off." Noah, 2026-11-11: "I want to
get PiP support in the next version". Device only: no wire change, nothing on the Mac, one new device
setting that is never sent.

## The problem

Today the picture stops when Sill leaves the screen. iOS suspends the app a few seconds after it goes to
the background; the Mac evicts a device that stops reading (no frame drained for 4 s); the session comes
back when Sill does (the reconnect, docs/reconnect-after-sleep-plan.md). A person waiting on a build, a
render or an export keeps Sill in front and does nothing else, or leaves and comes back to check.

iOS has the answer built in: Picture in Picture (PiP) takes an app's video into a small floating window
over every other app and keeps the app running while it shows. Sill's picture is an
`AVSampleBufferDisplayLayer` (HEVCDisplayView), which AVKit takes as a PiP content source since iOS 15.

## What Apple documents (checked 2026-11-11 against developer.apple.com, the iOS 27.1 SDK's headers and WWDC transcripts)

Documented:

- `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`: iOS and iPadOS
  15.0. The controller is nil on a device without PiP (`isPictureInPictureSupported()` first); hold it
  strongly; the content source holds its playback delegate weakly.
- `AVPictureInPictureSampleBufferPlaybackDelegate`: five methods required (`setPlaying`,
  `timeRangeForPlayback`, `isPlaybackPaused`, `didTransitionToRenderSize`, `skipByInterval`), one optional
  (`shouldProhibitBackgroundAudioPlayback`, iOS 15). For live content `timeRangeForPlayback` returns a range
  whose duration is positive infinity (its start is not documented). `skipByInterval`'s completion must
  always be called, or the window stays in a seeking state for good. `invalidatePlaybackState()` after every
  start or pause.
- `requiresLinearPlayback` (iOS 14): no fast forward, skip or scrubbing.
- `canStartPictureInPictureAutomaticallyFromInline` (iOS 14.2): PiP starts when the content is inline and
  the app goes to the background; for the person's primary focus only. The person can turn the automatic
  start off: Settings › General › Picture in Picture.
- **Start PiP only in response to the person**, never programmatically; App Review rejects an app that
  starts PiP itself as it goes to the background ("Adopting Picture in Picture in a Custom Player", and the
  archived iPad multitasking guide). So Sill never calls `startPictureInPicture()` in a Release build; iOS
  starts it, through the automatic start, as the person leaves.
- The audio background mode is required (`UIBackgroundModes` `audio`, the "Audio, AirPlay, and Picture in
  Picture" capability), with the `.playback` audio session category ("Configuring your app for media
  playback"). While PiP shows, "the system presents the video content on your behalf while your app
  continues to run, potentially in the background" (the archived iPad guide).
- `isPictureInPicturePossible` is false while another app (FaceTime) has PiP.
- The video-call variant (`AVPictureInPictureVideoCallViewController`) is for calls; a stream of a screen
  uses the sample-buffer source.

Not documented, so each is a device test (P list below): whether the PiP window shows the layer's
sublayers (Sill's pointer sprite is one); whether frames enqueued to display at once, with no timebase
(Sill's), show in PiP; whether `.mixWithOthers` keeps iOS from starting PiP; whether the app keeps running
while PiP is paused, and after it stops in the background; what PiP does when the device locks; which of
several scenes starts PiP; whether the simulator runs sample-buffer PiP. Secondary sources (developers,
not Apple): a live range starting at negative infinity cost a lot of CPU from iOS 16.1, a start at zero
did not (developer forums 724632); a sample-buffer PiP went black about 30 s after the device locked until
a flush (745840); one app was rejected under 2.5.4 for declaring the audio mode for AirPlay and PiP
(671406, unanswered by Apple).

## Decision

### In one paragraph

A switch, Settings › This iPad (This iPhone) › **Picture in Picture**, off by default
(`PictureInPicturePolicy.defaultOn`). With it on, while Sill's window shows the Mac's picture, Sill lets
iOS take that picture into PiP when the person leaves Sill (the automatic start; Sill never starts it
itself). The PiP window shows the Mac's picture as Sill receives it, at its own shape, and the Mac's sound
plays with it when Send Audio is on and this device's Mute is off. Nothing reaches the Mac from it. Its
pause freezes the picture and the sound; the Mac keeps sending, so play brings the live picture back at
once. Coming back to Sill (the PiP window's return button, or opening Sill) puts the picture back in Sill.
The session's end, the device's lock and ten minutes paused end PiP; after that Sill is in the background
as it is today. The Mac changes nothing: it keeps streaming to a device that keeps reading.

### The rule (`PictureInPicturePolicy`, pure, `Tests/checks/picture-in-picture`)

1. **Offered** (`qualifies`, `offered`): iOS may take a window's picture into PiP as the person leaves
   Sill (`canStartPictureInPictureAutomaticallyFromInline`) while all of these hold: the switch is on; iOS
   supports PiP here; the session is connected; a source streams (a window or the Desktop); its picture has
   come (the stream's format is known); nothing covers it (no locked-Mac cover, `lockShade`: a Mac locked,
   another user on it, or Unlocking…); and this is the window Sill offers it for (rule 2).
2. **One window** (`chosen`): with several Sill windows (iPad: Split View, Stage Manager), the one the
   person used last (DeviceIdlePolicy.lastUse: input sent, a control, the session's start, the window coming
   to the front) among those in front that qualify. While none of Sill's windows is in front (Sill on its
   way out, or away), the last choice stands: the scene's own activation never takes the offer away while
   iOS decides whether to start PiP.
3. **Watched** (`pictureWatched`): the picture counts as seen while its window's scene is foreground
   active, or while PiP shows it playing. KeyframeRecovery asks the Mac for a keyframe (kind 44) for an
   interrupted picture only then, so a picture interrupted as Sill leaves (the layer needing a flush) comes
   back in PiP without waiting for the Mac to repaint.
4. **Heard** (`soundHeard`): the Mac's sound plays while the app and the window's scene are in the
   foreground, as before, or while PiP plays. Muted, Send Audio off or PiP paused: silence.
5. **Running** (`running`): what Sill does by itself only in the foreground (the automatic reconnect's dials
   of a listed row, a failed browser made again: DiscoveryPolicy.redialRow and rebuildBrowser) runs while the
   app is not in the background, or while PiP is active (paused or not): iOS keeps the app running then. A
   return to the front after a stay in the background that PiP covered throughout is not a return from the
   background: the browsers are not made again (`cameForward`), since iOS never suspended the app.
6. **Paused** (`frozen`): PiP's pause freezes the picture (no frame goes onto the layer, which keeps its
   last picture) and silences the sound (rule 4); the connection keeps reading, so the Mac keeps the device.
   Play: the picture waits for a keyframe, which the device asks for at once. Paused for `pausedLimit`
   (10 minutes, DeviceIdlePolicy.idleLimit's): PiP stops (`pauseEnds`), as nobody is watching, so no paused
   PiP keeps a Mac streaming all night.
7. **Stops** (`stops`): PiP stops when the session ends (a goodbye, the Mac quitting Sill, a loss no move
   carries, Disconnect); when its window's scene comes back to the front (the person is back in Sill, by
   the return button or any other way, and half a second after iOS started it with the window already
   back in front: home, then straight back, when the scene's activation came first); when the device
   locks (iOS says protected data is about to go, which needs a passcode); and at `pausedLimit` paused. A
   move to another path (the cable, Wi-Fi, home) keeps it: the session goes on.
8. **Only there** (`onlyInPictureInPicture`: PiP active, its window not in front): iOS sends no touch or key
   to an app in the background, and keys and touches still down as Sill leaves are cancelled, so their ups
   reach the Mac (`pressesCancelled`, `touchesCancelled`, as today). Beside that, while the picture shows
   only there: the one input the device makes by itself, its pointer's move to the middle of a new frame
   (`pointerFrameChanged`, when the source changes while the portrait trackpad's arrow shows), waits, as it
   waits under the tour, and goes only once Sill's window is in front again (never as PiP stops with Sill
   away); a viewport the stream screen asks for waits too (`viewportHeld`), so a layout iOS makes for its
   app-switcher snapshots never resizes the Mac's window or restarts its stream, and goes once Sill's window
   is in front; and a copy on the Mac is not written to this device's clipboard (it would replace what the
   person copies in the app in front; before PiP, Sill was suspended there and none came).
9. Unchanged: the device's auto-lock hold (#230) counts only a window in front; the tour starts only
   while Sill is active; the clipboard's chip looks only when Sill becomes active; the viewport and the
   frame rate are what they were when Sill left (no restart on the Mac when PiP starts or stops); the stats
   every second go on while connected; the hardware keyboard's hold is the input view's, which a background
   app's keyboard never reaches.

### What a watcher sees in the PiP window

The PiP window shows the display layer's video and nothing drawn above it in Sill's own views.

| State | In Sill | In the PiP window |
|---|---|---|
| A window streams | its picture, the pointer sprite, the link's line | its picture at its own shape, without the pointer (the Mac's cursor is never in the video) |
| The Desktop streams | the Desktop | the Desktop at the display's shape |
| Pinch-zoomed | the zoomed part | the whole picture (the zoom is a view transform) |
| The Mac's screen locked | its lock screen (it streams by default) under the cover's words | the lock screen, no words |
| Another user on the Mac | black (the Mac's placeholder) under the cover's words | black |
| Unlocking… | the picture as it comes back | the picture as it comes back |
| The link can't keep up | the picture, the line over it | the picture, slower |
| The session ended | the connect screen | nothing: PiP stopped |
| Paused in the PiP window | (Sill is not on screen) | the last picture, frozen; silence |

Nothing is drawn into the video in this version: an honest picture of what the Mac sends, and the words
when the person comes back (open question 7).

### Sound and the audio session

- The category stays `.playback` with `.mixWithOthers` (AudioOutput's `SharedSession`): Sill never stops
  another app's music, whether Sill's sound plays, is muted, or Send Audio is off. That is the constraint
  Noah gave; whether iOS starts PiP with a mixing session is the first device test (P3), and open question
  5 has the fallback.
- While PiP is offered or active, Sill holds its audio session active (one more holder in
  `SharedSession`, beside each playing engine), so iOS sees a `.playback` session when it decides; the
  engine itself runs only while the sound is heard (rule 4). Mixing, an active session without sound
  changes nothing for other apps. DEBUG `-SillPiPSession inactive` leaves it inactive, for the comparison.
- The optional `shouldProhibitBackgroundAudioPlayback` answers no: the sound goes on while the PiP window
  is tucked against the screen's edge, as the picture does.
- The mode in Info.plist lets an app play sound in the background at all. Sill's engine still stops in
  the background unless PiP plays (rule 4), so with the switch off nothing is heard in the background,
  as before.

### Battery and the Mac

The device keeps the stream's rate and quality while in PiP: no new viewport, so no restart on the Mac for
any device (a viewport's rate change restarts the Mac's pipeline, and the stream runs at the highest rate any
device wants). The PiP window is small and the stream may be 120 fps on a ProMotion iPhone; asking for 30 fps
in PiP is open question 3.

### Several windows

One window's session offers PiP (rule 2): the one used last. Each window has its own session, display layer
and controller (`PictureInPicture`, one per StreamClient); `PictureInPictureHub` lists the windows as
DeviceIdleTimer does and tells each whether it is offered. What iOS does when one Sill window goes to the
background while another stays in front (Stage Manager's minimize) is not documented: P13.

## Beside the related work

- **#152** (acalatrava, open): a background task as Sill resigns active while streaming, so the stream stays
  responsive for the seconds iOS grants. It touches the same observers in StreamClient (willResignActive,
  didEnterBackground, willEnterForeground) and `tearDown`'s first lines: whichever lands second keeps both.
  With Picture in Picture on, iOS keeps Sill running for as long as the window shows, so the task matters
  only with the switch off, or before iOS starts Picture in Picture.
- **#206** (Keep Screen On, iPhone upright): its idle-timer hold is the foreground's, as #230's; Picture in
  Picture changes neither.
- **#284** (recording the stream): it would write the same frames the layer gets; a frozen picture
  (`setFrozen`) drops frames before the layer only, after the network queue has them.
- **#94** (Send Audio): the sound plays in Picture in Picture through the same engine and session rules
  (`soundHeard`), never in the background otherwise.

## Open questions for Noah (each default is taken unless Noah says otherwise)

1. **On by default?** Off (`PictureInPicturePolicy.defaultOn`, one constant): keeping the radio, the
   decoder and the Mac's stream running in the background should be opt-in until Noah has tried it.
2. **A button to start PiP by hand?** None in this version. Without one, a person who turned off iOS's
   Start PiP Automatically (Settings › General › Picture in Picture) gets no PiP from Sill; the footnote
   says so. A button in the bar (or the Settings panel) would also float the picture while Sill stays in
   front.
3. **A lower frame rate in PiP?** No: the stream keeps its rate (no restart on the Mac when PiP starts or
   stops). The alternative: the device asks for 30 fps while PiP shows, one restart each way, for every
   device on that Mac.
4. **Keep the PiP window through a reconnect?** No: the session's end stops PiP (a goodbye, a loss no move
   carries), and the reconnect runs when Sill comes back, as today. The alternative keeps PiP open on the
   last picture while the reconnect runs in the background, and goes on when the Mac answers.
5. **The audio session.** Mixing with other audio, always (the default). If P3 shows iOS will not start PiP
   with a mixing session, the fallback is a non-mixing session while PiP is offered or active, which stops
   another app's music as Sill's picture streams, until Sill leaves PiP: a worse trade, Noah's call.
6. **The device's lock.** PiP stops when the device locks (with a passcode iOS says so ~10 s after the
   lock); without a passcode Sill hears of no lock, and PiP goes on until iOS or the person stops it, or 10
   minutes paused. The alternative keeps PiP across a lock.
7. **Words in the PiP window?** None: the covers' words (a locked Mac, another user), the link's line and
   the pointer are Sill's views over the picture and do not travel to PiP. The alternative draws a still
   with the words into the video while the cover shows.
8. **Pause.** Freezes the picture and the sound; the Mac keeps streaming to the device (which drops the
   frames before decoding), so play is live at once; 10 minutes paused stops PiP. The alternative: pause
   does nothing (live content), which leaves a pause button that does nothing.
9. **Several windows.** The one used last offers PiP (rule 2). The alternative offers PiP only while Sill
   has one window, as the Mac's menus in the iPad's bar do.

## Gates

| Gate | What |
|---|---|
| G1 | `Tests/checks/picture-in-picture`: the rule's cases, random sessions against the invariants, and its mutants, every one caught (CI's mutants matrix has it) |
| G2 | The iOS app, Debug and Release for the simulator and Debug for a device (build only), with only the known `StreamClient` capture warning |
| G3 | Harness photos of the switch and its footnote (`-SillSettings 1 -SillSettingsScroll pip -SillPiPSupported 1`): the Duo's four sizes, an iPad's, an iPhone's, default and accessibility-extra-large text |
| G4 | On a private simulator of this run against `SillHost --synthetic` on loopback: what of PiP the simulator runs (supported, possible, a start through `-SillPiPStartAt`, frames in the PiP window, the host keeping the device, pause and play, the return, the session's end), photographed; said plainly where the simulator cannot |
| G5 | `swift build -c release` is not needed (no host file changes); the CLI and the host are untouched (`git diff --stat` shows iOSClient, docs and the check alone) |

## Test plan for Noah's devices (P list)

The iPad mini (60 Hz) and the iPhone 15 Pro, a Debug build of this branch (Xcode's console shows the `pip:`
lines), Sill for Mac 0.6.1, Settings › This iPad › Picture in Picture on. iOS's own switch first:
Settings › General › Picture in Picture › Start PiP Automatically on (P1 checks its name on iOS 27).

1. **The setting.** The switch is the first row of This iPad (This iPhone) with its footnote; off by
   default on a fresh install; its name and iOS's own setting's path read as on the device.
2. **A window, then home.** Stream a window that changes (a build log, a video): swipe home. The picture
   floats in iOS's PiP window and keeps moving, at the window's shape, without a pointer. Sill.log on the
   Mac keeps the device ("Client left" never comes); its card shows frame age and rtt as before.
3. **The audio session.** Music playing in Apple Music, Sill's sound muted (Mute on): stream, swipe home. The
   music never stops, and PiP still starts. If PiP does not start, note it (open question 5) and try once
   with Mute off and Send Audio on, then with `-SillPiPSession inactive` in the scheme.
4. **Sound.** Send Audio on, Mute off: the Mac's sound goes on with the PiP picture; Mute on before leaving:
   silence in PiP. Pause in the PiP window: the picture freezes and the sound stops; play: the live picture
   within a second, the sound back.
5. **The Desktop.** The Desktop streams, swipe home: PiP shows the Desktop at the display's shape.
6. **Another app's window.** In PiP, switch to Safari, scroll, type: nothing reaches the Mac (Sill.log has
   no input line, the Mac's pointer stays). With a Magic Keyboard attached: type in Notes while Sill is in
   PiP, nothing on the Mac; hold ⌘ in Sill and swipe home with the other hand: the Mac's ⌘ is up at once
   (no "Keys: … came up" line in Sill.log).
7. **Return.** Tap the PiP window, then its return button: Sill comes back with the picture in place, no
   reconnect (no new "Client connected" in Sill.log). Again by opening Sill from the Home Screen while PiP
   shows: PiP closes, the picture is in Sill.
8. **A locked Mac.** In PiP, lock the Mac (⌃⌘Q): the PiP window shows the Mac's lock screen; unlock it: the
   window comes back in PiP. In Settings › Devices on the Mac, another user logged in (fast user switch):
   black in PiP; back: the picture.
9. **The session ends.** In PiP, quit Sill on the Mac: PiP closes. Open Sill: the usual "‹Mac› quit Sill." and
   the reconnect once the Mac is back.
10. **The device locks.** In PiP, lock the iPad with its button: PiP is gone after unlocking, and within a
    minute the Mac's Sill.log says "Client left" (the device was suspended). Wait ten seconds before unlocking
    (iOS tells Sill of the lock about ten seconds after it, with a passcode). Leave PiP alone, untouched,
    for the iPad's Auto-Lock time: say whether the iPad locks by itself while PiP plays.
11. **Paused for long.** Pause PiP, wait ten minutes: PiP closes, and a minute later Sill.log says "Client
    left".
12. **A move.** At home on Wi-Fi in PiP, plug the cable in: PiP goes on (the Mac logs the new connection over
    the cable); pull it: PiP goes on over Wi-Fi.
13. **Two Sill windows (iPad).** Two windows side by side, each streaming a different Mac window: use the
    left one last, swipe home: the left one's picture floats. Back, use the right one, swipe home: the right
    one's. In Stage Manager, minimize one window while the other stays in front: say what happens.
14. **The switch off.** Switch off, swipe home: no PiP, the picture stops as before (Sill.log: "Client left"
    a few seconds later).
15. **Battery.** Thirty minutes of PiP on a moving window, from a full charge: note the drop, beside thirty
    minutes in Sill in front.
16. **VoiceOver.** The switch reads "Picture in Picture, switch button, off" and its footnote; in PiP,
    VoiceOver's own PiP controls work.
17. **The Mac's window keeps its size.** Aa set (1.5×) on a window, swipe home: in PiP the window keeps the
    size Sill gave it (Sill.log has no "Resized …" line and no stream restart while PiP shows); on the iPad,
    open the app switcher and leave it again while PiP shows, and say whether anything restarted.
18. **The clipboard.** Share Clipboard on: in PiP, copy something in Notes on the iPad, then have something
    copied on the Mac (another keyboard, or `echo hi | pbcopy` in Terminal): paste in Notes: the iPad's own
    copy, not the Mac's. Back in Sill, a new copy on the Mac reaches the iPad as before.
19. **iOS's switch off.** Sill's switch on, iOS's Start PiP Automatically off: leave Sill: no PiP, and Sill.log
    says "Client left" within about ten seconds (iOS suspended Sill as before, the audio session held by
    Sill's offer notwithstanding).

## Results

(Filled in as the gates run.)

## Progress

- 2026-11-11: plan written; the Apple documentation checked; code next. Builds wait: the disk was under
  the 25 GB floor (15 to 17 GB free) and the coordinator paused builds and simulators.
