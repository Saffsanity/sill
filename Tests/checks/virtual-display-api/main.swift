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

print("virtual-display-api: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
