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
