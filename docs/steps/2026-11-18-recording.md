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
- **Verified:** filled in below when the run's checks are done.
