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
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true, guardHolds: false, switchOn: true) == true,
      "headless with connected client, AppKit loop and API available needs virtual Desktop")
check(HDP.needsVirtualDesktop(hasDisplay: true, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true, guardHolds: false, switchOn: true) == false,
      "Mac with a display already does not need a headless fallback display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 0, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true, guardHolds: false, switchOn: true) == false,
      "0 connected clients does not create a headless display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: false, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true, guardHolds: false, switchOn: true) == false,
      "without AppKit loop does not create a headless display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: true, apiAvailable: true, screenRecording: true, onConsole: true, guardHolds: false, switchOn: true) == false,
      "synthetic test host does not create a headless display")
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: false, screenRecording: true, onConsole: true, guardHolds: false, switchOn: true) == false,
      "when CGVirtualDisplay API is unavailable does not create a headless display")
// Without Screen Recording, never (VirtualStage.prepare's rule): SCShareableContent never returns in a process without it
// once a virtual display exists (measured 2026-09-22), and the catalog's look right after the display is made has no timeout.
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: false, onConsole: true, guardHolds: false, switchOn: true) == false,
      "without Screen Recording no headless display is made")
// Never from a session another user has the screen from (off console): it would join their displays (#340's rule).
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: false, guardHolds: false, switchOn: true) == false,
      "off console no headless display is made")
// Never while the guard for #380 holds (DisplayMakeGuard: two runs in a row ended while making a display).
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true, guardHolds: true, switchOn: true) == false,
      "while the guard holds no headless display is made")
// Never while the Mac's user has it off (HostConfig.headlessDisplay: Settings › Virtual Display's "A Mac with no screen", on by
// default; the CLI's --no-headless-display): after #380's stops, or with a monitor #333's display changes turn off.
check(HDP.needsVirtualDesktop(hasDisplay: false, clientCount: 1, appKitLoop: true, synthetic: false, apiAvailable: true, screenRecording: true, onConsole: true, guardHolds: false, switchOn: false) == false,
      "with its switch off no headless display is made")
check(HDP.switchedOffLine.hasPrefix("Headless display: ") && HDP.switchedOffLine.contains("turned off")
      && HDP.switchedOffRemovedLine.hasPrefix("Headless display: ") && HDP.switchedOffRemovedLine.contains("removed Sill's display"),
      "the switch's two lines are Headless display lines (Sill.log's grep), each saying what it did")

// The lid opened (or a monitor plugged in) while the fallback display exists: macOS moved every window
// onto it when the last real display went, so it goes at once and they come back, not when the last
// device leaves.
check(HDP.stillNeeded(physicalDisplays: 0) == true, "no real display online: the fallback display stays")
check(HDP.stillNeeded(physicalDisplays: 1) == false, "the lid opened, the built-in display back: the fallback display goes")
check(HDP.stillNeeded(physicalDisplays: 2) == false, "two monitors plugged in: the fallback display goes")

// What a display is to these rules, by its role (DesktopDisplays.role, the Desktop stops' rule), never by its vendor
// alone (#200's `displayKind` took any 0x5111 display for Sill's Desktop display; the assessment of 2026-11-18,
// defect 3). The identities as CoreGraphics reads them on this Mac (2026-11-12): macOS's stand-in, a 1x 1920×1080
// "Display" ('unkn', 'virt'), the stage's display (0x5111, 1), Sill's Desktop display (0x5111, 2), Apple's built-in
// panel (0x610, 0xa050), and a display that has gone (0xFFFFFFFF, online -1).
func kindOf(vendor: UInt32, product: UInt32, madeByStage: Bool = false, online: Bool = true) -> HDP.Kind {
    HDP.kind(DesktopDisplays.role(vendor: vendor, product: product, madeByStage: madeByStage), online: online)
}
check(kindOf(vendor: 0x756e6b6e, product: 0x76697274) == .standIn, "macOS's stand-in ('unkn', 'virt') is no real display")
check(kindOf(vendor: 0x756e6b6e, product: 0x1234) == .real, "an unknown vendor alone is not the stand-in")
check(kindOf(vendor: 0x610, product: 0xa050) == .real, "Apple's built-in panel is a real display")
check(kindOf(vendor: 0x5111, product: 0x0002) == .sills, "Sill's Desktop display (product 2) is Sill's")
check(kindOf(vendor: 0x5111, product: 0x0001) == .stage, "the stage's display (product 1) is the stage's, not Sill's Desktop display")
check(kindOf(vendor: 0x5111, product: 0x0001, madeByStage: true) == .stage, "…made by this run's stage too")
check(kindOf(vendor: 0xFFFF_FFFF, product: 0xFFFF_FFFF, madeByStage: true) == .stage,
      "a stage display that has gone and still reads in a look: the stage's (no real screen)")
check(kindOf(vendor: 0xFFFF_FFFF, product: 0xFFFF_FFFF, madeByStage: true, online: false) == .gone, "…and gone, once offline")
check(kindOf(vendor: 0x610, product: 0xa050, online: false) == .gone, "a monitor unplugged that an old look lists: gone, no real screen")
check(kindOf(vendor: 0x5111, product: 0x0002, online: false) == .gone, "Sill's own display gone: gone")
check(kindOf(vendor: 0x756e6b6e, product: 0x76697274, online: false) == .gone, "the stand-in gone: gone")
check(kindOf(vendor: 0, product: 0) == .real && kindOf(vendor: 0, product: 0, madeByStage: true) == .stage,
      "vendor 0: a display of its own, unless the stage made that ID (DesktopDisplays.role)")
// Which displays the Desktop may stream: a real one, else Sill's, else the stand-in; never the stage's display or one gone.
check(HDP.pool([HDP.Kind.standIn, .sills, .real], kind: { $0 }) == [.real], "a real display online: it alone")
check(HDP.pool([HDP.Kind.standIn, .sills], kind: { $0 }) == [.sills], "the lid closed, Sill's Retina display made: it, not macOS's stand-in")
check(HDP.pool([HDP.Kind.standIn], kind: { $0 }) == [.standIn], "only macOS's stand-in (before Sill's is made): the stand-in")
check(HDP.pool([HDP.Kind](), kind: { $0 }) == [], "no display: none")
check(HDP.pool([HDP.Kind.stage, .standIn], kind: { $0 }) == [.standIn], "the stage's display and the stand-in: the stand-in, never the stage's")
check(HDP.pool([HDP.Kind.stage, .sills], kind: { $0 }) == [.sills], "the stage's display beside Sill's Desktop display: Sill's")
check(HDP.pool([HDP.Kind.stage, .sills], kind: { $0 }, sillsFirst: true) == [.sills], "…kept, the same")
check(HDP.pool([HDP.Kind.stage], kind: { $0 }) == [], "the stage's display alone: no display for the Desktop (it holds a window alone)")
check(HDP.pool([HDP.Kind.gone, .sills], kind: { $0 }) == [.sills], "a gone display listed beside Sill's: Sill's, the gone one no real screen")
check(HDP.pool([HDP.Kind.gone, .standIn], kind: { $0 }) == [.standIn], "a gone display beside the stand-in: the stand-in")
check(HDP.pool([HDP.Kind.gone], kind: { $0 }) == [], "only a gone display: none")
check(HDP.pool([HDP.Kind.real, .stage, .gone, .real], kind: { $0 }) == [.real, .real], "two screens among the rest: both, in order")
// While Sill's display exists and is not being released (the coordinator's keepsSills), the Desktop stays on it through
// a real screen's two seconds and moves once, when it goes (Watch).
check(HDP.pool([HDP.Kind.standIn, .sills, .real], kind: { $0 }, sillsFirst: true) == [.sills], "kept: Sill's display before a real one")
check(HDP.pool([HDP.Kind.real, .standIn], kind: { $0 }, sillsFirst: true) == [.real], "kept but not listed yet: the real one")
check(HDP.pool([HDP.Kind.standIn, .sills, .real], kind: { $0 }, sillsFirst: false) == [.real], "not kept: the real one first, as before")
// Sill's display as the Virtual Desktop (phase 2b, VirtualDesktopLife's role): one more screen after the real ones, so the
// Desktop may stream it beside them (its stop the last); with no real one, or kept as the headless display, as before.
check(HDP.pool([HDP.Kind.sills, .standIn, .real, .stage, .gone, .real], kind: { $0 }, virtualDesktop: true) == [.real, .real, .sills],
      "the Virtual Desktop: the real screens, then Sill's display, never the stand-in, the stage's or a gone one")
check(HDP.pool([HDP.Kind.sills, .standIn], kind: { $0 }, virtualDesktop: true) == [.sills], "…no real screen: Sill's alone, as before")
check(HDP.pool([HDP.Kind.real, .standIn], kind: { $0 }, virtualDesktop: true) == [.real], "…Sill's not listed yet: the real one")
check(HDP.pool([HDP.Kind.sills, .real], kind: { $0 }, sillsFirst: true, virtualDesktop: true) == [.sills],
      "…kept as the headless display (sillsFirst): Sill's alone, as before")
check(HDP.pool([HDP.Kind.standIn], kind: { $0 }, virtualDesktop: true) == [.standIn], "…only the stand-in: the stand-in")
check(HDP.pool([HDP.Kind.sills, .real], kind: { $0 }, virtualDesktop: false) == [.real], "not the Virtual Desktop: the real one alone, as before")

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

// The coordinator's part, modelled: macOS's callback looks at every change of the displays (the screens' sleep and wake
// among them, as NSWorkspace says them); the lock's changes say when this session came back; a Desktop that wants
// Sill's display looks, waits as `make` says, looks again then, and makes it on that look (the gate, on the console with
// a device, asked at every look); a look that finds the screens awake after asleep asks again for a Desktop with no real
// screen and no Sill's display (`screensWoke`, `desktopAgainAtWake`), unless a wait is under way; once made, `release`
// is asked at every change and at the end of each wait it names. The display the model makes is listed as Sill's.
struct Screens {
    let at: Double; let real: Int; let list: [String]; var asleep = false
    /// A look as the coordinator takes it from a Mac: the real displays active and online, the lid, whether macOS said
    /// the screens sleep, and whether macOS's stand-in is listed working (`standIn`); `real` and `asleep` by the rule's
    /// own functions.
    static func mac(at: Double, active: Int, online: Int, lidClosed: Bool, said: Bool, standIn: Bool = false, list: [String]) -> Screens {
        Screens(at: at, real: HDP.realDisplays(active: active, online: online, lidClosed: lidClosed), list: list,
                asleep: HDP.screensAsleep(said: said, active: active + (standIn ? 1 : 0)))
    }
}
func replay(screens: [Screens], cameBack: [Double], onConsole: (Double) -> Bool, wanted: Double, until end: Double)
    -> (made: Double?, released: Double?, makes: Int) {
    var w = Watch()
    var made: Double? = nil, released: Double? = nil, makes = 0
    var i = 0
    var backs = cameBack.sorted()
    var wantedSince = wanted
    var wakeUp: Double? = wanted, releaseAt: Double? = nil
    func seen() -> (real: Int, list: [String], asleep: Bool) {
        (screens[i].real, screens[i].list + (made != nil && released == nil ? ["sills:active"] : []), screens[i].asleep)
    }
    func look(_ t: Double) {
        let s = seen(), was = w.asleep
        w.saw(real: s.real, list: s.list, asleep: s.asleep, at: t)
        // The wake: the Desktop (wanted from `wanted` on) asks again, with no real screen and no Sill's display.
        let gate = HDP.needsVirtualDesktop(hasDisplay: w.real > 0, clientCount: 1, appKitLoop: true, synthetic: false,
                                           apiAvailable: true, screenRecording: true, onConsole: onConsole(t), guardHolds: false,
                                           switchOn: true)
        if was, !w.asleep, wakeUp == nil, t >= wanted,
           HDP.desktopAgainAtWake(streamsDesktop: true, sills: made != nil && released == nil, gate: gate) {
            wantedSince = t; wakeUp = t
        }
    }
    look(screens[0].at)
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
            look(next)              // a wait under way: a wake this look finds asks nothing more (its own select decides)
            wakeUp = nil
            guard onConsole(next) else { continue }
            switch w.make(wantedSince: wantedSince, now: next) {
            case .no, .asleep: break
            case .wait(let v): wakeUp = v
            case .make: made = next; makes += 1; w.changed(at: next); look(next)
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

// MARK: The screens' sleep (Noah's test of 2026-11-12, 03:56)
// The watch: never made while the screens sleep (`.asleep`), however long; the wake is a return (two seconds), found by
// a look alone; a real screen's `.no` comes first; the first look records no wake.
let twoAsleep = ["a:real:asleep", "b:real:asleep"]
do {
    var w = Watch()
    w.saw(real: 0, list: standIn, asleep: true, at: 0)
    check(w.asleep && w.cameBackAt == nil, "a first look asleep: asleep, and no return recorded")
    check(w.make(wantedSince: 10, now: 10) == .asleep, "no real screen, the screens asleep: not made (.asleep)")
    check(w.make(wantedSince: 10, now: 1000) == .asleep, "…however long the Desktop has wanted it")
    w.saw(real: 0, list: standIn, asleep: true, at: 20)
    check(w.cameBackAt == nil, "still asleep: no return")
    w.saw(real: 0, list: standIn, asleep: false, at: 120)
    check(!w.asleep && near(w.cameBackAt, 120) && w.listChangedAt == nil, "awake at 120: a return at 120, found by a look alone (the list the same)")
    check(w.make(wantedSince: 120, now: 120) == .wait(until: 122), "…made two seconds after the wake")
    check(w.make(wantedSince: 120, now: 122) == .make, "…then made")
    w.saw(real: 0, list: standIn, asleep: false, at: 130)
    check(near(w.cameBackAt, 120), "awake again: no new return")
    var real = Watch()
    real.saw(real: 2, list: twoAsleep, asleep: true, at: 0)
    check(real.make(wantedSince: 5, now: 5) == .no, "two monitors asleep, the screens asleep: .no (they count), not .asleep")
    var first = Watch()
    first.saw(real: 0, list: standIn, asleep: false, at: 3)
    check(first.cameBackAt == nil, "a first look awake: no return")
    var sleeping = Watch()
    sleeping.saw(real: 2, list: two, at: 0)
    sleeping.saw(real: 2, list: twoAsleep, asleep: true, at: 50)
    check(sleeping.realGoneAt == nil && sleeping.realBackAt == nil, "two monitors falling asleep: no real screen's going")
    sleeping.saw(real: 2, list: two, asleep: false, at: 90)
    check(sleeping.realBackAt == nil && near(sleeping.cameBackAt, 90), "…waking: no real screen's return, but this session's")
    check(sleeping.release(now: 200) == .release, "a real screen counted asleep or awake: a Sill's display there would go")
}

// Tonight at 03:56 (seconds after 03:55:00, from Sill.log and macOS's log): the lid closed, two monitors, this session
// back on the console and locked at 42.241, the iPad connected at 50.759; the lock screen's idle timer put the screens
// to sleep at 80.843 (both monitors online, asleep); the capture stopped and the iPad asked for the Desktop again at
// 80.889; 1414 made Sill's display at 83.369, which got no frame until a key at the Mac woke the screens at 154.418 (the
// monitors working by about 154.6), and removed it at 156.613. Nothing may be made.
let closedLid = true
func at0356(said: Bool, sleepSeenAt: Double) -> (made: Double?, released: Double?, makes: Int) {
    replay(screens: [.mac(at: 0, active: 2, online: 2, lidClosed: closedLid, said: false, list: two),
                     .mac(at: sleepSeenAt, active: 0, online: 2, lidClosed: closedLid, said: said, list: twoAsleep),
                     .mac(at: 154.45, active: 0, online: 2, lidClosed: closedLid, said: false, list: twoAsleep),
                     .mac(at: 154.6, active: 2, online: 2, lidClosed: closedLid, said: false, list: two)],
           cameBack: [42.241, 154.45], onConsole: { $0 >= 42.241 }, wanted: 80.889, until: 170)
}
let sleep0356 = at0356(said: true, sleepSeenAt: 80.843)
check(sleep0356.made == nil && sleep0356.makes == 0,
      "tonight at 03:56, the screens asleep at 80.843 and the Desktop asked at 80.889: nothing made (\(String(describing: sleep0356.made)))")
// The same without macOS saying the sleep (no NSWorkspace notification, no callback: the select's look the first to see
// it): the monitors asleep still count, so still nothing; 1414's rule made it at 82.889.
let unsaid0356 = at0356(said: false, sleepSeenAt: 80.889)
check(unsaid0356.made == nil, "…with the sleep never said: still nothing made, asleep monitors count (\(String(describing: unsaid0356.made)))")
// The only monitor unplugged while the screens sleep (a closed-lid MacBook, a device connected): nothing made while
// they sleep; the wake asks again; made two seconds after it, as no real screen came back.
let goneAsleep = replay(screens: [.mac(at: 0, active: 1, online: 1, lidClosed: true, said: false, list: ["m:real:active"]),
                                  .mac(at: 50, active: 0, online: 1, lidClosed: true, said: true, list: ["m:real:asleep"]),
                                  .mac(at: 60, active: 0, online: 0, lidClosed: true, said: true, list: standIn),
                                  .mac(at: 90, active: 0, online: 0, lidClosed: true, said: false, list: standIn)],
                        cameBack: [], onConsole: { _ in true }, wanted: 60.05, until: 100)
check(near(goneAsleep.made, 92) && goneAsleep.released == nil && goneAsleep.makes == 1,
      "the monitor unplugged while the screens sleep: none made asleep, made two seconds after the wake (\(String(describing: goneAsleep.made)))")
// A Mac mini whose monitor drops off as it sleeps and comes back 1.2 s after the wake: never made, never removed.
let dropOff = replay(screens: [.mac(at: 0, active: 1, online: 1, lidClosed: false, said: false, list: ["m:real:active"]),
                               .mac(at: 50, active: 0, online: 0, lidClosed: false, said: true, list: []),
                               .mac(at: 80, active: 0, online: 0, lidClosed: false, said: false, list: []),
                               .mac(at: 81.2, active: 1, online: 1, lidClosed: false, said: false, list: ["m:real:active"])],
                     cameBack: [], onConsole: { _ in true }, wanted: 50.05, until: 95)
check(dropOff.made == nil && dropOff.released == nil,
      "a monitor that drops off asleep and is back 1.2 s after the wake: nothing made or removed (\(String(describing: dropOff.made)))")
// A device connecting to a closed-lid Mac whose monitors sleep, its connect's wake slow to reach them (2.5 s): nothing.
let slowWake = replay(screens: [.mac(at: 0, active: 0, online: 2, lidClosed: true, said: true, list: twoAsleep),
                                .mac(at: 100.15, active: 0, online: 2, lidClosed: true, said: false, list: twoAsleep),
                                .mac(at: 102.65, active: 2, online: 2, lidClosed: true, said: false, list: two)],
                      cameBack: [100.15], onConsole: { _ in true }, wanted: 100.3, until: 110)
check(slowWake.made == nil, "a connect waking asleep monitors in 2.5 s with the lid closed: nothing made (\(String(describing: slowWake.made)))")
// A screenless Mac whose screens sleep and wake after Sill's display was made: kept through both, none made again.
let keptAsleep = replay(screens: [.mac(at: 0, active: 0, online: 0, lidClosed: true, said: false, list: standIn),
                                  .mac(at: 120, active: 0, online: 0, lidClosed: true, said: true, list: standIn),
                                  .mac(at: 150, active: 0, online: 0, lidClosed: true, said: false, list: standIn)],
                        cameBack: [], onConsole: { _ in true }, wanted: 100.3, until: 170)
check(near(keptAsleep.made, 101.3) && keptAsleep.released == nil && keptAsleep.makes == 1,
      "a screenless Mac asleep and awake after Sill's display was made: kept, made once (\(keptAsleep.makes))")
// No device (or off console): the screens sleep and wake, a monitor unplugged meanwhile: nothing made.
let nobody = replay(screens: [.mac(at: 0, active: 1, online: 1, lidClosed: true, said: false, list: ["m:real:active"]),
                              .mac(at: 50, active: 0, online: 1, lidClosed: true, said: true, list: ["m:real:asleep"]),
                              .mac(at: 60, active: 0, online: 0, lidClosed: true, said: true, list: standIn),
                              .mac(at: 90, active: 0, online: 0, lidClosed: true, said: false, list: standIn)],
                    cameBack: [], onConsole: { _ in false }, wanted: 60.05, until: 100)
check(nobody.made == nil, "no device or off console: nothing made at the wake either")
// The lid closed with nothing attached while a device streams (#61's own case): macOS may say the screens slept as the
// built-in one went, while its stand-in draws; a display working is awake, so Sill's display a second after the Desktop
// asked, as before.
let lidClose = replay(screens: [.mac(at: 0, active: 1, online: 1, lidClosed: false, said: false, list: ["builtin:real:active"]),
                                .mac(at: 50, active: 0, online: 0, lidClosed: true, said: true, standIn: true, list: standIn)],
                      cameBack: [], onConsole: { _ in true }, wanted: 50.3, until: 60)
check(near(lidClose.made, 52) && lidClose.makes == 1,
      "the lid closed, nothing attached, the sleep said but the stand-in drawing: made as before (\(String(describing: lidClose.made)))")

// TEST ONLY: SILL_TEST_HEADLESS, a test host's scripted list, and who takes it (not SILL_TEST_DISPLAYS, the Desktop's stops').
let parsed = HDP.testHeadlessList("real\nreal asleep # a comment\nstandin\nstandin asleep\nlid closed\nscreens asleep\nbogus line\n# real\n")
check(parsed.displays == [HDP.TestDisplay(kind: .real, active: true), HDP.TestDisplay(kind: .real, active: false),
                          HDP.TestDisplay(kind: .standIn, active: true), HDP.TestDisplay(kind: .standIn, active: false)]
      && parsed.lidClosed && parsed.screensAsleep,
      "the scripted list: a screen, one asleep, the stand-in working and dark, the lid closed, the screens asleep; comments and the rest left out")
check(HDP.testHeadlessList("").displays.isEmpty && !HDP.testHeadlessList("").lidClosed && !HDP.testHeadlessList("").screensAsleep,
      "an empty file: no display, the lid open, the screens awake")
check(!HDP.testHeadlessList("real\n# screens asleep\n").screensAsleep, "the screens' line commented out: awake")
check(HDP.testHeadless(environment: ["SILL_TEST_HEADLESS": "/tmp/d"], testHost: true).path == "/tmp/d", "a test host takes the file")
check(HDP.testHeadless(environment: ["SILL_TEST_DISPLAYS": "/tmp/d"], testHost: true) == (nil, nil), "the Desktop stops' variable is not this one")
let refused = HDP.testHeadless(environment: ["SILL_TEST_HEADLESS": "/tmp/d"], testHost: false)
check(refused.path == nil && refused.line == "SILL_TEST_HEADLESS ignored: only a --synthetic test host takes it, never Sill.app.", "any other host ignores it, with one line")
check(HDP.testHeadless(environment: [:], testHost: true) == (nil, nil), "unset: nothing")
// Which real displays keep Sill's display from being made (the review of 2026-11-09; Noah's test of 2026-11-12, 03:56):
// a display only asleep is online and keeps its windows, and it is asleep because macOS's display sleep took every
// screen, Sill's own with them, so it counts whatever the lid: a person's tap on a device wakes it (#151, #228).
check(HDP.realDisplays(active: 0, online: 1, lidClosed: false) == 1, "the lid open, its screen asleep: counted (the wake turns it on)")
check(HDP.realDisplays(active: 0, online: 2, lidClosed: false) == 2, "a Mac mini, its two monitors asleep: counted")
check(HDP.realDisplays(active: 1, online: 1, lidClosed: false) == 1, "a monitor awake: counted")
check(HDP.realDisplays(active: 0, online: 0, lidClosed: false) == 0, "a Mac with no monitor: none")
check(HDP.realDisplays(active: 0, online: 2, lidClosed: true) == 2, "the lid closed, its monitors asleep: counted (asleep, not gone)")
check(HDP.realDisplays(active: 1, online: 2, lidClosed: true) == 2, "the lid closed, one monitor awake, one asleep: both counted")
check(HDP.realDisplays(active: 2, online: 2, lidClosed: true) == 2, "the lid closed, both monitors awake: counted")
check(HDP.realDisplays(active: 0, online: 0, lidClosed: true) == 0, "the lid closed, nothing attached: none")
check(!HDP.stillNeeded(physicalDisplays: HDP.realDisplays(active: 0, online: 1, lidClosed: false)),
      "a screen asleep with the lid open, or a Mac mini's monitor asleep: no display made")
check(!HDP.stillNeeded(physicalDisplays: HDP.realDisplays(active: 0, online: 1, lidClosed: true)),
      "a monitor asleep with the lid closed: no display made either (tonight's 73 s without a frame)")
check(HDP.stillNeeded(physicalDisplays: HDP.realDisplays(active: 0, online: 0, lidClosed: true)),
      "the lid closed, nothing online but the stand-in: Sill's display wanted")

// The screens' sleep (macOS's display sleep), as the coordinator reads it: what macOS said, unless a display works (a real
// one, or macOS's stand-in).
check(HDP.screensAsleep(said: true, active: 0) == true, "macOS said they sleep, none works: asleep")
check(HDP.screensAsleep(said: false, active: 0) == false, "nothing said: awake (a Mac with no display at all reads none)")
check(HDP.screensAsleep(said: true, active: 1) == false, "said asleep, but a display works: awake (a wake macOS did not say, a stand-in drawing)")
check(HDP.screensAsleep(said: false, active: 2) == false, "awake and working: awake")
// The line a Desktop prints instead of making Sill's display: the lid closed, every real display asleep, none gone.
check(HDP.asleepNotGone(lidClosed: true, online: 2, active: 0) == 2, "the lid closed, two monitors asleep: the line, for two")
check(HDP.asleepNotGone(lidClosed: true, online: 1, active: 0) == 1, "…one monitor asleep: for one")
check(HDP.asleepNotGone(lidClosed: false, online: 1, active: 0) == nil, "the lid open, its screen asleep: no line (0.6.1 made none there)")
check(HDP.asleepNotGone(lidClosed: true, online: 2, active: 1) == nil, "a monitor working: no line")
check(HDP.asleepNotGone(lidClosed: true, online: 0, active: 0) == nil, "nothing online: no line (Sill's display is wanted)")
check(HDP.asleepNotGoneLine(asleep: 2) == "Headless display: the 2 screens are asleep, not gone; none made (a tap on a device wakes them).",
      "the line for two screens: \(HDP.asleepNotGoneLine(asleep: 2))")
check(HDP.asleepNotGoneLine(asleep: 1) == "Headless display: the screen is asleep, not gone; none made (a tap on a device wakes it).",
      "the line for one: \(HDP.asleepNotGoneLine(asleep: 1))")
check(HDP.waitsForWakeLine == "Headless display: no real screen, and the screens are asleep; none made until they wake.",
      "the line while the screens sleep with none: \(HDP.waitsForWakeLine)")
// At the wake, a Desktop that streams without a real screen and without Sill's display asks again.
check(HDP.desktopAgainAtWake(streamsDesktop: true, sills: false, gate: true) == true, "the Desktop on the stand-in at the wake: again")
check(HDP.desktopAgainAtWake(streamsDesktop: true, sills: true, gate: true) == false, "Sill's display there already: nothing")
check(HDP.desktopAgainAtWake(streamsDesktop: false, sills: false, gate: true) == false, "a window, or nothing, streams: nothing (the device asks)")
check(HDP.desktopAgainAtWake(streamsDesktop: true, sills: false, gate: false) == false,
      "a real screen came back, no device, off console, no Screen Recording: nothing")
// Its size and rate are the device's (VirtualDesktopSize, Tests/checks/virtual-desktop; Noah, 2026-11-18), no longer
// #200's built-in screen as last seen.

// MARK: The modes a display is made with, and its backing (phase 2b's probe P2: Scripts/display-modes-probe)

typealias Mode = VirtualDisplay.ModeSize
let pad13 = Mode(width: 1376, height: 1032)
check(pad13.turned == Mode(width: 1032, height: 1376), "a room turned a quarter swaps its sides: \(pad13.turned)")
check(pad13.turned.turned == pad13, "turned twice is the room again")
check(pad13.description == "1376×1032", "a mode reads W×H: \(pad13.description)")
// The list: the one asked for first, each other in its order, a size given twice listed once.
check(VirtualDisplay.modeList(asked: pad13, others: []) == [pad13], "one mode by default, as every display Sill made before")
check(VirtualDisplay.modeList(asked: pad13, others: [pad13.turned]) == [pad13, pad13.turned], "the room both ways, the asked one first")
check(VirtualDisplay.modeList(asked: pad13, others: [pad13, pad13.turned, pad13]) == [pad13, pad13.turned],
      "the asked size given again is listed once, first")
let mini = Mode(width: 1218, height: 800)
check(VirtualDisplay.modeList(asked: pad13, others: [mini, pad13.turned, mini]) == [pad13, mini, pad13.turned],
      "the others in their order, each once: \(VirtualDisplay.modeList(asked: pad13, others: [mini, pad13.turned, mini]))")
check(VirtualDisplay.modeList(asked: mini.turned, others: [mini]).first == mini.turned, "the asked one first even upright")
// The backing: the widest mode's width and the tallest mode's height, at the scale.
func backing(_ modes: [Mode], _ scale: Int) -> [Int] { let b = VirtualDisplay.maxPixels(modes, scale: scale); return [b.wide, b.high] }
check(backing([pad13], 2) == [2752, 2064], "one mode at 2×: its own pixels (as init sized it before: \(backing([pad13], 2)))")
check(backing([pad13], 1) == [1376, 1032], "at 1×: its points")
check(backing([pad13, pad13.turned], 2) == [2752, 2752], "the room both ways: a square of the longer side (\(backing([pad13, pad13.turned], 2)))")
check(backing([Mode(width: 800, height: 1200), Mode(width: 1600, height: 600)], 2) == [3200, 2400],
      "the widest's width and the tallest's height, from different modes: \(backing([Mode(width: 800, height: 1200), Mode(width: 1600, height: 600)], 2))")
check(backing([mini, pad13, Mode(width: 1000, height: 700)], 2) == [2752, 2064], "the largest of three, wherever it is listed")
check(backing([], 2) == [0, 0], "no mode, no backing")
// A backing asked for (the Virtual Desktop's, VirtualDesktopSize.backing): at least it each way, the modes' own where larger.
func atLeast(_ modes: [Mode], _ b: (wide: Int, high: Int)?) -> [Int] { let r = VirtualDisplay.maxPixels(modes, scale: 2, atLeast: b); return [r.wide, r.high] }
check(atLeast([mini], nil) == [2436, 1600], "none asked: the modes' own (\(atLeast([mini], nil)))")
check(atLeast([mini], (3072, 3072)) == [3072, 3072], "a square asked: the square, the room both ways inside (\(atLeast([mini], (3072, 3072))))")
check(atLeast([pad13], (2000, 2000)) == [2752, 2064], "smaller than the modes': the modes' own")
check(atLeast([mini], (2000, 3072)) == [2436, 3072], "each way on its own: the wider of the two widths, the taller of the heights (\(atLeast([mini], (2000, 3072))))")
// init's wiring, read as text: the descriptor's maximum is the list's backing, and every listed mode goes to setModes:.
// build.sh puts the VirtualDisplay.swift it compiled (a mutant's too) beside the binary.
let vdSource = (try? String(contentsOfFile: CommandLine.arguments[0] + ".VirtualDisplay.swift", encoding: .utf8)) ?? ""
check(!vdSource.isEmpty, "the VirtualDisplay.swift compiled in is read (\(CommandLine.arguments[0]).VirtualDisplay.swift)")
check(vdSource.contains("let maxPx = Self.maxPixels(modes, scale: scale, atLeast: backing)\n        self.backing = maxPx\n")
      && vdSource.contains("\"setMaxPixelsWide:\", UInt32(maxPx.wide))") && vdSource.contains("\"setMaxPixelsHigh:\", UInt32(maxPx.high))"),
      "init sizes the descriptor's maximum for every mode it lists and the backing asked for, and keeps it")
check(vdSource.contains("let modes = Self.modeList(asked: ModeSize(width: widthPt, height: heightPt), others: otherModes)")
      && vdSource.contains("let settings = try Self.newSettings(modes, scale: scale, refreshHz: refreshHz)"),
      "init lists the asked mode and the others, and applies them all")
check(vdSource.contains("guard displayID != 0, modesListed.contains(size) else { return false }"),
      "switchMode moves only to a mode the display was made with (or given since)")
// The follow in place's calls (probes P2b and P2c): applySettings: with the list at the rate asked, the size asked for now
// its first; the switch only to the size at the display's scale, a mode usable for the desktop first; nothing asked when
// none is listed; its code given back.
check(vdSource.contains("let rate = newRate ?? refreshHz\n        let settings = try Self.newSettings(list, scale: scale, refreshHz: rate)")
      && vdSource.contains("        modesListed = list\n        widthPt = list[0].width\n        heightPt = list[0].height\n        refreshHz = rate\n"),
      "applyModes sends the rate asked (else the one it has) and keeps the list, the size and the rate it took")
check(vdSource.contains("$0.width == size.width && $0.height == size.height && $0.pixelWidth == size.width * scale")
      && vdSource.contains("&& $0.pixelHeight == size.height * scale }")
      && vdSource.contains("return matching.first { $0.isUsableForDesktopGUI() } ?? matching.first"),
      "the mode switched to: the size at the display's scale, a usable one first")
check(vdSource.contains("guard let mode = listedMode(size) else { return nil }")
      && vdSource.contains("let done = CGCompleteDisplayConfiguration(config, .forSession)") && vdSource.contains("return done.rawValue"),
      "switchToListed asks nothing for a mode not listed, and gives back the complete code")
check(vdSource.contains("func listsUsable(_ size: ModeSize) -> Bool { listedMode(size)?.isUsableForDesktopGUI() == true }"),
      "listsUsable: listed and usable for the desktop")

print("virtual-display-api: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
