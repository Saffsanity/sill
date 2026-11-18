**The Close timeout and the interrupted picture (2026-10-19 and 20, PR #93 from addhumal, finished on
its branch `audit-fixes`, which has main at 4d990e9 in it; issue #101).** The triage of 2026-10-16 and
2026-10-19 (sill-handoff/triage): the close half ready; the re-pick, the broken harness and the
throttle to change. Host, device and one additive kind (44).
- Close (the contributor's, kept): the button `kAXCloseButtonAttribute` gives is a new element on the
  system's default timeout, pressed on the host's main actor, so an app whose close asks about unsaved
  changes in an alert of its own, or a hung one, held input, picks and settings for every device that
  long. It is type-checked (CFGetTypeID, then the cast, as MenuReader does) and given 1 s.
  `WindowSizer.perform` says what came of a light (`CommandOutcome`, its words per action): "Window
  104 close: no answer in time (the app is busy, or asking about unsaved changes); it may still act"
  where it said "refused"; a minimize or full screen with no answer says only that the app is busy
  and that the window may still minimize, or go in or out of full screen. The contributor's harness
  (`Scripts/menu-check/run.sh close`, the fixture's Slow Close window) builds again (since #75
  WindowSizer needs WindowRestore.swift), and checks the words of every action too.
- The interrupted picture, replaced: the PR picked the source again (kind 6) every 2 s, which
  restarted every device's stream and raised the window in regular mode, for ever if a layer kept
  failing. Now the device asks for a keyframe: kind 44 `keyframeRequest`, device → host, empty. The
  host answers with `HEVCEncoder.requestKeyframe` (a still window's last frame encoded again; every
  device gets it, as when one joins), at most one a second per connection ("Keyframe for ‹device›:
  its picture was interrupted."; the rest one line a minute), nothing while nothing streams, never a
  restart or a raise. A host from before skips it without a line, and the picture waits for the
  stream's next keyframe, as it did: the encoder makes one every fps × 4 encoded frames (no time
  limit: none while the window stays still), when a device joins and when the stream restarts, never
  because the window changed (its delta is dropped while the device waits). There was no
  device-to-host keyframe request before: the host asked its encoder only for a joining device and a
  dropped delta.
- Device: HEVCDisplayView's `checkLayer` (network queue) flushes a layer that failed (`status`,
  `error`), could not decode a frame (`failedToDecodeNotification`; one posted before the picture last
  came back is ignored) or needs a flush to decode again (`requiresFlushToResumeDecoding`, and its
  notification): at each frame, at each notification and when the picture's window becomes active.
  It says so (`onNeedsKeyframe`), and a keyframe that ends the wait says the picture is back
  (`onPictureBack`); a keyframe the flush throws away (the layer still read failed when it came) says
  both, back first. The rule, `KeyframeRecovery` (pure, main thread): one ask per interruption while
  its keyframe is due; an ask whose keyframe has not come within `answerWait` (max(4 s, 4 × the worst
  round trip of the last second that measured one), the settings timeout's and the clipboard
  receipt's measure) is owed again as a repeat, so a Mac that never answers is asked after 4, 8 and
  16 s, then every 32 s, which costs a Mac from before kind 44 nothing; only while the picture's
  window scene is foreground active (each Sill window has its own client) and something streams;
  2 s apart at least; a picture that fails again within 10 s of its keyframe, Sill active throughout,
  or an unanswered ask doubles the spacing (4, 8, 16, then 32 s); a trip away owes an ask that was
  out again and starts the spacing at 2 s again; a keyframe that comes while Sill is away never makes
  the next interruption a repeat; 10 s back ends a streak. The Mac sends its parameter sets before
  every keyframe and each sample carries the format, so nothing else is sent again. DEBUG lines
  "display: …" and "keyframe: …" ("no keyframe 4.0 s after the last ask; asked again");
  `-SillLayerFail <s>[,<s>…]` (a frame that cannot decode, enqueued) and `-SillKeyframeLost <n>` (the
  first n keyframes that end a wait thrown away by the flush); TEST ONLY `SILL_TEST_STILL_AFTER=<s>` (a
  synthetic Desktop still from then on), `SILL_TEST_KEYFRAME_IGNORE=<n>` (a synthetic host ignores
  the first n keyframe requests, as a Mac from before kind 44 ignores every one) and `sillclient.py
  --keyframe@T`. site/privacy.html's list of what a device sends its Mac gains the request ("When the
  picture on your device was interrupted, … a request to send the picture again."), between
  `<!-- Keyframe` and `<!-- /Keyframe -->` for the release that ships it (docs/release-checklist.md
  part 1 §3 has the perl line that cuts it for a republish before that release), and its date is
  October 20. No words for the release yet (the next What's New, README, support.html): as #80's
  did, they wait for Noah's device run of the trip to the background, the issue's own case, which no
  simulator shows.
- With #107 (on hold): its renderer already calls the same `onNeedsKeyframe`. It should drop its own
  throttle (`PictureSmoothing.DecoderRecovery`) and its re-pick, and call `onPictureBack` where its
  renderer takes a keyframe, so one rule serves both (Noah on #93, 2026-10-15: "One recovery mechanism
  should serve all of them"). #66 compiles StreamClient.swift for its Mac client: the new UIScene and
  UIApplication observers need its platform layer there.
- Kind 44 is this pull request's (posted on #81, 2026-10-19: 43 is #94's sound, 44 this keyframe
  request, 45 the Pencil's), but three open pull requests' checks still read 44 as free, and whichever
  lands second renumbers (a check's assertion or a mutant, never kind 44): #94's `compatibility` check
  asserts `StreamMessageKind(rawValue: 44) == nil` (its main.swift:258); #66's, #72's and #73's
  `pointer-control` mutant "kind 26 numbered 44" renumbers onto 44 (with 44 taken that mutant no
  longer compiles, which their mutants.py counts as not caught, so the mutants job fails: a free
  number instead, not 45); and #94, #66 and
  #158 each rewrite `pointer-control`'s "every other kind …" line around 44 (a textual conflict:
  keep 44 among the known kinds). #128 (Sill Viewer for Mac, left untouched by Noah's decision of
  2026-10-19) compiles iOSClient/StreamClient.swift with MacClient/HEVCDisplayView.swift, which has
  no `renderQueue`, `onNeedsKeyframe`, `onPictureBack` or `checkLayer`, its PlatformShims.swift no
  `UIScene.willDeactivateNotification`, `windowScene` or `activationState`, and its target no
  KeyframeRecovery.swift: whichever of the two lands second gives the Mac viewer those or keeps the
  recovery out of its build.
- Verified (2026-10-19): `keyframe-recovery` 51 checks and 20,000 random sessions against a model of
  the event history, 28 of 28 mutants (on the way it found a real fault: an ask held back until
  `last + spacing` was held again at that very time by rounding); `pointer-control` takes kind 44
  into its kind table (158 checks, its mutants again); `swift build -c release`; the iOS app for the
  simulator (CI's command), only the known StreamClient warning; `run-all.sh`, all 45; the menu checks
  against the fixture: reader 40, budget 4, mirror 69 (it failed 7 once while the screen was locked:
  nothing presses a menu under the login window), close 4 (back in 1.01 s, as no answer, the close
  delivered, the front app unchanged). Live on a private iPad simulator (iOS 27.0) against a loopback
  synthetic host on the software encoder, its Desktop still from 3 s: `-SillLayerFail 6` gave the
  layer's own -11821, one ask, one host line, the picture back 75 to 125 ms after, and one "Synthetic
  capture" line (no re-pick); `-SillLayerFail 6,6.6,12` asked at once, then 4.0 to 4.2 and 8.1 to
  8.3 s after the ask before (spacing 2, 4, 8), three host lines, twice; a trip to the background
  (Settings for 2 s): the simulator's layer never stops, nothing asked, the picture as it was;
  `sillclient.py --keyframe@3 --keyframe@3.2 --keyframe@3.4 --keyframe@5.5`: keyframes 50 to 60 ms
  after the two taken, one "ignored" line, and nothing for a request while nothing streams.
- The verifier's findings (2026-10-20, on 09549b3; each taken, one commit per theme): a keyframe
  the layer's own flush threw away left its interruption open with its ask out for good while Sill
  stayed active (now the picture back and lost again, and every ask has its wait); a trip to the
  background kept a streak's spacing (24 s more of a frozen picture after the return in its probe),
  and keyframes shown while away built one (now the trip starts the spacing at 2 s, and a keyframe
  shown while away keeps the trip); DEVELOPMENT.md said a Mac from before kind 44 brings the picture
  back when the window next changes (it waits for the stream's next keyframe; shown live against
  0.5.1); the minimize and full screen words; Noah's TextEdit step and 0.5.1 step; these merge notes.
- Verified after the fixes (2026-10-20, on the merge with main at 4d990e9, a machine shared with
  other agents and its load average in the hundreds, so every time here is slow):
  `keyframe-recovery` 95 checks and 20,000 random sessions against the model (never stuck while
  open, active and streaming; a re-ask only once its last ask's keyframe was overdue; no two asks
  less than 2 s apart, so the host's one a second never refuses a device's own ask), 39 of 39
  mutants, three of them each finding put back (an ask out never asked again; a trip away keeping
  the spacing; a keyframe shown while away ending the trip); `pointer-control` 158 checks and 33 of
  33 mutants; `run-all.sh`, all 47 (main's new `virtual-display-api` among them); `swift build -c
  release` on the merged tree, complete with no new warning; the iOS app for the simulator from
  clean derived data (CI's command, Xcode 27.1 27A9275), only the known StreamClient warning
  (StreamClient.swift:3819); `Scripts/menu-check/run.sh close`, 9 checks: back in 1.01 s as no
  answer, the close delivered, every action's words, the front app unchanged. The host alone
  (`sillclient.py`, loopback, software encoder): with `SILL_TEST_KEYFRAME_IGNORE=1`, requests at 4
  and 6 s: the first ignored with its line, the second answered (its keyframe 0.09 s later); the
  hook refuses `abc`, `0` and `-2` with its line. Live on a private iPad simulator (iOS 27.0)
  against loopback synthetic hosts on the software encoder, their Desktop still from 3 s, one
  "Synthetic capture" line a run (no re-pick): `-SillLayerFail 6`: the layer's own -11821, one ask,
  one host line, the picture back 1.2 s after; with `SILL_TEST_KEYFRAME_IGNORE=1` on the host: the
  first ask ignored with its line, then "keyframe: no keyframe 4.0 s after the last ask; asked the
  Mac for a keyframe (spacing 4 s)" 4.2 s after it, the host's "Keyframe for …", the picture back
  0.15 s later; `-SillKeyframeLost 1`: the keyframe that ended the wait thrown away ("flushed with
  the keyframe it waited for"), the next ask 4.06 s after the first (a repeat's spacing), two host
  lines, the picture back 0.08 s after it; `-SillLayerFail 6,9,13,21.5,37.5`: asks 4.05, 8.1 and
  16.0 s apart (spacing 2, 4, 8, 16), the fifth interruption held 28.5 s by a 32 s spacing, then
  Settings in front for 2 s and Sill back: asked at once ("spacing 2 s"), 21 s before the hold would
  have let it, five host lines and one "Synthetic capture" line in all. This build against Sill for
  Mac 0.5.1's host (`git archive v0.5.1`, its Desktop moving) with `-SillLayerFail 6`: asks at +0,
  +4.1 and +12.3 s, no line on the host and no disconnect, its pongs and frames throughout, and the
  picture back 15.2 s after the interruption with the stream's periodic keyframe.
- **Untested, for Noah:** on the iPad (and the iPhone) with this build and a Sill.app from this
  branch: a still window (TextEdit, nothing changing), Sill sent to the background for 2 s and back:
  the console's "display: the picture was interrupted …", one "Keyframe for …" in Sill.log, the
  picture at once, no "Capture started" and the window not raised; ten quick trips (a line each, and
  each ask at once, never one held for 4 s or more after a trip); a video playing in Split View beside
  Sill; two Sill windows, one swapped out and back; Close on a TextEdit window with unsaved changes:
  its sheet on the Mac, input and picks unaffected meanwhile, and in Sill.log most likely "Window N
  close: done" (a document's sheet returns at once; an app that asks in an alert of its own, or a
  hung one, gives "no answer in time …" after 1 s: either is fine); this iPad against Sill for Mac
  0.5.1: the device sends kind 44, which 0.5.1 skips with no line and no disconnect, the console's
  asks again after 4, 8 and 16 s, then every 32 s, and the picture back only with the stream's next
  keyframe (a still window's never, as before).
