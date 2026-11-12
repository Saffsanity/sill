import Compression
import Foundation

/// Update Now's own reading of a release's zip (docs/one-click-update-plan.md §4.4 and T8), so no
/// other program (ditto, unzip, Archive Utility) decides what lands on disk. `read` checks the whole
/// archive before a byte is written: one top-level folder, names of printable ASCII under it, no
/// `..`, no two names equal ignoring case, links only to places inside the folder and never written
/// through, no encryption, zip64 or method but stored and deflate, local headers that agree with the
/// central directory, no two entries sharing bytes, sizes within limits. UpdateInstaller then writes
/// exactly the `Listing`, through directory descriptors it made itself. AppleDouble entries (a Mac
/// zips extended attributes and resource forks as "._name" beside the file, or under "__MACOSX/") are
/// read past and never written: a signed bundle needs none of them.
///
/// Pure: Foundation and Compression, no file system. Checked by Tests/checks/update-install.
enum UpdateArchive {
    struct Limits: Equatable, Sendable {
        var entries = 4096
        var totalBytes: Int64 = 512 << 20
        var nameBytes = 1024
        var linkBytes = 1024
        /// Deflate expands at most about 1,032 times; an entry that claims more lies about its sizes.
        var ratio = 1100
    }

    enum Kind: Equatable, Sendable {
        case directory
        case file(executable: Bool)
        case link(target: String)
    }

    struct Entry: Equatable, Sendable {
        /// The path's parts, the top folder first ("Sill.app", "Contents", "Info.plist").
        let components: [String]
        let kind: Kind
        /// 0 stored, 8 deflated.
        let method: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let size: Int
        /// Where the entry's stored or deflated bytes start in the zip.
        let dataOffset: Int

        var path: String { components.joined(separator: "/") }
    }

    struct Listing: Equatable, Sendable {
        /// In archive order: a folder before what is in it, as ditto writes them.
        let entries: [Entry]
        let totalBytes: Int64
        let skipped: Int
    }

    enum Problem: Error, Equatable, Sendable {
        case notAZip
        case multiDisk
        case zip64
        case tooManyEntries(Int)
        case tooLarge
        /// A central or local header that does not fit in the file or lacks its signature.
        case badHeader(String)
        /// The local header disagrees with the central directory about the entry (its name, the
        /// central one's).
        case localMismatch(String)
        case encrypted(String)
        case method(String, UInt16)
        /// A name that is empty, too long, not printable ASCII, absolute, or has an empty part, "."
        /// or "..".
        case badName(String)
        case notUnderTop(String)
        case duplicate(String)
        /// Not made on a Unix system (its mode is unknown).
        case notUnix(String)
        /// A type other than file, folder or link, or setuid, setgid or sticky.
        case badMode(String, UInt32)
        case badLink(String)
        /// An entry inside a link, or a link through a link.
        case throughLink(String)
        /// Inside something that is a file.
        case underFile(String)
        /// Two entries share bytes, or one runs into the central directory.
        case overlap(String)
        case badSizes(String)
        /// No entry under the top folder, or the top is not a folder.
        case noTop
        case topNotFolder
        case crc(String)
        case inflate(String)
        /// The writer refused a piece (a disk error, which the writer knows).
        case writeFailed(String)

        /// For the log: what is wrong, with the entry's name.
        var text: String {
            switch self {
            case .notAZip: return "it is not a zip archive"
            case .multiDisk: return "it spans several disks"
            case .zip64: return "it uses zip64"
            case .tooManyEntries(let n): return "it has \(n) entries"
            case .tooLarge: return "it unpacks to more than the limit"
            case .badHeader(let n): return "a header is damaged (\(n))"
            case .localMismatch(let n): return "\(n)’s local header disagrees with the central directory"
            case .encrypted(let n): return "\(n) is encrypted"
            case .method(let n, let m): return "\(n) uses compression method \(m)"
            case .badName(let n): return "an entry’s name is not allowed (\(n))"
            case .notUnderTop(let n): return "\(n) is outside the app"
            case .duplicate(let n): return "\(n) is in it twice (ignoring case)"
            case .notUnix(let n): return "\(n) was not made on a Mac or Unix system"
            case .badMode(let n, let mode): return "\(n) has mode \(String(mode, radix: 8))"
            case .badLink(let n): return "the link \(n) points outside the app or at nothing in it"
            case .throughLink(let n): return "\(n) goes through a link"
            case .underFile(let n): return "\(n) is inside a file"
            case .overlap(let n): return "\(n) shares bytes with another entry"
            case .badSizes(let n): return "\(n)’s sizes are not possible"
            case .noTop: return "it holds no app"
            case .topNotFolder: return "its app is not a folder"
            case .crc(let n): return "\(n) is damaged (its checksum)"
            case .inflate(let n): return "\(n) does not unpack to its size"
            case .writeFailed(let n): return "\(n) could not be written"
            }
        }
    }

    // MARK: Reading

    /// The listing of `zip`, whose one top-level folder must be `top` ("Sill.app"), or why not.
    static func read(_ zip: Data, top: String, limits: Limits = Limits()) -> Result<Listing, Problem> {
        let b = [UInt8](zip)
        let n = b.count
        func u16(_ o: Int) -> Int? { o >= 0 && o + 2 <= n ? Int(b[o]) | Int(b[o + 1]) << 8 : nil }
        func u32(_ o: Int) -> Int? {
            o >= 0 && o + 4 <= n ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : nil
        }

        // The end of the central directory: the last record whose comment runs exactly to the end.
        guard n >= 22 else { return .failure(.notAZip) }
        var eocd = -1
        var o = n - 22
        while o >= max(0, n - 22 - 0xFFFF) {
            if u32(o) == 0x0605_4B50, let comment = u16(o + 20), o + 22 + comment == n { eocd = o; break }
            o -= 1
        }
        guard eocd >= 0, let disk = u16(eocd + 4), let cdDisk = u16(eocd + 6), let here = u16(eocd + 8),
              let total = u16(eocd + 10), let cdSize = u32(eocd + 12), let cdOffset = u32(eocd + 16) else { return .failure(.notAZip) }
        if eocd >= 20, u32(eocd - 20) == 0x0706_4B50 { return .failure(.zip64) }
        if here == 0xFFFF || total == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF { return .failure(.zip64) }
        guard disk == 0, cdDisk == 0, here == total else { return .failure(.multiDisk) }
        guard total <= limits.entries else { return .failure(.tooManyEntries(total)) }
        guard cdOffset + cdSize == eocd else { return .failure(.badHeader("the central directory")) }

        struct Raw {
            let name: String
            let components: [String]
            let mode: UInt32
            let method: UInt16
            let crc: UInt32
            let compressed: Int
            let size: Int
            let headerOffset: Int
            let dataOffset: Int
            let skipped: Bool
        }
        var raws: [Raw] = []
        var p = cdOffset
        var totalBytes: Int64 = 0
        for _ in 0..<total {
            guard u32(p) == 0x0201_4B50, let madeBy = u16(p + 4), let flags = u16(p + 8), let method = u16(p + 10),
                  let crc = u32(p + 16), let compressed = u32(p + 20), let size = u32(p + 24), let nameLength = u16(p + 28),
                  let extraLength = u16(p + 30), let commentLength = u16(p + 32), let diskStart = u16(p + 34),
                  let external = u32(p + 38), let headerOffset = u32(p + 42),
                  p + 46 + nameLength + extraLength + commentLength <= cdOffset + cdSize else {
                return .failure(.badHeader("a central entry"))
            }
            let nameBytes = Array(b[(p + 46)..<(p + 46 + nameLength)])
            guard (1...limits.nameBytes).contains(nameLength),
                  nameBytes.allSatisfy({ (0x20...0x7E).contains($0) && $0 != 0x5C }) else {
                return .failure(.badName(nameLength == 0 ? "an empty name" : "a name with a byte outside printable ASCII"))
            }
            let name = String(decoding: nameBytes, as: UTF8.self)
            p += 46 + nameLength + extraLength + commentLength
            if compressed == 0xFFFF_FFFF || size == 0xFFFF_FFFF || headerOffset == 0xFFFF_FFFF { return .failure(.zip64) }
            guard diskStart == 0 else { return .failure(.multiDisk) }
            if flags & 0x0041 != 0 { return .failure(.encrypted(name)) }
            guard method == 0 || method == 8 else { return .failure(.method(name, UInt16(method))) }
            guard madeBy >> 8 == 3 else { return .failure(.notUnix(name)) }
            let mode = UInt32(external >> 16)
            let type = mode & 0o170000
            guard type == 0o040000 || type == 0o100000 || type == 0o120000, mode & 0o7000 == 0 else {
                return .failure(.badMode(name, mode))
            }
            let isDirectory = name.hasSuffix("/")
            guard isDirectory == (type == 0o040000) else { return .failure(.badMode(name, mode)) }
            guard let components = components(of: name, isDirectory: isDirectory) else { return .failure(.badName(name)) }
            if method == 0 { guard compressed == size else { return .failure(.badSizes(name)) } }
            if method == 8 { guard compressed > 0, size <= compressed * limits.ratio else { return .failure(.badSizes(name)) } }
            if isDirectory { guard size == 0, compressed == 0 else { return .failure(.badSizes(name)) } }

            // The local header: the same name, method, flags and (without a data descriptor) sizes.
            guard u32(headerOffset) == 0x0403_4B50, let localFlags = u16(headerOffset + 6), let localMethod = u16(headerOffset + 8),
                  let localCRC = u32(headerOffset + 14), let localCompressed = u32(headerOffset + 18),
                  let localSize = u32(headerOffset + 22), let localNameLength = u16(headerOffset + 26),
                  let localExtraLength = u16(headerOffset + 28) else {
                return .failure(.badHeader(name))
            }
            let dataOffset = headerOffset + 30 + localNameLength + localExtraLength
            guard localNameLength == nameLength, dataOffset + compressed <= n,
                  Array(b[(headerOffset + 30)..<(headerOffset + 30 + nameLength)]) == nameBytes,
                  localMethod == method, localFlags & 0x0041 == 0, localFlags & 0x0008 == flags & 0x0008 else {
                return .failure(.localMismatch(name))
            }
            if flags & 0x0008 == 0 {
                guard localCRC == crc, localCompressed == compressed, localSize == size else { return .failure(.localMismatch(name)) }
            } else {
                // With a data descriptor the local fields may be zero; if they are not, they must agree.
                guard localCRC == 0 || localCRC == crc, localCompressed == 0 || localCompressed == compressed,
                      localSize == 0 || localSize == size else { return .failure(.localMismatch(name)) }
            }
            let skipped = components.first == "__MACOSX" || components.last!.hasPrefix("._")
            if !skipped {
                totalBytes += Int64(size)
                guard totalBytes <= limits.totalBytes else { return .failure(.tooLarge) }
            }
            raws.append(Raw(name: name, components: components, mode: mode, method: UInt16(method), crc: UInt32(crc),
                            compressed: compressed, size: size, headerOffset: headerOffset, dataOffset: dataOffset, skipped: skipped))
        }
        guard p == cdOffset + cdSize else { return .failure(.badHeader("the central directory")) }

        // No two entries share bytes, and none runs into the central directory.
        let spans = raws.sorted { $0.headerOffset < $1.headerOffset }
        for (i, r) in spans.enumerated() {
            let end = r.dataOffset + r.compressed
            let next = i + 1 < spans.count ? spans[i + 1].headerOffset : cdOffset
            guard end <= next, i == 0 || spans[i - 1].headerOffset < r.headerOffset else { return .failure(.overlap(r.name)) }
        }

        // What is written: everything but AppleDouble, all of it under the one top folder.
        let kept = raws.filter { !$0.skipped }
        var kinds: [String: Kind] = [:]     // by lowercased path
        var entries: [Entry] = []
        for r in kept {
            guard r.components.first == top else { return .failure(.notUnderTop(r.name)) }
            let key = r.components.joined(separator: "/").lowercased()
            guard kinds[key] == nil else { return .failure(.duplicate(r.name)) }
            let kind: Kind
            switch r.mode & 0o170000 {
            case 0o040000:
                kind = .directory
            case 0o120000:
                // A link's target is its stored bytes (ditto stores links), printable ASCII.
                guard r.method == 0, (1...limits.linkBytes).contains(r.size) else { return .failure(.badLink(r.name)) }
                let target = Array(b[r.dataOffset..<(r.dataOffset + r.size)])
                guard target.allSatisfy({ (0x20...0x7E).contains($0) && $0 != 0x5C }),
                      target.withUnsafeBytes({ crc32($0) }) == r.crc else { return .failure(.badLink(r.name)) }
                kind = .link(target: String(decoding: target, as: UTF8.self))
            default:
                kind = .file(executable: r.mode & 0o111 != 0)
            }
            if r.components.count == 1, kind != .directory { return .failure(.topNotFolder) }
            kinds[key] = kind
            entries.append(Entry(components: r.components, kind: kind, method: r.method, crc32: r.crc,
                                 compressedSize: r.compressed, size: r.size, dataOffset: r.dataOffset))
        }
        guard entries.contains(where: { $0.components.count > 1 }) else { return .failure(.noTop) }

        // Nothing inside a file or a link; every link inside the top folder, to something in it that
        // is not itself a link (or inside one).
        for e in entries {
            for k in 1..<e.components.count {
                switch kinds[e.components[0..<k].joined(separator: "/").lowercased()] {
                case .file?: return .failure(.underFile(e.path))
                case .link?: return .failure(.throughLink(e.path))
                default: break
                }
            }
            guard case .link(let target) = e.kind else { continue }
            guard let resolved = resolve(target, from: Array(e.components.dropLast())), resolved.count > 1,
                  resolved.first == top else { return .failure(.badLink(e.path)) }
            for k in 1...resolved.count {
                switch kinds[resolved[0..<k].joined(separator: "/").lowercased()] {
                case .link?: return .failure(.throughLink(e.path))
                case nil where k == resolved.count: return .failure(.badLink(e.path))
                default: break
                }
            }
        }
        return .success(Listing(entries: entries, totalBytes: totalBytes, skipped: raws.count - kept.count))
    }

    /// A name's parts, or nil when one is empty, "." or "..", or the name is absolute. A folder's
    /// name ends in "/", and only a folder's.
    static func components(of name: String, isDirectory: Bool) -> [String]? {
        guard !name.hasPrefix("/") else { return nil }
        var parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if isDirectory { guard parts.last == "" else { return nil }; parts.removeLast() }
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return parts
    }

    /// A relative link `target` read from the folder `from` (its parts), as parts from the archive's
    /// root; nil when it is absolute or climbs above the root.
    static func resolve(_ target: String, from: [String]) -> [String]? {
        guard !target.isEmpty, !target.hasPrefix("/") else { return nil }
        var path = from
        for part in target.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                guard !path.isEmpty else { return nil }
                path.removeLast()
            default: path.append(String(part))
            }
        }
        return path.isEmpty ? nil : path
    }

    // MARK: Unpacking one entry

    /// Inflates `input` (raw deflate, the entry's bytes) and hands each piece to `write`, which says
    /// whether it was written. Refuses a stream that makes more than `size` bytes, ends short of it,
    /// or stops making progress. Returns the CRC-32 of what it made.
    static func inflate(_ input: UnsafeRawBufferPointer, size: Int, name: String,
                        write: (UnsafeRawBufferPointer) -> Bool) -> Result<UInt32, Problem> {
        guard let source = input.baseAddress?.assumingMemoryBound(to: UInt8.self), input.count > 0 else { return .failure(.inflate(name)) }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return .failure(.inflate(name))
        }
        defer { compression_stream_destroy(stream) }
        let chunk = 1 << 16
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { out.deallocate() }
        stream.pointee.src_ptr = source
        stream.pointee.src_size = input.count
        var produced = 0
        var crc: UInt32 = 0
        while true {
            let before = stream.pointee.src_size
            stream.pointee.dst_ptr = out
            stream.pointee.dst_size = chunk
            let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            let made = chunk - stream.pointee.dst_size
            if made > 0 {
                produced += made
                guard produced <= size else { return .failure(.inflate(name)) }
                let piece = UnsafeRawBufferPointer(start: out, count: made)
                crc = crc32(piece, crc)
                guard write(piece) else { return .failure(.writeFailed(name)) }
            }
            if status == COMPRESSION_STATUS_END { return produced == size ? .success(crc) : .failure(.inflate(name)) }
            guard status == COMPRESSION_STATUS_OK, made > 0 || stream.pointee.src_size < before else { return .failure(.inflate(name)) }
        }
    }

    // MARK: CRC-32 (the zip polynomial)

    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// The CRC-32 of `bytes`, continuing from `crc` (0 to start).
    static func crc32(_ bytes: UnsafeRawBufferPointer, _ crc: UInt32 = 0) -> UInt32 {
        var c = ~crc
        for byte in bytes { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }
}
