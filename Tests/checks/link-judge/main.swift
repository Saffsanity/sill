// H10 (docs/remote-bundle-plan.md §6 and §11): Sources/SillHost/LinkJudge.swift on its own, compiled
// with StreamProtocol's HostSettings.swift (QualityPreset) as one module by build.sh:
//
//   Tests/checks/link-judge/build.sh . .build/checks/link-judge/check && .build/checks/link-judge/check
//
// What it checks: a short second; behind at exactly 3 short seconds of the last 5, fine again after 5
// clean ones in a row, still seconds as clean; stalled after 3 seconds with bytes waiting, none taken
// and nothing heard, and not when the device was heard (a keyframe crossing a slow link); the stall's
// end, to behind or to fine; a restart's reset, and which restarts judge afresh (another quality, or
// no stream: never one that keeps it); the carried rate (3 measured seconds, their mean); the
// report once more when the rate is first measured, once a spell; the suggestion at 60 and 120 fps,
// Low when none fits, one step down without a measure, Standard only with Low from Retina, the same
// bitrate at Standard below Low, nothing at Low · Standard, never higher; the host's lines. Then a
// model of the rules against 20,000 random runs. (The rule that frames before a device's first
// keyframe do not count is StreamServer's, not the judge's: the pacing harness's slowkfB case, H11,
// fails without it.)
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok" : "FAIL") \(what)")
    if !ok { failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias S = LinkJudge.Second
/// A short second (6 of 60 withheld), a clean one (60 sent), a still one (nothing), and one of a dead
/// path (nothing taken, bytes waiting, nothing heard).
let short = S(sent: 54, withheld: 6, taken: 100_000, waiting: 50_000, heard: true)
let clean = S(sent: 60, withheld: 0, taken: 300_000, waiting: 4_000, heard: true)
let still = S(sent: 0, withheld: 0, taken: 200, waiting: 0, heard: true)
let dead = S(sent: 0, withheld: 40, taken: 0, waiting: 900_000, heard: false)

/// The states after each second, and the verdicts' states (with `r` for a reset), as strings.
func run(_ seconds: [S], judge: LinkJudge = LinkJudge()) -> (states: String, verdicts: [LinkJudge.Verdict], judge: LinkJudge) {
    var j = judge
    var states: [String] = []
    var verdicts: [LinkJudge.Verdict] = []
    for s in seconds {
        if let v = j.close(s) { verdicts.append(v) }
        states.append(["fine": "F", "behind": "B", "stalled": "S"]["\(j.state)"]!)
    }
    return (states.joined(), verdicts, j)
}

// MARK: A short second

check(!LinkJudge.isShort(S(sent: 58, withheld: 2, taken: 0, waiting: 0, heard: true)), "2 of 60 withheld is not short")
check(!LinkJudge.isShort(S(sent: 57, withheld: 3, taken: 0, waiting: 0, heard: true)), "3 of 60 is not short (5 %)")
check(LinkJudge.isShort(S(sent: 54, withheld: 6, taken: 0, waiting: 0, heard: true)), "6 of 60 is short (10 %)")
check(LinkJudge.isShort(S(sent: 17, withheld: 3, taken: 0, waiting: 0, heard: true)), "3 of 20 is short")
check(!LinkJudge.isShort(S(sent: 0, withheld: 0, taken: 0, waiting: 0, heard: true)), "a still second is not short")
check(LinkJudge.isShort(S(sent: 0, withheld: 3, taken: 0, waiting: 0, heard: true)), "3 withheld and none sent is short")

// MARK: Behind and fine again

eq(run([short, short]).states, "FF", "2 short seconds stay fine")
eq(run([short, short, short]).states, "FFB", "behind at the third short second")
eq(run([short, clean, short, clean, short]).states, "FFFFB", "behind at 3 short of 5")
eq(run([short, clean, clean, clean, short, short]).states, "FFFFFF", "3 short in 6 but only 2 in the last 5: fine")
let behind3 = [short, short, short]
eq(run(behind3 + [clean, clean, clean, clean]).states, "FFBBBBB", "4 clean seconds in a row stay behind")
eq(run(behind3 + [clean, clean, clean, clean, clean]).states, "FFBBBBBF", "fine after 5 clean seconds in a row")
eq(run(behind3 + [clean, clean, still, still, clean]).states, "FFBBBBBF", "still seconds count as clean")
eq(run(behind3 + [clean, clean, clean, clean, short, clean, clean, clean, clean, clean]).states, "FFBBBBBBBBBBF",
   "a short second restarts the clean count")
do {
    let r = run(behind3 + [clean, clean, clean, clean, clean])
    eq(r.verdicts.map { "\($0.state)" }, ["behind", "fine"], "one report at behind and one at fine")
    check(r.verdicts.allSatisfy { !$0.reset }, "…neither a reset")
    eq(r.verdicts.first?.withheld, 6, "the report carries the second's withheld frames")
    eq(r.verdicts.first?.offered, 60, "…of the second's offered frames")
}

// MARK: Stalled

eq(run([dead, dead]).states, "FF", "2 dead seconds stay fine")
eq(run([dead, dead, dead]).states, "FFS", "stalled at the third dead second")
do {
    var heard = dead; heard.heard = true
    eq(run([heard, heard, heard]).states, "FFB", "3 seconds of nothing taken while the device was heard: not stalled (behind, frames withheld)")
    var slowKeyframe = still; slowKeyframe.taken = 0; slowKeyframe.waiting = 1_600_000
    eq(run([slowKeyframe, slowKeyframe, slowKeyframe, slowKeyframe]).states, "FFFF",
       "a keyframe crossing a slow link (nothing taken, bytes waiting, the device pinging): fine")
    var empty = dead; empty.waiting = 0
    eq(run([empty, empty, empty]).states, "FFB", "nothing taken and nothing waiting is no stall")
    var takenAlone = dead; takenAlone.taken = 5_000
    eq(run([dead, dead, takenAlone, dead, dead]).states, "FFBBB", "a second with bytes taken breaks the stall count")
}
eq(run([dead, dead, dead, dead]).states, "FFSS", "stalled while it lasts")
do {
    var back = clean; back.heard = true
    eq(run([dead, dead, dead, back]).states, "FFSB", "a stall ends at the first second anything is taken or heard: behind (3 of 5 short)")
    let r = run([clean, clean, clean, still, still]).judge
    var quiet = dead; quiet.withheld = 0
    eq(run([quiet, quiet, quiet, clean], judge: r).states, "FFSF", "…fine when fewer than 3 of the last 5 were short")
    var heardOnly = dead; heardOnly.heard = true; heardOnly.withheld = 0
    eq(run([quiet, quiet, quiet, heardOnly], judge: r).states, "FFSF", "…and ends as soon as the device is heard, nothing taken")
}
do {
    let r = run(behind3 + [dead, dead, dead, clean, clean, clean, clean, clean, clean])
    // The second that ends the stall is the first of the 5 clean ones.
    eq(r.states, "FFBBBSBBBBFF", "behind → stalled → behind → fine")
    // Between the changes, reports that only carry the rate as it falls (a quarter or more each).
    let changes = r.verdicts.map { "\($0.state)" }.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
    eq(changes, ["behind", "stalled", "behind", "fine"], "…a report at each change")
    eq(r.verdicts[1].waiting, 900_000, "the stalled report carries what waits")
}

// MARK: A restart

do {
    var r = run(behind3).judge
    let v = r.reset()
    check(v?.state == .fine && v?.reset == true, "a reset from behind reports fine, marked as a reset")
    eq(r.state, .fine, "…and the state is fine")
    eq(run([short, short], judge: r).states, "FF", "…and the window is cleared: 2 short seconds after it stay fine")
    var f = LinkJudge()
    check(f.reset() == nil, "a reset from fine reports nothing")
    var s = run([dead, dead, dead]).judge
    check(s.reset()?.reset == true, "a reset from stalled reports fine, marked as a reset")
}
do {
    // Which restarts judge afresh (the review of 2026-09-27): another quality, or no stream; never a
    // restart that keeps it (a window picked, a rotation), which clearing made the device's line go
    // and come back, spoken again.
    typealias Q = LinkJudge.Quality
    let pro = Q(bitrate: 40_000_000, fps: 60, captureScale: 2)
    check(!LinkJudge.judgedAfresh(from: pro, to: pro), "a restart at the same quality keeps the judgement")
    check(LinkJudge.judgedAfresh(from: pro, to: Q(bitrate: 4_000_000, fps: 60, captureScale: 2)), "another bitrate: afresh")
    check(LinkJudge.judgedAfresh(from: pro, to: Q(bitrate: 40_000_000, fps: 120, captureScale: 2)), "another rate: afresh")
    check(LinkJudge.judgedAfresh(from: pro, to: Q(bitrate: 40_000_000, fps: 60, captureScale: 1)),
          "another resolution alone: afresh (the suggestion Low · Standard from Low · Retina is that)")
    check(LinkJudge.judgedAfresh(from: Q(bitrate: 8_000_000, fps: 60, captureScale: 1), to: Q(bitrate: 4_000_000, fps: 120, captureScale: 1)),
          "the same bits a second at another bitrate and rate: afresh (the report names the bitrate per 60 fps)")
    check(LinkJudge.judgedAfresh(from: pro, to: nil), "the stream stops: afresh")
    check(LinkJudge.judgedAfresh(from: nil, to: pro), "a stream starts: afresh")
    check(!LinkJudge.judgedAfresh(from: nil, to: nil), "nothing streamed and nothing streams: nothing to do")
}

// MARK: The carried rate

do {
    func m(_ taken: Int) -> S { S(sent: 30, withheld: 30, taken: taken, waiting: 200_000, heard: true) }
    var j = LinkJudge()
    _ = j.close(m(0)); _ = j.close(m(0))
    check(j.carriedKbps == nil, "the carried rate needs 3 measured seconds")
    _ = j.close(m(2_250_000))
    eq(j.carriedKbps, 6_000, "0, 0 and 2.25 MB read 6 Mbps (a mean; a median would read 0)")
    var k = LinkJudge()
    for taken in [1_000_000, 1_000_000] { _ = k.close(m(taken)) }
    _ = k.close(S(sent: 60, withheld: 0, taken: 5_000_000, waiting: 16 * 1024 - 1, heard: true))
    check(k.carriedKbps == nil, "a second that ended with under 16 KB waiting is not measured")
    _ = k.close(S(sent: 60, withheld: 0, taken: 400_000, waiting: 16 * 1024, heard: true))
    eq(k.carriedKbps, 6_400, "one that ended with 16 KB is: (1 + 1 + 0.4 MB) / 3 = 6.4 Mbps")
    var w = LinkJudge()
    for taken in [1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 4_000_000] { _ = w.close(m(taken)) }
    eq(w.carriedKbps, 12_800, "only the last 5 seconds count: (4 × 1 + 4 MB) / 5 = 12.8 Mbps")
}
do {
    func m(_ withheld: Int) -> S { S(sent: 60 - withheld, withheld: withheld, taken: 750_000, waiting: 300_000, heard: true) }
    let r = run([m(20), m(20), m(20), m(20), m(20), m(20)])
    eq(r.verdicts.count, 1, "behind with its rate measured at once: one report, not another for the rate")
    check(r.verdicts.first?.carriedKbps == 6_000, "…carrying the rate: 6 Mbps")
    var unmeasured = m(20); unmeasured.waiting = 1_000
    let late = run([unmeasured, unmeasured, unmeasured, m(20), m(20), m(20), m(20)])
    eq(late.verdicts.map { $0.carriedKbps == nil ? "nil" : "rate" }, ["nil", "rate"], "behind without a rate, then one report when it is measured")
    let twice = run([unmeasured, unmeasured, unmeasured, m(20), m(20), m(20), m(20), m(20), m(20)])
    eq(twice.verdicts.count, 2, "…and none after that within the spell")
    // The first seconds read high while the buffers fill: a rate that moves by a quarter or more is
    // reported again, one that moves less is not.
    func t(_ taken: Int) -> S { S(sent: 40, withheld: 20, taken: taken, waiting: 300_000, heard: true) }
    let settling = run([t(1_500_000), t(1_500_000), t(1_500_000), t(1_000_000), t(1_000_000), t(1_000_000), t(1_000_000), t(1_000_000), t(1_000_000)])
    eq(settling.verdicts.map { $0.carriedKbps ?? -1 }, [12_000, 8_800],
       "a rate settling from 12 to 8 Mbps: 12, then 8.8 once it had moved 27 % (8 is 9 % from that: not again)")
    let steady = run([t(1_000_000), t(1_000_000), t(1_000_000), t(1_100_000), t(900_000), t(1_000_000), t(1_150_000)])
    eq(steady.verdicts.count, 1, "a rate that wanders by less than a quarter is not reported again")
    let again = run([unmeasured, unmeasured, unmeasured, m(20), m(20), m(20)] + Array(repeating: clean, count: 5)
                    + [unmeasured, unmeasured, unmeasured, m(20), m(20), m(20)])
    eq(again.verdicts.map { "\($0.state)\($0.carriedKbps == nil ? "" : "+")" }, ["behind", "behind+", "fine", "behind", "behind+"],
       "a new spell reports its rate again once it is measured")
}

// MARK: The suggestion

func sug(_ carried: Int?, _ bitrate: Int, fps: Int = 60, scale: Double = 2) -> String {
    guard let s = LinkJudge.suggestion(carriedKbps: carried, bitrate: bitrate, fps: fps, captureScale: scale) else { return "nil" }
    return "\(s.bitrate / 1_000_000)/\(s.captureScale.map { "\(Int($0))" } ?? "-")"
}
eq(sug(30_000, 40_000_000), "15/-", "Pro on a link that carried 30 Mbps: Balanced (the highest ≤ 21 Mbps at 60 fps)")
eq(sug(30_000, 40_000_000, fps: 120), "8/-", "…at 120 fps: Efficient (16 Mbps ≤ 21; Balanced would be 30)")
eq(sug(35_800, 40_000_000), "25/-", "a link that carried 35.8 Mbps fits High (25 ≤ 25.06)")
eq(sug(35_700, 40_000_000), "15/-", "…35.7 Mbps does not (25 > 24.99)")
eq(sug(3_000, 40_000_000), "4/1", "none fits (3 Mbps carried): Low, with Standard from Retina")
eq(sug(3_000, 40_000_000, scale: 1), "4/-", "…and Low alone at Standard")
eq(sug(nil, 40_000_000), "25/-", "without a measure: one step down (Pro → High)")
eq(sug(nil, 150_000_000), "80/-", "…Extreme → Ultra")
eq(sug(nil, 8_000_000), "4/1", "…Efficient → Low, with Standard from Retina")
eq(sug(nil, 8_000_000, scale: 1), "4/-", "…Low alone from Efficient at Standard")
eq(sug(20_000, 15_000_000), "8/-", "Balanced on 20 Mbps: Efficient, no resolution named")
eq(sug(nil, 4_000_000), "4/1", "Low · Retina: the same bitrate at Standard")
eq(sug(nil, 2_000_000), "2/1", "a hand-set 2 Mbps at Retina: the same bitrate at Standard")
eq(sug(5_000, 4_000_000, scale: 1), "nil", "Low · Standard: nothing lower")
eq(sug(nil, 2_000_000, scale: 1), "nil", "2 Mbps · Standard: nothing lower")
eq(sug(1_000_000, 40_000_000), "25/-", "never above the running bitrate: a gigabit link from Pro is High")
eq(sug(1_000_000, 30_000_000), "25/-", "a hand-set 30 Mbps: High is the highest below it")
eq(sug(nil, 30_000_000, scale: 1), "25/-", "…one step down from it without a measure")

// MARK: The lines

eq(LinkJudge.behindLine(device: "iPad (iPad14,1)", bitrate: 40_000_000, withheld: 52, offered: 58, carriedKbps: 6_400,
                        suggestion: (4_000_000, 1)),
   "Link to iPad (iPad14,1): cannot carry Pro (withheld 52 of 58 frames in the last second; the link carried about 6.4 Mbps); suggesting Low · Standard.",
   "the behind line with a rate and a suggestion that names a resolution")
eq(LinkJudge.behindLine(device: "iPad (iPad14,1)", bitrate: 150_000_000, withheld: 57, offered: 60, carriedKbps: nil,
                        suggestion: (80_000_000, nil)),
   "Link to iPad (iPad14,1): cannot carry Extreme (withheld 57 of 60 frames in the last second); suggesting Ultra.",
   "the behind line without a rate")
eq(LinkJudge.behindLine(device: "iPad (iPad14,1)", bitrate: 4_000_000, withheld: 20, offered: 45, carriedKbps: 2_100, suggestion: nil),
   "Link to iPad (iPad14,1): cannot carry Low (withheld 20 of 45 frames in the last second; the link carried about 2.1 Mbps); nothing lower to suggest.",
   "the behind line with nothing lower")
eq(LinkJudge.stalledLine(device: "iPad (iPad14,1)", waiting: 1_200_000),
   "Link to iPad (iPad14,1): nothing has got through for 3 s, and nothing has come from it (1.2 MB waiting).", "the stalled line")
eq(LinkJudge.fineLine(device: "iPad (iPad14,1)"), "Link to iPad (iPad14,1): keeping up again.", "the fine line")
eq([12_000, 800, 6_449, 6_450].map { LinkJudge.mbps(kbps: $0) }, ["12", "0.8", "6.4", "6.5"], "rates: 12, 0.8, 6.4, 6.5 Mbps")
eq([2_000_000, 1_249_999, 640_000, 999_499].map { LinkJudge.bytes($0) }, ["2 MB", "1.2 MB", "640 kB", "999 kB"], "sizes")

// MARK: A model against random runs

/// The rules as the plan words them, over the whole history, recomputed every second.
struct Model {
    var history: [S] = []
    var state = LinkJudge.State.fine
    mutating func close(_ s: S) -> Bool {
        history.append(s)
        let last5 = history.suffix(5)
        let shorts = last5.filter { $0.withheld >= 3 && 10 * $0.withheld >= $0.sent + $0.withheld }.count
        func deadRun(_ n: Int) -> Bool {
            history.count >= n && history.suffix(n).allSatisfy { $0.taken == 0 && $0.waiting > 0 && !$0.heard }
        }
        func cleanRun(_ n: Int) -> Bool {
            history.count >= n && history.suffix(n).allSatisfy { !($0.withheld >= 3 && 10 * $0.withheld >= $0.sent + $0.withheld) }
        }
        let before = state
        let isDead = s.taken == 0 && s.waiting > 0 && !s.heard
        switch state {
        case .fine: state = deadRun(3) ? .stalled : (shorts >= 3 ? .behind : .fine)
        case .behind: state = deadRun(3) ? .stalled : (cleanRun(5) ? .fine : .behind)
        case .stalled: if !isDead { state = shorts >= 3 ? .behind : .fine }
        }
        return state != before
    }
}
var generator = SystemRandomNumberGenerator()
var mismatches = 0, changes = 0
for _ in 0..<20_000 {
    var j = LinkJudge(), model = Model()
    for _ in 0..<Int.random(in: 1...40, using: &generator) {
        let kind = Int.random(in: 0..<6, using: &generator)
        let withheld = [0, 1, 2, 3, 6, 30][Int.random(in: 0..<6, using: &generator)]
        let s = S(sent: [0, 20, 54, 60][Int.random(in: 0..<4, using: &generator)], withheld: withheld,
                  taken: kind == 0 ? 0 : [0, 1_000, 500_000][Int.random(in: 0..<3, using: &generator)],
                  waiting: [0, 8_000, 300_000][Int.random(in: 0..<3, using: &generator)], heard: Bool.random(using: &generator))
        let v = j.close(s)
        let changed = model.close(s)
        if changed { changes += 1 }
        if j.state != model.state || (changed && v == nil) || (v?.state != nil && v!.state != model.state) { mismatches += 1 }
    }
}
check(mismatches == 0, "20,000 random runs: the judge's state and reports follow the model (\(changes) changes, \(mismatches) mismatches)")

print(failures == 0 ? "link-judge: all passed" : "link-judge: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
