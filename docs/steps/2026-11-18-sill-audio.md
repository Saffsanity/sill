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
