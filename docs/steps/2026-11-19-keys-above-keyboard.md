**The modifier keys above any keyboard on an iPhone held upright (2026-11-19, branch `keys-above-keyboard` from main at eb48ac9, a draft pull request for Noah).**
Asked for by mail: on an iPhone held upright a taller keyboard covered the key row. Noah's answer (10-30 and
11-16) promised a way to keep the modifiers reachable with any keyboard, and called the idea of leaving the
window picker tucked away while a keyboard is up part of the same change (the promises inventory's row 20,
`~/Downloads/sill-handoff/next/promises/INVENTORY.md`). Device only: no wire change, nothing on the Mac.

- **The cause.** On a phone held upright the stream screen ignores the keyboard (StreamScreen's
  `.ignoresSafeArea(edges: .bottom)` takes the keyboard's region with the bottom edge), and every row of
  `PhonePortraitLayout` is a function of the screen's size alone, or, with Larger Picture, of the screen and
  `keyboardHeight(for:)`, a table of Apple's own keyboards as measured on the iOS 27 simulators (233, 301,
  310, 320 pt). Nothing on a phone read the keyboard that actually came up: `KeyboardFrameMonitor` publishes
  its real frame, but only the Duo's inner display used it (#215). So the key row sat where Apple's keyboard
  leaves it clear: 56 pt above it on an 18 Pro in the standard arrangement, exactly 10 pt above the estimate
  with Larger Picture. A keyboard taller than that covered it, and ctrl, opt, cmd and shift with it: a
  third-party keyboard with a bar of its own, an input method's candidates (44 pt more), Display Zoom's and a
  future iPhone's keyboards. Two places were covered even with Apple's own: an iPhone SE's key row by 24 pt
  (phone-portrait's keyboard table, accepted in the portrait plan's open question 5), and the iPhone Duo's
  cover, whose key row ends 236 pt above the screen's foot, so any keyboard taller than that covered it.
- **The fix: `PhoneKeyboardLift`** (iOSClient/PhoneKeyboardLift.swift, pure; `Tests/checks/phone-keyboard-lift`,
  184 checks and 44 mutants; pbxproj A0B0/F0B0). From the keyboard's real top as UIKit reports it, only
  while the person's own keyboard is up (`keyboardShown`: never the drawer's search field's, never a hardware
  keyboard's hold): while the keyboard would come closer than 10 pt to the key row, row 1, the thumbnails'
  row and the key row lift together by just that much (whole points), and the picture's frame keeps its
  shape in the room left above them, centred across. The viewport stays the layout's picture, so the Mac
  resizes nothing; the lift is at most the picture's height. A keyboard that leaves the key row clear moves
  nothing, so every iPhone with Apple's keyboard is as on main but the SE (lifted 34 pt: the picture 304×190
  instead of 359×224 while the keyboard is up). The trackpad runs from 10 pt under the moved key row; the
  drawer follows row 1 (it can be open with the keyboard up); the dim is everything but row 1. No switch:
  it is a fix.
- **Hide Thumbnails While Typing**, the new behaviour, a switch, off unless turned on
  (`Sill.hideThumbnailsWhileTyping`): while a keyboard is up the thumbnails' row (the strip and the Menus
  button at its end) is tucked away and the key row takes its place, 16 pt under row 1's buttons as Larger
  Picture has it, so more of the trackpad shows above the keyboard (118 pt on an 18 Pro against 46) and a
  tall keyboard needs a smaller lift, or none (the Duo's cover under a 301 pt keyboard: 3 pt instead of 75).
  A thumbnail's lights close as the row tucks away. Larger Picture's arrangement has no thumbnails' row, so
  the switch changes nothing there. Place on this base: the Settings panel's This iPhone, right after Larger
  Picture (both are about the thumbnails' row held upright), on every iPhone and the iPhone Duo (its cover),
  never on an iPad. **It moves into the whole-screen Settings pane's device part (draft #393, `settings-pane`)
  with This iPhone's rows.**
- **The views.** PortraitStreamScreen reads the keyboard's frame (`phoneGlass`) and the switch, builds the
  lift over the layout and places the picture's frame, row 1, the strip (tucked: `TuckedAway`, out of sight,
  touch and VoiceOver, the same view), the key row, the trackpad, the drawer and the dim from it; the rows
  animate with the keyboard (0.25 s ease out). Full screen and the swipe in's preview never lift. DEBUG: the
  console's `keys: …` line at each change (`keys: lifted 34 pt, the key row 10 pt above the keyboard at
  414, the picture 304×190 in a room of 359×190, the trackpad from 414`), and the `keyboard: up, …` line now
  measures the placed rows.
- **The harness's tall keyboard:** `-SillTallKeyboard N` gives the stream's input view an input accessory
  view N pt tall, labelled as a stand-in, so UIKit's keyboard is really N pt taller and reports it (a
  simulator cannot install a third-party keyboard). DEBUG only. `-Sill.hideThumbnailsWhileTyping 1` turns
  the switch on for one run; `-SillSettingsScroll typing` scrolls Settings to it.
- **Community work on the same ground** (Noah's build-on rule): PR #383 (an accessory bar over every
  software keyboard, a bottom shortcut bar, custom shortcuts) and issue #371 (keys and trackpad on demand in
  the Duo's landscape). Not built on #383, for these reasons, read in its code: upright, where this fault is,
  the key row is already there, so the bar shows the same keys twice, and it makes the keyboard 44 pt taller,
  which Larger Picture's estimate does not know, so it covers the key row itself; its latch lives in the
  input view and the stream screen resets it on every update, so the bar and the key row disagree; a locked
  modifier reaches only the bar's own keys, never typed text; its bottom bar sits under every layout with no
  switch, which moves every approved phone rect; and it conflicts with #397 (`ready-276`) in StreamScreen.swift
  (`git merge-tree`, today's heads). The review of 2026-11-18 (`next/feature-requests/
  pr-evaluations/keys.md`, "#383") reached the same verdict: redo its ideas, credited, in the per-app keys
  work, where an accessory bar for layouts without a key row (sideways, #371's need) belongs. #371 is not
  touched here: it asks for the key row sideways, a layout change of its own.

**Defaults taken, for Noah to confirm**
- The fix lifts the rows and shrinks the picture's frame (at its shape) rather than covering the picture's
  foot with them: what is typed into stays in view. The other way is a one-line change in `frame(video:)`.
- The lift is live, with the keyboard, never learned: Larger Picture's estimate stays the room the Mac fits
  windows to, and only while a taller keyboard is up does the frame get smaller. (The Larger Picture plan's
  open question 3 had "learn the tallest keyboard and move the layout once" as its alternative.)
- Hide Thumbnails While Typing is off; the Menus button goes with the thumbnails (it is in their row);
  bringing it into row 1 instead would move the Keyboard button under the finger as the keyboard comes up.
- Its place: This iPhone, after Larger Picture, on the Duo too.

**Known, for Noah to decide (none changed here)**
- Where the rows lift, row 1 moves up with them, so the Keyboard button that brought the keyboard up is no
  longer under the finger (34 pt on an SE, 7 to 135 pt on the Duo's cover by keyboard). With Hide Thumbnails
  While Typing on, the SE needs no lift and the cover's own keyboard about 3 pt: a reason to consider the
  switch on by default on the smallest screens.
- The picture's frame is smaller while a lifting keyboard is up: on the Duo's cover under a 301 pt keyboard,
  245×153 against 366×228 (with the switch on, 361×225).

**Proposed words** (not in any published page)
- What's New: "iPhone held upright: the row of keys (esc, tab, ctrl, opt, cmd and shift) now stays above the
  on-screen keyboard, whatever its height: a keyboard from another app, one with characters to pick from, an
  iPhone SE’s own, and every keyboard on iPhone Duo’s cover. While a taller keyboard is up, the buttons and keys
  move up above it and the picture gets a little smaller; nothing changes on your Mac. New in Settings › This
  iPhone: Hide Thumbnails While Typing puts the window thumbnails away while the keyboard is up, so the keys sit
  right under the buttons."
- Support page (the phone's layout): "The keys stay above the on-screen keyboard, whatever keyboard you use. To
  keep the picture larger while you type, turn on Settings › This iPhone › Hide Thumbnails While Typing: the
  window thumbnails step aside until you put the keyboard away."
- Review notes: nothing new to review (a layout fix and a switch, no permission, no background mode).

**Merges with the other drafts** (trial merges of this branch at 61a22f42, by `git merge` in a throwaway worktree; the pure
checks run on each result):
- **#397 (`ready-276`, Hold to Lock Modifiers), #410 (`ready-315`, Arrow Keys), #393 (`settings-pane`):** each merges
  cleanly. On each result `phone-keyboard-lift` passes (183 then; 184 now), and `key-strokes` (607), `phone-key-row` (159) and
  `settings-pane` (258) respectively. With #397 the phone's key row now really is on screen whenever
  `ModifierLock.keyRowOnScreen` says so (on main a tall keyboard covered it while a lock rode it unseen). With #410
  the scrolling strip lives inside the key row's rect, which the lift moves. With #393 the switch's rows land in
  `thisDevice`, inside the pane's `devicePart`, and `-SillSettingsScroll typing` reaches them there. #397 and #410
  conflict with each other (their Keys group), not with this branch.
- **#383 (cubelikeplayDaniel):** one conflict, `InputOverlay.swift`: both give the input view an
  `inputAccessoryView`. Resolve with one override: nil while the hardware keyboard holds the keyboard; in DEBUG the
  harness's stand-in first when `-SillTallKeyboard` is set; else #383's bar. With this branch the bar no longer
  covers the key row upright (UIKit's frame includes it, so the rows lift over it), but it still repeats the key
  row's keys there.

**Verified:**
- `Tests/checks/phone-keyboard-lift`: 184 checks, 0 failed, among them a grid of 5,272,652 placements; **its
  mutants: 44 of 44 caught** (this Mac, in the heavy lock, 571 s at b14d034b). Nothing else's patterns changed:
  PhonePortraitLayout.swift is untouched, so `phone-portrait`, `tour` and `full-screen` (which compile it) keep
  their mutants as they were.
- `Tests/checks/run-all.sh` on this Mac at b14d034b: 75 of 75, "All passed" (661 s), `phone-portrait` 484,
  `tour` 732,447, `key-strokes` 505, `repo-rules` 11 of 11.
- CI's Build and check green on d15893c9 (run 44504467686) and on b14d034b (run 44508139153): `swift build -c
  release`, run-all 75 of 75, the iOS app for the simulator with Xcode 27.1 `** BUILD SUCCEEDED **`, its only
  warning main's own (StreamClient.swift:4527).
- The trial merges above.
- Harness photos (`Scripts/harness-photos/keys-above-keyboard.cases`, 11 cases on the agents' iPhone Duo, iOS 27.1,
  the cover upright, which draws an iPhone's arrangement; 2e5af22c against main eb48ac9f, 206 s with the
  simulator): 3 of 11 pixel for pixel main's, as they should be (the cover with no keyboard, with the switch on
  and no keyboard, and the inner display upright with its keyboard, #215's row); the 8 with a keyboard or the
  switch's row differ as planned. The cover's own keyboard is about 265 pt tall there (its top at about 413 of
  678 pt), so on main it covers the key row (398-442) but its top 15 pt; on this branch the rows lift 39 pt, the
  key row 10 pt above it, the picture 303×189 at 16:10. With the 60 pt stand-in the rows lift 99 pt; with the
  switch on the thumbnails tuck away and nothing lifts; Larger Picture on the cover (no hinge in the harness)
  covered the key row on main as well (its 233 pt estimate) and lifts over it here; the drawer follows row 1. The
  photos, the differences and a README: `~/Downloads/sill-handoff/next/keys-above-keyboard/photos/`.

**Untested, for Noah:** a real keyboard taller than Apple's on a device (a third-party one, Pinyin's or
Japanese's candidates), the rows' animation beside the keyboard's, Larger Picture with a window Aa fitted to the
room under a taller keyboard, the switch's trackpad band in use, VoiceOver with the thumbnails tucked away, a
hardware keyboard (nothing should move), Display Zoom's 320 pt, and the Duo's cover on a real Duo: the pull
request's numbered steps.
