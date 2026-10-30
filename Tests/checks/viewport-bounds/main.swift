// ViewportBounds (Sources/StreamProtocol/Viewport.swift): what a host takes from a device's viewport
// (kind 9), each side from 1 to 16384 points and a text scale, when there is one, from 0.25 to 4, any
// other viewport refused whole. Until 2026-10-29 a host took any number above 0: a side of 1e300
// points, or a scale of 1e-300, reached the Mac window's fit (StreamCoordinator.fitToViewport) and the
// virtual display's window size, whose log lines turned it into an Int, which traps, and the host died
// with every device's session (security scan, finding 4). Also what a device sends (`held`), the
// numbers the host's lines print (`whole`, `number`), which never trap, and a device's late-sound count
// (ClientStats.lateSince, beside Viewport in Viewport.swift), which the host's stats line adds up and
// which trapped past Int.max too (found in the review of finding 4).
// Compiled with Viewport.swift and the Data helpers it uses (run.sh):
//   swiftc -O Sources/StreamProtocol/Viewport.swift Sources/StreamProtocol/StreamMessage.swift \
//       Tests/checks/viewport-bounds/main.swift
// The rule case by case (the devices' own panels among them), the bug before it in a copy of the
// host's arithmetic, what JSON can carry, then 200,000 random viewports, real and hostile, against the
// rule's properties, then the late count. The virtual display's window size is VirtualDisplaySize's, in
// the capture-scale check.
import CoreGraphics
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { print("ok   \(what())") } else { failures += 1; print("FAIL \(what())") }
}
typealias B = ViewportBounds
func vp(_ w: Double, _ h: Double, _ s: Double?, fps: Int? = nil) -> Viewport { Viewport(width: w, height: h, scale: s, fps: fps) }

/// The Mac window's fit as StreamCoordinator.fitToViewport has it (a copy): its guard, then the target
/// in Mac points. The "Resized …" line printed each side, and the panel's, through Int() until
/// 2026-10-29, which traps when no Int holds the value.
func fitTarget(_ v: Viewport) -> CGSize? {
    guard let textScale = v.scale, textScale > 0, v.width > 0, v.height > 0 else { return nil }
    return CGSize(width: (v.width / textScale).rounded(), height: (v.height / textScale).rounded())
}
/// Int(x) traps: no Int holds `x` toward zero.
func traps(_ x: Double) -> Bool { Int(exactly: x.rounded(.towardZero)) == nil }
func traps(_ s: CGSize) -> Bool { traps(Double(s.width)) || traps(Double(s.height)) }
/// The "Resized …" line's numbers: the target and the panel.
func lineTraps(_ v: Viewport) -> Bool {
    guard let t = fitTarget(v) else { return false }
    return traps(t) || traps(v.width) || traps(v.height)
}

// MARK: - The bounds

check(B.sides == 1...16384 && B.scales == 0.25...4, "each side 1 to 16384 points, a text scale 0.25 to 4")

// The devices' own viewports (Sill.log's panels, 2026-09 and 10): every one taken.
for (w, h, s, what) in [(1117.0, 642.0, nil as Double?, "the iPad mini's landscape panel, Aa never touched"),
                        (1117, 610, 1, "the iPad mini at Aa 1x"), (1376, 1032, 0.5, "an iPad Pro 13-inch at the slider's smallest step"),
                        (377, 235, 1.5, "an iPhone 15 Pro upright at the slider's largest"), (386, 241, 0.75, "an 18 Pro's 16:10 pane"),
                        (424, 422, 1.25, "the 18 Pro Max's Larger Picture room"), (951, 669, 1, "the iPhone Duo's inner display"),
                        (377.33, 235.5, 1, "a panel of fractional points"), (3000, 1600, 0.5, "a Stage Manager window on a large display")] {
    check(B.refusal(vp(w, h, s)) == nil, "taken: \(what) (\(w)×\(h) at \(s.map { "\($0)" } ?? "none"))")
}
check(B.refusal(vp(1, 1, 0.25)) == nil && B.refusal(vp(16384, 16384, 4)) == nil, "the bounds themselves are taken: 1, 16384, 0.25 and 4")
check(B.refusal(vp(1117, 642, nil, fps: 120)) == nil && B.refusal(vp(1117, 642, nil, fps: -5)) == nil,
      "the rate is no part of it (wantedFPS holds it to 24…the Mac's limit)")

// Refused, with the field and its value in the host's line.
check(B.refusal(vp(1e300, 1e300, 1)) == "width 1e+300 (1 to 16384 points), height 1e+300 (1 to 16384 points)",
      "the scan's {\"width\":1e300,\"height\":1e300,\"scale\":1}: both sides refused (\(B.refusal(vp(1e300, 1e300, 1)) ?? "taken"))")
check(B.refusal(vp(-1, 642, nil)) == "width -1 (1 to 16384 points)", "a width of -1 refused, written -1")
check(B.refusal(vp(1117, 0, nil)) == "height 0 (1 to 16384 points)", "a height of 0 refused (no panel to fit)")
check(B.refusal(vp(-0.0, 642, nil)) == "width 0 (1 to 16384 points)", "-0 is 0, refused")
check(B.refusal(vp(0.999, 642, nil)) == "width 0.999 (1 to 16384 points)", "a side just under 1 refused, as it came")
check(B.refusal(vp(16384.001, 642, nil)) == "width 16384.001 (1 to 16384 points)", "a side just over 16384 refused")
check(B.refusal(vp(16385, 642, nil)) == "width 16385 (1 to 16384 points)", "16385 refused, written without .0")
check(B.refusal(vp(.nan, 642, nil)) == "width nan (1 to 16384 points)", "a NaN side refused (in no range)")
check(B.refusal(vp(1117, .infinity, nil)) == "height inf (1 to 16384 points)", "an infinite height refused")
check(B.refusal(vp(-.infinity, 642, nil)) == "width -inf (1 to 16384 points)", "a negative infinity refused")
check(B.refusal(vp(1117, 642, 1e-300)) == "scale 1e-300 (0.25 to 4)", "a scale of 1e-300 refused (it made a finite side infinite)")
check(B.refusal(vp(1117, 642, 0)) == "scale 0 (0.25 to 4)", "a scale of 0 refused")
check(B.refusal(vp(1117, 642, -1)) == "scale -1 (0.25 to 4)", "a negative scale refused")
check(B.refusal(vp(1117, 642, 0.2499)) == "scale 0.2499 (0.25 to 4)" && B.refusal(vp(1117, 642, 4.0001)) == "scale 4.0001 (0.25 to 4)",
      "a scale just outside 0.25 to 4 refused")
check(B.refusal(vp(1117, 642, .nan)) == "scale nan (0.25 to 4)" && B.refusal(vp(1117, 642, .infinity)) == "scale inf (0.25 to 4)",
      "a NaN or infinite scale refused")
check(B.refusal(vp(-1, .nan, 1e300)) == "width -1 (1 to 16384 points), height nan (1 to 16384 points), scale 1e+300 (0.25 to 4)",
      "every field out of its range named, in order")

// MARK: - The bug, in a copy of the host's arithmetic

// The fit's guard took any side and scale above 0, and its line printed them through Int().
check(fitTarget(vp(1e300, 1e300, 1)) != nil && lineTraps(vp(1e300, 1e300, 1)),
      "before: the scan's 1e300 passed the fit's guard, and the \"Resized\" line's Int() of it trapped")
check(fitTarget(vp(1000, 1000, 1e-300)) != nil && lineTraps(vp(1000, 1000, 1e-300)),
      "before: a 1000-point panel at a scale of 1e-300 asked 1e303 points: the line's Int() trapped")
check(fitTarget(vp(1e300, 1e300, 1e-300)).map { $0.width.isInfinite } == true && lineTraps(vp(1e300, 1e300, 1e-300)),
      "before: 1e300 at 1e-300 made the target infinite: the line's Int() trapped")
check(fitTarget(vp(9.3e18, 642, 1)) != nil && lineTraps(vp(9.3e18, 642, 1)), "before: anything past Int.max (9.22e18) trapped")
check(!lineTraps(vp(9.2e18, 642, 1)), "the model: 9.2e18 is an Int, no trap")
// Each of those refused now, so none reaches the fit.
for v in [vp(1e300, 1e300, 1), vp(1000, 1000, 1e-300), vp(1e300, 1e300, 1e-300), vp(9.3e18, 642, 1)] {
    check(B.refusal(v) != nil, "refused now: \(v.width)×\(v.height) at \(v.scale!)")
}
// The largest a host takes: 16384 points at a scale of 0.25, 65536 Mac points; the fit's numbers are Ints.
check(fitTarget(vp(16384, 16384, 0.25)) == CGSize(width: 65536, height: 65536) && !lineTraps(vp(16384, 16384, 0.25)),
      "the largest viewport a host takes asks 65536×65536 points, which the line prints")

// MARK: - What JSON carries (Wire.decode is JSONDecoder's)

func decoded(_ json: String) -> Viewport? { try? JSONDecoder().decode(Viewport.self, from: Data(json.utf8)) }
check(decoded(#"{"width":1e300,"height":1e300,"scale":1}"#).map { $0.width == 1e300 && B.refusal($0) != nil } == true,
      "1e300 decodes, and is refused")
check(decoded(#"{"width":-1,"height":642}"#).map { $0.width == -1 && B.refusal($0) != nil } == true, "-1 decodes, and is refused")
check(decoded(#"{"width":1000,"height":1000,"scale":1e-300}"#).map { B.refusal($0) == "scale 1e-300 (0.25 to 4)" } == true,
      "a scale of 1e-300 decodes, and is refused")
for json in [#"{"width":NaN,"height":642}"#, #"{"width":Infinity,"height":642}"#, #"{"width":1e999,"height":642}"#,
             #"{"width":-1e999,"height":642}"#, #"{"width":"NaN","height":642}"#, #"{"width":1117,"height":642,"fps":1e300}"#,
             #"{"width":1117}"#, #"[]"#, ""] {
    check(decoded(json) == nil, "JSON carries no such viewport: \(json.isEmpty ? "an empty payload" : json) does not decode (the host refuses it as such)")
}
let sent = Viewport(width: 1117, height: 642, scale: 1.5, localCursor: true, fps: 120)
check(decoded(String(decoding: try! JSONEncoder().encode(sent), as: UTF8.self)) == sent && B.refusal(sent) == nil,
      "a device's own viewport, encoded and decoded, is taken")

// MARK: - What a device sends (held)

check(B.held(vp(1117, 642, nil)) == vp(1117, 642, nil) && B.held(vp(377, 235, 1.5, fps: 60)) == vp(377, 235, 1.5, fps: 60),
      "a device's panel goes as it is")
let flagged = Viewport(width: 1117, height: 642, scale: 1, localCursor: true, fps: 120)
check(B.held(flagged) == flagged, "the pointer flag and the rate go as they are")
check(B.held(vp(0, 642, 1)) == nil && B.held(vp(1117, 0, 1)) == nil, "a panel not measured yet (a side of 0) sends nothing")
check(B.held(vp(-5, 642, 1)) == nil && B.held(vp(.nan, 642, 1)) == nil && B.held(vp(1117, .infinity, 1)) == nil,
      "a side that is not a positive number sends nothing")
check(B.held(vp(20000, 642, 1)) == vp(16384, 642, 1), "a side over 16384 goes as 16384")
check(B.held(vp(0.5, 642, nil)) == vp(1, 642, nil), "a side under a point goes as 1")
check(B.held(vp(1117, 642, 0.1)) == vp(1117, 642, 0.25) && B.held(vp(1117, 642, 10)) == vp(1117, 642, 4),
      "a scale outside 0.25 to 4 goes as the nearest bound")
for bad: Double in [0, -1, .nan, .infinity, -.infinity] {
    check(B.held(vp(1117, 642, bad)) == vp(1117, 642, nil), "a scale of \(bad) goes as none: the Mac window left alone")
}

// MARK: - The numbers in the host's lines

check(B.whole(1512.7) == "1512" && B.whole(-3.9) == "-3" && B.whole(0.0) == "0" && B.whole(-0.0) == "0", "whole: toward zero, as Int() printed it")
check(B.whole(1e300) == "1e+300" && B.whole(Double.nan) == "nan" && B.whole(Double.infinity) == "inf" && B.whole(-Double.infinity) == "-inf",
      "whole: what no Int holds, as Swift prints the Double, no trap")
check(B.whole(9.3e18) == "9.3e+18" && B.whole(-9.3e18) == "-9.3e+18" && B.whole(9.2e18) == "9200000000000000000",
      "whole: Int's range is the line (9.22e18)")
check(B.whole(CGFloat(1117.9)) == "1117" && B.whole(CGSize(width: 1117, height: 642.5)) == "1117×642",
      "whole: a CGFloat and a size, \"1117×642\"")
check(B.whole(CGSize(width: CGFloat.infinity, height: 1e300)) == "inf×1e+300", "whole: a size no Int holds")
check(B.number(-1) == "-1" && B.number(16385) == "16385" && B.number(0) == "0", "number: a whole number without .0")
check(B.number(0.1) == "0.1" && B.number(1e-300) == "1e-300" && B.number(16384.001) == "16384.001",
      "number: any other as it came, never rounded (0.1 is not 0)")
check(B.number(1e300) == "1e+300" && B.number(.nan) == "nan" && B.number(.infinity) == "inf", "number: what no Int holds, no trap")

// MARK: - 200,000 random viewports, real and hostile

var seed: UInt64 = 0x5111_0009
func next() -> UInt64 {   // a seeded generator, so a failure repeats
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return seed >> 11
}
func pick<T>(_ xs: [T]) -> T { xs[Int(next() % UInt64(xs.count))] }
func unit() -> Double { Double(next() % 1_000_001) / 1_000_000 }
let hostileSides: [Double] = [0, -0.0, -1, 0.5, 0.999, 1, 16384, 16384.001, 16385, 1e5, 1e18, 9.3e18, 1e300, .greatestFiniteMagnitude,
                              .leastNonzeroMagnitude, .nan, .infinity, -.infinity, -1e300]
let hostileScales: [Double?] = [nil, 0, -0.0, -1, 1e-300, .leastNonzeroMagnitude, 0.2499, 0.25, 0.5, 1, 1.5, 4, 4.0001, 1e300, .nan, .infinity]
func side() -> Double {
    switch next() % 4 {
    case 0: return pick(hostileSides)
    case 1: return unit() * 4000                       // a device's panel, any size it has
    case 2: return (unit() - 0.5) * 40000              // around the bounds, either side of them
    default: return Double(Int(next() % 20000)) - 100  // whole points, around the bounds
    }
}
func scale() -> Double? {
    switch next() % 3 {
    case 0: return pick(hostileScales)
    case 1: return [0.5, 0.75, 1, 1.25, 1.5][Int(next() % 5)]   // the slider's detents
    default: return unit() * 5 - 0.5
    }
}
/// The rule written another way: plain comparisons.
func oracleTakes(_ v: Viewport) -> Bool {
    let sideOK = { (x: Double) in x >= 1 && x <= 16384 }
    let scaleOK = v.scale.map { $0 >= 0.25 && $0 <= 4 } ?? true
    return sideOK(v.width) && sideOK(v.height) && scaleOK
}
var disagree = 0, takenTraps = 0, takenTooBig = 0, heldRefused = 0, heldNotIdentity = 0, heldNilWrong = 0, wordsWrong = 0
var bugReproduced = 0, bugStillTaken = 0, wholeWrong = 0
for _ in 0..<200_000 {
    let v = vp(side(), side(), scale(), fps: pick([nil, 60, 120]))
    let why = B.refusal(v)
    if (why == nil) != oracleTakes(v) { disagree += 1 }
    if why == nil {
        // What the host takes: the fit's numbers, and its line's, are Ints, within 65536 points.
        if lineTraps(v) { takenTraps += 1 }
        if let t = fitTarget(v), t.width > 65536 || t.height > 65536 { takenTooBig += 1 }
        if B.held(v) != v { heldNotIdentity += 1 }
    } else {
        // Each field out of its range named once, and only those.
        let w = !(v.width >= 1 && v.width <= 16384), h = !(v.height >= 1 && v.height <= 16384)
        let s = v.scale.map { !($0 >= 0.25 && $0 <= 4) } ?? false
        let named = [why!.contains("width "), why!.contains("height "), why!.contains("scale ")]
        if named != [w, h, s] { wordsWrong += 1 }
    }
    // The bug: what the old guard took and the line could not print. None of it is taken now.
    if lineTraps(v) { bugReproduced += 1; if why == nil { bugStillTaken += 1 } }
    // A device's viewport after `held` is always taken; nothing to send only for a side that is not a positive number.
    let held = B.held(v)
    let sendable = v.width.isFinite && v.height.isFinite && v.width > 0 && v.height > 0
    if (held == nil) == sendable { heldNilWrong += 1 }
    if let held, B.refusal(held) != nil { heldRefused += 1 }
    // whole() prints Int()'s number wherever Int() would not trap.
    for x in [v.width, v.height, v.scale ?? 1] {
        if let i = Int(exactly: x.rounded(.towardZero)), B.whole(x) != String(Int(x)) || String(i) != B.whole(x) { wholeWrong += 1 }
    }
}
check(disagree == 0, "200,000 random viewports: the rule as written another way agrees (\(disagree) not)")
check(bugReproduced > 1000 && bugStillTaken == 0,
      "\(bugReproduced) of them the old guard took and its line's Int() trapped on; none is taken now (\(bugStillTaken))")
check(takenTraps == 0 && takenTooBig == 0, "every viewport taken gives the fit numbers its line prints, at most 65536 points (\(takenTraps), \(takenTooBig))")
check(wordsWrong == 0, "every refusal names each field out of its range, and only those (\(wordsWrong) not)")
check(heldNilWrong == 0, "a device sends nothing only for a side that is not a positive number (\(heldNilWrong) not)")
check(heldRefused == 0, "whatever a device sends is taken (\(heldRefused) refused)")
check(heldNotIdentity == 0, "a viewport already taken goes as it is (\(heldNotIdentity) changed)")
check(wholeWrong == 0, "whole prints what Int() printed wherever Int() did not trap (\(wholeWrong) not)")

// MARK: - A device's late-sound count (ClientStats.lateSince)

// The host adds each stats report's `audioLate` to the count its next stats line prints (StreamServer).
// The device's own number: until 2026-10-29 a plain `+`, which traps past Int.max, so two reports of
// Int.max within the line's 1.5 s ended Sill and every device's session (found in the review of
// finding 4; live, a loopback host died at the third report, exit 133).
typealias S = ClientStats
check(S.lateSince(0, adding: 3) == 3 && S.lateSince(3, adding: 4) == 7, "late counts add up: 3, then 7")
check(S.lateSince(5, adding: nil) == 5 && S.lateSince(5, adding: 0) == 5, "no count from an older device, or 0, adds nothing")
check(S.lateSince(5, adding: -1) == 5 && S.lateSince(5, adding: .min) == 5, "a negative count adds nothing, Int.min neither")
check(S.lateSince(0, adding: .max) == .max, "one report of Int.max: Int.max")
check(S.lateSince(.max, adding: .max) == .max, "Int.max and Int.max again: Int.max, where `+` trapped")
check(S.lateSince(.max - 1, adding: 1) == .max && S.lateSince(.max - 1, adding: 2) == .max && S.lateSince(.max, adding: 0) == .max,
      "at the top: Int.max - 1 and 1 is Int.max, 2 stops there, and nothing more stays")
var lateCount = 0
for _ in 0..<3 { lateCount = S.lateSince(lateCount, adding: .max) }
check(lateCount == .max, "three reports of Int.max in a row, as the live run sent them: Int.max, no trap")
// Random runs of reports, real and hostile, against the sum in overflow-reporting arithmetic.
let latePool: [Int?] = [nil, 0, 1, 3, 60, 1_000, -1, .min, .max, .max - 1, 1 << 62, (1 << 62) + 1, -(1 << 62)]
var lateWrong = 0, lateNegative = 0, lateNotSum = 0
for _ in 0..<50_000 {
    var got = 0, wide = 0, saturated = false
    for _ in 0..<Int(1 + next() % 6) {
        let late: Int? = next() % 2 == 0 ? pick(latePool) : Int(next() % 10_000)
        got = S.lateSince(got, adding: late)
        let (sum, over) = wide.addingReportingOverflow(max(0, late ?? 0))
        if over || saturated { saturated = true; wide = .max } else { wide = sum }
    }
    if got != wide { lateWrong += 1 }
    if got < 0 { lateNegative += 1 }
    if !saturated, got != wide { lateNotSum += 1 }
}
check(lateWrong == 0 && lateNegative == 0 && lateNotSum == 0,
      "50,000 random runs of reports: the sum of the counts at or above 0, stopping at Int.max (\(lateWrong), \(lateNegative), \(lateNotSum))")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
