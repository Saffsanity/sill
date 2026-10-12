import AppKit
import Network
import StreamProtocol

/// Files dropped on one of this Mac's windows from a Mac client (kinds 34 and 35): they arrive in
/// parts into `~/Downloads/From ‹device›/`, then this Mac drags them, as a person would, from the
/// drop point and lets go there, so the app under it gets a real drop (Finder copies them into the
/// folder, a mail app attaches them, an editor opens them). The drag starts in a small panel of Sill's own
/// that never activates Sill; the events that move and release it are posted like a device's input.
/// Main actor.
@MainActor
final class FileDrops: NSObject {
    private struct Incoming { let url: URL; let handle: FileHandle; let total: UInt64; var written: UInt64 }
    private var incoming: [UInt32: Incoming] = [:]
    private var done: [UInt32: URL] = [:]
    private var panel: NSPanel?
    private var pending: [URL] = []

    /// One part of a file from `device`.
    func chunk(_ payload: Data, device: String) {
        guard let c = FileChunk.unpack(payload), c.total <= FileChunk.maxTotal else { return }
        if c.offset == 0 {
            incoming[c.id].map { try? $0.handle.close() }
            let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("From \(Self.safe(device))", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = Self.unique(folder.appendingPathComponent(Self.safe(c.name)))
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: url) else {
                print("File drop: could not write \(url.path)")
                return
            }
            incoming[c.id] = Incoming(url: url, handle: handle, total: c.total, written: 0)
        }
        guard var file = incoming[c.id], c.offset == file.written else { return }
        file.handle.write(c.bytes)
        file.written += UInt64(c.bytes.count)
        if file.written >= file.total {
            try? file.handle.close()
            incoming[c.id] = nil
            done[c.id] = file.url
        } else {
            incoming[c.id] = file
        }
    }

    /// The files of `drop`, all here, dropped at `point` (global, top-left origin).
    func drop(_ drop: FileDrop, at point: CGPoint, device: String) {
        let urls = drop.files.compactMap { done.removeValue(forKey: $0) }
        guard !urls.isEmpty else { print("File drop from \(device): no file arrived whole; nothing dropped"); return }
        print("File drop from \(device): \(urls.map(\.lastPathComponent).joined(separator: ", ")) at \(Int(point.x)),\(Int(point.y))")
        pending = urls
        // A panel of Sill's under the drop point takes the press that starts the drag.
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let p = NSPanel(contentRect: NSRect(x: point.x - 4, y: screenH - point.y - 4, width: 8, height: 8),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        p.hidesOnDeactivate = false
        let view = DragStart(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        view.onPress = { [weak self] event in self?.begin(from: view, event: event) }
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
        // Press, move a little (the drag starts), back onto the point, let go: the app there takes the drop.
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ at: CGPoint, after: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
        post(.mouseMoved, point, after: 0.05)
        post(.leftMouseDown, point, after: 0.1)
        post(.leftMouseDragged, CGPoint(x: point.x + 6, y: point.y + 6), after: 0.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.panel?.orderOut(nil) }   // the target under it now
        post(.leftMouseDragged, CGPoint(x: point.x + 2, y: point.y + 2), after: 0.4)
        post(.leftMouseDragged, point, after: 0.55)
        post(.leftMouseUp, point, after: 0.75)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.panel?.close(); self?.panel = nil }
    }

    private func begin(from view: NSView, event: NSEvent) {
        let items = pending.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 8, height: 8), contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        guard !items.isEmpty else { return }
        view.beginDraggingSession(with: items, event: event, source: self)
    }

    static func safe(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "file" + cleaned : String(cleaned.prefix(200))
    }

    static func unique(_ url: URL) -> URL {
        var candidate = url, n = 2
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

extension FileDrops: NSDraggingSource {
    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic, .link]
    }
}

/// The panel's view: the press the host posts starts the drag here.
private final class DragStart: NSView {
    var onPress: ((NSEvent) -> Void)?
    override func mouseDown(with event: NSEvent) { onPress?(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A drag out of one of this Mac's windows (kinds 36 and 37): while a device holds the left button
/// over the stream, this Mac's drag pasteboard is watched; once an app puts files on it (a Finder
/// item, a mail attachment dragged), the device is told which, so a drag that leaves its window
/// goes on there with them, and each file it is dropped as is sent when the device asks. Main actor.
@MainActor
final class DragOut {
    var send: ((StreamMessage, NWConnection) -> Void)?
    private var watching: (connection: NWConnection, baseline: Int, offered: Bool)?
    private var timer: Timer?
    private var offers: [UInt32: [URL]] = [:]
    private var order: [UInt32] = []

    func buttonDown(_ connection: NWConnection) {
        watching = (connection, NSPasteboard(name: .drag).changeCount, false)
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.look() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func buttonUp(_ connection: NWConnection) {
        guard let w = watching, w.connection === connection else { return }
        timer?.invalidate(); timer = nil
        watching = nil
        if w.offered { offer(DragOffer(id: 0, files: []), to: connection) }   // the drag ended here
    }

    private func look() {
        guard var w = watching, !w.offered else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != w.baseline else { return }
        let urls = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        w.baseline = board.changeCount
        guard !urls.isEmpty else { watching = w; return }
        let id = UInt32.random(in: 1...UInt32.max)
        offers[id] = urls
        order.append(id)
        if order.count > 8 { offers[order.removeFirst()] = nil }
        w.offered = true
        watching = w
        let files = urls.map { DragOffer.File(name: $0.lastPathComponent,
                                             size: UInt64((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)) }
        print("Drag out: offering \(files.map(\.name).joined(separator: ", ")) to the device dragging")
        offer(DragOffer(id: id, files: files), to: w.connection)
    }

    private func offer(_ o: DragOffer, to connection: NWConnection) {
        send?(StreamMessage(kind: .dragOffer, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: Wire.encode(o)), connection)
    }

    /// One offered file to the device, in parts (kind 34), off the main actor.
    func request(_ r: FileRequest, from connection: NWConnection) {
        guard let urls = offers[r.offer], urls.indices.contains(r.index), let send else { return }
        let url = urls[r.index]
        if r.trash == true {
            // Dragged to the device's Trash, as onto this Mac's: it goes to this Mac's Trash, from which it can be put back.
            NSWorkspace.shared.recycle([url]) { _, error in
                print(error == nil ? "Drag out: \(url.lastPathComponent) moved to the Trash (dragged to the device's)"
                                   : "Drag out: could not move \(url.lastPathComponent) to the Trash: \(error!.localizedDescription)")
            }
            return
        }
        print("Drag out: sending \(url.lastPathComponent)")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            var offset: UInt64 = 0
            repeat {
                let bytes = (try? handle.read(upToCount: FileChunk.maxBytes)) ?? Data()
                let message = StreamMessage(kind: .fileChunk, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                            payload: FileChunk.pack(id: r.transfer, name: url.lastPathComponent, total: size, offset: offset, bytes: bytes))
                DispatchQueue.main.async { send(message, connection) }
                offset += UInt64(bytes.count)
                if bytes.isEmpty { break }
            } while offset < size
            try? handle.close()
        }
    }
}
