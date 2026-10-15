import Foundation
// WindowOrder: the host's first-seen order and a device's arrangement. Compiled with
// Sources/StreamProtocol as one module.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias W = WindowOrder

// The host: newcomers first, in the order listed.
check(W.seen([], listed: [3, 1, 2], cap: 100) == [3, 1, 2], "the first poll: as listed")
check(W.seen([3, 1, 2], listed: [3, 1, 2], cap: 100) == [3, 1, 2], "nothing new: unchanged")
check(W.seen([3, 1, 2], listed: [2, 9, 3, 1, 8], cap: 100) == [9, 8, 3, 1, 2], "two new windows first, in the order listed")
// A window that leaves keeps its place for when it comes back (PR #111's review: minimized windows,
// other Spaces).
let gone = W.seen([3, 1, 2], listed: [3, 2], cap: 100)
check(gone == [3, 1, 2], "a window that left is remembered")
check(W.seen(gone, listed: [3, 1, 2], cap: 100) == [3, 1, 2], "back again: its old place, not first")
check(W.seen(gone, listed: [3, 1, 2, 7], cap: 100) == [7, 3, 1, 2], "back again beside a new one: only the new one first")
// The cap forgets the windows that left the longest ago, never one listed now.
let full = W.seen([5, 4, 3, 2, 1], listed: [6, 5, 1], cap: 4)
check(full.count == 4 && full == [6, 5, 4, 1], "past the cap: the gone windows at the end go first (\(full))")
let allListed = W.seen([3, 2, 1], listed: [4, 3, 2, 1], cap: 2)
check(allListed == [4, 3, 2, 1], "past the cap with every window listed: none forgotten")

// A device's arrangement.
check(W.arranged([], seen: [1, 2], listed: [9, 1, 2]) == nil, "no arrangement: the host's order shows")
check(W.arranged([2, 1], seen: [], listed: [9, 1, 2]) == nil, "the session's first list: nothing is new")
check(W.arranged([2, 1], seen: [1, 2], listed: [1, 2]) == nil, "nothing new")
check(W.arranged([2, 1], seen: [1, 2], listed: [9, 1, 8, 2]) == [9, 8, 2, 1], "new windows first, in the order listed")
check(W.arranged([2, 1], seen: [1, 2, 9], listed: [9, 1, 2]) == nil, "a window seen earlier this session and back again: not new")
check(W.arranged([2, 1, 9], seen: [1, 2], listed: [9, 1, 2]) == nil, "a window the arrangement already holds (from an earlier session): its place")

print(failures == 0 ? "window-order: all \(checks) checks passed" : "window-order: \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
