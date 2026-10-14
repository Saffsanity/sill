// Scripts/menu-check/run.sh close: WindowSizer's close (the bar's long-press Close, kind 15) against
// the fixture's "Slow Close" window, whose close holds the fixture's main thread 4 s. The press must
// come back within its own 1 s timeout, not the system's default, since the host makes it on its
// main actor. usage (fixture.py runs it): close PID FIXTURE_LOG FIXTURE_BIN
import Foundation
import ApplicationServices

let args = CommandLine.arguments
let pid = pid_t(args[1])!, fixtureLog = args[2]
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL \(what)") } else { print("ok   \(what)") } }
func log() -> String { (try? String(contentsOfFile: fixtureLog, encoding: .utf8)) ?? "" }

let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 1.0)
var value: CFTypeRef?
_ = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
let window = ((value as? [AXUIElement]) ?? []).first { w in
    var t: CFTypeRef?
    return AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success && (t as? String) == "Slow Close"
}
check(window != nil, "the fixture's Slow Close window is found")
if let window {
    AXUIElementSetMessagingTimeout(window, 1.0)
    let started = CFAbsoluteTimeGetCurrent()
    let done = MainActor.assumeIsolated { WindowSizer.perform(.close, element: window) }   // main.swift's top level runs on the main thread
    let took = CFAbsoluteTimeGetCurrent() - started
    print(String(format: "     close took %.2f s, %@", took, done ? "done" : "refused"))
    check(took < 1.5, "the close comes back within 1.5 s while the app holds its main thread")
    Thread.sleep(forTimeInterval: 0.3)
    check(log().contains("windowShouldClose 'Slow Close' (sleeping 4 s)"), "the press reached the window's close")
    Thread.sleep(forTimeInterval: 4.5)     // the fixture's sleep, so it exits cleanly
}
print(failures == 0 ? "close: all passed" : "close: \(failures) failed")
exit(failures == 0 ? 0 : 1)
