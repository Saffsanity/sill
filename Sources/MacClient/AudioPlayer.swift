import AVFoundation
import os
import StreamProtocol

/// The other Mac's sound (kind 33): the apps whose windows are open here, played on this Mac's
/// output. Packets of about 10 ms go into a short buffer that the engine pulls from: playback starts
/// once 40 ms are in and the buffer is cut back to 60 ms whenever it passes 150 ms, so the sound
/// never drifts behind the picture; an empty buffer plays silence. Play Sound in the status item
/// turns it off (the host then keeps the apps' sound). The sound comes compressed (AAC-ELD, about 96
/// kbit/s) unless `SillClient.plainAudio` is set; a host that cannot encode sends PCM, played as it
/// comes. Packets arrive on the network queue.
final class AudioPlayer: @unchecked Sendable {
    static let defaultsKey = "SillClient.playSound"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) == nil || UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// The codec asked for: AAC-ELD unless the default `SillClient.plainAudio` says plain PCM.
    static var codec: String? { UserDefaults.standard.bool(forKey: "SillClient.plainAudio") ? nil : AudioPacket.aacELD }

    private let lock = OSAllocatedUnfairLock()
    private var decoder: AACDecoder?
    private var buffer: [Float] = []       // interleaved
    private var readIndex = 0
    private var playing = false
    private var rate: Double = 0
    private var channels = 0
    private var engine: AVAudioEngine?

    private var buffered: Int { buffer.count - readIndex }   // samples; under the lock

    /// One kind 33 payload. Network queue.
    func receive(_ payload: Data) {
        if let e = AudioPacket.unpackEncoded(payload) {
            if decoder?.matches(rate: e.sampleRate, channels: e.channels, cookie: e.cookie) != true {
                decoder = AACDecoder(rate: e.sampleRate, channels: e.channels, cookie: e.cookie)
            }
            guard let samples = decoder?.decode(e.packet) else { return }
            append(samples, rate: e.sampleRate, channels: e.channels)
            return
        }
        guard let packet = AudioPacket.unpack(payload) else { return }
        append(packet.samples.map { Float($0) / 32767 }, rate: packet.sampleRate, channels: packet.channels)
    }

    /// Interleaved samples into the buffer the engine plays from. Network queue.
    private func append(_ samples: [Float], rate packetRate: Double, channels packetChannels: Int) {
        if packetRate != rate || packetChannels != channels {
            let r = packetRate, c = packetChannels
            rate = r; channels = c
            DispatchQueue.main.async { [weak self] in self?.restart(rate: r, channels: c) }
        }
        let c = packetChannels, perMs = Int(packetRate / 1000) * c
        lock.withLock {
            if readIndex > 48_000 * 8 { buffer.removeFirst(readIndex); readIndex = 0 }
            buffer.append(contentsOf: samples)
            if !playing, buffered >= 40 * perMs { playing = true }
            if buffered > 150 * perMs { readIndex = buffer.count - 60 * perMs }   // too far behind: catch up
        }
    }

    /// Stops playing and forgets what waited (a disconnect, Play Sound off).
    func stop() {
        engine?.stop()
        engine = nil
        lock.withLock { buffer.removeAll(); readIndex = 0; playing = false }
        rate = 0; channels = 0
    }

    private func restart(rate: Double, channels: Int) {
        engine?.stop()
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: false)
        else { return }
        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frames, list -> OSStatus in
            let out = UnsafeMutableAudioBufferListPointer(list)
            guard let self else { return noErr }
            self.lock.withLock {
                let n = Int(frames)
                for f in 0..<n {
                    let ready = self.playing && self.buffered >= channels
                    for c in 0..<min(channels, out.count) {
                        let dst = out[c].mData!.assumingMemoryBound(to: Float.self)
                        dst[f] = ready ? self.buffer[self.readIndex + c] : 0
                    }
                    if ready { self.readIndex += channels } else if self.playing { self.playing = false }   // ran dry: wait for 40 ms again
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
            print("audio: playing \(Int(rate)) Hz, \(channels) channel\(channels == 1 ? "" : "s")")
        } catch {
            print("audio: could not start (\(error))")
        }
    }
}

/// AAC-ELD packets back to interleaved float samples. Network queue.
private final class AACDecoder {
    private let converter: AVAudioConverter
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let rate: Double, channels: Int, cookie: Data

    init?(rate: Double, channels: Int, cookie: Data) {
        var desc = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatMPEG4AAC_ELD, mFormatFlags: 0,
                                               mBytesPerPacket: 0, mFramesPerPacket: 0, mBytesPerFrame: 0,
                                               mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &desc),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        converter.magicCookie = cookie
        self.input = input; self.output = output; self.converter = converter
        self.rate = rate; self.channels = channels; self.cookie = cookie
    }

    func matches(rate: Double, channels: Int, cookie: Data) -> Bool { rate == self.rate && channels == self.channels && cookie == self.cookie }

    func decode(_ packet: Data) -> [Float]? {
        let compressed = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: max(packet.count, 1))
        packet.withUnsafeBytes { compressed.data.copyMemory(from: $0.baseAddress!, byteCount: packet.count) }
        compressed.byteLength = UInt32(packet.count)
        compressed.packetCount = 1
        compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                              mDataByteSize: UInt32(packet.count))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 1024) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            if given { outStatus.pointee = .noDataNow; return nil }
            given = true
            outStatus.pointee = .haveData
            return compressed
        }
        guard status != .error, let data = pcm.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(pcm.frameLength) * channels))
    }
}
