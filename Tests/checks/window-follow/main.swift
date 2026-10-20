import Foundation
// WindowFollow: when the stream follows a new window of the streamed app, and where it goes back.
// Compiled with Sources/StreamProtocol and Sources/SillHost/WindowFollow.swift.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func w(_ id: UInt32, _ app: String) -> WindowInfo {
    WindowInfo(id: id, title: "w\(id)", appName: app, bundleID: app.isEmpty ? "" : "com.example.\(app)", width: 800, height: 600)
}
let claude = w(10, "Claude"), safari = w(20, "Safari"), iterm = w(30, "iTerm")
let before = [claude, safari, iterm]

// A new window of the streamed app, in front: followed.
let update = w(11, "Claude")
check(WindowFollow.next(previous: before, seen: [], current: before + [update], activeID: 10, topmost: 11) == 11, "Claude's new dialog in front: followed")
let iterm2 = w(31, "iTerm")
check(WindowFollow.next(previous: before, seen: [], current: [iterm2] + before, activeID: 30, topmost: 31) == 31, "iTerm's new window in front: followed")
// Not followed:
check(WindowFollow.next(previous: nil, seen: [], current: before + [update], activeID: 10, topmost: 11) == nil, "the first catalog follows nothing")
check(WindowFollow.next(previous: before, seen: [], current: before + [update], activeID: 10, topmost: 10) == nil, "the streamed window itself in front")
check(WindowFollow.next(previous: before, seen: [], current: before + [update], activeID: 10, topmost: nil) == nil, "nothing known in front")
check(WindowFollow.next(previous: before, seen: [], current: before + [update], activeID: 10, topmost: 20) == nil, "an older window of another app in front")
check(WindowFollow.next(previous: before + [update], seen: [], current: before + [update], activeID: 10, topmost: 11) == nil, "a window that was already there (not new)")
let newSafari = w(21, "Safari")
check(WindowFollow.next(previous: before, seen: [], current: before + [newSafari], activeID: 10, topmost: 21) == nil, "another app's new window in front")
check(WindowFollow.next(previous: before, seen: [], current: before, activeID: 10, topmost: 11) == nil, "a window in front that the catalog does not list (too small, Sill's own)")
check(WindowFollow.next(previous: before, seen: [], current: before + [update], activeID: 99, topmost: 11) == nil, "the streamed window unknown to both catalogs")
let noBundle = w(40, ""), noBundle2 = w(41, "")
check(WindowFollow.next(previous: [noBundle], seen: [], current: [noBundle, noBundle2], activeID: 40, topmost: 41) == nil, "no bundle ID: never treated as the same app")
// The streamed window closing in the same poll the new one appears: same app by the previous catalog.
check(WindowFollow.next(previous: before, seen: [], current: [update, safari, iterm], activeID: 10, topmost: 11) == 11, "the streamed window gone, its app's new one in front: followed")
// A window listed before in this run (minimized, its app hidden, on another Space) is not new when it
// comes back in front, even though the last catalog did not list it.
let earlier = w(12, "Claude")
check(WindowFollow.next(previous: before, seen: [10, 12, 20, 30], current: before + [earlier], activeID: 10, topmost: 12) == nil,
      "a window back from the Dock or another Space: not followed")
check(WindowFollow.next(previous: before, seen: [10, 20, 30], current: before + [earlier], activeID: 10, topmost: 12) == 12,
      "a window never listed before: followed")

// Going back.
check(WindowFollow.back([], current: before) == nil, "nothing followed: nowhere to go back to")
let one = WindowFollow.back([10], current: before)
check(one?.window == 10 && one?.rest == [], "back to the window followed from")
let skip = WindowFollow.back([10, 11], current: before)
check(skip?.window == 10 && skip?.rest == [], "a window followed from that closed too is skipped")
let unwind = WindowFollow.back([10, 11], current: before + [update])
check(unwind?.window == 11 && unwind?.rest == [10], "dialog over dialog: one at a time")
check(WindowFollow.back([10], current: [safari]) == nil, "everything followed from is gone")
check(WindowFollow.defaultsKey == "followNewWindows", "the defaults key")

print(failures == 0 ? "window-follow: all \(checks) checks passed" : "window-follow: \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
