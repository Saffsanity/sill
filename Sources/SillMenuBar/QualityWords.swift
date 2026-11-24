import Foundation
import StreamProtocol

/// The quality presets as this Mac's menu, Settings and card name them, in Sill.app's language.
/// StreamProtocol's `name` and `title` stay English: the host's log, the wire and the device use them.
extension QualityPreset {
    var localizedName: String {
        switch self {
        case .low: String(localized: "Low", comment: "Quality preset")
        case .efficient: String(localized: "Efficient", comment: "Quality preset")
        case .balanced: String(localized: "Balanced", comment: "Quality preset")
        case .high: String(localized: "High", comment: "Quality preset")
        case .pro: String(localized: "Pro", comment: "Quality preset")
        case .ultra: String(localized: "Ultra", comment: "Quality preset")
        case .extreme: String(localized: "Extreme", comment: "Quality preset")
        }
    }

    /// "Balanced — 15 Mbps".
    var localizedTitle: String { String(localized: "\(localizedName) — \(Self.mbps(rawValue)) Mbps") }

    /// A preset's title, or "Custom — 12 Mbps" for a bitrate set by hand.
    static func localizedTitle(forBitrate bitrate: Int) -> String {
        QualityPreset(rawValue: bitrate)?.localizedTitle ?? String(localized: "Custom — \(mbps(bitrate)) Mbps")
    }

    /// A preset's name, or "12 Mbps" for a bitrate set by hand.
    static func localizedName(forBitrate bitrate: Int) -> String {
        QualityPreset(rawValue: bitrate)?.localizedName ?? String(localized: "\(mbps(bitrate)) Mbps")
    }

    /// "Low · Standard", "Pro · Retina".
    static func localizedShortTitle(bitrate: Int, captureScale: Double) -> String {
        let resolution = captureScale >= 1.5 ? String(localized: "Retina") : String(localized: "Standard")
        return String(localized: "\(localizedName(forBitrate: bitrate)) · \(resolution)")
    }

    static var localizedFastLinkNote: String {
        String(localized: "\(QualityPreset.ultra.localizedName) and \(QualityPreset.extreme.localizedName) need the USB cable or very fast Wi\u{2011}Fi; if the picture lags, step down.")
    }
}
