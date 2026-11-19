**Recording the stream to Files › Sill Recordings (#284), on addhumal's #303: the merge, the wire's two fields and the Mac's notice (2026-11-18, branch `recording` from `sill-audio` at 98f234d5, on main's eb48ac9; draft #407).**
Noah, 2026-11-18, among the next features: "screen recording", with "Anything that it would make sense to add a toggle
to you should add a toggle"; #284 is his issue (his request of 2026-11-02 and its implementation notes). The plan is
docs/recording-plan.md (its review of #303, the assessment, is in the handoff folder beside it). This branch sits on
#394 (SillAudio), whose decoder the recorder will use. The plan has ten commits; this first run did its first three.
- **1, the merge of #303** (d94e51b9): Aditya Dhumal's 488fce43 as it is, so #303 shows as merged when this lands (as
  #355 did with #173). Its four conflicts with main keep both sides: the panel's `@AppStorage`s (Shake to Show
  Controls', then Record Sound's), `tearDown` (Picture in Picture's end, then `stopRecording()`), and on both stream
  screens the light after `LockedMacShade`, then main's `LinkLineView(text:lines:)` and Full Screen's
  `HiddenPictureElement`. One line more so it builds on #394: StreamRecorder.swift imports SillAudio, where
  `AudioDecoder` lives now. It behaves as #303 does; the plan's later commits replace most of what is under it.
- **2, the wire** (279952b0): `ClientStats.recording` (true while the device records, left out otherwise, never
  false; display only; the initializer's parameter last, nil by default) and `WindowList.recordings` (1 from a host
  whose menu and log say it; set after the initializer, as `keyRepeat`, in every list). Each is declared away from
  the lines the camera's and the files' branches add to the same two types, so whichever lands second merges
  without a conflict there. `Tests/checks/compatibility` checks both ways (round trip, left out when nil, nil from
  the peers before, skipped by the readers before) with four new mutants; its README's three texts, which merges
  had left "to be made one when the check next changes", are one.
- **3, the Mac** (70acc38b): `RecordingNotice` (Sources/SillHost, pure): `generation` 1, and each connection's log
  lines, "Recording: iPad (iPad14,1) started recording the stream.", "… stopped …", at most one every 10 s per
  connection, the changes in between counted in the next ("(3 more changes since the last line)"), the state
  brought up to date by the first report after the spacing, and "… left while recording the stream." (or a held
  stop) as the connection closes. The coordinator puts `recordings` in every window list (LockPolicy.list keeps it
  while locked), each report's `recording` into the device's `HostStatus` and through its connection's lines,
  and writes the last line as the connection closes, before the device leaves the snapshot that names it; it
  keeps nothing past the connection and acts on nothing. The menu (StatusText): the headline's subtitle starts
  "iPad is recording the stream." ("2 devices are recording the stream.") and the device's row "Recording · ";
  the glyph is unchanged. DebugHooks' preview samples `recording` and `recording-two`. `sillclient.py`
  `--recording@T`, `--recording-off@T` (a report at once, then one a second), `recordings=` on each list and
  `--expect=recordings=N`. `Tests/checks/recording-notice` is new: the words, scripted sessions, 20,000 random
  sessions against the invariants, 26 mutants.
- **Where this differs from the plan, and why.**
  - The log's lines start "Recording: ", as the overview (§2.1) asks of every new feature's lines; the rest of each
    line is the plan's.
  - The menu says a device records whatever else its headline says (test pattern mode and Screen Recording off
    included), not only beside the off-console view and "Pick a window…": it is the one thing #284 asks the Mac to
    say, and a test host's menu can then show it.
  - The plan's G2 expected Sill's lines at 2 s and 8 s; its own limiter writes a stop 6 s after a start only once
    the 10 s are over (or at the close). G2 here starts at 2 s and stops at 13 s, and the flood is on a second
    connection.
  - A case for `lock-policy` (a locked list keeps `recordings`) is left for the next change to that check, whose 189
    mutants take most of an hour of the shared lock; G2 shows it live instead, on a test host made locked.
- **Settings** stay where #303 put them for now (the panel's Mac group). The plan's commit 7 moves the rows to the
  first group of This iPad (This iPhone), with the Stop row on top; when draft #393 (the whole-screen Settings pane)
  lands, they go into its device part and the Stop row into its header.
- **Verified** (on c1d3b155, the head with all three):
  - CI, run 44393534359 ("Build and check", 19 min 43 s): `swift build -c release` (Xcode 27.2), all 75 pure checks
    (`compatibility` 177 checks, `recording-notice` 23, `lock-policy` 1,411 unchanged), and the iOS app for the
    simulator (Xcode 27.1, `** BUILD SUCCEEDED **`) with only StreamClient's known capture warning: the merge and
    StreamRecorder.swift add none. The merge commit's own run was cancelled by the next push; its iOS sources are
    the head's but for ClientStats' new parameter, which has a default.
  - On this Mac, in one hold of the heavy lock: the branch and the base (98f234d5) built from scratch, each with
    only the known CaptureProbe warning, none new; `compatibility` with its mutants, 42 of 42 caught;
    `recording-notice` with its mutants, 26 of 26 caught.
  - G2 (loopback test hosts only: a synthetic SillHost and the bare SillMenuBar, both with SILL_TEST_LOOPBACK,
    SILL_TEST_SOFTWARE_ENCODER, SILL_TEST_NO_ROUTER and SILL_TEST_NO_SCREEN, each under a minute), 13 of 13: an
    iPad's lines at 2.16 s and 13.16 s (`--recording@2 --recording-off@13`); on a second connection six flips in a
    second (3.0 to 4.0 s) made two lines, at 3.05 s and 13.11 s, the second "stopped recording the stream. (4 more
    changes since the last line)"; a device that left while recording, "started" at 1.05 s and "left while
    recording the stream." at its close, 5.06 s; six lines in all; every list `recordings=1`, a locked Mac's too
    (`SILL_TEST_LOCKED_FILE`: "0 windows … locked=1 recordings=1"). The bare app (`-requirePairing NO`, a TLS
    client): at 6 s its menu read "Test Pattern Mode / iPad is recording the stream. Not advertised; test clients
    connect to port …" and "iPad (iPad14,1) — Recording · 0 fps · …"; at 15 s, after the stop, neither; its log
    has the start line. Its defaults domain was put back as it was.
  - Previews (`-SillRenderPreviews`), the base's twice and the branch's: the branch adds only the four
    `card-recording*` pictures; menu.txt only the two samples' sections, its other 32 the base's; 314 of the 318
    other files byte for byte the base's. The four others are Settings › General's two panes in each look, whose
    "Running from" row shows each binary's own folder (the base's, longer, wraps onto a second line): not this
    change.
  - Not run here, and why: `Tests/checks/run-all.sh` ran on CI for this commit (above) rather than again in the
    shared lock; `lock-policy`'s case for `recordings` (above); nothing on a device: the device sends no
    `recording` yet (the plan's commit 6), so Noah has nothing to try from this group.
- **Proposed words** for the site, What's New and the review notes: none yet; they come with the device's commits
  (the plan's "Docs, site and App Store words", commit 9). The Mac's own words are above.

**Run 2 (2026-11-19): the device's rules, then the recorder, the client and the views.**
- **4, the device's rules** (the plan's commit 4): `RecordingPolicy` (rules 1–3, 5, 6, 8–11 and `Copy`),
  `RecordingClock` (rule 4) and `RecordedSound` (rule 7), Foundation only, pbxproj A284–A286/F284–F286. Beyond the
  plan's text:
  - `RecordingTimeline` (in RecordingClock.swift): the recorder's order of things as a pure type, rules 3 to 7
    together (the light's start, the pre-roll before 0:00, the chain, the clock, parts opening at a keyframe and
    closing at new parameter sets, each part's sound track, the follow), as actions the recorder carries out. So the
    random recordings run the decisions StreamRecorder makes, not a copy of them.
  - The clock keeps the Mac's time (stamp + correction) and goes on from the last picture at a step, also among the
    pictures before the anchor (a step inside the pre-roll's second made a 5.7 s jump in a random recording before
    this); a picture of a step back that is not yet seen is held a tick after the last one written.
  - A frame delivered twice is known by its stamp (the last 8 written), not by its time: a picture whose time a
    step back has not yet corrected is not a duplicate, and dropping it would break the chain.
  - New parameter sets empty the pre-roll and make the kept keyframe stale (a light between a new source's kind 0
    and its keyframe wrote the old source's frames into the new one's part in a random recording).
  - `SillDocuments` (the next features' overview, §2.3; no branch had it): the one owner of Documents, pbxproj
    A289/F289 (one past the plan's A284–A288, free on main, the 299 branches and the 115 pull request heads). The
    check's source rule lets only it name the Documents directory (the plan's text named StreamClient+Recording;
    the overview's rule is the one followed); #303's `StreamRecorder.folder` goes through it until the rewrite.
  - Space: minutes left at most 999 (a still window without sound writes almost nothing); an unreadable free space
    allows the start. Bytes are decimal (1 MB = 1,000,000), as Files counts them.
  - The light's time is the stop's formula at now (A − floor + correction − anchor, never before the last
    picture), not the newest sample's time: a still window without sound writes no sample for minutes, and the
    movie lasts to the stop all the same, so this is the time the movie would have.
- `Tests/checks/recording` (new): every rule's cases, `SillDocuments`, the timeline scripted, 20,000 random
  recordings against the invariants (each track's times increase; no jump beyond the link's own spread, through
  the Mac clock's steps and stalls; a delta only after its keyframe; each part closed after its last picture,
  its sound to its end and nothing held; the sound never 0.5 s behind the picture and each packet within 20 ms of
  its stamp; the recording's asks a second from any other; "Starting…" always has an ask or its give-up due, and
  gives up only with a Mac that skips the asks), and the source rules. 84 mutants. KeyframeRecovery compiled in
  for `answerWait`.
- `lock-policy`: a locked list keeps `recordings` (both locked readings), and its one mutant, "list: a locked list
  drops `recordings`". Only that mutant was run of the check's 189: no other mutant's pattern is in what changed
  (main.swift alone), and each of their patterns was confirmed to match once, a text check.
- **5 to 8, the recorder, the client, the views, the manifest** (the plan's commits 5 to 8): #303's recorder, taps
  and rows replaced by the plan's own; #303's file name, Record Sound's key (`Sill.recordSound`, on), the two
  Files keys, `Documents/Sill Recordings`, the count's shape, `stopRecording` in `tearDown`, the background task
  and `-SillRecordFor` kept.
  - StreamRecorder carries out RecordingTimeline's actions: its own samples (a delta marked not sync and
    depending on others), the Mac's stamps through the clock, its own AudioDecoder per epoch and RecordedSound's
    writes to AAC at 160 kbps (the tail held for its fade), a movie per picture size in fragments every 4 s, each
    part's session ended at the stop's time, `startSession` 10 s before 0:00 so the pre-roll's times stay
    positive, the writer's status and error read (never `cancelWriting`, which deletes the file). A picture
    not written breaks the chain and skips the rest of its batch.
  - Every kind 44 now goes through `sendKeyframeRequest`, which notes `lastKeyframeAskAt`: the recording keeps
    a second from it, or awaits the picture recovery's ask while its keyframe is due (`recoveryAskDueUntil`).
    One held ask at a time (a random recording found two asks in the same instant before this).
  - The sound is decided at "1", not at the light: the recorder exists from "1" to tap the pre-roll, a second
    before the light.
  - Endings: Stop and Cancel (Settings), the session's end (`tearDown`), the app's background, this window's
    scene's background (an iPad's other window going away ends nothing), `protectedDataWillBecomeUnavailable`,
    space, the writer's failure, the give-up. Picture in Picture ends it (decision 4), as the app's background.
  - The note is the recording's own (`recordingNote`, 4 s; a note made while Sill is away waits for its return):
    over the stream in the clipboard chip's corner (the chip waits meanwhile), in Settings' top row, on the
    connect screen. "Your recording was saved when the session ended." is one sentence more than the plan's list
    (its P11 asks for words there); "Nothing was recorded." when a recording stopped during "Starting…".
  - Settings: This iPad's first rows (Start Recording, Cancel, Stop; Record Sound shown, dimmed showing off, or
    hidden; the footnote with the older-Mac sentence by `WindowList.recordings`, now kept as
    `hostRecordings`), and Stop pinned under the header while it counts or records. When draft #393 (the
    whole-screen Settings pane) lands, the rows go into its device part and the Stop row into its header.
  - DeviceIdlePolicy: `Uses.recording` (decision 9), device-idle's cases and mutant M18.
  - The privacy manifest declares DiskSpace (E174.1, 85F4.1), read once a second at most through
    `SillDocuments.availableCapacity` (the one place, so the check's Documents rule holds). release-ios.sh's .ipa
    check refuses a build without the two Files keys.
  - Not built from the plan: `-SillRecordingFail` (a writer made to fail on the device: the rig's `full` case uses
    the space rule instead, and a real full disk is left to Noah's P15), and the rig's `move` case (a second
    connection only approximates a move's fenced hand-over; the random recordings deliver frames twice instead).
  - The rig reads its sound's clicks against the Mac's whole seconds from each part's 0:00 on the Mac's clock,
    which `StreamRecorder.Outcome.partStarts` gives it.
- **Proposed words** (for the release that ships it; not in any page yet):
  - README, in what Sill does: "Record what you stream: Settings › This iPad › Start Recording saves your Mac's
    picture, and its sound, as a movie in the Files app."
  - site/support.html, "Recording what you stream" (between `<!-- Recording` and `<!-- /Recording -->`): "In Sill's
    Settings › This iPad, tap Start Recording. After a 3, 2, 1 count, a red light with the time and size shows over
    the picture. Tap Stop Recording at the top of Settings to finish. The movie is in the Files app, in On My iPad ›
    Sill › Sill Recordings. It is the picture your Mac sent, without Sill's controls or the pointer, with your
    Mac's sound when Send Audio and Record Sound are on. A new picture size starts a new movie. The recording ends
    when you leave Sill, disconnect, or the device is almost full. Sill on your Mac shows in its menu that a device
    is recording. Deleting Sill deletes the folder: move what you keep to Photos or iCloud Drive."
  - site/privacy.html: what travels to the Mac, "Whether the device is recording the stream, once a second with its
    other numbers, so Sill for Mac can say so in its menu."; what stays on the device, "Your recordings, in Files ›
    On My iPad › Sill › Sill Recordings: in the device's backups like your other files, readable only while it is
    unlocked, and deleted with Sill; and whether Record Sound is on."; what the Mac's log keeps, "Which devices
    recorded the stream, and when."; Deleting your data, "Delete the Sill Recordings folder in Files, or delete
    Sill."
  - What's New: "Record what you stream: Settings › This iPad › Start Recording saves your Mac's picture, and its
    sound, as a movie in the Files app."
  - The review notes' "NEW IN" paragraph, 271 bytes (the overview's 300 at most): "Settings › This iPad › Start
    Recording saves the Mac's picture (and, with Send Audio on, its sound) as a movie in Files › On My iPad › Sill ›
    Sill Recordings, after a 3-second count. A red light shows while it records; Sill for Mac's menu says a device
    records."
- **Found by the rig's first run, fixed in the same run:**
  - A still window recorded a movie 0.067 s long: AVAssetWriter gives a last sample without a duration one frame's
    time, not the session's end, and that sample was the pre-roll's keyframe, before 0:00 (a keyframe written at
    0:00 itself, the older Mac's still case, did last to the end). The plan's fallback is built: each picture is held
    back until the next one, or the part's end, gives its duration, its sample made then with that duration (not a
    copy with new timing, which Core Media does not promise keeps the not-sync mark).
  - The test tone's clicks: AVAssetWriter's AAC keeps the sound sample-exact. Every click of the plain case lay
    0.09 ms from its whole second of the Mac's clock (moviecheck's first click finder was wrong; read again).
  - A recording killed 9 s in kept 7.96 s in its fragments; a still window from an older Mac started from its kept
    keyframe and lasted the 9 s; Starting… against an older Mac asked at 5.0, 9.2 and 13.3 s and gave up with no
    movie; the space rule stopped a recording 10 s in, its movie whole; a locked Mac's placeholder made a movie of
    its own between the Desktop's two; the Desktop stepping to another size made "(2)".
- **Verified** (run 2):
  - CI: run 44510170041 on 2596f194 and run 44517315333 on 25a89d99 (the recorder's last code change and this
    step file) passed: `swift build -c release`, every pure check, the iOS app for the simulator, the CLI.
  - The first hold of the heavy lock (06:00 to 06:30; HEAD 4b36e876, its iOS builds of d6ec05f9's tree): the
    release build (the known CaptureProbe warning alone); `recording` 400 checks, `device-idle` 53, `lock-policy`
    1,413, `compatibility` 177, `recording-notice` 23; mutants: `recording` 81 of 84 (two gaps, now cases, and one
    equivalent mutant, now out), `device-idle` 18 of 18, and of `lock-policy` its one new mutant, caught (its other
    188 not run: only main.swift changed, and each of their patterns still matches once, a text check); the iOS app
    Debug and Release for the simulator and Debug for a device, `** BUILD SUCCEEDED **` each, with the known
    StreamClient capture warning and one new (the note's observer, fixed); the built Info.plist carries both Files
    keys, the built privacy manifest DiskSpace, the binary one DiskSpace symbol; `Tests/checks/run-all.sh` 76 of 76.
  - The second hold (06:57 to 07:02; HEAD 25a89d99): `recording` 403 checks and its two re-run mutants caught, so
    83 of 83; the rig, every gate of its ten cases (plain: 20 s, 1,183 pictures of which the 5 keyframes are the
    sync samples, all 20 clicks within 0.1 ms of their second; still: 13 s from one picture; still-sound: 13 s,
    13 clicks within 0.1 ms; parts: two movies; oldmac-still: from the kept keyframe, 9 s; oldmac-gaveup: asks at
    5.0, 9.2 and 13.3 s, the give-up, no movie; oldmac-moving: from the Mac's own keyframe; kill: 7.96 s kept of 9;
    full: stopped for space at 10 s, the movie whole; lock: three movies); the iOS app Debug for the simulator, `**
    BUILD SUCCEEDED **` with the known warning alone.
  - Not run here: `release-ios.sh` (it archives and signs); nothing on a device.
  - Photos (G5, `Scripts/harness-photos/recording.cases` on the agents' Duo, iOS 27.1, of c5c5af13): the first try's
    first `simctl launch` hung (stopped at 301 s, the simulator shut down, the slot freed); after 10 minutes the
    second took all 28 in 188 s, none blank. Looked at: the This iPhone rows (Start Recording, Record Sound dimmed
    and off with Send Audio off, the footnote whole), an older Mac's (no Record Sound, the older-Sill sentence), the
    pinned Stop row ("Recording · 0:42 · 126 MB") with the light over the picture, the light moved to the bottom
    corner under the link's line, the iPhone upright's light, "Saved to Files › Sill Recordings." in the chip's
    corner, the connect screen's "Your recording was saved when the session ended.". No baseline: main has none of
    these states.
