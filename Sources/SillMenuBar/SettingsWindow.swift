import AppKit
import SwiftUI
import SillHostCore

/// The Settings window's tabs, in the toolbar's order.
enum SettingsTab: String, CaseIterable {
    case general, devices, streaming, virtualDisplay, permissions, remoteAccess

    var title: String {
        switch self {
        case .general: "General"
        case .devices: "Devices"
        case .streaming: "Streaming"
        case .virtualDisplay: "Virtual Display"
        case .permissions: "Permissions"
        case .remoteAccess: "Remote Access"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .devices: "ipad.and.iphone"
        case .streaming: "play.rectangle"
        case .virtualDisplay: "display"
        case .permissions: "lock.shield"
        case .remoteAccess: "globe"
        }
    }
}

/// Settings, owned by AppKit: toolbar tabs over grouped SwiftUI Forms, so it looks like a SwiftUI
/// Settings scene but opens from anywhere (the menu, ⌘,, reopening the app, onboarding) and is
/// kept off Sill's own virtual display. The window is made once and hidden on close.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private let tabs: SettingsTabController

    init(model: AppModel) {
        self.model = model
        tabs = SettingsTabController(model: model)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        super.init(window: window)
        window.delegate = self
        // Centred the first time; after that where the user left it.
        if !window.setFrameUsingName("SillSettings") { window.center() }
        window.setFrameAutosaveName("SillSettings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Opens Settings in front, on `tab` or the last one shown, and remembers that tab for the
    /// next launch. Remembered here as well as on a tab click: a tab selected while the window
    /// was hidden is not saved by the tab controller (see its `tabView(_:didSelect:)`).
    func show(tab: SettingsTab?) {
        tabs.select(tab ?? model.settings.settingsTab)
        guard let window else { return }
        WindowPlacement.bringForward(window)
        model.visibleSettingsTab = tabs.current
        model.settings.settingsTab = tabs.current
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closed by the user while a permission is still missing: later launches (a login item)
        // stop opening it and only mark the status item.
        model.permissions.refresh()
        if !model.permissions.allGranted { model.settings.permissionsOnboardingDismissed = true }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        model.visibleSettingsTab = nil
    }
}

/// One NSHostingController per tab, sized to its pane, so the window resizes as the tabs change.
@MainActor
final class SettingsTabController: NSTabViewController {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsPane(tab: tab, model: model))
            host.sizingOptions = [.preferredContentSize]
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    var current: SettingsTab {
        let index = max(0, selectedTabViewItemIndex)
        return (tabViewItems[index].identifier as? String).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }

    func select(_ tab: SettingsTab) {
        if let index = tabViewItems.firstIndex(where: { ($0.identifier as? String) == tab.rawValue }) {
            selectedTabViewItemIndex = index
        }
    }

    /// A tab the user picked. Only while the window is on screen: NSTabViewController also
    /// selects its first tab when `NSWindow(contentViewController:)` loads it, before `show`
    /// has read the saved tab, and saving that would reopen Settings on General every launch.
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard view.window?.isVisible == true else { return }
        let tab = current
        model.settings.settingsTab = tab
        model.visibleSettingsTab = tab
    }
}

/// Where Sill's windows appear, and how they come forward.
@MainActor
enum WindowPlacement {
    /// Centres `window` on the main display when it has no screen or sits on the Sill virtual
    /// display (a streamed window lives there, off the user's screens), then activates Sill and
    /// makes the window key. An accessory app's activation can be refused when no click led to
    /// it; the window is then ordered front anyway on the next turn, visible if not key.
    static func bringForward(_ window: NSWindow) {
        if onNoUsefulScreen(window), let area = NSScreen.screens.first?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !window.isKeyWindow { window.orderFrontRegardless() }
            }
        }
    }

    /// A window a device put up (a pairing window it asked for, the cable notice): in front of every
    /// app's windows (over a full-screen app too, with `.fullScreenAuxiliary` in its collection
    /// behavior), off the virtual display, without activating Sill or taking the keyboard, so a
    /// device's request can never swallow what is being typed in another app. A click makes it key.
    /// (docs/home-pairing-plan.md §6.3)
    static func showInFront(_ window: NSWindow) {
        if onNoUsefulScreen(window), let area = NSScreen.screens.first?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        }
        window.orderFrontRegardless()
    }

    private static func onNoUsefulScreen(_ window: NSWindow) -> Bool {
        guard let screen = window.screen else { return true }
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
        return StreamCoordinator.isSillVirtualDisplay(id)
    }
}
