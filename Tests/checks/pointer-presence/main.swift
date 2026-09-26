import CoreGraphics
import Foundation

// H3 of docs/pointer-visibility-plan.md, the device's part: PointerPresence, PointerFeedState and
// PointerFeed, and PadCursor (iOSClient/PointerPresence.swift), compiled on their own:
//   swiftc -O iOSClient/PointerPresence.swift Tests/checks/pointer-presence/main.swift -o check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
typealias P = PointerPresence
typealias F = PointerFeedState

// MARK: What the sprite shows, row by row ("What the device draws")

func presence(_ control: P.Control, mac: CGPoint? = nil, inside: Bool = false, own: CGPoint? = nil, origin: P.Origin = .none,
              portrait: Bool, streaming: Bool = true) -> P {
    var p = P()
    p.control = control; p.mac = mac; p.macInside = inside
    p.setOwn(own, from: origin)
    p.portrait = portrait; p.streaming = streaming
    return p
}
let macAt = pt(0.40, 0.30), ownAt = pt(0.62, 0.55)
let layouts = [(false, "landscape"), (true, "portrait")]

// The Mac (or another device) moved it last: the Mac's pointer while it is over the stream, in every
// layout, whatever drew this device's own pointer before.
for (portrait, layout) in layouts {
    for origin in [P.Origin.trackpad, .pencil, .none] {
        check(presence(.elsewhere, mac: macAt, inside: true, own: ownAt, origin: origin, portrait: portrait).sprite(now: 0) == macAt,
              "the Mac has it, over the stream: its pointer (\(layout), own from \(origin))")
        check(presence(.elsewhere, mac: macAt, inside: false, own: ownAt, origin: origin, portrait: portrait).sprite(now: 0) == nil,
              "the Mac has it, off the stream: hidden (\(layout), own from \(origin))")
    }
    check(presence(.elsewhere, mac: nil, inside: true, portrait: portrait).sprite(now: 0) == nil, "the Mac has it, no position yet: hidden (\(layout))")
}
// This device, with the on-screen trackpad: its own pointer in portrait only.
check(presence(.here, own: ownAt, origin: .trackpad, portrait: true).sprite(now: 0) == ownAt, "this device's trackpad, portrait: its own pointer")
check(presence(.here, own: ownAt, origin: .trackpad, portrait: false).sprite(now: 0) == nil, "this device's trackpad, landscape: hidden")
check(presence(.here, mac: macAt, inside: true, own: ownAt, origin: .trackpad, portrait: true).sprite(now: 0) == ownAt,
      "this device's trackpad in portrait: its own, never the Mac's last position")
check(presence(.here, mac: macAt, inside: true, own: ownAt, origin: .trackpad, portrait: false).sprite(now: 0) == nil,
      "this device's trackpad in landscape: not the Mac's last position either")
// This device, a finger on the stream, typing, a key, the iPad's own trackpad or mouse: hidden.
for (portrait, layout) in layouts {
    check(presence(.here, own: nil, origin: .none, portrait: portrait).sprite(now: 0) == nil, "this device, a finger or a key: hidden (\(layout))")
    check(presence(.here, mac: macAt, inside: true, own: ownAt, origin: .none, portrait: portrait).sprite(now: 0) == nil,
          "this device, no origin: hidden even with a position about (\(layout))")
}
// This device, with the Pencil: hidden (Q2), and shown in every layout with the flip.
for (portrait, layout) in layouts {
    var p = presence(.here, own: ownAt, origin: .pencil, portrait: portrait)
    check(p.sprite(now: 0) == nil, "the Pencil: hidden by default (\(layout))")
    p.pencilShowsPointer = true
    check(p.sprite(now: 0) == ownAt, "the Pencil with Q2's flip: shown (\(layout))")
}
check(P.pencilShowsPointerByDefault == false && P().pencilShowsPointer == false, "Q2's default: no Pencil arrow")
// Nothing streams: nothing shows, in any row.
for (portrait, layout) in layouts {
    for (control, origin) in [(P.Control.elsewhere, P.Origin.none), (.here, .trackpad), (.here, .pencil), (.here, .none)] {
        var p = presence(control, mac: macAt, inside: true, own: ownAt, origin: origin, portrait: portrait, streaming: false)
        p.pencilShowsPointer = true
        check(p.sprite(now: 0) == nil, "nothing streams: hidden (\(control), \(origin), \(layout))")
    }
}
// A new session: the Mac has the pointer (Q6), and the arrow shows once it says where.
do {
    var p = P()
    check(p.control == .elsewhere && p.sprite(now: 0) == nil, "a new session: the Mac's, nothing to show yet")
    p.streaming = true
    check(p.sprite(now: 0) == nil, "streaming, no report yet: nothing")
    p.mac = macAt; p.macInside = true
    check(p.sprite(now: 0) == macAt, "the first report over the stream: the Mac's arrow")
}
// A rotation: the trackpad's arrow goes in landscape and comes back in portrait; the Mac's stays.
do {
    var p = presence(.here, own: ownAt, origin: .trackpad, portrait: true)
    p.portrait = false
    let landscape = p.sprite(now: 0)
    p.portrait = true
    check(landscape == nil && p.sprite(now: 0) == ownAt, "rotating with the trackpad's arrow: gone in landscape, back in portrait")
    var m = presence(.elsewhere, mac: macAt, inside: true, portrait: true)
    m.portrait = false
    check(m.sprite(now: 0) == macAt, "rotating with the Mac's arrow: it stays")
}

// MARK: The trackpad's linger (Q1)

do {
    var p = presence(.here, own: ownAt, origin: .trackpad, portrait: true)
    check(P.trackpadLingerByDefault == nil && p.trackpadLinger == nil, "Q1's default: no linger")
    p.fingers(1, now: 10)
    p.fingers(0, now: 10)
    check(p.sprite(now: 1_000) == ownAt && p.lingerEnds == nil, "without the linger the pad's arrow stays after the finger lifts")
    p.trackpadLinger = 2
    check(p.lingerEnds == 12, "with it, the timer is due at lift + 2 s: \(String(describing: p.lingerEnds))")
    check(p.sprite(now: 11.9) == ownAt && p.sprite(now: 12) == ownAt, "shown until 2 s after the lift")
    check(p.sprite(now: 12.001) == nil, "hidden after")
    p.fingers(1, now: 13)
    check(p.sprite(now: 20) == ownAt && p.lingerEnds == nil, "a finger down again: shown, no timer")
    p.fingers(2, now: 14)
    p.fingers(1, now: 15)
    check(p.lingerEnds == nil && p.sprite(now: 30) == ownAt, "one of two fingers lifting starts nothing")
    p.fingers(0, now: 16)
    check(p.lingerEnds == 18 && p.sprite(now: 18.5) == nil, "the last lifting starts it")
    var q = presence(.here, own: ownAt, origin: .trackpad, portrait: true)
    q.trackpadLinger = 2
    q.fingers(0, now: 5)
    check(q.lingerEnds == nil && q.sprite(now: 100) == ownAt, "no finger ever down: nothing lifted, nothing to hide")
    q.fingers(-3, now: 6)
    check(q.fingersOnTrackpad == 0 && q.lingerEnds == nil, "a negative count is none")
    // Only the pad's own arrow lingers.
    var r = p
    r.control = .elsewhere; r.mac = macAt; r.macInside = true
    check(r.lingerEnds == nil && r.sprite(now: 100) == macAt, "the Mac's arrow never lingers out")
    r = p; r.portrait = false
    check(r.lingerEnds == nil, "no timer in landscape (hidden anyway)")
    r = p; r.setOwn(ownAt, from: .pencil)
    check(r.lingerEnds == nil, "no timer for the Pencil")
    r = p; r.streaming = false
    check(r.lingerEnds == nil, "no timer while nothing streams")
}

// MARK: Following the feed

do {
    var feed = F()
    _ = feed.report(at: macAt, seen: 0, sentOnSession: 0, movePending: false, now: 1)
    var p = presence(.here, own: ownAt, origin: .trackpad, portrait: true)
    p.follow(feed)
    check(p.control == .elsewhere && p.mac == macAt && p.macInside && p.sprite(now: 1) == macAt, "the presence follows the feed: the Mac's")
    _ = feed.sent(.pointer(ownAt), now: 2)
    p.follow(feed)
    check(p.control == .here && p.sprite(now: 2) == ownAt, "…and back to this device's own")
}

// MARK: Freshness (§3.3)

check(!P.isFresh(seen: 41, sentOnSession: 42, movePending: false), "seen 41 against 42 sent: stale")
check(P.isFresh(seen: 42, sentOnSession: 42, movePending: false), "seen 42 against 42: fresh")
check(!P.isFresh(seen: 42, sentOnSession: 42, movePending: true), "equal, with a move waiting to go out: stale")
check(P.isFresh(seen: 43, sentOnSession: 42, movePending: false), "more than sent: fresh")
check(P.isFresh(seen: nil, sentOnSession: 0, movePending: false), "nil against 0: fresh")
check(!P.isFresh(seen: nil, sentOnSession: 1, movePending: false), "nil against 1: stale")
check(P.isFresh(seen: 0, sentOnSession: 0, movePending: false) && !P.isFresh(seen: 0, sentOnSession: 0, movePending: true),
      "0 against 0: fresh, unless a move waits")
check(!P.isFresh(seen: -1, sentOnSession: 0, movePending: false), "a negative seen: stale")

// MARK: Restatements (§7.3)

let tiny = 0.001953125   // 2^-9, just under the tolerance, exact in binary
check(P.restatementTolerance == 0.002, "the tolerance is 0.002")
check(P.isRestatement(x: 0.25, y: 0.75, inside: true, anchor: pt(0.25, 0.75), recent: []), "at the anchor")
check(P.isRestatement(x: 0.25 + tiny, y: 0.75 - tiny, inside: true, anchor: pt(0.25, 0.75), recent: []), "within 0.002 of it on both axes")
check(!P.isRestatement(x: 0.2521, y: 0.75, inside: true, anchor: pt(0.25, 0.75), recent: []), "0.0021 off on x: not")
check(!P.isRestatement(x: 0.25, y: 0.7479, inside: true, anchor: pt(0.25, 0.75), recent: []), "0.0021 off on y: not")
check(!P.isRestatement(x: 0.25, y: 0.75, inside: false, anchor: pt(0.25, 0.75), recent: [pt(0.25, 0.75)]), "off the stream is never one")
check(P.isRestatement(x: 0.6, y: 0.1, inside: true, anchor: pt(0.25, 0.75), recent: [pt(0.1, 0.1), pt(0.6, 0.1 + tiny)]), "near a recent position")
check(!P.isRestatement(x: 0.6, y: 0.1, inside: true, anchor: nil, recent: []), "no anchor, nothing recent: not")
check(!P.isRestatement(x: 0.6, y: 0.1, inside: true, anchor: pt(0.25, 0.75), recent: [pt(0.5, 0.5)]), "far from all: not")

// MARK: The feed

do {
    var f = F()
    check(f.control == .elsewhere && f.mac == nil && !f.macInside && f.anchor == nil && f.takeovers == 0 && !f.carrying && f.recent.isEmpty,
          "a new feed: the Mac's, nothing known")
    check(f.sent(.pointer(pt(0.1, 0.2)), now: 1), "the first input brings the pointer here")
    check(f.control == .here && f.anchor == pt(0.1, 0.2) && f.recentPoints(now: 1) == [pt(0.1, 0.2)], "a pointer event: the anchor and the last 3 s")
    check(!f.sent(.pointer(pt(0.11, 0.2)), now: 1.01), "the next input: no change of hands")
    check(!f.sent(.other, now: 1.02) && f.anchor == pt(0.11, 0.2), "a key: here, the anchor unchanged")
    check(!f.sent(.scroll(pt(0.3, 0.3)), now: 1.03) && f.anchor == pt(0.11, 0.2) && f.recentPoints(now: 1.03).last == pt(0.3, 0.3),
          "a scroll: its location among the last 3 s, not the anchor")
    // The Mac's news takes it.
    check(f.report(at: pt(0.5, 0.5), seen: 4, sentOnSession: 4, movePending: false, now: 2) == .news(tookOver: true, changed: true),
          "a fresh report while here: news that takes the pointer")
    check(f.control == .elsewhere && f.mac == pt(0.5, 0.5) && f.macInside && f.anchor == pt(0.5, 0.5) && f.takeovers == 1,
          "…elsewhere, the Mac's position, the anchor there, one takeover")
    check(f.report(at: pt(0.6, 0.5), seen: 4, sentOnSession: 4, movePending: false, now: 2.03) == .news(tookOver: false, changed: true)
          && f.takeovers == 1, "the Mac's pointer moving: news, no takeover")
    check(f.report(at: pt(0.6, 0.5), seen: 4, sentOnSession: 4, movePending: false, now: 2.06) == .news(tookOver: false, changed: false),
          "the same position again: nothing changed")
    check(f.report(at: nil, seen: 4, sentOnSession: 4, movePending: false, now: 2.09) == .news(tookOver: false, changed: true)
          && !f.macInside && f.mac == pt(0.6, 0.5) && f.anchor == pt(0.6, 0.5), "off the stream: hidden; the last position and the anchor stay")
    // Stale reports change nothing.
    _ = f.sent(.pointer(pt(0.2, 0.2)), now: 3)
    let before = f
    check(f.report(at: pt(0.9, 0.9), seen: 4, sentOnSession: 5, movePending: false, now: 3.01) == .stale && f == before,
          "a report the Mac built before reading this device's input: stale, nothing changes")
    check(f.report(at: pt(0.9, 0.9), seen: 5, sentOnSession: 5, movePending: true, now: 3.02) == .stale && f == before,
          "a report while a move waits to go out: stale")
    check(f.report(at: pt(0.9, 0.9), seen: 5, sentOnSession: 5, movePending: false, now: 3.03) == .news(tookOver: true, changed: true)
          && f.takeovers == 2, "once the Mac has read it all: news, a takeover")
}
// The anchor: the newer of this device's last pointer event and the Mac's last position over the stream.
do {
    var f = F()
    _ = f.sent(.pointer(pt(0.1, 0.1)), now: 1)
    _ = f.report(at: pt(0.2, 0.2), seen: 1, sentOnSession: 1, movePending: false, now: 2)
    check(f.anchor == pt(0.2, 0.2), "the Mac's position after this device's: the Mac's")
    _ = f.sent(.pointer(pt(0.3, 0.3)), now: 3)
    check(f.anchor == pt(0.3, 0.3), "this device's after the Mac's: this device's")
    _ = f.sent(.scroll(pt(0.4, 0.4)), now: 4)
    _ = f.sent(.other, now: 5)
    check(f.anchor == pt(0.3, 0.3), "a scroll or a key leave it")
    _ = f.report(at: nil, seen: 4, sentOnSession: 4, movePending: false, now: 6)
    check(f.anchor == pt(0.3, 0.3), "a report off the stream leaves it")
    _ = f.report(at: pt(0.5, 0.5), seen: 3, sentOnSession: 4, movePending: false, now: 7)
    check(f.anchor == pt(0.3, 0.3), "a stale report leaves it")
}
// Takeovers count only the pointer leaving this device.
do {
    var f = F()
    _ = f.report(at: pt(0.2, 0.2), seen: 0, sentOnSession: 0, movePending: false, now: 1)
    _ = f.report(at: pt(0.3, 0.2), seen: 0, sentOnSession: 0, movePending: false, now: 1.1)
    check(f.takeovers == 0, "reports while the Mac has it: no takeover")
    _ = f.sent(.other, now: 2)
    _ = f.report(at: nil, seen: 1, sentOnSession: 1, movePending: false, now: 2.1)
    check(f.takeovers == 1, "a report off the stream takes it too")
    _ = f.sent(.other, now: 3)
    _ = f.report(at: pt(0.5, 0.5), seen: 1, sentOnSession: 2, movePending: false, now: 3.1)
    check(f.takeovers == 1 && f.control == .here, "a stale report takes nothing")
}
// A hand-over's carry-over.
do {
    var f = F()
    _ = f.sent(.pointer(pt(0.30, 0.40)), now: 10)
    _ = f.sent(.scroll(pt(0.70, 0.20)), now: 11)
    check(f.handedOver() && f.carrying, "a hand-over while this device has the pointer: it carries over")
    // The new connection's first reports: nothing read on it yet, so seen 0 against a count of 0.
    check(f.report(at: pt(0.30, 0.40), seen: 0, sentOnSession: 0, movePending: false, now: 12) == .restatement,
          "the Mac restating the anchor: this device's own doing")
    check(f.report(at: pt(0.30 + tiny, 0.40 - tiny), seen: 0, sentOnSession: 0, movePending: false, now: 12.03) == .restatement,
          "within 0.002 of it")
    check(f.report(at: pt(0.70, 0.20), seen: 0, sentOnSession: 0, movePending: false, now: 13.9) == .restatement,
          "a scroll's location from 2.9 s ago")
    check(f.control == .here && f.takeovers == 0 && f.mac == nil && f.carrying, "…none of them changed anything")
    check(f.report(at: pt(0.30, 0.40), seen: 0, sentOnSession: 1, movePending: false, now: 13.95) == .stale && f.carrying,
          "a stale one is stale first")
    var old = f
    check(old.report(at: pt(0.70, 0.20), seen: 0, sentOnSession: 0, movePending: false, now: 14.5) == .news(tookOver: true, changed: true),
          "that scroll's location 3.5 s later is news")
    var exact = f
    check(exact.report(at: pt(0.70, 0.20), seen: 0, sentOnSession: 0, movePending: false, now: 14) == .restatement,
          "…and exactly 3 s later still its own")
    var off = f
    check(off.report(at: nil, seen: 0, sentOnSession: 0, movePending: false, now: 12.1) == .news(tookOver: true, changed: true)
          && off.control == .elsewhere && !off.carrying, "off the stream during a carry-over: news, it takes the pointer")
    var far = f
    check(far.report(at: pt(0.9, 0.9), seen: 0, sentOnSession: 0, movePending: false, now: 12.2) == .news(tookOver: true, changed: true)
          && far.takeovers == 1 && !far.carrying, "a position of nobody's here: news, a takeover, the carry-over ends")
    check(far.report(at: pt(0.9 + tiny, 0.9), seen: 0, sentOnSession: 0, movePending: false, now: 12.23) == .news(tookOver: false, changed: true),
          "after news, a report near the new anchor is news too")
    // The first input on the new connection ends it.
    check(!f.sent(.pointer(pt(0.31, 0.40)), now: 15) && !f.carrying, "this device's first input on the new connection ends the carry-over")
    check(f.report(at: pt(0.31, 0.40), seen: 1, sentOnSession: 1, movePending: false, now: 15.5) == .news(tookOver: true, changed: true),
          "then even its own position reported back is news (the Mac read the input, so it is the Mac's doing)")
    // A hand-over while the Mac has the pointer carries nothing.
    var g = F()
    _ = g.report(at: pt(0.5, 0.5), seen: 0, sentOnSession: 0, movePending: false, now: 1)
    check(!g.handedOver() && !g.carrying, "a hand-over while the Mac has it: nothing to carry")
    check(g.report(at: pt(0.5, 0.5), seen: 0, sentOnSession: 0, movePending: false, now: 1.1) == .news(tookOver: false, changed: false),
          "…and its reports are news as ever")
    // A carry-over outlasts the Mac's reports, however many, until news or input.
    var h = F()
    _ = h.sent(.pointer(pt(0.5, 0.5)), now: 1)
    _ = h.handedOver()
    var restated = 0
    for i in 0..<100 where h.report(at: pt(0.5, 0.5), seen: 0, sentOnSession: 0, movePending: false, now: 1 + Double(i) * 0.03) == .restatement {
        restated += 1
    }
    check(restated == 100 && h.control == .here, "100 restatements over 3 s: this device keeps the pointer")
}
// The session ending.
do {
    var f = F()
    _ = f.sent(.pointer(pt(0.1, 0.1)), now: 1)
    _ = f.report(at: pt(0.2, 0.2), seen: 1, sentOnSession: 1, movePending: false, now: 2)
    _ = f.sent(.scroll(pt(0.3, 0.3)), now: 3)
    _ = f.handedOver()
    f.reset()
    check(f.control == .elsewhere && f.mac == nil && !f.macInside && f.anchor == nil && !f.carrying && f.recent.isEmpty,
          "tearDown: the Mac's, nothing known")
    check(f.takeovers == 1, "…but takeovers only grow")
}
// The last 3 s, bounded.
do {
    var f = F()
    for i in 0..<5_000 { _ = f.sent(.pointer(pt(CGFloat(i) / 5_000, 0.5)), now: 100 + Double(i) * 0.0001) }
    check(f.recent.count == F.recentLimit, "5,000 moves in half a second keep the newest \(F.recentLimit): \(f.recent.count)")
    check(f.recent.last?.point == pt(4_999.0 / 5_000, 0.5) && f.recent.first?.point == pt(CGFloat(5_000 - F.recentLimit) / 5_000, 0.5),
          "…oldest dropped first")
    var g = F()
    _ = g.sent(.pointer(pt(0.1, 0.1)), now: 10)
    _ = g.sent(.pointer(pt(0.2, 0.2)), now: 12)
    _ = g.sent(.pointer(pt(0.3, 0.3)), now: 13.5)
    check(g.recent.count == 2 && g.recentPoints(now: 13.5) == [pt(0.2, 0.2), pt(0.3, 0.3)], "what is older than 3 s goes")
    check(g.recentPoints(now: 15) == [pt(0.2, 0.2), pt(0.3, 0.3)] && g.recentPoints(now: 15.0001) == [pt(0.3, 0.3)],
          "a position counts for 3 s exactly")
}
// The lock: sends and reports from two threads at once, each report judged against a count that only grows.
do {
    let feed = PointerFeed()
    let group = DispatchGroup()
    let counter = NSLock()
    var sentCount = 0
    DispatchQueue.global().async(group: group) {
        for i in 0..<20_000 {
            counter.lock(); sentCount += 1; counter.unlock()
            _ = feed.sent(i % 3 == 0 ? .other : .pointer(pt(0.5, 0.5)), now: Double(i) * 0.0001)
        }
    }
    var news = 0
    DispatchQueue.global().async(group: group) {
        for i in 0..<20_000 {
            counter.lock(); let n = sentCount; counter.unlock()
            if case .news = feed.report(at: pt(0.25, 0.25), seen: n, sentOnSession: n, movePending: false, now: Double(i) * 0.0001) { news += 1 }
        }
    }
    group.wait()
    let state = feed.current
    check(state.takeovers <= news && news > 0, "20,000 sends against 20,000 reports: \(news) news, \(state.takeovers) takeovers")
    feed.reset()
    check(feed.current.control == .elsewhere && feed.current.anchor == nil && !feed.handedOver(), "the feed's reset and hand-over")
}

// MARK: The portrait pad's cursor

do {
    var pad = PadCursor()
    check(pad.cursor == pt(0.5, 0.5) && pad.takeoversSeen == 0, "the pad starts in the middle")
    pad.adopt(anchor: nil, takeovers: 3)
    check(pad.cursor == pt(0.5, 0.5) && pad.takeoversSeen == 3, "no anchor: the cursor stays; the count is seen")
    pad.adopt(anchor: pt(0.2, 0.9), takeovers: 3)
    check(pad.cursor == pt(0.2, 0.9), "a stroke's first finger carries on from the anchor")
    pad.adopt(anchor: pt(1.4, -0.2), takeovers: 3)
    check(pad.cursor == pt(1, 0), "an anchor out of range is clamped")
    pad.move(dx: -0.25, dy: 0.5)
    check(pad.cursor == pt(0.75, 0.5), "a move: travel added")
    pad.move(dx: 2, dy: -2)
    check(pad.cursor == pt(1, 0), "pushed past the edges: parked there")
    pad.catchUp(anchor: pt(0.1, 0.1), takeovers: 3)
    check(pad.cursor == pt(1, 0), "no takeover since the pad last looked: it keeps its own cursor")
    pad.catchUp(anchor: pt(0.1, 0.1), takeovers: 4)
    check(pad.cursor == pt(0.1, 0.1) && pad.takeoversSeen == 4, "the Mac took over mid-stroke: carry on from the anchor")
    pad.move(dx: 0.05, dy: 0)
    pad.catchUp(anchor: pt(0.1, 0.1), takeovers: 4)
    check(abs(pad.cursor.x - 0.15) < 1e-12 && pad.cursor.y == 0.1, "…once: the next move goes on from there")
    pad.catchUp(anchor: nil, takeovers: 5)
    check(abs(pad.cursor.x - 0.15) < 1e-12 && pad.takeoversSeen == 5, "a takeover with no anchor leaves the cursor")
}

// MARK: The plan's rows as a session (the feed, the presence and the pad together)

do {
    var feed = F()
    var shown = P()
    shown.streaming = true
    shown.portrait = true
    var pad = PadCursor()
    var sent = 0
    func render() -> CGPoint? { shown.follow(feed); return shown.sprite(now: 0) }
    // Connect: the Mac reports its pointer; the arrow shows (Q6).
    _ = feed.report(at: pt(0.40, 0.30), seen: 0, sentOnSession: sent, movePending: false, now: 1)
    check(render() == pt(0.40, 0.30), "session: the Mac's arrow at connect")
    // A stroke on the pad starts where the Mac's arrow is, and the first move lands there plus the travel.
    pad.adopt(anchor: feed.anchor, takeovers: feed.takeovers)
    pad.catchUp(anchor: feed.anchor, takeovers: feed.takeovers)
    pad.move(dx: 0.01, dy: 0)
    shown.setOwn(pad.cursor, from: .trackpad)
    _ = feed.sent(.pointer(pad.cursor), now: 2); sent += 1
    check(render().map { abs($0.x - 0.41) < 1e-12 && $0.y == 0.30 } == true, "session: the pad carries on from the Mac's arrow")
    // A report the Mac built before reading that move: stale, the pad's arrow stays.
    check(feed.report(at: pt(0.40, 0.30), seen: 0, sentOnSession: sent, movePending: false, now: 2.01) == .stale && render() == pad.cursor,
          "session: the Mac's older report is dropped")
    // The finger rests; the Mac's mouse moves: the arrow jumps to it.
    _ = feed.report(at: pt(0.70, 0.60), seen: sent, sentOnSession: sent, movePending: false, now: 3)
    check(render() == pt(0.70, 0.60), "session: the Mac takes over, the arrow jumps")
    // The resting finger moves again: the pad re-seeds from the Mac's pointer, no jump back.
    pad.catchUp(anchor: feed.anchor, takeovers: feed.takeovers)
    pad.move(dx: 0.01, dy: 0.01)
    check(abs(pad.cursor.x - 0.71) < 1e-12 && abs(pad.cursor.y - 0.61) < 1e-12, "session: the pad goes on from the Mac's pointer")
    shown.setOwn(pad.cursor, from: .trackpad)
    _ = feed.sent(.pointer(pad.cursor), now: 4); sent += 1
    check(render() == pad.cursor, "session: the pad's arrow again")
    // Rotate to landscape: the pad's arrow goes; the Mac's mouse: its arrow shows there too.
    shown.portrait = false
    check(render() == nil, "session: landscape hides the pad's arrow")
    _ = feed.report(at: pt(0.2, 0.2), seen: sent, sentOnSession: sent, movePending: false, now: 5)
    check(render() == pt(0.2, 0.2), "session: the Mac's arrow in landscape")
    // A tap on the stream: this device's again, and hidden.
    shown.setOwn(nil, from: .none)
    _ = feed.sent(.pointer(pt(0.5, 0.5)), now: 6); sent += 1
    check(render() == nil, "session: a tap on the stream hides it")
    // The session moves to a new connection: the count restarts, the Mac restates the tap's position.
    sent = 0
    _ = feed.handedOver()
    _ = feed.report(at: pt(0.5, 0.5), seen: 0, sentOnSession: sent, movePending: false, now: 6.5)
    check(render() == nil && feed.control == .here, "session: after a move, no arrow for this device's own position")
    _ = feed.report(at: pt(0.8, 0.1), seen: 0, sentOnSession: sent, movePending: false, now: 7)
    check(render() == pt(0.8, 0.1), "session: the Mac's own move after it shows")
    // Nothing streams any more: hidden.
    shown.streaming = false
    check(render() == nil, "session: nothing streams, nothing shows")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
