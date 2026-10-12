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

// The first window: its stream goes to it from its first parameter sets, whatever they are.
do {
    let r = MainRouter(), a = Sink("A")
    r.expect(a)
    check(r.draws(into: a), "an expected window counts as drawn into")
    r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true); r.frame(f("a2"), isKeyframe: false)
    check(a.log == ["ps:A", "K:a1", "d:a2"], "the first window gets its stream: \(a.log)")
}

// Focus A → B with different parameter sets: old frames stay on A, B starts at its own keyframe.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.expect(a); r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.expect(b)
    r.frame(f("a2"), isKeyframe: false)                  // the old stream, still coming
    check(r.draws(into: a) && r.draws(into: b), "both drawn into during the switch")
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true); r.frame(f("b2"), isKeyframe: false)
    check(a.log == ["ps:A", "K:a1", "d:a2"], "A keeps only its own frames: \(a.log)")
    check(b.log == ["ps:B", "K:b1", "d:b2"], "B's first picture is its own keyframe: \(b.log)")
    check(!r.draws(into: a) && r.draws(into: b), "after the switch only B is drawn into")
}

// The old stream's repeated parameter sets (a periodic keyframe) during the switch: they stay on A.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.expect(a); r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    r.expect(b)
    r.parameterSets(ps("A")); r.frame(f("a5"), isKeyframe: true)
    check(b.log.isEmpty, "B never shows A's periodic keyframe: \(b.log)")
    check(a.log.suffix(2) == ["ps:A", "K:a5"], "A keeps it: \(a.log)")
}

// Same-size windows (identical sets): the switch waits for the host's word, then takes the next sets.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.expect(a); r.parameterSets(ps("S")); r.frame(f("a1"), isKeyframe: true)
    r.expect(b)
    r.parameterSets(ps("S")); r.frame(f("a9"), isKeyframe: true)     // before the host's list: A's
    check(b.log.isEmpty, "identical sets before the host switched stay on A")
    r.hostSwitched()
    r.parameterSets(ps("S")); r.frame(f("b1"), isKeyframe: true)
    check(b.log == ["ps:S", "K:b1"], "after the host switched, B takes the next sets: \(b.log)")
}

// Focusing the window already drawn into changes nothing; a later expect starts afresh.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.expect(a); r.parameterSets(ps("A"))
    r.expect(a)
    check(!r.draws(into: b), "re-focusing A expects nothing else")
    r.parameterSets(ps("A2")); r.frame(f("a2"), isKeyframe: true)
    check(a.log == ["ps:A", "ps:A2", "K:a2"], "A goes on: \(a.log)")
    r.hostSwitched()
    r.expect(b)
    r.parameterSets(ps("A2"))
    check(b.log.isEmpty, "a host word before this expect does not count for it")
}

// A session that ended: the next one's first window takes its first sets, even identical ones.
do {
    let r = MainRouter(), a = Sink("A"), d = Sink("D")
    r.expect(a); r.parameterSets(ps("S")); r.frame(f("a1"), isKeyframe: true)
    r.reset()
    r.expect(d)
    r.parameterSets(ps("S")); r.frame(f("d1"), isKeyframe: true)
    check(d.log == ["ps:S", "K:d1"] && a.log == ["ps:S", "K:a1"], "after reset the new first window gets its stream: D \(d.log)")
}

// The host switched by itself, its new stream already begun: the window takes it now, from the
// stream's last keyframe, and the old window keeps only its own frames.
do {
    var clock = 100.0
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.now = { clock }
    r.expect(a); r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    clock += 5
    r.parameterSets(ps("B")); r.frame(f("b1"), isKeyframe: true); r.frame(f("b2"), isKeyframe: false)
    clock += 0.5
    r.follow(b)
    r.frame(f("b3"), isKeyframe: false)
    check(b.log == ["ps:B", "K:b1", "d:b2", "d:b3"], "B follows at once from its keyframe: \(b.log)")
}
// …not begun yet (or long ago): the window waits for the next sets, which the host's switch admits.
do {
    var clock = 100.0
    let r = MainRouter(), a = Sink("A"), b = Sink("B")
    r.now = { clock }
    r.expect(a); r.parameterSets(ps("A")); r.frame(f("a1"), isKeyframe: true)
    clock += 5
    r.follow(b)
    r.frame(f("a2"), isKeyframe: false)
    check(b.log.isEmpty && a.log.last == "d:a2", "the old stream stays on A until the new sets: B \(b.log)")
    r.parameterSets(ps("A")); r.frame(f("b1"), isKeyframe: true)
    check(b.log == ["ps:A", "K:b1"], "B takes the next sets, even identical ones: \(b.log)")
}

// A → B → C quickly: only the last expected window takes the new stream; B gets nothing.
do {
    let r = MainRouter(), a = Sink("A"), b = Sink("B"), c = Sink("C")
    r.expect(a); r.parameterSets(ps("A"))
    r.expect(b); r.expect(c)
    r.parameterSets(ps("C")); r.frame(f("c1"), isKeyframe: true)
    check(b.log.isEmpty && c.log == ["ps:C", "K:c1"], "the last focus wins: B \(b.log), C \(c.log)")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
