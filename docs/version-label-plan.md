# The version label on the iPhone and iPad

2026-11-11, branch `version-label` from main at dd6ea6a (0.6.1 released, plus #339), PR #351 (a draft).
Device only: no wire change, nothing on the Mac, nothing stored.

Noah, 2026-11-11: "One more thing I want to add in the next version is a version identifier (e.g. 0.6.1.
(1304)) at the bottom of the app in the connection screen and at the bottom of settings." Then: "Start
working on ... the version number addition".

## What it is

The app's own version and build, as its bundle says them (CFBundleShortVersionString and
CFBundleVersion), written "Sill 0.6.2 (1400)", the form Sill for Mac's Settings › General already ends
with ("Sill 0.6.1 (1388). Free and open source.", `SettingsPanes.swift`). A Release, TestFlight or
nightly build's number is its commit count (`Scripts/release-ios.sh --build-number`); a build from Xcode
says the project's own (`CURRENT_PROJECT_VERSION` 4). Whatever the bundle says is shown; nothing is
invented, nothing hidden.

- `VersionLabel` (iOSClient/VersionLabel.swift, pure, Foundation only; `Tests/checks/version-label`):
  the two values cleaned (trimmed, inner white space one space, control and format characters gone; an
  empty one, or one that is neither a string nor a number, counts as none); the words shown, "Sill 0.6.2
  (1400)" ("Sill 0.6.2" without a build, "Sill (1400)" without a version, no label without either); the
  words spoken, "Sill version 0.6.2, build 1400" ("Sill version 0.6.2", "Sill, build 1400").
- `VersionLine` (ContentView.swift): the words in the footnote size and the muted colour, one element for
  VoiceOver with the spoken words, a long press (a context menu) offering Copy, which copies the words
  shown, and the same as a VoiceOver action.
- The connect screen: in its footer ("Needs the free Sill app on your Mac." over the links), at the
  footer's trailing edge, on a line the footer already has wherever it fits there:
  1. at the end of "Needs the free Sill app on your Mac." (every screen from 390 pt wide at the default
     text size: an iPad, the Duo's displays, an iPhone but the 375 pt ones);
  2. else on a line of its own under the links, when they fit on one line (a 375 pt iPhone at the default
     size, larger text where the links fit);
  3. else beside "Support · Privacy Policy", when the links take two lines (a 320 pt screen; a 375 pt
     iPhone at the largest sizes), or beside "Get it at getsill.app", the shorter (the review's: a 320
     pt screen at xLarge);
  4. else on a line of its own under the two lines of links.
  One `ViewThatFits` over the five arrangements, in that order, inside the footer that ColumnOverFooter
  measures (its hidden copy is the same view), so the column, the title and the rows never move for it
  where it shares a line, and where the footer gains a line the column follows the rule it always had
  (it rises only to keep 24 pt clear of the footer, never closer than 16 pt to the top, and scrolls
  above it when even that does not fit). The footer stays where it was: above the home indicator (the
  safe area), under the laptop pose's fold, in the book pose's leading page (it is the column's width).
  VoiceOver reads it last in the footer, after the links, wherever it is drawn. On a line of its own it
  lies behind the links, whose tap areas reach 14 pt below their words into its line as they did below
  the footer's last line; beside the sentence, the links' upward reach covers its lower edge as it
  covers the sentence's.
- The Settings panel: the last thing in its middle, the part that scrolls, after Take the Tour's
  footnote: a line of its own at the footnotes' inset, their size and colour, with the gap between
  groups above it and below it. The header and Disconnect are pinned and do not change; where the
  middle fits without scrolling (a Mac without settings, on a tall screen), the panel is one line
  taller, as its height follows its content.

## Open questions, and the default taken for each

1. The Mac's version in the device's Settings panel, when the Mac says it? No (taken): Noah asked for
   the app's own identifier. What it would take: the window lists carry `hostVersion` (Sill.app's
   CFBundleShortVersionString; nil from SillHost and from Macs before 2026-09-25), which StreamClient
   keeps (`hostVersion`) and shows nowhere; a line "‹Mac›: Sill for Mac 0.6.2" under this one is a
   view change only. The Mac's build is not on the wire: "(1388)" would need a new optional field in
   `WindowList` (additive, the Compatibility floor's rules) set by Sill.app's AppModel.
2. A Debug build marks itself ("Debug", a dot)? No (taken): it says what its bundle says, 0.6.1 (4)
   from Xcode, which no build for testers has.
3. Sill for Mac: nothing to do. Settings › General already ends with "Sill 0.6.1 (1388). Free and open
   source." under Quit Sill (SettingsPanes.swift), in the same form.
4. Copy on a long press: yes (taken). People read the version out for a bug report; Copy puts "Sill
   0.6.2 (1400)" on the clipboard for one. A context menu, the system's: a long press, so a tap and a
   scroll are untouched, and it never reaches the stream screen's catcher (it is inside the panel).
   Like any text copied on the device, the clipboard's chip may offer it on the Mac the next time Sill
   becomes active during a session (docs/clipboard-plan.md); not special-cased.
5. Where on the connect screen: on a line the footer has wherever it fits (taken, above), at the
   trailing edge. The other way, always a line of its own at the bottom, is the same on every device
   but makes the footer a line taller everywhere (a column that rises or scrolls in the tightest cases,
   a phone held sideways with many Macs). Next to "Needs the free Sill app on your Mac." it could read
   as the version the Mac needs; the two apps share their version numbers since 0.5.1, so that reading
   is nearly true, and VoiceOver hears it after the links. One line in `ConnectScreen.footer` moves it.
6. "Sill 0.6.2 (1400)" (taken, Sill for Mac's form) or Noah's "0.6.1 (1304)" bare? With the name: in a
   screenshot or a pasted line it says whose version it is.
7. The support page: one sentence, behind the marker `Version label` for the release that ships it
   (docs/release-checklist.md part 1 §3): where each app shows its version, to put in an email.

## Gates

- G1 `Tests/checks/version-label`: the words and the cleaning at their edges (a missing key, a build
  that is not a number, white space, control characters, numbers, other types); and its mutants, every
  one caught (in CI's mutants matrix).
- G2 `Tests/checks/run-all.sh`, every check.
- G3 the iOS app: Debug and Release for the simulator, Debug for a device (build only), only the known
  warnings; the Release app's Info.plist read back (the bundle's values the label shows).
- G4 harness photos against origin/main's build (dd6ea6a), compared pixel by pixel, on a private iPad
  Pro 13-inch simulator on iOS 27.1: the connect screen in its tightest cases (`methods`, `remote`,
  `addmac`, many Macs as rows) and the Settings panel's end (`-SillSettings 1 -SillSettingsEnd 1`), at
  the Duo's four sizes with every hinge state the harness knows (none, `closed`, `half`, `flat`), an
  iPad's 1000x710 and 710x1000, iPhones from the smallest (375x667) to the largest (440x956), upright
  and sideways, at the default text size and at accessibility-extra-large. Outside the footer and the
  panel's last lines nothing may differ; where the footer gains a line, what moved and why. The panel
  also as it opens, at the top of its rows (`-SillSettings 1`): there nothing may differ unless the whole
  middle fits without scrolling. Scrolled to its end, the end shows one line more, so every row above it
  sits higher by that line: there only the middle may differ, never the header or Disconnect.
- G5 VoiceOver's order (`-SillAXDump`): one element, "Sill version 0.6.2, build 1400", last in the
  footer and last in the panel's middle.

## Results

- G1: `Tests/checks/version-label` 38 of 38; its mutants 26 of 26 caught. Found while writing it:
  Foundation's `whitespacesAndNewlines` counts a zero-width space (U+200B) as white space, so a first
  draft turned "14\u{200B}00" into "14 00", a space where none shows; the cleaning follows Unicode's
  White_Space instead and drops Cc and Cf (mutant C6 is that draft).
- The review (2026-11-11, an independent read of the diff, read-only): three fixes taken, in a commit of
  their own: on a line of its own the version lay over the links' tap areas (now behind them); with the
  links on two lines it can also sit beside the download link, the shorter line (a 320 pt screen at
  xLarge had a line it did not need); the connect screen's accessibility dump fired again over a live
  stream screen. And G4 as first written could not hold for the panel scrolled to its end (every row
  above the new line sits higher by it): reworded, with the panel at the top of its rows added.
- CI on the pull request (run 43154140966, head 567ea50, the review's fixes in it): Build and check
  passed: `run-all.sh`, all 67 (`version-label` 38 passed); the iOS app for the simulator, Debug, only the
  known StreamClient.swift:4320 capture warning.
- G3 here: the iOS app Debug for the simulator (before the review's fixes, MARKETING_VERSION 0.6.2 and
  CURRENT_PROJECT_VERSION 1400, so the bundle said what a TestFlight build of the next version would: its
  Info.plist read 0.6.2 and 1400), only the known warning; after the review's fixes, at 567ea50, Release for the simulator
  with CURRENT_PROJECT_VERSION 1404 (the commit count, as `release-ios.sh --build-number` gives it: its
  Info.plist read 0.6.1 and 1404) and Debug for a device (generic, unsigned): both BUILD SUCCEEDED with only
  the known warning, their products cleaned after (the coordinator's terms of 2026-11-12).
- G4: harness photos of main's build (dd6ea6a's Debug) and the branch's (its bundle 0.6.2 (1400)) with the
  same arguments, 432 pairs (24 sizes and hinge states × 9 cases × 2 text sizes), the Duo's on an iPhone Duo
  simulator (iOS 27.1: its cover display, the inner display's sizes scaled to 0.70, those sideways turned a
  quarter), the others 1:1 on an iPad Pro 13-inch simulator (iOS 27.0); one simulator at a time, each deleted
  after (the coordinator's terms of 2026-11-11 23:14, after two at once had loaded the Mac). Compared pixel
  by pixel, a pixel counting when a channel changed by more than 2 of 255 (new simulators redrew four of
  main's photos byte for byte but for 8 pixels of a tile's fade changed by 1):
  - the connect screen at the default text size, 144 pairs: 138 differ only in the version's own line (the
    title, the rows and the links unmoved), on every Duo size and hinge state, at 1000x710, 710x1000,
    393x852, 852x393, 440x956, 956x440 and 667x375; at 375x667 (6) the version takes a line of its own (the
    sentence's line has 323 pt, it needs about 328), the footer 24 pt taller: the column unmoved in 4
    (centred with room, or scrolling) and risen 24 pt in 2 (`methods`' six tiles, `homerows` as rows), which
    sat at the footer's 24 pt gap, as the column's rule has it;
  - at accessibility-extra-large (the footer caps at xxLarge), 144 pairs: at 375x667 (6) the version beside
    Support · Privacy Policy, no line added (the links take two lines there on main too); elsewhere a line
    of its own, the footer about 28 pt taller: the column risen 11 to 28.5 pt in 15, elsewhere unmoved
    (centred with room, or scrolling, its fade higher);
  - the panel at the top of its rows, 48 pairs: 41 identical, 7 within noise (at most 6 pixels, changed by
    at most 3 of 255);
  - the panel scrolled to its end, a Mac with settings and one without, 96 pairs: the middle one line on in
    every one, the header never different, Disconnect unmoved in 92; in 4 (a Mac without settings at
    1000x710, and in the Duo's inner display on its side with the hinge closed, flat and half) the middle
    fitted without scrolling on main and now scrolls, so the panel takes its whole room: Disconnect 7 and
    4.3 pt lower. No Mac a current device connects to lacks settings (every Sill for Mac since 0.4.0 sends
    them); the same panel shows only for the 2 s before a slow Mac's first state;
  - extras: "Sill 0.10.12 (10000)" at 375x667, 393x852 and 1000x710 (its own line where the sentence's has no
    room), a bundle without a build ("Sill 0.6.2"), 320x568 at the default size (beside Support · Privacy
    Policy) and at xLarge and xxLarge (beside the download link, then its own line), and what a build from
    Xcode says, "Sill 0.6.1 (4)", on the sentence's line even at 375x667.
  Photos, the table and INDEX.md: sill-handoff's `version-label/`.
- G4, the phone's own arrangement (`-SillIdiom phone`; the main pass drew the iPhone sizes with the iPad's
  compact halves, whose panel is the same view placed otherwise): the panel at its top and at its end, a Mac
  with settings and one without, at 375x667, 393x852, 440x956, 667x375, 852x393 and 956x440, default text and
  accessibility-extra-large, 36 pairs: at its top 12 of 12 identical; at its end 24 of 24 one line on, the
  last bright row (Disconnect's words) unmoved in every one.
- G5: `-SillAXDump` on the connect screen (1000x710 and the cover's 466x678, the Macs as rows): the footer
  reads "Needs the free Sill app on your Mac.", "Get it at getsill.app", "Support", "Privacy Policy", then
  "Sill version 0.6.2, build 1400" with the action Copy, though it is drawn on the sentence's line; at
  accessibility-extra-large at 393x852, the same order; the panel's end (1000x710): the tour's note, the
  version, Disconnect. `-SillAXAction 'Sill version|Copy'` on both screens: performed, the app's clipboard
  "Sill 0.6.2 (1400)", and the simulator's read back from outside (`xcrun simctl pbpaste`) the same.
- Not done here: the long press itself (no finger reaches a simulator here: the menu is UIKit's context menu,
  its Copy the same function as the VoiceOver action's), VoiceOver itself, anything on a device.

## An open question the photos raised

8. A 375 pt iPhone (the SE, the 12 and 13 mini) at the default text size: the sentence's line has 323 pt and
   "Sill 0.6.2 (1400)" with its gap needs about 328, so the version takes a line of its own, and a column
   with many Macs that sat at the footer's gap rises 24 pt. Taken: as it is (the rule of the footer). The
   other ways: on that line alone write it without the name, "0.6.2 (1400)" (Noah's own example has none;
   VoiceOver and Copy keep the name), which fits with room; or a 6 pt gap there, which fits by a point or
   two and reads as one sentence.

## After main moved

Main went to 936d627 (#349, a saved Mac keeps its VPN addresses: remote dialing only) and was merged in at
a8cb447 (a merge commit; CLAUDE.md's two new entries both kept, this one first). The photos' baseline stays
dd6ea6a: #349 changes nothing they draw. At a8cb447: CI's Build and check green (run 43168563298: `run-all.sh`
all 67, `version-label` 38, `remote-rules` 249; the iOS app for the simulator); here the check 38 of 38 and the
iOS app Debug and Release for the simulator (Info.plist 0.6.1 (1414), the commit count) and Debug for a
device, only the known warning, their products cleaned.
