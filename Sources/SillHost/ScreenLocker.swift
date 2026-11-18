import Foundation
import Darwin

/// The lock itself (PrivacyPolicy's `.lock` and `.sleepDisplays`; docs/privacy-mode-plan.md, part 1), on a queue of
/// its own (`sill.privacy.lock`): each is an IPC that may block, never on the main actor.
///
/// - The lock: login.framework's `SACLockScreenImmediate`, the call macOS's own "Lock Screen" makes, private as the
///   CGVirtualDisplay and SkyLight calls the host already makes. Looked up once with `dlopen` and `dlsym`, declared
///   `@convention(c) () -> Void` as #184 and the one published write-up found it; exported on macOS 27.2.1 (measured
///   2026-11-18 with `dyld_info -exports`, and looked up without a call). It returns nothing: whether the Mac locked
///   is SessionLock's reading within `PrivacyPolicy.lockConfirm`. Missing, it answers `.unavailable`, said in the
///   log at each attempt and in Settings › Devices.
/// - The display sleep: `/usr/bin/pmset displaysleepnow`, which needs no privilege (#275).
///
/// A test host's locker is a dry run (`dry`): it never loads login.framework, never calls it and never runs pmset;
/// it prints what it would do (`PrivacyPolicy.Words.dryLock`, `.drySleep`), counts `priv.lockDry` and
/// `priv.sleepDry`, and answers `.made`, or `.unavailable` under the TEST ONLY SILL_TEST_PRIVACY_NO_SYMBOL. Nothing
/// on a test host can lock this Mac or put its display to sleep.
final class ScreenLocker: @unchecked Sendable {
    /// Whether this locker acts (Sill.app) or only says what it would do (a test host).
    enum Mode: Equatable, Sendable {
        case real
        case dry(noSymbol: Bool)
    }

    let mode: Mode
    private let queue = DispatchQueue(label: "sill.privacy.lock", qos: .userInitiated)

    init(mode: Mode) { self.mode = mode }

    /// Locks this Mac now, on the locker's queue; `done` gets the answer there.
    func lock(_ done: @escaping @Sendable (PrivacyPolicy.Call) -> Void) {
        let mode = self.mode
        queue.async {
            switch mode {
            case .dry(let noSymbol):
                print(PrivacyPolicy.Words.dryLock)
                Stats.shared.bump("priv.lockDry")
                done(noSymbol ? .unavailable(PrivacyPolicy.Words.unavailableLog) : .made)
            case .real:
                guard let call = Self.lockScreenImmediate else {
                    done(.unavailable(PrivacyPolicy.Words.unavailableLog))
                    return
                }
                Stats.shared.bump("priv.lock")
                call()
                done(.made)
            }
        }
    }

    /// Puts the displays to sleep now (`pmset displaysleepnow`), on the locker's queue.
    func sleepDisplays() {
        let mode = self.mode
        queue.async {
            guard mode == .real else {
                print(PrivacyPolicy.Words.drySleep)
                Stats.shared.bump("priv.sleepDry")
                return
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["displaysleepnow"]
            do {
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus != 0 { print("Privacy: pmset displaysleepnow exited with status \(p.terminationStatus).") }
                Stats.shared.bump("priv.sleep")
            } catch {
                print("Privacy: couldn’t run pmset displaysleepnow: \(error.localizedDescription)")
            }
        }
    }

    // MARK: The private call (Sill.app only)

    /// `void SACLockScreenImmediate(void)`.
    private typealias LockScreenImmediate = @convention(c) () -> Void

    /// Where macOS keeps login.framework (in the dyld shared cache; dlopen finds it by this path).
    static let frameworkPaths = ["/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
                                 "/System/Library/PrivateFrameworks/login.framework/login"]

    /// Looked up once, at the first lock, never on a test host (`mode` is checked first). Nil when the framework or
    /// the symbol is missing.
    private static let lockScreenImmediate: LockScreenImmediate? = {
        for path in frameworkPaths {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { continue }
            if let symbol = dlsym(handle, "SACLockScreenImmediate") { return unsafeBitCast(symbol, to: LockScreenImmediate.self) }
        }
        return nil
    }()
}
