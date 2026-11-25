**Text typed into Parallels Desktop as real keys (2026-11-26, branch `keycode-typing-for-vms` from main at 22ab5a3).**

What: typing on the device's keyboard into a Parallels Desktop VM window gave "aaaa" in English and
"ㅁㅁㅁㅁ" with the guest's Korean input method on. `InputInjector.type` posts each character as
virtual key 0 with the character as its Unicode string; Mac apps read the string, but Parallels (like
other VMs and remote desktops) passes the guest only the key, and key 0 is the A key (ㅁ on 2-set).

The fix (`Sources/SillHost/KeycodeTyping.swift`, pure, `Tests/checks/keycode-typing`): when the app in
front is one known to read keys (`KeycodeTyping.keyCodeApps`: Parallels' two bundle ids, VMware
Fusion, UTM, Windows App), each character goes as the US key that types it, shift's own key around it
when needed, its Unicode string kept for the app's own fields; space as key 49. Hangul goes as the
2-set keys of its letters, for the guest's own Korean input method to compose. The device's Korean
keyboard rebuilds a syllable as it grows (backspace then the syllable again; TextComposition), which
would make the guest compose 한한그, so `HangulRun` holds a backspace inside a Hangul run until the
text after it (0.25 s at most) and sends only the difference in keys. An event's Hangul goes together.
Any input but text or a pointer move ends the run. Every other app is typed into exactly as before.

Decisions: the app list is by bundle id rather than switching every app to keys, as keys would go
through the Mac's own input method (a Korean input source on the Mac would compose them). The guest's
layout is assumed to be US/2-set; another guest layout gets the key in the US place, as a plugged-in
keyboard would.

Verified: `swift build -c release`, `Tests/checks/keycode-typing` (48 checks), `Tests/checks/repo-rules`.
Untested for Noah: on a real Parallels VM (Windows and macOS guests), English, Korean with the guest's
IME on, shifted symbols; whether Parallels needs shift's flagsChanged (posted) or reads the flag; the
guest's backspace behaviour after its composing syllable is deleted (the model assumes the syllable
before is committed, deleted whole); a Korean input source on the Mac while Parallels is in front.
SILL_TEST_KEYCODE_TYPING=1 forces the path on a synthetic host for the input log.
