**First-run tour (2026-09-27, branch `first-run-walkthrough` from main at
cf05a78, merged with main at 5c6a850 and 2b38179, not rebased, PR #35; the
plan, its critique and the results are in
`docs/first-run-walkthrough-plan.md`).** Noah (2026-09-26): "Add to feature
list, app usage walkthrough first time after pairing/connecting". The device
only: no wire change, nothing sent to the Mac, three UserDefaults keys (the
third, `Sill.tourVersion`, since tour version 2: the entry "The tour once
more, with what's new").
- What it does: a second after the first picture from a Mac (the window list,
  a frame size, a source), if nothing was touched anywhere on the screen, sent
  to the Mac, used or opened since (a recognizer on the window that takes
  nothing counts every touch; `StreamClient.lastInputAt` every input;
  `lastActionAt` a control used by any means, VoiceOver's double tap, Switch
  Control, Voice Control or Full Keyboard Access included), the stream
  screen dims (black 0.58 over the whole screen, safe areas included) and a
  card points at one part at a time, cut out of the dim and ringed in the
  accent: `touch` (the picture: tap, hold, drag; Apple Pencil on iPad), `bar`
  (hold a thumbnail, slide on Aa for a window's text; sideways and on a phone
  upright Keyboard), `settings` (Disconnect
  and Take the Tour live there; sideways "Hold your iPad upright"), upright
  `laptop` (the sticky modifiers, the keyboard key, the trackpad's two-finger
  tap and hold-then-drag). Three cards sideways, four upright; since tour
  version 2 (0.6) four and five, with `sharing` (Clipboard and Sound) before
  Settings, rows marked "New:", the Menus button lit, and Aa named only in
  the Virtual Display row (the entry "The tour once more"). Whoever touched
  anything in that second is left alone for the session; one decision per
  session and layout, and a turn after it offers only what its layout has
  alone (the laptop card). The automatic reconnect's session goes on with the
  last one's decision (`StreamClient.tourSession`), unless that one ended
  before it or mid-run. Next and Done save each step (`Sill.tourSeen`), so
  an ended session resumes at the first step not passed; Skip ends it for good
  (`Sill.tourSkipped`), but in Take the Tour only closes it; the Settings
  panel's last row, Take the Tour, shows every step of the layout again. While it shows the layouts take no touch and
  the keyboard is down (back after, but never under a pairing link), so no
  touch, Pencil, hover or key reaches the Mac, and the device's own pointer
  move for a new frame size waits (`inputPaused`); an outside pairing link
  puts it aside. Esc skips (Done on the last
  card), Return goes on. VoiceOver: no touch card and no trackpad rows, the
  rest in VoiceOver's words (swipe up or down for a thumbnail's actions and
  Aa), focus on each title with "step N of M" and where the lit part is, the
  escape gesture skips, Magic Tap goes on. Every text size: the card widens to
  560 pt at accessibility sizes and stays beside the controls it lights
  (sideways under the bar; upright from the picture's half toward the top,
  then down to 12 pt above its targets, never across the Duo's crease; on a
  phone upright standing on its targets, or under the rows when it does not
  fit above them), its words scrolling there under a fade with the footer in
  reach; only a room under 200 pt (a tiny window) makes it cover them, without
  a cutout or ring. Each step's words start at their top. Reduce Motion
  cross-fades. On a phone held upright (main's PR #30) `TourLayout.phone`:
  `bar` lights the thumbnails with Aa and row 1's Keyboard, the laptop card
  has no keyboard key row, the hints say where the rows are.
- Files (Layout): `TourPolicy.swift` (pure), `TourOverlay.swift`, targets in
  StreamScreen, TopBar and PortraitStreamScreen, the row in
  HostSettingsPanel, `lastInputAt`, `lastActionAt`, `inputPaused`,
  `tourSession` and a DEBUG tripwire in StreamClient, the harness's arguments
  and `-SillOrientation` in ContentView; `Tests/checks/tour` (compiles
  PhonePortraitLayout.swift too; in CI's mutants matrix). pbxproj A401/F401,
  A402/F402.
- Beyond the plan (its Results say why): the count goes on across a rotation
  (the plan restarted it); a laptop card passed under VoiceOver counts as seen;
  "not active" is UIKit's applicationState (SwiftUI's scenePhase read inactive
  for an active app in a headless simulator, so every decision passed); the
  strip's lit band takes in the active halo and the badge; the card's tail and
  frame come from its laid-out height (a GeometryReader in it saw the appear
  animation's scale); `-SillTakeTourAt`. Found and fixed: Done wrapping to two
  lines on the iPhone SE at accessibility-extra-large (the footer's line was
  measured with its words free to wrap); a run carried into the other layout
  left that layout's decision open; a card on a 3x screen fading its last
  row (below).
- Verified (the plan's Results): Debug and Release for the simulator and Debug
  for a device, only the known StreamClient warning, and each commit's state
  builds; `Tests/checks/tour` 34,059 checks and 35 of 35 mutants, `run-all.sh`
  whole (16 checks); the hard-rule greps (no presentation or TipKit, nothing
  sent from the tour's files, nothing outside the app changed); 32 harness
  photos against the base, pixel for pixel equal but the held thumbnail's
  wiggle (which differs base against base); the Settings panel's photos differ
  only by the new row at the end; every step photographed at 1000x710,
  710x500, 710x1000, 500x710, the iPad Pro 13-inch's two sizes and the iPhone
  SE's 667x375 and 375x667, at default and accessibility-extra-large text,
  the largest size at the tightest four, and the VoiceOver run, each card's
  frame and tail (the console's `tour: screen …` lines) as the check's model
  of the layouts; the rule in the mock (fresh, landscape, done, skipped, the
  Apps list, a stand-in touch, the pairing overlay, Next through Done); with
  the real keys in the mock, shown, then "nothing owed", then back from
  Settings. Live (03:28–03:40, once Noah's iPad had left Sill.app, which it
  streamed from until then; `SillHost --synthetic` on loopback, the guard
  before each host and a watchdog on Sill.log during, each host under 40 s,
  none left running; the normal app on an iPhone 18 Pro Max with
  `-SillConnect`): on a fresh install the first connection showed the touch
  card 1.06 s after the picture and, the stand-in pressing Next, saved all
  four steps; the second connection said "nothing owed here"; the Settings
  panel's Take the Tour (`-SillTakeTourAt 2`) showed it again from the first
  step; a session cut at the third card went on next time with what was left
  (the laptop card alone, with its subtitle); a host refusing this version
  (`SILL_TEST_MIN_DEVICE_VERSION=99`) gave its notice and no tour; every step
  upright and sideways (`-SillOrientation landscape` turns the normal app) at
  the default size and accessibility-extra-large, each ring on its controls
  under the real safe areas; the tripwire never fired. Found there and fixed:
  upright on that 3x screen the Settings card faded its second row as if it
  scrolled (its words missed their fit test by a rounding); the card is
  measured with a point of slack.
- Review fixes (2026-09-27; the plan's Results, "Review fixes", one commit
  each): Next kept the last card's scroll (Reduce Motion off); Skip in Take the
  Tour saved the permanent skip; an assistive technology's action did not count
  as starting; every automatic reconnect decided afresh (the dim over someone
  at work when a dropped picture came back); the bar card taught Aa over the
  Desktop, which Aa does not resize; at accessibility sizes a card covered the
  controls it lit, slivers of its ring beside it; a put-aside run ended by a
  turn put the keyboard back under a link's confirmation; a new frame size sent
  a pointer move under the tour. Found while verifying: the tour's delayed work
  acted on a gone stream screen (it now keeps to its session); DEBUG
  `-SillTourActivityAt` touches in the first session only. Then main at
  5c6a850 merged in (PRs #29 and #30; ci.yml, CLAUDE.md, DEVELOPMENT.md,
  HostSettingsPanel and PortraitStreamScreen conflicted; the targets on the
  views both arrangements share), and the phone's arrangement got its rules;
  then main at 2b38179 (PRs #31–#33): the Mac's pointer's `pointerFrameChanged`
  now holds its move while a card shows (the eighth fix, carried over).
  Verified: `Tests/checks/tour` 43,784 checks and 63 of 63 mutants,
  `run-all.sh` all 21 on the last merge; iOS Debug and Release for the simulator and Debug for a
  device, each commit's state building, only the known warning; `swift build
  -c release`; the review's probes before and after (the scroll after Next
  486 → 0; an accessibility activation in the beat: the tour came, now "not
  this session"); Take the Tour's Skip leaving the upright card owed (the
  mock); live through the remote door on loopback (a second host on the same
  port and identity, the app's own automatic redial): a session that passed,
  the reconnect's showed nothing; one cut mid-run, the reconnect's showed the
  tour from the step not passed; the build before showed the tour again after
  a reconnect; harness photos of every layout, text size and the phone's
  arrangement (four phone sizes); live on an iPhone 18 Pro Max, every step
  upright (the phone's arrangement) and sideways at two text sizes under the
  real safe areas; the tripwire never fired.
- **Untested, for Noah (the plan's P1–P16, on the iPad mini and the iPhone 15
  Pro):** the automatic tour needs a Release or TestFlight build on a fresh
  install, or Debug with `-SillTourState fresh` (Xcode's scheme). P1 a second
  after the Desktop shows, untouched: the tour; while it shows tap, hold and
  drag on the picture, type on a hardware keyboard, hover and touch with the
  Pencil, use a trackpad or mouse: nothing reaches the Mac (no `in.` counters
  in the host's `[1s]` lines) and the picture keeps moving; fresh again,
  touch the picture within the first second: no tour this session. P2 each
  step lights what it names in both layouts; held upright after a tour
  sideways and left alone: the laptop card once. P3 quit Sill.app at the
  third card, reopen: the next session starts at the first step not passed.
  P4 Take the Tour in both layouts with the keyboard up before Settings: the
  keyboard back after Done. P5 Skip on the first card: no tour at the next
  session, nor upright. P6 VoiceOver (no touch card, no trackpad rows, focus
  on each title, rows read whole, swipe up or down in the bar rows, the
  escape gesture skips, Magic Tap goes on, the stream screen read afresh
  after Done). P7 the largest text size. P8 Reduce Motion (fades only). P9 a
  hardware keyboard (Return on, Esc skips). P10 an outside link (the Camera on
  the Mac's pairing code) during the tour: it steps aside, Cancel, it is back
  at its step. P11 the iPhone upright and sideways: each ring on its
  controls, the cards clear of the Dynamic Island and the home indicator,
  "iPhone" and no Pencil row. Also the taps themselves: Next, Skip and Done
  under a finger, and a tap on the dim nudging Next (no tap could be made
  here; if one is lost to the dim, the plan's §6.1 drops the nudge). After the
  review: P12 the iPhone upright (the bar card under the thumbnails, the
  laptop card standing on the keys); P13 start at once, then drop the
  connection (Wi-Fi off and on, the Mac asleep and awake): no tour when the
  picture returns, and a tour on screen at the drop comes back; P14 VoiceOver,
  double-tap a thumbnail in the first second: no tour; P15 Take the Tour, Skip,
  then upright: the laptop card still comes; P16 the largest text size, every
  card beside its controls with its ring whole.
