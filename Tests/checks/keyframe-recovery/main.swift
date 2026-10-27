// KeyframeRecovery (iOSClient): when the device asks the Mac for a keyframe after its picture was
// interrupted (issue #101). Compiled with iOSClient/KeyframeRecovery.swift alone (run.sh). The rule
// case by case at its edges, then 20,000 random sessions against a model that keeps the history of
// events rather than the type's flags.
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
typealias R = KeyframeRecovery
/// The wait of an ask on a quick link (`answerWait` with round trips under a second).
let W = 4.0

extension KeyframeRecovery {
    /// Active, streaming, the quick link's wait: most cases.
    mutating func consider(_ now: TimeInterval) -> Decision { consider(now: now, active: true, streaming: true, wait: W) }
}

// MARK: - Cases

// How long an ask waits for its keyframe.
check(R.answerWait(worstRttMs: nil) == 4, "no round trip measured yet: an ask waits 4 s")
check(R.answerWait(worstRttMs: 0) == 4 && R.answerWait(worstRttMs: 300) == 4, "quick round trips: 4 s")
check(R.answerWait(worstRttMs: 1000) == 4, "1 s round trips: still 4 s")
check(R.answerWait(worstRttMs: 1500) == 6, "1.5 s round trips: four of them, 6 s")
check(R.answerWait(worstRttMs: 3000) == 12, "3 s round trips: 12 s")
check(R.answerWait(worstRttMs: -20) == 4, "a negative round trip counts as none")

var r = R()
check(r.consider(10) == .nothing, "no interruption: nothing to ask")
r.interrupted(now: 10)
check(r.open && !r.asked, "an interruption opens")
check(r.consider(10) == .askNow, "the first ask goes at once")
check(r.asked && r.lastAsk == 10, "the ask is counted")
check(r.consider(10.1) == .keyframeDue(14), "one ask per interruption while its keyframe is due (4 s after the ask)")
check(r.consider(13.999) == .keyframeDue(14), "just under 4 s: still due")
check(r.asked && r.repeats == 0, "a keyframe on its way changes nothing")
r.interrupted(now: 11)
check(r.consider(11) == .keyframeDue(14), "the layer read interrupted again: the same interruption, no second ask")
check(r.repeats == 0, "nor a repeat")

var answered = R()
answered.interrupted(now: 0)
_ = answered.consider(0)
answered.pictureBack(now: 0.1, active: true)
check(!answered.open, "a keyframe shown closes the interruption")
check(answered.consider(4) == .nothing && answered.consider(100) == .nothing, "the keyframe came: nothing more is asked")

// An ask whose keyframe never comes (a Mac from before kind 44 skips it; a keyframe lost on the way).
var unans = R()
unans.interrupted(now: 0)
_ = unans.consider(0)
check(unans.consider(4) == .askNow, "no keyframe 4 s after the ask: asked again")
check(unans.repeats == 1 && unans.spacingNow == 4, "an unanswered ask is a repeat: the spacing doubles")
check(unans.consider(7.9) == .keyframeDue(8), "the second ask's keyframe is due 4 s after it")
check(unans.consider(8) == .askAt(12), "none: owed again, held to 8 s after the second ask")
check(!unans.asked && unans.repeats == 2, "and not counted until then")
check(unans.consider(11.9) == .askAt(12), "still held just before")
check(unans.consider(12) == .askNow, "then asked")

// A Mac that never answers: a bounded series of asks, never one stuck ask and never one every 4 s.
var never = R()
never.interrupted(now: 0)
var neverAsks: [Double] = []
var nt = 0.0
while nt <= 300 {
    if never.consider(nt) == .askNow { neverAsks.append(nt) }
    nt += 0.25
}
check(neverAsks == [0, 4, 12, 28, 60, 92, 124, 156, 188, 220, 252, 284],
      "a Mac that never answers is asked again after 4, 8 and 16 s, then every 32 s (\(neverAsks))")
check(never.open && never.spacingNow == 32, "still open, the spacing at its cap")
check(neverAsks.count == 12, "12 asks in 300 s: bounded by the backoff (\(neverAsks.count))")

// On a slow link an ask waits four round trips, and the wait follows the round trip.
var slow = R()
slow.interrupted(now: 0)
_ = slow.consider(now: 0, active: true, streaming: true, wait: 10)
check(slow.consider(now: 9.9, active: true, streaming: true, wait: 10) == .keyframeDue(10), "on a slow link the keyframe is due four round trips after the ask (10 s)")
check(slow.consider(now: 10, active: true, streaming: true, wait: 10) == .askNow, "then asked again, the wait longer than the spacing")
check(slow.consider(now: 12, active: true, streaming: true, wait: 4) == .keyframeDue(14), "a quicker link: the next ask's keyframe due 4 s after it")
check(slow.consider(now: 13, active: true, streaming: true, wait: 8) == .keyframeDue(18), "a slower one: due later")

// A keyframe the layer's flush threw away (it still read failed when the keyframe came):
// HEVCDisplayView says the picture is back, then interrupted, in that order.
var lost = R()
lost.interrupted(now: 0)
_ = lost.consider(0)
lost.pictureBack(now: 0.1, active: true)
lost.interrupted(now: 0.1)
check(lost.open && !lost.asked && lost.repeats == 1, "a keyframe the flush threw away: back, lost again, a repeat")
check(lost.consider(0.1) == .askAt(4), "asked again at the repeat's spacing (4 s), never left owed to the keyframe that came")
check(lost.consider(4) == .askNow, "and asked")
lost.pictureBack(now: 4.1, active: true)
lost.interrupted(now: 4.1)
check(lost.consider(4.1) == .askAt(12), "lost again: 8 s")

// Seen in the background: held, and asked for on the way back.
var bg = R()
bg.leftForeground()
bg.interrupted(now: 5)
check(bg.consider(now: 5, active: false, streaming: true, wait: W) == .nothing, "seen in the background: held")
check(bg.lastAsk == nil && !bg.asked, "a held ask is not counted")
check(bg.consider(7) == .askNow, "active again: asked")

var idle = R()
idle.interrupted(now: 20)
check(idle.consider(now: 20, active: true, streaming: false, wait: W) == .nothing, "nothing streams: no ask")
check(idle.lastAsk == nil, "nor is one counted, so the spacing holds nothing back")
check(idle.consider(20.5) == .askNow, "a stream again: asked")

// The spacing between interruptions with a trip to the background between them: 2 s.
var sp = R()
sp.interrupted(now: 100)
_ = sp.consider(100)
sp.pictureBack(now: 100.5, active: true)
sp.leftForeground()
sp.interrupted(now: 101)
check(sp.repeats == 0 && sp.spacingNow == 2, "after a trip to the background: the base spacing")
check(sp.consider(101) == .askAt(102), "1 s after the last ask: owed at 2 s")
check(sp.consider(101.999) == .askAt(102), "just under 2 s: still owed")
check(!sp.asked, "an owed ask is not counted")
check(sp.consider(102) == .askNow, "at 2 s: asked")

// A picture that fails again right after each keyframe, Sill active throughout: 2, 4, 8, 16, 32, 32 s.
var rep = R()
var t = 0.0
rep.interrupted(now: t)
check(rep.consider(t) == .askNow, "a failing picture's first ask")
var gaps: [Double] = []
var lastAskTime = t
for _ in 0..<6 {
    rep.pictureBack(now: t + 0.1, active: true)
    rep.interrupted(now: t + 0.2)
    guard case .askAt(let at) = rep.consider(t + 0.2) else { check(false, "a repeat is held back"); break }
    t = at
    check(rep.consider(t) == .askNow, "a repeat asked at \(at - lastAskTime) s")
    gaps.append(t - lastAskTime)
    lastAskTime = t
}
check(gaps == [4, 8, 16, 32, 32, 32], "the spacing doubles for repeats, up to 32 s (\(gaps))")
check(rep.spacingNow == 32, "and stays there")

// A picture that stayed back for `calm` has recovered.
var calm = R()
calm.interrupted(now: 0); _ = calm.consider(0)
calm.pictureBack(now: 1, active: true)
calm.interrupted(now: 11)
check(calm.repeats == 0 && calm.spacingNow == 2, "back for 10 s: a new interruption, the base spacing")
var nearly = R()
nearly.interrupted(now: 0); _ = nearly.consider(0)
nearly.pictureBack(now: 1, active: true)
nearly.interrupted(now: 10.99)
check(nearly.repeats == 1 && nearly.spacingNow == 4, "back for just under 10 s: a repeat")
check(nearly.consider(10.99) == .askNow, "a repeat 11 s after the last ask is not held by its 4 s")

// A trip to the background ends a streak.
var trip = R()
trip.interrupted(now: 0); _ = trip.consider(0)
trip.pictureBack(now: 0.1, active: true); trip.interrupted(now: 0.2)
check(trip.repeats == 1, "a repeat")
_ = trip.consider(4)
trip.pictureBack(now: 4.1, active: true)
trip.leftForeground()
trip.interrupted(now: 4.3)
check(trip.repeats == 0 && trip.spacingNow == 2, "back from the background: the streak ends")
check(trip.consider(5) == .askAt(6), "and only the base spacing holds it back")

// A trip away while a streak holds an ask back: the spacing is 2 s again on the way back, not 32.
var streak = R()
var ht = 0.0
streak.interrupted(now: ht); _ = streak.consider(ht)
for _ in 0..<4 {
    streak.pictureBack(now: ht + 0.1, active: true); streak.interrupted(now: ht + 0.2)
    guard case .askAt(let at) = streak.consider(ht + 0.2) else { check(false, "a streak's repeat is held back"); break }
    ht = at; _ = streak.consider(ht)
}
streak.pictureBack(now: ht + 0.1, active: true); streak.interrupted(now: ht + 0.2)
check(streak.repeats == 5 && ht == 60 && streak.consider(ht + 0.2) == .askAt(92), "a streak of five, the last ask at 60 s: the next held until 92 s")
streak.leftForeground()
check(streak.repeats == 0 && streak.spacingNow == 2, "a trip away starts the spacing at 2 s again")
check(streak.consider(now: 66, active: false, streaming: true, wait: W) == .nothing, "not while away")
check(streak.consider(68) == .askNow, "back at 68 s: asked at once, not 24 s later at 92")

// A trip to the background while the ask is out: owed again on the way back.
var out = R()
out.interrupted(now: 50)
_ = out.consider(50)
out.leftForeground()
check(out.open && !out.asked, "the keyframe may come while Sill is away: the ask is owed again")
check(out.consider(now: 51, active: false, streaming: true, wait: W) == .nothing, "not while away")
check(out.consider(51) == .askAt(52), "back within 2 s: owed at the spacing")
check(out.consider(53) == .askNow, "then asked")
check(out.consider(54) == .keyframeDue(57), "once, while its keyframe is due")
var late = R()
late.interrupted(now: 0)
_ = late.consider(0)
late.leftForeground()
check(late.consider(now: 4, active: false, streaming: true, wait: W) == .nothing && late.repeats == 0,
      "an ask out when Sill went away is never counted unanswered while it is away")
check(late.consider(9) == .askNow && late.repeats == 0, "back after its wait: asked at once, no repeat")

// Keyframes that come in the background (iOS may refuse them) never count as repeats.
var bgk = R()
bgk.interrupted(now: 0); _ = bgk.consider(0)
bgk.pictureBack(now: 0.1, active: true)
bgk.leftForeground()
for k in 0..<4 {
    let at = 2 + Double(k) * 4
    bgk.interrupted(now: at)
    check(bgk.consider(now: at, active: false, streaming: true, wait: W) == .nothing, "away: nothing asked (\(k + 1))")
    bgk.pictureBack(now: at + 0.1, active: false)
}
bgk.interrupted(now: 17.9)
check(bgk.repeats == 0, "four keyframes shown and lost in the background: no repeat (\(bgk.repeats))")
check(bgk.consider(18) == .askNow, "back at 18 s: asked at once")
var keep = R()
keep.interrupted(now: 0); _ = keep.consider(0)
keep.leftForeground()
keep.pictureBack(now: 1, active: false)
keep.interrupted(now: 2)
check(keep.repeats == 0, "a keyframe shown while away keeps the trip away: the next interruption is not a repeat")
var front = R()
front.interrupted(now: 0); _ = front.consider(0)
front.leftForeground()
front.pictureBack(now: 1, active: true)
front.interrupted(now: 2)
check(front.repeats == 1, "a keyframe shown with Sill in front again ends the trip: the next interruption within 10 s is a repeat")

// A keyframe shown with nothing open changes nothing.
var stray = R()
stray.interrupted(now: 0); _ = stray.consider(0)
stray.pictureBack(now: 1, active: true)
stray.pictureBack(now: 9, active: true)
stray.interrupted(now: 11.5)
check(stray.repeats == 0, "a keyframe with nothing open does not move when the picture came back (10.5 s ago, not 2.5)")

// The owed ask made moot: the picture came back on its own (another device's ask, a moving window).
var moot = R()
moot.interrupted(now: 0); _ = moot.consider(0)
moot.pictureBack(now: 0.1, active: true); moot.interrupted(now: 0.2)
check(moot.consider(0.2) == .askAt(4), "owed at 4 s")
moot.pictureBack(now: 1, active: true)
check(moot.consider(4) == .nothing, "back before then: nothing to ask")

// A clock gone back (never with the uptime, but never a stuck ask either).
var clock = R()
clock.interrupted(now: 200); _ = clock.consider(200)
clock.pictureBack(now: 200.1, active: true); clock.leftForeground(); clock.interrupted(now: 200.2)
check(clock.consider(10) == .askNow, "a clock before the last ask: asked")
var clockOut = R()
clockOut.interrupted(now: 200); _ = clockOut.consider(200)
check(clockOut.consider(10) == .askNow, "a clock before an ask that is out: asked again, never waited for")
var early = R()
early.interrupted(now: 300); _ = early.consider(300)
early.pictureBack(now: 300.1, active: true)
early.interrupted(now: 20)
check(early.repeats == 0, "a clock before the picture's return: not a repeat")

// The cap on repeats keeps the spacing at 32 s.
var cap = R()
var ct = 0.0
cap.interrupted(now: ct); _ = cap.consider(ct)
for _ in 0..<20 {
    cap.pictureBack(now: ct + 0.1, active: true); cap.interrupted(now: ct + 0.2)
    if case .askAt(let at) = cap.consider(ct + 0.2) { ct = at; _ = cap.consider(ct) }
}
check(cap.spacingNow == 32 && cap.repeats == 20, "twenty repeats: still 32 s (repeats \(cap.repeats))")

// MARK: - A model: the history of events, not flags

/// The rule restated from what happened: the interruption is the span since the last open, its ask
/// out when an ask is the latest of its asks, trips away and unanswered marks, the streak read back
/// through the history.
struct Model {
    enum Event { case open(Double), back(Double, active: Bool), away, ask(Double), unanswered }
    var events: [Event] = []
    var isOpen: Bool {
        for e in events.reversed() { if case .open = e { return true }; if case .back = e { return false } }
        return false
    }
    /// An ask is out: since the open interruption opened, the latest of its asks, trips away and
    /// unanswered marks is an ask.
    var askOut: Bool {
        for e in events.reversed() {
            switch e {
            case .ask: return true
            case .away, .open, .unanswered: return false
            case .back: continue
            }
        }
        return false
    }
    var lastAsk: Double? {
        for e in events.reversed() { if case .ask(let t) = e { return t } }
        return nil
    }
    /// The streak: each open that came less than `calm` after the picture came back, with no trip
    /// away since the picture last came back with Sill in front, and each unanswered ask, add one; an
    /// open after the calm, or a trip away, starts it again.
    var streak: Int {
        var k = 0
        var lastBack: Double? = nil
        var awaySinceBack = false
        for e in events {
            switch e {
            case .back(let t, let active): lastBack = t; if active { awaySinceBack = false }
            case .away: awaySinceBack = true; k = 0
            case .open(let t):
                if let b = lastBack, !awaySinceBack, t >= b, t - b < R.calm { k += 1 } else { k = 0 }
            case .unanswered: k += 1
            case .ask: break
            }
        }
        return k
    }
    var spacing: Double { min(2 * pow(2, Double(streak)), 32) }

    mutating func interrupted(_ t: Double) { if !isOpen { events.append(.open(t)) } }
    mutating func back(_ t: Double, active: Bool) { if isOpen { events.append(.back(t, active: active)) } }
    mutating func away() { events.append(.away) }
    mutating func consider(_ t: Double, active: Bool, streaming: Bool, wait: Double) -> R.Decision {
        guard isOpen, active, streaming else { return .nothing }
        if askOut {
            if let last = lastAsk, t >= last, t < last + wait { return .keyframeDue(last + wait) }
            events.append(.unanswered)
        }
        if let last = lastAsk, t >= last, t < last + spacing { return .askAt(last + spacing) }
        events.append(.ask(t))
        return .askNow
    }
}

struct LCG {
    var s: UInt64
    mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
}

var rng = LCG(s: 0x5eed_101)
var disagreements = 0, asks = 0, reasks = 0, held = 0, due = 0, lostKeyframes = 0
var tooClose = 0, whileIdle = 0, earlyReask = 0, owedNotAsked = 0, dueNotOwed = 0, stuck = 0
for session in 0..<20_000 {
    var rule = R(), model = Model()
    var now = Double(rng.next() % 1000)
    var active = true, streaming = true
    var askTimes: [Double] = []
    /// The interruption's last ask since it opened and since the last trip away (nil: none yet), and
    /// whether the rule has since judged it unanswered (checked against that consider's wait).
    var segmentAsk: Double? = nil
    var overdue = false
    for _ in 0..<60 {
        // Mostly a quick link's 4 s, sometimes a slow one's longer wait.
        let wait = rng.unit() < 0.7 ? W : 4 + rng.unit() * 8
        let roll = rng.unit()
        if roll < 0.20 {
            if !rule.open { segmentAsk = nil; overdue = false }
            rule.interrupted(now: now); model.interrupted(now)
        } else if roll < 0.32 {
            rule.pictureBack(now: now, active: active); model.back(now, active: active)
        } else if roll < 0.36 {
            // A keyframe the flush threw away: the picture back, then lost again at once.
            if rule.open { lostKeyframes += 1 }
            rule.pictureBack(now: now, active: active); model.back(now, active: active)
            segmentAsk = nil; overdue = false
            rule.interrupted(now: now); model.interrupted(now)
        } else if roll < 0.44 {
            if active { active = false; rule.leftForeground(); model.away(); segmentAsk = nil; overdue = false } else { active = true }
        } else if roll < 0.48 {
            streaming.toggle()
        } else {
            let wasOut = rule.asked
            let wasOpen = rule.open
            let decided = rule.consider(now: now, active: active, streaming: streaming, wait: wait)
            let expected = model.consider(now, active: active, streaming: streaming, wait: wait)
            if decided != expected {
                disagreements += 1
                if disagreements <= 5 { print("     session \(session): at \(now) the rule said \(decided), the model \(expected)") }
            }
            if decided == .nothing, wasOpen, active, streaming { stuck += 1 }
            if wasOut, decided != .nothing {
                if case .keyframeDue = decided {} else {
                    // Judged unanswered here: the ask's keyframe must be overdue by this consider's wait.
                    if let prev = segmentAsk, now >= prev, now - prev < wait { earlyReask += 1 }
                    overdue = true
                }
            }
            switch decided {
            case .askNow:
                asks += 1
                if wasOut { reasks += 1 }
                if let last = askTimes.last, now >= last, now - last < R.spacing { tooClose += 1 }
                if !active || !streaming { whileIdle += 1 }
                if segmentAsk != nil, !overdue { earlyReask += 1 }    // a second ask with the first still out
                segmentAsk = now
                overdue = false
                askTimes.append(now)
            case .askAt(let at):
                held += 1
                // Owed: at that time, unless something changes, it goes.
                var copy = rule
                if copy.consider(now: at, active: true, streaming: true, wait: wait) != .askNow { owedNotAsked += 1 }
            case .keyframeDue(let at):
                due += 1
                // Overdue at that time: owed again, now or when the spacing allows, never waited for again.
                var copy = rule
                switch copy.consider(now: at, active: true, streaming: true, wait: wait) {
                case .askNow: break
                case .askAt(let next) where next > at: break
                default: dueNotOwed += 1
                }
            case .nothing: break
            }
        }
        // Mostly short steps (a frame, a round trip), sometimes seconds, now and then minutes.
        let step = rng.unit()
        now += step < 0.6 ? rng.unit() * 0.5 : step < 0.9 ? rng.unit() * 6 : rng.unit() * 120
    }
}
check(disagreements == 0, "20,000 random sessions: the rule decides as the model does (\(disagreements) differ)")
check(asks > 10_000 && held > 1_000 && due > 10_000 && reasks > 1_000 && lostKeyframes > 1_000,
      "the sessions ask (\(asks)), ask again (\(reasks)), hold asks back (\(held)), wait for keyframes (\(due)) and lose some (\(lostKeyframes))")
check(tooClose == 0, "no two asks less than 2 s apart (\(tooClose))")
check(whileIdle == 0, "no ask while Sill is not active or nothing streams (\(whileIdle))")
check(earlyReask == 0, "an interruption asked for again only once its last ask's keyframe is overdue (\(earlyReask))")
check(owedNotAsked == 0, "an ask held back goes at the time it was owed (\(owedNotAsked))")
check(dueNotOwed == 0, "a keyframe overdue makes the ask owed again, never waited for again (\(dueNotOwed))")
check(stuck == 0, "an open interruption, Sill active and something streaming: never nothing to do, so never stuck (\(stuck))")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
