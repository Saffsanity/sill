// VersionLabel (iOSClient/VersionLabel.swift) on its own: the app's version and build as the connect
// screen's footer and the Settings panel's last line show them (Noah, 2026-11-11; docs/version-label-plan.md).
//   - The words: "Sill 0.6.2 (1400)" shown and copied, "Sill version 0.6.2, build 1400" spoken; Noah's
//     example and a build from Xcode (4); without a build, without a version, without either (no label).
//   - From a bundle's Info.plist: the two keys and no other, an Info.plist with neither, none at all.
//   - The odd inputs: a build that is not a number ("4a", "1.2.3", "abc"), white space around and inside
//     (tabs, newlines, no-break spaces), an empty or blank value, control and format characters (a NUL,
//     a bell, a zero-width space, a right-to-left override, a byte order mark), numbers where a string
//     belongs (an Int, a Double, an NSNumber), a Boolean, other types; a long value whole, the name not
//     taken out of a version that has it.
//   - Random values from a palette of those characters (seeded), against the invariants: one line of
//     plain words, idempotent, a label exactly when either value has words, its words in the order given.
//   swiftc -O iOSClient/VersionLabel.swift Tests/checks/version-label/main.swift -o .build/checks/version-label/check && .build/checks/version-label/check
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }

/// The label's two forms, or "none".
func shown(_ v: Any?, _ b: Any?) -> String { VersionLabel(version: v, build: b).map { "\($0.text) | \($0.spoken)" } ?? "none" }
func shown(info: [String: Any]?) -> String { VersionLabel(info: info).map { "\($0.text) | \($0.spoken)" } ?? "none" }

// MARK: - The words

check("0.6.2 (1400): \"Sill 0.6.2 (1400)\", spoken \"Sill version 0.6.2, build 1400\"",
      shown("0.6.2", "1400") == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
check("Noah's example, 0.6.1 (1304)", shown("0.6.1", "1304") == "Sill 0.6.1 (1304) | Sill version 0.6.1, build 1304")
check("a build from Xcode says the project's 4: \"Sill 0.6.1 (4)\"", shown("0.6.1", "4") == "Sill 0.6.1 (4) | Sill version 0.6.1, build 4")
check("the values kept as given: 0.5 (2), 1.0 (1), 10.10.10 (99999)",
      shown("0.5", "2") == "Sill 0.5 (2) | Sill version 0.5, build 2" && shown("1.0", "1") == "Sill 1.0 (1) | Sill version 1.0, build 1"
      && shown("10.10.10", "99999") == "Sill 10.10.10 (99999) | Sill version 10.10.10, build 99999")
check("without a build: \"Sill 0.6.2\", spoken \"Sill version 0.6.2\"", shown("0.6.2", nil) == "Sill 0.6.2 | Sill version 0.6.2")
check("without a version: \"Sill (1400)\", spoken \"Sill, build 1400\"", shown(nil, "1400") == "Sill (1400) | Sill, build 1400")
check("without either: no label", shown(nil, nil) == "none")
check("the same version and build both shown: \"Sill 4 (4)\"", shown("4", "4") == "Sill 4 (4) | Sill version 4, build 4")
check("the fields hold the cleaned values", VersionLabel(version: " 0.6.2 ", build: "1400\n")?.version == "0.6.2"
      && VersionLabel(version: " 0.6.2 ", build: "1400\n")?.build == "1400" && VersionLabel(version: nil, build: "7")?.version == nil)
check("equal labels from equal values, unequal from a different build",
      VersionLabel(version: "0.6.2", build: "1400") == VersionLabel(version: " 0.6.2", build: "1400 ")
      && VersionLabel(version: "0.6.2", build: "1400") != VersionLabel(version: "0.6.2", build: "1401"))
check("the words shown have no \"version\" or \"build\" in them, the words spoken no parentheses",
      VersionLabel(version: "0.6.2", build: "1400").map { !$0.text.contains("version") && !$0.text.contains("build") && !$0.spoken.contains("(") && !$0.spoken.contains(")") } == true)

// MARK: - From a bundle's Info.plist

check("the two keys of an Info.plist", shown(info: ["CFBundleShortVersionString": "0.6.2", "CFBundleVersion": "1400",
                                                    "CFBundleName": "Sill", "CFBundleIdentifier": "me.saffer.sill"])
      == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
check("CFBundleShortVersionString is the version, CFBundleVersion the build (not the other way round)",
      VersionLabel(info: ["CFBundleShortVersionString": "0.6.2", "CFBundleVersion": "1400"])?.version == "0.6.2"
      && VersionLabel(info: ["CFBundleShortVersionString": "0.6.2", "CFBundleVersion": "1400"])?.build == "1400")
check("an Info.plist without CFBundleVersion: the version alone", shown(info: ["CFBundleShortVersionString": "0.6.2"]) == "Sill 0.6.2 | Sill version 0.6.2")
check("an Info.plist without CFBundleShortVersionString: the build alone", shown(info: ["CFBundleVersion": "1400"]) == "Sill (1400) | Sill, build 1400")
check("no other key stands in: CFBundleName, CFBundleGetInfoString, DTPlatformVersion → no label",
      shown(info: ["CFBundleName": "Sill", "CFBundleGetInfoString": "0.6.2", "DTPlatformVersion": "27.1", "CFBundleDisplayName": "Sill"]) == "none")
check("an empty Info.plist, and none at all: no label", shown(info: [:]) == "none" && shown(info: nil) == "none")

// MARK: - The odd inputs

check("a build that is not a number, as it is: 4a, 1.2.3, abc, 0.6.2b1",
      shown("0.6.2", "4a") == "Sill 0.6.2 (4a) | Sill version 0.6.2, build 4a"
      && shown("0.6.2", "1.2.3") == "Sill 0.6.2 (1.2.3) | Sill version 0.6.2, build 1.2.3"
      && shown("0.6.2", "abc") == "Sill 0.6.2 (abc) | Sill version 0.6.2, build abc"
      && shown("0.6.2b1", "1400") == "Sill 0.6.2b1 (1400) | Sill version 0.6.2b1, build 1400")
check("white space around a value goes: \" 0.6.2 \\n\" and \"\\t1400\\r\\n\"", shown(" 0.6.2 \n", "\t1400\r\n") == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
check("white space inside a value is one space: \"0.6  \\t .2\" → \"0.6 .2\", \"14\\n00\" → \"14 00\"",
      shown("0.6  \t .2", "14\n00") == "Sill 0.6 .2 (14 00) | Sill version 0.6 .2, build 14 00")
check("a no-break space, a line separator and a next line are white space too",
      shown("\u{00A0}0.6.2\u{2028}", "1400\u{0085}\u{00A0}") == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
check("an empty or blank value is none: \"\", \" \", \"\\n\\t\"",
      shown("", "1400") == "Sill (1400) | Sill, build 1400" && shown("0.6.2", " ") == "Sill 0.6.2 | Sill version 0.6.2"
      && shown("\n\t", "") == "none")
check("control characters go: a NUL, a bell, an escape", shown("0.6.2\u{0}", "\u{7}14\u{1B}00") == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
check("format characters go: a zero-width space, a right-to-left override, a byte order mark, a soft hyphen",
      shown("\u{202E}0.6.2\u{202C}", "\u{FEFF}14\u{200B}00\u{00AD}") == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
check("a zero-width space is no space (Foundation's whitespacesAndNewlines counts it as one): 14\\u{200B}00 → 1400, 0.6\\u{200B} .2 → 0.6 .2",
      VersionLabel.clean("14\u{200B}00") == "1400" && VersionLabel.clean("0.6\u{200B} .2") == "0.6 .2" && VersionLabel.clean("\u{200B}") == nil)
check("an isolate and a pop go too: \\u{2066}0.6.2\\u{2069}", VersionLabel.clean("\u{2066}0.6.2\u{2069}") == "0.6.2")
check("an ideographic space and a thin space are white space", VersionLabel.clean("0.6\u{3000}.2\u{2009}") == "0.6 .2")
check("only those: letters, digits, punctuation and emoji stay", shown("0.6.2-β (ü)", "14🍎00") == "Sill 0.6.2-β (ü) (14🍎00) | Sill version 0.6.2-β (ü), build 14🍎00")
check("a value of control and format characters only is none", shown("\u{200B}\u{202E}\u{0}", "1400") == "Sill (1400) | Sill, build 1400")
check("an Int where a string belongs: its digits", shown(info: ["CFBundleShortVersionString": "0.6.2", "CFBundleVersion": 1400]) == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
check("an NSNumber and a Double: their digits", shown(NSNumber(value: 6), NSNumber(value: 1400)) == "Sill 6 (1400) | Sill version 6, build 1400"
      && shown(0.5, 2) == "Sill 0.5 (2) | Sill version 0.5, build 2")
check("a Boolean is none, true or false, Swift's or Foundation's",
      shown("0.6.2", true) == "Sill 0.6.2 | Sill version 0.6.2" && shown(false, "1400") == "Sill (1400) | Sill, build 1400"
      && shown(NSNumber(value: true), kCFBooleanFalse as Any) == "none")
check("other types are none: an array, a dictionary, data, a date, NSNull",
      shown(["0.6.2"], ["b": "1400"]) == "none" && shown(Data("0.6.2".utf8), Date(timeIntervalSince1970: 0)) == "none"
      && shown(NSNull(), "1400") == "Sill (1400) | Sill, build 1400")
check("an NSString is a string", shown(NSString(string: "0.6.2"), NSString(string: " 1400 ")) == "Sill 0.6.2 (1400) | Sill version 0.6.2, build 1400")
let long = String(repeating: "1.", count: 100) + "0"
check("a long value whole, never cut short (\(long.count) characters)", VersionLabel(version: long, build: "1400")?.text == "Sill \(long) (1400)")
check("the name is not taken out of a version that has it: \"Sill 1.0\" → \"Sill Sill 1.0\"",
      VersionLabel(version: "Sill 1.0", build: "1")?.text == "Sill Sill 1.0 (1)")
check("parentheses in a build kept: \"(1400)\" → \"Sill 0.6.2 ((1400))\"", VersionLabel(version: "0.6.2", build: "(1400)")?.text == "Sill 0.6.2 ((1400))")

// MARK: - Random values against the invariants

/// SplitMix64: the same values on every run.
struct Seeded { var state: UInt64; mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15; var z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
var rng = Seeded(state: 20261111)
let palette: [Unicode.Scalar] = ["0", "1", "4", "6", "9", ".", "a", "b", "β", "(", ")", "-", " ", " ", "\t", "\n", "\r",
                                 "\u{00A0}", "\u{2028}", "\u{0085}", "\u{0}", "\u{7}", "\u{1B}", "\u{200B}", "\u{202E}",
                                 "\u{FEFF}", "\u{00AD}", "\u{1F34E}", "\u{3000}", "\u{2066}"]
func randomValue() -> String {
    let n = Int(rng.next() % 12)
    var s = String.UnicodeScalarView()
    for _ in 0..<n { s.append(palette[Int(rng.next() % UInt64(palette.count))]) }
    return String(s)
}
/// Unicode's White_Space, and its control and format characters (Cc, Cf).
func isSpace(_ c: Unicode.Scalar) -> Bool { c.properties.isWhitespace }
func isHidden(_ c: Unicode.Scalar) -> Bool { c.properties.generalCategory == .control || c.properties.generalCategory == .format }
func plain(_ s: String) -> Bool {
    // One line of plain words: no white space but single spaces between words, none at the ends,
    // no control or format character.
    !s.isEmpty && s.unicodeScalars.allSatisfy { !isHidden($0) && (!isSpace($0) || $0 == " ") }
        && !s.hasPrefix(" ") && !s.hasSuffix(" ") && !s.contains("  ")
}
/// The words of a value, by hand: white space splits them, control and format characters vanish.
func words(_ s: String) -> [String] {
    var out: [String] = [], word = ""
    for c in s.unicodeScalars {
        if isSpace(c) { if !word.isEmpty { out.append(word); word = "" } } else if !isHidden(c) { word.unicodeScalars.append(c) }
    }
    if !word.isEmpty { out.append(word) }
    return out
}
var broken: [String] = []
for i in 0..<20_000 {
    let v = rng.next() % 5 == 0 ? nil : randomValue(), b = rng.next() % 5 == 0 ? nil : randomValue()
    let cv = VersionLabel.clean(v), cb = VersionLabel.clean(b)
    var ok = true
    for (raw, c) in [(v, cv), (b, cb)] {
        guard let raw else { ok = ok && c == nil; continue }
        let w = words(raw)
        if w.isEmpty { ok = ok && c == nil } else { ok = ok && c == w.joined(separator: " ") && plain(c!) }
        ok = ok && VersionLabel.clean(c) == c                       // idempotent
    }
    let label = VersionLabel(version: v, build: b)
    ok = ok && (label == nil) == (cv == nil && cb == nil)
    if let label {
        ok = ok && label.version == cv && label.build == cb
        ok = ok && label.text == "Sill" + (cv.map { " \($0)" } ?? "") + (cb.map { " (\($0))" } ?? "")
        ok = ok && label.spoken == "Sill" + (cv.map { " version \($0)" } ?? "") + (cb.map { ", build \($0)" } ?? "")
        ok = ok && !label.text.contains("\n") && plain(label.text)
    }
    if !ok && broken.count < 5 { broken.append("#\(i) \(String(reflecting: v)) \(String(reflecting: b))") }
}
check("20,000 random values (seeded): cleaned to their words, idempotent, one line, a label exactly when either has words"
      + (broken.isEmpty ? "" : "; broken: " + broken.joined(separator: ", ")), broken.isEmpty)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
