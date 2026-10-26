import SwiftUI
import StreamProtocol

/// Sill Viewer: the iPhone and iPad app's client on a Mac. The Devices window lists every Mac as a
/// tile; each Mac opens in a session window of its own, with a client of its own (StreamClient, the
/// iOS app's), so several Macs stream at once.
@main
struct SillViewerApp: App {
    var body: some Scene {
        Window("Sill Viewer", id: "devices") {
            DevicesWindow()
        }
        .defaultSize(width: 900, height: 620)
        .commands {
            StreamCommands()
            DevicesCommands()
        }

        WindowGroup("Mac", id: "session", for: ViewerTarget.self) { $target in
            if let target {
                SessionWindow(target: target)
            } else {
                SessionWindow(target: .add())
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}

/// File › Add a Mac… and Window › Devices.
struct DevicesCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add a Mac…") { openWindow(id: "session", value: ViewerTarget.add()) }
                .keyboardShortcut("n")
        }
        CommandGroup(before: .windowList) {
            Button("Devices") { openWindow(id: "devices") }
                .keyboardShortcut("0")
            Divider()
        }
    }
}

// MARK: - Menu commands

extension FocusedValues {
    @Entry var sendsShortcuts: Binding<Bool>?
}

/// The Stream menu. The viewer's own shortcuts are ⌃⌥⌘ chords, which never go to the streamed Mac,
/// so they work while the stream has the keyboard.
struct StreamCommands: Commands {
    @FocusedObject private var client: StreamClient?
    @FocusedValue(\.sendsShortcuts) private var sendsShortcuts

    var body: some Commands {
        CommandMenu("Stream") {
            Button("Desktop") { client?.select(.desktop) }
                .keyboardShortcut("d", modifiers: [.command, .option, .control])
                .disabled(client?.connected != true)
            Button("Stop Streaming") { client?.select(.none) }
                .disabled(client?.connected != true || client?.active == StreamSource.none)
            Divider()
            if let sendsShortcuts {
                Toggle("Send Keyboard Shortcuts to the Mac", isOn: sendsShortcuts)
                    .keyboardShortcut("k", modifiers: [.command, .option, .control])
            }
            Divider()
            Button("Disconnect") { client?.disconnect() }
                .keyboardShortcut("w", modifiers: [.command, .option, .control])
                .disabled(client?.connected != true)
        }
    }
}
