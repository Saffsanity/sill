// PictureInPicturePolicy (iOSClient/PictureInPicturePolicy.swift): when Sill lets iOS take a window's
// picture into Picture in Picture as the person leaves, what counts as watched, heard and running while
// it shows, the pause, and what ends it (issue #291, docs/picture-in-picture-plan.md). Compiled on its own
// with swiftc (run.sh).
//
// What it checks: the default (off) and the paused limit (10 minutes); `qualifies` over all 64 of its
// inputs against the rule written out; `offered` only for the chosen window; `chosen` by cases (one window,
// two in front, one in the background, none in front keeping the last choice, a window that closed), then
// 20,000 random sets of windows against:
//   C1 with a window in front: a window in front whose session qualifies, used no earlier than any other
//      such (a window never used counting as the earliest), the first listed among equals; none when no
//      window in front qualifies;
//   C2 with none in front: the last choice while it is still listed, else none;
//   C3 a window in the background, or one in front that does not qualify, added anywhere, never changes a
//      choice made in front; nor does the order of windows used at different moments;
// then every truth table: watched, heard, running, frozen, only in Picture in Picture (the device's own input,
// its viewports and the Mac's copies wait), `stops` for each ending; `pauseEnds` at its edges; the words; then the Lifecycle by cases (start, pause, play, a pause
// looked at before and at its ten minutes, every ending, a second start, a play or pause while off) and
// 20,000 random lives of one window against:
//   L1 paused only while active, and a pause time exactly while paused;
//   L2 every play or pause while active tells AVKit (invalidate), none while off;
//   L3 the session's end, the window back in front and the device's lock ask for a stop exactly while
//      active; a look at the clock asks for one exactly once a pause has lasted the limit;
//   L4 no pause outlives the limit unasked: a pause past it is stopped at the first look after it, and a
//      pause's own effects say when to look (its start plus the limit);
//   L5 the effects never ask a stop while off, and AVKit's didStop leaves it off and not paused;
//   L6 a willStart while it shows changes and asks nothing, one while off starts it playing and tells AVKit;
//   L7 an ending or a look at the clock only asks (AVKit's didStop is what ends it).
import Foundation

var fails = 0, passes = 0
func check(_ what: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(what)") } else { fails += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check("\(what): \(a)" + (a == b ? "" : " (want \(b))"), a == b) }

typealias P = PictureInPicturePolicy
typealias S = PictureInPicturePolicy.State
typealias W = PictureInPicturePolicy.Window

struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func coin() -> Bool { below(2) == 0 }
}

// MARK: The constants

eq(P.defaultOn, false, "off by default (the plan's open question 1)")
eq(P.pausedLimit, 600, "a pause stops it after 10 minutes, DeviceIdlePolicy.idleLimit's")
eq(S.off, S(active: false, paused: false), "off: not active, not paused")

// MARK: Offered

func session(_ bits: Int) -> P.Session {
    P.Session(switchOn: bits & 1 != 0, supported: bits & 2 != 0, connected: bits & 4 != 0, streaming: bits & 8 != 0,
              pictureCame: bits & 16 != 0, covered: bits & 32 != 0)
}
var qualifyingCount = 0
for bits in 0..<64 {
    let s = session(bits)
    let want = s.switchOn && s.supported && s.connected && s.streaming && s.pictureCame && !s.covered
    if want { qualifyingCount += 1 }
    check("qualifies \(s): \(P.qualifies(s))", P.qualifies(s) == want)
    check("offered when chosen: as it qualifies (\(bits))", P.offered(s, chosen: true) == want)
    check("never offered when not chosen (\(bits))", P.offered(s, chosen: false) == false)
}
eq(qualifyingCount, 1, "exactly one of the 64 qualifies: everything on, no cover")
let all = P.Session(switchOn: true, supported: true, connected: true, streaming: true, pictureCame: true, covered: false)
eq(P.qualifies(all), true, "the switch on, supported, connected, streaming, its picture come, no cover: it qualifies")
var s1 = all; s1.switchOn = false; eq(P.qualifies(s1), false, "the switch off (the default): never")
s1 = all; s1.supported = false; eq(P.qualifies(s1), false, "a device without Picture in Picture: never")
s1 = all; s1.connected = false; eq(P.qualifies(s1), false, "the connect screen: never")
s1 = all; s1.streaming = false; eq(P.qualifies(s1), false, "connected, nothing streaming: never")
s1 = all; s1.pictureCame = false; eq(P.qualifies(s1), false, "streaming, its first picture still to come: not yet")
s1 = all; s1.covered = true; eq(P.qualifies(s1), false, "a locked Mac's cover, another user's, or Unlocking…: not while it shows")

// MARK: Chosen

func w(_ id: Int, front: Bool = true, q: Bool = true, used: Double? = 100) -> W {
    W(id: id, foregroundActive: front, qualifies: q, lastUsedAt: used)
}
eq(P.chosen([], previous: nil), nil, "no window: none")
eq(P.chosen([], previous: 3), nil, "no window, a last choice: none (its window closed)")
eq(P.chosen([w(1)], previous: nil), 1, "one window in front that qualifies: it")
eq(P.chosen([w(1, q: false)], previous: nil), nil, "one window in front that does not qualify: none")
eq(P.chosen([w(1, q: false)], previous: 1), nil, "in front, no longer qualifying: none, whatever was chosen")
eq(P.chosen([w(1, used: 100), w(2, used: 200)], previous: nil), 2, "two in front that qualify: the one used last")
eq(P.chosen([w(1, used: 200), w(2, used: 100)], previous: 2), 1, "in either order, whatever was chosen before")
eq(P.chosen([w(1, used: nil), w(2, used: 5)], previous: nil), 2, "one never used: the one used, however long ago")
eq(P.chosen([w(1, used: 5), w(2, used: nil)], previous: nil), 1, "and listed second")
eq(P.chosen([w(1, used: nil), w(2, used: nil)], previous: nil), 1, "neither used: the first listed")
eq(P.chosen([w(1, used: 100), w(2, used: 100)], previous: 2), 1, "used at the same moment: the first listed")
eq(P.chosen([w(1, used: 100), w(2, q: false, used: 200)], previous: nil), 1, "the one used last does not qualify: the other")
eq(P.chosen([w(1, used: 100), w(2, front: false, used: 200)], previous: 2), 1,
   "the one used last is in the background (a window put away): the one in front")
eq(P.chosen([w(1, front: false, q: false), w(2)], previous: 1), 2, "one in front qualifies: it, not the last choice")
eq(P.chosen([w(1, front: false), w(2, front: false)], previous: 2), 2,
   "none in front (Sill leaving, or away): the last choice stands")
eq(P.chosen([w(1, front: false, used: 900), w(2, front: false, used: 100)], previous: 2), 2,
   "none in front: the last choice, not the one used last")
eq(P.chosen([w(1, front: false, q: false)], previous: 1), 1,
   "none in front: the last choice even once it no longer qualifies (`offered` asks that)")
eq(P.chosen([w(1, front: false), w(2, front: false)], previous: nil), nil, "none in front, no last choice: none")
eq(P.chosen([w(1, front: false)], previous: 7), nil, "none in front, the last choice's window closed: none")

// C1–C3: 20,000 random sets of windows.
var rng = Rng(s: 0x291_0001)
var violations: [String: Int] = [:], firstViolation: [String: String] = [:]
func violated(_ what: String, _ detail: String) { violations[what, default: 0] += 1; if firstViolation[what] == nil { firstViolation[what] = detail } }
var choseInFront = 0, choseNone = 0, keptPrevious = 0
for set in 0..<20_000 {
    let n = rng.below(5)
    let windows: [W] = (0..<n).map { i in
        W(id: i + 1, foregroundActive: rng.below(3) != 0, qualifies: rng.below(3) != 0,
          lastUsedAt: rng.below(6) == 0 ? nil : Double(rng.below(40)))
    }
    let previous: Int? = rng.below(4) == 0 ? nil : 1 + rng.below(n + 1)     // n + 1: a window that closed
    let got = P.chosen(windows, previous: previous)
    let detail = "set \(set): \(windows), previous \(previous.map(String.init) ?? "none") -> \(got.map(String.init) ?? "none")"
    if windows.contains(where: \.foregroundActive) {
        let candidates = windows.filter { $0.foregroundActive && $0.qualifies }
        if candidates.isEmpty {
            if got != nil { violated("C1 a choice when no window in front qualifies", detail) }
            choseNone += 1
        } else {
            guard let id = got, let c = candidates.first(where: { $0.id == id }) else {
                violated("C1 none, or a window that is not in front and qualifying", detail); continue
            }
            let latest = candidates.map { $0.lastUsedAt ?? -.infinity }.max()!
            if (c.lastUsedAt ?? -.infinity) != latest { violated("C1 not the one used last", detail) }
            if let firstLatest = candidates.first(where: { ($0.lastUsedAt ?? -.infinity) == latest }), firstLatest.id != id {
                violated("C1 not the first listed among those used last", detail)
            }
            choseInFront += 1
        }
        // C3: windows that change nothing, added anywhere; the order of windows used at different moments.
        var more = windows
        more.insert(W(id: 90, foregroundActive: false, qualifies: true, lastUsedAt: 1_000), at: rng.below(more.count + 1))
        more.insert(W(id: 91, foregroundActive: true, qualifies: false, lastUsedAt: 1_000), at: rng.below(more.count + 1))
        if P.chosen(more, previous: previous) != got { violated("C3 a window in the background, or not qualifying, changed it", detail) }
        let uses = candidates.map { $0.lastUsedAt ?? -.infinity }
        if Set(uses).count == uses.count, P.chosen(windows.reversed(), previous: previous) != got {
            violated("C3 the order changed a choice between windows used at different moments", detail)
        }
    } else {
        let want = previous.flatMap { p in windows.contains(where: { $0.id == p }) ? p : nil }
        if got != want { violated("C2 none in front: not the last choice while it is listed", detail) }
        if got != nil { keptPrevious += 1 } else { choseNone += 1 }
    }
}
for (what, n) in violations.sorted(by: { $0.key < $1.key }) { check("\(what): \(n) times; first: \(firstViolation[what] ?? "")", false) }
check("20,000 random sets of windows (\(choseInFront) chosen in front, \(keptPrevious) kept while away, \(choseNone) none): C1–C3",
      violations.isEmpty && choseInFront > 5_000 && keptPrevious > 400 && choseNone > 2_000)

// MARK: While it shows: the truth tables

let states: [S] = [S(active: false, paused: false), S(active: false, paused: true), S(active: true, paused: false), S(active: true, paused: true)]
for pip in states {
    let plays = pip.active && !pip.paused
    for front in [false, true] {
        check("watched, the scene \(front ? "in front" : "not in front"), \(pip): \(P.pictureWatched(sceneForegroundActive: front, pip: pip))",
              P.pictureWatched(sceneForegroundActive: front, pip: pip) == (front || plays))
        check("only in Picture in Picture (the device's own input, viewports and the Mac's copies wait), the scene \(front ? "in front" : "not in front"), \(pip)",
              P.onlyInPictureInPicture(sceneForegroundActive: front, pip: pip) == (pip.active && !front))
        check("running, the app \(front ? "in the foreground" : "in the background"), \(pip)",
              P.running(appForeground: front, pip: pip) == (front || pip.active))
        for scene in [false, true] {
            check("heard, the app \(front ? "in front" : "away"), the scene \(scene ? "in front" : "away"), \(pip)",
                  P.soundHeard(appForeground: front, sceneForeground: scene, pip: pip) == ((front && scene) || plays))
        }
    }
    check("frozen \(pip): \(P.frozen(pip))", P.frozen(pip) == (pip.active && pip.paused))
    eq(P.stops(.sessionEnded, pip: pip), pip.active, "the session's end stops it exactly while active, \(pip)")
    eq(P.stops(.backInFront, pip: pip), pip.active, "the window back in front stops it exactly while active, \(pip)")
    eq(P.stops(.deviceLocked, pip: pip), pip.active, "the device's lock stops it exactly while active, \(pip)")
    eq(P.stops(.pausedTooLong, pip: pip), pip.active && pip.paused, "ten minutes paused stops it exactly while paused, \(pip)")
}
let playing = S(active: true, paused: false), paused = S(active: true, paused: true)
eq(P.pictureWatched(sceneForegroundActive: false, pip: playing), true, "Sill away, Picture in Picture playing: watched (keyframes asked for)")
eq(P.pictureWatched(sceneForegroundActive: false, pip: paused), false, "paused: not watched (the frozen picture needs nothing)")
eq(P.pictureWatched(sceneForegroundActive: false, pip: .off), false, "Sill away without it: not watched, as before")
eq(P.soundHeard(appForeground: false, sceneForeground: false, pip: playing), true, "Sill away, Picture in Picture playing: heard")
eq(P.soundHeard(appForeground: false, sceneForeground: false, pip: paused), false, "paused: silent")
eq(P.soundHeard(appForeground: true, sceneForeground: false, pip: .off), false, "this window's scene away, another in front: silent, as before")
eq(P.running(appForeground: false, pip: paused), true, "paused: still running (iOS keeps the app while it shows)")
eq(P.running(appForeground: false, pip: .off), false, "away without it: not running, as before")
eq(P.onlyInPictureInPicture(sceneForegroundActive: true, pip: playing), false, "back in front, before it stops: the person is at Sill")
eq(P.onlyInPictureInPicture(sceneForegroundActive: false, pip: paused), true, "away, paused: still only there (nothing of the device's own goes)")
eq(P.onlyInPictureInPicture(sceneForegroundActive: false, pip: .off), false, "away without it: as before (Sill is suspended there)")

// pauseEnds at its edges.
eq(P.pauseEnds(pip: paused, pausedAt: 100, now: 100), false, "paused just now: not yet")
eq(P.pauseEnds(pip: paused, pausedAt: 100, now: 699.9), false, "9 min 59.9 s paused: not yet")
eq(P.pauseEnds(pip: paused, pausedAt: 100, now: 700), true, "exactly 10 minutes paused: it ends")
eq(P.pauseEnds(pip: paused, pausedAt: 100, now: 5_000), true, "an hour paused: it ends")
eq(P.pauseEnds(pip: playing, pausedAt: 100, now: 5_000), false, "playing again: never")
eq(P.pauseEnds(pip: .off, pausedAt: 100, now: 5_000), false, "off: never")
eq(P.pauseEnds(pip: S(active: false, paused: true), pausedAt: 100, now: 5_000), false, "a pause flag without Picture in Picture: never")
eq(P.pauseEnds(pip: paused, pausedAt: nil, now: 5_000), false, "no pause time: never")
eq(P.pauseEnds(pip: paused, pausedAt: 700, now: 100), false, "a clock gone back: never")

// MARK: The words

let footnote = P.Copy.footnote(mac: "Mac mini")
eq(P.Copy.title, "Picture in Picture", "the switch's title, iOS's own name for it")
check("the footnote names the Mac: \(footnote)", footnote.hasPrefix("Leave Sill while Mac mini’s picture shows"))
check("the footnote says the sound comes with Send Audio", footnote.contains("with its sound when Send Audio is on"))
check("the footnote says nothing goes to the Mac from it", footnote.contains("only shows the picture"))
check("the footnote names iOS's own switch and where it is",
      footnote.contains("Start PiP Automatically") && footnote.contains("Settings › General › Picture in Picture"))
check("the footnote has no straight apostrophe", !footnote.contains("'"))

// MARK: The Lifecycle by cases

typealias L = PictureInPicturePolicy.Lifecycle
typealias E = PictureInPicturePolicy.Lifecycle.Effects
do {
    var l = L()
    eq(l.state, .off, "a new window: off")
    eq(l.setPlaying(false, now: 5), .none, "a pause while off: nothing (AVKit asks nothing then)")
    eq(l.state, .off, "and still off")
    eq(l.tick(now: 10_000), .none, "a look while off: nothing")
    eq(l.ending(.sessionEnded), .none, "the session's end while off: no stop")
    eq(l.willStart(), E(invalidate: true), "willStart: AVKit told it plays")
    eq(l.state, playing, "plays")
    eq(l.pausedAt, nil, "no pause time")
    eq(l.willStart(), .none, "a second willStart: nothing more")
    eq(l.setPlaying(false, now: 100), E(invalidate: true, lookAt: 700), "the pause: AVKit told, looked at again at 10 minutes")
    eq(l.state, paused, "paused")
    eq(l.pausedAt, 100, "since 100")
    eq(l.setPlaying(false, now: 200), E(invalidate: true, lookAt: 700), "a second pause keeps the first's time")
    eq(l.tick(now: 699), E(lookAt: 700), "at 9 min 59 s: looked at again at 10 minutes")
    eq(l.tick(now: 700), E(stop: true), "at 10 minutes: stopped")
    eq(l.setPlaying(true, now: 701), E(invalidate: true), "a play before AVKit's didStop: AVKit told")
    eq(l.state, playing, "plays again")
    eq(l.pausedAt, nil, "its pause forgotten")
    eq(l.tick(now: 10_000), .none, "playing: a look asks nothing")
    eq(l.ending(.backInFront), E(stop: true), "the window back in front: stopped")
    eq(l.ended(), .none, "AVKit's didStop")
    eq(l.state, .off, "off")
    eq(l.ending(.backInFront), .none, "back in front again, already off: nothing")
}
do {
    var l = L(); _ = l.willStart(); _ = l.setPlaying(false, now: 50)
    eq(l.willStart(), .none, "a willStart while paused: nothing")
    eq(l.state, paused, "still paused")
    eq(l.pausedAt, 50, "since 50")
    eq(l.ending(.sessionEnded), E(stop: true), "paused, the session ends: stopped")
    eq(l.ending(.deviceLocked), E(stop: true), "paused, the device locks: stopped")
    eq(l.ending(.pausedTooLong), E(stop: true), "paused: the pause's ending stops it")
    _ = l.ended()
    eq(l.pausedAt, nil, "didStop forgets the pause")
    eq(l.tick(now: 10_000), .none, "and no look is owed")
}
do {
    var l = L(); _ = l.willStart()
    eq(l.ending(.deviceLocked), E(stop: true), "playing, the device locks: stopped")
    eq(l.ending(.pausedTooLong), .none, "playing: the pause's ending stops nothing")
    eq(l.setPlaying(true, now: 3), E(invalidate: true), "a play while playing: AVKit told, nothing else")
}

// MARK: L1–L7: 20,000 random lives of one window

var rngLife = Rng(s: 0x291_0002)
var lifeViolations: [String: Int] = [:], lifeFirst: [String: String] = [:]
func lifeViolated(_ what: String, _ detail: String) { lifeViolations[what, default: 0] += 1; if lifeFirst[what] == nil { lifeFirst[what] = detail } }
var starts = 0, pauses = 0, pauseStops = 0, endingStops = 0
for life in 0..<20_000 {
    var l = L()
    var t = 0.0
    var log: [String] = []
    for _ in 0..<(1 + rngLife.below(40)) {
        t += rngLife.below(4) == 0 ? rngLife.unit() * 1_500 : rngLife.unit() * 30
        let before = l
        let event = rngLife.below(9)
        let effects: E
        switch event {
        case 0: effects = l.willStart(); log.append("start@\(Int(t))"); if !before.state.active { starts += 1 }
        case 1: effects = l.ended(); log.append("didStop@\(Int(t))")
        case 2, 3: let play = rngLife.coin(); effects = l.setPlaying(play, now: t); log.append("\(play ? "play" : "pause")@\(Int(t))")
            if !play, before.state.active, !before.state.paused { pauses += 1 }
        case 4: effects = l.ending(.sessionEnded); log.append("sessionEnded@\(Int(t))")
        case 5: effects = l.ending(.backInFront); log.append("backInFront@\(Int(t))")
        case 6: effects = l.ending(.deviceLocked); log.append("deviceLocked@\(Int(t))")
        default: effects = l.tick(now: t); log.append("tick@\(Int(t))")
        }
        let detail = "life \(life): \(log.joined(separator: " ")) -> \(l.state), pausedAt \(l.pausedAt.map { "\($0)" } ?? "nil"), \(effects)"
        // L1
        if l.state.paused && !l.state.active { lifeViolated("L1 paused while not active", detail) }
        if (l.pausedAt != nil) != (l.state.active && l.state.paused) { lifeViolated("L1 a pause time while not paused, or none while paused", detail) }
        // L2
        if event == 2 || event == 3 {
            if before.state.active != effects.invalidate { lifeViolated("L2 a play or pause told AVKit while off, or not while active", detail) }
            if !before.state.active, l != before { lifeViolated("L2 a play or pause changed something while off", detail) }
        }
        // L3
        if (4...6).contains(event), effects.stop != before.state.active { lifeViolated("L3 an ending's stop not exactly while active", detail) }
        if (4...6).contains(event), effects.stop { endingStops += 1 }
        if event >= 7 {
            let due = before.state.active && before.state.paused && before.pausedAt.map { t >= $0 + P.pausedLimit } == true
            if effects.stop != due { lifeViolated("L3 a look's stop not exactly at the pause's limit", detail) }
            if effects.stop { pauseStops += 1 }
        }
        // L4: a pause's effects say when to look; no look owed while playing or off.
        if l.state.active && l.state.paused, event == 2 || event == 3 {
            if effects.lookAt != l.pausedAt.map({ $0 + P.pausedLimit }) { lifeViolated("L4 a pause's look not at its start plus the limit", detail) }
        }
        if event >= 7, !effects.stop, l.state.active && l.state.paused, effects.lookAt != l.pausedAt.map({ $0 + P.pausedLimit }) {
            lifeViolated("L4 a look before the limit does not say when to look again", detail)
        }
        if !(l.state.active && l.state.paused), effects.lookAt != nil { lifeViolated("L4 a look owed while playing or off", detail) }
        // L4: the glue's look at the time it was told stops a pause still running, and one a moment before
        // that does not.
        if l.state.active, l.state.paused, let p = l.pausedAt {
            var atLimit = l, justBefore = l
            if !atLimit.tick(now: p + P.pausedLimit).stop { lifeViolated("L4 the look at the pause's limit stopped nothing", detail) }
            if justBefore.tick(now: p + P.pausedLimit - 0.001).stop { lifeViolated("L4 a look before the pause's limit stopped it", detail) }
        }
        // L5
        if effects.stop && !before.state.active { lifeViolated("L5 a stop asked while off", detail) }
        if event == 1, l.state != .off || l.pausedAt != nil { lifeViolated("L5 didStop left it on or paused", detail) }
        // L6: a willStart while it shows changes nothing; one while off starts it playing.
        if event == 0 {
            if before.state.active, l != before || effects != .none { lifeViolated("L6 a willStart while it showed changed it, or asked something", detail) }
            if !before.state.active, l.state != playing || l.pausedAt != nil { lifeViolated("L6 a willStart did not start it playing", detail) }
            if !before.state.active, effects != E(invalidate: true) { lifeViolated("L6 a start did not tell AVKit, or asked more", detail) }
        }
        // L7: only AVKit's events and a play or pause change it; an ending or a look only asks.
        if event >= 4, l != before { lifeViolated("L7 an ending or a look changed it", detail) }
    }
}
for (what, n) in lifeViolations.sorted(by: { $0.key < $1.key }) { check("\(what): \(n) times; first: \(lifeFirst[what] ?? "")", false) }
check("20,000 random lives (\(starts) starts, \(pauses) pauses, \(pauseStops) stopped at the pause's limit, \(endingStops) by an ending): L1–L7",
      lifeViolations.isEmpty && starts > 10_000 && pauses > 5_000 && pauseStops > 500 && endingStops > 5_000)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
