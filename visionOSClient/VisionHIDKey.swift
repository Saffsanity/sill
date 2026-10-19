import Foundation

// Same US shortcut key mapping as the iPad portrait keyboard; other composed text stays Unicode.
enum VisionHIDKey {
    static let escape: UInt16 = 0x29
    static let tab: UInt16 = 0x2B
    static let deleteBackward: UInt16 = 0x2A
    static let rightArrow: UInt16 = 0x4F
    static let leftArrow: UInt16 = 0x50
    static let downArrow: UInt16 = 0x51
    static let upArrow: UInt16 = 0x52

    /// US-layout character → HID usage. Shortcuts are named by the unshifted key (⌘⇧S is the S
    /// key with two modifiers), so the character is lowercased first. Returns nil for anything
    /// outside the table — accented letters, emoji, IME output — which stays on the text path.
    static func usage(for character: Character) -> UInt16? {
        let lowered = character.lowercased()
        guard lowered.count == 1, let ascii = lowered.first?.asciiValue else { return nil }
        switch ascii {
        case 0x61...0x7A: return 0x04 + UInt16(ascii - 0x61)   // a–z
        case 0x31...0x39: return 0x1E + UInt16(ascii - 0x31)   // 1–9
        case 0x30: return 0x27                                  // 0
        case 0x20: return 0x2C                                  // space
        case 0x0A, 0x0D: return 0x28                            // return
        case 0x09: return tab
        case 0x08: return deleteBackward
        case 0x2D: return 0x2D                                  // -
        case 0x3D: return 0x2E                                  // =
        case 0x5B: return 0x2F                                  // [
        case 0x5D: return 0x30                                  // ]
        case 0x5C: return 0x31                                  // \
        case 0x3B: return 0x33                                  // ;
        case 0x27: return 0x34                                  // '
        case 0x60: return 0x35                                  // `
        case 0x2C: return 0x36                                  // ,
        case 0x2E: return 0x37                                  // .
        case 0x2F: return 0x38                                  // /
        default: return nil
        }
    }
}
