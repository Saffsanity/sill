**The keyboard in the Duo's laptop pose (2026-10-27, finished 2026-11-09 for 0.6.1; its crease row replaced by
the toggle on 2026-11-10, the entry above; PR #220 from addhumal's
`duo-laptop-keyboard`, finished on it with maintainer edits, his commit 2e35172 kept; issue #215, matt-cahill
and kyeschung; the measurements, the rule, the crease, the results and P14 are in docs/iphone-duo-plan.md,
"The software keyboard in the laptop pose").** The software keyboard covered the laptop pose's key row, its
Keyboard cap with it, so nothing took the keyboard down. Noah's "A" (2026-10-27): while the person's software
keyboard is up there, the key row alone between the fold and the keyboard's glass, the window bar hidden and
back as it was with the keyboard down; B (a two-row strip) deferred. His "Crease" (2026-10-29): for the
keyboards too tall for that room, the row in the fold's band. Device only, no wire change; every Duo build and
photo on the iOS 27.1 runtime.
- What UIKit reports in the laptop pose (iOS 27.1 simulator; DEBUG `-SillKeyboardProbe 1`): shown, every
  keyboard as the whole lower page from the fold's top edge, (0, 455.5, 669×495.5); going, the glass as the
  hide's begin frame: the English keyboard (0, 555, 669×396), the Chinese (Pinyin) and emoji keyboards (0, 506,
  669×445); a switch to emoji while up sends nothing. Open flat upright the English keyboard is reported as
  itself, (0, 640, 669×311), and folded from there into the laptop pose with it up, UIKit goes on reporting that
  while the glass (a photo) is at 555. Taps between the fold and the glass, and in the crease, reach Sill.
- The rule (DuoPosture, pure; `Tests/checks/duo` 267,678 checks, 109 of 109 mutants): `visibleKeyboardTop`
  (a report at or above the fold's lower edge is the page, the glass the keyboard's own height above the foot:
  the one it last went with at that width, else the measured 396; any other report the glass, never lower than
  that height puts it); `keyboardHeightToLearn` (a hide's begin frame is learned only where UIKit had reported
  the keyboard from above it, the page: open flat's 311 once put the next laptop row under the glass);
  `keyboardRow` (a `KeyboardRow`: under the fold while the room holds 44 pt caps, Apple's least target, with 8
  of black (52 pt): the caps the room less 8, at most 58, the black above and below alike, 4 + 51 + 4 under the
  English keyboard; else in the crease, 34 pt caps centred on the fold's band, 458.5–492.5; 14 pt sides, 6 pt
  gaps; nil off the laptop pose, without the person's keyboard, and at 148 pt of room and more).
  PortraitStreamScreen: the caps as they are (the Keyboard cap lit, Spotlight while the Desktop streams) at the
  row; the controls under it hidden from sight, touch and, only while the row is alone, VoiceOver
  (`accessibilityHidden(while:)`, iOS 18's `isEnabled:`: the audit's §4, an unlabeled element beside "‹App›
  menus" on every iPad before); a cap held as the row goes alone comes up then (`KeyRow.hidden`).
- Verified (2026-11-09, the plan's Results): main 41e8cb88 merged (CLAUDE.md alone met), `run-all.sh` all 63 on
  the merge; `-SillAXDump` main's line for line on the iPad upright, the iPhone and the Duo's laptop pose with the
  keyboard down, the row alone with it up; harness photos pixel for pixel main's on the iPad upright, the iPhone
  upright and the Duo's six poses, differing only from 500 pt down in the laptop pose with the keyboard up;
  live against a loopback synthetic host with XCUITest taps (esc in the row and in the crease, ← in the crease,
  the Keyboard cap's 6 pt sliver over a first emoji keyboard), keyrig's Esc and letters while the row showed,
  folds with the keyboard up, a held esc up 10 ms after the row went alone. Photos in
  `~/Downloads/sill-handoff/device-tests/2026-11-09/215/` (Oct 27's in `…/2026-10-27/215/`).
- Known: a tall keyboard's first appearance, and a switch to emoji while up, place the row for 396 (its top
  6 pt above the glass, still tapped) until that keyboard has gone once; the window's eleven-cap row stays.
- **Untested, for Noah:** the plan's P14 on a Duo (the row over the device's own keyboard and its console
  lines, esc and ⌘C on the Mac, the cap; the emoji and Chinese keyboards and the crease, whose taps on a real
  fold only a device can show; a hardware keyboard; open flat then the laptop pose with the keyboard up;
  VoiceOver).
