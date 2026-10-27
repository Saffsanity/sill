import Foundation

/// The test tone a synthetic host sends with the Desktop's test pattern (docs/audio-plan.md §4.2): a
/// steady 440 Hz at −30 dBFS in both channels, and a 4 ms Hann-windowed 2 kHz click at −6 dBFS that
/// starts at each whole second of the wall clock, as the packets' stamps will carry it. So a checker
/// needs nothing but the stamps to know where each click belongs, end to end (H4, H5).
///
/// Frame k of the tone is at wall time `wallAtFrame0 + k ÷ sampleRate`: the samples follow the frame
/// index, never the moment they are made, so a paused tone that goes on from where the clock is keeps
/// its clicks on whole seconds. Pure: Foundation only (the `audio-codec` check and the harness's
/// device, Scripts/audiocheck.swift, compile it too).
struct TestTone {
    static let pitch = 440.0
    static let level = -30.0
    static let clickPitch = 2_000.0
    static let clickLevel = -6.0
    /// 4 ms.
    static let clickSeconds = 0.004

    let sampleRate: Double
    /// The wall-clock time (seconds since 1970) of frame 0.
    let wallAtFrame0: Double
    /// 440 Hz; the harness gives a second source another, so a source change is heard.
    var pitch = TestTone.pitch

    static func amplitude(dBFS: Double) -> Double { pow(10, dBFS / 20) }

    /// `frames` interleaved stereo frames from frame `start` on.
    func samples(from start: Int, frames: Int) -> [Float] {
        let tone = Self.amplitude(dBFS: Self.level), click = Self.amplitude(dBFS: Self.clickLevel)
        let clickFrames = Self.clickSeconds * sampleRate
        var out = [Float](repeating: 0, count: max(0, frames) * 2)
        for i in 0..<max(0, frames) {
            let k = start + i
            // The phase from the frame index, reduced per second of frames so it stays exact for hours.
            let perSecond = Int(sampleRate)
            let within = Double(k % perSecond) + (k < 0 ? Double(perSecond) : 0)
            var v = tone * sin(2 * .pi * pitch * within / sampleRate)
            // Frames since the last whole second of the wall clock.
            let wall = wallAtFrame0 + Double(k) / sampleRate
            let into = (wall - wall.rounded(.down)) * sampleRate
            if into < clickFrames {
                v += click * Self.window(into / clickFrames) * sin(2 * .pi * Self.clickPitch * into / sampleRate)
            }
            out[2 * i] = Float(v)
            out[2 * i + 1] = Float(v)
        }
        return out
    }

    /// The click alone, one channel, from its first frame: what a checker correlates against.
    static func click(sampleRate: Double) -> [Float] {
        let n = Int((clickSeconds * sampleRate).rounded())
        let a = amplitude(dBFS: clickLevel)
        return (0..<n).map { i in
            let x = Double(i)
            return Float(a * window(x / Double(n)) * sin(2 * .pi * clickPitch * x / sampleRate))
        }
    }

    /// The Hann window over 0…1.
    private static func window(_ x: Double) -> Double { 0.5 - 0.5 * cos(2 * .pi * x) }
}
