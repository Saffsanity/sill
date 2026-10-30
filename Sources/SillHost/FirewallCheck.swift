import Darwin
import Foundation

/// Asks the macOS Application Firewall what it holds for this process, read-only and without
/// privileges; FirewallRule decides what that means. Five questions to `socketfilterfw`, each in a
/// process of its own and given 2 s (then stopped: SIGTERM, and SIGKILL a second later):
/// `--getglobalstate` (nothing else is asked unless the firewall is on: off, Block all and a state
/// that doesn't read decide alone, FirewallRule.asksRules), `--getblockall`, `--getappblocked` for
/// the executable and for its bundle, and `--listapps`. Never a question that changes anything,
/// never sudo.
///
/// Measured on macOS 27.0.1 (2026-10-29), as an ordinary user with no privileges and no Full Disk
/// Access (Sill.app has none): each question answers in 4–8 ms, exit status 0, no prompt. Asked in
/// one run, the tool was killed (status 137, nothing printed) when some options followed
/// `--getappblocked`: `--getstealthmode` or `--getallowsigned` after either path, `--listapps` after
/// an app bundle's path (3 runs of 3 each; all five questions in one run, 133). `--getglobalstate`,
/// `--getblockall` and another `--getappblocked` after it, `--listapps` after an executable's path,
/// and each question alone answered every time: hence a process for each. The plist older Macs
/// kept, /Library/Preferences/com.apple.alf.plist, does not exist there (only the tool's own
/// defaults in /usr/libexec/ApplicationFirewall), so nothing is read from a file.
///
/// The coordinator asks at launch, whenever the listener comes up, when Sill.app's status menu or
/// Settings › General opens, and when a device gets in from the network while the verdict says none
/// can (FirewallRule.asksAgain); nothing asks on a timer.
package enum FirewallCheck {
    /// This process's executable as the kernel has it, symbolic links resolved (the firewall's rules
    /// name real paths: /private/tmp, not /tmp); the bundle's idea of it when the kernel will not say.
    package static func executablePath() -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            if !path.isEmpty { return path }
        }
        return Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    /// The firewall's answers, asked off the caller's thread, or the TEST ONLY hook's.
    package static func read(_ paths: FirewallRule.Paths, hook: TestHook?) async -> FirewallRule.Raw {
        if let hook { return hook.answers(paths) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: readNow(paths)) }
        }
    }

    /// The five questions, one after another (blocking: a utility queue's).
    static func readNow(_ paths: FirewallRule.Paths) -> FirewallRule.Raw {
        let tool = FirewallRule.Copy.tool
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            return FirewallRule.Raw(problem: "\(tool) isn’t there")
        }
        var raw = FirewallRule.Raw()
        var problems: [String] = []
        func ask(_ arguments: [String]) -> String? {
            switch run(tool, arguments) {
            case .answer(let text): return text
            case .failed(let why): problems.append(why); return nil
            }
        }
        raw.globalState = ask(["--getglobalstate"])
        // Off, Block all, or no state that reads: the verdict is decided (FirewallRule.asksRules), so
        // nothing more is asked, and a tool that doesn't answer costs one question's wait, not five.
        guard FirewallRule.asksRules(afterState: raw.globalState) else {
            raw.problem = problems.first
            return raw
        }
        raw.blockAll = ask(["--getblockall"])
        raw.executable = ask(["--getappblocked", paths.executable])
        if let bundle = paths.bundle { raw.bundle = ask(["--getappblocked", bundle]) }
        raw.listApps = ask(["--listapps"])
        raw.problem = problems.first
        return raw
    }

    private enum Outcome { case answer(String), failed(String) }

    /// Runs `tool` with `arguments`, its standard output and error read together, for at most
    /// `timeout` seconds (then it is stopped, SIGTERM and a second later SIGKILL: a question has
    /// nothing to undo).
    private static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 2) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let question = arguments.first ?? ""
        do { try process.run() } catch {
            return .failed("socketfilterfw \(question) couldn’t start: \(error.localizedDescription)")
        }
        // Read while it runs (a long list must never fill the pipe and stall it); the read ends when
        // it exits and the pipe closes.
        let output = Output()
        let reader = pipe.fileHandleForReading
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.set(reader.readDataToEndOfFile())
            read.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            // A tool that ignores SIGTERM is killed a second later, so nothing is left running, nor a
            // thread blocked on its pipe, however often Sill asks (the second review, 2026-10-29).
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            _ = read.wait(timeout: .now() + 1)
            return .failed("socketfilterfw \(question) didn’t answer in \(Int(timeout)) s")
        }
        _ = read.wait(timeout: .now() + 1)
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            return .failed("socketfilterfw \(question) ended with status \(process.terminationStatus)")
        }
        return .answer(String(decoding: output.data, as: UTF8.self))
    }

    /// What the reader read, handed from its queue to the one waiting.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        func set(_ data: Data) { lock.lock(); bytes = data; lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    }

    // MARK: TEST ONLY

    /// TEST ONLY: SILL_TEST_FIREWALL=executable|bundle|both|all|off|allowed|unreadable, or the path of
    /// a file whose first word is one of them, read again at every check so a test can change the
    /// answer while the host runs (FirewallRule.testSource and .canned): the firewall is never asked,
    /// and the answers are what macOS 27 would print in that case. Honoured only by a test host
    /// (DoorPolicy.isTestHost: one that does not advertise and is not Sill.app itself); anywhere else
    /// ignored with one line.
    package struct TestHook: Sendable {
        let source: FirewallRule.TestSource

        /// The hook, when the variable is set and this is a test host, and the line `start` prints
        /// about it (nil when the variable is not set).
        package static func read(testHost: Bool, environment: [String: String]) -> (hook: TestHook?, line: String?) {
            let taken = FirewallRule.testSource(environment["SILL_TEST_FIREWALL"], testHost: testHost)
            return (taken.source.map(TestHook.init), taken.line)
        }

        /// The canned answers for this check.
        func answers(_ paths: FirewallRule.Paths) -> FirewallRule.Raw {
            var text: String?
            if case .file(let path) = source { text = try? String(contentsOfFile: path, encoding: .utf8) }
            return FirewallRule.testAnswers(source, fileText: text, paths: paths)
        }
    }
}
