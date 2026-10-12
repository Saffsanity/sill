import AppKit
import Darwin

/// Input a Sill host on this Mac posted (it is being controlled from elsewhere): never sent on. With a
/// viewer on each of two Macs showing the other's Desktop, a move here reached the other Mac, landed
/// on its viewer, came back here as that host's posted move, and so on: neither pointer could be
/// moved (2026-10-12). A posted event carries the posting process (eventSourceUnixProcessID); the
/// hosts are Sill.app and the SillHost command-line tool. Main thread.
enum LocalHostInput {
    private static var known: [pid_t: Bool] = [:]

    /// Whether the event being handled now came from a Sill host on this Mac.
    static var current: Bool {
        guard let event = NSApp.currentEvent?.cgEvent else { return false }
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        return pid > 0 && isHost(pid)
    }

    private static func isHost(_ pid: pid_t) -> Bool {
        if let cached = known[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let name = proc_pidpath(pid, &path, UInt32(path.count)) > 0 ? (String(cString: path) as NSString).lastPathComponent : ""
        let host = app?.bundleIdentifier == "me.saffer.sill.mac" || ["SillHost", "SillMenuBar"].contains(name)
        known[pid] = host
        return host
    }
}
