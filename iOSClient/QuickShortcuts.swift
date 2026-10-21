import SwiftUI
import StreamProtocol

/// Quick shortcuts: a phone's row 1 Shortcuts button opens a drawer of shortcuts the person makes
/// (Raffael, 2026-10-21): a key combination for the Mac, an app to open there, text to type, or one of
/// Sill's own actions. Kept on this device alone (`Sill.quickShortcuts`), the same list for every Mac;
/// nothing new goes over the wire, each runs through what the client already sends.
struct QuickShortcut: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var action: Action
    /// Shown only while a window of this app streams (its bundle ID); nil: always.
    var onlyApp: String? = nil

    enum Action: Codable, Equatable {
        /// A key (a HID usage) with modifiers (`KeyModifiers`' raw value), pressed as a keyboard does.
        case keys(usage: UInt16, modifiers: UInt64)
        /// An app on the Mac: shown if it is open (its next window), opened if not.
        case app(bundleID: String, name: String)
        /// Text typed on the Mac, and Return after it when `thenReturn`.
        case text(String, thenReturn: Bool)
        case sill(SillAction)
    }

    /// Sill's own actions.
    enum SillAction: String, Codable, CaseIterable, Identifiable {
        case desktop, zoom, missionControl, appExpose, showDesktop, spotlight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .desktop: return "Desktop"
            case .zoom: return "Zoom"
            case .missionControl: return "Mission Control"
            case .appExpose: return "App Exposé"
            case .showDesktop: return "Show Desktop"
            case .spotlight: return "Spotlight"
            }
        }
        var symbol: String {
            switch self {
            case .desktop: return "desktopcomputer"
            case .zoom: return "plus.magnifyingglass"
            case .missionControl: return "rectangle.3.group"
            case .appExpose: return "rectangle.stack"
            case .showDesktop: return "macwindow.on.rectangle"
            case .spotlight: return "magnifyingglass"
            }
        }
    }

    var symbol: String {
        switch action {
        case .keys: return "command"
        case .app: return "app"
        case .text: return "text.cursor"
        case .sill(let a): return a.symbol
        }
    }

    /// What it does, short: "⌘C", "Opens Notes", "git status ⏎", "Mission Control".
    var detail: String {
        switch action {
        case .keys(let usage, let modifiers): return Self.chord(usage: usage, modifiers: KeyModifiers(rawValue: modifiers))
        case .app(_, let name): return "Opens \(name)"
        case .text(let text, let ret): return text + (ret ? " ⏎" : "")
        case .sill(let a): return a.title
        }
    }

    /// The Mac's way of writing a shortcut: ⌃⌥⇧⌘ then the key.
    static func chord(usage: UInt16, modifiers: KeyModifiers) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (keys.first { $0.usage == usage }?.name ?? "?")
    }

    /// The keys a shortcut can press, by HID usage (a US keyboard's places, which the Mac maps as its
    /// own keyboard: Sill sends a key's place, never its letter).
    static let keys: [(name: String, usage: UInt16)] = {
        var keys: [(String, UInt16)] = []
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { keys.append((String(c), UInt16(0x04 + i))) }
        for (i, c) in "123456789".enumerated() { keys.append((String(c), UInt16(0x1E + i))) }
        keys.append(("0", 0x27))
        keys += [("Return", 0x28), ("Esc", 0x29), ("Delete", 0x2A), ("Tab", 0x2B), ("Space", 0x2C),
                 ("-", 0x2D), ("=", 0x2E), ("[", 0x2F), ("]", 0x30), ("\\", 0x31), (";", 0x33), ("'", 0x34),
                 ("`", 0x35), (",", 0x36), (".", 0x37), ("/", 0x38),
                 ("→", 0x4F), ("←", 0x50), ("↓", 0x51), ("↑", 0x52)]
        for n in 1...12 { keys.append(("F\(n)", UInt16(0x39 + n))) }
        return keys
    }()

    /// What the drawer holds before the person changes anything.
    static let starters: [QuickShortcut] = [
        QuickShortcut(title: "Copy", action: .keys(usage: 0x06, modifiers: KeyModifiers.command.rawValue)),
        QuickShortcut(title: "Paste", action: .keys(usage: 0x19, modifiers: KeyModifiers.command.rawValue)),
        QuickShortcut(title: "Undo", action: .keys(usage: 0x1D, modifiers: KeyModifiers.command.rawValue)),
        QuickShortcut(title: "Switch App", action: .keys(usage: 0x2B, modifiers: KeyModifiers.command.rawValue)),
        QuickShortcut(title: "Mission Control", action: .sill(.missionControl)),
        QuickShortcut(title: "Zoom", action: .sill(.zoom)),
    ]
}

/// The shortcuts, saved on this device as JSON. Main thread.
final class QuickShortcutStore: ObservableObject {
    static let shared = QuickShortcutStore()
    static let key = "Sill.quickShortcuts"

    @Published var shortcuts: [QuickShortcut] { didSet { save() } }

    private init() {
        // One by one: a shortcut a later build cannot read is left out, never the whole list.
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Lenient].self, from: data) {
            shortcuts = saved.compactMap(\.shortcut)
        } else {
            shortcuts = QuickShortcut.starters
        }
    }

    /// One saved shortcut, or nil where it could not be read.
    private struct Lenient: Decodable {
        let shortcut: QuickShortcut?
        init(from decoder: Decoder) throws { shortcut = try? QuickShortcut(from: decoder) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func put(_ shortcut: QuickShortcut) {
        if let i = shortcuts.firstIndex(where: { $0.id == shortcut.id }) { shortcuts[i] = shortcut } else { shortcuts.append(shortcut) }
    }

    func remove(_ id: UUID) { shortcuts.removeAll { $0.id == id } }

    func move(_ id: UUID, by step: Int) {
        guard let from = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + step, 0), shortcuts.count - 1)
        guard to != from else { return }
        shortcuts.insert(shortcuts.remove(at: from), at: to)
    }
}

extension StreamClient {
    /// Runs a shortcut on the Mac. True when the drawer should close (it showed something else: an
    /// app, the Desktop, a view of the Mac's); false keeps it open for another tap (keys, text).
    @discardableResult
    func run(_ shortcut: QuickShortcut) -> Bool {
        noteAction()
        switch shortcut.action {
        case .keys(let usage, let modifiers):
            KeyChord.press(usage, with: KeyModifiers(rawValue: modifiers)).forEach { sendFromKeyRow($0) }
            return false
        case .app(let bundleID, _):
            // An open app: its next window, as the Apps drawer shows it; else the Mac opens it.
            let windows = orderedWindows.filter { $0.bundleID == bundleID }
            if let next = Self.nextWindow(of: windows, active: active) { select(.window(next.id)) } else { launch(bundleID: bundleID) }
            return true
        case .text(let text, let thenReturn):
            if !text.isEmpty { sendFromKeyRow(.text(text)) }
            if thenReturn { KeyChord.press(0x28, with: []).forEach { sendFromKeyRow($0) } }
            return false
        case .sill(let action):
            switch action {
            case .desktop: select(.desktop)
            case .zoom: zoom.toggle()
            case .missionControl: sendGesture(.swipeUp, fingers: 3)
            case .appExpose: sendGesture(.swipeDown, fingers: 3)
            case .showDesktop: sendGesture(.spread, fingers: 3)
            case .spotlight: KeyChord.spotlight.forEach { sendFromKeyRow($0) }
            }
            return action != .zoom
        }
    }

    /// The window after the one showing among `windows` (one app's), or the first.
    static func nextWindow(of windows: [WindowInfo], active: StreamSource) -> WindowInfo? {
        guard !windows.isEmpty else { return nil }
        if case .window(let id) = active, let i = windows.firstIndex(where: { $0.id == id }) {
            return windows[(i + 1) % windows.count]
        }
        return windows[0]
    }
}

/// The drawer: the shortcuts as tiles, a tap runs one; Edit to change, reorder, delete and add.
struct ShortcutsDrawer: View {
    @ObservedObject var client: StreamClient
    @ObservedObject var store = QuickShortcutStore.shared
    @Binding var open: Bool
    /// The Desktop as a fixed first tile, where no thumbnail row offers it (Larger Picture).
    var showsDesktop = false

    @State private var editing = false
    @State private var editor: QuickShortcut?
    /// The software keyboard's top in the screen's space, while it is up (the editor's fields): the
    /// stream screen ignores the keyboard, so the drawer keeps its content above it by itself.
    @State private var keyboardTop: CGFloat?
    /// The drawer's bottom in the screen's space.
    @State private var drawerBottom: CGFloat = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            if let shortcut = editor {
                ShortcutEditor(client: client, shortcut: shortcut,
                               isNew: !store.shortcuts.contains { $0.id == shortcut.id },
                               save: { store.put($0); editor = nil },
                               delete: { store.remove($0); editor = nil },
                               cancel: { editor = nil })
            } else {
                header
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        if showsDesktop && !editing {
                            tile(symbol: "desktopcomputer", title: "Desktop", detail: "The whole Mac") {
                                client.select(.desktop); close()
                            }
                        }
                        ForEach(store.shortcuts.filter { editing || $0.onlyApp == nil || $0.onlyApp == streamedApp }) { shortcut in
                            tile(symbol: shortcut.symbol, title: shortcut.title, detail: shortcut.detail) {
                                if editing { editor = shortcut } else if client.run(shortcut) { close() }
                            }
                            .overlay(alignment: .topTrailing) { if editing { reorder(shortcut) } }
                            .overlay(alignment: .topLeading) {
                                if let app = shortcut.onlyApp {
                                    AppIcon(image: client.icons[app], name: app, size: 18, radius: 5, fontSize: 8).padding(6)
                                }
                            }
                        }
                        if editing {
                            tile(symbol: "plus", title: "Add", detail: "A new shortcut") {
                                editor = QuickShortcut(title: "", action: .keys(usage: 0x04, modifiers: KeyModifiers.command.rawValue))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .padding(.bottom, keyboardTop.map { max(0, drawerBottom - $0) } ?? 0)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.bar))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 30, x: 0, y: 24)
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) { drawerBottom = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = UIScreen.main.bounds.height
            withAnimation(.easeOut(duration: 0.25)) { keyboardTop = end.minY < screen ? end.minY : nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardTop = nil }
        }
        .onChange(of: open) { _, isOpen in if !isOpen { editing = false; editor = nil } }
    }

    private var header: some View {
        HStack {
            Text("Shortcuts")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
            Spacer()
            Button(editing ? "Done" : "Edit") {
                withAnimation(.easeOut(duration: 0.15)) { editing.toggle() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
        }
    }

    private func tile(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title.isEmpty ? detail : title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.barLabel)
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.control))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? detail : "\(title), \(detail)")
        .accessibilityAddTraits(.isButton)
    }

    /// In Edit: move a tile earlier or later (a tap on the tile itself edits it).
    private func reorder(_ shortcut: QuickShortcut) -> some View {
        HStack(spacing: 2) {
            Button { store.move(shortcut.id, by: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Move \(shortcut.title) earlier")
            Button { store.move(shortcut.id, by: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Move \(shortcut.title) later")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Palette.text)
        .padding(5)
        .background(Capsule().fill(Palette.controlOpen))
        .padding(4)
    }

    private func close() { withAnimation(.easeOut(duration: 0.18)) { open = false } }

    /// The app whose window streams now, whose own shortcuts show; nil for the Desktop.
    private var streamedApp: String? {
        guard case .window(let id) = client.active else { return nil }
        return client.windows.first { $0.id == id }?.bundleID
    }
}

/// One shortcut's form, inside the drawer.
private struct ShortcutEditor: View {
    @ObservedObject var client: StreamClient
    @State var shortcut: QuickShortcut
    let isNew: Bool
    let save: (QuickShortcut) -> Void
    let delete: (UUID) -> Void
    let cancel: () -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case keys = "Keys", app = "App", text = "Text", sill = "Sill"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .keys
    @State private var usage: UInt16 = 0x04
    @State private var modifiers: KeyModifiers = .command
    @State private var bundleID = ""
    @State private var text = ""
    @State private var thenReturn = false
    @State private var sillAction: QuickShortcut.SillAction = .desktop

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Cancel", action: cancel).foregroundStyle(Palette.barLabel)
                Spacer()
                Text(isNew ? "New Shortcut" : "Edit Shortcut")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Button("Save") { save(built) }
                    .fontWeight(.semibold).foregroundStyle(Palette.accent)
                    .disabled(!valid)
            }
            .font(.system(size: 15))
            .frame(minHeight: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("", text: $shortcut.title, prompt: Text("Name").foregroundColor(Palette.muted))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.control))

                    Picker(selection: $shortcut.onlyApp) {
                        Text("Every App").tag(String?.none)
                        ForEach(appChoices, id: \.bundleID) { Text($0.name).tag(Optional($0.bundleID)) }
                    } label: {
                        Text("Show For").foregroundStyle(Palette.text)
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.text)

                    Picker("Kind", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch kind {
                    case .keys: keysForm
                    case .app: appForm
                    case .text: textForm
                    case .sill: sillForm
                    }

                    if !isNew {
                        Button(role: .destructive) { delete(shortcut.id) } label: {
                            Text("Delete Shortcut").frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: load)
    }

    private var keysForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                modifierToggle("⌃", .control, "Control")
                modifierToggle("⌥", .option, "Option")
                modifierToggle("⇧", .shift, "Shift")
                modifierToggle("⌘", .command, "Command")
            }
            Picker("Key", selection: $usage) {
                ForEach(QuickShortcut.keys, id: \.usage) { Text($0.name).tag($0.usage) }
            }
            .pickerStyle(.menu)
            .tint(Palette.text)
            Text(QuickShortcut.chord(usage: usage, modifiers: modifiers))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity)
        }
    }

    private func modifierToggle(_ glyph: String, _ flag: KeyModifiers, _ name: String) -> some View {
        let on = modifiers.contains(flag)
        return Button {
            if on { modifiers.remove(flag) } else { modifiers.insert(flag) }
        } label: {
            Text(glyph)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(on ? Color.white : Palette.text)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Palette.accent : Palette.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var appForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(appChoices, id: \.bundleID) { app in
                Button {
                    bundleID = app.bundleID
                    if shortcut.title.isEmpty { shortcut.title = app.name }
                } label: {
                    HStack(spacing: 10) {
                        AppIcon(image: client.icons[app.bundleID], name: app.name, size: 28, radius: 8, fontSize: 11)
                        Text(app.name).foregroundStyle(Palette.text)
                        Spacer()
                        if bundleID == app.bundleID { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                    }
                    .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var textForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $text, prompt: Text("Text to type").foregroundColor(Palette.muted), axis: .vertical)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Palette.text)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.control))
            Toggle("Press Return after", isOn: $thenReturn)
                .foregroundStyle(Palette.text)
                .tint(Palette.accent)
        }
    }

    private var sillForm: some View {
        Picker("Action", selection: $sillAction) {
            ForEach(QuickShortcut.SillAction.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .tint(Palette.text)
    }

    /// Every app the Mac listed, open ones first, by name.
    private var appChoices: [(bundleID: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for w in client.windows where seen.insert(w.bundleID).inserted { out.append((w.bundleID, w.appName)) }
        for a in client.apps.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            where seen.insert(a.bundleID).inserted { out.append((a.bundleID, a.name)) }
        return out
    }

    private var valid: Bool {
        switch kind {
        case .keys, .sill: return true
        case .app: return !bundleID.isEmpty
        case .text: return !text.isEmpty || thenReturn
        }
    }

    private var built: QuickShortcut {
        var s = shortcut
        switch kind {
        case .keys: s.action = .keys(usage: usage, modifiers: modifiers.rawValue)
        case .app: s.action = .app(bundleID: bundleID, name: appChoices.first { $0.bundleID == bundleID }?.name ?? bundleID)
        case .text: s.action = .text(text, thenReturn: thenReturn)
        case .sill: s.action = .sill(sillAction)
        }
        if s.title.trimmingCharacters(in: .whitespaces).isEmpty {
            if case .sill(let a) = s.action { s.title = a.title } else { s.title = s.detail }
        }
        return s
    }

    private func load() {
        switch shortcut.action {
        case .keys(let u, let m): kind = .keys; usage = u; modifiers = KeyModifiers(rawValue: m)
        case .app(let b, _): kind = .app; bundleID = b
        case .text(let t, let r): kind = .text; text = t; thenReturn = r
        case .sill(let a): kind = .sill; sillAction = a
        }
    }
}
