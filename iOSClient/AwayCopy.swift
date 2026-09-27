import Foundation
// In the app StreamProtocol is its own module; the away-copy check compiles this file together with
// Sources/StreamProtocol/HostSettings.swift as one module, where there is nothing to import.
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// Away from home and the link, on the device (docs/remote-bundle-plan.md §5.8, §6.7 and §8): every
/// string the Settings panel and the stream screen show for them, which callout shows, and when the
/// stream screen's line comes and goes (`LinkLine`). Values only ever from the Mac's own state on this
/// connection (`away` and `link` in its kind 16), never a pending pick. Pure (Foundation and
/// StreamProtocol's HostSettings.swift), checked with swiftc (Tests/checks/away-copy).
enum AwayCopy {
    /// "Low · Standard", from the Mac's word.
    static func title(_ bitrate: Int, _ captureScale: Double) -> String {
        QualityPreset.shortTitle(bitrate: bitrate, captureScale: captureScale)
    }

    /// The same for VoiceOver: "Low, Standard", "12 megabits per second, Retina".
    static func spoken(_ bitrate: Int, _ captureScale: Double) -> String {
        let name = QualityPreset(rawValue: bitrate)?.name ?? "\(QualityPreset.mbps(bitrate)) megabits per second"
        return "\(name), \(captureScale >= 1.5 ? "Retina" : "Standard")"
    }

    /// A title kept whole on its line ("Low · Standard", "12 Mbps · Retina"): no-break spaces.
    static func whole(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    // MARK: The panel's header

    /// The header's line under the route line, while the Mac counts this connection as away:
    /// "Away: Low · Standard" while the away quality runs, "Home quality: Pro · Retina (a device at
    /// home is connected)" while it does not; and what VoiceOver adds to the header for it. Nil at
    /// home, and from a Mac that sends no `away` (an older one, SillHost without --remote).
    static func headerLine(_ away: AwayQuality?) -> (text: String, spoken: String)? {
        guard let a = away, a.thisConnectionAway else { return nil }
        if a.awayRunning {
            return ("Away: \(whole(title(a.awayBitrate, a.awayCaptureScale)))",
                    ", away quality, \(spoken(a.awayBitrate, a.awayCaptureScale))")
        }
        return ("Home quality: \(whole(title(a.homeBitrate, a.homeCaptureScale))) (a device at home is connected)",
                ", home quality, \(spoken(a.homeBitrate, a.homeCaptureScale)), because a device at home is connected")
    }

    // MARK: The panel's footnote

    /// Under the stream rows' footer, one of three: away and running; away while a device at home is
    /// connected; at home, from a Mac that sent `away` and whose kind 18 says Remote Access is on. The
    /// qualities kept whole, as in the header, so a wrap never starts a line with "· Standard".
    static func footnote(_ away: AwayQuality?, mac: String, remoteAccessOn: Bool) -> String? {
        guard let a = away else { return nil }
        let home = whole(title(a.homeBitrate, a.homeCaptureScale))
        if a.thisConnectionAway, a.awayRunning {
            return "Away from home, \(mac) streams at what you choose here and keeps it for next time. At home it goes back to \(home)."
        }
        if a.thisConnectionAway {
            return "A device at home is connected, so \(mac) streams at its home quality, \(home). What you choose here applies once every device is away."
        }
        guard remoteAccessOn else { return nil }
        return "Away from home, \(mac) streams at \(whole(title(a.awayBitrate, a.awayCaptureScale)))."
    }

    // MARK: The link

    /// A suggestion as the device names it: "Low · Standard" when it changes the resolution, else the
    /// preset's name alone ("Balanced"); and spoken ("Low, Standard", "Balanced").
    static func suggestion(_ link: LinkReport) -> (title: String, spoken: String, change: HostSettingsChange)? {
        guard let bitrate = link.suggestedBitrate else { return nil }
        let change = HostSettingsChange(bitrate: bitrate, captureScale: link.suggestedCaptureScale)
        if let scale = link.suggestedCaptureScale {
            return (title(bitrate, scale), spoken(bitrate, scale), change)
        }
        let name = QualityPreset.name(forBitrate: bitrate)
        return (name, QualityPreset(rawValue: bitrate)?.name ?? "\(QualityPreset.mbps(bitrate)) megabits per second", change)
    }

    /// The callout while the link is behind, and its button. First match wins: away while a device at
    /// home is connected (the Mac keeps the home quality: nothing here would change it); a suggestion;
    /// nothing lower. Nil while the link keeps up, and for "stalled", which is the Mac's alone: a
    /// report of it queues behind the backlog it describes, so it can only arrive once the path is
    /// back, when it is no longer true.
    struct Callout: Equatable {
        let text: String
        /// "Use Low · Standard", spoken "Use Low, Standard", and the change it sends; nil for none.
        let button: Button?
        struct Button: Equatable {
            let title: String
            let spoken: String
            let change: HostSettingsChange
        }
    }

    static func callout(link: LinkReport?, away: AwayQuality?, mac: String) -> Callout? {
        guard let link, link.isBehind else { return nil }
        let quality = QualityPreset.name(forBitrate: link.bitrate)
        if let a = away, a.thisConnectionAway, !a.awayRunning {
            return Callout(text: "The link can’t carry \(quality), which \(mac) keeps while a device at home is connected.", button: nil)
        }
        if let s = suggestion(link) {
            return Callout(text: "The link can’t carry \(quality). \(whole(s.title)) is recommended.",
                           button: Callout.Button(title: "Use \(whole(s.title))", spoken: "Use \(s.spoken)", change: s.change))
        }
        return Callout(text: "The link to \(mac) is too slow for a steady picture, even at Low.", button: nil)
    }

    /// The old slow-link callout (the round trip over 250 ms away from home) shows only for a Mac that
    /// sent no `away`, an older one: a Mac that judges the link itself says when it cannot keep up,
    /// and a high round trip with nothing withheld is no reason to lower the quality.
    static func showsRttCallout(away: AwayQuality?, remote: Bool, slowLink: Bool) -> Bool {
        away == nil && remote && slowLink
    }

    /// The stream screen's line while the link is behind: "The link can’t keep up with Pro. Lower it in
    /// Settings." when the panel offers something to pick, else "The link to Mac mini can’t keep up."
    static func streamLine(link: LinkReport?, away: AwayQuality?, mac: String) -> String? {
        guard let c = callout(link: link, away: away, mac: mac), let link else { return nil }
        if c.button != nil { return "The link can’t keep up with \(QualityPreset.name(forBitrate: link.bitrate)). Lower it in Settings." }
        return "The link to \(mac) can’t keep up."
    }
}

/// The stream screen's line over time (docs/remote-bundle-plan.md §6.7): it shows as soon as a
/// report of behind arrives, while the Settings panel, the drawer and the pairing overlay are closed
/// (`allowed`); it goes 2 s after the report clears, so a quick flip back does not flicker; and
/// VoiceOver hears it once a spell, as it first shows (a spell ends when the line goes).
struct LinkLine: Equatable {
    static let linger = 2.0
    /// The line's text through its spell, the linger included; nil once it has gone.
    private(set) var text: String?
    /// On screen: a text, and nothing open over the stream.
    private(set) var visible = false
    /// When the report cleared, while the line lingers.
    private var clearedAt: Double?
    private var announced = false

    /// A report's line now (nil: none, or not behind), whether nothing is open over the stream, and the
    /// time. Returns the text to announce, once a spell.
    mutating func update(report: String?, allowed: Bool, now: Double) -> String? {
        if let report {
            text = report
            clearedAt = nil
        } else if text != nil {
            let since = clearedAt ?? now
            clearedAt = since
            if now >= since + Self.linger {
                text = nil
                clearedAt = nil
                announced = false
            }
        }
        visible = text != nil && allowed
        guard visible, !announced, let t = text else { return nil }
        announced = true
        return t
    }

    /// When to look again: the linger's end, while the line lingers.
    var recheckAt: Double? { clearedAt.map { $0 + Self.linger } }
}
