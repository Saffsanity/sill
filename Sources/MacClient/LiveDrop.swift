import AppKit
import StreamProtocol

/// A drag of files over the other Mac's windows, followed there as it goes (kind 38), to a Mac that
/// takes it (`hostLiveDrag`): the app under the pointer there shows where the files would land, and
/// this Mac's modifier keys choose what a drop does, as in a drag between two of its own windows.
///
/// - The other Mac's own files, dragged out of one of its windows (StreamInputView.dragOut): its drag
///   stays under way there, its button held, while the drag goes on here as promises; over any Sill
///   window the pointer there follows, let go on one it lands there, let go anywhere else (this Mac's
///   Finder, the Trash) the other Mac gives its drag up.
/// - This Mac's files dragged over a Sill window: sent at once, and the other Mac starts its own drag
///   of them under the pointer as they arrive; let go, they land there; dragged away, given up (the
///   other Mac removes its copies).
///
/// One drag at a time. Main thread.
final class LiveDrop {
    private let client: StreamClient
    init(client: StreamClient) { self.client = client }

    private struct Session {
        let id: UInt32
        let own: Bool
        /// The drag's own number (NSDraggingInfo.draggingSequenceNumber): a drag of this Mac's files.
        let sequence: Int
        var last: (window: UInt32?, x: Double, y: Double, modifiers: UInt64)?
    }
    private var session: Session?
    private var giveUp: DispatchWorkItem?

    var enabled: Bool { client.hostLiveDrag && client.connected }

    /// Shift, control, option and command, as InputEvent carries them (CGEventFlags' bits, NSEvent's).
    private static let mask = UInt64(NSEvent.ModifierFlags([.shift, .control, .option, .command]).rawValue)
    private var modifiers: UInt64 { UInt64(NSEvent.modifierFlags.rawValue) & Self.mask }

    /// The other Mac's own drag of an offer carried out of its window (`window`, at `at`): it goes on.
    func startOwn(offer: UInt32, window: UInt32?, at p: CGPoint) {
        if session != nil { cancel() }
        let id = UInt32.random(in: 1...UInt32.max)
        session = Session(id: id, own: true, sequence: -1)
        send(LiveDrag(id: id, phase: LiveDrag.start, window: window, x: Double(p.x), y: Double(p.y), modifiers: modifiers, offer: offer))
        windowLog("live drag \(id): the other Mac's own files, its drag held")
    }

    /// The drag over a Sill window (`window`, nil for the streamed one) at `p`, a fraction of its
    /// picture: what a drop would do there, as this Mac's cursor shows it.
    func over(_ info: NSDraggingInfo, window: UInt32?, at p: CGPoint) -> NSDragOperation {
        giveUp?.cancel(); giveUp = nil
        if info.draggingSource is StreamInputView {
            guard session?.own == true else { return [] }
            move(window, p)
            return modifiers & UInt64(NSEvent.ModifierFlags.option.rawValue) != 0 ? .copy : .move
        }
        if session?.sequence != info.draggingSequenceNumber {
            let urls = Self.files(info)
            guard !urls.isEmpty else { return [] }
            if session != nil { cancel() }
            let id = UInt32.random(in: 1...UInt32.max)
            session = Session(id: id, own: false, sequence: info.draggingSequenceNumber)
            send(LiveDrag(id: id, phase: LiveDrag.start, window: window, x: Double(p.x), y: Double(p.y), modifiers: modifiers))
            windowLog("live drag \(id): \(urls.count) file\(urls.count == 1 ? "" : "s") from this Mac, sending")
            let client = self.client
            DispatchQueue.global(qos: .userInitiated).async {
                let (ids, folders, total) = StreamInputView.upload(urls, client: client)
                client.send(.liveDrag, payload: Wire.encode(LiveDrag(id: id, phase: LiveDrag.filesSent, files: ids,
                                                                     folders: folders.isEmpty ? nil : folders)))
                windowLog("live drag \(id): \(ids.count) sent, \(total) bytes")
            }
        } else {
            move(window, p)
        }
        return .copy
    }

    /// The drag left a Sill window: a drag of this Mac's files that comes over none again within a
    /// moment is given up there (the other Mac's own drag waits for the drag to end: it may land
    /// on this Mac).
    func exited(_ info: NSDraggingInfo) {
        guard let s = session, !s.own else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.session?.id == s.id else { return }
            self.cancel()
        }
        giveUp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Let go over a Sill window: the files land there on the other Mac.
    func drop(_ info: NSDraggingInfo, window: UInt32?, at p: CGPoint) -> Bool {
        guard let s = session, s.own || s.sequence == info.draggingSequenceNumber else { return false }
        giveUp?.cancel(); giveUp = nil
        send(LiveDrag(id: s.id, phase: LiveDrag.drop, window: window, x: Double(p.x), y: Double(p.y), modifiers: modifiers))
        windowLog("live drag \(s.id): dropped on \(window.map { "window \($0)" } ?? "the streamed window")")
        session = nil
        return true
    }

    /// The drag out of the other Mac's window ended (StreamInputView's drag session): if it did not
    /// land on a Sill window, the other Mac gives its own drag up.
    func ownEnded() {
        guard session?.own == true else { return }
        cancel()
    }

    private func move(_ window: UInt32?, _ p: CGPoint) {
        guard var s = session else { return }
        let now = (window, Double(p.x), Double(p.y), modifiers)
        if let last = s.last, last.window == now.0, last.x == now.1, last.y == now.2, last.modifiers == now.3 { return }
        s.last = now
        session = s
        send(LiveDrag(id: s.id, phase: LiveDrag.move, window: window, x: now.1, y: now.2, modifiers: now.3))
    }

    private func cancel() {
        guard let s = session else { return }
        send(LiveDrag(id: s.id, phase: LiveDrag.cancel))
        windowLog("live drag \(s.id): given up")
        session = nil
    }

    private func send(_ d: LiveDrag) { client.send(.liveDrag, payload: Wire.encode(d)) }

    /// The files and folders a drag carries (a folder goes zipped).
    static func files(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            return v?.isRegularFile == true || v?.isDirectory == true
        }
    }
}
