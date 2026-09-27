import Foundation

// How a .DS_Store names its window's background picture: the "icvp" record's backgroundImageAlias,
// an Alias Manager record (version 2) for a file on the same volume. When the image is mounted,
// Finder finds the picture through it (by the volume's name and creation date, then the file's ID,
// its folder's ID or its path), wherever the volume is mounted.
//
// FinderAlias writes the record as Finder itself does for a background on a disk image's HFS+
// volume (a Finder-made installer image's record, 2023, fields and tags in this order), less the
// last tag, 20, an alias of the read-write image Finder had open, which names the build machine's
// folders and is not needed to find the picture:
//
//     0   4  application info, 0            114   4  the file's ID (its CNID)
//     4   2  the record's length            118   4  the file's creation date
//     6   2  version 2                       122   8  creator and type codes, 0
//     8   2  kind: 0, a file                 130   4  levels from and to, -1 and -1
//    10  28  the volume's name (Pascal)      134   4  volume attributes 0x0d02
//    38   4  the volume's creation date      138  12  file system ID and reserved, 0
//    42   2  file system, "H+"               150      tagged fields, each a 2-byte tag, a 2-byte
//    44   2  disk type 5, ejectable                   length and the value (padded to even), then
//    46   4  the parent folder's ID                   tag -1 with length 0:
//    50  64  the file's name (Pascal)
//
//   0 the parent folder's name      16 the volume's creation date   17 the file's creation date
//   1 the folder IDs up to the root  2 "Volume:folder:\0file"       14 the file's name (UTF-16)
//  15 the volume's name (UTF-16)    18 the file's path on the volume  19 the volume's mount point
//
// The 4-byte dates count seconds since 1904 in local time, as HFS+ keeps a volume's creation date;
// tags 16 and 17 count 1/65536 seconds since 1904 in UTC. Names go into the Pascal strings with ":"
// as "/", the way the Carbon path writes them.

struct FinderAlias: Equatable {
    var volumeName: String
    var volumeCreated: Date
    var parentID: UInt32
    var parentName: String
    var fileID: UInt32
    var fileName: String
    var fileCreated: Date
    /// The IDs of the folders from the file's parent up to (not including) the volume's root.
    var folderIDs: [UInt32]
    /// The file's path on the volume, from its root: "/.background/background.tiff".
    var path: String
    /// Where the volume is mounted when the alias is used: "/Volumes/<name>" on any Mac that opens
    /// the image, whatever folder it was mounted in while being made.
    var mountPoint: String

    static let hfsEpoch = Date(timeIntervalSince1970: -2_082_844_800)   // 1904-01-01 00:00:00 UTC
    static let tags: [Int16] = [0, 16, 17, 1, 2, 14, 15, 18, 19]

    /// The alias for `relativePath` (such as ".background/background.tiff"), a regular file in a
    /// folder on the volume mounted at `volume`, as Finder will see it once the image is mounted at
    /// /Volumes/<the volume's name>.
    static func forFile(_ relativePath: String, onVolumeAt volume: String) throws -> FinderAlias {
        let volumeURL = URL(fileURLWithPath: volume).resolvingSymlinksInPath()
        let values = try volumeURL.resourceValues(forKeys: [.volumeNameKey, .volumeCreationDateKey, .volumeURLKey])
        guard let name = values.volumeName, let created = values.volumeCreationDate else {
            throw DSStoreError("\(volume) reports no volume name or creation date")
        }
        let root = volumeURL.path
        guard let volumeRoot = values.volume?.resolvingSymlinksInPath().path, volumeRoot == root else {
            throw DSStoreError("\(volume) is not the root of a volume")
        }
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count >= 2, !components.contains(".."), !components.contains(".") else {
            throw DSStoreError("\(relativePath) must name a file in a folder on the volume, such as .background/background.tiff")
        }
        let info = try status(root + "/" + components.joined(separator: "/"))
        guard info.isRegularFile else { throw DSStoreError("\(relativePath) on \(volume) is not a regular file") }

        // The folders between the volume's root and the file, the parent first.
        var folderIDs: [UInt32] = []
        for depth in stride(from: components.count - 1, through: 1, by: -1) {
            folderIDs.append(try status(root + "/" + components[0..<depth].joined(separator: "/")).id)
        }
        return FinderAlias(
            volumeName: name, volumeCreated: created,
            parentID: folderIDs[0], parentName: components[components.count - 2],
            fileID: info.id, fileName: components[components.count - 1], fileCreated: info.created,
            folderIDs: folderIDs, path: "/" + components.joined(separator: "/"),
            mountPoint: "/Volumes/" + name)
    }

    private static func status(_ path: String) throws -> (id: UInt32, created: Date, isRegularFile: Bool) {
        var st = stat()
        guard lstat(path, &st) == 0 else { throw DSStoreError("can't stat \(path): \(String(cString: strerror(errno)))") }
        guard st.st_ino <= UInt64(UInt32.max) else { throw DSStoreError("\(path)'s ID \(st.st_ino) doesn't fit an alias") }
        let created = Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec)
            + TimeInterval(st.st_birthtimespec.tv_nsec) / 1e9)
        return (UInt32(st.st_ino), created, (st.st_mode & S_IFMT) == S_IFREG)
    }

    /// Whole seconds since 1904 in UTC.
    static func hfsSeconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince(hfsEpoch)).rounded(.down))
    }

    /// The record. `timeZone` makes the two 4-byte dates local time, as HFS+ does (the Mac that makes
    /// the image: its creation date on the volume is that Mac's local time too).
    func encoded(timeZone: TimeZone = .current) throws -> Data {
        func local(_ date: Date) throws -> UInt32 {
            let seconds = Self.hfsSeconds(date) + Int64(timeZone.secondsFromGMT(for: date))
            guard seconds >= 0, seconds <= Int64(UInt32.max) else { throw DSStoreError("\(date) is out of an alias's range") }
            return UInt32(seconds)
        }
        func pascal(_ string: String, _ size: Int) throws -> Data {
            let bytes = Array(string.replacingOccurrences(of: ":", with: "/").utf8)
            guard string.allSatisfy(\.isASCII), bytes.count < size else {
                throw DSStoreError("\"\(string)\" must be ASCII and at most \(size - 1) characters in an alias")
            }
            return Data([UInt8(bytes.count)] + bytes + [UInt8](repeating: 0, count: size - 1 - bytes.count))
        }
        func half(_ value: Int16) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
        func long(_ value: UInt64) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
        func utf16(_ string: String) -> Data {
            var data = half(Int16(string.utf16.count))
            data.appendUTF16(string)
            return data
        }

        var record = Data([0, 0, 0, 0])                      // application info
        record.append(half(0))                                // the length, filled in below
        record.append(half(2))                                // version 2
        record.append(half(0))                                // a file
        record.append(try pascal(volumeName, 28))
        record.appendWord(try local(volumeCreated))
        record.append(contentsOf: Array("H+".utf8))
        record.append(half(5))                                // ejectable: a disk image
        record.appendWord(parentID)
        record.append(try pascal(fileName, 64))
        record.appendWord(fileID)
        record.appendWord(try local(fileCreated))
        record.append(Data(count: 8))                         // creator and type
        record.append(half(-1))                               // levels from
        record.append(half(-1))                               // levels to
        record.appendWord(0x0d02)                             // volume attributes, as Finder's
        record.append(Data(count: 12))                        // file system ID and reserved

        func tag(_ number: Int16, _ value: Data) {
            record.append(half(number))
            record.append(half(Int16(value.count)))
            record.append(value)
            if value.count % 2 == 1 { record.append(0) }
        }
        tag(0, Data(parentName.replacingOccurrences(of: ":", with: "/").utf8))
        tag(16, long(UInt64(Self.hfsSeconds(volumeCreated)) << 16))
        tag(17, long(UInt64(Self.hfsSeconds(fileCreated)) << 16))
        var ids = Data()
        for id in folderIDs { ids.appendWord(id) }
        tag(1, ids)
        let carbon = path.split(separator: "/").map { $0.replacingOccurrences(of: ":", with: "/") }
        tag(2, Data((volumeName.replacingOccurrences(of: ":", with: "/") + ":" + carbon.joined(separator: ":\0")).utf8))
        tag(14, utf16(fileName))
        tag(15, utf16(volumeName))
        tag(18, Data(path.utf8))
        tag(19, Data(mountPoint.utf8))
        record.append(half(-1))
        record.append(half(0))

        guard record.count <= Int(Int16.max) else { throw DSStoreError("the alias is too long") }
        record.replace(at: 4, with: half(Int16(record.count)))
        return record
    }

    /// The fields of a record, read back: every field `encoded` writes (the 4-byte dates as they
    /// are, local time), and the tags in the order they came.
    struct Fields: Equatable {
        var length: Int, version: Int, kind: Int
        var volumeName: String, volumeDate: UInt32, fileSystem: String, diskType: Int
        var parentID: UInt32, fileName: String, fileID: UInt32, fileDate: UInt32
        var levelsFrom: Int, levelsTo: Int, volumeAttributes: UInt32
        var tagOrder: [Int16]
        var tagValues: [Int16: Data]
    }

    static func fields(of data: Data) throws -> Fields {
        let reader = ByteReader(data)
        guard data.count >= 150 else { throw DSStoreError("an alias record of \(data.count) bytes is too short") }
        func half(_ offset: Int) throws -> Int { Int(try reader.half(at: offset)) }
        func pascal(_ offset: Int) throws -> String {
            let length = Int(try reader.bytes(at: offset, count: 1)[0])
            return String(decoding: try reader.bytes(at: offset + 1, count: length), as: UTF8.self)
        }
        var fields = Fields(
            length: try half(4), version: try half(6), kind: try half(8),
            volumeName: try pascal(10), volumeDate: try reader.word(at: 38),
            fileSystem: String(decoding: try reader.bytes(at: 42, count: 2), as: UTF8.self), diskType: try half(44),
            parentID: try reader.word(at: 46), fileName: try pascal(50), fileID: try reader.word(at: 114),
            fileDate: try reader.word(at: 118), levelsFrom: try half(130), levelsTo: try half(132),
            volumeAttributes: try reader.word(at: 134), tagOrder: [], tagValues: [:])
        var offset = 150
        while true {
            let number = Int16(try half(offset)), length = try half(offset + 2)
            offset += 4
            if number == -1 { break }
            guard length >= 0 else { throw DSStoreError("tag \(number) has a negative length") }
            fields.tagOrder.append(number)
            fields.tagValues[number] = try reader.bytes(at: offset, count: length)
            offset += length + (length % 2)
        }
        guard offset == data.count, fields.length == data.count else {
            throw DSStoreError("the alias says it is \(fields.length) bytes; its fields end at \(offset) of \(data.count)")
        }
        return fields
    }

    /// Where the record leads on this Mac, found the way Finder finds it: CoreFoundation turns the
    /// alias into a bookmark and resolves that, without asking anything or mounting anything.
    static func resolve(_ record: Data) -> String? {
        guard let bookmark = (AliasManager.self as AliasBridge.Type).bookmark(fromAlias: record) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return url.standardizedFileURL.path
    }
}

// CFURLCreateBookmarkDataFromAliasRecord is deprecated with the rest of the Carbon Alias Manager,
// and its deprecation note names this very use: turning an alias record into bookmark data. Called
// through a protocol, so the build stays free of warnings.
private protocol AliasBridge {
    static func bookmark(fromAlias record: Data) -> Data?
}

private enum AliasManager: AliasBridge {
    @available(macOS, deprecated: 11.0)
    static func bookmark(fromAlias record: Data) -> Data? {
        CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault, record as CFData)?.takeRetainedValue() as Data?
    }
}
