import Foundation

// The Mac's sound on its way to the encoder (docs/audio-plan.md §4.3): the chunks of PCM a source
// delivers become blocks of exactly one packet's frames, each stamped with the host time of the
// sample its packet decodes to first, and a gap in the capture ends a segment. What the host does
// around it (which source it follows, how a delivered buffer becomes interleaved stereo, the first
// minute's tally) is its own: Sources/SillHost/AudioSourceRule.swift.
//
// Pure: Foundation only, so it is checked on its own with swiftc (Tests/checks/audio-packetizer).
// Public: SillAudio, which SillHostCore and the iOS app both link. Every time here is seconds of the
// host clock (mach absolute time, the clock ScreenCaptureKit stamps its buffers with); the pipeline
// turns a block's into the wall clock as it sends it.

/// PCM from a source: interleaved Float32 frames, and the host time of the first.
public struct PCMChunk {
    /// `frames × channels` samples, interleaved.
    public var samples: [Float]
    public var channels: Int
    public var sampleRate: Double
    /// Seconds of the host clock (mach absolute time) of its first frame.
    public var hostTime: Double

    public var frames: Int { channels > 0 ? samples.count / channels : 0 }

    public init(samples: [Float], channels: Int, sampleRate: Double, hostTime: Double) {
        self.samples = samples
        self.channels = channels
        self.sampleRate = sampleRate
        self.hostTime = hostTime
    }
}

/// Exactly one packet's frames, for the encoder.
public struct AudioBlock {
    /// `framesPerPacket × channels` samples, interleaved.
    public var samples: [Float]
    /// Its number in its segment, from 0.
    public var index: Int
    /// The first block of a segment: the encoder starts clean (AudioConverterReset) before it, and
    /// its packet carries the segment flag, so the device drops the codec's priming.
    public var segmentStart: Bool
    /// The host time of segment frame `index × framesPerPacket − priming`: the input frame the
    /// packet's first decoded sample is (the codec delays its output by `priming` frames, and hands
    /// the priming out rather than trimming it), from the anchor of the chunk it falls in.
    public var hostTime: Double
}

/// Chunks in, blocks out, for one epoch (one encoder: one packet size, one priming, one format).
///
/// Continuity: a chunk is expected where the one before it ended (its time + its frames ÷ the rate).
/// Within a quarter of a chunk of that (2.5 ms for 480 frames, 5.3 ms for 1024), it is appended as it
/// is: that is time stamp jitter, so the stamps follow each chunk's own anchor and the samples never
/// move. A lost buffer is a whole chunk late, so none hides in the tolerance. Anything else, later or
/// earlier, ends the segment where it is, and a new one starts at this chunk: what was still short
/// of a block is dropped, never flushed, padded or filled with zeros (a packet made now for frames of
/// a gap ago would reach the device late by the gap, and raise its jitter cover for 10 s as if the
/// link had jittered), and the encoder is reset before the new segment's first block, which drops
/// what it held too (its lookahead). The device fades the old segment out and places the new one by
/// its stamp.
///
/// Each block goes out with the chunk that completes it; a gap emits nothing.
public struct AudioPacketizer {
    public let framesPerPacket: Int
    public let priming: Int
    public let channels: Int
    public let sampleRate: Double

    /// Segments begun after a gap (a chunk late or early), for `aud.gap`.
    public private(set) var gaps = 0

    /// What is not yet a whole block, interleaved; `buffered` frames.
    private var fifo: [Float] = []
    /// Each chunk's first frame (its number in the segment) and its host time, oldest first; only
    /// those the next stamps can still need are kept.
    private var anchors: [(frame: Int, time: Double)] = []
    /// Frames of this segment appended so far, and blocks made of them.
    private var segmentFrames = 0
    private var blocksMade = 0
    /// Where the next chunk is expected; nil before the first.
    private var expected: Double?

    /// 512 when the first chunk's frames are a whole number of 512-frame packets, else 480: the
    /// packet that divides the capture's chunks is 9–10 ms faster end to end (docs/audio-plan.md,
    /// "Which codec: measured").
    public static func packetSize(firstChunkFrames frames: Int) -> Int {
        frames > 0 && frames % 512 == 0 ? 512 : 480
    }

    public init(framesPerPacket: Int, priming: Int, channels: Int, sampleRate: Double) {
        self.framesPerPacket = framesPerPacket
        self.priming = priming
        self.channels = channels
        self.sampleRate = sampleRate
    }

    /// The chunk is of this epoch's format (its rate and channels); another format is a new epoch
    /// (a new encoder), which the pipeline starts.
    public func takes(_ chunk: PCMChunk) -> Bool {
        chunk.channels == channels && chunk.sampleRate == sampleRate
    }

    /// The blocks this chunk completes, in order. A chunk of another format, or of no frames, is
    /// ignored (`takes`).
    public mutating func push(_ chunk: PCMChunk) -> [AudioBlock] {
        let frames = chunk.frames
        guard frames > 0, takes(chunk) else { return [] }
        let tolerance = 0.25 * Double(frames) / sampleRate
        if let expected, abs(chunk.hostTime - expected) <= tolerance {
            // Contiguous: appended as it is.
        } else {
            if expected != nil { gaps += 1 }
            fifo.removeAll(keepingCapacity: true)
            anchors.removeAll(keepingCapacity: true)
            segmentFrames = 0
            blocksMade = 0
        }
        anchors.append((segmentFrames, chunk.hostTime))
        fifo.append(contentsOf: chunk.samples.prefix(frames * channels))
        segmentFrames += frames
        expected = chunk.hostTime + Double(frames) / sampleRate

        var blocks: [AudioBlock] = []
        let blockSamples = framesPerPacket * channels
        while fifo.count >= blockSamples {
            let index = blocksMade
            blocks.append(AudioBlock(samples: Array(fifo[0..<blockSamples]), index: index, segmentStart: index == 0,
                                     hostTime: time(ofFrame: index * framesPerPacket - priming)))
            fifo.removeFirst(blockSamples)
            blocksMade += 1
        }
        // The next stamp is of frame `blocksMade × F − P`: every anchor before the one it falls in goes.
        let next = blocksMade * framesPerPacket - priming
        while anchors.count >= 2, anchors[1].frame <= next { anchors.removeFirst() }
        return blocks
    }

    /// The host time of segment frame `frame`, from the anchor of the chunk it falls in, or from the
    /// first chunk's before it (a segment's first packets start `priming` frames before its first
    /// captured frame).
    private func time(ofFrame frame: Int) -> Double {
        var anchor = anchors[0]
        for a in anchors.dropFirst() where a.frame <= frame { anchor = a }
        return anchor.time + Double(frame - anchor.frame) / sampleRate
    }
}
