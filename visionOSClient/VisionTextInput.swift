import Foundation
import StreamProtocol

/// Match the iPad's exclusive composed-text/latched-shortcut paths; never send both for one input.
enum VisionTextInput {
    static func events(_ text: String, modifiers: KeyModifiers) -> [InputEvent] {
        if !modifiers.isDisjoint(with: .shortcutMakers), text.count == 1,
           let character = text.first, let usage = VisionHIDKey.usage(for: character) {
            return KeyChord.press(usage, with: modifiers)
        }
        return [.text(text)]
    }
}
