import Foundation

/// Wire format shared by the Mac host and the iOS client.
/// Header (14 bytes, big endian): kind(1) timestamp(8, Double) isKeyframe(1) payloadLength(4)
public enum StreamMessageKind: UInt8 {
    case parameterSets = 0   // payload: ParameterSets.encoded()
    case frame = 1           // payload: one HEVC access unit, length-prefixed NALs (hvcC style)
}

public struct StreamHeader {
    public let kind: StreamMessageKind
    public let timestamp: Double      // host wall clock, seconds since 1970 (approximate cross-device)
    public let isKeyframe: Bool
    public let payloadLength: Int
}

public struct StreamMessage {
    public static let headerLength = 14

    public var kind: StreamMessageKind
    public var timestamp: Double
    public var isKeyframe: Bool
    public var payload: Data

    public init(kind: StreamMessageKind, timestamp: Double, isKeyframe: Bool, payload: Data) {
        self.kind = kind
        self.timestamp = timestamp
        self.isKeyframe = isKeyframe
        self.payload = payload
    }

    public func serialized() -> Data {
        var d = Data(capacity: Self.headerLength + payload.count)
        d.append(kind.rawValue)
        d.appendBigEndian(timestamp.bitPattern)
        d.append(isKeyframe ? 1 : 0)
        d.appendBigEndian(UInt32(payload.count))
        d.append(payload)
        return d
    }

    public static func parseHeader(_ data: Data) -> StreamHeader? {
        guard data.count >= headerLength, let kind = StreamMessageKind(rawValue: data[data.startIndex]) else { return nil }
        let ts = Double(bitPattern: data.readBigEndian(UInt64.self, at: 1))
        let key = data[data.startIndex + 9] == 1
        let len = Int(data.readBigEndian(UInt32.self, at: 10))
        return StreamHeader(kind: kind, timestamp: ts, isKeyframe: key, payloadLength: len)
    }
}

/// HEVC VPS/SPS/PPS as delivered by VideoToolbox, plus the NAL length-prefix size (normally 4).
public struct ParameterSets {
    public var nalUnitHeaderLength: Int
    public var sets: [Data]

    public init(nalUnitHeaderLength: Int, sets: [Data]) {
        self.nalUnitHeaderLength = nalUnitHeaderLength
        self.sets = sets
    }

    /// nalLen(1) count(1) then per set: length(2) bytes
    public func encoded() -> Data {
        var d = Data()
        d.append(UInt8(nalUnitHeaderLength))
        d.append(UInt8(sets.count))
        for s in sets {
            d.appendBigEndian(UInt16(s.count))
            d.append(s)
        }
        return d
    }

    public init?(encoded d: Data) {
        guard d.count >= 2 else { return nil }
        nalUnitHeaderLength = Int(d[d.startIndex])
        let count = Int(d[d.startIndex + 1])
        var offset = 2
        var result: [Data] = []
        for _ in 0..<count {
            guard d.count >= offset + 2 else { return nil }
            let len = Int(d.readBigEndian(UInt16.self, at: offset))
            offset += 2
            guard d.count >= offset + len else { return nil }
            result.append(d.subdata(in: (d.startIndex + offset)..<(d.startIndex + offset + len)))
            offset += len
        }
        sets = result
    }
}

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var v = value.bigEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readBigEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var v: T = 0
        let start = startIndex + offset
        _ = Swift.withUnsafeMutableBytes(of: &v) { dst in
            copyBytes(to: dst, from: start..<(start + MemoryLayout<T>.size))
        }
        return T(bigEndian: v)
    }
}
