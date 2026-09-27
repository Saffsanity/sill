import CoreGraphics
import Foundation

// docs/pointer-visibility-plan.md, the host's step: PointerWatch (Sources/SillHost), the shell around
// PointerControl, with the readers and the clock it is given, and its TEST ONLY scripted pointer and
// hooks. Compiled with PointerControl.swift, Stats.swift and Sources/StreamProtocol (their `import
// StreamProtocol` dropped), as build.sh does.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
final class Device {}
let deviceA = Device(), deviceB = Device()
let A = ObjectIdentifier(deviceA), B = ObjectIdentifier(deviceB)
/// The devices a sample is told of: two, so one is always sent the pointer whoever drives (the
/// re-read after a move then runs as it would with a device watching; see the cases for fewer).
let both = [A, B]

/// The clock a watch is given: set by the check, read on any thread.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 100.0
    var now: Double {
        get { lock.lock(); defer { lock.unlock() }; return t }
        set { lock.lock(); t = newValue; lock.unlock() }
    }
}
/// The pointer's location as the watch reads it, and how often it was read.
final class Location: @unchecked Sendable {
    private let lock = NSLock()
    private var p: CGPoint? = CGPoint(x: 0, y: 0)
    private var n = 0
    var point: CGPoint? {
        get { lock.lock(); defer { lock.unlock() }; return p }
        set { lock.lock(); p = newValue; lock.unlock() }
    }
    var reads: Int { lock.lock(); defer { lock.unlock() }; return n }
    func read() -> CGPoint? { lock.lock(); defer { lock.unlock() }; n += 1; return p }
}
/// A window's state as the watch re-reads it: what it answers, how often it was asked, on which
/// queue, and a gate that holds the answer back.
final class Windows: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: [CGWindowID: PointerWatch.WindowState] = [:]
    private var asked: [CGWindowID] = []
    private var queues: [String] = []
    var gate: DispatchSemaphore?
    func set(_ id: CGWindowID, _ s: PointerWatch.WindowState?) { lock.lock(); answer[id] = s; lock.unlock() }
    var calls: [CGWindowID] { lock.lock(); defer { lock.unlock() }; return asked }
    var labels: [String] { lock.lock(); defer { lock.unlock() }; return queues }
    func read(_ id: CGWindowID) -> PointerWatch.WindowState? {
        let label = String(cString: __dispatch_queue_get_label(nil))
        lock.lock(); asked.append(id); queues.append(label); let g = gate; lock.unlock()
        g?.wait()
        lock.lock(); defer { lock.unlock() }
        return answer[id]
    }
}
func waitUntil(_ cond: () -> Bool) -> Bool {
    for _ in 0..<3000 { if cond() { return true }; usleep(1000) }
    return cond()
}
/// Time for a re-read that should not have started to show that it did (they run on sill.pointer).
func quiet() { usleep(60_000) }
func watch(synthetic: Bool = false, path: TestPointerPath? = nil, clock: Clock, location: Location,
           windows: Windows = Windows(), after: Double = 0.1, anyway: Double = 2) -> PointerWatch {
    PointerWatch(synthetic: synthetic, path: path, readLocation: { location.read() }, readWindow: { windows.read($0) },
                 clock: { clock.now }, rereadAfterMove: after, rereadAnyway: anyway)
}
let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)

// MARK: No geometry, no read

do {
    let c = Clock(), l = Location()
    let w = watch(clock: c, location: l)
    check(w.sample(devices: both) == nil, "no geometry: no sample")
    check(l.reads == 0, "no geometry: the pointer is not read")
    w.setGeometry(.rect(screen), fps: 60)
    check(w.sample(devices: both) != nil && l.reads == 1, "a geometry: one read a sample")
    w.setGeometry(nil, fps: 60)
    check(w.sample(devices: both) == nil && l.reads == 1, "the geometry gone: no read again")
    check(!w.hasTestPointer, "a real host has no scripted pointer")
}

// A synthetic host never reads the real pointer: not without the scripted pointer, whatever the
// geometry (a real window picked there), and not with it.
do {
    let c = Clock(), l = Location()
    let w = watch(synthetic: true, clock: c, location: l)
    w.setGeometry(.rect(screen), fps: 60)
    check(w.sample(devices: both) == nil, "a synthetic host without the scripted pointer: no sample")
    w.setGeometry(.window(9, screen), fps: 60)
    check(w.sample(devices: both) == nil, "…a window geometry there either")
    let path = TestPointerPath(steps: [.init(t: 0, point: pt(10, 10))])
    let w2 = watch(synthetic: true, path: path, clock: c, location: l)
    w2.setGeometry(.rect(screen), fps: 60)
    check(w2.sample(devices: both) != nil, "with the scripted pointer: a sample")
    check(l.reads == 0, "a synthetic host never read the real pointer")
    check(w2.hasTestPointer, "hasTestPointer with a path")
    let w3 = watch(synthetic: false, path: path, clock: c, location: l)
    check(!w3.hasTestPointer, "a path on a real host is dropped")
}

// MARK: The fraction and inside

do {
    let c = Clock(), l = Location()
    let w = watch(clock: c, location: l)
    w.setGeometry(.rect(CGRect(x: 100, y: 50, width: 800, height: 400)), fps: 60)
    l.point = pt(500, 250)
    var r = w.sample(devices: both)!
    check(r.x == 0.5 && r.y == 0.5 && r.inside, "the middle: 0.5, 0.5, inside (\(r))")
    c.now += 0.03; l.point = pt(100, 50)
    r = w.sample(devices: both)!
    check(r.x == 0 && r.y == 0 && r.inside, "the top-left corner is inside")
    c.now += 0.03; l.point = pt(900, 450)
    r = w.sample(devices: both)!
    check(r.x == 1 && r.y == 1 && !r.inside, "the bottom-right corner is outside: the next display's first column and row")
    c.now += 0.03; l.point = pt(899.99, 449.99)
    r = w.sample(devices: both)!
    check(r.x == 1 && r.y == 1 && r.inside, "the last column and row are inside, rounded to 1")
    c.now += 0.03; l.point = pt(99, 250)
    r = w.sample(devices: both)!
    check(!r.inside, "a point left of it is outside")
    c.now += 0.03; l.point = pt(333.33333, 50)
    r = w.sample(devices: both)!
    check(r.x == 0.2917, "rounded to 4 places (\(r.x))")
    c.now += 0.03; l.point = nil
    check(w.sample(devices: both) == nil, "no location: no sample")
}

// MARK: The report each device is sent

do {
    let inside = PointerWatch.Reading(x: 0.25, y: 0.75, inside: true, controller: .mac, moving: false)
    check(inside.report(for: A, seen: 3) == MacPointer(x: 0.25, y: 0.75, inside: true, seen: 3), "inside: x, y, inside and seen")
    let outside = PointerWatch.Reading(x: 1.5, y: 0.5, inside: false, controller: .client(B), moving: true)
    let off = outside.report(for: A, seen: 0)
    check(off == MacPointer(inside: false, seen: 0), "outside: no x or y (\(String(describing: off)))")
    check(outside.report(for: B, seen: 7) == nil, "the device driving the pointer is sent nothing")
    check(outside.report(for: A, seen: 7)?.seen == 7, "another device is, with its own count")
    let json = String(decoding: Wire.encode(off!), as: UTF8.self)
    check(!json.contains("\"x\"") && !json.contains("\"y\""), "outside, the JSON carries no x or y: \(json)")
}

// MARK: Who moves it, through the watch

do {
    let c = Clock(), l = Location()
    let w = watch(clock: c, location: l)
    w.setGeometry(.rect(screen), fps: 60)
    l.point = pt(100, 100)
    check(w.sample(devices: both)?.controller == .mac, "at first the Mac has the pointer")
    c.now += 0.03
    w.inputArrived(from: A, movesPointer: true)
    check(w.sample(devices: both)?.controller == .client(A), "a device's input hands it the pointer")
    c.now += 0.03; l.point = pt(400, 100)   // Sill's own move, absolute
    check(w.sample(devices: both)?.controller == .client(A), "Sill's move within the settle stays the device's")
    for _ in 0..<8 { c.now += 0.03; _ = w.sample(devices: both) }   // the settle runs out, the pointer still
    check(w.sample(devices: both)?.controller == .client(A), "a still pointer after the settle stays the device's")
    c.now += 0.03; l.point = pt(401, 100)
    check(w.sample(devices: both)?.controller == .mac, "a real move after it: the Mac's")
    c.now += 0.03
    w.inputArrived(from: B, movesPointer: false)
    check(w.sample(devices: both)?.controller == .client(B), "a key hands the pointer to its device…")
    c.now += 0.03; l.point = pt(402, 100)
    check(w.sample(devices: both)?.controller == .mac, "…without the settle: the Mac's next move shows at once")
    c.now += 0.03
    w.inputArrived(from: A, movesPointer: false)
    _ = w.sample(devices: both)
    w.clientLeft(A)
    c.now += 0.03
    check(w.sample(devices: both)?.controller == .mac, "the driving device left: the Mac has it")
}

// Sill's own post, noted just before it, opens the settle without handing the pointer to anyone.
do {
    let c = Clock(), l = Location()
    let w = watch(clock: c, location: l)
    w.setGeometry(.rect(screen), fps: 60)
    l.point = pt(10, 10); _ = w.sample(devices: both)
    c.now += 0.03
    w.inputArrived(from: A, movesPointer: false)
    _ = w.sample(devices: both)
    c.now += 2          // long after: a held click's post
    _ = w.sample(devices: both)      // the pointer unwatched meanwhile: this read starts afresh
    c.now += 0.03
    w.sillMoved()
    l.point = pt(300, 300)
    c.now += 0.03
    check(w.sample(devices: both)?.controller == .client(A), "a post noted before it lands stays Sill's")
    c.now += 0.03
    w.sillMoved(to: pt(700, 400))   // a real host: `to` moves nothing
    l.point = pt(300, 300)
    check(w.sample(devices: both).map { $0.x == 0.3 && $0.y == 0.6 } == true, "on a real host the location reader alone says where it is")
}

// MARK: Moving, and the frame interval

do {
    let c = Clock(), l = Location()
    let w = watch(clock: c, location: l)
    w.setGeometry(.rect(screen), fps: 120)
    check(abs(w.frameInterval - 1.0 / 120) < 1e-12, "120 fps: a sample every 1/120 s")
    l.point = pt(1, 1); _ = w.sample(devices: both)
    c.now += 0.01; l.point = pt(2, 1)
    check(w.sample(devices: both)?.moving == true, "a read that differs: moving")
    c.now += 0.05
    check(w.sample(devices: both)?.moving == true, "0.05 s later, still: still counts as moving")
    c.now += 0.06
    check(w.sample(devices: both)?.moving == false, "0.11 s after the last change: not moving")
    w.setGeometry(.rect(screen), fps: 0)
    check(w.frameInterval == 1, "a rate of 0 counts as 1 (no division by zero)")
}

// MARK: The frame-rate sampler's interval (StreamServer; the plan's Q4, and its review)

do {
    let tick = 0.030
    let f60 = 1.0 / 60, f120 = 1.0 / 120, f30 = 1.0 / 30, f24 = 1.0 / 24
    func every(_ moving: Bool, _ inside: Bool, _ watched: Bool, _ frame: Double) -> Double? {
        PointerWatch.samplerInterval(moving: moving, inside: inside, watched: watched, frameInterval: frame, tickInterval: tick)
    }
    check(every(true, true, true, f60) == f60 && every(true, true, true, f120) == f120,
          "moving over the source, a device sent it: a sample every frame at 60 and at 120 fps")
    check(every(false, true, true, f120) == nil, "still: the tick samples")
    check(every(true, false, true, f120) == nil,
          "moving off the source: the tick samples (every device is told the same inside: false, so a faster sample sends nothing)")
    check(every(true, true, false, f120) == nil, "nobody is sent it (the only device drives): the tick samples")
    check(every(true, true, true, f30) == nil && every(true, true, true, f24) == nil,
          "30 and 24 fps: the tick samples, as often as the sampler would or more")
    check(every(true, true, true, tick) == nil, "a frame interval equal to the tick's: the tick")
    check(every(true, true, true, tick - 0.0001) == tick - 0.0001, "a frame interval just under the tick's: the sampler")
    check(every(false, false, false, f120) == nil && every(true, false, false, f24) == nil, "none of it: the tick")
}

// MARK: A regular-mode window: its bounds and on-screen flag, re-read on sill.pointer

do {
    let c = Clock(), l = Location(), wins = Windows()
    let w = watch(clock: c, location: l, windows: wins)
    let first = CGRect(x: 0, y: 0, width: 400, height: 200)
    wins.set(7, .init(bounds: CGRect(x: 100, y: 0, width: 400, height: 200), onScreen: true))
    l.point = pt(200, 100)
    c.now = 100
    w.setGeometry(.window(7, first), fps: 60)
    check(waitUntil { wins.calls.count == 1 }, "a window geometry is re-read at once")
    check(waitUntil { w.sample(devices: both)?.x == 0.25 }, "the re-read's bounds replace the coordinator's")
    check(wins.labels.allSatisfy { $0 == "sill.pointer" }, "re-read on sill.pointer, never on the sampling thread: \(wins.labels)")
    for _ in 0..<5 { _ = w.sample(devices: both) }
    quiet()
    check(wins.calls.count == 1, "a still pointer, the clock still: no re-read")
    c.now = 100.05; l.point = pt(210, 100); _ = w.sample(devices: both)
    quiet()
    check(wins.calls.count == 1, "a move 0.05 s after the last re-read: none yet")
    c.now = 100.11; l.point = pt(220, 100); _ = w.sample(devices: both)
    check(waitUntil { wins.calls.count == 2 }, "a move 0.11 s after it: a re-read")
    c.now = 101.5; _ = w.sample(devices: both)
    quiet()
    check(wins.calls.count == 2, "still for 1.4 s: none")
    c.now = 102.2; _ = w.sample(devices: both)
    check(waitUntil { wins.calls.count == 3 }, "2 s after the last, still: one anyway")
    // Off screen (minimized, another Space): never inside.
    wins.set(7, .init(bounds: CGRect(x: 100, y: 0, width: 400, height: 200), onScreen: false))
    c.now = 104.3; _ = w.sample(devices: both)
    check(waitUntil { w.sample(devices: both)?.inside == false }, "a window off screen: outside")
    wins.set(7, .init(bounds: CGRect(x: 100, y: 0, width: 400, height: 200), onScreen: true))
    c.now = 106.4; _ = w.sample(devices: both)
    check(waitUntil { w.sample(devices: both)?.inside == true }, "back on screen: inside again")
    // Gone from the window server's list: off screen too, its bounds kept.
    wins.set(7, nil)
    c.now = 108.5; _ = w.sample(devices: both)
    check(waitUntil { w.sample(devices: both)?.inside == false }, "a window the list no longer has: outside")
    check(w.sample(devices: both)?.x == 0.3, "its last bounds kept (\(String(describing: w.sample(devices: both)?.x)))")
}

// A sample never waits for the window server: with the answer held back, samples go on at once and
// start no second re-read; a geometry change meanwhile is owed one, and an answer for a window no
// longer judged against is dropped.
do {
    let c = Clock(), l = Location(), wins = Windows()
    let w = watch(clock: c, location: l, windows: wins, after: 0)
    let gate = DispatchSemaphore(value: 0)
    wins.gate = gate
    wins.set(7, .init(bounds: CGRect(x: 0, y: 0, width: 100, height: 100), onScreen: false))
    wins.set(8, .init(bounds: CGRect(x: 0, y: 0, width: 400, height: 400), onScreen: true))
    l.point = pt(50, 50)
    w.setGeometry(.window(7, CGRect(x: 0, y: 0, width: 200, height: 200)), fps: 60)
    check(waitUntil { wins.calls.count == 1 }, "the re-read started")
    let t0 = Date()
    var samples = 0
    for i in 0..<50 { c.now += 0.03; l.point = pt(50 + CGFloat(i), 50); if w.sample(devices: both) != nil { samples += 1 } }
    check(Date().timeIntervalSince(t0) < 0.5 && samples == 50, "50 samples while the re-read is held: none waited")
    quiet()
    check(wins.calls.count == 1, "no second re-read while one runs (\(wins.calls.count))")
    w.setGeometry(.window(8, CGRect(x: 0, y: 0, width: 300, height: 300)), fps: 60)   // owed: 7's still runs
    w.setGeometry(.window(8, CGRect(x: 0, y: 0, width: 300, height: 300)), fps: 60)   // a poll in the same moment: still one owed
    quiet()
    check(wins.calls.count == 1, "a new window's re-read waits for the one running (\(wins.calls.count))")
    gate.signal()   // 7's answer comes back: dropped (8 is judged now); 8's re-read follows
    check(waitUntil { wins.calls.count == 2 }, "the owed re-read ran after the held one")
    gate.signal()
    check(waitUntil { w.sample(devices: both).map { $0.x == 0.2475 && $0.inside } == true },
          "8's bounds and on-screen flag, not 7's (\(String(describing: w.sample(devices: both))))")
    quiet()
    check(wins.calls == [7, 8], "7, then 8 once: \(wins.calls)")
    wins.gate = nil
}

// The re-read after a move is for the devices that are sent the pointer (the review, 2026-09-27): a
// device driving alone moves the pointer at every input and is sent nothing, so its moves start no
// re-read and only the 2 s one runs; a second device watching, or the Mac taking the pointer, starts
// them again; with no device at all, none after a move either.
do {
    let c = Clock(), l = Location(), wins = Windows()
    let w = watch(clock: c, location: l, windows: wins)
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
    wins.set(7, .init(bounds: bounds, onScreen: true))
    l.point = pt(100, 100); c.now = 100
    w.setGeometry(.window(7, bounds), fps: 60)
    check(waitUntil { wins.calls.count == 1 }, "the geometry's own re-read")
    // A drives: each input arrives, Sill posts it (the settle), and the pointer moves where it says.
    for i in 1...20 {
        c.now = 100 + Double(i) * 0.03
        w.inputArrived(from: A, movesPointer: true); w.sillMoved(); l.point = pt(100 + CGFloat(i) * 5, 100)
        _ = w.sample(devices: [A])
    }
    quiet()
    check(wins.calls.count == 1, "one device driving alone: 20 moves over 0.6 s start no re-read (\(wins.calls.count - 1))")
    check(w.sample(devices: [A])?.controller == .client(A), "…A drives")
    c.now = 102.1; _ = w.sample(devices: [A])
    check(waitUntil { wins.calls.count == 2 }, "…and the 2 s re-read runs anyway")
    // B joins and watches while A drives: A's next move starts a re-read.
    c.now = 102.25; w.inputArrived(from: A, movesPointer: true); w.sillMoved()
    c.now = 102.3; l.point = pt(300, 100)
    check(w.sample(devices: [A, B])?.controller == .client(A), "A still drives with B watching")
    check(waitUntil { wins.calls.count == 3 }, "a device watching: A's move re-reads the window")
    // The Mac takes the pointer from A, the only device: it is sent it, so the move re-reads.
    c.now = 102.5; _ = w.sample(devices: [A])
    c.now = 102.6; l.point = pt(320, 140)
    check(w.sample(devices: [A])?.controller == .mac, "the Mac moves it past the settle: the Mac's")
    check(waitUntil { wins.calls.count == 4 }, "the Mac moving it with a device watching: a re-read")
    // No device at all: moves start no re-read; the 2 s one runs.
    let c2 = Clock(), l2 = Location(), wins2 = Windows()
    let w2 = watch(clock: c2, location: l2, windows: wins2)
    wins2.set(9, .init(bounds: bounds, onScreen: true))
    l2.point = pt(10, 10); c2.now = 200
    w2.setGeometry(.window(9, bounds), fps: 60)
    check(waitUntil { wins2.calls.count == 1 }, "a second watch's own re-read")
    for i in 1...10 { c2.now = 200 + Double(i) * 0.03; l2.point = pt(10 + CGFloat(i) * 5, 10); _ = w2.sample(devices: []) }
    quiet()
    check(wins2.calls.count == 1, "no device: moves start no re-read (\(wins2.calls.count - 1))")
    c2.now = 202.1; _ = w2.sample(devices: [])
    check(waitUntil { wins2.calls.count == 2 }, "…the 2 s one runs")
}

// The same window again (a catalog poll) keeps what the last re-read said about it being on screen.
do {
    let c = Clock(), l = Location(), wins = Windows()
    let w = watch(clock: c, location: l, windows: wins)
    wins.set(5, .init(bounds: screen, onScreen: false))
    l.point = pt(10, 10)
    w.setGeometry(.window(5, screen), fps: 60)
    check(waitUntil { w.sample(devices: both)?.inside == false }, "off screen, as the re-read said")
    let gate = DispatchSemaphore(value: 0)
    wins.gate = gate
    w.setGeometry(.window(5, screen), fps: 60)   // its re-read held
    check(waitUntil { wins.calls.count == 2 }, "the same window re-read again")
    check(w.sample(devices: both)?.inside == false, "until it answers, the same window stays off screen")
    wins.set(5, .init(bounds: screen, onScreen: true))
    gate.signal()
    check(waitUntil { w.sample(devices: both)?.inside == true }, "then its answer")
    wins.gate = nil
    w.setGeometry(.rect(screen), fps: 60)
    check(w.sample(devices: both)?.inside == true, "a rectangle needs no window")
}

// MARK: The scripted pointer (TEST ONLY)

do {
    let c = Clock(), l = Location()
    let path = TestPointerPath(steps: [.init(t: 0.5, point: pt(756, 474.5)), .init(t: 1.0, point: pt(1134, 237.25)),
                                       .init(t: 1.5, point: pt(-40, 474.5)), .init(t: 2.0, point: pt(378, 711.75))])
    let w = watch(synthetic: true, path: path, clock: c, location: l)
    w.setGeometry(.rect(CGRect(x: 0, y: 0, width: 1512, height: 949)), fps: 60)
    c.now = 10
    check(w.sample(devices: both) == nil, "before the first step: no pointer, no sample (the path's clock starts here)")
    c.now = 10.49
    check(w.sample(devices: both) == nil, "0.49 s in: still none")
    c.now = 10.5
    let r1 = w.sample(devices: both)
    check(r1.map { $0.x == 0.5 && $0.y == 0.5 && $0.inside } == true, "at 0.5 s the first step (\(String(describing: r1)))")
    c.now = 11.0
    check(w.sample(devices: both).map { $0.x == 0.75 && $0.y == 0.25 } == true, "at 1.0 s the second")
    c.now = 11.6
    check(w.sample(devices: both)?.inside == false, "at 1.5 s outside the pattern")
    c.now = 12.3
    check(w.sample(devices: both).map { $0.x == 0.25 && $0.y == 0.75 } == true, "at 2.0 s the fourth")
    c.now = 20
    check(w.sample(devices: both).map { $0.x == 0.25 && $0.y == 0.75 } == true, "after the last step it stays")
    check(l.reads == 0, "the real pointer never read")
}

// A dry run's move, noted as Sill's, moves the scripted pointer; the newer of it and a step wins.
do {
    let c = Clock(), l = Location()
    let path = TestPointerPath(steps: [.init(t: 0, point: pt(100, 100)), .init(t: 1.0, point: pt(200, 100)),
                                       .init(t: 2.0, point: pt(300, 100)), .init(t: 3.0, point: pt(400, 100))])
    let w = watch(synthetic: true, path: path, clock: c, location: l)
    w.setGeometry(.rect(CGRect(x: 0, y: 0, width: 1000, height: 1000)), fps: 60)
    c.now = 50
    check(w.sample(devices: both)?.x == 0.1, "the path starts: its first step")
    c.now = 50.5
    w.inputArrived(from: A, movesPointer: true)
    w.sillMoved(to: pt(600, 600))
    let r = w.sample(devices: both)
    check(r.map { $0.x == 0.6 && $0.y == 0.6 } == true, "the dry run's move (\(String(describing: r)))")
    check(r?.controller == .client(A), "…is Sill's: the device keeps the pointer")
    c.now = 50.9
    check(w.sample(devices: both)?.x == 0.6, "no step since: it stays")
    c.now = 51.2
    check(w.sample(devices: both)?.x == 0.2, "the step at 1.0 s is newer: it wins")
    c.now = 51.95
    w.sillMoved(to: pt(700, 700))
    c.now = 52.1       // the step at 2.0 s (52.0) is newer than the move at 51.95
    check(w.sample(devices: both)?.x == 0.3, "a step due after the move wins, even read later")
    c.now = 52.2
    w.sillMoved(to: pt(800, 800))
    check(w.sample(devices: both)?.x == 0.8, "a move after the latest step wins")
    c.now = 53.05      // the step at 3.0 s (53.0) came due before this move, but no sample read it
    w.sillMoved(to: pt(900, 900))
    c.now = 53.1
    check(w.sample(devices: both)?.x == 0.9, "a step due before a move, read after it, loses to the move")
    check(l.reads == 0, "the real pointer never read")
}

// A move before the path's clock started: the first sample's steps are newer.
do {
    let c = Clock(), l = Location()
    let w = watch(synthetic: true, path: TestPointerPath(steps: [.init(t: 0, point: pt(10, 10))]), clock: c, location: l)
    w.setGeometry(.rect(CGRect(x: 0, y: 0, width: 100, height: 100)), fps: 60)
    w.sillMoved(to: pt(50, 50))
    c.now += 0.01
    check(w.sample(devices: both)?.x == 0.1, "a step at 0 s starts with the first sample, after the move")
}

// An empty path: no pointer until a dry run's move puts one there.
do {
    let c = Clock(), l = Location()
    let w = watch(synthetic: true, path: TestPointerPath(steps: []), clock: c, location: l)
    w.setGeometry(.rect(CGRect(x: 0, y: 0, width: 100, height: 100)), fps: 60)
    check(w.sample(devices: both) == nil, "no step, no move: no sample")
    w.sillMoved(to: pt(25, 75))
    check(w.sample(devices: both).map { $0.x == 0.25 && $0.y == 0.75 } == true, "a dry run's move puts it there")
    w.sillMoved()
    check(w.sample(devices: both)?.x == 0.25, "a scroll's note (no position) moves nothing")
}

// MARK: The path's file

func parsed(_ text: String) -> Result<TestPointerPath, TestPointerPath.Problem> { TestPointerPath.parse(text) }
do {
    check((try? parsed("").get())?.steps == [], "an empty file: no steps")
    let two = try? parsed("0.5 756 474.5\n1.0 1134 237.25\n").get()
    check(two?.steps == [.init(t: 0.5, point: pt(756, 474.5)), .init(t: 1.0, point: pt(1134, 237.25))], "two steps: \(String(describing: two))")
    let messy = try? parsed("# a path\n\n  0.5\t756  474.5  \r\n# more\n1 -40 2000\r\n").get()
    check(messy?.steps.count == 2 && messy?.steps.last?.point == pt(-40, 2000), "comments, blank lines, tabs, CRLF, outside values")
    check((try? parsed("1 1 1\n1 2 2\n").get())?.steps.count == 2, "equal times are fine")
    check(parsed("0.5 756") == .failure(.notStep(line: 1)), "two fields")
    check(parsed("0.5 756 474.5 1") == .failure(.notStep(line: 1)), "four fields")
    check(parsed("a b c") == .failure(.notStep(line: 1)), "not numbers")
    check(parsed("nan 1 2") == .failure(.notStep(line: 1)), "a time that is not finite")
    check(parsed("1 inf 2") == .failure(.notStep(line: 1)), "a point that is not finite")
    check(parsed("-0.1 1 2") == .failure(.notStep(line: 1)), "a negative time")
    check(parsed("# c\n\n1 2") == .failure(.notStep(line: 3)), "lines are counted with comments and blanks")
    check(parsed("1 1 1\n0.5 2 2") == .failure(.goesBack(line: 2)), "a time that goes back")
    check(TestPointerPath.Problem.notStep(line: 3).words == "line 3 is not \"T X Y\" (seconds, then points)", "the plan's words")
    let most = String(repeating: "1 2 3\n", count: 10_000)
    check((try? parsed(most).get())?.steps.count == 10_000, "10,000 steps are fine")
    check(parsed(most + "1 2 3\n") == .failure(.tooManySteps), "10,001 are not")
}
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pointer-watch-\(getpid())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let good = dir.appendingPathComponent("good").path
    FileManager.default.createFile(atPath: good, contents: Data("0.5 756 474.5\n1.0 1134 237.25\n1.5 -40 474.5\n2.0 378 711.75\n2.0 378 711.75\n".utf8))
    check((try? TestPointerPath.load(good).get())?.steps.count == 5, "a file of five steps")
    check(TestPointerPath.load(dir.appendingPathComponent("none").path) == .failure(.unreadable), "a missing file")
    // Exactly 1 MiB of steps and comments is fine; one byte more is not.
    let line = "1 2 3\n"
    let body = String(repeating: line, count: 1000)
    let pad = TestPointerPath.maxBytes - body.utf8.count
    let full = body + "#" + String(repeating: "x", count: pad - 2) + "\n"
    let exact = dir.appendingPathComponent("exact").path, over = dir.appendingPathComponent("over").path
    FileManager.default.createFile(atPath: exact, contents: Data(full.utf8))
    FileManager.default.createFile(atPath: over, contents: Data((full + " ").utf8))
    check(full.utf8.count == TestPointerPath.maxBytes, "the padded file is 1 MiB (\(full.utf8.count))")
    check((try? TestPointerPath.load(exact).get())?.steps.count == 1000, "a 1 MiB file is read")
    check(TestPointerPath.load(over) == .failure(.tooBig), "a byte over is refused")
    let bad = dir.appendingPathComponent("bad").path
    FileManager.default.createFile(atPath: bad, contents: Data("0.5 1 1\n1.0 2 2\n1.5 x 3\n".utf8))

    // MARK: The hooks and their lines
    typealias H = PointerTestHooks
    check(H.pointerPath(synthetic: true, environment: [:]).path == nil && H.pointerPath(synthetic: true, environment: [:]).line == nil,
          "no variable: nothing, and no line")
    check(H.pointerPath(synthetic: true, environment: ["SILL_TEST_POINTER_PATH": ""]).line == nil, "an empty variable: no line")
    let real = H.pointerPath(synthetic: false, environment: ["SILL_TEST_POINTER_PATH": good])
    check(real.path == nil && real.line == "SILL_TEST_POINTER_PATH=\(good) ignored: only a --synthetic host takes it.",
          "a real host ignores it: \(String(describing: real.line))")
    let taken = H.pointerPath(synthetic: true, environment: ["SILL_TEST_POINTER_PATH": good])
    check(taken.path?.steps.count == 5 && taken.line == "Test pointer: 5 steps from \(good); this host records input and never posts it.",
          "a synthetic host takes it: \(String(describing: taken.line))")
    let one = dir.appendingPathComponent("one").path
    FileManager.default.createFile(atPath: one, contents: Data("0.5 1 1\n".utf8))
    check(H.pointerPath(synthetic: true, environment: ["SILL_TEST_POINTER_PATH": one]).line == "Test pointer: 1 step from \(one); this host records input and never posts it.",
          "one step")
    let refused = H.pointerPath(synthetic: true, environment: ["SILL_TEST_POINTER_PATH": bad])
    check(refused.path == nil && refused.line == "SILL_TEST_POINTER_PATH=\(bad) ignored: line 3 is not \"T X Y\" (seconds, then points).",
          "a bad file is refused whole: \(String(describing: refused.line))")
    check(H.softwareEncoder(synthetic: true, environment: [:]) == (false, nil), "no variable: software only is off, silently")
    check(H.softwareEncoder(synthetic: true, environment: ["SILL_TEST_SOFTWARE_ENCODER": "1"])
          == (true, "Test encoder: software only (SILL_TEST_SOFTWARE_ENCODER); the hardware encoder is never probed."), "=1 on a synthetic host")
    check(H.softwareEncoder(synthetic: false, environment: ["SILL_TEST_SOFTWARE_ENCODER": "1"])
          == (false, "SILL_TEST_SOFTWARE_ENCODER ignored: only a --synthetic host takes it."), "a real host ignores it")
    check(H.softwareEncoder(synthetic: true, environment: ["SILL_TEST_SOFTWARE_ENCODER": "yes"])
          == (false, "SILL_TEST_SOFTWARE_ENCODER=yes ignored: 1 turns it on."), "another value is ignored")
}

print(failures == 0 ? "pointer-watch: all \(checks) checks passed" : "pointer-watch: \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
