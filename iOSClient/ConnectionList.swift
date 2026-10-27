import Foundation
import CoreGraphics

/// The connect screen's arrangement (rows, or tiles with each saved Mac's last picture), the groups a
/// saved Mac can be put in, and the stored pictures (issue #116; Windows App's Connection Center:
/// tiles with stored screenshots and custom groups). Pure rules: Foundation and CoreGraphics only
/// (with KeyframeRecovery's spacing), checked by `Tests/checks/connection-list`.
enum ConnectionList {
    enum Style: String, CaseIterable, Equatable {
        case list, tiles
        var toggled: Style { self == .list ? .tiles : .list }
    }

    static let styleKey = "Sill.connectionStyle"
    static let groupsKey = "Sill.macGroups"
    static let presetGroups = ["Home", "Work", "Personal"]
    /// The section of the Macs with no group, once any Mac has one. Never a group's own name: a group
    /// called Other would be a second section of that title.
    static let otherTitle = "Other"
    static let maxGroupLength = 32
    static let twoColumnMinWidth: CGFloat = 340

    /// The stored style; `.list` for nil or any unknown value, so existing installs keep rows (tiles are
    /// a choice, never the default: Noah on issue #116).
    static func storedStyle(_ raw: String?) -> Style {
        raw == Style.tiles.rawValue ? .tiles : .list
    }

    /// Whether a session's end keeps a picture of the Mac's screen for its tile. Only while tiles are
    /// on: the list is the default, and a Mac's screen is kept on the device only by someone who chose
    /// tiles; a session that ends while the list shows leaves the kept picture as it was (the list hides
    /// the pictures and keeps their files: `previewPlan`). Only from the session's window in front: the
    /// other of two Sill windows, or one in the background, is not where the person was looking. Only
    /// for a saved Mac: only its tile shows a picture.
    static func takesPreview(style: Style, sceneActive: Bool, saved: Bool) -> Bool {
        style == .tiles && sceneActive && saved
    }

    /// The saved Mac a row of the connect screen stands for: whose picture its tile shows and whose group
    /// it is listed under. The Mac its tag names (a network or Direct row) or its record (a Remote row),
    /// else, for a row with no tag, the saved Mac it is taken for by its Bonjour name, as a tap dials it
    /// (DiscoveryPolicy.rowMac, FoundMac.savedByName; a tag that names no saved Mac never stands for one).
    /// So every row of one Mac, Wired, Wi-Fi, Direct and Remote, shows that Mac's one picture (Noah,
    /// 2026-10-27: "all tiles show the same device, so should show the same preview"); another Mac's rows
    /// show its own, and a row of no saved Mac the placeholder.
    static func tileMac(macID: String?, savedByName: String?) -> String? {
        macID ?? savedByName
    }

    /// What a launch or a change of style (the switch beside the title, a saved Mac's menu, another Sill
    /// window) does to the tiles' pictures: the files that go and the Macs whose kept picture shows
    /// (`previewPlan`).
    struct PreviewPlan: Equatable {
        /// File names to delete: only those of Macs no longer saved.
        let delete: [String]
        /// The saved Macs whose kept picture shows, read from its file, in order.
        let show: [String]
    }

    /// A style never deletes a picture (Noah, 2026-10-27: switched to the list and back, the thumbnail
    /// comes back). With tiles every saved Mac with a file shows its picture; with the list none shows,
    /// and every file stays for when tiles come back. Either way the files of Macs no longer saved go
    /// (`stalePreviewFiles`); Remove Preview Picture and Forget delete a Mac's own. `files`: the names in
    /// the pictures' folder.
    static func previewPlan(style: Style, files: [String], savedMacIDs: Set<String>) -> PreviewPlan {
        let delete = stalePreviewFiles(in: files, keepingMacIDs: savedMacIDs)
        guard style == .tiles else { return PreviewPlan(delete: delete, show: []) }
        let show = files.filter { file in
            let macID = String(file.dropLast(4))
            return savedMacIDs.contains(macID) && previewFileName(for: macID) == file
        }.map { String($0.dropLast(4)) }.sorted()
        return PreviewPlan(delete: delete, show: show)
    }

    // MARK: The tile's picture: the stream's last keyframe, decoded

    // The picture is never taken from the screen. On a device the display layer's video is composited
    // outside the app's own drawing, so a snapshot of the view (`drawHierarchy`) drew black in its
    // place; the simulator composites it in software, which is why its photos looked right. The client
    // keeps the session's last keyframe with the parameter sets it came with (one frame, replaced at
    // each keyframe, dropped with the session) and decodes it at the session's end (KeyframePicture).

    /// The picture's width at most, in points, and its scale: 640 pixels at most, as the tile shows it.
    static let previewPoints: CGFloat = 320
    static let previewScale: CGFloat = 2

    /// The picture's size in pixels for a video of `video` pixels: at most `previewPoints` ×
    /// `previewScale` wide, never wider than the video, in its shape, the height rounded down (at least
    /// a pixel). Nil for no video.
    static func previewPixels(video: CGSize) -> (width: Int, height: Int)? {
        guard video.width.isFinite, video.height.isFinite, video.width >= 1, video.height >= 1 else { return nil }
        let width = min((previewPoints * previewScale).rounded(.down), video.width.rounded(.down))
        let height = max(1, (video.height * width / video.width).rounded(.down))
        return (Int(width), Int(height))
    }

    /// How long a decode may take before its picture is given up: the old file stays.
    static let decodeBound: TimeInterval = 1

    /// The brightest a colour channel may be in a picture that counts as black.
    static let blackLevel: UInt8 = 24

    /// Whether a decoded picture is black: no pixel with a colour channel brighter than `blackLevel`.
    /// A Mac's screen always has something brighter (the menu bar, a window's text); a decode that came
    /// out black has nothing, and it must never replace a good picture. `pixels`: `height` rows of
    /// `bytesPerRow` bytes, each pixel 4 bytes whose first three are its colour (BGRX or RGBX: the
    /// fourth, alpha or padding, is not looked at), the bytes after `width` pixels in a row padding.
    static func looksBlack(_ pixels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int) -> Bool {
        guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * (height - 1) + width * 4 else { return true }
        for row in 0..<height {
            let start = row * bytesPerRow
            for x in 0..<width {
                let p = start + x * 4
                if pixels[p] > blackLevel || pixels[p + 1] > blackLevel || pixels[p + 2] > blackLevel { return false }
            }
        }
        return true
    }

    /// Whether a picture decoded after its session ended is kept when it lands: only while tiles are
    /// still on (switching to the list deleted every picture meanwhile) and the Mac is still saved
    /// (Forget deleted its picture).
    static func keepsDecodedPicture(style: Style, saved: Bool) -> Bool {
        style == .tiles && saved
    }

    // MARK: A fresh keyframe when Sill ends the session

    /// What Disconnect does before the session ends and its picture is taken (`freshPicture`).
    enum FreshPicture: Equatable {
        /// The picture from the keyframe kept now.
        case stored
        /// Ask the Mac for a keyframe (kind 44) and wait up to `freshKeyframeWait` for it, so the
        /// picture is the last thing on screen: the one kept can be from long before (the encoder
        /// makes one at a new source and every 4 × fps frames it encodes, so none while a window
        /// stays still, and the changes since then, another window brought forward on the Mac, are
        /// in later frames only). Every Mac is asked, as the picture's recovery asks (Noah,
        /// 2026-10-27): one from main on answers within a frame; one from before kind 44 (Sill for
        /// Mac 0.5.1) skips it, and its picture is the keyframe kept, after the wait.
        case ask
        /// A keyframe asked for by the picture's recovery is due (KeyframeRecovery): wait for it,
        /// asking no other, which the Mac would refuse.
        case awaitAsked
    }

    /// How long Disconnect waits for the keyframe it asked for. Then the session ends whatever came: a
    /// Mac that skips the request costs this pause before the connect screen.
    static let freshKeyframeWait: TimeInterval = 0.3

    /// Disconnect's step before the session ends. Only when its end keeps a picture (`takesPreview`)
    /// and something streams (the Mac asks its encoder for nothing then); every Mac is asked, whatever
    /// version it says. `sinceLastAsk`: seconds since the picture's recovery last asked
    /// (KeyframeRecovery), nil for never; `askOut`: that ask still waits for its keyframe. Asks keep the
    /// recovery's spacing (2 s, so the Mac's one a second never refuses one): within it, wait for that
    /// ask's keyframe while it is due, else the keyframe kept is the one it brought.
    static func freshPicture(takesPreview: Bool, streaming: Bool, sinceLastAsk: TimeInterval?, askOut: Bool) -> FreshPicture {
        guard takesPreview, streaming else { return .stored }
        if let since = sinceLastAsk, since < KeyframeRecovery.spacing { return askOut ? .awaitAsked : .stored }
        return .ask
    }

    /// Cleans a group name: whitespace and newlines collapsed to single spaces, at most
    /// `maxGroupLength` characters; a preset's name in any case is the preset ("work" is Work); nil when
    /// blank or Other in any case (where the Macs with no group already are).
    static func cleanGroup(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let name = String(words.joined(separator: " ").prefix(maxGroupLength)).trimmingCharacters(in: .whitespaces)
        if name.caseInsensitiveCompare(otherTitle) == .orderedSame { return nil }
        return presetGroups.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
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

    /// Puts `macID` in `group`, or in none for nil, blank or Other. A name already in use in another
    /// case ("home office" beside "Home Office") is that group, so one name never makes two sections.
    static func settingGroup(_ group: String?, for macID: String, in groups: [String: String]) -> [String: String] {
        guard !macID.isEmpty, macID.count <= 128 else { return groups }
        var next = groups
        if let clean = cleanGroup(group) {
            next[macID] = groups.values.filter { $0.caseInsensitiveCompare(clean) == .orderedSame }.min() ?? clean
        } else {
            next.removeValue(forKey: macID)
        }
        return next
    }

    /// A saved record retired for a newer one of the same Mac (SavedMacs.superseding, a re-pairing that
    /// replaces a record whose Mac has a new key): its group goes to the record that takes its place,
    /// unless that one has a group of its own.
    static func carryingGroup(from old: String, to new: String, in groups: [String: String]) -> [String: String] {
        guard old != new, let group = groups[old] else { return groups }
        var next = groups
        next.removeValue(forKey: old)
        if next[new] == nil { next[new] = group }
        return next
    }

    /// The order groups come in, in the Group menu and as sections, whatever order the Macs are listed
    /// in (so a section never moves as Macs come and go): the presets in their order, then other names
    /// as Finder sorts them.
    static func ordered(_ names: Set<String>) -> [String] {
        presetGroups.filter(names.contains) + names.subtracting(presetGroups).sorted { a, b in
            let order = a.localizedStandardCompare(b)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
    }

    /// The Group menu's names: every preset, then the other names in use.
    static func availableGroups(in groups: [String: String]) -> [String] {
        ordered(Set(presetGroups).union(groups.values.compactMap(cleanGroup)))
    }

    struct Section<Item: Equatable>: Equatable {
        let title: String?
        let items: [Item]
    }

    /// Groups `items` by each item's `macID` in `groups`: the groups in `ordered`'s order, each keeping
    /// the items' own order, then Other for the rest. When no item has a group, a single section with
    /// `title: nil`, so the connect screen has no header and is the flat list it always was.
    static func sections<Item: Equatable>(for items: [Item], macID: (Item) -> String?, groups: [String: String]) -> [Section<Item>] {
        guard !items.isEmpty else { return [] }
        var byGroup: [String: [Item]] = [:]
        var ungrouped: [Item] = []
        for item in items {
            if let id = macID(item), let g = cleanGroup(groups[id]) {
                byGroup[g, default: []].append(item)
            } else {
                ungrouped.append(item)
            }
        }
        guard !byGroup.isEmpty else { return [Section(title: nil, items: items)] }
        var out = ordered(Set(byGroup.keys)).compactMap { name in byGroup[name].map { Section(title: name, items: $0) } }
        if !ungrouped.isEmpty { out.append(Section(title: otherTitle, items: ungrouped)) }
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
