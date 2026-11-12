**Picture in Picture (2026-11-11, branch `picture-in-picture` from main at dd6ea6a; issue #291, Noah's: "I
want to get PiP support in the next version"; the plan, what Apple documents and does not, the rule, what a
watcher sees, nine open questions with the defaults taken, the gates and Noah's device tests are in
`docs/picture-in-picture-plan.md`).** Leave Sill while the Mac's picture shows, and it keeps playing in iOS's
Picture in Picture window. Device only: no wire change, nothing on the Mac, one device setting never sent.
- The switch: Settings › This iPad (This iPhone) › Picture in Picture, the group's first row, where iOS has
  it (`PictureInPicture.supported`); off by default (`PictureInPicturePolicy.defaultOn`, open question 1;
  `Sill.pictureInPicture`, `StreamClient.pictureInPictureKey`), its footnote naming iOS's own Start PiP
  Automatically, without which iOS never starts it (no button of Sill's: open question 2).
- The rule (`PictureInPicturePolicy`, pure, `Tests/checks/picture-in-picture`): offered
  (`canStartPictureInPictureAutomaticallyFromInline`) while the switch is on, iOS supports it, the session
  is connected and streams a source whose picture has come and no locked-Mac cover shows, for the window
  chosen (`chosen`: the one used last among those in front; while none is in front the last choice stands, so
  leaving never withdraws it). Sill never starts it in a Release build (App Review rejects an app that does
  on its way to the background): iOS does. While it plays the picture counts as watched (KeyframeRecovery's
  `active`), the sound as heard (AudioOutput, `soundHeard`), and while it is active, paused or not, Sill runs
  as in the foreground (`running`: the reconnect's dials, a browser made again; a stay in the background it
  covered throughout makes no browser again on the return). Its pause freezes the picture (no frame onto the
  layer, `HEVCDisplayView.setFrozen`) and the sound, the Mac still sending; play asks for a keyframe; ten
  minutes paused (`pausedLimit`) stops it. The session's end (`tearDown`), the window back in front, the
  device's lock (`protectedDataWillBecomeUnavailable`, with a passcode) stop it; a move keeps it. The
  device's own pointer move to a new frame's middle and its viewports wait, and the Mac's copies are not
  written to the device's clipboard, while the picture shows only there (`onlyInPictureInPicture`). The
  `Lifecycle` struct carries AVKit's events and the endings, so the glue only carries its answers out.
- The glue (`PictureInPicture.swift`): `PictureInPicture`, one per StreamClient, AVKit's controller on the
  display layer (`HEVCDisplayView.sampleBufferLayer`) made only once offered, `requiresLinearPlayback`, a
  live range (start zero, infinite duration), the five playback delegate methods and the sixth (sound kept
  while the window is tucked away), restore at once; `PictureInPictureHub`, the windows as DeviceIdleTimer
  lists them (WindowSessionObserver), the choice, each window's offer. The audio session stays `.playback`
  mixing with other audio, held active on a device while a picture is offered or shows (`SharedSession`'s
  extra holder), so another app's music never stops (open question 5). `UIBackgroundModes` `audio` in both
  Info.plists, for this alone (docs/audio-plan.md notes it). pbxproj A291/F291 (the rule), A29A/F29A (the
  glue). DEBUG: `-Sill.pictureInPicture 1`, `-SillPiPSupported 1|0`, `-SillSettingsScroll pip`,
  `-SillPiPStartAt <s>`, `-SillPiPPauseAt`, `-SillPiPLockAt`, `-SillPiPSession active|inactive`, the
  console's `pip:` lines (ContentView's contract, docs/DEVELOPMENT.md).
- What the window shows: the video layer alone (the pointer sprite, the covers' words, the link's line and
  the zoom are Sill's views): a window or the Desktop at its own shape, a locked Mac's lock screen, black for
  another user's (open question 7). docs/app-store-metadata.md holds a What's New paragraph and a review
  notes line for the next version (the background mode's purpose, guideline 2.5.4); no privacy manifest,
  App Privacy or privacy page change.
- Verified (the plan's Results; 2026-11-12, after main at 936d627 was merged in): `picture-in-picture` 344
  checks (20,000 random sets of windows, 20,000 random lives) and 43 of 43 mutants (the old rounding, M23b,
  caught 3,283 times); the iOS app in Debug and Release for the simulator and Debug for a device, only the
  known `StreamClient` capture warning (StreamClient.swift:4464), `UIBackgroundModes` `["audio"]` in each;
  14 harness photos of the switch on one iPhone Duo simulator (iOS 27.1 runs no iPad): the iPad's two sizes
  (`-SillIdiom pad`), the Duo's four, an iPhone's, default and accessibility-extra-large text, in
  `~/Downloads/sill-handoff/pip/photos/`. Picture in Picture itself never ran: AVKit reports none on that
  simulator (`isPictureInPictureSupported()` false), so nothing was offered; an iPad simulator (iOS 27.0) was
  not tried. Before the first build an independent review found nine things, all fixed (40dbfe6; the plan's
  "The review before the first build").
  After #351 (main at 57a6d86, merged in 4bfc931: the panel keeps this switch first in This iPad and #351's
  version line last; both pbxproj sets): the three iOS builds again (the known warning only), `picture-in-picture`
  344 and `version-label` 38, `run-all.sh` all 68, and 19 photos of the panel (`photos-after-351/`).
- Noah's first try (2026-11-12; the iPad mini with a Debug build of 52c0eaa, Sill for Mac main 1416): "PiP
  works really really well!", approved for merge the same night. The Mac's cursor in the PiP window: asked
  about, then dropped ("sounds too complicated and immersion breaking"; the plan's open question 10). The P
  list below was not reported item by item, and the iPhone is untried.
- **Untested, for Noah:** everything on a device, the plan's P1–P20 (iPad mini and iPhone 15 Pro, a Debug build,
  Xcode's console for the `pip:` lines, Sill.log on the Mac): the switch and where iOS 27 keeps its own Start PiP
  Automatically; a window and the Desktop floating as Sill leaves; Apple Music never stopped with Sill muted, and
  PiP still starting (the open question on `.mixWithOthers`); sound, pause and play; no input to the Mac from other
  apps, and a ⌘ held as Sill leaves coming up; the return by the window's button, from the Home Screen, and
  straight back before it floats; a locked Mac and another user; the Mac quitting Sill; the device's lock, and
  whether PiP keeps it awake; ten minutes paused; a move to the cable; two Sill windows and Stage Manager; the
  switch off and iOS's off; the Mac's window keeping its size (no viewport from a snapshot layout); the
  clipboard while PiP shows; battery over half an hour; VoiceOver; the iPhone upright and sideways.
