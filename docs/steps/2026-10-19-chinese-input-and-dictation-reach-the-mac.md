**Chinese input and dictation reach the Mac (2026-10-19 to 27, PR #147 from cinminori's `zhuyin-input`,
finished on it, with main at 76bc100 in it; issue #138).** Noah: "Chinese input and dictation if polished
then merge (detects user language set in iOS settings). Once testflight is enabled, ask users to test."
Device only: no wire change, nothing on the Mac, no Sill setting: the keyboards and dictation languages
set up in the device's Settings decide.
- The PR (kept): the stream's input view (`InputOverlayView`) is a `UITextInput`, not only a
  `UIKeyInput`, so an input method's composition (Zhuyin, Pinyin, Japanese…) stays on the device, drawn
  at the top middle of the picture, and only what is chosen goes to the Mac as text; dictation's text and
  its corrections go as backspaces back to the first difference, then the rest typed; while it composes
  every key is the input method's (pressesBegan hands them all on; Esc's key commands stand down, and a
  shortcut such as ⌘S goes to it too); spell checking and inline predictions off.
- The triage's four changes (2026-10-19), in commits of their own: ⌃Space is iPadOS's switch only
  with keyboards in two languages or more (`TextInputRules.isKeyboardSwitch`: Emoji and dictation aside, a
  language counted once, judged at the press; ⌃⇧, ⌃⌥ and ⌃⌘Space always the Mac's), else the Mac's as on
  main (the PR gave every ⌃Space to iPadOS); Scribble declined (a `UIScribbleInteraction` refusing every
  start: the Pencil is the Mac's mouse); the dictation tail: what was typed kept whole while the text
  system may revise it (the PR cut it to 200 characters inside every edit, unseen by the text system, so a
  correction past 200 landed at the end and typed its words twice), trimmed past 4,000 to the last 1,000
  between edits with the text system told, forgotten wherever the Mac's caret may move (a click or a key
  from any view, a pick, a launch, a window's button, a menu item, a gesture:
  `StreamClient.onCaretMayMove`, before it goes out, the pick and the rest now behind queued input,
  `sendAfterInput`), a correction taken before a forget or a trim sending nothing (`generation`), and a
  composition still in progress then, or when the input view resigns or leaves its window, sent first, as
  it stands; and mutants for its check.
- Also: Korean (2-Set selects the syllables it rebuilds and types them again: `TextComposition.selection`;
  한글 reached a simulator Mac as 한한한글 before); VoiceOver (the input view stays no element); Writing
  Tools, math results and grammar checking off; Debug `textinput:` lines; #110's latched-shift Return and
  Tab behind `!composition.isComposing` (Noah's conflict comment). Docs: docs/DEVELOPMENT.md, "Other
  languages and dictation"; README's How it works; site/support.html's paragraph inside `<!-- Other
  languages` markers (docs/release-checklist.md part 1 §3's perl line); the next What's New
  (docs/app-store-metadata.md); docs/hardware-keyboard-plan.md's item 11 answered.
- The verification (2026-10-26, fix-first: sill-handoff's
  `triage/2026-10-20-reports/verdicts-2026-10-26/pr147-verdict.md`), one commit per theme: a Return or a
  Tab typed as text ("\n", "\r" or "\t", alone or anywhere in it: a hardware one without shift, the
  on-screen return key, dictation's "new line") counted as the Mac's caret moving
  (`TextInputRules.movesCaret`, `carriesReturnOrTab`): it went whole, then all of what was typed was
  forgotten (`onCaretMayMove`, `forgetTyped`, the text system told), so a correction dictation made later
  of the phrase before it, taken before it, sent nothing (it sent 15 backspaces and "Send the build.\n":
  the message sent twice, the command run twice), a forget the second verification replaced with the
  fence (below); a finger's tap or long press on the letterbox mid-composition sends nothing (its forget after the guard
  that drops it, as touchesBegan's, where it sent the composition as it stood with no click);
  and DEVELOPMENT.md says the keyboard's name shows over the picture at any switch while the input view
  holds the keyboard, the on-screen keyboard's Globe key included (`inputModeChanged`), not only with a
  hardware keyboard.
- Verified (2026-10-26, on the tree merged with main at 36e7212): `Tests/checks/text-composition` 99
  checks and 60 of 60 mutants (in CI's matrix; 119 and 65 of 65 since the verification's fix, above);
  key-strokes 353; `swift build -c release`; the iOS app
  Debug and Release for the simulator and Debug for a device, only the known StreamClient capture
  warning; the touch rig, 72 scenarios; a private iPad simulator (iOS 27.0) against a loopback synthetic
  host (software encoder, `SILL_TEST_INPUT_LOG`, a scripted pointer), keys from `Tests/keyrig`: Zhuyin
  (ㄋㄧˇㄏㄠˇ, Return), Pinyin (nihao, Space), Japanese (nihonn, Return) and Korean (2-Set's g k s r m f)
  each reached the host once (你好, 你好, 日本, 한글); a scripted tap mid-composition sent 好 first, then
  the click; ⌃Space stayed on the device with keyboards in two languages and reached the host (key 49
  with control) with one; letters as text, ⌘S and Esc as keys, ⌘S mid-composition nowhere;
  `-SillInputTest 1` as before. The simulator takes a language's keyboards from `-AppleLanguages` and
  `-AppleLocale`, not from its `AppleKeyboards` preference.
- Verified after the verification's fixes (2026-10-26, on the tree merged with main at c215514, #159):
  text-composition 119 checks and 65 of 65 mutants; key-strokes 353; `run-all.sh`, all 49; the iOS app
  Debug and Release for the simulator and Debug for a device on Xcode 27.1, only the known StreamClient
  capture warning; the touch rig 72 of 72 against main's; a private iPad simulator (iOS 27.0) against a
  loopback synthetic host, keys from `Tests/keyrig`, the device's bytes recorded by `sillrelay.py`:
  "send the build", Return, "ok", Backspace, ⌘S and Esc went as the 14 letters, "\n" (then "forgot the
  15 characters typed"), "o", "k", one backspace, ⌘S's keys and Esc's; `-SillInputTest 1` as before;
  mid-composition (Zhuyin's 你) a scripted tap on the letterbox sent nothing, one on the picture the
  move, 你, then the click; with an uncommitted DEBUG step standing in for dictation (`insertText`,
  then `replace` with the range it held), a correction after a hardware Return sent nothing (2dc6c75's
  build with the same step: 15 backspaces and "Send the build.\n") and one with no Return went as before.
- The second verification (2026-10-26, fix-first: `pr147-verdict-2.md` beside it): forgetting at a typed
  Return was wrong for dictation's own "new line" said mid-utterance. The document empty after it, the
  phrase's last pass through the range from where it began (offset 0, never past an empty document's
  end, so not stale) was typed again at the caret, Return included (the Mac with the phrase twice, a
  chat a second, garbled message), and in other models of how iPadOS sends the rest of an utterance the
  words after the Return never arrived, or went three times (the verifier's harness, S1–S12). Now the
  fence (`TextComposition.fence`): a Return or a Tab typed as text keeps the document and its
  generation, goes whole, and makes what was sent up to just after its last Return or Tab final; a
  correction whose first change falls before it sends nothing (`refusal`'s `.final`), wherever its
  range starts, so an utterance sent again whole from its start that only adds words after the Return
  goes; a selection wholly before it is not kept, so the next edit goes at the end ("send the bill⏎ok"
  typed, "bill" selected, then "build": "okbuild" on the new line; select, backspace and "build", as
  Korean rebuilds: "obuild", the backspace deleting the last character; acceptable, as no input method
  has been seen selecting wholly before a Return: Korean's selections cross it, the person's backspace
  selects one character); an edit's backspaces stop at it (the difference looked for after it, so a CR
  and an LF typed later cost no backspace over the CR); the person's own backspace (text, from the
  on-screen keyboard and from a hardware one without ⌘, ⌃ or ⌥) goes back across it and takes it back to
  what is left, which stays final; a second Return moves it to just after itself; a forget puts it at 0
  and a trim moves it with the text it keeps (to 0 when the cut passes it); a composition follows what
  was sent, after it; the 4,000-character cap stays, reached across Returns now.
  `TextInputRules.movesCaret` is false for all text again (`endOfReturnOrTab` says where the fence
  goes); clicks, keys (⇧Return and ⇧Tab among them), picks, gestures and menu items keep the full
  forget. Decided here: the fence goes just after the last Return or Tab, not at the end of the text
  that brought it (the verifier's variant), as what follows the Return went where the caret went: the
  verifier's own text with only "deploy it " corrected after is sent, and a hypothesis that revises a
  word after the Return as it adds more keeps its new words (the harness's S13: the variant lost " it").
  Known (the third verification, 2026-10-27: `pr147-verdict-3.md` beside it): a correction that changes
  the line before a Return sends nothing, the words it adds after the Return with it, and dictation that
  sends its whole utterance again with each update carries a word revised there into every later update,
  each sending nothing too, so the rest of the utterance never reaches the Mac (the verifier's harness:
  "send the bill", "send the bill⏎deploy", "send the build⏎deploy it", "send the build⏎deploy it now",
  "Send the build.⏎Deploy it now." leave it "send the bill⏎deploy", " it now" never arriving, in an
  editor too). Nothing is sent twice, and where new words come at the caret and each revision is a
  replace of its own, every word arrives (the revision left out). The testers' "new line" step would
  show which way iPadOS goes; a possible follow-up applies such an update's text after its k-th Return
  or Tab (k: the Returns and Tabs in what is final) instead of refusing it whole. Docs: DEVELOPMENT.md's
  "Other languages and dictation" (the fence, and plainly: after a click, a key or a pick a correction
  through a range built again from offsets kept, starting where what was typed began, is typed again at
  the caret, as before; after a Return or a Tab it sends nothing), the checks README. Found live and
  fixed in a commit of its own: Korean's 2-Set rebuilds the character before its syllable together with
  it, so right after a Return it selected "\nㅎ", deleted it and typed "\n" and "하" again, and with that
  selection refused (the verifier's variant did the same: its harness's S18) the Mac got a second Return
  at each of the first syllable's letters. A selection that reaches back across the fence from after it
  is now kept: its deletion deletes only what follows the fence and leaves the rest in place as
  `retype`, which the text typed next does not type again (in pieces too; text that starts otherwise
  would change what is final, and sends nothing, so "\nㅎ" selected and deleted, then "하" typed alone,
  loses the syllable: check J4, a nit of the third verification's, which Korean did not do live; a new
  selection, or any other edit, ends it); text typed over it goes only while it keeps what is final; a
  composition over it deletes only after the fence, nothing held back; one wholly before the fence is
  still not kept (the text system selects the character a backspace deletes, so the person's backspace
  right after a Return deletes that Return). Telling the text system at a Return (an experiment) did not
  change what the input method selects.
- Verified after the second verification's fix (2026-10-27, on 3187d56, the tree with main at c215514 in
  it): text-composition 178 checks and 87 of 87 mutants (F1–F14 the fence's, J1–J8 the crossing
  selection's; in CI's matrix); the verifier's harness, S1–S12, against its fence variant: the same output
  in every scenario; five more (S13–S17) where the two differ only in S13 and S14 (the variant drops the
  words a hypothesis adds as it revises one after the Return, and a correction of only the words after the
  Return in the same text), and S18, Korean's rebuild across a Return, where the variant sends a second
  Return at each letter and this rule none; key-strokes 353; `swift build -c release` from `git archive`
  (only the CaptureProbe warning); the iOS app Debug and Release for the simulator and Debug for a device
  on Xcode 27.1, only the known StreamClient capture warning; the touch rig 72 of 72 against main's
  (74d099c); a private iPad simulator (iOS 27.0) against a loopback synthetic host (software encoder, no
  router, no ScreenCaptureKit, `SILL_TEST_INPUT_LOG`, a scripted pointer), keys from `Tests/keyrig`, the
  device's bytes recorded by `sillrelay.py`: with an uncommitted DEBUG step standing in for dictation
  (`insertText`, then `replace` through the range from where the text began), "send the build", the
  hardware Return's "\n", nothing for the phrase's correction after it, "send the build\ndeploy it "
  whole, nothing for its whole-phrase pass, 10 backspaces and "Deploy it. " for the words after its
  Return, "hello there" corrected as before; a b c Return d e f as letters and one "\n"; ⌘S and Esc as
  keys; Korean 2-Set's 한글⏎한글⏎한 once (before the crossing fix 한글⏎⏎⏎한글⏎); Zhuyin's ㄋㄧˇ⏎⏎ㄋㄧˇ⏎⏎
  as 你⏎你⏎ once; a Backspace right after a Return deleted that Return; `-SillInputTest 1` as before.
- **Untested, for Noah and #138's testers (TestFlight):** Zhuyin and Pinyin on the on-screen keyboard and
  on a Magic Keyboard (the candidates beside the composition), Japanese, Korean, dictation in Chinese and
  in English with its corrections and punctuation (nothing typed twice), Return right after dictating in
  Messages, Slack or Terminal (the line goes once), dictation with "new line" said in the middle of a
  sentence, talking on, in TextEdit and in Messages or Slack, in English and in Chinese (every word
  arrives once, nothing is sent twice), ⌃Space with one keyboard and
  with two, the Globe key, Caps Lock's switch to and from ABC, a tap mid-composition, a shortcut
  mid-composition, an Apple Pencil over the picture (no handwriting), VoiceOver.
  If dictation corrects a word before the "new line" while you keep talking, the words after it may not
  reach the Mac; nothing is sent twice either way. Say which words were missing and in which app.
