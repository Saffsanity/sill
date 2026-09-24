import CoreGraphics

/// The host's knobs, as one value. The CLI streams with `standard` (plus its --virtual-display
/// flag); the menu bar app starts from the same values and lets Settings change them while it
/// runs. Change `standard`, rebuild, measure: both pick it up.
///
/// The coordinator takes a new value only between pipelines (inside `select`), so one pipeline
/// never mixes two settings. See `StreamCoordinator.setTarget`.
package struct HostConfig: Equatable, Sendable {
    /// Ceiling for the stream rate; each device asks for its own panel's rate (60 until it does).
    package var maxFPS: Int
    /// 2 = Retina capture, 1 = points (much cheaper).
    package var captureScale: CGFloat
    /// Bits per second per 60 fps; a faster stream gets proportionally more.
    package var bitrate: Int
    /// Apple: trades quality for encode speed; try after the baseline.
    package var prioritizeSpeed: Bool
    /// A picked window streams from its own HiDPI virtual display (see VirtualStage). Needs the
    /// AppKit event loop, so the CLI turns it on only with --virtual-display.
    package var virtualDisplay: Bool

    package init(maxFPS: Int, captureScale: CGFloat, bitrate: Int, prioritizeSpeed: Bool, virtualDisplay: Bool) {
        self.maxFPS = maxFPS
        self.captureScale = captureScale
        self.bitrate = bitrate
        self.prioritizeSpeed = prioritizeSpeed
        self.virtualDisplay = virtualDisplay
    }

    /// The spike's knobs, formerly the `let`s at the top of the CLI's main.swift, and the app's
    /// defaults. Virtual display off in both until Noah flips it.
    package static let standard = HostConfig(maxFPS: 120, captureScale: 2, bitrate: 15_000_000,
                                             prioritizeSpeed: false, virtualDisplay: false)

    /// Within what the pipeline supports: 24…120 fps, Retina or points, 1–100 Mbps per 60 fps.
    /// A hand-edited default or a launch argument can hold anything.
    package func validated() -> HostConfig {
        var c = self
        c.maxFPS = min(max(maxFPS, 24), 120)
        c.captureScale = captureScale >= 1.5 ? 2 : 1
        c.bitrate = min(max(bitrate, 1_000_000), 100_000_000)
        return c
    }

    /// What differs from `new`, for the log: "frame rate limit 120 → 60 fps, bitrate 15 → 8 Mbps
    /// per 60 fps, Retina → points, speed off → on, virtual display off → on".
    package func changes(to new: HostConfig) -> String {
        func onOff(_ b: Bool) -> String { b ? "on" : "off" }
        func scaleName(_ s: CGFloat) -> String { s >= 1.5 ? "Retina" : "points" }
        var parts: [String] = []
        if maxFPS != new.maxFPS { parts.append("frame rate limit \(maxFPS) → \(new.maxFPS) fps") }
        if bitrate != new.bitrate { parts.append("bitrate \(Self.mbps(bitrate)) → \(Self.mbps(new.bitrate)) Mbps per 60 fps") }
        if captureScale != new.captureScale { parts.append("\(scaleName(captureScale)) → \(scaleName(new.captureScale))") }
        if prioritizeSpeed != new.prioritizeSpeed { parts.append("speed \(onOff(prioritizeSpeed)) → \(onOff(new.prioritizeSpeed))") }
        if virtualDisplay != new.virtualDisplay { parts.append("virtual display \(onOff(virtualDisplay)) → \(onOff(new.virtualDisplay))") }
        return parts.isEmpty ? "no change" : parts.joined(separator: ", ")
    }

    /// "15", or "8.5" for a bitrate that is not whole megabits.
    package static func mbps(_ bitsPerSecond: Int) -> String {
        bitsPerSecond % 1_000_000 == 0 ? "\(bitsPerSecond / 1_000_000)"
                                       : String(format: "%.1f", Double(bitsPerSecond) / 1_000_000)
    }
}
