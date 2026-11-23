**SillAudio: the sound's encoder, decoder, packetizer and playout as one library both apps link, with no change in behaviour (2026-11-18, branch `sill-audio` from main at eb48ac9, #394).**
Noah, 2026-11-18, of the six features (#200's display, the microphone, recording, the camera, files,
privacy mode): "Any tasks that were opened by me that are mentioned above should have an agent assigned
and wip". This is the overview's item 5 (`sill-handoff/next/OVERVIEW.md` §4.1 and §2.3) and the
microphone plan's commit 1 (its §3.4, §5.1 and §12): the code the Mac's sound already has, moved where
the microphone (the encoder on the device, the decoder and the playout on the Mac) and recording (the
decoder in StreamRecorder and its rig) can both take it, before either starts.
- **What moved.** A new SwiftPM target and library product, `SillAudio` (`Sources/SillAudio/`,
  AudioToolbox and Foundation only, nothing of the wire), beside StreamProtocol:
  - `AudioEncoder.swift` from Sources/SillHost, and `AudioDecoder.swift` and `AudioPlayout.swift` from
    iOSClient, each moved whole (`git mv`);
  - `AudioPacketizer.swift`'s packetizer (`PCMChunk`, `AudioBlock`, `AudioPacketizer`); the rest of that
    file, the host's own rules around it (`AudioKey`, `AudioSourceRule`, `PCMLayout`,
    `AudioBufferTally`), stays in the host as `Sources/SillHost/AudioSourceRule.swift`, word for word.
  Their types and the members anything outside uses are `public` (with `PCMChunk`'s initializer
  written out, since a memberwise one is internal); nothing else in them changed but their header
  comments. SillHostCore depends on SillAudio; AudioPipeline, AudioCapture and SyntheticAudio import
  it, and so does the iOS app's AudioOutput. The Xcode project links the product (AA05, the framework
  build file, and DA01, the product dependency; free on main, every open pull request and every
  worktree) and drops the two files' four entries each (AA01/FA01, AA02/FA02).
- **Why the split of AudioPacketizer.swift.** Only what both later features share moves: which
  ScreenCaptureKit source the pipeline follows, a captured buffer's layout and the first minute's
  tally are the host's alone, and a library the iOS app links has no use for a Mac app's pid. It also
  keeps addhumal's #367 (which changes `AudioKey` and `AudioSourceRule`) merging cleanly: the host's
  file keeps those lines byte for byte, and git follows it as a rename (54% similar).
- **What did not change.** No behaviour, no API but access levels, no wire, no setting, no word a
  person sees. The plan's later additions (the encoder's `channels` and `bitrate` at init, the
  playout's `Mode.microphone`) are the microphone's own commits, not this one.
- **The checks and harnesses, at the new paths.** `audio-codec`, `audio-packetizer` and `audio-playout`
  compile the files where they are now (each run.sh, README, main.swift's header and mutants.py);
  `audio-packetizer` compiles both halves of the old file, and its mutants apply to whichever half
  holds their pattern, its list of mutants unchanged. Three of `audio-playout`'s mutants named
  `static let` lines that are `public static let` now. `Scripts/audio/build.sh` gives the harness's
  host package a SillAudio target (as the real package has) and its device the new paths;
  `Scripts/pacing/build.sh` builds a side with Sources/SillAudio the same way and a side from before
  it as before.
- **Docs.** docs/LAYOUT.md (the new folder, the host's AudioSourceRule, the iOS entries and the IDs),
  CLAUDE.md's list of the code's folders, and a note atop docs/audio-plan.md that its paths are those
  of before.
- **Verified.**
  - CI on #394 (run 44281228153): `swift build -c release`, all 74 pure checks, the iOS app for the
    simulator (`** BUILD SUCCEEDED **`, SillAudio built as a package product), no new warning (only
    StreamClient's known capture warning and CaptureProbe's).
  - The three moved checks print exactly what main's print (89, 21 and 218 checks; the playout's 5,000
    random runs too), main's from a `git archive` of origin/main. Their mutants: `audio-packetizer` 27
    of 27, `audio-codec` 9 of 9, `audio-playout` 38 of 38.
  - The sound harness (`Scripts/audio/run.sh`, every case): every gate passes but H12, the CPU gate that
    fails on every full run (its header). H12 then ran twice more on each side, main's harness (a `git
    archive`) and this branch's in turn: main +1.9 and +1.5 points, this branch +1.9 and +4.5 (+3.9 in
    the full run). The readings move from run to run with the Mac's load; the encode path itself does
    not: 30 s of the test tone through main's packetizer and encoder in one module, and through
    SillAudio's built as a module of its own, gave the same packets (2,029,015 bytes, FNV-1a
    518481e1053403fa) for the same CPU time (medians of five rounds 263.5 and 255.8 ms on main's, 261.9
    and 259.7 ms on SillAudio's: 0.85 to 0.88% of a core).
  - `Scripts/pacing/build.sh` builds both sides: origin/main's "with the sound" as before, and this
    tree's "with the sound (SillAudio)".
  - `git merge-tree` against this branch: #367 merges cleanly; #303, #156, #124, #191, #193, #189, #184
    and `settings-pane` conflict only where they already conflict with main.
- **Not run here:** docs/audio-plan.md's live simulator gate S2 needs `-SillLive`, which the agents'
  simulators refuse (next/OVERVIEW.md §4.3), so the device's engine with SillAudio's decoder and
  playout is Noah's to hear: Send Audio on, the Mac's sound plays as before.
- **Proposed words** for What's New, the site and the review notes: none, since nothing a person sees
  or hears changes.

**2026-11-23: main brought in (c33d1057: #399, #396, #402; merge e7ff9a84).** GitHub reported #394 in conflict
with main after #396 (`pr367-ready`, addhumal's #367 for issue #365) changed the Mac's sound: an app's sound is
captured on Sill's display while its window is staged there, `AudioKey.app` names that display (so Sill's display
made anew is a new capture), and the pipeline tries a failed source again by itself, at most every 160 s. This run
merged main and checked that the move's claim still holds: the library's code behaves exactly as main's.
- **The conflict.** One file, docs/LAYOUT.md (the sound's host files). This branch's `AudioSourceRule` entry is kept,
  with #396's words: `SILL_TEST_AUDIO_END`, and "with the retry's wait".
- **Where #396 landed.** All of #396's changes to the old `Sources/SillHost/AudioPacketizer.swift` were in its host
  half: the display in `AudioKey`, plus `retryCap`, `retryIn` and `failures`. Git followed the rename, so they are in
  `Sources/SillHost/AudioSourceRule.swift`. That file's 200 lines from `AudioKey` on are now main's byte for byte.
  - #396 did not touch the packetizer, the encoder, the decoder or the playout. So `Sources/SillAudio` is byte for
    byte the old head's (98f234d5), and no iOSClient file changed.
  - `AudioPipeline`, `AudioCapture` and `SyntheticAudio` are main's, plus `import SillAudio`.
  - `audio-packetizer` is main's check (106 checks, 42 mutants), compiling the two files. Each mutant's pattern is
    found exactly once in them: 15 in the library, 27 in the host's file.
  - #399 and #402 touch no sound file.
- **The move, as text** (`next/sill-audio/run-1123/movecheck.sh`). With `public ` removed, each of the library's
  three whole files differs from main's only in three header comment lines. The packetizer's two halves together are
  main's whole file, except for `PCMChunk`'s written-out initializer and one blank line.
- **Verified.**
  - CI on the merge (run 45149223674, e7ff9a84 merged with main): `swift build -c release` (140.5 s); all 75 pure
    checks, among them `audio-packetizer` 106, `audio-codec` 21 and `audio-playout` 218, the counts main's checks
    print; the iOS app for the simulator (`** BUILD SUCCEEDED **`); the CLI's `--internet` (exit 2) and
    `--print-reachability`. No new warning: only CaptureProbe's and StreamClient's known capture warning.
  - Work in flight (`git merge-tree`, 39 open pull requests against main and against e7ff9a84): 36 conflict exactly
    where they conflict with main. #175, #411 and #195 conflict in the Xcode project alone, as they did against
    98f234d5. The microphone (#415) and recording (#407) conflict only in #402's files and docs/LAYOUT.md.
  - GitHub: mergeable and clean, also once main moved on to 5d062a3c during the run (#389, #418: the site and the
    iOS key row, no file of this branch's; not merged here).
  - **Not yet run here: the local hold** (`next/sill-audio/run-1123/hold1.sh`): H2 against main's CLI, #396's
    `retry_gate.py` on both CLIs, the sound harness's every case (with #396's `retry`), `audio-packetizer`'s 42
    mutants, the three sound checks' output against main's, the pacing build and `run-all.sh`. The 0.7 set had the
    lock until 19:23, and from 17:15 on this Mac had 24.2 to 24.4 GiB free, under the 25 GB floor; it is queued for
    when the space comes back (`run-1123/queue.sh`).
- **Not run.**
  - The live simulator gate S2, as before: it needs `-SillLive`, which the agents' simulators refuse.
  - The encode bench of 2026-11-18. Its inputs did not change: main's packetizer and encoder are unchanged since
    eb48ac9f, and the library since 98f234d5.
  - `audio-codec`'s and `audio-playout`'s mutants. The merge touched neither check nor any file they compile; on
    these same files they were 9 of 9 and 38 of 38.
  - #396's ScreenCaptureKit behaviours (a filter on Sill's display, its end when that display goes). These are
    Noah's on main too, and this branch changes none of that code.
