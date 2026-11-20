import Foundation

var failures = 0
var cases = 0
func check(_ ok: Bool, _ what: String) {
    cases += 1
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}

typealias A = StageCaptureWindows.Application
typealias W = StageCaptureWindows.Window
let first = A(pid: 10, bundleID: "example.app")
let second = A(pid: 20, bundleID: "example.app")
let unrelated = A(pid: 30, bundleID: "example.other")
let selected = W(id: 200, owner: second)
let windows = [W(id: 100, owner: first), W(id: 101, owner: first),
               selected, W(id: 201, owner: second), W(id: 202, owner: second),
               W(id: 300, owner: unrelated), W(id: 301, owner: nil)]
let apps = [first, second, unrelated]
let policy = StageCaptureWindows(selected: selected, applications: apps, windows: windows)
check(policy.filter == .windows([200, 201, 202]), "second instance includes its main window, sheet and popover only")
check(StageCaptureWindows(selected: selected, applications: [], windows: windows) == policy,
      "window owners also reveal a duplicate instance")
check(StageCaptureWindows(selected: selected, applications: apps.reversed(), windows: windows.reversed()) == policy,
      "reordering is not a membership change")
check(StageCaptureWindows(selected: selected, applications: apps, windows: windows.filter { $0.id != 200 }) == policy,
      "a selected window resolved by ID stays included when absent from the on-screen list")
check(StageCaptureWindows(selected: selected, applications: apps, windows: windows + [W(id: 203, owner: second)]).filter
      == .windows([200, 201, 202, 203]), "opening an owned auxiliary window changes membership")
check(StageCaptureWindows(selected: selected, applications: apps, windows: windows.filter { $0.id != 201 }).filter
      == .windows([200, 202]), "closing an owned auxiliary window changes membership")
check(StageCaptureWindows(selected: selected, applications: apps, windows: windows + [W(id: 302, owner: unrelated)]) == policy,
      "unrelated auxiliary windows do not change membership")
check(StageCaptureWindows(selected: windows[0], applications: apps, windows: windows).filter == .windows([100, 101]),
      "switching to the first instance discards the second PID's set")
check(StageCaptureWindows(selected: W(id: 200, owner: nil), applications: apps, windows: windows).filter == .windows([200]),
      "missing owner permits only the selected window")
check(StageCaptureWindows(selected: selected, applications: [second], windows: [selected]).filter == .application(20),
      "a single instance keeps app filtering")
check(StageCaptureWindows(selected: selected, applications: [second, unrelated], windows: [selected, windows[5]]).filter == .application(20),
      "different bundle identifiers keep app filtering")
check(StageCaptureWindows(selected: selected, applications: [second, second], windows: [selected, selected]).filter == .application(20),
      "repeated entries for one PID are not a collision")
check(StageCaptureWindows(selected: W(id: 200, owner: A(pid: 20, bundleID: "")),
                          applications: [A(pid: 10, bundleID: ""), A(pid: 20, bundleID: "")], windows: []).filter == .application(20),
      "empty bundle identifiers do not group unrelated processes")

print("stage-capture-windows: \(cases) checks, \(failures) failed")
if failures > 0 { exit(1) }
