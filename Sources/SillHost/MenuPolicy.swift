import Foundation
import StreamProtocol

// The Mac's menus (docs/menu-bar-plan.md §4.2): the mirror's decisions as values, so they can be
// checked without Accessibility. Pure: Foundation and StreamProtocol (the cache keeps the items a
// device is sent), checked on its own with swiftc (Tests/checks/menus).

/// One menu's items as last read, per id. AppKit validates a menu when it is read and throttles
/// that to about once a second per menu (measured): a read within the second returns the state
/// computed at the last one. So an answer comes from a read of less than a second ago, made while
/// the app was frontmost, and a read made while it was not (its states are an inactive app's) is
/// not read again until its second is over.
package struct MenuCache {
    package static let lifetime = 1.0

    package struct Entry: Equatable {
        package let items: [MacMenuItem]
        package let more: Int
        package let at: Double
        package let appWasFrontmost: Bool
        package init(items: [MacMenuItem], more: Int, at: Double, appWasFrontmost: Bool) {
            self.items = items; self.more = more; self.at = at; self.appWasFrontmost = appWasFrontmost
        }
    }

    private var entries: [String: Entry] = [:]

    package init() {}

    package mutating func store(_ id: String, _ entry: Entry) { entries[id] = entry }

    /// An entry to answer from: read less than a second ago, while the app was frontmost.
    package func fresh(_ id: String, now: Double) -> Entry? {
        guard let e = entries[id], e.appWasFrontmost, now - e.at < Self.lifetime else { return nil }
        return e
    }

    /// How long to wait before reading `id` again: the rest of the second after a read made while
    /// the app was not frontmost (AppKit would answer from that validation); else 0.
    package func wait(_ id: String, now: Double) -> Double {
        guard let e = entries[id], !e.appWasFrontmost, now - e.at < Self.lifetime else { return 0 }
        return Self.lifetime - (now - e.at)
    }

    package mutating func clear() { entries = [:] }
    package var isEmpty: Bool { entries.isEmpty }
}

/// Each connection's requests of the last second: at most 20 fetches and 4 presses (a sweep across
/// the iPad's bar opens a menu at a time; a person chooses far fewer), and one "ignored" line a
/// second at most. What is refused does not count.
package struct RequestRate {
    package static let fetchesPerSecond = 20, pressesPerSecond = 4

    private var fetches: [Double] = []
    private var presses: [Double] = []
    private var lastIgnoredLine: Double?

    package init() {}

    package mutating func allowFetch(now: Double) -> Bool { Self.allow(&fetches, limit: Self.fetchesPerSecond, now: now) }
    package mutating func allowPress(now: Double) -> Bool { Self.allow(&presses, limit: Self.pressesPerSecond, now: now) }

    /// True at most once a second: whether an "ignored" line may print now.
    package mutating func ignoredLineDue(now: Double) -> Bool {
        if let last = lastIgnoredLine, now - last < 1 { return false }
        lastIgnoredLine = now
        return true
    }

    private static func allow(_ arrivals: inout [Double], limit: Int, now: Double) -> Bool {
        arrivals.removeAll { now - $0 >= 1 }
        guard arrivals.count < limit else { return false }
        arrivals.append(now)
        return true
    }
}

/// The bar's menus as last read: only a change here (with the app's own change) moves the version.
package struct TopLevel: Equatable {
    package var titles: [String]
    package var enabled: [Bool]
    package init(titles: [String], enabled: [Bool]) { self.titles = titles; self.enabled = enabled }
}

/// Why a fetch or a press was not served: the words the device shows (`note`), and the log line's.
package enum MenuRefusal: Equatable {
    /// The item is disabled.
    case disabled
    /// Another version, an id that names nothing, or an item whose title is not the one shown.
    case changed
    /// The app quit.
    case gone
    /// The app did not answer Accessibility within the timeout (or is shown stale meanwhile).
    case notAnswering
    /// This Mac has not given Sill Accessibility.
    case notTrusted
    /// Over `RequestRate`'s limits.
    case tooMany
    /// Any other Accessibility error, by its name.
    case failed(String)

    package static let changedNote = "The menus changed. Open the menu again."
    package static let unavailableNote = "It isn’t available right now."
    package static let tooManyNote = "Too many requests. Open the menu again."
    package static let noAccessNote = "Allow Accessibility for Sill on the Mac (System Settings › Privacy & Security › Accessibility)."
    package static func notRespondingNote(_ app: String) -> String { "\(app) isn’t responding." }
    package static func goneNote(_ app: String) -> String { "\(app) is no longer open." }

    /// What the device shows as it is.
    package func note(app: String) -> String {
        switch self {
        case .disabled, .failed: Self.unavailableNote
        case .changed: Self.changedNote
        case .gone: Self.goneNote(app)
        case .notAnswering: Self.notRespondingNote(app)
        case .notTrusted: Self.noAccessNote
        case .tooMany: Self.tooManyNote
        }
    }

    /// The end of the host's "Menu from … refused: …" line.
    package func logReason(app: String) -> String {
        switch self {
        case .disabled: "disabled"
        case .changed: "the menus changed"
        case .gone: "\(app) is no longer open"
        case .notAnswering: "\(app) is not answering Accessibility"
        case .notTrusted: "no Accessibility permission"
        case .tooMany: "too many requests"
        case .failed(let error): "Accessibility refused it (\(error))"
        }
    }
}

package enum PressDecision: Equatable {
    /// The kept element, its title still the one shown.
    case press
    /// Found again by its path, its title the one shown.
    case pressFound
    case refuse(MenuRefusal)

    /// `elementValid`: the kept element answered; `current`: the item's title now (the kept
    /// element's, or the one found at the path; nil: nothing there); `shown`: the device's;
    /// `enabled`: its AXEnabled; `hasChildren`: it has a submenu (or a custom view's children).
    /// In order:
    /// 1. The title now must be the one shown, for a kept element as for one found again: a
    ///    delegate that fills its menu with `menu:updateItem:atIndex:shouldCancel:` keeps its
    ///    NSMenuItems and rewrites them, so after the validation the press's own read sets off the
    ///    same element can stand for another command. An empty or missing title never matches: no
    ///    device was shown one. An item retitled meanwhile ("Undo Typing" → "Undo Paste") is
    ///    refused too, which is what a device that showed the old title should hear.
    /// 2. A leaf only: AXPress on an item with children opens its menu on the Mac, and the app then
    ///    sits in menu tracking until someone closes it.
    /// 3. Enabled: a disabled item is refused (after the title, so a retitled and disabled item
    ///    reads as changed).
    package static func decide(elementValid: Bool, current: String?, shown: String?, enabled: Bool?,
                               hasChildren: Bool) -> PressDecision {
        guard let current, !current.isEmpty, current == shown else { return .refuse(.changed) }
        if hasChildren { return .refuse(.changed) }
        if enabled == false { return .refuse(.disabled) }
        return elementValid ? .press : .pressFound
    }
}

/// The host's own words for an item in a log line: the app, then each menu on the way and the item,
/// "Code › File › Save", each cleaned to SafeText's 64 characters. Nil when any is unknown: the line
/// then gives the id.
package enum MenuLog {
    package static func path(app: String, titles: [String?]) -> String? {
        var parts = [SafeText.label(app)]
        for t in titles {
            guard let t else { return nil }
            let clean = SafeText.label(t)
            guard !clean.isEmpty else { return nil }
            parts.append(clean)
        }
        return parts.joined(separator: " › ")
    }
}
