import Foundation

/// This app's version and build as its bundle says them (CFBundleShortVersionString and
/// CFBundleVersion), at the bottom of the connect screen and of the Settings panel (Noah, 2026-11-11:
/// "a version identifier (e.g. 0.6.1. (1304)) at the bottom of the app in the connection screen and at
/// the bottom of settings"; docs/version-label-plan.md): "Sill 0.6.2 (1400)", the form Sill for Mac's
/// Settings › General ends with, and to VoiceOver "Sill version 0.6.2, build 1400".
///
/// A Release, TestFlight or nightly build's number is its commit count (`Scripts/release-ios.sh
/// --build-number`); a build from Xcode says the project's own (4). Whatever the bundle says is shown,
/// cleaned only so it stays one line of plain words: nothing invented, nothing hidden.
///
/// Pure: Foundation only, checked in Tests/checks/version-label.
struct VersionLabel: Equatable {
    /// CFBundleShortVersionString, cleaned ("0.6.2"); nil when the bundle has none.
    let version: String?
    /// CFBundleVersion, cleaned ("1400", or whatever it holds: "4", "1.2.3"); nil when the bundle has none.
    let build: String?

    /// Nil when neither value is there: nothing to show.
    init?(version: Any?, build: Any?) {
        let v = Self.clean(version), b = Self.clean(build)
        guard v != nil || b != nil else { return nil }
        self.version = v
        self.build = b
    }

    /// From a bundle's Info.plist (`Bundle.main.infoDictionary`).
    init?(info: [String: Any]?) {
        self.init(version: info?["CFBundleShortVersionString"], build: info?["CFBundleVersion"])
    }

    /// The words shown, and copied: "Sill 0.6.2 (1400)"; "Sill 0.6.2" without a build, "Sill (1400)"
    /// without a version.
    var text: String {
        var words = "Sill"
        if let version { words += " \(version)" }
        if let build { words += " (\(build))" }
        return words
    }

    /// The words VoiceOver says: "Sill version 0.6.2, build 1400"; "Sill version 0.6.2" without a
    /// build, "Sill, build 1400" without a version.
    var spoken: String {
        var words = "Sill"
        if let version { words += " version \(version)" }
        if let build { words += ", build \(build)" }
        return words
    }

    /// A value as the label takes it: a string, or a number (an Info.plist can hold an integer where a
    /// string belongs) as its decimal digits, never a Boolean; trimmed, each run of white space inside
    /// it one space (Unicode's White_Space: tabs, newlines, no-break spaces), control and format
    /// characters gone (Unicode's Cc and Cf, a zero-width space and a right-to-left override among
    /// them: never a space where none shows), so it stays one line of plain words in the order written.
    /// Empty after that, or anything else: none.
    static func clean(_ value: Any?) -> String? {
        let raw: String
        switch value {
        case let s as String: raw = s
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): raw = n.stringValue
        default: return nil
        }
        let words = raw.unicodeScalars
            .filter { $0.properties.isWhitespace || ![.control, .format].contains($0.properties.generalCategory) }
            .split(whereSeparator: { $0.properties.isWhitespace })
            .map { String($0) }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
