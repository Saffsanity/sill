import Foundation
// H3 (DeviceGate): the floor rule, the refusal's words and the log lines. Compiled with
// Sources/StreamProtocol and Sources/SillHost/DeviceGate.swift (its `import StreamProtocol` dropped).
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func h(_ v: String?, _ device: String? = nil, build: String? = nil, protocol p: Int? = nil) -> Hello {
    Hello(appVersion: v, build: build, protocol: p, device: device)
}
let zero = SillVersion.zero, f12 = SillVersion("1.2")!, f01 = SillVersion("0.1")!

// The shipped constant parses, and is "0" in this build: nobody is refused.
check(SillVersion(DeviceGate.minimumDeviceVersion) != nil, "the shipped floor parses")
check(DeviceGate.floor == zero, "this build's floor is 0")
// Floor 0 admits everyone, those without a hello included.
for hello in [nil, h(nil), h(""), h("junk"), h("0"), h("0.1"), h("1.0"), h("99.9.9"), h("v2")] as [Hello?] {
    check(DeviceGate.admits(hello, floor: zero), "floor 0 admits \(String(describing: hello?.appVersion))")
}
// Floor 1.2.
for hello in [nil, h(nil), h(""), h("junk"), h("0.1"), h("1.1.9"), h("1.1"), h("1"), h("v1.1.99")] as [Hello?] {
    check(!DeviceGate.admits(hello, floor: f12), "floor 1.2 refuses \(String(describing: hello?.appVersion))")
}
for v in ["1.2", "1.2.0", "1.10", "2", "v1.2", "1.2-beta.1", " 1.2.1 ", "1.2 (7)"] {
    check(DeviceGate.admits(h(v), floor: f12), "floor 1.2 admits \(v)")
}
// A device that sends no version counts as 0: refused by any floor above 0.
check(!DeviceGate.admits(nil, floor: f01) && !DeviceGate.admits(h(nil), floor: f01), "floor 0.1 refuses no version")
check(DeviceGate.version(nil) == zero && DeviceGate.version(h("dev")) == zero && DeviceGate.version(h("1.3")) == SillVersion("1.3")!, "version()")

// The words.
check(DeviceGate.deviceWord(h("1.0", "iPad (iPad14,1)")) == "iPad", "an iPad")
check(DeviceGate.deviceWord(h("1.0", "iPhone (iPhone17,1)")) == "iPhone", "an iPhone")
check(DeviceGate.deviceWord(h("1.0", "iPad16,6 simulator")) == "iPad", "a simulator named by its model")
check(DeviceGate.deviceWord(h("1.0", "sillclient")) == "device", "a test client")
check(DeviceGate.deviceWord(h("1.0", "sillclient iPhone")) == "device", "iPhone only at the start")
check(DeviceGate.deviceWord(h("1.0", "\u{202E}iPad")) == "iPad", "a bidi override is cleaned first")
check(DeviceGate.deviceWord(h("1.0", nil)) == "device" && DeviceGate.deviceWord(nil) == "device", "no name")
let ipadRefusal = DeviceGate.refusal(h("1.1", "iPad (iPad14,1)"), floor: f12, macName: "Mac mini")
check(ipadRefusal == Goodbye(reason: "update", message: "Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.",
                             minimumVersion: "1.2", reconnect: false), "the iPad's refusal: \(ipadRefusal)")
check(DeviceGate.message(h("1.1", "iPhone (iPhone17,1)"), floor: SillVersion("2")!, macName: "Noah’s MacBook Pro")
      == "Update Sill on your iPhone to keep using Noah’s MacBook Pro. It needs version 2.0 or later.", "an iPhone's message, floor 2 shows 2.0")
check(DeviceGate.message(nil, floor: SillVersion("99")!, macName: "Mac")
      == "Update Sill on your device to keep using Mac. It needs version 99.0 or later.", "no hello: 'your device'")
check(DeviceGate.refusal(nil, floor: SillVersion("1.2.0")!, macName: "M").minimumVersion == "1.2", "minimumVersion as SillVersion shows it")
check(DeviceGate.message(h("1", "iPad"), floor: f12, macName: "Mac mini").count <= 200, "at most 200 characters (§4.6)")

// The log lines.
check(DeviceGate.refusedLine(h("1.0", "iPad (iPad14,1)"), endpoint: "192.168.1.23:52344", floor: f12)
      == "Refused iPad (iPad14,1) (Sill 1.0): needs 1.2 or later.", "Refused, a named device")
check(DeviceGate.refusedLine(nil, endpoint: "192.168.1.23:52344", floor: f12)
      == "Refused 192.168.1.23:52344 (an older Sill): needs 1.2 or later.", "Refused, no hello")
check(DeviceGate.refusedLine(h(nil), endpoint: "127.0.0.1:5", floor: f12) == "Refused 127.0.0.1:5 (no version): needs 1.2 or later.",
      "Refused, a hello without a version")
check(!DeviceGate.refusedLine(h("1.0\nClient connected: forged", "iPad\nforged"), endpoint: "e", floor: f12).contains("\n"),
      "no newline from the device reaches the Refused line")
check(DeviceGate.countLine(14, source: "192.168.1.23", floor: f12)
      == "Refused 14 more connections from 192.168.1.23 in the last minute: too old for this Mac (needs 1.2 or later).", "count line")
check(DeviceGate.countLine(1, source: "::1", floor: f12).hasPrefix("Refused 1 more connection from ::1 "), "count line, one")
check(DeviceGate.helloLine(h("1.0", "iPad (iPad14,1)", build: "42", protocol: 1), endpoint: "192.168.1.23:52344")
      == "Client hello: iPad (iPad14,1), Sill 1.0 (42), protocol 1 (192.168.1.23:52344)", "hello line, full")
check(DeviceGate.helloLine(h(nil), endpoint: "192.168.1.23:52344") == "Client hello: 192.168.1.23:52344, no version", "hello line, empty")
check(DeviceGate.helloLine(h("1.0", "iPad (iPad14,1)", protocol: 1), endpoint: "127.0.0.1:5")
      == "Client hello: iPad (iPad14,1), Sill 1.0, protocol 1 (127.0.0.1:5)", "hello line, no build (H5)")
check(DeviceGate.helloLine(h(nil, nil, protocol: 1), endpoint: "e") == "Client hello: e, no version, protocol 1", "hello line, protocol only")
check(DeviceGate.helloLine(h("", "iPad"), endpoint: "e") == "Client hello: iPad, no version (e)", "an empty version is no version")
check(!DeviceGate.helloLine(h("1\n2", "a\u{2028}b", build: "4\r2"), endpoint: "e").contains(where: { $0.isNewline }), "the hello line stays one line")
check(DeviceGate.helloLine(h(String(repeating: "9", count: 100), "iPad"), endpoint: "e").count < 100, "a long version is cut")
// The loop rule.
check(!DeviceGate.slows(refusedInWindow: 0) && !DeviceGate.slows(refusedInWindow: 4), "the first five at once")
check(DeviceGate.slows(refusedInWindow: 5) && DeviceGate.slows(refusedInWindow: 50), "the sixth on slowed")
check(DeviceGate.firstMessageDeadline == 2 && DeviceGate.loopDelay == 2 && DeviceGate.loopWindow == 60, "the constants")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
