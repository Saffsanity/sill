import Foundation

// RecordingNotice (Sources/SillHost/RecordingNotice.swift; #284, docs/recording-plan.md), compiled with it as one
// module (module.txt, -package-name sill): what the Mac says of a device recording the stream. Its window lists'
// `recordings`, the log's words, and each connection's lines from the device's once-a-second reports
// (ClientStats.recording): scripted sessions, then 20,000 random ones against the invariants.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias N = RecordingNotice
typealias Line = RecordingNotice.Line

// MARK: - The numbers and the words

check(N.generation == 1, "generation 1 (the window list's recordings): this host's menu and log say it")
check(N.lineSpacing == 10, "at most a line every 10 s per connection: \(N.lineSpacing)")
let words: [(Line, String, String)] = [
    (Line(event: .started, held: 0), "iPad (iPad14,1)", "Recording: iPad (iPad14,1) started recording the stream."),
    (Line(event: .stopped, held: 0), "iPad (iPad14,1)", "Recording: iPad (iPad14,1) stopped recording the stream."),
    (Line(event: .left, held: 0), "iPhone (iPhone17,1)", "Recording: iPhone (iPhone17,1) left while recording the stream."),
    (Line(event: .stopped, held: 1), "iPad", "Recording: iPad stopped recording the stream. (1 more change since the last line)"),
    (Line(event: .started, held: 3), "iPad", "Recording: iPad started recording the stream. (3 more changes since the last line)"),
    (Line(event: .left, held: 2), "192.168.1.23:52344",
     "Recording: 192.168.1.23:52344 left while recording the stream. (2 more changes since the last line)"),
]
for (line, device, want) in words {
    let got = N.text(line, device: device)
    check(got == want, "the words for \(line): \(got)")
}

// MARK: - Scripted sessions

/// A session's reports (seconds, recording), then its close when `close`: each line with its report's time
/// (nil for the close's).
func session(_ reports: [(Double, Bool)], close: Bool = true) -> [(at: Double?, line: Line)] {
    var lines = N.Lines()
    var out: [(at: Double?, line: Line)] = []
    for (t, r) in reports { if let l = lines.report(recording: r, at: t) { out.append((t, l)) } }
    if close, let l = lines.closed() { out.append((nil, l)) }
    return out
}
/// Reports once a second from `from` to `to`, recording while `on` says.
func everySecond(_ from: Int, _ to: Int, _ on: (Double) -> Bool) -> [(Double, Bool)] {
    (from...to).map { (Double($0), on(Double($0))) }
}
func same(_ a: [(at: Double?, line: Line)], _ b: [(Double?, RecordingNotice.Event, Int)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.at == $1.0 && $0.line.event == $1.1 && $0.line.held == $1.2 }
}
func show(_ a: [(at: Double?, line: Line)]) -> String {
    a.isEmpty ? "no line" : a.map { "\($0.at.map { "\($0) s" } ?? "close"): \($0.line.event) +\($0.line.held)" }.joined(separator: ", ")
}

// A device that never records: no line, at its close neither.
let never = session(everySecond(0, 60) { _ in false })
check(never.isEmpty, "never recording: \(show(never))")
// Started at 2 s, stopped at 30 s: a line at each, nothing more at the close.
let plain = session(everySecond(0, 40) { $0 >= 2 && $0 < 30 })
check(same(plain, [(2, .started, 0), (30, .stopped, 0)]), "a start and a stop 28 s apart: \(show(plain))")
// Stopped 6 s after the start: held, then written by the first report 10 s after the start's line.
let quick = session(everySecond(0, 20) { $0 >= 2 && $0 < 8 })
check(same(quick, [(2, .started, 0), (12, .stopped, 0)]), "a stop within 10 s waits for the spacing: \(show(quick))")
// The same session closing at 11 s, before the spacing is over: the stop is written at the close.
let quickClosed = session(everySecond(0, 11) { $0 >= 2 && $0 < 8 })
check(same(quickClosed, [(2, .started, 0), (nil, .stopped, 0)]), "a held stop is written as the connection closes: \(show(quickClosed))")
// The spacing's edge: 9.999 s after the last line holds, 10 s writes.
let edge = session([(0, true), (5, false), (9.999, false), (10, false)], close: false)
check(same(edge, [(0, .started, 0), (10, .stopped, 0)]), "10 s after the last line, not 9.999: \(show(edge))")
// Closed while recording: it left while recording, whatever the spacing.
let left = session([(1, true), (2, true), (3, true)])
check(same(left, [(1, .started, 0), (nil, .left, 0)]), "closed while recording: \(show(left))")
// Stopped and started again within the spacing, then closed: it left while recording, the two changes held.
let again = session([(0, true), (2, false), (4, true), (6, true)])
check(same(again, [(0, .started, 0), (nil, .left, 2)]), "a stop and a start held, then closed: \(show(again))")
// The same with the spacing over: the start written again, with the two changes it held.
let restated = session([(0, true), (2, false), (4, true), (10, true)], close: false)
check(same(restated, [(0, .started, 0), (10, .started, 2)]), "a stop and a start held, then said: \(show(restated))")
// A start held after a stop, then closed: it left while recording, the start that line's own.
let heldStart = session([(0, true), (15, false), (20, true), (22, true)])
check(same(heldStart, [(0, .started, 0), (15, .stopped, 0), (nil, .left, 0)]), "a held start, then closed: \(show(heldStart))")
// A flood: the field flipped every 0.2 s from 3 s to 9 s (31 changes, the last to recording), then off from
// 10 s on (32 changes): two lines, the second at 13 s saying the 30 it does not say itself.
var flood: [(Double, Bool)] = (0...30).map { (3 + Double($0) / 5, $0 % 2 == 0) }
flood += (10...30).map { (Double($0), false) }
let floodLines = session(flood)
check(same(floodLines, [(3, .started, 0), (13, .stopped, 30)]), "a flood of 32 changes: \(show(floodLines))")
// A report of the same state is never a line.
let steady = session([(0, true)] + (1...100).map { (Double($0) / 10, true) }, close: false)
check(same(steady, [(0, .started, 0)]), "the same state again and again: \(show(steady))")
// The close, once.
var twice = N.Lines()
_ = twice.report(recording: true, at: 0)
check(twice.closed() == Line(event: .left, held: 0) && twice.closed() == nil, "a second close says nothing")
var silent = N.Lines()
check(silent.closed() == nil, "a connection that never reported: nothing at its close")

// MARK: - 20,000 random sessions against the invariants

/// SplitMix64, seeded: every run the same.
struct Random {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}
var rng = Random(state: 284)
var broken = 0
func broke(_ what: String) {
    if broken < 10 { print("random: \(what)") }
    broken += 1
}
var linesSeen = 0, closesSeen = 0, leftSeen = 0
for run in 0..<20_000 {
    // The device's changes: a recording of minutes, of seconds, or a flood of a fifth of a second.
    let mean = [30.0, 4.0, 0.2][Int(rng.next() % 3)]
    let duration = 5 + rng.unit() * 115
    var changesAt: [Double] = []
    var t = rng.unit() * mean
    while t < duration {
        changesAt.append(t)
        t += max(0.01, -log(max(1e-12, rng.unit())) * mean)
    }
    // Reports: once a second with a little jitter, and one at each change (as sillclient.py sends them).
    var reportsAt: [Double] = []
    var r = rng.unit()
    while r < duration {
        reportsAt.append(r)
        r += 0.9 + rng.unit() * 0.2
    }
    reportsAt = (reportsAt + changesAt).sorted()
    var lines = N.Lines()
    var said = false          // what the lines so far said, as a reader of the log takes them
    var accounted = 0         // the changes the lines so far said or counted
    var lastReportLine: Double?
    var changed = 0           // the changes up to now
    var next = 0              // the next change in changesAt
    for at in reportsAt {
        while next < changesAt.count, changesAt[next] <= at { next += 1; changed += 1 }
        let now = changed % 2 == 1
        if let line = lines.report(recording: now, at: at) {
            linesSeen += 1
            if let last = lastReportLine, at - last < N.lineSpacing { broke("run \(run): lines at \(last) and \(at), under the spacing") }
            lastReportLine = at
            if line.event == .left || (line.event == .started) != now { broke("run \(run): \(line) at \(at), recording \(now)") }
            let own = (line.event != .stopped) != said ? 1 : 0
            if line.held < 0 || line.held + own < 1 { broke("run \(run): \(line) at \(at) accounts for no change") }
            accounted += line.held + own
            said = line.event == .started
        }
        if lines.recording != now { broke("run \(run): holds \(lines.recording) at \(at), the device \(now)") }
        if lines.said != said { broke("run \(run): says \(lines.said) at \(at), its lines \(said)") }
        if accounted + lines.changes != changed { broke("run \(run): \(accounted) said + \(lines.changes) pending, \(changed) changes at \(at)") }
        // The log comes to say what the device does by the first report once the spacing is over.
        if lines.said != now, lines.lastLineAt.map({ at - $0 >= N.lineSpacing }) ?? true {
            broke("run \(run): at \(at) the log says \(lines.said), the device \(now), the last line at \(String(describing: lines.lastLineAt))")
        }
    }
    // Most sessions end with a close.
    guard rng.next() % 4 != 0 else { continue }
    closesSeen += 1
    let pending = lines.changes, recording = lines.recording
    let line = lines.closed()
    if recording {
        if line?.event != .left { broke("run \(run): closed while recording: \(String(describing: line))") } else { leftSeen += 1 }
    } else if pending > 0 {
        if line?.event != .stopped { broke("run \(run): closed with \(pending) held: \(String(describing: line))") }
    } else if let line {
        broke("run \(run): closed with nothing to say: \(line)")
    }
    if let line {
        // "Left while recording" may say no change (a recording the log already said); a stop says one at least.
        let own = (line.event != .stopped) != said ? 1 : 0
        if line.held < 0 || (line.event == .stopped && line.held + own < 1) { broke("run \(run): the close's \(line) accounts for no change") }
        accounted += line.held + own
    }
    if accounted != changed { broke("run \(run): closed with \(accounted) of \(changed) changes said or counted") }
    if lines.closed() != nil { broke("run \(run): a second close said something") }
}
check(broken == 0, "20,000 random sessions (\(linesSeen) lines, \(closesSeen) closes, \(leftSeen) left while recording): \(broken) broke an invariant")
check(linesSeen > 50_000 && leftSeen > 1_000, "the random sessions reach the rule: \(linesSeen) lines, \(leftSeen) left while recording")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
