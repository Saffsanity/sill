import AppKit
import Network
import StreamProtocol

/// The clipboard's text and image, shared with the devices that ask (kind 32; the Mac client): a device's copy
/// becomes this Mac's clipboard, and this Mac's becomes each asking device's, whenever its
/// changeCount moves (read four times a second while one asks; nothing is read while none does). What
/// this Mac took from a device is not sent back. Text and an image (Clipboard's limits). A
/// synthetic test host never writes this Mac's clipboard: it says what it would have written.
/// Main actor.
@MainActor
final class HostClipboard {
    private let server: StreamServer
    private let dryRun: Bool
    private var subscribers: [ObjectIdentifier: NWConnection] = [:]
    private var timer: Timer?
    private var lastSeen = NSPasteboard.general.changeCount

    init(server: StreamServer, dryRun: Bool) {
        self.server = server
        self.dryRun = dryRun
    }

    func received(_ clip: Clipboard, from c: NWConnection, device: String) {
        let id = ObjectIdentifier(c)
        if subscribers[id] == nil {
            subscribers[id] = c
            startPolling()   // what is on it now stays here: only a copy made from now on goes across
        }
        let text = clip.text.flatMap { $0.utf8.count <= Clipboard.maxBytes ? $0 : nil }
        guard text != nil || clip.image != nil else { return }
        if dryRun {
            print("Test clipboard: \(device) copied \(text.map { "\($0.count) characters" } ?? "no text")\(clip.image.map { ", an image of \($0.count) bytes" } ?? "") (not written: a test host)")
            return
        }
        ClipboardPasteboard.write(Clipboard(text: text, image: clip.image))
        lastSeen = NSPasteboard.general.changeCount
    }

    func clientLeft(_ c: NWConnection) {
        subscribers[ObjectIdentifier(c)] = nil
        if subscribers.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func startPolling() {
        guard timer == nil else { return }
        lastSeen = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let count = NSPasteboard.general.changeCount
        guard count != lastSeen else { return }
        lastSeen = count
        let clip = ClipboardPasteboard.read(imageLimit: Clipboard.maxImageFromHost)
        guard clip.text != nil || clip.image != nil, let payload = clip.payload(within: Clipboard.messageFromHost) else { return }
        let m = StreamMessage(kind: .clipboard, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload)
        server.send(each: subscribers.values.map { ($0, m) })
    }
}
