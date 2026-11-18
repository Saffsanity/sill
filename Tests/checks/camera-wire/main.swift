import Foundation

// Kind 46, the device's camera on the Mac (Camera.swift, docs/camera-plan.md §5), against
// Sources/StreamProtocol compiled into this binary:
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/camera-wire/main.swift -o check
// The three types round trip; every cap and bound at its edge; a writer refuses rather than cuts; unknown
// types skipped, unknown keys skipped; generation 1's parameter sets; kind 16's CameraState read by this
// build; then 20,000 random and mutated payloads that never trap and never yield a value outside the
// bounds, each one parsed writing back to what was read.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
typealias M = CameraMessage
typealias F = CameraFormat

/// SplitMix64: the same payloads on every run.
struct Rand {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    mutating func bool() -> Bool { next() & 1 == 1 }
    mutating func bytes(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8(truncatingIfNeeded: next()) }) }
}

/// Parameter sets as VideoToolbox gives them: a NAL length of 4 and the VPS, SPS and PPS.
func sets(_ lengths: [Int] = [24, 42, 7], nal: Int = 4) -> Data {
    ParameterSets(nalUnitHeaderLength: nal, sets: lengths.enumerated().map { i, n in Data(repeating: UInt8(0x40 + i), count: n) }).encoded()
}
let goodSets = sets()
func epoch(_ e: Int = 5, w: Int = 1280, h: Int = 720, fps: Int = 30) -> F {
    F(position: CameraCodec.positionFront, codec: CameraCodec.hevc, width: w, height: h, fps: fps, epoch: e, parameterSets: goodSets, bitrate: 2_500_000)
}
func roundTrips(_ m: M) -> Bool { m.serialized().flatMap(M.parse) == m }

// MARK: - The kind, the types, the caps

check(StreamMessageKind.camera.rawValue == 46 && StreamMessageKind(rawValue: 46) == .camera, "kind 46 is the camera")
check(M.typeFormat == 1 && M.typeFrame == 2 && M.typeDemand == 3, "types 1, 2 and 3")
check(M.maxFormatPayload == 4096 && M.maxDemandPayload == 4096, "a format and a demand at most 4,096 bytes")
check(CameraFrame.headerBytes == 7 && CameraFrame.maxDataBytes == 262_144 && M.maxFramePayload == 7 + 262_144,
      "a frame: 7 bytes of header, at most 262,144 of data")
check(M.maxFramePayload < StreamMessage.maxClientPayload, "every type fits under the 1 MiB a device may send")
check(CameraCodec.generation == 1 && CameraCodec.hevc == "hevc", "generation 1, HEVC")
check(CameraCodec.sides == 16...1920 && CameraCodec.rates == 1...30 && CameraCodec.epochs == 0...65_535, "generation 1's bounds")
check(CameraCodec.maxParameterSetBytes == 1024 && CameraCodec.bitrates == 0...100_000_000, "parameter sets and bitrates")

// MARK: - Type 1: offers, pauses, stops and epochs

let offer = F(position: CameraCodec.positionFront, claim: true)
check(json(offer) == #"{"claim":true,"position":"front"}"#, "an offer's keys: \(json(offer))")
check(roundTrips(.format(offer)), "an offer round-trips")
check(!offer.isEpoch && offer.isValid, "an offer is no epoch")
check(json(F()) == "{}" && roundTrips(.format(F())), "{} is a format, and round-trips")
check(roundTrips(.format(F(stop: true))) && json(F(stop: true)) == #"{"stop":true}"#, "#193's stop round-trips")
for pause in F.pauses {
    let p = F(position: CameraCodec.positionBack, pause: pause)
    check(roundTrips(.format(p)) && p.knownPause == pause, "the pause \(pause) round-trips and reads as itself")
}
check(F.pauses == ["waiting", "background", "multitasking", "busy", "scanner", "thermal", "denied", "unavailable"], "the eight pauses")
check(F(pause: "overheated").knownPause == F.unavailable && F(pause: "").knownPause == F.unavailable, "a later pause reads as unavailable")
check(F().knownPause == nil, "no pause, none read")
let e5 = epoch()
check(e5.isEpoch && e5.isValid && roundTrips(.format(e5)), "an epoch's format round-trips")
check(json(e5).contains(#""parameterSets":""#) && json(e5).contains(goodSets.base64EncodedString()), "the parameter sets are base64 in the JSON")
check(M.parse(Data([M.typeFormat]) + Data(#"{"codec":"hevc","width":1280,"height":720,"fps":30,"epoch":5,"parameterSets":"\#(goodSets.base64EncodedString())","later":[1,2],"position":"front"}"#.utf8))
      == .format(F(position: "front", codec: "hevc", width: 1280, height: 720, fps: 30, epoch: 5, parameterSets: goodSets)),
      "a later device's keys are skipped")
// An epoch is whole or refused: generation 1 knows HEVC alone, with every field.
check(!F(codec: "h264", width: 1280, height: 720, fps: 30, epoch: 1, parameterSets: goodSets).isValid, "H.264 is not generation 1")
check(!F(codec: "jpeg", width: 640, height: 480, fps: 15, epoch: 1, parameterSets: goodSets).isValid, "#193's JPEG is not generation 1")
for missing in ["width", "height", "fps", "epoch", "parameterSets"] {
    var f = epoch()
    switch missing {
    case "width": f.width = nil
    case "height": f.height = nil
    case "fps": f.fps = nil
    case "epoch": f.epoch = nil
    default: f.parameterSets = nil
    }
    check(!f.isValid && M.format(f).serialized() == nil, "an epoch without its \(missing) is refused")
    let raw = Data([M.typeFormat]) + Wire.encode(f)
    check(M.parse(raw) == nil, "and dropped when read without its \(missing)")
}
// #193's own format as #193 sent it: dropped here, never decoded as JPEG.
check(M.parse(Data([1]) + Data(#"{"codec":"jpeg","width":640,"height":480,"fps":15,"position":"front","epoch":5}"#.utf8)) == nil,
      "#193's JPEG format is dropped")

// The bounds, each at its edges.
for (w, ok) in [(14, false), (15, false), (16, true), (17, false), (640, true), (1919, false), (1920, true), (1921, false), (1922, false), (0, false), (-2, false)] {
    check(epoch(w: w).isValid == ok && epoch(h: w).isValid == ok, "a side of \(w): \(ok ? "taken" : "refused")")
    check((M.format(epoch(w: w)).serialized() != nil) == ok, "a side of \(w) written only if taken")
    check(F(width: w).isValid == ok, "a side of \(w) in an offer too")
}
for (fps, ok) in [(0, false), (1, true), (15, true), (30, true), (31, false), (60, false), (-1, false)] {
    check(epoch(fps: fps).isValid == ok, "\(fps) fps: \(ok ? "taken" : "refused")")
}
for (e, ok) in [(-1, false), (0, true), (65_535, true), (65_536, false)] {
    check(epoch(e).isValid == ok, "epoch \(e): \(ok ? "taken" : "refused")")
}
for (b, ok) in [(-1, false), (0, true), (100_000_000, true), (100_000_001, false)] {
    check(F(bitrate: b).isValid == ok, "a bitrate of \(b): \(ok ? "taken" : "refused")")
}
// Parameter sets: three to sixteen non-empty sets, a NAL length of 1, 2 or 4, nothing after, 1,024 bytes.
check(CameraCodec.validParameterSets(goodSets), "the VPS, SPS and PPS")
check(!CameraCodec.validParameterSets(sets([24, 42])), "two sets refused")
check(CameraCodec.validParameterSets(sets([1, 1, 1] + Array(repeating: 1, count: 13))), "sixteen sets taken")
check(!CameraCodec.validParameterSets(sets(Array(repeating: 1, count: 17))), "seventeen refused")
check(!CameraCodec.validParameterSets(sets([24, 0, 7])), "an empty set refused")
check(CameraCodec.validParameterSets(sets(nal: 1)) && CameraCodec.validParameterSets(sets(nal: 2)), "NAL lengths 1 and 2 taken")
check(!CameraCodec.validParameterSets(sets(nal: 3)) && !CameraCodec.validParameterSets(sets(nal: 0)) && !CameraCodec.validParameterSets(sets(nal: 8)),
      "NAL lengths 3, 0 and 8 refused")
check(!CameraCodec.validParameterSets(goodSets + Data([0])), "a byte after the sets refused")
check(!CameraCodec.validParameterSets(Data(goodSets.dropLast())), "a set cut short refused")
check(!CameraCodec.validParameterSets(Data()) && !CameraCodec.validParameterSets(Data([4])), "nothing, or a length alone, refused")
// The edge: 2 + 3 × 2 + 1,016 bytes of sets is 1,024 exactly.
let edgeSets = sets([1000, 8, 8])
check(edgeSets.count == 1024 && CameraCodec.validParameterSets(edgeSets), "1,024 bytes of sets taken")
check(!CameraCodec.validParameterSets(sets([1001, 8, 8])), "1,025 refused")
check(roundTrips(.format(F(codec: "hevc", width: 1920, height: 1080, fps: 30, epoch: 65_535, parameterSets: edgeSets))),
      "an epoch at every edge round-trips")

// The cap at its edge: a format padded with a long position (any position reads as front).
func formatPayload(size: Int) -> Data {
    let base = Data([M.typeFormat]) + Wire.encode(F(position: ""))
    return Data([M.typeFormat]) + Wire.encode(F(position: String(repeating: "x", count: size - base.count)))
}
check(formatPayload(size: 4096).count == 4096 && M.parse(formatPayload(size: 4096)) != nil, "a format of 4,096 bytes is read")
check(formatPayload(size: 4097).count == 4097 && M.parse(formatPayload(size: 4097)) == nil, "4,097 dropped whole")
for n in 4070...4090 {
    let written = M.format(F(position: String(repeating: "x", count: n))).serialized()
    check(written.map { $0.count <= 4096 && $0.count == 16 + n } ?? (16 + n > 4096), "a format of \(16 + n) bytes: written only within the cap")
}
check(M.format(F(position: String(repeating: "x", count: 5000))).serialized() == nil, "a format past the cap is refused, never cut")
check(CameraCodec.position(nil) == "front" && CameraCodec.position("back") == "back" && CameraCodec.position("front") == "front",
      "the positions read")
check(CameraCodec.position("BACK") == "front" && CameraCodec.position("side") == "front" && CameraCodec.position(String(repeating: "x", count: 99)) == "front",
      "any other position reads as front")
check(M.parse(Data([M.typeFormat]) + Data("not json".utf8)) == nil && M.parse(Data([M.typeFormat])) == nil, "a format that does not decode is dropped")
check(M.parse(Data([M.typeFormat]) + Data(#"{"width":"1280"}"#.utf8)) == nil, "a retyped field is dropped")

// MARK: - Type 2: frames

let au = Data([0, 0, 0, 5, 0x26, 0x01, 0xAF, 0x09, 0x40])
let f5 = CameraFrame(epoch: 5, seq: 19, data: au)
check(f5.serialized() == Data([2, 0, 5, 0, 0, 0, 19]) + au, "the layout: type 2 · epoch · seq · data, big endian")
check(roundTrips(.frame(f5)), "a frame round-trips")
check(roundTrips(.frame(CameraFrame(epoch: 65_535, seq: .max, data: Data([1])))), "the largest epoch and seq, one byte of data")
check(roundTrips(.frame(CameraFrame(epoch: 0, seq: 0, data: Data(count: CameraFrame.maxDataBytes)))), "262,144 bytes of data")
check(CameraFrame(epoch: 0, seq: 0, data: Data(count: CameraFrame.maxDataBytes + 1)).serialized() == nil, "262,145 refused, never cut")
check(CameraFrame(epoch: 0, seq: 0, data: Data()).serialized() == nil, "no data refused")
check(CameraFrame(epoch: -1, seq: 0, data: au).serialized() == nil && CameraFrame(epoch: 65_536, seq: 0, data: au).serialized() == nil,
      "an epoch outside 0 to 65,535 refused, never wrapped")
check(M.parse(Data([2, 0, 5, 0, 0, 0, 19])) == nil && M.parse(Data([2, 0, 5, 0, 0, 0])) == nil && M.parse(Data([2])) == nil,
      "a frame without data, or cut short, dropped")
check(M.parse(Data([2, 0, 5, 0, 0, 0, 19]) + Data(count: CameraFrame.maxDataBytes + 1)) == nil, "a frame past the cap dropped whole")
check(M.parse(Data([2, 0, 5, 0, 0, 0, 19]) + Data(count: CameraFrame.maxDataBytes)) != nil, "one at the cap read")
// #193's 12-byte layout never shipped; read here it is an access unit like any other, of #193's width and
// height bytes first: the decoder refuses it, nothing else reads it.
// The whole message: the capture time and the keyframe flag in the header.
let fm = M.frameMessage(f5, captured: 1_800_000_123.5, keyframe: true)
check(fm.map { $0.kind == .camera && $0.timestamp == 1_800_000_123.5 && $0.isKeyframe } == true, "the header stamps the capture time and the keyframe")
check(M.frameMessage(f5, captured: 1, keyframe: false)?.isKeyframe == false, "a P-frame says so")
check(fm.flatMap { M.parse($0.payload) } == .frame(f5), "its payload is the frame")
check(M.frameMessage(CameraFrame(epoch: 1, seq: 0, data: Data()), captured: 1, keyframe: true) == nil, "no message without data")
check(M.message(.frame(f5), now: 1) == nil, "a frame never goes stamped with the time it is sent")
check(M.message(.format(offer), now: 7).map { $0.kind == .camera && $0.timestamp == 7 && !$0.isKeyframe } == true, "a format is stamped when sent")

// MARK: - Type 3: demands

let d1 = CameraDemand(width: 1280, height: 720, fps: 30, keyframe: true, maxBitrate: 2_500_000, token: 4)
check(json(d1) == #"{"fps":30,"height":720,"keyframe":true,"maxBitrate":2500000,"token":4,"width":1280}"#, "a demand's keys: \(json(d1))")
check(roundTrips(.demand(d1)) && roundTrips(.demand(CameraDemand())), "demands round-trip, {} too")
check(M.parse(Data([3]) + Data(#"{"width":640,"height":360,"fps":30,"wanted":true,"reason":"idle","later":{}}"#.utf8))
      == .demand(CameraDemand(width: 640, height: 360, fps: 30)), "the plan's first keys and a later host's are skipped")
for bad in [CameraDemand(width: 15), CameraDemand(height: 1921), CameraDemand(fps: 0), CameraDemand(fps: 31),
            CameraDemand(maxBitrate: -1), CameraDemand(maxBitrate: 100_000_001), CameraDemand(token: -1)] {
    check(!bad.isValid && M.demand(bad).serialized() == nil, "a demand outside the bounds is refused: \(json(bad))")
    check(M.parse(Data([3]) + Wire.encode(bad)) == nil, "and dropped when read: \(json(bad))")
}
func demandPayload(size: Int) -> Data {
    let base = Data([3]) + Data(#"{"later":""}"#.utf8)
    return Data([3]) + Data(#"{"later":"\#(String(repeating: "y", count: size - base.count))"}"#.utf8)
}
check(demandPayload(size: 4096).count == 4096 && M.parse(demandPayload(size: 4096)) == .demand(CameraDemand()), "a demand of 4,096 bytes is read")
check(M.parse(demandPayload(size: 4097)) == nil, "4,097 dropped whole")

// MARK: - Unknown types

for t in [0, 4, 5, 46, 127, 255] as [UInt8] {
    check(M.parse(Data([t])) == nil && M.parse(Data([t]) + Data("{}".utf8)) == nil && M.parse(Data([t]) + au) == nil, "type \(t) skipped")
}
check(M.parse(Data()) == nil, "an empty payload skipped")

// MARK: - Kind 16's CameraState as this build reads it

check(CameraState.states == ["off", "notReady", "unpaired", "idle", "another", "inUse"], "the six states")
for s in CameraState.states {
    check(CameraState(state: s).knownState == s && CameraState(state: s).wanted == (s == "inUse"), "\(s) reads as itself, wanted only in use")
}
check(CameraState(state: "paused").knownState == CameraState.off && !CameraState(state: "paused").wanted, "a later state reads as off")
check(CameraState(state: "INUSE").knownState == CameraState.off && !CameraState(state: "INUSE").wanted, "case matters")
check(json(CameraState(state: "another", holder: "iPhone")) == #"{"holder":"iPhone","state":"another"}"#, "another, with its holder")
check(Wire.decode(CameraState.self, from: Data(#"{"holder":"x"}"#.utf8)) == nil, "a camera without a state does not decode")

// MARK: - 20,000 random and mutated payloads

/// Every parsed value is inside the bounds and writes back to what was read.
func sound(_ m: M, from payload: Data) -> Bool {
    switch m {
    case .format(let f):
        return f.isValid && M.parse(M.format(f).serialized() ?? Data()) == m && payload.count <= M.maxFormatPayload
    case .frame(let f):
        return CameraCodec.epochs.contains(f.epoch) && (1...CameraFrame.maxDataBytes).contains(f.data.count) && f.serialized() == payload
    case .demand(let r):
        return r.isValid && M.parse(M.demand(r).serialized() ?? Data()) == m && payload.count <= M.maxDemandPayload
    }
}
var rand = Rand(state: 0x5111_CA3E_2026_1118)
let keys = ["stop", "position", "claim", "pause", "codec", "width", "height", "fps", "epoch", "parameterSets", "bitrate",
            "keyframe", "maxBitrate", "token", "later"]
func randomValue() -> String {
    switch rand.int(0...9) {
    case 0: return "true"
    case 1: return "null"
    case 2: return "\(rand.int(-3...70_000))"
    case 3: return "\(rand.int(0...2000) * 2)"
    case 4: return "\"\(["hevc", "front", "back", "busy", "jpeg", "", "thermal"][rand.int(0...6)])\""
    case 5: return "\"\(goodSets.base64EncodedString())\""
    case 6: return "\"\(rand.bytes(rand.int(0...40)).base64EncodedString())\""
    case 7: return "1.5"
    case 8: return "[\(rand.int(0...9))]"
    default: return "{}"
    }
}
var parsedCount = [0, 0, 0]
var unsound = 0
let seeds: [Data] = [M.format(offer).serialized()!, M.format(e5).serialized()!, f5.serialized()!, M.demand(d1).serialized()!,
                     M.format(F(pause: F.thermal)).serialized()!]
for i in 0..<20_000 {
    var payload: Data
    switch i % 4 {
    case 0:   // raw bytes behind a type
        payload = Data([UInt8(rand.int(0...4))]) + rand.bytes(rand.int(0...64))
    case 1:   // JSON objects of the known keys and others
        var fields: [String] = []
        for _ in 0..<rand.int(0...6) { fields.append("\"\(keys[rand.int(0...keys.count - 1)])\":\(randomValue())") }
        payload = Data([UInt8([1, 3, 1, 3, 2][rand.int(0...4)])]) + Data("{\(fields.joined(separator: ","))}".utf8)
    case 2:   // a real payload with bytes flipped, cut or added
        payload = seeds[rand.int(0...seeds.count - 1)]
        for _ in 0..<rand.int(1...4) {
            switch rand.int(0...2) {
            case 0 where !payload.isEmpty: let at = rand.int(0...payload.count - 1); payload[at] ^= UInt8(1 << rand.int(0...7))
            case 1 where payload.count > 1: payload = Data(payload.prefix(rand.int(1...payload.count - 1)))
            default: payload += rand.bytes(rand.int(1...8))
            }
        }
    default:  // sizes around the caps
        let type = UInt8(rand.int(1...3))
        let cap = type == 2 ? M.maxFramePayload : M.maxFormatPayload
        payload = Data([type]) + Data(count: max(0, cap + rand.int(-3...3) - 1))
        if type != 2 { payload = type == 1 ? formatPayload(size: cap + rand.int(-2...2)) : demandPayload(size: cap + rand.int(-2...2)) }
    }
    guard let m = M.parse(payload) else { continue }
    switch m { case .format: parsedCount[0] += 1; case .frame: parsedCount[1] += 1; case .demand: parsedCount[2] += 1 }
    if !sound(m, from: payload) {
        unsound += 1
        if unsound <= 3 { print("unsound: \(payload.prefix(40).map { String($0) }.joined(separator: " ")) → \(m)") }
    }
}
check(unsound == 0, "every value read from 20,000 payloads is inside the bounds and writes back (\(unsound) not)")
check(parsedCount.allSatisfy { $0 > 200 }, "each type was read often enough to mean something: \(parsedCount)")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
