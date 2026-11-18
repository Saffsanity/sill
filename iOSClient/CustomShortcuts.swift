import Foundation
import StreamProtocol

/// State of a modifier key: Off, Latched (applies to next non-modifier key press, then clears), or Locked (persists).
enum ModifierKeyState: Equatable {
    case off
    case latched
    case locked

    var isActive: Bool { self != .off }
}

/// Model managing modifier keys for the built-in multi-touch keyboard and accessory bar.
final class VirtualKeyboardModifierState: ObservableObject {
    @Published var control: ModifierKeyState = .off
    @Published var option: ModifierKeyState = .off
    @Published var command: ModifierKeyState = .off
    @Published var shift: ModifierKeyState = .off

    init() {}

    /// Combines active latched and locked modifiers into a KeyModifiers bitmask.
    var activeModifiers: KeyModifiers {
        var mods: KeyModifiers = []
        if control.isActive { mods.insert(.control) }
        if option.isActive  { mods.insert(.option) }
        if command.isActive { mods.insert(.command) }
        if shift.isActive   { mods.insert(.shift) }
        return mods
    }

    /// Cycles modifier state: off -> latched -> locked -> off.
    func cycle(_ flag: KeyModifiers) {
        if flag.contains(.control) { control = nextState(control) }
        if flag.contains(.option)  { option  = nextState(option) }
        if flag.contains(.command) { command = nextState(command) }
        if flag.contains(.shift)   { shift   = nextState(shift) }
    }

    /// Explicitly sets state.
    func set(_ flag: KeyModifiers, to state: ModifierKeyState) {
        if flag.contains(.control) { control = state }
        if flag.contains(.option)  { option  = state }
        if flag.contains(.command) { command = state }
        if flag.contains(.shift)   { shift   = state }
    }

    /// Called after a regular key is pressed: resets any latched modifier back to off (locked modifiers stay locked).
    func consumeLatched() {
        if control == .latched { control = .off }
        if option  == .latched { option  = .off }
        if command == .latched { command = .off }
        if shift   == .latched { shift   = .off }
    }

    /// Clears all modifiers.
    func clearAll() {
        control = .off
        option = .off
        command = .off
        shift = .off
    }

    private func nextState(_ current: ModifierKeyState) -> ModifierKeyState {
        switch current {
        case .off: return .latched
        case .latched: return .locked
        case .locked: return .off
        }
    }
}

/// A custom shortcut key combination that sends keyboard HID events to the Mac.
struct CustomShortcut: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var symbol: String?
    var modifiers: UInt64
    var hidUsage: UInt16
    var keyLabel: String

    init(id: UUID = UUID(), title: String, symbol: String? = nil, modifiers: UInt64 = 0, hidUsage: UInt16, keyLabel: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.modifiers = modifiers
        self.hidUsage = hidUsage
        self.keyLabel = keyLabel
    }

    /// Formatted display string of modifiers + key label, e.g. "⌃⌘X" or "⌘Z".
    var comboDisplay: String {
        var str = ""
        let mods = KeyModifiers(rawValue: modifiers)
        if mods.contains(.control) { str += "⌃" }
        if mods.contains(.option)  { str += "⌥" }
        if mods.contains(.shift)   { str += "⇧" }
        if mods.contains(.command) { str += "⌘" }
        str += keyLabel
        return str
    }

    /// Converts this shortcut into a list of InputEvents (press modifiers + key down + key up + modifiers up).
    func makeEvents() -> [InputEvent] {
        let mods = KeyModifiers(rawValue: modifiers)
        return KeyChord.press(hidUsage, with: mods)
    }
}

/// Available keys for custom shortcut creation.
struct ShortcutKeyOption: Identifiable, Hashable {
    let id: UInt16
    let hidUsage: UInt16
    let label: String

    init(hidUsage: UInt16, label: String) {
        self.id = hidUsage
        self.hidUsage = hidUsage
        self.label = label
    }

    /// Common shortcut key choices.
    static let allOptions: [ShortcutKeyOption] = {
        var list: [ShortcutKeyOption] = []
        // Letters A-Z
        for charCode in UInt8(ascii: "A")...UInt8(ascii: "Z") {
            let letter = String(UnicodeScalar(charCode))
            let usage = 0x04 + UInt16(charCode - UInt8(ascii: "A"))
            list.append(ShortcutKeyOption(hidUsage: usage, label: letter))
        }
        // Numbers 0-9
        for n in 1...9 {
            list.append(ShortcutKeyOption(hidUsage: 0x1E + UInt16(n - 1), label: "\(n)"))
        }
        list.append(ShortcutKeyOption(hidUsage: 0x27, label: "0"))

        // Special common keys
        list.append(ShortcutKeyOption(hidUsage: 0x2C, label: "Space"))
        list.append(ShortcutKeyOption(hidUsage: 0x28, label: "Return"))
        list.append(ShortcutKeyOption(hidUsage: 0x2A, label: "Delete"))
        list.append(ShortcutKeyOption(hidUsage: 0x29, label: "Esc"))
        list.append(ShortcutKeyOption(hidUsage: 0x2B, label: "Tab"))
        list.append(ShortcutKeyOption(hidUsage: 0x4F, label: "→"))
        list.append(ShortcutKeyOption(hidUsage: 0x50, label: "←"))
        list.append(ShortcutKeyOption(hidUsage: 0x51, label: "↓"))
        list.append(ShortcutKeyOption(hidUsage: 0x52, label: "↑"))
        list.append(ShortcutKeyOption(hidUsage: 0x2D, label: "-"))
        list.append(ShortcutKeyOption(hidUsage: 0x2E, label: "="))
        list.append(ShortcutKeyOption(hidUsage: 0x2F, label: "["))
        list.append(ShortcutKeyOption(hidUsage: 0x30, label: "]"))
        list.append(ShortcutKeyOption(hidUsage: 0x31, label: "\\"))
        list.append(ShortcutKeyOption(hidUsage: 0x33, label: ";"))
        list.append(ShortcutKeyOption(hidUsage: 0x34, label: "'"))
        list.append(ShortcutKeyOption(hidUsage: 0x36, label: ","))
        list.append(ShortcutKeyOption(hidUsage: 0x37, label: "."))
        list.append(ShortcutKeyOption(hidUsage: 0x38, label: "/"))

        // F1-F12
        for f in 1...12 {
            list.append(ShortcutKeyOption(hidUsage: 0x3A + UInt16(f - 1), label: "F\(f)"))
        }
        return list
    }()
}

/// Store and persistence for custom shortcuts.
final class CustomShortcutStore: ObservableObject {
    static let shared = CustomShortcutStore()
    private let storageKey = "SillCustomShortcuts_v1"

    @Published var shortcuts: [CustomShortcut] = []

    init() {
        loadShortcuts()
    }

    static let defaultPresets: [CustomShortcut] = [
        CustomShortcut(title: "Undo", symbol: "arrow.uturn.backward", modifiers: KeyModifiers.command.rawValue, hidUsage: 0x1D, keyLabel: "Z"),
        CustomShortcut(title: "Redo", symbol: "arrow.uturn.forward", modifiers: KeyModifiers.command.rawValue | KeyModifiers.shift.rawValue, hidUsage: 0x1D, keyLabel: "Z"),
        CustomShortcut(title: "Save", symbol: "square.and.arrow.down", modifiers: KeyModifiers.command.rawValue, hidUsage: 0x16, keyLabel: "S"),
        CustomShortcut(title: "Hand", symbol: "hand.raised", modifiers: 0, hidUsage: 0x2C, keyLabel: "Space"),
        CustomShortcut(title: "Copy", symbol: "doc.on.doc", modifiers: KeyModifiers.command.rawValue, hidUsage: 0x06, keyLabel: "C"),
        CustomShortcut(title: "Paste", symbol: "doc.on.clipboard", modifiers: KeyModifiers.command.rawValue, hidUsage: 0x19, keyLabel: "V"),
        CustomShortcut(title: "Cut", symbol: "scissors", modifiers: KeyModifiers.command.rawValue, hidUsage: 0x1B, keyLabel: "X"),
        CustomShortcut(title: "Brush", symbol: "paintbrush", modifiers: 0, hidUsage: 0x05, keyLabel: "B"),
        CustomShortcut(title: "Eraser", symbol: "eraser", modifiers: 0, hidUsage: 0x08, keyLabel: "E")
    ]

    func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CustomShortcut].self, from: data),
           !decoded.isEmpty {
            self.shortcuts = decoded
        } else {
            self.shortcuts = Self.defaultPresets
        }
    }

    func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func add(title: String, symbol: String? = nil, modifiers: UInt64, hidUsage: UInt16, keyLabel: String) {
        let item = CustomShortcut(title: title.isEmpty ? keyLabel : title, symbol: symbol, modifiers: modifiers, hidUsage: hidUsage, keyLabel: keyLabel)
        shortcuts.append(item)
        saveShortcuts()
    }

    func remove(at index: Int) {
        guard index >= 0 && index < shortcuts.count else { return }
        shortcuts.remove(at: index)
        saveShortcuts()
    }

    func remove(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        saveShortcuts()
    }

    func resetToDefaults() {
        shortcuts = Self.defaultPresets
        saveShortcuts()
    }
}
