import AppKit
import Network
import StreamProtocol

/// The clipboard, the host's side (kind 32; docs/clipboard-plan.md). The rules are ClipboardPolicy's;
/// this reads and writes the pasteboard and keeps who subscribed.
///
/// - A device subscribes with any kind 32 (an empty one at connect, while its Share Clipboard is on)
///   and stops with `stop`; one line each ("Clipboard: iPad (iPad14,1) shares the clipboard."). A
///   device that leaves is forgotten without a line.
/// - While at least one subscribes, the pasteboard's change count is looked at four times a second.
///   The count as it stands when the first subscribes is taken as seen: what was on the clipboard then
///   is never sent, only what is copied while a device shares it. A change ClipboardPolicy.hostDecides
///   takes goes to every subscriber; one whose pasteboard has no items yet is looked at again for up
///   to a second first (`hostWaits`: an app clears, then writes). One from another device through
///   Universal Clipboard is never read; a password manager's copy goes like any other (2026-10-29).
/// - A device's text becomes the pasteboard's, written for this Mac only (`.currentHostOnly`: Universal
///   Clipboard does not carry it to the person's other devices, the sender among them) with the
///   marker `ClipboardPolicy.ownType` naming this launch; it goes to every other subscriber at once,
///   and the look never sends it again.
/// - Off (`HostConfig.shareClipboard`, `setEnabled`): every subscription dropped, nothing looked at,
///   and a kind 32 ignored without a word or an answer. The coordinator's window lists say
///   `clipboard` only while it is on.
/// - Images (generation 2, docs/clipboard-plan.md "Generation 2"), while Include images is on
///   (`HostConfig.shareClipboardImages`, `setImages`; the lists say 2, else 1): a subscriber takes them
///   while its last subscription said `accepts` 2 (its Include Images on; a Paste leaves that as it was,
///   ClipboardPolicy.subscriberTakesImages). The look reads an image only while one does; its bytes are
///   read on the pasteboard's queue and fitted on a queue of their own (`fitQueue`), to 8 MiB for a
///   subscriber at home and 2 MiB for one away (ClipboardPolicy.imageCap), and go on the server's image
///   path (StreamServer.sendClipboardImage), never ahead of a newer copy. A device's image (PNG or JPEG,
///   by its first bytes, never parsed here) becomes the pasteboard's as its text does, and goes on to
///   the other subscribers that take images, away only within 2 MiB. Off, an image from a device is
///   refused and none is read or sent.
/// - macOS's paste privacy (`MacClipboard`, ClipboardPolicy.MacAccess; macOS 15.4 and later): the look
///   reads the pasteboard only while macOS allows every read Sill makes on its own; while it would ask
///   (its alert at every copy) or denies, the look reads nothing, not even the change count, and what
///   is copied meanwhile is never sent (`accessStep`). One line when that changes (`accessLine`). A
///   device's text is written whatever macOS says: writing needs no leave.
///
/// Never logs what was copied. Stats: `clip.sent` (messages sent), `clip.recv` (texts and images taken).
///
/// Threading: main actor for the subscribers and the lines; the pasteboard itself is read and written
/// on a queue of its own (`Board`), one call at a time, so a slow read (an app asked for text it only
/// promised, which can take a while) never holds up the main actor, where devices' input is handled,
/// but for a device's text, which the main actor waits to see written (`Board.write`): the ⌘V a device
/// sends right after it (paste right away) must find it there.
/// The look is a Task.sleep loop, not a RunLoop timer, which the CLI's dispatchMain never runs.
@MainActor
final class HostClipboard {
    /// Share clipboard with devices.
    private(set) var enabled: Bool
    /// Include images (HostConfig.shareClipboardImages): the Mac owner's say on images.
    private(set) var imagesOn: Bool
    /// The window lists' `clipboard`: 2 while on with images, 1 while on without, nil while off (and while
    /// this Mac is locked, which the coordinator's list leaves out: LockPolicy.list).
    var advertised: Int? { ClipboardPolicy.hostGeneration(shareClipboard: enabled, images: imagesOn) }
    /// This Mac's screen is locked (LockPolicy, docs/locked-mac-plan.md; `setLocked`): the clipboard is
    /// paused both ways, nothing read (no look) and nothing written (a device's text dropped), while the
    /// subscriptions stay.
    private(set) var locked = false
    /// The lock's gate now (SessionLock's, set on its own queue the moment a witness says locked): asked
    /// before each look and each write, so neither happens after the lock even before `setLocked`. The
    /// server withholds a kind 32 to a device from that moment too.
    var isLocked: () -> Bool = { false }
    private var paused: Bool { locked || isLocked() }

    private let server: StreamServer
    /// The pasteboard, on its own queue: `NSPasteboard.general`, or a synthetic host's own.
    private let board: Board
    /// A synthetic host's own pasteboard: its name, said at its first subscription. Nil for the Mac's.
    private let testBoardName: String?
    private var saidTestBoard = false
    /// TEST ONLY (SILL_TEST_CLIPBOARD_LOG=1, a synthetic host): each decision, with sizes, never text.
    private let testLog: Bool
    /// The test hooks' line for `start` (one, when a variable is set), nil without them.
    let testHookLine: String?

    /// A subscriber: its connection, its name for the lines, whether it takes images (what its
    /// subscriptions said, ClipboardPolicy.subscriberTakesImages) and whether it is away from home
    /// (AwayPolicy: its images are fitted to ClipboardPolicy.awayImageBytes).
    private struct Subscriber {
        let connection: NWConnection
        let who: String
        var images: Bool
        let away: Bool
    }
    private var subscribers: [ObjectIdentifier: Subscriber] = [:]
    /// In the order they subscribed, for a stable order of sends.
    private var order: [ObjectIdentifier] = []
    private var look: Task<Void, Never>?
    /// Each connection's subscriptions and texts of the last second (ClipboardPolicy.hostReceives).
    private var arrivals: [ObjectIdentifier: [Double]] = [:]
    /// macOS's answer at the last look, for its line (ClipboardPolicy.accessLine); kept for the launch.
    private var reportedAccess: ClipboardPolicy.MacAccess?
    private lazy var ignored = RefusalSummary(queue: .main, categories: ["rate", "tooLong", "undecodable", "images"]) { counts in
        ClipboardPolicy.Copy.ignoredLine(rate: counts["rate"] ?? 0, tooLong: counts["tooLong"] ?? 0,
                                         undecodable: counts["undecodable"] ?? 0, images: counts["images"] ?? 0)
    }
    /// Copied images are fitted here (ClipboardImage.fitted): never on the pasteboard's queue, where a
    /// device's text waits to be written while the main actor waits for it (#300's D8).
    private let fitQueue = DispatchQueue(label: "sill.clipboard.fit", qos: .utility)
    /// Moves at every copy sent or written (a look's decision that sends, a device's text or image): a fit
    /// that finishes after a newer one is dropped, so an older image never lands after newer text.
    private var copies = 0

    /// `synthetic`: a host that never touches this Mac's clipboard (as it never reads the real
    /// pointer): a pasteboard of its own, `me.saffer.sill.test.<pid>`, or the one TEST ONLY
    /// `SILL_TEST_PASTEBOARD` names, so a test can write and read it. macOS asks about no pasteboard
    /// but the general one, so a synthetic host's reads are always allowed, unless TEST ONLY
    /// `SILL_TEST_CLIPBOARD_ACCESS` says otherwise: `allowed`, `notAsked`, `asks` or `denied`, or the
    /// path of a file holding one of them, read at each look (so a test can change it while it runs).
    init(server: StreamServer, enabled: Bool, images: Bool, launchID: String, synthetic: Bool,
         environment env: [String: String] = ProcessInfo.processInfo.environment) {
        self.server = server
        self.enabled = enabled
        self.imagesOn = images
        var lines: [String] = []
        if synthetic {
            let named = env["SILL_TEST_PASTEBOARD"].flatMap { $0.isEmpty ? nil : $0 }
            let name = named ?? "me.saffer.sill.test.\(getpid())"
            var access: @Sendable () -> ClipboardPolicy.MacAccess = { .allowed }
            switch env["SILL_TEST_CLIPBOARD_ACCESS"] {
            case nil, "":
                break
            case let spec? where ClipboardPolicy.MacAccess(rawValue: spec) != nil:
                let fixed = ClipboardPolicy.MacAccess(rawValue: spec)!
                access = { fixed }
                lines.append("Test clipboard access: macOS's answer for this host's pasteboard is \(spec).")
            case let spec? where spec.hasPrefix("/"):
                access = {
                    let word = (try? String(contentsOfFile: spec, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return word.flatMap(ClipboardPolicy.MacAccess.init(rawValue:)) ?? .allowed
                }
                lines.append("Test clipboard access: macOS's answer for this host's pasteboard is read from \(spec) at each look.")
            case let spec?:
                lines.append("SILL_TEST_CLIPBOARD_ACCESS=\(spec) ignored: allowed, notAsked, asks, denied or a file's path.")
            }
            board = Board(name: name, launchID: launchID, access: access)
            testBoardName = name
        } else {
            board = Board(name: nil, launchID: launchID, access: { MacClipboard.access() })
            testBoardName = nil
            if let named = env["SILL_TEST_PASTEBOARD"], !named.isEmpty {
                lines.append("SILL_TEST_PASTEBOARD ignored: only a --synthetic host takes it.")
            }
            if let spec = env["SILL_TEST_CLIPBOARD_ACCESS"], !spec.isEmpty {
                lines.append("SILL_TEST_CLIPBOARD_ACCESS ignored: only a --synthetic host takes it.")
            }
        }
        switch (env["SILL_TEST_CLIPBOARD_LOG"], synthetic) {
        case (nil, _), ("", _):
            testLog = false
        case ("1", true):
            testLog = true
            lines.append("Test clipboard log: each change and each device's text is printed with its size, never its text.")
        case ("1", false):
            testLog = false
            lines.append("SILL_TEST_CLIPBOARD_LOG ignored: only a --synthetic host takes it.")
        case (let value?, _):
            testLog = false
            lines.append("SILL_TEST_CLIPBOARD_LOG=\(value) ignored: 1 turns it on.")
        }
        testHookLine = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: The setting

    /// Turns sharing on or off at once; true when it changed (the caller sends the lists again). Off
    /// drops every subscription without a line: the devices see the list without `clipboard`.
    @discardableResult
    func setEnabled(_ on: Bool) -> Bool {
        guard on != enabled else { return false }
        enabled = on
        if !on {
            for sub in subscribers.values { server.setClipboardImages(sub.connection, false) }
            subscribers = [:]
            order = []
            arrivals = [:]
            stopLooking()
        }
        return true
    }

    /// Include images on or off at once; true when it changed (the caller sends the lists again: they say 2
    /// or 1). Off, no image is read, fitted, sent or taken; the subscriptions and what each said stay.
    @discardableResult
    func setImages(_ on: Bool) -> Bool {
        guard on != imagesOn else { return false }
        imagesOn = on
        for id in order { tellServer(id) }
        if !on { copies += 1 }      // a fit under way goes nowhere
        return true
    }

    /// This Mac's screen locked (true) or unlocked (LockPolicy, docs/locked-mac-plan.md). Locked: the
    /// look stops, so nothing is read, and a device's text is not written; the subscriptions stay.
    /// Unlocked: the look starts again for the subscribers, the change count as it stands taken as seen,
    /// so what was copied while the Mac was locked is never sent.
    func setLocked(_ on: Bool) {
        guard on != locked else { return }
        locked = on
        if on { stopLooking() } else if !subscribers.isEmpty { startLooking() }
    }

    // MARK: A device's message

    /// A kind 32 from `connection` (decoded once by the coordinator, nil when it did not decode), named
    /// `who` for the lines, `away` from home or not (AwayPolicy). False when it brought text or an image
    /// that was dropped because this Mac is locked (the coordinator says so, a line a minute at most).
    @discardableResult
    func received(_ clip: Clipboard?, from connection: NWConnection, who: String, away: Bool) -> Bool {
        guard enabled else { return true }
        let id = ObjectIdentifier(connection)
        // What it asks first, then the rate, which a stop never meets (ClipboardPolicy.hostReceives).
        let got = ClipboardPolicy.hostReceives(clip, arrivals: arrivals[id] ?? [], now: ProcessInfo.processInfo.systemUptime,
                                               imagesOn: imagesOn)
        arrivals[id] = got.kept
        // What its subscription says of images, from this message (a Paste leaves it as it was).
        let images = clip.map { ClipboardPolicy.subscriberTakesImages($0, was: subscribers[id]?.images) } ?? false
        switch got.ask {
        case .subscribe:
            subscribe(connection, who: who, images: images, away: away)
        case .set(let text):
            subscribe(connection, who: who, images: images, away: away)
            // Locked: written nowhere and sent to nobody (LockPolicy); the subscription stays.
            guard !paused else { return false }
            board.write(text)
            copies += 1
            Stats.shared.bump("clip.recv")
            let others = ClipboardPolicy.forward(to: order, from: id).compactMap { subscribers[$0]?.connection }
            if testLog { print("Test clipboard: \(text.utf8.count) bytes from \(who) set on the pasteboard, sent to \(others.count) other device\(others.count == 1 ? "" : "s").") }
            send(payload: ClipboardPolicy.payload(text: text), to: others)
        case .setImage(let image):
            subscribe(connection, who: who, images: images, away: away)
            guard !paused else { return false }
            board.write(image: image)
            copies += 1
            Stats.shared.bump("clip.recv")
            let takers = order.compactMap { id in subscribers[id].map { (id: id, images: $0.images, away: $0.away) } }
            let others = ClipboardPolicy.forwardImage(to: takers, from: id, bytes: image.count).compactMap { subscribers[$0]?.connection }
            if testLog { print("Test clipboard: an image of \(image.count) bytes from \(who) set on the pasteboard, sent to \(others.count) other device\(others.count == 1 ? "" : "s").") }
            // Encoded again only for someone (#300's D7).
            if !others.isEmpty { sendImage(payload: ClipboardPolicy.payload(image: image), to: others) }
        case .stop:
            guard let gone = subscribers.removeValue(forKey: id) else { return true }
            order.removeAll { $0 == id }
            server.setClipboardImages(connection, false)
            print(ClipboardPolicy.Copy.stoppedLine(device: gone.who))
            if subscribers.isEmpty { stopLooking() }
        case .refuse(let why):
            ignored.count(why.rawValue)     // "rate", "tooLong", "undecodable", "images"
        }
        return true
    }

    /// The device left: forgotten without a line.
    func clientLeft(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        arrivals[id] = nil
        guard subscribers.removeValue(forKey: id) != nil else { return }
        order.removeAll { $0 == id }
        if subscribers.isEmpty { stopLooking() }
    }

    /// Subscribes `connection` (taking images or not), or, already subscribed, takes what it says of
    /// images now: a line when that changed.
    private func subscribe(_ connection: NWConnection, who: String, images: Bool, away: Bool) {
        let id = ObjectIdentifier(connection)
        if let was = subscribers[id] {
            guard was.images != images else { return }
            subscribers[id]?.images = images
            print(ClipboardPolicy.Copy.imagesLine(device: was.who, images: images))
            tellServer(id)
            return
        }
        if let testBoardName, !saidTestBoard {
            saidTestBoard = true
            print("Test clipboard: a pasteboard of this host's own, \(testBoardName), never this Mac's clipboard.")
        }
        subscribers[id] = Subscriber(connection: connection, who: who, images: images, away: away)
        order.append(id)
        print(ClipboardPolicy.Copy.sharesLine(device: who, images: images))
        tellServer(id)
        if !locked { startLooking() }      // locked: the unlock starts it (`setLocked`)
    }

    /// The server's word on `id`'s connection: its kind 32 may be an image's 12 MiB only while it takes
    /// images and Include images is on (StreamMessage.maxClientPayload(for:clipboardImages:), #300's D10).
    private func tellServer(_ id: ObjectIdentifier) {
        guard let sub = subscribers[id] else { return }
        server.setClipboardImages(sub.connection, imagesOn && sub.images)
    }

    /// Whether a look reads the pasteboard's image: only while Include images is on and a subscriber takes
    /// images (#300's D8: every image copied was read and fitted for devices that take none).
    private var wantsImages: Bool { imagesOn && subscribers.values.contains(where: \.images) }

    // MARK: The pasteboard

    private func startLooking() {
        guard look == nil else { return }
        board.takeAsSeen()             // what is on the clipboard now is never sent
        look = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ClipboardPolicy.lookInterval))
                guard !Task.isCancelled, let board = self?.board else { return }
                // A locked Mac's pasteboard is not read (LockPolicy), even before `setLocked` stops this.
                if self?.paused == true { continue }
                // On the board's queue; the main actor waits for nothing meanwhile.
                let looked = await board.look(images: self?.wantsImages ?? false)
                guard !Task.isCancelled, let self else { return }
                // Locked during the look: what it found goes nowhere (and its change counts as seen).
                if self.paused { continue }
                self.lookedAt(looked)
            }
        }
    }

    private func stopLooking() {
        look?.cancel()
        look = nil
    }

    /// A look: macOS's answer's line when it changed (ClipboardPolicy.accessLine), and a change the
    /// board looked at to every subscriber, when ClipboardPolicy took it.
    private func lookedAt(_ looked: Board.Look) {
        if let line = ClipboardPolicy.accessLine(was: reportedAccess, now: looked.access) { print(line) }
        reportedAccess = looked.access
        guard let (count, decision) = looked.change else { return }
        switch decision {
        case .send(let payload):
            copies += 1
            let to = order.compactMap { subscribers[$0]?.connection }
            if testLog { print("Test clipboard: change \(count) sent to \(to.count) device\(to.count == 1 ? "" : "s") (\(payload.count) bytes of JSON).") }
            send(payload: payload, to: to)
        case .sendImage(let image):
            copies += 1
            fit(image, change: count)
        case .skip(let why):
            if testLog { print("Test clipboard: change \(count) not sent (\(why.rawValue)).") }
        }
    }

    /// A copied image (as the pasteboard holds it) fitted on `fitQueue` for the subscribers that take
    /// images, once for those at home and once for those away, then sent (`fitted`).
    private func fit(_ image: Data, change count: Int) {
        let takers = order.compactMap { subscribers[$0] }.filter(\.images)
        let home = takers.contains { !$0.away }, away = takers.contains(where: \.away)
        guard imagesOn, home || away else { return }
        let copy = copies
        fitQueue.async { [weak self] in
            let forHome = home ? ClipboardImage.fitted(image, max: ClipboardPolicy.imageCap(away: false)) : nil
            let forAway = away ? ClipboardImage.fitted(forHome ?? image, max: ClipboardPolicy.imageCap(away: true)) : nil
            let payloads = (home: forHome.flatMap(ClipboardPolicy.payload(image:)), away: forAway.flatMap(ClipboardPolicy.payload(image:)))
            Task { @MainActor in self?.fitted(payloads, of: image.count, change: count, copy: copy) }
        }
    }

    /// A copied image made to fit: to each subscriber that takes images as they are now, the fit for its
    /// route, unless a newer copy went or was written since (`copies`), this Mac locked or images went off.
    private func fitted(_ payloads: (home: Data?, away: Data?), of bytes: Int, change count: Int, copy: Int) {
        guard copy == copies, enabled, imagesOn, !paused else {
            if testLog { print("Test clipboard: change \(count), an image, not sent (a newer copy, a lock, or images off came while it was made to fit).") }
            return
        }
        let takers = order.compactMap { subscribers[$0] }.filter(\.images)
        let home = takers.filter { !$0.away }.map(\.connection), away = takers.filter(\.away).map(\.connection)
        if testLog {
            func size(_ p: Data?) -> String { p.map { "\($0.count) bytes of JSON" } ?? "none fits" }
            print("Test clipboard: change \(count), an image of \(bytes) bytes, sent to \(home.count) device\(home.count == 1 ? "" : "s") at home (\(size(payloads.home)))"
                  + " and \(away.count) away (\(size(payloads.away))).")
        }
        if !home.isEmpty { sendImage(payload: payloads.home, to: home) }
        if !away.isEmpty { sendImage(payload: payloads.away, to: away) }
    }

    /// The pasteboard, read and written on `queue` alone, in order: a write a device asked for is
    /// done before any later look, so the look always finds it as this host's own (its change count
    /// taken as seen, and its marker naming this launch besides).
    private final class Board: @unchecked Sendable {
        private let queue = DispatchQueue(label: "sill.clipboard", qos: .userInitiated)
        private let board: NSPasteboard
        private let launchID: String
        /// macOS's answer for this pasteboard (MacClipboard.access, or a synthetic host's own).
        private let access: @Sendable () -> ClipboardPolicy.MacAccess
        // On `queue`: the change count the looks have dealt with, the one after this host's own last
        // write, the first look at a change whose pasteboard was still empty (ClipboardPolicy.hostWaits),
        // and macOS's answer at the last look (or when the count was last taken as seen).
        private var seen = 0
        private var ownChangeCount: Int?
        private var firstLook: (count: Int, at: Double)?
        private var lastAccess: ClipboardPolicy.MacAccess?

        /// What a look found: macOS's answer, and a change of the pasteboard with ClipboardPolicy's
        /// decision (nil when the count did not move, the pasteboard was still empty, or nothing was read).
        struct Look {
            let access: ClipboardPolicy.MacAccess
            let change: (count: Int, decision: ClipboardPolicy.HostDecision)?
        }

        /// `name`: a pasteboard of a synthetic host's own; nil, the Mac's.
        init(name: String?, launchID: String, access: @escaping @Sendable () -> ClipboardPolicy.MacAccess) {
            board = name.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
            self.launchID = launchID
            self.access = access
        }

        /// The change count as it stands is seen: what is on the clipboard now is never sent. While
        /// macOS does not allow every read, nothing is read: the first look it allows takes it then.
        func takeAsSeen() {
            queue.async {
                let now = self.access()
                self.lastAccess = now
                if ClipboardPolicy.hostLooks(now) { self.seen = self.board.changeCount }
            }
        }

        /// One look: macOS's answer, then, while it allows every read and the change count moved,
        /// ClipboardPolicy's decision from the items' types, the marker and the text read only when it
        /// needs them, and the image's bytes only when `images` (a subscriber takes them).
        func look(images: Bool) async -> Look {
            await withCheckedContinuation { done in
                queue.async { done.resume(returning: self.lookNow(images: images)) }
            }
        }

        private func lookNow(images: Bool) -> Look {
            let access = self.access()
            let step = ClipboardPolicy.accessStep(was: lastAccess, now: access)
            lastAccess = access
            switch step {
            case .wait:
                return Look(access: access, change: nil)
            case .takeAsSeen:
                // Allowed again: what was copied while macOS asked or denied is never sent.
                seen = board.changeCount
                firstLook = nil
                return Look(access: access, change: nil)
            case .look:
                break
            }
            let count = board.changeCount
            guard count != seen else { return Look(access: access, change: nil) }
            let types = (board.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
            // Cleared and not yet written: look again (the write does not move the count).
            let now = ProcessInfo.processInfo.systemUptime
            if firstLook?.count != count { firstLook = (count, now) }
            if ClipboardPolicy.hostWaits(types: types, firstLook: firstLook?.at ?? now, now: now) {
                return Look(access: access, change: nil)
            }
            seen = count
            let own = NSPasteboard.PasteboardType(ClipboardPolicy.ownType)
            let decision = ClipboardPolicy.hostDecides(types: types, changeCount: count, ownChangeCount: ownChangeCount,
                                                       launchID: launchID,
                                                       ownMarker: { self.board.string(forType: own) },
                                                       text: { self.board.string(forType: .string) },
                                                       image: images ? { self.image() } : nil)
            return Look(access: access, change: (count, decision))
        }

        /// The pasteboard's image as it holds it: its PNG, else its JPEG, its HEIC, its TIFF. Read here,
        /// fitted on HostClipboard's `fitQueue`.
        private func image() -> Data? {
            for type in ["public.png", "public.jpeg", "public.heic", "public.tiff"] {
                if let data = board.data(forType: NSPasteboard.PasteboardType(type)), !data.isEmpty { return data }
            }
            return nil
        }

        /// A device's image, as `write(_:)` writes its text.
        func write(image: Data) {
            write { item in
                item.setData(image, forType: NSPasteboard.PasteboardType(Clipboard.imageType(image) ?? "public.png"))
            }
        }

        /// A device's text, for this Mac only, marked as this launch's, its change count kept. Written
        /// whatever macOS says of reads: writing needs no leave. Synchronous (the review of #242): the
        /// main actor, which handles each device's messages in order, returns from `received` only once
        /// the pasteboard holds the text, so the ⌘V a device sends after it (paste right away, 50 ms
        /// after the receipt the network queue echoed at once) always pastes it. Written asynchronously,
        /// as before, a main actor busy as the text arrived (a host's first stream start held it 70 to
        /// 150 ms) took the text and the keys back to back: V's key came within half a millisecond of the
        /// write's end and before it in 4 of 25 pastes on loopback, where with the main actor free it
        /// came 50 to 66 ms after. The cost: the write (about a millisecond) and a look the queue is in
        /// the middle of. Nothing on this queue ever waits for the main actor, so it cannot deadlock.
        func write(_ text: String) {
            write { $0.setString(text, forType: .string) }
        }

        private func write(_ fill: (NSPasteboardItem) -> Void) {
            queue.sync {
                let prepared = self.board.prepareForNewContents(with: .currentHostOnly)
                let item = NSPasteboardItem()
                fill(item)
                item.setString(self.launchID, forType: NSPasteboard.PasteboardType(ClipboardPolicy.ownType))
                self.board.writeObjects([item])
                // The count after it: read back while macOS allows reads, as the looks do; else the one
                // the write began with, which the write itself does not move.
                let count = self.lastAccess.map(ClipboardPolicy.hostLooks) == false ? prepared : self.board.changeCount
                self.ownChangeCount = count
                self.seen = count
            }
        }
    }

    private func send(payload: Data?, to connections: [NWConnection]) {
        guard let payload, !connections.isEmpty else { return }
        let message = StreamMessage(kind: .clipboard, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload)
        server.send(each: connections.map { ($0, message) })
        for _ in connections { Stats.shared.bump("clip.sent") }
    }

    /// An image's kind 32 on the server's image path (StreamServer.sendClipboardImage), which counts each
    /// as it goes (`clip.sent`).
    private func sendImage(payload: Data?, to connections: [NWConnection]) {
        guard let payload, !connections.isEmpty else { return }
        let message = StreamMessage(kind: .clipboard, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload)
        server.sendClipboardImage(message, to: connections)
    }
}

/// macOS's paste privacy for this Mac's clipboard (ClipboardPolicy.MacAccess; macOS 15.4 and later),
/// for HostClipboard's looks and Sill.app's Settings › General. `access` reads NSPasteboard.general's
/// `accessBehavior` alone, which never brings macOS's alert and reads nothing of the clipboard.
package enum MacClipboard {
    package static func access() -> ClipboardPolicy.MacAccess {
        if #available(macOS 15.4, *) {
            return ClipboardPolicy.macAccess(raw: NSPasteboard.general.accessBehavior.rawValue)
        }
        return ClipboardPolicy.macAccess(raw: nil)
    }

    /// Settings › General's Allow in System Settings while macOS has not asked about Sill yet
    /// (`notAsked`): one read of the clipboard, made because the person clicked, so that macOS asks
    /// about Sill and lists it under Paste from Other Apps. What it read is dropped at once and never
    /// leaves this process. Off the main thread, which macOS's alert would hold until it is answered;
    /// `then` runs on the main queue afterwards. Never from a look.
    package static func askOnce(then done: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = NSPasteboard.general.string(forType: .string)
            DispatchQueue.main.async(execute: done)
        }
    }
}
