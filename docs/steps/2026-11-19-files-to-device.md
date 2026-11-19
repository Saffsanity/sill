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
  it asks), Save Photos and Videos to Photos (off); on the Mac, a switch for the device's Get Files under Share files
  with devices. They sit where Settings is today and move into the whole-screen pane of #393 (`settings-pane`).
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
