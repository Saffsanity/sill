import Foundation
import Network
import ApplicationServices
import StreamProtocol

/// The streamed app's menus, for the devices that asked for them (docs/menu-bar-plan.md §4.4).
///
/// Main actor: the target, the version, the top level, the kept elements and the cache are its
/// state. Every Accessibility call is the reader's, on `sill.menus`; none is made here. Answers go
/// out through the server (thread-safe). Nothing is read, sent or printed until a device asks: with
/// no subscriber a target change costs the coordinator one comparison, so an older device, and a
/// test client that never sends kind 27, are served exactly as before.
///
/// Requests are served one at a time, in arrival order (`enqueue`): a fetch's activation and read,
/// a press, a subscription's read. So a device's answers follow its requests, and no two reads of
/// one app overlap. Target and version change at once (`setTarget`); every step that waited checks
/// them again, and a read that comes back for another version is dropped.
@MainActor
final class MenuMirror {
    struct Target: Equatable {
        let pid: pid_t
        let app: String
        let bundleID: String?
        /// The streamed window, for a window source: another window of the same app keeps the
        /// version (the same menus) but not the cache (its key window, so its states, changed).
        var window: UInt32? = nil
    }

    private let server: StreamServer
    private let reader: MenuReader
    /// Before a read or a press of a window source: its app active and the window key (the
    /// coordinator's `focusForMenus`). True when the app is frontmost as it returns; true at once
    /// for the Desktop and for nothing.
    var prepare: () async -> Bool = { true }
    /// The app behind the current source, asked when the first device subscribes (the coordinator
    /// tells the mirror of changes only while someone subscribes).
    var currentTarget: () -> Target? = { nil }
    /// The first device subscribed (true) or the last one left (false).
    var onSubscribersChanged: ((Bool) -> Void)?

    private(set) var target: Target?
    /// One for all devices, from 1 each launch: +1 whenever the target changes, or a re-read finds
    /// the top level changed. Ids are good within one version only.
    private(set) var version = 1
    /// The top level as sent, and whether it has been read for this version.
    private var top: [MacMenuItem] = []
    private var topRead = false
    private var topLevel: TopLevel?
    /// The app did not answer a read within the timeout: presses are refused and fetches answered
    /// with `note`, until a read (each catalog poll) succeeds again.
    private var stale = false
    private var note: String?
    /// The element of every item read in this version, for presses and for reading its submenu,
    /// with its title (the host's own, for the log). This version only; at most `maxKept`.
    private struct Kept { let element: AXUIElement; let title: String }
    private var elements: [MenuPath: Kept] = [:]
    private static let maxKept = 5_000
    private var cache = MenuCache()
    private var subscribers: [ObjectIdentifier: NWConnection] = [:]
    private var rates: [ObjectIdentifier: RequestRate] = [:]
    /// The last top level broadcast to the subscribers (never an answer): sent again only changed.
    private var lastSent: MacMenu?
    private var chain: Task<Void, Never>?
    private var staleRetryQueued = false

    var hasSubscribers: Bool { !subscribers.isEmpty }

    init(server: StreamServer, reader: MenuReader = MenuReader()) {
        self.server = server
        self.reader = reader
    }

    // MARK: From the coordinator

    /// The app behind the current source, when it may have changed: a pick, the Desktop's frontmost
    /// app. Equal to the current one: nothing. Otherwise the version moves and, with subscribers,
    /// the new top level goes to each of them once read (never an empty one in between: a device's
    /// Menus button would flicker), or at once with no menus for no target.
    func setTarget(_ t: Target?) {
        guard t != target else { return }
        let sameApp = adopt(t)
        guard hasSubscribers else { return }
        // The same app, or none: nothing to read (a name shown differently is sent, deduplicated).
        if sameApp || t == nil { publishTop(); return }
        let v = version
        enqueue {
            guard await self.readTop(version: v) else { return }
            self.publishTop()
        }
    }

    /// Makes `t` the target. The same app (another of its windows, or the Desktop with it in front)
    /// keeps the version, its menus and ids, but not the cache: its states were computed for
    /// another key window. Any other change moves the version. True for the same app.
    private func adopt(_ t: Target?) -> Bool {
        if let t, let old = target, t.pid == old.pid {
            target = t
            cache.clear()
            return true
        }
        target = t
        newVersion()
        return false
    }

    /// Kind 27. Without an id: the subscription, answered with the top level. With one: that menu's
    /// items, from a read of less than a second ago made while the app was frontmost, or read now.
    /// At most 20 a second per connection; the rest get "Too many requests…" at once.
    func fetch(_ r: FetchMenu, from c: NWConnection, who: String) {
        let id = ObjectIdentifier(c)
        let now = CFAbsoluteTimeGetCurrent()
        var rate = rates[id] ?? RequestRate()
        let allowed = rate.allowFetch(now: now)
        if !allowed, rate.ignoredLineDue(now: now) {
            print("Menus from \(who) ignored: more than \(RequestRate.fetchesPerSecond) requests a second.")
        }
        rates[id] = rate
        guard allowed else {
            Stats.shared.bump("menu.refused")
            send(MacMenu(version: version, answering: r.token, menu: r.id.flatMap(MenuPath.init)?.id, items: [],
                         note: MenuRefusal.tooManyNote), to: c)
            return
        }
        guard let menuID = r.id else { subscribe(c, token: r.token); return }
        enqueue { await self.serveFetch(r, id: menuID, to: c) }
    }

    /// Kind 25: choose one item, at most 4 a second per connection. Logged whatever the outcome.
    func press(_ r: PressMenuItem, from c: NWConnection, who: String) {
        let id = ObjectIdentifier(c)
        let now = CFAbsoluteTimeGetCurrent()
        var rate = rates[id] ?? RequestRate()
        let allowed = rate.allowPress(now: now)
        if !allowed, rate.ignoredLineDue(now: now) {
            print("Menus from \(who) ignored: more than \(RequestRate.pressesPerSecond) choices a second.")
        }
        rates[id] = rate
        guard allowed else {
            Stats.shared.bump("menu.refused")
            send(MacMenu(version: version, answering: r.token, pressed: false, note: MenuRefusal.tooManyNote), to: c)
            return
        }
        enqueue { await self.servePress(r, to: c, who: who) }
    }

    /// A connection closed.
    func clientLeft(_ c: NWConnection) {
        let id = ObjectIdentifier(c)
        rates[id] = nil
        guard subscribers.removeValue(forKey: id) != nil else { return }
        if subscribers.isEmpty {
            // Nobody to answer: let go of the app's elements; the next subscriber reads afresh.
            elements = [:]
            cache.clear()
            onSubscribersChanged?(false)
        }
    }

    /// Each catalog poll (every 2 s while a device is connected): while the app is shown as not
    /// answering, read its top level again; a read that succeeds clears that and sends the top level.
    func catalogPolled() {
        guard stale, hasSubscribers, target != nil, !staleRetryQueued else { return }
        staleRetryQueued = true
        let v = version
        enqueue {
            self.staleRetryQueued = false
            guard self.stale, await self.readTop(version: v) else { return }
            self.publishTop()
        }
    }

    // MARK: Serving, one request at a time

    private func subscribe(_ c: NWConnection, token: Int?) {
        let id = ObjectIdentifier(c)
        let first = subscribers.isEmpty
        subscribers[id] = c
        if first {
            onSubscribersChanged?(true)
            // Until now the coordinator told the mirror nothing: take the current app, as setTarget
            // would (a different one moves the version).
            let t = currentTarget()
            if t != target { _ = adopt(t) }
        }
        enqueue {
            guard self.subscribers[id] != nil else { return }
            // Read even when this version's top level is known: nobody may have watched it change.
            if self.target != nil { _ = await self.readTop(version: self.version) }
            guard self.subscribers[id] != nil else { return }
            self.send(self.topMessage(answering: token), to: c)
            self.publishTop(except: id)
        }
    }

    private func serveFetch(_ r: FetchMenu, id menuID: String, to c: NWConnection) async {
        let path = MenuPath(menuID)
        func answer(_ m: MacMenu) { send(m, to: c) }
        func refuse(_ note: String) {
            Stats.shared.bump("menu.refused")
            answer(MacMenu(version: version, answering: r.token, menu: path?.id, items: [], note: note))
        }
        guard r.version == version, let path, let t = target else { refuse(MenuRefusal.changedNote); return }
        if stale {
            answer(MacMenu(version: version, answering: r.token, menu: path.id, items: [], stale: true, note: note))
            return
        }
        if let e = cache.fresh(path.id, now: CFAbsoluteTimeGetCurrent()) {
            Stats.shared.bump("menu.cached")
            answer(MacMenu(version: version, answering: r.token, menu: path.id, items: e.items, more: e.more > 0 ? e.more : nil))
            return
        }
        let v = version
        let frontmost = await prepare()
        guard v == version, target?.pid == t.pid else { refuse(MenuRefusal.changedNote); return }
        let wait = cache.wait(path.id, now: CFAbsoluteTimeGetCurrent())
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
            guard v == version, target?.pid == t.pid else { refuse(MenuRefusal.changedNote); return }
        }
        // The top level again, then the menu, in one hop: a top level that changed meanwhile moves
        // the version, and this answer then says so (the menu is not read).
        let reader = self.reader
        let expected: TopLevel? = topRead ? topLevel : nil      // nothing to compare with before a first read
        let kept = path.indexes.count > 1 ? elements[path]?.element : nil
        let (topResult, menuResult) = await onMenus { () -> (Result<(titles: [MenuReader.Read], ms: Double), MenuReader.Failure>, Result<MenuReader.Menu, MenuReader.Failure>?) in
            let top = reader.topLevel(pid: t.pid)
            guard case .success(let got) = top else { return (top, nil) }
            if let expected, Self.level(of: got.titles) != expected { return (top, nil) }
            let parent = path.indexes.count == 1 ? got.titles.first { $0.index == path.indexes[0] }?.element : kept
            return (top, reader.items(pid: t.pid, of: parent, path: path))
        }
        guard v == version, target?.pid == t.pid else { refuse(MenuRefusal.changedNote); return }
        applyTop(topResult, target: t)
        guard v == version, target?.pid == t.pid else {
            publishTop()
            refuse(target == nil ? MenuRefusal.goneNote(label(t.app)) : MenuRefusal.changedNote)
            return
        }
        if stale {
            publishTop()
            answer(MacMenu(version: version, answering: r.token, menu: path.id, items: [], stale: true, note: note))
            return
        }
        guard let menuResult else {
            if case .failure(.notTrusted) = topResult { refuse(MenuRefusal.noAccessNote) } else { refuse(MenuRefusal.changedNote) }
            return
        }
        switch menuResult {
        case .success(let menu):
            Stats.shared.bump("menu.read")
            var items: [MacMenuItem] = []
            for read in menu.reads {
                guard let childPath = path.child(read.index), let item = MenuFormat.item(read.item, id: childPath.id) else { continue }
                items.append(item)
                if item.separator != true, elements.count < Self.maxKept || elements[childPath] != nil {
                    elements[childPath] = Kept(element: read.element, title: item.title ?? "")
                }
            }
            let more = max(0, menu.total - MenuReader.maxItems)
            cache.store(path.id, MenuCache.Entry(items: items, more: more, at: CFAbsoluteTimeGetCurrent(), appWasFrontmost: frontmost))
            answer(MacMenu(version: version, answering: r.token, menu: path.id, items: items, more: more > 0 ? more : nil))
        case .failure(.notAnswering):
            Stats.shared.bump("menu.axTimeout")
            becomeStale(t)
            publishTop()
            answer(MacMenu(version: version, answering: r.token, menu: path.id, items: [], stale: true, note: note))
        case .failure(.gone):
            targetGone()
            publishTop()
            refuse(MenuRefusal.goneNote(label(t.app)))
        case .failure(.notTrusted):
            refuse(MenuRefusal.noAccessNote)
        case .failure(.noMenuBar), .failure(.failed):
            refuse(MenuRefusal.changedNote)
        }
    }

    private func servePress(_ r: PressMenuItem, to c: NWConnection, who: String) async {
        let path = r.id.flatMap(MenuPath.init)
        let app = label(target?.app ?? "")
        // The host's own titles; the device's are never logged. An id from another version, or one
        // that names nothing, is given as it came (cleaned).
        let shownID = path?.id ?? SafeText.label(r.id ?? "no id", limit: 32)
        func refuse(_ why: MenuRefusal, what: String) {
            Stats.shared.bump("menu.refused")
            print("Menu from \(who) refused: \(what): \(why.logReason(app: app))")
            send(MacMenu(version: version, answering: r.token, pressed: false, note: why.note(app: app)), to: c)
        }
        guard r.version == version, let path, let t = target else { refuse(.changed, what: shownID); return }
        if stale { refuse(.notAnswering, what: logPath(path, app: t.app)); return }
        let v = version
        _ = await prepare()
        guard v == version, target?.pid == t.pid else { refuse(.changed, what: shownID); return }
        let reader = self.reader
        let kept = elements[path]?.element
        let shown = r.title
        let result = await onMenus { reader.press(pid: t.pid, element: kept, path: path, shownTitle: shown) }
        // A press can change any state.
        cache.clear()
        let what = logPath(path, app: t.app, last: result.foundTitle)
        switch result.outcome {
        case .pressed:
            Stats.shared.bump("menu.press")
            print("Menu from \(who): \(what)")
            send(MacMenu(version: version, answering: r.token, pressed: true), to: c)
        case .pressedNoAnswer:
            Stats.shared.bump("menu.press")
            Stats.shared.bump("menu.axTimeout")
            print("Menu from \(who): \(what) (\(label(t.app)) did not answer within 1 s; a dialog may be open)")
            send(MacMenu(version: version, answering: r.token, pressed: true), to: c)
        case .refused(let why):
            if why == .notAnswering { Stats.shared.bump("menu.axTimeout") }
            refuse(why, what: what)
            if why == .gone, target?.pid == t.pid { targetGone(); publishTop() }
            if why == .notAnswering, target?.pid == t.pid, !stale { becomeStale(t); publishTop() }
        }
    }

    // MARK: The top level

    /// Reads the target's bar for version `v` and applies it. False when the read was dropped (the
    /// version or the target moved meanwhile).
    private func readTop(version v: Int) async -> Bool {
        guard v == version, let t = target else { return false }
        let reader = self.reader
        let result = await onMenus { reader.topLevel(pid: t.pid) }
        guard v == version, target?.pid == t.pid else { return false }
        applyTop(result, target: t)
        return true
    }

    /// What a read of the bar found: the top level of this version, a changed top level (the
    /// version moves), the app not answering (stale), gone (no target), or no menus.
    private func applyTop(_ result: Result<(titles: [MenuReader.Read], ms: Double), MenuReader.Failure>, target t: Target) {
        switch result {
        case .success(let got):
            Stats.shared.bump("menu.top")
            if stale { print("Menus of \(label(t.app)) answering again.") }
            setTop(Self.level(of: got.titles), got.titles.compactMap { MenuFormat.topItem($0.item, index: $0.index) }, note: nil)
        case .failure(.notAnswering):
            Stats.shared.bump("menu.axTimeout")
            becomeStale(t)
        case .failure(.gone):
            targetGone()
        case .failure(.notTrusted):
            setTop(TopLevel(titles: [], enabled: []), [], note: MenuRefusal.noAccessNote)
        case .failure(.noMenuBar):
            setTop(TopLevel(titles: [], enabled: []), [], note: nil)
        case .failure(.failed):
            break      // a passing error: what was read stays, and the next read tries again
        }
    }

    /// A top level as read: when this version already had one and it differs (titles, count,
    /// enabled flags, or menus where there were none), the version moves first.
    private func setTop(_ level: TopLevel, _ items: [MacMenuItem], note newNote: String?) {
        if topRead, level != topLevel { newVersion() }
        stale = false
        note = newNote
        topLevel = level
        topRead = true
        top = items
    }

    nonisolated private static func level(of reads: [MenuReader.Read]) -> TopLevel {
        TopLevel(titles: reads.map { MenuFormat.displayTitle(title: $0.item.title, description: nil) },
                 enabled: reads.map { $0.item.enabled != false })
    }

    private func becomeStale(_ t: Target) {
        guard !stale else { return }
        stale = true
        note = MenuRefusal.notRespondingNote(label(t.app))
        print("Menus of \(label(t.app)) not answering (\(String(format: "%.1f", Double(MenuReader.timeout))) s); shown as unavailable until it answers.")
    }

    private func targetGone() {
        target = nil
        newVersion()
    }

    private func newVersion() {
        version += 1
        cache.clear()
        elements = [:]
        top = []
        topRead = false
        topLevel = nil
        stale = false
        note = nil
    }

    private func topMessage(answering: Int?) -> MacMenu {
        guard let t = target else { return MacMenu(version: version, menus: [], answering: answering) }
        return MacMenu(version: version, app: label(t.app), bundleID: t.bundleID, menus: top, answering: answering,
                       stale: stale ? true : nil, note: note)
    }

    /// The top level to every subscriber (but `except`), when it differs from the last one sent.
    private func publishTop(except: ObjectIdentifier? = nil) {
        let m = topMessage(answering: nil)
        guard m != lastSent else { return }
        lastSent = m
        for (id, c) in subscribers where id != except { send(m, to: c) }
    }

    // MARK: Helpers

    /// "menufixture › Probe › Set Label A" from the host's own titles, else the id.
    private func logPath(_ path: MenuPath, app: String, last: String? = nil) -> String {
        let lineage = path.lineage
        let titles: [String?] = lineage.enumerated().map { i, p in
            let known = p.indexes.count == 1 ? top.first { $0.id == p.id }?.title : elements[p]?.title
            return known ?? (i == lineage.count - 1 ? last : nil)
        }
        return MenuLog.path(app: app, titles: titles) ?? path.id
    }

    private func label(_ app: String) -> String { SafeText.label(app) }

    private func send(_ m: MacMenu, to c: NWConnection) {
        guard c.state == .ready else { return }   // it closed meanwhile: nothing to answer
        server.send(StreamMessage(kind: .macMenu, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                  payload: Wire.encode(m)), to: c)
    }

    /// One request after the other, in arrival order (see the class comment).
    private func enqueue(_ op: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await op()
        }
    }

    /// `work` on `sill.menus`, the caller resuming on the main actor with its result.
    private func onMenus<T>(_ work: @escaping @Sendable () -> T) async -> T {
        let queue = reader.queue
        return await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in
            queue.async { c.resume(returning: work()) }
        }
    }
}
