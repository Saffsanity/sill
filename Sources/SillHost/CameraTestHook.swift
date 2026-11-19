import Foundation

/// TEST ONLY: a test host's Sill Camera (docs/camera-plan.md §7, §13.2), so the receiving side runs
/// headless with no camera extension, no camera and no window: honoured only by a test host
/// (DoorPolicy.isTestHost: one that does not advertise and is not Sill.app's own code), ignored with one
/// line anywhere else. Pure: Foundation only, checked with swiftc (Tests/checks/camera-host).
///
/// - `SILL_TEST_CAMERA=count`: the test host takes devices' cameras (its Use iPhone and iPad cameras on,
///   its Sill Camera ready) and counts each decoded frame (`cam.decoded`); `dump:DIR` also writes every
///   30th decoded frame, and the first of each epoch, as a PNG into DIR (an existing folder).
/// - `SILL_TEST_CAMERA_DEMAND='S on WxH@F [NAME]; S off; S notready; S ready'`: what Sill Camera's apps
///   would do, at S seconds after the host starts: an app opens it at that size and rate (named NAME,
///   "Test" when left out), closes it, or Sill Camera stops or starts being ready (the list then says
///   `camera` 0, kind 16 `notReady`). Without it no app ever uses the test host's Sill Camera.
/// - `SILL_TEST_CAMERA_LOG=1`: one line per decoded frame, with its size and how late it came.
enum CameraTestHook {
    static let variable = "SILL_TEST_CAMERA"
    static let demandVariable = "SILL_TEST_CAMERA_DEMAND"
    static let logVariable = "SILL_TEST_CAMERA_LOG"

    enum Output: Equatable {
        case count
        case dump(String)
    }

    enum Step: Equatable {
        case on(width: Int, height: Int, fps: Int, name: String)
        case off
        case notReady
        case ready
    }

    struct Hook: Equatable {
        var output: Output
        var script: [(at: Double, step: Step)]
        var log: Bool
        static func == (a: Hook, b: Hook) -> Bool {
            a.output == b.output && a.log == b.log && a.script.count == b.script.count
                && zip(a.script, b.script).allSatisfy { $0.at == $1.at && $0.step == $1.step }
        }
    }

    /// The hook, and the line to print about it: nil and nil when SILL_TEST_CAMERA is not set (every other
    /// output stays as it was), nil and a line when it is set but refused or does not parse.
    static func read(testHost: Bool, environment: [String: String]) -> (hook: Hook?, line: String?) {
        guard let raw = environment[variable], !raw.isEmpty else {
            if !(environment[demandVariable] ?? "").isEmpty { return (nil, "\(demandVariable) ignored: it needs \(variable).") }
            return (nil, nil)
        }
        guard testHost else { return (nil, "\(variable) ignored: only a --synthetic test host takes it, never Sill.app.") }
        guard let output = parseOutput(raw) else {
            return (nil, "\(variable)=\(raw.prefix(80)) ignored: it takes count, or dump:DIR with DIR an existing folder's path.")
        }
        var script: [(at: Double, step: Step)] = []
        if let s = environment[demandVariable], !s.isEmpty {
            guard let parsed = parseScript(s) else {
                return (nil, "\(demandVariable) ignored, and with it \(variable): it takes 'S on WxH@F [NAME]; S off; S notready; S ready' steps.")
            }
            script = parsed
        }
        let log = environment[logVariable] == "1"
        let what: String
        switch output {
        case .count: what = "counts each decoded frame"
        case .dump(let dir): what = "writes every 30th decoded frame as a PNG into \(dir)"
        }
        let line = "TEST: this host takes devices' cameras (\(variable)): its Sill Camera \(what)"
            + (script.isEmpty ? "; no app uses it." : "; \(script.count) scripted step\(script.count == 1 ? "" : "s") of its apps (\(demandVariable)).")
        return (Hook(output: output, script: script, log: log), line)
    }

    /// `count`, or `dump:DIR` with an absolute or relative path of at most 1,024 bytes.
    static func parseOutput(_ raw: String) -> Output? {
        if raw == "count" { return .count }
        guard raw.hasPrefix("dump:") else { return nil }
        let dir = String(raw.dropFirst(5))
        guard !dir.isEmpty, dir.utf8.count <= 1024 else { return nil }
        return .dump(dir)
    }

    /// Steps separated by ';', each `S on WxH@F [NAME]`, `S off`, `S notready` or `S ready`, S seconds from
    /// 0 to 3600, sorted by S; W and H generation 1's sides (even, 16 to 1920), F 1 to 60 (the app's rate,
    /// which the demand holds to 30), NAME up to 40 characters. Nil when any step does not parse, or there
    /// are more than 64.
    static func parseScript(_ raw: String) -> [(at: Double, step: Step)]? {
        var steps: [(at: Double, step: Step)] = []
        for entry in raw.split(separator: ";") {
            let words = entry.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count >= 2, let at = Double(words[0]), at.isFinite, (0...3600).contains(at) else { return nil }
            switch words[1] {
            case "on":
                guard words.count >= 3, words.count <= 4 else { return nil }
                let sizeRate = words[2].split(separator: "@")
                guard sizeRate.count == 2, let fps = Int(sizeRate[1]), (1...60).contains(fps) else { return nil }
                let wh = sizeRate[0].split(separator: "x")
                guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]) else { return nil }
                guard w >= 16, w <= 1920, w % 2 == 0, h >= 16, h <= 1920, h % 2 == 0 else { return nil }
                let name = words.count == 4 ? words[3] : "Test"
                guard name.count <= 40 else { return nil }
                steps.append((at, .on(width: w, height: h, fps: fps, name: name)))
            case "off": guard words.count == 2 else { return nil }; steps.append((at, .off))
            case "notready": guard words.count == 2 else { return nil }; steps.append((at, .notReady))
            case "ready": guard words.count == 2 else { return nil }; steps.append((at, .ready))
            default: return nil
            }
        }
        guard !steps.isEmpty, steps.count <= 64 else { return nil }
        return steps.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    }
}
