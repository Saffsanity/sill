import Foundation
struct LaunchApp { let bundleID: String }
enum StreamSource: Equatable { case window(UInt32), desktop }
struct WindowInfo { let id: UInt32; let bundleID: String }
final class Connection {}
@MainActor final class Catalog {
    var infos: [WindowInfo] = []
    var afterRefresh: [WindowInfo]?
    var refreshes = 0
    var onRefresh: (() async -> Void)?
    func refreshWindows() async { refreshes += 1; if let afterRefresh { infos = afterRefresh }; await onRefresh?() }
}
enum WindowCatalog { static let ownPID: Int32 = 123 }
@MainActor final class NSRunningApplication {
    enum Policy { case regular, accessory }
    var activationPolicy = Policy.regular
    var isTerminated = false
    var processIdentifier: Int32 = 456
    var activations = 0, unhides = 0
    struct Options: OptionSet { let rawValue: Int; static let activateAllWindows = Options(rawValue: 1) }
    func activate(options: Options) { activations += 1 }
    func unhide() { unhides += 1 }
    static var apps: [String: NSRunningApplication] = [:]
    static func runningApplications(withBundleIdentifier id: String) -> [NSRunningApplication] { apps[id].map { [$0] } ?? [] }
}
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    final class OpenConfiguration { var activates = true }
    var opens = 0, lastActivates: Bool?
    func urlForApplication(withBundleIdentifier id: String) -> URL? { URL(fileURLWithPath: "/Applications/Fixture.app") }
    func openApplication(at url: URL, configuration: OpenConfiguration, completion: (NSRunningApplication?, Error?) -> Void) {
        opens += 1; lastActivates = configuration.activates; completion(nil, nil)
    }
}
struct Chords { func forget() {} }
@MainActor final class Coordinator {
    var selectionIntent = UUID()
    var pendingLaunch: (bundleID: String, intent: UUID, owner: ObjectIdentifier, expires: Date)?
    var appRestoreTask: Task<Void, Never>?
    var appRestoreOwner: ObjectIdentifier?
    var connections: [ObjectIdentifier: Connection] = [:]
    let catalog = Catalog()
    let gestureChords = Chords()
    var ownsInputFocus = true, switching = false, shuttingDown = false
    var restartOf: StreamSource?
    var pickArrivedWhileSwitching: (source: StreamSource, intent: UUID, owner: ObjectIdentifier?)?
    var picks: [StreamSource] = []
    func select(_ source: StreamSource, bringForward: Bool = false) async {
        precondition(!switching, "pending launch must wait until capture switching completes")
        picks.append(source)
    }
    nonisolated static func restoreMinimizedWindow(pid: Int32) {}
    func launch(_ req: LaunchApp, connection: Connection) async {
        /* LAUNCH */
    }
    /* RESOLVER */
    /* PICKS */
    func admit() -> Connection { let connection = Connection(); connections[ObjectIdentifier(connection)] = connection; return connection }
    func choose(_ source: StreamSource) { selectionIntent = UUID(); pendingLaunch = nil; picks.append(source) }
}
@main struct Check {
    @MainActor static func main() async {
        var checks = 0
        func expect(_ value: Bool, _ label: String) { checks += 1; precondition(value, label) }
        let editor = "test.editor", other = "test.other"
        let a = WindowInfo(id: 1, bundleID: editor), b = WindowInfo(id: 2, bundleID: other)
        let first = Coordinator(), firstConnection = first.admit()
        first.catalog.infos = [b, a]
        await first.launch(LaunchApp(bundleID: editor), connection: firstConnection)
        expect(first.picks == [.window(1)], "All Apps immediately chooses an existing app window without a catalog mutation")
        expect(NSWorkspace.shared.opens == 0 && first.pendingLaunch == nil, "existing app does not reopen or leave a deferred selection")
        _ = await first.selectPendingAppWindow()
        expect(first.picks.count == 1, "later background window updates do not steal selection")

        let busy = Coordinator(), busyConnection = busy.admit()
        busy.catalog.infos = [a]; busy.switching = true
        await busy.launch(LaunchApp(bundleID: editor), connection: busyConnection)
        expect(busy.picks.isEmpty && busy.pendingLaunch != nil, "existing app pick waits through an in-flight capture switch")
        busy.switching = false
        expect(await busy.selectPendingAppWindow() && busy.picks == [.window(1)], "existing app is selected after switching settles")

        let running = NSRunningApplication(); NSRunningApplication.apps[editor] = running
        let minimized = Coordinator(), minimizedConnection = minimized.admit()
        minimized.catalog.afterRefresh = [a]
        await minimized.launch(LaunchApp(bundleID: editor), connection: minimizedConnection)
        expect(minimized.picks == [.window(1)] && minimized.catalog.refreshes == 1, "restored minimized app selects its refreshed window")
        expect(running.activations == 1 && running.unhides == 1, "explicit minimized selection activates its app")
        let minimizedBusy = Coordinator(), minimizedBusyConnection = minimizedBusy.admit()
        minimizedBusy.catalog.afterRefresh = [a]; minimizedBusy.switching = true
        let opensBeforeBusy = NSWorkspace.shared.opens
        await minimizedBusy.launch(LaunchApp(bundleID: editor), connection: minimizedBusyConnection)
        expect(NSWorkspace.shared.opens == opensBeforeBusy, "matching restored window during capture switch never reopens app")
        expect(minimizedBusy.picks.isEmpty && minimizedBusy.pendingLaunch != nil, "restored minimized window waits for capture switch")
        minimizedBusy.switching = false
        expect(await minimizedBusy.selectPendingAppWindow() && minimizedBusy.picks == [.window(1)], "restored minimized window selects when capture settles")
        let superseded = Coordinator(), supersededConnection = superseded.admit()
        superseded.catalog.afterRefresh = [a]
        superseded.catalog.onRefresh = { superseded.choose(.window(2)) }
        await superseded.launch(LaunchApp(bundleID: editor), connection: supersededConnection)
        expect(superseded.picks == [.window(2)] && superseded.pendingLaunch == nil, "new user pick during restore refresh supersedes app selection")
        let windowless = Coordinator(), windowlessConnection = windowless.admit()
        await windowless.launch(LaunchApp(bundleID: editor), connection: windowlessConnection)
        expect(windowless.picks.isEmpty && windowless.pendingLaunch != nil, "running app remains pending through an empty restore refresh")
        expect(NSWorkspace.shared.opens == 1, "windowless running app receives a reopen event")
        windowless.catalog.infos = [b]
        expect(await windowless.selectPendingAppWindow() == false, "another app cannot fulfill delayed restoration")
        windowless.catalog.infos = [a]
        expect(await windowless.selectPendingAppWindow() && windowless.picks == [.window(1)], "delayed restored, unhidden or fullscreen app window is eventually selected")
        let reopened = Coordinator(), reopenedConnection = reopened.admit()
        reopened.catalog.afterRefresh = [a]
        reopened.catalog.onRefresh = { _ = await reopened.selectPendingAppWindow() }
        let opensBeforeCallback = NSWorkspace.shared.opens
        await reopened.launch(LaunchApp(bundleID: editor), connection: reopenedConnection)
        expect(NSWorkspace.shared.opens == opensBeforeCallback, "refresh callback that consumed pending intent cannot trigger an extra reopen")
        expect(reopened.picks == [.window(1)] && reopened.pendingLaunch == nil, "catalog callback and direct refresh consume the same intent only once")

        let closing = Coordinator(), closingConnection = closing.admit()
        closing.catalog.onRefresh = { closing.shuttingDown = true }
        let opensBeforeClose = NSWorkspace.shared.opens
        await closing.launch(LaunchApp(bundleID: editor), connection: closingConnection)
        expect(closing.picks.isEmpty && NSWorkspace.shared.opens == opensBeforeClose, "shutdown during refresh prevents selection and reopen")
        let queued = Coordinator(), queuedConnection = queued.admit()
        queued.switching = true
        await queued.handlePick(.window(1), owner: ObjectIdentifier(queuedConnection))
        expect(queued.pickArrivedWhileSwitching?.source == .window(1), "cataloged Apps row survives a switch to a different source")
        let oldPick = queued.pickArrivedWhileSwitching!
        queued.switching = false
        await queued.applyQueuedPick(oldPick)
        expect(queued.picks == [.window(1)], "queued explicit window is replayed after switching")
        queued.selectionIntent = UUID()
        await queued.applyQueuedPick(oldPick)
        expect(queued.picks.count == 1, "newer launch or pick invalidates already scheduled queue replay")
        let disconnect = Coordinator(), disconnectedConnection = disconnect.admit()
        disconnect.switching = true
        await disconnect.handlePick(.window(1), owner: ObjectIdentifier(disconnectedConnection))
        disconnect.switching = false; disconnect.connections = [:]
        await disconnect.applyQueuedPick(disconnect.pickArrivedWhileSwitching!)
        expect(disconnect.picks.isEmpty, "disconnected scene cannot replay its queued selection")

        NSRunningApplication.apps = [:]
        let fresh = Coordinator(), freshConnection = fresh.admit()
        await fresh.launch(LaunchApp(bundleID: editor), connection: freshConnection)
        expect(fresh.picks.isEmpty && fresh.pendingLaunch?.bundleID == editor, "new app waits for its own window")
        expect(NSWorkspace.shared.lastActivates == false, "new app launch itself does not take focus before window selection")
        fresh.catalog.infos = [b]
        expect(await fresh.selectPendingAppWindow() == false && fresh.picks.isEmpty, "unrelated app window cannot fulfill launch")
        fresh.catalog.infos = [b, a]; fresh.switching = true
        expect(await fresh.selectPendingAppWindow() == false && fresh.pendingLaunch != nil, "capture restart retains pending selection")
        fresh.switching = false
        expect(await fresh.selectPendingAppWindow() && fresh.picks == [.window(1)] && fresh.pendingLaunch == nil, "unchanged poll after capture restart fulfills pending launch exactly once")

        let second = Coordinator(), secondConnection = second.admit()
        await second.launch(LaunchApp(bundleID: other), connection: secondConnection)
        second.catalog.infos = [a, b]
        _ = await second.selectPendingAppWindow()
        expect(second.picks == [.window(2)] && fresh.picks == [.window(1)], "each scene consumes only its own app request")
        for invalidation in 0..<4 {
            let stale = Coordinator(), connection = stale.admit()
            await stale.launch(LaunchApp(bundleID: editor), connection: connection)
            if invalidation == 0 { stale.selectionIntent = UUID() }
            if invalidation == 1 { stale.connections = [:] }
            if invalidation == 2 { stale.pendingLaunch?.expires = Date.distantPast }
            if invalidation == 3 { stale.shuttingDown = true }
            stale.catalog.infos = [a]
            expect(await stale.selectPendingAppWindow() == false && stale.picks.isEmpty && stale.pendingLaunch == nil, "superseded, disconnected, expired or closing request cannot select")
        }
        print("app-selection: \(checks) checks passed")
    }
}
