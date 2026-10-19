import Foundation
import CryptoKit
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// SceneStorage contains references to paired identity and window identity, never credentials,
/// addresses, a connection seed, window titles or keyboard state. visionOS owns spatial placement; a bounded credential-free scene-set journal can
/// recover missing windows after a whole-process exit.
struct VisionWorkspace: Codable, Equatable {
    var version = 1
    var macID: String
    var window: Window?
    var width: Double?
    var height: Double?

    struct Window: Codable, Equatable {
        var id: UInt32
        var bundleID: String
        var titleDigest: String

        init(_ info: WindowInfo) {
            id = info.id
            bundleID = info.bundleID
            titleDigest = VisionWorkspace.digest(info.title)
        }
    }

    static func digest(_ title: String) -> String {
        SHA256.hash(data: Data(title.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ text: String) -> Self? {
        guard text.utf8.count <= 4096, let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.version == 1, !value.macID.isEmpty, value.macID.utf8.count <= 64,
              value.window.map({ !$0.bundleID.isEmpty && $0.bundleID.utf8.count <= 512 && $0.titleDigest.count == 64 }) ?? true,
              value.sizeIsValid else { return nil }
        return value
    }

    var encoded: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), data.count <= 4096 else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private var sizeIsValid: Bool {
        if width == nil && height == nil { return true }
        guard let width, let height else { return false }
        return width.isFinite && height.isFinite && width > 0 && height > 0 && width <= 3840 && height <= 2880
    }

    var size: CGSize? {
        guard sizeIsValid, let width, let height else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Numeric IDs can be recycled. A unique bundle + title identity survives host restarts;
    /// a unique remaining window of the same app can survive a changed document title.
    /// Ambiguous/missing apps fall back to Desktop. Restoration never launches an app.
    func source(in windows: [WindowInfo]) -> StreamSource {
        reconciledSource(in: windows, allowFallback: true) ?? .desktop
    }

    func reconciledSource(in windows: [WindowInfo], allowFallback: Bool) -> StreamSource? {
        guard let window else { return .desktop }
        let app = windows.filter { $0.bundleID == window.bundleID }
        let exact = app.filter { Self.digest($0.title) == window.titleDigest }
        if exact.count == 1 { return .window(exact[0].id) }
        guard allowFallback else { return nil }
        if exact.isEmpty, app.count == 1 { return .window(app[0].id) }
        return .desktop
    }
}
