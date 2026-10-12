import AppKit
import AVFoundation
import Combine
import StreamProtocol

/// The other Mac's windows as this Mac's windows. Each window opened from the status item (and the
/// Desktop) is a window here, sized 1:1 in points to the window there, with no frame of its own: the
/// title bar is transparent and the picture fills it, so the other window's own title bar and
/// buttons sit under this window's, which close and minimize it here.
///
/// Every window open here is live. The key one is the host's main stream (kind 6, full rate, the one
/// input goes to); the stream view (`StreamInputView`, the client's display) moves to it. Each other
/// window of the host's is a side stream (kinds 29–31) at a lower rate, drawn by the window's own
/// layer (`SideView`); a host before side streams leaves them on its latest thumbnail. Focusing a
/// window makes it the main stream; its side picture stays until the main stream's first keyframe.
/// Main thread.
/// DEBUG: what the window manager does, on stderr ("windows: …").
func windowLog(_ line: @autoclosure () -> String) {
    #if DEBUG
    FileHandle.standardError.write(Data("windows: \(line())\n".utf8))
    #endif
}

final class StreamWindows: NSObject, NSWindowDelegate {
    private let client: StreamClient
    private(set) lazy var input: StreamInputView = {
        let view = StreamInputView(client: client)
        view.live = live
        return view
    }()
    /// A drag of files followed live on the other Mac (kind 38).
    private lazy var live = LiveDrop(client: client)
    private var open: [StreamSource: StreamWindow] = [:]
    /// The window whose stream the picture shows, once the host has switched to it.
    private var showing: StreamSource?
    private var subscriptions = Set<AnyCancellable>()
    /// Where the main stream is drawn: the focused window's own layer, switched when the new
    /// stream's parameter sets arrive (MainRouter), so no window ever shows another's picture.
    private let router = MainRouter()
    /// The last source this Mac asked the host for (a focus): the host drops a pick that comes while
    /// it is still switching, so one its list does not name is asked for again.
    private var requested: StreamSource?
    /// A Dock icon per remote app with a window open here.
    let dock = DockProxies()
    /// The focused window's controls (close, minimize, full screen, its title), above it.
    private let pill = WindowPill()
    /// Every window the host has listed this session: a window new to it opens here by itself when
    /// its app has a window open here (a new document, a dialog).
    private var known: Set<UInt32>?
    /// Each window's app, as the host last listed it (kept after the window leaves the list).
    private var appOf: [UInt32: String] = [:]

    init(client: StreamClient) {
        self.client = client
        super.init()
        client.$active.removeDuplicates().sink { [weak self] active in
            DispatchQueue.main.async { self?.activeChanged(active) }
        }.store(in: &subscriptions)
        client.$windows.sink { [weak self] list in
            DispatchQueue.main.async { self?.windowsChanged(list) }
        }.store(in: &subscriptions)
        // An app's icon can come after its Dock icon started: it is badged and shown then.
        client.$icons.sink { [weak self] _ in DispatchQueue.main.async { self?.syncDock() } }.store(in: &subscriptions)
        client.$thumbnails.sink { [weak self] thumbs in
            DispatchQueue.main.async { self?.thumbnailsChanged(thumbs) }
        }.store(in: &subscriptions)
        client.$hostSideStreams.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.requestSideStreams() }
        }.store(in: &subscriptions)
        client.$hostAudio.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.requestSideStreams() }
        }.store(in: &subscriptions)
        let feeds = sideFeeds, route = router
        // A window the main stream draws into takes no side frames: its side stream is on its way out.
        client.onSideParameterSets = { id, ps in
            guard let feed = feeds.get(id), !route.draws(into: feed) else { return }
            feed.apply(ps)
        }
        client.onSideFrame = { id, data, isKey in
            guard let feed = feeds.get(id), !route.draws(into: feed) else { return }
            feed.enqueue(data, isKeyframe: isKey)
        }
        dock.onFocus = { [weak self] app, window in self?.focus(app: app, window: window) }
        dock.onLaunch = { [weak self] app in self?.launchFromDock(app) }
        dock.askMenu = { [weak self] app in
            guard let self, self.client.hostDockMenu, self.client.connected else { return }
            self.client.send(.dockMenu, payload: Wire.encode(DockMenu(app: app, token: UInt32.random(in: 1...UInt32.max))))
        }
        dock.pressMenu = { [weak self] app, id, title in
            guard let self, self.client.hostDockMenu, self.client.connected else { return }
            windowLog("dock: \(app) › \(title) pressed on the other Mac")
            self.client.send(.dockMenu, payload: Wire.encode(DockMenu(app: app, token: UInt32.random(in: 1...UInt32.max), press: id, title: title)))
        }
        client.onDockMenu = { [weak self] menu in
            guard let items = menu.items else { return }
            windowLog("dock: \(menu.app)'s menu on the other Mac: \(items.filter { $0.separator != true }.map(\.title))")
            self?.dock.setMenu(menu.app, items)
        }
        dock.onClose = { [weak self] app in
            guard let self else { return }
            for (source, window) in self.open {
                if case .window(let id) = source, self.appOf[id] == app { window.close() }
            }
        }
        client.onDragOffer = { [weak self] offer in self?.input.dragOffer = offer.files.isEmpty ? nil : offer }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updatePill()
                // On activation the key window can come a moment later (a click on a window that was
                // key while the app was in the background): look again then.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.updatePill() }
            }
        }
        _ = input   // makes the display view, which takes the client's frame hooks
        // The display view decodes too, for the picture's geometry (input), but never shows: each
        // window's own layer is its picture, the main stream's while it is focused.
        input.display.isHidden = true
        input.viewportAllowed = { [weak self] in
            guard let self, let window = self.input.window as? StreamWindow else { return false }
            return window.source == self.client.active && window.source == self.showing
        }
        input.holding = { [weak self] in
            guard let self, let wanted = self.requested else { return false }
            return self.client.active != wanted
        }
        let router = self.router
        client.onWindowListActive = { router.listed(active: $0) }
        let shownPS = client.onParameterSets
        client.onParameterSets = { ps in shownPS?(ps); router.parameterSets(ps) }
        let shownFrame = client.onFrame
        client.onFrame = { data, isKey in shownFrame?(data, isKey); router.frame(data, isKeyframe: isKey) }
    }

    var openSources: Set<StreamSource> { Set(open.keys) }

    // MARK: Windows kept across sessions

    /// A window open here, as remembered for the next session with this Mac: its ID (stable while
    /// its app runs), and its app and title to find it again after the app relaunched.
    private struct Kept: Codable { let id: UInt32; let app: String; let title: String }
    private var keptKey: String { "SillClient.openWindows." + client.macName }
    /// Off while windows close for the session's end, so the list survives it.
    private var keeping = true
    /// The list has been looked at for this session.
    private var restored = false

    private func keep() {
        guard keeping, client.connected, !client.macName.isEmpty else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SillResizeTest") { return }   // never the real session's list
        #endif
        let ordered = NSApp.orderedWindows.compactMap { $0 as? StreamWindow }.map(\.source).filter { open[$0] != nil }.reversed()
        let kept = ordered.compactMap { source -> Kept? in
            guard case .window(let id) = source, let w = client.windows.first(where: { $0.id == id }) else { return nil }
            return Kept(id: id, app: w.bundleID, title: w.title)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(kept), forKey: keptKey)
    }

    /// The windows open in the last session with this Mac, opened again (back to front, the last one
    /// key), once its first list has come.
    private func restore() {
        guard !restored, client.connected, !client.windows.isEmpty else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SillResizeTest") { restored = true; return }   // the test's own window only
        #endif
        restored = true
        windowLog("restore: key \(keptKey), saved \(UserDefaults.standard.data(forKey: keptKey)?.count ?? 0) bytes")
        guard let data = UserDefaults.standard.data(forKey: keptKey),
              let kept = try? JSONDecoder().decode([Kept].self, from: data), !kept.isEmpty else { return }
        var used = Set<UInt32>()
        let found = kept.compactMap { k -> UInt32? in
            let w = client.windows.first { $0.id == k.id && !used.contains($0.id) }
                ?? client.windows.first { $0.bundleID == k.app && $0.title == k.title && !used.contains($0.id) }
            guard let w else { return nil }
            used.insert(w.id)
            return w.id
        }
        for (i, id) in found.enumerated() { open(.window(id), focus: i == found.count - 1) }
    }

    /// Each window's side stream decoder, by the host's window ID, for the network queue.
    private let sideFeeds = FeedBox()

    /// Every window open here but the main stream's, as side streams (a host that streams fewer
    /// takes the first ones: the most recently used first).
    func requestSideStreams() {
        guard client.connected else { return }
        // Every window open here, the focused one too: the host streams it as the main stream, not
        // as a side one, and keeps them all on Sill's desk, also between two picks.
        // Only windows still open: a closing one is still among AppKit's while it closes, and asked
        // for then, the host kept it on its desk, captured, the sharing indicator on (2026-10-12).
        let ordered = NSApp.orderedWindows.compactMap { $0 as? StreamWindow }.map(\.source).filter { open[$0] != nil }
        let ids = ordered.compactMap { source -> UInt32? in
            guard case .window(let id) = source else { return nil }
            return id
        }
        // Every window with what belongs to it: its menus, popovers, sheets and the system's panels.
        client.requestSideStreams(ids, wholeApp: true, screen: Self.largestScreen,
                                  audio: client.hostAudio && AudioPlayer.enabled ? true : nil, audioCodec: AudioPlayer.codec)
    }

    /// This Mac's largest display, in points: the room the host keeps for each window (Sill's desk).
    static var largestScreen: CGSize? {
        NSScreen.screens.map(\.frame.size).max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Shows the window for `source`, making it if there is none, and gives it the keyboard, which
    /// asks the host for its stream.
    func open(_ source: StreamSource, focus: Bool = true) {
        windowLog("open \(source) focus \(focus) (already open: \(open[source] != nil))")
        guard source != .none else { return }
        if let window = open[source] {
            if window.isMiniaturized { window.deminiaturize(nil) }
            if focus { window.makeKeyAndOrderFront(nil); NSApp.activate() } else { window.orderFront(nil) }
            return
        }
        let window = StreamWindow(source: source, size: initialSize(source))
        window.delegate = self
        if case .window(let id) = source {
            window.container.over = { [weak self] info, at in self?.dragOver(info, at: at, window: id) ?? [] }
            window.container.exited = { [weak self] info in self?.live.exited(info) }
            window.container.onDrop = { [weak self] info, at in self?.dropped(info, at: at, window: id) ?? false }
            window.container.onBackgroundPress = { [weak self, weak window] event in
                guard let self, let window else { return }
                self.heldPress = (window.source, event.locationInWindow, Date())
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }
        window.title = title(source)
        window.placeholder.image = thumbnail(source)
        if case .window(let id) = source {
            sideFeeds.set(id, window.side.feed)
            appOf[id] = client.windows.first { $0.id == id }?.bundleID ?? appOf[id]
        }
        open[source] = window
        defer { syncDock(); keep() }
        window.center()
        if let key = NSApp.keyWindow as? StreamWindow, key !== window {
            window.setFrameTopLeftPoint(NSPoint(x: key.frame.minX + 28, y: key.frame.maxY - 28))
        }
        if focus {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            window.orderFront(nil)
            requestSideStreams()
        }
    }

    // MARK: Drops on a window shown beside the streamed one

    /// Followed live on a Mac that takes that (LiveDrop), else only accepted for a drop where let go.
    private func dragOver(_ info: NSDraggingInfo, at: CGPoint, window: UInt32) -> NSDragOperation {
        if live.enabled { return live.over(info, window: window, at: at) }
        return acceptsDrop(info) ? .copy : []
    }

    private func acceptsDrop(_ info: NSDraggingInfo) -> Bool {
        guard client.hostFileDrop, client.connected else { return false }
        let ok = info.draggingSource is StreamInputView ? !input.outgoing.isEmpty : !droppedFiles(info).isEmpty
        windowLog("drop: over a window, source \(String(describing: info.draggingSource.map { type(of: $0) })), own files \(input.outgoing.count), types \(info.draggingPasteboard.types?.map(\.rawValue).prefix(4) ?? []) → \(ok)")
        return ok
    }

    private func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
        LiveDrop.files(info)
    }

    /// Files from this Mac go across and are dropped there; the other Mac's own files, dragged out of
    /// one of its windows, are dropped from where they are, nothing copied either way.
    private func dropped(_ info: NSDraggingInfo, at: CGPoint, window: UInt32) -> Bool {
        windowLog("drop: let go on window \(window) at \(at)")
        if live.enabled { return live.drop(info, window: window, at: at) }
        guard client.hostFileDrop else { return false }
        if info.draggingSource is StreamInputView {
            let own = input.outgoing
            guard let offer = own.first?.offer else { return false }
            input.outgoing = []
            client.send(.fileDrop, payload: Wire.encode(FileDrop(files: own.map { UInt32($0.index) }, x: Double(at.x), y: Double(at.y),
                                                                  offer: offer, window: window)))
            windowLog("drop: \(own.count) of the other Mac's own files moved onto window \(window), nothing copied")
            return true
        }
        let urls = droppedFiles(info)
        guard !urls.isEmpty else { return false }
        StreamInputView.send(urls, at: at, client: client, window: window)
        return true
    }

    /// The Dock icons follow the windows open here, by app.
    private func syncDock() {
        var apps: [String: DockProxies.AppWindows] = [:]
        var byApp: [String: [DockProxies.Window]] = [:]
        // Each app's front window (the Dock's ✓): the first of its windows here in this Mac's order.
        var front: [String: UInt32] = [:]
        for case let window as StreamWindow in NSApp.orderedWindows where !window.isMiniaturized && window.isVisible {
            if case .window(let id) = window.source, let app = appOf[id], front[app] == nil { front[app] = id }
        }
        for (source, window) in open {
            guard case .window(let id) = source, let app = appOf[id] else { continue }
            let w = client.windows.first { $0.id == id }
            let state: DockProxies.Window.State = window.isMiniaturized ? .minimized : (front[app] == id ? .front : .other)
            byApp[app, default: []].append(DockProxies.Window(id: id, title: w.map { $0.title.isEmpty ? $0.appName : $0.title } ?? title(source),
                                                              state: state))
        }
        for (app, windows) in byApp {
            let name = client.windows.first { $0.bundleID == app }?.appName ?? app
            apps[app] = DockProxies.AppWindows(name: name, icon: client.icons[app], windows: windows.sorted { $0.title < $1.title })
        }
        dock.sync(apps)
    }

    private func updatePill() {
        guard NSApp.isActive, let key = NSApp.keyWindow as? StreamWindow else { pill.show(over: nil, title: "", image: nil); return }
        var image: NSImage?
        if case .window(let id) = key.source, let app = appOf[id] { image = client.icons[app] }
        pill.show(over: key, title: title(key.source), image: image)
    }

    /// From a Dock icon: one window, or every window of the app (the most recent one key).
    private func focus(app: String, window: UInt32?) {
        if let window { open(.window(window)); return }
        let mine = NSApp.orderedWindows.compactMap { $0 as? StreamWindow }.filter {
            guard case .window(let id) = $0.source else { return false }
            return appOf[id] == app
        }
        for w in mine.reversed() { if w.isMiniaturized { w.deminiaturize(nil) }; w.orderFront(nil) }
        mine.first?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }


    /// Apps whose Dock icon, kept in the Dock, was clicked before the other Mac was connected.
    private var dockLaunches: Set<String> = []
    private var lastDockLaunch: [String: Date] = [:]

    /// A kept Dock icon clicked with none of its app's windows open here: its windows on the other
    /// Mac open here, or, with none there, the app is launched there (its first window then streams
    /// here, as an app opened from the status item does).
    private func launchFromDock(_ app: String) {
        guard client.connected, known != nil else { dockLaunches.insert(app); return }
        dockLaunches.remove(app)
        // The Dock icon asks as it starts and as it becomes active: one answer.
        if let last = lastDockLaunch[app], Date().timeIntervalSince(last) < 3 { return }
        lastDockLaunch[app] = Date()
        let theirs = client.windows.filter { $0.bundleID == app && !$0.title.isEmpty && $0.width >= 80 && $0.height >= 150 }
        windowLog("dock: \(app) asked for from the Dock: \(theirs.isEmpty ? "launching it" : "\(theirs.count) window(s)")")
        if theirs.isEmpty { client.launch(bundleID: app); return }
        for w in theirs.dropFirst().reversed() { open(.window(w.id), focus: false) }
        open(.window(theirs[0].id), focus: true)
    }

    func closeAll() {
        pill.show(over: nil, title: "", image: nil)
        keeping = false
        defer { keeping = true; restored = false }
        for window in open.values { window.delegate = nil; window.close() }
        open.removeAll()
        known = nil
        sideFeeds.removeAll()
        client.requestSideStreams([], wholeApp: true, screen: Self.largestScreen)
        dock.quitAll()
        router.reset()
        showing = nil
    }

    func letGo() { input.letGo() }

    // MARK: Following the host

    /// The host streams `active`: a source this Mac chose, or one the host picked (an app opened
    /// from the status item streams its new window). The window for it gets the picture, made if
    /// there is none.
    private func activeChanged(_ active: StreamSource) {
        windowLog("host streams \(active) (requested \(String(describing: requested)), showing \(String(describing: showing)))")
        guard client.connected, active != .none else { return }
        // A focus the host dropped while it switched: asked for again, once its list has come.
        if let wanted = requested, wanted != active, (NSApp.keyWindow as? StreamWindow)?.source == wanted, open[wanted] != nil {
            pick(wanted)
            return
        }
        requested = nil
        input.flushHeld()
        if open[active] == nil { open(active) }
        router.hostSwitched()
        attach(to: active)
        requestSideStreams()
    }

    /// A window the host no longer lists has closed there (a moment's absence is the host's to wait
    /// out: it lists a window again within a poll): its window here closes too.
    private func windowsChanged(_ list: [WindowInfo]) {
        let ids = Set(list.map(\.id))
        // New windows of an app open here open by themselves: in front when the app is the one in use.
        if let seen = known, client.connected {
            let openApps = Set(open.keys.compactMap { source -> String? in
                guard case .window(let id) = source else { return nil }
                return client.windows.first { $0.id == id }?.bundleID ?? appOf[id]
            })
            let focusedApp: String? = {
                guard case .window(let id)? = (NSApp.keyWindow as? StreamWindow)?.source else { return nil }
                return appOf[id]
            }()
            // Not an app's untitled strips (a browser's full-screen bar, 115 points tall across the display).
            for w in list where !seen.contains(w.id) && openApps.contains(w.bundleID) && w.width >= 80 && w.height >= 150
                                && !w.title.isEmpty {
                open(.window(w.id), focus: w.bundleID == focusedApp)
            }
        }
        known = (known ?? []).union(ids)
        restore()
        for app in dockLaunches { launchFromDock(app) }
        for w in list { appOf[w.id] = w.bundleID }
        defer { syncDock() }
        for (source, window) in open {
            guard case .window(let id) = source else { continue }
            if ids.contains(id) {
                window.title = title(source)
            } else {
                window.close()
            }
        }
    }

    private func thumbnailsChanged(_ thumbs: [UInt32: NSImage]) {
        for (source, window) in open where source != showing {
            if case .window(let id) = source, let image = thumbs[id] { window.placeholder.image = image }
        }
    }

    /// The stream view goes into `source`'s window, with the window's own viewport: a window
    /// streams 1:1 (the Mac window is sized to this one), the Desktop as it is.
    /// A press on a window in the background, waiting for the other Mac to stream it.
    private var heldPress: (source: StreamSource, at: NSPoint, when: Date)?

    private func attach(to source: StreamSource) {
        guard let window = open[source] else { return }
        defer {
            // The press that brought it forward, still held: it goes on there now (a drag out of a
            // window in the background starts with one press).
            if let held = heldPress, held.source == source {
                heldPress = nil
                if Date().timeIntervalSince(held.when) < 2, NSEvent.pressedMouseButtons & 1 != 0 {
                    windowLog("buttons: the press on \(source) in the background goes on there")
                    input.beginHeldPress(at: held.at)
                }
            }
        }
        // The host streams this window now: if no focus here asked for it (the host picked it, or the
        // window opened for an app opened from the status item), its stream is followed into it.
        if !router.draws(into: window.side.feed) { router.follow(window.side.feed) }
        showing = source
        if case .window = source { input.textScale = 1 } else { input.textScale = nil }
        if input.superview !== window.container {
            input.removeFromSuperview()
            input.frame = window.container.bounds
            input.autoresizingMask = [.width, .height]
            window.container.addSubview(input)
        }
        if window.isKeyWindow { window.makeFirstResponder(input) }
        input.sendViewportNow()
        updatePill()
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? StreamWindow else { return }
        windowLog("key: \(window.source)")
        updatePill()
        syncDock()   // the Dock menu's ✓ follows the front window
        focused(window)
    }

    #if DEBUG
    /// -SillFlipTest: what the window becoming key does, without the app being in front (a test
    /// started over ssh cannot take the front from the person using the Mac).
    func flipTest(to source: StreamSource) {
        guard let window = open[source] else { return }
        windowLog("flip test: \(source)")
        window.orderFront(nil)
        focused(window)
    }
    #endif

    private func focused(_ window: StreamWindow) {
        if client.active != window.source {
            window.placeholder.image = thumbnail(window.source) ?? window.placeholder.image
            router.expect(window.side.feed)   // the new stream's picture goes here once it comes
            pick(window.source)
        } else {
            attach(to: window.source)
        }
    }

    /// Asks the host for `source`: the stream view goes into its window (for the pointer's geometry),
    /// a viewport with no scale goes first (the host fits the window it picks to the last viewport,
    /// which was another window's), and the window's own size once the host has switched (`attach`).
    private func pick(_ source: StreamSource) {
        windowLog("pick \(source) (window: \(open[source] != nil), active \(client.active))")
        guard let window = open[source] else { return }
        requested = source
        showing = source
        if input.superview !== window.container {
            input.removeFromSuperview()
            input.frame = window.container.bounds
            input.autoresizingMask = [.width, .height]
            window.container.addSubview(input)
        }
        if window.isKeyWindow { window.makeFirstResponder(input) }
        input.textScale = nil
        input.sendViewportNow()
        client.select(source)
        watchPick(source, tries: 0)
    }

    /// A pick the host has not taken (it was switching, or the message went with a connection that
    /// moved) never changes `active`, so nothing would end the hold and every key would wait and be
    /// dropped: asked again after 1.5 s, twice, then input goes to whatever streams.
    private func watchPick(_ source: StreamSource, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.requested == source, self.client.active != source, self.client.connected else { return }
            if tries < 2, self.open[source] != nil {
                windowLog("pick \(source) not taken after 1.5 s; asking again")
                self.client.select(source)
                self.watchPick(source, tries: tries + 1)
            } else {
                windowLog("pick \(source) never taken; input goes on to \(self.client.active)")
                self.requested = nil
                self.input.dropHeld()   // made for the window that never came: never typed into another
            }
        }
    }


    func windowDidResignKey(_ notification: Notification) { updatePill() }
    func windowDidMiniaturize(_ notification: Notification) { updatePill(); syncDock() }
    func windowDidDeminiaturize(_ notification: Notification) { updatePill(); syncDock() }
    func windowDidEnterFullScreen(_ notification: Notification) { updatePill() }
    func windowDidExitFullScreen(_ notification: Notification) { updatePill() }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? StreamWindow else { return }
        open[window.source] = nil
        if case .window(let id) = window.source { sideFeeds.set(id, nil) }
        defer { requestSideStreams(); syncDock(); keep() }
        guard showing == window.source else { return }
        input.letGo()
        input.removeFromSuperview()
        showing = nil
        // The next window of the other Mac's takes the stream, or nothing streams.
        if let next = NSApp.orderedWindows.compactMap({ $0 as? StreamWindow }).first(where: { $0 !== window && !$0.isMiniaturized }) {
            next.makeKeyAndOrderFront(nil)
        } else if client.connected {
            client.select(.none)
        }
    }

    /// Moved to another of this Mac's displays: its rate (120 Hz or 60) and, full screen, its size
    /// are that display's, so the host's desk display for the window follows (a new viewport: the
    /// host makes the desk display again when it must grow, at the new rate).
    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? StreamWindow, window.source == showing else { return }
        input.sendViewport(after: 0.1)
    }

    func windowDidResize(_ notification: Notification) {
        pill.place()
        guard let window = notification.object as? StreamWindow, window.source == showing else { return }
        input.sendViewport(after: 0.25)
    }

    // MARK: Helpers

    private func initialSize(_ source: StreamSource) -> NSSize {
        let room = (NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900))
        var size: NSSize
        switch source {
        case .window(let id):
            let w = client.windows.first { $0.id == id }
            size = NSSize(width: CGFloat(w?.width ?? 1000), height: CGFloat(w?.height ?? 700))
        default:
            // The Desktop: the frame's shape when known, else 16:10.
            let video = client.videoSize
            size = video.width > 0 && client.active == .desktop
                ? NSSize(width: 1280, height: 1280 * video.height / video.width)
                : NSSize(width: 1280, height: 800)
        }
        let fit = min(1, (room.width - 40) / size.width, (room.height - 40) / size.height)
        return NSSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
    }

    func title(_ source: StreamSource) -> String {
        switch source {
        case .window(let id):
            guard let w = client.windows.first(where: { $0.id == id }) else { return client.macName }
            return w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)"
        case .desktop: return "\(client.macName) — Desktop"
        case .none: return client.macName
        }
    }

    private func thumbnail(_ source: StreamSource) -> NSImage? {
        if case .window(let id) = source { return client.thumbnails[id] }
        return nil
    }
}

/// The other Mac's windows by ID, each with its side stream's decoder, for the network queue.
final class FeedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [UInt32: HEVCSampleFeed] = [:]
    func get(_ id: UInt32) -> HEVCSampleFeed? { lock.lock(); defer { lock.unlock() }; return map[id] }
    func set(_ id: UInt32, _ feed: HEVCSampleFeed?) { lock.lock(); map[id] = feed; lock.unlock() }
    func removeAll() { lock.lock(); map.removeAll(); lock.unlock() }
}

/// A window's own picture while it is not the main stream: its side stream, decoded by its own layer.
final class SideView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private(set) lazy var feed = HEVCSampleFeed(layer: displayLayer)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(displayLayer)
        _ = feed
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}

/// A stream window's content: takes files dropped on the picture (the focused window's own view
/// takes them first), as the point they were let go at, a fraction of the picture from its top left.
final class DropContainer: NSView {
    var onDrop: ((NSDraggingInfo, CGPoint) -> Bool)?
    /// What a drop would do at that point (a fraction of the picture from its top left).
    var over: ((NSDraggingInfo, CGPoint) -> NSDragOperation)?
    var exited: ((NSDraggingInfo) -> Void)?
    /// A press on the picture of a window in the background (the stream view is elsewhere): the
    /// window comes forward, and the press goes on once the other Mac streams it.
    var onBackgroundPress: ((NSEvent) -> Void)?
    /// The stream view, while it is in this window (`StreamInputView`).
    private var input: StreamInputView? { subviews.lazy.compactMap { $0 as? StreamInputView }.first }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if input != nil { return super.hitTest(point) }
        return frame.contains(point) ? self : nil   // the picture and placeholder take no presses of their own
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if let input { input.mouseDown(with: event) } else { onBackgroundPress?(event) }
    }
    // The press began here: its drag and its up go to the stream view once it has come (it ignores
    // them until the held press is begun, `beginHeldPress`).
    override func mouseDragged(with event: NSEvent) { input?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { input?.mouseUp(with: event) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { at(sender).flatMap { over?(sender, $0) } ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { at(sender).flatMap { over?(sender, $0) } ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { if let sender { exited?(sender) } }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let p = at(sender) else { return false }
        return onDrop?(sender, p) ?? false
    }
    private func at(_ sender: NSDraggingInfo) -> CGPoint? {
        let p = convert(sender.draggingLocation, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return CGPoint(x: min(max(p.x / bounds.width, 0), 1), y: min(max(1 - p.y / bounds.height, 0), 1))
    }
}

/// One of the other Mac's windows: its picture at 1:1, filling a window with no frame of its own.
final class StreamWindow: NSWindow {
    let source: StreamSource
    let container = DropContainer()
    let placeholder = NSImageView()
    let side = SideView()

    init(source: StreamSource, size: NSSize) {
        self.source = source
        // No frame of its own: the picture fills it, title bar included. This Mac's controls are the
        // pill above it (WindowPill); the other Mac's title bar and buttons, with that Mac's own
        // window menu, are in the picture.
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        collectionBehavior.insert(.fullScreenPrimary)
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(kind)?.isHidden = true }
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
        backgroundColor = .black
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.frame = container.bounds
        placeholder.autoresizingMask = [.width, .height]
        // An NSImageView registers for file and image drags itself and, not editable, refuses them;
        // as the deepest view under the pointer it took every drop meant for the container.
        placeholder.unregisterDraggedTypes()
        container.addSubview(placeholder)
        side.frame = container.bounds
        side.autoresizingMask = [.width, .height]
        container.addSubview(side)
        contentView = container
    }
}
