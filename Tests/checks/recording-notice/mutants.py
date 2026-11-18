"""Mutants of RecordingNotice.swift (Sources/SillHost; #284): each changes it in one place, is compiled with the
check as one module (../module.py) and must make the check fail.
usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import module

R = "Sources/SillHost/RecordingNotice.swift"
M = [
    # The numbers.
    ("generation 2", R, "package static let generation = 1", "package static let generation = 2"),
    ("a line every 5 s", R, "package static let lineSpacing: TimeInterval = 10", "package static let lineSpacing: TimeInterval = 5"),
    ("a line every 20 s", R, "package static let lineSpacing: TimeInterval = 10", "package static let lineSpacing: TimeInterval = 20"),
    # A report.
    ("the spacing's edge held", R, "time - last < RecordingNotice.lineSpacing", "time - last <= RecordingNotice.lineSpacing"),
    ("no spacing", R, "            if let last = lastLineAt, time - last < RecordingNotice.lineSpacing { return nil }\n", ""),
    ("the line's time never kept", R, "            lastLineAt = time\n", ""),
    ("a change not counted", R, "                changes += 1\n", ""),
    ("a change not kept", R, "                recording = now\n                changes += 1", "                changes += 1"),
    ("a report without a change writes a line", R, "            guard changes > 0 else { return nil }\n", ""),
    ("a report's line says the opposite", R, "return line(recording ? .started : .stopped)", "return line(recording ? .stopped : .started)"),
    # The line.
    ("held counts the change the line says", R, "let held = changes - (says != said ? 1 : 0)", "let held = changes"),
    ("held one less always", R, "let held = changes - (says != said ? 1 : 0)", "let held = changes - 1"),
    ("a left line says it stopped", R, "let says = event != .stopped", "let says = event == .started"),
    ("what was said never kept", R, "            said = event == .started\n", ""),
    ("changes never reset", R, "            changes = 0\n", ""),
    ("a second close says it again", R, "            recording = event == .left ? false : recording\n", ""),
    # The close.
    ("no line as it leaves while recording", R, "            if recording { return line(.left) }\n", ""),
    ("leaving said as a start", R, "            if recording { return line(.left) }", "            if recording { return line(.started) }"),
    ("a held stop dropped at the close", R, "            return changes > 0 ? line(.stopped) : nil", "            return nil"),
    ("a stop at every close", R, "            return changes > 0 ? line(.stopped) : nil", "            return line(.stopped)"),
    # The words.
    ("started and stopped swapped", R, 'case .started: what = "started recording the stream."', 'case .started: what = "stopped recording the stream."'),
    ("left said as stopped", R, 'case .left: what = "left while recording the stream."', 'case .left: what = "stopped recording the stream."'),
    ("no singular", R, 'change\\(line.held == 1 ? "" : "s")', 'changes'),
    ("the count never said", R, "let more = line.held > 0 ?", "let more = line.held > 1_000_000 ?"),
    ("no feature first", R, 'return "Recording: \\(device) \\(what)\\(more)"', 'return "\\(device) \\(what)\\(more)"'),
    ("no device", R, 'return "Recording: \\(device) \\(what)\\(more)"', 'return "Recording: a device \\(what)\\(more)"'),
]
sys.exit(0 if module.mutate("recording-notice", M, sys.argv[1]) else 1)
