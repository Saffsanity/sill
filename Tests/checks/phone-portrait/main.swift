// H2 (docs/iphone-portrait-plan.md): iOSClient/PhonePortraitLayout.swift on its own, the rectangles of
// a phone held upright. The plan's two tables pinned phone by phone (the layout, then the keyboard:
// row 1 clear of it on every phone), 320 pt wide, and a grid of every width from 300 to 599 pt and
// every height from the width + 1 to 1,400: everything inside the screen and in order, the gaps,
// five equal buttons and six equal caps across the row, the picture 16:10 unless the trackpad would
// drop under 120 pt, the trackpad's span, the ruler, the drawer and the panel, the dim.
//   swiftc -O iOSClient/PhonePortraitLayout.swift Tests/checks/phone-portrait/main.swift -o .build/checks/phone-portrait/check && .build/checks/phone-portrait/check
import CoreGraphics
import Foundation

typealias L = PhonePortraitLayout
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", name) } else { passes += 1; print("ok  ", name) } }
/// Equal to within a hundredth of a point, which is closer than any screen draws.
func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
func near(_ a: CGRect, _ b: CGRect) -> Bool {
    near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
}
func str(_ r: CGRect) -> String { String(format: "(%.2f, %.2f, %.2f×%.2f)", r.minX, r.minY, r.width, r.height) }

// MARK: - The plan's layout table
//
// Each phone's screen, less its top safe-area inset (the status bar, the Dynamic Island), is the
// stream screen's container; iPhones upright have no side insets and the stream screen ignores the
// bottom one. Row 1 is y from its top to its bottom (the button's width); row 2 likewise; row 3 (the
// cap's width); the trackpad's width and height; the panel room from under row 1 to the trackpad's
// bottom. "Today" (the Duo's outer layout that every iPhone got until now) is in the comments.

struct Phone {
    let name: String
    let screen: CGSize
    let inset: CGFloat
    /// The software keyboard's height as the input view shows it (autocorrection off, so no
    /// suggestions bar): measured on the iOS 27 simulators for the 18 Pro Max (320), the 18 Pro and
    /// the 17e (301, both), 2026-09-27; the 15 Pro and the 13 mini taken as the 18 Pro's, the SE
    /// as the classic 216. A keyboard with a candidate bar (an IME) is about 44 pt taller.
    let keyboard: CGFloat?
    var container: CGSize { CGSize(width: screen.width, height: screen.height - inset) }
}

struct Row {
    let phone: Phone
    let picture: CGSize
    let row1: (CGFloat, CGFloat), button: CGFloat
    let row2: (CGFloat, CGFloat)
    let row3: (CGFloat, CGFloat), cap: CGFloat
    let trackpad: CGSize
    let panelRoom: CGFloat
}

let proMax = Phone(name: "iPhone 18 Pro Max", screen: CGSize(width: 440, height: 956), inset: 62, keyboard: 320)
let pro = Phone(name: "iPhone 18 Pro (and 17)", screen: CGSize(width: 402, height: 874), inset: 62, keyboard: 301)
let fifteenPro = Phone(name: "iPhone 15 Pro", screen: CGSize(width: 393, height: 852), inset: 59, keyboard: 301)
let seventeenE = Phone(name: "iPhone 17e", screen: CGSize(width: 390, height: 844), inset: 47, keyboard: 301)
let mini = Phone(name: "iPhone 13 mini", screen: CGSize(width: 375, height: 812), inset: 50, keyboard: 301)
let se = Phone(name: "iPhone SE (3rd generation)", screen: CGSize(width: 375, height: 667), inset: 20, keyboard: 216)
let duoOuter = Phone(name: "the Duo's outer display (the harness)", screen: CGSize(width: 500, height: 710), inset: 0, keyboard: nil)

let table: [Row] = [
    // today: trackpad 243, panel room 351
    Row(phone: proMax, picture: CGSize(width: 424, height: 265), row1: (291, 341), button: 76, row2: (351, 413),
        row3: (423, 467), cap: 62, trackpad: CGSize(width: 412, height: 401), panelRoom: 529),
    // today: 202, 310
    Row(phone: pro, picture: CGSize(width: 386, height: 241), row1: (267, 317), button: 68.4, row2: (327, 389),
        row3: (399, 443), cap: 334.0 / 6, trackpad: CGSize(width: 374, height: 343), panelRoom: 471),
    // today: 192, 300
    Row(phone: fifteenPro, picture: CGSize(width: 377, height: 235), row1: (261, 311), button: 66.6, row2: (321, 383),
        row3: (393, 437), cap: 325.0 / 6, trackpad: CGSize(width: 365, height: 330), panelRoom: 458),
    // today: 194, 302
    Row(phone: seventeenE, picture: CGSize(width: 374, height: 233), row1: (259, 309), button: 66, row2: (319, 381),
        row3: (391, 435), cap: 322.0 / 6, trackpad: CGSize(width: 362, height: 336), panelRoom: 464),
    // today: 177, 285
    Row(phone: mini, picture: CGSize(width: 359, height: 224), row1: (250, 300), button: 63, row2: (310, 372),
        row3: (382, 426), cap: 307.0 / 6, trackpad: CGSize(width: 347, height: 310), panelRoom: 438),
    // today: 119, 227
    Row(phone: se, picture: CGSize(width: 359, height: 224), row1: (250, 300), button: 63, row2: (310, 372),
        row3: (382, 426), cap: 307.0 / 6, trackpad: CGSize(width: 347, height: 195), panelRoom: 323),
    // today: 151, 259
    Row(phone: duoOuter, picture: CGSize(width: 484, height: 302), row1: (328, 378), button: 88, row2: (388, 450),
        row3: (460, 504), cap: 72, trackpad: CGSize(width: 472, height: 180), panelRoom: 308),
]

for row in table {
    let size = row.phone.container
    let l = L(size: size)
    let n = "\(row.phone.name) (\(Int(size.width))×\(Int(size.height)))"
    check("\(n): the picture is \(Int(row.picture.width))×\(Int(row.picture.height)) at (8, 8)",
          l.picture == CGRect(x: 8, y: 8, width: row.picture.width, height: row.picture.height))
    check("\(n): row 1 at \(Int(row.row1.0))–\(Int(row.row1.1)), from 14 to \(Int(size.width - 14))",
          l.row1 == CGRect(x: 14, y: row.row1.0, width: size.width - 28, height: row.row1.1 - row.row1.0))
    check("\(n): five buttons \(row.button) wide, 50 tall, 8 apart",
          l.buttons.count == 5 && l.buttons.enumerated().allSatisfy { i, b in
              near(b, CGRect(x: 14 + CGFloat(i) * (row.button + 8), y: row.row1.0, width: row.button, height: 50)) })
    check("\(n): the strip at \(Int(row.row2.0))–\(Int(row.row2.1)), from 6 to \(Int(size.width - 6))",
          l.strip == CGRect(x: 6, y: row.row2.0, width: size.width - 12, height: row.row2.1 - row.row2.0))
    check("\(n): row 3 at \(Int(row.row3.0))–\(Int(row.row3.1))",
          l.keys == CGRect(x: 14, y: row.row3.0, width: size.width - 28, height: row.row3.1 - row.row3.0))
    check("\(n): six caps " + String(format: "%.1f", row.cap) + " wide, 44 tall, 8 apart",
          l.caps.count == 6 && l.caps.enumerated().allSatisfy { i, c in
              near(c, CGRect(x: 14 + CGFloat(i) * (row.cap + 8), y: row.row3.0, width: row.cap, height: 44)) })
    check("\(n): the trackpad \(Int(row.trackpad.width))×\(Int(row.trackpad.height)), to 16 pt from the bottom",
          l.trackpad == CGRect(x: 14, y: row.row3.1 + 10, width: row.trackpad.width, height: row.trackpad.height)
            && l.trackpad.maxY == size.height - 16)
    check("\(n): the drawer and the panel get \(Int(row.panelRoom)) pt, from 8 under row 1",
          l.drawer.minY == row.row1.1 + 8 && l.drawer.height == row.panelRoom
            && l.settings.minY == row.row1.1 + 8 && l.settings.height == row.panelRoom)
    check("\(n): the drawer from 14, \(Int(min(380, size.width - 28))) wide; the panel to \(Int(size.width - 14)), \(Int(min(360, size.width - 28))) wide",
          l.drawer.minX == 14 && l.drawer.width == min(380, size.width - 28)
            && l.settings.maxX == size.width - 14 && l.settings.width == min(360, size.width - 28))
    check("\(n): the ruler 36 a detent, 204 wide, centred on Aa over row 1",
          l.rulerStep == 36 && near(l.ruler, CGRect(x: l.buttons[1].midX - 102, y: row.row1.0, width: 204, height: 50)))
    check("\(n): the trackpad's span is its width ÷ 1.6 (" + String(format: "%.2f", row.trackpad.width / 1.6) + ")",
          near(l.trackpadSpan, row.trackpad.width / 1.6))
    check("\(n): the Settings panel grows from its top-trailing corner",
          near(l.settingsAnchor.x, (size.width - 14) / size.width) && near(l.settingsAnchor.y, (row.row1.1 + 8) / size.height))
    check("\(n): the dim is above and below row 1's band",
          l.dim == [CGRect(x: 0, y: 0, width: size.width, height: row.row1.0),
                    CGRect(x: 0, y: row.row1.1, width: size.width, height: size.height - row.row1.1)])
}

// The mockup's own numbers (Noah's approval): the picture and the buttons exactly; its trackpads
// (389 and 331) are 12 pt shorter than these, which keep today's gaps under the picture and between
// the rows.
check("mockup: Pro Max picture 424×265, buttons 76×50", L(size: proMax.container).picture.size == CGSize(width: 424, height: 265)
      && L(size: proMax.container).buttons.allSatisfy { near($0.width, 76) && $0.height == 50 })
check("mockup: Pro picture 386×241, buttons 68.4×50", L(size: pro.container).picture.size == CGSize(width: 386, height: 241)
      && L(size: pro.container).buttons.allSatisfy { near($0.width, 68.4) && $0.height == 50 })
check("mockup: the button width is (row width − 4 × 8) ÷ 5 on both",
      [proMax, pro].allSatisfy { p in L(size: p.container).buttons.allSatisfy { near($0.width, (p.container.width - 28 - 32) / 5) } })

// 320 pt (an iPad window in Slide Over; no phone is this narrow): the buttons 52, the caps 42 (as the
// Duo's outer layout had them), the ruler's step 28 so it stays inside the row.
let narrow = L(size: CGSize(width: 320, height: 1000))
check("320 wide: five buttons 52 wide", narrow.buttons.allSatisfy { near($0.width, 52) })
check("320 wide: six caps 42 wide", narrow.caps.allSatisfy { near($0.width, 42) })
check("320 wide: the ruler's step 28, its leading edge at the row's", near(narrow.rulerStep, 28) && near(narrow.ruler.minX, 14))
let threeSixty = L(size: CGSize(width: 360, height: 1000))
check("360 wide: the ruler's step 34", near(threeSixty.rulerStep, 34))

// MARK: - The keyboard table
//
// With the keyboard up (the layout never moves for it), in the screen's coordinates: row 1 ends
// above the keyboard's top on every phone, so its Keyboard button can take the keyboard down, and
// rows 2 and 3 too, on the SE only just (5 pt, with its assumed keyboard). The trackpad is under it
// on every phone. The plan assumed keyboards with a suggestions bar (346, 336, 260), which put row 3
// under it on the mini and the SE; the input view has none (the heights above), and a keyboard with
// a candidate bar still leaves row 1 clear on every phone (the last check).

struct KeyboardRow { let phone: Phone; let top: CGFloat; let row1: CGFloat; let row2: CGFloat; let row3: CGFloat }
let keyboardTable: [KeyboardRow] = [
    KeyboardRow(phone: proMax, top: 636, row1: 403, row2: 475, row3: 529),
    KeyboardRow(phone: pro, top: 573, row1: 379, row2: 451, row3: 505),
    KeyboardRow(phone: fifteenPro, top: 551, row1: 370, row2: 442, row3: 496),
    KeyboardRow(phone: seventeenE, top: 543, row1: 356, row2: 428, row3: 482),
    KeyboardRow(phone: mini, top: 511, row1: 350, row2: 422, row3: 476),
    KeyboardRow(phone: se, top: 451, row1: 320, row2: 392, row3: 446),
]
for k in keyboardTable {
    let l = L(size: k.phone.container)
    let top = k.phone.screen.height - k.phone.keyboard!
    let inset = k.phone.inset
    check("\(k.phone.name): the keyboard's top at \(Int(k.top)); row 1 ends at \(Int(k.row1)), rows 2 and 3 at \(Int(k.row2)) and \(Int(k.row3))",
          top == k.top && inset + l.row1.maxY == k.row1 && inset + l.strip.maxY == k.row2 && inset + l.keys.maxY == k.row3)
    check("\(k.phone.name): row 1, with Keyboard, clear of the keyboard (\(Int(top - inset - l.row1.maxY)) pt)",
          inset + l.row1.maxY < top)
    check("\(k.phone.name): the trackpad under the keyboard", inset + l.trackpad.maxY > top)
}
for p in [proMax, pro, fifteenPro, seventeenE, mini, se] {
    let l = L(size: p.container)
    check("\(p.name): rows 2 and 3 clear of the keyboard too (\(Int(p.screen.height - p.keyboard! - p.inset - l.keys.maxY)) pt)",
          p.inset + l.keys.maxY < p.screen.height - p.keyboard!)
}
check("measured: 107 pt between row 3 and the keyboard on the 18 Pro Max, 68 on the 18 Pro, 61 on the 17e",
      [(proMax, 107), (pro, 68), (seventeenE, 61)].allSatisfy { p, gap in
          p.screen.height - p.keyboard! - p.inset - L(size: p.container).keys.maxY == CGFloat(gap) })
check("with a candidate bar (44 pt more) row 1 is still clear on every phone",
      [proMax, pro, fifteenPro, seventeenE, mini, se].allSatisfy { p in
          p.inset + L(size: p.container).row1.maxY < p.screen.height - p.keyboard! - 44 })

// MARK: - Every width from 300 to 599 pt, every height from the width + 1 to 1,400

/// Each rule over the whole grid is one case: it passes when every size keeps it, and a failure
/// names the first size that did not.
final class Rule {
    let name: String
    var firstFailure: String?
    var sizes = 0
    init(_ name: String) { self.name = name }
    func expect(_ ok: @autoclosure () -> Bool, _ size: CGSize, _ detail: @autoclosure () -> String = "") {
        guard firstFailure == nil else { return }
        if !ok() { firstFailure = "\(Int(size.width))×\(Int(size.height))" + { let d = detail(); return d.isEmpty ? "" : ": " + d }() }
    }
}
let inside = Rule("everything inside the screen")
let ordered = Rule("top to bottom: the picture, row 1, the strip, row 3, the trackpad, none overlapping")
let gaps = Rule("the gaps: 18 under the picture, 10 between rows, 10 above the trackpad, 16 under it")
let pictureRule = Rule("the picture at (8, 8), full width less 16, exactly ⌊(W − 16) ÷ 1.6⌋ tall while the trackpad keeps 120 pt, else the trackpad exactly 120 (the picture never below 0)")
let buttonsRule = Rule("five equal buttons, 50 tall, 8 apart, from 14 to W − 14, each at least 44 wide")
let capsRule = Rule("six equal caps, 44 tall, 8 apart, from 14 to W − 14; at least 44 wide from 332 pt up")
let alignRule = Rule("the rows line up: Apps, the first thumbnail, esc and the trackpad at 14; Settings, shift and the trackpad end at W − 14; the strip from 6 to W − 6")
let spanRule = Rule("the trackpad's span is its width ÷ 1.6")
let rulerRule = Rule("the ruler over row 1, centred on Aa, 4 × step + 60 wide, inside the row, 36 a detent where it fits, less where not")
let panelsRule = Rule("the drawer and the panel from 8 under row 1 to the trackpad's bottom, at the leading and trailing edges, at most 380 and 360 wide")
let anchorRule = Rule("the panel's anchor is its top-trailing corner")
let dimRule = Rule("the dim covers everything but row 1's band, in two pieces")
let rules = [inside, ordered, gaps, pictureRule, buttonsRule, capsRule, alignRule, spanRule, rulerRule, panelsRule, anchorRule, dimRule]

func within(_ r: CGRect, _ size: CGSize) -> Bool {
    r.minX >= -0.001 && r.minY >= -0.001 && r.maxX <= size.width + 0.001 && r.maxY <= size.height + 0.001 && r.width >= 0 && r.height >= 0
}

var gridSizes = 0
for w in 300...599 {
    for h in (w + 1)...1400 {
        let size = CGSize(width: w, height: h)
        let W = CGFloat(w), H = CGFloat(h)
        let l = L(size: size)
        gridSizes += 1

        let all = [l.picture, l.row1, l.strip, l.keys, l.trackpad, l.ruler, l.drawer, l.settings] + l.buttons + l.caps + l.dim
        inside.expect(all.allSatisfy { within($0, size) }, size, all.first { !within($0, size) }.map(str) ?? "")

        ordered.expect(l.picture.maxY <= l.row1.minY && l.row1.maxY <= l.strip.minY && l.strip.maxY <= l.keys.minY
                       && l.keys.maxY <= l.trackpad.minY, size)

        gaps.expect(l.row1.minY - l.picture.maxY == 18 && l.strip.minY - l.row1.maxY == 10 && l.keys.minY - l.strip.maxY == 10
                    && l.trackpad.minY - l.keys.maxY == 10 && H - l.trackpad.maxY == 16, size,
                    "\(l.row1.minY - l.picture.maxY), \(l.strip.minY - l.row1.maxY), \(l.keys.minY - l.strip.maxY), \(l.trackpad.minY - l.keys.maxY), \(H - l.trackpad.maxY)")

        let natural = ((W - 16) / 1.6).rounded(.down)
        let keepsPad = H - 228 - natural >= 120
        pictureRule.expect(l.picture.minX == 8 && l.picture.minY == 8 && l.picture.width == W - 16
                           && (keepsPad ? l.picture.height == natural
                                        : (h >= 348 ? l.trackpad.height == 120 : l.picture.height == 0))
                           && l.picture.height <= natural && l.picture.height >= 0, size,
                           "picture \(str(l.picture)), trackpad \(l.trackpad.height)")

        let b = l.buttons
        let bw = (W - 60) / 5
        buttonsRule.expect(b.count == 5 && b.allSatisfy { near($0.width, bw) && $0.height == 50 && $0.minY == l.row1.minY }
                           && b[0].minX == 14 && near(b[4].maxX, W - 14)
                           && zip(b, b.dropFirst()).allSatisfy { near($1.minX - $0.maxX, 8) } && bw >= 44, size)

        let c = l.caps
        let cw = (W - 68) / 6
        capsRule.expect(c.count == 6 && c.allSatisfy { near($0.width, cw) && $0.height == 44 && $0.minY == l.keys.minY }
                        && c[0].minX == 14 && near(c[5].maxX, W - 14)
                        && zip(c, c.dropFirst()).allSatisfy { near($1.minX - $0.maxX, 8) } && (w < 332 || cw >= 44), size)

        alignRule.expect(b[0].minX == 14 && l.strip.minX + L.stripInset == 14 && c[0].minX == 14 && l.trackpad.minX == 14
                         && near(b[4].maxX, W - 14) && near(c[5].maxX, W - 14) && l.trackpad.maxX == W - 14
                         && l.strip.minX == 6 && l.strip.maxX == W - 6 && l.strip.height == 62, size)

        spanRule.expect(near(l.trackpadSpan, l.trackpad.width / 1.6), size)

        let aa = b[1]
        let fitting = min(36, ((aa.midX - 14) * 2 - 60) / 4)
        rulerRule.expect(near(l.ruler.midX, aa.midX) && l.ruler.minY == l.row1.minY && l.ruler.height == 50
                         && near(l.ruler.width, 4 * l.rulerStep + 60) && l.ruler.minX >= 14 - 0.001 && l.ruler.maxX <= W - 14 + 0.001
                         && near(l.rulerStep, fitting) && l.rulerStep <= 36, size,
                         "ruler \(str(l.ruler)), step \(l.rulerStep)")

        panelsRule.expect(l.drawer.minY == l.row1.maxY + 8 && l.settings.minY == l.row1.maxY + 8
                          && l.drawer.maxY == H - 16 && l.settings.maxY == H - 16
                          && l.drawer.minX == 14 && l.drawer.width == min(380, W - 28)
                          && l.settings.maxX == W - 14 && l.settings.width == min(360, W - 28), size)

        anchorRule.expect(near(l.settingsAnchor.x, l.settings.maxX / W, 0.0001) && near(l.settingsAnchor.y, l.settings.minY / H, 0.0001), size)

        dimRule.expect(l.dim.count == 2 && l.dim[0] == CGRect(x: 0, y: 0, width: W, height: l.row1.minY)
                       && l.dim[1] == CGRect(x: 0, y: l.row1.maxY, width: W, height: H - l.row1.maxY)
                       && !l.dim.contains { $0.intersects(l.row1) }, size)
    }
}
for rule in rules {
    check("grid (\(gridSizes) sizes): \(rule.name)" + (rule.firstFailure.map { " — first failure at \($0)" } ?? ""), rule.firstFailure == nil)
}

// The shortest screens the rule has: the picture gives way first, then nothing.
check("348 pt tall: no picture, a 120 pt trackpad", L(size: CGSize(width: 320, height: 348)).picture.height == 0
      && L(size: CGSize(width: 320, height: 348)).trackpad.height == 120)
check("500 pt tall at 400 wide: the picture gives way (152 of its 240), the trackpad keeps 120",
      L(size: CGSize(width: 400, height: 500)).picture.height == 152 && L(size: CGSize(width: 400, height: 500)).trackpad.height == 120)
check("588 pt tall at 400 wide: the picture whole (240) and the trackpad exactly 120",
      L(size: CGSize(width: 400, height: 588)).picture.height == 240 && L(size: CGSize(width: 400, height: 588)).trackpad.height == 120)
check("a tall screen never makes the picture taller than 16:10",
      L(size: CGSize(width: 402, height: 1400)).picture.height == 241)
check("the size is all it depends on", L(size: pro.container) == L(size: pro.container) && L(size: pro.container) != L(size: proMax.container))

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
