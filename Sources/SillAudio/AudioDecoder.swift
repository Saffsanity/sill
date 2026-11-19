import AudioToolbox
#if os(iOS)
import CoreAudio   // UnsafeMutableAudioBufferListPointer, which AudioToolbox brings with it on macOS only
#endif
import Foundation

/// The Mac's sound, decoded (docs/audio-plan.md §7.3): AAC-ELD packets in, 48 kHz stereo Float32 out,
/// a buffer per channel (the format AVAudioPlayerNode plays), one packet at a time; and a device's
/// microphone on the Mac, mono (`channels` at init; docs/microphone-plan.md §3.4), whose one buffer comes
/// back as both. AudioToolbox
/// only, so the host's `audio-codec` check and the harness's device (Scripts/audiocheck.swift) compile
/// it as it is; it knows nothing of the wire (the caller reads the format message's codec, packet
/// size and cookie).
///
/// A fresh or reset decoder decodes packet n of a segment to its frames n·F to (n+1)·F − 1, the first
/// `primingFrames` of a segment being the codec's own. One that starts in the middle of a segment
/// (a device joining, the packet after a gap) decodes its first packet to noise (−5 to −6 dB against
/// the signal), its second within −41 dB and its fourth exactly (the plan's probe): the caller drops
/// the first and fades in the next.
///
/// Threads: every call on one queue; nothing here locks. Public: SillAudio, which SillHostCore and the
/// iOS app both link.
public final class AudioDecoder {
    public struct Failure: Error, CustomStringConvertible {
        public let status: OSStatus
        public let step: String
        public var description: String { "\(step) failed (\(status))" }
    }

    /// The codecs this decoder plays, as the wire names them (StreamProtocol's AudioCodec.aacELD).
    public static let codecs = ["aac-eld"]
    public static let sampleRate = 48_000.0
    /// The Mac's sound's: stereo.
    public static let channels = 2

    public let framesPerPacket: Int
    /// The packets' channels (1 or 2).
    public let channels: Int

    private let converter: AudioConverterRef
    private let feed = Feed()
    private let list: UnsafeMutableAudioBufferListPointer
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>

    /// A decoder for AAC-ELD at 48 kHz, `channels` of them (1 or 2), `framesPerPacket` frames a packet, with
    /// the encoder's magic cookie (its AudioSpecificConfig).
    public init(framesPerPacket: Int, cookie: Data, channels: Int = AudioDecoder.channels) throws {
        guard (1...8192).contains(framesPerPacket) else { throw Failure(status: -50, step: "the packet size") }
        guard channels == 1 || channels == 2 else { throw Failure(status: -50, step: "the channel count") }
        var input = AudioStreamBasicDescription()
        input.mFormatID = kAudioFormatMPEG4AAC_ELD
        input.mSampleRate = Self.sampleRate
        input.mChannelsPerFrame = UInt32(channels)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &input)
        guard status == noErr else { throw Failure(status: status, step: "AAC-ELD's format") }
        input.mFramesPerPacket = UInt32(framesPerPacket)
        var output = AudioStreamBasicDescription(mSampleRate: Self.sampleRate, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                                                 mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                                 mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var made: AudioConverterRef?
        status = AudioConverterNew(&input, &output, &made)
        guard status == noErr, let converter = made else { throw Failure(status: status, step: "AudioConverterNew") }
        if !cookie.isEmpty {
            status = cookie.withUnsafeBytes {
                AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, UInt32(cookie.count), $0.baseAddress!)
            }
            guard status == noErr else { AudioConverterDispose(converter); throw Failure(status: status, step: "the magic cookie") }
        }
        self.converter = converter
        self.framesPerPacket = framesPerPacket
        self.channels = channels
        feed.channels = channels
        left = .allocate(capacity: framesPerPacket)
        right = .allocate(capacity: framesPerPacket)
        list = AudioBufferList.allocate(maximumBuffers: channels)
    }

    deinit {
        AudioConverterDispose(converter)
        left.deallocate()
        right.deallocate()
        free(list.unsafeMutablePointer)
    }

    /// One packet's frames, a buffer per channel: `framesPerPacket` of them from a packet the decoder
    /// can use; a mono decoder's one buffer as both. Nil when the converter made nothing (a packet it
    /// refused).
    public func decode(_ packet: Data) -> (left: [Float], right: [Float])? {
        guard !packet.isEmpty else { return nil }
        return packet.withUnsafeBytes { bytes -> (left: [Float], right: [Float])? in
            feed.packet = bytes.baseAddress
            feed.bytes = bytes.count
            defer { feed.packet = nil; feed.bytes = 0 }
            let byteCount = UInt32(framesPerPacket * MemoryLayout<Float>.size)
            list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: byteCount, mData: left)
            if channels > 1 { list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: byteCount, mData: right) }
            var frames = UInt32(framesPerPacket)
            let status = AudioConverterFillComplexBuffer(converter, Self.supply, Unmanaged.passUnretained(feed).toOpaque(),
                                                         &frames, list.unsafeMutablePointer, nil)
            guard status == noErr || status == Self.noMoreInput, frames > 0 else { return nil }
            let n = Int(frames)
            let l = Array(UnsafeBufferPointer(start: left, count: n))
            return (l, channels > 1 ? Array(UnsafeBufferPointer(start: right, count: n)) : l)
        }
    }

    /// The next packet decodes as on a fresh decoder (a new segment, the packet after a gap).
    public func reset() {
        AudioConverterReset(converter)
    }

    /// The input proc's status once the packet has been handed over ('nomo', never a real error).
    private static let noMoreInput: OSStatus = 0x6E6F_6D6F

    /// The packet the input proc hands the converter, once, with its description: memory of its own,
    /// since the converter reads the description after the proc returns.
    private final class Feed {
        var packet: UnsafeRawPointer?
        var bytes = 0
        var channels = AudioDecoder.channels
        let description = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        deinit { description.deallocate() }
    }

    private static let supply: AudioConverterComplexInputDataProc = { _, count, data, descriptions, context in
        let feed = Unmanaged<Feed>.fromOpaque(context!).takeUnretainedValue()
        guard let packet = feed.packet, feed.bytes > 0 else {
            count.pointee = 0
            return AudioDecoder.noMoreInput
        }
        count.pointee = 1
        data.pointee.mNumberBuffers = 1
        data.pointee.mBuffers.mNumberChannels = UInt32(feed.channels)
        data.pointee.mBuffers.mDataByteSize = UInt32(feed.bytes)
        data.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: packet)
        feed.description.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(feed.bytes))
        descriptions?.pointee = feed.description
        feed.packet = nil
        feed.bytes = 0
        return noErr
    }
}
