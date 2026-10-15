import Foundation

/// Which running apps ask for the user's attention now, their Dock icon bouncing (`requestUserAttention`):
/// the Dock keeps it in each app's LaunchServices information, `LSWantsAttention` 1 while it asks, 0 or
/// absent otherwise (docs/notifications-spike.md, §2). Read through two private, exported LaunchServices
/// calls, in this login session; no permission. Nil when the calls are missing (another macOS), so the
/// host sends nothing rather than something wrong. Any thread.
enum AttentionWatch {
    private typealias CopyRunning = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyInformation = @convention(c) (Int32, UnsafeRawPointer?, CFArray?) -> Unmanaged<CFDictionary>?
    private static let calls: (CopyRunning, CopyInformation)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let running = dlsym(handle, "_LSCopyRunningApplicationArray"),
              let information = dlsym(handle, "_LSCopyApplicationInformation") else { return nil }
        return (unsafeBitCast(running, to: CopyRunning.self), unsafeBitCast(information, to: CopyInformation.self))
    }()
    /// kLSDefaultSessionID: the caller's own session.
    private static let session: Int32 = -1
    /// Only the two keys read, not each app's whole dictionary.
    private static let keys = ["CFBundleIdentifier", "LSWantsAttention"] as CFArray

    /// The bundle IDs of the running apps asking for attention.
    static func bundleIDs() -> Set<String>? {
        guard let (copyRunning, copyInformation) = calls,
              let apps = copyRunning(session)?.takeRetainedValue() as? [AnyObject] else { return nil }
        var asking: Set<String> = []
        for asn in apps {
            guard let info = copyInformation(session, Unmanaged.passUnretained(asn).toOpaque(), keys)?
                    .takeRetainedValue() as? [String: Any],
                  (info["LSWantsAttention"] as? NSNumber)?.boolValue == true,
                  let id = info["CFBundleIdentifier"] as? String else { continue }
            asking.insert(id)
        }
        return asking
    }
}
