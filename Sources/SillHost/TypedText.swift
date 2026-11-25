import Foundation

// Decomposition of typed `.text` payloads into the keyboard events InputInjector posts on the Mac.
//
// In Swift, "\r\n" (CRLF) is a single extended grapheme cluster (`Character`), so switching on
// `Character` against "\n" alone missed both "\r" (sent by third-party iOS keyboards such as Hamster)
// and "\r\n", posting them as virtual key 0 with control scalars instead of the Return key while
// `TextInputRules.endOfReturnOrTab` had already treated them as Returns. Matching each `Character`
// keeps emoji, skin tones and combining sequences together for `keyboardSetUnicodeString`, while
// turning all three ASCII line breaks ("\n", "\r" and "\r\n") into one Return each.
//
// Pure: Foundation only, checked standalone by `Tests/checks/typed-text`.

package enum TypedText {
    package enum Step: Equatable, Sendable {
        case returnKey
        case tabKey
        case backspaceKey
        case unicode([UInt16])
    }

    package static func step(for character: Character) -> Step {
        switch character {
        case "\n", "\r", "\r\n":
            return .returnKey
        case "\t":
            return .tabKey
        case "\u{8}":
            return .backspaceKey
        default:
            return .unicode(Array(character.utf16))
        }
    }

    package static func steps(for string: String) -> [Step] {
        string.map(step(for:))
    }
}
