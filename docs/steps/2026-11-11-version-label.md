**The version on the iPhone and iPad (2026-11-11, branch `version-label` from main at dd6ea6a, PR #351
(a draft); Noah, 2026-11-11: "a version identifier (e.g. 0.6.1. (1304)) at the bottom of the app in the
connection screen and at the bottom of settings", for the next version; the plan, its open questions with
the defaults taken, the gates and the results are in `docs/version-label-plan.md`).** Device only: no wire
change, nothing on the Mac, nothing stored.
- `VersionLabel` (pure, `Tests/checks/version-label`): CFBundleShortVersionString and CFBundleVersion as the
  bundle says them, "Sill 0.6.2 (1400)" shown and copied, "Sill version 0.6.2, build 1400" spoken (the form
  Sill for Mac's Settings › General already ends with); cleaned only to one line of plain words (Unicode's
  White_Space to one space, Cc and Cf gone: Foundation's `whitespacesAndNewlines` counts a zero-width space
  as a space, so it is not used); a missing or empty value, a Boolean or another type none, a number its
  digits; "Sill 0.6.2" without a build, "Sill (1400)" without a version, no label without either. A
  Release, TestFlight or nightly build says its commit count (`release-ios.sh --build-number`), a build from
  Xcode the project's 4.
- `VersionLine` (ContentView.swift): muted, footnote-sized, one VoiceOver element, Copy on a long press (a
  context menu) and as a VoiceOver action. The connect screen: at the footer's trailing edge on a line it
  already has wherever it fits there (after "Needs the free Sill app on your Mac.", every screen from 390 pt
  wide at the default text size; else a line of its own under the links on one line; else, the links on two
  lines, beside Support · Privacy Policy or beside the download link; else a line under those: one
  ViewThatFits over five arrangements, which ColumnOverFooter's hidden copy measures the same; the gap is
  the version's own padding, so ViewThatFits counts it), read last in the footer
  (`accessibilitySortPriority(-1)` in a `.contain` container); on a line of its own it lies behind the
  links (`zIndex(-1)`), whose tap areas reach 14 pt into its line. The Settings panel: its last line, after
  Take the Tour's footnote, in the part that scrolls, at the footnotes' inset.
- DEBUG: `-SillAppVersion <v>` and `-SillAppBuild <b>` stand in for the bundle's values in the label (empty:
  none); `-SillAXDump` also on the connect screen, each line with the element's custom actions;
  `-SillAXAction '<label>|<action>'` performs one and says what the clipboard holds.
- Defaults taken (the plan's seven): the Mac's version not in the panel (what it would take: a view line
  from `hostVersion`; its build needs a new optional WindowList field); no Debug mark; Sill for Mac
  unchanged (it shows its version already); Copy on a long press; on a footer line where it fits (always a
  line of its own is one line in `footer`); "Sill" before the numbers; the support page's sentence behind
  the marker `Version label`; and the photos' own (8): a 375 pt iPhone keeps the name and takes a line of its
  own (the sentence's line is about 5 pt short), not "0.6.2 (1400)" there.
- The review (2026-11-11, an independent read of the diff): three fixes in a commit of their own (the own-line
  version behind the links' tap areas; the arrangement beside the download link; the connect screen's dump
  not over a live stream screen), and the plan's G4 reworded for the panel scrolled to its end.
- Verified: `version-label` 38 checks and 26 of 26 mutants (in CI's matrix; C6, Foundation's white space,
  was the first draft, which turned a zero-width space into a space); CI's Build and check on 567ea50
  (`run-all.sh`, all 67; the iOS app for the simulator, Debug, only the known StreamClient.swift:4320
  capture warning); here the iOS app Debug for the simulator (MARKETING_VERSION 0.6.2 and
  CURRENT_PROJECT_VERSION 1400: its Info.plist 0.6.2 and 1400), Release for the simulator with
  CURRENT_PROJECT_VERSION 1404 (567ea50's commit count, as `release-ios.sh --build-number` gives it: its
  Info.plist 0.6.1 and 1404) and Debug for a device (generic, unsigned), each BUILD SUCCEEDED with only that
  warning. Harness photos, main's build (dd6ea6a) against the branch's with the same arguments, 432 pairs
  (the connect screen's `methods`, `methods` as rows, `remote`, `addmac`, `homerows` as rows and `tiles`, the
  panel at its top and scrolled to its end for a Mac with settings and one without, at the Duo's four sizes
  with each hinge state, 1000x710, 710x1000, 375x667, 667x375, 393x852, 852x393, 440x956, 956x440, default
  text and accessibility-extra-large), compared pixel by pixel (a pixel counts over 2 of 255: new simulators
  redrew main's photos byte for byte but 8 pixels of a fade by 1): the connect screen at the default size, 138
  of 144 differ only in the version's line, the 6 at 375x667 gain a line (the column unmoved in 4, risen
  24 pt in 2 that sat at the footer's 24 pt gap); at accessibility-extra-large a line of its own but at
  375x667 (beside Support · Privacy Policy), the column risen 11 to 28.5 pt in 15 of 144, elsewhere unmoved;
  the panel at its top 41 of 48 identical, 7 within noise (6 pixels, 3 of 255 at most); at its end the
  middle one line on, the header never, Disconnect unmoved in 92 of 96 and 4.3 to 7 pt lower in the 4 where a
  Mac without settings had a middle that fitted and now scrolls (no Mac a current device connects to lacks
  settings). VoiceOver's order (`-SillAXDump`): the footer's links, then "Sill version 0.6.2, build 1400"
  with Copy, also where it is drawn beside the sentence; the panel's tour note, the version, Disconnect; Copy
  (`-SillAXAction`) left "Sill 0.6.2 (1400)" on the simulator's clipboard (`simctl pbpaste`). Extras: a long
  version (its own line), no build ("Sill 0.6.2"), 320x568 at xLarge (beside the download link), Xcode's
  "Sill 0.6.1 (4)". The panel in the phone's own arrangement too (`-SillIdiom phone`; the main pass drew the
  iPhone sizes with the iPad's compact halves), 36 pairs at six iPhone sizes: its top 12 of 12 identical, its
  end one line on with Disconnect unmoved in 24 of 24. Photos and the tables in sill-handoff's
  `version-label/` (photos/INDEX.md). The photos' baseline is dd6ea6a; main at 936d627 (#349, remote dialing
  only) merged in at a8cb447 after them: CI green there (`run-all.sh` all 67, the iOS app), and here the check
  38 of 38 and the iOS app Debug and Release for the simulator (Info.plist 0.6.1 (1414)) and Debug for a
  device, the known warning only.
- **Untested, for Noah:** with a build of this branch on the iPad mini and the iPhone 15 Pro (TestFlight or a
  nightly says "Sill 0.6.2 (N)", N its commit count; one from Xcode "Sill 0.6.1 (4)" until main moves to
  0.6.2): the connect screen's footer ends its first line with the version (both have the room: 360 and 341
  pt of footer, about 328 needed at the default text size) and nothing else moved; the Settings panel's last line
  is the version, under Take the Tour's note; touch and hold either: Copy, then paste it in Notes; VoiceOver:
  "Sill version 0.6.2, build N" after Privacy Policy, Copy among its actions, and in the panel after the
  tour's note, before Disconnect; the largest text size: a line of its own (the footer a line taller),
  nothing cut; Split View and Slide Over on the iPad (the narrowest: beside a link line); copying it in the
  panel during a session, then leaving Sill and coming back: the clipboard's chip may offer it for the Mac,
  as for any text copied on the device. On a Duo from October 23: the cover and the inner display in each
  pose.
