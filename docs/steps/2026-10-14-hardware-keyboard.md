**A hardware keyboard and trackpad on the device (2026-10-14, branch `hardware-keyboard` from main at
985a733, PR #80; issues #67 and #68; the plan, its eleven open questions with the defaults taken, and the
results are in `docs/hardware-keyboard-plan.md`).** Noah: "Work on the keyboard and trackpad change (#67
and #68 together)". Device only: no wire change, nothing on the Mac changed.
- Esc (#67: an iPad Pro M4's Magic Keyboard sent none, 22 `in.text` and no `in.key`):
  `InputOverlayView.keyCommands` adds Esc with each of the sixteen ⌃⌥⇧⌘ combinations
  (`wantsPriorityOverSystemBehavior`, no title) while the view is first responder and no `EscapeKey` is on
  screen in its window (`EscapeKey.onScreen(in:)`; an EscapeKey's own Esc goes to the newest one in the
  window it was pressed in, `fire(in:)`: each Sill window is its own); the action goes through
  `ForwardedKeys.commanded` (down and up, the command's modifiers). One key press is sent once whichever
  channel brings it (`pressed`: a press no later than a command is swallowed with its up; `commanded`:
  nothing while the press holds it down). The Settings panel gains `EscapeKey(action: close)` (Done keeps
  `.cancelAction` for ⌘.). DEBUG: an `hwkey:` line for every hardware key and its channel, `escape:` when
  an EscapeKey takes Esc, `-SillKeyProbe 1` (GameController's view of each key), `-SillEscViaCommand 1`.
  For the reporter: Control-[ is Esc in a terminal.
- Keys without the Keyboard button (#68): `HardwareKeyboardPolicy` (pure, `Tests/checks/hardware-keyboard`),
  owned by `InputOverlayProxy` (one per stream screen; it outlives a rotation). With a hardware keyboard
  (`HardwareKeyboardMonitor`, GameController's coalesced keyboard; DEBUG `-SillHardwareKeyboard 1|0`) the
  input view takes the keyboard by itself when a view joins a window (a session's start, a rotation, a
  reconnect), a keyboard attaches or the last taker closes (`StreamScreen.keyboardTakers`: Settings,
  pairing, the tour, the Apps drawer, Menus), and lets go when a taker opens or the keyboard goes; another
  responder's keyboard is not fought. Never the person's own: `keyboardShown` (the Keyboard button, the key
  row's cap, the tour's busy and activity tests) is only the person's (`onOwnChange`), so keyboard users get
  the tour. The button: over the hold, the person's (`makeOwn`: iPadOS's keyboard views back); again, the
  hardware keyboard's (`makeAutomatic`). During the hold the input view is an empty view with no assistant
  groups: nothing drawn, even where UIKit and GameController disagree.
- Trackpad and wheel (#68): two scroll-only pans (`.continuous`, a phased gesture with the finger's coast;
  `.discrete`, plain deltas), `maximumNumberOfTouches = 0`, `[.indirectPointer]`, touches refused, beside
  the hover; one path with the finger pan (`scroll(_:at:translation:velocity:from:)`), one scroll gesture
  at a time; a pointer scroll's first event and a lone notch are deltas (`scrolled(to:at:)`).
- Defaults taken: the button keeps its software-keyboard meaning; the drawer and Menus are takers; all
  sixteen Esc combinations; nothing drawn during the hold; the person's keyboard across a rotation and ⌘W
  with a taker open as before; Sill's own coast for a trackpad; no scrolling over the on-screen trackpad;
  the hold also under Full Keyboard Access and Switch Control until Noah's step 13 says otherwise (UIKit
  can tell Switch Control, not Full Keyboard Access).
- Verified (the plan's Results): hardware-keyboard 51 checks, 20,000 random sessions, 31 of 31 mutants (in
  CI's matrix); key-strokes 347 (18 new) and 81 of 81 mutants (9 new); `run-all.sh` all 41; the iOS app
  Debug and Release for the simulator and Debug for a device, and `swift build -c release`, with the known
  warnings only; 19 harness photos identical to main's (the Menus pull-down open among them, the hold let
  go under it); live on private simulators against `SillHost --synthetic`, with `Tests/keyrig` (new, TEST
  ONLY: a virtual HID keyboard and mouse inside the simulator, as duorig): keys and ⌘W with no Keyboard
  button, after two turns too (an iPhone, `-SillTurnAt`); Esc, ⇧Esc, ⌘Esc and ⌥⌘Esc through both channels;
  Esc closing Settings and skipping the tour with nothing sent; the tour shown with a keyboard attached; a
  keyboard going and coming; the button's two states on a fresh iPhone; wheel notches; the touch rig 72 of
  72 against main's. Found there and fixed: a lone wheel notch was never sent; the rule asked with no view
  in a window. Learned in the simulator: its GameController always counts its own keyboard, UIKit counts
  one once keys arrive, iPadOS 27 refuses programmatic turns, and scroll events marked as momentum reached
  no pan there (no real trackpad's events reached the continuous pan, so a device decides whether iPadOS
  coasts too). CI's Build and check passed on 807c8ef. With the other open pull requests it meets in the
  docs and, with #79, in StreamScreen.swift's DEBUG hooks (keep both): the plan's Progress.
- The review (2026-10-14; the plan's Results, "The review and its fixes"): four findings, each checked
  here first and fixed in a commit of its own. Esc's key commands and EscapeKey keep to their own window
  (`onScreen(in:)`, `fire(in:)`): Settings open in a window behind took the stream's Esc key commands in
  front (a private simulator, `-SillSecondWindow 1 -SillSettings 1 -SillEscViaCommand 1`: 2fc53ed's build
  sent no key 53 to the host, this one did), and Esc could close another window's panel. README, the
  support page, the App Store bullet and the next What's New kept Esc and trackpad scrolling out until
  Noah's steps 1, 7 and 9 passed, through Universal Control on 2026-10-15 (the plan's "Words that wait
  for a device", and the Results' "Noah's test through Universal Control"), and then took them; the support page's Keyboard
  button sentence; Full Keyboard Access and Switch Control (open question 11, step 13). Towards #68, not
  Fixes. Again on 7fdc902: the three iOS builds and a clean `swift build -c release`, the known warnings
  only; `run-all.sh` all 41 at the first run; the touch rig 72 of 72; Esc in one window and in two, live; no check
  compiles a file the review changed, so no mutants again.
- **Untested, for Noah (the plan's 1–13, on the iPad with the Magic Keyboard, a Debug build):** which
  channel brings Esc (`hwkey:`; `-SillKeyProbe 1`), Esc in iTerm2's vim, zsh's vi mode and Zed, and
  Control-[; typing right after connecting and after a turn; ⌘W closing the Mac's window, not Sill's;
  nothing drawn, and nothing popping up when the keyboard is taken away; the Keyboard button's two states;
  Esc over Settings, the tour and pairing; the tour on a fresh install with the keyboard attached;
  two-finger scrolling (any double coast) and a mouse's wheel; VoiceOver; an input method's candidates
  (none drawn during the hold: the Keyboard button brings iPadOS's views back); two Sill windows side by
  side (Settings open in one leaves Esc to the other; Esc closes only its own window's panel); Full
  Keyboard Access and Switch Control (Tab, Space and Esc through Sill's bar while the stream holds the
  keyboard).
