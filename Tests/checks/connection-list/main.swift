// ConnectionList (iOSClient): the connect screen's list vs. tiles style, when a session's end keeps a
// picture for a tile, the picture's size and its black test, when a decoded picture lands, when
// Disconnect asks the Mac for a fresh keyframe first, per-Mac groups and sections, preview JPEG
// filenames and pruning, and tile column count. Compiled with iOSClient/ConnectionList.swift and
// iOSClient/KeyframeRecovery.swift (its spacing) (run.sh).
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

// A style never deletes a picture (Noah, 2026-10-27): the list hides the kept pictures and keeps their
// files, tiles show them again at once; only the files of Macs no longer saved go, at a launch or a
// change of style in either style. The round trip, step by step, as StreamClient.syncPreviews applies it.
typealias Plan = C.PreviewPlan
func applying(_ plan: Plan, to files: [String]) -> [String] { files.filter { !plan.delete.contains($0) } }
let saved: Set<String> = ["M1", "M2"]
let onDisk = ["M1.jpg", "M2.jpg", "GONE.jpg", "notes.txt"]
let tilesLaunch = C.previewPlan(style: .tiles, files: onDisk, savedMacIDs: saved)
check(tilesLaunch == Plan(delete: ["GONE.jpg"], show: ["M1", "M2"]),
      "a tiles launch shows every saved Mac's picture and deletes only the picture of a Mac no longer saved")
var kept = applying(tilesLaunch, to: onDisk)
let toList = C.previewPlan(style: .list, files: kept, savedMacIDs: saved)
check(toList == Plan(delete: [], show: []), "switched to the list: no picture shows, and no file is deleted")
kept = applying(toList, to: kept)
check(kept == ["M1.jpg", "M2.jpg", "notes.txt"], "after the switch to the list every saved Mac's picture is still on the device")
let backToTiles = C.previewPlan(style: .tiles, files: kept, savedMacIDs: saved)
check(backToTiles == Plan(delete: [], show: ["M1", "M2"]), "switched back to tiles: every kept picture shows again at once")
check(C.previewPlan(style: .list, files: onDisk, savedMacIDs: saved) == Plan(delete: ["GONE.jpg"], show: []),
      "a launch with the list hides the pictures, keeps the saved Macs' files and deletes a Mac no longer saved's")
check(C.previewPlan(style: .tiles, files: ["M2.jpg"], savedMacIDs: saved) == Plan(delete: [], show: ["M2"]),
      "a picture removed (Remove Preview Picture) does not come back; the others show")
check(C.previewPlan(style: .tiles, files: ["M1.jpg", "M2.jpg"], savedMacIDs: ["M1"]) == Plan(delete: ["M2.jpg"], show: ["M1"]),
      "a Mac forgotten since: its picture is deleted and not shown")
check(C.previewPlan(style: .tiles, files: ["M1.png", "M1.jpg.jpg", ".jpg", "M2.jpg"], savedMacIDs: ["M1", "M2"])
      == Plan(delete: ["M1.jpg.jpg", ".jpg"], show: ["M2"]),
      "only a saved Mac's own .jpg shows; other names never show, and stale .jpg names go")
check(C.previewPlan(style: .tiles, files: [], savedMacIDs: saved) == Plan(delete: [], show: []), "no files: nothing to show or delete")
check(C.previewPlan(style: .tiles, files: ["M2.jpg", "M1.jpg"], savedMacIDs: saved).show == ["M1", "M2"], "the shown Macs in order")

// Every row of one Mac shows that Mac's one picture, whatever way it reaches the Mac (Noah, 2026-10-27):
// a network row whose tag names the saved Mac, a row taken for it by its Bonjour name alone, its Remote
// row. Another Mac's rows show its own; a row of no saved Mac shows the placeholder.
struct Tile: Equatable { let word: String; let macID: String?; let savedByName: String? }
let pictures = ["M1": "M1's picture", "M2": "M2's picture"]
func picture(_ t: Tile) -> String? { C.tileMac(macID: t.macID, savedByName: t.savedByName).flatMap { pictures[$0] } }
let m1Wired = Tile(word: "Wired", macID: "M1", savedByName: nil)            // its tag names M1
let m1WiFiByName = Tile(word: "Wi-Fi", macID: nil, savedByName: "M1")       // no tag, M1's Bonjour name
let m1Remote = Tile(word: "Remote", macID: "M1", savedByName: nil)          // its saved record
let m2Remote = Tile(word: "Remote", macID: "M2", savedByName: nil)
let stranger = Tile(word: "Not paired", macID: nil, savedByName: nil)
check([m1Wired, m1WiFiByName, m1Remote].map(picture) == ["M1's picture", "M1's picture", "M1's picture"],
      "one Mac listed as Wired, Wi-Fi and Remote at once: every tile shows its one picture")
check(picture(m2Remote) == "M2's picture" && picture(m1Remote) == "M1's picture", "two Macs: each shows its own picture")
check(C.tileMac(macID: nil, savedByName: nil) == nil && picture(stranger) == nil, "a row of no saved Mac: the placeholder")
check(C.tileMac(macID: nil, savedByName: "M1") == "M1", "a row taken for the saved Mac by its name alone stands for that Mac")
check(C.tileMac(macID: "M1", savedByName: "M2") == "M1", "a row's tag names its Mac before any name does")
check(picture(Tile(word: "Wired", macID: "M3", savedByName: nil)) == nil, "a saved Mac with no picture kept: the placeholder")
let tileSections = C.sections(for: [m1Wired, m1WiFiByName, stranger, m1Remote, m2Remote],
                              macID: { C.tileMac(macID: $0.macID, savedByName: $0.savedByName) }, groups: ["M1": "Home", "M2": "Work"])
check(tileSections == [C.Section(title: "Home", items: [m1Wired, m1WiFiByName, m1Remote]),
                       C.Section(title: "Work", items: [m2Remote]), C.Section(title: "Other", items: [stranger])],
      "every row of one Mac is listed under its group, the row taken by its name too")

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

// The picture's size: the stream's last keyframe decoded at most 320 pt wide at 2x (640 pixels), in
// the video's shape, never wider than the video, the height rounded down and at least a pixel.
func pixels(_ w: CGFloat, _ h: CGFloat) -> String {
    C.previewPixels(video: CGSize(width: w, height: h)).map { "\($0.width)x\($0.height)" } ?? "nil"
}
check(pixels(3024, 1964) == "640x415", "a Retina Desktop's keyframe makes a 640×415 picture (415.66 rounded down)")
check(pixels(1920, 1080) == "640x360" && pixels(6016, 3384) == "640x360", "16:9 at any size: 640×360")
check(pixels(1512, 982) == "640x415", "a Standard Desktop's: 640×415")
check(pixels(640, 400) == "640x400" && pixels(641, 401) == "640x400", "640 wide is kept; 641×401 is 640×400")
check(pixels(500, 300) == "500x300" && pixels(1, 1) == "1x1", "a video narrower than 640 pixels keeps its own size")
check(pixels(1080, 1920) == "640x1137", "a display turned upright: 640 wide, as tall as its shape makes it")
check(pixels(7680, 1) == "640x1", "a picture is at least a pixel tall")
check(C.previewPoints * C.previewScale == 640, "320 pt at 2x")
check(pixels(0, 100) == "nil" && pixels(100, 0) == "nil" && pixels(-5, 10) == "nil" && pixels(0.5, 10) == "nil"
      && pixels(.infinity, 10) == "nil" && pixels(10, .nan) == "nil", "no video, no picture")

// The black test: no colour channel brighter than 24 anywhere is black; the fourth byte (alpha or
// padding) and the row's padding are never looked at.
func buffer(_ w: Int, _ h: Int, rowBytes: Int? = nil, fill: UInt8 = 0, alpha: UInt8 = 0, padding: UInt8 = 0,
            set: [(x: Int, y: Int, channel: Int, value: UInt8)] = []) -> (bytes: [UInt8], rowBytes: Int) {
    let row = rowBytes ?? w * 4
    var bytes = [UInt8](repeating: padding, count: row * h)
    for y in 0..<h { for x in 0..<w { for c in 0..<4 { bytes[y * row + x * 4 + c] = c == 3 ? alpha : fill } } }
    for p in set { bytes[p.y * row + p.x * 4 + p.channel] = p.value }
    return (bytes, row)
}
func black(_ b: (bytes: [UInt8], rowBytes: Int), _ w: Int, _ h: Int) -> Bool {
    b.bytes.withUnsafeBytes { C.looksBlack($0, width: w, height: h, bytesPerRow: b.rowBytes) }
}
check(black(buffer(8, 5), 8, 5), "every pixel 0: black")
check(!black(buffer(8, 5, fill: 96), 8, 5), "the test pattern's grey 96: not black")
check(black(buffer(8, 5, fill: 24), 8, 5) && !black(buffer(8, 5, fill: 25), 8, 5), "24 is black, 25 is not")
check(!black(buffer(8, 5, set: [(7, 4, 0, 200)]), 8, 5), "one bright pixel, the last of the last row: not black")
check(!black(buffer(8, 5, set: [(0, 0, 1, 200)]), 8, 5) && !black(buffer(8, 5, set: [(3, 2, 2, 200)]), 8, 5),
      "a bright second or third colour channel: not black")
check(black(buffer(8, 5, alpha: 255), 8, 5), "the fourth byte (alpha or padding) bright: still black")
check(black(buffer(8, 5, rowBytes: 48, padding: 255), 8, 5), "rows padded with bright bytes: the padding is not the picture")
check(!black(buffer(8, 5, rowBytes: 48, padding: 255, set: [(7, 4, 2, 90)]), 8, 5), "a padded picture's last pixel bright: not black")
let tiny = buffer(8, 5, fill: 96)
check(tiny.bytes.withUnsafeBytes { C.looksBlack($0, width: 0, height: 5, bytesPerRow: 32) }
      && tiny.bytes.withUnsafeBytes { C.looksBlack($0, width: 8, height: 0, bytesPerRow: 32) }
      && tiny.bytes.withUnsafeBytes { C.looksBlack($0, width: 8, height: 5, bytesPerRow: 16) }
      && tiny.bytes.withUnsafeBytes { C.looksBlack($0, width: 8, height: 6, bytesPerRow: 32) },
      "no pixels, rows shorter than their pixels, or fewer bytes than the rows: no picture, black")
check(!tiny.bytes.withUnsafeBytes { C.looksBlack($0, width: 8, height: 5, bytesPerRow: 32) },
      "the same bytes read whole: a picture")

// A picture decoded after its session ended lands only while tiles are still on and the Mac still saved.
for style in C.Style.allCases {
    for saved in [false, true] {
        let want = style == .tiles && saved
        check(C.keepsDecodedPicture(style: style, saved: saved) == want, "a decoded picture kept: \(style), saved \(saved) → \(want)")
    }
}
check(C.decodeBound == 1, "a decode is given up after 1 s")

// Disconnect's fresh keyframe: asked of every Mac (Noah, 2026-10-27: one from main on answers within a
// frame, one from before kind 44 skips it and costs the 300 ms wait), only when the session's end keeps
// a picture and something streams; within the picture's recovery's spacing (2 s) of its last ask, no
// other ask: wait for its keyframe while that is due, else the keyframe kept is the one it brought.
typealias F = C.FreshPicture
check(KeyframeRecovery.spacing == 2, "the recovery's spacing is 2 s")
for takes in [false, true] {
    for streaming in [false, true] {
        for since in [nil, 0, 0.5, 1.5, 1.99, 2, 2.01, 30] as [TimeInterval?] {
            for out in [false, true] {
                let got = C.freshPicture(takesPreview: takes, streaming: streaming, sinceLastAsk: since, askOut: out)
                let want: F
                if !(takes && streaming) { want = .stored }
                else if let since, since < 2 { want = out ? .awaitAsked : .stored }
                else { want = .ask }
                check(got == want, "fresh keyframe: picture \(takes), streaming \(streaming), "
                      + "last ask \(since.map { "\($0) s ago" } ?? "never")\(out ? ", out" : "") → \(want)")
            }
        }
    }
}
check(C.freshPicture(takesPreview: true, streaming: true, sinceLastAsk: nil, askOut: false) == .ask,
      "every Mac is asked: a session's end that keeps a picture, something streaming, no recent ask")
check(C.freshKeyframeWait == 0.3, "Disconnect waits 300 ms at most for the keyframe")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
