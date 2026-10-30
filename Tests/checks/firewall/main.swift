import Foundation

// Checks FirewallRule (Sources/SillHost/FirewallRule.swift; a user's report of 2026-10-29): what
// `socketfilterfw`'s read-only answers mean for Sill, and every word Sill says about it. Compiled
// alone with swiftc (Foundation only; `package` access needs -package-name), run.sh:
//   swiftc -O -package-name sill Sources/SillHost/FirewallRule.swift Tests/checks/firewall/main.swift
// The answers below are macOS 27.0.1's as measured on 2026-10-29 (as an ordinary user, no sudo), and
// the legacy form whose strings the tool still holds (`strings socketfilterfw`). The report's Mac is
// the case that matters most: the bundle allowed, its executable blocked, and the bundle's own answer
// "permitted".

typealias R = FirewallRule
var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL line \(line): \(what())") }
}
func same<T: Equatable>(_ got: T, _ want: T, _ what: String, line: Int = #line) {
    check(got == want, "\(what): got \(got), want \(want)", line: line)
}

let exe = "/Applications/Sill.app/Contents/MacOS/Sill"
let app = "/Applications/Sill.app"
let bundled = R.Paths(executable: exe, bundle: app)
let bare = R.Paths(executable: "/private/tmp/sill/.build/arm64-apple-macosx/release/SillMenuBar", bundle: nil)
let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"

// MARK: The paths a rule may name

same(R.paths(executable: exe), bundled, "Sill.app's executable and its bundle")
same(R.paths(executable: "/Users/me/Downloads/Sill 2.app/Contents/MacOS/Sill").bundle, "/Users/me/Downloads/Sill 2.app", "a renamed copy")
same(R.paths(executable: "/Sill.app/Contents/MacOS/Sill").bundle, "/Sill.app", "a bundle at the root")
same(R.paths(executable: "/Applications/Outer.app/Contents/Helpers/Sill.app/Contents/MacOS/Sill").bundle,
     "/Applications/Outer.app/Contents/Helpers/Sill.app", "the innermost bundle")
same(R.paths(executable: bare.executable), bare, "the bare SillMenuBar binary has no bundle")
same(R.paths(executable: "/usr/local/bin/SillHost").bundle, nil, "the CLI has none")
same(R.paths(executable: "/usr/local/Contents/MacOS/tool").bundle, nil, "Contents/MacOS outside a .app")
same(R.paths(executable: "/x/.app/Contents/MacOS/Sill").bundle, nil, "a folder named .app alone")
same(R.paths(executable: "/x/Sill.app/Contents/MacOS/").bundle, nil, "no executable's name")
same(R.paths(executable: "/x/Sill.app/Contents/Resources/Sill").bundle, nil, "a file in Resources")
same(R.paths(executable: "/x/Sill.application/Contents/MacOS/Sill").bundle, nil, "not .app")
same(R.paths(executable: "/x/Sill.app/contents/macos/Sill").bundle, nil, "the bundle's folders as macOS names them")
same(R.paths(executable: "Sill.app/Contents/MacOS/Sill").bundle, nil, "too short to be a path to a bundle")
same(R.paths(executable: "").bundle, nil, "no path")

// MARK: --getglobalstate

same(R.state("Firewall is enabled. (State = 1)\n"), .on, "macOS 27: on")
same(R.state("Firewall is disabled. (State = 0)\n"), .off, "macOS 27: off")
same(R.state("Firewall is blocking all non-essential incoming connections. (State = 2)\n"), .blockAll, "macOS 27: block all")
same(R.state("Firewall is enabled. (State = 1) \n"), .on, "legacy: on, a space for the full stop")
same(R.state("Firewall is disabled. (State = 0)\n"), .off, "legacy: off")
same(R.state("Firewall is set to block all non-essential incoming connections \n"), .blockAll, "legacy: block all, no number")
same(R.state("Firewall is in bootstrap mode. (State = 3)\n"), .unknown, "bootstrap mode tells nothing")
same(R.state("Firewall is in undefined state. (State = 4)\n"), .unknown, "an undefined state tells nothing")
same(R.state("Firewall is enabled. (State = 12)"), .unknown, "a number this build does not know")
same(R.state("Firewall is disabled. (State = 1)"), .on, "the number decides")
same(R.state("Firewall is enabled. (State = 0)"), .off, "the number decides, off")
same(R.state("Firewall is enabled."), .on, "no number: the words")
same(R.state("Firewall is disabled."), .off, "no number: the words, off")
same(R.state("Firewall is enabled. (State = 1"), .on, "an unclosed number falls back to the words")
same(R.state("(State = 1"), .unknown, "an unclosed number and no words")
same(R.state("(State = )"), .unknown, "no digits")
same(R.state(""), .unknown, "nothing")
same(R.state("zsh: command not found: socketfilterfw"), .unknown, "not the tool's answer")

// MARK: --getblockall

same(R.blockAll("Firewall is blocking all non-essential incoming connections.\n"), true, "macOS 27: block all on")
same(R.blockAll("Firewall has block all state set to disabled.\n"), false, "macOS 27: block all off")
same(R.blockAll("Firewall is set to block all non-essential incoming connections \n"), true, "legacy: on")
same(R.blockAll("Block all DISABLED! \n"), false, "legacy: off")
same(R.blockAll("Firewall has unknown block all state.\n"), nil, "unknown")
same(R.blockAll("Firewall is in undefined block all state.\n"), nil, "undefined")
same(R.blockAll(""), nil, "nothing")

// MARK: --getappblocked

same(R.appAnswer("Incoming connection to \(exe) is blocked.\n", path: exe), .blocked, "macOS 27: blocked")
same(R.appAnswer("Incoming connection to \(exe) is permitted.\n", path: exe), .permitted, "macOS 27: permitted")
same(R.appAnswer("Incoming connection to \(app) is permitted.\n", path: app), .permitted, "the report's bundle: permitted")
same(R.appAnswer("Incoming connection to \(exe) is blocked \n", path: exe), .blocked, "legacy: blocked")
same(R.appAnswer("Incoming connection to \(exe) is permitted \n", path: exe), .permitted, "legacy: permitted")
same(R.appAnswer("Incoming connection to the application is blocked \n", path: exe), .blocked, "legacy, no path: blocked")
same(R.appAnswer("Incoming connection to the application is permitted \n", path: exe), .permitted, "legacy, no path: permitted")
same(R.appAnswer("The application is not part of the firewall \n", path: exe), .unknown, "legacy: no rule of its own (the list decides)")
same(R.appAnswer("Incoming connection to \(exe) is blocked.\n", path: app), .unknown,
     "the bundle's question never takes the executable's answer (its path starts with the bundle's)")
same(R.appAnswer("Incoming connection to \(app) is blocked.\n", path: exe), .unknown, "another path's answer")
same(R.appAnswer("Incoming connection to /Users/x/This is blocked/Sill is permitted.\n", path: "/Users/x/This is blocked/Sill"),
     .permitted, "a path with \" is blocked\" in it")
same(R.appAnswer("Incoming connection to /x/Sill. is blocked.\n", path: "/x/Sill."), .blocked, "a path ending in a full stop")
same(R.appAnswer("objc[401]: a note\nIncoming connection to \(exe) is blocked.\n", path: exe), .blocked, "a line before the answer")
same(R.appAnswer("Incoming connection to \(exe) is maybe.\n", path: exe), .unknown, "an answer this build does not know")
same(R.appAnswer("The file path you specified does not exist \n", path: exe), .unknown, "no such file (legacy)")
same(R.appAnswer("", path: exe), .unknown, "nothing")

// MARK: --listapps

// macOS 27.0.1's form: a total with a space after it, then each rule's number, path and a space, over
// its state 13 spaces in. Its paths here are the report's two and a few of the system's.
let list27 = """
Total number of apps = 5
1 : /usr/libexec/rapportd
             (Allow incoming connections)
2 : \(app)
             (Allow incoming connections)
3 : /Applications/Google Chrome.app
             (Allow incoming connections)
4 : \(exe)
             (Block incoming connections)
5 : /usr/sbin/smbd
             (Allow incoming connections)

"""
same(R.listed(list27), [R.Listed(path: "/usr/libexec/rapportd", blocks: false), R.Listed(path: app, blocks: false),
                        R.Listed(path: "/Applications/Google Chrome.app", blocks: false), R.Listed(path: exe, blocks: true),
                        R.Listed(path: "/usr/sbin/smbd", blocks: false)], "macOS 27's list, the report's two rules")
// The legacy form's pieces (its strings are in the tool still): the state in parentheses with spaces
// inside; here also the log's "ALF: total…" wording, blank lines, two spaces after the colon and the
// state after spaces and a tab, none of which may throw the reading off.
let listOld = "ALF: total number of apps = 2 \n\n1 :  \(app) \n \t ( Allow incoming connections ) \n\n2 :  \(exe) \n \t ( Block incoming connections ) \n\n"
same(R.listed(listOld), [R.Listed(path: app, blocks: false), R.Listed(path: exe, blocks: true)], "the legacy form")
same(R.listed("Total number of apps = 0 \n"), [], "an empty list is a list")
same(R.listed(""), nil, "nothing is no list")
// The tool's usage, as macOS 27.0.1 prints it for an option it does not know (status 255): it names
// --listapps, so only a text with the total is a list (the review, 2026-10-29: a stand-in without
// "apps" let a reading that takes any mention of apps for a list pass).
let usage27 = "usage: /usr/libexec/ApplicationFirewall/socketfilterfw [-h] [--getglobalstate] [--setglobalstate on | off] [--getblockall] [--setblockall on | off] [--listapps] [--getappblocked <path>] [--blockapp <path>] [--unblockapp <path>] [--add <path>] [--remove <path>] [--getallowsigned] [--setallowsigned on | off] [--setallowsignedapp on | off] [--getstealthmode] [--setstealthmode on | off]\n"
same(R.listed(usage27), nil, "the usage is no list")
same(R.listed("usage: socketfilterfw [-h]\n"), nil, "a short usage is no list")
same(R.listed("Total number of apps = 2 \n1 : /a \n2 : /b \n             (Block incoming connections)\n"),
     [R.Listed(path: "/a", blocks: nil), R.Listed(path: "/b", blocks: true)], "a rule with no state line keeps none")
same(R.listed("Total number of apps = 1 \n             (Block incoming connections)\n1 : /a \n"),
     [R.Listed(path: "/a", blocks: nil)], "a state line before any rule belongs to none")
same(R.listed("Total number of apps = 1 \n1 : /a \n             (Allow incoming connections)\n             (Block incoming connections)\n"),
     [R.Listed(path: "/a", blocks: false)], "a rule takes the first state line under it")
same(R.listed("Total number of apps = 1 \n1 : /a \nnote: a line of something else\n             (Block incoming connections)\n"),
     [R.Listed(path: "/a", blocks: true)], "a line that names no rule, between a rule and its state")
same(R.listed("Total number of apps = 2 \n1 : /a \n             (Allow incoming connections)\n2 :  \n             (Block incoming connections)\n"),
     [R.Listed(path: "/a", blocks: false)], "a number that names nothing is no rule")
same(R.listed("Total number of apps = 1 \n4 : /Volumes/A : B/Sill.app \n             (Block incoming connections)\n"),
     [R.Listed(path: "/Volumes/A : B/Sill.app", blocks: true)], "a path with \" : \" in it")
same(R.listed("Total number of apps = 1 \n1 : com.example.tool \n             (Block incoming connections)\n"),
     [R.Listed(path: "com.example.tool", blocks: true)], "a rule that names no path is still a rule")
same(R.listed("Total number of apps = 1 \n   12 : /a   \n             (Maybe incoming connections)\n"),
     [R.Listed(path: "/a", blocks: nil)], "an unknown state line sets nothing")

// MARK: Answers and the verdict

/// The raw answers as macOS 27 prints them; `nil` leaves a question unanswered.
func raw(state: String? = "Firewall is enabled. (State = 1)\n", all: String? = "Firewall has block all state set to disabled.\n",
         exe exeAnswer: String? = "permitted", app appAnswer: String? = "permitted", list: [(String, Bool)]? = [],
         problem: String? = nil) -> R.Raw {
    var text: String?
    if let list {
        text = "Total number of apps = \(list.count) \n" + list.enumerated().map { i, r in
            "\(i + 1) : \(r.0) \n             (\(r.1 ? "Block" : "Allow") incoming connections)\n"
        }.joined()
    }
    return R.Raw(globalState: state, blockAll: all,
                 executable: exeAnswer.map { "Incoming connection to \(exe) is \($0).\n" },
                 bundle: appAnswer.map { "Incoming connection to \(app) is \($0).\n" },
                 listApps: text, problem: problem)
}

extension R.Raw {
    /// The same answers, both `--getappblocked` answers replaced by `text`.
    func withAnswers(_ text: String) -> R.Raw { var r = self; r.executable = text; r.bundle = text; return r }
}

// The report's Mac exactly: the bundle allowed, its executable blocked, the bundle's answer "permitted".
same(R.verdict(raw(exe: "blocked", app: "permitted", list: [(app, false), (exe, true)]), paths: bundled),
     .blocks(executable: exe, bundle: nil), "the report's Mac")
same(R.verdict(raw(exe: "permitted", app: "permitted", list: [(app, false), (exe, true)]), paths: bundled),
     .blocks(executable: exe, bundle: nil), "the executable's rule in the list alone is enough")
same(R.verdict(raw(exe: "blocked", list: nil), paths: bundled), .blocks(executable: exe, bundle: nil),
     "its answer alone is enough (no list)")
same(R.verdict(raw(app: "blocked", list: [(app, true)]), paths: bundled), .blocks(executable: nil, bundle: app), "the bundle blocked")
same(R.verdict(raw(app: "permitted", list: [(app, true)]), paths: bundled), .blocks(executable: nil, bundle: app),
     "the bundle's rule in the list alone")
same(R.verdict(raw(app: "blocked", list: nil), paths: bundled), .blocks(executable: nil, bundle: app), "the bundle's answer alone")
same(R.verdict(raw(exe: "blocked", app: "blocked", list: [(app, true), (exe, true)]), paths: bundled),
     .blocks(executable: exe, bundle: app), "both blocked")
same(R.verdict(raw(list: [(app, false), ("/usr/sbin/smbd", true)]), paths: bundled), .allows, "another app blocked is no matter")
same(R.verdict(raw(list: [(app, false), (exe + "2", true)]), paths: bundled), .allows, "a path that only starts with the executable's")
same(R.verdict(raw(list: [(exe + "/", true), (exe.uppercased(), true)]), paths: bundled), .allows,
     "a rule names exactly the path (as the kernel and the firewall have it)")
same(R.verdict(raw(list: [(exe, false), (exe, true)]), paths: bundled), .blocks(executable: exe, bundle: nil),
     "two rules for one path: the one that blocks counts")
same(R.verdict(raw(), paths: bundled), .allows, "on, nothing blocked")
same(R.verdict(raw(exe: nil, app: nil, list: [(app, false)]), paths: bundled), .allows, "the list alone read")
// A path's own "permitted" never stands in for the list (the review, 2026-10-29): the list is what showed
// the report's rule, and on the report's Mac a "permitted" (the bundle's) was what misled.
same(R.verdict(raw(exe: "permitted", app: nil, list: nil), paths: bundled), .unknown("its rules didn’t read"),
     "the executable's own \"permitted\" without the list: not allowed")
same(R.verdict(raw(exe: "permitted", app: "permitted", list: nil, problem: "socketfilterfw --listapps ended with status 9"),
               paths: bundled), .unknown("socketfilterfw --listapps ended with status 9"),
     "the report's Mac with its list unread (the tool killed): unknown, and why, never allowed")
same(R.verdict(raw(exe: "blocked", app: "permitted", list: nil, problem: "socketfilterfw --listapps didn’t answer in 2 s"),
               paths: bundled), .blocks(executable: exe, bundle: nil), "its list unread, its own answer blocked: blocked")
// No rule at all: the list read and empty, and no answer of its own (macOS 27 says "permitted"; the legacy
// form "not part of the firewall"): allowed.
same(R.verdict(raw(exe: nil, app: nil, list: []), paths: bundled), .allows, "an empty list read, no answers: allowed")
same(R.verdict(raw(list: []).withAnswers("The application is not part of the firewall \n"), paths: bundled), .allows,
     "legacy, no rule at all: allowed")
same(R.verdict(raw(list: [(app, false), (exe, true)]).withAnswers("The application is not part of the firewall \n"),
               paths: bundled), .blocks(executable: exe, bundle: nil), "legacy: no answer of its own, the list decides (blocked)")
same(R.verdict(raw(list: [(app, false)]).withAnswers("The application is not part of the firewall \n"), paths: bundled), .allows,
     "legacy: no answer of its own, the list decides (allowed)")
same(R.verdict(raw(exe: nil, app: "permitted", list: nil), paths: bundled), .unknown("its rules didn’t read"),
     "the bundle's answer alone says nothing of the executable")
same(R.verdict(raw(exe: nil, app: nil, list: nil, problem: "socketfilterfw --listapps didn’t answer in 2 s"), paths: bundled),
     .unknown("socketfilterfw --listapps didn’t answer in 2 s"), "nothing read: why")
same(R.verdict(raw(state: "Firewall is disabled. (State = 0)\n", exe: "blocked", app: "blocked", list: [(exe, true)]), paths: bundled),
     .off, "off: no rule matters")
same(R.verdict(raw(state: "Firewall is disabled. (State = 0)\n", all: nil, exe: nil, app: nil, list: nil), paths: bundled), .off,
     "off, asked nothing else (FirewallCheck stops there)")
same(R.verdict(raw(state: "Firewall is blocking all non-essential incoming connections. (State = 2)\n"), paths: bundled),
     .blocksAll, "block all, from the state")
same(R.verdict(raw(all: "Firewall is blocking all non-essential incoming connections.\n"), paths: bundled), .blocksAll,
     "block all, from --getblockall")
same(R.verdict(raw(all: "Firewall is blocking all non-essential incoming connections.\n", exe: "blocked"), paths: bundled), .blocksAll,
     "block all whatever the rules say")
same(R.verdict(raw(all: nil), paths: bundled), .allows, "no answer to --getblockall: the state's word stands")
same(R.verdict(raw(state: nil, exe: "blocked", list: [(exe, true)], problem: "socketfilterfw --getglobalstate ended with status 1"),
               paths: bundled), .unknown("socketfilterfw --getglobalstate ended with status 1"), "no state: nothing can be told")
same(R.verdict(raw(state: "Firewall is in bootstrap mode. (State = 3)\n", exe: "blocked"), paths: bundled),
     .unknown("its state didn’t read"), "a state this build does not know")
same(R.verdict(raw(exe: nil, app: "blocked", list: [(app, true), (bare.executable, false)]), paths: bare), .allows,
     "no bundle: a rule for one never counts")
same(R.verdict(raw(exe: nil, app: nil, list: [(bare.executable, true)]), paths: bare), .blocks(executable: bare.executable, bundle: nil),
     "the bare binary's own rule")
same(R.verdict(raw(list: [(exe, false)]), paths: bundled), .allows, "an allowed rule")
same(R.verdict(R.Raw(globalState: "Firewall is enabled. (State = 1)\n", executable: "Incoming connection to \(exe) is permitted.\n",
                     listApps: "Total number of apps = 1 \n1 : \(exe) \n"), paths: bundled), .allows,
     "a rule for the executable with no state line blocks nothing")
same(R.answers(raw(exe: "blocked", app: "blocked", list: [(app, true)]), paths: bare).bundle, .unknown,
     "no bundle: its answer is not read")
same(R.answers(R.Raw(), paths: bundled), R.Answers(state: .unknown), "nothing answered")
same(R.answers(raw(list: [(exe, true)]), paths: bundled).listed, [R.Listed(path: exe, blocks: true)], "the list is read")

// What FirewallCheck asks after the state: only while the firewall is on. Off, Block all and a state that
// doesn't read decide the verdict alone, whatever the rest would have said (the second review, 2026-10-29:
// a tool that never answered was asked all five questions, 10 s a check, and one that ignored SIGTERM left
// five processes running).
check(R.asksRules(afterState: "Firewall is enabled. (State = 1)\n"), "on: the rules are asked")
check(R.asksRules(afterState: "Firewall is enabled. (State = 1) \n"), "on, the legacy form: the rules are asked")
for text: String? in [nil, "", "Firewall is disabled. (State = 0)\n", "Firewall is blocking all non-essential incoming connections. (State = 2)\n",
                      "Firewall is set to block all non-essential incoming connections \n", "Firewall is in bootstrap mode. (State = 3)\n",
                      "Firewall is enabled. (State = 12)", "zsh: command not found: socketfilterfw"] {
    check(!R.asksRules(afterState: text), "\(text.debugDescription): nothing more is asked")
    for rest in [raw(exe: "blocked", app: "blocked", list: [(app, true), (exe, true)]),
                 raw(all: "Firewall is blocking all non-essential incoming connections.\n"), raw(), raw(list: nil),
                 raw(exe: nil, app: nil, list: nil, problem: "socketfilterfw --getglobalstate didn’t answer in 2 s")] {
        var full = rest
        full.globalState = text
        same(R.verdict(R.Raw(globalState: text, problem: full.problem), paths: bundled), R.verdict(full, paths: bundled),
             "\(text.debugDescription): the verdict without the rest is the verdict with it")
    }
}

for v: R.Verdict in [.blocks(executable: exe, bundle: nil), .blocks(executable: nil, bundle: app), .blocksAll] {
    check(v.blocksDevices, "\(v) keeps devices out")
    // A device that got in from the network says the verdict is stale: asked again. Over loopback,
    // which the firewall never filters, it says nothing.
    check(R.asksAgain(after: v, fromLoopback: false), "a device in from the network while \(v): asked again")
    check(!R.asksAgain(after: v, fromLoopback: true), "a device over loopback while \(v): not asked")
}
for v: R.Verdict in [.off, .allows, .unknown("x")] {
    check(!v.blocksDevices, "\(v) does not")
    check(!R.asksAgain(after: v, fromLoopback: false), "a device in while \(v): nothing to ask")
}
check(!R.asksAgain(after: nil, fromLoopback: false), "a device in before the first answer: the first check is under way")

// MARK: Words

let onlyExe = R.Verdict.blocks(executable: exe, bundle: nil)
let onlyApp = R.Verdict.blocks(executable: nil, bundle: app)
let both = R.Verdict.blocks(executable: exe, bundle: app)
same(R.Copy.tool, tool, "the tool")
same(R.Copy.command(onlyExe), "sudo \(tool) --unblockapp \(exe)", "the report's fix, word for word")
same(R.Copy.command(onlyApp), "sudo \(tool) --unblockapp \(app)", "the bundle's")
same(R.Copy.command(both), "sudo \(tool) --unblockapp \(exe) --unblockapp \(app)", "both, the executable's first")
same(R.Copy.command(.blocks(executable: "/Applications/Sill Beta.app/Contents/MacOS/Sill", bundle: nil)),
     "sudo \(tool) --unblockapp '/Applications/Sill Beta.app/Contents/MacOS/Sill'", "a path with a space, quoted")
for v: R.Verdict in [.blocksAll, .allows, .off, .unknown("x"), .blocks(executable: nil, bundle: nil)] {
    same(R.Copy.command(v), nil, "no command for \(v)")
}
same(R.Copy.paneLine(onlyExe).map { $0 + " " + R.Copy.command(onlyExe)! },
     "The macOS firewall blocks Sill’s executable, so devices on the network cannot connect. In Terminal: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /Applications/Sill.app/Contents/MacOS/Sill",
     "the pane's line and its command, as the task words it")
same(R.Copy.paneLine(onlyApp), "The macOS firewall blocks Sill.app, so devices on the network cannot connect. In Terminal:", "the bundle's line")
same(R.Copy.paneLine(.blocks(executable: nil, bundle: "/Users/me/Sill 2.app")),
     "The macOS firewall blocks Sill 2.app, so devices on the network cannot connect. In Terminal:", "a copy by its own name")
same(R.Copy.paneLine(both), "The macOS firewall blocks Sill.app and its executable, so devices on the network cannot connect. In Terminal:",
     "both")
// The command as Settings › General shows it: the tool, then each option on a line of its own after
// the shell's continuation, never "--" over "unblockapp".
same(R.Copy.commandLines(onlyExe), ["sudo \(tool) \\", "  --unblockapp \(exe)"], "the report's command, a line per option")
same(R.Copy.commandLines(both), ["sudo \(tool) \\", "  --unblockapp \(exe) \\", "  --unblockapp \(app)"], "both, the executable's first")
same(R.Copy.commandLines(.blocks(executable: "/Applications/Sill Beta.app/Contents/MacOS/Sill", bundle: nil))?.last,
     "  --unblockapp '/Applications/Sill Beta.app/Contents/MacOS/Sill'", "a path with a space, quoted on its line")
for v: R.Verdict in [.blocksAll, .allows, .off, .unknown("x"), .blocks(executable: nil, bundle: nil)] {
    same(R.Copy.commandLines(v), nil, "no lines for \(v)")
}
same(R.Copy.paneLine(.blocksAll),
     "The macOS firewall blocks all incoming connections, so devices on the network cannot connect. Turn off Block all incoming connections in System Settings › Network › Firewall › Options.",
     "block all")
for v: R.Verdict in [.allows, .off, .unknown("x")] {
    same(R.Copy.paneLine(v), nil, "no line for \(v)")
    same(R.Copy.menuSubtitle(v), nil, "no menu item for \(v)")
}
same(R.Copy.menuSubtitle(onlyExe), "The macOS firewall blocks Sill’s executable.", "the menu's subtitle")
same(R.Copy.menuSubtitle(onlyApp), "The macOS firewall blocks Sill.app.", "the menu's, the bundle")
same(R.Copy.menuSubtitle(both), "The macOS firewall blocks Sill.app and its executable.", "the menu's, both")
same(R.Copy.menuSubtitle(.blocksAll), "The macOS firewall blocks all incoming connections.", "the menu's, block all")
for v: R.Verdict in [onlyExe, onlyApp, both, .blocksAll] {
    let words = [R.Copy.paneLine(v), R.Copy.menuSubtitle(v), R.Copy.command(v), R.Copy.logLine(from: nil, to: v)].compactMap { $0 }
    check(!words.joined().contains("'s"), "a typographic apostrophe in \(v)'s words")
    // Only ever the way out: nothing that adds, removes or blocks, nothing about the firewall's own state.
    for word in ["--add", "--remove", "--blockapp", "--setglobalstate", "--setblockall", "--setallowsigned", "--setstealthmode"] {
        check(!(R.Copy.command(v) ?? "").contains(word), "\(v)'s command never says \(word)")
    }
    check(R.Copy.menuSubtitle(v).map { $0.count <= 60 } ?? false, "\(v)'s menu subtitle fits one line")
}

// The log's lines: one when the verdict changes, none for a first one that blocks nothing.
let blockedLine = "Firewall: the macOS firewall blocks Sill’s executable, so devices on the network cannot connect. In Terminal: sudo \(tool) --unblockapp \(exe)"
let noLonger = "Firewall: the macOS firewall no longer blocks devices from connecting to Sill."
same(R.Copy.logLine(from: nil, to: .allows), nil, "first: allowed, nothing printed")
same(R.Copy.logLine(from: nil, to: .off), nil, "first: off, nothing printed")
same(R.Copy.logLine(from: nil, to: onlyExe), blockedLine, "first: blocked")
same(R.Copy.logLine(from: .allows, to: onlyExe), blockedLine, "blocked from allowed")
same(R.Copy.logLine(from: onlyExe, to: onlyExe), nil, "the same again, nothing")
same(R.Copy.logLine(from: onlyExe, to: both), "Firewall: the macOS firewall blocks Sill.app and its executable, so devices on the network cannot connect. In Terminal: sudo \(tool) --unblockapp \(exe) --unblockapp \(app)",
     "more blocked: the new line")
same(R.Copy.logLine(from: onlyExe, to: .allows), noLonger, "unblocked")
same(R.Copy.logLine(from: .blocksAll, to: .off), noLonger, "block all, then off")
same(R.Copy.logLine(from: .allows, to: .off), nil, "allowed, then off")
same(R.Copy.logLine(from: .off, to: .allows), nil, "off, then on and allowed")
same(R.Copy.logLine(from: .allows, to: .blocksAll),
     "Firewall: the macOS firewall blocks all incoming connections, so devices on the network cannot connect. Turn off Block all incoming connections in System Settings › Network › Firewall › Options.",
     "block all")
same(R.Copy.logLine(from: nil, to: .unknown("socketfilterfw --getglobalstate didn’t answer in 2 s")),
     "Firewall: couldn’t read the macOS firewall’s settings (socketfilterfw --getglobalstate didn’t answer in 2 s), so Sill can’t tell whether it blocks devices.",
     "unreadable")
same(R.Copy.logLine(from: .unknown("x"), to: .unknown("x")), nil, "unreadable again, nothing")
same(R.Copy.logLine(from: .unknown("x"), to: .allows), nil, "readable again and allowed, nothing")
same(R.Copy.logLine(from: onlyExe, to: .unknown("x")),
     "Firewall: couldn’t read the macOS firewall’s settings (x), so Sill can’t tell whether it blocks devices.", "blocked, then unreadable")
same(R.Copy.logLine(from: .unknown("x"), to: onlyExe), blockedLine, "unreadable, then blocked")

// MARK: Shell quoting

same(R.Copy.shellQuoted(exe), exe, "a plain path stays as it is")
same(R.Copy.shellQuoted("/a b/c"), "'/a b/c'", "a space")
same(R.Copy.shellQuoted("/it's/x"), "'/it'\\''s/x'", "a quote inside")
same(R.Copy.shellQuoted(""), "''", "nothing")
for path in ["/x/$HOME/y", "/x/`id`", "/x/a;b", "~/x", "/x/=y", "/x/Sillé", "/x/a*b", "/x/a\"b", "/x/a\\b", "/x/(a)", "/x/a&b|c", "/x/a!b",
             "/x/tab\there", "/x/new\nline", "/x/'''", "/x/{a,b}", "/x/a#b"] {
    let quoted = R.Copy.shellQuoted(path)
    check(quoted.hasPrefix("'") && quoted.hasSuffix("'"), "\(path) is quoted: \(quoted)")
}
// Each shell hands the path back as it was (printf %s of the quoted word), in bash and zsh.
func echoed(_ shell: String, _ word: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: shell)
    p.arguments = ["-c", "printf %s " + word]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}
for shell in ["/bin/bash", "/bin/zsh"] where FileManager.default.isExecutableFile(atPath: shell) {
    for path in [exe, "/Applications/Sill Beta.app/Contents/MacOS/Sill", "/it's/x", "/x/$HOME/y", "/x/`id`", "/x/a;b", "~/x",
                 "/x/=y", "/x/Sillé", "/x/a*b", "/x/a\"b", "/x/a\\b", "/x/(a)", "/x/a&b|c", "/x/a!b", "/x/'''", "/x/{a,b}", "/x/a#b",
                 "/x/a+b,c:d@e%f"] {
        same(echoed(shell, R.Copy.shellQuoted(path)), path, "\(shell) reads the quoted path back")
    }
}

// The lines, selected and pasted into a shell, are the one command: each shell reads the same words
// from them as from `command` (the first word made an argument of a function, so nothing runs).
func words(_ shell: String, _ command: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: shell)
    p.arguments = ["-c", "f() { printf '<%s>' \"$@\"; }; f " + command]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}
for shell in ["/bin/bash", "/bin/zsh"] where FileManager.default.isExecutableFile(atPath: shell) {
    for v: R.Verdict in [onlyExe, onlyApp, both, .blocks(executable: "/Applications/Sill Beta.app/Contents/MacOS/Sill", bundle: "/it's/x.app")] {
        guard let command = R.Copy.command(v), let lines = R.Copy.commandLines(v) else { check(false, "\(v) has a command"); continue }
        let one = words(shell, command)
        same(words(shell, lines.joined(separator: "\n")), one, "\(shell) reads \(v)'s lines as its command")
        check(one?.hasPrefix("<sudo><\(tool)><--unblockapp>") == true, "\(shell): \(v)'s command starts as it should: \(one ?? "nil")")
    }
}

// MARK: TEST ONLY: SILL_TEST_FIREWALL's answers

same(R.verdict(R.canned("executable", paths: bundled)!, paths: bundled), onlyExe, "executable: the report's Mac")
same(R.verdict(R.canned("executable", paths: bare)!, paths: bare), .blocks(executable: bare.executable, bundle: nil),
     "executable, the bare binary")
same(R.verdict(R.canned("bundle", paths: bundled)!, paths: bundled), onlyApp, "bundle")
same(R.verdict(R.canned("bundle", paths: bare)!, paths: bare), .allows, "bundle, the bare binary: it has none to block")
same(R.verdict(R.canned("both", paths: bundled)!, paths: bundled), both, "both")
same(R.verdict(R.canned("all", paths: bundled)!, paths: bundled), .blocksAll, "all")
same(R.verdict(R.canned("off", paths: bundled)!, paths: bundled), .off, "off")
same(R.verdict(R.canned("allowed", paths: bundled)!, paths: bundled), .allows, "allowed")
same(R.verdict(R.canned("unreadable", paths: bundled)!, paths: bundled), .unknown("SILL_TEST_FIREWALL=unreadable: nothing answered"),
     "unreadable")
same(R.canned("blocked", paths: bundled), nil, "an unknown word")
same(R.canned("", paths: bundled), nil, "no word")
for word in R.cannedWords { check(R.canned(word, paths: bundled) != nil, "\(word) has answers") }
// The report's answers as macOS 27 prints them, each read on its own as the real ones are.
let report = R.canned("executable", paths: bundled)!
same(report.globalState, "Firewall is enabled. (State = 1)", "the state, as measured")
same(report.blockAll, "Firewall has block all state set to disabled.", "block all off, as measured")
same(R.appAnswer(report.executable ?? "", path: exe), .blocked, "its executable's answer says blocked")
same(R.appAnswer(report.bundle ?? "", path: app), .permitted, "its bundle's answer says permitted, as on the report's Mac")
same(R.listed(report.listApps ?? ""), [R.Listed(path: app, blocks: false), R.Listed(path: exe, blocks: true)],
     "its list: the bundle allowed, the executable blocked")
same(R.listed(R.canned("allowed", paths: bundled)?.listApps ?? ""), [R.Listed(path: app, blocks: false)], "allowed's list")
same(R.listed(R.canned("bundle", paths: bundled)?.listApps ?? ""), [R.Listed(path: app, blocks: true)], "bundle's list")
same(R.appAnswer(R.canned("bundle", paths: bundled)?.executable ?? "", path: exe), .permitted, "bundle: the executable's answer")

// Who takes SILL_TEST_FIREWALL, and the line each host prints about it.
let ignoredLine = "SILL_TEST_FIREWALL ignored: only a test host takes it (one that does not advertise and is not Sill.app itself)."
for value in ["executable", "all", "/tmp/answer", "nonsense"] {
    let taken = R.testSource(value, testHost: false)
    same(taken.source, nil, "a host that is not a test host never takes \(value)")
    same(taken.line, ignoredLine, "…and says so once")
}
same(R.testSource(nil, testHost: true).source, nil, "not set: nothing")
same(R.testSource(nil, testHost: true).line, nil, "not set: no line")
same(R.testSource(nil, testHost: false).line, nil, "not set: no line on Sill.app either")
same(R.testSource("", testHost: true).line, nil, "empty: as not set")
same(R.testSource("executable", testHost: true).source, .word("executable"), "a known word")
same(R.testSource("executable", testHost: true).line,
     "Test firewall: the macOS firewall is never asked; its answers are canned (executable).", "its line")
same(R.testSource("/tmp/answer", testHost: true).source, .file("/tmp/answer"), "an absolute path: a file")
same(R.testSource("/tmp/answer", testHost: true).line,
     "Test firewall: the macOS firewall is never asked; its answers are canned (the word in /tmp/answer, read at each check).", "its line")
same(R.testSource("blocked", testHost: true).source, nil, "an unknown word is not taken")
same(R.testSource("blocked", testHost: true).line,
     "SILL_TEST_FIREWALL=blocked ignored: expected executable, bundle, both, all, off, allowed, unreadable, or a file holding one.", "…and says so")
same(R.testSource("tmp/answer", testHost: true).source, nil, "a relative path is no file")
for word in R.cannedWords { same(R.testSource(word, testHost: true).source, .word(word), "\(word) is taken") }
// Each check's answers: the word's, or the file's first word as it reads now.
same(R.testAnswers(.word("executable"), fileText: nil, paths: bundled), R.canned("executable", paths: bundled)!, "a word's answers")
same(R.testAnswers(.file("/f"), fileText: "allowed\n", paths: bundled), R.canned("allowed", paths: bundled)!, "the file's word")
same(R.testAnswers(.file("/f"), fileText: "  executable  # the report's Mac\n", paths: bundled), R.canned("executable", paths: bundled)!,
     "the file's first word, after spaces")
same(R.verdict(R.testAnswers(.file("/f"), fileText: nil, paths: bundled), paths: bundled),
     .unknown("SILL_TEST_FIREWALL: no known word in /f"), "a file that can't be read answers nothing")
same(R.verdict(R.testAnswers(.file("/f"), fileText: "maybe", paths: bundled), paths: bundled),
     .unknown("SILL_TEST_FIREWALL: no known word in /f"), "a file whose word is unknown answers nothing")
same(R.verdict(R.testAnswers(.file("/f"), fileText: "", paths: bundled), paths: bundled),
     .unknown("SILL_TEST_FIREWALL: no known word in /f"), "an empty file answers nothing")

print("firewall: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
