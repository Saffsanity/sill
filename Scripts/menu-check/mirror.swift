// Scripts/menu-check/run.sh mirror: MenuMirror end to end against the fixture, with no host, network
// or encoder: the real MenuMirror, MenuReader, MenuPolicy, MenuFormat and StreamProtocol, with stubs
// for the server's send, a connection's state, Stats and print (all recorded). It drives the mirror
// as the coordinator does (fetch, press, setTarget, catalogPolled, clientLeft) and checks each kind
// 24 and log line (docs/menu-bar-plan.md §4.4, §4.7; H4–H8's and H10's logic). Presses go only to the
// fixture whose pid is given; a /bin/sleep it starts stands for an app whose top level cannot be
// read. usage (fixture.py runs it): mirror PID FIXTURE_LOG FIXTURE_BIN
import Foundation
import ApplicationServices

// MARK: Stubs of the host's types
enum WindowSizer { static func axErrorName(_ e: AXError) -> String { "AXError \(e.rawValue)" } }
final class Stats: @unchecked Sendable {
    static let shared = Stats()
    private let lock = NSLock(); private var counts: [String: Int] = [:]
    func bump(_ key: String) { lock.lock(); counts[key, default: 0] += 1; lock.unlock() }
    func take() -> [String: Int] { lock.lock(); defer { counts = [:]; lock.unlock() }; return counts }
}
final class FakeConnection {
    enum State { case ready, cancelled }
    var state: State = .ready
    let name: String
    init(_ name: String) { self.name = name }
}
struct Sent { let to: String; let at: Double; let m: MacMenu }
final class StreamServer: @unchecked Sendable {
    private let lock = NSLock(); private var log: [Sent] = []
    func send(_ message: StreamMessage, to c: FakeConnection) {
        guard message.kind == .macMenu, let m = Wire.decode(MacMenu.self, from: message.payload) else { return }
        lock.lock(); log.append(Sent(to: c.name, at: CFAbsoluteTimeGetCurrent(), m: m)); lock.unlock()
    }
    func all() -> [Sent] { lock.lock(); defer { lock.unlock() }; return log }
}
final class Lines: @unchecked Sendable {
    static let shared = Lines()
    private let lock = NSLock(); private var lines: [String] = []
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    func all() -> [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let s = items.map { "\($0)" }.joined(separator: separator)
    Lines.shared.add(s); Swift.print("  host: " + s, terminator: terminator)
}

// MARK: The run
let args = CommandLine.arguments
let pid = pid_t(args[1])!, fixtureLog = args[2], fixtureBin = args[3]
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) { checks += 1; if !ok { failures += 1; Swift.print("FAIL \(what)") } else { Swift.print("ok   \(what)") } }
func run(_ path: String, _ a: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = a
    let out = Pipe(); p.standardOutput = out; try? p.run(); p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
func label() -> String { run(fixtureBin, ["label", String(pid)]) }
func fixture() -> [String] { ((try? String(contentsOfFile: fixtureLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
func describe(_ it: MacMenuItem) -> String {
    if it.separator == true { return "—" }
    var s = "\(it.id ?? "?") \(it.title ?? "")"
    if it.submenu == true { s += " ▸" }; if let k = it.key { s += " \(k)" }; if let m = it.mark { s += " \(m)" }
    if it.enabled == false { s += " (off)" }
    return s
}
func dynamic(_ m: MacMenu?) -> Int { Int(m?.items?.compactMap { $0.title }.first { $0.hasPrefix("Dynamic ") }?.dropFirst(8) ?? "") ?? -1 }

@MainActor func main() async -> Int32 {
    let server = StreamServer()
    let mirror = MenuMirror(server: server)
    let fixtureTarget = MenuMirror.Target(pid: pid, app: "menufixture", bundleID: nil)
    var current: MenuMirror.Target? = fixtureTarget
    mirror.currentTarget = { current }
    mirror.prepare = { true }
    var subscribedEvents: [Bool] = []
    mirror.onSubscribersChanged = { subscribedEvents.append($0) }
    let A = FakeConnection("A"), B = FakeConnection("B")
    var token = 0
    func next() -> Int { token += 1; return token }
    func answer(_ c: FakeConnection, _ t: Int, timeout: Double = 4) async -> MacMenu? {
        let until = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < until {
            if let s = server.all().first(where: { $0.to == c.name && $0.m.answering == t }) { return s.m }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }
    func broadcasts(_ c: FakeConnection, after t: Double) -> [MacMenu] { server.all().filter { $0.to == c.name && $0.at >= t && $0.m.answering == nil }.map(\.m) }
    func fetch(_ c: FakeConnection, _ v: Int?, _ id: String?) async -> MacMenu? {
        let t = next(); mirror.fetch(FetchMenu(version: v, id: id, token: t), from: c, who: c.name); return await answer(c, t)
    }
    func press(_ c: FakeConnection, _ v: Int?, _ id: String, _ title: String?) async -> (MacMenu?, Double) {
        let t = next(); let t0 = CFAbsoluteTimeGetCurrent()
        mirror.press(PressMenuItem(version: v, id: id, title: title, token: t), from: c, who: c.name)
        let a = await answer(c, t); return (a, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }
    func sleep(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
    func lines(since n: Int) -> [String] { Array(Lines.shared.all().dropFirst(n)) }

    // H4: the subscription, File, Probe (read, cached, read again), Deep level by level.
    let sub = await fetch(A, nil, nil)
    check(sub?.version == 2 && sub?.answering == 1 && sub?.app == "menufixture" && sub?.menus?.map { $0.title ?? "" } == ["menufixture", "File", "Edit", "Probe"]
          && sub?.menus?.map { $0.id ?? "" } == ["1", "2", "3", "4"], "the subscription: v2's top level, menufixture File Edit Probe at 1–4")
    check(subscribedEvents == [true], "the first subscriber: onSubscribersChanged(true)")
    let v = sub?.version ?? 0
    let file = await fetch(A, v, "2")
    check(file?.items?.map(describe) == ["2.0 New ⌘N", "2.1 Open… ⌘O", "—", "2.3 Open Recent ▸", "—", "2.5 Close ⌘W (off)"], "File: \(file?.items?.map(describe) ?? [])")
    _ = Stats.shared.take()
    let p1 = await fetch(A, v, "4")
    let probeWant = ["4.0 Set Label A ⌥⌘A", "4.1 Set Label B ⌃⇧B", "—", "4.3 Checked ✓", "4.4 Mixed -", "4.5 Unavailable (off)", "—", "4.9 F5 Item F5",
                     "4.10 Delete Item ⌘⌫", "4.11 Up Item ⌃⌘↑", "4.12 Escape Item ⎋", "4.13 Space Item ⌥⌘Space", "4.14 Primary ⌘K", "4.15 Alternate ⌥⌘K"]
    let got = p1?.items?.map(describe) ?? []
    check(Array(got.prefix(14)) == probeWant && got.suffix(6) == ["4.16 Dynamic \(dynamic(p1))", "4.17 Slow Action", "4.18 Rebuilt ▸", "4.19 Deep ▸", "4.20 300 Items ▸", "4.21 600 Items ▸"],
          "Probe as §5's table (no Hidden, no custom-view or image-only item): \(got)")
    await sleep(0.4)
    let cb0 = fixture().filter { $0.contains("menuNeedsUpdate 'Probe'") }.count
    let p2 = await fetch(A, v, "4")
    let cb1 = fixture().filter { $0.contains("menuNeedsUpdate 'Probe'") }.count
    await sleep(1.2)
    let p3 = await fetch(A, v, "4")
    let cb2 = fixture().filter { $0.contains("menuNeedsUpdate 'Probe'") }.count
    let stats = Stats.shared.take()
    check(p2?.items == p1?.items && cb1 == cb0 && stats["menu.cached"] == 1, "a fetch 0.4 s after the read: from the cache (no fixture callback, menu.cached 1; Dynamic \(dynamic(p1)) → \(dynamic(p2)))")
    check(dynamic(p3) > dynamic(p2) && cb2 == cb1 + 1 && stats["menu.read"] == 2, "a fetch 1.6 s after: read again (Dynamic \(dynamic(p3)), menu.read \(stats["menu.read"] ?? 0))")
    let d1 = await fetch(A, v, "4.19"), d2 = await fetch(A, v, "4.19.0"), d3 = await fetch(A, v, "4.19.0.0")
    check(d1?.items?.map(describe) == ["4.19.0 Level 2 ▸"] && d2?.items?.map(describe) == ["4.19.0.0 Level 3 ▸"] && d3?.items?.map(describe) == ["4.19.0.0.0 Deep Leaf"],
          "Deep level by level")
    let six = await fetch(A, v, "4.21")
    check(six?.items?.count == 500 && six?.more == 100, "600 Items: 500 items, more 100")

    // H5: presses.
    await sleep(1.1)
    var n = Lines.shared.all().count
    var (a, ms) = await press(A, v, "4.0", "Set Label A")
    check(a?.pressed == true && label() == "A" && lines(since: n).contains("Menu from A: menufixture › Probe › Set Label A"), "4.0 pressed in \(Int(ms)) ms, the label A, the host's line")
    (a, ms) = await press(A, v, "4.19.0.0.0", "Deep Leaf")
    check(a?.pressed == true && label() == "Deep" && Lines.shared.all().contains("Menu from A: menufixture › Probe › Deep › Level 2 › Level 3 › Deep Leaf"), "Deep Leaf pressed, the label Deep")
    (a, ms) = await press(A, v, "4.5", "Unavailable")
    check(a?.pressed == false && a?.note == "It isn’t available right now." && Lines.shared.all().contains("Menu from A refused: menufixture › Probe › Unavailable: disabled"), "4.5 refused, disabled")
    await sleep(1.0)
    (a, ms) = await press(A, v, "4.1", "Set Label A")
    check(a?.pressed == false && a?.note == "The menus changed. Open the menu again." && Lines.shared.all().contains("Menu from A refused: menufixture › Probe › Set Label B: the menus changed"),
          "4.1 kept, under another title: refused, the menus changed")
    let deepBefore = fixture().filter { $0.contains("'Deep'") }.count
    (a, ms) = await press(A, v, "4", "Probe")
    check(a?.pressed == false && ms < 100 && Lines.shared.all().contains("Menu from A refused: menufixture › Probe: the menus changed"), "4, a bar item: refused in \(Int(ms)) ms")
    (a, ms) = await press(A, v, "4.19", "Deep")
    check(a?.pressed == false && ms < 100 && Lines.shared.all().contains("Menu from A refused: menufixture › Probe › Deep: the menus changed"), "4.19, a submenu item: refused in \(Int(ms)) ms")
    await sleep(0.3)
    check(fixture().filter { $0.contains("'Deep'") }.count == deepBefore, "…nothing named Deep in the fixture's log after them: nothing opened")
    check(!fixture().contains { $0.hasSuffix("ACTION Deep") || $0.contains("ACTION Probe") }, "…no action ran")
    (a, ms) = await press(A, 1, "4.0", "Set Label A")
    check(a?.pressed == false && a?.note == "The menus changed. Open the menu again." && Lines.shared.all().contains("Menu from A refused: 4.0: the menus changed"),
          "an older version (1): refused, the line giving the id")
    (a, ms) = await press(A, v, "4.0", nil)
    check(a?.pressed == false, "a press without a title: refused")

    // H6: Dynamic N; a rebuilt menu.
    await sleep(1.1)
    let q1 = await fetch(A, v, "4"); await sleep(0.3)
    (a, ms) = await press(A, v, "4.16", "Dynamic \(dynamic(q1))")
    check(a?.pressed == true && label() == "Dynamic \(dynamic(q1))", "Dynamic \(dynamic(q1)) pressed 0.3 s after its fetch")
    await sleep(1.4)
    let q2 = await fetch(A, v, "4"); await sleep(1.5)
    (a, ms) = await press(A, v, "4.16", "Dynamic \(dynamic(q2))")
    check(a?.pressed == false && a?.note == "The menus changed. Open the menu again.", "Dynamic \(dynamic(q2)) pressed 1.5 s after its fetch: refused")
    let r = await fetch(A, v, "4.18")
    check(r?.items?.map(describe) == ["4.18.0 Rebuilt Leaf"], "Rebuilt's leaf")
    kill(pid, SIGUSR1); await sleep(0.3)
    n = Lines.shared.all().count
    (a, ms) = await press(A, v, "4.18.0", "Rebuilt Leaf")
    check(a?.pressed == true && label() == "Rebuilt" && lines(since: n).contains("Menu from A: menufixture › Probe › Rebuilt › Rebuilt Leaf"), "rebuilt, the same title: found again by its path, pressed")
    kill(pid, SIGUSR2); await sleep(0.3)
    n = Lines.shared.all().count
    (a, ms) = await press(A, v, "4.18.0", "Rebuilt Leaf")
    check(a?.pressed == false && label() == "Rebuilt" && lines(since: n).contains("Menu from A refused: menufixture › Probe › Rebuilt › Renamed Leaf: the menus changed"),
          "rebuilt as Renamed Leaf: refused, the line naming the title found there")

    // H7: rates.
    await sleep(1.1)
    n = Lines.shared.all().count
    var tokens: [Int] = []
    for _ in 0..<50 { let t = next(); tokens.append(t); mirror.fetch(FetchMenu(version: v, id: "4", token: t), from: A, who: "A") }
    var answers: [MacMenu] = []
    for t in tokens { if let m = await answer(A, t) { answers.append(m) } }
    let served = answers.filter { $0.note == nil && ($0.items?.isEmpty == false) }.count, tooMany = answers.filter { $0.note == "Too many requests. Open the menu again." }.count
    check(answers.count == 50 && served == 20 && tooMany == 30, "50 fetches at once: \(served) served, \(tooMany) too many")
    check(lines(since: n).filter { $0 == "Menus from A ignored: more than 20 requests a second." }.count == 1, "one ignored line for them")
    await sleep(1.1)
    n = Lines.shared.all().count
    var ptoks: [Int] = []
    for _ in 0..<10 { let t = next(); ptoks.append(t); mirror.press(PressMenuItem(version: v, id: "4.0", title: "Set Label A", token: t), from: A, who: "A") }
    var pans: [MacMenu] = []
    for t in ptoks { if let m = await answer(A, t) { pans.append(m) } }
    check(pans.filter { $0.pressed == true }.count == 4 && pans.filter { $0.pressed == false && $0.note == "Too many requests. Open the menu again." }.count == 6, "ten presses at once: 4 pressed, 6 too many")
    check(lines(since: n).filter { $0 == "Menus from A ignored: more than 4 choices a second." }.count == 1, "one ignored line for them")

    // H10's mirror part: an action that holds the app's main thread.
    await sleep(1.1)
    n = Lines.shared.all().count
    let tSlow = CFAbsoluteTimeGetCurrent()
    (a, ms) = await press(A, v, "4.17", "Slow Action")
    check(a?.pressed == true, "Slow Action pressed in \(Int(ms)) ms")
    let s1 = await fetch(A, v, "4")
    check(s1?.stale == true && s1?.note == "menufixture isn’t responding." && s1?.items == [], "a fetch while it runs: stale, menufixture isn’t responding.")
    check(broadcasts(A, after: tSlow).contains { $0.stale == true && $0.version == v }, "…and a stale top level of the same version to the subscriber")
    check(lines(since: n).contains("Menus of menufixture not answering (1.0 s); shown as unavailable until it answers."), "…the host's not answering line")
    (a, ms) = await press(A, v, "4.0", "Set Label A")
    check(a?.pressed == false && a?.note == "menufixture isn’t responding.", "a press while stale: refused")
    await sleep(max(0, 2.4 - (CFAbsoluteTimeGetCurrent() - tSlow)))
    let tBack = CFAbsoluteTimeGetCurrent()
    mirror.catalogPolled(); await sleep(0.5)
    check(Lines.shared.all().contains("Menus of menufixture answering again.") && broadcasts(A, after: tBack).contains { $0.stale == nil && $0.version == v && $0.menus?.count == 4 },
          "a poll after the action: answering again, the top level sent fresh")

    // A second subscriber; the same app in another window; the target moves.
    let tB = CFAbsoluteTimeGetCurrent()
    let subB = await fetch(B, nil, nil)
    check(subB?.version == v && subB?.menus?.count == 4 && broadcasts(A, after: tB).isEmpty, "a second subscriber gets the top level; the first gets nothing new")
    let tW = CFAbsoluteTimeGetCurrent()
    mirror.setTarget(MenuMirror.Target(pid: pid, app: "menufixture", bundleID: nil, window: 7)); await sleep(0.3)
    let w = await fetch(A, v, "2")
    check(broadcasts(A, after: tW).isEmpty && w?.items?.count == 6 && mirror.version == v, "another window of the same app: the same version, nothing sent, a fetch served")
    let tN = CFAbsoluteTimeGetCurrent()
    current = nil; mirror.setTarget(nil); await sleep(0.2)
    check(broadcasts(A, after: tN).map { "\($0.version ?? -1) \($0.menus?.count ?? -1)" } == ["\(v + 1) 0"] && broadcasts(B, after: tN).count == 1, "no target: v+1 with no menus, to both")
    let tT = CFAbsoluteTimeGetCurrent()
    current = fixtureTarget; mirror.setTarget(fixtureTarget); await sleep(0.5)
    check(broadcasts(A, after: tT).map { "\($0.version ?? -1) \($0.menus?.count ?? -1)" } == ["\(v + 2) 4"], "the fixture again: v+2 with its menus")
    let old = await fetch(A, v, "4")
    check(old?.note == "The menus changed. Open the menu again." && old?.items == [], "a fetch with the old version: the menus changed")
    for junk in ["0", "04", "a", "-1", "1.1.1.1.1.1.1.1.1", "4.99"] {
        let j = await fetch(A, v + 2, junk)
        check(j?.note == "The menus changed. Open the menu again.", "a fetch of \(junk): the menus changed")
    }

    // C5: a target whose top level cannot be read (a process with no Accessibility server: quick
    // errors, `failed`) sends nothing; each poll reads it again; once gone, no menus are sent.
    let sleeper = Process(); sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep"); sleeper.arguments = ["30"]; try? sleeper.run()
    let tS = CFAbsoluteTimeGetCurrent()
    let sleepTarget = MenuMirror.Target(pid: sleeper.processIdentifier, app: "sleep", bundleID: nil)
    current = sleepTarget; mirror.setTarget(sleepTarget); await sleep(1.0)
    let vS = mirror.version
    check(vS == v + 3 && broadcasts(A, after: tS).isEmpty, "a top level that fails to read: v+3, and nothing sent (\(broadcasts(A, after: tS).map { "\($0.version ?? -1) \($0.menus?.count ?? -1)" }))")
    mirror.catalogPolled(); await sleep(1.0)
    check(broadcasts(A, after: tS).isEmpty, "…a poll reads it again, and still nothing is sent")
    sleeper.terminate(); sleeper.waitUntilExit()
    let tG = CFAbsoluteTimeGetCurrent()
    mirror.catalogPolled(); await sleep(1.0)
    check(broadcasts(A, after: tG).map { "\($0.version ?? -1) \($0.menus?.count ?? -1)" } == ["\(vS + 1) 0"], "…the next poll finds the process gone: v+1 with no menus")
    current = fixtureTarget; mirror.setTarget(fixtureTarget); await sleep(0.5)
    let vF = mirror.version

    // H8: the app quits.
    // The runner, the fixture's parent, kills and reaps it: a zombie still answers kill(pid, 0).
    let request = fixtureLog + ".kill"
    FileManager.default.createFile(atPath: request, contents: nil)
    while FileManager.default.fileExists(atPath: request) { await sleep(0.05) }
    check(!MenuReader.alive(pid), "the fixture is gone (killed and reaped by its parent)")
    let tK = CFAbsoluteTimeGetCurrent()
    let gone = await fetch(A, vF, "4")
    let sentK = broadcasts(A, after: tK).map { "\($0.version ?? -1) \($0.menus?.count ?? -1)" }
    check(gone?.note == "menufixture is no longer open." && sentK == ["\(vF + 1) 0"],
          "the fixture killed: the fetch refused (\(gone?.note ?? "no answer")); v+1 with no menus sent (\(sentK))")

    // Leaving.
    mirror.clientLeft(A); check(subscribedEvents == [true], "one subscriber left: nothing")
    mirror.clientLeft(B); check(subscribedEvents == [true, false] && !mirror.hasSubscribers, "the last left: onSubscribersChanged(false)")
    Swift.print("\(checks - failures) of \(checks) checks passed")
    return failures == 0 ? 0 : 1
}
exit(await main())
