import SwiftUI
import Network
import StreamProtocol

/// What a session window is for: one Mac (a saved one by its Mac ID, any other by its row), or Add a
/// Mac… (pairing by address and code, then the session in the same window). Opening a Mac whose
/// window is open brings that window forward (SwiftUI matches the value), so one Mac has one window,
/// while any number of Macs can stream side by side, each with a client of its own.
struct ViewerTarget: Codable, Hashable {
    /// `address`: DEBUG's `-SillOpenAddresses`, a test host by address (StreamClient's `-SillConnect`
    /// for one window of several); a Release build never makes one.
    enum Kind: String, Codable { case saved, row, add, address }
    var kind: Kind
    /// The saved Mac's ID, the row's ID (`FoundMac.id`), or a fresh one for each Add a Mac… window.
    var key: String
    /// The window's title until the Mac's own name arrives.
    var name: String

    static func saved(_ mac: SavedMac, name: String) -> ViewerTarget { ViewerTarget(kind: .saved, key: mac.macID, name: name) }
    static func row(_ mac: FoundMac) -> ViewerTarget {
        if let id = mac.savedID { return ViewerTarget(kind: .saved, key: id, name: mac.name) }
        return ViewerTarget(kind: .row, key: mac.id, name: mac.name)
    }
    static func add() -> ViewerTarget { ViewerTarget(kind: .add, key: UUID().uuidString, name: "Add a Mac") }

    /// The tile this window belongs to (DevicesWindow): a saved Mac's ID, or the row's.
    var tileKey: String { key }
}

/// Which tiles have a window open, and whether it streams. Main thread.
final class SessionRegistry: ObservableObject {
    static let shared = SessionRegistry()
    enum State { case connecting, connected }
    @Published private(set) var states: [String: State] = [:]

    func set(_ key: String, _ state: State?) {
        if states[key] != state { states[key] = state }
    }
}

/// The last picture of each Mac, for its tile: the thumbnail of the window it streamed (or its
/// frontmost window), kept in Application Support so the tiles show it after a relaunch.
final class TileImages: ObservableObject {
    static let shared = TileImages()
    @Published private(set) var images: [String: NSImage] = [:]
    private var written: [String: Date] = [:]

    private let folder: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("Sill Viewer/Tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func file(_ key: String) -> URL? {
        let safe = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return folder?.appendingPathComponent(safe + ".jpg")
    }

    func image(_ key: String) -> NSImage? {
        if let image = images[key] { return image }
        guard let url = file(key), let image = NSImage(contentsOf: url) else { return nil }
        DispatchQueue.main.async { self.images[key] = image }
        return image
    }

    /// A newer picture: shown at once, written at most every 20 s (and at the session's end, `force`).
    func update(_ key: String, _ image: NSImage, force: Bool = false) {
        if images[key] !== image { images[key] = image }
        guard force || Date().timeIntervalSince(written[key] ?? .distantPast) > 20, let url = file(key),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        written[key] = Date()
        try? jpeg.write(to: url, options: .atomic)
    }
}

/// One session window: finds its Mac among its own client's rows, connects, pairs when the Mac asks
/// for it (the code typed here), and shows the stream once connected. When the session ends the
/// window stays, with why and Reconnect.
struct SessionWindow: View {
    let target: ViewerTarget
    @StateObject private var client = StreamClient()
    @StateObject private var statsReporter = ClientStatsReporter()
    @AppStorage("SillViewer.sendsShortcuts") private var sendsShortcuts = true
    @Environment(\.dismiss) private var dismiss

    /// The dial is under way (looking for the row, or the client connecting); false once it gave up.
    @State private var dialing = false
    /// The row was dialed (`client.connect`); the client takes it from there.
    @State private var dialedRow = false
    @State private var dialStarted = Date()
    @State private var wasConnected = false
    @State private var homeCard: String?
    @State private var lookTimer: Timer?

    private var macName: String {
        if !client.macName.isEmpty { return client.macName }
        if target.kind == .saved, client.savedMac(target.key) != nil { return client.displayName(target.key) }
        return target.name
    }

    var body: some View {
        Group {
            if client.connected {
                StreamScreen(client: client, sendsShortcuts: $sendsShortcuts)
            } else {
                notConnected
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle(macName)
        .focusedSceneObject(client)
        .focusedSceneValue(\.sendsShortcuts, $sendsShortcuts)
        .onAppear(perform: start)
        .onDisappear(perform: end)
        .onChange(of: client.macs) { _, _ in dialIfListed() }
        .onChange(of: client.connected) { _, up in
            if up { wasConnected = true; dialing = false }
            SessionRegistry.shared.set(target.tileKey, up ? .connected : (dialing ? .connecting : nil))
            if !up { saveTile(force: true) }
        }
        .onChange(of: client.thumbnails) { _, _ in saveTile() }
        .onChange(of: client.homeAsk) { _, ask in
            if let ask, ask.phase == .shown { homeCard = ask.name }
            else if ask == nil, homeCard != nil {
                switch client.pairing {
                case .working, .paired: break
                case .idle, .failed: homeCard = nil
                }
            }
        }
        .onChange(of: client.pairing) { old, new in
            if case .paired = old, new == .idle, !client.connected { homeCard = nil }
        }
    }

    // MARK: Before the stream

    @ViewBuilder private var notConnected: some View {
        VStack(spacing: 0) {
            if let link = client.pendingLink {
                card { LinkConfirmationCard(link: link, client: client) }
            } else if target.kind == .add && !wasConnected && homeCard == nil {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add a Mac").font(.title2.weight(.semibold))
                        PairingCard(client: client, home: nil, close: { dismiss() })
                    }
                }
            } else if let mac = homeCard {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(DiscoveryPolicy.HomeCopy.cardTitle(mac: mac)).font(.title2.weight(.semibold))
                        PairingCard(client: client, home: mac, close: {
                            client.cancelPairing()
                            homeCard = nil
                            dialing = false
                        })
                    }
                }
            } else {
                status
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: 480)
                .padding(32)
                .frame(maxWidth: .infinity)
        }
    }

    private var status: some View {
        VStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(macName).font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                if dialing || client.reconnect != nil { ProgressView().controlSize(.small) }
                Text(statusLine)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 420)
            if !dialing && client.reconnect == nil {
                HStack {
                    Button("Close Window") { dismiss() }
                    Button("Connect") { redial() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
        }
        .padding(32)
    }

    private var statusLine: String {
        if dialing && !client.connected && client.homeAsk == nil && Date().timeIntervalSince(dialStarted) < 0.5 {
            return "Looking for \(macName)…"
        }
        let line = client.status
        if line == StreamClient.lookingOnNetwork || line == StreamClient.lookingNearby {
            return dialing ? "Looking for \(macName)…" : "\(macName) isn’t on this network, and Sill couldn’t reach it from afar."
        }
        return line
    }

    // MARK: The dial

    private func start() {
        statsReporter.attach(to: client)
        client.startBrowsing()
        client.startRemote()
        #if DEBUG
        if target.kind == .address {
            let parts = target.key.split(separator: ":")
            if parts.count == 2, let port = NWEndpoint.Port(String(parts[1])) {
                dialing = true
                dialedRow = true
                SessionRegistry.shared.set(target.tileKey, .connecting)
                _ = client.connect(to: .hostPort(host: NWEndpoint.Host(String(parts[0])), port: port), name: target.key)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { watchDial() }
            }
            return
        }
        #endif
        guard target.kind != .add && target.kind != .address else {
            // A sill://pair link from outside (DevicesWindow): its confirmation first.
            if target.key.hasPrefix("link:"), let url = URL(string: String(target.key.dropFirst(5))) { client.handleOpenURL(url) }
            return
        }
        redial()
    }

    private func end() {
        lookTimer?.invalidate()
        saveTile(force: true)
        if client.connected || client.reconnect != nil { client.disconnect() }
        client.cancelPairing()
        SessionRegistry.shared.set(target.tileKey, nil)
    }

    /// Look for the Mac's row again and dial it once listed.
    private func redial() {
        dialing = true
        dialedRow = false
        dialStarted = Date()
        SessionRegistry.shared.set(target.tileKey, .connecting)
        lookTimer?.invalidate()
        // The rows change as the browsers answer; a Remote row comes 3 s after the network's first
        // look, so check again on a clock too. 15 s without a row: give up and say so.
        lookTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !dialing { timer.invalidate(); return }
            dialIfListed()
            if dialing, !client.connected, client.homeAsk == nil, client.pairing == .idle,
               Date().timeIntervalSince(dialStarted) > 15 {
                dialing = false
                timer.invalidate()
                SessionRegistry.shared.set(target.tileKey, nil)
            }
        }
        dialIfListed()
    }

    /// The row to dial: at home (the network, the cable, Direct) at once; through the remote door
    /// only once the network had its 3 s to list the Mac, as the iPad's Remote row waits.
    private func dialIfListed() {
        guard dialing, !dialedRow, !client.connected, client.homeAsk == nil, client.reconnect == nil else { return }
        let rows = client.macs.filter { row in
            switch target.kind {
            case .saved: return row.savedID == target.key
            case .row: return row.id == target.key
            case .add, .address: return false
            }
        }
        let home = rows.first { $0.route != .remote }
        let away = rows.first { $0.route == .remote }
        guard let row = home ?? (Date().timeIntervalSince(dialStarted) > 3.2 ? away : nil) else { return }
        lookTimer?.invalidate()
        lookTimer = nil
        dialedRow = true
        client.connect(to: row)
        // The client says how it goes from here (connecting, asking to pair, why it failed); the
        // window offers Connect again once nothing is under way.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if !client.connected, client.homeAsk == nil { watchDial() } }
    }

    /// After a dial: the window goes back to its Connect button once the client stops trying.
    private func watchDial() {
        let busy = client.connected || client.homeAsk != nil || client.reconnect != nil
            || client.status.hasPrefix("Connecting") || client.status.hasPrefix("Reconnecting") || client.pairing != .idle
        if busy {
            if !client.connected { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { watchDial() } }
            return
        }
        dialing = false
        dialedRow = false
        SessionRegistry.shared.set(target.tileKey, nil)
    }

    // MARK: The tile's picture

    private func saveTile(force: Bool = false) {
        let key = client.savedMacs.first { $0.name == client.macName }.map(\.macID) ?? target.tileKey
        var image: NSImage?
        if case .window(let id) = client.active { image = client.thumbnails[id] }
        if image == nil, let first = client.orderedWindows.first { image = client.thumbnails[first.id] }
        guard let image else { return }
        TileImages.shared.update(key, image, force: force)
        if key != target.tileKey { TileImages.shared.update(target.tileKey, image, force: force) }
    }
}
