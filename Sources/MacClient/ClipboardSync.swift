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
    private var synced = NSPasteboard.general.changeCount
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?

    init(client: StreamClient) {
        self.client = client
        client.onClipboard = { [weak self] clip in self?.received(clip) }
        client.$hostClipboard.removeDuplicates().sink { [weak self] shares in
            DispatchQueue.main.async {
                guard shares, Self.enabled, let self else { return }
                self.synced = NSPasteboard.general.changeCount   // what is here now stays here
                self.client.sendClipboard(Clipboard())             // the other Mac’s copies from now on
            }
        }.store(in: &subscriptions)
        client.onMoved = { [weak self] in
            guard let self, Self.enabled, self.client.hostClipboard else { return }
            self.client.sendClipboard(Clipboard())   // the Mac's copies on the new connection too
        }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.sendIfChanged() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func received(_ clip: Clipboard) {
        guard Self.enabled else { return }
        ClipboardPasteboard.write(clip)
        synced = NSPasteboard.general.changeCount
    }

    private func sendIfChanged() {
        let board = NSPasteboard.general
        guard Self.enabled, client.connected, client.hostClipboard, board.changeCount != synced else { return }
        synced = board.changeCount
        let clip = ClipboardPasteboard.read(imageLimit: Clipboard.maxImageFromDevice)
        guard clip.text != nil || clip.image != nil else { return }
        client.sendClipboard(clip)
    }
}
