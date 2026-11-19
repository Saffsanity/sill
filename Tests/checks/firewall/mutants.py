"""Each mutant of FirewallRule.swift must fail the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "firewall")     # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/FirewallRule.swift")
orig = open(SRC).read()
MUTANTS = {
    # The paths a rule may name
    "P1 any folder for the bundle": ('parts[n - 4].hasSuffix(".app"), parts[n - 4].count > 4', 'parts[n - 4].count > 4'),
    "P2 no MacOS folder needed": ('parts[n - 2] == "MacOS", parts[n - 3] == "Contents"', 'parts[n - 3] == "Contents"'),
    "P3 the bundle one folder too deep": ("parts.dropLast(3).joined", "parts.dropLast(2).joined"),
    "P4 .app alone is a bundle": ('parts[n - 4].count > 4', 'parts[n - 4].count > 3'),
    # --getglobalstate
    "S1 on read as off": ("case 1: return .on", "case 1: return .off"),
    "S2 block all read as on": ("case 2: return .blockAll", "case 2: return .on"),
    "S3 off read as on": ("case 0: return .off", "case 0: return .on"),
    "S4 an unknown number read as on": ("            default: return .unknown\n            }\n        }\n        let t",
                                        "            default: return .on\n            }\n        }\n        let t"),
    "S5 no words without a number": ('        if t.contains("firewall is enabled") { return .on }\n', ""),
    "S6 the older block all unread": ('if t.contains("block all non-essential") || t.contains("blocking all non-essential") { return .blockAll }',
                                      'if t.contains("blocking all non-essential") { return .blockAll }'),
    "S7 an unclosed number counts": ('guard !digits.isEmpty, text[start.upperBound...].dropFirst(digits.count).first == ")" else { return nil }',
                                     'guard !digits.isEmpty else { return nil }'),
    # --getblockall
    "B1 block all off read as on": ('if t.contains("block all state set to disabled") || t.contains("block all disabled") { return false }',
                                    'if t.contains("block all state set to disabled") || t.contains("block all disabled") { return true }'),
    "B3 the legacy block all off unread": ('if t.contains("block all state set to disabled") || t.contains("block all disabled") { return false }',
                                           'if t.contains("block all state set to disabled") { return false }'),
    "B2 block all on unread": ('if t.contains("blocking all non-essential") || t.contains("set to block all non-essential") { return true }',
                               'if t.contains("set to block all non-essential") { return true }'),
    # --getappblocked
    "A1 no older form": ('for subject in [path, "the application"]', 'for subject in [path]'),
    "A2 the full stop kept": ("            if line.hasSuffix(\".\") { line.removeLast() }\n", ""),
    "A3 blocked read as permitted": ('case "blocked": return .blocked', 'case "blocked": return .permitted'),
    "A4 any answer after the path": ('let prefix = "Incoming connection to \\(subject) is "', 'let prefix = "Incoming connection to "'),
    "A5 the answer's last word unread": ('case "permitted": return .permitted', 'case "permitted": return .unknown'),
    # --listapps
    "L1 a later state line wins": ("if let last = rules.indices.last, rules[last].blocks == nil { rules[last].blocks = blocks }",
                                   "if let last = rules.indices.last { rules[last].blocks = blocks }"),
    "L2 anything is a list": ("return isList ? rules : nil", "return rules"),
    "L3 Block read as Allow": ('case "Block incoming connections": return true', 'case "Block incoming connections": return false'),
    "L4 the older state unread": ("switch line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces) {",
                                  "switch String(line.dropFirst().dropLast()) {"),
    "L5 any colon line is a rule": ("guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }",
                                    "guard !number.isEmpty else { return nil }"),
    "L6 a number that names nothing is a rule": ("return name.isEmpty ? nil : name", "return name"),
    "L7 the older total unread": ('if line.lowercased().contains("total number of apps")', 'if line.hasPrefix("Total number of apps")'),
    "L8 any mention of apps is a list": ('if line.lowercased().contains("total number of apps")', 'if line.lowercased().contains("apps")'),
    # answers
    "N1 the list never read": ("listed: raw.listApps.flatMap(listed),", "listed: nil,"),
    "N2 the bundle's answer from the executable's text": ("raw.bundle.map { appAnswer($0, path: bundle) }",
                                                          "raw.executable.map { appAnswer($0, path: bundle) }"),
    "N3 the rules asked unless off": ("text.map(state) == .on", "text.map(state) != .off"),
    "N4 the rules never asked": ("text.map(state) == .on", "text.map(state) == .off"),
    # the verdict
    "V1 off still judged": ("        case .off: return .off\n        case .blockAll", "        case .off: break\n        case .blockAll"),
    "V2 block all from the state ignored": ("        case .blockAll: return .blocksAll\n        case .unknown",
                                            "        case .blockAll: break\n        case .unknown"),
    "V3 block all from --getblockall ignored": ("        if a.blockAll == true { return .blocksAll }\n", ""),
    "V4 both must block": ("if executable != nil || bundle != nil {", "if executable != nil && bundle != nil {"),
    "V5 unread said allowed": ("        if a.listed == nil { return .unknown(a.problem ?? \"its rules didn’t read\") }\n", ""),
    "V6 an unknown state judged as on": ('case .unknown: return .unknown(a.problem ?? "its state didn’t read")', "case .unknown: break"),
    "V7 the path's own answer ignored": ("        if answer == .blocked { return path }\n", ""),
    "V8 any blocked rule counts": ("$0.path == path && $0.blocks == true", "$0.blocks == true"),
    "V9 a rule that starts with the path counts": ("$0.path == path && $0.blocks == true", "$0.path.hasPrefix(path) && $0.blocks == true"),
    "V10 a rule with no state blocks": ("$0.path == path && $0.blocks == true", "$0.path == path && $0.blocks != false"),
    "V11 the bundle never judged": ("let bundle = paths.bundle.flatMap { blocked($0, a.bundle, a.listed) }",
                                    "let bundle: String? = nil"),
    "V12 block all keeps devices in": ("            case .blocks, .blocksAll: return true\n            case .off, .allows, .unknown: return false",
                                       "            case .blocks: return true\n            case .blocksAll, .off, .allows, .unknown: return false"),
    "V13 a device over loopback counts": ("verdict?.blocksDevices == true && !fromLoopback", "verdict?.blocksDevices == true"),
    "V14 any device asks again": ("verdict?.blocksDevices == true && !fromLoopback", "!fromLoopback"),
    "V15 a path's own permitted stands in for the list": ("        if a.listed == nil { return .unknown", "        if a.listed == nil, a.executable == .unknown { return .unknown"),
    "V16 an empty list taken as unread": ("        if a.listed == nil { return .unknown", "        if a.listed?.isEmpty != false { return .unknown"),
    # words
    "W1 no sudo": ('(["sudo", tool] + paths', '([tool] + paths'),
    "W2 the bundle's first": ("let paths = [executable, bundle].compactMap { $0 }", "let paths = [bundle, executable].compactMap { $0 }"),
    "W3 the bundle called the executable": ("case (nil, .some(let name)): return name", "case (nil, .some): return \"Sill’s executable\""),
    "W4 a path unquoted": ('paths.flatMap { ["--unblockapp", shellQuoted($0)] }', 'paths.flatMap { ["--unblockapp", $0] }'),
    "W5 block all without the way out": ('connect. \\(blockAllPlace)"', 'connect."'),
    "W6 a line for every check": ("            guard old != new else { return nil }\n", ""),
    "W7 a line for a first verdict that blocks nothing": ("                guard old?.blocksDevices == true else { return nil }\n", ""),
    "W8 the blocked line without its command": ('return "Firewall: " + lowercasedFirst(line) + " " + command', 'return "Firewall: " + lowercasedFirst(line)'),
    "W9 a quote inside escaped wrongly": ("""replacingOccurrences(of: "'", with: "'\\\\''")""", """replacingOccurrences(of: "'", with: "\\\\'")"""),
    "W10 a space left plain": ('"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@%"',
                               '"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@% "'),
    "W11 a tilde left plain": ('"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@%"',
                               '"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+,:@%~"'),
    "W12 the menu silent about block all": ('case .blocksAll: return "The macOS firewall blocks all incoming connections."',
                                            'case .blocksAll: return nil'),
    "W13 no continuation between the lines": ('i < lines.count - 1 ? line + " \\\\" : line', 'line'),
    "W14 a continuation after the last line too": ('i < lines.count - 1 ? line + " \\\\" : line', 'line + " \\\\"'),
    "W15 a line's path unquoted": ('paths.map { "  --unblockapp \\(shellQuoted($0))" }', 'paths.map { "  --unblockapp \\($0)" }'),
    # TEST ONLY
    "T1 the canned list's executable rule turned round": ("executable.map { (paths.executable, $0) }", "executable.map { (paths.executable, !$0) }"),
    "T2 the report's bundle answers blocked": ("bundle: paths.bundle.map { answer($0, bundle == true) }",
                                               "bundle: paths.bundle.map { answer($0, bundle != nil) }"),
    "T3 a host that advertises takes the hook": ("        guard testHost else {\n", "        guard testHost || true else {\n"),
    "T4 an unknown word taken": ("guard cannedWords.contains(value) else {", "guard !value.isEmpty else {"),
    "T5 a relative path taken for a file": ('if value.hasPrefix("/") {', 'if value.contains("/") {'),
    "T6 the file's last word": ("fileText?.split(whereSeparator: \\.isWhitespace).first", "fileText?.split(whereSeparator: \\.isWhitespace).last"),
    "T7 the bundle's canned rule never listed": ("let listed = [paths.bundle.flatMap { path in bundle.map { (path, $0) } },",
                                                 "let listed = [Optional<(String, Bool)>.none,"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"MISSED {name}: pattern found {orig.count(old)} times"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", "-package-name", "sill", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"MISSED {name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {failed[:2]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
