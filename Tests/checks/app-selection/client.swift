import Foundation
struct SpatialSourceSize { let source: StreamSource; let size: CGSize }
@MainActor final class StreamClient {
    var connected = true, requiresSpatialCapability = true, supportsSpatialWindows = true
    var suppressSpatialAutoDesktop = false
    var pendingAppSelection: (windowID: UInt32?, bundleID: String?, expires: Date)?
    var spatialPreferredSourceSize: SpatialSourceSize?
    var active: StreamSource = .desktop
    var windows: [WindowInfo] = []
    var runningApps: [AppInfo]? = []
    var resumeSource: StreamSource?
    var choicesSent = 0, status = "Connected"
    var sent: [(StreamMessageKind, Data)] = []
    func clearSpatialPendingSelectionForManualConnect() {}
    func noteAction() {}
    func send(_ kind: StreamMessageKind, _ data: Data) { sent.append((kind, data)) }
    /* CLIENT */
}
struct OpenApp { let bundleID: String; let windows: [WindowInfo] }
@MainActor final class Drawer {
    let client: StreamClient
    var drawerOpen = true
    init(_ client: StreamClient) { self.client = client }
    /* ROW */
}
@main struct ClientCheck {
    @MainActor static func main() {
        var checks = 0
        func expect(_ value: Bool, _ label: String) { checks += 1; precondition(value, label) }
        let editor = "test.editor", other = "test.other"
        let a = WindowInfo(id: 1, title: "A", appName: "Editor", bundleID: editor, width: 800, height: 600)
        var b = a; b.id = 2
        var c = a; c.id = 3; c.bundleID = other
        let client = StreamClient(); client.windows = [a,b,c]
        let drawer = Drawer(client)
        drawer.show(OpenApp(bundleID: editor, windows: [a,b]))
        expect(client.sent.last?.0 == .selectSource && Wire.decode(StreamSource.self, from: client.sent.last!.1) == .window(1), "actual cataloged Apps row sends its first window")
        expect(!drawer.drawerOpen && client.spatialPreferredSourceSize?.size == CGSize(width: 800, height: 600), "row closes drawer and freezes Mac window size before host capture resize")
        expect(client.awaitingAppSelection(active: .none, windows: []) && client.awaitingAppSelection(active: .desktop, windows: [a]), "provisional empty or Desktop snapshots cannot cause immediate autoDesktop to cancel explicit window pick")
        expect(!client.awaitingAppSelection(active: .window(1), windows: [a]), "matching active window acknowledges pick")
        client.active = .window(1)
        drawer.show(OpenApp(bundleID: editor, windows: [a,b]))
        expect(Wire.decode(StreamSource.self, from: client.sent.last!.1) == .window(2), "actual row retains next-window cycling")
        client.runningApps = [AppInfo(name: "Editor", bundleID: editor)]
        client.resumeSource = .desktop
        let choices = client.choicesSent
        drawer.show(OpenApp(bundleID: editor, windows: []))
        expect(client.sent.last?.0 == .launchApp && Wire.decode(LaunchApp.self, from: client.sent.last!.1)?.bundleID == editor, "actual running-without-window row sends launch with no Desktop preselect")
        expect(client.resumeSource == nil && client.choicesSent != choices, "explicit launch invalidates stale transport resume and delayed closed-window Desktop callback choices fence")
        expect(client.awaitingAppSelection(active: .window(3), windows: [c]), "unrelated active source cannot acknowledge launch")
        expect(client.awaitingAppSelection(active: .none, windows: [a]), "catalog appearance without active target does not release Desktop suppression")
        expect(!client.awaitingAppSelection(active: .window(2), windows: [a,b]), "own active app window fulfills launch")
        client.launch(bundleID: editor)
        client.pendingAppSelection?.expires = .distantPast
        let sentBeforeTimeout = client.sent.count
        expect(!client.awaitingAppSelection(active: .desktop, windows: []) && client.pendingAppSelection == nil && client.status.contains("Try Apps again"), "bounded timeout clears waiting without requesting Desktop or replacing the stream")
        expect(client.sent.count == sentBeforeTimeout, "timeout does not send a source change")
        client.launch(bundleID: editor)
        client.resumeSource = .window(3)
        client.select(.desktop)
        expect(client.pendingAppSelection == nil && client.resumeSource == nil, "manual Desktop supersedes pending launch and stale resume")
        let second = StreamClient(); second.launch(bundleID: other)
        expect(client.pendingAppSelection == nil && second.pendingAppSelection?.bundleID == other, "client selection ownership stays within each scene")
        print("app-selection client and actual drawer: \(checks) checks passed")
    }
}
