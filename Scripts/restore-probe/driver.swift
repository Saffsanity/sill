import Foundation
import AppKit
import ScreenCaptureKit
import ApplicationServices

// TEST ONLY. The restore probe's driver (Scripts/restore-probe/run.sh; issue #57,
// docs/restore-window-frames-plan.md). It runs `owner`, a window of its own, finds that window through
// ScreenCaptureKit as the catalog does, fits it with the real WindowSizer.resize (WindowRestore.fit
// through Accessibility) as StreamCoordinator.fitToViewport does, into the same WindowRestore.Ledger
// the coordinator keeps, and puts it back with the ledger's restore (WindowRestore.stop through
// WindowSizer.AXWindows) as restoreFits does, printing each frame. Never another app's window, never
// input, never a virtual display, never focus: the front app (`lsappinfo front`) is read before and
// after each step and must not change.
// usage: driver OWNER-EXECUTABLE

let ownerPath = CommandLine.arguments[1]

final class Owner {
    let proc = Process()
    let inPipe = Pipe(), outPipe = Pipe()
    private let lock = NSLock()
    private var lines: [String] = []
    private(set) var pid: pid_t = 0
    private(set) var windowID: CGWindowID = 0

    init(_ token: String, _ r: CGRect, fixed: Bool = false) throws {
        proc.executableURL = URL(fileURLWithPath: ownerPath)
        proc.arguments = [token, "\(Int(r.minX))", "\(Int(r.minY))", "\(Int(r.width))", "\(Int(r.height))"] + (fixed ? ["fixed"] : [])
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard let self, !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            self.lock.lock(); self.lines += s.split(separator: "\n").map(String.init); self.lock.unlock()
        }
        try proc.run()
        guard let ready = wait({ $0.hasPrefix("ready ") }) else { proc.terminate(); throw NSError(domain: "owner", code: 1) }
        let p = ready.split(separator: " ")
        pid = pid_t(p[1])!; windowID = CGWindowID(p[2])!
    }
    func wait(_ match: (String) -> Bool, timeout: TimeInterval = 5) -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            lock.lock(); let hit = lines.first(where: match); if let hit { lines.removeAll { $0 == hit } }; lock.unlock()
            if let hit { return hit }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }
    /// The person at the Mac does something to the window (its own app does it).
    func send(_ cmd: String) {
        inPipe.fileHandleForWriting.write((cmd + "\n").data(using: .utf8)!)
        _ = wait({ $0 == "ok " + cmd })
        Thread.sleep(forTimeInterval: 0.2)       // until the window server shows it
    }
    func end() {
        if proc.isRunning { kill(pid, SIGCONT); inPipe.fileHandleForWriting.write("quit\n".data(using: .utf8)!) }
        proc.waitUntilExit()
    }
}

func fmt(_ r: CGRect?) -> String { r.map(WindowRestore.text) ?? "(none)" }

/// The front app as Launch Services has it, read without this process's AppKit run loop.
func frontApp() -> String {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
    p.arguments = ["front"]
    p.standardOutput = out
    try? p.run(); p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
}

@MainActor
final class Probe {
    let sizer = WindowSizer()
    var ledger = WindowRestore.Ledger<WindowSizer.Placement>()
    var passed = 0, failed = 0
    let front = frontApp()

    func scwindow(_ id: CGWindowID) async -> SCWindow? {
        for _ in 0..<30 {
            if let c = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
               let w = c.windows.first(where: { $0.windowID == id }) { return w }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func live(_ id: CGWindowID) -> CGRect? { WindowSizer.liveBounds(of: id) }

    /// StreamCoordinator.fitToViewport, as written (the viewport's target already worked out).
    func fit(_ w: SCWindow, _ target: CGSize) -> String {
        let current = WindowSizer.liveBounds(of: w.windowID)?.size ?? w.frame.size
        if abs(current.width - target.width) <= 2, abs(current.height - target.height) <= 2 { return "already there" }
        guard let fit = sizer.resize(window: w, to: target) else { return "resize refused" }
        ledger.fitted(w.windowID, handle: fit.placement, before: fit.before, after: fit.after, asked: target)
        return "fitted from \(fmt(fit.before)) to \(fmt(fit.after)) (asked \(Int(target.width))×\(Int(target.height)))"
    }

    /// StreamCoordinator.restoreFits, as written (nothing is staged here).
    func stop(keeping: CGWindowID?) -> [String] {
        var out: [String] = []
        var windows = WindowSizer.AXWindows(sizer: sizer)
        for s in ledger.restore(keeping: keeping, staged: nil, on: &windows) {
            if let decision = s.decision { out.append("decision \(decision)") }
            if let line = s.line { out.append(line) }
        }
        return out
    }

    func expect(_ what: String, _ got: CGRect?, _ want: CGRect?) {
        let ok: Bool
        if let got, let want { ok = WindowRestore.same(got, want) } else { ok = got == nil && want == nil }
        tally(ok, "\(what): \(fmt(got))\(ok ? "" : ", expected \(fmt(want))")")
    }
    func tally(_ ok: Bool, _ what: String) {
        if ok { passed += 1 } else { failed += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
    }
    func settle() async { try? await Task.sleep(for: .milliseconds(250)) }

    func open(_ tag: String, _ r: CGRect, fixed: Bool = false) async -> (Owner, SCWindow)? {
        guard let o = try? Owner("Sill restore probe \(tag) \(UUID().uuidString.prefix(8))", r, fixed: fixed) else {
            tally(false, "\(tag): the probe's window did not come up"); return nil
        }
        guard let w = await scwindow(o.windowID) else { o.end(); tally(false, "\(tag): ScreenCaptureKit did not list it"); return nil }
        // The window must be where its app put it, as Accessibility and the window server see it: not
        // so while the screen is locked (the window server shows it transformed and Accessibility
        // lists no window), which run.sh refuses before this.
        guard let e = sizer.element(for: w), let ax = WindowSizer.frame(of: e), WindowRestore.same(ax, r) else {
            o.end(); tally(false, "\(tag): Accessibility does not see the window at \(fmt(r)) (\(fmt(live(w.windowID))) listed)"); return nil
        }
        return (o, w)
    }

    func run() async {
        guard let area = WindowSizer.visibleArea(around: CGDisplayBounds(CGMainDisplayID())) else { print("no display"); exit(2) }
        // Lower left of the main display, behind every other window.
        let S0 = CGRect(x: area.minX + 20, y: area.minY + 40, width: min(900, area.width - 80), height: min(600, area.height - 120))
        let pad = CGSize(width: 667, height: 473)            // a 1000×710 panel at Aa 1.5×
        let tall = CGSize(width: 473, height: 667)           // the same, upright
        let movedTo = CGPoint(x: area.minX + 280, y: area.minY + 140)
        let movedHome = CGRect(origin: WindowRestore.keep(CGRect(origin: movedTo, size: S0.size), in: area), size: S0.size)
        print("Main display's visible area \(fmt(area)); the probe's window starts at \(fmt(S0)). Front app: \(front)")

        print("1. A fit, then the window stops streaming: its whole frame back")
        if let (o, w) = await open("whole", S0) {
            print("  before  \(fmt(live(w.windowID)))")
            print("  " + fit(w, pad)); await settle()
            print("  during  \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), S0)
            o.end()
        }

        print("2. A fit, a rotation's re-fit, then a stop: the first frame back")
        if let (o, w) = await open("refit", S0) {
            print("  " + fit(w, pad)); await settle()
            print("  " + fit(w, tall)); await settle()
            print("  during  \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), S0)
            o.end()
        }

        print("3. A fit, moved on the Mac, then a stop: its own size where it was moved")
        if let (o, w) = await open("moved", S0) {
            print("  " + fit(w, pad)); await settle()
            o.send("move \(Int(movedTo.x)) \(Int(movedTo.y))")
            print("  moved   \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), movedHome)
            o.end()
        }

        print("4. A fit, moved, a rotation's re-fit where it was moved, then a stop: it keeps its new place")
        if let (o, w) = await open("movedrefit", S0) {
            print("  " + fit(w, pad)); await settle()
            o.send("move \(Int(movedTo.x)) \(Int(movedTo.y))")
            print("  " + fit(w, tall)); await settle()
            print("  during  \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), movedHome)
            o.end()
        }

        print("5. A fit, resized on the Mac, then a stop: left alone")
        if let (o, w) = await open("resized", S0) {
            print("  " + fit(w, pad)); await settle()
            o.send("size 720 520")
            print("  resized \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), CGRect(x: S0.minX, y: S0.minY, width: 720, height: 520))
            o.end()
        }

        print("6. An app whose minimum is above the size asked: back to its frame")
        if let (o, w) = await open("minimum", S0) {
            o.send("min 800 540")
            print("  " + fit(w, pad)); await settle()
            print("  during  \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), S0)
            o.end()
        }

        print("7. A fit, then the window closes: nothing to put back, no line")
        if let (o, w) = await open("gone", S0) {
            print("  " + fit(w, pad)); await settle()
            o.send("close"); await settle()
            let lines = stop(keeping: nil)
            tally(lines == ["decision gone"], "gone: \(lines)")
            o.end()
        }

        print("8. Near the right edge, a larger size asked: the fit's nudge undone with the rest")
        let edge = CGRect(x: area.maxX - 500, y: area.minY + 200, width: 480, height: 360)
        if let (o, w) = await open("nudge", edge) {
            print("  " + fit(w, CGSize(width: 1000, height: 710))); await settle()
            print("  during  \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), edge)
            o.end()
        }

        print("9. A window that cannot be resized, near the edge: if its app refuses the size, the nudge is put back at once and nothing recorded")
        if let (o, w) = await open("fixed", edge, fixed: true) {
            let result = fit(w, CGSize(width: 1000, height: 710)); await settle()
            print("  " + result)
            if result == "resize refused" {
                expect("after the refused fit", live(w.windowID), edge)
                tally(ledger.isEmpty, "nothing recorded")
            } else {
                // AppKit took the size through Accessibility after all: then it goes back like any other.
                print("  (its app took the size: restored as in 8)")
                for l in stop(keeping: nil) { print("  " + l) }; await settle()
                expect("after", live(w.windowID), edge)
            }
            _ = stop(keeping: nil)
            o.end()
        }

        print("10. An app that does not answer (stopped with SIGSTOP): left where it is, about a second, no writes")
        if let (o, w) = await open("stopped", S0) {
            print("  " + fit(w, pad)); await settle()
            let during = live(w.windowID)
            kill(o.pid, SIGSTOP)
            let t0 = Date()
            let lines = stop(keeping: nil)
            let took = Date().timeIntervalSince(t0)
            for l in lines { print("  " + l) }
            kill(o.pid, SIGCONT); await settle()
            tally(lines.count == 1 && lines[0].contains("not answering") && took < 2.5, String(format: "not answering, in %.2f s", took))
            expect("after (left at Sill's size)", live(w.windowID), during)
            o.end()
        }

        print("11. The virtual display's way home for a fitted window that was moved (worked out only; no display is made)")
        if let (o, w) = await open("stagehome", S0) {
            print("  " + fit(w, pad)); await settle()
            o.send("move \(Int(movedTo.x)) \(Int(movedTo.y))")
            if let e = ledger.entries[w.windowID] {
                var windows = WindowSizer.AXWindows(sizer: sizer)
                expect("home for the stage", WindowRestore.stageHome(e.handle, e.record, on: &windows), movedHome)
            } else { tally(false, "no record") }
            _ = ledger.take(w.windowID)
            o.end()
        }

        print("12. Two windows: A fitted, B picked (A goes back, B is fitted), then the last device leaves (B goes back)")
        let SA = CGRect(x: S0.minX, y: S0.minY, width: S0.width - 40, height: S0.height - 40)
        let SB = CGRect(x: S0.minX + 100, y: S0.minY + 60, width: S0.width - 120, height: S0.height - 80)
        if let (oa, a) = await open("A", SA), let (ob, b) = await open("B", SB) {
            print("  A: " + fit(a, pad)); await settle()
            for l in stop(keeping: b.windowID) { print("  B picked: " + l) }; await settle()
            expect("A after B was picked", live(a.windowID), SA)
            print("  B: " + fit(b, pad)); await settle()
            print("  B during \(fmt(live(b.windowID)))")
            for l in stop(keeping: nil) { print("  last device: " + l) }; await settle()
            expect("B after the last device left", live(b.windowID), SB)
            expect("A untouched since", live(a.windowID), SA)
            oa.end(); ob.end()
        }

        print("13. An app that stops answering once its window is matched (SIGSTOP), during a fit: the size goes unanswered and is recorded all the same; the app takes it, or not, once it runs again (SIGCONT), and the stop puts the window back")
        if let (o, w) = await open("unanswered", S0) {
            if let e = sizer.element(for: w) {
                AXUIElementSetMessagingTimeout(e, 1.0)          // as WindowSizer.resize sets it
                let p = WindowSizer.Placement(windowID: w.windowID, pid: o.pid, element: e, originalFrame: .null,
                                              appName: w.owningApplication?.applicationName ?? "?", title: w.title ?? "")
                var windows = WindowSizer.AXWindows(sizer: sizer)
                kill(o.pid, SIGSTOP)
                let t0 = Date()
                let result = WindowRestore.fit(p, to: pad, fallback: live(w.windowID) ?? S0, on: &windows)
                let took = Date().timeIntervalSince(t0)
                kill(o.pid, SIGCONT)
                print(String(format: "  fit: \(result), in %.2f s", took))
                if case .fitted(let before, let after, true) = result {
                    tally(true, "the size went unanswered and was recorded")
                    ledger.fitted(w.windowID, handle: p.homed(at: before), before: before, after: after, asked: pad)
                } else {
                    tally(false, "the size went unanswered and was recorded")
                }
                try? await Task.sleep(for: .milliseconds(800))
                let now = live(w.windowID)
                print("  after SIGCONT \(fmt(now)): the app \(now.map { WindowRestore.same($0.size, pad) } == true ? "took the size late" : "did not take the size")")
                for l in stop(keeping: nil) { print("  " + l) }; await settle()
                expect("after", live(w.windowID), S0)
            } else {
                tally(false, "unanswered: no Accessibility element")
            }
            o.end()
        }

        print("14. A fit, its left edge dragged in on the Mac (the right edge kept), a re-fit, then a stop: its whole frame back, not a move")
        if let (o, w) = await open("leftedge", S0) {
            print("  " + fit(w, pad)); await settle()
            if let l = live(w.windowID) {
                o.send("frame \(Int(l.minX + 60)) \(Int(l.minY)) \(Int(l.width - 60)) \(Int(l.height))")
                print("  resized from the left \(fmt(live(w.windowID)))")
            }
            print("  " + fit(w, pad)); await settle()             // the catalog's resize check fits it again
            print("  during  \(fmt(live(w.windowID)))")
            for l in stop(keeping: nil) { print("  " + l) }; await settle()
            expect("after", live(w.windowID), S0)
            o.end()
        }

        tally(frontApp() == front, "the front app never changed (\(front))")
        print("restore probe: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)   // the window server's connection, before ScreenCaptureKit; never a Dock icon
if let s = CGSessionCopyCurrentDictionary() as? [String: Any], (s["CGSSessionScreenIsLocked"] as? Int ?? 0) != 0 {
    print("The screen is locked: the window server shows a new window transformed and Accessibility lists none. Unlock the Mac and run again.")
    exit(2)
}
guard AXIsProcessTrusted() else {
    print("Accessibility is not allowed for the app that runs this (System Settings › Privacy & Security › Accessibility). Nothing was asked for.")
    exit(2)
}
guard CGPreflightScreenCaptureAccess() else {
    print("Screen Recording is not allowed for the app that runs this (ScreenCaptureKit lists the window, as the catalog does). Nothing was asked for.")
    exit(2)
}
let probe = Probe()
await probe.run()
