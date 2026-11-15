// The log file (Sources/SillHost/HostLog.swift) written by two Sills at once, as at an update's hand-over (the
// new copy starts while the old one still runs) and at a second launch that waits and leaves: every line of
// both whole, in the order written, at the file's end; a file one of them moved aside followed by the other;
// a deleted file written again at its path. The writers are this binary run again (`check writer LOG TAG`),
// each with its own HostLog, told when to write over its stdin, so the order is the same every run.
import Foundation

func say(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

/// A writer's line n: 65 characters, so 90 bytes in the file with the 24 of its time stamp and the newline.
func text(_ tag: String, _ n: Int) -> String { "\(tag) \(String(format: "%04d", n)) " + String(repeating: "x", count: 58) }

// MARK: A writer

if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "writer" {
    let tag = CommandLine.arguments[3]
    HostLog.shared.configure(keepLines: 0, fileURL: URL(fileURLWithPath: CommandLine.arguments[2]))
    HostLog.shared.flush()
    say("ready")
    var n = 0
    while let command = readLine() {
        let words = command.split(separator: " ")
        if words.count == 2, words[0] == "write", let count = Int(words[1]) {
            for _ in 0..<count { n += 1; HostLog.shared.append(text(tag, n)) }
            HostLog.shared.flush()
            say("done")
        } else { break }
    }
    exit(0)
}

// MARK: The check

var checks = 0
var failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !ok { failures += 1; say("FAIL \(what())") }
}

final class Writer {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()

    init(_ log: URL, _ tag: String) {
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["writer", log.path, tag]
        process.standardInput = input
        process.standardOutput = output
        do { try process.run() } catch { say("FAIL a writer did not start: \(error)"); exit(1) }
        expect("ready")
    }

    private func expect(_ word: String) {
        while true {
            if let end = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...end)
                if line != word { say("FAIL a writer said \"\(line)\", not \"\(word)\""); exit(1) }
                return
            }
            let more = output.fileHandleForReading.availableData
            if more.isEmpty { say("FAIL a writer ended before saying \"\(word)\""); exit(1) }
            buffer.append(more)
        }
    }

    func write(_ count: Int) {
        input.fileHandleForWriting.write(Data("write \(count)\n".utf8))
        expect("done")
    }

    func quit() {
        input.fileHandleForWriting.write(Data("quit\n".utf8))
        process.waitUntilExit()
    }
}

/// A file's lines (without the empty one after the last newline) and its length.
func read(_ url: URL) -> (lines: [String], bytes: Int)? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return (lines, data.count)
}

/// A writer's line as the file has it: "2026-11-14 23:16:33.565 A 0001 xxx…", whole, else nil.
func writerLine(_ line: String) -> String? {
    let c = Array(line.utf8)
    guard c.count == 89 else { return nil }
    let shape = Array("0000-00-00 00:00:00.000 ".utf8)
    for (i, s) in shape.enumerated() {
        let digit = c[i] >= 0x30 && c[i] <= 0x39
        if s == 0x30 ? !digit : c[i] != s { return nil }
    }
    let rest = String(decoding: c[24...], as: UTF8.self)
    guard rest.hasSuffix(" " + String(repeating: "x", count: 58)) else { return nil }
    let words = rest.split(separator: " ")
    guard words.count == 3, words[0].count == 1, words[1].count == 4, Int(words[1]) != nil else { return nil }
    return "\(words[0]) \(Int(words[1])!)"
}

func filler(_ n: Int) -> String { "2026-01-01 00:00:00.000 filler \(String(format: "%06d", n)) " + String(repeating: ".", count: 61) }   // 99 characters

func expected(_ tag: String, _ range: ClosedRange<Int>) -> [String] { range.map { "\(tag) \($0)" } }

let work = FileManager.default.temporaryDirectory.appendingPathComponent("sill-host-log-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: work)
defer { try? FileManager.default.removeItem(at: work) }

func folder(_ name: String, filler count: Int) -> (log: URL, aside: URL) {
    let dir = work.appendingPathComponent(name, isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let log = dir.appendingPathComponent("Sill.log")
    if count > 0 {
        var data = Data(capacity: count * 100)
        for n in 1...count { data.append(contentsOf: Array((filler(n) + "\n").utf8)) }
        try! data.write(to: log)
    }
    return (log, dir.appendingPathComponent("Sill.1.log"))
}

// 1. Two Sills, one file: each line whole, at the end, in the order written.
do {
    let (log, aside) = folder("two", filler: 3)
    let a = Writer(log, "A"), b = Writer(log, "B")
    a.write(20); b.write(20); a.write(20); b.write(20)
    a.quit(); b.quit()
    let file = read(log)
    check(file != nil, "two writers: the log is gone")
    let lines = file?.lines ?? []
    check(file?.bytes == 300 + 80 * 90, "two writers: the log is \(file?.bytes ?? -1) bytes, not \(300 + 80 * 90): lines were written over or lost")
    check(Array(lines.prefix(3)) == (1...3).map(filler), "two writers: what the file held before them changed")
    let want = expected("A", 1...20) + expected("B", 1...20) + expected("A", 21...40) + expected("B", 21...40)
    let got = lines.dropFirst(3).map { writerLine($0) ?? "torn: \($0.prefix(60))" }
    check(got == want, "two writers: the lines are not each whole and in the order written; the first that differs: \(zip(got, want).first { $0 != $1 }.map { "\($0.0), not \($0.1)" } ?? "\(got.count) lines, not \(want.count)")")
    check(!FileManager.default.fileExists(atPath: aside.path), "two writers: a short log was moved aside")
}

// 2. One of them moves the file aside at 10 MB: the other writes the new file from its next line on, and the
//    moved one is kept whole.
do {
    let (log, aside) = folder("moved", filler: 99_990)          // 9,999,000 bytes
    let a = Writer(log, "A"), b = Writer(log, "B")
    a.write(5); b.write(5)                                       // 9,999,900
    a.write(20)                                                  // A6 fits (9,999,990); A7 would pass 10,000,000
    b.write(5)                                                   // B's open file is Sill.1.log now
    a.write(3)
    a.quit(); b.quit()
    let old = read(aside), new = read(log)
    check(old != nil, "moved aside: no Sill.1.log")
    check(old?.bytes == 9_999_990, "moved aside: Sill.1.log is \(old?.bytes ?? -1) bytes, not 9,999,990 (moved at the first line that would pass 10 MB, by the file's real length)")
    check(old?.lines.first == filler(1) && old?.lines.count == 99_990 + 11, "moved aside: Sill.1.log is not the file from before, whole")
    let oldTail = (old?.lines.suffix(11) ?? []).map { writerLine($0) ?? "torn: \($0.prefix(60))" }
    check(oldTail == expected("A", 1...5) + expected("B", 1...5) + expected("A", 6...6), "moved aside: Sill.1.log ends \(oldTail)")
    let got = (new?.lines ?? []).map { writerLine($0) ?? "torn: \($0.prefix(60))" }
    let want = expected("A", 7...25) + expected("B", 6...10) + expected("A", 26...28)
    check(got == want, "moved aside: Sill.log holds \(got.count) lines, not the \(want.count) written since, in order; the first that differs: \(zip(got, want).first { $0 != $1 }.map { "\($0.0), not \($0.1)" } ?? "-")")
    check(new?.bytes == 27 * 90, "moved aside: Sill.log is \(new?.bytes ?? -1) bytes, not \(27 * 90)")
}

// 3. The file deleted under a running Sill: its next line makes the file at the path again.
do {
    let (log, _) = folder("deleted", filler: 0)
    let a = Writer(log, "A")
    a.write(3)
    check(read(log)?.lines.count == 3, "deleted: the first three lines are not in the file")
    try? FileManager.default.removeItem(at: log)
    a.write(3)
    a.quit()
    let got = (read(log)?.lines ?? []).map { writerLine($0) ?? "torn" }
    check(got == expected("A", 4...6), "deleted: the file at the path holds \(got), not the three lines written since")
}

// 4. A file already at 10 MB when Sill starts is moved aside before the first line.
do {
    let (log, aside) = folder("launch", filler: 100_000)        // 10,000,000 bytes
    let a = Writer(log, "A")
    check(read(aside)?.bytes == 10_000_000 && read(log)?.bytes == 0, "launch: a 10 MB file was not moved aside as Sill started")
    a.write(2)
    a.quit()
    check(read(aside)?.bytes == 10_000_000, "launch: Sill.1.log changed after the start")
    check((read(log)?.lines ?? []).map { writerLine($0) ?? "torn" } == expected("A", 1...2), "launch: the new Sill.log does not hold the two lines written")
}

say(failures == 0 ? "host-log: \(checks) checks passed" : "host-log: \(failures) of \(checks) checks FAILED")
try? FileManager.default.removeItem(at: work)
exit(failures == 0 ? 0 : 1)
