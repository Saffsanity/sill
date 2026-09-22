#if DEBUG
import UIKit
import StreamProtocol

/// DEBUG-only stand-in for a live session, used by the layout harness in `ContentView`.
///
/// It builds a `StreamClient` that *looks* connected — window list, thumbnails, icons, installed
/// apps — without touching the network: `StreamClient` only starts Bonjour when `startBrowsing()`
/// is called, so nothing here needs a hook into it. The display view stays black, since no frames
/// ever arrive; the harness is about layout, not picture.
///
/// None of this exists in a Release build.
enum MockCatalog {

    // MARK: - The catalog

    /// Bundle ID → the colour the design boards give that app's icon.
    private static let boardColours: [String: UInt32] = [
        "com.apple.finder": 0x2F62C4,
        "com.microsoft.VSCode": 0x1F6F8B,
        "com.apple.Notes": 0x8A6A10,
        "com.apple.Safari": 0x4A55C9,
        "com.apple.MobileSMS": 0x1F7A45,
        "com.apple.Terminal": 0x3A3D44,
        "com.apple.calculator": 0x3A3D44,
        "com.apple.iCal": 0xA3475F,
        "com.apple.mail": 0x2F62C4,
        "com.apple.Music": 0xA3475F,
    ]

    private static let mockWindows: [WindowInfo] = [
        WindowInfo(id: 101, title: "Desktop", appName: "Finder",
                   bundleID: "com.apple.finder", width: 1400, height: 900),
        WindowInfo(id: 102, title: "stream.py", appName: "Code",
                   bundleID: "com.microsoft.VSCode", width: 1440, height: 900),
        WindowInfo(id: 103, title: "Packing list", appName: "Notes",
                   bundleID: "com.apple.Notes", width: 1360, height: 880),
        WindowInfo(id: 104, title: "Release notes", appName: "Safari",
                   bundleID: "com.apple.Safari", width: 1400, height: 920),
        WindowInfo(id: 105, title: "Team chat", appName: "Messages",
                   bundleID: "com.apple.MobileSMS", width: 1280, height: 880),
        WindowInfo(id: 106, title: "zsh", appName: "Terminal",
                   bundleID: "com.apple.Terminal", width: 1400, height: 900),
    ]

    private static let mockApps: [AppInfo] = [
        AppInfo(name: "Calculator", bundleID: "com.apple.calculator"),
        AppInfo(name: "Calendar", bundleID: "com.apple.iCal"),
        AppInfo(name: "Mail", bundleID: "com.apple.mail"),
        AppInfo(name: "Music", bundleID: "com.apple.Music"),
    ]

    /// A client populated as if a Mac had just sent its whole catalog. Main thread.
    ///
    /// `active` is what the Mac would be streaming: the default is Code's window, as the boards
    /// draw it. `.none` is the state a fresh connection starts in — nothing picked yet, so the app
    /// drawer opens by itself — which the harness asks for with `-SillActive none`.
    static func client(active: StreamSource = .window(102)) -> StreamClient {
        let client = StreamClient()
        client.connected = true
        client.status = "Connected to Mac mini"
        client.macName = "Mac mini"
        client.windows = mockWindows
        client.active = active
        client.apps = mockApps
        client.videoSize = CGSize(width: 2800, height: 1800)

        var icons: [String: UIImage] = [:]
        for app in mockWindows.map({ ($0.bundleID, $0.appName) }) + mockApps.map({ ($0.bundleID, $0.name) }) {
            icons[app.0] = icon(colour: boardColours[app.0] ?? 0x3A3D44, initials: String(app.1.prefix(2)))
        }
        client.icons = icons

        var thumbnails: [UInt32: UIImage] = [:]
        for (index, window) in mockWindows.enumerated() {
            thumbnails[window.id] = thumbnail(seed: index)
        }
        client.thumbnails = thumbnails

        return client
    }

    // MARK: - Drawn images

    private static func colour(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    /// 64×64 rounded square in the board colour with the app's two-letter initials.
    private static func icon(colour hex: UInt32, initials: String) -> UIImage {
        let side: CGFloat = 64
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            colour(hex).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 15).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let text = initials as NSString
            let bounds = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2),
                      withAttributes: attributes)
        }
    }

    /// 208×132 window portrait: a dark body under a 9 pt title strip, with a few grey bars so it
    /// reads as a tiny window rather than a blank rectangle.
    private static func thumbnail(seed: Int) -> UIImage {
        let size = CGSize(width: 208, height: 132)
        return UIGraphicsImageRenderer(size: size).image { _ in
            colour(0x26282D).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            colour(0x34373D).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: size.width, height: 9)).fill()
            colour(0x4A4E56).setFill()
            for dot in 0..<3 {
                UIBezierPath(ovalIn: CGRect(x: 6 + CGFloat(dot) * 8, y: 3, width: 3, height: 3)).fill()
            }

            // Widths shuffle with the seed so six thumbnails are not one image repeated.
            let widths: [CGFloat] = [150, 96, 128, 72, 164, 110]
            colour(0xFFFFFF, alpha: 0.16).setFill()
            for row in 0..<5 {
                let width = widths[(seed + row) % widths.count]
                let bar = CGRect(x: 14, y: 26 + CGFloat(row) * 18, width: width, height: 7)
                UIBezierPath(roundedRect: bar, cornerRadius: 3.5).fill()
            }
        }
    }
}
#endif
