// What the iOS app's own layout and ledger code computes, for the Kotlin ports to match
// (clients/design/generate.sh compiles this with iOSClient/PhonePortraitLayout.swift,
// iOSClient/HostSettingsLedger.swift, iOSClient/DuoPosture.swift and
// Sources/StreamProtocol/HostSettings.swift, as they are).
import Foundation

func n(_ v: CGFloat) -> String { String(format: "%.6f", Double(v)) }
func r(_ c: CGRect) -> String { "[\(n(c.minX)),\(n(c.minY)),\(n(c.width)),\(n(c.height))]" }
func rs(_ a: [CGRect]) -> String { "[" + a.map(r).joined(separator: ",") + "]" }

var out: [String] = []

// The phone's arrangement at every size a phone (or a narrow window) has, standard and with Larger
// Picture above each keyboard height the layout knows, and the video shapes `pane` handles.
var layouts: [String] = []
let videos: [CGSize] = [.zero, CGSize(width: 1920, height: 1080), CGSize(width: 1600, height: 1000), CGSize(width: 1000, height: 1600), CGSize(width: 3024, height: 1964)]
for w in stride(from: 300, through: 600, by: 20) {
    for h in stride(from: 480, through: 1000, by: 40) {
        for k: CGFloat? in [nil, PhonePortraitLayout.keyboardHeight(for: CGSize(width: w, height: h))] {
            let l = PhonePortraitLayout(size: CGSize(width: w, height: h), keyboard: k)
            var e = "{\"w\":\(w),\"h\":\(h),\"k\":\(k.map { n($0) } ?? "null")"
            e += ",\"picture\":\(r(l.picture)),\"row1\":\(r(l.row1)),\"buttons\":\(rs(l.buttons)),\"buttonsBesideMenus\":\(rs(l.buttonsBesideMenus))"
            e += ",\"strip\":\(r(l.strip)),\"menus\":\(r(l.menus)),\"stripBesideMenus\":\(r(l.stripBesideMenus)),\"keys\":\(r(l.keys)),\"caps\":\(rs(l.caps))"
            e += ",\"trackpad\":\(r(l.trackpad)),\"trackpadSpan\":\(n(l.trackpadSpan)),\"ruler\":\(r(l.ruler)),\"rulerStep\":\(n(l.rulerStep))"
            e += ",\"rulerBesideMenus\":\(r(l.rulerBesideMenus)),\"rulerStepBesideMenus\":\(n(l.rulerStepBesideMenus))"
            e += ",\"drawer\":\(r(l.drawer)),\"settings\":\(r(l.settings)),\"anchor\":[\(n(l.settingsAnchor.x)),\(n(l.settingsAnchor.y))],\"dim\":\(rs(l.dim))"
            e += ",\"panes\":[" + videos.map { r(l.pane(video: $0)) }.joined(separator: ",") + "]"
            e += ",\"spans\":[" + videos.map { n(l.trackpadSpan(video: $0)) }.joined(separator: ",") + "]}"
            layouts.append(e)
        }
    }
}
out.append("\"phoneLayouts\":[\n" + layouts.joined(separator: ",\n") + "\n]")

var rules: [String] = []
for w in stride(from: 300, through: 1000, by: 20) {
    for h in stride(from: 300, through: 1000, by: 20) {
        let s = CGSize(width: w, height: h)
        let gains = PhonePortraitLayout.largerPictureGains(s, keyboard: PhonePortraitLayout.keyboardHeight(for: s))
        rules.append("[\(w),\(h),\(n(PhonePortraitLayout.keyboardHeight(for: s))),\(gains),\(PhonePortraitLayout.offersLargerPicture(screen: s))]")
    }
}
out.append("\"phoneRules\":[\n" + rules.joined(separator: ",\n") + "\n]")

// The ledger: a seeded run of picks, answers, broadcasts and expiries, each step's outcome.
struct Rand { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] } }
var rng = Rand(s: 0x5111)
var ledger = SettingsLedger()
var steps: [String] = []
var token = 0
var now = 0.0
var hostSettings = StreamSettings(maxFPS: 60, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: false, directWireless: false)
var lastSent: [Int] = []
func js(_ s: StreamSettings?) -> String {
    guard let s else { return "null" }
    return "[\(s.maxFPS),\(s.bitrate),\(s.captureScale),\(s.prioritizeSpeed),\(s.virtualDisplay),\(s.directWireless.map { "\($0)" } ?? "null")]"
}
func jc(_ c: HostSettingsChange?) -> String {
    guard let c else { return "null" }
    func o<T>(_ v: T?) -> String { v.map { "\($0)" } ?? "null" }
    return "[\(o(c.token)),\(o(c.maxFPS)),\(o(c.bitrate)),\(o(c.captureScale)),\(o(c.prioritizeSpeed)),\(o(c.virtualDisplay)),\(o(c.directWireless))]"
}
for _ in 0..<2000 {
    now += Double(rng.next() % 1500) / 1000
    let op = rng.next() % 10
    var step = ""
    switch op {
    case 0...3:
        token += 1
        var c = HostSettingsChange()
        switch rng.next() % 6 {
        case 0: c.maxFPS = rng.pick([60, 120])
        case 1: c.bitrate = rng.pick([4_000_000, 15_000_000, 40_000_000, 150_000_000])
        case 2: c.captureScale = rng.pick([1.0, 2.0])
        case 3: c.prioritizeSpeed = rng.pick([true, false])
        case 4: c.virtualDisplay = rng.pick([true, false])
        default: c.directWireless = rng.pick([true, false])
        }
        let sent = ledger.pick(c, token: token, now: now)
        if sent != nil { lastSent.append(token) }
        step = "{\"op\":\"pick\",\"t\":\(now),\"change\":\(jc(c)),\"token\":\(token),\"sent\":\(jc(sent))"
    case 4...6:
        // The Mac answers one sent pick (taking or refusing it), or broadcasts.
        var answering: Int? = nil
        if !lastSent.isEmpty, rng.next() % 3 != 0 { answering = lastSent.removeFirst() }
        if rng.next() % 2 == 0 { hostSettings.maxFPS = rng.pick([60, 120]) }
        if rng.next() % 3 == 0 { hostSettings.bitrate = rng.pick([8_000_000, 15_000_000, 25_000_000]) }
        let noDirect = rng.next() % 5 == 0
        var s = hostSettings
        if noDirect { s.directWireless = nil }
        let state = HostSettingsState(settings: s, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false, answering: answering)
        let refused = ledger.receive(state).map { "\"\($0)\"" }.sorted()
        step = "{\"op\":\"receive\",\"t\":\(now),\"settings\":\(js(s)),\"answering\":\(answering.map { "\($0)" } ?? "null"),\"refused\":[\(refused.joined(separator: ","))]"
    case 7...8:
        let dropped = ledger.expire(now: now, timeout: 4)
        step = "{\"op\":\"expire\",\"t\":\(now),\"dropped\":\(dropped)"
    default:
        if rng.next() % 10 == 0 { ledger.reset(); step = "{\"op\":\"reset\",\"t\":\(now)" }
        else { step = "{\"op\":\"none\",\"t\":\(now)" }
    }
    steps.append(step + ",\"displayed\":\(js(ledger.displayed))}")
}
out.append("\"ledger\":[\n" + steps.joined(separator: ",\n") + "\n]")


// The fold (DuoPosture.swift): every rule a layout consults, over screens of the Duo's, the
// foldables' and the plain devices' sizes, with no fold known, none folded, and bands down and
// across them (the stand-in's, narrower and wider ones, off-centre, partly off the screen, of no
// thickness). A fold is "inferred", null (known, nothing folded) or the band's rectangle.
func jf(_ f: FoldInfo) -> String {
    switch f {
    case .inferred: return "\"inferred\""
    case .known(let b): return b.map(r) ?? "null"
    }
}
func on<T>(_ v: T?, _ f: (T) -> String) -> String { v.map(f) ?? "null" }
let duoSizes: [CGSize] = [CGSize(width: 951, height: 669), CGSize(width: 669, height: 951), CGSize(width: 466, height: 678),
    CGSize(width: 678, height: 466), CGSize(width: 900, height: 675), CGSize(width: 675, height: 900), CGSize(width: 412, height: 915),
    CGSize(width: 915, height: 412), CGSize(width: 841, height: 701), CGSize(width: 701, height: 841), CGSize(width: 1000, height: 710),
    CGSize(width: 710, height: 1000), CGSize(width: 375, height: 667), CGSize(width: 1366, height: 1024), CGSize(width: 620, height: 900),
    CGSize(width: 700, height: 1050)]
func duoFolds(_ s: CGSize) -> [FoldInfo] {
    let w = s.width, h = s.height
    return [.inferred, .known(nil), .known(DuoPosture.standInFold(s)),
            .known(CGRect(x: w * 0.4 - 10, y: 0, width: 20, height: h)), .known(CGRect(x: w / 2, y: 0, width: 0, height: h)),
            .known(CGRect(x: -10, y: 0, width: 60, height: h)),
            .known(CGRect(x: 0, y: h * 0.3, width: w, height: 30)), .known(CGRect(x: 0, y: h / 2 - 40, width: w, height: 80))]
}
var duo: [String] = []
for s in duoSizes {
    for f in duoFolds(s) {
        let w = s.width, h = s.height
        var e = "{\"w\":\(n(w)),\"h\":\(n(h)),\"f\":\(jf(f))"
        e += ",\"vertical\":\(on(f.verticalBand, r)),\"horizontal\":\(on(f.horizontalBand, r))"
        e += ",\"crease\":\(on(DuoPosture.crease(s, f)) { "[\(n($0.top)),\(n($0.bottom))]" })"
        e += ",\"roomAboveFold\":\(on(DuoPosture.roomAboveFold(s, f), n))"
        var splits: [String] = []
        for a: CGFloat in [1.6, 0.6, 2.4] { for c: CGFloat in [180, 204, 400] {
            let p = DuoPosture.portraitSplit(s, f, aspect: a, controls: c); splits.append("[\(n(p.picture)),\(n(p.controls))]") } }
        e += ",\"splits\":[\(splits.joined(separator: ","))]"
        e += ",\"columnX\":[\(n(DuoPosture.columnX(columnWidth: 380, screenWidth: w, fold: f))),\(n(DuoPosture.columnX(columnWidth: max(200, w - 32), screenWidth: w, fold: f)))]"
        e += ",\"leadingPage\":\(on(DuoPosture.leadingPage(f), n))"
        let targets: [CGRect?] = [nil, CGRect(x: 20, y: 10, width: 60, height: 60), CGRect(x: w - 80, y: 10, width: 60, height: 60)]
        e += ",\"pageWidth\":[" + targets.map { on(DuoPosture.pageWidth(screenWidth: w, margin: 12, fold: f, for: $0), n) }.joined(separator: ",") + "]"
        var books: [String] = []
        for (pad, gap, bw, cw, b, pw) in [(22.0, 12.0, 66.0, 64.0, 5, 360.0), (14.0, 12.0, 64.0, 64.0, 5, 340.0), (14.0, 12.0, 64.0, 56.0, 4, 360.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat, Int, CGFloat)] {
            let k = DuoPosture.bookBar(width: w, fold: f, padding: pad, gap: gap, buttonWidth: bw, compactButtonWidth: cw, buttons: b, panelWidth: pw)
            books.append("[\(n(k.buttonWidth)),\(n(k.gap)),\(on(k.stripWidth, n)),\(n(k.panelWidth)),\(k.clears)]")
        }
        e += ",\"bookBars\":[\(books.joined(separator: ","))]"
        var offs: [String] = []
        for cw: CGFloat in [200, 360, 500] { for x in [0, w / 2 - 100, w - 300] {
            offs.append(n(DuoPosture.offTheFold(x: x, width: cw, screenWidth: w, margin: 12, fold: f))) } }
        e += ",\"offTheFold\":[\(offs.joined(separator: ","))]"
        var lights: [String] = []
        for t in [CGRect(x: w / 2 - 46, y: 20, width: 92, height: 58), CGRect(x: w * 0.2, y: h * 0.55, width: 92, height: 58),
                  CGRect(x: w * 0.6, y: h * 0.4, width: 92, height: 58)] {
            for below in [true, false] {
                let m = DuoPosture.lightsMenu(x: t.midX, below: below, thumbnail: t, size: CGSize(width: 214, height: 62), gap: 8, screenWidth: w, fold: f)
                lights.append("[\(n(m.x)),\(n(m.y)),\(m.below)]")
            }
        }
        e += ",\"lights\":[\(lights.joined(separator: ","))]}"
        duo.append(e)
    }
}
out.append("\"duoRules\":[\n" + duo.joined(separator: ",\n") + "\n]")

// The posture itself: what each hinge and fold make of a screen, the hinge before its first
// report, the status bar, the pane's shape.
let hinges: [DuoPosture.Hinge] = [.unknown, .closed, .partiallyOpen, .fullyOpen]
var postures: [String] = []
for s in [CGSize(width: 951, height: 669), CGSize(width: 669, height: 951), CGSize(width: 466, height: 678), CGSize(width: 900, height: 675)] {
    for hinge in hinges {
        for fold: CGRect? in [nil, DuoPosture.standInFold(s), CGRect(x: s.width - 20, y: 0, width: 60, height: s.height),
                              CGRect(x: s.width + 10, y: 0, width: 40, height: s.height)] {
            let p = DuoPosture(hinge: hinge, fold: fold)
            postures.append("{\"w\":\(n(s.width)),\"h\":\(n(s.height)),\"hinge\":\"\(hinge.rawValue)\",\"fold\":\(on(fold, r)),\"info\":\(jf(p.info(in: s))),\"pose\":\"\(p.pose(s).rawValue)\",\"active\":\(p.foldActive),\"inner\":\(p.onInnerDisplay),\"hides\":\(DuoPosture.hidesStatusBar(p.pose(s)))}")
        }
    }
}
out.append("\"duoPostures\":[\n" + postures.joined(separator: ",\n") + "\n]")
var hingeRules: [String] = []
for h in hinges { for a: Bool? in [nil, true, false] {
    hingeRules.append("[\"\(h.rawValue)\",\(a.map { "\($0)" } ?? "null"),\"\(DuoPosture.hinge(reported: h, regionActive: a).rawValue)\"]") } }
out.append("\"duoHinge\":[" + hingeRules.joined(separator: ",") + "]")
var aspects: [String] = []
for v in [CGSize.zero, CGSize(width: 1920, height: 1080), CGSize(width: 1000, height: 1600), CGSize(width: 0, height: 900)] { for fit in [true, false] {
    aspects.append("[\(n(v.width)),\(n(v.height)),\(fit),\(n(DuoPosture.paneAspect(video: v, fitsWindowToPane: fit)))]") } }
out.append("\"duoAspects\":[" + aspects.joined(separator: ",") + "]")

print("{\n" + out.joined(separator: ",\n") + "\n}")
