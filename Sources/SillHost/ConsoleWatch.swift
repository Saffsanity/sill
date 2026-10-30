import AppKit
import CoreGraphics

/// Runs ConsoleSession (issue #211) on the main actor: whether this Mac's user session has the
/// console, looked at when the host starts (`start`), at each NSWorkspace session notification, as
/// a device connects (`look`), and once a second while any is connected (`watch`). A change prints
/// its line and calls `onChange`, which the coordinator puts in the status snapshot, and so in every
/// device's kind 16.
///
/// A synthetic host never reads this Mac's console: with SILL_TEST_CONSOLE_FILE (TEST ONLY) it reads
/// that file, without it nothing, and it stays on the console.
@MainActor
final class ConsoleWatch {
    /// The last look that said anything; true until one does, as a host before #221 told devices
    /// nothing.
    private(set) var onConsole = true
    /// After a change's line.
    var onChange: ((Bool) -> Void)?
    private let read: () -> Bool?
    /// False for a synthetic host without the test file: it never looks at all.
    private let looks: Bool
    private let notifications: Bool
    private var observers: [NSObjectProtocol] = []
    private var looking: Task<Void, Never>?

    /// `testFile`: SILL_TEST_CONSOLE_FILE's path, honoured only when `synthetic`
    /// (ConsoleSession.testHook decides).
    init(synthetic: Bool, testFile: String?) {
        if synthetic {
            read = { testFile.map { ConsoleSession.testRead(contents: try? String(contentsOfFile: $0, encoding: .utf8)) } }
        } else {
            read = { ConsoleSession.onConsole(dictionary: CGSessionCopyCurrentDictionary() as? [String: Any]) }
        }
        looks = !synthetic || testFile != nil
        notifications = !synthetic
    }

    /// A look now, and from here on one at each session notification. The notifications only say
    /// when to look: the dictionary says what is so.
    func start() {
        guard looks else { return }
        look()
        guard notifications, observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.look() }
            })
        }
    }

    /// While `on` (a device is connected): a look now, then one every ConsoleSession.lookInterval.
    func watch(_ on: Bool) {
        guard looks, on else {
            looking?.cancel()
            looking = nil
            return
        }
        guard looking == nil else { return }
        looking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.look()
                try? await Task.sleep(for: .seconds(ConsoleSession.lookInterval))
            }
        }
    }

    /// One look: a change prints its line and calls `onChange`.
    func look() {
        guard looks, let change = ConsoleSession.next(current: onConsole, read: read()) else { return }
        onConsole = change.onConsole
        print(change.line)
        onChange?(change.onConsole)
    }
}
