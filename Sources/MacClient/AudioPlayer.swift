import AVFoundation
import os
import StreamProtocol

/// The other Mac's sound (kind 33): the apps whose windows are open here, played on this Mac's
/// output. Packets of about 10 ms go into a short buffer that the engine pulls from: playback starts
/// once 40 ms are in and the buffer is cut back to 60 ms whenever it passes 150 ms, so the sound
/// never drifts behind the picture; an empty buffer plays silence. Play Sound in the status item
/// turns it off (the host then keeps the apps' sound). Packets arrive on the network queue.
final class AudioPlayer: @unchecked Sendable {
    static let defaultsKey = "SillClient.playSound"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) == nil || UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private let lock = OSAllocatedUnfairLock()
    private var buffer: [Float] = []       // interleaved
    private var readIndex = 0
    private var playing = false
    private var rate: Double = 0
    private var channels = 0
    private var engine: AVAudioEngine?

    private var buffered: Int { buffer.count - readIndex }   // samples; under the lock

    /// One kind 33 payload. Network queue.
    func receive(_ payload: Data) {
        guard let packet = AudioPacket.unpack(payload) else { return }
        if packet.sampleRate != rate || packet.channels != channels {
            let r = packet.sampleRate, c = packet.channels
            rate = r; channels = c
            DispatchQueue.main.async { [weak self] in self?.restart(rate: r, channels: c) }
        }
        let c = packet.channels, perMs = Int(packet.sampleRate / 1000) * c
        lock.withLock {
            if readIndex > 48_000 * 8 { buffer.removeFirst(readIndex); readIndex = 0 }
            buffer.append(contentsOf: packet.samples.lazy.map { Float($0) / 32767 })
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
