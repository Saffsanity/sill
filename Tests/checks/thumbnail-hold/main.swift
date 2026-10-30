// ThumbnailHold (iOSClient/ThumbnailHold.swift) on its own: how long a window's thumbnail is held before
// its lights show and it can be dragged (issue #113; Noah's decision of 2026-10-29: a stepper from 0.2 to
// 2 s in tenths of a second, 0.5 s unless changed, never sent to the Mac).
//   - The constants: the key, the range, the step, the standard half second (shorter than the 1.5 s of
//     before), the range in tenths and in seconds agreeing.
//   - The lengths: every tenth from 0.2 to 2 s as itself, exactly the decimal it reads as; halfway
//     values rounding up; under the range its floor, over it its ceiling (a huge value without
//     overflowing), nothing usable the standard; what the stepper's + and − give, a tenth at a time and
//     no further than the ends, 18 steps up from 0.2 s exactly 2 s with every value on the way exactly
//     its decimal.
//   - A stored value: a number (Double, Int, Bool), a string as a launch argument gives it, junk;
//     UserDefaults' registration (in memory only), and the launch argument itself in a child run of this
//     binary (`-Sill.thumbnailHold 0.3`, a string in the argument domain).
//   - The words: the row's title, the VoiceOver label and value ("Hold to show window controls, 0.5
//     seconds"), the value shown ("0.5 s", always a tenth's digit), the footnote, the console's line;
//     the title's three lines, the narrowest it may be beside the stepper (its words in order, whole,
//     and in the system font, CoreText's on this Mac, the split of its words into three lines whose
//     widest line is shortest: the review, 2026-10-29).
//   - A grid of every hundredth from -4 to 10 s against the invariants (in the range, on the grid,
//     within half a tenth of the clamped value, monotonic, idempotent, its words its length's).
//   swiftc -O iOSClient/ThumbnailHold.swift Tests/checks/thumbnail-hold/main.swift -o .build/checks/thumbnail-hold/check && .build/checks/thumbnail-hold/check
import Foundation
import CoreText

typealias H = ThumbnailHold

// A child run: what UserDefaults hands back for the key with the launch argument this run was given.
if CommandLine.arguments.dropFirst().first == "--child" {
    let stored = UserDefaults.standard.object(forKey: H.key)
    print("\(stored.map { String(describing: type(of: $0)) } ?? "nil")|\(stored.map { "\($0)" } ?? "nil")|\(H.seconds(stored: stored))")
    exit(0)
}

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }

// MARK: - The constants

check("the key is Sill.thumbnailHold", H.key == "Sill.thumbnailHold")
check("0.2 to 2 s", H.range.lowerBound == 0.2 && H.range.upperBound == 2.0)
check("in tenths, 2 to 30", H.tenthsRange.lowerBound == 2 && H.tenthsRange.upperBound == 20)
check("the two ranges agree", Double(H.tenthsRange.lowerBound) / 10 == H.range.lowerBound && Double(H.tenthsRange.upperBound) / 10 == H.range.upperBound)
check("a step is a tenth of a second", H.step == 0.1)
check("0.5 s unless changed", H.standard == 0.5)
check("the standard is on the grid and in the range", H.seconds(H.standard) == H.standard && H.range.contains(H.standard))
check("shorter than the 1.5 s of before", H.before == 1.5 && H.standard < H.before)

// MARK: - The lengths

for t in 2...20 {
    let s = Double(t) / 10
    let literal = Double("\(t / 10).\(t % 10)")!
    check("\(literal) s is itself, in tenths \(t)", H.tenths(s) == t && H.seconds(s) == literal && H.seconds(tenths: t) == literal && H.seconds(literal) == literal)
}
check("halfway values round up: 0.25 → 0.3, 0.75 → 0.8, 1.25 → 1.3, 1.75 → 1.8",
      H.seconds(0.25) == 0.3 && H.seconds(0.75) == 0.8 && H.seconds(1.25) == 1.3 && H.seconds(1.75) == 1.8)
check("just under halfway rounds down: 0.249 → 0.2, 1.2499 → 1.2", H.seconds(0.249) == 0.2 && H.seconds(1.2499) == 1.2)
check("between steps the nearest: 0.53 → 0.5, 0.57 → 0.6, 1.04 → 1.0, 1.96 → 2.0",
      H.seconds(0.53) == 0.5 && H.seconds(0.57) == 0.6 && H.seconds(1.04) == 1.0 && H.seconds(1.96) == 2.0)
check("under the range its floor: 0.19, 0.15, 0.1, 0.05, 0, -1, -1e300 → 0.2",
      [0.19, 0.15, 0.1, 0.05, 0, -1, -1e300].allSatisfy { H.seconds($0) == 0.2 && H.tenths($0) == 2 })
check("over the range its ceiling: 2.04, 2.05, 2.1, 5, 60, 1e300, Double.greatestFiniteMagnitude → 3",
      [2.04, 2.05, 2.1, 5, 60, 1e300, Double.greatestFiniteMagnitude].allSatisfy { H.seconds($0) == 2.0 && H.tenths($0) == 20 })
check("nothing usable is the standard: nan, +inf, -inf → 0.5",
      [Double.nan, .infinity, -.infinity].allSatisfy { H.seconds($0) == 0.5 && H.tenths($0) == 5 })
check("tenths kept in the range: 1, 0, -7, Int.min → 0.2; 21, 50, Int.max → 3",
      [1, 0, -7, Int.min].allSatisfy { H.seconds(tenths: $0) == 0.2 } && [21, 50, Int.max].allSatisfy { H.seconds(tenths: $0) == 2.0 })

// The stepper's + and −.
check("+ from 0.5 s is 0.6 s, − is 0.4 s", H.adjusted(0.5, up: true) == 0.6 && H.adjusted(0.5, up: false) == 0.4)
check("+ at 2 s stays 2 s, − at 0.2 s stays 0.2 s", H.adjusted(2.0, up: true) == 2.0 && H.adjusted(0.2, up: false) == 0.2)
check("− at 2 s is 1.9 s, + at 0.2 s is 0.3 s", H.adjusted(2.0, up: false) == 1.9 && H.adjusted(0.2, up: true) == 0.3)
check("a step from a value between steps starts from its nearest tenth: 0.53 + → 0.6, 0.57 − → 0.5",
      H.adjusted(0.53, up: true) == 0.6 && H.adjusted(0.57, up: false) == 0.5)
check("a step from outside the range starts from its end: 9 − → 2.9, 0 + → 0.3, nan + → 0.6",
      H.adjusted(9, up: false) == 1.9 && H.adjusted(0, up: true) == 0.3 && H.adjusted(.nan, up: true) == 0.6)
var walked = 0.2, onGrid = true, stepsUp = 0
while walked < 2.0 {
    let next = H.adjusted(walked, up: true)
    stepsUp += 1
    onGrid = onGrid && next == Double("\(H.tenths(next) / 10).\(H.tenths(next) % 10)")! && abs(next - walked - H.step) < 1e-9
    if next == walked || stepsUp > 100 { break }
    walked = next
}
check("18 steps up from 0.2 s reach exactly 2 s, every value on the way exactly its decimal, each a tenth more",
      walked == 2.0 && stepsUp == 18 && onGrid)
var down = 2.0, stepsDown = 0
while down > 0.2, stepsDown < 100 { down = H.adjusted(down, up: false); stepsDown += 1 }
check("18 steps down from 2 s reach exactly 0.2 s", down == 0.2 && stepsDown == 18)

// MARK: - A stored value

check("nothing stored is the standard", H.seconds(stored: nil) == 0.5)
check("a Double: 0.3 → 0.3, 1.24 → 1.2, 7.5 → 2", H.seconds(stored: 0.3) == 0.3 && H.seconds(stored: 1.24) == 1.2 && H.seconds(stored: 7.5) == 2.0)
check("an Int: 2 → 2, 0 → 0.2", H.seconds(stored: 2) == 2.0 && H.seconds(stored: 0) == 0.2)
check("an NSNumber: 0.7 → 0.7, nan → the standard", H.seconds(stored: NSNumber(value: 0.7)) == 0.7 && H.seconds(stored: NSNumber(value: Double.nan)) == 0.5)
check("a Bool (an NSNumber): true → 1, false → 0.2", H.seconds(stored: true) == 1.0 && H.seconds(stored: false) == 0.2)
check("a string as a launch argument gives it: \"0.3\" → 0.3, \"1.2\" → 1.2, \" 1.5 \\n\" → 1.5, \"5\" → 2, \"0\" → 0.2",
      H.seconds(stored: "0.3") == 0.3 && H.seconds(stored: "1.2") == 1.2 && H.seconds(stored: " 1.5 \n") == 1.5
      && H.seconds(stored: "5") == 2.0 && H.seconds(stored: "0") == 0.2)
check("a string that is no number is the standard: \"\", \"abc\", \"0.5s\", \"nan\"",
      ["", "abc", "0.5s", "nan"].allSatisfy { H.seconds(stored: $0) == 0.5 })
check("other types are the standard: Data, an array, a dictionary, a date",
      H.seconds(stored: Data([1, 2])) == 0.5 && H.seconds(stored: [1.0]) == 0.5 && H.seconds(stored: ["a": 1.0]) == 0.5 && H.seconds(stored: Date()) == 0.5)
// UserDefaults' registration domain is in memory only: nothing of this run is written to disk.
UserDefaults.standard.register(defaults: [H.key: 1.2])
check("a registered default reads back through UserDefaults: 1.2 → 1.2", H.seconds(stored: UserDefaults.standard.object(forKey: H.key)) == 1.2)
UserDefaults.standard.register(defaults: [H.key: "2.0"])
check("a registered string too: \"2.0\" → 2", H.seconds(stored: UserDefaults.standard.object(forKey: H.key)) == 2.0)

/// This binary again with `-Sill.thumbnailHold VALUE`, as the app is launched with it: what UserDefaults
/// hands back ("String|0.3|0.3"), or nil if the child did not run.
func child(_ value: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    p.arguments = ["--child", "-" + H.key, value]
    let pipe = Pipe()
    p.standardOutput = pipe
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
let child03 = child("0.3"), child7 = child("7"), childJunk = child("abc")
check("the launch argument -Sill.thumbnailHold 0.3: a string in the argument domain, read as 0.3 (\(child03 ?? "no child"))",
      child03.map { $0.hasSuffix("|0.3|0.3") && $0.contains("String") } ?? false)
check("-Sill.thumbnailHold 7: its ceiling, 2 (\(child7 ?? "no child"))", child7.map { $0.hasSuffix("|7|2.0") } ?? false)
check("-Sill.thumbnailHold abc: the standard (\(childJunk ?? "no child"))", childJunk.map { $0.hasSuffix("|abc|0.5") } ?? false)

// MARK: - The words

check("the row's title", H.title == "Hold to Show Window Controls")
check("its label for VoiceOver", H.spokenTitle == "Hold to show window controls")
check("VoiceOver reads the row as \"Hold to show window controls, 0.5 seconds\"", "\(H.spokenTitle), \(H.spokenValue(H.standard))" == "Hold to show window controls, 0.5 seconds")
check("the value shown: 0.5 s, 0.2 s, 1.0 s, 1.5 s, 2.0 s",
      H.valueText(0.5) == "0.5 s" && H.valueText(0.2) == "0.2 s" && H.valueText(1.0) == "1.0 s" && H.valueText(1.5) == "1.5 s" && H.valueText(2.0) == "2.0 s")
check("the value shown is the length's: 1.04 → 1.0 s, 1.25 → 1.3 s, 9 → 2.0 s, -1 → 0.2 s",
      H.valueText(1.04) == "1.0 s" && H.valueText(1.25) == "1.3 s" && H.valueText(9) == "2.0 s" && H.valueText(-1) == "0.2 s")
check("spoken: 0.5 seconds, 0.2 seconds, 1 second, 1.5 seconds, 2 seconds",
      H.spokenValue(0.5) == "0.5 seconds" && H.spokenValue(0.2) == "0.2 seconds" && H.spokenValue(1.0) == "1 second"
      && H.spokenValue(1.5) == "1.5 seconds" && H.spokenValue(2.0) == "2 seconds")
check("spoken is the length's: 0.95 → 1 second, 1.04 → 1 second, 1.96 → 2 seconds, nan → 0.5 seconds",
      H.spokenValue(0.95) == "1 second" && H.spokenValue(1.04) == "1 second" && H.spokenValue(1.96) == "2 seconds" && H.spokenValue(.nan) == "0.5 seconds")
check("the footnote", H.footnote == "How long to hold a window’s thumbnail before its close, minimize and full-screen controls appear, and before it can be dragged to another place.")
check("the console's line: thumbnails: hold 0.3 s", H.consoleLine(0.3) == "thumbnails: hold 0.3 s" && H.consoleLine(3) == "thumbnails: hold 2.0 s")
// The title's three lines (HostSettingsPanel's ThumbnailHoldRow keeps the title beside the stepper only
// while it has room for them; narrower, the row stacks rather than break a word or run to a fourth line).
check("the title's lines beside the stepper: three, its words in order, each whole",
      H.titleLines.count == 3 && H.titleLines.joined(separator: " ") == H.title
      && H.titleLines.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) && !$0.contains("  ") })
/// The widest of `lines` in the system font at `size` points (CoreText's UI font on this Mac: SF Pro, as
/// on iOS).
func widest(_ lines: [String], _ size: CGFloat) -> CGFloat {
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
    return lines.map { line -> CGFloat in
        let text = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil))
    }.max() ?? 0
}
let titleWords = H.title.split(separator: " ").map(String.init)
var splits: [[String]] = []
for a in 1..<titleWords.count {
    for b in (a + 1)..<titleWords.count {
        splits.append([titleWords[..<a], titleWords[a..<b], titleWords[b...]].map { $0.joined(separator: " ") })
    }
}
let narrowest = [CGFloat(17), 19, 21].allSatisfy { size in splits.allSatisfy { widest(H.titleLines, size) <= widest($0, size) + 0.01 } }
check("they are the narrowest of the title's \(splits.count) three-line splits at 17, 19 and 21 pt (\(String(format: "%.1f", widest(H.titleLines, 17))) pt at 17)",
      splits.count == 6 && narrowest)
var wordsOK = true
for t in 2...20 {
    let s = H.seconds(tenths: t)
    let shown = H.valueText(s), spoken = H.spokenValue(s)
    let shownOK = shown.count == 5 && shown.hasSuffix(" s") && shown.dropLast(2).split(separator: ".").count == 2
    let spokenOK = spoken.hasSuffix(t == 10 ? " second" : " seconds") && !spoken.contains(".0 ") && !spoken.hasSuffix(".0 seconds")
    let agree = Double(shown.dropLast(2)) == s && Double(spoken.split(separator: " ")[0]) == s
    if !(shownOK && spokenOK && agree) { wordsOK = false; print("     words of \(t) tenths: \(shown) / \(spoken)") }
}
check("every length's words: shown with one decimal, spoken without \"point zero\", both reading as the length", wordsOK)

// MARK: - A grid of every hundredth from -4 to 10 s

var inRange = true, gridded = true, near = true, monotonic = true, idempotent = true, words = true
var previous = -Double.infinity
for i in -400...1000 {
    let x = Double(i) / 100
    let s = H.seconds(x)
    let clamped = min(max(x, 0.2), 2.0)
    inRange = inRange && H.range.contains(s)
    gridded = gridded && s == Double(H.tenths(x)) / 10
    near = near && abs(s - clamped) <= 0.05 + 1e-9
    monotonic = monotonic && s >= previous
    idempotent = idempotent && H.seconds(s) == s && H.tenths(s) == H.tenths(x)
    words = words && H.valueText(x) == H.valueText(s) && H.spokenValue(x) == H.spokenValue(s)
    previous = s
}
check("the grid: every length in the range", inRange)
check("the grid: every length on the grid of tenths", gridded)
check("the grid: within half a tenth of the value kept in the range", near)
check("the grid: a longer value never gives a shorter hold", monotonic)
check("the grid: a length is its own length", idempotent)
check("the grid: a value's words are its length's", words)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
