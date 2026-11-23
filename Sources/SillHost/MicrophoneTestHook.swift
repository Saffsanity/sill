import Foundation

/// TEST ONLY: a test host's Sill Microphone (docs/microphone-plan.md §5.3, §10.2), so the receiving side runs
/// headless with no audio plug-in, no audio device and nothing played: honoured only by a test host
/// (DoorPolicy.isTestHost: one that does not advertise and is not Sill.app's own code), ignored with one line
/// anywhere else. Pure: Foundation only, checked with swiftc (Tests/checks/mic-host).
///
/// - `SILL_TEST_MIC_SINK=dry`: the test host takes devices' microphones (its Use iPhone and iPad microphones on,
///   its Sill Microphone set up) and counts each frame it would play (`mic.dry`); `file:PATH` also writes
///   exactly what Sill Microphone would hear to PATH, a WAV of 48 kHz mono 32-bit float from the moment the
///   first device's sound comes until the host quits, silence where nothing played (its sample 0's wall-clock
///   time is printed: "Test microphone: the file's sample 0 is at …").
/// - `SILL_TEST_MIC_APP=PATH`: whether an app uses Sill Microphone, read once a second: `0` (or no file) none,
///   anything else one does. Without it an app always does.
/// - `SILL_TEST_MIC_SETUP=PATH`: Sill Microphone's state, read once a second: `missing` or `notloaded` is not
///   set up (the list then says `microphone` 0 and kind 16 `notReady`), anything else (or no file) set up.
/// - `SILL_TEST_MIC_LOG=1`: one line per epoch the playout starts and one a second of its numbers.
enum MicrophoneTestHook {
    static let sinkVariable = "SILL_TEST_MIC_SINK"
    static let appVariable = "SILL_TEST_MIC_APP"
    static let setupVariable = "SILL_TEST_MIC_SETUP"
    static let logVariable = "SILL_TEST_MIC_LOG"

    enum Sink: Equatable {
        case dry
        case file(String)
    }

    struct Hook: Equatable {
        var sink: Sink
        var appFile: String?
        var setupFile: String?
        var log: Bool
    }

    /// The hook, and the line to print about it: nil and nil when SILL_TEST_MIC_SINK is not set (every other
    /// output stays as it was), nil and a line when it is set but refused or does not parse, or when one of the
    /// others is set without it.
    static func read(testHost: Bool, environment: [String: String]) -> (hook: Hook?, line: String?) {
        guard let raw = environment[sinkVariable], !raw.isEmpty else {
            for v in [appVariable, setupVariable, logVariable] where !(environment[v] ?? "").isEmpty {
                return (nil, "\(v) ignored: it needs \(sinkVariable).")
            }
            return (nil, nil)
        }
        guard testHost else { return (nil, "\(sinkVariable) ignored: only a --synthetic test host takes it, never Sill.app.") }
        guard let sink = parseSink(raw) else {
            return (nil, "\(sinkVariable)=\(raw.prefix(80)) ignored: it takes dry, or file:PATH.")
        }
        let app = path(environment[appVariable])
        let setup = path(environment[setupVariable])
        let what: String
        switch sink {
        case .dry: what = "counts what it would play"
        case .file(let p): what = "writes what it would play to \(p)"
        }
        let line = "TEST: this host takes devices' microphones (\(sinkVariable)): its Sill Microphone \(what)"
            + (app.map { "; an app uses it while \($0) says so" } ?? "; an app always uses it")
            + (setup.map { "; set up while \($0) does not say missing" } ?? "") + "."
        return (Hook(sink: sink, appFile: app, setupFile: setup, log: environment[logVariable] == "1"), line)
    }

    /// `dry`, or `file:PATH` with a path of 1 to 1,024 bytes.
    static func parseSink(_ raw: String) -> Sink? {
        if raw == "dry" { return .dry }
        guard raw.hasPrefix("file:") else { return nil }
        let p = String(raw.dropFirst(5))
        guard !p.isEmpty, p.utf8.count <= 1024 else { return nil }
        return .file(p)
    }

    private static func path(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.utf8.count <= 1024 else { return nil }
        return raw
    }

    /// What SILL_TEST_MIC_APP's file says: an app uses Sill Microphone unless it reads `0` or is missing.
    static func appUses(_ contents: String?) -> Bool {
        guard let c = contents?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return c != "0" && !c.isEmpty
    }

    /// What SILL_TEST_MIC_SETUP's file says: set up unless it reads `missing` or `notloaded`.
    static func setUp(_ contents: String?) -> Bool {
        let c = contents?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return c != "missing" && c != "notloaded"
    }

    /// The file sink's WAV header for `frames` frames of 48 kHz mono 32-bit float (format 3), little endian:
    /// RIFF, fmt (16 bytes), and data. 44 bytes.
    static func wavHeader(frames: Int, sampleRate: Int = 48_000) -> Data {
        let dataBytes = UInt32(min(max(0, frames), Int(UInt32.max / 4) - 9) * 4)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 &+ dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(3); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(32)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        return d
    }
}
