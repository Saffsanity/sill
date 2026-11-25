import Foundation

// Typed text as real keys, for the apps that read only a key event's virtual key (#keycode-typing).
//
// InputInjector types a device's text as virtual key 0 with the character as the event's Unicode
// string, which every Mac app reads whatever the Mac's keyboard layout is. A virtual machine or a
// remote desktop does not: Parallels Desktop (and VMware Fusion, UTM, Windows App) hands the guest the
// key the event names and drops its string, so every character reached the guest as key 0, the A key:
// "aaaa" in English and "ㅁㅁㅁㅁ" with the guest's Korean input method on (2026-11-26).
//
// For those apps (`readsKeyCodes`) each character goes as the key that types it on a US keyboard,
// with shift when it needs it (`strokes`): what the guest's own layout and input method then make of
// it is the guest's, as with a keyboard plugged into it. A Hangul character goes as the keys of the
// 2-set (두벌식) Korean layout that type its letters, for the guest's Korean input method to put
// together; `HangulRun` keeps the guest's composition in step with the device's, whose Korean
// keyboard deletes and types each syllable again as it grows (ㅎ, then a backspace and 하, then a
// backspace and 한). A character with no key (an emoji, kana) still goes as before.
//
// Pure: Foundation only, checked on its own with swiftc (Tests/checks/keycode-typing).

enum KeycodeTyping {
    /// A key on the Mac: its virtual key (kVK_ANSI_*), and whether shift is down for it.
    struct Stroke: Equatable {
        var key: UInt16
        var shift: Bool
    }

    /// The apps known to read a key event's virtual key and not its Unicode string: virtual machines
    /// and remote desktops, which pass the key on to another system.
    static let keyCodeApps: Set<String> = [
        "com.parallels.desktop.console",    // Parallels Desktop's VM windows
        "com.parallels.desktop",
        "com.vmware.fusion",                // VMware Fusion
        "com.utmapp.UTM",                   // UTM
        "com.microsoft.rdc.macos",          // Windows App (Microsoft Remote Desktop)
    ]

    static func readsKeyCodes(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return keyCodeApps.contains(bundleID)
    }

    // MARK: A US keyboard

    /// Each printable ASCII character's key on a US (ANSI) keyboard, unshifted and shifted.
    private static let usKeys: [Character: Stroke] = {
        var map: [Character: Stroke] = [:]
        let rows: [(UInt16, Character, Character)] = [
            (0, "a", "A"), (1, "s", "S"), (2, "d", "D"), (3, "f", "F"), (4, "h", "H"), (5, "g", "G"),
            (6, "z", "Z"), (7, "x", "X"), (8, "c", "C"), (9, "v", "V"), (11, "b", "B"), (12, "q", "Q"),
            (13, "w", "W"), (14, "e", "E"), (15, "r", "R"), (16, "y", "Y"), (17, "t", "T"),
            (18, "1", "!"), (19, "2", "@"), (20, "3", "#"), (21, "4", "$"), (22, "6", "^"), (23, "5", "%"),
            (24, "=", "+"), (25, "9", "("), (26, "7", "&"), (27, "-", "_"), (28, "8", "*"), (29, "0", ")"),
            (30, "]", "}"), (31, "o", "O"), (32, "u", "U"), (33, "[", "{"), (34, "i", "I"), (35, "p", "P"),
            (37, "l", "L"), (38, "j", "J"), (39, "'", "\""), (40, "k", "K"), (41, ";", ":"),
            (42, "\\", "|"), (43, ",", "<"), (44, "/", "?"), (45, "n", "N"), (46, "m", "M"),
            (47, ".", ">"), (50, "`", "~"),
        ]
        for (key, plain, shifted) in rows {
            map[plain] = Stroke(key: key, shift: false)
            map[shifted] = Stroke(key: key, shift: true)
        }
        map[" "] = Stroke(key: 49, shift: false)
        return map
    }()

    // MARK: The 2-set Korean layout

    /// Each Hangul letter's keys on the 2-set layout, as the US keys in those places: a double letter
    /// (ㅘ, ㄺ) is its two letters' keys.
    private static let jamoKeys: [Character: String] = [
        "ㅂ": "q", "ㅈ": "w", "ㄷ": "e", "ㄱ": "r", "ㅅ": "t", "ㅛ": "y", "ㅕ": "u", "ㅑ": "i", "ㅐ": "o", "ㅔ": "p",
        "ㅁ": "a", "ㄴ": "s", "ㅇ": "d", "ㄹ": "f", "ㅎ": "g", "ㅗ": "h", "ㅓ": "j", "ㅏ": "k", "ㅣ": "l",
        "ㅋ": "z", "ㅌ": "x", "ㅊ": "c", "ㅍ": "v", "ㅠ": "b", "ㅜ": "n", "ㅡ": "m",
        "ㅃ": "Q", "ㅉ": "W", "ㄸ": "E", "ㄲ": "R", "ㅆ": "T", "ㅒ": "O", "ㅖ": "P",
        "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅢ": "ml",
        "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg", "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq", "ㄽ": "ft",
        "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg", "ㅄ": "qt",
    ]
    private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let medials = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let finals = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

    /// The 2-set keys of a Hangul syllable (가…힣) or letter (ㄱ…ㅣ), as US characters; nil for any
    /// other character.
    static func hangulKeys(_ character: Character) -> String? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        let value = scalar.value
        if (0xAC00...0xD7A3).contains(value) {
            let index = Int(value - 0xAC00)
            let l = index / 588, v = (index % 588) / 28, t = index % 28
            var keys = jamoKeys[initials[l]]! + jamoKeys[medials[v]]!
            if t > 0 { keys += jamoKeys[finals[t - 1]]! }
            return keys
        }
        return jamoKeys[character]
    }

    static func isHangul(_ character: Character) -> Bool { hangulKeys(character) != nil }

    /// The keys that type `character` for an app that reads keys: a US key, or a Hangul character's
    /// 2-set keys; nil when no key types it (it goes as its Unicode string, as for every other app).
    static func strokes(for character: Character) -> [Stroke]? {
        if let us = usKeys[character] { return [us] }
        guard let keys = hangulKeys(character) else { return nil }
        return keys.map { usKeys[$0]! }
    }
}

/// The run of Hangul typed into an app that reads keys, since anything else was: what the device
/// has typed of it, and so what the guest's Korean input method holds, its last syllable still being
/// composed. The device's Korean keyboard rebuilds a syllable as it grows (한 then ㄱ: 한ㄱ deleted and
/// 한그 typed), which a guest composing the letters itself must be sent only the new letters of, or it
/// would build 한한그. So a backspace inside the run waits (`backspace`), and what is typed next is
/// sent as the difference between the keys the guest has and those of the run as it now stands
/// (`type`); a backspace nothing follows goes on its own (`settle`).
///
/// How the guest deletes, assumed (the 2-set input methods of Windows and macOS): a backspace deletes
/// one letter key of the syllable being composed, and a whole character of those before it.
struct HangulRun: Equatable {
    /// What reaches the guest: a backspace, or a key.
    enum Action: Equatable {
        case backspace
        case stroke(KeycodeTyping.Stroke)
    }

    /// The device's Hangul since the run began, as it stands once the waiting backspaces are done.
    private(set) var run: [Character] = []
    /// Backspaces the device sent that are still waiting for what it types next.
    private(set) var waiting = 0

    var isEmpty: Bool { run.isEmpty && waiting == 0 }

    /// The device's backspace: true when it waits (the run holds a character it may be rebuilding),
    /// false when it goes now as a plain backspace (the run has nothing it would delete).
    mutating func backspace() -> Bool {
        guard waiting < run.count else { return false }
        waiting += 1
        return true
    }

    /// Hangul typed, all of one text event's together (the device's 한그 after deleting 한ㄱ is one
    /// event; taken a character at a time, its 한 would first delete the ㄱ): what the guest is sent
    /// to hold the run with them on the end.
    mutating func type(_ characters: [Character]) -> [Action] {
        move(to: Array(run.dropLast(waiting)) + characters)
    }

    /// Nothing more follows the waiting backspaces (a moment passed, or something other than Hangul
    /// comes): what the guest is sent to delete what they delete.
    mutating func settle() -> [Action] {
        guard waiting > 0 else { return [] }
        return move(to: Array(run.dropLast(waiting)))
    }

    /// The run ends: the guest's input method has committed it (a space, a key, a click). The waiting
    /// backspaces go first.
    mutating func end() -> [Action] {
        let out = settle()
        run = []
        return out
    }

    private static func keys(_ characters: [Character]) -> [[KeycodeTyping.Stroke]] {
        characters.map { KeycodeTyping.strokes(for: $0) ?? [] }
    }

    /// From the run the guest holds to `target`: back to where their keys first differ, then the rest.
    /// Inside the last character (the one being composed) a backspace takes one key; before it, the
    /// guest has committed each character, and a backspace takes a whole one, which is typed again.
    private mutating func move(to target: [Character]) -> [Action] {
        let old = Self.keys(run), new = Self.keys(target)
        let oldFlat = old.flatMap { $0 }, newFlat = new.flatMap { $0 }
        var common = 0
        while common < oldFlat.count, common < newFlat.count, oldFlat[common] == newFlat[common] { common += 1 }
        var out: [Action] = []
        var keep = common
        if common < oldFlat.count {
            let lastStart = oldFlat.count - (old.last?.count ?? 0)
            if common >= lastStart {
                out += Array(repeating: .backspace, count: oldFlat.count - common)
            } else {
                // Back into the committed characters: the composed one letter by letter, then each
                // committed one whole, back to the start of the one where the keys first differ.
                out += Array(repeating: .backspace, count: old.last?.count ?? 0)
                var start = 0, index = 0
                while index < old.count - 1, start + old[index].count <= common { start += old[index].count; index += 1 }
                out += Array(repeating: .backspace, count: old.count - 1 - index)
                keep = start
            }
        }
        out += newFlat[keep...].map { .stroke($0) }
        run = target
        waiting = 0
        return out
    }
}
