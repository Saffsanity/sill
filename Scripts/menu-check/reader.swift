// Scripts/menu-check/run.sh reader|budget: MenuReader against the fixture, with no host, network or
// encoder: its reads and presses as the mirror makes them (docs/menu-bar-plan.md, the critique's
// C1–C3, and H4–H6's and H10's reader-level parts). Presses go only to the fixture whose pid is
// given. usage (fixture.py runs it): reader PID FIXTURE_LOG FIXTURE_BIN [budget]
// The ids are the fixture's (§5's table): Deep 4.19, Dynamic N 4.16, Rebuilt 4.18, 600 Items 4.21.
import Foundation
import ApplicationServices

enum WindowSizer { static func axErrorName(_ e: AXError) -> String { "AXError \(e.rawValue)" } }

let args = CommandLine.arguments
let pid = pid_t(args[1])!, fixtureLog = args[2], fixtureBin = args[3]
let budgetRun = args.count > 4 && args[4] == "budget"
let r = MenuReader()
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) { checks += 1; if !ok { failures += 1; print("FAIL \(what)") } else { print("ok   \(what)") } }
func onQueue<T>(_ f: () -> T) -> T { r.queue.sync(execute: f) }
func log() -> [String] { ((try? String(contentsOfFile: fixtureLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
func label() -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: fixtureBin); p.arguments = ["label", String(pid)]
    let out = Pipe(); p.standardOutput = out; try? p.run(); p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
func front() -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo"); p.arguments = ["front"]
    let out = Pipe(); p.standardOutput = out; try? p.run(); p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
func path(_ id: String) -> MenuPath { MenuPath(id)! }
/// The fixture's log lines written during `body`, and its result.
func watching<T>(_ body: () -> T) -> (T, [String]) {
    let before = log().count
    let v = body()
    Thread.sleep(forTimeInterval: 0.15)
    return (v, Array(log().dropFirst(before)))
}
func items(_ id: String, of parent: AXUIElement?) -> MenuReader.Menu? {
    if case .success(let m) = onQueue({ r.items(pid: pid, of: parent, path: path(id)) }) { return m }
    return nil
}
func press(_ id: String, _ element: AXUIElement?, shown: String?) -> (MenuReader.Pressed, Double, [String]) {
    let t = CFAbsoluteTimeGetCurrent()
    let (p, lines) = watching { onQueue { r.press(pid: pid, element: element, path: path(id), shownTitle: shown) } }
    return (p, (CFAbsoluteTimeGetCurrent() - t - 0.15) * 1000, lines)
}
let front0 = front()

guard case .success(let top) = onQueue({ r.topLevel(pid: pid) }) else { print("FAIL top level unreadable"); exit(1) }
let topTitles = top.titles.map { $0.item.title ?? "" }
check(topTitles == ["menufixture", "File", "Edit", "Probe"] && top.titles.map(\.index) == [1, 2, 3, 4],
      "top level: menufixture, File, Edit, Probe at 1–4 (\(topTitles))")
let probeBar = top.titles.first { $0.index == 4 }!.element

if budgetRun {
    // The read budget, in a build whose readBudget is 0.005 s: 600 Items stops early and counts the rest.
    check(MenuReader.readBudget < 0.01, "this build's readBudget is \(MenuReader.readBudget) s")
    if let probe = items("4", of: probeBar) {
        let stoppedEarly = probe.unread > 0
        check(probe.total == 22 && probe.unread == 22 - (probe.reads.last.map { $0.index + 1 } ?? 0)
              && (stoppedEarly ? probe.ms >= MenuReader.readBudget * 1000 : probe.reads.count == 22),
              "Probe within the budget: \(probe.reads.count) read, unread \(probe.unread) of \(probe.total) in \(String(format: "%.1f", probe.ms)) ms (stopped early only past the budget)")
    } else { check(false, "Probe readable") }
    guard let m = items("4.21", of: nil) else { print("FAIL 600 Items unreadable"); exit(1) }
    check(m.total == 600 && m.reads.count < 500 && m.reads.count >= 1 && m.unread == 600 - m.reads.count,
          "600 Items within the budget: \(m.reads.count) read, unread \(m.unread) of \(m.total), in \(String(format: "%.1f", m.ms)) ms")
    print("\(checks - failures) of \(checks) checks passed"); exit(failures == 0 ? 0 : 1)
}

// Probe's items, kept as the mirror keeps them.
guard let probe = items("4", of: probeBar) else { print("FAIL Probe unreadable"); exit(1) }
var kept: [String: (AXUIElement, String)] = [:]
for read in probe.reads { if let t = read.item.title { kept["4.\(read.index)"] = (read.element, t) } }
print("Probe: " + probe.reads.map { "4.\($0.index) \($0.item.title ?? "nil")" }.joined(separator: " | "))
let deepID = kept.first { $0.value.1 == "Deep" }!.key
let dynamicID = kept.first { $0.value.1.hasPrefix("Dynamic ") }!.key
let rebuiltID = kept.first { $0.value.1 == "Rebuilt" }!.key
check(deepID == "4.19", "Deep is \(deepID) (4.19 with the hidden item left out)")
check(label() == "none", "the label starts as none")

// C1: a bar item and a submenu item are refused, and nothing opens.
var (p, ms, lines) = press("4", probeBar, shown: "Probe")
check(p.outcome == .refused(.changed) && lines.isEmpty, "a bar item (4, Probe): refused, the menus changed, in \(Int(ms)) ms, no fixture callback (\(lines))")
(p, ms, lines) = press(deepID, kept[deepID]!.0, shown: "Deep")
check(p.outcome == .refused(.changed), "a submenu item (\(deepID), Deep), kept: refused in \(Int(ms)) ms")
check(!lines.contains { $0.contains("'Deep'") } && !lines.contains { $0.contains("ACTION") },
      "…and nothing named Deep in the fixture's log after it: nothing opened (\(lines.filter { !$0.contains("validateMenuItem") }))")
(p, ms, lines) = press(deepID, nil, shown: "Deep")
check(p.outcome == .refused(.changed), "a submenu item found again by its path: refused in \(Int(ms)) ms")
check(!lines.contains { $0.contains("'Deep'") } && !lines.contains { $0.contains("ACTION") }, "…nothing named Deep opened (\(lines.filter { $0.contains("Deep") }))")

// Presses of leaves.
(p, ms, lines) = press("4.0", kept["4.0"]!.0, shown: "Set Label A")
check(p.outcome == .pressed && lines.contains { $0.hasSuffix("ACTION Set Label A") } && label() == "A",
      "4.0 kept, its title the one shown: pressed in \(Int(ms)) ms, ACTION Set Label A, the label A")
(p, ms, lines) = press("4.1", kept["4.1"]!.0, shown: "Set Label A")
check(p.outcome == .refused(.changed) && !lines.contains { $0.contains("ACTION") } && label() == "A",
      "4.1 kept but another title shown (Set Label A): refused, no ACTION, the label still A")
(p, ms, lines) = press("4.1", nil, shown: "Set Label B")
check(p.outcome == .pressed && p.foundTitle == "Set Label B" && label() == "B", "4.1 found again by its path: pressed, found as Set Label B, the label B")
(p, ms, lines) = press("4.5", kept["4.5"]!.0, shown: "Unavailable")
check(p.outcome == .refused(.disabled) && !lines.contains { $0.contains("ACTION") }, "4.5 Unavailable: refused, disabled, no ACTION")
(p, ms, lines) = press("4.2", kept["4.2"]?.0, shown: "")
check(p.outcome == .refused(.changed) && !lines.contains { $0.contains("ACTION") }, "4.2, the separator, with an empty title: refused")
(p, ms, lines) = press("4.0", kept["4.0"]!.0, shown: String(repeating: "x", count: 100_000))
check(p.outcome == .refused(.changed) && !lines.contains { $0.contains("ACTION") }, "4.0 with a long other title: refused")

// Dynamic N (H6): pressed within AppKit's second after the read, refused once the press's own read
// validates the menu again and retitles it.
Thread.sleep(forTimeInterval: 1.2)
guard let probe2 = items("4", of: probeBar) else { print("FAIL Probe unreadable"); exit(1) }
let dyn = probe2.reads.first { "4.\($0.index)" == dynamicID }!
let dynTitle = dyn.item.title!
Thread.sleep(forTimeInterval: 0.3)
(p, ms, lines) = press(dynamicID, dyn.element, shown: dynTitle)
check(p.outcome == .pressed && label() == dynTitle, "\(dynamicID) \(dynTitle) pressed 0.3 s after the read: pressed, the label \(dynTitle) (\(lines.filter { !$0.contains("validateMenuItem '") || $0.contains("Dynamic") }))")
Thread.sleep(forTimeInterval: 1.5)
(p, ms, lines) = press(dynamicID, dyn.element, shown: dynTitle)
check(p.outcome == .refused(.changed) && !lines.contains { $0.contains("ACTION") },
      "\(dynamicID) \(dynTitle) pressed 1.8 s after the read: refused, the menus changed (\(lines.filter { $0.contains("Dynamic") || $0.contains("menuNeedsUpdate") }))")

// Rebuilt (H6): the same title found again by its path; renamed, refused.
guard let rebuilt = items(rebuiltID, of: kept[rebuiltID]!.0), let leaf = rebuilt.reads.first else { print("FAIL Rebuilt unreadable"); exit(1) }
check(leaf.item.title == "Rebuilt Leaf", "Rebuilt's leaf read: \(leaf.item.title ?? "nil")")
kill(pid, SIGUSR1); Thread.sleep(forTimeInterval: 0.3)
(p, ms, lines) = press("\(rebuiltID).\(leaf.index)", leaf.element, shown: "Rebuilt Leaf")
check(p.outcome == .pressed && p.foundTitle == "Rebuilt Leaf" && label() == "Rebuilt",
      "rebuilt with the same title: found again by its path, pressed, the label Rebuilt (found \(p.foundTitle ?? "nil"))")
kill(pid, SIGUSR2); Thread.sleep(forTimeInterval: 0.3)
(p, ms, lines) = press("\(rebuiltID).\(leaf.index)", leaf.element, shown: "Rebuilt Leaf")
check(p.outcome == .refused(.changed) && p.foundTitle == "Renamed Leaf" && label() == "Rebuilt",
      "rebuilt as Renamed Leaf: refused, found Renamed Leaf, the label unchanged")

// Deep, level by level, then its leaf (H4/H5's).
guard let d1 = items(deepID, of: kept[deepID]!.0), let l2 = d1.reads.first,
      let d2 = items("\(deepID).\(l2.index)", of: l2.element), let l3 = d2.reads.first,
      let d3 = items("\(deepID).\(l2.index).\(l3.index)", of: l3.element), let deepLeaf = d3.reads.first else { print("FAIL Deep unreadable"); exit(1) }
check(l2.item.title == "Level 2" && l3.item.title == "Level 3" && deepLeaf.item.title == "Deep Leaf", "Deep › Level 2 › Level 3 › Deep Leaf")
(p, ms, lines) = press("\(deepID).\(l2.index).\(l3.index).\(deepLeaf.index)", deepLeaf.element, shown: "Deep Leaf")
check(p.outcome == .pressed && label() == "Deep", "Deep Leaf: pressed, the label Deep")

// 600 Items: 500 read, 100 more.
let six = probe.reads.first { $0.item.title == "600 Items" }!
if let m = items("4.\(six.index)", of: six.element) {
    check(m.reads.count == 500 && m.unread == 100 && m.total == 600, "600 Items: 500 read, 100 unread, in \(String(format: "%.0f", m.ms)) ms (budget \(MenuReader.readBudget) s)")
} else { check(false, "600 Items readable") }

// Slow Action (H10's reader part): pressed, whether AXPress answers before the action runs or
// after its 1 s timeout; a read while the action holds the app's main thread runs into the timeout.
let slow = probe.reads.first { $0.item.title == "Slow Action" }!
let tSlow = CFAbsoluteTimeGetCurrent()
(p, ms, lines) = press("4.\(slow.index)", slow.element, shown: "Slow Action")
check(p.outcome == .pressed || p.outcome == .pressedNoAnswer, "Slow Action: \(p.outcome) after \(Int(ms)) ms")
print("note Slow Action's AXPress answered after \(Int(ms)) ms (\(p.outcome == .pressed ? "before its action ran" : "at the timeout"))")
let tRead = CFAbsoluteTimeGetCurrent()
let during = onQueue { r.items(pid: pid, of: probeBar, path: path("4")) }
let readMS = (CFAbsoluteTimeGetCurrent() - tRead) * 1000
if case .failure(.notAnswering) = during {
    check(readMS >= 900 && readMS < 1600, "a read of Probe while the action sleeps: not answering, after \(Int(readMS)) ms")
} else if CFAbsoluteTimeGetCurrent() - tSlow > 2 {
    check(true, "the action was over before the read (\(during))")
} else { check(false, "a read of Probe while the action sleeps: \(during) after \(Int(readMS)) ms") }
Thread.sleep(forTimeInterval: max(0, 2.3 - (CFAbsoluteTimeGetCurrent() - tSlow)))
check(log().contains { $0.hasSuffix("ACTION Slow Action done") }, "…its action finished")
if case .success = onQueue({ r.topLevel(pid: pid) }) { check(true, "…and the app answers again") } else { check(false, "the app answers again") }

check(front() == front0, "the frontmost app the same before and after (\(front0))")
print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
