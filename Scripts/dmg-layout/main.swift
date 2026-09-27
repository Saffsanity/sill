import Foundation
import ImageIO
import UniformTypeIdentifiers

// dmg-layout: lays out a disk image's Finder window from the command line, for Scripts/make-dmg.sh.
// Built there with `xcrun swiftc -O Scripts/dmg-layout/*.swift`; nothing here asks Finder anything.
//
//   dmg-layout write VOLUME LAYOUT     writes VOLUME/.DS_Store (DSStore.swift, FinderAlias.swift) and,
//                                      with VOLUME/.VolumeIcon.icns there, sets the volume's
//                                      custom-icon flag
//   dmg-layout check VOLUME LAYOUT     reads them back from a mounted image: the records the layout
//                                      makes, the background's alias leading to the picture on
//                                      this volume, the picture's two sizes, the icon flag
//   dmg-layout dump FILE               prints a .DS_Store's records
//   dmg-layout crop IN OUT WxH         the top-left WxH pixels of IN (a Quick Look render) as a PNG
//
// LAYOUT: --window WxH (the content, in points: the picture's size at 1x) --position X,Y
//   --icon-size N --text-size N --background PATH (on the volume) --background-color RRGGBB
//   --item NAME=X,Y (an icon's centre; repeated) --hidden NAME (repeated)

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("dmg-layout: \(message)\n".utf8))
    exit(status)
}

func parseLayout(_ arguments: ArraySlice<String>) -> DMGLayout {
    var layout = DMGLayout(width: 0, height: 0, left: 0, top: 0, iconSize: 0, textSize: 0, background: "",
                           backgroundColor: (0, 0, 0), items: [], hidden: [])
    var seen = Set<String>()
    var rest = arguments.makeIterator()
    func pair(_ text: String, _ separator: Character, _ option: String) -> (Int, Int) {
        let parts = text.split(separator: separator).map { Int($0) }
        guard parts.count == 2, let a = parts[0], let b = parts[1], a >= 0, b >= 0 else {
            fail("\(option) takes two whole numbers separated by \"\(separator)\", not \"\(text)\"", status: 2)
        }
        return (a, b)
    }
    while let option = rest.next() {
        guard let value = rest.next() else { fail("\(option) needs a value", status: 2) }
        seen.insert(option)
        switch option {
        case "--window": (layout.width, layout.height) = pair(value, "x", option)
        case "--position": (layout.left, layout.top) = pair(value, ",", option)
        case "--icon-size": layout.iconSize = Int(value) ?? 0
        case "--text-size": layout.textSize = Int(value) ?? 0
        case "--background": layout.background = value
        case "--background-color":
            guard value.count == 6, let rgb = Int(value, radix: 16) else { fail("--background-color takes RRGGBB, not \"\(value)\"", status: 2) }
            layout.backgroundColor = (rgb >> 16, (rgb >> 8) & 0xff, rgb & 0xff)
        case "--item":
            guard let equals = value.lastIndex(of: "=") else { fail("--item takes NAME=X,Y, not \"\(value)\"", status: 2) }
            let (x, y) = pair(String(value[value.index(after: equals)...]), ",", option)
            layout.items.append(.init(name: String(value[..<equals]), x: x, y: y))
        case "--hidden": layout.hidden.append(value)
        default: fail("unknown option \(option)", status: 2)
        }
    }
    for needed in ["--window", "--position", "--icon-size", "--text-size", "--background", "--background-color", "--item"]
    where !seen.contains(needed) {
        fail("\(needed) is missing", status: 2)
    }
    guard layout.width > 0, layout.height > 0, (16...512).contains(layout.iconSize), (10...16).contains(layout.textSize) else {
        fail("the window needs a size, the icons 16 to 512 points and the text 10 to 16", status: 2)
    }
    for item in layout.items where item.x > layout.width || item.y > layout.height {
        fail("\(item.name) at \(item.x),\(item.y) is outside the \(layout.width)x\(layout.height) window", status: 2)
    }
    return layout
}

/// The picture's representations as (width, height, dpi), from its file.
func pictureSizes(_ path: String) -> [(width: Int, height: Int, dpi: Int)] {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return [] }
    return (0..<CGImageSourceGetCount(source)).compactMap { index in
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return (width, height, Int(dpi.rounded()))
    }
}

func write(_ volume: String, _ layout: DMGLayout) throws {
    let data = try layout.dsStore(onVolumeAt: volume)
    try data.write(to: URL(fileURLWithPath: volume + "/.DS_Store"), options: .atomic)
    if FileManager.default.fileExists(atPath: volume + "/.VolumeIcon.icns") {
        try VolumeIcon.setCustomIcon(volume)
    }
    print("Wrote \(volume)/.DS_Store (\(data.count) bytes): a \(layout.width)x\(layout.height) window, "
          + layout.items.map { "\($0.name) at \($0.x),\($0.y)" }.joined(separator: ", "))
}

/// The path with every symbolic link resolved (/tmp is /private/tmp), or itself when it's not there.
func real(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// How `have` differs from `want`, record by record. Property lists (bwsp, icvp) are compared as
/// what they hold: their bytes follow the order a dictionary happens to have in the process that
/// wrote them.
func differences(_ have: [DSRecord], _ want: [DSRecord]) -> [String] {
    func plist(_ record: DSRecord) -> NSDictionary? {
        guard case .blob(let data) = record.value else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary
    }
    var problems: [String] = []
    let haveKeys = have.map { "\($0.name) \($0.code)" }, wantKeys = want.map { "\($0.name) \($0.code)" }
    if haveKeys != wantKeys {
        return ["its .DS_Store has the records \(haveKeys), not \(wantKeys)"]
    }
    for (a, b) in zip(have, want) {
        if let pa = plist(a), let pb = plist(b) {
            for key in Set(pa.allKeys.compactMap { $0 as? String } + pb.allKeys.compactMap { $0 as? String }).sorted()
            where !((pa[key] as AnyObject?)?.isEqual(pb[key]) ?? (pb[key] == nil)) {
                problems.append("\(a.name) \(a.code): \(key) is \(pa[key].map { "\($0)" } ?? "missing"), not \(pb[key].map { "\($0)" } ?? "missing")")
            }
        } else if a.value != b.value {
            problems.append("\(a) is not \(b)")
        }
    }
    return problems
}

/// Everything the layout promises, read back from the mounted image. Returns the problems.
func check(_ volume: String, _ layout: DMGLayout) -> [String] {
    var problems: [String] = []
    let root = real(volume)
    guard let data = FileManager.default.contents(atPath: root + "/.DS_Store") else {
        return ["\(volume) has no .DS_Store"]
    }
    let records: [DSRecord]
    do { records = try DSStore.decode(data) } catch { return ["its .DS_Store can't be read: \(error)"] }

    // The alias as the file has it; everything else must be exactly what the layout makes.
    guard let icvp = records.first(where: { $0.name == "." && $0.code == "icvp" }), case .blob(let icvpData) = icvp.value,
          let options = try? PropertyListSerialization.propertyList(from: icvpData, format: nil) as? [String: Any],
          let alias = options["backgroundImageAlias"] as? Data else {
        return ["its .DS_Store has no icon view settings with a background alias"]
    }
    do {
        let expected = try layout.records(backgroundAlias: alias)
        problems += differences(records, expected)
        // The file itself: exactly the blocks, tree and free lists this writer makes of its records.
        if try DSStore.encode(records) != data {
            problems.append("its .DS_Store holds the records, but not laid out as DSStore.encode lays them out")
        }
    } catch {
        problems.append("the layout's records can't be made: \(error)")
    }

    // The alias: every field that doesn't depend on a time zone as the volume has it now, the
    // local-time dates within a time zone of the UTC ones, and resolving to the picture here.
    do {
        let actual = try FinderAlias.fields(of: alias)
        let now = try FinderAlias.forFile(layout.background, onVolumeAt: root)
        let wanted = try FinderAlias.fields(of: try now.encoded(timeZone: TimeZone(identifier: "UTC")!))
        var same = actual, other = wanted
        same.volumeDate = 0; same.fileDate = 0; other.volumeDate = 0; other.fileDate = 0
        if same != other { problems.append("the background alias is \(actual), not \(wanted)") }
        for (local, utc, what) in [(actual.volumeDate, wanted.volumeDate, "volume"), (actual.fileDate, wanted.fileDate, "file")] {
            let offset = Int64(local) - Int64(utc)
            if abs(offset) > 14 * 3600 || offset % 900 != 0 {
                problems.append("the alias's \(what) date is \(offset) s from UTC, not a time zone's offset")
            }
        }
        let resolved = FinderAlias.resolve(alias).map(real)
        if resolved != real(root + "/" + layout.background) {
            problems.append("the background alias leads to \(resolved ?? "nothing"), not \(root)/\(layout.background)")
        }
    } catch {
        problems.append("the background alias can't be checked: \(error)")
    }

    // The picture: 1x at the window's size, 2x at twice it.
    let sizes = pictureSizes(root + "/" + layout.background)
    let want1 = (layout.width, layout.height, 72), want2 = (layout.width * 2, layout.height * 2, 144)
    if sizes.count != 2 || !sizes.contains(where: { $0 == want1 }) || !sizes.contains(where: { $0 == want2 }) {
        problems.append("the background has \(sizes.map { "\($0.width)x\($0.height) at \($0.dpi) dpi" }), "
                        + "not \(layout.width)x\(layout.height) at 72 dpi and \(layout.width * 2)x\(layout.height * 2) at 144")
    }

    // The icons: every item there, and the volume's own icon shown.
    for item in layout.items + layout.hidden.map({ .init(name: $0, x: 0, y: 0) }) {
        var status = stat()
        if lstat(root + "/" + item.name, &status) != 0 { problems.append("\(item.name) is not on the volume") }
    }
    if !FileManager.default.fileExists(atPath: root + "/.VolumeIcon.icns") {
        problems.append("the volume has no .VolumeIcon.icns")
    } else if VolumeIcon.flags(root) & VolumeIcon.hasCustomIcon == 0 {
        problems.append("the volume's root lacks the custom-icon flag, so Finder ignores .VolumeIcon.icns")
    }
    return problems
}

func dump(_ path: String) throws {
    guard let data = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
    for record in try DSStore.decode(data) {
        print(record)
        guard case .blob(let blob) = record.value else { continue }
        if record.code == "Iloc", blob.count == 16 {
            let reader = ByteReader(blob)
            print("    centre at \(try reader.word(at: 0)),\(try reader.word(at: 4))")
        } else if let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any] {
            for key in plist.keys.sorted() {
                if let alias = plist[key] as? Data {
                    let fields = try FinderAlias.fields(of: alias)
                    print("    \(key): alias of \(alias.count) bytes for \"\(fields.fileName)\" (ID \(fields.fileID)) in folder \(fields.parentID) on \"\(fields.volumeName)\", "
                          + "path \(String(decoding: fields.tagValues[18] ?? Data(), as: UTF8.self)), tags \(fields.tagOrder)")
                } else {
                    print("    \(key) = \(plist[key]!)")
                }
            }
        }
    }
}

func crop(_ input: String, _ output: String, _ size: String) {
    let parts = size.split(separator: "x").compactMap { Int($0) }
    guard parts.count == 2, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("crop takes a picture and WxH: \(input) \(size)", status: 2)
    }
    // Drawn into an opaque bitmap: the picture has no transparent pixels, and without an alpha
    // channel the TIFF is a quarter smaller.
    let (width, height) = (parts[0], parts[1])
    guard width <= image.width, height <= image.height,
          let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fail("\(input) is \(image.width)x\(image.height), smaller than \(size)")
    }
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let opaque = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("can't draw \(input)")
    }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(output)") }
}

var arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.popFirst() else {
    fail("usage: dmg-layout write|check VOLUME LAYOUT, dump FILE, crop IN OUT WxH (Scripts/dmg-layout/main.swift)", status: 2)
}
do {
    switch command {
    case "write", "check":
        guard let volume = arguments.popFirst() else { fail("\(command) needs the mounted volume", status: 2) }
        let layout = parseLayout(arguments)
        if command == "write" {
            try write(volume, layout)
        } else {
            let problems = check(volume, layout)
            if !problems.isEmpty { fail("the image's window is not as laid out:\n  - " + problems.joined(separator: "\n  - ")) }
            print("The window: \(layout.width)x\(layout.height) points at \(layout.left),\(layout.top), icons \(layout.iconSize) points, "
                  + layout.items.map { "\($0.name) at \($0.x),\($0.y)" }.joined(separator: ", ")
                  + "; the background's alias leads to \(layout.background) on this volume; the volume's icon is on.")
        }
    case "dump":
        guard let file = arguments.popFirst() else { fail("dump needs a .DS_Store", status: 2) }
        try dump(file)
    case "crop":
        let rest = Array(arguments)
        guard rest.count == 3 else { fail("crop takes IN OUT WxH", status: 2) }
        crop(rest[0], rest[1], rest[2])
    default:
        fail("unknown command \(command)", status: 2)
    }
} catch {
    fail("\(error)")
}
