import Foundation

/// Which identity store the menu-bar host uses, and why (docs/keychain-plan.md). Pure: it turns
/// four launch facts into one choice, so the rule is checked on its own (Tests/checks/keychain)
/// without a keychain, a bundle or a signature. AppModel reads the facts (its bundle, its arguments,
/// its own entitlements) and builds the store the choice names.
enum IdentityStoreChoice: Equatable {
    /// Sill.app entitled to a keychain access group (a Developer ID build with an embedded
    /// provisioning profile): the data-protection keychain under that group, which only a process of
    /// the same team and entitlement can read or create. Never the legacy store beside it, so a
    /// legacy item another process planted before the first launch cannot be adopted.
    case dataProtection(accessGroup: String)
    /// Sill.app without that entitlement (a development build signed Apple Development, or a release
    /// with no embedded profile): the legacy login keychain, as remote access shipped it. Safe by
    /// necessity — the entitlement, hence the strong keychain, needs a profile — and every real user
    /// runs the entitled Developer ID build.
    case legacy
    /// A test host that never touches a keychain: `--synthetic`, or the bare SillMenuBar binary
    /// (whose ad hoc signature changes every build). Nothing outlives the process.
    case memory
    /// TEST ONLY (SILL_TEST_REMOTE_DIR): the bare `--synthetic` binary keeps the identity in a 0700
    /// directory, so a test can pair, restart and find the same Mac ID.
    case testDirectory(String)
}

enum IdentityStorePlan {
    /// The store for this launch (docs/keychain-plan.md §4).
    ///
    /// - `bundled`: running from a `.app` (real Sill.app), not the bare SillMenuBar test binary.
    /// - `synthetic`: `--synthetic` (a test host, off Bonjour).
    /// - `entitledAccessGroup`: the `keychain-access-groups` value the running binary actually holds,
    ///   read from its own signature at launch (nil for any build without an embedded profile: every
    ///   development and ad hoc build, as measured — an unentitled binary reads its own entitlement
    ///   as nil). Non-nil means the data-protection keychain is reachable under that group.
    /// - `testRemoteDir`: SILL_TEST_REMOTE_DIR, already trimmed to non-empty by the caller.
    ///
    /// The one rule that matters for the hardening: an entitled real Sill.app uses the
    /// data-protection keychain and never the legacy one, so no planted legacy item is ever adopted;
    /// an unentitled real Sill.app uses the legacy keychain (the safe, profile-free fallback).
    static func choose(bundled: Bool, synthetic: Bool, entitledAccessGroup: String?, testRemoteDir: String?) -> IdentityStoreChoice {
        // A test host — the bare binary, or Sill.app run with --synthetic — keeps nothing in a
        // keychain: its signature is not stable, and a test must never write the login keychain.
        if synthetic || !bundled {
            if synthetic, !bundled, let dir = testRemoteDir, !dir.isEmpty { return .testDirectory(dir) }
            return .memory
        }
        // Real Sill.app: the data-protection keychain only when entitled to a group, and then only
        // that — never the legacy store as well. Otherwise the legacy login keychain.
        if let group = entitledAccessGroup, !group.isEmpty { return .dataProtection(accessGroup: group) }
        return .legacy
    }
}

/// Persistent headless pairing through an authenticated CLI workflow (issue #180):
/// `Sill.app/Contents/MacOS/Sill --pair-code` asks the running `Sill.app` instance (over a
/// `0700` per-user directory and `0600` response file) to open its pairing window using its
/// persistent identity and trust list, and prints the single-use 12-digit code and link to the
/// terminal without writing them to `Sill.log`.
enum HeadlessPairing {
    static let flag = "--pair-code"
    static let requestNotification = Notification.Name("me.saffer.sill.mac.headlessPairRequest")

    enum Validation: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    struct Response: Codable, Equatable, Sendable {
        var groupedCode: String?
        var url: String?
        var expiresInSeconds: Int?
        var port: Int?
        var error: String?
    }

    static func requested(in arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    static func validateRequest(isTerminal: Bool, hostRunning: Bool) -> Validation {
        guard isTerminal else {
            return .refused("Refused: --pair-code must be run from an interactive terminal (such as SSH or Terminal).")
        }
        guard hostRunning else {
            return .refused("Sill is not running. Start Sill first, then run --pair-code again.")
        }
        return .allowed
    }

    static func encode(_ response: Response) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data()
    }

    static func decode(_ data: Data) -> Response? {
        try? JSONDecoder().decode(Response.self, from: data)
    }

    static func outputLines(for response: Response) -> [String] {
        if let error = response.error, !error.isEmpty {
            return ["Pairing failed: \(error)"]
        }
        guard let code = response.groupedCode, !code.isEmpty, let url = response.url else {
            return ["Pairing failed: Sill did not return a pairing code."]
        }
        let seconds = max(1, response.expiresInSeconds ?? 300)
        let minutes = Int((Double(seconds) / 60.0).rounded())
        let span = seconds >= 60 ? "\(minutes) minute\(minutes == 1 ? "" : "s")" : "\(seconds) s"
        let port = response.port ?? 7455
        return [
            "Pairing code (valid for \(span), single-use): \(code)",
            "Pairing link: \(url)",
            "On your iPhone or iPad, open Sill → Add a Mac → Enter Code Instead (port \(port)).",
        ]
    }
}

#if canImport(AppKit) && canImport(SillHostCore)
import AppKit
import Darwin
import SillHostCore

extension HeadlessPairing {
    static var ipcDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["SILL_TEST_REMOTE_DIR"], !dir.isEmpty, !AppModel.bundled {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Sill/HeadlessPairing", isDirectory: true)
    }

    static var runningMarkerURL: URL { ipcDirectory.appendingPathComponent("host.pid") }
    static var responseFileURL: URL { ipcDirectory.appendingPathComponent("pair-response.json") }

    private static func ensurePrivateDirectory() throws {
        let dir = ipcDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }

    /// Runs the `--pair-code` CLI command before `HostLog` or `NSApplication` starts, printing
    /// only to `stdout`/`stderr` (never `Sill.log`) and exiting.
    static func runCLIIfRequested(arguments: [String] = CommandLine.arguments) {
        guard requested(in: arguments) else { return }
        let isTTY = isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
        let allowNonTTYTest = !AppModel.bundled && ProcessInfo.processInfo.environment["SILL_TEST_PAIR_CLI"] == "1"
        let hostRunning = isHostRunning()
        switch validateRequest(isTerminal: isTTY || allowNonTTYTest, hostRunning: hostRunning) {
        case .refused(let reason):
            FileHandle.standardError.write(Data((reason + "\n").utf8))
            exit(1)
        case .allowed:
            break
        }
        let responseURL = responseFileURL
        try? FileManager.default.removeItem(at: responseURL)
        let nonce = UUID().uuidString
        DistributedNotificationCenter.default().postNotificationName(
            requestNotification,
            object: nonce,
            userInfo: nil,
            deliverImmediately: true
        )
        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline {
            if let data = try? Data(contentsOf: responseURL), let response = decode(data) {
                try? FileManager.default.removeItem(at: responseURL)
                for line in outputLines(for: response) {
                    FileHandle.standardOutput.write(Data((line + "\n").utf8))
                }
                exit(response.error == nil ? 0 : 1)
            }
            usleep(50_000)
        }
        FileHandle.standardError.write(Data("Pairing timed out waiting for Sill.\n".utf8))
        exit(1)
    }

    private static func isHostRunning() -> Bool {
        if let text = try? String(contentsOf: runningMarkerURL, encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 0, kill(pid, 0) == 0 {
            return true
        }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: "me.saffer.sill.mac").isEmpty
    }

    @MainActor
    static func startHostListener(model: AppModel) {
        do {
            try ensurePrivateDirectory()
            let pidData = Data("\(getpid())\n".utf8)
            try FileIdentityStore.writePrivate(pidData, to: runningMarkerURL)
        } catch {
            return
        }
        DistributedNotificationCenter.default().addObserver(
            forName: requestNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                model.handleHeadlessPairRequest()
            }
        }
    }

    @MainActor
    static func writeOffer(_ offer: RemoteAccess.PairingOffer) {
        do {
            try ensurePrivateDirectory()
            let secs = max(1, Int(offer.expiresAt.timeIntervalSinceNow.rounded()))
            let response = Response(
                groupedCode: offer.groupedCode,
                url: offer.url,
                expiresInSeconds: secs,
                port: offer.port,
                error: nil
            )
            try FileIdentityStore.writePrivate(encode(response), to: responseFileURL)
        } catch {}
    }

    @MainActor
    static func writeError(_ message: String) {
        do {
            try ensurePrivateDirectory()
            let response = Response(groupedCode: nil, url: nil, expiresInSeconds: nil, port: nil, error: message)
            try FileIdentityStore.writePrivate(encode(response), to: responseFileURL)
        } catch {}
    }
}
#endif
