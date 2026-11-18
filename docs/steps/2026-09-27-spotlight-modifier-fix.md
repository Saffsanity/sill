**The stuck command after Spotlight (2026-09-27, branch `spotlight-modifier-fix`
from main at 643af6b, with main at da43f6b (PR #38) merged in; not pushed).**
Noah: "The stuck command after Spotlight", found by PR #38's review. The
Spotlight key sent ⌘Space as one key down and up, each carrying command, and
the host posted both as they came; every keyboard event posted leaves its flags
in the HID state table its source reads (CGEventSource.h), and pointer and
scroll events start from them, so the next tap was a ⌘-click until something
was typed. The key row, a latched ⌘, ⌃ or ⌥ on the software keyboard and a
hardware keyboard's ⌘ did the same. Inferred, not observed: nothing may be
posted while this is built.
- Host (`KeyStrokes`, pure): a key's down carries its device's modifiers and
  what the modifier keys down hold, its up only what they hold; a modifier's
  own key is a flags-changed event with what is held; a key or text that no
  longer says a modifier lets go of that key first; a device that leaves, and
  the host at its end (Sill.app's Quit, a Ctrl-C, kill or hangup; the CLI
  without --virtual-display then dies of the signal as before,
  `HostShutdown.installKeyRelease`), let go of every key and button. Input
  with nowhere to land (nothing streams, or a switch drops held input) is
  dropped but for the up of a key or a button the Mac has down
  (`DroppedInput`), a button's where the pointer is.
- The tripwire (`KeyUpCheck`, pure): a quarter of a second after every key's
  up whose down put a modifier in the table (a modifier key's own, a
  shortcut's key, the ups KeyStrokes makes), the table is read again; a
  modifier the up should have taken out and the table still holds, that no
  key down holds and no key since carried, is counted, `in.keyModifiersLeft`,
  and said once with the key ("Keys: a quarter of a second after a device's
  key 55 came up, …"). TEST ONLY `SILL_TEST_INPUT_LOG=1` (Build and run)
  prints what a `--synthetic` host would post and each check it arms.
- Device (`KeyChords`, pure): a shortcut goes out as a keyboard sends it, its
  modifiers' own keys around it (`KeyChord.press`: the Spotlight key, the key
  row, a latched ⌘S), so Sill.app 0.3.x is left nothing held either; a
  hardware key's up follows its down (`ForwardedKeys`), a cancelled press
  comes up, and the overlay lets go of its keys when it stops taking them.
- `Tests/checks/key-strokes` (329 checks, 72 mutants; CI and its mutants
  matrix): every path's exact events on this Mac and on one from before, the
  tripwire armed for each path and reporting on Macs that keep their table
  through a modifier key's up or another key's, input with nowhere to land,
  and random sessions of two older devices (3,000, and 1,000 on each such Mac)
  and of this device (2,000, and 500 each). Against main's rules, 205 of the
  279 checks before the review failed.
- Review (2026-09-27; each reproduced first, then fixed in a commit of its
  own): the tripwire was armed for none of this device's paths; the CLI's
  default path died of a signal with a device's modifier down; the drag guard
  this branch had added to `TrackpadSurface.didMoveToWindow` never ran (UIKit
  cancels the long press first, and its end lets the button and the modifiers
  up and spends the latch: a rig on a private simulator) and is gone; and,
  older than the branch, a button's up with nowhere to land was dropped,
  leaving the Mac's button down and every later move a drag.
- Verified: `swift build -c release`; iOS Debug for the simulator (CI's
  command), only the StreamClient warning; `run-all.sh`, all 27; the dry run on
  a synthetic host against 84ddd9c's (this device's Spotlight key arms a check
  for command at key 55's up; a drag whose stream stops ends "left mouse up
  (none) at 454,285" and the moves after are moves, where 84ddd9c's are
  drags); SIGINT, SIGTERM and SIGHUP with ⌘ and the button held let go of both
  and end with 84ddd9c's wait status; the app's `-SillInputTest` against that host, a
  rotation rig and the touch rig (72 of 72 against main's) on a private
  simulator, deleted after.
- **Untested, for Noah:** with this Sill.app and this iPad build, the Spotlight
  key and then a tap on a file in Finder selects it (not a ⌘-click), and the
  same after the key row's ⌘esc, a latched ⌘S and a hardware ⌘C; a latched
  ⌘-click stays a ⌘-click and the next tap is plain; ⌘ held while Wi-Fi drops,
  and Quit Sill.app while holding it: plain clicks after; a drag held on the
  trackpad while the window is closed on the Mac (⌘W there), let go, then
  another window picked: the pointer moves there, nothing drags. Sill.log
  should have no "Keys: … came up, this Mac's modifier keys still read" line;
  if it has, note the key (55 is ⌘). With this iPad build against Sill.app
  0.3.1, the Spotlight key then a tap is a plain click.
