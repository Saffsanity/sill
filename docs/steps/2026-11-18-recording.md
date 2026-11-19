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
