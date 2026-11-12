**The iPhone Duo with the iOS 27.1 SDK (2026-10-08, branch `duo-layout` from main at e6b3265,
main at 05f2bb8 (PR #39) merged in at 7bd7c41, not rebased; docs/iphone-duo-plan.md has the probe's
facts, the decisions, the review, the results and what Noah tests).** Noah: research the iOS 27.1
SDK for iPhone Duo, then "adapt the app to use this SDK, then use the simulator with iPhone Duo, make
sure it works properly, then take screenshots of all poses", with PR #39's merge kept cheap.
Approved from mockups: (a) the book pose, one stream across the fold and nothing you touch on it;
(b1) the laptop pose split at the fold's real frame; (b2) open flat upright, the picture at the
window's own shape and the trackpad the rest; (c1) the cover upright, the phone's arrangement beside
the camera's strip; (c2) on its side, the compact landscape bar. Device only, no wire change (a TEST
ONLY host picture aside).
- `DuoPosture` (pure) and `DuoPostureReader`: `onHingeChange` at the app's root (SillApp) into the
  environment; the fold's `.division` region (`.includeInactive`) from each screen's own
  GeometryReader, in its space, and before the hinge's first report the region alone (active: partly
  open; inactive: flat); nothing before iOS 27.1, and a device without a hinge or fold reads
  `unknown`, so every layout there is what it was (the inferred crease included). The fold is in the
  way while the hinge is partly open.
- Decisions (the plan's "The build: decisions", revised after the review; the status bar Noah's
  pick of 2026-10-09, option 1 of the three the mock canvas drew): the stream screen hides the
  status bar on the inner display in every pose (upright the picture keeps the 82 pt above the
  fold; sideways Sill has all 951 pt), and every other screen keeps it in every pose, the cover its
  strip; at 951 pt the book pose's bar keeps its regular size, its group beginning at 551, past the
  fold's 455.5–495.5, the strip ending 12 pt short of it (at 867 pt, the status bar shown, it would
  take the approved step to the compact width, Menus at 497); the laptop pose splits at 455 and
  496; open flat the pane takes the picture's
  own shape, 16:10 while the Mac fits a window to it (Aa, the virtual display); in the book pose the
  connect column, the pairing overlay, the window lights and PR #39's link line keep to a page, and
  a tour card to its targets' page (355.5 pt beside Settings); upright the connect column scrolls
  in the room above the fold, Add a Mac side by side there; the tour on the inner display says
  "Turn your iPhone on its side" for the keys and trackpad. The cover needed nothing.
- Hooks, a few lines each: StreamScreen (also `duoStatusBar` and LinkLineView), PortraitStreamScreen,
  AddMacCard (`ConnectLayout`), ContentView (the connect screen's room; the harness), PairingOverlay,
  TourPolicy and TourOverlay, SillApp; pbxproj AB01/FB01, AB02/FB02. The harness: `-SillLayout
  951x669`, `669x951`, `466x678`, `678x466` with the displays' safe areas as this build has them,
  `-SillHinge closed|half|flat`. CI: the Mac side on Xcode 27 (not a beta), the iOS app alone on
  27.1 (select-xcode's `allow-beta`: the image has only `Xcode_27.1_beta.app`, 27A9269); release-ios.sh
  refuses an Xcode before 27.1 and an app not built with the iOS 27.1 SDK, so TestFlight from
  GitHub Actions waits for a 27.1 release there. `SILL_TEST_PATTERN=picture:<path>` (TEST ONLY): a
  synthetic host's Desktop a still picture.
- The review (2026-10-08, two lenses): eleven findings, two of them the same (the status bar).
  Eight fixed, one commit per theme (5c2188a the status bar and the fold before the report, 7db22a3
  the connect column, 8906024 the tour, 9e4f36c CI; the checklist and README with the docs), and
  the plan's own leftover too (e75ea48 #39's link line); one tested here and given to Noah (the 27.1
  SDK off the Duo: P9; folds while away: P10, fine on the simulator); one older than the branch and
  left (an unlabeled VoiceOver element on the phone row's Menus button). c70a04c is the test picture.
- Checks: `duo` 252,557 and 67 of 67 mutants; `tour` 51,840 and 72 of 72; `run-all.sh`, all 40;
  each fix commit builds and passes both. Builds: iOS Debug for the Duo simulator, Release for the
  simulator, Debug for a device, `swift build -c release`, only the known warnings.
- Verified on a private simulator ("Sill duo", iOS 27.1, deleted after) folded by Tests/duorig
  against `SillHost --synthetic` on loopback (software encoder, a Weather picture as the Desktop):
  the stream, connect and Settings screens in all six poses, the tour's cards, folds and turns
  while Sill was in the background (six, each layout right on return, one connection) and slow
  folds mid-stream (180→90→180→120→0→90); the harness's mock in every pose with the drawer, lights,
  pairing, Add a Mac, eight Macs, the link line and the Menus pull-down. Photos at App Store
  Connect's Duo sizes in `~/Downloads/sill-handoff/duo/final/` (INDEX.md; `live/` private: this
  Mac's windows and name). The harness at 46 earlier cases against main's build (05f2bb8): 39
  identical, 7 differing only as main's build differs from itself. The branch contains main: the
  pull request merges without a conflict. CI run by hand on the branch (37835771799): green, the
  Mac side on Xcode 27.0, the iOS app on `Xcode_27.1_beta.app` (27A9269).
- **Untested, for Noah (on an iPhone Duo from Oct 23, a build from Xcode 27.1; TestFlight 0.5 (3),
  from Xcode 27.0, runs there in an 871×669 compatibility window, sideways only):** the plan's
  P1–P13: every pose, folding mid-stream by hand, the keyboard on the cover, 120 Hz on each display,
  Split View if iOS offers it, VoiceOver in the book pose, the iPad mini and iPhone 15 Pro on a 27.1
  build (P9), folds while away (P10), and the status bar decision. Left: (d) TestFlight 0.5.1 waits
  for the Duo's release.
