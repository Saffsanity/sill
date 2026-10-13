import AppKit
import StreamProtocol

/// Sill's controls, in the menu bar's status item, so the menu bar itself is the controlled app's:
/// the connection (Connect…, Disconnect), the other Mac's windows (each opens as a window here, a
/// check on those open, a dot on the one streaming) with the Desktop and its apps to open, the
/// other Mac's streaming settings (as its own menu has them, kind 17), the gestures macOS keeps
/// for itself here, and Capture System Shortcuts. Built afresh each time it opens. Main thread.
final class StatusMenu: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var client: StreamClient { app.client }

    init(app: AppDelegate) {
        self.app = app
        super.init()
        let image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Sill Viewer")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    /// Drops the menu down, as a click on the icon does.
    func open() { item.button?.performClick(nil) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if client.connected {
            menu.addItem(header("Connected to \(client.macName)" + (client.linkStats.map { " · \($0.fps) fps" } ?? "")))
            windowItems(into: menu)
            menu.addItem(.separator())
            settingsItems(into: menu)
            menu.addItem(.separator())
            menu.addItem(submenu("Gestures", gestureItems()))
            menu.addItem(captureItem())
            menu.addItem(shareClipboardItem())
            menu.addItem(playSoundItem())
            if let key = NSApp.orderedWindows.first(where: { $0 is StreamWindow && $0.styleMask.contains(.fullScreen) }) {
                menu.addItem(action("Exit Full Screen") { key.toggleFullScreen(nil) })
            }
            menu.addItem(.separator())
            menu.addItem(action("Connect to Another Mac…") { [weak self] in self?.app.showConnectWindow() })
            menu.addItem(action("Disconnect") { [weak self] in self?.app.disconnect() })
        } else {
            menu.addItem(header(client.status))
            for mac in client.macs {
                menu.addItem(action(mac.name + (mac.word.map { " — \($0)" } ?? "")) { [weak self] in
                    self?.client.connect(to: mac)
                    self?.app.showConnectWindow()
                })
            }
            menu.addItem(action("Connect to a Mac…") { [weak self] in self?.app.showConnectWindow() })
            menu.addItem(captureItem())
        }
        menu.addItem(.separator())
        menu.addItem(action("Quit Sill Viewer") { NSApp.terminate(nil) })
    }

    // MARK: Windows

    private func windowItems(into menu: NSMenu) {
        let open = app.windows.openSources
        menu.addItem(.separator())
        if client.hostDisplays.isEmpty {
            let desktop = action("Desktop") { [weak self] in self?.app.windows.open(.desktop) }
            desktop.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: nil)
            mark(desktop, source: .desktop, open: open)
            menu.addItem(desktop)
        } else {
            // Each of the other Mac's displays, a Desktop window of its own.
            for d in client.hostDisplays {
                let source = StreamSource.window(DesktopWindow.id(display: d.id))
                let item = action(client.hostDisplays.count > 1 ? "Desktop — \(d.name)" : "Desktop") { [weak self] in
                    self?.app.windows.open(source)
                }
                item.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: nil)
                mark(item, source: source, open: open)
                menu.addItem(item)
            }
        }
        // By app, as the Dock groups them: the app opens all its windows; each window opens alone.
        var appOrder: [String] = []
        var byApp: [String: [WindowInfo]] = [:]
        for w in client.orderedWindows {
            if byApp[w.bundleID] == nil { appOrder.append(w.bundleID) }
            byApp[w.bundleID, default: []].append(w)
        }
        for app in appOrder {
            let windows = byApp[app] ?? []
            let name = windows.first?.appName ?? app
            let header = action(windows.count > 1 ? "\(name) — all \(windows.count) windows" : name) { [weak self] in
                guard let self else { return }
                for (i, w) in windows.enumerated() { self.app.windows.open(.window(w.id), focus: i == windows.count - 1) }
            }
            header.image = icon(client.icons[app])
            // The app's Dock badge on the other Mac ("3"), as its Dock icon here shows it.
            if let badge = client.hostBadges[app], !badge.isEmpty {
                header.badge = Int(badge).map { NSMenuItemBadge(count: $0) } ?? NSMenuItemBadge(string: badge)
            }
            if windows.count == 1 { mark(header, source: .window(windows[0].id), open: open) }
            menu.addItem(header)
            guard windows.count > 1 else { continue }
            for w in windows {
                let title = w.title.isEmpty ? w.appName : w.title
                let item = action(Self.clip(title)) { [weak self] in self?.app.windows.open(.window(w.id)) }
                item.indentationLevel = 1
                item.toolTip = title
                mark(item, source: .window(w.id), open: open)
                menu.addItem(item)
            }
        }
        if client.windows.isEmpty { menu.addItem(note("No windows on \(client.macName)")) }
        var apps: [NSMenuItem] = []
        for a in client.apps {
            let item = action(a.name) { [weak self] in self?.client.launch(bundleID: a.bundleID) }
            item.image = icon(client.icons[a.bundleID])
            apps.append(item)
        }
        menu.addItem(submenu("Open App", apps.isEmpty ? [note("Still listing apps…")] : apps))
    }

    /// A check on a window open here, and "streaming" after the one the other Mac streams now.
    private func mark(_ item: NSMenuItem, source: StreamSource, open: Set<StreamSource>) {
        item.state = open.contains(source) ? .on : .off
        guard app.windows.local(client.active) == source else { return }
        let text = NSMutableAttributedString(string: item.title + "  ")
        text.append(NSAttributedString(string: "streaming", attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                                                                         .font: NSFont.menuFont(ofSize: 11)]))
        item.attributedTitle = text
    }

    // MARK: Settings (kind 17, as the other Mac's own menu has them)

    private func settingsItems(into menu: NSMenu) {
        guard let s = client.settings.displayed else {
            menu.addItem(note(client.hostVersion == nil && client.connectedAt.map({ Date().timeIntervalSince($0) > 2 }) == true
                              ? "Update Sill on \(client.macName) to change its settings here" : "Reading \(client.macName)’s settings…"))
            return
        }
        var quality = QualityPreset.allCases.map { p -> NSMenuItem in
            let item = action("\(p.name) — \(p.rawValue / 1_000_000) Mbps") { [weak self] in self?.client.changeSettings(HostSettingsChange(bitrate: p.rawValue)) }
            item.state = s.bitrate == p.rawValue ? .on : .off
            return item
        }
        if QualityPreset(rawValue: s.bitrate) == nil {
            let custom = note("Custom — \(s.bitrate / 1_000_000) Mbps")
            custom.state = .on
            quality.append(custom)
        }
        menu.addItem(submenu("Quality", quality, subtitle: QualityPreset(rawValue: s.bitrate)?.name))
        let resolution = [(2.0, "Retina"), (1.0, "Standard")].map { scale, name -> NSMenuItem in
            let item = action(name) { [weak self] in self?.client.changeSettings(HostSettingsChange(captureScale: scale)) }
            item.state = s.captureScale == scale ? .on : .off
            return item
        }
        menu.addItem(submenu("Resolution", resolution, subtitle: s.captureScale == 2 ? "Retina" : "Standard"))
        let rates = SettingsChoices.maxFPS.map { fps -> NSMenuItem in
            let item = action("Up to \(fps) fps") { [weak self] in self?.client.changeSettings(HostSettingsChange(maxFPS: fps)) }
            item.state = s.maxFPS == fps ? .on : .off
            return item
        }
        menu.addItem(submenu("Frame Rate", rates, subtitle: "\(s.maxFPS) fps"))
        menu.addItem(toggle("Prioritize Encoding Speed", s.prioritizeSpeed) { [weak self] in
            self?.client.changeSettings(HostSettingsChange(prioritizeSpeed: !s.prioritizeSpeed))
        })
        // No Virtual Display item: the iPad's staging of the one streamed window. This viewer's windows
        // always live on Sill's desk, a display of their own each, whatever that setting says.
        if let direct = s.directWireless {
            menu.addItem(toggle("Direct Wireless Connection", direct) { [weak self] in
                self?.client.changeSettings(HostSettingsChange(directWireless: !direct))
            })
        }
        if let problem = client.settingsProblem { menu.addItem(note(problem)) }
    }

    // MARK: Gestures and keys

    private func gestureItems() -> [NSMenuItem] {
        let gestures: [(String, TrackpadGestures.Gesture, Int)] = [
            ("Mission Control", .swipeUp, 3), ("App Exposé", .swipeDown, 3), ("Previous Space", .swipeRight, 3),
            ("Next Space", .swipeLeft, 3), ("Show Desktop", .spread, 4), ("Show Apps", .pinch, 4),
        ]
        return gestures.map { title, gesture, fingers in
            action(title) { [weak self] in _ = self?.client.sendGesture(gesture, fingers: fingers) }
        }
    }

    private func captureItem() -> NSMenuItem {
        let item = toggle("Capture System Shortcuts", SystemKeyTap.shared.enabled) {
            SystemKeyTap.shared.enabled.toggle()
        }
        item.toolTip = "⌘Tab, ⌘Space and the other shortcuts go to the other Mac while its window has the keyboard. ⌃⌥⌘⎋ gives the keyboard back."
        return item
    }

    private func playSoundItem() -> NSMenuItem {
        let item = toggle("Play Sound", AudioPlayer.enabled) { [app] in
            AudioPlayer.enabled.toggle()
            if !AudioPlayer.enabled { app.audio.stop() }
            app.windows.requestSideStreams()   // the host taps, or gives the apps their sound back
        }
        item.toolTip = client.hostAudio ? "The sound of the apps open here plays on this Mac and is silenced on \(client.macName)."
                                        : "\(client.macName)’s Sill does not send sound yet."
        item.isEnabled = client.hostAudio
        return item
    }

    private func shareClipboardItem() -> NSMenuItem {
        let item = toggle("Share Clipboard", ClipboardSync.enabled) { ClipboardSync.enabled.toggle() }
        item.toolTip = client.hostClipboard ? "Copies on either Mac paste on the other." : "\(client.macName)’s Sill does not share its clipboard yet."
        item.isEnabled = client.hostClipboard
        return item
    }

    // MARK: Items

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
    private func note(_ text: String) -> NSMenuItem { header(text) }

    private func action(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureItem(title: title, run: run)
        return item
    }

    private func toggle(_ title: String, _ on: Bool, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = action(title, run)
        item.state = on ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem], subtitle: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let subtitle {
            let text = NSMutableAttributedString(string: title + "    ")
            text.append(NSAttributedString(string: subtitle, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = text
        }
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach { menu.addItem($0) }
        item.submenu = menu
        return item
    }

    private func icon(_ image: NSImage?) -> NSImage? {
        guard let image = image?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func clip(_ s: String) -> String { s.count > 60 ? String(s.prefix(57)) + "…" : s }
}

/// A menu item that runs a closure.
final class ClosureItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
