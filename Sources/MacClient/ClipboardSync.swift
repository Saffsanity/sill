import AppKit
import Combine
import StreamProtocol

/// The clipboard's text and images between this Mac and the controlled one (kind 32), for a host that
/// shares it and while Share Clipboard is on (the status item; on by default): a copy made on either
/// Mac becomes the other's clipboard as it is made (each side looks four times a second). Connecting
/// overwrites neither. Main thread.
final class ClipboardSync {
    static let defaultsKey = "SillClient.shareClipboard"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) == nil || UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private let client: StreamClient
    /// The local clipboard's changeCount when it last went across or was set from the other Mac.
    private var synced: Int?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var subscribed = false
    private var accepting: Int?

    init(client: StreamClient) {
        self.client = client
        client.onClipboard = { [weak self] clip in self?.received(clip) }
        client.$hostClipboard.removeDuplicates().sink { [weak self] capability in
            // A reset and the next list can arrive before the queued update: forget the old
            // connection now so even a reconnect with the same generation subscribes again.
            if !ClipboardPolicy.hostTakes(capability) {
                self?.subscribed = false
                self?.accepting = nil
            }
            DispatchQueue.main.async { self?.updateSubscription() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSubscription() }
        }.store(in: &subscriptions)
        client.onMoved = { [weak self] in
            self?.subscribed = false
            self?.updateSubscription()
        }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.sendIfChanged() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func updateSubscription() {
        guard client.connected, let request = ClipboardPolicy.viewerSubscription(hostClipboard: client.hostClipboard) else {
            subscribed = false
            accepting = nil
            return
        }
        if Self.enabled {
            guard !subscribed || accepting != request.accepts else { return }
            synced = nil
            client.sendClipboard(request)
            subscribed = true
            accepting = request.accepts
        } else if subscribed {
            client.sendClipboard(Clipboard(stop: true))
            subscribed = false
            accepting = nil
        }
    }

    private func received(_ clip: Clipboard) {
        guard Self.enabled, subscribed, ClipboardPolicy.hostTakes(client.hostClipboard) else { return }
        let clip = Clipboard(text: clip.text, image: (client.hostClipboard ?? 0) >= ClipboardPolicy.imageGeneration ? clip.image : nil)
        guard clip.text != nil || clip.image != nil, let payload = clip.payload(within: ClipboardPolicy.maxPayload),
              let clip = Wire.decode(Clipboard.self, from: payload) else { return }
        ClipboardPasteboard.write(clip)
        synced = ClipboardPasteboard.canRead ? NSPasteboard.general.changeCount : nil
    }

    private func sendIfChanged() {
        let board = NSPasteboard.general
        updateSubscription()
        guard Self.enabled, client.connected, subscribed, ClipboardPolicy.hostTakes(client.hostClipboard),
              ClipboardPasteboard.canRead else { synced = nil; return }
        guard let synced else { self.synced = board.changeCount; return }
        guard board.changeCount != synced else { return }
        self.synced = board.changeCount
        guard !ClipboardPasteboard.fromOtherMac else { return }   // the other Mac's copy, or one Sill here wrote
        let clip = ClipboardPasteboard.read(imageLimit: (client.hostClipboard ?? 0) >= ClipboardPolicy.imageGeneration ? Clipboard.maxImageFromDevice : 0)
        guard clip.text != nil || clip.image != nil else { return }
        client.sendClipboard(clip)
    }
}
