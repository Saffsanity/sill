import Foundation

// Kind 48, the device's microphone on the Mac (Microphone.swift, docs/microphone-plan.md §4), and both ends'
// rules (MicrophonePolicy.swift, §3.3 with the 2026-11-18 overview's rules), against Sources/StreamProtocol
// compiled into this binary:
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/microphone/main.swift -o check
// The wire: the three types round trip, the caps and generation 1's bounds at their edges, a writer refuses
// rather than cuts, unknown types and keys skipped, the type 1 JSON is kind 43's AudioFormat's with two keys
// beside, kind 16's MicrophoneState and the window list's field; 20,000 random and mutated payloads never trap.
// The device: its rule over every combination of its inputs, the link's messages, the window it records
// from, the row's words. The Mac: the reducer's states, holder, takeovers, grace, limits and lines, each at
// its edge. Then 3,000 random sessions of devices and a Mac together against the invariants.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; if failures < 60 { print("FAIL (line \(line)): \(what())") } }
}
let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
typealias M = MicrophoneMessage
typealias F = MicrophoneFormat
typealias P = MicrophonePolicy
typealias S = MicrophoneState

/// SplitMix64: the same runs every time.
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
    mutating func bool(_ p: Double = 0.5) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
    mutating func bytes(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8(truncatingIfNeeded: next()) }) }
}

let cookie = Data([0xF8, 0xF0, 0x21, 0x2C, 0x00, 0xBC, 0x00])
func epoch(_ e: Int = 7, priming: Int = 240) -> F { F.epoch(e, primingFrames: priming, cookie: cookie) }
func roundTrips(_ m: M) -> Bool { m.serialized().flatMap(M.parse) == m }
func packets(_ epoch: Int = 7, seq: UInt32 = 0, count: Int = 10, bytes: Int = 80, segment: Bool = false) -> AudioPackets {
    AudioPackets(epoch: epoch, seq: seq, segmentStart: segment, packets: (0..<count).map { Data(repeating: UInt8($0 & 0xFF), count: bytes) })
}

// MARK: - The kind, the types, the caps

check(StreamMessageKind.microphone.rawValue == 48 && StreamMessageKind(rawValue: 48) == .microphone, "kind 48 is the microphone")
check(StreamMessageKind(rawValue: 45) == nil && StreamMessageKind(rawValue: 46) == nil, "45 and 46 are not this build's (the pen's, the camera's)")
check(M.typeFormat == 1 && M.typePackets == 2 && M.typeEnd == 3, "types 1, 2 and 3")
check(M.maxFormatPayload == 4096 && M.maxPacketsPayload == 16384, "kind 43's caps: 4,096 and 16,384 bytes")
check(MicrophoneCodec.generation == 1 && MicrophoneCodec.aacELD == "aac-eld" && MicrophoneCodec.hostTakes == ["aac-eld"]
      && MicrophoneCodec.deviceMakes == ["aac-eld"], "generation 1, AAC-ELD both ends")
check(MicrophoneCodec.sampleRate == 48_000 && MicrophoneCodec.channels == 1 && MicrophoneCodec.framesPerPacket == 480
      && MicrophoneCodec.bitrate == 64_000 && MicrophoneCodec.packetsPerMessage == 10, "48 kHz mono, 480 frames, 64 kbps, ten a message")
check(MicrophoneCodec.packetSizes == [480, 512] && MicrophoneCodec.primings == 0...2048 && MicrophoneCodec.cookieBytes == 1...256
      && MicrophoneCodec.bitrates == 8_000...320_000 && MicrophoneCodec.epochs == 0...65_535, "generation 1's bounds")
check(MicrophoneCodec.choose(taken: ["aac-eld"]) == "aac-eld" && MicrophoneCodec.choose(taken: ["opus", "aac-eld"]) == "aac-eld",
      "the first of the Mac's list the device makes")
check(MicrophoneCodec.choose(taken: nil) == nil && MicrophoneCodec.choose(taken: []) == nil && MicrophoneCodec.choose(taken: ["opus"]) == nil,
      "no list, an empty one, nothing in common: no codec")
check(MicrophoneCodec.choose(taken: ["opus", "aac-eld"], makes: ["opus", "aac-eld"]) == "opus", "the Mac's order wins")

// MARK: - Type 1: offers, claims, pauses and epochs

let offer = F(claim: true)
check(json(offer) == #"{"claim":true}"#, "an offer with its claim: \(json(offer))")
check(roundTrips(.format(offer)) && !offer.isEpoch && offer.isValid, "an offer round-trips, no epoch")
check(json(F()) == "{}" && roundTrips(.format(F())), "{} is an offer, and round-trips")
for pause in F.pauses {
    let p = F(pause: pause)
    check(roundTrips(.format(p)) && p.knownPause == pause && json(p) == "{\"pause\":\"\(pause)\"}", "the pause \(pause) round-trips")
}
check(F.pauses == ["background", "busy", "unavailable"], "three pauses")
check(F(pause: "thermal").knownPause == F.unavailable && F(pause: "").knownPause == F.unavailable, "a later pause reads as unavailable")
check(F().knownPause == nil, "no pause, none read")
let e7 = epoch()
check(e7.isEpoch && e7.isValid && roundTrips(.format(e7)), "an epoch's format round-trips")
check(json(e7) == #"{"bitrate":64000,"channels":1,"codec":"aac-eld","cookie":"\#(cookie.base64EncodedString())","epoch":7,"framesPerPacket":480,"primingFrames":240,"sampleRate":48000}"#,
      "an epoch's JSON is kind 43's AudioFormat's: \(json(e7))")
check(json(e7) == json(e7.format), "with no claim or pause, the very JSON of kind 43's format")
let withBoth = F(format: e7.format, claim: true, pause: F.busy)
check(json(withBoth) == #"{"bitrate":64000,"channels":1,"claim":true,"codec":"aac-eld","cookie":"\#(cookie.base64EncodedString())","epoch":7,"framesPerPacket":480,"pause":"busy","primingFrames":240,"sampleRate":48000}"#,
      "claim and pause beside kind 43's keys in one object: \(json(withBoth))")
check(roundTrips(.format(withBoth)), "an epoch with its claim and pause round-trips")
check(Wire.decode(AudioFormat.self, from: Wire.encode(withBoth)) == e7.format, "kind 43's reader reads a microphone format, skipping claim and pause")
check(Wire.decode(F.self, from: Wire.encode(e7.format)) == e7, "a kind 43 format reads as a microphone format without claim or pause")
check(M.parse(Data([M.typeFormat]) + Data(#"{"claim":false,"later":[1,2],"pause":"busy"}"#.utf8)) == .format(F(claim: false, pause: "busy")),
      "a later device's keys are skipped")
check(M.parse(Data([M.typeFormat]) + Data(#"{"claim":"yes"}"#.utf8)) == nil, "a claim that is not a Bool: the whole format dropped")
check(M.parse(Data([M.typeFormat]) + Data(#"{"pause":3}"#.utf8)) == nil, "a pause that is not a string: dropped")
check(M.parse(Data([M.typeFormat]) + Data("[]".utf8)) == nil && M.parse(Data([M.typeFormat])) == nil, "an array, or nothing: dropped")
// An epoch is whole or refused.
var bad = e7; bad.format.codec = "opus"
check(!bad.isValid && bad.isEpoch, "another codec is not generation 1")
for (name, mutate) in [("sampleRate", { (f: inout F) in f.format.sampleRate = nil }), ("channels", { $0.format.channels = nil }),
                       ("framesPerPacket", { $0.format.framesPerPacket = nil }), ("primingFrames", { $0.format.primingFrames = nil }),
                       ("epoch", { $0.format.epoch = nil }), ("cookie", { $0.format.cookie = nil })] as [(String, (inout F) -> Void)] {
    var f = e7; mutate(&f)
    check(!f.isValid, "an epoch without \(name) is refused")
    check(M.format(f).serialized() == nil, "a writer refuses an epoch without \(name)")
    check(M.parse(Data([M.typeFormat]) + Wire.encode(f)) == nil, "a reader drops an epoch without \(name)")
}
var noBitrate = e7; noBitrate.format.bitrate = nil
check(noBitrate.isValid, "an epoch may leave its bitrate out (display only)")
func edge(_ mutate: (inout F) -> Void) -> Bool { var f = e7; mutate(&f); return f.isValid }
check(edge { $0.format.sampleRate = 48_000 } && !edge { $0.format.sampleRate = 44_100 } && !edge { $0.format.sampleRate = 96_000 }, "48 kHz alone")
check(edge { $0.format.channels = 1 } && !edge { $0.format.channels = 2 } && !edge { $0.format.channels = 0 }, "one channel alone")
check(edge { $0.format.framesPerPacket = 480 } && edge { $0.format.framesPerPacket = 512 } && !edge { $0.format.framesPerPacket = 1024 }
      && !edge { $0.format.framesPerPacket = 479 } && !edge { $0.format.framesPerPacket = 0 }, "480 or 512 frames a packet")
check(edge { $0.format.primingFrames = 0 } && edge { $0.format.primingFrames = 2048 } && !edge { $0.format.primingFrames = 2049 }
      && !edge { $0.format.primingFrames = -1 }, "a priming of 0 to 2,048")
check(edge { $0.format.epoch = 0 } && edge { $0.format.epoch = 65_535 } && !edge { $0.format.epoch = 65_536 } && !edge { $0.format.epoch = -1 }, "epochs 0 to 65,535")
check(edge { $0.format.bitrate = 8_000 } && edge { $0.format.bitrate = 320_000 } && !edge { $0.format.bitrate = 7_999 }
      && !edge { $0.format.bitrate = 320_001 }, "bitrates 8 to 320 kbps")
check(edge { $0.format.cookie = Data([1]) } && edge { $0.format.cookie = Data(count: 256) } && !edge { $0.format.cookie = Data() }
      && !edge { $0.format.cookie = Data(count: 257) }, "a cookie of 1 to 256 bytes")
// An offer's stray kind 43 keys are bounded too.
check(!F(format: AudioFormat(sampleRate: 44_100)).isValid && !F(format: AudioFormat(epoch: 70_000)).isValid, "an offer's own keys within bounds")
check(F(format: AudioFormat(source: "test", app: "x")).isValid, "an offer's unused keys are let be")
// The cap.
let bigPause = String(repeating: "p", count: 4096 - 1 - #"{"pause":""}"#.utf8.count)
check(M.format(F(pause: bigPause)).serialized()?.count == 4096, "a format of exactly 4,096 bytes is written")
check(M.parse(M.format(F(pause: bigPause)).serialized() ?? Data()) != nil, "and read")
check(M.format(F(pause: bigPause + "p")).serialized() == nil, "one byte more is refused")
check(M.parse(Data([M.typeFormat]) + Data(#"{"pause":"\#(bigPause)p"}"#.utf8)) == nil, "and dropped by a reader")

// MARK: - Type 2: kind 43's packets

let p10 = packets()
check(roundTrips(.packets(p10)), "ten packets round-trip")
check(M.packets(p10).serialized() == p10.serialized(), "byte for byte kind 43's layout")
check(M.parse(p10.serialized()) == .packets(p10), "kind 43's packets read as the microphone's")
check(roundTrips(.packets(packets(count: 1))) && roundTrips(.packets(packets(count: 255, bytes: 50))), "1 and 255 packets")
check(M.packets(packets(count: 0)).serialized() == nil, "no packet: refused")
check(M.packets(packets(count: 256, bytes: 1)).serialized() == nil, "256 packets: refused, never cut")
check(M.packets(AudioPackets(epoch: 1, seq: 0, segmentStart: false, packets: [Data(count: 65_536)])).serialized() == nil,
      "a packet over 65,535 bytes: refused")
// At the 16,384-byte cap: 9 + n × (2 + bytes).
let atCap = AudioPackets(epoch: 1, seq: 0, segmentStart: true, packets: [Data(count: 16_384 - 9 - 2)])
check(M.packets(atCap).serialized()?.count == 16_384 && M.parse(atCap.serialized()) == .packets(atCap), "exactly 16,384 bytes: written and read")
let overCap = AudioPackets(epoch: 1, seq: 0, segmentStart: true, packets: [Data(count: 16_384 - 9 - 1)])
check(M.packets(overCap).serialized() == nil && M.parse(overCap.serialized()) == nil, "one byte more: refused and dropped")
var cut = p10.serialized(); cut.removeLast()
check(M.parse(cut) == nil, "a packets message cut short")
check(M.parse(p10.serialized() + Data([0])) == nil, "a byte left over")
check(M.parse(Data([2, 0, 1, 0, 0, 0, 0, 0, 0])) == nil, "a count of 0")
check(M.parse(Data([2, 0, 1])) == nil, "a header cut short")
let seg = packets(9, seq: 70_000, segment: true)
check(M.parse(seg.serialized()) == .packets(seg), "the epoch, seq and segment flag kept")
// The whole message: its header's stamp is the capture time.
let pm = M.packetsMessage(p10, captured: 1_800_000_000.25)
check(pm?.kind == .microphone && pm?.timestamp == 1_800_000_000.25 && pm?.isKeyframe == false && pm?.payload == p10.serialized(),
      "a type 2's header stamps its capture time")
check(M.packetsMessage(p10, captured: .nan) == nil && M.packetsMessage(packets(count: 0), captured: 1) == nil, "a stamp that is no time, or no packet: none")
let om = M.message(.format(offer), now: 12.5)
check(om?.kind == .microphone && om?.timestamp == 12.5 && om?.payload == M.format(offer).serialized(), "a type 1 stamped now")
check(M.message(.packets(p10), now: 1) == nil, "packets go only with their capture time")
check(M.message(.end, now: 3)?.payload == Data([3]), "the end stamped now")
if let whole = om?.serialized(), let h = StreamMessage.parseHeader(whole) {
    check(h.kind == .microphone && h.payloadLength == whole.count - StreamMessage.headerLength, "kind 48's header parses")
} else { check(false, "kind 48's header") }

// MARK: - Type 3, and the rest

check(M.end.serialized() == Data([3]) && M.parse(Data([3])) == .end, "the end is the single byte 3")
check(M.parse(Data([3, 0])) == nil && M.parse(Data([3, 3])) == nil, "an end with anything after: dropped")
check(M.parse(Data()) == nil, "an empty payload")
for t in [0, 4, 5, 43, 48, 255] { check(M.parse(Data([UInt8(t), 1, 2, 3])) == nil, "type \(t) is unknown") }
check(M.packets(p10).serialized()?.first == 2 && M.format(e7).serialized()?.first == 1, "each payload's first byte is its type")

// MARK: - Kind 16 and the window list

check(S.states == ["off", "notReady", "unpaired", "refused", "idle", "another", "inUse"], "the seven states")
for s in S.states { check(S(state: s).knownState == s, "\(s) reads as itself") }
check(S(state: "busy").knownState == S.off && S(state: "").knownState == S.off, "an unknown state reads as off")
check(S(state: S.inUse).wanted && S.states.filter { S(state: $0).wanted } == [S.inUse], "only inUse records")
check(S.states.filter { S(state: $0).takesOffers } == [S.idle, S.another, S.inUse], "offers go while idle, another or inUse")
check(!S(state: "future").takesOffers, "an unknown state takes no offer")
let st = S(state: S.another, codecs: ["aac-eld"], device: "iPhone")
check(json(st) == #"{"codecs":["aac-eld"],"device":"iPhone","state":"another"}"#, "kind 16's microphone: \(json(st))")
check(Wire.decode(S.self, from: Data(#"{"state":"idle","later":1}"#.utf8)) == S(state: S.idle), "a later key skipped")
check(Wire.decode(S.self, from: Data(#"{"codecs":["aac-eld"]}"#.utf8)) == nil, "no state: none")
let hs = HostSettingsState(settings: StreamSettings(maxFPS: 60, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: true,
                                                    directWireless: false, sendAudio: true),
                           persistent: true, virtualDisplayAvailable: true, softwareEncoder: false)
check(hs.microphone == nil && !json(hs).contains("microphone"), "kind 16 says nothing of the microphone unless set")
var hsMic = hs; hsMic.microphone = S(state: S.inUse, codecs: ["aac-eld"])
check(Wire.decode(HostSettingsState.self, from: Wire.encode(hsMic))?.microphone == S(state: S.inUse, codecs: ["aac-eld"]), "kind 16's microphone round-trips")
/// What a device before kind 48 decodes kind 16 as: the fields it knew.
struct OlderState: Codable { var settings: StreamSettings; var persistent: Bool; var virtualDisplayAvailable: Bool; var softwareEncoder: Bool }
check(Wire.decode(OlderState.self, from: Wire.encode(hsMic)) != nil, "an older device skips kind 16's microphone")
var list = WindowList(macName: "Studio", windows: [], active: .none)
check(list.microphone == nil && !json(list).contains("microphone"), "a list says nothing of the microphone unless set")
list.microphone = 1
check(Wire.decode(WindowList.self, from: Wire.encode(list))?.microphone == 1, "the list's microphone round-trips")
struct OlderList: Codable { var macName: String; var windows: [WindowInfo]; var active: StreamSource }
check(Wire.decode(OlderList.self, from: Wire.encode(list)) != nil, "an older device skips the list's microphone")

// MARK: - Random and mutated payloads

var rand = Rand(state: 0x4D1C_0048)
let seeds: [Data] = [M.format(e7).serialized()!, M.format(withBoth).serialized()!, M.format(offer).serialized()!,
                     M.packets(p10).serialized()!, M.end.serialized()!, M.packets(seg).serialized()!]
for i in 0..<20_000 {
    var d: Data
    switch i % 4 {
    case 0: d = rand.bytes(rand.int(0...64))
    case 1: d = Data([UInt8(rand.int(1...3))]) + rand.bytes(rand.int(0...200))
    default:
        d = seeds[rand.int(0...seeds.count - 1)]
        for _ in 0..<rand.int(1...4) where !d.isEmpty {
            switch rand.int(0...3) {
            case 0: d[d.startIndex + rand.int(0...d.count - 1)] = UInt8(truncatingIfNeeded: rand.next())
            case 1: d.removeLast(rand.int(1...min(4, d.count)))
            case 2: d.append(rand.bytes(rand.int(1...4)))
            default: d.insert(UInt8(truncatingIfNeeded: rand.next()), at: d.startIndex + rand.int(0...d.count - 1))
            }
        }
    }
    guard let m = M.parse(d) else { continue }
    switch m {
    case .format(let f): check(f.isValid, "a format read is inside the bounds")
    case .packets(let p): check((1...255).contains(p.packets.count) && d.count <= 16_384, "packets read are inside the caps")
    case .end: check(d == Data([3]), "an end read is the single byte")
    }
    check(m.serialized().flatMap(M.parse) == m, "what was read writes back to itself")
}

// MARK: - The device's rule

/// Every combination of the inputs that matter, by a mixed-radix index.
let permissions: [P.Permission] = [.undetermined, .granted, .denied]
let lists: [Int?] = [nil, 0, 1, 2]
let deviceStates: [S?] = [nil, S(state: S.off), S(state: S.idle, codecs: ["aac-eld"]), S(state: S.inUse, codecs: ["aac-eld"]),
                          S(state: S.another, codecs: ["aac-eld"], device: "iPhone"), S(state: S.inUse, codecs: ["opus"]),
                          S(state: S.refused), S(state: S.unpaired), S(state: "later")]
func device(_ index: Int) -> P.Device {
    var i = index
    func take(_ n: Int) -> Int { defer { i /= n }; return i % n }
    var d = P.Device()
    d.switchOn = take(2) == 1
    d.permission = permissions[take(3)]
    d.connected = take(2) == 1
    d.list = lists[take(4)]
    d.locked = take(2) == 1
    d.state = deviceStates[take(9)]
    d.foreground = take(2) == 1
    d.chosen = take(2) == 1
    d.interrupted = take(2) == 1
    d.inputAvailable = take(2) == 1
    return d
}
var combos = 0
for index in 0..<(2 * 3 * 2 * 4 * 2 * 9 * 2 * 2 * 2 * 2) {
    let d = device(index)
    let bits = index
    combos += 1
    let takes = d.connected && (d.list ?? 0) >= 1 && !d.locked
    check(P.macTakes(d) == takes, "the Mac takes kind 48 only connected, listed 1 or more, unlocked (\(bits))")
    let offers = d.switchOn && d.permission == .granted && takes && d.chosen && (d.state.map { [S.idle, S.another, S.inUse].contains($0.state) } ?? true)
    check(P.offers(d) == offers, "the offer's rule (\(bits))")
    let pause: String? = !d.foreground ? F.background : d.interrupted ? F.busy : !d.inputAvailable ? F.unavailable : nil
    check(P.pause(d) == pause, "the pause's order (\(bits))")
    let records = offers && pause == nil && d.state?.state == S.inUse && d.state?.codecs?.contains("aac-eld") == true
    check(P.records(d) == records, "records only offering, unpaused, inUse with a codec it makes (\(bits))")
    if P.records(d) {
        check(d.foreground && d.switchOn && d.permission == .granted && !d.locked && d.chosen && !d.interrupted, "never records in the background, locked, off or not chosen")
    }
}
check(combos == 13_824, "every combination of the device's inputs (\(combos))")
check(P.maxUnsentSeconds == 0.2 && P.maxUnsentMessages == 2, "at most 200 ms unsent: two messages")

// The link: what each step sends.
var d0 = P.Device(); d0.connected = true; d0.list = 1; d0.switchOn = true; d0.permission = .granted
var link = P.DeviceLink()
var r = link.step(d0, claimOwed: true)
check(r.send == [.format(F(claim: true))] && r.claimed, "the switch just on: an offer with its claim")
r = link.step(d0, claimOwed: false)
check(r.send.isEmpty && !r.claimed, "nothing more while nothing changes")
d0.foreground = false
r = link.step(d0, claimOwed: false)
check(r.send == [.format(F(pause: F.background))], "Sill leaves the screen: the offer again with its pause")
d0.foreground = true
r = link.step(d0, claimOwed: false)
check(r.send == [.format(F())], "back: the offer without a pause")
r = link.step(d0, claimOwed: true)
check(r.send == [.format(F(claim: true))] && r.claimed, "turned off and on again: a claim")
d0.state = S(state: S.inUse, codecs: ["aac-eld"])
r = link.step(d0, claimOwed: false)
check(r.send.isEmpty && P.records(d0), "inUse: records; the link sends nothing (the capture sends the epoch)")
d0.switchOn = false
r = link.step(d0, claimOwed: false)
check(r.send == [.end], "the switch off: the end")
r = link.step(d0, claimOwed: false)
check(r.send.isEmpty, "one end only, while the Mac still says inUse")
d0.state = S(state: S.idle, codecs: ["aac-eld"])
r = link.step(d0, claimOwed: false)
check(r.send.isEmpty, "idle after the end: nothing")
d0.state = S(state: S.inUse, codecs: ["aac-eld"])
r = link.step(d0, claimOwed: false)
check(r.send == [.end], "the Mac says inUse to a connection that does not offer: the end, once")
r = link.step(d0, claimOwed: false)
check(r.send.isEmpty, "and only once")
// Not chosen: no offer, no end, until the Mac says inUse.
var d1 = P.Device(); d1.connected = true; d1.list = 1; d1.switchOn = true; d1.permission = .granted
var link1 = P.DeviceLink()
_ = link1.step(d1, claimOwed: false)
d1.chosen = false
r = link1.step(d1, claimOwed: false)
check(r.send.isEmpty, "another window chosen: this one stops offering, without an end")
d1.state = S(state: S.inUse, codecs: ["aac-eld"])
r = link1.step(d1, claimOwed: false)
check(r.send == [.end], "and ends it once the Mac says inUse to it")
// Locked, or no field: nothing at all, and the offer again after.
var d2 = P.Device(); d2.connected = true; d2.list = 1; d2.switchOn = true; d2.permission = .granted
var link2 = P.DeviceLink()
check(link2.step(d2, claimOwed: false).send == [.format(F())], "an offer")
d2.locked = true
check(link2.step(d2, claimOwed: false).send.isEmpty, "locked: nothing")
d2.switchOn = false
check(link2.step(d2, claimOwed: false).send.isEmpty, "the switch off while locked: no end goes (the Mac takes nothing)")
d2.locked = false; d2.switchOn = true
check(link2.step(d2, claimOwed: false).send == [.format(F())], "unlocked: the offer again")
d2.list = 0
check(link2.step(d2, claimOwed: false).send.isEmpty, "a list that says 0: nothing")
d2.list = nil
check(link2.step(d2, claimOwed: false).send.isEmpty, "a list without the field: nothing")
var d3 = P.Device(); d3.connected = true; d3.list = 1; d3.switchOn = true; d3.permission = .undetermined
var link3 = P.DeviceLink()
check(link3.step(d3, claimOwed: true).send.isEmpty, "the permission not yet given: no offer, the claim kept")
d3.permission = .granted
check(link3.step(d3, claimOwed: true).send == [.format(F(claim: true))], "given: the offer with the claim")
d3.permission = .denied
check(link3.step(d3, claimOwed: false).send == [.end], "refused afterwards: the end")

// The window it records from.
let w = [P.Window(id: 1, foregroundActive: true, takes: true, lastUsedAt: 10), P.Window(id: 2, foregroundActive: true, takes: true, lastUsedAt: 20),
         P.Window(id: 3, foregroundActive: false, takes: true, lastUsedAt: 30), P.Window(id: 4, foregroundActive: true, takes: false, lastUsedAt: 40)]
check(P.chosen(w, previous: nil) == 2, "of those in front whose Mac takes it, the one used last")
check(P.chosen([w[0], P.Window(id: 5, foregroundActive: true, takes: true, lastUsedAt: nil)], previous: nil) == 1, "never used counts as before every other")
check(P.chosen([P.Window(id: 5, foregroundActive: true, takes: true, lastUsedAt: nil), P.Window(id: 6, foregroundActive: true, takes: true, lastUsedAt: nil)], previous: nil) == 5,
      "at the same moment, the first listed")
check(P.chosen([w[2]], previous: 3) == 3 && P.chosen([w[2]], previous: 9) == nil, "none in front: the last choice while it is listed")
check(P.chosen([w[3]], previous: nil) == nil, "a Mac that does not take it is never chosen")

// The row and its words.
func row(_ mutate: (inout P.Device) -> Void, version: String? = "0.7.0", other: Bool = false) -> P.Row {
    var d = P.Device(); d.connected = true; d.list = 1; d.state = S(state: S.idle, codecs: ["aac-eld"])
    mutate(&d)
    return P.row(d, hostVersion: version, mac: "Studio", device: "iPad", otherWindow: other)
}
check(row({ $0.list = nil }, version: nil) == .hidden, "the CLI: no row")
check(row({ $0.list = nil }) == .shown(enabled: false, footnote: "Update Sill on Studio to use this."), "an older Sill.app: update")
check(row({ $0.locked = true }) == .hidden, "locked: no row (the header says why)")
check(row({ $0.connected = false }) == .hidden, "not connected: no row")
check(row({ $0.list = 0; $0.state = S(state: S.off) }) == .shown(enabled: false, footnote: "Turn on Use iPhone and iPad microphones in Sill’s settings on Studio to use this."),
      "the Mac's switch off")
check(row({ $0.list = 0; $0.state = S(state: S.notReady) }) == .shown(enabled: false, footnote: "Set up Sill Microphone in Sill’s settings on Studio to use this."),
      "Sill Microphone not set up")
check(row({ $0.state = S(state: S.unpaired) }) == .shown(enabled: false, footnote: "Pair this iPad with Studio to use its microphone there."), "unpaired")
check(row({ $0.state = S(state: S.refused) }) == .shown(enabled: true, footnote: "Studio stopped taking this iPad’s microphone for a minute."), "refused")
check(row({ _ in }) == .shown(enabled: true, footnote: "Turn this on to use this iPad’s microphone on Studio: choose Sill Microphone there, in a call, a recording or dictation. It turns off when Sill closes."),
      "off, the Mac ready")
check(row({ $0.state = S(state: S.another, codecs: ["aac-eld"], device: "iPhone") }) == .shown(enabled: true, footnote: "Studio is using iPhone’s microphone. Turn this on to use this iPad’s instead."),
      "off, another device's in use")
check(row({ $0.switchOn = true }) == .shown(enabled: true, footnote: "Ready: Studio hears this microphone once an app there uses Sill Microphone."), "on, waiting")
check(row({ $0.switchOn = true; $0.state = S(state: S.inUse, codecs: ["aac-eld"]) })
      == .shown(enabled: true, footnote: "Studio hears this iPad’s microphone as Sill Microphone. While it’s on, sound from Studio plays as on a call."), "on and in use")
check(row({ $0.switchOn = true; $0.state = S(state: S.another, codecs: ["aac-eld"], device: "iPhone") })
      == .shown(enabled: true, footnote: "Studio is using iPhone’s microphone. Turn this off and on again to use this one instead."), "on, another device took it")
check(row({ $0.switchOn = true; $0.interrupted = true }) == .shown(enabled: true, footnote: "Paused during the call on this iPad."), "a call")
check(row({ $0.switchOn = true; $0.inputAvailable = false }) == .shown(enabled: true, footnote: "This iPad has no microphone to use right now."), "no input")
check(row({ $0.switchOn = true }, other: true) == .shown(enabled: true, footnote: "Your other Sill window sends the microphone."), "another window")
check(row({ $0.permission = .denied }) == .shown(enabled: true, footnote: "Sill isn’t allowed to use the microphone. You can allow it in Settings."), "refused permission")
check(row({ $0.switchOn = true; $0.state = S(state: "later", codecs: ["aac-eld"]) }) == .shown(enabled: false, footnote: "Turn on Use iPhone and iPad microphones in Sill’s settings on Studio to use this."),
      "an unknown state reads as off")
check(P.Copy.rowTitle == "Share Microphone" && P.Copy.rowSpoken(mac: "Studio", device: "iPad") == "Send this iPad’s microphone to Studio", "the row's title and VoiceOver")
check(P.Copy.openSettings == "Open Settings", "the button")

// MARK: - The Mac's rule

typealias H = P.Host
func ready(_ h: inout H, at t: Double = 0) {
    _ = h.handle(.switchChanged(true), at: t); _ = h.handle(.readyChanged(true), at: t); _ = h.handle(.unlockedChanged(true), at: t)
}
func states(_ fx: [H.Effect]) -> [Int: S?] {
    var out: [Int: S?] = [:]
    for e in fx { if case .state(let id, let s) = e { out[id] = s } }
    return out
}
func lines(_ fx: [H.Effect]) -> [String] { fx.compactMap { if case .line(let l) = $0 { return l } else { return nil } } }
func playout(_ fx: [H.Effect]) -> H.Effect? { fx.last { if case .playout = $0 { return true }; if case .noPlayout = $0 { return true }; return false } }

check(H.grace == 10 && H.maxOffersPerSecond == 10 && H.maxEpochsPerMinute == 6 && H.maxSoundPerSecond == 1.5 && H.soundWindow == 2
      && H.refusedFor == 60 && H.silenceAfter == 2 && H.refusalLineSpacing == 60, "the Mac's limits")
var h = H()
var fx = h.handle(.joined(1, key: "kA", paired: true, name: "iPad"), at: 0)
check(states(fx)[1] == .some(nil) || states(fx)[1] == nil, "locked at first (no reading): no state")
check(h.state(of: 1, at: 0) == nil && !h.available && h.advertised == 0, "nothing until the switch, Sill Microphone and the lock allow it")
fx = h.handle(.unlockedChanged(true), at: 0)
check(states(fx)[1] == .some(S(state: S.off)), "unlocked, the switch off: off")
fx = h.handle(.switchChanged(true), at: 0)
check(states(fx)[1] == .some(S(state: S.notReady)) && h.advertised == 0, "the switch on, Sill Microphone not set up: notReady, the list says 0")
fx = h.handle(.readyChanged(true), at: 0)
check(states(fx)[1] == .some(S(state: S.idle, codecs: ["aac-eld"])) && h.advertised == 1, "set up: idle with the codecs, the list says 1")
fx = h.handle(.format(1, F(claim: true)), at: 1)
check(h.holder == "kA" && states(fx).isEmpty, "a claim: the holder; idle still, since no app uses it")
fx = h.handle(.appChanged(true), at: 2)
check(states(fx)[1] == .some(S(state: S.inUse, codecs: ["aac-eld"])) && h.wanted(1, at: 2), "an app uses it: inUse")
check(playout(fx) == nil, "no playout before its epoch's format")
fx = h.handle(.format(1, epoch(7)), at: 2.5)
check(playout(fx) == .playout(key: "kA", session: 1, format: epoch(7)), "the epoch's format: the playout's source")
check(lines(fx) == ["Microphone: iPad is Sill Microphone’s input now (AAC-ELD 48 kHz mono, 64 kbps)."], "its line: \(lines(fx))")
var t = h.takesPackets(1, epoch: 7, packets: 10, framesPerPacket: 480, at: 2.6)
check(t.take && t.effects == [.count("mic.in")], "its packets are taken")
t = h.takesPackets(1, epoch: 8, packets: 10, framesPerPacket: 480, at: 2.7)
check(!t.take && t.effects == [.count("mic.dropped.epoch")], "another epoch's are not")
check(h.inUse(at: 2.7) == "iPad", "the card's name")
// A second device, paired, offering without a claim: another.
fx = h.handle(.joined(2, key: "kB", paired: true, name: "iPhone"), at: 3)
check(states(fx)[2] == .some(S(state: S.another, codecs: ["aac-eld"], device: "iPad")), "another device joins: another, naming the holder")
fx = h.handle(.format(2, F()), at: 3)
check(h.holder == "kA" && states(fx).isEmpty, "an offer without a claim does not take it")
t = h.takesPackets(2, epoch: 7, packets: 10, framesPerPacket: 480, at: 3.1)
check(!t.take && t.effects == [.count("mic.dropped.notWanted")], "nor are its packets taken")
// Its claim takes it, and tells the previous holder.
fx = h.handle(.format(2, F(claim: true)), at: 4)
check(h.holder == "kB", "a claim takes it")
check(states(fx)[1] == .some(S(state: S.another, codecs: ["aac-eld"], device: "iPhone")), "the previous holder hears another, naming the new one")
check(states(fx)[2] == .some(S(state: S.inUse, codecs: ["aac-eld"])), "the new holder: inUse")
check(lines(fx).contains("Microphone: iPhone took over from iPad."), "one took-over line: \(lines(fx))")
check(playout(fx) == .noPlayout, "the old sound stops until the new epoch comes")
fx = h.handle(.format(2, epoch(3)), at: 4.2)
check(playout(fx) == .playout(key: "kB", session: 2, format: epoch(3)), "the new device's epoch")
check(!h.takesPackets(1, epoch: 7, packets: 10, framesPerPacket: 480, at: 4.3).take, "the old holder's packets go nowhere now")
// Its end: the most recent standing offer takes it back.
fx = h.handle(.end(2), at: 5)
check(h.holder == "kA" && lines(fx).contains("Microphone: iPhone stopped."), "the holder's end: the standing offer takes it, a line")
check(states(fx)[1] == .some(S(state: S.inUse, codecs: ["aac-eld"])) && states(fx)[2] == .some(S(state: S.another, codecs: ["aac-eld"], device: "iPad")),
      "inUse again for A; B, whose offer ended, hears that A has it")
// A move: A's session leaves, its new one offers within the grace: kept, silently.
fx = h.handle(.format(1, epoch(9)), at: 5.1)
check(playout(fx) == .playout(key: "kA", session: 1, format: epoch(9)), "A's new epoch")
fx = h.handle(.joined(3, key: "kA", paired: true, name: "iPad"), at: 6)
check(states(fx)[3] == .some(S(state: S.idle, codecs: ["aac-eld"])), "A's second session: idle (the first one offers)")
fx = h.handle(.format(3, epoch(9)), at: 6)
check(h.holder == "kA" && playout(fx) == .playout(key: "kA", session: 3, format: epoch(9)), "the move: the same device, the same epoch, the new session")
check(lines(fx).isEmpty, "a move says nothing")
check(states(fx)[1] == .some(S(state: S.idle, codecs: ["aac-eld"])) && states(fx)[3] == .some(S(state: S.inUse, codecs: ["aac-eld"])), "the old session idle, the new inUse")
fx = h.handle(.left(1), at: 6.5)
check(h.holder == "kA" && playout(fx) == nil, "the old session leaving changes nothing")
// The new session leaves: the offer outlives it for the grace, then the holder goes.
fx = h.handle(.left(3), at: 7)
check(h.holder == "kA" && playout(fx) == .noPlayout, "the holder's session left: silence, the holder kept for the grace")
check(h.state(of: 2, at: 7) == S(state: S.another, codecs: ["aac-eld"], device: "iPad") && states(fx)[2] == nil, "B still hears another meanwhile")
fx = h.handle(.tick, at: 16.9)
check(h.holder == "kA", "kept until the grace is over")
fx = h.handle(.tick, at: 17)
check(h.holder == nil && lines(fx) == ["Microphone: iPad left."], "the grace over: freed, one line (B has no standing offer: it ended)")
check(states(fx)[2] == .some(S(state: S.idle, codecs: ["aac-eld"])), "B idle")
// Back within the grace keeps it: a quick reconnect.
var g = H(); ready(&g)
_ = g.handle(.appChanged(true), at: 0)
_ = g.handle(.joined(1, key: "kA", paired: true, name: "iPad"), at: 0)
_ = g.handle(.joined(2, key: "kB", paired: true, name: "iPhone"), at: 0)
_ = g.handle(.format(2, F(claim: true)), at: 0)
_ = g.handle(.format(1, F(claim: true)), at: 1)
_ = g.handle(.left(1), at: 2)
_ = g.handle(.tick, at: 11.9)
check(g.holder == "kA", "within the grace")
_ = g.handle(.joined(5, key: "kA", paired: true, name: "iPad"), at: 11.95)
fx = g.handle(.format(5, F()), at: 11.95)
check(g.holder == "kA" && g.wanted(5, at: 12) && states(fx)[5] == .some(S(state: S.inUse, codecs: ["aac-eld"])), "a reconnect within the grace keeps it, without a claim")
_ = g.handle(.tick, at: 30)
check(g.holder == "kA", "and the grace is over for nobody")
// An end from a session that no longer says the offer (the old connection of a move, a window no longer
// chosen) ends nothing.
var mv = H(); ready(&mv); _ = mv.handle(.appChanged(true), at: 0)
_ = mv.handle(.joined(1, key: "kA", paired: true, name: "iPad"), at: 0)
_ = mv.handle(.joined(2, key: "kA", paired: true, name: "iPad"), at: 0)
_ = mv.handle(.format(1, F(claim: true)), at: 0)
_ = mv.handle(.format(2, F()), at: 1)
fx = mv.handle(.end(1), at: 2)
check(mv.holder == "kA" && mv.offers["kA"]?.session == 2 && mv.wanted(2, at: 2) && lines(fx).isEmpty, "an end from the session no longer offering ends nothing")
fx = mv.handle(.end(2), at: 3)
check(mv.holder == nil && lines(fx) == ["Microphone: iPad stopped."], "the offering session's end ends it")
// The successor: the most recent claim.
var q = H(); ready(&q); _ = q.handle(.appChanged(true), at: 0)
for (i, k) in ["kA", "kB", "kC"].enumerated() { _ = q.handle(.joined(i + 1, key: k, paired: true, name: k), at: 0) }
_ = q.handle(.format(1, F(claim: true)), at: 1)
_ = q.handle(.format(3, F(claim: true)), at: 2)
_ = q.handle(.format(2, F(claim: true)), at: 3)
check(q.holder == "kB", "the last claim holds it")
_ = q.handle(.end(2), at: 4)
check(q.holder == "kC", "its end: the most recent of the others (kC claimed after kA)")
_ = q.handle(.format(1, F(pause: F.background)), at: 5)
check(q.holder == "kC", "an offer's pause takes nothing")
_ = q.handle(.end(3), at: 6)
check(q.holder == "kA", "then kA")
// Refusals: unpaired, the switch, readiness, the lock.
var u = H(); ready(&u); _ = u.handle(.appChanged(true), at: 0)
fx = u.handle(.joined(1, key: "kU", paired: false, name: "Guest"), at: 0)
check(states(fx)[1] == .some(S(state: S.unpaired)), "an unpaired session: unpaired")
fx = u.handle(.format(1, F(claim: true)), at: 0)
check(u.holder == nil && fx.contains(.count("mic.refused.unpaired")) && lines(fx) == ["Microphone: refused from Guest: it isn’t paired with this Mac."],
      "its offer refused, one line: \(lines(fx))")
fx = u.handle(.format(1, F(claim: true)), at: 30)
check(lines(fx).isEmpty && fx.contains(.count("mic.refused.unpaired")), "a line a minute at most")
fx = u.handle(.format(1, F(claim: true)), at: 61)
check(lines(fx).count == 1, "the next minute's")
check(!u.takesPackets(1, epoch: 0, packets: 10, framesPerPacket: 480, at: 61).take, "its packets never taken")
fx = u.handle(.joined(2, key: nil, paired: false, name: "Plain"), at: 62)
check(states(fx)[2] == .some(S(state: S.unpaired)), "a plain door's session (no key): unpaired")
_ = u.handle(.joined(3, key: "kP", paired: true, name: "Paired"), at: 62)
_ = u.handle(.format(3, F(claim: true)), at: 62)
_ = u.handle(.format(3, epoch(1)), at: 62)
check(u.wanted(3, at: 62), "a paired session records")
fx = u.handle(.paired(3, false), at: 63)
check(!u.wanted(3, at: 63) && u.holder == nil && states(fx)[3] == .some(S(state: S.unpaired)) && playout(fx) == .noPlayout,
      "unpaired mid-session: refused at once, the sound stops")
check(lines(fx) == ["Microphone: Paired is no longer paired: its microphone stopped."], "its line: \(lines(fx))")
_ = u.handle(.paired(3, true), at: 64)
_ = u.handle(.format(3, F(claim: true)), at: 64)
_ = u.handle(.format(3, epoch(2)), at: 64)
fx = u.handle(.removed(key: "kP"), at: 65)
check(u.holder == nil && !u.wanted(3, at: 65) && playout(fx) == .noPlayout, "removed from the trust list: freed at once, no grace")
for (event, state) in [(H.Event.switchChanged(false), S.off), (.readyChanged(false), S.notReady)] {
    var v = H(); ready(&v); _ = v.handle(.appChanged(true), at: 0)
    _ = v.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
    _ = v.handle(.format(1, F(claim: true)), at: 0); _ = v.handle(.format(1, epoch(1)), at: 0)
    fx = v.handle(event, at: 1)
    check(states(fx)[1] == .some(S(state: state)) && playout(fx) == .noPlayout && !v.wanted(1, at: 1), "\(event): \(state), silence")
    check(!v.takesPackets(1, epoch: 1, packets: 10, framesPerPacket: 480, at: 1).take, "\(event): no packet taken")
    check(v.advertised == 0, "\(event): the list says 0")
}
var lk = H(); ready(&lk); _ = lk.handle(.appChanged(true), at: 0)
_ = lk.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
_ = lk.handle(.format(1, F(claim: true)), at: 0); _ = lk.handle(.format(1, epoch(1)), at: 0)
fx = lk.handle(.unlockedChanged(false), at: 1)
check(states(fx)[1] == .some(nil) && playout(fx) == .noPlayout && !lk.wanted(1, at: 1), "locked: no state at all, silence")
check(!lk.takesPackets(1, epoch: 1, packets: 10, framesPerPacket: 480, at: 1).take, "locked: nothing taken")
fx = lk.lockedArrival(1, offConsole: false, at: 1)
check(fx == [.count("mic.refused.locked"), .line("Microphone: refused from iPad: this Mac is locked.")], "a kind 48 refused by the lock: \(fx)")
check(lk.lockedArrival(1, offConsole: true, at: 30) == [.count("mic.refused.locked")], "a line a minute")
check(lk.lockedArrival(1, offConsole: true, at: 62) == [.count("mic.refused.locked"), .line("Microphone: refused from iPad: another user is on the screen.")], "off console's words")
fx = lk.handle(.unlockedChanged(true), at: 70)
check(states(fx)[1] == .some(S(state: S.inUse, codecs: ["aac-eld"])) && lk.holder == "k", "unlocked: the holder kept, inUse again")
check(playout(fx) == nil, "its old epoch is over: no playout before a new format")
fx = lk.handle(.format(1, epoch(2)), at: 70.5)
check(playout(fx) == .playout(key: "k", session: 1, format: epoch(2)), "a new epoch after the unlock")
// No app: idle, silence.
fx = lk.handle(.appChanged(false), at: 71)
check(states(fx)[1] == .some(S(state: S.idle, codecs: ["aac-eld"])) && playout(fx) == .noPlayout, "no app: idle, silence")
check(!lk.takesPackets(1, epoch: 2, packets: 10, framesPerPacket: 480, at: 71).take, "no app: nothing taken")
// The limits at their edges.
var lim = H(); ready(&lim); _ = lim.handle(.appChanged(true), at: 0)
_ = lim.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
for i in 0..<10 { _ = lim.handle(.format(1, F(pause: i % 2 == 0 ? F.busy : nil)), at: 0.5) }
check(lim.refusal(1, at: 0.5) == nil, "ten type 1 in a second: taken")
fx = lim.handle(.format(1, F()), at: 0.6)
check(lim.refusal(1, at: 0.6) == .refused && states(fx)[1] == .some(S(state: S.refused)) && lim.holder == nil,
      "the eleventh: refused for a minute, its offer gone")
check(lines(fx) == ["Microphone: iPad sent more than 10 offers in a second: refused for a minute."], "its line: \(lines(fx))")
check(lim.refusal(1, at: 60.5) == .refused, "for the minute")
fx = lim.handle(.tick, at: 60.6)
check(lim.refusal(1, at: 60.6) == nil && states(fx)[1] == .some(S(state: S.idle, codecs: ["aac-eld"])), "then idle again")
var ep = H(); ready(&ep); _ = ep.handle(.appChanged(true), at: 0)
_ = ep.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
_ = ep.handle(.format(1, F(claim: true)), at: 0)
for i in 0..<6 { _ = ep.handle(.format(1, epoch(i)), at: Double(i) * 5) }
check(ep.refusal(1, at: 30) == nil, "six epochs a minute: taken")
fx = ep.handle(.format(1, epoch(6)), at: 30)
check(ep.refusal(1, at: 30) == .refused && lines(fx) == ["Microphone: iPad started more than 6 recordings in a minute: refused for a minute."], "the seventh: refused")
var ep2 = H(); ready(&ep2); _ = ep2.handle(.appChanged(true), at: 0)
_ = ep2.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
_ = ep2.handle(.format(1, F(claim: true)), at: 0)
for i in 0..<7 { _ = ep2.handle(.format(1, epoch(i)), at: Double(i) * 10.1) }
check(ep2.refusal(1, at: 61) == nil, "seven epochs over more than a minute: taken")
// Sound: 1.5 s a second over 2 s, at the edge.
var snd = H(); ready(&snd); _ = snd.handle(.appChanged(true), at: 0)
_ = snd.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
_ = snd.handle(.format(1, F(claim: true)), at: 0); _ = snd.handle(.format(1, epoch(1)), at: 0)
var taken = 0
for i in 0..<30 { if snd.takesPackets(1, epoch: 1, packets: 10, framesPerPacket: 480, at: 1 + Double(i) * 0.0666).take { taken += 1 } }
check(taken == 30 && snd.refusal(1, at: 3) == nil, "3 s of sound in 2 s: taken whole (\(taken))")
t = snd.takesPackets(1, epoch: 1, packets: 1, framesPerPacket: 480, at: 2.95)
check(!t.take && snd.refusal(1, at: 2.95) == .refused && t.effects.contains(.line("Microphone: iPad sent 1.5 s of sound in a second: refused for a minute.")),
      "10 ms more: refused, its line: \(t.effects)")
check(t.effects.contains(.state(1, S(state: S.refused))) && t.effects.contains(.noPlayout), "refused: its state, silence")
var steady = H(); ready(&steady); _ = steady.handle(.appChanged(true), at: 0)
_ = steady.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
_ = steady.handle(.format(1, F(claim: true)), at: 0); _ = steady.handle(.format(1, epoch(1)), at: 0)
var all = true
for i in 0..<3600 { all = all && steady.takesPackets(1, epoch: 1, packets: 10, framesPerPacket: 480, at: Double(i) * 0.1).take }
check(all, "an hour of one second a second: every message taken")
// Silence.
fx = steady.handle(.tick, at: 360.5)
check(lines(fx).isEmpty, "1.6 s without a packet: nothing")
fx = steady.handle(.tick, at: 362)
check(lines(fx) == ["Microphone: iPad went silent for 2 s."], "2 s: one line")
check(lines(steady.handle(.tick, at: 365)).isEmpty, "said once")
_ = steady.takesPackets(1, epoch: 1, packets: 10, framesPerPacket: 480, at: 366)
check(lines(steady.handle(.tick, at: 368.5)) == ["Microphone: iPad went silent for 2 s."], "again after sound came back")
// Names are cleaned.
var nm = H(); ready(&nm)
_ = nm.handle(.joined(1, key: "k", paired: true, name: "Evil\nMicrophone: forged"), at: 0)
_ = nm.handle(.joined(2, key: "k2", paired: true, name: "Other"), at: 0)
_ = nm.handle(.format(1, F(claim: true)), at: 0)
check(nm.state(of: 2, at: 0)?.device == "Evil Microphone: forged", "a name is one clean line")
var empty = H(); ready(&empty)
_ = empty.handle(.joined(1, key: "k", paired: true, name: "\n\t"), at: 0)
_ = empty.handle(.joined(2, key: "k2", paired: true, name: "Other"), at: 0)
_ = empty.handle(.format(1, F(claim: true)), at: 0)
check(empty.state(of: 2, at: 0)?.device == "A device", "an empty name: A device")
check(P.Copy.switchChange(from: false, to: true) == "Settings: device microphones off → on", "the settings line")

// MARK: - Random sessions of devices and a Mac

/// One window of one device, with its connection to the Mac.
struct Win {
    var device: Int
    var conn: Int?
    var front = true
    var lastUsed: Double = 0
    var d = P.Device()
    var link = P.DeviceLink()
    var recording = false
    var epoch = 0
    var seq: UInt32 = 0
}
struct Dev {
    var switchOn = false
    var permission = P.Permission.granted
    var claimOwed = false
    var interrupted = false
    var paired = true
    var chosen: Int?
    var nextEpoch = 0
}
enum Up: Equatable { case msg(MicrophoneMessage), packets(epoch: Int, count: Int) }

var rng = Rand(state: 0x5111_0048)
var runs = 0
var everAnotherAfterClaim = true
var coverage = (taken: 0, takeovers: 0, moves: 0, movesRecording: 0, refusedTaken: 0, ends: 0, selfHeals: 0, lockedDrops: 0)
for run in 0..<3000 {
    runs += 1
    var mac = H()
    var now = 0.0
    var devs = (0..<rng.int(1...3)).map { _ in Dev(paired: rng.bool(0.85)) }
    var wins: [Win] = []
    for i in devs.indices { for _ in 0..<rng.int(1...2) { wins.append(Win(device: i)) } }
    var nextConn = 1
    var upQueue: [Int: [Up]] = [:]          // per connection, in order
    var downState: [Int: MicrophoneState?] = [:]   // per connection, the latest kind 16
    var pendingDown: [(at: Double, conn: Int, state: MicrophoneState?)] = []
    var connOf: [Int: Int] = [:]            // connection → window index
    var lockedNow = true
    func key(_ dev: Int) -> String { "k\(dev)" }
    func apply(_ fx: [H.Effect]) {
        for e in fx {
            if case .state(let c, let s) = e { pendingDown.append((now + Double(rng.int(0...30)) / 1000, c, s)) }
        }
    }
    for _ in 0..<rng.int(40...160) {
        now += Double(rng.int(1...400)) / 1000
        // Something happens.
        switch rng.int(0...19) {
        case 0: apply(mac.handle(.switchChanged(rng.bool(0.85)), at: now))
        case 1: apply(mac.handle(.readyChanged(rng.bool(0.9)), at: now))
        case 2: lockedNow = rng.bool(0.2); apply(mac.handle(.unlockedChanged(!lockedNow), at: now))
        case 3, 4: apply(mac.handle(.appChanged(rng.bool(0.7)), at: now))
        case 5, 6:
            let i = rng.int(0...devs.count - 1)
            let on = rng.bool(0.7)
            if on && !devs[i].switchOn { devs[i].claimOwed = true }
            devs[i].switchOn = on
            if !on { devs[i].claimOwed = false }
        case 7:
            let i = rng.int(0...wins.count - 1)
            if let c = wins[i].conn {
                // The connection ends (a drop, or the end of a move).
                apply(mac.handle(.left(c), at: now)); upQueue[c] = nil; connOf[c] = nil; wins[i].conn = nil
                wins[i].link = P.DeviceLink(); wins[i].recording = false
            } else {
                let c = nextConn; nextConn += 1
                wins[i].conn = c; connOf[c] = i; upQueue[c] = []
                let dv = wins[i].device
                apply(mac.handle(.joined(c, key: devs[dv].paired ? key(dv) : (rng.bool(0.5) ? key(dv) : nil), paired: devs[dv].paired, name: "Device \(dv)"), at: now))
                wins[i].d.state = nil
            }
        case 8:
            // A move: a new connection for the window, the old one leaving a little later.
            let i = rng.int(0...wins.count - 1)
            guard let old = wins[i].conn else { break }
            let c = nextConn; nextConn += 1
            let dv = wins[i].device
            apply(mac.handle(.joined(c, key: devs[dv].paired ? key(dv) : nil, paired: devs[dv].paired, name: "Device \(dv)"), at: now))
            wins[i].conn = c; connOf[c] = i; upQueue[c] = []
            wins[i].link = P.DeviceLink()
            wins[i].d.state = nil
            if wins[i].recording { upQueue[c]?.append(.msg(.format(F.epoch(wins[i].epoch, primingFrames: 240, cookie: cookie)))) }
            apply(mac.handle(.left(old), at: now + 0.001)); upQueue[old] = nil; connOf[old] = nil
            coverage.moves += 1
            if wins[i].recording { coverage.movesRecording += 1 }
        case 9: let i = rng.int(0...wins.count - 1); wins[i].front = rng.bool(0.7)
        case 10: let i = rng.int(0...wins.count - 1); wins[i].lastUsed = now
        case 11: let i = rng.int(0...devs.count - 1); devs[i].interrupted = rng.bool(0.3)
        case 12:
            // The device is removed from the Mac's trust list.
            let i = rng.int(0...devs.count - 1)
            if rng.bool(0.15), devs[i].paired { devs[i].paired = false; apply(mac.handle(.removed(key: key(i)), at: now)) }
        case 13: let i = rng.int(0...devs.count - 1); if rng.bool(0.1) { devs[i].permission = .denied; devs[i].switchOn = false }
        default: apply(mac.handle(.tick, at: now))
        }
        // Kind 16 arrives.
        pendingDown.sort { $0.at < $1.at }
        while let first = pendingDown.first, first.at <= now {
            pendingDown.removeFirst()
            if let i = connOf[first.conn] { wins[i].d.state = first.state }
            downState[first.conn] = first.state
        }
        // Each device chooses its window, and each window steps.
        for dv in devs.indices {
            let mine = wins.indices.filter { wins[$0].device == dv }
            let windows = mine.map { P.Window(id: $0, foregroundActive: wins[$0].front, takes: wins[$0].conn != nil && (mac.advertised >= 1) && !lockedNow, lastUsedAt: wins[$0].lastUsed) }
            devs[dv].chosen = P.chosen(windows, previous: devs[dv].chosen)
        }
        for i in wins.indices {
            let dv = wins[i].device
            var d = wins[i].d
            d.switchOn = devs[dv].switchOn
            d.permission = devs[dv].permission
            d.connected = wins[i].conn != nil
            d.list = mac.advertised      // the list as the Mac sends it now (its field)
            d.locked = lockedNow
            d.foreground = wins[i].front
            d.chosen = devs[dv].chosen == i
            d.interrupted = devs[dv].interrupted
            wins[i].d = d
            guard let c = wins[i].conn else { continue }
            let step = wins[i].link.step(d, claimOwed: devs[dv].claimOwed)
            if step.claimed { devs[dv].claimOwed = false }
            for m in step.send { upQueue[c, default: []].append(.msg(m)) }
            let rec = P.records(d)
            // Invariants of the device.
            if rec {
                check(d.foreground && !d.interrupted && d.switchOn && !d.locked && d.chosen, "run \(run): a device records only in front, on, unlocked, chosen")
            }
            if rec && !wins[i].recording {
                wins[i].recording = true
                wins[i].epoch = devs[dv].nextEpoch & 0xFFFF; devs[dv].nextEpoch += 1
                wins[i].seq = 0
                upQueue[c, default: []].append(.msg(.format(F.epoch(wins[i].epoch, primingFrames: 240, cookie: cookie))))
            } else if !rec && wins[i].recording {
                wins[i].recording = false
            }
            if wins[i].recording { upQueue[c, default: []].append(.packets(epoch: wins[i].epoch, count: 10)) }
        }
        // Never two windows of a device recording.
        for dv in devs.indices { check(wins.filter { $0.device == dv && $0.recording }.count <= 1, "run \(run): one window of a device records") }
        // The Mac reads what came, a few messages per connection.
        for c in upQueue.keys.sorted() {
            for _ in 0..<rng.int(0...4) {
                guard var q = upQueue[c], !q.isEmpty else { break }
                let up = q.removeFirst(); upQueue[c] = q
                if lockedNow { _ = mac.lockedArrival(c, offConsole: false, at: now); coverage.lockedDrops += 1; continue }
                let holderBefore = mac.holder
                switch up {
                case .msg(.format(let f)):
                    let fx = mac.handle(.format(c, f), at: now); apply(fx)
                    if let before = holderBefore, let after = mac.holder, before != after, f.claim == true,
                       let o = mac.offers[before], let s = o.session, mac.sessions[s] != nil {
                        // A takeover tells the previous holder's offering session.
                        let told = fx.contains { if case .state(s, let st) = $0 { return st?.state == S.another } else { return false } }
                        everAnotherAfterClaim = everAnotherAfterClaim && told
                        coverage.takeovers += 1
                    }
                case .msg(.end):
                    coverage.ends += 1
                    if let i = connOf[c], wins[i].d.switchOn { coverage.selfHeals += 1 }
                    apply(mac.handle(.end(c), at: now))
                case .msg(.packets): break
                case .packets(let e, let n):
                    let r = mac.takesPackets(c, epoch: e, packets: n, framesPerPacket: 480, at: now)
                    apply(r.effects)
                    if r.take {
                        coverage.taken += 1
                        let s = mac.sessions[c]
                        check(s != nil && s!.paired && s!.key != nil, "run \(run): taken only from a present, paired session")
                        check(mac.available && mac.appUses && !lockedNow, "run \(run): taken only while available and used")
                        check(s?.key == mac.holder && mac.offers[mac.holder ?? ""]?.session == c, "run \(run): taken only from the holder's offering session")
                    }
                }
            }
        }
        // The Mac's invariants.
        let wanted = mac.sessions.keys.filter { mac.wanted($0, at: now) }
        check(wanted.count <= 1, "run \(run): at most one session wanted (\(wanted))")
        for id in wanted {
            let s = mac.sessions[id]!
            check(mac.available && mac.appUses && s.paired && s.key == mac.holder, "run \(run): wanted only when allowed, used, paired and the holder's")
        }
        if lockedNow { check(wanted.isEmpty, "run \(run): nothing wanted while locked") }
        if let h = mac.holder { check(mac.offers[h] != nil, "run \(run): the holder has an offer") }
        if let p = mac.playing { check(wanted.contains(p.session) && p.key == mac.holder, "run \(run): the playout plays only the wanted session") }
        for (id, s) in mac.sessions where !s.paired || s.key == nil {
            check(mac.state(of: id, at: now).map { [S.off, S.notReady, S.unpaired].contains($0.state) } ?? true, "run \(run): an unpaired session never hears idle or inUse")
        }
    }
    // Quiet: one device on, in front, paired, alone with an available Mac an app uses: it records.
    if run % 10 == 0 {
        var m = H(); ready(&m); _ = m.handle(.appChanged(true), at: 0)
        _ = m.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
        var d = P.Device(); d.connected = true; d.list = m.advertised; d.switchOn = true; d.permission = .granted
        var l = P.DeviceLink()
        var owed = true
        for step in 0..<4 {
            d.state = m.state(of: 1, at: Double(step))
            let s = l.step(d, claimOwed: owed)
            if s.claimed { owed = false }
            for msg in s.send { if case .format(let f) = msg { _ = m.handle(.format(1, f), at: Double(step)) } }
        }
        check(P.records(d) && m.wanted(1, at: 4), "run \(run): one device alone records")
    }
}
check(everAnotherAfterClaim, "a takeover always tells the previous holder's session")
print("random sessions: \(coverage.taken) packet messages taken, \(coverage.takeovers) takeovers, \(coverage.moves) moves (\(coverage.movesRecording) while recording), \(coverage.ends) ends (\(coverage.selfHeals) with the switch on), \(coverage.lockedDrops) refused while locked")
check(coverage.taken > 5_000 && coverage.takeovers > 100 && coverage.movesRecording > 100 && coverage.selfHeals > 50 && coverage.lockedDrops > 30,
      "the random sessions reach every part: \(coverage)")
check(runs == 3000, "3,000 random sessions")

print(failures == 0 ? "microphone: all \(checks) checks passed" : "microphone: \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
