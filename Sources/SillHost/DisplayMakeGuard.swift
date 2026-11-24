import Foundation

/// A guard for issue #380: Sill for Mac stopping while it makes a display (four of five picks ended right after
/// "Removed virtual display N", the stage remaking its display; a MacBook Air M2 on macOS 27.2; the cause unknown).
/// A Mac with no working screen gets Sill's own display by itself as a device shows the Desktop (PR #200), so on a
/// Mac that stops there every session would end at its first Desktop; this keeps it to two runs (docs/virtual-desktop-
/// plan.md §9, as revised 2026-11-18):
/// - Just before making any display of Sill's (the stage's for a picked window, the Desktop's for a Mac with no
///   working screen), Sill.app writes a marker (`Store.markerName` in ~/Library/Application Support/Sill: what it
///   makes and when, synced), and removes it once the display came up or failed (`waitUntilOnline` returned), and at
///   a clean quit.
/// - At launch a marker means the last run ended while making a display, by a crash or a forced quit: one more stop in
///   a row (`displayMakeStops` in Sill.app's defaults). Two in a row and Sill makes no display by itself (`holds`): the
///   stage streams windows where they are, and a Mac with no working screen streams what macOS shows, until the person
///   chooses Try Again (Settings › Virtual Display). A display that comes up resets the count; so does Try Again.
/// - The CLI keeps no marker: it makes displays only with --virtual-display, run by a person watching. TEST ONLY:
///   `SILL_TEST_MAKE_GUARD=<folder>` gives a test host one there (the count in a file beside it), so a gate trips it
///   with a marker of its own and never touches Sill.app's.
///
/// The rule is pure (`atLaunch`, `holds`, `afterMake`, the marker's words, the lines); `Store` keeps the marker and the
/// count in the folder and the counter it is given, so the check runs it in a folder of its own. Main actor only, as
/// the displays are made there. Checked by Tests/checks/virtual-desktop.
enum DisplayMakeGuard {
    /// Stops in a row at which Sill makes no display by itself.
    static let tripAt = 2

    /// The count at launch: one more when the last run left a marker (it ended while making a display), else as kept.
    static func atLaunch(markerFound: Bool, stops: Int) -> Int {
        max(0, stops) + (markerFound ? 1 : 0)
    }

    /// Whether Sill makes no display by itself.
    static func holds(stops: Int) -> Bool { stops >= tripAt }

    /// The count after a make: 0 once a display came up, unchanged when it did not (a refusal or a timeout is no stop).
    static func afterMake(cameUp: Bool, stops: Int) -> Int { cameUp ? 0 : stops }

    /// What a marker says: the display's role ("stage", "desktop") and when, as ISO 8601 in UTC.
    static func marker(role: String, at date: Date) -> String {
        "\(role) \(iso.string(from: date))\n"
    }

    /// The role and the time a marker gives; nil for anything else (a marker half written still counts as found).
    static func parse(_ text: String) -> (role: String, at: Date)? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count == 2, ["stage", "desktop"].contains(String(parts[0])), let date = iso.date(from: String(parts[1])) else { return nil }
        return (String(parts[0]), date)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: The words

    /// The launch's line when the last run left a marker (`marker`: its text); nil when it left none.
    static func launchLine(marker: String?, stops: Int) -> String? {
        guard let marker else { return nil }
        let which = parse(marker).map { "its \($0.role == "stage" ? "window" : "Desktop") display, \(iso.string(from: $0.at))" }
        if holds(stops: stops) {
            return "Sill stopped while making a display last time (\(stops) runs in a row\(which.map { ": " + $0 } ?? "")); "
                + "it makes none by itself until you choose Try Again in Settings › Virtual Display."
        }
        return "Sill stopped while making a display last time\(which.map { " (" + $0 + ")" } ?? ""); "
            + "after \(tripAt) runs in a row it makes none by itself."
    }

    /// While the guard holds and the Desktop would have had Sill's display (no real screen works), once a run.
    static let headlessHeldLine = "Headless display: no real screen, but Sill stopped while making its displays \(tripAt) runs in a row; it makes none by itself until you choose Try Again in Settings › Virtual Display."

    /// Try Again chosen.
    static let tryAgainLine = "Displays: Try Again chosen; Sill makes its displays again."

    /// The menu's few words after "real window (virtual display: …)", and VirtualStage.Failure.guarded's.
    static let stageSummary = "Sill stopped twice while making its display"


    // MARK: The marker and the count

    /// The marker and the count (Sill.app: ~/Library/Application Support/Sill and its defaults' `displayMakeStops`; a
    /// test host: the folder SILL_TEST_MAKE_GUARD names and a file in it). Made once at launch, which takes what the
    /// last run left (`launchLine`). Main actor only.
    final class Store {
        static let markerName = "making-display"
        static let stopsKey = "displayMakeStops"

        let folder: URL
        private let writeStops: (Int) -> Void
        /// Stops in a row, as kept.
        private(set) var stops: Int
        /// The launch's line (nil: the last run left no marker).
        let launchLine: String?

        /// `readStops`/`writeStops`: where the count lives.
        init(folder: URL, readStops: () -> Int, writeStops: @escaping (Int) -> Void) {
            self.folder = folder
            self.writeStops = writeStops
            let marker = folder.appendingPathComponent(Self.markerName)
            let found = (try? String(contentsOf: marker, encoding: .utf8)) ?? (FileManager.default.fileExists(atPath: marker.path) ? "" : nil)
            let stops = DisplayMakeGuard.atLaunch(markerFound: found != nil, stops: readStops())
            self.stops = stops
            launchLine = DisplayMakeGuard.launchLine(marker: found, stops: stops)
            if found != nil {
                try? FileManager.default.removeItem(at: marker)
                writeStops(stops)
            }
        }

        /// Sill.app's: the folder in Application Support, the count in its defaults.
        static func app(defaults: UserDefaults = .standard) -> Store? {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            let folder = support.appendingPathComponent("Sill", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return Store(folder: folder, readStops: { defaults.integer(forKey: stopsKey) },
                         writeStops: { defaults.set($0, forKey: stopsKey) })
        }

        /// TEST ONLY (SILL_TEST_MAKE_GUARD=<folder>): the count in a file `display-make-stops` beside the marker.
        static func test(folder: URL) -> Store {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("display-make-stops")
            return Store(folder: folder,
                         readStops: { Int(((try? String(contentsOf: file, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 },
                         writeStops: { try? "\($0)\n".write(to: file, atomically: true, encoding: .utf8) })
        }

        /// Whether Sill makes no display by itself now.
        var holds: Bool { DisplayMakeGuard.holds(stops: stops) }

        /// Just before the private calls that make a display: the marker, written and synced.
        func willMake(_ role: String, at date: Date = Date()) {
            let url = folder.appendingPathComponent(Self.markerName)
            let data = Data(DisplayMakeGuard.marker(role: role, at: date).utf8)
            guard FileManager.default.createFile(atPath: url.path, contents: data),
                  let handle = try? FileHandle(forWritingTo: url) else { return }
            try? handle.synchronize()
            try? handle.close()
        }

        /// The make returned (`cameUp`: the display is there): the marker gone, the count reset when it came up.
        func made(cameUp: Bool) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.markerName))
            let after = DisplayMakeGuard.afterMake(cameUp: cameUp, stops: stops)
            if after != stops { stops = after; writeStops(after) }
        }

        /// A clean quit: a make in flight is no stop.
        func quitting() {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.markerName))
        }

        /// Try Again (Settings › Virtual Display): the count back to 0, so Sill makes its displays again.
        func tryAgain() {
            stops = 0
            writeStops(0)
        }

        /// Whether a marker is there now (for the check).
        var markerPresent: Bool { FileManager.default.fileExists(atPath: folder.appendingPathComponent(Self.markerName).path) }
    }
}
