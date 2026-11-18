import Foundation

/// The kernel's word on whether a process is still there. Update Now's new copy waits at launch for the Sill
/// that started it to quit (AppUpdater.waitForOtherSill), and what it asked at first, NSRunningApplication's
/// `isTerminated`, is a value AppKit keeps from LaunchServices' notifications: in a Sill that had only just
/// launched it stayed false through the wait's 30 s although the other Sill had exited 0.2 s after saying so
/// (the rehearsal, 2026-11-15: the new copy gave up and quit, and no Sill was running until it was opened by
/// hand). A pid goes to another process once its own is gone, so a process is known here by its pid and the
/// time it started. Foundation only; `Tests/checks/update-install` runs it against a process of its own.
struct ProcessLife: Equatable, Sendable {
    /// When a process started, by the kernel.
    struct Start: Equatable, Sendable {
        let seconds: Int
        let microseconds: Int
    }

    let pid: pid_t
    /// Nil when it couldn't be read.
    let started: Start?

    /// The process that has `pid` now; nil when none has.
    static func of(_ pid: pid_t) -> ProcessLife? {
        guard exists(pid) else { return nil }
        return ProcessLife(pid: pid, started: start(of: pid))
    }

    /// Whether this very process has gone, asked now.
    var gone: Bool { Self.gone(then: self, now: Self.of(pid)) }

    /// The rule: gone when no process has the pid, or when the one that has it started at another time (the pid
    /// was given to another process). A start that couldn't be read, then or now, decides nothing: a process
    /// with the pid then counts as the same one, so a Sill is never started beside one that may still run.
    static func gone(then: ProcessLife, now: ProcessLife?) -> Bool {
        guard let now else { return true }
        if let before = then.started, let after = now.started, before != after { return true }
        return false
    }

    /// A process has `pid`. `kill` with signal 0 sends nothing; it fails with ESRCH only when there is none
    /// (with EPERM there is one, another account's). No pid at all (0 or less) counts as there.
    static func exists(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno != ESRCH
    }

    /// The process that started `pid` (its parent, kern.proc.pid); nil when there is no such process or it can't
    /// be read. A process this one is starting shows this one's own program path until its own is loaded, so a
    /// look for other copies of Sill by path takes its own child for one (UpdateInstaller.processesRunning).
    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard pid > 0, sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0,
              size >= MemoryLayout<kinfo_proc>.stride, info.kp_proc.p_pid == pid else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// When the process `pid` started (kern.proc.pid); nil when there is none or it can't be read.
    static func start(of pid: pid_t) -> Start? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard pid > 0, sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0,
              size >= MemoryLayout<kinfo_proc>.stride, info.kp_proc.p_pid == pid else { return nil }
        let t = info.kp_proc.p_starttime
        return Start(seconds: Int(t.tv_sec), microseconds: Int(t.tv_usec))
    }
}
