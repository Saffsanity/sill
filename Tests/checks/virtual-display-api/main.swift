import Foundation
import ObjectiveC

// Checks VirtualDisplay's private API surface and how a method's type encoding, as the Objective-C
// runtime reports it, is matched against it (#87, #62): every encoding measured on Apple silicon or
// reported from Intel machines passes for its method, a BOOL return passes spelled "B" or "c" and
// nothing else does, and the offsets come off. Compiled with Sources/SillHost/VirtualDisplay.swift
// whole, as VirtualDisplayProbe compiles it. The decision is Runtime.method's own: each encoding is
// put on a method of a class this check makes at run time and judged by VirtualDisplay.methodProblem,
// which checkPrivateAPI asks too, and applySettings: is sent as init sends it
// (VirtualDisplay.applySettings(_:to:)) to three more such classes, typed B, c and C. Nothing here
// looks up a private class or makes a display.

var checks = 0
var failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { return }
    failures += 1
    print("FAIL: \(what())")
}

typealias Encoding = VirtualDisplay.TypeEncoding

/// An NSObject subclass made and registered at run time, so `Runtime.cls` finds it by name.
func makeClass(_ name: String, _ methods: [(selector: String, imp: IMP, types: String)] = []) -> AnyClass {
    guard let c = objc_allocateClassPair(NSObject.self, name, 0) else { fatalError("\(name): not made") }
    for m in methods {
        guard class_addMethod(c, NSSelectorFromString(m.selector), m.imp, m.types) else {
            fatalError("\(name) \(m.selector): not added")
        }
    }
    objc_registerClassPair(c)
    return c
}

// The methods `passes` adds are only looked up, as `checkPrivateAPI` looks up a CGVirtualDisplay's.
let neverCalled: @convention(block) (AnyObject) -> Void = { _ in fatalError("a looked-up method was called") }
let neverCalledIMP = imp_implementationWithBlock(neverCalled)
let lookedUp: AnyClass = makeClass("SillCheckLookedUp")
var methodsAdded = 0

/// Whether the runtime's `raw` encoding passes for `expected`: `Runtime.method`'s own decision
/// (`VirtualDisplay.methodProblem`) about a method the runtime reports as typed `raw`.
func passes(_ raw: String, _ expected: String) -> Bool {
    methodsAdded += 1
    let selector = "method\(methodsAdded):"
    guard class_addMethod(lookedUp, NSSelectorFromString(selector), neverCalledIMP, raw) else {
        fatalError("\(selector) typed \(raw): not added")
    }
    return VirtualDisplay.methodProblem(cls: "SillCheckLookedUp", selector: selector, encoding: expected) == nil
}

// --- What the runtime reported ------------------------------------------------------------------
// `method_getTypeEncoding` for every method on the surface, offsets and all, keyed "class selector",
// read on 2026-10-20 on an M2 Pro with macOS 27.0.1 (26A434) by a probe that only looks the methods
// up: natively, and under Rosetta, where all but applySettings: read the same.
let arm64macOS27: [String: String] = [
    "CGVirtualDisplayDescriptor init": "@16@0:8",
    "CGVirtualDisplayDescriptor setName:": "v24@0:8@16",
    "CGVirtualDisplayDescriptor setMaxPixelsWide:": "v20@0:8I16",
    "CGVirtualDisplayDescriptor setMaxPixelsHigh:": "v20@0:8I16",
    "CGVirtualDisplayDescriptor setSizeInMillimeters:": "v32@0:8{CGSize=dd}16",
    "CGVirtualDisplayDescriptor setVendorID:": "v20@0:8I16",
    "CGVirtualDisplayDescriptor setProductID:": "v20@0:8I16",
    "CGVirtualDisplayDescriptor setSerialNum:": "v20@0:8I16",
    "CGVirtualDisplayDescriptor setQueue:": "v24@0:8@16",
    "CGVirtualDisplayDescriptor setTerminationHandler:": "v24@0:8@?16",
    "CGVirtualDisplay initWithDescriptor:": "@24@0:8@16",
    "CGVirtualDisplay applySettings:": "B24@0:8@16",
    "CGVirtualDisplay displayID": "I16@0:8",
    "CGVirtualDisplayMode initWithWidth:height:refreshRate:": "@32@0:8I16I20d24",
    "CGVirtualDisplaySettings init": "@16@0:8",
    "CGVirtualDisplaySettings setHiDPI:": "v20@0:8I16",
    "CGVirtualDisplaySettings setModes:": "v24@0:8@16",
]
var x86RosettaMacOS27 = arm64macOS27
x86RosettaMacOS27["CGVirtualDisplay applySettings:"] = "c24@0:8@16"
// Reported, applySettings: alone, without offsets: an Intel Mac mini (Core i5-8500B, T2) with macOS
// 15.7.3 (24G419) printed "found c@:@" (#87), and an Intel machine (i9-12900KF) running macOS 26.7.1
// (25G241) through OpenCore passed the self test with an x86_64 build of 985a733 (build 585), which
// expected "B@:@" alone (#62; inferred: the encoding itself was not printed). Both passed every other
// method as written.
let reported: [(where: String, raw: String)] = [
    ("x86_64, macOS 15.7.3 (#87)", "c@:@"),
    ("x86_64, macOS 26.7.1 (#62)", "B@:@"),
]

let surface = VirtualDisplay.privateAPISurface
func key(_ e: (cls: String, selector: String, encoding: String)) -> String { "\(e.cls) \(e.selector)" }

// The surface is what was measured: one entry per method, each measured on both, none left over.
check(Set(surface.map(key)).count == surface.count, "the surface lists each method once")
check(Set(surface.map(key)) == Set(arm64macOS27.keys),
      "the surface's methods are the measured ones: \(Set(surface.map(key)).symmetricDifference(arm64macOS27.keys).sorted())")
for e in surface {
    check(Encoding.normalized(e.encoding) == e.encoding, "\(key(e)): written without offsets (\(e.encoding))")
    for (name, measured) in [("arm64, macOS 27.0.1", arm64macOS27), ("x86_64 under Rosetta, macOS 27.0.1", x86RosettaMacOS27)] {
        guard let raw = measured[key(e)] else { check(false, "\(key(e)): not measured on \(name)"); continue }
        check(passes(raw, e.encoding), "\(key(e)): \(raw) on \(name) passes for \(e.encoding)")
    }
}
let applySettings = surface.first { $0.cls == "CGVirtualDisplay" && $0.selector == "applySettings:" }
check(applySettings?.encoding == "B@:@", "applySettings: is written \"B@:@\" (got \(applySettings?.encoding ?? "nothing"))")
for r in reported {
    check(passes(r.raw, applySettings?.encoding ?? ""), "applySettings: \(r.raw) on \(r.where) passes")
}

// A BOOL return passes spelled "B" or "c", and the method is otherwise the same: nothing else passes.
check(Encoding.accepted("B@:@") == ["B@:@", "c@:@"], "\"B@:@\" takes \"B@:@\" and \"c@:@\": \(Encoding.accepted("B@:@"))")
for raw in ["B24@0:8@16", "c24@0:8@16", "B@:@", "c@:@"] {
    check(passes(raw, "B@:@"), "\(raw) passes for B@:@")
}
for raw in ["C24@0:8@16",   // unsigned char
            "b@:@", "i@:@", "I@:@", "s@:@", "q@:@", "v@:@", "@@:@", "*@:@",
            "B@:", "c@:", "B@:@@", "c@:@@", "B@:I", "c@:I",
            "cB@:@", "Bc@:@", "cc@:@", "BB@:@", "", "?"] {
    check(!passes(raw, "B@:@"), "\(raw) does not pass for B@:@")
}
// Only a return is a BOOL here: an argument, a void or an object return keeps its one spelling.
for expected in ["v@:I", "v@:@", "@@:", "@@:@", "I@:", "@@:IId", "v@:{CGSize=dd}", "v@:@?", "v@:B", "@@:B"] {
    check(Encoding.accepted(expected) == [expected], "\(expected) takes only itself: \(Encoding.accepted(expected))")
}
check(!passes("v@:c", "v@:B"), "a BOOL argument does not pass spelled c (none is on the surface)")
check(!passes("c@:I", "v@:I"), "a void return does not pass as c")
check(!passes("B@:I", "v@:I"), "a void return does not pass as B")
// Written "c", a return keeps that one spelling: the surface writes a BOOL return "B".
check(Encoding.accepted("c@:@") == ["c@:@"], "\"c@:@\" takes only itself: \(Encoding.accepted("c@:@"))")
check(!passes("B24@0:8@16", "c@:@"), "B24@0:8@16 does not pass for c@:@")
check(Encoding.accepted("") == [""], "an empty encoding takes only itself")

// applySettings: as init sends it: three classes made at run time, each answering applySettings:
// with what the NSNumber it is sent says, typed with a BOOL return spelled "B" or "c" or with an
// unsigned char ("C"), which is not a BOOL. The first two answer YES and NO through ObjCBool; the
// third is refused before it is called, with the line checkPrivateAPI would list.
let answer: @convention(block) (AnyObject, AnyObject) -> ObjCBool = { _, settings in
    ObjCBool((settings as? NSNumber)?.boolValue ?? false)
}
let answerIMP = imp_implementationWithBlock(answer)
let surfaceEncoding = applySettings?.encoding ?? ""
for (name, types, isBOOL) in [("SillCheckAnswersBool", "B24@0:8@16", true),
                              ("SillCheckAnswersSignedChar", "c24@0:8@16", true),
                              ("SillCheckAnswersUnsignedChar", "C24@0:8@16", false)] {
    let display = (makeClass(name, [("applySettings:", answerIMP, types)]) as! NSObject.Type).init()
    let problem = VirtualDisplay.methodProblem(cls: name, selector: "applySettings:", encoding: surfaceEncoding)
    let refusal = "\(name) applySettings: changed signature: expected B@:@ or c@:@, found C@:@"
    if isBOOL {
        check(problem == nil, "\(types): taken for \(surfaceEncoding) (\(problem ?? ""))")
    } else {
        check(problem == refusal, "\(types): refused for \(surfaceEncoding) as \"\(refusal)\" (\(problem ?? "taken"))")
    }
    for yes in [true, false] {
        do {
            let read = try VirtualDisplay.applySettings(NSNumber(value: yes), to: display)
            check(isBOOL && read == yes, "\(types): applySettings: answering \(yes ? "YES" : "NO") reads \(read)")
        } catch {
            check(!isBOOL && "\(error)" == refusal, "\(types): applySettings: \(error)")
        }
    }
}
// A method the class lacks, and a class that is not there, as checkPrivateAPI lists them.
for (cls, selector, encoding, line) in [
    ("SillCheckAnswersBool", "displayID", "I@:", "private class SillCheckAnswersBool does not respond to displayID"),
    ("SillCheckNoSuchClass", "applySettings:", "B@:@",
     "private class SillCheckNoSuchClass not found in CoreGraphics (API removed or renamed)"),
] {
    let problem = VirtualDisplay.methodProblem(cls: cls, selector: selector, encoding: encoding)
    check(problem == line, "\(cls) \(selector): \"\(line)\" (\(problem ?? "taken"))")
}

// The offsets come off, and nothing else does.
for (raw, types) in [("B24@0:8@16", "B@:@"), ("c24@0:8@16", "c@:@"), ("@16@0:8", "@@:"),
                     ("v32@0:8{CGSize=dd}16", "v@:{CGSize=dd}"), ("v24@0:8@?16", "v@:@?"),
                     ("@32@0:8I16I20d24", "@@:IId"), ("I16@0:8", "I@:"), ("v@:@", "v@:@"), ("", "")] {
    check(Encoding.normalized(raw) == types, "\(raw) without offsets is \(types): \(Encoding.normalized(raw))")
}
for raw in Array(arm64macOS27.values) + Array(x86RosettaMacOS27.values) {
    check(Encoding.normalized(Encoding.normalized(raw)) == Encoding.normalized(raw), "\(raw): normalized twice is normalized once")
}

// Headless Mac / closed-lid MacBook virtual Desktop fallback (issue #61):
typealias HDP = HeadlessDesktopPolicy
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true) == true,
      "headless with connected client, AppKit loop and API available needs virtual Desktop")
check(HDP.needsVirtualDesktop(hasDisplay: true, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true) == false,
      "Mac with a display already does not need a headless fallback display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 0, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true) == false,
      "0 connected clients does not create a headless display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: false, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true) == false,
      "without AppKit loop does not create a headless display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: true, apiAvailable: true, screenRecording: true, onConsole: true) == false,
      "synthetic test host does not create a headless display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: false, screenRecording: true, onConsole: true) == false,
      "when CGVirtualDisplay API is unavailable does not create a headless display")
// Without Screen Recording, never (VirtualStage.prepare's rule): SCShareableContent never returns in a process without it
// once a virtual display exists (measured 2026-09-22), and the catalog's look right after the display is made has no timeout.
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: false, onConsole: true) == false,
      "without Screen Recording no headless display is made")
// Never from a session another user has the screen from (off console): it would join their displays (#340's rule).
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: false) == false,
      "off console no headless display is made")

// The lid opened (or a monitor plugged in) while the fallback display exists: macOS moved every window
// onto it when the last real display went, so it goes at once and they come back, not when the last
// device leaves.
check(HDP.stillNeeded(physicalDisplays: 0) == true, "no real display online: the fallback display stays")
check(HDP.stillNeeded(physicalDisplays: 1) == false, "the lid opened, the built-in display back: the fallback display goes")
check(HDP.stillNeeded(physicalDisplays: 2) == false, "two monitors plugged in: the fallback display goes")

// macOS's own stand-in, a 1x 1920×1080 "Display" (vendor 'unkn', model 'virt') with the lid closed and nothing
// attached (seen on macOS 27, 2026-11-02): not a real display, so Sill's Retina one is made in its place.
check(HDP.isStandIn(vendor: 0x756e6b6e, model: 0x76697274) == true, "macOS's stand-in ('unkn', 'virt') is no real display")
check(HDP.isStandIn(vendor: 0x5111, model: 0x0001) == false, "Sill's own virtual display is not the stand-in")
check(HDP.isStandIn(vendor: 0x610, model: 0xa050) == false, "Apple's built-in panel is a real display")
check(HDP.isStandIn(vendor: 0x756e6b6e, model: 0x1234) == false, "an unknown vendor alone is not the stand-in")
// Which displays the Desktop may stream: a real one, else Sill's, else the stand-in.
check(HDP.pool([HDP.Kind.standIn, .sills, .real], kind: { $0 }) == [.real], "a real display online: it alone")
check(HDP.pool([HDP.Kind.standIn, .sills], kind: { $0 }) == [.sills], "the lid closed, Sill's Retina display made: it, not macOS's stand-in")
check(HDP.pool([HDP.Kind.standIn], kind: { $0 }) == [.standIn], "only macOS's stand-in (before Sill's is made): the stand-in")
check(HDP.pool([HDP.Kind](), kind: { $0 }) == [], "no display: none")
// While Sill's display exists and is not being released (the coordinator's keepsSills), the Desktop stays on it through
// a real screen's two seconds and moves once, when it goes (Watch).
check(HDP.pool([HDP.Kind.standIn, .sills, .real], kind: { $0 }, sillsFirst: true) == [.sills], "kept: Sill's display before a real one")
check(HDP.pool([HDP.Kind.real, .standIn], kind: { $0 }, sillsFirst: true) == [.real], "kept but not listed yet: the real one")
check(HDP.pool([HDP.Kind.standIn, .sills, .real], kind: { $0 }, sillsFirst: false) == [.real], "not kept: the real one first, as before")

// MARK: When Sill's display is made and when it goes (Watch; Noah's test of 2026-11-12)

typealias Watch = HDP.Watch
func near(_ a: Double?, _ b: Double?) -> Bool { a == b || (a != nil && b != nil && abs(a! - b!) < 1e-9) }
func waitUntil(_ m: Watch.Make) -> Double? { if case .wait(let t) = m { return t }; return nil }
func waitUntil(_ r: Watch.Release) -> Double? { if case .wait(let t) = r { return t }; return nil }

check(Watch.settle == 1 && Watch.settleCap == 3 && Watch.hysteresis == 2, "a second to settle, three at most, two seconds both ways")
// The watch's own bookkeeping.
do {
    var w = Watch()
    w.saw(real: 0, list: ["s:standIn:active"], at: 10)
    check(w.listChangedAt == nil && w.realGoneAt == nil && w.realBackAt == nil, "the first look records no change")
    w.saw(real: 0, list: ["s:standIn:active"], at: 11)
    check(w.listChangedAt == nil, "the same list again: no change")
    w.saw(real: 0, list: ["t:standIn:active"], at: 12)
    check(near(w.listChangedAt, 12), "another list, the same count: a change, seen by a look alone")
    w.saw(real: 1, list: ["m:real:active"], at: 13)
    check(near(w.realBackAt, 13) && w.realGoneAt == nil, "a real screen back: when")
    w.saw(real: 0, list: ["s:standIn:active"], at: 14)
    check(near(w.realGoneAt, 14) && near(w.realBackAt, 13), "the real screen gone: when")
    w.changed(at: 15)
    check(near(w.listChangedAt, 15), "macOS's callback is a change before any look")
    w.cameBack(at: 16)
    check(near(w.cameBackAt, 16), "back on the console, unlocked or woken: when")
    var first = Watch()
    first.saw(real: 2, list: ["a:real:active", "b:real:active"], at: 1)
    check(first.realBackAt == nil && first.realGoneAt == nil && first.real == 2, "a first look with screens: no transition")
}
// The make rule at its edges: a second's quiet after the later of the list's change, the return and the first look;
// two seconds without a real screen after the later of its going and the return; three seconds at most.
do {
    var w = Watch()
    w.saw(real: 0, list: ["s:standIn:active"], at: 0)
    check(w.make(wantedSince: 100, now: 100) == .wait(until: 101), "a screenless Mac, steady: a second after the first look")
    check(w.make(wantedSince: 100, now: 100.999) == .wait(until: 101), "…not before")
    check(w.make(wantedSince: 100, now: 101) == .make, "…then made")
    w.saw(real: 1, list: ["m:real:active"], at: 50)
    check(w.make(wantedSince: 100, now: 200) == .no, "a real screen works: never made")
    var lid = Watch()
    lid.saw(real: 1, list: ["builtin:real:active"], at: 0)
    lid.saw(real: 0, list: ["s:standIn:active"], at: 90)                 // the lid closed, nothing attached
    check(waitUntil(lid.make(wantedSince: 90.2, now: 90.2)) == 92, "the built-in screen gone 0.2 s ago: two seconds after it went")
    check(waitUntil(lid.make(wantedSince: 95, now: 95)) == 96, "gone 5 s ago: a second after the first look")
    var back = lid
    back.cameBack(at: 94)
    check(waitUntil(back.make(wantedSince: 94.3, now: 94.3)) == 96, "back on the console at 94: two seconds after it")
    var busy = lid
    busy.changed(at: 99)
    check(waitUntil(busy.make(wantedSince: 98, now: 99)) == 100, "the list changed at 99: a second after it")
    busy.changed(at: 100.9)
    check(waitUntil(busy.make(wantedSince: 98, now: 100.9)) == 101, "still changing: three seconds after the first look at most")
    check(busy.make(wantedSince: 98, now: 101) == .make, "…then made on that look")
}
// The release rule: two seconds after a real screen came back, the lid closed and a device connected too.
do {
    var w = Watch()
    w.saw(real: 0, list: ["s:sills:active"], at: 0)
    check(w.release(now: 100) == .keep, "no real screen: kept")
    w.saw(real: 1, list: ["m:real:active", "s:sills:active"], at: 120)
    check(w.release(now: 120) == .wait(until: 122), "a monitor back: two seconds")
    check(w.release(now: 121.999) == .wait(until: 122), "…not before")
    check(w.release(now: 122) == .release, "…then it goes")
    w.saw(real: 0, list: ["s:sills:active"], at: 121)
    check(w.release(now: 122) == .keep, "the monitor gone again within the two seconds: kept")
}

// The coordinator's part, modelled: macOS's callback looks at every change of the displays; the lock's changes say when
// this session came back; a Desktop that wants Sill's display looks, waits as `make` says, looks again then, and makes
// it on that look (the gate, on the console with a device, asked at every look); once made, `release` is asked at
// every change and at the end of each wait it names. The display the model makes is listed as Sill's.
struct Screens { let at: Double; let real: Int; let list: [String] }
func replay(screens: [Screens], cameBack: [Double], onConsole: (Double) -> Bool, wanted: Double, until end: Double)
    -> (made: Double?, released: Double?, makes: Int) {
    var w = Watch()
    var made: Double? = nil, released: Double? = nil, makes = 0
    var i = 0
    var backs = cameBack.sorted()
    func seen() -> (real: Int, list: [String]) {
        (screens[i].real, screens[i].list + (made != nil && released == nil ? ["sills:active"] : []))
    }
    func look(_ t: Double) { let s = seen(); w.saw(real: s.real, list: s.list, at: t) }
    look(screens[0].at)
    var wakeUp: Double? = wanted, releaseAt: Double? = nil
    func askRelease(_ t: Double) {
        guard made != nil, released == nil else { return }
        switch w.release(now: t) {
        case .release: released = t; releaseAt = nil; w.changed(at: t); look(t)
        case .wait(let u): releaseAt = u
        case .keep: releaseAt = nil
        }
    }
    // One event at a time, in time order: a return, then a change, then the Desktop's look, then the release's.
    while true {
        let change = i + 1 < screens.count ? screens[i + 1].at : Double.infinity
        let back = backs.first ?? Double.infinity
        let next = min(change, back, wakeUp ?? Double.infinity, releaseAt ?? Double.infinity)
        guard next <= end else { break }
        if back == next { w.cameBack(at: next); backs.removeFirst(); continue }
        if change == next { i += 1; w.changed(at: next); look(next); askRelease(next); continue }
        if wakeUp == next {
            look(next)
            guard onConsole(next) else { wakeUp = nil; continue }
            switch w.make(wantedSince: wanted, now: next) {
            case .no: wakeUp = nil
            case .wait(let v): wakeUp = v
            case .make: made = next; makes += 1; wakeUp = nil; w.changed(at: next); look(next)
            }
            continue
        }
        if releaseAt == next { releaseAt = nil; look(next); askRelease(next) }
    }
    return (made, released, makes)
}

// Tonight's sequence, from Sill.log (seconds after 01:10:00, 2026-11-12): the lid closed, two monitors; off console at
// 48.598 (the off-console view on); the stand-in alone from 53.743 (the Desktop followed it to 1920×1080); back on the
// console, unlocked, at 54.688; locked at 55.040, when the Desktop asked for the display (made at 55.203 before this);
// the monitors back a second after the return. Nothing may be made.
let two = ["a:real:active", "b:real:active"], standIn = ["s:standIn:active"]
func tonight(monitorsBack: Double) -> (made: Double?, released: Double?, makes: Int) {
    replay(screens: [Screens(at: 0, real: 2, list: two), Screens(at: 53.743, real: 0, list: standIn),
                     Screens(at: monitorsBack, real: 2, list: two)],
           cameBack: [54.688], onConsole: { $0 < 48.598 || $0 >= 54.688 }, wanted: 55.040, until: 70)
}
let night = tonight(monitorsBack: 55.688)
check(night.made == nil && night.makes == 0, "tonight: the monitors back a second after the return: nothing made (\(String(describing: night.made)))")
do {
    var w = Watch()
    w.saw(real: 2, list: two, at: 0)
    w.changed(at: 53.743); w.saw(real: 0, list: standIn, at: 53.743)
    w.cameBack(at: 54.688)
    check(near(waitUntil(w.make(wantedSince: 55.040, now: 55.040)), 56.688), "tonight at 55.040, the instant the old rule made it: wait until 56.688")
}
let slower = tonight(monitorsBack: 56.6)
check(slower.made == nil, "the monitors back 1.9 s after the return: still nothing made")
let late = tonight(monitorsBack: 57.5)
check(near(late.made, 56.688) && near(late.released, 59.5) && late.makes == 1,
      "the monitors back 2.8 s after the return: made at 56.688, gone two seconds after they came (\(String(describing: late.made)), \(String(describing: late.released)))")
// #340's off-console view at the switch: the Desktop streams off console, and the stand-in alone while off console.
let viewed = replay(screens: [Screens(at: 0, real: 2, list: two), Screens(at: 53.743, real: 0, list: standIn)],
                    cameBack: [], onConsole: { $0 < 48.598 }, wanted: 53.9, until: 70)
check(viewed.made == nil, "off console (the view on), the stand-in alone: nothing made")
// A Mac with truly no screen: the stand-in alone and steady; the display a second after the Desktop asked.
let bare = replay(screens: [Screens(at: 0, real: 0, list: standIn)], cameBack: [], onConsole: { _ in true }, wanted: 100.3, until: 110)
check(near(bare.made, 101.3) && bare.released == nil, "a screenless Mac: made a second after the Desktop asked (\(String(describing: bare.made)))")
let bareLocked = replay(screens: [Screens(at: 0, real: 0, list: standIn)], cameBack: [], onConsole: { _ in true }, wanted: 100.3, until: 110)
check(near(bareLocked.made, 101.3), "…locked (the lock screen on the console): the same")
let bareOff = replay(screens: [Screens(at: 0, real: 0, list: standIn)], cameBack: [], onConsole: { _ in false }, wanted: 100.3, until: 110)
check(bareOff.made == nil, "…off console: none")
// A monitor back with the lid closed and a device connected: gone two seconds after, locked or not.
let monitor = replay(screens: [Screens(at: 0, real: 0, list: standIn), Screens(at: 120, real: 1, list: ["m:real:active"])],
                     cameBack: [], onConsole: { _ in true }, wanted: 100.3, until: 130)
check(near(monitor.made, 101.3) && near(monitor.released, 122), "a monitor back at 120: gone at 122 (\(String(describing: monitor.released)))")
// A monitor that flickers every half second from 130 to 136, then stays: kept through the flicker, gone at 138.
var flicker = [Screens(at: 0, real: 0, list: standIn)]
for k in 0..<12 { flicker.append(Screens(at: 130 + Double(k) * 0.5, real: k % 2 == 0 ? 1 : 0, list: k % 2 == 0 ? ["m:real:active"] : standIn)) }
flicker.append(Screens(at: 136, real: 1, list: ["m:real:active"]))
let flickered = replay(screens: flicker, cameBack: [], onConsole: { _ in true }, wanted: 100.3, until: 145)
check(near(flickered.made, 101.3) && near(flickered.released, 138) && flickered.makes == 1,
      "a monitor flickering 130–136: kept through it, gone at 138 (\(String(describing: flickered.released)))")
// A monitor flickering while the Desktop waits for the display: decided at the cap (three seconds), once.
var early = [Screens(at: 0, real: 0, list: standIn)]
for k in 0..<14 { early.append(Screens(at: 139.5 + Double(k) * 0.5, real: k % 2 == 0 ? 1 : 0, list: k % 2 == 0 ? ["m:real:active"] : standIn)) }
let waited = replay(screens: early, cameBack: [], onConsole: { _ in true }, wanted: 140.2, until: 150)
check(waited.makes <= 1 && (waited.made == nil || near(waited.made, 143.2)), "a monitor flickering while the Desktop waits: decided at 143.2, once (\(String(describing: waited.made)))")
check(waited.released == nil, "…and nothing made and removed in a loop while it flickers")

// TEST ONLY: SILL_TEST_HEADLESS, a test host's scripted list, and who takes it (not SILL_TEST_DISPLAYS, the Desktop's stops').
let parsed = HDP.testHeadlessList("real\nreal asleep # a comment\nstandin\nlid closed\nbogus line\n# real\n")
check(parsed.displays == [HDP.TestDisplay(kind: .real, active: true), HDP.TestDisplay(kind: .real, active: false),
                          HDP.TestDisplay(kind: .standIn, active: true)] && parsed.lidClosed,
      "the scripted list: a screen, one asleep, the stand-in, the lid closed; comments and the rest left out")
check(HDP.testHeadlessList("").displays.isEmpty && !HDP.testHeadlessList("").lidClosed, "an empty file: no display, the lid open")
check(HDP.testHeadless(environment: ["SILL_TEST_HEADLESS": "/tmp/d"], testHost: true).path == "/tmp/d", "a test host takes the file")
check(HDP.testHeadless(environment: ["SILL_TEST_DISPLAYS": "/tmp/d"], testHost: true) == (nil, nil), "the Desktop stops' variable is not this one")
let refused = HDP.testHeadless(environment: ["SILL_TEST_HEADLESS": "/tmp/d"], testHost: false)
check(refused.path == nil && refused.line == "SILL_TEST_HEADLESS ignored: only a --synthetic test host takes it, never Sill.app.", "any other host ignores it, with one line")
check(HDP.testHeadless(environment: [:], testHost: true) == (nil, nil), "unset: nothing")
// Which real displays keep Sill's display from being made (the review of 2026-11-09): a display only asleep is
// online and keeps its windows, and 0.6.0's display wake (#151) turns it on as a device connects, so it counts; with
// the lid closed only the active ones count, a monitor asleep there being none (#298).
check(HDP.realDisplays(active: 0, online: 1, lidClosed: false) == 1, "the lid open, its screen asleep: counted (the wake turns it on)")
check(HDP.realDisplays(active: 0, online: 2, lidClosed: false) == 2, "a Mac mini, its two monitors asleep: counted")
check(HDP.realDisplays(active: 1, online: 1, lidClosed: false) == 1, "a monitor awake: counted")
check(HDP.realDisplays(active: 0, online: 0, lidClosed: false) == 0, "a Mac with no monitor: none")
check(HDP.realDisplays(active: 0, online: 2, lidClosed: true) == 0, "the lid closed, its monitors asleep: none (#298)")
check(HDP.realDisplays(active: 1, online: 2, lidClosed: true) == 1, "the lid closed, a monitor awake: counted")
check(HDP.realDisplays(active: 0, online: 0, lidClosed: true) == 0, "the lid closed, nothing attached: none")
check(!HDP.stillNeeded(physicalDisplays: HDP.realDisplays(active: 0, online: 1, lidClosed: false)),
      "a screen asleep with the lid open, or a Mac mini's monitor asleep: no display made")
check(HDP.stillNeeded(physicalDisplays: HDP.realDisplays(active: 0, online: 1, lidClosed: true)),
      "a monitor asleep with the lid closed: Sill's display made (#298)")
// Its size: the MacBook's own screen as Sill last saw it, so windows keep their places (Noah's choice, 2026-11-02).
check(HDP.desktopDimensions(builtIn: (1800, 1169), viewportWidth: 1366, viewportHeight: 1024) == HDP.Dimensions(widthPt: 1800, heightPt: 1168, scale: 2),
      "the built-in screen last seen at 1800×1169 pt: 1800×1168 @2× (even), not the iPad's size")
check(HDP.desktopDimensions(builtIn: (1512, 982), viewportWidth: nil, viewportHeight: nil) == HDP.Dimensions(widthPt: 1512, heightPt: 982, scale: 2),
      "a 14-inch MacBook Pro's default 1512×982 pt: kept")
check(HDP.desktopDimensions(builtIn: nil, viewportWidth: 1366, viewportHeight: 1024) == HDP.Dimensions(widthPt: 1366, heightPt: 1024, scale: 2),
      "the built-in screen never seen (a Mac mini): the viewport, as before")

check(HDP.desktopDimensions(viewportWidth: nil, viewportHeight: nil) == HDP.Dimensions(widthPt: 1920, heightPt: 1080, scale: 2),
      "no viewport defaults to 1920×1080 @2×")
check(HDP.desktopDimensions(viewportWidth: 1366, viewportHeight: 1024) == HDP.Dimensions(widthPt: 1366, heightPt: 1024, scale: 2),
      "iPad Pro viewport 1366×1024 kept")
check(HDP.desktopDimensions(viewportWidth: 1195, viewportHeight: 835) == HDP.Dimensions(widthPt: 1194, heightPt: 834, scale: 2),
      "odd viewport dimensions rounded down to even points")
check(HDP.desktopDimensions(viewportWidth: 400, viewportHeight: 300) == HDP.Dimensions(widthPt: 1024, heightPt: 640, scale: 2),
      "small viewport clamped to minimum 1024×640")
check(HDP.desktopDimensions(viewportWidth: 6000, viewportHeight: 4000) == HDP.Dimensions(widthPt: 3840, heightPt: 2400, scale: 2),
      "huge viewport clamped to maximum 3840×2400")

print("virtual-display-api: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
