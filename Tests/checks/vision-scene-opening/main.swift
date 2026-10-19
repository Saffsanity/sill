import Foundation
// Deliberately execute canceled callbacks too, so stale callback guards are tested directly.
final class DispatchWorkItem {
    let body: () -> Void
    init(block: @escaping () -> Void) { body = block }
    func cancel() {}
    func perform() { body() }
}
enum Scheduler { static var pending: [DispatchWorkItem] = [] }
enum StreamSource: Equatable { case window(UInt32), desktop }
struct WindowInfo { let id: UInt32; var bundleID = "test.editor" }
struct WindowList { let windows: [WindowInfo] }
struct LaunchApp { let bundleID: String }
enum Wire { static func encode(_ app: LaunchApp) -> LaunchApp { app } }
enum MessageKind { case launchApp }
final class Connection { enum State { case ready, cancelled }; var state = State.ready }
final class Client {
    var connection: Connection? = Connection()
    var active: StreamSource = .desktop
    var windows: [WindowInfo] = []
    var resumeSource: StreamSource?
    var pendingAppSelection: (windowID: UInt32?, bundleID: String?, expires: Date)?
    var spatialWorkspaceClearGeneration = 0
    var pendingSpatialWorkspace: Int?
    var pendingSpatialWorkspaceSource: StreamSource?
    var spatialPreservesRestoredSize = false
    var spatialRestoredSize: CGSize?
    var pendingSpatialSource: StreamSource?
    var pendingSpatialSourceSize: CGSize?
    var pendingSpatialSourceTimeout: DispatchWorkItem?
    var pendingSpatialSourceTimeoutID: UUID?
    var spatialPreferredSourceSize: CGSize?
    var suppressSpatialAutoDesktop = false
    var status = "", disconnects = 0
    var requests: [StreamSource] = []
    var desktopFallbacks = 0
    var requiresSpatialCapability = true, supportsSpatialWindows = true, choicesSent = 0
    var appLaunches: [String] = []
    func send(_ kind: MessageKind, _ app: LaunchApp) { appLaunches.append(app.bundleID) }
    /* CLEAR */
    /* SELECT */
    /* LAUNCH */
    func noteAction() {}
    func disconnect() { clearSpatialPendingSelectionForManualConnect(); disconnects += 1; connection = nil }
    func request(_ source: StreamSource, spatialSnapshot: CGSize? = nil) { requests.append(source) }
    func receive(_ list: WindowList) {
        let from = connection
        /* RECEIVER */
        if requests.isEmpty { desktopFallbacks += 1 }
    }
}
func CGPreflightScreenCaptureAccess() -> Bool { true }
final class Catalog {
    var infos: [WindowInfo] = []
    var read: (() -> Void)?
    func start() {}
    func refreshWindows() async { read?() }
}
final class Server {
    var lists: [[WindowInfo]] = []
    var activates = 0
    var onActivate: (() -> Void)?
    func broadcast(_ list: [WindowInfo]) { lists.append(list) }
    func activateScopedSession(_ connection: Connection, route: Int, link: Int) { activates += 1; onActivate?() }
}
final class Host {
    var isIndependent = true, shuttingDown = false
    var independentCoordinators: [UUID: Host] = [:]
    var catalog = Catalog(), server = Server()
    func listMessage() -> [WindowInfo] { catalog.infos }
    /* BROADCAST */
    /* SEND_GUARD */
    func bootstrap(child: Host, id: UUID, connection: Connection) async {
        let scoped = child.server, route = 0, link = 0
        /* BOOTSTRAP */
    }
}
@main struct Check {
    static func main() async {
        var checks = 0
        func expect(_ value: Bool, _ label: String) { checks += 1; precondition(value, label) }
        let target = WindowInfo(id: 42)
        let client = Client(); client.pendingSpatialSource = .window(42)
        client.receive(WindowList(windows: []))
        let oldTimeout = Scheduler.pending.last!
        expect(client.pendingSpatialSource == .window(42) && client.requests.isEmpty && client.desktopFallbacks == 0, "early empty child catalog must preserve seed and suppress automatic Desktop")
        client.receive(WindowList(windows: []))
        expect(Scheduler.pending.count == 1, "unchanged empty polls cannot extend deadline")
        client.receive(WindowList(windows: [target]))
        expect(client.requests == [.window(42)] && client.pendingSpatialSource == nil, "later real catalog automatically selects seeded Mac window")
        oldTimeout.perform()
        expect(client.disconnects == 0, "timer cannot disconnect selected window after fulfillment")
        let sibling = Client(); sibling.select(.window(5))
        let pending = Client(); pending.pendingSpatialSource = .window(42)
        pending.receive(WindowList(windows: []))
        let supersededTimeout = Scheduler.pending.last!
        pending.select(.window(7))
        pending.receive(WindowList(windows: [target])); supersededTimeout.perform()
        expect(pending.requests == [.window(7)] && pending.disconnects == 0, "manual selection supersedes seed and stale timeout")
        expect(sibling.requests == [.window(5)] && sibling.disconnects == 0, "sibling stream stays independent")
        let appChoice = Client(); appChoice.pendingSpatialSource = .window(42)
        appChoice.receive(WindowList(windows: [])); let appChoiceTimeout = Scheduler.pending.last!
        appChoice.launch(bundleID: "test.editor")
        appChoice.receive(WindowList(windows: [target])); appChoiceTimeout.perform()
        expect(appChoice.appLaunches == ["test.editor"] && appChoice.requests.isEmpty && appChoice.disconnects == 0, "explicit Apps choice cancels seed and stale timeout")
        let unsupported = Client(); unsupported.supportsSpatialWindows = false
        unsupported.launch(bundleID: "test.editor")
        expect(unsupported.appLaunches.isEmpty, "spatial app launch requires independent-host capability")
        let reconnected = Client(); reconnected.pendingSpatialSource = .window(42)
        reconnected.receive(WindowList(windows: [])); let previousConnectionTimeout = Scheduler.pending.last!
        reconnected.connection = Connection()
        previousConnectionTimeout.perform()
        expect(reconnected.disconnects == 0, "old connection timer cannot end replacement connection")
        let renewed = Client(); renewed.pendingSpatialSource = .window(42)
        renewed.receive(WindowList(windows: [])); let oldRequestTimeout = Scheduler.pending.last!
        renewed.clearSpatialPendingSelectionForManualConnect()
        renewed.pendingSpatialSource = .window(42)
        renewed.receive(WindowList(windows: [])); oldRequestTimeout.perform()
        expect(renewed.disconnects == 0 && renewed.pendingSpatialSource == .window(42), "old timer cannot end newer request for same source on same connection")
        let disconnected = Client(); disconnected.pendingSpatialSource = .window(42)
        disconnected.receive(WindowList(windows: [])); let disconnectedTimeout = Scheduler.pending.last!
        disconnected.disconnect(); disconnectedTimeout.perform()
        expect(disconnected.disconnects == 1, "scene disconnect cancels deferred launch timer")
        let missing = Client(); missing.pendingSpatialSource = .window(42)
        missing.receive(WindowList(windows: [])); Scheduler.pending.last!.perform()
        expect(missing.disconnects == 1 && missing.pendingSpatialSource == nil && !missing.status.isEmpty, "closed or unreadable target ends with visible reconnect-screen error")
        let desktop = Client(); desktop.pendingSpatialSource = .desktop
        desktop.receive(WindowList(windows: []))
        expect(desktop.requests == [.desktop], "Desktop seed does not need a window catalog entry")

        let root = Host(), child = Host(), id = UUID(), connection = Connection()
        root.independentCoordinators[id] = child
        child.catalog.read = {
            child.broadcastList() // refreshRunningApps occurs before reading the windows.
            child.sendCatalog(to: connection) // An early direct publication must be guarded too.
            expect(child.server.lists.isEmpty && child.server.activates == 0, "provisional running-app callback cannot publish empty initial list")
            child.catalog.infos = [target]
            child.broadcastList() // onWindowsChanged can run before activation too.
        }
        child.server.onActivate = { child.broadcastList() }
        await root.bootstrap(child: child, id: id, connection: connection)
        expect(child.server.activates == 1 && child.server.lists.count == 1 && child.server.lists[0].map(\.id) == [42], "first published child catalog follows initial window read")
        for termination in 0..<3 {
            let closed = Host(), closeID = UUID(), closeConnection = Connection()
            root.independentCoordinators[closeID] = closed
            closed.catalog.read = {
                if termination == 0 { root.independentCoordinators[closeID] = nil }
                if termination == 1 { closed.shuttingDown = true }
                if termination == 2 { closeConnection.state = .cancelled }
            }
            await root.bootstrap(child: closed, id: closeID, connection: closeConnection)
            expect(closed.server.activates == 0 && closed.server.lists.isEmpty, "closing or replaced pipeline cannot activate after awaited catalog read")
        }
        print("vision-scene-opening: \(checks) checks passed")
    }
}
