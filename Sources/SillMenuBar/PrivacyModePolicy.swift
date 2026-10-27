import CoreGraphics
import Foundation

/// Privacy Mode on the Mac (issues #133 and #141): when Sill blanks the Mac's physical displays
/// during an active session (so people near the Mac cannot see what is being streamed) and when it
/// locks the Mac after the last connected device disconnects.
///
/// Pure (CoreGraphics and Foundation only), so `Tests/checks/privacy-mode` compiles it on its own.
enum PrivacyModePolicy {
    /// One display attached to the Mac.
    struct Screen: Equatable, Sendable {
        var id: UInt32
        var frame: CGRect
        var sillVirtual: Bool

        init(id: UInt32, frame: CGRect, sillVirtual: Bool) {
            self.id = id
            self.frame = frame
            self.sillVirtual = sillVirtual
        }
    }

    /// What a transition decides: whether the black shield windows should be on screen, whether the
    /// Mac console should be locked now, and the log lines to print.
    struct Decision: Equatable, Sendable {
        var shieldActive: Bool
        var shouldLock: Bool
        var logLines: [String]
    }

    /// Tracks whether the privacy shield is currently shown and whether at least one device was
    /// connected prior to the current update.
    struct State: Equatable, Sendable {
        private(set) var shieldActive = false
        private(set) var hadConnectedDevices = false

        init() {}

        mutating func update(
            privacyMode: Bool,
            lockOnDisconnect: Bool,
            connectedDevices: Int,
            consoleUnlocked: Bool,
            physicalScreens: Int,
            shuttingDown: Bool
        ) -> Decision {
            let wantShield = privacyMode && connectedDevices > 0 && physicalScreens > 0 && !shuttingDown
            let lastDisconnected = hadConnectedDevices && connectedDevices == 0
            let shouldLock = lastDisconnected && lockOnDisconnect && consoleUnlocked && !shuttingDown

            var lines: [String] = []
            if wantShield && !shieldActive {
                let target = physicalScreens == 1 ? "the display" : "\(physicalScreens) displays"
                lines.append("Privacy mode: blanking \(target) while a device is connected.")
            } else if !wantShield && shieldActive {
                lines.append("Privacy mode: restored the display.")
            }
            if shouldLock {
                lines.append("Privacy mode: locking this Mac after the last device disconnected.")
            }

            shieldActive = wantShield
            hadConnectedDevices = connectedDevices > 0
            return Decision(shieldActive: wantShield, shouldLock: shouldLock, logLines: lines)
        }
    }

    /// Physical displays that should be covered by a black privacy shield window: never Sill's own
    /// virtual display, and never a zero-area frame.
    static func shieldScreens(_ screens: [Screen]) -> [Screen] {
        screens.filter { !$0.sillVirtual && $0.frame.width > 0 && $0.frame.height > 0 }
    }

    /// Copy for Settings › Remote Access (and General).
    enum Copy {
        static let sectionHeader = "Privacy"
        static let blankToggle = "Blank display while connected"
        static let lockToggle = "Lock this Mac when the last device disconnects"
        static let footnote = "Covers this Mac’s physical displays with a black screen while a device is connected (your streamed windows still reach your iPhone or iPad), and locks the screen when the last device disconnects."
    }
}

#if canImport(AppKit) && canImport(SillHostCore)
import AppKit
import Darwin
import SillHostCore

/// Owns the black screen-saver-level shield windows on the Mac's physical displays and triggers
/// the screen lock when the last device disconnects (`PrivacyModePolicy`, issues #133 and #141).
@MainActor
final class PrivacyShieldController {
    private var state = PrivacyModePolicy.State()
    private var windows: [UInt32: NSWindow] = [:]
    private var shuttingDown = false
    private var lastPrivacyMode = false
    private var lastLockOnDisconnect = false
    private var lastConnectedDevices = 0
    private var lastSynthetic = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged(_ notification: Notification) {
        update(
            privacyMode: lastPrivacyMode,
            lockOnDisconnect: lastLockOnDisconnect,
            connectedDevices: lastConnectedDevices,
            synthetic: lastSynthetic
        )
    }

    func update(privacyMode: Bool, lockOnDisconnect: Bool, connectedDevices: Int, synthetic: Bool) {
        lastPrivacyMode = privacyMode
        lastLockOnDisconnect = lockOnDisconnect
        lastConnectedDevices = connectedDevices
        lastSynthetic = synthetic

        let screens = PrivacyModePolicy.shieldScreens(Self.currentScreens())
        let testHost = synthetic && !AppModel.bundled
        let unlocked = SessionLock.shared.unlocked(testHost: testHost)
        let decision = state.update(
            privacyMode: privacyMode,
            lockOnDisconnect: lockOnDisconnect,
            connectedDevices: connectedDevices,
            consoleUnlocked: unlocked,
            physicalScreens: screens.count,
            shuttingDown: shuttingDown
        )
        for line in decision.logLines {
            print(line)
        }
        if decision.shieldActive && !synthetic {
            syncWindows(to: screens)
        } else {
            closeAllWindows()
        }
        if decision.shouldLock && !synthetic {
            Self.lockScreen()
        }
    }

    func tearDownForQuit(privacyMode: Bool, lockOnDisconnect: Bool, connectedDevices: Int, synthetic: Bool) {
        shuttingDown = true
        update(privacyMode: privacyMode, lockOnDisconnect: lockOnDisconnect, connectedDevices: connectedDevices, synthetic: synthetic)
    }

    private func syncWindows(to screens: [PrivacyModePolicy.Screen]) {
        let keep = Set(screens.map(\.id))
        for (id, window) in windows where !keep.contains(id) {
            window.orderOut(nil)
            window.close()
            windows.removeValue(forKey: id)
        }
        for screen in screens {
            let window = windows[screen.id] ?? Self.makeShieldWindow(frame: screen.frame)
            windows[screen.id] = window
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: true)
            }
            window.orderFrontRegardless()
        }
    }

    private func closeAllWindows() {
        guard !windows.isEmpty else { return }
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private static func makeShieldWindow(frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.sharingType = .none
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }

    private static func currentScreens() -> [PrivacyModePolicy.Screen] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return PrivacyModePolicy.Screen(
                id: id,
                frame: screen.frame,
                sillVirtual: StreamCoordinator.isSillVirtualDisplay(id)
            )
        }
    }

    private static func lockScreen() {
        typealias LockFn = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "SACLockScreenImmediate") {
                unsafeBitCast(sym, to: LockFn.self)()
            }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }
}
#endif
