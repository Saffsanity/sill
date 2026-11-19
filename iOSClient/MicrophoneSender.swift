import Foundation
import SillAudio
import StreamProtocol

/// This device's microphone on its way to the Mac (kind 48, docs/microphone-plan.md §3.4, §5.6): a capture
/// buffer's frames in (48 kHz mono 32-bit float, and the host time of the first), kind 48's messages out, each
/// stamped on the wall clock. SillAudio's packetizer cuts the frames into 10 ms blocks (a gap in the capture ends
/// a segment), its encoder makes one AAC-ELD packet of each (mono, 64 kbps), and the packets a buffer completes
/// go in one type 2 message (ten for a capture buffer's 100 ms), never split across a segment's start. A new
/// recording is a new epoch, which `start` gives the format of (type 1, to go before its first packet); the seq
/// counts packets through the epoch.
///
/// Stamps: a packet's is the capture time of its first decoded sample (the packetizer's host time) converted to
/// the wall clock by the offset the caller reads as it sends (`wallOffset`: an elapsed time, the privacy
/// manifest's reason 35F9.1), so the Mac's playout's floor needs nothing else (AudioPlayout, rule 1).
///
/// Threads: every call on one queue (the capture's `sill.mic`); nothing here locks. Pure: Foundation, SillAudio
/// and StreamProtocol, no AVFAudio, so it is checked on the Mac (Tests/checks/mic-send).
final class MicrophoneSender {
    /// The most packets one message carries: a capture buffer of 400 ms, the most a tap gives, is 40.
    static let maxPacketsPerMessage = 40

    private var encoder: AudioEncoder?
    private var packetizer: AudioPacketizer?
    /// The epoch of the recording, 0 to 65,535; the next recording's is one more, wrapping.
    private(set) var epoch: Int
    private var seq: UInt32 = 0
    /// The recording's format (its epoch, priming and cookie), nil while none runs: a move's new connection gets
    /// it again, so the Mac goes on with the same epoch.
    private(set) var format: MicrophoneFormat?
    /// Why the last `start` made no encoder, for the console.
    private(set) var failure: String?

    /// `lastEpoch`: the epoch before the first recording's (a random one, so two of this device's launches and
    /// two devices rarely meet the Mac with the same).
    init(lastEpoch: Int) { epoch = lastEpoch & 0xFFFF }

    /// A new recording: the next epoch and a fresh encoder; its format, to send before its packets, or nil when
    /// no encoder could be made (`failure` says why).
    func start() -> MicrophoneFormat? {
        do {
            let e = try AudioEncoder(framesPerPacket: MicrophoneCodec.framesPerPacket, bitrate: MicrophoneCodec.bitrate,
                                     channels: MicrophoneCodec.channels)
            epoch = (epoch + 1) & 0xFFFF
            seq = 0
            encoder = e
            packetizer = AudioPacketizer(framesPerPacket: e.framesPerPacket, priming: e.priming, channels: MicrophoneCodec.channels,
                                         sampleRate: Double(MicrophoneCodec.sampleRate))
            let f = MicrophoneFormat.epoch(epoch, primingFrames: e.priming, cookie: e.cookie, bitrate: e.bitrate, framesPerPacket: e.framesPerPacket)
            format = f.isValid ? f : nil
            failure = format == nil ? "the encoder's format is outside generation 1's bounds" : nil
            return format
        } catch {
            stop()
            failure = "\(error)"
            return nil
        }
    }

    /// The recording ends: what the encoder held is dropped.
    func stop() {
        encoder = nil
        packetizer = nil
        format = nil
    }

    /// One capture buffer: `samples` at 48 kHz, mono, from host time `hostTime` (seconds), with the wall clock
    /// `wallOffset` ahead of the host clock now. The messages it completes, in order; none while no recording runs.
    func push(_ samples: [Float], hostTime: Double, wallOffset: Double) -> [StreamMessage] {
        guard let encoder, var p = packetizer, !samples.isEmpty, hostTime.isFinite, wallOffset.isFinite else { return [] }
        let blocks = p.push(PCMChunk(samples: samples, channels: MicrophoneCodec.channels, sampleRate: Double(MicrophoneCodec.sampleRate),
                                     hostTime: hostTime))
        packetizer = p
        var out: [StreamMessage] = []
        var packets: [Data] = []
        var first: (seq: UInt32, stamp: Double, segmentStart: Bool)?
        func flush() {
            guard let f = first, !packets.isEmpty else { return }
            let message = AudioPackets(epoch: epoch, seq: f.seq, segmentStart: f.segmentStart, packets: packets)
            if let m = MicrophoneMessage.packetsMessage(message, captured: f.stamp) { out.append(m) }
            packets = []
            first = nil
        }
        for b in blocks {
            // A segment's first block: a clean start for the encoder. It is always a buffer's first block (the
            // packetizer starts a segment at the buffer after a gap), and every buffer starts its own message, so
            // the segment flag is its message's first packet's.
            if b.segmentStart { encoder.reset() }
            guard let packet = encoder.encode(b.samples) else { continue }
            if first == nil { first = (seq, b.hostTime + wallOffset, b.segmentStart) }
            packets.append(packet)
            seq &+= 1
            if packets.count == Self.maxPacketsPerMessage { flush() }
        }
        flush()
        return out
    }
}
