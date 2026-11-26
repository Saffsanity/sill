import Darwin
import Foundation
import os

/// Rule 12 of DarkenPolicy (docs/privacy-mode-plan.md): a hung Sill must not leave this Mac's screens black. The probe
/// G0 (2026-11-23) saw a stopped process keep its black window for as long as it was stopped, and a killed one's go
/// within 16 ms: only the end of the process lifts a hung Sill's black. So while the black is up (`arm` … `disarm`)
/// the main actor beats once a second (PrivacyScreen), and a timer on this watchdog's own queue
/// (`sill.privacy.watchdog`) looks once a second. Beats stopped for DarkenPolicy.hangLimit (10 s, on a clock that stops
/// while the Mac sleeps, so a sleep is no hang) end Sill.app at once: its line, the log flushed, Sill opened again
/// (DarkenPolicy.reopenCommand: `open -n -g` on its bundle, at most once in DarkenPolicy.relaunchSpacing, remembered in
/// a file written before the end, which the next launch reads for its line), then `_exit(70)`, with no atexit handler
/// that could wait on the stuck thread, and a second `_exit` 2 s later in case the line or the log are what is stuck.
/// The black windows go with the process. Everywhere but Sill.app itself (`dry`) it only says so (`priv.watchdogDry`),
/// nothing quits, and the count starts again.
final class PrivacyWatchdog: @unchecked Sendable {
    enum Mode: Equatable, Sendable {
        /// Sill.app itself, and where its bundle is.
        case real(bundlePath: String)
        case dry
    }

    private struct Beats: Sendable {
        var armed = false
        var last: Double = 0
    }

    let mode: Mode
    private let queue = DispatchQueue(label: "sill.privacy.watchdog", qos: .userInteractive)
    private let beats = OSAllocatedUnfairLock(initialState: Beats())
    /// Touched on `queue` only.
    private var timer: DispatchSourceTimer?

    init(mode: Mode) { self.mode = mode }

    /// The black is up: the beats count from now, and the timer looks once a second.
    func arm() {
        let now = Self.uptime()
        beats.withLock { $0 = Beats(armed: true, last: now) }
        queue.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.look() }
            t.resume()
            timer = t
        }
    }

    /// The main actor answered.
    func beat() {
        let now = Self.uptime()
        beats.withLock { if $0.armed { $0.last = now } }
    }

    /// The black is down: nothing to watch.
    func disarm() {
        beats.withLock { $0.armed = false }
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    private func look() {
        let now = Self.uptime()
        let fires = beats.withLock { (b: inout Beats) -> Bool in
            guard DarkenPolicy.watchdogFires(lastBeat: b.last, now: now, dark: b.armed) else { return false }
            b.last = now        // the dry run's count starts again
            return true
        }
        guard fires else { return }
        switch mode {
        case .dry:
            Stats.shared.bump("priv.watchdogDry")
            print(DarkenPolicy.Words.dryWatchdog)
        case .real(let bundlePath):
            end(bundlePath: bundlePath)
        }
    }

    /// Sill.app only: says why, opens Sill again unless it did within `relaunchSpacing`, and ends this process now.
    private func end(bundlePath: String) -> Never {
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 2) { _exit(70) }
        let wall = Date().timeIntervalSince1970
        let command = DarkenPolicy.reopens(lastReopen: Self.lastReopen(), now: wall) ? DarkenPolicy.reopenCommand(bundlePath: bundlePath) : nil
        print(command != nil ? DarkenPolicy.Words.watchdog : DarkenPolicy.Words.watchdogNoReopen)
        HostLog.shared.flush()
        if let command {
            Self.record(wall)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: command[0])
            p.arguments = Array(command.dropFirst())
            try? p.run()
        }
        _exit(70)
    }

    /// Seconds on a clock that stops while the Mac sleeps.
    static func uptime() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }

    /// Where the last reopening is remembered (seconds since 1970): ~/Library/Application Support/Sill/privacy-watchdog.
    private static var recordURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sill", isDirectory: true).appendingPathComponent("privacy-watchdog")
    }

    /// When the watchdog last opened Sill again; nil for never. Sill.app only (PrivacyScreen reads it at launch).
    static func lastReopen() -> Double? {
        guard let url = recordURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Written and synced before the end, so the next launch and the next watchdog read it.
    private static func record(_ wall: Double) {
        guard let url = recordURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: Data(String(format: "%.3f\n", wall).utf8)),
              let handle = FileHandle(forWritingAtPath: url.path) else { return }
        try? handle.synchronize()
        try? handle.close()
    }
}
