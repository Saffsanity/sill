// ConnectionList (iOSClient): the connect screen's list vs. tiles style, when a session's end keeps a
// picture for a tile, per-Mac groups and sections, preview JPEG filenames and pruning, and tile column
// count. Compiled with iOSClient/ConnectionList.swift alone (run.sh).
import Foundation
import CoreGraphics

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
typealias C = ConnectionList

// Style: default is list so existing connect screens are unchanged; only "tiles" switches to tiles.
check(C.storedStyle(nil) == .list && C.storedStyle("") == .list && C.storedStyle("grid") == .list, "default style is list")
check(C.storedStyle("list") == .list && C.storedStyle("tiles") == .tiles, "stored style round-trips")
check(C.Style.list.toggled == .tiles && C.Style.tiles.toggled == .list, "toggling flips between list and tiles")

// A picture at a session's end: only with tiles, from a window in front, for a saved Mac. Every
// combination, so dropping any one condition (or joining them with "or") fails.
for style in C.Style.allCases {
    for sceneActive in [false, true] {
        for saved in [false, true] {
            let want = style == .tiles && sceneActive && saved
            check(C.takesPreview(style: style, sceneActive: sceneActive, saved: saved) == want,
                  "picture kept: \(style), window in front \(sceneActive), saved \(saved) → \(want)")
        }
    }
}

// Group cleaning and JSON persistence.
check(C.cleanGroup(nil) == nil && C.cleanGroup("   \n\t ") == nil, "blank group is nil")
check(C.cleanGroup("  Work \n Office ") == "Work Office", "whitespace and newlines collapse")
let longGroup = String(repeating: "A", count: 50)
check(C.cleanGroup(longGroup)?.count == C.maxGroupLength, "group name capped at 32 characters")
let cutAtSpace = String(repeating: "B", count: 31) + " tail"
check(C.cleanGroup(cutAtSpace) == String(repeating: "B", count: 31), "a name cut at the cap ends without a space")
check(C.cleanGroup("Other") == nil && C.cleanGroup(" other ") == nil && C.cleanGroup("OTHER") == nil,
      "Other in any case is no group: the Macs with no group are already under Other")
check(C.cleanGroup("Others") == "Others" && C.cleanGroup("Other Macs") == "Other Macs", "only Other itself is reserved")
check(C.cleanGroup("home") == "Home" && C.cleanGroup("WORK") == "Work" && C.cleanGroup(" personal ") == "Personal",
      "a preset's name in any case is the preset")

var groups = C.decodeGroups(nil)
check(groups.isEmpty, "nil JSON decodes empty")
check(C.decodeGroups("not json").isEmpty, "invalid JSON decodes empty")
groups = C.settingGroup("Work", for: "M1", in: groups)
groups = C.settingGroup("  Home ", for: "M2", in: groups)
check(groups == ["M1": "Work", "M2": "Home"], "setting groups stores cleaned names")
let encoded = C.encodeGroups(groups)
check(C.decodeGroups(encoded) == groups, "encode/decode round-trips")
groups = C.settingGroup("   ", for: "M1", in: groups)
check(groups == ["M2": "Home"], "blank group removes the Mac's group")
check(C.settingGroup("other", for: "M2", in: groups).isEmpty, "Other removes the Mac's group")
check(C.decodeGroups(#"{"":"Work","M1":"   ","M2":"Lab","M3":"Other"}"#) == ["M2": "Lab"], "decode drops empty keys, blank values and Other")
check(C.settingGroup("home office", for: "M3", in: ["M1": "Home Office"]) == ["M1": "Home Office", "M3": "Home Office"],
      "a name in use in another case joins that group")
check(C.settingGroup("Lab", for: "M3", in: ["M1": "Studio"]) == ["M1": "Studio", "M3": "Lab"], "a new name makes a new group")

// A retired record's group goes to the one that takes its place, unless that one has its own.
check(C.carryingGroup(from: "OLD", to: "NEW", in: ["OLD": "Work", "M1": "Home"]) == ["NEW": "Work", "M1": "Home"],
      "a superseded record's group goes to its successor")
check(C.carryingGroup(from: "OLD", to: "NEW", in: ["OLD": "Work", "NEW": "Lab"]) == ["NEW": "Lab"],
      "a successor keeps a group of its own")
check(C.carryingGroup(from: "OLD", to: "NEW", in: ["M1": "Home"]) == ["M1": "Home"], "no group to carry: nothing changes")
check(C.carryingGroup(from: "M1", to: "M1", in: ["M1": "Home"]) == ["M1": "Home"], "a record that supersedes itself keeps its group")

// Available groups: presets in order, plus any custom groups sorted (as Finder sorts) and deduplicated.
check(C.availableGroups(in: [:]) == ["Home", "Work", "Personal"], "presets when no custom groups")
check(C.availableGroups(in: ["M1": "Studio", "M2": "Work", "M3": "Client"]) == ["Home", "Work", "Personal", "Client", "Studio"],
      "custom groups appended sorted without duplicates")
check(C.availableGroups(in: ["M1": "lab", "M2": "Attic", "M3": "Room 10", "M4": "Room 9"])
      == ["Home", "Work", "Personal", "Attic", "lab", "Room 9", "Room 10"], "custom groups sorted as Finder sorts them")

// Sections: when no row is grouped, a single unnamed section preserves the exact flat list.
struct Row: Equatable { let name: String; let macID: String? }
let rows = [Row(name: "A", macID: "M1"), Row(name: "B", macID: "M2"), Row(name: "C", macID: nil), Row(name: "D", macID: "M3")]
check(C.sections(for: [Row](), macID: \.macID, groups: ["M1": "Work"]).isEmpty, "no rows: no sections")
check(C.sections(for: rows, macID: \.macID, groups: [:]) == [C.Section(title: nil, items: rows)],
      "no groups assigned: one unnamed section with all rows")
check(C.sections(for: rows, macID: \.macID, groups: ["OTHER": "Work"]) == [C.Section(title: nil, items: rows)],
      "groups for unlisted Macs only: still one unnamed section")

let grouped = C.sections(for: rows, macID: \.macID, groups: ["M1": "Work", "M3": "Work", "M2": "Home"])
check(grouped == [
    C.Section(title: "Home", items: [rows[1]]),
    C.Section(title: "Work", items: [rows[0], rows[3]]),
    C.Section(title: "Other", items: [rows[2]]),
], "presets in their order whatever order the rows come in, each keeping the rows' order, then Other")
let customs = C.sections(for: rows, macID: \.macID, groups: ["M1": "Studio", "M2": "Client", "M3": "Personal"])
check(customs.map(\.title) == ["Personal", "Client", "Studio", "Other"], "presets, then other names sorted, then Other")
check(C.sections(for: Array(rows.reversed()), macID: \.macID, groups: ["M1": "Studio", "M2": "Client", "M3": "Personal"]).map(\.title)
      == ["Personal", "Client", "Studio", "Other"], "the sections' order does not follow the rows' order")

let allGrouped = C.sections(for: [rows[0], rows[1]], macID: \.macID, groups: ["M1": "Home", "M2": "Home"])
check(allGrouped == [C.Section(title: "Home", items: [rows[0], rows[1]])], "no Other section when every row has a group")

// Preview filenames and pruning: path traversal refused, stale files listed.
check(C.previewFileName(for: "041061050R3GG28A") == "041061050R3GG28A.jpg", "valid Mac ID gives .jpg filename")
check(C.previewFileName(for: "") == nil && C.previewFileName(for: "../secret") == nil && C.previewFileName(for: "a/b") == nil
      && C.previewFileName(for: ".hidden") == nil && C.previewFileName(for: String(repeating: "A", count: 129)) == nil,
      "empty, traversal, slash, dot or oversized Mac IDs refused")
let files = ["M1.jpg", "M2.jpg", "notes.txt", "M3.jpg"]
check(C.stalePreviewFiles(in: files, keepingMacIDs: ["M1", "M3"]) == ["M2.jpg"], "only stale .jpg files are pruned")

// Tile columns: 2 columns at >= 340 pt, 1 column on narrower widths or at accessibility text sizes.
check(C.columns(forWidth: 380, accessibleText: false) == 2 && C.columns(forWidth: 340, accessibleText: false) == 2,
      "340 pt and wider: 2 tile columns")
check(C.columns(forWidth: 339, accessibleText: false) == 1 && C.columns(forWidth: 380, accessibleText: true) == 1,
      "narrower than 340 pt or accessibility text size: 1 tile column")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
