# `keycode-typing`

**Checks:** the keys an app that reads only a key event's virtual key (Parallels Desktop, VMware Fusion, UTM, Windows App) is sent for a device's text (2026-11-26, branch `keycode-typing-for-vms`), where every character had reached the guest as key 0, the A key: each printable ASCII character's US key and shift, Hangul syllables' and letters' 2-set keys, which apps read keys; and `HangulRun` against a model of the guest's 2-set input method: the device's Korean keyboard rebuilding each syllable (ㅎ, 하, 한, 한ㄱ, 한그, 글) sends only the new keys, a final consonant moving on (하나) likewise, a backspace inside the composing syllable one key, a backspace nothing follows waiting and then going, a deletion into a committed character, and the run's end

**Compiles:** `Sources/SillHost/KeycodeTyping.swift` (`-package-name sill`)
