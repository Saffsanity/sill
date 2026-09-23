import AppKit
import SwiftUI
import SillHostCore

/// One line of the status menu, as data. `MenuBuilder` makes the list, the status item turns it
/// into NSMenuItems, and the previews hook prints it to menu.txt, so the three cannot disagree.
struct MenuEntry: Equatable {
    enum Kind: Equatable { case card, item, separator }
    enum Action: Equatable {
        case none
        case allowScreenRecording, allowAccessibility, openPrivacy
        case toggleVirtualDisplay
        case setMaxFPS(Int), setBitrate(Int), setCaptureScale(CGFloat)
        case toggleLaunchAtLogin
        case showLog, showSettings, quit
    }

    var kind: Kind
    var title = ""
    var subtitle: String?
    var checked = false
    var enabled = true
    /// An orange warning in front: something needs the user.
    var attention = false
    /// ⌘ plus this key.
    var key = ""
    var action: Action = .none
    var children: [MenuEntry] = []

    static let separator = MenuEntry(kind: .separator)
}

/// Launch at login as the menu shows it.
struct LoginState: Equatable {
    var available: Bool
    var on: Bool
    var needsApproval: Bool
    var error: String?
}

/// The status menu, top to bottom. Titles are title case, subtitles sentence case. The controls
/// mirror the Settings window and only ever set the app's settings.
enum MenuBuilder {
    static func entries(presentation p: StatusPresentation, config: HostConfig, login: LoginState,
                        permissions: PermissionState) -> [MenuEntry] {
        var menu: [MenuEntry] = [MenuEntry(kind: .card, title: p.header)]
        for a in p.attention {
            let action: MenuEntry.Action = switch a.action {
            case .allowScreenRecording: .allowScreenRecording
            case .allowAccessibility: .allowAccessibility
            case .none: .none
            }
            menu.append(MenuEntry(kind: .item, title: a.title, subtitle: a.subtitle, enabled: action != .none,
                                  attention: true, action: action))
        }
        menu.append(.separator)

        menu.append(MenuEntry(kind: .item, title: "Virtual Display", subtitle: p.virtualDisplayNote,
                              checked: config.virtualDisplay, action: .toggleVirtualDisplay))
        menu.append(MenuEntry(kind: .item, title: "Frame Rate", children: [60, 120].map { fps in
            MenuEntry(kind: .item, title: "Up to \(fps) fps", checked: config.maxFPS == fps, action: .setMaxFPS(fps))
        }))
        var quality = QualityPreset.allCases.map { preset in
            MenuEntry(kind: .item, title: preset.title, checked: config.bitrate == preset.rawValue, action: .setBitrate(preset.rawValue))
        }
        if QualityPreset(rawValue: config.bitrate) == nil {
            quality.append(MenuEntry(kind: .item, title: QualityPreset.title(forBitrate: config.bitrate), checked: true, enabled: false))
        }
        menu.append(MenuEntry(kind: .item, title: "Quality", subtitle: "Per 60 fps; a 120 fps stream gets twice as much",
                              children: quality))
        menu.append(MenuEntry(kind: .item, title: "Resolution", children: [
            MenuEntry(kind: .item, title: "Retina", checked: config.captureScale >= 1.5, action: .setCaptureScale(2)),
            MenuEntry(kind: .item, title: "Standard", subtitle: "A quarter of the pixels; much lighter to encode",
                      checked: config.captureScale < 1.5, action: .setCaptureScale(1)),
        ]))
        menu.append(.separator)

        var loginNote: String?
        if !login.available { loginNote = "Available when Sill runs from its app bundle" }
        else if let error = login.error { loginNote = error }
        else if login.needsApproval { loginNote = "Approve Sill in System Settings › Login Items" }
        menu.append(MenuEntry(kind: .item, title: "Launch at Login", subtitle: loginNote, checked: login.on,
                              enabled: login.available, action: .toggleLaunchAtLogin))
        menu.append(MenuEntry(kind: .item, title: "Permissions", children: [
            permissions.screenRecording
                ? MenuEntry(kind: .item, title: "Screen Recording: Allowed", enabled: false)
                : MenuEntry(kind: .item, title: "Screen Recording: Not Allowed…", action: .allowScreenRecording),
            permissions.accessibility
                ? MenuEntry(kind: .item, title: "Accessibility: Allowed", enabled: false)
                : MenuEntry(kind: .item, title: "Accessibility: Not Allowed…", action: .allowAccessibility),
            .separator,
            MenuEntry(kind: .item, title: "Open Privacy & Security…", action: .openPrivacy),
        ]))
        menu.append(.separator)

        menu.append(MenuEntry(kind: .item, title: "Show Log…", action: .showLog))
        menu.append(MenuEntry(kind: .item, title: "Settings…", key: ",", action: .showSettings))
        menu.append(.separator)
        menu.append(MenuEntry(kind: .item, title: "Quit Sill", key: "q", action: .quit))
        return menu
    }

    /// The menu as text, for the previews: "✓" checked, "⚠" attention, "(off)" disabled.
    static func dump(_ entries: [MenuEntry], card: StatusPresentation? = nil, indent: String = "") -> String {
        var out = ""
        for e in entries {
            switch e.kind {
            case .separator:
                out += indent + "────────\n"
            case .card:
                guard let p = card else { out += indent + "[card]\n"; continue }
                out += indent + "[card] \(p.header)\n"
                if let s = p.subtitle { out += indent + "       \(s)\n" }
                for row in [p.source].compactMap({ $0 }) + p.devices {
                    out += indent + "       · \(row.title)\(row.detail.map { " — \($0)" } ?? "")\n"
                }
            case .item:
                let mark = e.attention ? "⚠ " : (e.checked ? "✓ " : "  ")
                var line = indent + mark + e.title
                if !e.key.isEmpty { line += "  ⌘" + e.key.uppercased() }
                if !e.enabled { line += "  (off)" }
                if let s = e.subtitle { line += "  — \(s)" }
                out += line + (e.children.isEmpty ? "\n" : " ▸\n")
                if !e.children.isEmpty { out += dump(e.children, indent: indent + "    ") }
            }
        }
        return out
    }
}

/// The menu bar item and its menu. The menu is rebuilt each time it opens (permissions and the
/// login item re-read first), and the status card inside it follows the host live while it is
/// open. Every control only sets `model.settings.config`, the one path to the coordinator.
///
/// Its actions are AppKit target/action, the one safe place to start what may run a modal loop
/// (NSApp.terminate): see AppDelegate.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let model: AppModel
    private let card: NSHostingView<LiveStatusCard>
    private var glyph: StatusGlyph.State?
    private var menuOpen = false

    private static let attentionImage: NSImage? = {
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
        let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Needs attention")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }()

    init(model: AppModel) {
        self.model = model
        card = NSHostingView(rootView: LiveStatusCard(model: model))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.autosaveName = "SillStatusItem"
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        show(model.presentation)
    }

    /// The glyph, tooltip and accessibility label for a new presentation.
    func show(_ p: StatusPresentation) {
        guard let button = item.button else { return }
        if glyph != p.glyph {
            glyph = p.glyph
            button.image = StatusGlyph.image(p.glyph)
        }
        button.toolTip = p.tooltip
        button.setAccessibilityLabel(p.accessibilityLabel)
        // A device joining while the menu is open makes the card taller.
        if menuOpen { card.frame.size = card.fittingSize }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.permissions.refresh()
        model.loginItem.refresh()
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private func rebuild() {
        let login = LoginState(available: model.loginItem.available, on: model.loginItem.isOn,
                               needsApproval: model.loginItem.needsApproval, error: model.loginItem.error)
        let permissions = PermissionState(screenRecording: model.permissions.screenRecording,
                                          accessibility: model.permissions.accessibility)
        menu.removeAllItems()
        for entry in MenuBuilder.entries(presentation: model.presentation, config: model.settings.config,
                                         login: login, permissions: permissions) {
            menu.addItem(makeItem(entry))
        }
    }

    private func makeItem(_ e: MenuEntry) -> NSMenuItem {
        switch e.kind {
        case .separator:
            return .separator()
        case .card:
            let cardItem = NSMenuItem()
            card.frame = NSRect(origin: .zero, size: card.fittingSize)
            cardItem.view = card
            return cardItem
        case .item:
            let menuItem = NSMenuItem(title: e.title, action: e.action == .none ? nil : #selector(menuAction(_:)), keyEquivalent: e.key)
            menuItem.target = self
            menuItem.representedObject = e.action
            menuItem.state = e.checked ? NSControl.StateValue.on : .off
            menuItem.isEnabled = e.enabled
            if let subtitle = e.subtitle {
                if #available(macOS 14.4, *) { menuItem.subtitle = subtitle } else { menuItem.toolTip = subtitle }
            }
            if e.attention { menuItem.image = Self.attentionImage }
            if !e.children.isEmpty {
                let submenu = NSMenu(title: e.title)
                submenu.autoenablesItems = false
                for child in e.children { submenu.addItem(makeItem(child)) }
                menuItem.submenu = submenu
            }
            return menuItem
        }
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuEntry.Action else { return }
        switch action {
        case .none: break
        case .allowScreenRecording: model.permissions.requestScreenRecording()
        case .allowAccessibility: model.permissions.requestAccessibility()
        case .openPrivacy: model.permissions.openPrivacyPane()
        case .toggleVirtualDisplay: model.settings.config.virtualDisplay.toggle()
        case .setMaxFPS(let fps): model.settings.config.maxFPS = fps
        case .setBitrate(let bitrate): model.settings.config.bitrate = bitrate
        case .setCaptureScale(let scale): model.settings.config.captureScale = scale
        case .toggleLaunchAtLogin: model.loginItem.set(!model.loginItem.isOn)
        case .showLog: model.showLog?()
        case .showSettings: model.showSettings?(nil)
        case .quit: NSApp.terminate(nil)
        }
    }
}
