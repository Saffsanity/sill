import Foundation

// The device's camera stream (CameraStream; docs/camera-plan.md §6.1 points 4 to 8, §6.2 with §0's settlement),
// compiled with Sources/StreamProtocol and CameraPolicy as one module (module.txt): what becomes of each picture
// the camera gives and each frame the encoder makes. Case by case: nothing while stopped; an encoder and an epoch
// at the first picture, at a new size (the device turned), a new rate or camera, never for a new bitrate alone;
// the epoch's format right before its first frame, which must be a keyframe with parameter sets; an older
// encoder's frames never going; keyframes at an epoch's start, the Mac's ask (once a second at most), after a
// frame dropped or one the encoder did not give back, never after a skip; the send budget's skips (a fence, a
// hold, the connection holding more than the budget) and its drops (a fence that went up since the encoding);
// after a dropped frame nothing but a keyframe goes; a frame past the cap dropped and the bitrate stepped down;
// a keyframe with new parameter sets opening an epoch of its own; epochs going round at 65,535; the bitrate's
// steps and a second's numbers. Then 20,000 random lives against the invariants:
//   S1 every frame follows its epoch's format (the latest format said is of the frame's epoch);
//   S2 the first frame after a format is a keyframe, in the same breath;
//   S3 within an epoch, frames go in order of their numbers, and a number is never used twice;
//   S4 no frame of an encoder that is not the current one;
//   S5 no frame goes at a fence;
//   S6 after a frame dropped (or one the encoder did not give back), nothing but a keyframe goes until one has;
//   S7 a picture is encoded as a keyframe exactly when one is owed: a new encoder, an ask a second after the
//      last one taken, a drop or a frame the encoder did not give back since the last keyframe encoded;
//   S8 no picture is encoded at a fence or while the connection holds more than the budget;
//   S9 every format is valid and every frame serializes;
//   S10 the bitrate stays within a fifth of the target (300 kbit/s at least) and the target.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias S = CameraStream
typealias A = CameraStream.Action
let ps1 = ParameterSets(nalUnitHeaderLength: 4, sets: [Data([0x40, 0x01, 0x0C]), Data([0x42, 0x01, 0x01]), Data([0x44, 0x01, 0xC1])])
let ps2 = ParameterSets(nalUnitHeaderLength: 4, sets: [Data([0x40, 0x01, 0x0C]), Data([0x42, 0x01, 0x02]), Data([0x44, 0x01, 0xC2])])
let open = S.Uplink(fenced: false, unsent: 0, takenLastSecond: 1_000_000)
let fenced = S.Uplink(fenced: true, unsent: 0, takenLastSecond: 1_000_000)
let plan = S.Plan(fps: 30, bitrate: 2_500_000, position: "front")
func bytes(_ n: Int, _ v: UInt8 = 7) -> Data { Data(repeating: v, count: n) }
func frames(_ a: [A]) -> [CameraFrame] { a.compactMap { if case .frame(let f, _) = $0 { return f }; return nil } }
func formats(_ a: [A]) -> [CameraFormat] { a.compactMap { if case .format(let f) = $0 { return f }; return nil } }
func encodes(_ a: [A]) -> [Bool] { a.compactMap { if case .encode(let k) = $0 { return k }; return nil } }
func encoders(_ a: [A]) -> [S.Encoder] { a.compactMap { if case .encoder(let e, _) = $0 { return e }; return nil } }
func bitrates(_ a: [A]) -> [Int] { a.compactMap { if case .bitrate(let b) = $0 { return b }; return nil } }

// MARK: - Stopped, then the first epoch

var s = S()
check(s.picture(width: 1280, height: 720, uplink: open, at: 0).isEmpty, "stopped: a picture does nothing")
check(s.encoded(serial: 1, data: bytes(10), keyframe: true, parameterSets: ps1, fenced: false, at: 0).isEmpty, "stopped: a frame goes nowhere")
check(s.run(plan, at: 0).isEmpty, "running asks for nothing until the first picture")
check(s.picture(width: 3840, height: 2160, uplink: open, at: 0).isEmpty && s.picture(width: 1279, height: 720, uplink: open, at: 0).isEmpty
      && s.picture(width: 8, height: 8, uplink: open, at: 0).isEmpty && s.encoder == nil,
      "a picture generation 1 cannot carry (past 1920 a side, odd, under 16): never encoded, no encoder made")
var a = s.picture(width: 1280, height: 720, uplink: open, at: 0)
check(a == [.encoder(S.Encoder(serial: 1, width: 1280, height: 720, fps: 30), bitrate: 2_500_000), .encode(keyframe: true)],
      "the first picture: an encoder at its size and the plan's rate and bitrate, and a keyframe: \(a)")
check(s.epoch == 0, "the first epoch is 0")
check(s.picture(width: 1280, height: 720, uplink: open, at: 0.033) == [.encode(keyframe: false)], "the next picture: no keyframe")
a = s.encoded(serial: 1, data: bytes(5000), keyframe: true, parameterSets: ps1, fenced: false, at: 0.04)
let first = CameraFormat(position: "front", codec: "hevc", width: 1280, height: 720, fps: 30, epoch: 0, parameterSets: ps1.encoded(), bitrate: 2_500_000)
check(a == [.format(first), .frame(CameraFrame(epoch: 0, seq: 0, data: bytes(5000)), keyframe: true)],
      "the epoch's first frame: its format right before it, the keyframe's parameter sets in it: \(a)")
check(first.isValid && CameraMessage.format(first).serialized() != nil, "that format is generation 1's and goes on the wire")
a = s.encoded(serial: 1, data: bytes(900), keyframe: false, parameterSets: nil, fenced: false, at: 0.07)
check(a == [.frame(CameraFrame(epoch: 0, seq: 1, data: bytes(900)), keyframe: false)], "the next frame alone, numbered 1")

// An epoch whose first frame is no keyframe, or a keyframe without parameter sets: dropped, a keyframe next.
do {
    var t = S()
    _ = t.run(plan, at: 0)
    _ = t.picture(width: 640, height: 360, uplink: open, at: 0)
    check(t.encoded(serial: 1, data: bytes(100), keyframe: false, parameterSets: ps1, fenced: false, at: 0).isEmpty,
          "an epoch's first frame that is no keyframe never goes, whatever parameter sets it carries")
    check(t.picture(width: 640, height: 360, uplink: open, at: 0.03) == [.encode(keyframe: true)], "and the next picture is a keyframe")
    check(t.encoded(serial: 1, data: bytes(100), keyframe: true, parameterSets: nil, fenced: false, at: 0.04).isEmpty,
          "a keyframe without parameter sets cannot open the epoch either")
    let bad = ParameterSets(nalUnitHeaderLength: 3, sets: [Data([1]), Data([2]), Data([3])])
    _ = t.picture(width: 640, height: 360, uplink: open, at: 0.07)
    check(t.encoded(serial: 1, data: bytes(100), keyframe: true, parameterSets: bad, fenced: false, at: 0.08).isEmpty,
          "nor with parameter sets outside generation 1 (a NAL length of 3)")
    _ = t.picture(width: 640, height: 360, uplink: open, at: 0.1)
    a = t.encoded(serial: 1, data: bytes(100), keyframe: true, parameterSets: ps1, fenced: false, at: 0.11)
    check(formats(a).count == 1 && frames(a).map(\.seq) == [3], "a keyframe with them opens it, its number the fourth made (3): the gap says three dropped")
}

// MARK: - New encoders: size, rate, camera; never for a bitrate alone

a = s.picture(width: 720, height: 1280, uplink: open, at: 1)
check(encoders(a) == [S.Encoder(serial: 2, width: 720, height: 1280, fps: 30)] && encodes(a) == [true] && s.epoch == 1,
      "a picture at another size (the device turned): a new encoder and epoch, a keyframe: \(a)")
check(s.encoded(serial: 1, data: bytes(800), keyframe: false, parameterSets: nil, fenced: false, at: 1.01).isEmpty,
      "a frame the old encoder still gives back never goes")
a = s.encoded(serial: 2, data: bytes(6000), keyframe: true, parameterSets: ps1, fenced: false, at: 1.02)
check(formats(a).map { [$0.epoch, $0.width, $0.height] } == [[1, 720, 1280]] && frames(a).map(\.seq) == [0],
      "the new epoch's format, upright, then its frame 0")
a = s.run(S.Plan(fps: 30, bitrate: 1_200_000, position: "front"), at: 2)
check(a == [.bitrate(1_200_000)], "a new target bitrate alone: taken at once, the same encoder: \(a)")
check(s.picture(width: 720, height: 1280, uplink: open, at: 2.03) == [.encode(keyframe: false)], "and no new epoch for it")
_ = s.run(S.Plan(fps: 20, bitrate: 1_200_000, position: "front"), at: 3)
a = s.picture(width: 720, height: 1280, uplink: open, at: 3.05)
check(encoders(a) == [S.Encoder(serial: 3, width: 720, height: 1280, fps: 20)] && encodes(a) == [true], "a new rate: a new encoder at the next picture")
_ = s.run(S.Plan(fps: 20, bitrate: 1_200_000, position: "back"), at: 4)
a = s.picture(width: 720, height: 1280, uplink: open, at: 4.05)
check(encoders(a).map(\.serial) == [4] && encodes(a) == [true], "the other camera: a new encoder")
a = s.encoded(serial: 4, data: bytes(3000), keyframe: true, parameterSets: ps1, fenced: false, at: 4.06)
check(formats(a).map(\.position) == ["back"], "its format says the back camera")
check(s.run(nil, at: 5) == [.noEncoder] && s.picture(width: 720, height: 1280, uplink: open, at: 5.1).isEmpty,
      "stopped: the encoder goes, pictures do nothing")
check(s.run(nil, at: 5.2).isEmpty, "stopped twice: nothing more")
_ = s.run(plan, at: 6)
a = s.picture(width: 720, height: 1280, uplink: open, at: 6.1)
check(encoders(a).map(\.serial) == [5] && encodes(a) == [true] && s.epoch == 4, "started again: a new encoder and epoch, even at the same size")

// MARK: - The budget: skips, drops, and only a keyframe after a drop

do {
    var t = S()
    _ = t.run(plan, at: 0)
    _ = t.picture(width: 1280, height: 720, uplink: open, at: 0)
    _ = t.encoded(serial: 1, data: bytes(4000), keyframe: true, parameterSets: ps1, fenced: false, at: 0.01)
    check(encodes(t.picture(width: 1280, height: 720, uplink: fenced, at: 0.03)).isEmpty, "a fence or a hold: the picture is skipped")
    let tight = S.Uplink(fenced: false, unsent: 20_000, takenLastSecond: 200_000)   // budget max(16 KB, 8 KB)
    check(encodes(t.picture(width: 1280, height: 720, uplink: tight, at: 0.06)).isEmpty, "20 KB not taken, over a 16 KB budget: skipped")
    let wide = S.Uplink(fenced: false, unsent: 20_000, takenLastSecond: 1_000_000)  // budget 40 KB
    check(t.picture(width: 1280, height: 720, uplink: wide, at: 0.1) == [.encode(keyframe: false)],
          "20 KB within a 40 KB budget (1 MB taken in the last second): encoded, and no keyframe after a skip")
    a = t.encoded(serial: 1, data: bytes(800), keyframe: false, parameterSets: nil, fenced: true, at: 0.12)
    check(a.isEmpty && t.awaitingKeyframe, "a frame at a fence that went up since its encoding: dropped")
    check(t.picture(width: 1280, height: 720, uplink: open, at: 0.13) == [.encode(keyframe: true)], "the next picture is a keyframe")
    check(t.encoded(serial: 1, data: bytes(800), keyframe: false, parameterSets: nil, fenced: false, at: 0.14).isEmpty,
          "a frame encoded before that keyframe never goes: it may need the dropped one")
    a = t.encoded(serial: 1, data: bytes(3000), keyframe: true, parameterSets: ps1, fenced: false, at: 0.15)
    check(formats(a).isEmpty && frames(a).map(\.seq) == [3] && !t.awaitingKeyframe, "the keyframe goes, no new format (the same epoch), numbered after the gap (1 and 2 dropped)")
    check(frames(t.encoded(serial: 1, data: bytes(800), keyframe: false, parameterSets: nil, fenced: false, at: 0.17)).count == 1,
          "then frames go again")
    // A frame the encoder did not give back.
    t.encodeFailed(serial: 1)
    check(t.picture(width: 1280, height: 720, uplink: open, at: 0.2) == [.encode(keyframe: true)], "after a frame the encoder dropped: a keyframe")
    check(t.encoded(serial: 1, data: bytes(800), keyframe: false, parameterSets: nil, fenced: false, at: 0.21).isEmpty,
          "and nothing but a keyframe goes until it has")
    let was = t
    t.encodeFailed(serial: 99)
    check(t == was, "a failure of another encoder changes nothing")
    // A frame the link refused after `encoded` let it go (a fence went up in between).
    _ = t.picture(width: 1280, height: 720, uplink: open, at: 0.22)
    _ = t.encoded(serial: 1, data: bytes(3000), keyframe: true, parameterSets: ps1, fenced: false, at: 0.23)
    check(!t.awaitingKeyframe, "a keyframe went: frames go again")
    t.notSent()
    check(t.awaitingKeyframe && t.picture(width: 1280, height: 720, uplink: open, at: 0.24) == [.encode(keyframe: true)],
          "the link refused the frame after all: as a drop, a keyframe next")
    check(t.encoded(serial: 1, data: bytes(700), keyframe: false, parameterSets: nil, fenced: false, at: 0.25).isEmpty,
          "and nothing but a keyframe goes until it has")
    var stopped = S()
    stopped.notSent()
    check(stopped == S(), "a refusal with no encoder changes nothing")
    // A frame past the cap.
    let before = t.step?.current ?? 0
    a = t.encoded(serial: 1, data: bytes(CameraFrame.maxDataBytes + 1), keyframe: true, parameterSets: ps1, fenced: false, at: 0.3)
    check(frames(a).isEmpty && bitrates(a) == [before * 2 / 3] && t.keyframeOwed, "a frame past 256 KB: dropped, the bitrate a third down at once, a keyframe owed: \(a)")
    a = t.encoded(serial: 1, data: bytes(CameraFrame.maxDataBytes), keyframe: true, parameterSets: ps1, fenced: false, at: 0.33)
    check(frames(a).count == 1 && CameraMessage.frame(frames(a)[0]).serialized() != nil, "one of exactly 256 KB goes, and serializes")
    check(t.encoded(serial: 1, data: Data(), keyframe: true, parameterSets: ps1, fenced: false, at: 0.34).isEmpty && t.awaitingKeyframe,
          "an empty frame never goes, and counts as dropped (the bitrate kept)")
}

// MARK: - Keyframes the Mac asks for

do {
    var t = S()
    _ = t.run(plan, at: 0)
    _ = t.picture(width: 1280, height: 720, uplink: open, at: 0)
    _ = t.encoded(serial: 1, data: bytes(4000), keyframe: true, parameterSets: ps1, fenced: false, at: 0.01)
    t.keyframeAsked(at: 5)
    check(t.picture(width: 1280, height: 720, uplink: open, at: 5.01) == [.encode(keyframe: true)], "the Mac's ask: the next picture is a keyframe")
    t.keyframeAsked(at: 5.5)
    check(t.picture(width: 1280, height: 720, uplink: open, at: 5.51) == [.encode(keyframe: false)], "a second ask within the second: not honoured")
    t.keyframeAsked(at: 6.0)
    check(t.picture(width: 1280, height: 720, uplink: open, at: 6.01) == [.encode(keyframe: true)], "an ask a second after the last honoured: honoured")
    // A keyframe with other parameter sets: an epoch of its own, its format again.
    let e = t.epoch
    a = t.encoded(serial: 1, data: bytes(4000), keyframe: true, parameterSets: ps2, fenced: false, at: 6.02)
    check(formats(a).map(\.epoch) == [e + 1] && formats(a).first?.parameterSets == ps2.encoded() && frames(a).map { [$0.epoch, Int($0.seq)] } == [[e + 1, 0]],
          "a keyframe with new parameter sets: a new epoch, its format with them, its frame 0: \(a)")
    a = t.encoded(serial: 1, data: bytes(4000), keyframe: true, parameterSets: ps2, fenced: false, at: 6.05)
    check(formats(a).isEmpty && frames(a).map(\.epoch) == [e + 1], "the same parameter sets again: the same epoch")
}

// MARK: - Epochs go round

do {
    var t = S()
    for i in 0..<65_537 {
        _ = t.run(i % 2 == 0 ? plan : S.Plan(fps: 15, bitrate: 2_500_000, position: "front"), at: Double(i))
        _ = t.picture(width: 64, height: 64, uplink: open, at: Double(i))
    }
    check(t.epoch == 0, "65,537 encoders: the epoch went round to 0 (\(t.epoch))")
    a = t.encoded(serial: 65_537, data: bytes(10), keyframe: true, parameterSets: ps1, fenced: false, at: 70_000)
    check(formats(a).first.map { $0.isValid && $0.epoch == 0 } == true, "its format is valid")
}

// MARK: - The bitrate's steps and a second's numbers

do {
    var t = S()
    _ = t.run(plan, at: 0)
    _ = t.picture(width: 1280, height: 720, uplink: open, at: 0)
    _ = t.encoded(serial: 1, data: bytes(4000), keyframe: true, parameterSets: ps1, fenced: false, at: 0.01)
    _ = t.picture(width: 1280, height: 720, uplink: open, at: 0.03)
    _ = t.encoded(serial: 1, data: bytes(1000), keyframe: false, parameterSets: nil, fenced: false, at: 0.04)
    var (sec, act) = t.closeSecond(at: 1)
    check(sec == S.Second(frames: 2, bytes: 5000 + 2 * CameraFrame.headerBytes, skipped: 0, dropped: 0) && act.isEmpty,
          "a quiet second: its frames and bytes, the bitrate kept: \(sec)")
    check(sec.kbps == (5000 + 14) * 8 / 1000, "kbps from its bytes")
    (sec, act) = t.closeSecond(at: 2)
    check(sec == S.Second(), "the numbers start again each second")
    _ = t.picture(width: 1280, height: 720, uplink: fenced, at: 2.5)
    (sec, act) = t.closeSecond(at: 3)
    check(sec.skipped == 1 && act == [.bitrate(2_500_000 * 2 / 3)], "a second with a skip: a third down")
    var at = 3.0, last = 2_500_000 * 2 / 3
    for _ in 0..<12 {
        _ = t.picture(width: 1280, height: 720, uplink: fenced, at: at + 0.5)
        at += 1
        (_, act) = t.closeSecond(at: at)
        if let b = bitrates(act).last { last = b }
    }
    check(last == 500_000, "skips every second: down to a fifth of the target, no lower (\(last))")
    _ = t.run(S.Plan(fps: 20, bitrate: 2_500_000, position: "front"), at: at)
    a = t.picture(width: 1280, height: 720, uplink: open, at: at + 0.01)
    check(a.first == .encoder(S.Encoder(serial: 2, width: 1280, height: 720, fps: 20), bitrate: 500_000),
          "a new encoder then (a new rate) starts at the bitrate the steps reached, not the target: \(a)")
    var ups: [Int] = []
    for _ in 0..<80 { at += 1; (_, act) = t.closeSecond(at: at); ups += bitrates(act) }
    check(ups.first == 750_000 && ups.last == 2_500_000 && ups.count == 8 && ups == ups.sorted(),
          "then quiet: a tenth of the target back every 5 s, up to the target and no higher: \(ups)")
    _ = t.run(nil, at: at)
    (_, act) = t.closeSecond(at: at + 1)
    check(act.isEmpty, "stopped: no bitrate")
}

// MARK: - 20,000 random lives

struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ n: Int) -> Bool { below(n) == 0 }
}
var rng = Rng(s: 0x193_0046)
var violations: [String: Int] = [:], firstSeen: [String: String] = [:]
func violated(_ what: String, _ detail: String) {
    violations[what, default: 0] += 1
    if firstSeen[what] == nil { firstSeen[what] = detail }
}
var sentFrames = 0, sentKeyframes = 0, skips = 0, drops = 0, epochsOpened = 0
for life in 0..<20_000 {
    var t = S()
    var now = 0.0
    var log: [String] = []
    // The oracle's view.
    var pending: [(serial: Int, key: Bool)] = []        // pictures in the encoder, in order
    var current: Int?                                   // the current encoder's serial
    var owed = false                                    // a keyframe is owed (S7)
    var awaiting = false                                // only a keyframe may go (S6)
    var lastAsk: Double?
    var lastFormatEpoch: Int?
    var expectKeyNext = false                           // S2: the next frame must be a keyframe in the same breath
    var lastSeq: [Int: UInt32] = [:]
    var target = 0
    var paramSets = ps1
    func apply(_ acts: [A], fencedNow: Bool, step: String) {
        for (i, act) in acts.enumerated() {
            switch act {
            case .encoder(let e, _):
                current = e.serial; owed = true; epochsOpened += 1     // the older encoder's frames may still come back (S4)
            case .noEncoder:
                current = nil
            case .encode(let k):
                if k != owed { violated("S7 a keyframe exactly when owed", "life \(life): \(log.suffix(6)) \(step): encode(\(k)), owed \(owed)") }
                if k { owed = false }
                if let c = current { pending.append((c, k)) }
            case .format(let f):
                if !f.isValid || CameraMessage.format(f).serialized() == nil { violated("S9 a valid format", "life \(life): \(f)") }
                lastFormatEpoch = f.epoch
                expectKeyNext = true
                let nextIsKeyframe: Bool = {
                    guard i + 1 < acts.count, case .frame(_, let k) = acts[i + 1] else { return false }
                    return k
                }()
                if !nextIsKeyframe { violated("S2 a keyframe right after its format", "life \(life): \(acts)") }
            case .frame(let f, let k):
                if f.epoch != lastFormatEpoch { violated("S1 a frame after its epoch's format", "life \(life): \(log.suffix(6)) frame of \(f.epoch), format \(String(describing: lastFormatEpoch))") }
                if expectKeyNext, !k { violated("S2 a keyframe right after its format", "life \(life): \(acts)") }
                expectKeyNext = false
                if let p = lastSeq[f.epoch], f.seq <= p { violated("S3 numbers in order, once", "life \(life): epoch \(f.epoch) \(p) then \(f.seq)") }
                lastSeq[f.epoch] = f.seq
                if fencedNow { violated("S5 no frame at a fence", "life \(life): \(log.suffix(4))") }
                if awaiting, !k { violated("S6 only a keyframe after a drop", "life \(life): \(log.suffix(8)) \(step)") }
                if k { awaiting = false; sentKeyframes += 1 }
                if CameraMessage.frame(f).serialized() == nil { violated("S9 a frame that serializes", "life \(life): \(f.data.count) bytes") }
                sentFrames += 1
            case .bitrate(let b):
                if b < max(300_000, target / 5) || b > target { violated("S10 the bitrate within its bounds", "life \(life): \(b) for \(target)") }
            }
        }
    }
    let steps = 20 + rng.below(80)
    for _ in 0..<steps {
        now += Double(rng.below(400)) / 1000
        switch rng.below(20) {
        case 0:
            // Mostly a new target bitrate alone; now and then a new rate or camera, or a stop.
            let base = t.plan ?? plan
            let p: S.Plan? = rng.chance(6) ? nil : S.Plan(fps: rng.chance(3) ? [15, 20, 30][rng.below(3)] : base.fps,
                                                             bitrate: [1_200_000, 2_500_000, 4_000_000][rng.below(3)],
                                                             position: rng.chance(4) ? (rng.chance(2) ? "back" : "front") : base.position)
            log.append("run(\(p.map { "\($0.fps)/\($0.bitrate)/\($0.position)" } ?? "nil"))")
            if let p { target = p.bitrate }
            apply(t.run(p, at: now), fencedNow: false, step: "run")
        case 1, 2, 3, 4, 5, 6, 7, 8:
            let size = rng.chance(30) ? (720, 1280) : (1280, 720)
            let up = S.Uplink(fenced: rng.chance(12), unsent: [0, 0, 0, 4_000, 20_000, 60_000][rng.below(6)],
                              takenLastSecond: [0, 200_000, 1_000_000, 1_000_000][rng.below(4)])
            log.append("picture(\(size.0)x\(size.1), fenced \(up.fenced), \(up.unsent)/\(up.takenLastSecond))")
            let acts = t.picture(width: size.0, height: size.1, uplink: up, at: now)
            if acts.contains(where: { if case .encode = $0 { return true }; return false }),
               up.fenced || up.unsent > CameraPacing.budget(takenLastSecond: up.takenLastSecond) {
                violated("S8 nothing encoded over the budget", "life \(life): \(up)")
            }
            if t.plan != nil, !acts.contains(where: { if case .encode = $0 { return true }; return false }) { skips += 1 }
            apply(acts, fencedNow: false, step: "picture")
        case 9, 10, 11, 12, 13, 14:
            guard !pending.isEmpty else { continue }
            let p = pending.removeFirst()
            let fence = rng.chance(12)
            let size = rng.chance(40) ? CameraFrame.maxDataBytes + 1 : (p.key ? 3_000 : 600) + rng.below(400)
            if p.key, rng.chance(25) { paramSets = paramSets.encoded() == ps1.encoded() ? ps2 : ps1 }
            log.append("encoded(\(p.serial), key \(p.key), \(size) B, fenced \(fence))")
            let acts = t.encoded(serial: p.serial, data: bytes(size), keyframe: p.key, parameterSets: p.key ? paramSets : nil, fenced: fence, at: now)
            if p.serial == current, frames(acts).isEmpty {
                // Dropped (a fence, the cap, no keyframe after a drop, an epoch without its format): only a keyframe next.
                owed = true; awaiting = true; drops += 1
            }
            if p.serial != current, !acts.isEmpty { violated("S4 nothing of an older encoder", "life \(life): \(acts)") }
            apply(acts, fencedNow: fence, step: "encoded")
            if !frames(acts).isEmpty, rng.chance(20) {
                // The link refused it after all (a fence went up in between): as a drop.
                log.append("notSent")
                t.notSent()
                owed = true; awaiting = true
            }
        case 15:
            guard !pending.isEmpty else { continue }
            let p = pending.removeFirst()
            log.append("encodeFailed(\(p.serial))")
            t.encodeFailed(serial: p.serial)
            if p.serial == current { owed = true; awaiting = true }
        case 16, 17:
            log.append("ask")
            if lastAsk.map({ now - $0 >= 1 }) ?? true { lastAsk = now; owed = true }
            t.keyframeAsked(at: now)
        default:
            log.append("second")
            apply(t.closeSecond(at: now).1, fencedNow: false, step: "second")
        }
    }
}
for (what, n) in violations.sorted(by: { $0.key < $1.key }) { check(false, "\(what): \(n) times; first: \(firstSeen[what] ?? "")") }
check(violations.isEmpty && sentFrames > 60_000 && sentKeyframes > 20_000 && skips > 40_000 && drops > 10_000 && epochsOpened > 20_000,
      "20,000 random lives (\(sentFrames) frames, \(sentKeyframes) keyframes, \(skips) skips, \(drops) drops, \(epochsOpened) encoders): every invariant")

print(failures == 0 ? "ok: \(checks) checks" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
