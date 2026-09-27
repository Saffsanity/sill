// H6 (docs/remote-bundle-plan.md §4 and §11): kind 16's two new fields, `away` (AwayQuality) and
// `link` (LinkReport), and QualityPreset's two helpers, on their own. Sources/StreamProtocol/
// HostSettings.swift only imports Foundation, so it compiles alone with this file:
//
//   swiftc -O Sources/StreamProtocol/HostSettings.swift Tests/checks/away-wire/main.swift \
//     -o .build/checks/away-wire/check && .build/checks/away-wire/check
//
// What it checks: both types round-trip through JSON under their wire names; `{}` and a report
// without its state fail to decode, a report with only its required fields decodes; a state without
// either field (an older host's) decodes with both nil, and one with both nil encodes exactly the keys
// an older host's does; an older device's decoder (`BaseState`: HostSettingsState as main had it at
// 2b38179, verbatim but for its name) reads the new state, fields and all, and skips the two new
// ones; `isBehind` is "behind" alone; `name(forBitrate:)` and `shortTitle(bitrate:captureScale:)`.
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok" : "FAIL") \(what)")
    if !ok { failures += 1 }
}

func encode<T: Encodable>(_ v: T) -> Data { try! JSONEncoder().encode(v) }
func decode<T: Decodable>(_ t: T.Type, _ d: Data) -> T? { try? JSONDecoder().decode(t, from: d) }
func object(_ d: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:] }
func keys(_ d: Data) -> Set<String> { Set(object(d).keys) }
func json(_ s: String) -> Data { Data(s.utf8) }

/// HostSettingsState as main had it at 2b38179 (before this change): what every older device decodes.
struct BaseState: Codable, Hashable, Sendable {
    var settings: StreamSettings
    var persistent: Bool
    var virtualDisplayAvailable: Bool
    var virtualDisplayNote: String?
    var softwareEncoder: Bool
    var stream: RunningStream?
    var answering: Int?
}

let settings = StreamSettings(maxFPS: 120, bitrate: 4_000_000, captureScale: 1, prioritizeSpeed: false, virtualDisplay: false,
                              directWireless: false)
let stream = RunningStream(width: 1512, height: 982, fps: 60, mbps: 4, onVirtualDisplay: false)
let away = AwayQuality(homeBitrate: 40_000_000, homeCaptureScale: 2, awayBitrate: 4_000_000, awayCaptureScale: 1,
                       thisConnectionAway: true, awayRunning: true)
let link = LinkReport(state: LinkReport.behind, withheldPerSecond: 52, bitrate: 150_000_000, carriedKbps: 6400,
                      suggestedBitrate: 4_000_000, suggestedCaptureScale: 1)

// MARK: AwayQuality

do {
    let d = encode(away)
    check(decode(AwayQuality.self, d) == away, "AwayQuality round-trips")
    check(keys(d) == ["homeBitrate", "homeCaptureScale", "awayBitrate", "awayCaptureScale", "thisConnectionAway", "awayRunning"],
          "AwayQuality's wire names: \(keys(d).sorted())")
    let o = object(d)
    check(o["homeBitrate"] as? Int == 40_000_000 && o["awayBitrate"] as? Int == 4_000_000, "AwayQuality carries both bitrates")
    check(o["homeCaptureScale"] as? Double == 2 && o["awayCaptureScale"] as? Double == 1, "AwayQuality carries both scales")
    check(o["thisConnectionAway"] as? Bool == true && o["awayRunning"] as? Bool == true, "AwayQuality carries its two flags")
    check(decode(AwayQuality.self, json("{}")) == nil, "{} is no AwayQuality")
    check(decode(AwayQuality.self, json(#"{"homeBitrate":1,"homeCaptureScale":2,"awayBitrate":3,"awayCaptureScale":1,"thisConnectionAway":false}"#)) == nil,
          "an AwayQuality without awayRunning does not decode (every field is required)")
    let later = json(#"{"homeBitrate":1,"homeCaptureScale":2,"awayBitrate":3,"awayCaptureScale":1,"thisConnectionAway":false,"awayRunning":true,"laterField":7}"#)
    check(decode(AwayQuality.self, later)?.awayRunning == true, "an AwayQuality with a later field decodes")
}

// MARK: LinkReport

do {
    let d = encode(link)
    check(decode(LinkReport.self, d) == link, "LinkReport round-trips")
    check(keys(d) == ["state", "withheldPerSecond", "bitrate", "carriedKbps", "suggestedBitrate", "suggestedCaptureScale"],
          "LinkReport's wire names: \(keys(d).sorted())")
    check(object(d)["state"] as? String == "behind", "behind is the string \"behind\"")
    let bare = LinkReport(state: LinkReport.stalled, withheldPerSecond: 0, bitrate: 40_000_000)
    let b = encode(bare)
    check(keys(b) == ["state", "withheldPerSecond", "bitrate"], "a bare report leaves its nil fields out: \(keys(b).sorted())")
    check(object(b)["state"] as? String == "stalled", "stalled is the string \"stalled\"")
    check(decode(LinkReport.self, b) == bare, "a bare report round-trips")
    check(decode(LinkReport.self, json("{}")) == nil, "{} is no LinkReport")
    check(decode(LinkReport.self, json(#"{"withheldPerSecond":3,"bitrate":4000000}"#)) == nil, "a report without its state does not decode")
    check(decode(LinkReport.self, json(#"{"state":"behind","withheldPerSecond":3,"bitrate":4000000}"#))?.carriedKbps == nil,
          "a report with only its required fields decodes, carried nil")
    let suggestedOnly = decode(LinkReport.self, json(#"{"state":"behind","withheldPerSecond":3,"bitrate":40000000,"suggestedBitrate":15000000}"#))
    check(suggestedOnly?.suggestedBitrate == 15_000_000 && suggestedOnly?.suggestedCaptureScale == nil,
          "a suggestion without a scale keeps the resolution (nil)")
    check(link.isBehind, "\"behind\" is behind")
    check(!bare.isBehind, "\"stalled\" is not behind: a device shows nothing for it")
    check(!LinkReport(state: "slowish", withheldPerSecond: 9, bitrate: 1).isBehind, "a state this build does not know reads as keeping up")
    check(!LinkReport(state: "Behind", withheldPerSecond: 9, bitrate: 1).isBehind, "the state is matched exactly")
}

// MARK: HostSettingsState with and without them

do {
    let old = HostSettingsState(settings: settings, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false, stream: stream)
    check(old.away == nil && old.link == nil, "the init leaves both new fields nil by default")
    let oldJSON = encode(old)
    let base = BaseState(settings: settings, persistent: true, virtualDisplayAvailable: true, virtualDisplayNote: nil,
                         softwareEncoder: false, stream: stream, answering: nil)
    let baseJSON = encode(base)
    check(keys(oldJSON) == keys(baseJSON), "a state without away and link has exactly an older host's keys: \(keys(oldJSON).sorted())")
    check(NSDictionary(dictionary: object(oldJSON)).isEqual(to: object(baseJSON)), "…and exactly its values")
    let fromOldHost = decode(HostSettingsState.self, baseJSON)
    check(fromOldHost != nil && fromOldHost?.away == nil && fromOldHost?.link == nil, "an older host's state decodes, away and link nil")
    check(fromOldHost?.settings == settings && fromOldHost?.stream == stream, "…with its settings and stream")

    let new = HostSettingsState(settings: settings, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false,
                                stream: stream, answering: 7, away: away, link: link)
    let newJSON = encode(new)
    check(decode(HostSettingsState.self, newJSON) == new, "a state with away and link round-trips")
    check(keys(newJSON).isSuperset(of: ["away", "link"]), "…under the names away and link")
    check(object(newJSON)["away"] as? [String: Any] != nil && object(newJSON)["link"] as? [String: Any] != nil,
          "…each an object")
    let olderDevice = decode(BaseState.self, newJSON)
    check(olderDevice != nil, "an older device decodes the new state (it skips away and link)")
    check(olderDevice?.settings == settings && olderDevice?.stream == stream && olderDevice?.answering == 7
            && olderDevice?.persistent == true && olderDevice?.virtualDisplayAvailable == true && olderDevice?.softwareEncoder == false,
          "…with every field it knows as sent")
    let awayOnly = HostSettingsState(settings: settings, persistent: false, virtualDisplayAvailable: false, softwareEncoder: true, away: away)
    let awayOnlyJSON = encode(awayOnly)
    check(keys(awayOnlyJSON).contains("away") && !keys(awayOnlyJSON).contains("link"), "away without link: no link key")
    check(decode(HostSettingsState.self, awayOnlyJSON) == awayOnly, "…and it round-trips")
    let linkOnly = HostSettingsState(settings: settings, persistent: false, virtualDisplayAvailable: false, softwareEncoder: true, link: link)
    let linkOnlyJSON = encode(linkOnly)
    check(keys(linkOnlyJSON).contains("link") && !keys(linkOnlyJSON).contains("away"), "link without away (SillHost without --remote): no away key")
    check(decode(HostSettingsState.self, linkOnlyJSON)?.link == link, "…and the link decodes")
    // A malformed field fails the whole state, as any field does: a host sends both whole or not at all.
    var broken = object(newJSON)
    broken["away"] = [String: Any]()
    let brokenJSON = try! JSONSerialization.data(withJSONObject: broken)
    check(decode(HostSettingsState.self, brokenJSON) == nil, "a state whose away is {} does not decode")
    check(decode(BaseState.self, brokenJSON) != nil, "…while an older device still reads it")
}

// MARK: QualityPreset's helpers

do {
    let names = QualityPreset.allCases.map { QualityPreset.name(forBitrate: $0.rawValue) }
    check(names == ["Low", "Efficient", "Balanced", "High", "Pro", "Ultra", "Extreme"], "every preset by its name: \(names)")
    check(QualityPreset.name(forBitrate: 12_000_000) == "12 Mbps", "a hand-set bitrate reads \"12 Mbps\"")
    check(QualityPreset.name(forBitrate: 8_500_000) == "8.5 Mbps", "…and \"8.5 Mbps\"")
    check(QualityPreset.name(forBitrate: 2_000_000) == "2 Mbps", "…and \"2 Mbps\" under Low")
    check(QualityPreset.shortTitle(bitrate: 4_000_000, captureScale: 1) == "Low · Standard", "Low · Standard")
    check(QualityPreset.shortTitle(bitrate: 40_000_000, captureScale: 2) == "Pro · Retina", "Pro · Retina")
    check(QualityPreset.shortTitle(bitrate: 12_000_000, captureScale: 2) == "12 Mbps · Retina", "12 Mbps · Retina")
    check(QualityPreset.shortTitle(bitrate: 150_000_000, captureScale: 1.5) == "Extreme · Retina", "1.5 counts as Retina (validated()'s rule)")
    check(QualityPreset.shortTitle(bitrate: 15_000_000, captureScale: 1.49) == "Balanced · Standard", "1.49 counts as Standard")
}

print(failures == 0 ? "away-wire: all passed" : "away-wire: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
