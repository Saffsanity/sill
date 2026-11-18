import SwiftUI
import StreamProtocol

/// The bottom shortcut bar, anchored at the very bottom of the streaming screen,
/// offering quick access to common combinations (Undo, Redo, Save, Copy, Paste, etc.)
/// and custom user-defined shortcuts.
struct BottomShortcutBar: View {
    @ObservedObject var shortcutStore = CustomShortcutStore.shared
    @Binding var isNativeKeyboardShown: Bool
    let sendInput: (InputEvent) -> Void
    let toggleNativeKeyboard: () -> Void

    @State private var isCollapsed = false
    @State private var showingAddSheet = false
    @State private var pressedShortcutID: UUID? = nil

    init(isNativeKeyboardShown: Binding<Bool>,
         sendInput: @escaping (InputEvent) -> Void,
         toggleNativeKeyboard: @escaping () -> Void) {
        self._isNativeKeyboardShown = isNativeKeyboardShown
        self.sendInput = sendInput
        self.toggleNativeKeyboard = toggleNativeKeyboard
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                collapsedBar
            } else {
                expandedBar
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddShortcutSheet(store: shortcutStore)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isCollapsed)
    }

    // MARK: - Collapsed Handle
    private var collapsedBar: some View {
        HStack {
            Spacer()
            Button(action: { isCollapsed = false }) {
                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .font(.system(size: 13, weight: .bold))
                    Text("Shortcuts")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Palette.panel.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.3), radius: 6, y: -2)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .padding(.trailing, 16)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Expanded Bar
    private var expandedBar: some View {
        HStack(spacing: 8) {
            // Left: Native Keyboard Toggle
            Button(action: toggleNativeKeyboard) {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .medium))
                    Text("Keyboard")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(isNativeKeyboardShown ? Color.white : Palette.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isNativeKeyboardShown ? Palette.accent : Color.white.opacity(0.08))
                )
            }
            .help(isNativeKeyboardShown ? "Hide system keyboard" : "Show system keyboard")
            .padding(.leading, 6)

            Divider()
                .frame(height: 22)
                .background(Color.white.opacity(0.15))

            // Middle: Scrollable Shortcuts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shortcutStore.shortcuts) { shortcut in
                        shortcutButton(shortcut)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()
                .frame(height: 22)
                .background(Color.white.opacity(0.15))

            // Right: Add & Collapse
            HStack(spacing: 6) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.accent)
                }
                .help("Add custom shortcut")

                Button(action: { isCollapsed = true }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .padding(6)
                }
                .help("Collapse shortcuts bar")
            }
            .padding(.trailing, 8)
        }
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.panel.opacity(0.95))
                .shadow(color: Color.black.opacity(0.35), radius: 8, y: -2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Shortcut Capsule Button
    @ViewBuilder
    private func shortcutLabel(_ shortcut: CustomShortcut, isPressed: Bool) -> some View {
        HStack(spacing: 4) {
            if let sym = shortcut.symbol, !sym.isEmpty {
                Image(systemName: sym)
                    .font(.system(size: 11))
            }
            Text(shortcut.comboDisplay)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            if !shortcut.title.isEmpty && shortcut.title != shortcut.keyLabel {
                Text(shortcut.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Palette.muted)
            }
        }
        .foregroundStyle(isPressed ? Palette.accent : Palette.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isPressed ? Palette.accent.opacity(0.25) : Color.white.opacity(0.09))
        )
        .overlay(
            Capsule()
                .strokeBorder(isPressed ? Palette.accent : Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func shortcutButton(_ shortcut: CustomShortcut) -> some View {
        let isPressed = pressedShortcutID == shortcut.id

        Button(action: {
            triggerShortcut(shortcut)
        }) {
            shortcutLabel(shortcut, isPressed: isPressed)
        }
        .contextMenu {
            Button(role: .destructive, action: {
                shortcutStore.remove(id: shortcut.id)
            }) {
                Label("Delete shortcut", systemImage: "trash")
            }
        }
    }

    private func triggerShortcut(_ shortcut: CustomShortcut) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation(.easeInOut(duration: 0.1)) {
            pressedShortcutID = shortcut.id
        }

        for event in shortcut.makeEvents() {
            sendInput(event)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            if pressedShortcutID == shortcut.id {
                pressedShortcutID = nil
            }
        }
    }
}

/// Sheet modal to create and save a new custom shortcut.
struct AddShortcutSheet: View {
    @ObservedObject var store: CustomShortcutStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var hasCommand = true
    @State private var hasControl = false
    @State private var hasOption = false
    @State private var hasShift = false
    @State private var selectedOption: ShortcutKeyOption = ShortcutKeyOption.allOptions.first(where: { $0.label == "X" }) ?? ShortcutKeyOption.allOptions[0]
    @State private var filterQuery: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Modifiers
                Section(header: Text("Modifiers")) {
                    HStack(spacing: 12) {
                        modifierToggle("⌘ Command", isOn: $hasCommand)
                        modifierToggle("⌥ Option", isOn: $hasOption)
                        modifierToggle("⌃ Control", isOn: $hasControl)
                        modifierToggle("⇧ Shift", isOn: $hasShift)
                    }
                    .padding(.vertical, 4)
                }

                // Section 2: Main Key Selection
                Section(header: Text("Key (Selected: \(selectedOption.label))")) {
                    TextField("Filter key (e.g. X, Space, F1...)", text: $filterQuery)
                        .textFieldStyle(.roundedBorder)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(filteredOptions) { opt in
                                Button(action: {
                                    selectedOption = opt
                                    if title.isEmpty {
                                        title = opt.label
                                    }
                                }) {
                                    Text(opt.label)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(selectedOption.id == opt.id ? Color.white : Palette.text)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selectedOption.id == opt.id ? Palette.accent : Color.white.opacity(0.1))
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // Section 3: Name & Preview
                Section(header: Text("Shortcut Title & Preview")) {
                    TextField("Label (e.g. Cut, Hand, Select All)", text: $title)

                    HStack {
                        Text("Preview:")
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(currentComboDisplay)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                            if !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }
            }
            .navigationTitle("Add Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveShortcut()
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredOptions: [ShortcutKeyOption] {
        if filterQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return ShortcutKeyOption.allOptions
        }
        return ShortcutKeyOption.allOptions.filter {
            $0.label.localizedCaseInsensitiveContains(filterQuery)
        }
    }

    private var currentModifiersMask: UInt64 {
        var mods: KeyModifiers = []
        if hasCommand { mods.insert(.command) }
        if hasControl { mods.insert(.control) }
        if hasOption  { mods.insert(.option) }
        if hasShift   { mods.insert(.shift) }
        return mods.rawValue
    }

    private var currentComboDisplay: String {
        var str = ""
        if hasControl { str += "⌃" }
        if hasOption  { str += "⌥" }
        if hasShift   { str += "⇧" }
        if hasCommand { str += "⌘" }
        str += selectedOption.label
        return str
    }

    private func modifierToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.white : Palette.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn.wrappedValue ? Palette.accent : Color.white.opacity(0.1))
                )
        }
    }

    private func saveShortcut() {
        let finalTitle = title.trimmingCharacters(in: .whitespaces)
        store.add(
            title: finalTitle.isEmpty ? selectedOption.label : finalTitle,
            symbol: nil,
            modifiers: currentModifiersMask,
            hidUsage: selectedOption.hidUsage,
            keyLabel: selectedOption.label
        )
    }
}
