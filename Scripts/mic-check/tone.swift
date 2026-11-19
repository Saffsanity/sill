import Foundation

// TEST ONLY (docs/microphone-plan.md §5.7): a device's microphone as a packets file for Scripts/sillclient.py's
// --mic. The host's test tone (Sources/SillHost/TestTone.swift: 440 Hz at −30 dBFS and a 4 ms 2 kHz click at
// −6 dBFS on each whole second of its own clock, frame 0 on one), its left channel alone, through SillAudio's
// packetizer and encoder as a device makes its microphone's: mono, 64 kbps, in a capture buffer's 4,800-frame
// chunks, one segment from frame 0. Compiled by build.sh with AudioEncoder.swift, AudioPacketizer.swift and
// TestTone.swift; AudioToolbox only.
//
//   tone OUT SECONDS
//
// The file: "SILLMIC1", then big endian UInt32 frames a packet, priming and bitrate, a UInt16 cookie length and
// the cookie, a UInt32 count, and each packet as a UInt16 length and its bytes. Packet n decodes to tone frames
// n × F − P on (the packetizer's stamps), so a client that puts frame 0 on a whole second of its clock stamps
// packet n at that second + (n × F − P) ÷ 48,000, and every click falls on a whole second.
let args = CommandLine.arguments
guard args.count == 3, let seconds = Double(args[2]), seconds > 0, seconds <= 900 else {
    FileHandle.standardError.write(Data("usage: tone OUT SECONDS (at most 900)\n".utf8)); exit(2)
}
let rate = 48_000.0
let chunk = 4_800
guard let enc = try? AudioEncoder(framesPerPacket: 480, bitrate: 64_000, channels: 1) else {
    FileHandle.standardError.write(Data("tone: no AAC-ELD encoder\n".utf8)); exit(1)
}
var packetizer = AudioPacketizer(framesPerPacket: enc.framesPerPacket, priming: enc.priming, channels: 1, sampleRate: rate)
let tone = TestTone(sampleRate: rate, wallAtFrame0: 0)
var packets: [Data] = []
for k in 0..<(Int(seconds * rate) / chunk) {
    let stereo = tone.samples(from: k * chunk, frames: chunk)
    let mono = stride(from: 0, to: stereo.count, by: 2).map { stereo[$0] }
    for b in packetizer.push(PCMChunk(samples: mono, channels: 1, sampleRate: rate, hostTime: Double(k * chunk) / rate)) {
        if b.segmentStart { enc.reset() }
        guard let p = enc.encode(b.samples) else { FileHandle.standardError.write(Data("tone: no packet\n".utf8)); exit(1) }
        packets.append(p)
    }
}
var d = Data("SILLMIC1".utf8)
func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).bigEndian) { d.append(contentsOf: $0) } }
func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).bigEndian) { d.append(contentsOf: $0) } }
u32(enc.framesPerPacket); u32(enc.priming); u32(enc.bitrate); u16(enc.cookie.count); d.append(enc.cookie); u32(packets.count)
for p in packets { u16(p.count); d.append(p) }
do { try d.write(to: URL(fileURLWithPath: args[1])) } catch { FileHandle.standardError.write(Data("tone: \(error)\n".utf8)); exit(1) }
let bytes = packets.reduce(0) { $0 + $1.count }
print("tone: \(packets.count) packets of \(enc.framesPerPacket) frames (priming \(enc.priming)), \(String(format: "%.1f", Double(bytes * 8) / seconds / 1000)) kbps, cookie \(enc.cookie.count) bytes: \(args[1])")
