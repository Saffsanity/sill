import Foundation

// The Mac's rules for the devices' cameras (CameraHostPolicy, docs/camera-plan.md §6.3), compiled with
// Sources/StreamProtocol as one module (module.txt). Every rule through directed scenarios, then 20,000
// random lives of up to four devices (offers, claims, pauses, stops, moves, leaves, removals, locks, the
// switch, Sill Camera's readiness, an app opening and closing it, frames and failed decodes) against the
// invariants: one holder at most, present and offering; one session wanted at most, the holder's, paired,
// never while the camera is unavailable or unused; a claim always wins; kind 16 said exactly when it
// changes; frames taken only from the wanted session's announced epoch, within the rate; a keyframe asked
// of a device at most once a second.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = CameraHostPolicy
typealias E = CameraHostPolicy.Effect

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

let sets = ParameterSets(nalUnitHeaderLength: 4, sets: [Data([0x40, 1]), Data([0x42, 1]), Data([0x44, 1])]).encoded()
func epochFormat(_ e: Int, w: Int = 1280, h: Int = 720) -> CameraFormat {
    CameraFormat(position: "front", codec: CameraCodec.hevc, width: w, height: h, fps: 30, epoch: e, parameterSets: sets)
}
let offer = CameraFormat(position: "front")
let claim = CameraFormat(position: "front", claim: true)
let stop = CameraFormat(stop: true)
let faceTime = P.AppUse(name: "FaceTime", width: 1280, height: 720, fps: 30)

/// A policy driven step by step, keeping every effect.
struct Run {
    var p = P()
    var t: Double = 1000
    var log: [E] = []
    @discardableResult mutating func on(_ e: P.Event, after dt: Double = 0.01) -> [E] {
        t += dt
        let out = p.handle(e, at: t)
        log += out
        return out
    }
    mutating func frame(_ id: Int, epoch: Int, after dt: Double = 0.001) -> Bool {
        t += dt
        let r = p.takesFrame(id, epoch: epoch, at: t)
        log += r.effects
        return r.take
    }
    /// The Mac ready: the switch on, Sill Camera ready, unlocked.
    mutating func ready() { on(.switchChanged(true)); on(.readyChanged(true)); on(.unlockedChanged(true)) }
    mutating func join(_ id: Int, key: String?, paired: Bool = true, name: String? = nil, away: Bool = false, reads: Bool = true) {
        on(.joined(id, key: key, paired: paired, name: name ?? "Device \(id)", away: away, reads: reads))
    }
}
func demands(_ effects: [E]) -> [(Int, CameraDemand)] { effects.compactMap { if case .demand(let i, let d) = $0 { return (i, d) }; return nil } }
func states(_ effects: [E]) -> [(Int, CameraState?)] { effects.compactMap { if case .state(let i, let s) = $0 { return (i, s) }; return nil } }
func lines(_ effects: [E]) -> [String] { effects.compactMap { if case .line(let l) = $0 { return l }; return nil } }
func counts(_ effects: [E]) -> [String] { effects.compactMap { if case .count(let c) = $0 { return c }; return nil } }
func lastFeed(_ effects: [E]) -> P.Feed? { effects.compactMap { if case .feed(let f) = $0 { return f }; return nil }.last }

// MARK: - The constants

check(P.grace == 10, "a move or a return within 10 s keeps the camera")
check(P.maxFormatsPerSecond == 10 && P.maxFramesPerSecond == 60, "10 formats and 60 frames a second per session")
check(P.keyframeSpacing == 1 && P.refusalLineSpacing == 60, "a keyframe a second at most; a refusal's line a minute")
check(P.awayMaxWidth == 1280 && P.awayMaxHeight == 720 && P.awayMaxBitrate == 1_200_000, "away: 1280×720 and 1.2 Mbit/s at most")
check(P.homeBitrate(width: 1280, height: 720, fps: 30) == 2_500_000, "1280×720 at 30 fps: 2.5 Mbit/s")
check(P.homeBitrate(width: 1920, height: 1080, fps: 30) == 4_000_000, "1920×1080 at 30 fps: 4 Mbit/s")
check(P.homeBitrate(width: 1280, height: 720, fps: 15) == 1_250_000, "half the rate, half the bitrate")
check(P.homeBitrate(width: 640, height: 360, fps: 30) == 625_000, "a quarter of the pixels, a quarter")
check(P.homeBitrate(width: 160, height: 90, fps: 5) == 300_000 && P.homeBitrate(width: 1920, height: 1920, fps: 30) == 4_000_000,
      "never under 300 kbit/s nor over 4 Mbit/s")

// MARK: - Who may: the switch, readiness, the lock, pairing

do {
    var r = Run()
    r.join(1, key: "A")
    check(r.p.state(of: 1) == nil && r.p.feed == .unavailable, "before the first reading (locked until read): no camera listed, nothing shown")
    r.on(.unlockedChanged(true))
    check(r.p.state(of: 1) == CameraState(state: CameraState.off), "the switch off: off")
    r.on(.switchChanged(true))
    check(r.p.state(of: 1) == CameraState(state: CameraState.notReady), "the switch on, Sill Camera not ready: notReady")
    r.on(.readyChanged(true))
    check(r.p.state(of: 1) == CameraState(state: CameraState.idle) && r.p.feed == .waiting, "ready: idle, Sill Camera waits for a device")
    check(r.p.available, "available: the switch, readiness, unlocked")
    r.join(2, key: "B", paired: false, name: "Stranger")
    check(r.p.state(of: 2) == CameraState(state: CameraState.unpaired), "an unpaired session: unpaired")
    let refused = r.on(.format(2, claim))
    check(r.p.holder == nil && r.p.offers.isEmpty, "an unpaired session's claim takes nothing")
    check(counts(refused) == ["cam.refused.unpaired"] && lines(refused) == ["Camera: refused from Stranger: not paired."], "counted and said: \(refused)")
    let again = r.on(.format(2, claim), after: 30)
    check(counts(again) == ["cam.refused.unpaired"] && lines(again).isEmpty, "said once a minute at most")
    check(lines(r.on(.format(2, claim), after: 31)).count == 1, "and again after a minute")
    check(r.frame(2, epoch: 1) == false && counts(r.log).last == "cam.refused.unpaired", "its frames dropped")
    r.join(3, key: nil, paired: false)
    check(r.p.state(of: 3) == CameraState(state: CameraState.unpaired), "a plain door's session (no key): unpaired")
    r.on(.paired(2, true))
    check(r.p.state(of: 2) == CameraState(state: CameraState.idle), "paired during its session: idle, its offer taken from now")
    r.on(.format(2, offer))
    check(r.p.holder == "B", "and its offer counts")
}

// MARK: - One device: offer, an app, the demand, the epoch, frames

do {
    var r = Run()
    r.ready()
    r.join(1, key: "A", name: "iPad (iPad14,1)")
    let o = r.on(.format(1, offer))
    check(r.p.holder == "A" && lines(o) == ["Camera: iPad (iPad14,1) offers its front camera."], "an offer with nobody holding: the holder, said once: \(lines(o))")
    check(r.p.state(of: 1) == CameraState(state: CameraState.idle) && demands(o).isEmpty, "no app yet: idle, no demand")
    check(r.p.feed == .device(name: "iPad (iPad14,1)", pause: nil), "Sill Camera shows the holder's name")
    let a = r.on(.appChanged(faceTime))
    check(states(a).count == 1 && states(a)[0].1 == CameraState(state: CameraState.inUse, app: "FaceTime"), "an app: inUse, its name")
    let d = demands(a)
    check(d.count == 1 && d[0].0 == 1 && d[0].1 == CameraDemand(width: 1280, height: 720, fps: 30, keyframe: true, maxBitrate: 2_500_000, token: 1),
          "the demand: the app's size and rate, the ceiling, a keyframe, token 1: \(d)")
    let si = a.firstIndex { if case .state = $0 { return true }; return false }!
    let di = a.firstIndex { if case .demand = $0 { return true }; return false }!
    check(si < di, "kind 16 says inUse before the demand goes")
    check(!a.contains { if case .decoder = $0 { return true }; return false }, "no decoder before an epoch")
    check(r.frame(1, epoch: 3) == false && counts(r.log).last == "cam.dropped.epoch", "a frame before its epoch's format: dropped")
    let e = r.on(.format(1, epochFormat(3)))
    check(e.contains(.decoder(session: 1, epochFormat(3))), "the epoch: the decoder made for it")
    check(r.frame(1, epoch: 3), "a frame of it: taken")
    check(!r.frame(1, epoch: 2), "a frame of another epoch: dropped")
    let e4 = r.on(.format(1, epochFormat(4, w: 720, h: 1280)))
    check(e4.contains(.decoder(session: 1, epochFormat(4, w: 720, h: 1280))) && r.frame(1, epoch: 4) && !r.frame(1, epoch: 3),
          "a new epoch (the phone turned upright): a new decoder, the old epoch's frames dropped")
    check(demands(r.on(.tick, after: 5)).isEmpty, "nothing said again while nothing changes")
    let bigger = r.on(.appChanged(P.AppUse(name: "FaceTime", width: 1920, height: 1080, fps: 30)))
    check(demands(bigger).map(\.1) == [CameraDemand(width: 1920, height: 1080, fps: 30, maxBitrate: 4_000_000, token: 2)],
          "the app's size changes: a new demand, no keyframe (a new epoch starts with one)")
    let gone = r.on(.appChanged(nil))
    check(states(gone).map(\.1) == [CameraState(state: CameraState.idle)] && gone.contains(.noDecoder) && demands(gone).isEmpty,
          "the app closes Sill Camera: idle, no decoder")
    check(!r.frame(1, epoch: 4) && counts(r.log).last == "cam.dropped.notWanted", "its frames dropped")
    r.on(.appChanged(faceTime))
    check(!r.frame(1, epoch: 4), "wanted again: the old epoch is not taken (its next frames come of a new one)")
    r.on(.format(1, epochFormat(5)))
    check(r.frame(1, epoch: 5), "the new epoch is")
}

// MARK: - Pauses, stops, two devices, claims

do {
    var r = Run()
    r.ready()
    r.on(.appChanged(faceTime))
    r.join(1, key: "A", name: "iPad")
    r.join(2, key: "B", name: "iPhone")
    r.on(.format(1, offer))
    r.on(.format(1, epochFormat(1)))
    check(r.p.wanted(1) && !r.p.wanted(2), "A offered first: A is wanted")
    let p = r.on(.format(1, CameraFormat(position: "front", pause: CameraFormat.background)))
    check(lines(p) == ["Camera: iPad paused its camera (background)."] && r.p.feed == .device(name: "iPad", pause: "background"),
          "a pause: said, and Sill Camera shows it: \(lines(p))")
    check(r.p.wanted(1), "a pause keeps the camera wanted (the device comes back to it)")
    check(lines(r.on(.format(1, CameraFormat(position: "front", pause: CameraFormat.background)))).isEmpty, "the same pause: said once")
    r.on(.format(1, CameraFormat(position: "front")))
    check(r.p.feed == .device(name: "iPad", pause: nil), "the pause over")
    let o2 = r.on(.format(2, offer))
    check(r.p.holder == "A" && r.p.state(of: 2) == CameraState(state: CameraState.another, holder: "iPad"),
          "an offer without a claim takes nothing from a holder: B hears another, iPad")
    check(lines(o2) == ["Camera: iPhone offers its front camera."], "said")
    let c = r.on(.format(2, claim))
    check(r.p.holder == "B" && lines(c).contains("Camera: iPhone took Sill Camera from iPad."), "a claim takes it: \(lines(c))")
    check(r.p.state(of: 1) == CameraState(state: CameraState.another, holder: "iPhone")
          && r.p.state(of: 2) == CameraState(state: CameraState.inUse, app: "FaceTime"), "A hears another, B is in use")
    check(demands(c).map(\.0) == [2] && demands(c)[0].1.keyframe == true, "B is asked, with a keyframe")
    check(c.contains(.noDecoder) && !r.frame(1, epoch: 1), "A's epoch no longer decodes; A's frames dropped")
    r.on(.format(2, epochFormat(9)))
    check(r.frame(2, epoch: 9), "B's frames taken")
    // A claims back: the last one turned on is the camera.
    r.on(.format(1, claim), after: 1)
    check(r.p.holder == "A", "A turned on again: A")
    // A stops: B, the other standing offer, takes it.
    let s = r.on(.format(1, stop))
    check(r.p.holder == "B" && lines(s).contains("Camera: iPad stopped sharing its camera.") && lines(s).contains("Camera: iPhone is Sill Camera now."),
          "A's stop: B takes it: \(lines(s))")
    check(r.p.offers["A"] == nil && r.p.state(of: 1) == CameraState(state: CameraState.another, holder: "iPhone"), "A's offer gone; A hears another")
    check(demands(s).map(\.0) == [2] && demands(s)[0].1.keyframe == true, "B asked again with a keyframe")
}
do {
    // With three: the most recent standing offer takes a freed camera.
    var r = Run()
    r.ready()
    r.on(.appChanged(faceTime))
    r.join(1, key: "A"); r.join(2, key: "B"); r.join(3, key: "C")
    r.on(.format(1, claim), after: 1)
    r.on(.format(2, claim), after: 1)
    r.on(.format(3, claim), after: 1)
    check(r.p.holder == "C", "the last claim wins")
    r.on(.format(3, stop))
    check(r.p.holder == "B", "C stops: B, turned on after A, takes it")
    r.on(.format(1, CameraFormat(position: "back", pause: CameraFormat.thermal)), after: 1)
    r.on(.format(2, stop))
    check(r.p.holder == "A", "B stops: A, whose offer was only said again (no claim), takes it")
}

// MARK: - Moves, leaves, removals: the grace

do {
    var r = Run()
    r.ready()
    r.on(.appChanged(faceTime))
    r.join(1, key: "A", name: "iPad")
    r.join(2, key: "B", name: "iPhone")
    r.on(.format(1, offer)); r.on(.format(1, epochFormat(1)))
    r.on(.format(2, offer))
    // A move: the cable plugged in, a new connection with the same key.
    r.join(3, key: "A", name: "iPad")
    let left = r.on(.left(1), after: 0.2)
    check(r.p.holder == "A" && !r.p.wanted(3), "the old connection gone: A keeps the camera, its new one not wanted before it offers")
    check(left.contains(.noDecoder), "nothing decodes meanwhile")
    let back = r.on(.format(3, offer), after: 0.5)
    check(r.p.holder == "A" && r.p.wanted(3) && demands(back).map(\.0) == [3] && demands(back)[0].1.keyframe == true,
          "the new one offers: wanted, asked with a keyframe")
    r.on(.format(3, epochFormat(2)))
    check(r.frame(3, epoch: 2), "its frames taken")
    // A leaves for good: after the grace, B takes it.
    r.on(.left(3), after: 1)
    r.on(.tick, after: P.grace - 0.5)
    check(r.p.holder == "A", "within the grace the camera waits for A")
    check(r.p.state(of: 2) == CameraState(state: CameraState.another, holder: "iPad"), "B still hears another, iPad (from its offer)")
    let expired = r.on(.tick, after: 1)
    check(r.p.holder == "B" && lines(expired).contains("Camera: iPad is gone; Sill Camera is free.") && lines(expired).contains("Camera: iPhone is Sill Camera now."),
          "after it, B: \(lines(expired))")
    // A removal frees it at once.
    r.join(4, key: "A", name: "iPad")
    r.on(.format(4, claim))
    check(r.p.holder == "A", "A back and turned on again")
    let removed = r.on(.removed(key: "A"))
    check(r.p.holder == "B" && r.p.offers["A"] == nil && lines(removed).first == "Camera: iPad was removed; Sill Camera is free.",
          "A removed: B at once: \(lines(removed))")
    check(r.p.state(of: 4) == CameraState(state: CameraState.unpaired) && !r.frame(4, epoch: 2), "A's session: unpaired, its frames dropped")
}

// MARK: - The lock

do {
    var r = Run()
    r.ready()
    r.on(.appChanged(faceTime))
    r.join(1, key: "A", name: "iPad")
    r.on(.format(1, offer)); r.on(.format(1, epochFormat(1)))
    let locked = r.on(.unlockedChanged(false))
    check(r.p.state(of: 1) == nil && states(locked).map(\.1) == [nil], "locked: kind 16 has no camera (the list has none)")
    check(r.p.feed == .unavailable && locked.contains(.noDecoder) && !r.p.wanted(1), "nothing wanted, nothing shown, no decoder")
    check(!r.frame(1, epoch: 1) && counts(r.log).last == "cam.refused.locked", "a frame at a locked screen: refused")
    check(lines(r.log).filter { $0.hasPrefix("Camera: dropped while") }.count == 1, "said once a minute")
    r.on(.format(1, offer))
    check(counts(r.log).last == "cam.refused.locked", "an offer too")
    check(r.p.holder == "A", "the holder kept through the lock")
    r.on(.tick, after: 600)
    check(r.p.holder == "A", "however long it lasts")
    let unlocked = r.on(.unlockedChanged(true))
    check(r.p.wanted(1) && demands(unlocked).first?.1.keyframe == true, "unlocked: wanted again at once, with a keyframe")
    check(!r.frame(1, epoch: 1), "the epoch from before the lock is not taken")
    r.on(.format(1, offer), after: 2)
    r.on(.tick, after: P.grace)
    check(r.p.holder == "A", "said again within the grace: kept")
    // Locked again; this time A says nothing after the unlock (its switch went off meanwhile, say).
    r.on(.unlockedChanged(false))
    r.on(.unlockedChanged(true), after: 60)
    r.on(.tick, after: P.grace + 0.1)
    check(r.p.holder == nil && r.p.feed == .waiting, "no word from A within the grace after the unlock: free")
}

// MARK: - Rates, keyframes, away, a device that reads no type 3

do {
    var r = Run()
    r.ready()
    r.on(.appChanged(faceTime))
    r.join(1, key: "A")
    r.on(.format(1, offer)); r.on(.format(1, epochFormat(1)))
    r.t = (r.t + 10).rounded(.up)
    var taken = 0
    for _ in 0..<70 { if r.frame(1, epoch: 1, after: 0.001) { taken += 1 } }
    check(taken == 60, "60 frames a second taken, the rest dropped: \(taken)")
    check(counts(r.log).filter { $0 == "cam.dropped.rate" }.count == 10, "counted")
    r.t += 1
    check(r.frame(1, epoch: 1), "the next second takes again")
    var formats = 0
    for _ in 0..<12 { if counts(r.on(.format(1, epochFormat(2)), after: 0.001)).isEmpty { formats += 1 } }
    check(formats == 10, "10 formats a second, the rest dropped: \(formats)")
    r.t += 5
    let k1 = r.on(.decodeFailed(1))
    check(demands(k1).count == 1 && demands(k1)[0].1.keyframe == true && counts(k1) == ["cam.keyframeAsked"], "a failed decode: a keyframe asked")
    check(demands(r.on(.decodeFailed(1), after: 0.5)).isEmpty, "again within a second: not asked")
    check(demands(r.on(.decodeFailed(1), after: 0.6)).count == 1, "after it: asked")
    r.join(2, key: "B", away: true, reads: true)
    r.join(3, key: "C", reads: false)
    r.on(.appChanged(P.AppUse(name: "Zoom", width: 1920, height: 1080, fps: 30)))
    let away = r.on(.format(2, claim))
    check(demands(away).map(\.1) == [CameraDemand(width: 1280, height: 720, fps: 30, keyframe: true, maxBitrate: 1_200_000, token: 5)],
          "away: 1280×720 and 1.2 Mbit/s at most: \(demands(away))")
    let silent = r.on(.format(3, claim))
    check(r.p.wanted(3) && demands(silent).isEmpty, "a device whose hello reads no type 3 is never sent one")
    var narrow = Run()
    narrow.ready()
    narrow.on(.appChanged(P.AppUse(name: nil, width: 1080, height: 1920, fps: 60)))
    narrow.join(1, key: "A", away: true)
    let d = demands(narrow.on(.format(1, offer)))
    check(d.first?.1.width == 404 && d.first?.1.height == 720 && d.first?.1.fps == 30, "an upright app away: fitted into 1280×720, even, its rate at most 30: \(d)")
    check(narrow.p.state(of: 1) == CameraState(state: CameraState.inUse), "an app Sill Camera cannot name: inUse without a name")
}

// MARK: - The switch and readiness while in use

do {
    var r = Run()
    r.ready()
    r.on(.appChanged(faceTime))
    r.join(1, key: "A")
    r.on(.format(1, offer)); r.on(.format(1, epochFormat(1)))
    let off = r.on(.switchChanged(false))
    check(r.p.state(of: 1) == CameraState(state: CameraState.off) && off.contains(.noDecoder) && r.p.feed == .unavailable,
          "the switch off: off, no decoder, nothing shown")
    check(lines(off) == ["Camera: Use iPhone and iPad cameras off."], "said: \(lines(off))")
    check(!r.frame(1, epoch: 1) && counts(r.log).last == "cam.refused.off", "frames refused")
    let on = r.on(.switchChanged(true))
    check(r.p.wanted(1) && demands(on).first?.1.keyframe == true, "on again: wanted, a keyframe asked")
    r.on(.readyChanged(false))
    check(r.p.state(of: 1) == CameraState(state: CameraState.notReady) && !r.p.wanted(1), "Sill Camera gone: notReady")
}

// MARK: - 20,000 random lives

var rand = Rand(state: 0x5111_CA3E_0046_2026)
var lives = 0, wantedSeen = 0, takenSeen = 0, claimsSeen = 0, holdersFreed = 0
outer: for life in 0..<20_000 {
    var r = Run()
    r.t = Double(rand.int(0...100_000))
    // Most lives start with the camera available, and many with an app using it; the events change both.
    if rand.chance(0.85) { r.ready() }
    if rand.chance(0.6) { r.on(.appChanged(faceTime)) }
    let devices = rand.int(1...4)
    let keys = (0..<devices).map { "K\($0)" }
    var paired = keys.map { _ in rand.chance(0.85) }
    var next = 1
    var connections: [Int: Int] = [:]          // session → device
    var epochs: [Int: Int] = [:]               // session → its last announced epoch
    var sent: [Int: CameraState?] = [:]        // kind 16 as the receiver would keep it
    var lastKeyframe: [String: Double] = [:]   // when each device was last asked for a keyframe
    func apply(_ effects: [E], _ r: Run) {
        for e in effects {
            switch e {
            case .state(let id, let s): sent[id] = s
            case .demand(let id, let d):
                if d.keyframe == true, let dev = connections[id] { lastKeyframe[keys[dev]] = r.t }
            default: break
            }
        }
    }
    for _ in 0..<rand.int(10...60) {
        let roll = rand.int(0...99)
        var effects: [E] = []
        var claimed: (session: Int, key: String)?
        switch roll {
        case 0..<12:   // a device connects (a move, if it has a session already)
            let dev = rand.int(0...devices - 1)
            let id = next; next += 1
            connections[id] = dev
            effects = r.on(.joined(id, key: keys[dev], paired: paired[dev], name: "D\(dev)", away: rand.chance(0.2), reads: rand.chance(0.95)),
                           after: Double(rand.int(0...3000)) / 1000)
        case 12..<20:  // a session leaves
            guard let id = connections.keys.sorted().randomElement(using: &rand) else { continue }
            connections[id] = nil; epochs[id] = nil; sent[id] = nil
            effects = r.on(.left(id), after: Double(rand.int(0...3000)) / 1000)
        case 20..<45:  // a type 1: an offer, a claim, a pause, a stop or an epoch
            guard let id = connections.keys.sorted().randomElement(using: &rand) else { continue }
            let f: CameraFormat
            switch rand.int(0...9) {
            case 0, 1: f = claim; claimed = (id, keys[connections[id]!])
            case 2, 3: f = offer
            case 4: f = stop
            case 5: f = CameraFormat(position: "back", pause: CameraFormat.pauses.randomElement(using: &rand))
            default:
                let e = rand.int(0...65_535)
                f = epochFormat(e)
            }
            effects = r.on(.format(id, f), after: Double(rand.int(0...500)) / 1000)
            if f.isEpoch, r.p.refusal(id) == nil, !counts(effects).contains("cam.dropped.rate") { epochs[id] = f.epoch }
            if f.stop == true { epochs[id] = nil }
        case 45..<70:  // frames
            guard let id = connections.keys.sorted().randomElement(using: &rand) else { continue }
            for _ in 0..<rand.int(1...20) {
                let epoch = rand.chance(0.8) ? (epochs[id] ?? 0) : rand.int(0...65_535)
                let wantedBefore = r.p.wanted(id)
                let announced = r.p.sessions[id]?.epoch?.epoch
                let took = r.frame(id, epoch: epoch, after: Double(rand.int(0...40)) / 1000)
                if took {
                    takenSeen += 1
                    if !(wantedBefore && announced == epoch) {
                        check(false, "life \(life): a frame of epoch \(epoch) taken from session \(id), wanted \(wantedBefore), announced \(announced.map { "\($0)" } ?? "none")")
                        break outer
                    }
                }
            }
        case 70..<74:   // a frame that did not decode: a keyframe asked of that device at most once a second
            guard let id = connections.keys.sorted().randomElement(using: &rand) else { continue }
            let before = lastKeyframe[keys[connections[id]!]]
            effects = r.on(.decodeFailed(id), after: Double(rand.int(0...1500)) / 1000)
            if demands(effects).contains(where: { $0.1.keyframe == true }), let before, r.t - before < P.keyframeSpacing - 1e-9 {
                check(false, "life \(life): a keyframe asked of a device \(r.t - before) s after the last"); break outer
            }
        case 74..<79:
            let dev = rand.int(0...devices - 1)
            paired[dev] = false
            for id in connections.keys.sorted() where connections[id] == dev { effects += r.on(.paired(id, false)) }
            effects += r.on(.removed(key: keys[dev]))
        case 79..<81:
            let dev = rand.int(0...devices - 1)
            paired[dev] = true
            for id in connections.keys.sorted() where connections[id] == dev { effects += r.on(.paired(id, true)) }
        case 81..<85: effects = r.on(.unlockedChanged(rand.chance(0.6)), after: Double(rand.int(0...20_000)) / 1000)
        case 85..<87: effects = r.on(.switchChanged(rand.chance(0.7)))
        case 87..<89: effects = r.on(.readyChanged(rand.chance(0.8)))
        case 89..<95:
            effects = r.on(.appChanged(rand.chance(0.7) ? P.AppUse(name: ["FaceTime", "Zoom", nil].randomElement(using: &rand)!,
                                                                    width: [640, 1280, 1920].randomElement(using: &rand)!,
                                                                    height: [360, 720, 1080].randomElement(using: &rand)!, fps: [15, 30].randomElement(using: &rand)!) : nil))
        default: effects = r.on(.tick, after: Double(rand.int(0...15_000)) / 1000)
        }
        apply(effects, r)
        // The invariants, after every step.
        let p = r.p
        if let h = p.holder, p.offers[h] == nil { check(false, "life \(life): a holder \(h) without an offer"); break outer }
        let wantedNow = p.sessions.keys.filter { p.wanted($0) }
        if wantedNow.count > 1 { check(false, "life \(life): \(wantedNow.count) sessions wanted at once"); break outer }
        if let w = wantedNow.first {
            wantedSeen += 1
            let s = p.sessions[w]!
            if !(p.available && p.app != nil && s.key == p.holder && s.paired) {
                check(false, "life \(life): session \(w) wanted while available \(p.available), app \(p.app != nil), holder \(p.holder ?? "none"), paired \(s.paired)")
                break outer
            }
        }
        if !p.available, p.feed != .unavailable { check(false, "life \(life): the camera unavailable but Sill Camera shows \(p.feed)"); break outer }
        if let c = claimed, p.refusal(c.session) == nil, !counts(effects).contains("cam.dropped.rate") {
            claimsSeen += 1
            if p.holder != c.key { check(false, "life \(life): a claim from \(c.key) did not take the camera (holder \(p.holder ?? "none"))"); break outer }
        }
        for id in connections.keys where (sent[id] ?? nil) != p.state(of: id) {
            check(false, "life \(life): session \(id)'s kind 16 says \(String(describing: sent[id] ?? nil)), the rule \(String(describing: p.state(of: id)))")
            break outer
        }
        if p.holder == nil, p.available, p.offers.values.contains(where: { $0.session != nil && $0.leftAt == nil && p.stands($0, at: r.t) }) {
            check(false, "life \(life): a free camera with a standing offer from a session still here"); break outer
        }
    }
    if r.log.contains(where: { if case .line(let l) = $0 { return l.hasSuffix("is free.") }; return false }) { holdersFreed += 1 }
    lives += 1
}
check(lives == 20_000, "every life ran to its end (\(lives))")
check(wantedSeen > 20_000 && takenSeen > 20_000 && claimsSeen > 5_000 && holdersFreed > 500,
      "the lives reached every part: \(wantedSeen) steps with a session wanted, \(takenSeen) frames taken, \(claimsSeen) claims, \(holdersFreed) lives freed a holder")

print("lives: \(wantedSeen) steps with a session wanted, \(takenSeen) frames taken, \(claimsSeen) claims, \(holdersFreed) lives freed a holder")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
