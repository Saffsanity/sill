// devicerig (TEST ONLY; Tests/devicerig/README.md): drives an app already installed on a physical
// iPad or iPhone, Sill by default, from a script of steps: XCUITest's own touches, keys and
// screenshots, for what cannot be done by hand headless (a finger's drag over the picture, a pinch,
// a hold of a given length on a thumbnail, taps, typed text, and photographs of the result).
//
// A UI testing bundle with no host app: XCUIApplication(bundleIdentifier:) drives the installed app,
// so the rig never builds or installs Sill. Tests/devicerig/run.sh passes the script and Sill's launch
// arguments through xcodebuild's TEST_RUNNER_ variables, which reach this process without the prefix:
//
//   RIG_SCRIPT        the steps, one per line or separated by ';' (README.md lists them)
//   RIG_LAUNCH_ARGS   the app's launch arguments for `launch`, split as a shell would ("-SillConnect H:P")
//   RIG_APP           the app's bundle identifier (me.saffer.sill)
//   RIG_TREE_LINES    how many lines of the accessibility tree `tree` prints (300; the whole tree is
//                     attached to the result either way)
//
// Every line it prints starts with "rig:", which run.sh picks out of xcodebuild's output. Coordinates
// are points in the app's first window, from its top-left corner.
import XCTest

final class DeviceRig: XCTestCase {
    @MainActor
    func testScript() throws {
        // A step XCTest could not do (no keyboard focus, no such element) is recorded and printed
        // (record(_:)), and the script goes on: the photographs after it still say what happened.
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        let script = env["RIG_SCRIPT"] ?? ""
        let steps = RigScript.steps(script)
        guard !steps.isEmpty else {
            XCTFail("RIG_SCRIPT is empty: run the rig through Tests/devicerig/run.sh, which passes it as TEST_RUNNER_RIG_SCRIPT")
            return
        }
        let bundle = (env["RIG_APP"] ?? "").isEmpty ? "me.saffer.sill" : env["RIG_APP"]!
        let rig = Rig(test: self, bundle: bundle,
                      arguments: RigScript.words(env["RIG_LAUNCH_ARGS"] ?? ""),
                      treeLines: Int(env["RIG_TREE_LINES"] ?? "") ?? 300)
        Rig.say("\(steps.count) step\(steps.count == 1 ? "" : "s") for \(bundle)")
        for (index, step) in steps.enumerated() {
            rig.run(step, number: index + 1)
        }
        Rig.say("done")
    }

    /// Every issue XCTest records, printed as it happens, so the log says which step it belonged to.
    override func record(_ issue: XCTIssue) {
        Rig.say("issue: \(issue.compactDescription)")
        super.record(issue)
    }
}

/// One step of a script: its verb and the rest of its line.
struct RigStep: Equatable {
    let verb: String
    let rest: String
}

/// The script's grammar, kept apart from XCUITest.
enum RigScript {
    /// Steps are separated by newlines or by ';'. A backslash keeps the next character as it is, so
    /// "type a\;b" types "a;b"; the escapes `type` reads (\n, \t, \s, \\) pass through to it untouched.
    /// A line that starts with '#' is a comment.
    static func steps(_ script: String) -> [RigStep] {
        var lines: [String] = []
        var current = ""
        var escaped = false
        for character in script {
            if escaped {
                // Only a separator loses its backslash here; anything else keeps it for `type`.
                if character != ";" { current.append("\\") }
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == ";" || character == "\n" {
                lines.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        lines.append(current)
        return lines.compactMap { line in
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let verb = trimmed.prefix { $0 != " " && $0 != "\t" }
            // The rest without the blanks around it (`type` spells a space at either end "\s").
            let rest = trimmed.dropFirst(verb.count).drop { $0 == " " || $0 == "\t" }
            return RigStep(verb: String(verb).lowercased(),
                           rest: String(rest.reversed().drop { $0 == " " || $0 == "\t" }.reversed()))
        }
    }

    /// Launch arguments split as a shell splits words: blanks between words, single or double quotes
    /// around a word with blanks in it, a backslash for one character.
    static func words(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped { current.append(character); escaped = false; inWord = true; continue }
            if let q = quote {
                if character == q { quote = nil } else { current.append(character) }
                continue
            }
            switch character {
            case "\\": escaped = true
            case "'", "\"": quote = character; inWord = true
            case " ", "\t", "\n":
                if inWord { words.append(current); current = ""; inWord = false }
            default: current.append(character); inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }

    /// `type`'s text with its escapes read: \n Return, \t Tab, \s a space, \\ a backslash.
    static func text(_ raw: String) -> String {
        var out = ""
        var escaped = false
        for character in raw {
            if escaped {
                switch character {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "s": out.append(" ")
                default: out.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        if escaped { out.append("\\") }
        return out
    }

    /// "X,Y" as a point.
    static func point(_ word: Substring) -> CGPoint? {
        let parts = word.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }
}

/// The steps, carried out with XCUITest against the app.
@MainActor
final class Rig {
    private unowned let test: XCTestCase
    private let bundle: String
    private let arguments: [String]
    private let treeLines: Int
    private let app: XCUIApplication
    private let started = Date()
    private var trees = 0

    init(test: XCTestCase, bundle: String, arguments: [String], treeLines: Int) {
        self.test = test
        self.bundle = bundle
        self.arguments = arguments
        self.treeLines = max(1, treeLines)
        app = XCUIApplication(bundleIdentifier: bundle)
    }

    /// One line of the rig's output, flushed at once so xcodebuild streams it.
    nonisolated static func say(_ line: String) {
        print("rig: \(line)")
        fflush(stdout)
    }

    private func say(_ line: String) {
        Self.say(String(format: "%7.2f ", Date().timeIntervalSince(started)) + line)
    }

    func run(_ step: RigStep, number: Int) {
        let words = step.rest.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let label = "\(number) \(step.verb)\(step.rest.isEmpty ? "" : " " + step.rest)"
        switch step.verb {
        case "launch":
            app.launchArguments = arguments
            app.launch()
            say("\(label): \(bundle) \(arguments.joined(separator: " ")), \(state), window \(describe(window.frame))")
        case "activate":
            app.activate()
            say("\(label): \(state), window \(describe(window.frame))")
        case "terminate":
            app.terminate()
            say("\(label): \(state)")
        case "wait":
            guard words.count == 1, let seconds = Double(words[0]), seconds >= 0 else { return bad(label, "wait S") }
            say(label)
            Thread.sleep(forTimeInterval: seconds)
        case "tap":
            guard words.count == 1, let p = RigScript.point(words[0]) else { return bad(label, "tap X,Y") }
            say(label)
            at(p).tap()
        case "hold":
            guard words.count == 2, let p = RigScript.point(words[0]), let seconds = Double(words[1]), seconds >= 0
            else { return bad(label, "hold X,Y S") }
            say(label)
            at(p).press(forDuration: seconds)
            say("\(number) hold: lifted")
        case "drag", "swipe":
            // drag: a finger pressed for S seconds, then moved to the second point at V (XCUITest's
            // default speed when left out) and held there H seconds before it lifts (none when left
            // out). swipe: the same motion with no press before it and no hold after it, at V (2000
            // when left out), so the finger is still moving when it lifts: a flick.
            let isDrag = step.verb == "drag"
            let needed = isDrag ? 3 : 2
            guard words.count >= needed, words.count <= needed + (isDrag ? 2 : 1),
                  let from = RigScript.point(words[0]), let to = RigScript.point(words[1]) else {
                return bad(label, isDrag ? "drag X1,Y1 X2,Y2 S [V [H]]" : "swipe X1,Y1 X2,Y2 [V]")
            }
            let press = isDrag ? Double(words[2]) : 0
            let velocity = words.count > needed ? Double(words[needed]) : (isDrag ? nil : 2000)
            let hold = isDrag && words.count > needed + 1 ? Double(words[needed + 1]) : 0
            guard let press, press >= 0, let hold, hold >= 0,
                  words.count <= needed || (velocity ?? 0) > 0 else {
                return bad(label, isDrag ? "drag X1,Y1 X2,Y2 S [V [H]]" : "swipe X1,Y1 X2,Y2 [V]")
            }
            say(label)
            at(from).press(forDuration: press, thenDragTo: at(to),
                           withVelocity: velocity.map { XCUIGestureVelocity(rawValue: CGFloat($0)) } ?? .default,
                           thenHoldForDuration: hold)
            say("\(number) \(step.verb): lifted")
        case "pinch":
            // XCUITest pinches at the middle of the window. The speed's sign follows the scale (in
            // under 1, out over 1), whichever sign it is given with.
            guard words.count == 2, let scale = Double(words[0]), scale > 0, let speed = Double(words[1]), speed != 0
            else { return bad(label, "pinch SCALE V") }
            say(label)
            window.pinch(withScale: CGFloat(scale), velocity: CGFloat(scale < 1 ? -abs(speed) : abs(speed)))
            say("\(number) pinch: lifted")
        case "type":
            let text = RigScript.text(step.rest)
            guard !text.isEmpty else { return bad(label, "type TEXT") }
            say("\(label): \(text.count) character\(text.count == 1 ? "" : "s")")
            app.typeText(text)
        case "key":
            guard (1...2).contains(words.count), let key = Self.key(String(words[0])) else {
                return bad(label, "key NAME [MODS] (MODS: cmd,shift,opt,ctrl,fn joined by +)")
            }
            var flags: XCUIElement.KeyModifierFlags = []
            if words.count == 2 {
                for part in words[1].lowercased().split(whereSeparator: { $0 == "+" || $0 == "," }) {
                    switch part {
                    case "cmd", "command": flags.insert(.command)
                    case "shift": flags.insert(.shift)
                    case "opt", "option", "alt": flags.insert(.option)
                    case "ctrl", "control": flags.insert(.control)
                    case "fn", "function": flags.insert(.function)
                    case "caps", "capslock": flags.insert(.capsLock)
                    default: return bad(label, "key NAME [MODS]: no modifier \(part)")
                    }
                }
            }
            say(label)
            app.typeKey(key, modifierFlags: flags)
        case "hover", "click", "rightclick":
            // The iPad's pointer (a trackpad's or a mouse's), not a finger.
            guard words.count == 1, let p = RigScript.point(words[0]) else { return bad(label, "\(step.verb) X,Y") }
            say(label)
            switch step.verb {
            case "hover": at(p).hover()
            case "click": at(p).click()
            default: at(p).rightClick()
            }
        case "wheel":
            // A scroll with the iPad's pointer over a point: a trackpad's or a mouse's, not a finger's.
            guard words.count == 2, let p = RigScript.point(words[0]), let d = RigScript.point(words[1])
            else { return bad(label, "wheel X,Y DX,DY") }
            say(label)
            at(p).scroll(byDeltaX: d.x, deltaY: d.y)
        case "orient":
            let orientations: [String: UIDeviceOrientation] = [
                "portrait": .portrait, "upsidedown": .portraitUpsideDown,
                "landscapeleft": .landscapeLeft, "landscaperight": .landscapeRight,
            ]
            guard words.count == 1, let orientation = orientations[words[0].lowercased()] else {
                return bad(label, "orient portrait|upsidedown|landscapeleft|landscaperight")
            }
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1)        // the turn's animation, so the frame is the new one
            say("\(label): window \(describe(window.frame))")
        case "shot":
            guard words.count == 1, !words[0].contains("/") else { return bad(label, "shot NAME") }
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = String(words[0])
            attachment.lifetime = .keepAlways
            test.add(attachment)
            let size = screenshot.image.size, scale = screenshot.image.scale
            say("\(label): \(Int(size.width * scale))x\(Int(size.height * scale)) px, attached as \(words[0])")
        case "find":
            guard !step.rest.isEmpty else { return bad(label, "find TEXT") }
            let exact = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR identifier == %@", step.rest, step.rest))
            let count = exact.count
            if count > 0 {
                let first = exact.element(boundBy: 0)
                say("\(label): yes, \(count) (the first a \(Self.name(first.elementType)) at \(describe(first.frame)))")
            } else {
                let near = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS[c] %@", step.rest)).count
                say("\(label): no\(near > 0 ? " (\(near) whose label contains it)" : "")")
            }
        case "waitfor":
            guard words.count >= 2, let seconds = Double(words.last!), seconds >= 0 else {
                return bad(label, "waitfor TEXT S")
            }
            let text = words.dropLast().joined(separator: " ")
            let element = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR identifier == %@", text, text)).firstMatch
            let found = element.waitForExistence(timeout: seconds)
            say("\(label): \(found ? "found" : "not found")")
        case "tree":
            trees += 1
            let tree = app.debugDescription
            let attachment = XCTAttachment(string: tree)
            attachment.name = "tree-\(trees)"
            attachment.lifetime = .keepAlways
            test.add(attachment)
            let lines = tree.split(separator: "\n", omittingEmptySubsequences: false)
            say("\(label): \(lines.count) lines, attached as tree-\(trees)")
            for line in lines.prefix(treeLines) {
                Self.say("  " + String(line.prefix(220)))
            }
            if lines.count > treeLines { Self.say("  … \(lines.count - treeLines) more lines in the attachment") }
        default:
            bad(label, "no such step")
        }
    }

    /// The app's first window, which coordinates are measured in.
    private var window: XCUIElement { app.windows.element(boundBy: 0) }

    /// A point in the app's first window, in points from its top-left corner.
    private func at(_ point: CGPoint) -> XCUICoordinate {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x, dy: point.y))
    }

    private var state: String {
        switch app.state {
        case .notRunning: return "not running"
        case .runningBackgroundSuspended: return "suspended"
        case .runningBackground: return "in the background"
        case .runningForeground: return "in front"
        default: return "state unknown"
        }
    }

    private func describe(_ frame: CGRect) -> String {
        guard !frame.isEmpty else { return "(none)" }
        return "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }

    private func bad(_ label: String, _ usage: String) {
        say("\(label): not run: \(usage)")
        XCTFail("step \(label): \(usage)")
    }

    /// A key by name, or a single character as itself.
    static func key(_ name: String) -> String? {
        let named: [String: XCUIKeyboardKey] = [
            "escape": .escape, "esc": .escape, "return": .return, "enter": .enter, "tab": .tab,
            "space": .space, "delete": .delete, "forwarddelete": .forwardDelete,
            "up": .upArrow, "down": .downArrow, "left": .leftArrow, "right": .rightArrow,
            "home": .home, "end": .end, "pageup": .pageUp, "pagedown": .pageDown,
            "f1": .F1, "f2": .F2, "f3": .F3, "f4": .F4, "f5": .F5, "f6": .F6, "f7": .F7, "f8": .F8,
            "f9": .F9, "f10": .F10, "f11": .F11, "f12": .F12,
            "command": .command, "shift": .shift, "option": .option, "control": .control,
            "capslock": .capsLock,
        ]
        if let key = named[name.lowercased()] { return key.rawValue }
        return name.count == 1 ? name : nil
    }

    /// An element type's name, for `find`.
    static func name(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .staticText: return "text"
        case .image: return "image"
        case .other: return "group"
        case .window: return "window"
        case .application: return "application"
        case .scrollView: return "scroll view"
        case .textField: return "text field"
        case .switch: return "switch"
        case .slider: return "slider"
        case .cell: return "cell"
        case .keyboard: return "keyboard"
        case .key: return "key"
        case .menu: return "menu"
        case .menuItem: return "menu item"
        default: return "element of type \(type.rawValue)"
        }
    }
}
