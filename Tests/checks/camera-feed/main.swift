import Foundation

// Sill Camera's rules (CameraFeedPolicy, docs/camera-plan.md §6.4), compiled alone as one module (module.txt): the
// formats and rates; what Sill for Mac writes (the state) and reads (the demand), their encodings and caps; which
// client may feed Sill Camera; the placeholder's words; frames, ticks, formats and apps step by step; then 20,000
// random lives (feeders starting, stopping and leaving, Sill and others, states written by anyone, frames of every
// kind, formats, rates, apps starting and stopping the stream, ticks) against the invariants: one feeder at most,
// always Sill; nothing said and no frame kept while nobody feeds; a picture goes out only while an app runs the
// stream, from the feeder, while it says that device's camera is live, of the size apps take, under a second old,
// and never after anything retired it; every placeholder's words are the state's, and only a device state names a
// device; the stream never starves while an app runs it; the demand is what runs.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = CameraFeedPolicy

/// SplitMix64: the same lives on every run.
struct Rand: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
}

func fourCC(_ v: UInt32) -> String {
    String(bytes: [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)], encoding: .ascii) ?? "?"
}

let sill = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
let sill2 = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
let other = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
let nv12 = P.pixelFormat
func state(_ s: P.Show) -> String { P.encode(s) }
let liveIPad = state(.device(name: "iPad", paused: false))

/// A policy driven step by step on a clock of its own.
struct Run {
    var p = P()
    var t: Double = 1000
    mutating func feed(_ client: UUID = sill) { _ = p.sinkStart(client: client, signingID: P.sillIdentifier, signatureValid: true) }
    @discardableResult mutating func write(_ text: String) -> Bool { p.stateWritten(text) }
    @discardableResult mutating func frame(_ client: UUID = sill, w: Int = 1280, h: Int = 720, format: UInt32 = P.pixelFormat,
                                           more: Bool = false, after dt: Double = 0.001) -> P.FrameVerdict {
        t += dt
        return p.frame(from: client, width: w, height: h, pixelFormat: format, more: more, at: t)
    }
    mutating func tick(after dt: Double = P.tickInterval) -> P.Send? {
        t += dt
        return p.tick(at: t)
    }
    /// An app runs the stream, Sill feeds it and says the iPad's camera is live.
    static func live() -> Run {
        var r = Run()
        r.p.sourceStarted()
        r.feed()
        r.write(liveIPad)
        return r
    }
}
func line(_ s: P.Send?) -> String? { if case .placeholder(let p)? = s { return p.line }; return nil }

// MARK: - The constants and the formats

check(P.formats == [P.Format(width: 1280, height: 720), P.Format(width: 1920, height: 1080)],
      "the formats: 1280×720 first, then 1920×1080 (\(P.formats))")
check(fourCC(P.pixelFormat) == "420v", "NV12 in video range, as the Mac's decoder makes it (\(fourCC(P.pixelFormat)))")
check(P.fpsRange == 15...30 && P.defaultFps == 30, "15 to 30 frames a second, 30 by default")
check(P.frameLifetime == 1 && abs(P.tickInterval - 1.0 / 60) < 1e-12, "a frame stands a second; the timer runs at 60 Hz")
check(P.sinkQueueSize == 2, "the sink holds two frames")
check(P.stateCap == 4096 && P.nameCap == 40 && P.appsCap == 16 && P.appIDCap == 128, "the caps")
check(P.sillIdentifier == "me.saffer.sill.mac", "Sill for Mac's signing identifier")
let durations: [(Double, Int)] = [
    (1.0 / 30, 30), (1.0 / 15, 15), (1.0 / 24, 24), (1.0 / 25, 25), (1.0 / 29.97, 30), (1.0 / 29.6, 30),
    (1.0 / 60, 30), (1.0 / 120, 30), (1.0 / 10, 15), (1.0, 15), (0.0, 30), (-1.0, 30), (-1.0 / 30, 30),
    (Double.nan, 30), (Double.infinity, 30), (1e-300, 30), (Double.leastNonzeroMagnitude, 30),
]
for (d, want) in durations {
    check(P.fps(frameDuration: d) == want, "a frame duration of \(d) s: \(want) fps (\(P.fps(frameDuration: d)))")
}

// MARK: - What Sill for Mac writes: the state

for s in [P.Show.off, .unavailable, .waiting, .device(name: "iPad", paused: false), .device(name: "Noah’s iPhone", paused: true)] {
    check(P.decode(P.encode(s)) == s, "the state round trips: \(s)")
}
check(P.encode(.device(name: "iPad", paused: true)) == #"{"name":"iPad","paused":true,"show":"device"}"#,
      "the state's JSON: \(P.encode(.device(name: "iPad", paused: true)))")
check(P.encode(.waiting) == #"{"show":"waiting"}"#, "a state without a device names nobody: \(P.encode(.waiting))")
check(P.decode(#"{"show":"device","name":"iPad"}"#) == .device(name: "iPad", paused: false), "paused left out: live")
for bad in ["", "not json", "{}", #"{"show":"later"}"#, #"{"show":"device"}"#, #"{"show":"device","name":"  \n\t "}"#,
            #"{"show":3}"#, #"["off"]"#, #"{"show":"device","name":7}"#] {
    check(P.decode(bad) == nil, "not a state: \(bad.debugDescription)")
}
let pad = String(repeating: "a", count: 4096 - #"{"show":"waiting","x":""}"#.utf8.count)
let atCap = #"{"show":"waiting","x":"\#(pad)"}"#
check(atCap.utf8.count == 4096 && P.decode(atCap) == .waiting, "a state of 4,096 bytes reads (unknown fields skipped)")
check(P.decode(#"{"show":"waiting","x":"\#(pad)a"}"#) == nil, "a state of 4,097 bytes does not")
check(P.cleanName("iPad\nFake line") == "iPad Fake line", "a line break in a name is a space")
check(P.cleanName("  iPad \t  mini  ") == "iPad mini", "runs of spaces are one, the ends trimmed")
check(P.cleanName("\u{202E}evil\u{200B}") == "evil", "format characters (a right-to-left override, a zero width space) go: \(P.cleanName("\u{202E}evil\u{200B}").debugDescription)")
check(P.cleanName("a\u{0007}b\u{0000}c") == "a b c", "control characters are spaces")
let forty = String(repeating: "x", count: 40)
check(P.cleanName(forty) == forty && P.cleanName(forty + "y") == forty, "at most 40 characters")
check(P.cleanName(String(repeating: "x", count: 39) + " yy") == String(repeating: "x", count: 39), "cut at 40, trimmed again")
check(P.cleanName("Noah’s iPad 🎥") == "Noah’s iPad 🎥", "a name's own letters, apostrophes and emoji stay")
check(P.decode(P.encode(.device(name: "iPad\nSoftware Update", paused: false))) == .device(name: "iPad Software Update", paused: false),
      "a name is cleaned when written and when read")

// MARK: - What Sill for Mac reads: the demand

let demand = P.Demand(running: true, width: 1920, height: 1080, fps: 24, apps: [P.App(id: "com.apple.FaceTime", pid: 412)])
check(P.decodeDemand(P.encode(demand)) == demand, "the demand round trips")
check(P.encode(P.Demand(running: false, width: 1280, height: 720, fps: 30, apps: [])) == #"{"apps":[],"fps":30,"height":720,"running":false,"width":1280}"#,
      "the demand's JSON")
for (what, d) in [("640×480", P.Demand(running: true, width: 640, height: 480, fps: 30, apps: [])),
                  ("60 fps", P.Demand(running: true, width: 1280, height: 720, fps: 60, apps: [])),
                  ("14 fps", P.Demand(running: true, width: 1280, height: 720, fps: 14, apps: [])),
                  ("17 apps", P.Demand(running: true, width: 1280, height: 720, fps: 30, apps: Array(repeating: P.App(id: "a", pid: 1), count: 17)))] {
    check(P.decodeDemand(P.encode(d)) == nil, "not a demand Sill Camera writes: \(what)")
}
check(P.decodeDemand(P.encode(P.Demand(running: true, width: 1280, height: 720, fps: 15, apps: Array(repeating: P.App(id: "a", pid: 1), count: 16)))) != nil,
      "16 apps and 15 fps are a demand")
check(P.decodeDemand("nope") == nil && P.decodeDemand(String(repeating: " ", count: 4097)) == nil, "garbage, and past 4,096 bytes")
check(P.App(id: "com.apple.FaceTime\n x\u{00E9}", pid: 1).id == "com.apple.FaceTimex", "an app's identifier: printable ASCII only (\(P.App(id: "com.apple.FaceTime\n x\u{00E9}", pid: 1).id ?? "nil"))")
check(P.App(id: String(repeating: "a", count: 200), pid: 1).id?.count == 128 && P.App(id: nil, pid: 3).id == nil, "at most 128 characters; none stays none")

// MARK: - Who feeds Sill Camera

check(P.sinkVerdict(signingID: "me.saffer.sill.mac", signatureValid: true, feeder: nil, client: sill) == .accept, "Sill, its team's signature: fed")
check(P.sinkVerdict(signingID: "me.saffer.sill.mac", signatureValid: nil, feeder: nil, client: sill) == .accept,
      "Sill where the sandbox would not say: fed (by its identifier alone, said in the extension's log)")
check(P.sinkVerdict(signingID: "me.saffer.sill.mac", signatureValid: false, feeder: nil, client: sill) == .signature, "Sill's identifier, another signature: refused")
check(P.sinkVerdict(signingID: "com.example.camera", signatureValid: true, feeder: nil, client: other) == .notSill, "another app: refused")
check(P.sinkVerdict(signingID: "me.saffer.sill.mac.camera", signatureValid: true, feeder: nil, client: other) == .notSill, "a longer identifier: refused")
check(P.sinkVerdict(signingID: nil, signatureValid: nil, feeder: nil, client: other) == .unsigned
      && P.sinkVerdict(signingID: "", signatureValid: nil, feeder: nil, client: other) == .unsigned, "no identifier: refused")
check(P.sinkVerdict(signingID: "me.saffer.sill.mac", signatureValid: true, feeder: sill, client: sill2) == .busy, "a second Sill while one feeds: refused")
check(P.sinkVerdict(signingID: "me.saffer.sill.mac", signatureValid: true, feeder: sill, client: sill) == .accept, "the feeder again: fed")
do {
    var r = Run()
    check(r.p.sinkStart(client: other, signingID: "com.example.camera", signatureValid: true) == .notSill && r.p.feeder == nil, "a refused client feeds nothing")
    r.feed()
    check(r.p.feeder == sill, "Sill feeds it")
    check(r.p.sinkStart(client: sill2, signingID: P.sillIdentifier, signatureValid: true) == .busy && r.p.feeder == sill, "the first Sill keeps it")
    r.p.sinkStop(client: sill2)
    check(r.p.feeder == sill, "another client's stop changes nothing")
    r.p.sinkStop(client: sill)
    check(r.p.feeder == nil, "its own stop ends the feed")
    check(r.p.sinkStart(client: sill2, signingID: P.sillIdentifier, signatureValid: true) == .accept && r.p.feeder == sill2, "then the second Sill feeds it")
}

// MARK: - The words

do {
    var r = Run()
    // Nothing feeds it: Sill is not running, or its switch is off (Sill for Mac then never feeds it), one line for both.
    check(P.Copy.noSill == "Open Sill on this Mac and turn on Use iPhone and iPad cameras in its Settings.", "the no-feeder words: \(P.Copy.noSill)")
    check(r.p.placeholder == P.Placeholder(title: "Sill Camera", line: P.Copy.noSill, format: P.Format(width: 1280, height: 720)),
          "nothing feeds it: Open Sill on this Mac and turn on… (\(r.p.placeholder))")
    r.feed()
    check(r.p.placeholder.line == "Sill Camera isn’t available right now.", "fed, nothing said yet: not available, nobody named")
    let words: [(P.Show, String)] = [
        (.off, "Turn on Use iPhone and iPad cameras in Sill’s Settings on this Mac."),
        (.unavailable, "Sill Camera isn’t available right now."),
        (.waiting, "Turn on Share Camera in Sill on your iPhone or iPad."),
        (.device(name: "iPad", paused: false), "Waiting for iPad’s camera…"),
        (.device(name: "iPad", paused: true), "iPad’s camera is paused."),
    ]
    for (s, want) in words {
        check(r.write(state(s)), "Sill's state taken: \(s)")
        check(r.p.placeholder.line == want && r.p.placeholder.title == "Sill Camera", "\(s): \(want) (\(r.p.placeholder.line))")
    }
    r.p.formatChosen(1)
    check(r.p.placeholder.format == P.Format(width: 1920, height: 1080), "the placeholder at the size apps take")
    r.p.sinkStop(client: sill)
    check(r.p.placeholder.line == P.Copy.noSill && r.p.show == nil, "Sill gone: what it said goes too")
    r.feed(sill2)
    check(r.p.placeholder.line == "Sill Camera isn’t available right now.", "the next Sill starts from nothing, naming nobody (\(r.p.placeholder.line))")
}

// MARK: - The state

do {
    var r = Run()
    check(!r.write(liveIPad) && r.p.show == nil, "a state written while nothing feeds is not taken")
    r.feed()
    check(!r.write("garbage") && r.p.show == nil, "a state that does not read is not taken")
    check(r.write(liveIPad) && r.p.show == .device(name: "iPad", paused: false), "Sill's state taken")
    check(!r.write("{}") && r.p.show == .device(name: "iPad", paused: false), "a bad one changes nothing")
}
for (s, keeps) in [(P.Show.unavailable, false), (.off, false), (.waiting, false), (.device(name: "iPad", paused: true), false),
                   (.device(name: "iPhone", paused: false), false), (.device(name: "iPad", paused: false), true)] {
    var r = Run.live()
    check(r.frame() == .send, "a live frame goes")
    r.write(state(s))
    check((r.p.frameAt != nil) == keeps, "the newest frame \(keeps ? "kept" : "retired") at \(s)")
    let out = r.tick(after: 0.05)
    if keeps {
        check(out == .frame, "the same device's live camera: its frame again (\(String(describing: out)))")
    } else {
        check(line(out) != nil, "\(s): the placeholder at once, never the last picture (\(String(describing: out)))")
    }
}

// MARK: - Frames

do {
    var r = Run()
    r.p.sourceStarted()
    check(r.frame() == .notFeeder, "nothing feeds: refused")
    r.feed()
    check(r.frame() == .notLive, "nothing said yet: refused")
    for s in [P.Show.off, .unavailable, .waiting, .device(name: "iPad", paused: true)] {
        r.write(state(s))
        check(r.frame() == .notLive, "\(s): refused")
    }
    r.write(liveIPad)
    check(r.frame(other) == .notFeeder, "another client's frame: refused")
    check(r.frame(format: 0x3432_3066) == .wrongFormat, "full range NV12 ('420f'): refused")
    check(r.frame(format: 0x4247_5241) == .wrongFormat, "BGRA: refused")
    check(r.frame(w: 1920, h: 1080) == .wrongSize && r.frame(w: 1280, h: 960) == .wrongSize && r.frame(w: 720, h: 1280) == .wrongSize, "another size: refused")
    check(r.p.frameAt == nil, "nothing refused is kept")
    check(r.frame(more: true) == .kept && !r.p.frameSent, "more behind it: kept, not sent")
    check(r.frame() == .send && r.p.frameSent, "the last of them: sent at once")
    r.p.formatChosen(1)
    check(r.frame(w: 1920, h: 1080) == .send, "after the app chose 1920×1080, its frames")
    check(r.frame() == .wrongSize, "and 1280×720 no longer")
}
do {
    var r = Run()
    r.feed()
    r.write(liveIPad)
    check(r.frame() == .kept && r.tick() == nil, "no app runs the stream: kept, nothing goes out")
    r.p.sourceStarted()
    check(r.tick() == .frame, "an app starts it: the kept frame at once")
    check(r.tick() == nil, "then nothing until a frame duration passed")
}

// MARK: - The timer

do {
    var r = Run()
    check(r.tick() == nil, "no app runs it: nothing")
    r.p.sourceStarted()
    let first = r.tick()
    check(line(first) == P.Copy.noSill, "an app runs it, nothing feeds: the placeholder at once (\(String(describing: first)))")
    check(r.tick(after: 0.01) == nil, "the same placeholder within a frame duration: nothing")
    check(line(r.tick(after: 0.03)) == P.Copy.noSill, "a frame duration on: again")
    r.feed()
    check(line(r.tick(after: 0.001)) == "Sill Camera isn’t available right now.", "new words: at once")
    r.write(liveIPad)
    check(line(r.tick(after: 0.001)) == "Waiting for iPad’s camera…", "the device said: at once")
    check(r.frame(after: 0.002) == .send, "its first frame goes as it comes")
    check(r.tick(after: 0.0166) == nil, "within a frame duration of it: nothing")
    check(r.tick(after: 0.0167) == .frame, "a frame duration after it: the same frame again")
    var repeats = 0
    var gaps: [Double] = []
    var last = r.t
    for _ in 0..<57 {
        if r.tick() == .frame { repeats += 1; gaps.append(r.t - last); last = r.t }
    }
    check(repeats == 28 && gaps.allSatisfy { abs($0 - 2 * P.tickInterval) < 1e-9 }, "a stalled device's frame at 30 fps for under a second: \(repeats) repeats, every two ticks")
    let after = r.tick(after: 0.06)
    check(line(after) == "Waiting for iPad’s camera…", "past a second without a frame: the placeholder (\(String(describing: after)))")
    r.p.formatChosen(1)
    if case .placeholder(let p)? = r.tick(after: 0.001) {
        check(p.format == P.Format(width: 1920, height: 1080), "a new size: the placeholder at once at it")
    } else {
        check(false, "a new size: the placeholder at once")
    }
}
do {
    var r = Run.live()
    r.p.frameDurationChosen(seconds: 1.0 / 15)
    check(r.p.fps == 15, "15 fps chosen")
    _ = r.frame()
    check(r.tick(after: 1.0 / 30) == nil && r.tick(after: 1.0 / 30) == .frame, "at 15 fps the frame again only after 1/15 s")
    var s = Run.live()
    _ = s.frame()
    check(s.tick(after: 1.0 / 30 - P.tickInterval / 2 + 1e-9) == .frame, "half a tick of slack: due at 1/30 − 1/120 s")
    var u = Run.live()
    _ = u.frame()
    check(u.tick(after: 1.0 / 30 - P.tickInterval / 2 - 0.001) == nil, "but not before")
    var v = Run.live()
    _ = v.frame()
    check(v.tick(after: 0.5) == .frame && v.tick(after: 0.49) == .frame, "under a second old: the frame")
    check(line(v.tick(after: 0.02)) != nil, "a second old: the placeholder")
    var w = Run.live()
    _ = w.frame()
    check(line(w.tick(after: 1.5)) != nil, "a second and a half old: the placeholder")
}

// MARK: - Apps and the demand

do {
    var r = Run()
    let faceTime = P.App(id: "com.apple.FaceTime", pid: 412), booth = P.App(id: "com.apple.PhotoBooth", pid: 518)
    check(r.p.demand == P.Demand(running: false, width: 1280, height: 720, fps: 30, apps: []), "nothing runs: the demand says so")
    check(r.p.appsNow([faceTime]) && r.p.demand.apps.isEmpty, "apps while nothing runs are not in the demand")
    r.p.sourceStarted()
    check(r.p.demand.running && r.p.demand.apps == [faceTime], "an app runs it: in the demand")
    check(!r.p.appsNow([faceTime]) && r.p.appsNow([faceTime, booth]), "appsNow says when they changed")
    r.p.formatChosen(1)
    r.p.frameDurationChosen(seconds: 1.0 / 24)
    check(r.p.demand == P.Demand(running: true, width: 1920, height: 1080, fps: 24, apps: [faceTime, booth]), "its size and rate")
    r.p.clientLeft(other, pid: 412)
    check(r.p.demand.apps == [booth], "an app that left is not")
    r.p.sourceStopped()
    r.p.sourceStarted()
    check(r.p.demand.apps.isEmpty, "a stopped stream forgets its apps")
    check(r.p.appsNow(Array(repeating: faceTime, count: 20)) && r.p.apps.count == 16, "at most 16 apps")
    check(!r.p.formatChosen(2) && !r.p.formatChosen(-1) && r.p.formatIndex == 1, "a format Sill Camera does not offer: refused")
    var s = Run.live()
    _ = s.frame()
    check(s.p.formatChosen(0) && s.p.frameAt != nil, "the same format again keeps the frame")
    s.p.clientLeft(sill, pid: 99)
    check(s.p.feeder == nil && s.p.frameAt == nil && line(s.tick(after: 0.05)) == P.Copy.noSill, "the feeder left: its frame never again")
}

// MARK: - Apps that start and stop the stream

do {
    var r = Run()
    r.p.sourceStarted()
    r.p.sourceStarted()
    r.p.sourceStopped()
    check(r.p.running, "two apps started it, one stopped: it runs")
    r.p.sourceStopped()
    check(!r.p.running && r.tick() == nil, "the last stop ends the run")
    r.p.sourceStopped()
    r.p.sourceStarted()
    check(r.p.running && r.p.starts == 1, "a stop too many changes nothing: the next start runs it")
}

// MARK: - 20,000 random lives

var lives = 0, framesSent = 0, placeholdersSent = 0, deviceWords = 0, retiredSeen = 0, steadyJudged = 0
var rng = Rand(state: 0x5111_CA)
let names = ["iPad", "Noah’s iPhone", "iPad\nSoftware Update", "  "]
outer: for life in 0..<20_000 {
    var p = P()
    var t: Double = 0
    // The check's own record of what happened, to judge the policy's answers by; `seq` orders events at one time.
    var seq = 0
    var feeding: UUID?
    var said: P.Show?
    var fmt = 0
    var lastFrame: (at: Double, seq: Int, format: Int)?
    var retiredSeq = -1
    var running = false
    var starts = 0
    var nilTicks = 0
    let steady = rng.chance(0.3)
    func isLive(_ s: P.Show?) -> Bool { if case .device(_, false)? = s { return true }; return false }
    for _ in 0..<rng.int(20...160) {
        seq += 1
        switch rng.int(0...99) {
        case 0..<8:
            let client = [sill, sill2, other][rng.int(0...2)]
            let id = client == other ? ["com.example.camera", nil, "me.saffer.sill.mac.camera"][rng.int(0...2)] : P.sillIdentifier
            let sig: Bool? = [true, nil, false][rng.int(0...2)]
            let v = p.sinkStart(client: client, signingID: id, signatureValid: sig)
            let want: P.SinkVerdict = id == nil ? .unsigned : id != P.sillIdentifier ? .notSill : sig == false ? .signature
                : (feeding != nil && feeding != client) ? .busy : .accept
            if v != want { check(false, "life \(life): a feed from \(id ?? "nil") (signature \(String(describing: sig))) was \(v), the rule \(want)"); break outer }
            if v == .accept { feeding = client }
        case 8..<12:
            let client = [sill, sill2, other][rng.int(0...2)]
            if rng.chance(0.5) { p.sinkStop(client: client) } else { p.clientLeft(client, pid: Int32(rng.int(1...4))) }
            if client == feeding { feeding = nil; said = nil; lastFrame = nil; retiredSeq = seq }
        case 12..<24:
            let s: P.Show = rng.chance(0.6) ? .device(name: names[rng.chance(0.9) ? rng.int(0...2) : 3], paused: rng.chance(0.2))
                : [P.Show.off, .unavailable, .waiting][rng.int(0...2)]
            let text = rng.chance(0.1) ? "{\"show\":\"device\"}" : P.encode(s)
            let taken = p.stateWritten(text)
            let reads = P.decode(text)
            if taken != (feeding != nil && reads != nil) { check(false, "life \(life): a state taken \(taken) while feeding \(feeding != nil)"); break outer }
            if taken, let n = reads {
                var keeps = false
                if case .device(let a, false) = n, case .device(let b, false)? = said { keeps = a == b }
                if !keeps { lastFrame = nil; retiredSeq = seq; retiredSeen += 1 }
                said = n
            }
        case 24..<56:
            t += rng.chance(0.5) ? 0.0 : Double(rng.int(1...40)) / 1000
            let client = [sill, sill, sill2, other][rng.int(0...3)]
            let size = rng.chance(0.85) ? P.formats[fmt] : P.formats[1 - fmt]
            let pixels: UInt32 = rng.chance(0.95) ? P.pixelFormat : 0x3432_3066
            let more = rng.chance(0.15)
            let v = p.frame(from: client, width: size.width, height: size.height, pixelFormat: pixels, more: more, at: t)
            let want: P.FrameVerdict = client != feeding ? .notFeeder : !isLive(said) ? .notLive : pixels != P.pixelFormat ? .wrongFormat
                : size != P.formats[fmt] ? .wrongSize : (running && !more) ? .send : .kept
            if v != want { check(false, "life \(life): a frame was \(v), the rule \(want)"); break outer }
            if v == .send || v == .kept { lastFrame = (t, seq, fmt) }
            if v == .send { framesSent += 1; nilTicks = 0 }
        case 56..<60:
            let i = rng.int(-1...2)
            let ok = p.formatChosen(i)
            if ok != (0...1).contains(i) { check(false, "life \(life): format \(i) taken \(ok)"); break outer }
            if ok, i != fmt { fmt = i; lastFrame = nil; retiredSeq = seq }
        case 60..<62:
            p.frameDurationChosen(seconds: [1.0 / 30, 1.0 / 15, 1.0 / 24, 0, 1.0 / 60][rng.int(0...4)])
        case 62..<66:
            if rng.chance(0.55) { p.sourceStarted(); starts += 1 } else { p.sourceStopped(); starts = max(0, starts - 1) }
            running = starts > 0
            nilTicks = 0
        case 66..<68:
            _ = p.appsNow((0..<rng.int(0...3)).map { P.App(id: "app\($0)", pid: Int32($0 + 1)) })
        default:
            t += steady ? P.tickInterval : [0.001, 0.01, P.tickInterval, 0.05, 0.3, 1.2][rng.int(0...5)]
            let out = p.tick(at: t)
            if !running, out != nil { check(false, "life \(life): something went out while no app runs the stream"); break outer }
            let fresh = lastFrame.map { $0.seq > retiredSeq && $0.format == fmt && t - $0.at < P.frameLifetime } ?? false
            switch out {
            case .frame?:
                framesSent += 1
                if !(fresh && feeding != nil && isLive(said)) {
                    check(false, "life \(life): a picture went out that may not (\(String(describing: lastFrame)), retired at \(retiredSeq), feeding \(feeding != nil), said \(String(describing: said)))")
                    break outer
                }
                nilTicks = 0
            case .placeholder(let ph)?:
                placeholdersSent += 1
                if fresh, feeding != nil, isLive(said) { check(false, "life \(life): the placeholder over a live frame"); break outer }
                let want: String
                switch (feeding, said) {
                case (nil, _): want = P.Copy.noSill
                case (_, nil), (_, .unavailable?): want = P.Copy.unavailable
                case (_, .off?): want = P.Copy.off
                case (_, .waiting?): want = P.Copy.waiting
                case (_, .device(let n, let paused)?): want = paused ? P.Copy.paused(n) : P.Copy.starting(n)
                }
                if ph.line != want || ph.title != P.Copy.title || ph.format != P.formats[fmt] {
                    check(false, "life \(life): the placeholder said \(ph), the rule \(want)"); break outer
                }
                let named = names.map(P.cleanName).filter { !$0.isEmpty && ph.line.contains("\($0)’s camera") }
                if !named.isEmpty {
                    deviceWords += 1
                    guard case .device(let n, _)? = said, named.contains(n) else {
                        check(false, "life \(life): a placeholder names \(named) while the state is \(String(describing: said))"); break outer
                    }
                }
                nilTicks = 0
            case nil:
                if steady, running {
                    nilTicks += 1
                    steadyJudged += 1
                    // At 15 fps a frame duration is four ticks: never more than four ticks running without anything.
                    if nilTicks > 4 { check(false, "life \(life): \(nilTicks) ticks without anything while an app runs the stream"); break outer }
                }
            }
        }
        if p.feeder == nil, p.show != nil || p.frameAt != nil { check(false, "life \(life): nothing feeds, yet something is said or kept"); break outer }
        if p.feeder != feeding || p.show != said || p.formatIndex != fmt {
            check(false, "life \(life): feeder \(String(describing: p.feeder)), state \(String(describing: p.show)), format \(p.formatIndex); the rule \(String(describing: feeding)), \(String(describing: said)), \(fmt)")
            break outer
        }
        if p.demand.running != running || (!running && !p.demand.apps.isEmpty) { check(false, "life \(life): the demand \(p.demand) while running \(running)"); break outer }
    }
    lives += 1
}
check(lives == 20_000, "every life ran to its end (\(lives))")
check(framesSent > 25_000 && placeholdersSent > 100_000 && deviceWords > 30_000 && retiredSeen > 50_000 && steadyJudged > 30_000,
      "the lives reached every part: \(framesSent) pictures out, \(placeholdersSent) placeholders, \(deviceWords) naming a device, \(retiredSeen) frames retired by a state, \(steadyJudged) steady ticks judged")
print("lives: \(framesSent) pictures out, \(placeholdersSent) placeholders, \(deviceWords) naming a device, \(retiredSeen) states retiring a frame, \(steadyJudged) steady ticks judged")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
