import Foundation

// H3 of docs/update-notice-plan.md (its protocol part): SillVersion and the payloads, against
// Sources/StreamProtocol compiled into this binary:
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/compatibility/main.swift -o check
// Given a path, it also writes the payloads that H4 read with an older StreamProtocol (cb0ec55's).
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func v(_ s: String) -> SillVersion? { SillVersion(s) }

// §3.2's examples.
check(v("v0.4.0")?.components == [0, 4], "v0.4.0")
check(v("V0.4")?.components == [0, 4], "V0.4")
check(v(" 0.4.0 ")?.components == [0, 4], "' 0.4.0 '")
check(v("\t0.4.0\n")?.components == [0, 4], "tab/newline")
check(v("1.2.3-beta.1")?.components == [1, 2, 3], "1.2.3-beta.1")
check(v("01.2")?.components == [1, 2], "01.2")
check(v("1..2") == nil, "1..2")
check(v("1.")?.components == [1], "1.")
check(v("1...")?.components == [1], "1...")
check(v("") == nil, "empty")
check(v("   ") == nil, "spaces")
check(v("dev") == nil, "dev")
check(v("v") == nil, "v")
check(v("vv1.0") == nil, "vv1.0")
check(v(".1") == nil, ".1")
check(v("v.1") == nil, "v.1")
check(v("-1") == nil, "-1")
check(v("+1") == nil, "+1")
check(v("1234567890") == nil, "10 digits")
check(v("123456789")?.components == [123456789], "9 digits")
check(v("1.1234567890") == nil, "a 10-digit part")
check(v("1.2.3.4.5.6.7.8")?.components == [1, 2, 3, 4, 5, 6, 7, 8], "eight parts")
check(v("1.2.3.4.5.6.7.8.9") == nil, "nine parts")
check(v("1.2.3.4.5.6.7.8.")?.components == [1, 2, 3, 4, 5, 6, 7, 8], "eight parts and a dot")
check(v("0") == .zero && v("0.0.0") == .zero && v("v0") == .zero, "zero")
check(v("٣.١") == nil, "Arabic-Indic digits are not ASCII")
check(v("1.٣")?.components == [1], "a non-ASCII digit ends the prefix")
check(v("１.2") == nil, "fullwidth digit")
check(v("0.3.0 (85)") == v("0.3.0") && v("0.3.0 (85)") != nil, "0.3.0 (85) is 0.3.0")
check(!(v("0.3.0 (85)")! > v("0.3.0")!), "0.3.0 (85) is not newer than 0.3.0")
check(v("nightly") == nil, "nightly")
check(v("v0.4.0-rc.1") == v("0.4"), "rc suffix ignored")
check(v("2026.09.25")?.components == [2026, 9, 25], "a date-like tag")
// Comparing.
check(v("0.10")! > v("0.9")!, "0.10 > 0.9")
check(v("1.0.1")! > v("1.0")!, "1.0.1 > 1.0")
check(v("v0.4.0")! == v("0.4")!, "v0.4.0 == 0.4")
check(v("0.4")! > v("0.3.9")!, "0.4 > 0.3.9")
check(v("1")! == v("1.0.0")!, "1 == 1.0.0")
check(v("1.0.0.1")! > v("1")!, "1.0.0.1 > 1")
check(!(v("1.2")! < v("1.2")!), "irreflexive")
check(v("v0.4.0")! > v("0.3.0")!, "tag with v against a bundle version")
check(v("0.4.0")! > v("v0.3.0")!, "bundle with v")
check(SillVersion.zero < v("0.0.1")!, "0 < 0.0.1")
// Showing.
check(v("0.4.0")!.description == "0.4", "0.4.0 shows 0.4")
check(v("1")!.description == "1.0", "1 shows 1.0")
check(v("1.0.1")!.description == "1.0.1", "1.0.1 shows 1.0.1")
check(SillVersion.zero.description == "0.0", "0 shows 0.0")
check(v("99")!.description == "99.0", "99 shows 99.0")
check(v("1.2.0.0")!.description == "1.2", "1.2.0.0 shows 1.2")
check(v("0.0.5")!.description == "0.0.5", "0.0.5 shows 0.0.5")
check(SillVersion(components: [1, 0, 0]).components == [1], "trailing zeros dropped")
check(v("1.2")!.hashValue == v("1.2.0")!.hashValue, "equal versions hash alike")

// 1,000 random pairs against a reference: padded lexicographic comparison of the generated parts,
// written with or without "v", with trailing ".0"s, leading zeros and a suffix.
var rng = SystemRandomNumberGenerator()
func reference(_ a: [Int], _ b: [Int]) -> Int {
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}
func write(_ parts: [Int]) -> String {
    var p = parts.isEmpty ? [0] : parts
    for _ in 0..<Int.random(in: 0...2, using: &rng) where p.count < 8 { p.append(0) }
    var s = p.map { n in Bool.random(using: &rng) && n < 10 ? "0\(n)" : "\(n)" }.joined(separator: ".")
    if Bool.random(using: &rng) { s = (Bool.random(using: &rng) ? "v" : "V") + s }
    if Int.random(in: 0...3, using: &rng) == 0 { s += ["-beta.1", " (85)", "+build.7", "rc1"].randomElement(using: &rng)! }
    if Int.random(in: 0...5, using: &rng) == 0 { s = "  " + s + "\n" }
    return s
}
var randomFailures = 0
for _ in 0..<1000 {
    let a = (0..<Int.random(in: 0...5, using: &rng)).map { _ in Int.random(in: 0...12, using: &rng) }
    let b = Bool.random(using: &rng) ? a : (0..<Int.random(in: 0...5, using: &rng)).map { _ in Int.random(in: 0...12, using: &rng) }
    let sa = write(a), sb = write(b)
    guard let va = v(sa), let vb = v(sb) else { randomFailures += 1; print("no parse: \(sa.debugDescription) \(sb.debugDescription)"); continue }
    let want = reference(a, b)
    let got = va < vb ? -1 : (vb < va ? 1 : 0)
    if want != got || (want == 0) != (va == vb) { randomFailures += 1; print("order: \(sa.debugDescription) vs \(sb.debugDescription): want \(want), got \(got)") }
    // The description round-trips.
    if v(va.description) != va { randomFailures += 1; print("round trip: \(sa.debugDescription) → \(va.description)") }
}
check(randomFailures == 0, "1,000 random pairs: \(randomFailures) wrong")

// The payloads.
let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
let hello = Hello(appVersion: "1.0", build: "42", protocol: 1, device: "iPad (iPad14,1)")
check(json(hello) == #"{"appVersion":"1.0","build":"42","device":"iPad (iPad14,1)","protocol":1}"#, "Hello's keys: \(json(hello))")
check(json(Hello()) == "{}", "an empty hello is {}")
check(Wire.decode(Hello.self, from: Data("{}".utf8)) == Hello(), "{} decodes")
check(Wire.decode(Hello.self, from: Data(#"{"appVersion":"1.2","protocol":1,"extra":[1,2]}"#.utf8)) == Hello(appVersion: "1.2", protocol: 1),
      "unknown keys are skipped")
check(Wire.decode(Hello.self, from: Data(#"{"appVersion":12}"#.utf8)) == nil, "a number as the version does not decode")
check(Wire.decode(Hello.self, from: Data("[]".utf8)) == nil, "not an object")
// The five goodbyes this branch sends, byte for byte, through the host's own encoder (Wire).
for reason in [Goodbye.quit, Goodbye.removed, Goodbye.remoteOff, Goodbye.internetOff, Goodbye.busy] {
    let bytes = String(decoding: Wire.encode(Goodbye(reason: reason)), as: UTF8.self)
    check(bytes == "{\"reason\":\"\(reason)\"}", "goodbye \(reason): \(bytes)")
}
let update = Goodbye(reason: Goodbye.update, message: "Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.",
                     minimumVersion: "1.2", reconnect: false)
check(json(update) == #"{"message":"Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.","minimumVersion":"1.2","reason":"update","reconnect":false}"#,
      "the update goodbye: \(json(update))")
check(Wire.decode(Goodbye.self, from: Data(#"{"reason":"quit"}"#.utf8)) == Goodbye(reason: "quit"), "an old goodbye reads with nil fields")
check(Wire.decode(Goodbye.self, from: Data(#"{"message":"x"}"#.utf8)) == nil, "no reason: no goodbye")
let later = #"{"reason":"pairingRequired","message":"Pair this iPad with Mac mini again: choose Pair iPhone or iPad… on the Mac.","reconnect":false}"#
check(Wire.decode(Goodbye.self, from: Data(later.utf8))?.reason == "pairingRequired", "a later reason decodes")
// The window list with and without the new keys.
let list = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L", hostVersion: "0.4.0", protocol: SillProtocol.current)
let listJSON = json(list)
check(listJSON.contains(#""hostVersion":"0.4.0""#) && listJSON.contains(#""protocol":1"#), "the list carries both keys: \(listJSON)")
let bare = json(WindowList(macName: "Mac mini", windows: [], active: .none, launchID: "L"))
check(!bare.contains("hostVersion") && !bare.contains("protocol"), "nil keys are left out: \(bare)")
let oldList = #"{"macName":"Mac mini","windows":[],"active":{"desktop":{}},"launchID":"L"}"#
let decodedOld = Wire.decode(WindowList.self, from: Data(oldList.utf8))
check(decodedOld != nil && decodedOld?.hostVersion == nil && decodedOld?.protocol == nil, "an older host's list decodes, both nil")
check(StreamMessageKind.hello.rawValue == 23 && StreamMessageKind(rawValue: 23) == .hello, "kind 23 is hello")
let helloMessage = StreamMessage(kind: .hello, timestamp: 1, isKeyframe: false, payload: Wire.encode(hello)).serialized()
check(StreamMessage.parseHeader(helloMessage)?.kind == .hello, "the hello's header parses")
check(SillProtocol.current == 1, "protocol 1")

// For H4: what cb0ec55's StreamProtocol must read.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
if let out {
    let payloads: [String: String] = [
        "goodbyeUpdate": String(decoding: Wire.encode(update), as: UTF8.self),
        "goodbyeLater": later,
        "windowList": String(decoding: Wire.encode(list), as: UTF8.self),
        "helloMessage": helloMessage.base64EncodedString(),
    ]
    try! JSONSerialization.data(withJSONObject: payloads, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: out))
}
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
