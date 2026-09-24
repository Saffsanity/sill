import CoreGraphics

/// The host's knobs, as one value. The CLI streams with `standard` (plus its --virtual-display and
/// --direct-wireless flags); the menu bar app starts from the same values and lets Settings change
/// them while it runs. Change `standard`, rebuild, measure: both pick it up.
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
    /// Direct Wireless Connection: peer-to-peer Wi-Fi (AWDL) on the listener and its Bonjour
    /// registration, so a device with no network in common can find and reach the Mac. Off by
    /// default: while it is on the kernel keeps AWDL up and the Mac's one radio leaves its Wi-Fi
    /// channel up to ~97 ms every 524 ms (CLAUDE.md, trackpad stutter). The listener's, not the
    /// pipeline's: a change replaces the listener (StreamServer.setPeerToPeer) and never restarts
    /// the stream.
    package var directWireless: Bool
    /// Remote access: the remote door runs (TLS 1.3, paired devices only; RemoteAccess). The Mac's
    /// alone: absent from StreamSettings, HostSettingsChange, DeviceSettings.accepted, `applying`
    /// and `restartNeeded`, so no device can widen who reaches the Mac.
    package var remoteAccess: Bool
    /// The remote door's port. 7455 in `standard`; 0 = any free port (SillHost --remote without a
    /// port). Never another port by itself: saved addresses depend on it.
    package var remotePort: Int
    /// The remote door also admits sources outside this Mac's networks and VPNs (a router port
    /// forward).
    package var internetAccess: Bool

    /// Every knob is required, so the compiler finds each place that builds one when a knob is added.
    package init(maxFPS: Int, captureScale: CGFloat, bitrate: Int, prioritizeSpeed: Bool, virtualDisplay: Bool,
                 directWireless: Bool, remoteAccess: Bool, remotePort: Int, internetAccess: Bool) {
        self.maxFPS = maxFPS
        self.captureScale = captureScale
        self.bitrate = bitrate
        self.prioritizeSpeed = prioritizeSpeed
        self.virtualDisplay = virtualDisplay
        self.directWireless = directWireless
        self.remoteAccess = remoteAccess
        self.remotePort = remotePort
        self.internetAccess = internetAccess
    }

    /// The spike's knobs, formerly the `let`s at the top of the CLI's main.swift, and the app's
    /// defaults. Virtual display off in both until Noah flips it. Direct Wireless off in both
    /// (Noah, 2026-09-24): AWDL costs every Wi-Fi stream its steadiness, and a shared network needs
    /// none of it. Remote access and internet access off in both: only the Mac's own user widens
    /// exposure. 7455 is unassigned at IANA and below the ephemeral range.
    package static let standard = HostConfig(maxFPS: 120, captureScale: 2, bitrate: 15_000_000,
                                             prioritizeSpeed: false, virtualDisplay: false, directWireless: false,
                                             remoteAccess: false, remotePort: 7455, internetAccess: false)

    /// The remote door's port when none is set.
    package static let defaultRemotePort = 7455

    /// Within what the pipeline supports: 24…120 fps, Retina or points, 1–100 Mbps per 60 fps, a
    /// remote port of 0 (any) or 1024…65535 (else 7455). A hand-edited default or a launch argument
    /// can hold anything.
    package func validated() -> HostConfig {
        var c = self
        c.maxFPS = min(max(maxFPS, 24), 120)
        c.captureScale = captureScale >= 1.5 ? 2 : 1
        c.bitrate = min(max(bitrate, 1_000_000), 100_000_000)
        if remotePort != 0 && !(1024...65535).contains(remotePort) { c.remotePort = Self.defaultRemotePort }
        return c
    }

    /// What differs from `new`, for the log: "frame rate limit 120 → 60 fps, bitrate 15 → 8 Mbps
    /// per 60 fps, Retina → points, speed off → on, virtual display off → on, direct wireless
    /// off → on, remote access off → on, remote port 7455 → 7460, internet access off → on".
    package func changes(to new: HostConfig) -> String {
        func onOff(_ b: Bool) -> String { b ? "on" : "off" }
        func scaleName(_ s: CGFloat) -> String { s >= 1.5 ? "Retina" : "points" }
        var parts: [String] = []
        if maxFPS != new.maxFPS { parts.append("frame rate limit \(maxFPS) → \(new.maxFPS) fps") }
        if bitrate != new.bitrate { parts.append("bitrate \(Self.mbps(bitrate)) → \(Self.mbps(new.bitrate)) Mbps per 60 fps") }
        if captureScale != new.captureScale { parts.append("\(scaleName(captureScale)) → \(scaleName(new.captureScale))") }
        if prioritizeSpeed != new.prioritizeSpeed { parts.append("speed \(onOff(prioritizeSpeed)) → \(onOff(new.prioritizeSpeed))") }
        if virtualDisplay != new.virtualDisplay { parts.append("virtual display \(onOff(virtualDisplay)) → \(onOff(new.virtualDisplay))") }
        if directWireless != new.directWireless { parts.append("direct wireless \(onOff(directWireless)) → \(onOff(new.directWireless))") }
        if remoteAccess != new.remoteAccess { parts.append("remote access \(onOff(remoteAccess)) → \(onOff(new.remoteAccess))") }
        if remotePort != new.remotePort { parts.append("remote port \(remotePort) → \(new.remotePort)") }
        if internetAccess != new.internetAccess { parts.append("internet access \(onOff(internetAccess)) → \(onOff(new.internetAccess))") }
        return parts.isEmpty ? "no change" : parts.joined(separator: ", ")
    }

    /// "15", or "8.5" for a bitrate that is not whole megabits.
    package static func mbps(_ bitsPerSecond: Int) -> String {
        bitsPerSecond % 1_000_000 == 0 ? "\(bitsPerSecond / 1_000_000)"
                                       : String(format: "%.1f", Double(bitsPerSecond) / 1_000_000)
    }
}
