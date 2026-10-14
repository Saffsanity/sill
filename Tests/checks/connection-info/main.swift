// ConnectionInfo (iOSClient): the Settings panel's Connection Information rows and the text Copy puts
// on the clipboard. Compiled with iOSClient/ConnectionInfo.swift alone (run.sh).
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
func value(_ rows: [ConnectionInfo.Row], _ label: String) -> String? { rows.first { $0.label == label }?.value }

let full = ConnectionInfo.Facts(
    mac: "Mac mini", route: "Wi-Fi",
    stream: .init(width: 3024, height: 1898, fps: 60, mbps: 40), received: 58,
    rtt: .init(median: 7, max: 24), frameAge: .init(median: 9, max: 31),
    hostVersion: "0.5.1", hostProtocol: 1,
    appVersion: "0.5.1", build: "4", system: "iPadOS 27.0", model: "iPad14,1")
let rows = ConnectionInfo.rows(full)
check(rows.map(\.label) == ["Mac", "Connection", "Picture", "Received", "Round trip", "Frame age", "Mac's Sill", "This device"],
      "the rows, in order")
check(value(rows, "Mac") == "Mac mini", "the Mac's name")
check(value(rows, "Connection") == "Wi-Fi", "the route word")
check(value(rows, "Picture") == "3024×1898 · 60 fps · 40 Mbps", "the running stream")
check(value(rows, "Received") == "58 fps", "frames received")
check(value(rows, "Round trip") == "7 ms, worst 24 ms", "round trip: median and worst")
check(value(rows, "Frame age") == "9 ms, worst 31 ms", "frame age: median and worst")
check(value(rows, "Mac's Sill") == "0.5.1, protocol 1", "the Mac's version and protocol")
check(value(rows, "This device") == "Sill 0.5.1 (4), iPadOS 27.0, iPad14,1", "this device")

let bare = ConnectionInfo.Facts(mac: "", route: nil, stream: nil, received: nil, rtt: nil, frameAge: nil,
                                hostVersion: nil, hostProtocol: nil, appVersion: "0.5.1", build: "4",
                                system: "iOS 27.0", model: "iPhone17,1")
let b = ConnectionInfo.rows(bare)
check(value(b, "Mac") == "–", "no name: a dash")
check(value(b, "Connection") == "–", "no route: a dash")
check(value(b, "Picture") == "Not streaming", "no stream")
check(value(b, "Received") == "–" && value(b, "Round trip") == "–" && value(b, "Frame age") == "–",
      "a second without samples reads as none, never as zero")
check(value(b, "Mac's Sill") == "an older Sill or the command-line host", "no host version")
let protoOnly = ConnectionInfo.rows(.init(mac: "M", route: nil, stream: nil, received: 0, rtt: nil, frameAge: nil,
                                          hostVersion: "0.6", hostProtocol: nil, appVersion: "1", build: "1",
                                          system: "iOS 27.0", model: "x"))
check(value(protoOnly, "Mac's Sill") == "0.6", "a version without a protocol")
check(value(protoOnly, "Received") == "0 fps", "zero frames is a measurement")
let sameWorst = ConnectionInfo.rows(.init(mac: "M", route: nil, stream: nil, received: 1, rtt: .init(median: 5, max: 5),
                                          frameAge: nil, hostVersion: nil, hostProtocol: nil, appVersion: "1",
                                          build: "1", system: "iOS", model: "x"))
check(value(sameWorst, "Round trip") == "5 ms", "worst equal to the median: said once")

let at = Date(timeIntervalSince1970: 1_791_993_600)   // 2026-10-14 16:00:00 UTC
let text = ConnectionInfo.text(rows, at: at)
check(text.hasPrefix("Sill connection information, 2026-10-14T16:00:00Z\n"), "the text starts with its UTC time")
check(text.contains("\nRound trip: 7 ms, worst 24 ms\n"), "each row is one 'label: value' line")
check(text.hasSuffix("This device: Sill 0.5.1 (4), iPadOS 27.0, iPad14,1\n"), "and ends with the last row")
check(!text.contains("\u{00A0}"), "no no-break spaces in what is pasted")
var hyphenated = full; hyphenated.route = "Wi\u{2011}Fi"
let pasted = ConnectionInfo.text(ConnectionInfo.rows(hyphenated), at: at)
check(pasted.contains("\nConnection: Wi-Fi\n"), "the route's non-breaking hyphen pastes as a plain one")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
