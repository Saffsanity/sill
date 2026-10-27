import Foundation

/// The Settings panel's Connection Information: what this session runs on, a row each, refreshed
/// with every second's link stats, and the same as text for Copy (a bug report, a support mail).
/// A second without a sample reads "–", never as zero, as the HUD and the Mac's log read it.
enum ConnectionInfo {
    struct Stream: Equatable { var width: Int, height: Int, fps: Int, mbps: Int }
    struct Sample: Equatable { var median: Int, max: Int }

    struct Facts: Equatable {
        var mac: String
        /// "Wi-Fi", "Wired", "Direct", or a remote session's "through Tailscale"; nil when no path says.
        var route: String?
        var stream: Stream?
        /// Frames received in the last second; nil before the first second closes.
        var received: Int?
        var rtt: Sample?
        var frameAge: Sample?
        var hostVersion: String?
        var hostProtocol: Int?
        var appVersion: String
        var build: String
        var system: String
        var model: String
    }

    struct Row: Equatable { let label: String; let value: String }

    static func rows(_ f: Facts) -> [Row] {
        let host = f.hostVersion.map { v in f.hostProtocol.map { "\(v), protocol \($0)" } ?? v }
        return [
            Row(label: "Mac", value: f.mac.isEmpty ? "–" : f.mac),
            Row(label: "Connection", value: f.route ?? "–"),
            Row(label: "Picture", value: f.stream.map { "\($0.width)×\($0.height) · \($0.fps) fps · \($0.mbps) Mbps" } ?? "Not streaming"),
            Row(label: "Received", value: f.received.map { "\($0) fps" } ?? "–"),
            Row(label: "Round trip", value: ms(f.rtt)),
            Row(label: "Frame age", value: ms(f.frameAge)),
            Row(label: "Mac's Sill", value: host ?? "an older Sill or the command-line host"),
            Row(label: "This device", value: "Sill \(f.appVersion) (\(f.build)), \(f.system), \(f.model)"),
        ]
    }

    /// What Copy puts on the clipboard: a header with the UTC time, then one "label: value" line a row,
    /// the screen's non-breaking hyphens and spaces as plain ones (a pasted "Wi‑Fi" should search).
    static func text(_ rows: [Row], at date: Date) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        let lines = "Sill connection information, \(stamp)\n" + rows.map { "\($0.label): \($0.value)\n" }.joined()
        return lines.replacingOccurrences(of: "\u{2011}", with: "-").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func ms(_ s: Sample?) -> String {
        guard let s else { return "–" }
        return s.max > s.median ? "\(s.median) ms, worst \(s.max) ms" : "\(s.median) ms"
    }
}
