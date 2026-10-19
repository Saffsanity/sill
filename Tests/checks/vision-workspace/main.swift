import Foundation

final class DispatchWorkItem {
    let body: () -> Void
    init(block: @escaping () -> Void) { body = block }
    func cancel() {}
    func perform() { body() }
}
enum Scheduler { static var pending: [DispatchWorkItem] = [] }
final class Connection {}
struct RestoreCatalog { var windows: [WindowInfo]; var active: StreamSource = .none }
final class RestoreClient {
    var connection: Connection? = Connection()
    var pendingSpatialWorkspace: VisionWorkspace?
    var pendingSpatialWorkspaceSource: StreamSource?
    var pendingSpatialSourceTimeout: DispatchWorkItem?
    var pendingSpatialSourceTimeoutID: UUID?
    var windows: [WindowInfo] = []
    var active: StreamSource = .none
    var status = ""
    var requests: [StreamSource] = []
    var disconnects = 0
    var acknowledged = 0
    func cancelSpatialSourceTimeout() {
        pendingSpatialSourceTimeout?.cancel()
        pendingSpatialSourceTimeout = nil
        pendingSpatialSourceTimeoutID = nil
    }
    func request(_ source: StreamSource) { requests.append(source) }
    func disconnect(preservingWorkspace: Bool) {
        cancelSpatialSourceTimeout()
        pendingSpatialWorkspace = nil
        pendingSpatialWorkspaceSource = nil
        disconnects += 1
        connection = nil
    }
    /* REQUEST */
    func receive(_ list: RestoreCatalog) {
        let from = connection
        windows = list.windows
        active = list.active
        /* RECEIVER */
        acknowledged += 1
    }
}
final class PresentationClient {
    var connected = true
    var connectedAt: Date? = Date(timeIntervalSince1970: 1)
    var active: StreamSource = .desktop
    var spatialPresentationSession: Date?
    var spatialPresentationSource: StreamSource?
    var spatialPresentationSize: CGSize?
    /* PRESENTATION */
}
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
func info(_ id: UInt32, _ title: String, bundle: String = "test.editor") -> WindowInfo {
    WindowInfo(id: id, title: title, appName: "Editor", bundleID: bundle, width: 1000, height: 700)
}
let original = info(1, "Synthetic document")
let saved = VisionWorkspace(macID: "synthetic-paired-id", window: .init(original), width: 2400, height: 1680)
expect(VisionWorkspace.decode(saved.encoded) == saved, "Descriptor round-trips")
expect(!saved.encoded.contains(original.title), "Raw document title is not persisted")
expect(!saved.encoded.contains("fingerprint") && !saved.encoded.contains("recognitionKey") && !saved.encoded.contains("keyboard"), "No credentials or keyboard state in descriptor")
expect(saved.source(in: [info(9, original.title)]) == .window(9), "Identity survives changed ephemeral ID")
expect(saved.source(in: [info(1, "Other", bundle: "test.other")]) == .desktop, "Recycled ID cannot choose another app")
expect(saved.source(in: [info(1, "Other"), info(2, "Third")]) == .desktop, "Recycled ID cannot choose ambiguous same-app window")
expect(saved.source(in: [info(8, "Changed title")]) == .window(8), "Unique same-app fallback tolerates title changes")
expect(saved.source(in: [info(8, original.title), info(9, original.title)]) == .desktop, "Duplicate exact titles are ambiguous")
expect(saved.source(in: []) == .desktop, "Missing app falls back without launch")
expect(saved.reconciledSource(in: [], allowFallback: false) == nil, "Empty catalog waits before fallback")
expect(saved.reconciledSource(in: [info(8, "Changed title")], allowFallback: false) == nil, "Partial catalog cannot select sole-app fallback early")
expect(VisionWorkspace(macID: "synthetic-paired-id").reconciledSource(in: [], allowFallback: false) == .desktop, "Desktop restores without catalog wait")
expect(VisionWorkspace.decode(String(repeating: "a", count: 4097)) == nil, "Oversized storage rejected")
expect(VisionWorkspace.decode(saved.encoded.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")) == nil, "Unknown schema rejected")
expect(VisionWorkspace.decode("{\"version\":1,\"macID\":\"id\",\"width\":4000,\"height\":700}") == nil, "Oversized native size rejected")
expect(VisionWorkspace.decode("{\"version\":1,\"macID\":\"id\",\"width\":700}") == nil, "Incomplete native size rejected")
let client = RestoreClient(); client.pendingSpatialWorkspace = saved
client.receive(.init(windows: []))
expect(client.requests.isEmpty && client.pendingSpatialWorkspace == saved, "Initial empty catalog preserves pending descriptor")
let staleGrace = Scheduler.pending.last!
client.receive(.init(windows: [info(9, original.title)]))
let ackTimeout = Scheduler.pending.last!
expect(client.requests == [.window(9)] && client.pendingSpatialWorkspace == saved, "Resolved selection remains pending until acknowledgement")
staleGrace.perform()
expect(client.requests == [.window(9)], "Canceled warmup grace cannot overwrite exact match")
client.receive(.init(windows: [info(9, original.title)], active: .window(9)))
expect(client.pendingSpatialWorkspace == nil && client.acknowledged == 1, "Host acknowledgement completes restore")
ackTimeout.perform()
expect(client.disconnects == 0, "Late timeout cannot disconnect acknowledged session")
let absent = RestoreClient(); absent.pendingSpatialWorkspace = saved
absent.receive(.init(windows: [])); Scheduler.pending.last!.perform()
expect(absent.requests == [.desktop] && absent.pendingSpatialWorkspace != nil, "Grace ends with bounded Desktop fallback, still awaiting acknowledgement")
absent.receive(.init(windows: [], active: .desktop))
expect(absent.pendingSpatialWorkspace == nil, "Desktop fallback acknowledgement completes restore")
let closed = RestoreClient(); closed.pendingSpatialWorkspace = saved
closed.receive(.init(windows: [])); let closeGrace = Scheduler.pending.last!
closed.pendingSpatialWorkspace = nil; closeGrace.perform()
expect(closed.requests.isEmpty, "Manual cancellation prevents delayed restore")
let replacement = RestoreClient(); replacement.pendingSpatialWorkspace = saved
replacement.receive(.init(windows: [])); let oldGrace = Scheduler.pending.last!
replacement.connection = Connection(); oldGrace.perform()
expect(replacement.requests.isEmpty, "Old connection grace cannot act on replacement")
let stalled = RestoreClient(); stalled.pendingSpatialWorkspace = saved
stalled.receive(.init(windows: [info(9, original.title)])); Scheduler.pending.last!.perform()
expect(stalled.disconnects == 1 && !stalled.status.isEmpty, "Unacknowledged restore ends with visible bounded failure")
let unrelated = RestoreClient(); unrelated.pendingSpatialWorkspace = saved
unrelated.receive(.init(windows: [info(9, original.title)]))
unrelated.receive(.init(windows: [info(9, original.title)], active: .desktop))
expect(unrelated.pendingSpatialWorkspace == saved && unrelated.acknowledged == 0, "Transient unrelated active source cannot finish or overwrite restoration")
let presentation = PresentationClient()
let stamp = presentation.connectedAt
let small = CGSize(width: 1400, height: 787.5), large = CGSize(width: 2400, height: 1350)
presentation.noteSpatialPresentationSize(small, source: .desktop, session: stamp)
expect(presentation.spatialPresentationSize == nil, "Unconfirmed initial root geometry cannot overwrite remembered size")
presentation.noteSpatialPresentationSize(small, source: .desktop, session: stamp, confirmed: true)
presentation.noteSpatialPresentationSize(large, source: .desktop, session: stamp)
expect(presentation.spatialPresentationSize == large, "Native resize after confirmed lock updates remembered scene size")
presentation.connectedAt = Date(timeIntervalSince1970: 2)
presentation.noteSpatialPresentationSize(small, source: .desktop, session: stamp, confirmed: true)
expect(presentation.spatialPresentationSize == large, "Queued confirmation from old connection cannot overwrite new scene size")
presentation.noteSpatialPresentationSize(small, source: .desktop, session: presentation.connectedAt)
expect(presentation.spatialPresentationSize == large, "New connection waits for its own lock confirmation")
presentation.active = .window(8)
presentation.noteSpatialPresentationSize(small, source: .desktop, session: presentation.connectedAt, confirmed: true)
expect(presentation.spatialPresentationSize == large, "Stale source confirmation cannot overwrite current source geometry")
print("vision-workspace: \(checks) checks passed")
