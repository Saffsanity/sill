// PictureSmoothing (iOSClient): the This-device setting for how the picture is scaled, which
// renderer draws it, and the shader's filter for each level. Compiled with
// iOSClient/PictureSmoothing.swift alone (run.sh).
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
typealias S = PictureSmoothing

check(S.allCases.map(\.title) == ["Automatic", "None", "Low", "Medium", "High"], "Windows App's five, in its order")
check(S.stored(nil) == .automatic, "nothing stored: Automatic")
check(S.stored("") == .automatic && S.stored("ultra") == .automatic, "a value this build does not know: Automatic")
for s in S.allCases { check(S.stored(s.rawValue) == s, "\(s.title) is kept as it was stored") }

check(!S.automatic.usesOwnRenderer, "Automatic keeps the system's video layer")
check(S.allCases.filter(\.usesOwnRenderer) == [.none, .low, .medium, .high], "every other level draws with Sill's own renderer")

check(S.none.filter == .nearest, "None: the nearest pixel")
check(S.low.filter == .bilinear, "Low: bilinear")
check(S.medium.filter == .bicubic, "Medium: bicubic")
check(S.high.filter == .lanczos, "High: Lanczos")
check(S.automatic.filter == nil, "Automatic: no filter of Sill's")
check(Set(S.allCases.compactMap { $0.filter?.shaderMode }) == [0, 1, 2, 3], "each filter has its own shader mode")
check(S.Filter.nearest.shaderMode == 0 && S.Filter.lanczos.shaderMode == 3, "the shader's modes in order of cost")

check(S.footnote.contains("Automatic") && S.footnote.contains("battery"), "the footnote says what Automatic is and what the others cost")

// The kernels the shader uses, against their definitions: Catmull-Rom (bicubic) and Lanczos-3.
let F = S.Filter.self
check(S.kernel(.bicubic, 0) == 1 && S.kernel(.bicubic, 1) == 0 && S.kernel(.bicubic, 2) == 0, "bicubic: 1 on its sample, 0 on the others")
check(abs(S.kernel(.bicubic, 0.5) - 0.5625) < 1e-9 && abs(S.kernel(.bicubic, 1.5) - -0.0625) < 1e-9, "bicubic between: 9/16, then -1/16")
check(S.kernel(.lanczos, 0) == 1 && abs(S.kernel(.lanczos, 1)) < 1e-12 && abs(S.kernel(.lanczos, 2)) < 1e-12 && S.kernel(.lanczos, 3) == 0,
      "Lanczos: 1 at 0, 0 at whole numbers and from 3 on")
check(S.kernel(.lanczos, 0.5) > 0.6 && S.kernel(.lanczos, 1.5) < 0 && S.kernel(.lanczos, -0.5) == S.kernel(.lanczos, 0.5), "Lanczos: a negative lobe, and even")
check(F.bicubic.support == 2 && F.lanczos.support == 3, "their reach in source pixels")

// The reference resampler: what one pass of the shader computes for a row.
let flat = [Double](repeating: 0.7, count: 40)
for f in [F.nearest, .bilinear, .bicubic, .lanczos] {
    for n in [13, 40, 97] {
        check(S.resample(flat, to: n, filter: f).allSatisfy { abs($0 - 0.7) < 1e-9 }, "\(f) keeps a flat row flat (40 → \(n))")
    }
}
let ramp = (0..<8).map { Double($0) }
check(S.resample(ramp, to: 8, filter: .nearest) == ramp && S.resample(ramp, to: 8, filter: .bilinear) == ramp, "the same size: nearest and bilinear copy")
check(S.resample(ramp, to: 16, filter: .nearest) == ramp.flatMap { [$0, $0] }, "nearest, twice the size: each pixel twice")
let up = S.resample(ramp, to: 16, filter: .bilinear)
check(abs(up[1] - 0.25) < 1e-9 && abs(up[2] - 0.75) < 1e-9 && up[0] == 0 && up[15] == 7, "bilinear, twice the size: quarter steps, the edges clamped")
let stripes = (0..<64).map { ($0 / 4) % 2 == 0 ? 0.0 : 1.0 }
let between = { (row: [Double]) in row.filter { $0 > 0.05 && $0 < 0.95 }.count }
check(between(S.resample(stripes, to: 68, filter: .nearest)) == 0, "nearest never makes a grey")
check(between(S.resample(stripes, to: 68, filter: .bilinear)) > 0, "bilinear does, at the edges")
let lan = S.resample(stripes, to: 68, filter: .lanczos)
check(lan.contains { $0 < -0.01 } || lan.contains { $0 > 1.01 }, "Lanczos rings past black and white (the shader clamps on output)")
// Shrinking widens the filter by the shrink, so a pattern finer than the output averages out
// instead of aliasing: 1-pixel stripes halved are grey, not a stripe of every other pixel.
let fine = (0..<64).map { Double($0 % 2) }
for f in [F.bilinear, .bicubic, .lanczos] {
    let half = S.resample(fine, to: 32, filter: f).dropFirst(3).dropLast(3)
    check(half.allSatisfy { abs($0 - 0.5) < 0.15 }, "\(f) halving 1-pixel stripes gives grey")
}
check(Set(S.resample(fine, to: 32, filter: .nearest)).count == 1, "nearest halving them keeps one of the two (it aliases, as None should)")

// When the hardware decoder must be made again (iOS invalidates a VTDecompressionSession in the
// background: kVTInvalidSessionErr -12903, kVTVideoDecoderMalfunctionErr -12911) and ask for a
// keyframe, at most once per 2 s, as opposed to a bad delta (-12909) where the session is still live.
check(S.sessionBroken(-12903) && S.sessionBroken(-12911), "invalidated (-12903) and malfunction (-12911) recreate the decoder")
check(!S.sessionBroken(0) && !S.sessionBroken(-12909) && !S.sessionBroken(-12910), "ok and a bad frame (-12909) keep the decoder")
var rec = S.DecoderRecovery()
check(!rec.shouldAskKeyframe(now: 10, active: false), "in the background: never asks for a keyframe")
check(rec.shouldAskKeyframe(now: 10, active: true), "active, first recovery: asks for a keyframe")
check(!rec.shouldAskKeyframe(now: 11.9, active: true), "within 2 s: does not ask again")
check(rec.shouldAskKeyframe(now: 12.0, active: true), "at 2 s: asks again")
check(rec.shouldAskKeyframe(now: 5.0, active: true), "clock went back: asks")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
