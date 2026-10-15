import Foundation

var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

/// A window's layer: what it was given, in order.
final class Sink: FrameSink {
    let name: String
    var log: [String] = []
    init(_ name: String) { self.name = name }
    func apply(_ ps: ParameterSets) { log.append("ps:\(ps.sets.first.map { String(decoding: $0, as: UTF8.self) } ?? "")") }
    func enqueue(_ data: Data, isKeyframe: Bool) { log.append((isKeyframe ? "K:" : "d:") + String(decoding: data, as: UTF8.self)) }
}
func ps(_ s: String) -> ParameterSets { ParameterSets(nalUnitHeaderLength: 4, sets: [Data(s.utf8)]) }
func f(_ s: String) -> Data { Data(s.utf8) }
let w1 = StreamSource.window(1), w2 = StreamSource.window(2), w3 = StreamSource.window(3)

// The first stream goes to its source's window.
do {
    let r = MainRouter(), a = Sink("A")
    r.register(w1, a); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true); r.frame(f("a2"), isKeyframe: false)
    check(a.log == ["ps:A", "K:a1", "d:a2"], "the first window gets its stream: \(a.log)")
    check(r.draws(into: a), "A is drawn into")
}

// A → B: the old stream's frames still on their way stay on A; B starts at its own keyframe.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.register(w2, b); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.listed(active: w2)
    r.frame(f("a2"), isKeyframe: false)
    check(r.draws(into: a) && !r.draws(into: b), "A until B's stream begins")
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true); r.frame(f("b2"), isKeyframe: false)
    check(a.log == ["ps:A", "K:a1", "d:a2"], "A keeps only its own frames: \(a.log)")
    check(b.log == ["ps:B", "K:b1", "d:b2"], "B's first picture is its own keyframe: \(b.log)")
    check(!r.draws(into: a) && r.draws(into: b), "after the switch only B is drawn into")
}

// The old stream restarted (another size, a periodic keyframe) before the host's word: it stays on A.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.register(w2, b); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.parameterSets(ps("A-resized")); r.frame(f("a2"), isKeyframe: true)
    r.parameterSets(ps("A-resized")); r.frame(f("a3"), isKeyframe: true)
    check(b.log.isEmpty, "B never shows A's restarts: \(b.log)")
    check(a.log.suffix(4) == ["ps:A-resized", "K:a2", "ps:A-resized", "K:a3"], "A keeps its own restarts: \(a.log)")
}

// Identical sets (two windows of one size): only the host's list moves the stream; the same source
// listed again moves nothing.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.register(w2, b); r.listed(active: w1)
    r.parameterSets(ps("S")); r.frame(f("a1"), isKeyframe: true)
    r.listed(active: w1)
    r.parameterSets(ps("S")); r.frame(f("a9"), isKeyframe: true)
    check(b.log.isEmpty && a.log.last == "K:a9", "a list naming the same source moves nothing: B \(b.log)")
    r.listed(active: w2)
    r.parameterSets(ps("S")); r.frame(f("b1"), isKeyframe: true)
    check(b.log == ["ps:S", "K:b1"] && !a.log.contains("K:b1"), "B's first sets go to B: A \(a.log), B \(b.log)")
}

// The host streams a window not open here yet: once it opens, it takes the stream from its last
// keyframe, then goes on.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.listed(active: w2)
    r.parameterSets(ps("B")); r.frame(f("b0"), isKeyframe: true); r.frame(f("x"), isKeyframe: false)
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true); r.frame(f("b2"), isKeyframe: false)
    check(a.log == ["ps:A", "K:a1"], "A gets none of B's stream: \(a.log)")
    r.register(w2, b)
    r.frame(f("b3"), isKeyframe: false)
    check(b.log == ["ps:B", "K:b1", "d:b2", "d:b3"], "B takes it from its last keyframe: \(b.log)")
}

// A window opening for the listed source before its stream begins gets no old stream (2026-10-12:
// one app's picture shown in another's window), then its own.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.listed(active: w2)
    r.register(w2, b)
    r.frame(f("a2"), isKeyframe: false)
    check(b.log.isEmpty, "B gets nothing of A's stream: \(b.log)")
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true)
    check(b.log == ["ps:B", "K:b1"], "then its own: \(b.log)")
}

// …nor when the old window had closed (nothing drawn into while the switch was on its way).
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.register(w1, nil)
    r.listed(active: w2)
    r.register(w2, b)
    check(b.log.isEmpty, "B gets nothing of A's stream after A closed: \(b.log)")
}

// A window opening for a source the host does not stream gets nothing, whether or not the streamed
// source has a window here.
do {
    let r = MainRouter(), c = Sink("C")
    r.listed(active: w2)
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true)
    r.register(w3, c)
    check(c.log.isEmpty, "C gets none of B's stream: \(c.log)")
}
do {
    let r = MainRouter(), a = Sink("A"), c = Sink("C")
    r.register(w1, a); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.register(w3, c)
    r.frame(f("a2"), isKeyframe: false)
    check(c.log.isEmpty && a.log.last == "d:a2", "C gets nothing: \(c.log)")
}

// The streamed window closed here: nothing more goes to it.
do {
    let r = MainRouter(), a = Sink("A")
    r.register(w1, a); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.register(w1, nil)
    r.frame(f("a2"), isKeyframe: false)
    check(a.log == ["ps:A", "K:a1"] && !r.draws(into: a), "a closed window gets nothing: \(a.log)")
}

// A stream too large to replay (over gopLimit since its keyframe): a window opening late takes it
// from the next sets.
do {
    let r = MainRouter(), b = Sink("B")
    r.listed(active: w2)
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true)
    r.frame(Data(count: MainRouter.gopLimit + 1), isKeyframe: false)
    r.register(w2, b)
    check(b.log.isEmpty, "nothing replayed past the limit: \(b.log.count) entries")
    r.parameterSets(ps("B")); r.frame(f("b2"), isKeyframe: true)
    check(b.log == ["ps:B", "K:b2"], "B takes the next sets: \(b.log)")
}

// A session that ended: its windows are forgotten, and the next session's stream goes only to a
// window registered in it.
do {
    let r = MainRouter(), a = Sink("A"), d = Sink("D")
    r.register(w1, a); r.listed(active: w1)
    r.parameterSets(ps("S")); r.frame(f("a1"), isKeyframe: true)
    r.reset()
    r.frame(f("x0"), isKeyframe: false)
    r.listed(active: w1)
    r.parameterSets(ps("S")); r.frame(f("x1"), isKeyframe: true)
    check(a.log == ["ps:S", "K:a1"], "a window of the old session gets nothing: \(a.log)")
    r.register(w1, d)
    check(d.log == ["ps:S", "K:x1"], "the new session's window takes the stream: \(d.log)")
}

// A → B → A quickly: each stream to its own window, whatever order the main thread hears of it.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.register(w2, b); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.listed(active: w2); r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true)
    r.listed(active: w1); r.frame(f("b2"), isKeyframe: false)
    r.parameterSets(ps("A")); r.frame(f("a2"), isKeyframe: true)
    check(a.log == ["ps:A", "K:a1", "ps:A", "K:a2"], "A: \(a.log)")
    check(b.log == ["ps:B", "K:b1", "d:b2"], "B: \(b.log)")
}

// Side streams: the host starts a window's side stream as the main stream leaves it. Its first sets
// come while the main stream still draws there and are dropped; its frames are then drawn nowhere until
// its next sets, never against the main stream's sets (2026-10-12: a quarter-size picture).
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.register(w1, a); r.register(w2, b); r.listed(active: w1)
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.sideFrame(f("sx"), isKeyframe: false, into: b)
    check(b.log.isEmpty, "a side frame before its own sets is drawn nowhere: \(b.log)")
    r.listed(active: w2)
    r.sideParameterSets(ps("A-side"), into: a)                          // A's side stream starts, A still drawn
    r.sideFrame(f("as1"), isKeyframe: true, into: a)
    check(a.log == ["ps:A", "K:a1"], "the main stream's window takes no side sets or frames: \(a.log)")
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true)
    r.sideFrame(f("as2"), isKeyframe: false, into: a)
    check(a.log == ["ps:A", "K:a1"], "after the switch, A's side frames wait for their own sets: \(a.log)")
    r.sideParameterSets(ps("A-side"), into: a); r.sideFrame(f("as3"), isKeyframe: true, into: a)
    check(a.log.suffix(2) == ["ps:A-side", "K:as3"], "then they are drawn: \(a.log)")
    // The main stream back to A: its sets claim it, and the side stream's frames stop there.
    r.listed(active: w1); r.parameterSets(ps("A")); r.frame(f("a2"), isKeyframe: true)
    r.sideFrame(f("as4"), isKeyframe: false, into: a)
    check(a.log.suffix(2) == ["ps:A", "K:a2"], "the main stream's sets take the window back: \(a.log)")
    r.listed(active: w2); r.parameterSets(ps("B")); r.frame(f("b2"), isKeyframe: true)
    r.sideFrame(f("as5"), isKeyframe: false, into: a)
    check(a.log.suffix(2) == ["ps:A", "K:a2"], "left again, A waits for its side sets once more: \(a.log)")
    // B, left by the main stream, waits for its side sets too.
    r.sideFrame(f("bs1"), isKeyframe: false, into: b)
    check(!b.log.contains("d:bs1"), "B draws no side frame on the main stream's sets: \(b.log)")
}

// A closed window's claim goes with it: a new window whose feed takes the same address (the same
// object here) draws no side frame before its own sets.
do {
    let r = MainRouter(), a = Sink("A"), m = Sink("M")
    r.register(w2, m); r.register(w1, a); r.listed(active: w2)
    r.parameterSets(ps("M")); r.frame(f("m1"), isKeyframe: true)
    r.sideParameterSets(ps("A-side"), into: a); r.sideFrame(f("as1"), isKeyframe: true, into: a)
    r.register(w1, nil)
    r.register(w3, a)
    r.sideFrame(f("cs1"), isKeyframe: false, into: a)
    check(!a.log.contains("d:cs1"), "a reused feed draws no side frame before its own sets: \(a.log)")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
