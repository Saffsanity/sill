**Held keys repeat, as on the Mac (2026-10-28, branch `key-repeat` from main at 6c5b5d2; issue #162; PR #240).**
Noah, 2026-10-27: "#162 should expand to make holding down keys work on all keys when held, same as a
regular keyboard, wait times and all, where non-command keys wait a second before starting their
repeating. Same as desktop." An event posted from a CGEventSource never repeats (the HID system repeats
only the keyboards it reads), so a held arrow, ⌥← or ⌘Z reached the Mac once. The host repeats it, so
every device gets it from a Mac with this build (no wire change for that; the window lists' additive
`keyRepeat` came with a hardware keyboard's letters, below). Supersedes addhumal's #163 (the device
repeating at its own 0.4 s and 20 a second), which this branch leaves alone.
- Host (`KeyRepeat`, pure; `Tests/checks/key-repeat`): InputInjector tells it each keyboard event it
  posts and steps it at the times it names (a Task on the main actor); a key held down repeats after
  the Mac's own Delay Until Repeat and at its Key Repeat Rate (NSEvent's keyRepeatDelay and
  keyRepeatInterval, read at each key's down: 0.5 s and 1/30 s on this Mac), each repeat the key's
  down again with the autorepeat flag (kCGKeyboardEventAutorepeat) and the flags in force (what the
  down carried less a modifier let go since, and what the modifier keys down hold now: ⇧ pressed while
  → repeats selects, ⌥ let go turns word jumps into steps). Every key but the modifiers, Caps Lock,
  fn and the media keys; one key at a time, the last pressed (an earlier one still held never takes
  over again). It stops at its up (any device's), another key's down, typed text, a gesture's chord,
  its device leaving and the host's end (every key let go), and input with nowhere to land (the
  coordinator's `keyRepeatLanding`, `currentSourceRect` nil, and select's drop point); it waits while
  input is held for an activation (a repeat never overtakes it), and while its device has been quiet
  half a second (`StreamServer.lastHeard`, every message's header; a device pings every 0.25 s), then
  starts over after the delay: a stalled link can hold the key's up back for the 4 to 8 s before the
  Mac drops the device. Its first repeat (after the press, and after a quiet spell) waits for a word
  from its device heard after the press and no earlier than `KeyRepeat.firstWord` (0.3 s) before it is
  due (the review of the held letters): the link keeps the device's messages in order, so a key only
  tapped (a letter, a Delete) whose up a stall holds back never repeats, and a key held has its ping in
  time. A late wake posts once, the next at least half an interval on. Off (a delay
  or an interval of a minute or more) and nonsense repeat nothing; a delay under 0.1 s and an
  interval under 15 ms count as those. `in.keyRepeat` on a host that posts; a `--synthetic` host
  counts `in.dry`, and with SILL_TEST_INPUT_LOG=1 prints "Test input: key 123 repeats after 0.50 s,
  every 0.033 s" at each press and "Test input: key 123 repeat (none)" for each repeat.
- Device (`HeldCap` in KeyChords.swift, checked in `key-strokes`): the portrait key row's esc, tab and
  arrows go down at a finger's touch and up at its release (a ButtonStyle's isPressed; `KeyChord.down`
  and `up`, `press` = both), what is latched going down with the key and spent at the touch; one cap at
  a time; the Button's own action after a touch sends nothing, or the up of a press whose end
  isPressed had not told yet (the action comes with the release: a missed end never leaves a key down
  repeating), an activation with no touch (VoiceOver, Switch Control, Voice Control, a keyboard) the
  whole press as before; the latch is spent when a key goes down with it (`spendsLatch`); the row
  leaving the screen lets a held cap up. A phone's esc and tab stay taps at the accessibility text sizes, where a long press
  shows the cap large (`capsHold`). The latching modifiers, Keyboard and Spotlight are taps as before.
  A hardware keyboard's characters: the next bullet (they were thought to keep iPadOS's own repeat).
- Held letters (2026-10-29; Noah on the iPad mini with a Bluetooth keyboard and through Universal Control:
  "hold p didnt work … When I held down e it showed the keyboard options for Spanish characters"). The text
  system's keys never reached the Mac as held keys: in the iPad simulator with `Tests/keyrig` (`wait:S` holds
  a key) against a loopback synthetic host, 4504a96c's build typed a held P once (one `pressesBegan` handed
  to the text system, one `insertText "p"`, nothing more in 2.3 s), a held E once and then iPadOS's
  press-and-hold accent popover (è é ê ë ě ẽ ē ė ę, still up after the release), and repeated Delete and
  Space itself (the first after about 0.4 s, then every 0.105 s: 20 separate presses each in 2.3 s, iPadOS's
  timing, not the Mac's). Now `KeyTyping` (TextComposition.swift, pure, checked in `text-composition`) says
  at each key's down who types a hardware keyboard's characters: the Mac, as keys, while it says it repeats a
  held key (`WindowList.keyRepeat` 1, additive, nil from every host before: `KeyRepeat.generation`, set in
  every window list; the device's `StreamClient.hostKeyRepeat`), the keyboard selected on the iPad types the
  Latin alphabet directly (its primary language's likely script is Latn, and its input method does not
  compose: `composingLatin`, Vietnamese and Hawaiian, whose input managers say they compose text in the iOS
  27.0 runtime's TextInput bundles), nothing is composed and nothing is latched on the key row (with no
  keyboard selected, only if every keyboard set up would); else iPadOS's text system, as before (a Sill for
  Mac from before key repeat, which would type each key once where iPadOS repeats Delete and Space itself; an
  input method's keyboard, Chinese, Cantonese, Japanese, Korean, Vietnamese, Hawaiian or a transliteration
  one; another script's, Russian, Greek, Arabic, Hindi…; a latch, whose shortcut `insertText` makes), and
  while marked text is open every key is the input method's. While the Mac types,
  `ForwardedKeys.characterUsages` (the letters, digits, Return, Delete, Tab, Space, the punctuation keys
  `` - = [ ] \ ; ' ` , . / `` and Shift's two keys, each a key every Sill for Mac answers to) go down and up
  as keys, so the host repeats them at the Mac's timing, the Mac's own layout and dead keys make the
  characters (⌥E then E is é), Shift is a key the Mac hears (the repeats follow it; a click with it held is a
  shift-click) and no accent popover comes; Caps Lock stays the iPad's (its key the text system's) and a
  letter typed with it on and no ⌘, ⌃ or ⌥ carries Shift (`ForwardedKeys.carried`). The keypad and the ISO
  keyboards' Non-US `\` and # stay the text system's (no Sill for Mac before has them as keys). Unchanged:
  the ⌃Space rule (#138), the on-screen keyboard (`insertText`), dictation, Esc's key command, every key that
  already went as a key, the host's repeat; the wire but for the additive `keyRepeat`. DEBUG: each hardware
  key's down line ends in who types it, and so do textinput's first-responder and keyboard-switch lines:
  `hwkey: usage 19 down via pressesBegan (none): to the Mac; the Mac types: en-US`,
  `…: the text system's; iPadOS types: zh-Hant`,
  `…; iPadOS types: the Mac repeats no key (a Sill for Mac before key repeat)`; `-SillInputScript`'s
  `type TEXT` hands the input view text as the on-screen keyboard does. Defaults taken
  (docs/hardware-keyboard-plan.md, open question 12): the Latin alphabet only, as a keyboard chosen in
  another script says which characters are meant and, with two keyboards, ⌃Space is iPadOS's (alternative:
  every keyboard that does not compose); Hawaiian left to iPadOS with Vietnamese (its input manager says it
  composes; whether it marks text for a hardware keyboard is a device's to show); the Latin keyboards that
  compose a letter with its accents (`UIKeyboardComposesText`: Czech, Slovak, Faroese, Navajo, Guarani…) the
  Mac's, as a hardware keyboard's dead keys make those and the Mac's input source has its own. Known: the
  iPad's hardware keyboard layout and Key Repeat settings no longer apply to the Mac's keys (the Mac's input
  source does); letters typed through iPadOS still never repeat. Verified: `key-strokes` 440 checks (55 new)
  and 115 of 115 mutants (16 new); `text-composition` 193 (15 new) and 102 of 102 (15 new); `key-repeat` 106
  (6 new: P held, P then E, ⇧A with ⇧ let go, A with Caps Lock, `KeyRepeat.generation`) and 37 of 37 (1 new);
  `compatibility` 145 (5 new: `keyRepeat` in the JSON, left out when nil, nil from an older host,
  round-tripped, skipped by an older reader) and 34 of 34; `run-all.sh`, all 57 (one at a time on the final
  code, each started under a load of 20; 2,720 s); `swift build -c release`, only the CaptureProbe warning;
  the iOS sources typechecked with and without DEBUG, and Debug and Release for the simulator and Debug for a
  device, only the StreamClient warning, the Release binary none of the DEBUG lines (the three builds on
  4bb51fb2; the last two commits typechecked both ways and built by CI); CI's "Build and check" green on
  4bb51fb2 and on f534be17; live on a private iPad mini simulator (iOS 27.0) against loopback synthetic hosts
  with the input log, keys from the rig: P held 2.3 s (key 35 down, "key 35 repeats after 0.50 s, every 0.033
  s", 55 repeats from 0.49 s at 30.6 a second, its up, no `insertText`), E held 3.3 s (85 repeats, no popover
  in the photo), ⇧A with ⇧ let go mid-hold (40 repeats with shift, then 40 without), Delete and Space (55 and
  56 repeats at the Mac's 0.5 s and 30 a second), A with Caps Lock on (25 repeats with caps lock and shift; 1
  with caps lock alone), ⌥E then E, Return, Tab, ⇧Return and ⇧Tab (Shift's own key around them); ⌘S, ⌘Z, Esc
  and ⌃Space with one keyboard the base build's events exactly; Zhuyin (ㄋㄧˇ, Return: 你 once) and Japanese
  Romaji (に) composing on the iPad as before; ⌃Space with Zhuyin and English iPadOS's switch, then P
  repeating on the Mac with English and composing ㄣ with Zhuyin; Russian's з typed once through iPadOS; the
  on-screen keyboard's `insertText "pe"` as text; a held P let up on the Mac when Sill went to the background
  (UIKit's `pressesEnded` at the switch) and when the keyboard went (the hold let go); and the gate: against
  this branch's host P went as a key (54 repeats), against 4504a96c's (no `keyRepeat`) P was typed once
  through iPadOS and Delete repeated by iPadOS, 20 separate presses, as before. The Mac's own press and hold
  applies as to its own keyboard (the repeats carry the autorepeat flag): in TextEdit or Notes with macOS's
  default a held E shows the Mac's accent menu and a held P types once; Terminal, iTerm2 and apps with
  `ApplePressAndHoldEnabled` off repeat. **Untested, for Noah** (Sill for Mac from this branch, the iPad with
  a Bluetooth keyboard and through Universal Control), in Terminal (or with the Mac's press and hold off):
  hold P (ppp… after the Mac's delay, at its rate), hold E (eee…, no accents on the iPad), ⌥E then E (é), ⇧
  held over a letter and let go (capitals, then small letters), Caps Lock, Space and Delete held; in
  TextEdit, a held E shows the Mac's accent menu, as the Mac's own keyboard does; a Chinese keyboard on the
  iPad (composes as before; ⌃Space switches); a keyboard layout on the iPad other than the Mac's (the Mac's
  wins).
- The review of the held letters (2026-10-29, after 79ace754; the report's "The review", sill-handoff's
  `triage/2026-10-20-reports/verdicts-2026-10-29/key-repeat-letters-report.md`). A letter typed or a Delete
  (a key held a tenth of a second) whose up a stalled link held back more than 0.4 s was typed again one to
  three times when a ping had come during the press, the host repeating while the device was heard in the
  last half second: on loopback against a synthetic host with a stand-in device (letters at nine phases of
  the pings, the up and what followed it held back), 12 of 27 at 0.45, 0.6 and 1 s, the four phases with a
  ping in the press. Now a key's first repeat waits for a word heard after the press and no earlier than
  `KeyRepeat.firstWord` (0.3 s) before it is due (0288e6cb): none of 45, a key held still first repeated at
  0.50 s; key-repeat 114 checks (8 new) and 42 of 42 mutants (5 new). Kept from an earlier attempt at the
  review, stopped at the usage limit: iPadOS's ⌃Space switch (two languages) let the keys held on the Mac go
  on repeating, as ⌃P, so they now come up at the Space (fbcf4b69, `ForwardedKeys.keyboardSwitch`; key-strokes
  450 and 118 of 118), and the Mac's `keyRepeat` is read in one checked place (a66a7fbc, `KeyTyping.macRepeats`;
  text-composition 194 and 105 of 105). The switch's DEBUG note is made only in Debug (f7374b10). For Noah: a
  key held and let go during a stall repeats on for up to half a second (measured: 3, 6, 8 and 11 more for an
  up held back 0.1, 0.2, 0.3 and 0.6 s), as the arrows always did, now Delete too; with two Latin keyboards
  ⌃Space stays the iPad's though the Mac types; a hardware letter ends what dictation can revise. run-all.sh
  57 of 57 (55 one at a time on 0288e6cb, key-strokes and text-composition with their mutants); CI green on
  0288e6cb and f7374b10. No simulator this time (the free disk stayed under the rules' 25 GB, other sessions'
  work): each of the first run's live runs replayed against the final host, its device events as its app logged
  them put through the real `ForwardedKeys`, gave the first run's numbers (P held 55 repeats, E 85, ⇧A 40 and 40,
  Delete 55, Space 56, Caps Lock's A 25 with caps lock and shift, ⌘Z 25, Esc 25, each first at 0.49 to 0.51 s).
- sillclient.py: `--key=USAGE,HOLD@T` (a key held, pinging four a second meanwhile, as a device) and
  `--ping=S`.
- Defaults taken (docs/hardware-keyboard-plan.md, open question 12): modifiers mid-hold change the
  repeats, never stop them; the silence pause; the floors; the accessibility-size taps. Known: while
  iPadOS types the characters, ⇧ let go while a hardware ⇧→ is held keeps selecting until → comes up (the
  text system keeps ⇧'s own key; while the Mac types them, ⇧ is a key it hears).
- Verified: `key-repeat` 100 checks (2,400 random sessions, 600 held to the exact cadence) and 36 of 36
  mutants (in CI's matrix); `key-strokes` 385 (32 new) and 99 of 99 (16 new, two retargeted to `press`'s
  new body); `run-all.sh`, all 56; `swift build -c release`, only the CaptureProbe warning; the iOS app
  Debug and Release for the simulator and Debug for a device, only the known StreamClient warning
  (StreamClient.swift:4110); H2 against origin/main's CLI from `git archive`: idle identical masked and
  sorted, with a client identical but for which seconds count the software encoder's
  `enc.mailboxDrop`; live on loopback synthetic hosts with the input log, eleven runs: ← held 1.2 s
  (the down, 21 repeats from 0.48 s at 29.7 a second, the up), a tap and a 0.3 s hold (none), ⌥←
  with ⌥ let go mid-hold (option, then none), ⇧ pressed mid-hold (shift, then none), ⌘Z (command),
  → over ← (← stops, → repeats), text (stops), pings stopped (repeats end half a second after the
  last), the client leaving (its key up, nothing after), a pick of none (stops; the up still goes),
  Esc. Not run: the key row's caps pressed on a screen. A scratch rig (the cap's SwiftUI Button and
  HeldCapStyle with HeldCap, pressed by Tests/touchrig's TouchSynth on a private iOS 27.0 simulator,
  deleted after) reached no SwiftUI control at all, through `sendEvent` or UIKit's HID entry point (iOS
  27 has no `UITouch setGestureView:`), so the press's report is untested; if SwiftUI never reports it
  the caps are taps as before, and a missed end is ended by the action.
- **Untested, for Noah** (a Mac build of this branch and the iPad with a Magic Keyboard): hold ←, →,
  ⌥←, ⌘→, Forward Delete and ⌘Z in TextEdit and a terminal: the first repeat after this Mac's delay
  and then at its rate, as the Mac's own keyboard (System Settings › Keyboard changes both), and
  nothing after the release; ⇧ pressed while → repeats selects; letters held repeat at iPadOS's own
  rate as before; Esc held in vim. Upright on the iPad mini and iPhone, hold the key row's esc, tab
  and arrows (repeats until the finger lifts; with ⌥ latched, word jumps), slide off a cap (it stops),
  turn the device while holding one (it stops), VoiceOver's double tap (one press), an accessibility
  text size's long press on esc (the large cap, one Esc). Wi-Fi off while holding a key: the repeats
  stop within about half a second. Sill.log's `[1s]` lines count `in.keyRepeat`.
