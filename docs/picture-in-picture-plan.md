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
plays with it when Send Audio is on and this device's Mute is off. Nothing reaches the Mac from it, nor
from the device by itself meanwhile (no pointer move, no viewport), and the Mac's copies do not replace
the device's clipboard while the person is in another app. Its pause freezes the picture and the sound;
the Mac keeps sending, so play brings the live picture back at once. Coming back to Sill (the PiP
window's return button, or opening Sill) puts the picture back in Sill. The session's end, the device's
lock and ten minutes paused end PiP; after that Sill is in the background as it is today. The Mac changes
nothing: it keeps streaming to a device that keeps reading.

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
   Start PiP Automatically (an iPhone's Settings › General › Picture in Picture; iPadOS 26 moved the iPad's,
   a person's report says to Multitasking & Gestures) gets no PiP from Sill; the footnote
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
| G4 | On a private simulator of this run against `SillHost --synthetic` on loopback: what of PiP the simulator runs (supported, possible, a start through `-SillPiPStartAt`, frames in the PiP window, the host keeping the device, pause and play, the return, the session's end), photographed; said plainly where the simulator cannot (it cannot: Results) |
| G5 | `swift build -c release` is not needed (no host file changes); the CLI and the host are untouched (`git diff --stat` shows iOSClient, docs and the check alone) |

## Test plan for Noah's devices (P list)

**Set up.** A Debug build of this branch on the iPad mini (60 Hz) and the iPhone 15 Pro, Xcode's console
open on the device (its `pip:`, `display:`, `audio:`, `keyframe:`, `viewport:` and `clipboard:` lines say what
happened); Sill for Mac 0.6.1 on the Mac (nothing on the Mac changes), `tail -F ~/Library/Logs/Sill/Sill.log`
in Terminal. iOS's own switch on: on the iPhone, Settings › General › Picture in Picture › Start PiP
Automatically; on the iPad, search Settings for "Picture in Picture" (iPadOS 26 moved it). Then, in Sill's
Settings (the gear) › This iPad (This iPhone), turn **Picture in Picture** on.

1. **The switch.** It is the first row of This iPad (This iPhone), off on a fresh install, with the footnote
   "Leave Sill while ‹Mac›’s picture shows, and it keeps playing in a small window over your other apps, with
   its sound when Send Audio is on. That window only shows the picture: tap it to come back to Sill. iOS
   starts it only while its own Start PiP Automatically setting is on." Turning it on prints `pip: the switch
   on`, `pip: controller made on the display layer`, `pip: offered: …` and, a moment later, `pip: possible
   true`. Note where iOS 27 keeps its own switch on each device, and whether it is called Start PiP
   Automatically.
2. **A window, then home.** Stream a window that keeps changing (Terminal running `top`, a video in
   QuickTime Player). Swipe up to the Home Screen. Expected: the picture shrinks into a floating window that
   keeps moving, at the window's shape, without a pointer; the console says `pip: playing (iOS starts Picture
   in Picture)`, `pip: started`, `pip: the window shows the picture at W×H px`. Leave it two minutes over the
   Home Screen and another app: Sill.log never says "Client left", and the Mac's card for the device keeps its
   fps, frame age and rtt.
3. **Your music.** Play something in Apple Music on the device. In Sill, Settings › Mute on, then swipe home:
   the music never pauses, and the picture still floats. If it does not float, note the console's `pip:
   possible …` and any `pip: failed to start: …`, try again with Mute off, then with `-SillPiPSession inactive`
   in the scheme's arguments (open question 5).
4. **Sound, pause and play.** Send Audio on, Mute off, a video playing in a Mac window: in PiP the sound goes
   on with the picture. Tap the PiP window, then its pause button: the picture freezes and the sound stops
   (`pip: paused`, `display: frozen: …`, `audio: engine off (Picture in Picture paused)`). Its play button: the
   picture moves again within about a second (`display: frozen no more: waiting for a keyframe`, `keyframe: …
   asked the Mac for a keyframe`, `pip: playing`), then the sound.
5. **The Desktop.** The Desktop streaming (Sill's Desktop button), swipe home: the PiP window shows the
   Desktop at the display's shape.
6. **Nothing reaches the Mac.** While PiP shows: in Safari, scroll, tap and type. On the Mac nothing moves
   or types, and Sill.log has no line of input. With the Magic Keyboard: type in Notes: nothing on the Mac.
   Back in Sill, hold ⌘ on the Magic Keyboard and swipe home with the other hand: a click on the Mac right
   after is a plain click, and Sill.log has no "Keys: … came up, this Mac's modifier keys still read" line.
7. **Coming back.** Tap the PiP window, then its return button: Sill comes back with the picture in place
   and no reconnect (Sill.log: no new "Client connected"; the console: `pip: the window's return button: Sill's
   interface restored`, `pip: off (it stopped)`). Leave again, and this time open Sill from the Home Screen
   while PiP shows: PiP closes and the picture is in Sill (`pip: stopping: its window is in front again`).
   Swipe home and come straight back before the picture has floated: it ends in Sill, not floating over it.
8. **A locked Mac.** In PiP, lock the Mac (⌃⌘Q): the PiP window shows the Mac's lock screen. Unlock it: the
   window's picture comes back in PiP. Fast-switch the Mac to another user: black in PiP; back to yours: the
   picture.
9. **The session ends.** In PiP, quit Sill on the Mac: PiP closes (`pip: stopping: the session ended (…)`).
   Open Sill: "‹Mac› quit Sill.", and the session comes back once Sill on the Mac is open again.
10. **The device locks.** In PiP, press the top button, wait 15 seconds, unlock: no PiP (`pip: stopping: the
    device locked`), and within a minute Sill.log says "Client left". Then leave PiP alone, untouched, with
    the window moving, for the device's Auto-Lock time: say whether the device locked by itself.
11. **Ten minutes paused.** Pause PiP and wait ten minutes: PiP closes (`pip: stopping: paused for 10
    minutes`), and within a minute Sill.log says "Client left".
12. **A move.** At home on Wi-Fi, in PiP, plug the USB cable in: PiP goes on, and Sill.log shows the new
    connection over the cable, then "Client left" for the Wi-Fi one. Pull it: PiP goes on over Wi-Fi.
13. **Two Sill windows (iPad).** Two windows side by side, each streaming a different Mac window. Tap in the
    left one last, swipe home: the left one's picture floats. Come back, tap in the right one, swipe home: the
    right one's. In Stage Manager, minimize one window while the other stays in front: say what happens.
14. **The switch off.** Turn it off, swipe home: no PiP, and Sill.log says "Client left" a few seconds later,
    as before this branch.
15. **Battery.** Thirty minutes of PiP over a moving window from a known charge, then thirty minutes with Sill
    in front: note both drops.
16. **VoiceOver.** The switch reads "Picture in Picture, switch button, off", then its footnote; PiP's own
    controls work with VoiceOver.
17. **The Mac's window keeps its size.** Aa at 1.5× on a window, swipe home: in PiP, Sill.log has no
    "Resized …" line and no stream restart. On the iPad, open the app switcher and leave it again while PiP
    shows: still none (the console says `viewport: held while the picture shows only in Picture in Picture` if
    iOS laid Sill out for its snapshots).
18. **The clipboard.** Share Clipboard on. In PiP, copy something in Notes on the device, then copy on the Mac
    (`echo hi | pbcopy` in Terminal): paste in Notes: the device's own copy, not "hi" (`clipboard: a copy from
    the Mac not written: …`). Back in Sill, a new copy on the Mac reaches the device as before.
19. **iOS's switch off.** Sill's switch on, iOS's Start PiP Automatically off: leave Sill: no PiP, and Sill.log
    says "Client left" within about ten seconds (iOS suspended Sill as before).
20. **The iPhone.** P2, P4 and P7 on the iPhone 15 Pro, held upright and sideways, with Larger Picture on too:
    the PiP window keeps the window's shape whatever Sill's layout.

## Results

### G1: the check (2026-11-12, 00:34–00:38)

`Tests/checks/picture-in-picture`: 344 checks pass, the 20,000 random sets of windows among them (C1–C3:
11,561 chosen in front, 848 kept while away, 7,591 none) and the 20,000 random lives of one window (27,391 starts,
13,153 pauses, 4,467 stopped at the pause's limit, 54,889 by an ending; L1–L7). Its mutants: 43 of 43
caught, the unchanged check passing first. M23b, the pause's end measured by its length
(`now - pausedAt >= pausedLimit`), fails L4 3,283 times: a look at exactly the time the rule gave found
nothing due in those lives, which the review found before the first run (below).

### G2: the builds (2026-11-12, 01:20–01:22, after main at 936d627 was merged in)

On 61bbee7 (this branch with main's #339 and #349): the check again, 344 passed; the iOS app for the
simulator in Debug (ad hoc signed, 26 s) and Release (50 s), and for a device in Debug (23 s), each from
one derived data folder under the worktree's `.build`, each with only the known `StreamClient` capture
warning (StreamClient.swift:4464, `[#ImplicitStrongCapture]`, the closed window's Desktop request, older
than this branch); each built Info.plist carries `UIBackgroundModes` `["audio"]`. The Release and device
products were removed once their results were in.

### G3 and G4: one simulator (2026-11-12, 01:37–01:54)

The iOS 27.1 runtime runs no iPad, only the iPhone Duo (`simctl list runtimes`: its supported device types
are the Duo alone), and every Duo photo is that runtime's: so one iPhone Duo simulator of this run, made,
used and deleted inside heavy.sh, twice. The first pass's photos came out black: the Duo boots closed,
Sill runs on its cover display, and `simctl io screenshot` takes the inner one by default (Tests/duorig's
README); the simulator was deleted, and the second pass, with the app built again for its diagnostic line,
photographed the cover (`--display=primary`).

- **G3, the switch** (`-SillSettings 1 -SillSettingsScroll pip -SillPiPSupported 1`, the mock Mac "Mac mini"):
  14 photos in `~/Downloads/sill-handoff/pip/photos/`: the iPad's 1133×744 and 744×1133 (`-SillIdiom pad`,
  "This iPad", drawn at 0.60 on the cover), the Duo's 951×669, 669×951 (drawn at 0.69), 466×678 and 678×466
  (its cover, at its own size) and an iPhone's 393×852 (0.79), "This iPhone", each at the default text size
  and accessibility-extra-large (the panel holds its text at xxLarge, as before). The switch is the group's
  first row, off, with its footnote whole above Share Clipboard (or Larger Picture's row on a phone).
- **G4, Picture in Picture itself:** not on this simulator. AVKit says it has none:
  `AVPictureInPictureController.isPictureInPictureSupported()` is false on the iPhone Duo simulator (iOS 27.1),
  so no controller is made and nothing is offered (the console, for every session: `pip: window 1 not
  offered: iOS has it false (AVKit false), connected true, streaming true, picture true, covered false, in
  front true`). What the pass did show, against `SillHost --synthetic` on loopback (SILL_TEST_LOOPBACK,
  SOFTWARE_ENCODER, NO_ROUTER, NO_SCREEN): the offer's inputs follow the session (connected, then the
  Desktop streaming, its picture, in front, away and back again, each on its own line); the Settings app in
  front sends Sill to the background (`pip: Sill is in the background`) and the host kept streaming to it
  for the eight seconds before it was brought back (the simulator did not suspend it that soon, PiP or
  not); a host that quits ends the session as before. An iPad simulator (the iOS 27.0 runtime) may have
  Picture in Picture; it was not tried (one simulator).

### The review before the first build (2026-11-11)

Builds waited for disk space, so the code was read before it was ever compiled: an independent read-only
review of the branch found nine things, each fixed (40dbfe6) before the first build:

1. The pause's end measured by its length rounds below the limit: the check would have failed on the rule
   as written (and `--mutants` would have called every mutant caught). Now against the time it is due; the
   mutants run the check unchanged first.
2. The device's own pointer move went out as PiP stopped with Sill away (its ✕, the lock, ten minutes
   paused): now it goes only with Sill's window in front.
3. The audio category was set after the controller was made, on a queue: now at once, before it.
4. The Mac's copies would have replaced the device's clipboard while the person was in another app: now
   not written while the picture shows only in PiP (rule 8).
5. Home, then straight back: the scene's activation could come before iOS started PiP, leaving it over
   Sill in front: now stopped half a second after it starts with the window in front (rule 7).
6. The controller outlived the switch in a window that was not offered: now let go whatever the offer.
7. A layout iOS makes for its app-switcher snapshots could send a viewport while PiP showed (a restart, a
   window resized with Aa): now held until Sill's window is in front (rule 8; P17).
8. The audio session was made active on the main thread, and a failed take never tried again: now on a
   queue of its own, tried again at each look.
9. No `invalidatePlaybackState()` at the start: now at every start.


## Progress

- 2026-11-11: plan written; the Apple documentation checked; the rule, its check, the glue and the switch
  written, and reviewed by an independent read before any build (nine findings, fixed in 40dbfe6), while the
  disk was under the 25 GB floor (15 to 22 GB free) and builds and simulators were paused. Draft pull
  request #353.
- 2026-11-12: main at 936d627 (#339, #349) merged in (61bbee7; CLAUDE.md alone conflicted; #349 changes the
  saved records and the remote dial's candidates, not the foreground rules). G1, G2, G3 done; G4 shows the
  simulator has no Picture in Picture. Next: Noah's devices (P1–P20).
