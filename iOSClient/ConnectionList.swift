import Foundation
import CoreGraphics

/// The connect screen's list vs. tiles arrangement, per-Mac groups, and stored preview pictures
/// (Windows App's Connection Center: tiles with live/stored screenshots and custom groups).
/// Pure rules: Foundation and CoreGraphics only, checked by `Tests/checks/connection-list`.
enum ConnectionList {
    enum Style: String, CaseIterable, Equatable {
        case list, tiles
        var toggled: Style { self == .list ? .tiles : .list }
    }

    static let styleKey = "Sill.connectionStyle"
    static let groupsKey = "Sill.macGroups"
    static let presetGroups = ["Home", "Work", "Personal"]
    static let maxGroupLength = 32
    static let twoColumnMinWidth: CGFloat = 340

    /// The stored style; `.list` for nil or any unknown value, so existing installs keep rows.
    static func storedStyle(_ raw: String?) -> Style {
        raw == Style.tiles.rawValue ? .tiles : .list
    }

    /// Cleans a group name: collapses whitespace/newlines, caps at `maxGroupLength`, nil when blank.
    static func cleanGroup(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        return String(joined.prefix(maxGroupLength))
    }

    static func decodeGroups(_ text: String?) -> [String: String] {
        guard let text, let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var out: [String: String] = [:]
        for (macID, group) in raw where !macID.isEmpty && macID.count <= 128 {
            if let clean = cleanGroup(group) { out[macID] = clean }
        }
        return out
    }

    static func encodeGroups(_ groups: [String: String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(groups)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func settingGroup(_ group: String?, for macID: String, in groups: [String: String]) -> [String: String] {
        guard !macID.isEmpty, macID.count <= 128 else { return groups }
        var next = groups
        if let clean = cleanGroup(group) {
            next[macID] = clean
        } else {
            next.removeValue(forKey: macID)
        }
        return next
    }

    /// Preset groups in order, followed by any custom group names currently assigned (sorted).
    static func availableGroups(in groups: [String: String]) -> [String] {
        let custom = Set(groups.values.compactMap(cleanGroup)).subtracting(presetGroups).sorted()
        return presetGroups + custom
    }

    struct Section<Item: Equatable>: Equatable {
        let title: String?
        let items: [Item]
    }

    /// Groups `items` by each item's `macID` in `groups`. When no item has a group, returns a single
    /// section with `title: nil` so the connect screen has no section header and matches the flat list.
    static func sections<Item: Equatable>(for items: [Item], macID: (Item) -> String?, groups: [String: String]) -> [Section<Item>] {
        guard !items.isEmpty else { return [] }
        var order: [String] = []
        var byGroup: [String: [Item]] = [:]
        var ungrouped: [Item] = []
        for item in items {
            if let id = macID(item), let g = cleanGroup(groups[id]) {
                if byGroup[g] == nil { order.append(g) }
                byGroup[g, default: []].append(item)
            } else {
                ungrouped.append(item)
            }
        }
        guard !order.isEmpty else { return [Section(title: nil, items: items)] }
        var out = order.compactMap { name in byGroup[name].map { Section(title: name, items: $0) } }
        if !ungrouped.isEmpty { out.append(Section(title: "Other", items: ungrouped)) }
        return out
    }

    /// Safe filename for a saved Mac's preview JPEG (`<macID>.jpg`); nil for anything that could
    /// traverse paths or is not a valid identifier.
    static func previewFileName(for macID: String) -> String? {
        guard !macID.isEmpty, macID.count <= 128,
              macID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return macID + ".jpg"
    }

    /// `.jpg` filenames in the preview folder whose Mac ID is no longer in `keepingMacIDs`.
    static func stalePreviewFiles(in files: [String], keepingMacIDs: Set<String>) -> [String] {
        files.filter { file in
            guard file.hasSuffix(".jpg") else { return false }
            let id = String(file.dropLast(4))
            return !keepingMacIDs.contains(id)
        }
    }

    /// How many tile columns fit `width`: 2 columns at 340 pt and wider, 1 column on narrower
    /// screens or at accessibility text sizes.
    static func columns(forWidth width: CGFloat, accessibleText: Bool) -> Int {
        (!accessibleText && width >= twoColumnMinWidth) ? 2 : 1
    }
}
