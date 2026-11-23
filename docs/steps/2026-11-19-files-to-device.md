**Files and photos from the Mac to the iPhone or iPad (2026-11-19, branch `files-to-device` from the branch `files` at f1e264e6, which carries main at eb48ac9).**
Noah, 2026-11-18: "share files and photos between iOS and Mac" (one of the six features of that night's assignment),
"Anything that it would make sense to add a toggle to you should add a toggle", and that every task he opened that
the assignment names has an agent assigned and a pull request in progress. The files branch (draft pull request
#391, on @addhumal's #189) sends files and photos from a device to the Mac; nothing goes the other way yet. This
branch is the plan's second pull request (docs/files-plan.md §14, steps 7 and 8; the overview's decision 8: "Two pull
requests: device to Mac, then Mac to device"), based on `files`, so its pull request shows only this half; it merges
after #391.

The plan for this branch (the plan's §5.4, §7.5, §8.4, §9 and §10; the overview's §2.1 to §2.3):
- **The device takes files**: its hello says `files` 1, so a Mac offers it the files its person sends and answers its
  pick. They land in the Files app, On My ‹iPad› › Sill › From ‹Mac›, through one owner of Documents (`SillDocuments`,
  the overview's §2.3: From ‹Mac› protected `complete`), staged in Library/Application Support until whole and
  checked. A chip asks first ("‹Mac› wants to send you…", Accept, Decline) unless the device asked for them, shows the
  percentage, and ends with Show and, for a photo or a video, Save to Photos.
- **The Mac gives files**: the device's Get Files from ‹Mac›… (a `pick`, answered with the Mac's Open panel), and
  Sill's menu Send Files to ‹device›…; each file read in parts on `sill.files` and sent on a path of the server's own
  that waits while the picture needs the link (`FileFlow.hostMaySend`: never ahead of a keyframe, at most one part in
  Sill's own queue), paced by the device's acknowledgements.
- **Switches** (Noah's toggle rule; new behaviour off until turned on): on the device, Ask Before Receiving Files (on:
  taking files unasked stays off until it is turned off), Save Photos and Videos to Photos (off); on the Mac, Share
  files with devices covers both directions (see the defaults below). The device's sit where Settings is today and
  move into the whole-screen pane of #393 (`settings-pane`).
- **Never** shown on this Mac in a test: an Open panel (a TEST ONLY choice of files answers a pick on a test host),
  the simulator's photo library beyond what Scripts/harness-photos.sh does.

**First building run (2026-11-19): the Mac sends, the device takes.** Five commits on top of `files` (f1e264e6):

- **The rules and the device's words** (07050315): `FilePolicy.deviceGets` (the Get Files row and the receiving
  switches only where the Mac gives files, `files` 2), `FilePolicy.askedFor` (an offer is taken without asking only
  when it says `asked`, names the transfer of this device's own pick and comes within the panel's 3 minutes and 30 s:
  a Mac's word alone never skips the question; `deviceAnswers` takes this judgement), `FileFlow.hostMaySend` with
  the frames' quiet (a device waits for a keyframe from its connect until the first comes, so with nothing picked the
  Mac's files would never have gone: the wait holds files only while a frame went to any device within a second),
  and in FilesCopy+Device everything a device shows of files from the Mac (`IncomingFiles`, the chip's words in the
  receiver's own voice, the folder From ‹Mac›, photos and videos by extension, which chip shows first).
- **The Mac sends** (782b59b9): StreamServer's send path for the Mac's parts (one waits in a device's slot until
  FileFlow.hostMaySend allows; FileHub hears `onFileRoom` once it went, and only then reads the next), `takesFiles`
  from the hello, `lastInput(from:)`; FileHub both ways (the Mac's offer to a device by FilePolicy.macOffers, regular
  files only, read in parts and hashed within the device's window; the device's answer, acks, done and cancel; a
  device's pick by FilePolicy.takesPick with `onPick`, `pickEnded` and the panel's 3 minutes; every stop for both
  directions; the running count for both, so Sill.app's App Nap hold covers the Mac's sending); the coordinator (who
  takes files, each device's route and link for the window, `files` 2 where the host gives files); the log's lines
  for the Mac's own transfers. TEST ONLY on a test host: `SILL_TEST_FILES_PICK=<path>[:<path>…]` answers a pick with
  those files and no Open panel (the list says 2), `SILL_TEST_FILES_OFFER='<s> <path>[:<path>…]'` offers them s
  seconds after a device that takes files connects, as Sill's menu would.
- **The device takes** (821649a0): the hello says `files` 1; DeviceFiles' incoming side (asked about, or taken at
  once for its own pick; parts from the network queue written at once and acknowledged on the person's lane; each
  file checked, 0644, protected `complete`, moved into Documents › From ‹Mac› under a free name; Accept, Decline,
  Cancel, Get Files and its end; every stop and each launch delete what was partial); `DeviceInbox` (no stat-family
  call: Scripts/release-ios.sh refuses file-timestamp APIs the privacy manifest does not declare); `SillDocuments`
  (the overview's one owner of Documents, A18D/F18D); `PhotoSaver` (Save to Photos, add-only, A18E/F18E); the chip
  (the Mac's question with Accept and Decline, Get Files waiting with Cancel, the percentage, the end with Show
  through Quick Look and Save to Photos); the rows in today's Settings panel (Get Files from ‹Mac›…, Ask Before
  Receiving Files, Save Photos and Videos to Photos, the line and the footnote; they move into #393's whole-screen
  pane, its device part); the background task, auto-lock and the moves for either direction; Info.plists:
  UIFileSharingEnabled, NSPhotoLibraryAddUsageDescription.
- **The gate H6 and the harness**: `sillclient.py --accept-files=DIR --decline-files --ignore-files --pick-files@T
  --cancel-receive@T --receive-pace=B --expect-received=N` (any of them: the hello says `files` 1);
  `Scripts/files-check/live.py OUT give` (offered on cue and kept byte for byte, a device that takes no files offered
  nothing, declined, a pick answered as asked for and the list saying 2, a second pick within 5 s refused `rate`, an
  unpaired session's pick `notPaired`, `--no-files` refusing a pick `off`, the device's cancel mid-file, the Mac
  locking mid-file); `-SillFiles incoming|picking|receiving|received|received3|photosSaved|receiveStopped`.

**Defaults taken for Noah to confirm** (the plan's recommendations, and this run's): the device asks before taking
files it did not ask for (Ask Before Receiving Files on; plan Q5 a); photos and videos land in Files, Save to Photos
one tap, the automatic switch off (Q6 a; it asks for add-only access as it goes on and takes the files out of Files
once Photos has them, as §8.4 says); the Mac's one switch, Share files with devices, covers both directions (no switch
of its own for the device's Get Files: a paired device that can control the Mac gains nothing new by it); the end of
a transfer from the Mac stays 12 s on the chip (Show and Save to Photos need the time; one to the Mac stays 6 s); the
device's own Decline and a question nobody answered end without a chip; the Mac's files go only one part at a time
into Sill's own queue, never ahead of a keyframe while frames go, and a device that waits for its first keyframe
while nothing streams holds nothing up.

**Not in this run** (next): Sill.app's Open panel for a device's pick shown in the stream (FilePick, the catalog's
exception for that one window, the source switched to it and back; the plan's spike S0 first, which only Noah can
run, since no Open panel may be shown on this Mac in a test), so Sill.app says `files` 1 until then and its devices
show no Get Files row; Sill's menu Send Files to ‹device›… and drops on the menu bar icon; the status menu's card for
a transfer; H8's pacing cases for the Mac's sending.

**Heavy results** (one hold, 05:36 to 07:32, on a snapshot of dbb91c48; the scripts are in the handoff folder):
- `swift build -c release` in 64 s, only the known CaptureProbe warning.
- The gates H3 to H6 (`Scripts/files-check/live.py all`): 56 of 56 against the release build, among them the files
  branch's corrected locked verdict and H6's 18 (offered on cue and kept byte for byte with nothing half written and
  no name in the host's output; nothing offered to a device that takes no files; declined; a pick answered as asked
  for with the list saying files=2; a second pick within 5 s refused `rate`; an unpaired session's pick `notPaired`;
  `--no-files` refusing a pick `off`; the device's cancel mid-file; the Mac locking mid-file).
- H2, the CLI's stdout against main's (eb48ac9f) in the same hold: the same lines, masked, and no counter main never
  prints (2 of 2).
- Mutants: files 115 of 115, device-files 38 of 38, file-hub 31 of 33. The two file-hub survivors were gaps in the
  check, not bugs: a folder is refused anyway for having no size (the regular-file test is there for a named pipe,
  which has a size, 0, and would block the hub's queue on its first read), and a file that shrank stopped `cantRead`
  one read later anyway (the check now looks at every part handed); sharpened in 06c7567b. In a follow-up hold
  (07:53, ef4c1af3: file-hub 80 and device-files 105 pass) the short read was caught; the regular-file mutant was not,
  and cannot be: Foundation gives no file size for a folder, a named pipe, a socket or a device, so the size's test
  refuses each anyway. FileHub keeps both tests; the mutant now removes both (5023aec4), caught at 07:58 by the
  named pipe and the folder. So every file-hub mutant is caught (33).
- `Tests/checks/run-all.sh`: all passed but device-files, 104 of 105: the second run's case "the copy and its folder
  deleted after the transfer" looked at once, while DeviceFiles deletes its own copies just after it publishes the
  end, so on a busy Mac the check could look first (it passed locally, in CI and in every mutant run). It now waits
  for them, here (7497f070) and on `files` (1f774638), merged in (93ce9a2c).
- The iOS app, Release for a device, not signed: built in 60 s; its one warning is main's own (StreamClient's window
  drop-off, line 4583), as in the second run.
- CI on #417 green at dfff57b3 (run 44507553550): release build, run-all, the iOS app for the simulator, the CLI.
- Harness photos on the agents' Duo (iOS 27.1), 17 cases against `files` (f1e264e6), in a hold of their own: the
  first try (07:32) hung in its first `simctl launch` for 7.5 minutes with nothing photographed and was stopped as the
  agents' rule says (the Duo shut down, the slot freed); the second (07:59, after 10 minutes outside the lock) took
  them all in 269 s. The four that must not change are identical (Settings' Files rows at `files` 1, the chip sending,
  the stream, Settings' end); the 13 new ones differ as they should and were looked at: Settings with Get Files from
  ‹Mac›…, Ask Before Receiving Files (on), Save Photos and Videos to Photos (off) and their footnote, also with a
  transfer's line and upright; the chip's question ("Mac mini wants to send you “IMG_1204.heic” (48 MB).", Decline,
  Accept), Get Files waiting ("Choose files on Mac mini", Cancel), receiving (42%, its bar, Cancel), received ("3
  files from Mac mini are in Files › Sill.", Show, Save 2 to Photos), saved to Photos, a full iPhone. One defect: on
  the cover the question cut the file's name away ("…c” (48 MB)."); fixed (a0ed8e82: the words above the buttons
  where one row does not fit), and photographed again (08:09, 6 cases against 7bd9ddc0): the cover's question now
  whole above Decline and Accept, the five others (the question on the inner display and upright, received, sending,
  sending on the cover) identical.

**Second run (2026-11-23): `files` merged in twice, with main at c33d1057 and then at 5d062a3c.** GitHub reported
#391 in conflict with main, so main went into `files` first (cf965192: #399 native tab switches followed in a staged
window, #396 sound from a window on Sill's display, #402 Lock this Mac when the last device leaves; seven conflicts,
each two additions side by side, settled in that branch's step file), then `git fetch origin files`, `git merge
FETCH_HEAD` here: b7fd8bca. main moved on during the run (#389 the support page, #418 keys above any keyboard on an
iPhone held upright), went into `files` too (23b26345: one conflict, the Settings panel's This ‹device›), and so here
again: d4097661. Neither merge conflicted here: git merged StreamCoordinator.swift (the Mac's sending beside the
privacy lock's lines), TestHooks.swift (the lock's variables, the files', then SILL_TEST_FILES_PICK and
SILL_TEST_FILES_OFFER), HostSettingsPanel.swift (main's Hide Thumbnails While Typing beside Larger Picture, then the
Files rows with Get Files and its two switches), ContentView.swift, the pbxproj (PhoneKeyboardLift's A0B0/F0B0 beside
A188 to A18E: no id twice, `plutil -lint` OK) and docs/BUILD-AND-RUN.md, DEVELOPMENT.md and LAYOUT.md by itself, each
with both sides kept. No product decision was needed: nothing of #399, #396, #402, #389 or #418 meets the Mac's
sending (a transfer belongs to a connected session; the lock's wait runs only once none is). Before each hold, with no
build: every mutant pattern a script lists plainly (1,574 in 63 checks) is found exactly once in the merged tree;
against this branch's last head only away-quality's AQ-O1 changed (found nowhere before: the branch had never had the
lock's arguments).

**Verified** (two holds of the agents' build lock, slot A, in this worktree):
- At b7fd8bca (15:57 to 16:49, with `files`' own part first): `swift build -c release` in 70 s, only the known
  CaptureProbe warning; the gates H3 to H6 (`Scripts/files-check/live.py all`), 56 of 56 in 235 s, H6's among them;
  H2 against main's c33d1057 SillHost, built from `git archive` and run in the same hold: the same lines, masked, and
  no per-second counter main never prints (2 of 2); mutants of the checks whose rules or patterns the merge touched,
  every one: away-quality 58 of 58, stage-release 25 of 25 (files', file-hub's and device-files' own were not run
  again: the merges changed no file they compile or read); `Tests/checks/run-all.sh` 79 of 79 in 906 s; the worktree
  clean afterwards.
- At d4097661 (17:34 to 17:50): this branch's Mac sources (Sources/, Scripts/files-check, Scripts/sillclient.py) are
  byte for byte b7fd8bca's, and main's Mac sources did not change from c33d1057 to 5d062a3c, so the build, the gates,
  H2 and the mutants above stand for it; `swift build -c release` (incremental, 30 s) and run-all 80 of 80 in 923 s
  (main's new phone-keyboard-lift 184 among them), the worktree clean afterwards.
- CI green at b7fd8bca (run 45150805503) and at d4097661 (run 45164183752): the release build, run-all (files 496,
  file-hub 80, device-files 105), the iOS app for the simulator, the CLI's paths. GitHub reports #417 mergeable.
- Not run on Noah's Mac: the iOS app's build (CI's simulator build is green at d4097661) and harness photos. This
  branch's photo cases show nothing the merges changed (the Settings cases start at the Files rows; the chips and the
  stream are untouched); a photo of the merged group with the mock Mac giving files (`next/files/run4/merge-f2d.cases`
  in the handoff folder) was queued after the second hold and not started: 26 GB free, under the 27 GB this run asked
  before two iOS builds. The second hold's first two turns of the lock (17:07, 17:12) had stopped before running
  anything, with 23 and 21 GB free (other jobs' builds), as the floor says.
- Known visible defect, carried from `files` (Noah's own test of #391 on 2026-11-20): the row "Send Photos to ‹Mac›…"
  takes two lines in the floating Settings panel with a long Mac name; "Get Files from ‹Mac›…" sits in the same panel
  and was never photographed with a long name. Named in #417's description; not fixed in this run.
