import Foundation

/// The macOS Application Firewall and Sill (a user's report, 2026-10-29). The firewall keeps a rule
/// per path, and a Mac held "/Applications/Sill.app" allowed and "/Applications/Sill.app/Contents/
/// MacOS/Sill" blocked at once (`socketfilterfw --listapps`): Sill's port took nothing from the
/// network while the Mac itself connected fine, System Settings showed Sill allowed, and
/// `--getappblocked` on the bundle said "permitted". `sudo socketfilterfw --unblockapp` on the
/// executable's path fixed it.
///
/// This turns what `socketfilterfw` answers, asked read-only and without privileges (FirewallCheck),
/// into a verdict and its words: the line in Sill.app's Settings › General with the Terminal command
/// that unblocks Sill, the status menu's "Devices Can’t Connect", the log's lines. A rule that blocks
/// the running executable or its bundle counts while the firewall is on, and so does Block all
/// incoming connections, which leaves no app's own rule any say. Pure: Foundation alone, checked by
/// Tests/checks/firewall.
package enum FirewallRule {
    /// The firewall's global state (`--getglobalstate`).
    package enum State: Equatable, Sendable {
        case off, on
        /// Block all incoming connections: only essential services (DHCP, Bonjour, IPsec) get in.
        case blockAll
        /// No answer, or one this build does not know (bootstrap mode, an undefined state).
        case unknown
    }

    /// One path's answer (`--getappblocked <path>`).
    package enum AppAnswer: Equatable, Sendable { case blocked, permitted, unknown }

    /// One rule of `--listapps`: its path (or whatever the line names) and whether it blocks incoming
    /// connections; nil when no state line followed it.
    package struct Listed: Equatable, Sendable {
        package var path: String
        package var blocks: Bool?
        package init(path: String, blocks: Bool?) { self.path = path; self.blocks = blocks }
    }

    /// The paths a rule may name for this process: its executable, as the kernel has it (the
    /// firewall's rules name real paths, /private/tmp rather than /tmp), and, for an app bundle's
    /// main executable, the bundle.
    package struct Paths: Equatable, Sendable {
        package var executable: String
        package var bundle: String?
        package init(executable: String, bundle: String?) { self.executable = executable; self.bundle = bundle }
    }

    /// What `socketfilterfw` printed for each question, nil for one not asked or not answered;
    /// `problem`, why the first that went unanswered did (the log says it when nothing can be told).
    package struct Raw: Equatable, Sendable {
        package var globalState: String?
        package var blockAll: String?
        package var executable: String?
        package var bundle: String?
        package var listApps: String?
        package var problem: String?
        package init(globalState: String? = nil, blockAll: String? = nil, executable: String? = nil, bundle: String? = nil,
                     listApps: String? = nil, problem: String? = nil) {
            self.globalState = globalState; self.blockAll = blockAll; self.executable = executable; self.bundle = bundle
            self.listApps = listApps; self.problem = problem
        }
    }

    /// The answers, read.
    package struct Answers: Equatable, Sendable {
        package var state: State
        /// `--getblockall`: true while Block all incoming connections is on; nil without an answer.
        package var blockAll: Bool?
        package var executable: AppAnswer
        package var bundle: AppAnswer
        /// Every rule `--listapps` printed; nil when it printed no list.
        package var listed: [Listed]?
        package var problem: String?
        package init(state: State, blockAll: Bool? = nil, executable: AppAnswer = .unknown, bundle: AppAnswer = .unknown,
                     listed: [Listed]? = nil, problem: String? = nil) {
            self.state = state; self.blockAll = blockAll; self.executable = executable; self.bundle = bundle
            self.listed = listed; self.problem = problem
        }
    }

    /// What the firewall does to devices that connect to this process.
    package enum Verdict: Equatable, Sendable {
        /// The firewall is off.
        case off
        /// It is on, its rules were read (`--listapps`), and none blocks the executable or its bundle.
        case allows
        /// It is on, and a rule blocks these paths (at least one is set): devices on the network
        /// cannot connect, whatever the other path's rule says.
        case blocks(executable: String?, bundle: String?)
        /// Block all incoming connections is on.
        case blocksAll
        /// Its answers could not be read, and why.
        case unknown(String)

        /// Devices on the network cannot connect: Settings › General and the menu say so.
        package var blocksDevices: Bool {
            switch self {
            case .blocks, .blocksAll: return true
            case .off, .allows, .unknown: return false
            }
        }
    }

    // MARK: Paths

    /// The paths for the executable at `executable`: itself, and the bundle when it is an app
    /// bundle's main executable ("…/Sill.app/Contents/MacOS/Sill" → "…/Sill.app"); the bare
    /// SillMenuBar binary and the CLI have none.
    package static func paths(executable: String) -> Paths {
        let parts = executable.split(separator: "/", omittingEmptySubsequences: false)
        let n = parts.count
        if n >= 5, !parts[n - 1].isEmpty, parts[n - 2] == "MacOS", parts[n - 3] == "Contents",
           parts[n - 4].hasSuffix(".app"), parts[n - 4].count > 4 {
            return Paths(executable: executable, bundle: parts.dropLast(3).joined(separator: "/"))
        }
        return Paths(executable: executable, bundle: nil)
    }

    // MARK: Reading the answers

    /// `--getglobalstate`: "Firewall is enabled. (State = 1)" (macOS 27.0.1, measured), "Firewall is
    /// disabled. (State = 0)", "Firewall is blocking all non-essential incoming connections. (State =
    /// 2)"; the legacy form, whose strings the tool still holds, has a space for the full stop and
    /// says "Firewall is set to block all non-essential incoming connections " with no number. The
    /// number decides when there is one; 3 and up (bootstrap mode, an undefined state) tell nothing.
    package static func state(_ text: String) -> State {
        if let number = stateNumber(text) {
            switch number {
            case 0: return .off
            case 1: return .on
            case 2: return .blockAll
            default: return .unknown
            }
        }
        let t = text.lowercased()
        if t.contains("block all non-essential") || t.contains("blocking all non-essential") { return .blockAll }
        if t.contains("firewall is disabled") { return .off }
        if t.contains("firewall is enabled") { return .on }
        return .unknown
    }

    /// The N of "(State = N)".
    private static func stateNumber(_ text: String) -> Int? {
        guard let start = text.range(of: "(State = ") else { return nil }
        let digits = text[start.upperBound...].prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, text[start.upperBound...].dropFirst(digits.count).first == ")" else { return nil }
        return Int(digits)
    }

    /// `--getblockall`: "Firewall is blocking all non-essential incoming connections." (or the legacy
    /// "… is set to block all …") true; "Firewall has block all state set to disabled." (macOS 27.0.1,
    /// measured) or the legacy "Block all DISABLED! " false; anything else (an unknown or undefined
    /// block all state) nil.
    package static func blockAll(_ text: String) -> Bool? {
        let t = text.lowercased()
        if t.contains("blocking all non-essential") || t.contains("set to block all non-essential") { return true }
        if t.contains("block all state set to disabled") || t.contains("block all disabled") { return false }
        return nil
    }

    /// `--getappblocked <path>`: "Incoming connection to <path> is blocked." or "… is permitted."
    /// (macOS 27.0.1, measured); the legacy forms end in a space instead of the full stop, one with
    /// "the application" for the path, and say "The application is not part of the firewall " for a
    /// path with no rule (unknown here: the list decides then). Only an answer about `path` counts. On
    /// macOS 27 a path with no rule of its own reads "permitted" (measured with a path that does not
    /// exist).
    package static func appAnswer(_ text: String, path: String) -> AppAnswer {
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(".") { line.removeLast() }
            for subject in [path, "the application"] {
                let prefix = "Incoming connection to \(subject) is "
                guard line.hasPrefix(prefix) else { continue }
                switch line.dropFirst(prefix.count) {
                case "blocked": return .blocked
                case "permitted": return .permitted
                default: continue
                }
            }
        }
        return .unknown
    }

    /// `--listapps`: "Total number of apps = 46 " then each rule as "19 : /Applications/Sill.app " over
    /// "             (Allow incoming connections)" or "(Block incoming connections)" (macOS 27.0.1,
    /// measured: 46 rules on this Mac, every one Allow); the legacy state is "( Block incoming
    /// connections )". A state line belongs to the rule right above it. Nil when the text is no list.
    package static func listed(_ text: String) -> [Listed]? {
        var rules: [Listed] = []
        var isList = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().contains("total number of apps") { isList = true; continue }
            if let blocks = ruleState(line) {
                if let last = rules.indices.last, rules[last].blocks == nil { rules[last].blocks = blocks }
                continue
            }
            if let name = ruleName(line) { rules.append(Listed(path: name, blocks: nil)) }
        }
        return isList ? rules : nil
    }

    /// "(Block incoming connections)" or "( Block incoming connections )" true, the Allow ones false.
    private static func ruleState(_ line: String) -> Bool? {
        guard line.hasPrefix("("), line.hasSuffix(")") else { return nil }
        switch line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces) {
        case "Block incoming connections": return true
        case "Allow incoming connections": return false
        default: return nil
        }
    }

    /// "12 : /Applications/Sill.app" → "/Applications/Sill.app": what a numbered line names.
    private static func ruleName(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let number = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let name = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Whether FirewallCheck asks anything after `--getglobalstate` (`text`, its answer; nil when it
    /// gave none): only while the firewall is on. Off, Block all and a state that doesn't read decide
    /// the verdict alone (`verdict`), so nothing more is asked then, and a tool that doesn't answer
    /// costs one question's wait, not five (the second review, 2026-10-29).
    package static func asksRules(afterState text: String?) -> Bool {
        text.map(state) == .on
    }

    /// Every answer read; `paths` says which of them are about this process.
    package static func answers(_ raw: Raw, paths: Paths) -> Answers {
        Answers(state: raw.globalState.map(state) ?? .unknown,
                blockAll: raw.blockAll.flatMap(blockAll),
                executable: raw.executable.map { appAnswer($0, path: paths.executable) } ?? .unknown,
                bundle: paths.bundle.flatMap { bundle in raw.bundle.map { appAnswer($0, path: bundle) } } ?? .unknown,
                listed: raw.listApps.flatMap(listed),
                problem: raw.problem)
    }

    // MARK: The verdict

    /// What the firewall does to devices connecting to this process. Off: nothing. On: a path is
    /// blocked when its own answer says so or a rule `--listapps` printed for exactly that path
    /// blocks, either one enough (on the report's Mac the bundle's answer said "permitted" beside its
    /// executable's rule that blocked); allowed only once the list was read and nothing blocks; else
    /// unknown, with why. A path's own "permitted" never stands in for the list (the review,
    /// 2026-10-29): the list is what showed the report's rule, a "permitted" is what misled there,
    /// and a list that didn't read (the tool killed or slow, or refusing an option it no longer
    /// knows, which ends with status 255) is said in the log instead of taken for allowed. Block all
    /// incoming connections, from either answer, blocks whatever the rules say.
    package static func verdict(_ a: Answers, paths: Paths) -> Verdict {
        switch a.state {
        case .off: return .off
        case .blockAll: return .blocksAll
        case .unknown: return .unknown(a.problem ?? "its state didn’t read")
        case .on: break
        }
        if a.blockAll == true { return .blocksAll }
        let executable = blocked(paths.executable, a.executable, a.listed)
        let bundle = paths.bundle.flatMap { blocked($0, a.bundle, a.listed) }
        if executable != nil || bundle != nil { return .blocks(executable: executable, bundle: bundle) }
        if a.listed == nil { return .unknown(a.problem ?? "its rules didn’t read") }
        return .allows
    }

    /// The raw answers' verdict.
    package static func verdict(_ raw: Raw, paths: Paths) -> Verdict {
        verdict(answers(raw, paths: paths), paths: paths)
    }

    /// A device reached this host from the network while the last verdict says none can: the
    /// firewall has changed since (the user ran the command from the support page with Settings
    /// closed, say), so it is asked again, and the menu's "Devices Can’t Connect" goes without
    /// General being opened. Not for a connection over loopback, which the firewall never filters.
    package static func asksAgain(after verdict: Verdict?, fromLoopback: Bool) -> Bool {
        verdict?.blocksDevices == true && !fromLoopback
    }

    /// `path` when its answer or a rule for it blocks.
    private static func blocked(_ path: String, _ answer: AppAnswer, _ listed: [Listed]?) -> String? {
        if answer == .blocked { return path }
        if listed?.contains(where: { $0.path == path && $0.blocks == true }) == true { return path }
        return nil
    }

    // MARK: Words

    package enum Copy {
        /// The firewall's own command-line tool, which FirewallCheck asks and the Terminal command runs.
        package static let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"

        /// Where Block all incoming connections is turned off (macOS 13 and later).
        static let blockAllPlace = "Turn off Block all incoming connections in System Settings › Network › Firewall › Options."

        /// The Terminal command that unblocks what the verdict says is blocked, one `--unblockapp` a
        /// path (the tool takes several options in one run, in order). The executable's first and the
        /// bundle's last: asked in one run, the tool was killed when some options followed a bundle's
        /// path (FirewallCheck), and nothing follows it here. Nil unless rules block: Block all
        /// incoming connections is turned off in System Settings.
        package static func command(_ verdict: Verdict) -> String? {
            guard let paths = unblocked(verdict) else { return nil }
            return (["sudo", tool] + paths.flatMap { ["--unblockapp", shellQuoted($0)] }).joined(separator: " ")
        }

        /// The paths the command unblocks, the executable's first; nil unless rules block one.
        static func unblocked(_ verdict: Verdict) -> [String]? {
            guard case .blocks(let executable, let bundle) = verdict else { return nil }
            let paths = [executable, bundle].compactMap { $0 }
            return paths.isEmpty ? nil : paths
        }

        /// `command` as Settings › General shows it: the tool on the first line, then each
        /// `--unblockapp` and its path on a line of its own, after the shell's line continuation (" \\"),
        /// so a line never breaks inside an option ("--" over "unblockapp", as a wrapped line did) and
        /// the lines, selected and pasted into Terminal, are still the one command. Copy copies
        /// `command` itself, on one line.
        package static func commandLines(_ verdict: Verdict) -> [String]? {
            guard let paths = unblocked(verdict) else { return nil }
            let lines = ["sudo \(tool)"] + paths.map { "  --unblockapp \(shellQuoted($0))" }
            return lines.enumerated().map { i, line in i < lines.count - 1 ? line + " \\" : line }
        }

        /// What the rules block: "Sill’s executable", the bundle by its name ("Sill.app"), or
        /// "Sill.app and its executable".
        static func what(executable: String?, bundle: String?) -> String {
            let name = bundle.map { ($0 as NSString).lastPathComponent }
            switch (executable, name) {
            case (.some, .some(let name)): return "\(name) and its executable"
            case (nil, .some(let name)): return name
            default: return "Sill’s executable"
            }
        }

        /// Settings › General's line, while devices cannot connect: what is blocked and why it
        /// matters, then "In Terminal:" over the command (`command`), or where to turn Block all off.
        package static func paneLine(_ verdict: Verdict) -> String? {
            switch verdict {
            case .blocks(let executable, let bundle):
                return "The macOS firewall blocks \(what(executable: executable, bundle: bundle)), so devices on the network cannot connect. In Terminal:"
            case .blocksAll:
                return "The macOS firewall blocks all incoming connections, so devices on the network cannot connect. \(blockAllPlace)"
            case .off, .allows, .unknown:
                return nil
            }
        }

        /// The status menu's "Devices Can’t Connect" subtitle: one sentence, one line.
        package static func menuSubtitle(_ verdict: Verdict) -> String? {
            switch verdict {
            case .blocks(let executable, let bundle): return "The macOS firewall blocks \(what(executable: executable, bundle: bundle))."
            case .blocksAll: return "The macOS firewall blocks all incoming connections."
            case .off, .allows, .unknown: return nil
            }
        }

        /// The log's line when the verdict changes from `old` (nil before the first check): what is
        /// blocked and the way out; that nothing is blocked any more; that the firewall could not be
        /// read. Nothing for a first verdict that blocks nothing, so a host the firewall leaves
        /// alone prints what it always printed.
        package static func logLine(from old: Verdict?, to new: Verdict) -> String? {
            guard old != new else { return nil }
            switch new {
            case .blocks:
                guard let line = paneLine(new), let command = command(new) else { return nil }
                return "Firewall: " + lowercasedFirst(line) + " " + command
            case .blocksAll:
                return paneLine(new).map { "Firewall: " + lowercasedFirst($0) }
            case .off, .allows:
                guard old?.blocksDevices == true else { return nil }
                return "Firewall: the macOS firewall no longer blocks devices from connecting to Sill."
            case .unknown(let why):
                return "Firewall: couldn’t read the macOS firewall’s settings (\(why)), so Sill can’t tell whether it blocks devices."
            }
        }

        private static func lowercasedFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

        /// `path` as one word for zsh and bash: as it is when it holds only characters no shell
        /// treats specially, else in single quotes, a quote inside as '\''.
        package static func shellQuoted(_ path: String) -> String {
            let plain = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@%".unicodeScalars)
            if !path.isEmpty, path.unicodeScalars.allSatisfy(plain.contains) { return path }
            return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
    }

    // MARK: TEST ONLY

    /// The answers SILL_TEST_FIREWALL gives a test host instead of asking, as macOS 27.0.1 prints
    /// them: `executable` the report's Mac (on; the bundle's rule allows, the executable's blocks, the
    /// bundle's own answer "permitted"), `bundle` (the bundle's rule blocks), `both`, `all` (Block all
    /// incoming connections), `off`, `allowed` (on, nothing blocked) and `unreadable` (nothing
    /// answers). A process with no bundle (the bare binary, the CLI) has no bundle's rule to block.
    /// Nil for any other word.
    package static func canned(_ word: String, paths: Paths) -> Raw? {
        let on = "Firewall is enabled. (State = 1)"
        let notAll = "Firewall has block all state set to disabled."
        func answer(_ path: String, _ blocked: Bool) -> String {
            "Incoming connection to \(path) is \(blocked ? "blocked" : "permitted")."
        }
        func list(_ rules: [(String, Bool)]) -> String {
            var text = "Total number of apps = \(rules.count) \n"
            for (i, rule) in rules.enumerated() {
                text += "\(i + 1) : \(rule.0) \n             (\(rule.1 ? "Block" : "Allow") incoming connections)\n"
            }
            return text
        }
        /// On, with these rules for the executable and the bundle (nil: no rule of its own).
        func rules(executable: Bool?, bundle: Bool?) -> Raw {
            let listed = [paths.bundle.flatMap { path in bundle.map { (path, $0) } },
                          executable.map { (paths.executable, $0) }].compactMap { $0 }
            return Raw(globalState: on, blockAll: notAll, executable: answer(paths.executable, executable == true),
                       bundle: paths.bundle.map { answer($0, bundle == true) }, listApps: list(listed))
        }
        switch word {
        case "executable": return rules(executable: true, bundle: false)
        case "bundle": return rules(executable: nil, bundle: true)
        case "both": return rules(executable: true, bundle: true)
        case "allowed": return rules(executable: nil, bundle: false)
        case "all":
            return Raw(globalState: "Firewall is blocking all non-essential incoming connections. (State = 2)",
                       blockAll: "Firewall is blocking all non-essential incoming connections.",
                       executable: answer(paths.executable, false), bundle: paths.bundle.map { answer($0, false) },
                       listApps: list(paths.bundle.map { [($0, false)] } ?? []))
        case "off":
            return Raw(globalState: "Firewall is disabled. (State = 0)")
        case "unreadable":
            return Raw(problem: "SILL_TEST_FIREWALL=unreadable: nothing answered")
        default:
            return nil
        }
    }

    /// The words SILL_TEST_FIREWALL takes.
    package static let cannedWords = ["executable", "bundle", "both", "all", "off", "allowed", "unreadable"]

    /// Where a test host's answers come from: one of `cannedWords`, or a file whose first word is one,
    /// read again at every check so a test can change the answer while the host runs.
    package enum TestSource: Equatable, Sendable {
        case word(String)
        case file(String)
    }

    /// SILL_TEST_FIREWALL (`value`) as a host takes it, with the line `start` prints about it (nil when
    /// the variable is not set): only a test host (DoorPolicy.isTestHost: one that does not advertise
    /// and is not Sill.app itself) takes it, and only a word `canned` knows or an absolute path; the
    /// firewall is then never asked.
    package static func testSource(_ value: String?, testHost: Bool) -> (source: TestSource?, line: String?) {
        guard let value, !value.isEmpty else { return (nil, nil) }
        guard testHost else {
            return (nil, "SILL_TEST_FIREWALL ignored: only a test host takes it (one that does not advertise and is not Sill.app itself).")
        }
        if value.hasPrefix("/") {
            return (.file(value), "Test firewall: the macOS firewall is never asked; its answers are canned (the word in \(value), read at each check).")
        }
        guard cannedWords.contains(value) else {
            return (nil, "SILL_TEST_FIREWALL=\(value) ignored: expected \(cannedWords.joined(separator: ", ")), or a file holding one.")
        }
        return (.word(value), "Test firewall: the macOS firewall is never asked; its answers are canned (\(value)).")
    }

    /// A check's canned answers: the word's, or the first word of the file's text (`fileText`, nil
    /// when the file could not be read). A word `canned` does not know answers nothing, and says why.
    package static func testAnswers(_ source: TestSource, fileText: String?, paths: Paths) -> Raw {
        switch source {
        case .word(let word):
            return canned(word, paths: paths) ?? Raw(problem: "SILL_TEST_FIREWALL: no answers for \(word)")
        case .file(let path):
            let word = fileText?.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            return canned(word, paths: paths) ?? Raw(problem: "SILL_TEST_FIREWALL: no known word in \(path)")
        }
    }
}
