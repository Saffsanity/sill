import Foundation

// The .DS_Store file Finder reads to lay out a folder's window: which view, the window's size and
// place, the background picture and where each icon sits. Scripts/make-dmg.sh writes one into
// Sill.dmg with this code instead of asking Finder to (AppleScript would need Automation
// permission, and Finder, to lay out a window, needs a logged-in session that shows it).
//
// The format is Apple's and undocumented; this follows the file Finder itself writes (a disk
// image's .DS_Store is one B-tree leaf, and Finder's own for such a folder is 10,244 bytes laid out
// exactly as `encode` lays it out) and the descriptions in Mac::Finder::DSStore's
// DSStoreFormat.pod and the ds_store Python package, whose layout Finder-made images share:
//
// - The file is a 4-byte 1, then a "buddy allocator" whose addresses count from byte 4. Its header,
//   at address 0, is "Bud1", the root block's address and size, the address again, and 16 bytes
//   Finder leaves as 00 00 10 0c and zeros.
// - Every block has a power-of-two size of at least 32 bytes, at an address that is a multiple of
//   its size, and is named by a 32-bit word: the address with the size's log2 in the low 5 bits.
// - The root block lists the blocks by number (in pages of 256 words), a table of contents that
//   names block 1 "DSDB", and the free lists: for each size 2^0 to 2^31, the addresses of the free
//   blocks of that size. The allocated and the free blocks cover the 2 GiB address space exactly.
// - "DSDB" is five words: the B-tree's root node (a block number), its levels below the root, the
//   number of records, the number of nodes and the page size, 4096.
// - A node is a word that is 0 for a leaf (else the last child's block number), a count, and the
//   records, sorted by file name without regard to case, then by code.
// - A record is its file name (a word counting UTF-16 units, then UTF-16BE), a four-character code
//   such as "Iloc", a four-character type and the value: "long" and "shor" 4 bytes, "bool" 1,
//   "type" 4, "comp" and "dutc" 8, "blob" a length and bytes, "ustr" a UTF-16 count and UTF-16BE.

/// One record: a file name ("." for the folder itself), a four-character code and a value.
struct DSRecord: Equatable, CustomStringConvertible {
    enum Value: Equatable {
        case long(UInt32)
        case shor(UInt16)
        case bool(Bool)
        case type(String)
        case comp(UInt64)
        case dutc(UInt64)
        case blob(Data)
        case ustr(String)
    }

    var name: String
    var code: String
    var value: Value

    var description: String {
        let shown: String
        switch value {
        case .long(let v): shown = "long \(v)"
        case .shor(let v): shown = "shor \(v)"
        case .bool(let v): shown = "bool \(v)"
        case .type(let v): shown = "type '\(v)'"
        case .comp(let v): shown = "comp \(v)"
        case .dutc(let v): shown = "dutc \(v)"
        case .blob(let v): shown = "blob \(v.count) bytes"
        case .ustr(let v): shown = "ustr \"\(v)\""
        }
        return "\"\(name)\" \(code) \(shown)"
    }
}

struct DSStoreError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum DSStore {
    /// Finder's page size, the size of every B-tree node.
    static let pageSize = 0x1000

    // Where encode puts the blocks: as Finder does for a folder with a few records.
    static let headerAddress = 0x0, headerSize = 0x20     // the "Bud1" header itself
    static let masterAddress = 0x40, masterSize = 0x20    // "DSDB", block 1
    static let leafAddress = 0x1000                       // the one node, block 2, a page
    static let rootAddress = 0x2000, rootSize = 0x800     // the allocator's root block, block 0

    /// Whether `a` sorts before `b` in a .DS_Store: by file name without regard to case (as Finder
    /// compares names on a case-insensitive volume), then by code.
    static func precedes(_ a: DSRecord, _ b: DSRecord) -> Bool {
        let an = Array(a.name.lowercased().utf16), bn = Array(b.name.lowercased().utf16)
        if an != bn { return an.lexicographicallyPrecedes(bn) }
        return Array(a.code.utf8).lexicographicallyPrecedes(Array(b.code.utf8))
    }

    /// A whole .DS_Store holding `records` (in any order) in one leaf node.
    static func encode(_ records: [DSRecord]) throws -> Data {
        let sorted = records.sorted(by: precedes)
        for (a, b) in zip(sorted, sorted.dropFirst()) where !precedes(a, b) {
            throw DSStoreError("two records for \"\(a.name)\" \(a.code)")
        }

        var leaf = Data()
        leaf.appendWord(0)                         // a leaf: no children
        leaf.appendWord(UInt32(sorted.count))
        for record in sorted { try leaf.appendRecord(record) }
        guard leaf.count <= pageSize else {
            throw DSStoreError("the records take \(leaf.count) bytes, more than one \(pageSize)-byte node; this writer makes only one")
        }

        var master = Data()
        master.appendWord(2)                       // the root node: block 2
        master.appendWord(0)                       // no levels below it
        master.appendWord(UInt32(sorted.count))
        master.appendWord(1)                       // one node
        master.appendWord(UInt32(pageSize))

        let allocated = [
            (address: headerAddress, size: headerSize), (address: masterAddress, size: masterSize),
            (address: leafAddress, size: pageSize), (address: rootAddress, size: rootSize),
        ]
        var root = Data()
        let blocks = [(rootAddress, rootSize), (masterAddress, masterSize), (leafAddress, pageSize)]
        root.appendWord(UInt32(blocks.count))
        root.appendWord(0)
        for index in 0..<256 {
            if index < blocks.count {
                root.appendWord(UInt32(blocks[index].0) | UInt32(log2(blocks[index].1)))
            } else {
                root.appendWord(0)
            }
        }
        root.appendWord(1)                         // the table of contents: one name
        root.append(4)
        root.append(contentsOf: Array("DSDB".utf8))
        root.appendWord(1)                         // "DSDB" is block 1
        let free = freeLists(allocated: allocated)
        for width in 0..<32 {
            root.appendWord(UInt32(free[width].count))
            for address in free[width] { root.appendWord(UInt32(address)) }
        }
        guard root.count <= rootSize else { throw DSStoreError("the root block takes \(root.count) bytes") }

        var file = Data(count: 4 + rootAddress + rootSize)
        file.replace(at: 0, with: word(1))
        var header = Data("Bud1".utf8)
        header.appendWord(UInt32(rootAddress))
        header.appendWord(UInt32(rootSize))
        header.appendWord(UInt32(rootAddress))
        header.append(contentsOf: [0, 0, 0x10, 0x0c] + [UInt8](repeating: 0, count: 12))
        file.replace(at: 4 + headerAddress, with: header)
        file.replace(at: 4 + masterAddress, with: master)
        file.replace(at: 4 + leafAddress, with: leaf)
        file.replace(at: 4 + rootAddress, with: root)
        return file
    }

    /// The free blocks a buddy allocator has around `allocated`, by width (log2 of the size): the
    /// largest aligned blocks of the 2^31-byte space that hold no allocated byte.
    static func freeLists(allocated: [(address: Int, size: Int)]) -> [[Int]] {
        var lists = [[Int]](repeating: [], count: 32)
        func visit(_ address: Int, _ width: Int) {
            let size = 1 << width, end = address + size
            let overlapping = allocated.filter { $0.address < end && address < $0.address + $0.size }
            if overlapping.isEmpty {
                lists[width].append(address)
            } else if overlapping.count == 1, overlapping[0].address == address, overlapping[0].size == size {
                return
            } else if width > 5 {
                visit(address, width - 1)
                visit(address + size / 2, width - 1)
            }
        }
        visit(0, 31)
        return lists.map { $0.sorted() }
    }

    /// The records of a .DS_Store, in the order the file keeps them, whatever its shape.
    static func decode(_ data: Data) throws -> [DSRecord] {
        var reader = ByteReader(data)
        guard try reader.word(at: 0) == 1, try reader.bytes(at: 4, count: 4) == Data("Bud1".utf8) else {
            throw DSStoreError("not a .DS_Store (no \"Bud1\" header)")
        }
        let rootOffset = Int(try reader.word(at: 8)), rootLength = Int(try reader.word(at: 12))
        guard try reader.word(at: 16) == UInt32(rootOffset) else { throw DSStoreError("the header's two root addresses differ") }
        reader.position = 4 + rootOffset
        let blockCount = Int(try reader.nextWord())
        _ = try reader.nextWord()
        var blocks: [UInt32] = []
        for index in 0..<((blockCount + 255) / 256 * 256) {
            let word = try reader.nextWord()
            if index < blockCount { blocks.append(word) }
        }
        var contents: [String: UInt32] = [:]
        for _ in 0..<(try reader.nextWord()) {
            let length = Int(try reader.nextByte())
            let name = String(decoding: try reader.next(length), as: UTF8.self)
            contents[name] = try reader.nextWord()
        }
        guard reader.position <= 4 + rootOffset + rootLength else { throw DSStoreError("the root block's table of contents runs past its end") }
        guard let masterBlock = contents["DSDB"] else { throw DSStoreError("no DSDB in the table of contents") }

        func blockOffset(_ number: UInt32) throws -> Int {
            guard Int(number) < blocks.count else { throw DSStoreError("no block \(number)") }
            return 4 + Int(blocks[Int(number)] & ~0x1f)
        }
        let rootNode = try reader.word(at: try blockOffset(masterBlock))
        var records: [DSRecord] = []
        var visited = Set<UInt32>()
        func walk(_ node: UInt32) throws {
            guard visited.insert(node).inserted else { throw DSStoreError("the B-tree visits node \(node) twice") }
            reader.position = try blockOffset(node)
            let last = try reader.nextWord()
            let count = try reader.nextWord()
            var children: [UInt32] = []
            var own: [DSRecord] = []
            for _ in 0..<count {
                if last != 0 { children.append(try reader.nextWord()) }
                own.append(try reader.nextRecord())
            }
            // Children come before their separating record, so read this node's records first,
            // then walk (walking moves the reader).
            for (index, record) in own.enumerated() {
                if last != 0 { try walk(children[index]) }
                records.append(record)
            }
            if last != 0 { try walk(last) }
        }
        try walk(rootNode)
        return records
    }

    static func log2(_ size: Int) -> Int { size.trailingZeroBitCount }
    static func word(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
}

extension Data {
    mutating func appendWord(_ value: UInt32) { append(DSStore.word(value)) }

    mutating func replace(at offset: Int, with bytes: Data) {
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    mutating func appendUTF16(_ string: String) {
        for unit in string.utf16 {
            append(UInt8(unit >> 8))
            append(UInt8(unit & 0xff))
        }
    }

    mutating func appendRecord(_ record: DSRecord) throws {
        guard record.code.utf8.count == 4, record.code.allSatisfy(\.isASCII) else {
            throw DSStoreError("\"\(record.code)\" is not a four-character code")
        }
        appendWord(UInt32(record.name.utf16.count))
        appendUTF16(record.name)
        append(contentsOf: Array(record.code.utf8))
        switch record.value {
        case .long(let v): append(contentsOf: Array("long".utf8)); appendWord(v)
        case .shor(let v): append(contentsOf: Array("shor".utf8)); appendWord(UInt32(v))
        case .bool(let v): append(contentsOf: Array("bool".utf8)); append(v ? 1 : 0)
        case .type(let v):
            guard v.utf8.count == 4 else { throw DSStoreError("\"\(v)\" is not a four-character type") }
            append(contentsOf: Array("type".utf8)); append(contentsOf: Array(v.utf8))
        case .comp(let v): append(contentsOf: Array("comp".utf8)); appendWord(UInt32(v >> 32)); appendWord(UInt32(v & 0xffff_ffff))
        case .dutc(let v): append(contentsOf: Array("dutc".utf8)); appendWord(UInt32(v >> 32)); appendWord(UInt32(v & 0xffff_ffff))
        case .blob(let v): append(contentsOf: Array("blob".utf8)); appendWord(UInt32(v.count)); append(v)
        case .ustr(let v): append(contentsOf: Array("ustr".utf8)); appendWord(UInt32(v.utf16.count)); appendUTF16(v)
        }
    }
}

/// Big-endian reads from a Data, each checked against its end.
struct ByteReader {
    let data: Data
    var position = 0

    init(_ data: Data) { self.data = Data(data) }   // a copy, so indices start at 0

    func bytes(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset + count <= data.count else {
            throw DSStoreError("the file ends before byte \(offset + count)")
        }
        return data.subdata(in: offset..<(offset + count))
    }

    func word(at offset: Int) throws -> UInt32 {
        try bytes(at: offset, count: 4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    func half(at offset: Int) throws -> Int16 {
        Int16(bitPattern: try bytes(at: offset, count: 2).reduce(UInt16(0)) { $0 << 8 | UInt16($1) })
    }

    mutating func next(_ count: Int) throws -> Data {
        let result = try bytes(at: position, count: count)
        position += count
        return result
    }

    mutating func nextByte() throws -> UInt8 { try next(1)[0] }
    mutating func nextWord() throws -> UInt32 { try next(4).reduce(0) { $0 << 8 | UInt32($1) } }

    mutating func nextUTF16(_ units: Int) throws -> String {
        let raw = try next(units * 2)
        let codeUnits = stride(from: 0, to: raw.count, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
        return String(decoding: codeUnits, as: UTF16.self)
    }

    mutating func nextRecord() throws -> DSRecord {
        let name = try nextUTF16(Int(try nextWord()))
        let code = String(decoding: try next(4), as: UTF8.self)
        let type = String(decoding: try next(4), as: UTF8.self)
        let value: DSRecord.Value
        switch type {
        case "long": value = .long(try nextWord())
        case "shor": value = .shor(UInt16(truncatingIfNeeded: try nextWord()))
        case "bool": value = .bool(try nextByte() != 0)
        case "type": value = .type(String(decoding: try next(4), as: UTF8.self))
        case "comp": value = .comp(UInt64(try nextWord()) << 32 | UInt64(try nextWord()))
        case "dutc": value = .dutc(UInt64(try nextWord()) << 32 | UInt64(try nextWord()))
        case "blob": value = .blob(try next(Int(try nextWord())))
        case "ustr": value = .ustr(try nextUTF16(Int(try nextWord())))
        default: throw DSStoreError("record \"\(name)\" \(code) has the unknown type \"\(type)\"")
        }
        return DSRecord(name: name, code: code, value: value)
    }
}
