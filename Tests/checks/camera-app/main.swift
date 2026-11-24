import Foundation

// Sill.app's side of Sill Camera (docs/camera-plan.md §6.5, §7, §11, step 8), compiled as one module with Sill Camera's
// own rules (module.txt): CameraExtensionPolicy (what Sill asks macOS for and when, macOS's answers, what Settings ›
// Streaming's camera section says, its words, buttons and log lines, the dry run's script) and CameraSinkPolicy (the
// state Sill writes into Sill Camera, the app its demand names, the sink's two frames with the newest winning). Step by
// step, then 20,000 random lives of each against their invariants: nothing asked while the switch is off, nor ever by a
// Sill.app that may not ask; an activation only when the switch goes on or Try Again; a removal only when asked; Sill's
// feed reaching Sill Camera always shows it working, a switch off never does; what is remembered as installed is what
// macOS last said; the sink's queue never past its two, its frames in order, none a second old from the wait.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias X = CameraExtensionPolicy
typealias S = CameraSinkPolicy

/// SplitMix64: the same lives on every run.
struct Rand: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
}

/// Sill.app in /Applications with Sill Camera inside and the install entitlement: it may ask.
func facts(real: Bool = true, apps: Bool = true, inside: Bool = true, entitled: Bool = true, installed: String? = nil,
           build: String = "1700") -> X.Facts {
    X.Facts(real: real, inApplications: apps, extensionInside: inside, entitled: entitled, installedBuild: installed, build: build)
}

func asks(_ effects: [X.Effect]) -> Bool { effects.contains(.activate) }
func removes(_ effects: [X.Effect]) -> Bool { effects.contains(.deactivate) }
func lines(_ effects: [X.Effect]) -> [String] { effects.compactMap { if case .line(let l) = $0 { return l }; return nil } }
func remembered(_ effects: [X.Effect]) -> String?? {
    for e in effects { if case .remember(let b) = e { return .some(b) } }
    return .none
}

// MARK: - Who may ask

do {
    check(X.identifier == "me.saffer.sill.mac.camera" && X.errorDomain == "OSSystemExtensionErrorDomain", "Sill Camera's identifier and the error domain")
    for real in [false, true] { for apps in [false, true] { for inside in [false, true] { for entitled in [false, true] {
        let f = facts(real: real, apps: apps, inside: inside, entitled: entitled)
        let want: CameraExtensionState? = !real ? nil : (!inside || !entitled) ? .unsupportedBuild : !apps ? .needsApplications : nil
        check(X.refusal(f) == want, "refusal(real \(real), Applications \(apps), inside \(inside), entitled \(entitled)) = \(String(describing: X.refusal(f))), not \(String(describing: want))")
    } } } }
}

// MARK: - The switch

do {
    // Off at launch, as by default: nothing at all.
    var m = X.Model(facts: facts())
    check(X.handle(.switchChanged(false), &m).isEmpty && m.request == .none, "off at launch: nothing asked, nothing said")
    check(X.shown(m, sink: .stopped, use: nil) == .off(installed: false), "off, never installed: nothing to say")
    check(X.words(.off(installed: false), macOS: 27) == X.Words(line: nil, attention: false, button: nil, remove: false), "off: the switch and footnote alone")

    // On: a first install.
    var e = X.handle(.switchChanged(true), &m)
    check(e == [.activate, .line("Camera extension: activation requested.")] && m.request == .activating(.install) && m.switchOn,
          "on: one activation, its line (\(e))")
    check(X.shown(m, sink: .looking, use: nil) == .installing, "on, no answer yet, never installed: installing")
    check(X.handle(.switchChanged(true), &m).isEmpty, "on again: nothing more asked")
    check(X.handle(.tryAgain, &m) == [.activate, .line("Camera extension: activation requested.")], "Try Again asks again")

    // The one installed starts; another build is replaced.
    var same = X.Model(facts: facts(installed: "1700"))
    _ = X.handle(.switchChanged(true), &same)
    check(same.request == .activating(.start) && X.shown(same, sink: .looking, use: nil) == .starting, "installed, this build: starting")
    var older = X.Model(facts: facts(installed: "1650"))
    _ = X.handle(.switchChanged(true), &older)
    check(older.request == .activating(.update) && X.shown(older, sink: .looking, use: nil) == .updating, "installed, another build: updating")
    e = X.handle(.replacing(from: "1650", to: "1700"), &older)
    check(e == [.line("Camera extension: replacing build 1650 with 1700.")] && older.request == .activating(.update), "macOS asks to replace: replaced, said")
    var notAsked = X.Model(facts: facts())
    check(X.handle(.replacing(from: "1", to: "2"), &notAsked).isEmpty && notAsked.request == .none, "a replacement outside an activation: nothing")
    check(X.handle(.needsApproval, &notAsked).isEmpty && notAsked.request == .none, "an approval outside an activation: nothing")

    // A Sill.app that may not ask says why, and asks nothing.
    for (f, want) in [(facts(inside: false), CameraExtensionState.unsupportedBuild), (facts(entitled: false), .unsupportedBuild),
                      (facts(apps: false), .needsApplications)] {
        var r = X.Model(facts: f)
        let effects = X.handle(.switchChanged(true), &r)
        check(!asks(effects) && r.request == .none && X.shown(r, sink: .looking, use: nil) == want, "refused: \(want), nothing asked (\(effects))")
        check(lines(effects).first?.hasPrefix("Camera extension: not asked: ") == true, "refused: its line (\(lines(effects)))")
        check(!asks(X.handle(.tryAgain, &r)), "refused: Try Again asks nothing either")
    }
    check(lines(X.handle(.switchChanged(true), &notAsked)) == ["Camera extension: activation requested."], "the real request's line")
    // The dry run asks nobody, and says so.
    var dry = X.Model(facts: facts(real: false, apps: false, inside: false, entitled: false))
    e = X.handle(.switchChanged(true), &dry)
    check(e == [.activate, .line("Camera extension: activation requested (dry run: nothing asked of macOS).")], "the dry run plays an activation, saying so (\(e))")

    // Off again: nothing to cancel, nothing asked, Sill Camera stays.
    e = X.handle(.switchChanged(false), &m)
    check(!asks(e) && !removes(e) && m.request == .none && !m.switchOn, "off: nothing asked, nothing removed (\(e))")
    check(lines(e) == ["Camera extension: Use iPhone and iPad cameras off; Sill Camera is not installed."], "off's line, never installed")
    check(X.handle(.tryAgain, &m).isEmpty, "off: Try Again asks nothing")
}

// MARK: - macOS's answers

do {
    var m = X.Model(facts: facts())
    _ = X.handle(.switchChanged(true), &m)
    var e = X.handle(.needsApproval, &m)
    check(e == [.line("Camera extension: waits for approval in System Settings.")] && m.request == .needsApproval, "approval needed: said")
    check(X.shown(m, sink: .looking, use: nil) == .awaitingApproval, "waiting for approval")
    let w15 = X.words(.awaitingApproval, macOS: 27)
    check(w15.line == "Waiting for approval: in System Settings › General › Login Items & Extensions, click ⓘ beside Camera Extensions and turn on Sill Camera."
          && w15.attention && w15.button == .openSettings(.loginItems) && !w15.remove, "macOS 15 and later: Login Items & Extensions (\(w15))")
    check(X.words(.awaitingApproval, macOS: 15) == w15, "macOS 15 itself: the same")
    let w14 = X.words(.awaitingApproval, macOS: 14)
    check(w14.line == "Waiting for approval: in System Settings › Privacy & Security, click Allow for Sill." && w14.button == .openSettings(.privacySecurity),
          "macOS 14: Privacy & Security (\(w14))")

    e = X.handle(.completed, &m)
    check(e == [.remember("1700"), .line("Camera extension: activated (build 1700).")] && m.request == .activated && m.facts.installedBuild == "1700",
          "approved: activated, remembered (\(e))")
    check(X.shown(m, sink: .looking, use: nil) == .starting, "activated, the feed not there yet: starting")
    check(X.shown(m, sink: .feeding, use: nil) == .ready, "the feed reaches Sill Camera: ready")
    check(X.shown(m, sink: .feeding, use: X.Use(app: "FaceTime", device: "iPad")) == .inUse(app: "FaceTime", device: "iPad"), "an app uses it: in use")
    check(X.shown(m, sink: .refused, use: nil) == .notFed, "activated but the feed refused: said")
    check(X.shown(m, sink: .cameraDenied, use: nil) == .cameraDenied, "camera access denied: said")

    // Approved after the switch went off: installed all the same, unused.
    var late = X.Model(facts: facts())
    _ = X.handle(.switchChanged(true), &late)
    _ = X.handle(.needsApproval, &late)
    _ = X.handle(.switchChanged(false), &late)
    check(late.request == .none, "off while waiting: the request forgotten (macOS's stays pending until Sill quits)")
    e = X.handle(.completed, &late)
    check(remembered(e) == .some("1700") && late.request == .none && X.shown(late, sink: .stopped, use: nil) == .off(installed: true),
          "approved after off: remembered as installed, the switch still off (\(e))")
    let off = X.words(.off(installed: true), macOS: 27)
    check(off.line == "Sill Camera stays installed while this is off, and apps still list it." && off.remove && !off.attention, "off, installed: said, removable")
    check(lines(X.handle(.switchChanged(true), &late)) == ["Camera extension: activation requested."] && late.request == .activating(.start), "on again: starts it")
    check(lines(X.handle(.switchChanged(false), &late)) == ["Camera extension: Use iPhone and iPad cameras off; Sill Camera stays installed, unused."], "off's line, installed")

    // After a restart.
    var reboot = X.Model(facts: facts())
    _ = X.handle(.switchChanged(true), &reboot)
    e = X.handle(.completesAfterReboot, &reboot)
    check(remembered(e) == .some("1700") && reboot.request == .rebootNeeded && X.shown(reboot, sink: .looking, use: nil) == .needsRestart, "after a restart: said")

    // Failures, by code.
    let cases: [(Int, CameraExtensionState)] = [(2, .unsupportedBuild), (3, .needsApplications), (4, .unsupportedBuild), (10, .forbidden),
                                                (8, .failed("its signature isn’t valid")), (9, .failed("macOS couldn’t validate it")),
                                                (11, .failed("the request was cancelled")), (13, .failed("an administrator has to allow it")),
                                                (1, .failed("macOS gave no reason")), (77, .failed("error 77"))]
    for (code, want) in cases {
        var f = X.Model(facts: facts())
        _ = X.handle(.switchChanged(true), &f)
        let effects = X.handle(.failed(.systemExtension(code)), &f)
        check(f.request == .failed(.systemExtension(code)) && X.shown(f, sink: .looking, use: nil) == want, "code \(code): \(X.shown(f, sink: .looking, use: nil)), not \(want)")
        check(lines(effects) == ["Camera extension: failed: \(X.reason(.systemExtension(code)))."], "code \(code): its line")
        check(asks(X.handle(.tryAgain, &f)), "code \(code): Try Again asks again")
    }
    var other = X.Model(facts: facts())
    _ = X.handle(.switchChanged(true), &other)
    _ = X.handle(.failed(X.Failure(domain: "NSCocoaErrorDomain", code: 4)), &other)
    check(X.shown(other, sink: .looking, use: nil) == .failed("error 4 (NSCocoaErrorDomain)"), "another domain's code 4 is no missing extension")
    var superseded = X.Model(facts: facts())
    _ = X.handle(.switchChanged(true), &superseded)
    check(X.handle(.failed(.systemExtension(12)), &superseded).isEmpty && superseded.request == .activating(.install), "superseded: its own answer follows")
    let failed = X.words(.failed("its signature isn’t valid"), macOS: 27)
    check(failed.line == "Couldn’t install Sill Camera: its signature isn’t valid." && failed.attention && failed.button == .tryAgain, "a failure: why, and Try Again")
    var reasons = Set<String>()
    for code in 1...13 { reasons.insert(X.reason(.systemExtension(code))) }
    check(reasons.count == 13 && !reasons.contains(where: \.isEmpty), "thirteen reasons, each its own")
}

// MARK: - Removal, and System Settings' switch

do {
    var m = X.Model(facts: facts(installed: "1700"))
    _ = X.handle(.switchChanged(true), &m)
    _ = X.handle(.completed, &m)
    var e = X.handle(.remove, &m)
    check(e == [.deactivate, .line("Camera extension: removal requested.")] && !m.switchOn && m.request == .removing, "Remove: the switch off, one removal (\(e))")
    check(X.shown(m, sink: .stopped, use: nil) == .removing, "removing")
    e = X.handle(.removeCompleted, &m)
    check(e == [.remember(nil), .line("Camera extension: removed.")] && m.facts.installedBuild == nil && X.shown(m, sink: .stopped, use: nil) == .removed,
          "removed: forgotten (\(e))")
    check(X.words(.removed, macOS: 27).line == "Sill Camera was removed.", "removed's words")
    e = X.handle(.switchChanged(true), &m)
    check(m.request == .activating(.install) && asks(e), "on again after removal: a fresh install")

    var gone = X.Model(facts: facts(installed: "1700"))
    _ = X.handle(.remove, &gone)
    e = X.handle(.removeFailed(.systemExtension(4)), &gone)
    check(remembered(e) == .some(nil) && gone.request == .removed && lines(e) == ["Camera extension: removed (it was not installed)."], "nothing to remove: as removed")
    var refused = X.Model(facts: facts(installed: "1700"))
    _ = X.handle(.remove, &refused)
    e = X.handle(.removeFailed(.systemExtension(13)), &refused)
    check(remembered(e) == .none && refused.request == .removeFailed(.systemExtension(13)) && refused.facts.installedBuild == "1700"
          && X.shown(refused, sink: .stopped, use: nil) == .removeFailed("an administrator has to allow it"), "a refused removal: said, still installed")
    let rf = X.words(.removeFailed("an administrator has to allow it"), macOS: 27)
    check(rf.line == "Couldn’t remove Sill Camera: an administrator has to allow it." && rf.remove && rf.attention, "a refused removal: Remove again")
    var dryRemove = X.Model(facts: facts(real: false))
    check(lines(X.handle(.remove, &dryRemove)) == ["Camera extension: removal requested (dry run: nothing asked of macOS)."], "the dry run's removal says so")

    var s = X.Model(facts: facts(installed: "1700"))
    _ = X.handle(.switchChanged(true), &s)
    _ = X.handle(.completed, &s)
    e = X.handle(.enabledInSettings(false), &s)
    check(s.disabledInSettings && e == [.line("Camera extension: turned off in System Settings.")], "turned off in System Settings: said")
    check(X.shown(s, sink: .looking, use: nil) == .disabledInSettings, "turned off there: the section says where")
    check(X.handle(.enabledInSettings(false), &s).isEmpty, "off there again: nothing new")
    let ds = X.words(.disabledInSettings, macOS: 27)
    check(ds.line == "Sill Camera is turned off in System Settings › General › Login Items & Extensions." && ds.button == .openSettings(.loginItems), "its words")
    e = X.handle(.enabledInSettings(true), &s)
    check(!s.disabledInSettings && e == [.line("Camera extension: turned on in System Settings.")], "turned on there again")
}

// MARK: - What shows, whatever the request

do {
    let requests: [X.Request] = [.none, .activating(.install), .activating(.start), .activating(.update), .needsApproval, .activated, .rebootNeeded,
                                 .failed(.systemExtension(8)), .failed(.systemExtension(3)), .removing, .removed, .removeFailed(.systemExtension(13))]
    let sinks: [X.Sink] = [.stopped, .looking, .feeding, .refused, .cameraDenied]
    for f in [facts(), facts(apps: false), facts(inside: false), facts(real: false)] {
        for r in requests { for sink in sinks { for disabled in [false, true] { for on in [false, true] {
            var m = X.Model(facts: f)
            m.switchOn = on; m.request = r; m.disabledInSettings = disabled
            let shown = X.shown(m, sink: sink, use: nil)
            let used = X.shown(m, sink: sink, use: X.Use(app: "Zoom", device: "iPhone"))
            if !on {
                let offStates: Bool
                switch shown { case .off, .removing, .removed, .removeFailed: offStates = true; default: offStates = false }
                check(offStates, "off shows nothing working: \(shown) (\(r), \(sink))")
            } else if sink == .feeding {
                check(shown == .ready && used == .inUse(app: "Zoom", device: "iPhone"), "Sill's feed reaches Sill Camera: it works, whatever was asked (\(r), \(shown))")
            } else {
                check(shown != .ready, "no feed, never ready (\(r), \(sink))")
                if case .inUse = shown { check(false, "no feed, never in use (\(r), \(sink))") }
                if sink == .cameraDenied { check(shown == .cameraDenied, "camera access denied wins over the request (\(r))") }
                else if disabled { check(shown == .disabledInSettings, "turned off in System Settings wins over the request (\(r), \(sink))") }
                else if let refusal = X.refusal(f) { check(shown == refusal, "a refused Sill shows why, whatever the request (\(r))") }
                check(X.words(shown, macOS: 27).line?.isEmpty == false, "on: always a line (\(shown))")
            }
        } } } }
    }
}

// MARK: - The words

do {
    let all: [CameraExtensionState] = [.off(installed: false), .off(installed: true), .installing, .starting, .updating, .awaitingApproval,
                                       .needsApplications, .disabledInSettings, .forbidden, .unsupportedBuild, .needsRestart, .cameraDenied, .notFed,
                                       .ready, .inUse(app: "FaceTime", device: "iPad"), .inUse(app: nil, device: "iPhone"), .failed("x"),
                                       .removing, .removed, .removeFailed("x")]
    let attention: Set<String> = ["awaitingApproval", "needsApplications", "disabledInSettings", "forbidden", "unsupportedBuild", "needsRestart",
                                  "cameraDenied", "notFed", "failed", "removeFailed"]
    let removable: Set<String> = ["off(installed: true)", "disabledInSettings", "cameraDenied", "notFed", "ready", "inUse", "removeFailed"]
    for s in all {
        let w = X.words(s, macOS: 27)
        let name = "\(s)".components(separatedBy: "(").first ?? "\(s)"
        let full = "\(s)" == "off(installed: true)" ? "off(installed: true)" : name
        check(w.attention == attention.contains(name), "\(s): attention \(w.attention)")
        check(w.remove == removable.contains(full), "\(s): Remove Sill Camera… \(w.remove)")
        if let line = w.line { check(line.hasSuffix(".") || line.hasSuffix("…"), "\(s): a sentence (\(line))") }
    }
    let exact: [(CameraExtensionState, String)] = [
        (.installing, "Installing Sill Camera…"), (.starting, "Starting Sill Camera…"), (.updating, "Updating Sill Camera to this version of Sill…"),
        (.needsApplications, "Move Sill to the Applications folder, open it from there, and turn this on again."),
        (.forbidden, "This Mac’s administrator doesn’t allow camera extensions from other developers."),
        (.unsupportedBuild, "This build of Sill can’t install Sill Camera."), (.needsRestart, "Restart this Mac to finish installing Sill Camera."),
        (.ready, "Ready. Apps on this Mac can choose “Sill Camera”."), (.inUse(app: "FaceTime", device: "iPad"), "In use by FaceTime, with iPad’s camera."),
        (.inUse(app: nil, device: "iPhone"), "In use by an app, with iPhone’s camera."), (.inUse(app: "", device: "iPhone"), "In use by an app, with iPhone’s camera."),
        (.removing, "Removing Sill Camera…"),
    ]
    for (s, line) in exact { check(X.words(s, macOS: 27).line == line, "\(s): “\(X.words(s, macOS: 27).line ?? "nil")”") }
    check(X.words(.cameraDenied, macOS: 27).button == .openSettings(.camera), "camera access: Privacy & Security › Camera")
    check(X.Copy.toggle == "Use iPhone and iPad cameras" && X.Copy.header == "Camera and Microphone (beta)" && X.Copy.remove == "Remove Sill Camera…"
          && X.Copy.openSettings == "Open System Settings…" && X.Copy.tryAgain == "Try Again", "the section's names")
    check(X.Copy.footnote.hasPrefix("Apps on this Mac, such as FaceTime and Zoom, can choose “Sill Camera”") && X.Copy.footnote.contains("administrator"), "the footnote")
    check(X.Copy.cardTitle(app: "FaceTime") == "Camera: FaceTime" && X.Copy.cardTitle(app: "") == "Camera: In Use" && X.Copy.cardTitle(app: nil) == "Camera: In Use",
          "the card's camera line")
    check(X.Copy.cardDetail(device: "iPad") == "iPad’s camera", "the card's second line")
}

// MARK: - The dry run's script

do {
    let s = X.dryRunScript("3 complete; 1 approval; 2 replace:1650>1700")
    check(s?.map(\.at) == [1, 2, 3] && s?.map(\.event) == [.needsApproval, .replacing(from: "1650", to: "1700"), .completed], "read and sorted: \(String(describing: s))")
    check(X.dryRunScript("0 fail:8")?.first?.event == .failed(.systemExtension(8)), "fail:8")
    check(X.dryRunScript("1 removefail:13")?.first?.event == .removeFailed(.systemExtension(13)), "removefail:13")
    check(X.dryRunScript("1 disabled;2 enabled;3 removed;4 reboot")?.map(\.event) == [.enabledInSettings(false), .enabledInSettings(true), .removeCompleted, .completesAfterReboot],
          "the other answers")
    for bad in ["", "1", "x complete", "1 approve", "1 fail:0", "1 fail:100", "1 fail:x", "-1 complete", "601 complete", "1 replace:>2", "1 replace:1>",
                "1 replace:12345678901234567>1", "1 complete extra"] {
        check(X.dryRunScript(bad) == nil, "refused: “\(bad)”")
    }
    check(X.dryRunScript(Array(repeating: "1 complete", count: 16).joined(separator: ";"))?.count == 16, "sixteen steps")
    check(X.dryRunScript(Array(repeating: "1 complete", count: 17).joined(separator: ";")) == nil, "seventeen refused")
    check(X.dryRunScript("2 approval; 2 complete")?.map(\.event) == [.needsApproval, .completed], "one time: written order")
}

// MARK: - The sink: what it writes, the app it names, its frames

do {
    check(S.state(.unavailable) == "{\"show\":\"unavailable\"}" && S.state(.waiting) == "{\"show\":\"waiting\"}", "nothing of anyone, and waiting")
    check(S.show(.device(name: "iPad", pause: nil)) == .device(name: "iPad", paused: false), "a live device")
    check(S.show(.device(name: "iPad", pause: "background")) == .device(name: "iPad", paused: true), "a pause")
    check(CameraFeedPolicy.decode(S.state(.device(name: "iPad\n(x)", pause: "busy"))) == .device(name: "iPad (x)", paused: true), "round trip, cleaned")
    check(S.lastPart("com.apple.FaceTime") == "FaceTime" && S.lastPart("Zoom") == "Zoom", "an identifier's last part")

    let named: [Int32: String] = [10: "FaceTime", 11: "zoom.us", 12: "Google Chrome", 13: "FaceTime"]
    let name = { (pid: Int32) in named[pid] }
    func app(_ id: String?, _ pid: Int32) -> CameraFeedPolicy.App { CameraFeedPolicy.App(id: id, pid: pid) }
    check(S.appNames([app("com.apple.FaceTime", 10)], name: name) == "FaceTime", "one app")
    check(S.appNames([app("com.apple.FaceTime", 10), app("us.zoom.xos", 11)], name: name) == "FaceTime and zoom.us", "two")
    check(S.appNames([app("a", 10), app("b", 11), app("c", 12)], name: name) == "FaceTime and 2 more", "three")
    check(S.appNames([app("a", 10), app("b", 13)], name: name) == "FaceTime", "the same app twice, once")
    check(S.appNames([app("com.example.Gone", 99)], name: name) == "Gone", "not running: its identifier's last part")
    check(S.appNames([app(nil, 99)], name: name) == nil && S.appNames([], name: name) == nil, "nobody to name")
    check(S.appNames([app("x", 50)], name: { _ in "Ann\u{202E}\u{0007}\nApp" }) == "Ann App", "cleaned of control and format characters")
    let long = S.appNames([app("x", 51)], name: { _ in String(repeating: "W", count: 60) })
    check(long?.count == CameraFeedPolicy.nameCap, "at most \(CameraFeedPolicy.nameCap) characters (\(long?.count ?? 0))")
    let two = S.appNames([app("x", 52), app("y", 53)], name: { $0 == 52 ? String(repeating: "A", count: 30) : "Zoom" })
    check(two.map { $0.count <= CameraFeedPolicy.nameCap } == true, "two long names capped too (\(two ?? ""))")

    func demand(_ running: Bool, _ w: Int, _ h: Int, _ fps: Int, _ apps: [CameraFeedPolicy.App]) -> String {
        CameraFeedPolicy.encode(CameraFeedPolicy.Demand(running: running, width: w, height: h, fps: fps, apps: apps))
    }
    check(S.use(demand(true, 1280, 720, 30, [app("com.apple.FaceTime", 10)]), name: name) == S.Use(name: "FaceTime", width: 1280, height: 720, fps: 30),
          "the app, its size and rate")
    check(S.use(demand(true, 1920, 1080, 15, []), name: name) == S.Use(name: nil, width: 1920, height: 1080, fps: 15), "running, nobody named")
    check(S.use(demand(false, 1280, 720, 30, []), name: name) == nil, "not running: no use")
    check(S.use(nil, name: name) == nil && S.use("{", name: name) == nil && S.use(demand(true, 640, 480, 30, []), name: name) == nil,
          "nothing, not JSON, a size Sill Camera never offers: no use")

    var q = S.Slots()
    check(q.arrive(count: 0, capacity: 2, at: 0) == .enqueue && q.pendingSince == nil, "room: in")
    check(q.arrive(count: 1, capacity: 2, at: 0.03) == .enqueue, "room for a second")
    check(q.arrive(count: 2, capacity: 2, at: 0.06) == .hold && q.pendingSince == 0.06, "full: waits")
    check(q.arrive(count: 2, capacity: 2, at: 0.09) == .replace && q.pendingSince == 0.09, "full again: the newest waits in its place")
    check(!q.freed(count: 2, capacity: 2, at: 0.1) && q.pendingSince == 0.09, "still full: it waits on")
    check(q.freed(count: 1, capacity: 2, at: 0.12) && q.pendingSince == nil, "room: it goes")
    check(!q.freed(count: 0, capacity: 2, at: 0.13), "nothing waiting: nothing goes")
    _ = q.arrive(count: 2, capacity: 2, at: 1)
    check(!q.freed(count: 1, capacity: 2, at: 2.0) && q.pendingSince == nil, "a second old by then: dropped")
    _ = q.arrive(count: 2, capacity: 2, at: 3)
    check(q.arrive(count: 1, capacity: 2, at: 3.01) == .enqueue && q.pendingSince == nil, "room before it went: the newer goes, the older is dropped")
    _ = q.arrive(count: 2, capacity: 2, at: 4)
    q.clear()
    check(q.pendingSince == nil && !q.freed(count: 0, capacity: 2, at: 4.01), "cleared")
    var fresh = S.Slots()
    check(fresh.arrive(count: 0, capacity: 0, at: 0) == .enqueue, "a queue that says no capacity yet: one goes in")
}

// MARK: - Random lives: the request

do {
    var rng = Rand(state: 0xCA4E_2A00)
    var lives = 0, asked = 0, removed = 0, feeding = 0
    outer: for life in 0..<20_000 {
        let f = facts(real: rng.chance(0.7), apps: rng.chance(0.85), inside: rng.chance(0.9), entitled: rng.chance(0.9),
                      installed: rng.chance(0.3) ? (rng.chance(0.5) ? "1700" : "1650") : nil)
        var m = X.Model(facts: f)
        var lastRemembered: String?? = .none
        for _ in 0..<rng.int(1...30) {
            let before = m
            let event: X.Event
            switch rng.int(0...12) {
            case 0, 1: event = .switchChanged(rng.chance(0.6))
            case 2: event = .tryAgain
            case 3: event = .remove
            case 4: event = .replacing(from: "1650", to: "1700")
            case 5: event = .needsApproval
            case 6: event = .completed
            case 7: event = .completesAfterReboot
            case 8: event = .failed(.systemExtension(rng.int(1...13)))
            case 9: event = .removeCompleted
            case 10: event = .removeFailed(.systemExtension(rng.chance(0.5) ? 4 : rng.int(1...13)))
            default: event = .enabledInSettings(rng.chance(0.5))
            }
            let effects = X.handle(event, &m)
            if asks(effects) {
                asked += 1
                let allowed: Bool
                switch event {
                case .switchChanged(true): allowed = !before.switchOn
                case .tryAgain: allowed = before.switchOn
                default: allowed = false
                }
                if !allowed || X.refusal(f) != nil || !m.switchOn { check(false, "life \(life): asked on \(event) (before \(before), refusal \(String(describing: X.refusal(f))))"); break outer }
            }
            if removes(effects) {
                removed += 1
                if event != .remove || m.switchOn { check(false, "life \(life): a removal on \(event)"); break outer }
            }
            if let r = remembered(effects) {
                lastRemembered = r
                let ok: Bool
                switch event {
                case .completed, .completesAfterReboot: ok = r == f.build
                case .removeCompleted: ok = r == nil
                case .removeFailed(let failure): ok = failure == .systemExtension(4) && r == nil
                default: ok = false
                }
                if !ok { check(false, "life \(life): remembered \(String(describing: r)) on \(event)"); break outer }
            }
            if case .switchChanged(false) = event, asks(effects) || removes(effects) { check(false, "life \(life): off asked macOS for something"); break outer }
            for sink in [X.Sink.looking, .feeding, .refused] {
                let shown = X.shown(m, sink: sink, use: nil)
                if m.switchOn, sink == .feeding {
                    feeding += 1
                    if shown != .ready { check(false, "life \(life): fed but \(shown)"); break outer }
                }
                if !m.switchOn {
                    switch shown { case .off, .removing, .removed, .removeFailed: break
                    default: check(false, "life \(life): off but \(shown)"); break outer }
                }
            }
        }
        if case .some(let r) = lastRemembered, m.facts.installedBuild != r { check(false, "life \(life): installed \(String(describing: m.facts.installedBuild)), remembered \(String(describing: r))"); break }
        lives += 1
    }
    check(lives == 20_000 && asked > 5_000 && removed > 5_000 && feeding > 20_000, "every life ran (\(lives)), reaching every part: \(asked) asks, \(removed) removals, \(feeding) fed")
    print("request lives: \(asked) asks, \(removed) removals, \(feeding) fed states judged")
}

// MARK: - Random lives: the sink's frames

do {
    var rng = Rand(state: 0x51_4B00)
    var lives = 0, inQueue = 0, dropped = 0, late = 0
    outer: for life in 0..<20_000 {
        var slots = S.Slots()
        var queue: [Double] = []           // Sill Camera's queue: each frame's arrival time
        var pending: Double?               // the frame waiting, by its arrival time
        var lastIn = -Double.infinity      // the newest frame that went in
        var now = 0.0
        let capacity = 2
        for _ in 0..<rng.int(5...80) {
            // Mostly a frame's time, sometimes a stall of up to a second and a half (Sill Camera's side busy, or no
            // app reading it), so a frame can wait past its second.
            now += Double(rng.chance(0.1) ? rng.int(400...1500) : rng.int(1...400)) / 1000
            let step = rng.int(0...99)
            if step < 50 {
                // A decoded frame arrives.
                switch slots.arrive(count: queue.count, capacity: capacity, at: now) {
                case .enqueue:
                    if queue.count >= capacity { check(false, "life \(life): in past the queue's two"); break outer }
                    if pending != nil { dropped += 1 }
                    pending = nil
                    queue.append(now); lastIn = now; inQueue += 1
                case .hold:
                    if pending != nil || queue.count < capacity { check(false, "life \(life): held with room or another waiting"); break outer }
                    pending = now
                case .replace:
                    if pending == nil || queue.count < capacity { check(false, "life \(life): replaced nothing"); break outer }
                    dropped += 1; pending = now
                }
            } else if step < 80, !queue.isEmpty {
                // Sill Camera takes one.
                queue.removeFirst()
                let goes = slots.freed(count: queue.count, capacity: capacity, at: now)
                if goes {
                    guard let p = pending else { check(false, "life \(life): something went in from an empty wait"); break outer }
                    if now - p >= CameraFeedPolicy.frameLifetime { check(false, "life \(life): a frame \(now - p) s old went in"); break outer }
                    if p < lastIn { check(false, "life \(life): an older frame went in after a newer one"); break outer }
                    queue.append(p); lastIn = p; pending = nil; inQueue += 1
                } else if let p = pending, slots.pendingSince == nil {
                    if now - p < CameraFeedPolicy.frameLifetime { check(false, "life \(life): a fresh frame dropped from the wait"); break outer }
                    late += 1; pending = nil
                }
            }
            if slots.pendingSince != pending { check(false, "life \(life): the wait is \(String(describing: slots.pendingSince)), the model's \(String(describing: pending))"); break outer }
            if queue.count > capacity { check(false, "life \(life): \(queue.count) in the queue"); break outer }
        }
        lives += 1
    }
    check(lives == 20_000 && inQueue > 100_000 && dropped > 10_000 && late > 100, "every life ran (\(lives)), reaching every part: \(inQueue) in, \(dropped) dropped for a newer, \(late) too old by then")
    print("sink lives: \(inQueue) frames in, \(dropped) dropped for a newer one, \(late) too old by the time there was room")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
