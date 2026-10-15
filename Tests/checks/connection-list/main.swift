// ConnectionList (iOSClient): the connect screen's list vs. tiles style, per-Mac groups and sections,
// preview JPEG filenames and pruning, and tile column count. Compiled with
// iOSClient/ConnectionList.swift alone (run.sh).
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

// Group cleaning and JSON persistence.
check(C.cleanGroup(nil) == nil && C.cleanGroup("   \n\t ") == nil, "blank group is nil")
check(C.cleanGroup("  Work \n Office ") == "Work Office", "whitespace and newlines collapse")
let longGroup = String(repeating: "A", count: 50)
check(C.cleanGroup(longGroup)?.count == C.maxGroupLength, "group name capped at 32 characters")

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
check(C.decodeGroups(#"{"":"Work","M1":"   ","M2":"Lab"}"#) == ["M2": "Lab"], "decode drops empty keys and blank values")

// Available groups: presets in order, plus any custom groups sorted and deduplicated.
check(C.availableGroups(in: [:]) == ["Home", "Work", "Personal"], "presets when no custom groups")
check(C.availableGroups(in: ["M1": "Studio", "M2": "Work", "M3": "Client"]) == ["Home", "Work", "Personal", "Client", "Studio"],
      "custom groups appended sorted without duplicates")

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
    C.Section(title: "Work", items: [rows[0], rows[3]]),
    C.Section(title: "Home", items: [rows[1]]),
    C.Section(title: "Other", items: [rows[2]]),
], "named groups in first-seen order, then Other for ungrouped rows")

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
