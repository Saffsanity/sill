import SwiftUI
import StreamProtocol

/// A connected Mac: its windows, the Desktop and its apps in the sidebar, the picked one streaming
/// in the window's main area, used with this Mac's mouse, trackpad and keyboard. The iPad's bar
/// (StreamScreen.swift there) as a Mac sidebar; the Settings panel as a popover.
struct StreamScreen: View {
    @ObservedObject var client: StreamClient
    @Binding var sendsShortcuts: Bool

    @State private var search = ""
    @State private var panelSize: CGSize = .zero
    @State private var pendingViewport: Task<Void, Never>?
    @State private var settingsShown = false
    @State private var columns = NavigationSplitViewVisibility.all
    /// The Mac window's size against the picture (the iPad's Aa): nil leaves the window as it is and
    /// fits its picture here; 1 sizes it to this window's picture area, point for point; above 1
    /// makes it smaller, so its text shows larger here. Remembered between sessions.
    @AppStorage("SillViewer.textScale") private var storedScale: Double = 0

    private var textScale: Double? { storedScale > 0 ? storedScale : nil }
    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            WindowSidebar(client: client, search: search)
                .searchable(text: $search, placement: .sidebar, prompt: "Windows and Apps")
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 420)
        } detail: {
            surface
                .toolbar { toolbar }
                .navigationTitle(client.macName.isEmpty ? "Sill Viewer" : client.macName)
                .navigationSubtitle(subtitle)
        }
        .onAppear { sendViewport() }
        .onChange(of: client.active) { _, _ in sendViewport() }
        .onChange(of: client.connected) { _, up in if up { sendViewport() } }
        .onChange(of: panelSize) { _, _ in sendViewport(after: 0.25) }
        .onChange(of: storedScale) { _, _ in sendViewport(after: 0.1) }
        .onChange(of: client.remoteRoute) { _, _ in sendViewport() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in sendViewport(after: 0.25) }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            sendViewport(after: 0.25)
        }
    }

    // MARK: The picture

    private var surface: some View {
        ZStack(alignment: .top) {
            StreamSurface(client: client, sendsShortcuts: sendsShortcuts) { size in
                DispatchQueue.main.async { panelSize = size }
            }
            .ignoresSafeArea()

            if client.active == .none {
                ContentUnavailableView {
                    Label("Nothing Streaming", systemImage: "macwindow")
                } description: {
                    Text("Choose a window or the Desktop of \(mac) in the sidebar.")
                } actions: {
                    Button("Show Desktop") { client.select(.desktop) }
                }
                .foregroundStyle(.white)
            }

            if let line = AwayCopy.streamLine(link: client.settings.host?.link, away: client.settings.host?.away, mac: mac) {
                Label(line, systemImage: "wifi.exclamationmark")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            MacClipboardChip(client: client).padding(16)
        }
        // Under the floating sidebar's inset too, so no strip of window background shows beside it.
        .background(Color.black.ignoresSafeArea())
    }

    /// What streams, and how the link is doing: "Safari — Start Page · 60 fps · 7 ms".
    private var subtitle: String {
        var parts: [String] = []
        switch client.active {
        case .none: parts.append("Nothing streaming")
        case .desktop: parts.append("Desktop")
        case .window(let id):
            if let w = client.windows.first(where: { $0.id == id }) {
                parts.append(w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)")
            }
        }
        if let stats = client.linkStats {
            parts.append("\(stats.fps) fps")
            if let rtt = stats.rtt { parts.append("\(rtt.median) ms") }
        }
        if let remote = client.remoteRoute { parts.append(remote.phrase) }
        else if let route = client.route?.word { parts.append(route) }
        return parts.joined(separator: " · ")
    }

    // MARK: The toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { client.select(.desktop) } label: {
                Label("Desktop", systemImage: "menubar.dock.rectangle")
            }
            .help("Show the Desktop of \(mac)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Window Size", selection: $storedScale) {
                    Text("Leave the Window as It Is").tag(0.0)
                    Divider()
                    ForEach(Self.scales, id: \.self) { s in
                        Text(Self.scaleTitle(s)).tag(s)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Text Size", systemImage: "textformat.size")
            }
            .help("Size the window on \(mac) to this window, so its text shows at the size you pick")

            Toggle(isOn: $sendsShortcuts) {
                Label("Send Shortcuts", systemImage: "command")
            }
            .help(sendsShortcuts ? "⌘ shortcuts go to \(mac) (⌃⌥⌘K to keep them here)"
                                 : "⌘ shortcuts stay on this Mac (⌃⌥⌘K to send them to \(mac))")

            Button { settingsShown.toggle() } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .help("Streaming settings of \(mac)")
            .popover(isPresented: $settingsShown, arrowEdge: .bottom) {
                SettingsPopover(client: client)
            }

            Button { client.disconnect() } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            .help("Disconnect from \(mac)")
        }
    }

    /// The iPad's Aa detents.
    static let scales: [Double] = [0.5, 0.75, 1, 1.25, 1.5]

    static func scaleTitle(_ s: Double) -> String {
        s == 1 ? "Fit to This Window (Actual Size)" : "Fit to This Window, Text at \(Int((s * 100).rounded())) %"
    }

    // MARK: Viewport

    /// Tells the host the picture area's size and the text scale, now or after `delay` seconds; a
    /// newer call replaces a pending one. Nothing goes out before the area is measured.
    private func sendViewport(after delay: Double = 0) {
        pendingViewport?.cancel()
        pendingViewport = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            guard client.connected, panelSize.width > 0, panelSize.height > 0 else { return }
            let fps = StreamClient.wantedFPS(remote: client.awayCapsFrameRate)
            client.sendViewport(Viewport(width: Double(panelSize.width), height: Double(panelSize.height),
                                         scale: textScale, fps: fps))
        }
    }
}

// MARK: - The sidebar

/// The Desktop, the Mac's windows (live thumbnails, front to back, in this Mac's own order), and
/// every app installed there, filtered by the sidebar's search field.
private struct WindowSidebar: View {
    @ObservedObject var client: StreamClient
    let search: String

    private var selection: Binding<StreamSource?> {
        // The pick goes out after the table's own turn: `active` changes with the host's answer, and
        // changing it inside the table's delegate call is reentrant.
        Binding(get: { client.active == .none ? nil : client.active },
                set: { source in
                    guard let source, source != client.active else { return }
                    DispatchQueue.main.async { client.select(source) }
                })
    }

    private func matches(_ text: String...) -> Bool {
        search.isEmpty || text.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    private var windows: [WindowInfo] { client.orderedWindows.filter { matches($0.title, $0.appName) } }

    /// Apps with no window listed come after the windows: launching one opens it.
    private var apps: [AppInfo] {
        client.apps.filter { matches($0.name) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(selection: selection) {
            if matches("Desktop") {
                Label("Desktop", systemImage: "menubar.dock.rectangle")
                    .tag(StreamSource.desktop)
            }
            Section("Windows") {
                ForEach(windows) { window in
                    WindowRow(window: window, thumbnail: client.thumbnails[window.id], icon: client.icons[window.bundleID])
                        .tag(StreamSource.window(window.id))
                        .contextMenu {
                            Button("Show") { client.select(.window(window.id)) }
                            Divider()
                            Button("Close Window") { client.command(.close, window: window.id) }
                            Button("Minimize Window") { client.command(.minimize, window: window.id) }
                            Button("Full Screen") { client.command(.fullScreen, window: window.id) }
                        }
                }
                if windows.isEmpty {
                    Text(search.isEmpty ? "No windows" : "No matching windows").foregroundStyle(.secondary)
                }
            }
            if !apps.isEmpty {
                Section(search.isEmpty ? "Apps" : "Apps on the Mac") {
                    ForEach(apps) { app in
                        AppRow(app: app, icon: client.icons[app.bundleID]) { client.launch(bundleID: app.bundleID) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct WindowRow: View {
    let window: WindowInfo
    let thumbnail: NSImage?
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    }
                }
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18).offset(x: 5, y: 5)
                }
            }
            .frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.title.isEmpty ? window.appName : window.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(window.appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct AppRow: View {
    let app: AppInfo
    let icon: NSImage?
    let launch: () -> Void

    var body: some View {
        Button(action: launch) {
            HStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app").frame(width: 18, height: 18)
                }
                Text(app.name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(app.name) on the Mac")
    }
}

// MARK: - Settings

/// The streamed Mac's settings, as the iPad's Settings panel has them: every control shows the
/// Mac's value with this Mac's unanswered picks over it (SettingsLedger), and moving one sends that
/// one field.
private struct SettingsPopover: View {
    @ObservedObject var client: StreamClient
    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }

    var body: some View {
        Form {
            if let state = client.settings.host, let shown = client.settings.displayed {
                if let stream = state.stream {
                    Section {
                        LabeledContent("Streaming", value: "\(stream.width)×\(stream.height) · \(stream.fps) fps · \(stream.mbps) Mbps"
                                       + (stream.onVirtualDisplay ? " · Virtual Display" : ""))
                    }
                }
                if state.softwareEncoder {
                    Text("\(mac)’s hardware encoder is busy or not responding, so for now streams run at up to 60 fps at Standard.")
                        .foregroundStyle(.orange)
                }
                if let problem = client.settingsProblem {
                    Text(problem).foregroundStyle(.orange)
                }
                if let callout = AwayCopy.callout(link: state.link, away: state.away, mac: mac) {
                    Section {
                        Text(callout.text)
                        if let b = callout.button { Button(b.title) { client.changeSettings(b.change) } }
                    }
                }
                Section {
                    Picker("Quality", selection: binding(shown.bitrate) { HostSettingsChange(bitrate: $0) }) {
                        ForEach(QualityPreset.allCases) { Text($0.title).tag($0.rawValue) }
                        if QualityPreset(rawValue: shown.bitrate) == nil {
                            Text(QualityPreset.title(forBitrate: shown.bitrate)).tag(shown.bitrate)
                        }
                    }
                    Picker("Resolution", selection: binding(shown.captureScale) { HostSettingsChange(captureScale: $0) }) {
                        Text("Retina").tag(2.0)
                        Text("Standard").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    Picker("Frame Rate", selection: binding(shown.maxFPS) { HostSettingsChange(maxFPS: $0) }) {
                        Text("60 fps").tag(60)
                        Text("120 fps").tag(120)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if let note = AwayCopy.footnote(state.away, mac: mac, remoteAccessOn: client.macInfo?.remoteAccess == true) {
                        Text(note).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Prioritize Encoding Speed", isOn: binding(shown.prioritizeSpeed) { HostSettingsChange(prioritizeSpeed: $0) })
                    Toggle("Virtual Display", isOn: binding(shown.virtualDisplay) { HostSettingsChange(virtualDisplay: $0) })
                        .disabled(!state.virtualDisplayAvailable && !shown.virtualDisplay)
                    if let direct = shown.directWireless {
                        Toggle("Direct Wireless Connection", isOn: binding(direct) { HostSettingsChange(directWireless: $0) })
                            .disabled(client.remoteRoute != nil)
                    }
                } footer: {
                    Text(state.virtualDisplayNote
                         ?? "Applies to every device streaming from \(mac). The stream restarts for a moment.")
                        .foregroundStyle(.secondary)
                }
                if !state.persistent {
                    Text("SillHost keeps these until it quits.").foregroundStyle(.secondary)
                }
                if ClipboardPolicy.hostTakes(client.hostClipboard) {
                    Section {
                        Toggle("Share Clipboard", isOn: Binding(
                            get: { StreamClient.clipboardOn },
                            set: { UserDefaults.standard.set($0, forKey: StreamClient.clipboardKey); client.clipboardSwitchChanged() }))
                    } footer: {
                        Text("Text you copy on \(mac) lands on this Mac’s clipboard. To send this Mac’s, use Paste on the chip that appears when you come back to the viewer.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading settings… (an older Sill on \(mac) has none to show)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Shows the value the panel displays; moving the control sends that one field.
    private func binding<V>(_ value: V, _ change: @escaping (V) -> HostSettingsChange) -> Binding<V> {
        Binding(get: { value }, set: { client.changeSettings(change($0)) })
    }
}
