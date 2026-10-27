import AudioToolbox
import Foundation

/// The Mac's sound as AAC-ELD (docs/audio-plan.md §4.4): 48 kHz stereo Float32 in, one packet of
/// 480 or 512 frames out per block, at 128 kbps. AudioToolbox only (no CoreMedia, no AVFoundation),
/// so the encoder-free harness (Scripts/audio) and the `audio-codec` check link it.
///
/// One block in is one packet out: the converter takes exactly a packet's frames of new input for
/// each packet it makes, and delays its output by its priming (`priming`, 240 or 256 frames): packet
/// n of a segment decodes, on a fresh decoder, to input frames n·F − P to (n+1)·F − P − 1, the first
/// P of a segment being the codec's own. `reset()` (AudioConverterReset) drops what the converter
/// holds (at most F − 1 + P frames) and starts the next packet with the same priming: the plan's
/// probe, rerun on this Mac at the start of this step (H0).
///
/// Threads: every call on one queue (the pipeline's `sill.audio`); nothing here locks.
final class AudioEncoder {
    struct Failure: Error, CustomStringConvertible {
        let status: OSStatus
        let step: String
        var description: String { "\(step) failed (\(status)\(Self.fourCC(status)))" }
        /// OSStatus values that are four printable characters ('fmt?') read better that way.
        private static func fourCC(_ s: OSStatus) -> String {
            let v = UInt32(bitPattern: s)
            let bytes = [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
            guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "" }
            return ", '" + String(decoding: bytes, as: UTF8.self) + "'"
        }
    }

    static let sampleRate = 48_000.0
    static let channels = 2
    static let bitrate = 128_000

    /// The frames each packet decodes to (the converter's own figure, read back).
    let framesPerPacket: Int
    /// The codec's delay: the decoded frames a segment starts with that are not input.
    let priming: Int
    /// The magic cookie (AAC-ELD's AudioSpecificConfig), which the device's decoder needs.
    let cookie: Data
    /// The encoder's target, bits per second, as it reads back.
    let bitrate: Int

    private let converter: AudioConverterRef
    private let maxPacketBytes: Int
    private let output: UnsafeMutableRawPointer
    private let feed = Feed()

    /// A converter from interleaved stereo Float32 at 48 kHz to AAC-ELD at 48 kHz, `framesPerPacket`
    /// (480 or 512) frames a packet, `bitrate` bits a second.
    init(framesPerPacket: Int, bitrate: Int = AudioEncoder.bitrate) throws {
        let ch = UInt32(Self.channels)
        var input = AudioStreamBasicDescription(mSampleRate: Self.sampleRate, mFormatID: kAudioFormatLinearPCM,
                                                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                mBytesPerPacket: 4 * ch, mFramesPerPacket: 1, mBytesPerFrame: 4 * ch,
                                                mChannelsPerFrame: ch, mBitsPerChannel: 32, mReserved: 0)
        var out = AudioStreamBasicDescription()
        out.mFormatID = kAudioFormatMPEG4AAC_ELD
        out.mSampleRate = Self.sampleRate
        out.mChannelsPerFrame = ch
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &out)
        guard status == noErr else { throw Failure(status: status, step: "AAC-ELD's format") }
        out.mFramesPerPacket = UInt32(framesPerPacket)
        var made: AudioConverterRef?
        status = AudioConverterNew(&input, &out, &made)
        guard status == noErr, let converter = made else { throw Failure(status: status, step: "AudioConverterNew") }
        var rate = UInt32(bitrate)
        status = AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &rate)
        guard status == noErr else { AudioConverterDispose(converter); throw Failure(status: status, step: "the bitrate") }

        var got = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &got)
        guard status == noErr, got.mFramesPerPacket > 0 else {
            AudioConverterDispose(converter); throw Failure(status: status, step: "the output format")
        }
        var prime = AudioConverterPrimeInfo()
        size = UInt32(MemoryLayout<AudioConverterPrimeInfo>.size)
        status = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &size, &prime)
        guard status == noErr else { AudioConverterDispose(converter); throw Failure(status: status, step: "the priming") }
        var cookieSize: UInt32 = 0
        var cookie = Data()
        if AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookieSize, nil) == noErr, cookieSize > 0 {
            cookie = Data(count: Int(cookieSize))
            status = cookie.withUnsafeMutableBytes {
                AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookieSize, $0.baseAddress!)
            }
            guard status == noErr else { AudioConverterDispose(converter); throw Failure(status: status, step: "the magic cookie") }
            cookie = cookie.prefix(Int(cookieSize))
        }
        var maxPacket: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &maxPacket) != noErr || maxPacket == 0 {
            maxPacket = 8192
        }
        var readRate: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioConverterGetProperty(converter, kAudioConverterEncodeBitRate, &size, &readRate) != noErr { readRate = UInt32(bitrate) }

        self.converter = converter
        self.framesPerPacket = Int(got.mFramesPerPacket)
        self.priming = Int(prime.leadingFrames)
        self.cookie = cookie
        self.bitrate = Int(readRate)
        self.maxPacketBytes = Int(maxPacket)
        self.output = UnsafeMutableRawPointer.allocate(byteCount: Int(maxPacket), alignment: 16)
    }

    deinit {
        AudioConverterDispose(converter)
        output.deallocate()
    }

    /// One packet for exactly one block: `framesPerPacket` frames of interleaved stereo Float32.
    /// Nil for a block of another size, or when the converter makes nothing (it never has, in the
    /// probe or the checks).
    func encode(_ block: [Float]) -> Data? {
        guard block.count == framesPerPacket * Self.channels else { return nil }
        return block.withUnsafeBufferPointer { samples -> Data? in
            feed.samples = UnsafeRawPointer(samples.baseAddress)
            feed.frames = framesPerPacket
            defer { feed.samples = nil; feed.frames = 0 }
            var packets: UInt32 = 1
            var description = AudioStreamPacketDescription()
            var list = AudioBufferList(mNumberBuffers: 1,
                                       mBuffers: AudioBuffer(mNumberChannels: UInt32(Self.channels),
                                                             mDataByteSize: UInt32(maxPacketBytes), mData: output))
            let status = AudioConverterFillComplexBuffer(converter, Self.supply, Unmanaged.passUnretained(feed).toOpaque(),
                                                         &packets, &list, &description)
            guard status == noErr || status == Self.noMoreInput, packets == 1 else { return nil }
            return Data(bytes: output, count: Int(list.mBuffers.mDataByteSize))
        }
    }

    /// A new segment: what the converter holds (a partial packet's input and its lookahead) is
    /// dropped, and the next packet starts with the codec's priming again.
    func reset() {
        AudioConverterReset(converter)
    }

    /// The input proc's status once the block has been handed over: the converter returns what it
    /// made and keeps its state for the next call ('nomo', never a real AudioToolbox error).
    private static let noMoreInput: OSStatus = 0x6E6F_6D6F

    /// The block the input proc hands the converter, once.
    private final class Feed {
        var samples: UnsafeRawPointer?
        var frames = 0
    }

    private static let supply: AudioConverterComplexInputDataProc = { _, count, data, _, context in
        let feed = Unmanaged<Feed>.fromOpaque(context!).takeUnretainedValue()
        guard let samples = feed.samples, feed.frames > 0 else {
            count.pointee = 0
            return AudioEncoder.noMoreInput
        }
        let frames = min(Int(count.pointee), feed.frames)
        count.pointee = UInt32(frames)
        data.pointee.mNumberBuffers = 1
        data.pointee.mBuffers.mNumberChannels = UInt32(AudioEncoder.channels)
        data.pointee.mBuffers.mDataByteSize = UInt32(frames * AudioEncoder.channels * MemoryLayout<Float>.size)
        data.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: samples)
        feed.samples = samples.advanced(by: frames * AudioEncoder.channels * MemoryLayout<Float>.size)
        feed.frames -= frames
        return noErr
    }
}
