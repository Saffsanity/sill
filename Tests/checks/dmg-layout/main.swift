// Scripts/dmg-layout's writer on its own: DSStore.swift, FinderAlias.swift and DMGLayout.swift, the
// code that lays out Sill.dmg's Finder window for Scripts/make-dmg.sh, compiled with this file. No
// disk image is made. The .DS_Store of that window is read back byte by byte with a reader of this
// file's own (not DSStore.decode) and held to Finder's own layout of such a file (the blocks, the
// free lists and the header bytes of a Finder-made image's .DS_Store), then what its property lists
// hold and the icons' places; the background's alias field by field; the encoder and the decoder
// against each other; the volume icon's flag; and that make-dmg.sh and design/DMGBackground.svg
// still give the window checked here.
//   swiftc -O Scripts/dmg-layout/DSStore.swift Scripts/dmg-layout/FinderAlias.swift Scripts/dmg-layout/DMGLayout.swift Tests/checks/dmg-layout/main.swift -o .build/checks/dmg-layout/check
//   .build/checks/dmg-layout/check .build/checks/dmg-layout .build/checks/dmg-layout/layout.txt design/DMGBackground.svg
// run.sh does both, after writing layout.txt: make-dmg.sh's layout arguments, one per line.
import Foundation

var passes = 0, fails = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passes += 1; print("ok  ", name) } else { fails += 1; print("FAIL", name, detail()) }
}
func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 { bytes.map { String(format: "%02x", $0) }.joined() }
func words(_ values: [UInt32]) -> [UInt8] { values.flatMap { [UInt8($0 >> 24), UInt8($0 >> 16 & 0xff), UInt8($0 >> 8 & 0xff), UInt8($0 & 0xff)] } }
func long(_ value: UInt64) -> [UInt8] { words([UInt32(value >> 32), UInt32(value & 0xffff_ffff)]) }
func utf16BE(_ string: String) -> [UInt8] { string.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] } }
/// Where two byte strings first differ, for a failure's message.
func difference(_ have: [UInt8], _ want: [UInt8]) -> String {
    let at = zip(have, want).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(have.count, want.count)
    return "(\(have.count) bytes, \(want.count) wanted; first difference at \(at): "
        + "\(hex(have.dropFirst(at).prefix(12))) against \(hex(want.dropFirst(at).prefix(12))))"
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: check OUT LAYOUT.txt DMGBackground.svg (Tests/checks/dmg-layout/run.sh runs it)")
    exit(2)
}
let out = arguments[1], layoutFile = arguments[2], svgFile = arguments[3]

/// Big-endian reads that never trap: a read past the end gives nil, which fails its check.
struct Bytes {
    let b: [UInt8]
    init(_ data: Data) { b = [UInt8](data) }
    var count: Int { b.count }
    func slice(_ at: Int, _ n: Int) -> [UInt8]? { at >= 0 && n >= 0 && at + n <= b.count ? Array(b[at..<(at + n)]) : nil }
    func word(_ at: Int) -> UInt32? { slice(at, 4).map { $0.reduce(0) { $0 << 8 | UInt32($1) } } }
    func zero(_ from: Int, _ to: Int) -> Bool { from >= 0 && from <= to && to <= b.count && b[from..<to].allSatisfy { $0 == 0 } }
}

/// A record as the file has it: its value's bytes as they are, a blob's with its length first.
struct Rec { var name: String, code: String, type: String, value: [UInt8] }

/// The records of one node, read the way DSStoreFormat.pod describes them, and where they end.
func parseRecords(_ f: Bytes, from start: Int, count: Int) -> (records: [Rec], end: Int)? {
    var p = start, records: [Rec] = []
    for _ in 0..<count {
        guard let n = f.word(p).map(Int.init), let units = f.slice(p + 4, 2 * n) else { return nil }
        let name = String(decoding: stride(from: 0, to: units.count, by: 2).map { UInt16(units[$0]) << 8 | UInt16(units[$0 + 1]) }, as: UTF16.self)
        p += 4 + 2 * n
        guard let code = f.slice(p, 4), let type = f.slice(p + 4, 4) else { return nil }
        p += 8
        let typeName = String(decoding: type, as: UTF8.self), length: Int
        switch typeName {
        case "long", "shor", "type": length = 4
        case "bool": length = 1
        case "comp", "dutc": length = 8
        case "blob": guard let l = f.word(p) else { return nil }; length = 4 + Int(l)
        case "ustr": guard let l = f.word(p) else { return nil }; length = 4 + 2 * Int(l)
        default: return nil
        }
        guard let value = f.slice(p, length) else { return nil }
        records.append(Rec(name: name, code: String(decoding: code, as: UTF8.self), type: typeName, value: value))
        p += length
    }
    return (records, p)
}

/// A property list's values as "key: type value" lines, sorted by key: the type as the file has it
/// (a bool, an integer or a real are three things to Finder).
func plistLines(_ blob: Data) -> [String] {
    guard blob.starts(with: Array("bplist00".utf8)) else { return ["(not a binary property list)"] }
    guard let dictionary = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any] else {
        return ["(not a dictionary)"]
    }
    func describe(_ value: Any) -> String {
        let object = value as AnyObject
        if CFGetTypeID(object) == CFBooleanGetTypeID() { return "bool \((object as! NSNumber).boolValue)" }
        if let number = object as? NSNumber { return CFNumberIsFloatType(number as CFNumber) ? "real \(number.doubleValue)" : "int \(number.int64Value)" }
        if let string = object as? String { return "string \(string)" }
        if let data = object as? Data { return "data \(hex(data))" }
        return "other \(object)"
    }
    return dictionary.keys.sorted().map { "\($0): \(describe(dictionary[$0]!))" }
}
func plistLines(_ record: Rec?) -> [String] {
    guard let record = record, record.type == "blob", record.value.count >= 4 else { return ["(no blob)"] }
    return plistLines(Data(record.value.dropFirst(4)))
}
func plistLines(_ record: DSRecord?) -> [String] {
    guard let record = record, case .blob(let data) = record.value else { return ["(no blob)"] }
    return plistLines(data)
}

// MARK: The window make-dmg.sh lays out, and the picture it lays it out on

let release = DMGLayout(width: 660, height: 400, left: 200, top: 120, iconSize: 128, textSize: 12,
                        background: ".background/background.tiff", backgroundColor: (255, 255, 255),
                        items: [.init(name: "Sill.app", x: 170, y: 180), .init(name: "Applications", x: 490, y: 180)],
                        hidden: [".background", ".VolumeIcon.icns"])
let releaseArguments = ["--window", "660x400", "--position", "200,120", "--icon-size", "128", "--text-size", "12",
                        "--background", ".background/background.tiff", "--background-color", "ffffff",
                        "--item", "Sill.app=170,180", "--item", "Applications=490,180",
                        "--hidden", ".background", "--hidden", ".VolumeIcon.icns"]
let fromScript = ((try? String(contentsOfFile: layoutFile, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
check("make-dmg.sh: its layout is the one checked here", fromScript == releaseArguments,
      "(make-dmg.sh gives \(fromScript): move this check's release layout and its expectations with it)")

let svg = (try? String(contentsOfFile: svgFile, encoding: .utf8)) ?? ""
func svgMatch(_ pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)) else { return nil }
    return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: svg).map { String(svg[$0]) } }
}
check("DMGBackground.svg: 660 x 400 points, the window's content",
      svgMatch(#"<svg[^>]*\swidth="(\d+)"\s+height="(\d+)"\s+viewBox="0 0 (\d+) (\d+)""#) == ["660", "400", "660", "400"],
      "(\(svgMatch(#"(<svg[^>]*>)"#) ?? []))")
check("DMGBackground.svg: its first shape fills the picture with white, the window's backgroundColor, to every edge",
      svgMatch(##"<rect x="0" y="0" width="660" height="400" fill="#([0-9a-fA-F]{6})""##)?.first?.lowercased() == "ffffff")

// MARK: The background's alias, field by field

let utc = TimeZone(identifier: "UTC")!
let toHFS: Int64 = 2_082_844_800                                   // 1904-01-01 to 1970-01-01, in seconds
let volumeCreated = Date(timeIntervalSince1970: 1_790_000_000)     // September 2026
let fileCreated = Date(timeIntervalSince1970: 1_790_000_061.75)    // a fraction: whole seconds kept
let volumeSeconds = 1_790_000_000 + toHFS, fileSeconds = 1_790_000_061 + toHFS
let alias = FinderAlias(volumeName: "Sill", volumeCreated: volumeCreated, parentID: 30, parentName: ".background",
                        fileID: 31, fileName: "background.tiff", fileCreated: fileCreated, folderIDs: [30],
                        path: "/.background/background.tiff", mountPoint: "/Volumes/Sill")

func pascal(_ string: String, _ size: Int) -> [UInt8] {
    let bytes = Array(string.utf8)
    return [UInt8(bytes.count)] + bytes + [UInt8](repeating: 0, count: size - 1 - bytes.count)
}
/// The record as Finder writes it for a file on a disk image's HFS+ volume (FinderAlias.swift's
/// header has the table): the fixed part, then each tag's number, length, value and a pad byte to
/// an even length, then tag -1.
func aliasBytes(volume: String, volumeDate: Int64, parentID: UInt32, file: String, fileID: UInt32, fileDate: Int64,
                tags: [(Int16, [UInt8])]) -> [UInt8] {
    var r: [UInt8] = [0, 0, 0, 0] + [0, 0] + [0, 2] + [0, 0]           // application info, length, version 2, a file
    r += pascal(volume, 28) + words([UInt32(volumeDate)]) + Array("H+".utf8) + [0, 5]
    r += words([parentID]) + pascal(file, 64) + words([fileID, UInt32(fileDate)])
    r += [UInt8](repeating: 0, count: 8) + [0xff, 0xff, 0xff, 0xff] + words([0x0d02]) + [UInt8](repeating: 0, count: 12)
    for (number, value) in tags {
        let n = UInt16(bitPattern: number)
        r += [UInt8(n >> 8), UInt8(n & 0xff), UInt8(value.count >> 8), UInt8(value.count & 0xff)] + value
        if value.count % 2 == 1 { r.append(0) }
    }
    r += [0xff, 0xff, 0, 0]
    r[4] = UInt8(r.count >> 8); r[5] = UInt8(r.count & 0xff)
    return r
}
func releaseTags() -> [(Int16, [UInt8])] {
    [(0, Array(".background".utf8)), (16, long(UInt64(volumeSeconds) << 16)), (17, long(UInt64(fileSeconds) << 16)),
     (1, words([30])), (2, Array("Sill:.background:\u{0}background.tiff".utf8)),
     (14, [0, 15] + utf16BE("background.tiff")), (15, [0, 4] + utf16BE("Sill")),
     (18, Array("/.background/background.tiff".utf8)), (19, Array("/Volumes/Sill".utf8))]
}
let wantUTC = aliasBytes(volume: "Sill", volumeDate: volumeSeconds, parentID: 30, file: "background.tiff", fileID: 31,
                         fileDate: fileSeconds, tags: releaseTags())
let aliasUTC = (try? alias.encoded(timeZone: utc)) ?? Data()
check("alias: the background's record as Finder writes it, byte for byte (the 4-byte dates in UTC)",
      [UInt8](aliasUTC) == wantUTC, difference([UInt8](aliasUTC), wantUTC))
// HFS+ keeps a volume's dates in local time: the Mac that makes the image puts its own offset in
// the two 4-byte dates, and nothing else changes (tags 16 and 17 stay UTC).
let eastern = TimeZone(secondsFromGMT: -4 * 3600)!
let wantEastern = aliasBytes(volume: "Sill", volumeDate: volumeSeconds - 14_400, parentID: 30, file: "background.tiff",
                             fileID: 31, fileDate: fileSeconds - 14_400, tags: releaseTags())
let aliasEastern = (try? alias.encoded(timeZone: eastern)) ?? Data()
check("alias: 4 hours west of UTC, the two 4-byte dates 14,400 s earlier and nothing else",
      [UInt8](aliasEastern) == wantEastern, difference([UInt8](aliasEastern), wantEastern))

if let fields = try? FinderAlias.fields(of: aliasUTC) {
    check("alias: fields(of:) reads its length, version and kind", fields.length == wantUTC.count && fields.version == 2 && fields.kind == 0)
    check("alias: fields(of:) reads the volume: Sill, its date, H+, an ejectable disk",
          fields.volumeName == "Sill" && fields.volumeDate == UInt32(volumeSeconds) && fields.fileSystem == "H+" && fields.diskType == 5)
    check("alias: fields(of:) reads the file: its folder 30, background.tiff, ID 31, its date",
          fields.parentID == 30 && fields.fileName == "background.tiff" && fields.fileID == 31 && fields.fileDate == UInt32(fileSeconds))
    check("alias: fields(of:) reads levels -1 and -1 and the attributes 0x0d02",
          fields.levelsFrom == -1 && fields.levelsTo == -1 && fields.volumeAttributes == 0x0d02)
    check("alias: the tags Finder writes, in its order (0, 16, 17, 1, 2, 14, 15, 18, 19)",
          fields.tagOrder == [0, 16, 17, 1, 2, 14, 15, 18, 19], "(\(fields.tagOrder))")
    check("alias: fields(of:) reads each tag's value", releaseTags().allSatisfy { fields.tagValues[$0.0].map([UInt8].init) == $0.1 })
} else {
    check("alias: fields(of:) reads the record back", false)
}
check("alias: fields(of:) refuses a record cut short", (try? FinderAlias.fields(of: aliasUTC.prefix(aliasUTC.count - 2))) == nil)
check("alias: fields(of:) refuses a record shorter than its fixed part", (try? FinderAlias.fields(of: aliasUTC.prefix(149))) == nil)
check("alias: fields(of:) refuses a byte past its end", (try? FinderAlias.fields(of: aliasUTC + Data([0]))) == nil)
var misnamed = aliasUTC; misnamed[5] &+= 2
check("alias: fields(of:) refuses a length that isn't the record's", (try? FinderAlias.fields(of: misnamed)) == nil)

// Names with a colon: the Pascal strings and the Carbon path (tag 2) write it as "/", as the Carbon
// path does; the UTF-16 names and the POSIX paths keep it.
let colon = FinderAlias(volumeName: "Si:ll", volumeCreated: volumeCreated, parentID: 7, parentName: "x:y", fileID: 8,
                        fileName: "f:g.tiff", fileCreated: fileCreated, folderIDs: [7], path: "/x:y/f:g.tiff",
                        mountPoint: "/Volumes/Si:ll")
let wantColon = aliasBytes(volume: "Si/ll", volumeDate: volumeSeconds, parentID: 7, file: "f/g.tiff", fileID: 8, fileDate: fileSeconds,
                           tags: [(0, Array("x/y".utf8)), (16, long(UInt64(volumeSeconds) << 16)), (17, long(UInt64(fileSeconds) << 16)),
                                  (1, words([7])), (2, Array("Si/ll:x/y:\u{0}f/g.tiff".utf8)),
                                  (14, [0, 8] + utf16BE("f:g.tiff")), (15, [0, 5] + utf16BE("Si:ll")),
                                  (18, Array("/x:y/f:g.tiff".utf8)), (19, Array("/Volumes/Si:ll".utf8))])
let aliasColon = (try? colon.encoded(timeZone: utc)).map { [UInt8]($0) } ?? []
check("alias: a colon is \"/\" in the Pascal names and tags 0 and 2, itself elsewhere", aliasColon == wantColon, difference(aliasColon, wantColon))

func encodes(_ change: (inout FinderAlias) -> Void) -> Bool {
    var a = alias
    change(&a)
    return (try? a.encoded(timeZone: utc)) != nil
}
check("alias: a volume name of 27 characters fits, 28 doesn't",
      encodes { $0.volumeName = String(repeating: "v", count: 27) } && !encodes { $0.volumeName = String(repeating: "v", count: 28) })
check("alias: a file name of 63 characters fits, 64 doesn't",
      encodes { $0.fileName = String(repeating: "f", count: 63) } && !encodes { $0.fileName = String(repeating: "f", count: 64) })
check("alias: names must be ASCII", !encodes { $0.volumeName = "Sillé" } && !encodes { $0.fileName = "hintergrund‑bild.tiff" })
check("alias: a date before 1904 is refused", !encodes { $0.volumeCreated = Date(timeIntervalSince1970: -2_100_000_000) })

// MARK: The .DS_Store, byte by byte

let releaseRecords = (try? release.records(backgroundAlias: aliasUTC)) ?? []
let fileData = (try? DSStore.encode(releaseRecords)) ?? Data()
let f = Bytes(fileData)
check("file: 10,244 bytes, as Finder's own for a folder with a few records", f.count == 10_244, "(\(f.count))")
guard f.count == 10_244 else {
    print("\(passes) passed, \(fails) failed (the rest needs the file)")
    exit(1)
}
check("file: the word 1, then the allocator's header \"Bud1\"", f.word(0) == 1 && f.slice(4, 4) == Array("Bud1".utf8))
check("header: the root block's address 0x2000 and size 0x800, and the address again",
      f.word(8) == 0x2000 && f.word(12) == 0x800 && f.word(16) == 0x2000)
check("header: then 00 00 10 0c and twelve zero bytes, as Finder writes them",
      f.slice(20, 16) == [0, 0, 0x10, 0x0c] + [UInt8](repeating: 0, count: 12), "(\(hex(f.slice(20, 16) ?? [])))")
// Addresses count from byte 4: the block at address A starts at byte 4 + A.
let root = 4 + 0x2000
check("root block: three blocks", f.word(root) == 3 && f.word(root + 4) == 0)
let offsets = (0..<256).map { f.word(root + 8 + 4 * $0) ?? 0xffff_ffff }
check("root block: block 0 itself (0x2000, 2^11 bytes), 1 DSDB (0x40, 2^5), 2 the leaf (0x1000, 2^12), then 253 zero words",
      offsets == [0x200b, 0x45, 0x100c] + [UInt32](repeating: 0, count: 253), "(\(offsets.prefix(4).map { String($0, radix: 16) }))")
var p = root + 8 + 1024
check("root block: its table of contents names one block, 1, \"DSDB\"",
      f.word(p) == 1 && f.slice(p + 4, 1) == [4] && f.slice(p + 5, 4) == Array("DSDB".utf8) && f.word(p + 9) == 1)
p += 13
// A Finder-made image's .DS_Store (an installer image of 2023) has exactly these free lists: for
// each size 2^0 to 2^31, the free blocks around the four that are allocated.
var finderFree = [[UInt32]](repeating: [], count: 32)
finderFree[5] = [0x20, 0x60]; finderFree[7] = [0x80]; finderFree[8] = [0x100]; finderFree[9] = [0x200]
finderFree[10] = [0x400]; finderFree[11] = [0x800, 0x2800]; finderFree[12] = [0x3000]
for width in 14...30 { finderFree[width] = [UInt32(1) << UInt32(width)] }
var freeRead: [[UInt32]] = []
for _ in 0..<32 {
    let n = min(Int(f.word(p) ?? 0), 64)
    freeRead.append((0..<n).map { f.word(p + 4 + 4 * $0) ?? 0xffff_ffff })
    p += 4 + 4 * n
}
check("root block: the free lists, size by size, Finder's", freeRead == finderFree,
      "(\(freeRead.enumerated().filter { !$0.element.isEmpty }.map { "\($0.offset): \($0.element.map { String($0, radix: 16) })" }))")
check("root block: nothing after them in its 0x800 bytes", f.zero(p, root + 0x800))
let dsdb = 4 + 0x40
check("DSDB: the root node is block 2, no levels below it, 8 records, 1 node, pages of 4,096 bytes",
      (0..<5).map { f.word(dsdb + 4 * $0) } == [2, 0, 8, 1, 4096])
check("free: the bytes between the header and DSDB, and after DSDB up to the leaf, are zero",
      f.zero(4 + 0x20, dsdb) && f.zero(dsdb + 20, 4 + 0x1000))
let leaf = 4 + 0x1000
check("leaf: a leaf (no children) with 8 records", f.word(leaf) == 0 && f.word(leaf + 4) == 8)
let parsed = parseRecords(f, from: leaf + 8, count: 8)
check("leaf: the records read, and every byte after them in the page is zero", parsed.map { f.zero($0.end, leaf + 0x1000) } == true)
let recs = parsed?.records ?? []
check("records: the folder's four, then each icon's place, sorted by name without regard to case, then by code",
      recs.map { "\($0.name) \($0.code) \($0.type)" } == [". bwsp blob", ". icvp blob", ". vSrn long", ". vstl type", ".background Iloc blob",
                                                          ".VolumeIcon.icns Iloc blob", "Applications Iloc blob", "Sill.app Iloc blob"],
      "(\(recs.map { "\($0.name) \($0.code)" }))")
func record(_ name: String, _ code: String) -> Rec? { recs.first { $0.name == name && $0.code == code } }
let bwspWant = ["ContainerShowSidebar: bool false", "PreviewPaneVisibility: bool false", "ShowPathbar: bool false",
                "ShowSidebar: bool false", "ShowStatusBar: bool false", "ShowTabView: bool false", "ShowToolbar: bool false",
                "SidebarWidth: int 0", "WindowBounds: string {{200, 120}, {660, 432}}"]
check("bwsp: the window at (200, 120), 660 x 432 points (the picture's 400 and macOS 27's 32-point title bar), no bars",
      plistLines(record(".", "bwsp")) == bwspWant.sorted(), "(\(plistLines(record(".", "bwsp"))))")
let icvpWant = ["arrangeBy: string none", "backgroundColorBlue: real 1.0", "backgroundColorGreen: real 1.0", "backgroundColorRed: real 1.0",
                "backgroundImageAlias: data \(hex(aliasUTC))", "backgroundType: int 2", "gridOffsetX: real 0.0", "gridOffsetY: real 0.0",
                "gridSpacing: real 100.0", "iconSize: real 128.0", "labelOnBottom: bool true", "showIconPreview: bool true",
                "showItemInfo: bool false", "textSize: real 12.0", "viewOptionsVersion: int 1"]
check("icvp: the picture through its alias, white beyond it, 128-point icons, 12-point names below them, no arrangement",
      plistLines(record(".", "icvp")) == icvpWant.sorted(), "(\(plistLines(record(".", "icvp"))))")
check("vSrn: 1", record(".", "vSrn")?.value == [0, 0, 0, 1])
check("vstl: icon view (icnv), whatever the Mac's default view", record(".", "vstl")?.value == Array("icnv".utf8))
func iloc(_ x: UInt32, _ y: UInt32) -> [UInt8] { words([16, x, y]) + [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0] }
check("Iloc: Sill.app's centre at (170, 180), the arrow's tail, then the eight bytes Finder writes",
      record("Sill.app", "Iloc")?.value == iloc(170, 180))
check("Iloc: Applications at (490, 180), the arrow's head", record("Applications", "Iloc")?.value == iloc(490, 180))
check("Iloc: .background and .VolumeIcon.icns in a row below the 400 points, out of sight",
      record(".background", "Iloc")?.value == iloc(128, 656) && record(".VolumeIcon.icns", "Iloc")?.value == iloc(316, 656))
check("decode: DSStore.decode reads back the records encode wrote", (try? DSStore.decode(fileData)) == releaseRecords)

// Another window, with numbers of its own: a colour's channels, the bounds' four numbers, names
// whose case changes their order, no hidden items.
let other = DMGLayout(width: 500, height: 300, left: 10, top: 20, iconSize: 96, textSize: 14, background: ".bg/picture.png",
                      backgroundColor: (0x12, 0x34, 0x56), items: [.init(name: "B", x: 1, y: 2), .init(name: "a", x: 3, y: 4)], hidden: [])
let otherRecords = (try? other.records(backgroundAlias: Data([1, 2, 3]))) ?? []
check("another window: its records, \"a\" before \"B\"",
      otherRecords.map { "\($0.name) \($0.code)" } == [". bwsp", ". icvp", ". vSrn", ". vstl", "a Iloc", "B Iloc"])
check("another window: its bounds, {{10, 20}, {500, 332}}",
      plistLines(otherRecords.first { $0.code == "bwsp" }).contains("WindowBounds: string {{10, 20}, {500, 332}}"))
let otherIcvp = plistLines(otherRecords.first { $0.code == "icvp" })
check("another window: its colour channel by channel, its sizes, its alias",
      ["backgroundColorRed: real \(Double(0x12) / 255)", "backgroundColorGreen: real \(Double(0x34) / 255)",
       "backgroundColorBlue: real \(Double(0x56) / 255)", "iconSize: real 96.0", "textSize: real 14.0",
       "backgroundImageAlias: data 010203"].allSatisfy(otherIcvp.contains), "(\(otherIcvp))")
check("another window: each icon's place", otherRecords.first { $0.name == "a" }?.value == .blob(Data(iloc(3, 4).dropFirst(4)))
      && otherRecords.first { $0.name == "B" }?.value == .blob(Data(iloc(1, 2).dropFirst(4))))

// MARK: The encoder and the decoder, every kind of value

let variety: [DSRecord] = [
    DSRecord(name: "Zebra", code: "Iloc", value: .blob(Data([1, 2, 3]))),
    DSRecord(name: "apple", code: "lg1S", value: .comp(0x0123_4567_89ab_cdef)),
    DSRecord(name: "Mango", code: "modD", value: .dutc(42)),
    DSRecord(name: ".", code: "vstl", value: .type("clmv")),
    DSRecord(name: ".", code: "vSrn", value: .long(0xfedc_ba98)),
    DSRecord(name: ".", code: "fwvh", value: .shor(0xbeef)),
    DSRecord(name: ".", code: "ICVO", value: .bool(true)),
    DSRecord(name: "Ünïcödé 名前", code: "cmmt", value: .ustr("a comment, 👍")),
]
let sortedVariety = [variety[6], variety[5], variety[4], variety[3], variety[1], variety[2], variety[0], variety[7]]
let varietyData = (try? DSStore.encode(variety)) ?? Data()
check("encode, decode: every kind of value comes back, sorted: \".\" (ICVO, fwvh, vSrn, vstl), apple, Mango, Zebra, Ünïcödé",
      (try? DSStore.decode(varietyData)) == sortedVariety, "(\((try? DSStore.decode(varietyData))?.map { $0.name + " " + $0.code } ?? []))")
let varietyParsed = parseRecords(Bytes(varietyData), from: 4 + 0x1000 + 8, count: variety.count)?.records ?? []
check("encode: each value's bytes (bool 1 byte, shor, long and type 4, comp and dutc 8, blob and ustr counted)",
      varietyParsed.map { hex($0.value) } == ["01", "0000beef", "fedcba98", "636c6d76", "0123456789abcdef", "000000000000002a", "00000003010203",
                                               hex(words([UInt32("a comment, 👍".utf16.count)])) + hex(utf16BE("a comment, 👍"))], "(\(varietyParsed.map { hex($0.value) }))")
check("encode: names in UTF-16, the count in 16-bit units", varietyParsed.last?.name == "Ünïcödé 名前")
check("encode: the same name twice, whatever its case, and the same code, is refused",
      (try? DSStore.encode([DSRecord(name: "A", code: "Iloc", value: .long(1)), DSRecord(name: "a", code: "Iloc", value: .long(2))])) == nil)
check("encode: a code or a type that isn't four characters is refused",
      (try? DSStore.encode([DSRecord(name: "a", code: "Ilo", value: .long(1))])) == nil
      && (try? DSStore.encode([DSRecord(name: "a", code: "Iloç", value: .long(1))])) == nil
      && (try? DSStore.encode([DSRecord(name: "a", code: "vstl", value: .type("icn"))])) == nil)
check("encode: records that don't fit one 4,096-byte node are refused (this writer makes one)",
      (try? DSStore.encode((0..<60).map { DSRecord(name: "file \($0)", code: "Iloc", value: .blob(Data(count: 80))) })) == nil)
check("encode: the same file every time", (try? DSStore.encode(variety.reversed())) == varietyData)

// The free lists, on their own.
let fourBlocks = [(address: 0, size: 0x20), (address: 0x40, size: 0x20), (address: 0x1000, size: 0x1000), (address: 0x2000, size: 0x800)]
let lists = DSStore.freeLists(allocated: fourBlocks)
check("free lists: Finder's, around the four blocks encode allocates", lists.map { $0.map(UInt32.init) } == finderFree)
var blocks = fourBlocks.map { (address: $0.address, size: $0.size) }
for (width, list) in lists.enumerated() { blocks += list.map { (address: $0, size: 1 << width) } }
blocks.sort { $0.address < $1.address }
let tiles = zip(blocks, blocks.dropFirst()).allSatisfy { $0.address + $0.size == $1.address }
check("free lists: with the allocated blocks, they tile the 2 GiB address space, each block aligned to its size",
      blocks.first?.address == 0 && tiles && blocks.last.map { $0.address + $0.size } == 1 << 31
      && blocks.allSatisfy { $0.address % $0.size == 0 && $0.size.nonzeroBitCount == 1 })
check("free lists: around one 32-byte block at 0, one block of each size from 32 bytes to 1 GiB",
      DSStore.freeLists(allocated: [(address: 0, size: 32)]) == (0..<32).map { (5...30).contains($0) ? [1 << $0] : [] })

// A tree of two levels, as Finder makes for a folder with more records than a page holds: the
// decoder reads a child's records before the one that separates it from the next.
func longRecord(_ name: String, _ value: UInt32) -> [UInt8] {
    words([UInt32(name.utf16.count)]) + utf16BE(name) + Array("Iloc".utf8) + Array("long".utf8) + words([value])
}
var tree = [UInt8](repeating: 0, count: 4 + 0x5000)
func put(_ bytes: [UInt8], at offset: Int) { tree.replaceSubrange(offset..<(offset + bytes.count), with: bytes) }
put(words([1]) + Array("Bud1".utf8) + words([0x2000, 0x800, 0x2000]), at: 0)
put(words([5, 0, 0x200b, 0x45, 0x100c, 0x300c, 0x400c]), at: 4 + 0x2000)
put(words([1]) + [4] + Array("DSDB".utf8) + words([1]), at: 4 + 0x2000 + 8 + 1024)
put(words([2, 1, 3, 3, 4096]), at: 4 + 0x40)
put(words([4, 1, 3]) + longRecord("m", 2), at: 4 + 0x1000)      // block 2: child 3, "m", then the last child, 4
put(words([0, 1]) + longRecord("a", 1), at: 4 + 0x3000)
put(words([0, 1]) + longRecord("z", 3), at: 4 + 0x4000)
check("decode: a two-level tree in order: the first child's \"a\", \"m\", the last child's \"z\"",
      (try? DSStore.decode(Data(tree)))?.map { "\($0.name)=\($0.value)" } == ["a=long(1)", "m=long(2)", "z=long(3)"],
      "(\((try? DSStore.decode(Data(tree)))?.map { "\($0.name)=\($0.value)" } ?? []))")
var notBud = fileData; notBud[4] = 0x63
check("decode: refuses a file without \"Bud1\", one cut short, and one whose two root addresses differ",
      (try? DSStore.decode(notBud)) == nil && (try? DSStore.decode(fileData.prefix(5000))) == nil
      && (try? DSStore.decode({ var d = fileData; d[19] = 0x08; return d }())) == nil)

// MARK: The volume icon's flag

let iconFolder = out + "/volume-icon"
try? FileManager.default.removeItem(atPath: iconFolder)
try? FileManager.default.createDirectory(atPath: iconFolder, withIntermediateDirectories: true)
func finderInfo(_ path: String) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 32)
    return getxattr(path, "com.apple.FinderInfo", &bytes, 32, 0, XATTR_NOFOLLOW) == 32 ? bytes : []
}
check("volume icon: a new folder has no Finder flags", VolumeIcon.flags(iconFolder) == 0)
let setOnce = (try? VolumeIcon.setCustomIcon(iconFolder)) != nil
check("volume icon: the custom-icon flag (0x0400) set in a folder that had no Finder info, the rest zero",
      setOnce && finderInfo(iconFolder) == [UInt8](repeating: 0, count: 8) + [0x04, 0x00] + [UInt8](repeating: 0, count: 22),
      "(\(hex(finderInfo(iconFolder))))")
// The folder's own Finder info (its window's rectangle, flags, place) is kept; the kernel keeps the
// second 16 bytes' dates to itself, so those stay zero here.
let seeded: [UInt8] = [0, 1, 0, 2, 0, 3, 0, 4, 0x01, 0x02, 0, 5, 0, 6, 0, 0] + [UInt8](repeating: 0, count: 16)
let seededFolder = out + "/volume-icon/seeded"
try? FileManager.default.createDirectory(atPath: seededFolder, withIntermediateDirectories: true)
let wroteSeed = setxattr(seededFolder, "com.apple.FinderInfo", seeded, 32, 0, XATTR_NOFOLLOW) == 0
var wantSeeded = seeded; wantSeeded[8] = 0x05
check("volume icon: the flag added to the folder's flags, every other byte kept",
      wroteSeed && (try? VolumeIcon.setCustomIcon(seededFolder)) != nil && finderInfo(seededFolder) == wantSeeded,
      "(\(hex(finderInfo(seededFolder))))")
check("volume icon: flags() reads it", VolumeIcon.flags(seededFolder) == 0x0502)

// MARK: An alias for a real file, and the whole .DS_Store for it

// forFile and dsStore on this Mac's own file system (the volume the check's folder is on, as Finder
// sees it): the IDs are the folders' and the file's, the path the file's from the volume's root, the
// mount point /Volumes/<the volume's name>. No disk image, so the alias isn't resolved here
// (make-dmg.sh's `check` resolves the real one on the mounted image).
let picture = out + "/real/.background/background.tiff"
try? FileManager.default.removeItem(atPath: out + "/real")
try? FileManager.default.createDirectory(atPath: out + "/real/.background", withIntermediateDirectories: true)
FileManager.default.createFile(atPath: picture, contents: Data("not a picture".utf8))
func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}
func inode(_ path: String) -> UInt64? { var st = stat(); return lstat(path, &st) == 0 ? st.st_ino : nil }
let volumeValues = try? URL(fileURLWithPath: out).resourceValues(forKeys: [.volumeURLKey, .volumeNameKey, .volumeCreationDateKey])
let volumeRoot = volumeValues?.volume.map { realPath($0.path) }
let realPicture = realPath(picture)
if let volumeRoot = volumeRoot, let volumeName = volumeValues?.volumeName, let created = volumeValues?.volumeCreationDate,
   realPicture.hasPrefix(volumeRoot == "/" ? "/" : volumeRoot + "/") {
    let relative = String(realPicture.dropFirst(volumeRoot == "/" ? 1 : volumeRoot.count + 1))
    // The folders from the picture's up to the volume's root (not included), the parent first.
    var folders: [UInt64] = [], folder = (realPicture as NSString).deletingLastPathComponent
    while folder != volumeRoot && folder != "/" {
        folders.append(inode(folder) ?? 0)
        folder = (folder as NSString).deletingLastPathComponent
    }
    do {
        let found = try FinderAlias.forFile(relative, onVolumeAt: volumeRoot)
        check("forFile: the volume's name and creation date", found.volumeName == volumeName && found.volumeCreated == created)
        check("forFile: the picture's ID and name, its folder's ID and name",
              UInt64(found.fileID) == inode(realPicture) && found.fileName == "background.tiff"
              && UInt64(found.parentID) == folders.first && found.parentName == ".background")
        check("forFile: every folder's ID from the picture's up to the volume's root, the parent first",
              found.folderIDs.map(UInt64.init) == folders, "(\(found.folderIDs) against \(folders))")
        check("forFile: the path from the volume's root, and the mount point /Volumes/<its name> wherever it is mounted now",
              found.path == "/" + relative && found.mountPoint == "/Volumes/" + volumeName, "(\(found.path), \(found.mountPoint))")
        var birth = stat()
        _ = lstat(realPicture, &birth)
        check("forFile: the picture's creation date",
              found.fileCreated == Date(timeIntervalSince1970: TimeInterval(birth.st_birthtimespec.tv_sec) + TimeInterval(birth.st_birthtimespec.tv_nsec) / 1e9))
        var onVolume = release
        onVolume.background = relative
        let whole = try onVolume.dsStore(onVolumeAt: volumeRoot, timeZone: utc)
        let icvp = try DSStore.decode(whole).first { $0.code == "icvp" }
        let foundAlias = try found.encoded(timeZone: utc)
        check("dsStore: the layout's .DS_Store names the picture by forFile's alias",
              plistLines(icvp).contains("backgroundImageAlias: data \(hex(foundAlias))"))
    } catch let error as DSStoreError where error.description.contains("doesn't fit an alias") {
        print("skip forFile and dsStore: this file system's IDs don't fit an alias's 32 bits (\(error))")
    } catch {
        check("forFile: an alias for \(relative) on \(volumeRoot)", false, "(\(error))")
    }
    check("forFile: refuses a folder that isn't a volume's root",
          (try? FinderAlias.forFile(".background/background.tiff", onVolumeAt: out + "/real")) == nil)
    let folderRelative = (relative as NSString).deletingLastPathComponent
    check("forFile: refuses a folder where the picture should be, a path with \"..\", and a file at the root",
          (try? FinderAlias.forFile(folderRelative, onVolumeAt: volumeRoot)) == nil
          && (try? FinderAlias.forFile(folderRelative + "/../.background/background.tiff", onVolumeAt: volumeRoot)) == nil
          && (try? FinderAlias.forFile("background.tiff", onVolumeAt: volumeRoot)) == nil)
} else {
    print("skip forFile and dsStore: can't tell which volume \(out) is on")
}

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
