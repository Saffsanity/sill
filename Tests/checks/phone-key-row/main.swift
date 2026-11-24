// PhoneKeyRow (iOSClient/PhoneKeyRow.swift): the key row of a phone held upright and its switch, Arrow Keys
// (issue #287, PR #315 by oyyblin; the review's brief in keys.md, "#315 and #293"). Compiled with
// PhonePortraitLayout (iOSClient/PhonePortraitLayout.swift), whose row 3 the caps are laid across, with
// swiftc (run.sh).
//
// What it checks:
//   K1 the switch: `Sill.arrowKeys`, off by default (new behaviour is off unless turned on), offered on an
//      iPhone (the phone's arrangement, the iPhone Duo's cover among them) and never on an iPad;
//   K2 the caps: off, the six that name a key, PhonePortraitLayout's six, the row as it was (no scrolling);
//      on, the four arrows after shift, ten in a row that scrolls;
//   K3 the row that scrolls, at every width a phone's arrangement has (300 to 599 pt, in half points) on
//      PhonePortraitLayout's own row 3 and gap: every cap at least 44 pt wide; as many whole as fit so, six
//      at most (maximal: one more would be under 44 pt); `peek` (0.6, over half) of the next showing past
//      them; the row filled exactly; never wider than the six's caps of the row with the switch off;
//      each named iPhone's numbers (six whole from 375 pt, 49.4 pt on a 402 pt iPhone, five of 45 pt at
//      Display Zoom's 320 pt); the bound itself (a cap of exactly 44 pt counts);
//   K4 its ends: at rest the six that name a key whole where six fit; at the end the last arrow at the
//      row's edge, shift and the four arrows whole on every iPhone (cmd too where six fit), the content
//      the caps and the gaps between them, and the scroll no further;
//   K5 the fades: an edge fades exactly while caps lie past it (at rest the trailing edge alone, at the
//      end the leading alone, both between, half a point the threshold either way), over the cut cap's
//      part and the gap before it, at most half the row; the end;
//   K6 VoiceOver's action on every cap (#293's words): "Show the arrow keys" short of the end, which
//      takes VoiceOver to the left arrow, "Show the modifier keys" at the end, back to esc;
//   K7 the words of Settings › This iPhone › Keys;
//   K8 20,000 random rows (width, gap, count, how far scrolled) against K3–K6's invariants, and the
//      degenerate rows (none wide enough for one 44 pt cap, a row of no width).
import CoreGraphics
import Foundation

var fails = 0, passes = 0
func check(_ what: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(what)") } else { fails += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check("\(what): \(a)" + (a == b ? "" : " (want \(b))"), a == b) }
func near(_ a: CGFloat, _ b: CGFloat, _ what: String, within: CGFloat = 1e-9) {
    check("\(what): \(String(format: "%.4f", Double(a)))" + (abs(a - b) <= within ? "" : " (want \(String(format: "%.4f", Double(b))))"),
          abs(a - b) <= within)
}

typealias R = PhoneKeyRow
typealias Strip = PhoneKeyRow.Strip

struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

// MARK: K1 the switch

eq(R.arrowKeysKey, "Sill.arrowKeys", "K1 the switch's key, this device's own (-Sill.arrowKeys 1 for one run)")
eq(R.arrowKeysDefault, false, "K1 Arrow Keys is off unless turned on")
eq(R.offered(phoneArrangement: true), true, "K1 offered on an iPhone (the phone's arrangement upright, the Duo's cover too)")
eq(R.offered(phoneArrangement: false), false, "K1 never offered on an iPad, whose key rows have the arrows")

// MARK: K2 the caps

eq(R.named, PhonePortraitLayout.capCount, "K2 the caps that name a key are PhonePortraitLayout's six")
eq(R.named, 6, "K2 esc, tab, ctrl, opt, cmd and shift")
eq(R.arrows, 4, "K2 ← ↓ ↑ →")
eq(R.capCount(arrowKeys: false), 6, "K2 off: the six, as the row was")
eq(R.capCount(arrowKeys: true), 10, "K2 on: the six and the four arrows")
eq(R.capCount(arrowKeys: R.arrowKeysDefault), PhonePortraitLayout.capCount, "K2 by default the row PhonePortraitLayout lays out")
eq(R.firstArrow, 6, "K2 the arrows start right after shift (the seventh cap)")
eq(R.scrolls(arrowKeys: false), false, "K2 off: the row does not scroll (six equal caps)")
eq(R.scrolls(arrowKeys: true), true, "K2 on: the row scrolls")
eq(R.scrolls(arrowKeys: R.arrowKeysDefault), false, "K2 by default nothing scrolls")

// MARK: K3 the row that scrolls, on PhonePortraitLayout's row

eq(R.minCapWidth, 44, "K3 a touch target's least: 44 pt")
eq(R.maxWhole, 6, "K3 at most six whole: the six that name a key")
check("K3 over half of the next cap shows, never all of it (peek \(R.peek))", R.peek > 0.5 && R.peek < 1)
near(R.peek, 0.6, "K3 peek: 0.6 of a cap")

/// What a cap's width is with `whole` whole, written out apart from the rule: `whole` caps and gaps and
/// 0.6 of a cap fill the row.
func widthFor(_ whole: Int, row: CGFloat, gap: CGFloat) -> CGFloat {
    (row - CGFloat(whole) * gap) / (CGFloat(whole) + 0.6)
}

let gap = PhonePortraitLayout.gap
eq(gap, 8, "K3 the gap between caps is PhonePortraitLayout's 8 pt")
var widths = 0, sixes = 0, fives = 0
var narrowest: CGFloat = .infinity
var sw: CGFloat = 300
while sw < 600 {
    for height: CGFloat in [548, 812] {
        let layout = PhonePortraitLayout(size: CGSize(width: sw, height: height))
        let row = layout.keys.width
        let s = Strip(rowWidth: row, gap: gap, count: R.capCount(arrowKeys: true))
        let at = "at \(sw)x\(Int(height)) (row \(row))"
        widths += 1
        narrowest = min(narrowest, s.capWidth)
        if s.whole == 6 { sixes += 1 }
        if s.whole == 5 { fives += 1 }
        if !(1...R.maxWhole).contains(s.whole) { check("K3 whole \(s.whole) in 1...6 \(at)", false) }
        if s.capWidth < 44 { check("K3 every cap at least 44 pt: \(s.capWidth) \(at)", false) }
        if s.whole < R.maxWhole && widthFor(s.whole + 1, row: row, gap: gap) >= 44 {
            check("K3 maximal: \(s.whole + 1) whole would still be \(widthFor(s.whole + 1, row: row, gap: gap)) pt \(at)", false)
        }
        if abs(s.capWidth - widthFor(s.whole, row: row, gap: gap)) > 1e-9 {
            check("K3 the cap's width is the row's share: \(s.capWidth) against \(widthFor(s.whole, row: row, gap: gap)) \(at)", false)
        }
        let filled = CGFloat(s.whole) * (s.capWidth + gap) + 0.6 * s.capWidth
        if abs(filled - row) > 1e-9 { check("K3 the row filled exactly: \(filled) of \(row) \(at)", false) }
        let cut = row - s.capStart(s.whole, scrolled: 0)
        if abs(cut - 0.6 * s.capWidth) > 1e-9 { check("K3 0.6 of the next cap shows at rest: \(cut) of \(s.capWidth) \(at)", false) }
        // Where six show whole, the peek costs width: narrower than the six's caps with the switch off.
        if s.whole == 6 && s.capWidth >= layout.caps[0].width {
            check("K3 six whole are narrower than the six's caps with the switch off (\(layout.caps[0].width)) \(at)", false)
        }
        if sw >= 367 && s.whole != 6 { check("K3 six whole from 367 pt: \(s.whole) \(at)", false) }
        if sw >= 315 && s.whole < 5 { check("K3 five whole at least from 315 pt: \(s.whole) \(at)", false) }
    }
    sw += 0.5
}
check("K3 \(widths) rows from 300 to 599.5 pt: every cap at least 44 pt (the narrowest \(String(format: "%.2f", Double(narrowest)))), "
      + "six whole on \(sixes), five on \(fives)", narrowest >= 44 && sixes > 0 && fives > 0)

// Named iPhones, upright (the stream screen's width; row 3 is 28 pt narrower).
let named: [(CGFloat, Int, CGFloat, String)] = [
    (320, 5, 45.0, "Display Zoom on an SE, a mini or a 6.1-inch iPhone"),
    (375, 6, (347.0 - 48) / 6.6, "an SE or a mini"),
    (382, 6, (354.0 - 48) / 6.6, "the iPhone Duo's cover"),
    (390, 6, (362.0 - 48) / 6.6, "the 12 to 14"),
    (393, 6, (365.0 - 48) / 6.6, "the 15 and 16"),
    (402, 6, (374.0 - 48) / 6.6, "the 17 and the 17 and 18 Pro"),
    (430, 6, (402.0 - 48) / 6.6, "a Plus or a Pro Max"),
    (440, 6, (412.0 - 48) / 6.6, "the 17 and 18 Pro Max"),
]
for (width, whole, cap, what) in named {
    let row = PhonePortraitLayout(size: CGSize(width: width, height: 812)).keys.width
    let s = Strip(rowWidth: row, gap: gap, count: 10)
    eq(s.whole, whole, "K3 \(Int(width)) pt (\(what)): whole caps at rest")
    near(s.capWidth, cap, "K3 \(Int(width)) pt (\(what)): a cap's width", within: 1e-6)
}
near(Strip(rowWidth: 374, gap: 8, count: 10).capWidth, 49.393939, "K3 49.4 pt on a 402 pt iPhone (the six's are 55.7)", within: 1e-5)
near(Strip(rowWidth: 292, gap: 8, count: 10).capWidth, 45, "K3 45 pt at 320 pt: five whole, not six of 37 pt", within: 1e-9)
// The bound itself: a row where six whole leave exactly 44 pt keeps six (44 counts), and a hair less drops to five.
for whole in 1...6 {
    let exact = 44 * (CGFloat(whole) + 0.6) + CGFloat(whole) * gap
    let s = Strip(rowWidth: exact, gap: gap, count: 10)
    eq(s.whole, whole, "K3 a row of \(exact) pt: \(whole) whole of exactly 44 pt")
    near(s.capWidth, 44, "K3 a row of \(exact) pt: 44 pt caps")
    if whole > 1 { eq(Strip(rowWidth: exact - 0.01, gap: gap, count: 10).whole, whole - 1, "K3 \(exact - 0.01) pt: \(whole - 1) whole") }
}

// MARK: K4 its ends

for width: CGFloat in [320, 375, 402, 440] {
    let row = width - 2 * PhonePortraitLayout.side
    let s = Strip(rowWidth: row, gap: gap, count: 10)
    let at = "\(Int(width)) pt"
    near(s.content, 10 * s.capWidth + 9 * gap, "K4 \(at): the content, ten caps and nine gaps")
    near(s.maxScroll, s.content - row, "K4 \(at): it scrolls the content past the row and no further")
    check("K4 \(at): it scrolls (\(s.maxScroll) pt)", s.maxScroll > 0)
    near(s.capStart(9, scrolled: s.maxScroll) + s.capWidth, row, "K4 \(at): at the end, the right arrow's trailing edge at the row's")
    check("K4 \(at): at the end shift and the four arrows whole in view",
          (5...9).allSatisfy { s.capStart($0, scrolled: s.maxScroll) >= -1e-9 && s.capStart($0, scrolled: s.maxScroll) + s.capWidth <= row + 1e-9 })
    if s.whole == 6 {
        check("K4 \(at): at the end cmd whole too, beside shift and the arrows", s.capStart(4, scrolled: s.maxScroll) >= -1e-9)
        check("K4 \(at): at rest the six that name a key whole", s.capStart(5, scrolled: 0) + s.capWidth <= row + 1e-9)
        check("K4 \(at): at rest the left arrow cut, not whole", s.capStart(6, scrolled: 0) + s.capWidth > row + 1)
    } else {
        check("K4 \(at): at rest shift cut, past five whole", s.capStart(5, scrolled: 0) + s.capWidth > row + 1
              && s.capStart(4, scrolled: 0) + s.capWidth <= row + 1e-9)
    }
    near(s.capStart(0, scrolled: 0), 0, "K4 \(at): at rest esc at the row's leading edge")
}

// MARK: K5 the fades

for width: CGFloat in [320, 402, 440] {
    let row = width - 2 * PhonePortraitLayout.side
    let s = Strip(rowWidth: row, gap: gap, count: 10)
    let at = "\(Int(width)) pt"
    near(s.fadeWidth, 0.6 * s.capWidth + gap, "K5 \(at): the fade covers the cut cap's part in view and the gap before it")
    near(s.fadeShare, s.fadeWidth / row, "K5 \(at): its share of the row")
    check("K5 \(at): the fade is a short edge (\(s.fadeShare) of the row)", s.fadeShare > 0 && s.fadeShare < 0.25)
    eq(s.fadesLeading(scrolled: 0), false, "K5 \(at): at rest the leading edge is clear")
    eq(s.fadesTrailing(scrolled: 0), true, "K5 \(at): at rest the trailing edge fades (the left arrow, or shift, past it)")
    eq(s.atEnd(scrolled: 0), false, "K5 \(at): at rest, not at the end")
    eq(s.fadesLeading(scrolled: s.maxScroll), true, "K5 \(at): at the end the leading edge fades")
    eq(s.fadesTrailing(scrolled: s.maxScroll), false, "K5 \(at): at the end the trailing edge is clear")
    eq(s.atEnd(scrolled: s.maxScroll), true, "K5 \(at): at the end")
    let middle = s.maxScroll / 2
    eq(s.fadesLeading(scrolled: middle) && s.fadesTrailing(scrolled: middle), true, "K5 \(at): between, both edges fade")
    eq(s.atEnd(scrolled: middle), false, "K5 \(at): between, not at the end")
    eq(s.fadesLeading(scrolled: 0.5), false, "K5 \(at): half a point scrolled still counts as at rest")
    eq(s.fadesLeading(scrolled: 1), true, "K5 \(at): a point scrolled fades the leading edge")
    eq(s.fadesTrailing(scrolled: s.maxScroll - 0.5), false, "K5 \(at): half a point short of the end counts as the end")
    eq(s.fadesTrailing(scrolled: s.maxScroll - 1), true, "K5 \(at): a point short of the end still fades the trailing edge")
    eq(s.atEnd(scrolled: s.maxScroll - 0.5), true, "K5 \(at): half a point short of the end is the end")
    eq(s.atEnd(scrolled: s.maxScroll - 1), false, "K5 \(at): a point short of the end is not")
    eq(s.atEnd(scrolled: s.maxScroll + 3), true, "K5 \(at): past the end (a bounce) is the end")
}

// MARK: K6 VoiceOver's action

eq(R.Copy.scrollAction(atEnd: false), "Show the arrow keys", "K6 short of the end, every cap's action brings the arrows")
eq(R.Copy.scrollAction(atEnd: true), "Show the modifier keys", "K6 at the end, it takes the row back")
eq(R.Copy.showArrows, "Show the arrow keys", "K6 #293's words")
eq(R.Copy.showModifiers, "Show the modifier keys", "K6 #293's words")
eq(R.voiceOverFocus(atEnd: false), R.firstArrow, "K6 after bringing the arrows, VoiceOver is on the left arrow")
eq(R.voiceOverFocus(atEnd: true), 0, "K6 after taking the row back, VoiceOver is on esc")
let focusRow = Strip(rowWidth: 374, gap: 8, count: 10)
check("K6 the left arrow is whole in view at the end, where the action takes VoiceOver",
      focusRow.capStart(R.voiceOverFocus(atEnd: false), scrolled: focusRow.maxScroll) >= 0)

// MARK: K7 the words

eq(R.Copy.group, "Keys", "K7 the group's heading, under This iPhone")
eq(R.Copy.title, "Arrow Keys", "K7 the switch")
eq(R.Copy.footnote, "Adds ← ↓ ↑ → after shift in the key row. Swipe the row to reach them.", "K7 the words under it")

// MARK: K8 random rows, and the degenerate ones

var rng = Rng(s: 315)
var k8: [String: Int] = [:]
var k8First: [String: String] = [:]
func violated(_ what: String, _ detail: String) {
    k8[what, default: 0] += 1
    if k8First[what] == nil { k8First[what] = detail }
}
var scrolledCount = 0, endCount = 0, restCount = 0
for _ in 0..<20_000 {
    let row = 80 + rng.unit() * 520
    let g = rng.unit() * 16
    let count = 7 + rng.below(8)
    let s = Strip(rowWidth: row, gap: g, count: count)
    let detail = "row \(row), gap \(g), \(count) caps: whole \(s.whole), cap \(s.capWidth)"
    let fits = widthFor(1, row: row, gap: g) >= 44
    if !(1...6).contains(s.whole) { violated("whole outside 1...6", detail) }
    if fits && s.capWidth < 44 - 1e-9 { violated("a cap under 44 pt where one fits", detail) }
    if s.whole < 6 && widthFor(s.whole + 1, row: row, gap: g) >= 44 { violated("not maximal", detail) }
    if abs(CGFloat(s.whole) * (s.capWidth + g) + 0.6 * s.capWidth - row) > 1e-6 { violated("the row not filled exactly", detail) }
    if abs(s.content - (CGFloat(count) * s.capWidth + CGFloat(count - 1) * g)) > 1e-6 { violated("the content", detail) }
    if abs(s.maxScroll - max(0, s.content - row)) > 1e-6 { violated("the scroll's end", detail) }
    if abs(s.fadeShare - min(0.5, (0.6 * s.capWidth + g) / row)) > 1e-9 { violated("the fade's share", detail) }
    let at = (rng.unit() * 1.2 - 0.1) * (s.maxScroll + 4) - 2
    let where_ = detail + ", scrolled \(at) of \(s.maxScroll)"
    if s.fadesLeading(scrolled: at) != (at > 0.5) { violated("the leading fade not exactly while scrolled", where_) }
    if s.fadesTrailing(scrolled: at) != (at < s.maxScroll - 0.5) { violated("the trailing fade not exactly while short of the end", where_) }
    if s.atEnd(scrolled: at) == s.fadesTrailing(scrolled: at) { violated("the end not exactly where the trailing edge clears", where_) }
    if R.Copy.scrollAction(atEnd: s.atEnd(scrolled: at)) != (s.atEnd(scrolled: at) ? "Show the modifier keys" : "Show the arrow keys") {
        violated("VoiceOver's words", where_)
    }
    if s.maxScroll > 1 && at > 0.5 && at < s.maxScroll - 0.5 { scrolledCount += 1 }
    if s.atEnd(scrolled: at) { endCount += 1 }
    if !s.fadesLeading(scrolled: at) { restCount += 1 }
}
for (what, n) in k8.sorted(by: { $0.key < $1.key }) { check("K8 \(what): \(n) times; first: \(k8First[what] ?? "")", false) }
check("K8 20,000 random rows (\(scrolledCount) between the ends, \(endCount) at the end, \(restCount) at rest): K3–K6's invariants",
      k8.isEmpty && scrolledCount > 5_000 && endCount > 1_000 && restCount > 1_000)

let tooNarrow = Strip(rowWidth: 60, gap: 8, count: 10)
eq(tooNarrow.whole, 1, "K8 a row too narrow for one 44 pt cap: one whole")
near(tooNarrow.capWidth, (60 - 8) / 1.6, "K8 a row too narrow: the one cap as wide as the row allows")
let none = Strip(rowWidth: 0, gap: 8, count: 10)
eq(none.capWidth, 0, "K8 a row of no width (before layout): caps of no width")
eq(none.fadeShare, 0, "K8 a row of no width: no fade")
let tiny = Strip(rowWidth: 20, gap: 8, count: 10)
near(tiny.fadeShare, 0.5, "K8 a fade wider than half a tiny row stops at half")

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
