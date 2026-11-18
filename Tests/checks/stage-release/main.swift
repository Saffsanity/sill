// StageRelease (Sources/SillHost/StageRelease.swift) on its own: when Sill's display (the stage, Virtual Display) may be
// removed after the staged window was sent home, and what the look after the removal does; a model of the window server
// and an app that commits an Accessibility move late, run through both orders (the display removed at once, as before
// 2026-11-12, and removed once the window has left it); the way out's wiring in VirtualStage.swift and
// StreamCoordinator.swift, read as text. Noah's test of PR #355 (2026-11-12, 04:30): Google Chrome, filling the Dell to the
// left of the main display, came back filling the main display instead.
//   swiftc -O Sources/SillHost/StageRelease.swift Tests/checks/stage-release/main.swift -o .build/checks/stage-release/check
import CoreGraphics
import Foundation

var passed = 0, failed = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(what())") }
}

// Noah's desk, lid closed: the Lenovo, main, at 0,0; the Dell to its left; Sill's display to the right of the main one.
let lenovo = CGRect(x: 0, y: 0, width: 2560, height: 1440)
let dell = CGRect(x: -1920, y: 156, width: 1920, height: 1080)
let stage = CGRect(x: 2560, y: 0, width: 2234, height: 1250)
let chromeHome = CGRect(x: -1920, y: 186, width: 1920, height: 1050)        // filling the Dell below its menu bar
let chromeStaged = CGRect(x: 2560, y: 30, width: 2234, height: 1220)        // "Moved Google Chrome — … to (2560,30,2234×1220)"
let chromeOnMain = CGRect(x: 0, y: 30, width: 2560, height: 1410)           // where it came back: filling the main display

// MARK: leftStage

check(StageRelease.leftStage(listed: nil, home: chromeHome, stage: stage), "a window not listed (closed) has left")
check(StageRelease.leftStage(listed: chromeHome, home: chromeHome, stage: stage), "a window listed at its home has left")
check(!StageRelease.leftStage(listed: chromeStaged, home: chromeHome, stage: stage), "a window still listed on Sill's display has not left")
check(StageRelease.leftStage(listed: chromeHome.offsetBy(dx: 2, dy: -2), home: chromeHome, stage: stage), "2 pt from home is home")
check(StageRelease.leftStage(listed: chromeOnMain, home: chromeHome, stage: stage), "off the display anywhere (kept on the main display) has left")
let halfOn = CGRect(x: 2400, y: 100, width: 400, height: 300)               // half on the main display, half on Sill's
check(!StageRelease.leftStage(listed: halfOn, home: chromeHome, stage: stage), "a window half on Sill's display has not left")
check(StageRelease.leftStage(listed: halfOn, home: halfOn, stage: stage), "a home that itself reaches over Sill's display is home all the same")
check(!StageRelease.leftStage(listed: halfOn.offsetBy(dx: 3, dy: 0), home: halfOn, stage: stage), "3 pt from such a home, on the display, has not left")
let touching = CGRect(x: 2160, y: 100, width: 400, height: 300)            // its right edge on the display's left edge
check(StageRelease.leftStage(listed: touching, home: chromeHome, stage: stage), "a window touching the display's edge is off it")
let onePointIn = CGRect(x: 2161, y: 100, width: 400, height: 300)
check(!StageRelease.leftStage(listed: onePointIn, home: chromeHome, stage: stage), "a window one point onto the display is on it")
let below = CGRect(x: 2600, y: 1250, width: 400, height: 300)              // under the display, its top on the display's bottom
check(StageRelease.leftStage(listed: below, home: chromeHome, stage: stage), "a window touching the display's bottom edge is off it")

// MARK: decide

check(StageRelease.decide(elapsed: 0, listed: chromeStaged, home: chromeHome, stage: stage) == .wait, "still on the display at once: wait")
check(StageRelease.decide(elapsed: 0.999, listed: chromeStaged, home: chromeHome, stage: stage) == .wait, "still on it at 999 ms: wait")
check(StageRelease.decide(elapsed: 1.0, listed: chromeStaged, home: chromeHome, stage: stage) == .remove(left: false),
      "still on it at the deadline: remove it all the same, the window not off it")
check(StageRelease.decide(elapsed: 5, listed: chromeStaged, home: chromeHome, stage: stage) == .remove(left: false), "past the deadline: remove")
check(StageRelease.decide(elapsed: 0.03, listed: chromeHome, home: chromeHome, stage: stage) == .remove(left: true), "home at 30 ms: remove now")
check(StageRelease.decide(elapsed: 0, listed: nil, home: chromeHome, stage: stage) == .remove(left: true), "a closed window: remove at once")
check(StageRelease.decide(elapsed: 0, listed: chromeHome, home: chromeHome, stage: stage) == .remove(left: true), "home already: remove at once")
check(StageRelease.commitDeadline == 1.0, "the deadline is prepare's own 1 s")
check(StageRelease.pollInterval > 0 && StageRelease.pollInterval <= 0.02, "the list read every 20 ms or less")

// MARK: afterRemoval

check(StageRelease.afterRemoval(listed: nil, settled: chromeHome, home: chromeHome) == .gone, "closed after the removal: nothing to watch")
check(StageRelease.afterRemoval(listed: chromeHome, settled: chromeHome, home: chromeHome) == .stay, "still home: stay")
check(StageRelease.afterRemoval(listed: chromeOnMain, settled: chromeHome, home: chromeHome) == .putBack,
      "macOS moved it to the main display after the removal: put it back")
check(StageRelease.afterRemoval(listed: chromeOnMain, settled: nil, home: chromeHome) == .putBack,
      "never left in time and dumped on the main display: put it back")
check(StageRelease.afterRemoval(listed: chromeHome, settled: nil, home: chromeHome) == .stay, "never left in time but home after all: stay")
let kept = CGRect(x: 640, y: 300, width: 1280, height: 800)                // its home display unplugged: kept on the main display
check(StageRelease.afterRemoval(listed: kept, settled: kept, home: chromeHome) == .stay,
      "kept on the main display (its home gone) and still there: stay, never a put-back to a home on no display")
check(StageRelease.afterRemoval(listed: chromeHome.offsetBy(dx: -2, dy: 2), settled: chromeHome, home: chromeHome) == .stay, "2 pt: the same place")
check(StageRelease.afterRemoval(listed: chromeHome.offsetBy(dx: 3, dy: 0), settled: chromeHome, home: chromeHome) == .putBack, "3 pt: moved")
check(StageRelease.afterRemoval(listed: CGRect(x: chromeHome.minX, y: chromeHome.minY, width: chromeHome.width, height: chromeHome.height + 3),
                                settled: chromeHome, home: chromeHome) == .putBack, "3 pt taller: another frame")
check(StageRelease.afterLook >= 1.0 && StageRelease.afterLook <= 3, "watched 1 to 3 s after the removal (macOS handled it within 0.2 s)")
check(StageRelease.afterPoll > 0 && StageRelease.afterPoll <= 0.2, "looked at every 200 ms or less")

// MARK: The model: a window server and an app that commits a move late

/// One way out, in virtual time (milliseconds from the Accessibility writes that send the window home). The app commits
/// the move `commit` ms after the writes (nil: never); the window server, at the display's removal, moves a window still on
/// the display to the main one, where an app that filled its screen fills the main display, its own late commit lost.
/// `removeAtOnce`: the order before 2026-11-12. Returns where the window ends, when the display went, and whether it was
/// put back.
let pollMs = Int((StageRelease.pollInterval * 1000).rounded())
let afterPollMs = Int((StageRelease.afterPoll * 1000).rounded())
let afterLookMs = Int((StageRelease.afterLook * 1000).rounded())
let deadlineMs = Int((StageRelease.commitDeadline * 1000).rounded())
func wayOut(commit: Int?, removeAtOnce: Bool, home: CGRect = chromeHome) -> (end: CGRect, removedAt: Int, putBack: Bool) {
    var now = 0
    var listed = chromeStaged
    var dumped = false
    func advance(to t: Int) {
        now = t
        if !dumped, let c = commit, now >= c { listed = home }
    }
    advance(to: 0)
    // The display's wait, as releaseHome reads the list.
    var settled: CGRect? = nil
    if !removeAtOnce {
        while true {
            let d = StageRelease.decide(elapsed: Double(now) / 1000, listed: listed, home: home, stage: stage)
            if case .remove(let off) = d { if off { settled = listed }; break }
            advance(to: now + max(1, pollMs))
        }
    }
    let removedAt = now
    if !StageRelease.leftStage(listed: listed, home: home, stage: stage) {
        listed = chromeOnMain
        dumped = true
    }
    // The look after the removal (none before 2026-11-12).
    var putBack = false
    if !removeAtOnce {
        var t = removedAt
        while t - removedAt < afterLookMs {
            t += max(1, afterPollMs)
            advance(to: t)
            let a = StageRelease.afterRemoval(listed: listed, settled: settled, home: home)
            if a == .putBack { listed = home; putBack = true; break }      // the put-back's own commit lands home
            if a == .gone { break }
        }
    }
    return (listed, removedAt, putBack)
}

var oldOrderLost = 0, newOrderHome = 0, cases = 0
var commits: [Int?] = Array(stride(from: 0, through: 2000, by: 5))
commits.append(nil)
for c in commits {
    cases += 1
    let words = c.map { "commit at \($0) ms" } ?? "no commit"
    let before = wayOut(commit: c, removeAtOnce: true)
    if !StageRelease.same(before.end, chromeHome) { oldOrderLost += 1 }
    let after = wayOut(commit: c, removeAtOnce: false)
    if StageRelease.same(after.end, chromeHome) { newOrderHome += 1 }
    else { check(false, "\(words): the window ended at \(after.end), not home") }
    // The spec, not the constants: an app that commits within 1 s is waited for (the display gone within 20 ms of the
    // commit) and never needs a put-back, which shows on the Mac as a jump to the main display and back; a later commit, or
    // none, sees the display go at 1 s and the window put back.
    if let c, c <= 1000 {
        check(after.removedAt >= c && after.removedAt < c + 20, "\(words): removed at \(after.removedAt) ms, not right after it")
        check(!after.putBack, "\(words): put back, though the window was home before the display went")
    } else {
        check(after.removedAt >= 1000 && after.removedAt < 1020, "\(words): removed at \(after.removedAt) ms, not at the deadline")
        check(after.putBack, "\(words): not put back after the deadline")
    }
}
// The race as it was: the display removed in the same millisecond lost every window whose app had not committed yet.
check(oldOrderLost == cases - 1, "the old order lost \(oldOrderLost) of \(cases) ways out (all but a commit at 0 ms)")
check(newOrderHome == cases, "the new order brought \(newOrderHome) of \(cases) windows home")

// MARK: The wiring, read as text

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
func source(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
let stageSource = source("Sources/SillHost/VirtualStage.swift")
let coordinator = source("Sources/SillHost/StreamCoordinator.swift")
check(!stageSource.isEmpty && !coordinator.isEmpty, "the sources read (\(root.path))")
check(stageSource.contains("func releaseHome() async"), "VirtualStage has its waiting way out")
check(stageSource.contains("StageRelease.decide(") && stageSource.contains("StageRelease.afterRemoval("),
      "releaseHome and its look after the removal follow StageRelease")
check(stageSource.contains("homeward = (p, display?.displayID)"), "releaseWindow notes the window on its way home and the display it left")
// select's Desktop or nothing: the display goes once the window is home.
check(coordinator.contains("                await stage.leaveFullScreenIfNeeded()\n                await stage.releaseHome()\n            }"),
      "select's Desktop or nothing waits for the window to leave Sill's display")
check(coordinator.contains("await stage.leaveFullScreenIfNeeded(); await stage.releaseHome()\n                if case .window = source"),
      "Virtual Display turned off waits for the window too")
check(coordinator.contains("if virtualDisplay { await stage.releaseHome() }   // nothing streams"), "a stream that did not start waits too")
// The teardowns cannot wait: Quit and the signals keep the synchronous way out.
if let quit = coordinator.range(of: "package func shutdownForExit() {") {
    let body = coordinator[quit.upperBound...].prefix(600)
    check(body.contains("stage.release()") && !body.contains("releaseHome"), "Quit keeps the synchronous way out")
} else { check(false, "shutdownForExit not found") }
check(coordinator.contains("guard !shuttingDown else { stage.release(); active = .none; broadcastList(); return }"),
      "a shutdown mid-switch keeps the synchronous way out")
// A pick of another window keeps the display: the old window home, nothing removed.
check(coordinator.contains("if let staged = stage.placement, staged.windowID != id {\n                    await stage.leaveFullScreenIfNeeded()\n                    stage.releaseWindow()\n                }"),
      "a pick of another window keeps the display (releaseWindow alone)")

print(failed == 0 ? "stage-release: \(passed) checks passed (the model: \(cases) commit times each way; the old order lost \(oldOrderLost))"
                  : "stage-release: \(failed) of \(passed + failed) checks FAILED")
exit(failed == 0 ? 0 : 1)
