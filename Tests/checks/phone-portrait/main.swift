// H2 (docs/iphone-portrait-plan.md): iOSClient/PhonePortraitLayout.swift on its own, the rectangles of
// a phone held upright. The plan's two tables pinned phone by phone (the layout, then the keyboard:
// row 1 clear of it on every phone, and on the Duo's outer display up to a 326 pt keyboard; and the
// iPhone Duo's real cover, docs/iphone-duo-plan.md), the
// approved mockup's numbers, 320 pt wide, and a grid of every width from 300 to 599 pt and every
// height from the width + 1 to 1,400: everything inside the screen and in order, the gaps, five
// equal buttons and six equal caps across the row, the picture 16:10 unless the trackpad would drop
// under 120 pt, the trackpad's span, the ruler, the drawer and the panel across row 1, the dim.
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
// bottom one. Row 1 is y from its buttons' top to their bottom (the button's width); row 2 likewise;
// row 3 (the cap's width); the trackpad's width and height; the panel room from under row 1 to the
// trackpad's bottom. "Today" (the Duo's outer layout that every iPhone got until now) is in the
// comments.

struct Phone {
    let name: String
    let screen: CGSize
    let inset: CGFloat
    /// The software keyboard's height as the input view shows it (autocorrection off, so no
    /// suggestions bar): measured on the iOS 27 simulators for the 18 Pro Max (320), the 18 Pro and
    /// the 17e (301, both), 2026-09-27; then (docs/larger-picture-plan.md, 2026-10-14) the 15 Pro (301),
    /// the 12 and 13 mini (310) and the SE (233; the plan had taken the classic 216). A keyboard with
    /// a candidate bar (an IME) is about 44 pt taller.
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
let mini = Phone(name: "iPhone 13 mini", screen: CGSize(width: 375, height: 812), inset: 50, keyboard: 310)
let se = Phone(name: "iPhone SE (3rd generation)", screen: CGSize(width: 375, height: 667), inset: 20, keyboard: 233)
let duoOuter = Phone(name: "the Duo's outer display (the harness)", screen: CGSize(width: 500, height: 710), inset: 0, keyboard: nil)
/// The iPhone Duo's cover upright on the iOS 27.1 simulator (docs/iphone-duo-plan.md): 466×678 with its
/// camera's 84 pt strip down the right edge (a side inset, so the container is 382 wide) and no top one.
let duoCover = Phone(name: "the iPhone Duo's cover (iOS 27.1, less its camera's strip)", screen: CGSize(width: 382, height: 678), inset: 0, keyboard: nil)

let table: [Row] = [
    // today: trackpad 243, panel room 351
    Row(phone: proMax, picture: CGSize(width: 424, height: 265), row1: (297, 347), button: 76, row2: (363, 425),
        row3: (435, 479), cap: 62, trackpad: CGSize(width: 412, height: 389), panelRoom: 523),
    // today: 202, 310
    Row(phone: pro, picture: CGSize(width: 386, height: 241), row1: (273, 323), button: 68.4, row2: (339, 401),
        row3: (411, 455), cap: 334.0 / 6, trackpad: CGSize(width: 374, height: 331), panelRoom: 465),
    // today: 192, 300
    Row(phone: fifteenPro, picture: CGSize(width: 377, height: 235), row1: (267, 317), button: 66.6, row2: (333, 395),
        row3: (405, 449), cap: 325.0 / 6, trackpad: CGSize(width: 365, height: 318), panelRoom: 452),
    // today: 194, 302
    Row(phone: seventeenE, picture: CGSize(width: 374, height: 233), row1: (265, 315), button: 66, row2: (331, 393),
        row3: (403, 447), cap: 322.0 / 6, trackpad: CGSize(width: 362, height: 324), panelRoom: 458),
    // today: 177, 285
    Row(phone: mini, picture: CGSize(width: 359, height: 224), row1: (256, 306), button: 63, row2: (322, 384),
        row3: (394, 438), cap: 307.0 / 6, trackpad: CGSize(width: 347, height: 298), panelRoom: 432),
    // today: 119, 227
    Row(phone: se, picture: CGSize(width: 359, height: 224), row1: (256, 306), button: 63, row2: (322, 384),
        row3: (394, 438), cap: 307.0 / 6, trackpad: CGSize(width: 347, height: 183), panelRoom: 317),
    // today: 151, 259
    Row(phone: duoOuter, picture: CGSize(width: 484, height: 302), row1: (334, 384), button: 88, row2: (400, 462),
        row3: (472, 516), cap: 72, trackpad: CGSize(width: 472, height: 168), panelRoom: 302),
    // The real cover (the approved (c1): the phone's arrangement, narrower by the camera's strip):
    // the picture 366×228 the probe photographed.
    Row(phone: duoCover, picture: CGSize(width: 366, height: 228), row1: (260, 310), button: 64.4, row2: (326, 388),
        row3: (398, 442), cap: 314.0 / 6, trackpad: CGSize(width: 354, height: 210), panelRoom: 344),
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
    check("\(n): the drawer and the panel span row 1, from 14 to \(Int(size.width - 14)), Apps' leading edge to Settings' trailing one",
          l.drawer.minX == 14 && l.drawer.width == size.width - 28 && l.settings.minX == 14 && l.settings.width == size.width - 28
            && l.drawer.minX == l.buttons[0].minX && near(l.settings.maxX, l.buttons[4].maxX))
    check("\(n): the ruler 36 a detent, 204 wide, centred on Aa over row 1",
          l.rulerStep == 36 && near(l.ruler, CGRect(x: l.buttons[1].midX - 102, y: row.row1.0, width: 204, height: 50)))
    check("\(n): the trackpad's span is its width ÷ 1.6 (" + String(format: "%.2f", row.trackpad.width / 1.6) + ")",
          near(l.trackpadSpan, row.trackpad.width / 1.6))
    check("\(n): the Settings panel grows from its top-trailing corner",
          near(l.settingsAnchor.x, (size.width - 14) / size.width) && near(l.settingsAnchor.y, (row.row1.1 + 8) / size.height))
    check("\(n): the dim is above and below row 1's buttons",
          l.dim == [CGRect(x: 0, y: 0, width: size.width, height: row.row1.0),
                    CGRect(x: 0, y: row.row1.1, width: size.width, height: size.height - row.row1.1)])
}

// The mockup's own numbers (Noah's approval, its frame()), in the screen's points: on the Pro Max the
// picture 70–335, Apps 359–409, the thumbnails 431–481, the caps 497–541 and the trackpad 551–940,
// 389 pt; on the Pro the trackpad 331 pt (the mockup's 330.75: it does not round the picture down).
check("mockup: Pro Max picture 424×265, buttons 76×50", L(size: proMax.container).picture.size == CGSize(width: 424, height: 265)
      && L(size: proMax.container).buttons.allSatisfy { near($0.width, 76) && $0.height == 50 })
check("mockup: Pro picture 386×241, buttons 68.4×50", L(size: pro.container).picture.size == CGSize(width: 386, height: 241)
      && L(size: pro.container).buttons.allSatisfy { near($0.width, 68.4) && $0.height == 50 })
check("mockup: the button width is (row width − 4 × 8) ÷ 5 on both",
      [proMax, pro].allSatisfy { p in L(size: p.container).buttons.allSatisfy { near($0.width, (p.container.width - 28 - 32) / 5) } })
do {
    let l = L(size: proMax.container), y = proMax.inset
    check("mockup: Pro Max picture 70–335, Apps 359–409, thumbnails 431–481, caps 497–541, trackpad 551–940 (389 pt)",
          y + l.picture.minY == 70 && y + l.picture.maxY == 335 && y + l.row1.minY == 359 && y + l.row1.maxY == 409
            && y + l.strip.minY + 6 == 431 && y + l.strip.maxY - 6 == 481 && y + l.keys.minY == 497 && y + l.keys.maxY == 541
            && y + l.trackpad.minY == 551 && y + l.trackpad.maxY == 940 && l.trackpad.height == 389)
    check("mockup: Pro trackpad 331 pt", L(size: pro.container).trackpad.height == 331)
    check("mockup: 24 pt from the picture to the buttons, 22 from the buttons to the thumbnails",
          l.row1.minY - l.picture.maxY == 24 && (l.strip.minY + 6) - l.row1.maxY == 22)
}

// 320 pt (an iPhone SE or 13 mini with Display Zoom): the buttons 52, the caps 42 (as the Duo's outer
// layout had them), the ruler's step 28 so it stays inside the row.
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
// rows 2 and 3 too on every phone but the SE, whose key row the keyboard covers by 24 pt (its 233 pt
// keyboard, measured on 2026-10-14; the plan took 216 and 7 pt; open question 5 accepts it: a latch
// set before the keyboard comes up still works, and Larger Picture puts the key row above it).
// The trackpad is under it on every phone. The plan assumed keyboards with a suggestions bar (346,
// 336, 260); the input view has none (the heights above), and a keyboard with a candidate bar still
// leaves row 1 clear on every phone. The Duo's outer display (the harness's 500×710, no inset, its
// keyboard unknown): row 1 is clear of a keyboard up to 326 pt, rows 2 and 3 only of one under 248
// and 194 pt, which no iPhone keyboard is (216 and up): only row 1 stays above it there.

struct KeyboardRow { let phone: Phone; let top: CGFloat; let row1: CGFloat; let row2: CGFloat; let row3: CGFloat }
let keyboardTable: [KeyboardRow] = [
    KeyboardRow(phone: proMax, top: 636, row1: 409, row2: 487, row3: 541),
    KeyboardRow(phone: pro, top: 573, row1: 385, row2: 463, row3: 517),
    KeyboardRow(phone: fifteenPro, top: 551, row1: 376, row2: 454, row3: 508),
    KeyboardRow(phone: seventeenE, top: 543, row1: 362, row2: 440, row3: 494),
    KeyboardRow(phone: mini, top: 502, row1: 356, row2: 434, row3: 488),
    KeyboardRow(phone: se, top: 434, row1: 326, row2: 404, row3: 458),
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
for p in [proMax, pro, fifteenPro, seventeenE, mini] {
    let l = L(size: p.container)
    check("\(p.name): rows 2 and 3 clear of the keyboard too (\(Int(p.screen.height - p.keyboard! - p.inset - l.keys.maxY)) pt)",
          p.inset + l.keys.maxY < p.screen.height - p.keyboard!)
}
do {
    let l = L(size: se.container), top = se.screen.height - se.keyboard!
    check("iPhone SE: row 2 clear of the keyboard (30 pt), the key row 24 pt under it (open question 5)",
          top - (se.inset + l.strip.maxY) == 30 && (se.inset + l.keys.maxY) - top == 24)
}
check("measured: 95 pt between row 3 and the keyboard on the 18 Pro Max, 56 on the 18 Pro, 49 on the 17e",
      [(proMax, 95), (pro, 56), (seventeenE, 49)].allSatisfy { p, gap in
          p.screen.height - p.keyboard! - p.inset - L(size: p.container).keys.maxY == CGFloat(gap) })
check("with a candidate bar (44 pt more) row 1 is still clear on every phone",
      [proMax, pro, fifteenPro, seventeenE, mini, se].allSatisfy { p in
          p.inset + L(size: p.container).row1.maxY < p.screen.height - p.keyboard! - 44 })
do {
    let l = L(size: duoOuter.container), h = duoOuter.container.height
    check("the Duo's outer display: row 1 ends at 384, rows 2 and 3 at 462 and 516",
          l.row1.maxY == 384 && l.strip.maxY == 462 && l.keys.maxY == 516)
    check("the Duo's outer display: row 1 clear of a keyboard up to 326 pt; rows 2 and 3 only of one under 248 and 194 pt",
          h - l.row1.maxY == 326 && h - l.strip.maxY == 248 && h - l.keys.maxY == 194)
    check("the Duo's outer display: a 320 pt keyboard (the 18 Pro Max's) leaves row 1 clear by 6 pt and covers rows 2 and 3",
          h - 320 - l.row1.maxY == 6 && l.strip.maxY > h - 320 && l.keys.maxY > h - 320)
    check("the Duo's outer display: the key row under any iPhone keyboard (216 pt and up)", l.keys.maxY > h - 216)
}

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
let gaps = Rule("the gaps: 24 from the picture to row 1's buttons, 16 from them to the strip, 10 to row 3, 10 above the trackpad, 16 under it")
let pictureRule = Rule("the picture at (8, 8), full width less 16, exactly ⌊(W − 16) ÷ 1.6⌋ tall while the trackpad keeps 120 pt, else the trackpad exactly 120 (the picture never below 0)")
let buttonsRule = Rule("five equal buttons, 50 tall, 8 apart, from 14 to W − 14, each at least 44 wide")
let capsRule = Rule("six equal caps, 44 tall, 8 apart, from 14 to W − 14; at least 44 wide from 332 pt up")
let alignRule = Rule("the rows line up: Apps, the first thumbnail, esc and the trackpad at 14; Settings, shift and the trackpad end at W − 14; the strip from 6 to W − 6")
let spanRule = Rule("the trackpad's span is its width ÷ 1.6")
let rulerRule = Rule("the ruler over row 1, centred on Aa, 4 × step + 60 wide, inside the row, 36 a detent where it fits, less where not")
let panelsRule = Rule("the drawer and the panel from 8 under row 1 to the trackpad's bottom, both across row 1, from 14 to W − 14")
let anchorRule = Rule("the panel's anchor is its top-trailing corner")
let dimRule = Rule("the dim covers everything but row 1's buttons, in two pieces")
let menusRule = Rule("row 2 with the Mac's menus: the Menus button under Settings and as wide, 50 tall, centred in the strip's 62; the strip from 6 to 8 before it, a whole 80 pt thumbnail and its 8 pt ends in it")
let gainsRule = Rule("Larger Picture applies (its keyboard the estimate, the switch offered) exactly where its room above the estimated keyboard is taller than today's picture and row 1's six buttons are 44 pt or more; never with the switch off or a hinge")
let sourceRule = Rule("Larger Picture only while a window streams: with the switch on a window gets that keyboard, the Desktop and nothing streaming none (the standard arrangement); the switch off none, and a hinge none, whatever streams")
let rules = [inside, ordered, gaps, pictureRule, buttonsRule, capsRule, alignRule, spanRule, rulerRule, panelsRule, anchorRule, dimRule, menusRule, gainsRule, sourceRule]

func within(_ r: CGRect, _ size: CGSize) -> Bool {
    r.minX >= -0.001 && r.minY >= -0.001 && r.maxX <= size.width + 0.001 && r.maxY <= size.height + 0.001 && r.width >= 0 && r.height >= 0
}

/// What can stream (`StreamClient.active`'s three cases, as Larger Picture's rule reads them).
let streamings: [L.Streaming] = [.nothing, .desktop, .window]
var gridSizes = 0
for w in 300...599 {
    for h in (w + 1)...1400 {
        let size = CGSize(width: w, height: h)
        let W = CGFloat(w), H = CGFloat(h)
        let l = L(size: size)
        gridSizes += 1

        let all = [l.picture, l.row1, l.strip, l.menus, l.stripBesideMenus, l.keys, l.trackpad, l.ruler, l.drawer, l.settings]
            + l.buttons + l.caps + l.dim
        inside.expect(all.allSatisfy { within($0, size) }, size, all.first { !within($0, size) }.map(str) ?? "")

        ordered.expect(l.picture.maxY <= l.row1.minY && l.row1.maxY <= l.strip.minY && l.strip.maxY <= l.keys.minY
                       && l.keys.maxY <= l.trackpad.minY, size)

        gaps.expect(l.row1.minY - l.picture.maxY == 24 && l.strip.minY - l.row1.maxY == 16 && l.keys.minY - l.strip.maxY == 10
                    && l.trackpad.minY - l.keys.maxY == 10 && H - l.trackpad.maxY == 16, size,
                    "\(l.row1.minY - l.picture.maxY), \(l.strip.minY - l.row1.maxY), \(l.keys.minY - l.strip.maxY), \(l.trackpad.minY - l.keys.maxY), \(H - l.trackpad.maxY)")

        let natural = ((W - 16) / 1.6).rounded(.down)
        let keepsPad = H - 240 - natural >= 120
        pictureRule.expect(l.picture.minX == 8 && l.picture.minY == 8 && l.picture.width == W - 16
                           && (keepsPad ? l.picture.height == natural
                                        : (h >= 360 ? l.trackpad.height == 120 : l.picture.height == 0))
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
                          && l.drawer.minX == 14 && l.drawer.maxX == W - 14
                          && l.settings.minX == 14 && l.settings.maxX == W - 14, size)

        anchorRule.expect(near(l.settingsAnchor.x, l.settings.maxX / W, 0.0001) && near(l.settingsAnchor.y, l.settings.minY / H, 0.0001), size)

        dimRule.expect(l.dim.count == 2 && l.dim[0] == CGRect(x: 0, y: 0, width: W, height: l.row1.minY)
                       && l.dim[1] == CGRect(x: 0, y: l.row1.maxY, width: W, height: H - l.row1.maxY)
                       && !l.dim.contains { $0.intersects(l.row1) }, size)

        menusRule.expect(near(l.menus.minX, b[4].minX) && near(l.menus.width, b[4].width) && l.menus.height == 50
                         && near(l.menus.midY, l.strip.midY) && l.stripBesideMenus.minX == l.strip.minX
                         && l.stripBesideMenus.minY == l.strip.minY && l.stripBesideMenus.height == l.strip.height
                         && near(l.menus.minX - l.stripBesideMenus.maxX, 8) && l.stripBesideMenus.width - 16 >= 80, size,
                         "menus \(str(l.menus)), strip \(str(l.stripBesideMenus))")

        let estimate = L.keyboardHeight(for: size)
        let applies = L(size: size, keyboard: estimate).picture.height > l.picture.height && (W - 68) / 6 >= 44
        let given = L.keyboard(for: size, largerPicture: true, foldable: false)
        gainsRule.expect(given == (applies ? estimate : nil) && L.offersLargerPicture(screen: size) == applies
                         && L.keyboard(for: size, largerPicture: false, foldable: false) == nil
                         && L.keyboard(for: size, largerPicture: true, foldable: true) == nil, size,
                         "estimate \(estimate), given \(String(describing: given)), applies \(applies)")

        // What StreamScreen hands the layout: the rule's answer for the switch and what streams, placed.
        func placed(_ on: Bool, _ streaming: L.Streaming, hinge: Bool = false) -> CGFloat? {
            L.keyboard(for: size, largerPicture: L.largerPicture(switchOn: on, streaming: streaming), foldable: hinge)
        }
        sourceRule.expect(placed(true, .window) == given && placed(true, .desktop) == nil && placed(true, .nothing) == nil
                          && streamings.allSatisfy { placed(false, $0) == nil && placed(true, $0, hinge: true) == nil }, size,
                          "window \(String(describing: placed(true, .window))), Desktop \(String(describing: placed(true, .desktop))), nothing \(String(describing: placed(true, .nothing)))")
    }
}
for rule in rules {
    check("grid (\(gridSizes) sizes): \(rule.name)" + (rule.firstFailure.map { " — first failure at \($0)" } ?? ""), rule.firstFailure == nil)
}

// The shortest screens the rule has: the picture gives way first, then nothing. The shortest phone is
// an iPhone SE with Display Zoom (320×568, 320×548 under its status bar): its picture gives way by
// 2 pt, to 188, and its trackpad is the least, 120.
check("iPhone SE with Display Zoom (320×548): the picture 304×188, the trackpad 292×120",
      L(size: CGSize(width: 320, height: 548)).picture.size == CGSize(width: 304, height: 188)
        && L(size: CGSize(width: 320, height: 548)).trackpad.size == CGSize(width: 292, height: 120))
check("360 pt tall: no picture, a 120 pt trackpad", L(size: CGSize(width: 320, height: 360)).picture.height == 0
      && L(size: CGSize(width: 320, height: 360)).trackpad.height == 120)
check("500 pt tall at 400 wide: the picture gives way (140 of its 240), the trackpad keeps 120",
      L(size: CGSize(width: 400, height: 500)).picture.height == 140 && L(size: CGSize(width: 400, height: 500)).trackpad.height == 120)
check("600 pt tall at 400 wide: the picture whole (240) and the trackpad exactly 120",
      L(size: CGSize(width: 400, height: 600)).picture.height == 240 && L(size: CGSize(width: 400, height: 600)).trackpad.height == 120)
check("a tall screen never makes the picture taller than 16:10",
      L(size: CGSize(width: 402, height: 1400)).picture.height == 241)
// Row 2 with the Mac's menus (docs/menu-bar-plan.md §7.5), on the narrowest and a common phone.
do {
    let l = L(size: se.container)
    check("iPhone SE (375 wide): the Menus button \(str(l.menus)) under Settings, the strip 6 to \(l.stripBesideMenus.maxX): two whole thumbnails and more",
          near(l.menus, CGRect(x: 298, y: l.strip.minY + 6, width: 63, height: 50)) && near(l.stripBesideMenus.width, 284)
            && (l.stripBesideMenus.width - 16) / (80 + 12) >= 2.9)
    let w320 = L(size: CGSize(width: 320, height: 548))
    check("320 pt (Display Zoom): the button 52 wide at 254, the strip 240 (two whole thumbnails)",
          near(w320.menus.minX, 254) && near(w320.menus.width, 52) && near(w320.stripBesideMenus.width, 240)
            && (w320.stripBesideMenus.width - 16) / (80 + 12) >= 2.4)
}
check("the size is all it depends on", L(size: pro.container) == L(size: pro.container) && L(size: pro.container) != L(size: proMax.container))

// MARK: - Larger Picture (docs/larger-picture-plan.md)
//
// With the switch on while a window streams (the Desktop and nothing streaming keep today's
// arrangement: `largerPicture(switchOn:streaming:)`, below the plan's table) and the keyboard's
// height known, the thumbnails' row goes and the picture's
// room is every point that keeps the key row 10 pt above the software keyboard: the container less
// the keyboard less 152 pt; the trackpad is the keyboard's footprint; row 1 gets the Menus button
// after Apps while the Mac sent menus; the frame takes the picture's own shape inside the room, from
// its top; the trackpad's span follows that shape. It applies only where the room is taller than
// today's picture and row 1's six buttons are 44 pt or more (not at Display Zoom's 320 pt).

// Today's arrangement is what it was: no keyboard is the default, and nothing of the switch shows in it.
for p in [proMax, pro, fifteenPro, seventeenE, mini, se, duoOuter, duoCover] {
    let l = L(size: p.container)
    let videos = [CGSize.zero, CGSize(width: 3024, height: 1964), CGSize(width: 848, height: 844), CGSize(width: 1000, height: 2000)]
    check("\(p.name): without the switch the layout is today's (no keyboard), its frame the picture whatever the video, its span the width ÷ 1.6, row 1 the same beside the Mac's menus",
          l == L(size: p.container, keyboard: nil) && l.keyboard == nil && !l.largerPicture
            && videos.allSatisfy { l.pane(video: $0) == l.picture && l.trackpadSpan(video: $0) == l.trackpadSpan }
            && l.buttonsBesideMenus == l.buttons && l.rulerBesideMenus == l.ruler && l.rulerStepBesideMenus == l.rulerStep
            && l.strip.height == 62)
}

// The keyboard's height, from the stream screen's shape and width as measured on the iOS 27
// simulators (2026-10-14): 233 with a Home button (under 1.9 times as tall as wide); with Face ID
// 320 from 414 pt wide, 301 from 390, 310 from 375, and the tallest, 320, narrower (Display Zoom).
struct Estimate { let name: String; let container: CGSize; let keyboard: CGFloat }
let estimates: [Estimate] = [
    Estimate(name: "18 Pro Max", container: proMax.container, keyboard: 320),
    Estimate(name: "15 Pro Max, 16 Plus (430×932, inset 59)", container: CGSize(width: 430, height: 873), keyboard: 320),
    Estimate(name: "14 Plus (428×926, inset 47)", container: CGSize(width: 428, height: 879), keyboard: 320),
    Estimate(name: "Air (420×912, inset 68)", container: CGSize(width: 420, height: 844), keyboard: 320),
    Estimate(name: "11 Pro Max (414×896, inset 44)", container: CGSize(width: 414, height: 852), keyboard: 320),
    Estimate(name: "11 (414×896, inset 48)", container: CGSize(width: 414, height: 848), keyboard: 320),
    Estimate(name: "18 Pro", container: pro.container, keyboard: 301),
    Estimate(name: "15 Pro", container: fifteenPro.container, keyboard: 301),
    Estimate(name: "17e and 16e", container: seventeenE.container, keyboard: 301),
    Estimate(name: "12 and 13 mini", container: mini.container, keyboard: 310),
    Estimate(name: "11 Pro (375×812, inset 44; its own 301)", container: CGSize(width: 375, height: 768), keyboard: 310),
    Estimate(name: "SE", container: se.container, keyboard: 233),
    Estimate(name: "SE with Display Zoom (320×568, inset 20)", container: CGSize(width: 320, height: 548), keyboard: 233),
    Estimate(name: "a Face ID phone with Display Zoom (320×693, inset 48)", container: CGSize(width: 320, height: 645), keyboard: 320),
    Estimate(name: "a Pro Max with Display Zoom (375×812, inset 50)", container: CGSize(width: 375, height: 762), keyboard: 310),
    Estimate(name: "the Duo's cover (382×678, no top inset)", container: duoCover.container, keyboard: 233),
]
for e in estimates {
    check("the keyboard estimated on the \(e.name), \(Int(e.container.width))×\(Int(e.container.height)): \(Int(e.keyboard)) pt (\(L.keyboardHeight(for: e.container)))",
          L.keyboardHeight(for: e.container) == e.keyboard)
}
check("the estimate's edges: 1.9 times as tall reads Face ID, a hair less a Home button; 414, 390 and 375 pt wide begin their keyboards; no width a Home button",
      L.keyboardHeight(for: CGSize(width: 400, height: 760)) == 301 && L.keyboardHeight(for: CGSize(width: 400, height: 759.9)) == 233
        && L.keyboardHeight(for: CGSize(width: 414, height: 900)) == 320 && L.keyboardHeight(for: CGSize(width: 413, height: 900)) == 301
        && L.keyboardHeight(for: CGSize(width: 390, height: 800)) == 301 && L.keyboardHeight(for: CGSize(width: 389, height: 800)) == 310
        && L.keyboardHeight(for: CGSize(width: 375, height: 760)) == 310 && L.keyboardHeight(for: CGSize(width: 374, height: 760)) == 320
        && L.keyboardHeight(for: .zero) == 233)
check("the switch off: no keyboard (today's arrangement), on a phone or a Duo",
      L.keyboard(for: proMax.container, largerPicture: false, foldable: false) == nil
        && L.keyboard(for: proMax.container, largerPicture: false, foldable: true) == nil)
check("the switch on, the iPhone Duo (a hinge): no keyboard, the cover left as it is",
      L.keyboard(for: duoCover.container, largerPicture: true, foldable: true) == nil
        && L.keyboard(for: proMax.container, largerPicture: true, foldable: true) == nil)
// Larger Picture only where it is larger (the review of 2026-10-14): the room taller than today's
// picture and row 1's six buttons 44 pt or more. Display Zoom at 320 pt wide (the SE, the minis and
// the 6.1-inch iPhones) has neither: no keyboard there, today's arrangement and no switch.
let zoomed320 = ["SE with Display Zoom (320×568, inset 20)", "a Face ID phone with Display Zoom (320×693, inset 48)"]
check("the switch on, a phone without a hinge: its estimate, but where Display Zoom makes it 320 pt wide",
      estimates.allSatisfy { e in
          L.keyboard(for: e.container, largerPicture: true, foldable: false) == (zoomed320.contains(e.name) ? nil : e.keyboard) })

// The plan's table, phone by phone: the room (and today's picture), row 1, the key row, the trackpad
// (its top the keyboard's), the panels' room, and the frame of a window of a 14-inch MacBook Pro's
// Desktop's shape (3024×1964, 1.54:1; the Desktop itself keeps the standard arrangement, below).
struct Larger {
    let phone: Phone
    let room: CGSize, today: CGFloat
    let row1: (CGFloat, CGFloat), keys: (CGFloat, CGFloat)
    let trackpad: CGSize, padTop: CGFloat, panelRoom: CGFloat
    let desktop: CGSize
}
let fifteenProMax = Phone(name: "iPhone 15 Pro Max (and 16 Plus)", screen: CGSize(width: 430, height: 932), inset: 59, keyboard: 320)
let air = Phone(name: "iPhone Air", screen: CGSize(width: 420, height: 912), inset: 68, keyboard: 320)
let elevenProMax = Phone(name: "iPhone 11 Pro Max", screen: CGSize(width: 414, height: 896), inset: 44, keyboard: 320)
/// Display Zoom's phones, their keyboards the estimate's (none of them measured): the 6.7-inch ones
/// zoom to 375×812, a 6.9-inch Pro Max (the 16's on) to 402×874, both larger with the switch; the SE,
/// the minis and the 6.1-inch ones to 320 pt wide, where Larger Picture does not apply.
let seZoom = Phone(name: "iPhone SE with Display Zoom", screen: CGSize(width: 320, height: 568), inset: 20, keyboard: 233)
let sixOneZoom = Phone(name: "a 6.1-inch iPhone with Display Zoom", screen: CGSize(width: 320, height: 693), inset: 48, keyboard: 320)
let sixSevenZoom = Phone(name: "a 6.7-inch iPhone with Display Zoom", screen: CGSize(width: 375, height: 812), inset: 50, keyboard: 310)
let proMaxZoom = Phone(name: "a 6.9-inch Pro Max with Display Zoom", screen: CGSize(width: 402, height: 874), inset: 62, keyboard: 301)
let largerTable: [Larger] = [
    Larger(phone: proMax, room: CGSize(width: 424, height: 422), today: 265, row1: (454, 504), keys: (520, 564),
           trackpad: CGSize(width: 412, height: 304), padTop: 574, panelRoom: 366, desktop: CGSize(width: 424, height: 275)),
    Larger(phone: fifteenProMax, room: CGSize(width: 414, height: 401), today: 258, row1: (433, 483), keys: (499, 543),
           trackpad: CGSize(width: 402, height: 304), padTop: 553, panelRoom: 366, desktop: CGSize(width: 414, height: 268)),
    Larger(phone: air, room: CGSize(width: 404, height: 372), today: 252, row1: (404, 454), keys: (470, 514),
           trackpad: CGSize(width: 392, height: 304), padTop: 524, panelRoom: 366, desktop: CGSize(width: 404, height: 262)),
    Larger(phone: elevenProMax, room: CGSize(width: 398, height: 380), today: 248, row1: (412, 462), keys: (478, 522),
           trackpad: CGSize(width: 386, height: 304), padTop: 532, panelRoom: 366, desktop: CGSize(width: 398, height: 258)),
    Larger(phone: pro, room: CGSize(width: 386, height: 359), today: 241, row1: (391, 441), keys: (457, 501),
           trackpad: CGSize(width: 374, height: 285), padTop: 511, panelRoom: 347, desktop: CGSize(width: 386, height: 250)),
    Larger(phone: fifteenPro, room: CGSize(width: 377, height: 340), today: 235, row1: (372, 422), keys: (438, 482),
           trackpad: CGSize(width: 365, height: 285), padTop: 492, panelRoom: 347, desktop: CGSize(width: 377, height: 244)),
    Larger(phone: seventeenE, room: CGSize(width: 374, height: 344), today: 233, row1: (376, 426), keys: (442, 486),
           trackpad: CGSize(width: 362, height: 285), padTop: 496, panelRoom: 347, desktop: CGSize(width: 374, height: 242)),
    Larger(phone: mini, room: CGSize(width: 359, height: 300), today: 224, row1: (332, 382), keys: (398, 442),
           trackpad: CGSize(width: 347, height: 294), padTop: 452, panelRoom: 356, desktop: CGSize(width: 359, height: 233)),
    Larger(phone: se, room: CGSize(width: 359, height: 262), today: 224, row1: (294, 344), keys: (360, 404),
           trackpad: CGSize(width: 347, height: 217), padTop: 414, panelRoom: 279, desktop: CGSize(width: 359, height: 233)),
    Larger(phone: sixSevenZoom, room: CGSize(width: 359, height: 300), today: 224, row1: (332, 382), keys: (398, 442),
           trackpad: CGSize(width: 347, height: 294), padTop: 452, panelRoom: 356, desktop: CGSize(width: 359, height: 233)),
    Larger(phone: proMaxZoom, room: CGSize(width: 386, height: 359), today: 241, row1: (391, 441), keys: (457, 501),
           trackpad: CGSize(width: 374, height: 285), padTop: 511, panelRoom: 347, desktop: CGSize(width: 386, height: 250)),
]
let macBookDesktop = CGSize(width: 3024, height: 1964)
for row in largerTable {
    let size = row.phone.container, k = row.phone.keyboard!
    let l = L(size: size, keyboard: L.keyboard(for: size, largerPicture: true, foldable: false))
    let n = "Larger Picture, \(row.phone.name) (\(Int(size.width))×\(Int(size.height)), keyboard \(Int(k)))"
    check("\(n): the keyboard estimated as measured", l.keyboard == k && l.largerPicture)
    check("\(n): the room \(Int(row.room.width))×\(Int(row.room.height)) at (8, 8), against today's \(Int(row.today)) pt",
          l.picture == CGRect(x: 8, y: 8, width: row.room.width, height: row.room.height) && L(size: size).picture.height == row.today)
    check("\(n): row 1 at \(Int(row.row1.0))–\(Int(row.row1.1)), 24 pt under the room",
          l.row1 == CGRect(x: 14, y: row.row1.0, width: size.width - 28, height: 50) && l.row1.minY - l.picture.maxY == 24)
    check("\(n): no thumbnails' row", l.strip.height == 0 && l.stripBesideMenus.height == 0)
    check("\(n): the key row at \(Int(row.keys.0))–\(Int(row.keys.1)), 16 pt under row 1's buttons",
          l.keys == CGRect(x: 14, y: row.keys.0, width: size.width - 28, height: 44) && l.keys.minY - l.row1.maxY == 16)
    check("\(n): the key row 10 pt above the keyboard's top (\(Int(size.height - k)) in the stream screen, \(Int(row.phone.screen.height - k)) on the screen)",
          size.height - k - l.keys.maxY == 10 && row.phone.screen.height - k - (row.phone.inset + l.keys.maxY) == 10)
    check("\(n): the trackpad \(Int(row.trackpad.width))×\(Int(row.trackpad.height)) from \(Int(row.padTop)): the keyboard's footprint, 16 pt off the bottom",
          l.trackpad == CGRect(x: 14, y: row.padTop, width: row.trackpad.width, height: row.trackpad.height)
            && l.trackpad.minY == size.height - k && l.trackpad.maxY == size.height - 16)
    check("\(n): the panel gets \(Int(row.panelRoom)) pt (the keyboard + 46), from 8 under row 1, across it",
          l.settings == CGRect(x: 14, y: row.row1.1 + 8, width: size.width - 28, height: row.panelRoom) && row.panelRoom == k + 46)
    // The review of 2026-10-14: under row 1 a keyboard up left only the drawer's 62 pt of padding and
    // search field in view. The drawer opens above row 1 instead, over the room, to 8 pt above row 1.
    check("\(n): the drawer above row 1, from 8 to 8 above it (\(Int(row.room.height + 16)) pt: the room + 16), across it",
          l.drawer == CGRect(x: 14, y: 8, width: size.width - 28, height: row.row1.0 - 16) && l.drawer.height == row.room.height + 16)
    check("\(n): the whole drawer clear of the keyboard, by \(Int(size.height - k - l.drawer.maxY)) pt (a candidate bar's 44 more too)",
          l.drawer.maxY == size.height - k - 128 && l.drawer.maxY < size.height - k - 44)
    check("\(n): a window of the Desktop's shape: its frame \(Int(row.desktop.width))×\(Int(row.desktop.height))",
          l.pane(video: macBookDesktop).size == row.desktop)
    check("\(n): the dim is above and below row 1's buttons",
          l.dim == [CGRect(x: 0, y: 0, width: size.width, height: row.row1.0),
                    CGRect(x: 0, y: row.row1.1, width: size.width, height: size.height - row.row1.1)])
    check("\(n): the panel grows from its top-trailing corner",
          near(l.settingsAnchor.x, (size.width - 14) / size.width) && near(l.settingsAnchor.y, (row.row1.1 + 8) / size.height))
    check("\(n): with a candidate bar (44 pt more) row 1 is still clear of the keyboard (\(Int(size.height - k - 44 - l.row1.maxY)) pt)",
          l.row1.maxY < size.height - k - 44)
}
// The review's numbers (2026-10-14): a drawer under Larger Picture's row 1, which ends 70 pt above the
// keyboard, kept 62 pt in view above the keyboard on every phone (its padding and search field), where
// today's keeps 219, 167, 138 and 100; the drawer above row 1 has all of its 438, 356, 316 and 278.
for (p, today, drawer) in [(proMax, CGFloat(219), CGFloat(438)), (fifteenPro, 167, 356), (mini, 138, 316), (se, 100, 278)] {
    let c = p.container, top = c.height - p.keyboard!
    let larger = L(size: c, keyboard: p.keyboard!), standard = L(size: c)
    check("\(p.name): with the keyboard up, today's drawer keeps \(Int(today)) pt in view; under Larger Picture's row 1 one would keep 62; above it, all \(Int(drawer))",
          top - standard.drawer.minY == today && top - (larger.row1.maxY + 8) == 62
            && larger.drawer.height == drawer && larger.drawer.maxY < top)
}
check("Larger Picture is larger on every phone it applies to (all but those Display Zoom makes 320 pt wide)",
      largerTable.allSatisfy { r in r.room.height > r.today && L.largerPictureGains(r.phone.container, keyboard: r.phone.keyboard!) })
// Display Zoom at 320 pt wide (the review of 2026-10-14): the keyboard rule would make the picture
// smaller, a 6.1-inch iPhone's 304×173 against today's 304×190 (a picture of the Desktop's shape 266×173)
// and the zoomed SE's 304×163 against 304×188, with six buttons of 42 pt; so no keyboard, today's
// arrangement, and the switch not offered, upright or on its side.
for (p, room, today) in [(sixOneZoom, CGFloat(173), CGFloat(190)), (seZoom, 163, 188)] {
    let c = p.container
    let would = L(size: c, keyboard: p.keyboard!)
    check("\(p.name) (\(Int(c.width))×\(Int(c.height))): above its \(Int(p.keyboard!)) pt keyboard the room would be \(Int(room)) against today's \(Int(today)), six buttons 42 wide",
          would.picture.height == room && L(size: c).picture.height == today && near(would.menus.width, 42) && L.keyboardHeight(for: c) == p.keyboard!)
    check("\(p.name): so Larger Picture does not apply: no keyboard, the layout today's, no switch offered",
          !L.largerPictureGains(c, keyboard: p.keyboard!) && L.keyboard(for: c, largerPicture: true, foldable: false) == nil
            && L(size: c, keyboard: L.keyboard(for: c, largerPicture: true, foldable: false)) == L(size: c)
            && !L.offersLargerPicture(screen: c) && !L.offersLargerPicture(screen: CGSize(width: p.screen.height, height: p.screen.width)))
}
check("a 6.1-inch iPhone with Display Zoom and a 44 pt inset (320×649): 177 against 190, not offered either",
      L(size: CGSize(width: 320, height: 649), keyboard: 320).picture.height == 177 && L.keyboard(for: CGSize(width: 320, height: 649), largerPicture: true, foldable: false) == nil)
check("each condition alone keeps it off: a 320 pt screen tall enough for a larger room still has 42 pt buttons (320×700: 228 against 190); a 400 pt one whose room is no taller than today's picture (400×710 above 320: 238 against 240)",
      L(size: CGSize(width: 320, height: 700), keyboard: 320).picture.height == 228 && !L.largerPictureGains(CGSize(width: 320, height: 700), keyboard: 320)
        && L(size: CGSize(width: 400, height: 710), keyboard: 320).picture.height == 238 && L(size: CGSize(width: 400, height: 710)).picture.height == 240
        && !L.largerPictureGains(CGSize(width: 400, height: 710), keyboard: 320)
        && L.largerPictureGains(CGSize(width: 400, height: 713), keyboard: 320) && L.largerPictureGains(CGSize(width: 332, height: 900), keyboard: 320)
        && !L.largerPictureGains(CGSize(width: 331, height: 900), keyboard: 320))
// The Settings panel's switch, on every iPhone held either way: sideways the stream screen is the
// screen less a notch's inset at each side (none on an SE), so the upright height it is judged on is
// short by one inset (or long by the SE's status bar); the answer is the upright one on every phone,
// for every side inset a notch has (0 to 70 pt).
let everyPhone: [(Phone, [CGFloat])] = [(proMax, Array(stride(from: 0, through: 70, by: 1))), (pro, Array(stride(from: 0, through: 70, by: 1))),
    (fifteenPro, Array(stride(from: 0, through: 70, by: 1))), (seventeenE, Array(stride(from: 0, through: 70, by: 1))),
    (mini, Array(stride(from: 0, through: 70, by: 1))), (se, [0]), (fifteenProMax, Array(stride(from: 0, through: 70, by: 1))),
    (air, Array(stride(from: 0, through: 70, by: 1))), (elevenProMax, Array(stride(from: 0, through: 70, by: 1))),
    (seZoom, [0]), (sixOneZoom, Array(stride(from: 0, through: 70, by: 1))), (sixSevenZoom, Array(stride(from: 0, through: 70, by: 1))),
    (proMaxZoom, Array(stride(from: 0, through: 70, by: 1)))]
for (p, insets) in everyPhone {
    let upright = L.offersLargerPicture(screen: p.container)
    let expected = p.name != seZoom.name && p.name != sixOneZoom.name
    check("\(p.name): the switch " + (expected ? "offered" : "not offered") + " upright, and on its side with any of \(insets.count) side insets",
          upright == expected && insets.allSatisfy { side in
              L.offersLargerPicture(screen: CGSize(width: p.screen.height - 2 * side, height: p.screen.width)) == expected })
}
check("the triage's numbers: the 15 Pro 377×235 → 377×340, the 18 Pro Max 424×265 → 424×422, the SE 359×224 → 359×279 above the 216 pt keyboard it assumed (359×262 above the 233 measured)",
      L(size: fifteenPro.container, keyboard: 301).picture.size == CGSize(width: 377, height: 340)
        && L(size: proMax.container, keyboard: 320).picture.size == CGSize(width: 424, height: 422)
        && L(size: se.container, keyboard: 216).picture.size == CGSize(width: 359, height: 279)
        && L(size: se.container, keyboard: 233).picture.size == CGSize(width: 359, height: 262))
check("the keyboard and the switch are inputs: another keyboard, another layout",
      L(size: pro.container, keyboard: 301) != L(size: pro.container) && L(size: pro.container, keyboard: 301) != L(size: pro.container, keyboard: 320))

// Larger Picture only while a window streams (Noah, 2026-10-15, on his iPhone 15 Pro: "when in Desktop
// mode, there is negative space on the bottom, seemingly because of the Mac aspect ratio"). Aa never
// resizes the Desktop, so the room's extra height could only be black under it: on the 18 Pro Max its
// 424×275 frame left 147 pt of the 424×422 room black, on the 15 Pro 96 of 340. The Desktop and
// nothing streaming (connecting; a window closed or off the Mac's list for a moment; a pick that
// failed) keep the standard arrangement with the switch on: every rect, the viewport (the picture),
// the frame and the span are the switch off's. A window keeps Larger Picture as before. The rule,
// then what StreamScreen does with it: `keyboard(for:largerPicture:foldable:)` given its answer.
check("the rule: Larger Picture in effect with the switch on while a window streams, and only then",
      L.largerPicture(switchOn: true, streaming: .window) && !L.largerPicture(switchOn: true, streaming: .desktop)
        && !L.largerPicture(switchOn: true, streaming: .nothing) && streamings.allSatisfy { !L.largerPicture(switchOn: false, streaming: $0) })
/// The arrangement StreamScreen draws on a phone held upright for the switch and what streams.
func arrangement(_ size: CGSize, switchOn: Bool, streaming: L.Streaming, hinge: Bool = false) -> L {
    L(size: size, keyboard: L.keyboard(for: size, largerPicture: L.largerPicture(switchOn: switchOn, streaming: streaming), foldable: hinge))
}
let pictureShapes = [CGSize.zero, macBookDesktop, CGSize(width: 1512, height: 949), CGSize(width: 2560, height: 1080),
                     CGSize(width: 848, height: 844), CGSize(width: 1000, height: 2000)]
for row in largerTable {
    let c = row.phone.container
    let off = L(size: c), larger = L(size: c, keyboard: row.phone.keyboard!)
    let n = "\(row.phone.name) (\(Int(c.width))×\(Int(c.height)))"
    for source in [L.Streaming.desktop, .nothing] {
        let on = arrangement(c, switchOn: true, streaming: source)
        let what = source == .desktop ? "the Desktop" : "nothing"
        check("\(n), the switch on while \(what) streams: the switch off's arrangement, every rect (the picture \(Int(off.picture.width))×\(Int(off.picture.height)), the thumbnails, the trackpad \(Int(off.trackpad.height)) pt)",
              on == off && on == arrangement(c, switchOn: false, streaming: source) && on.keyboard == nil && !on.largerPicture
                && on.strip.height == 62 && on.buttonsBesideMenus == off.buttons && on.drawer == off.drawer)
        check("\(n), the switch on while \(what) streams: the viewport the 16:10 pane, the frame the pane and the span the width ÷ 1.6, whatever the picture's shape",
              on.picture.size == off.picture.size && pictureShapes.allSatisfy { on.pane(video: $0) == off.picture && on.trackpadSpan(video: $0) == off.trackpadSpan })
    }
    let window = arrangement(c, switchOn: true, streaming: .window)
    check("\(n), the switch on while a window streams: Larger Picture as before, the viewport its room (\(Int(row.room.width))×\(Int(row.room.height))), every rect, frame and span the same",
          window == larger && window.picture.size == row.room
            && pictureShapes.allSatisfy { window.pane(video: $0) == larger.pane(video: $0) && window.trackpadSpan(video: $0) == larger.trackpadSpan(video: $0) })
    check("\(n), the switch off while a window streams: the standard arrangement", arrangement(c, switchOn: false, streaming: .window) == off)
    // A switch between the Desktop and a window changes the arrangement, and with it the viewport (the
    // picture's size): one new viewport each way, as a rotation sends.
    check("\(n): the viewport \(Int(off.picture.width))×\(Int(off.picture.height)) with the Desktop, \(Int(row.room.width))×\(Int(row.room.height)) with a window",
          arrangement(c, switchOn: true, streaming: .desktop).picture.size == off.picture.size && window.picture.size != off.picture.size)
}
do {
    // Noah's finding, in numbers: the branch's Larger Picture drew a 14-inch MacBook Pro's Desktop
    // (3024×1964) at the room's width, from its top, with black under it in the room.
    for (p, frame, room, black) in [(fifteenPro, CGSize(width: 377, height: 244), CGSize(width: 377, height: 340), CGFloat(96)),
                                    (proMax, CGSize(width: 424, height: 275), CGSize(width: 424, height: 422), CGFloat(147))] {
        let c = p.container, before = L(size: c, keyboard: p.keyboard!), now = arrangement(c, switchOn: true, streaming: .desktop)
        check("\(p.name): before, the Desktop \(Int(frame.width))×\(Int(frame.height)) at the top of a \(Int(room.width))×\(Int(room.height)) room, \(Int(black)) pt of black under it; now the 16:10 pane, \(Int(now.picture.width))×\(Int(now.picture.height)), with the thumbnails",
              before.pane(video: macBookDesktop).size == frame && before.picture.size == room && room.height - frame.height == black
                && now == L(size: c) && now.pane(video: macBookDesktop) == L(size: c).picture && now.strip.height == 62)
    }
}
check("the iPhone Duo's cover as the branch left it: the switch on gives it no keyboard whatever streams (a hinge), the standard arrangement",
      streamings.allSatisfy { arrangement(duoCover.container, switchOn: true, streaming: $0, hinge: true) == L(size: duoCover.container)
                                && arrangement(proMax.container, switchOn: true, streaming: $0, hinge: true) == L(size: proMax.container) })
check("the switch is offered whatever streams: it is judged as for a window (the 18 Pro Max and the 15 Pro offer it, Display Zoom's 320 pt does not)",
      L.offersLargerPicture(screen: proMax.container) && L.offersLargerPicture(screen: fifteenPro.container)
        && !L.offersLargerPicture(screen: sixOneZoom.container))

// Row 1 beside the Mac's menus: six equal buttons, Menus after Apps (the landscape bar's order with
// the strip gone); the ruler on that row's Aa, 36 a detent on every phone.
do {
    let l = L(size: proMax.container, keyboard: 320), six = (proMax.container.width - 68) / 6
    let b = l.buttonsBesideMenus
    check("Pro Max: six buttons of \(six) (62): Apps at 14, Menus at 84, Aa, Keyboard, Desktop, Settings to 426",
          near(six, 62) && b.count == 5 && near(b[0], CGRect(x: 14, y: 454, width: 62, height: 50)) && near(l.menus, CGRect(x: 84, y: 454, width: 62, height: 50))
            && near(b[1].minX, 154) && near(b[2].minX, 224) && near(b[3].minX, 294) && near(b[4].minX, 364) && near(b[4].maxX, 426))
    check("Pro Max: the ruler on that Aa, 204 wide, 36 a detent", near(l.rulerStepBesideMenus, 36)
          && near(l.rulerBesideMenus, CGRect(x: b[1].midX - 102, y: 454, width: 204, height: 50)))
    let w320 = L(size: CGSize(width: 320, height: 548), keyboard: 233)
    check("320 pt: six buttons of 42, the ruler still 36 a detent (Aa is third); under 44, so Larger Picture never draws it",
          w320.buttonsBesideMenus.allSatisfy { near($0.width, 42) } && near(w320.menus.width, 42) && near(w320.rulerStepBesideMenus, 36)
            && near(w320.rulerStep, 28) && !L.largerPictureGains(CGSize(width: 320, height: 548), keyboard: 233))
    check("the narrowest phone Larger Picture applies to (375 pt: the SE, the minis, the 6.7-inch ones zoomed) has six of 51.2",
          near(L(size: se.container, keyboard: 233).menus.width, 307.0 / 6) && near(L(size: mini.container, keyboard: 310).menus.width, 307.0 / 6))
}

// The frame: the picture's own shape inside the room, from its top (the 18 Pro Max's room, 424×422).
do {
    let l = L(size: proMax.container, keyboard: 320)
    check("before a frame: 16:10, 424×265 from the top", l.pane(video: .zero) == CGRect(x: 8, y: 8, width: 424, height: 265))
    check("the test pattern (1512×949): 424×266", l.pane(video: CGSize(width: 1512, height: 949)) == CGRect(x: 8, y: 8, width: 424, height: 266))
    check("a window the Mac fitted to the room (848×844 at 2x): the whole room",
          l.pane(video: CGSize(width: 848, height: 844)) == l.picture && l.pane(video: CGSize(width: 1272, height: 1266)) == l.picture)
    check("a picture within a hundredth of a point of the room fills it (424 × 84,399 ÷ 84,800 = 421.995)",
          l.pane(video: CGSize(width: 84800, height: 84399)) == l.picture)
    check("a wide window (21:9, 2560×1080): 424×178 from the top", l.pane(video: CGSize(width: 2560, height: 1080)) == CGRect(x: 8, y: 8, width: 424, height: 178))
    check("a square window: as tall as the room, 422×422, centred across it", l.pane(video: CGSize(width: 1000, height: 1000)) == CGRect(x: 9, y: 8, width: 422, height: 422))
    check("a window twice as tall as wide: 211×422, centred", l.pane(video: CGSize(width: 1000, height: 2000)) == CGRect(x: 114, y: 8, width: 211, height: 422))
    check("the trackpad's span with a 16:10 picture is the width ÷ 1.6, as today", near(l.trackpadSpan(video: .zero), 412 / 1.6) && near(l.trackpadSpan, 412 / 1.6))
    check("…with the window fitted to the room: 412 × 422 ÷ 424 (410.06), as far down as across",
          near(l.trackpadSpan(video: CGSize(width: 848, height: 844)), 412.0 * 422 / 424))
    check("…with a window twice as tall as wide: 824", near(l.trackpadSpan(video: CGSize(width: 1000, height: 2000)), 824))
    check("…with a window of the Desktop's shape (424×275): 267.2", near(l.trackpadSpan(video: macBookDesktop), 412.0 * 275 / 424))
}

// Fractions and edges: the room in whole points, the trackpad from the keyboard's exact top; a keyboard
// shorter than the least trackpad and its margin is taken as 136 pt; a screen too short leaves no room.
do {
    let half = L(size: pro.container, keyboard: 300.5)
    check("a keyboard of 300.5: the room 359 (whole points), the trackpad from 511.5, the key row 10.5 above it",
          half.picture.height == 359 && half.trackpad.minY == 511.5 && half.trackpad.minY - half.keys.maxY == 10.5)
    let short = L(size: pro.container, keyboard: 100)
    check("a keyboard of 100: the trackpad keeps 120 pt, the room 524", short.trackpad.height == 120 && short.picture.height == 812 - 136 - 152)
    let tiny = L(size: CGSize(width: 400, height: 450), keyboard: 320)
    check("a screen too short for the room (400×450 above a 320 pt keyboard): no picture, the rows from the top",
          tiny.picture.height == 0 && tiny.row1.minY == 32 && tiny.keys.maxY == 142 && tiny.trackpad.minY == 152)
}

// Every width from 300 to 599, every height from the width + 1 to 1,400, each of the four keyboards,
// where the room is not empty.
let lInside = Rule("Larger Picture: everything inside the screen")
let lOrdered = Rule("Larger Picture: the room, row 1, the key row, the trackpad top to bottom, no thumbnails' row")
let lGaps = Rule("Larger Picture: 24 from the room to row 1's buttons, 16 from them to the key row, 10 to the keyboard, the trackpad from its top to 16 off the bottom")
let lRoom = Rule("Larger Picture: the room at (8, 8), W − 16 wide, the height less the keyboard less 152")
let lRow1 = Rule("Larger Picture: five equal buttons as today, and beside the Mac's menus six, Menus second, each (W − 68) ÷ 6, 8 apart, from 14 to W − 14")
let lCaps = Rule("Larger Picture: six equal caps, 44 tall, 8 apart, from 14 to W − 14")
let lRulers = Rule("Larger Picture: both rulers over row 1, centred on their Aa, inside the row, 36 a detent where they fit")
let lPanels = Rule("Larger Picture: the panel from 8 under row 1 to 16 off the bottom, the drawer from 8 to 8 above row 1 (128 above the keyboard), both across row 1; the anchor the panel's corner; the dim all but row 1")
let lFrames = Rule("Larger Picture: each frame inside the room, from its top, whole points, at the picture's shape (to a point), centred across when taller than the room; the span the pad's width × the frame's shape")
let largerRules = [lInside, lOrdered, lGaps, lRoom, lRow1, lCaps, lRulers, lPanels, lFrames]
let frameVideos = [CGSize.zero, CGSize(width: 3024, height: 1964), CGSize(width: 2560, height: 1080), CGSize(width: 1000, height: 1000),
                   CGSize(width: 1000, height: 2000), CGSize(width: 1512, height: 949)]
var largerSizes = 0
for keyboard: CGFloat in [233, 301, 310, 320] {
    for w in 300...599 {
        for h in (w + 1)...1400 {
            let W = CGFloat(w), H = CGFloat(h)
            guard H - keyboard - 152 > 0 else { continue }
            let size = CGSize(width: w, height: h)
            let l = L(size: size, keyboard: keyboard)
            largerSizes += 1
            let all = [l.picture, l.row1, l.keys, l.trackpad, l.ruler, l.rulerBesideMenus, l.menus, l.drawer, l.settings]
                + l.buttons + l.buttonsBesideMenus + l.caps + l.dim
            lInside.expect(all.allSatisfy { within($0, size) }, size, all.first { !within($0, size) }.map(str) ?? "")
            lOrdered.expect(l.picture.maxY <= l.row1.minY && l.row1.maxY <= l.strip.minY && l.strip.height == 0 && l.strip.maxY <= l.keys.minY
                            && l.keys.maxY <= l.trackpad.minY && l.largerPicture && l.keyboard == keyboard, size)
            lGaps.expect(l.row1.minY - l.picture.maxY == 24 && l.keys.minY - l.row1.maxY == 16 && H - keyboard - l.keys.maxY == 10
                         && l.trackpad.minY == H - keyboard && H - l.trackpad.maxY == 16, size,
                         "\(l.row1.minY - l.picture.maxY), \(l.keys.minY - l.row1.maxY), \(H - keyboard - l.keys.maxY), \(l.trackpad.minY)")
            lRoom.expect(l.picture == CGRect(x: 8, y: 8, width: W - 16, height: H - keyboard - 152), size, str(l.picture))
            let b = l.buttons, s = l.buttonsBesideMenus, five = (W - 60) / 5, six = (W - 68) / 6
            let row = [s[0], l.menus] + s.dropFirst()
            lRow1.expect(b.count == 5 && b.allSatisfy { near($0.width, five) && $0.minY == l.row1.minY && $0.height == 50 }
                         && s.count == 5 && row.allSatisfy { near($0.width, six) && $0.minY == l.row1.minY && $0.height == 50 }
                         && row[0].minX == 14 && near(row[5].maxX, W - 14) && zip(row, row.dropFirst()).allSatisfy { near($1.minX - $0.maxX, 8) }, size)
            let c = l.caps, cw = (W - 68) / 6
            lCaps.expect(c.count == 6 && c.allSatisfy { near($0.width, cw) && $0.height == 44 && $0.minY == l.keys.minY }
                         && c[0].minX == 14 && near(c[5].maxX, W - 14) && zip(c, c.dropFirst()).allSatisfy { near($1.minX - $0.maxX, 8) }, size)
            var rulersOK = true
            for (ruler, step, aa) in [(l.ruler, l.rulerStep, b[1]), (l.rulerBesideMenus, l.rulerStepBesideMenus, s[1])] {
                let fitting = min(36, ((aa.midX - 14) * 2 - 60) / 4)
                rulersOK = rulersOK && near(ruler.midX, aa.midX) && ruler.minY == l.row1.minY && ruler.height == 50
                    && near(ruler.width, 4 * step + 60) && ruler.minX >= 14 - 0.001 && ruler.maxX <= W - 14 + 0.001 && near(step, fitting)
            }
            lRulers.expect(rulersOK, size)
            lPanels.expect(l.settings == CGRect(x: 14, y: l.row1.maxY + 8, width: W - 28, height: H - 16 - l.row1.maxY - 8)
                           && l.drawer == CGRect(x: 14, y: 8, width: W - 28, height: l.row1.minY - 16) && l.drawer.maxY == H - keyboard - 128
                           && near(l.settingsAnchor.x, l.settings.maxX / W, 0.0001) && near(l.settingsAnchor.y, l.settings.minY / H, 0.0001)
                           && l.dim == [CGRect(x: 0, y: 0, width: W, height: l.row1.minY), CGRect(x: 0, y: l.row1.maxY, width: W, height: H - l.row1.maxY)], size)
            var framesOK = true, bad = ""
            for v in frameVideos {
                let f = l.pane(video: v)
                let aspect = v == .zero ? 1.6 : v.width / v.height
                let tall = l.picture.width / aspect > l.picture.height + 0.01
                let shapeOK = tall ? (f.height == l.picture.height && f.width <= f.height * aspect + 0.01 && f.height * aspect - f.width < 1
                                      && abs((f.minX - l.picture.minX) - (l.picture.maxX - f.maxX)) <= 1)
                                   : (f.width == l.picture.width && f.minX == l.picture.minX && f.height <= f.width / aspect + 0.01 && f.width / aspect - f.height < 1)
                let ok = f.minY == l.picture.minY && f.maxY <= l.picture.maxY && f.minX >= l.picture.minX && f.maxX <= l.picture.maxX
                    && f.width == f.width.rounded() && f.height == f.height.rounded() && f.minX == f.minX.rounded() && shapeOK
                    && near(l.trackpadSpan(video: v), f.width > 0 && f.height > 0 ? l.trackpad.width * f.height / f.width : l.trackpadSpan)
                if !ok { framesOK = false; bad = "\(v): \(str(f))" }
            }
            lFrames.expect(framesOK, size, bad)
        }
    }
}
for rule in largerRules {
    check("Larger Picture grid (\(largerSizes) layouts): \(rule.name)" + (rule.firstFailure.map { " — first failure at \($0)" } ?? ""), rule.firstFailure == nil)
}

// MARK: Full Screen (FullScreenLayout)

// An iPhone 12 Pro: 390×844, 47 pt above, 34 below; its keyboard 301 pt.
let fsSize = CGSize(width: 390, height: 844)
let fsOpen = FullScreenLayout(size: fsSize, top: 47, bottom: 34, keyboard: nil, expanded: true)
check("full screen: the picture from under the notch down to the controls",
      fsOpen.picture.minY == 47 && fsOpen.picture.width == 390 && near(fsOpen.picture.maxY, fsOpen.ground.minY))
check("full screen: the key row ends at the home indicator", near(fsOpen.keys.maxY, 844 - 34) && fsOpen.keys.height == 44)
check("full screen: row 1 10 pt above the keys, the handle 6 above row 1",
      near(fsOpen.row1.maxY, fsOpen.keys.minY - 10) && near(fsOpen.handle.maxY, fsOpen.row1.minY - 6))
check("full screen: five buttons and six caps across the rows",
      fsOpen.buttons.count == 5 && fsOpen.caps.count == 6 && near(fsOpen.buttons[4].maxX, 376) && near(fsOpen.caps[5].maxX, 376))
check("full screen: the ground from above the handle to the bottom",
      near(fsOpen.ground.minY, fsOpen.handle.minY - 8) && near(fsOpen.ground.maxY, 844))
check("full screen: the handle's three buttons at its ends and middle",
      fsOpen.mode.minX == fsOpen.handle.minX && fsOpen.exit.maxX == fsOpen.handle.maxX && near(fsOpen.collapse.midX, fsOpen.handle.midX))
check("full screen: the drawer under the top inset, above the controls",
      near(fsOpen.drawer.minY, 47 + 8) && near(fsOpen.drawer.maxY, fsOpen.ground.minY - 8))
check("full screen: the dim covers everything above the controls",
      fsOpen.dim.count == 1 && near(fsOpen.dim[0].maxY, fsOpen.ground.minY))
check("full screen with the Mac's menus: Menus after Apps, six across",
      near(fsOpen.menus.minX, fsOpen.buttonsBesideMenus[0].maxX + 8) && fsOpen.buttonsBesideMenus.count == 5
      && near(fsOpen.buttonsBesideMenus[4].maxX, 376) && fsOpen.menus.width >= 44)
check("full screen: Aa's ruler over row 1", near(fsOpen.ruler.midX, fsOpen.buttons[1].midX) && fsOpen.ruler.minX >= fsOpen.row1.minX - 0.01)

let fsShut = FullScreenLayout(size: fsSize, top: 47, bottom: 34, keyboard: nil, expanded: false)
check("collapsed: only the handle, at the home indicator", near(fsShut.handle.maxY, 844 - 34) && fsShut.row1.height == 0
      && fsShut.keys.height == 0 && fsShut.ground == .zero)
check("collapsed: the drawer reaches down to the handle", near(fsShut.drawer.maxY, fsShut.handle.minY - 8))
check("collapsed: the picture down to the handle", near(fsShut.picture.maxY, fsShut.handle.minY - 8)
      && fsShut.picture.height > fsOpen.picture.height)

let fsKeys = FullScreenLayout(size: fsSize, top: 47, bottom: 34, keyboard: 301, expanded: true)
check("the keyboard up: the key row 10 pt above it", near(fsKeys.keys.maxY, 844 - 301 - 10))
check("the keyboard up: the picture shrinks to the room above the controls",
      near(fsKeys.picture.maxY, fsKeys.ground.minY) && fsKeys.picture.height < fsOpen.picture.height)
let fsKeysShut = FullScreenLayout(size: fsSize, top: 47, bottom: 34, keyboard: 301, expanded: false)
check("the keyboard up, collapsed: the handle above it", near(fsKeysShut.handle.maxY, 844 - 301 - 10))
let fsNoInsets = FullScreenLayout(size: fsSize, top: 0, bottom: 0, keyboard: nil, expanded: true)
check("no insets: still 8 pt from the bottom and the top", near(fsNoInsets.keys.maxY, 836) && near(fsNoInsets.drawer.minY, 16)
      && fsNoInsets.picture.minY == 0)

// Every phone's size, both states, with and without the keyboard: everything on screen, in order.
var fsOK = true
for (w, h) in [(320, 548), (375, 667), (375, 812), (390, 844), (393, 852), (402, 874), (430, 932), (440, 956)] {
    for expanded in [true, false] {
        for keyboard in [nil, PhonePortraitLayout.keyboardHeight(for: CGSize(width: w, height: h - 47))] as [CGFloat?] {
            let l = FullScreenLayout(size: CGSize(width: w, height: h), top: 47, bottom: 34, keyboard: keyboard, expanded: expanded)
            let floor = CGFloat(h) - max(34, (keyboard ?? 0) + (keyboard == nil ? 0 : 10))
            fsOK = fsOK && l.handle.minY >= 0 && l.handle.maxY <= floor + 0.01 && (expanded ? near(l.keys.maxY, floor) : near(l.handle.maxY, floor))
                && l.drawer.height >= 0 && l.drawer.maxY <= l.handle.minY && l.picture.minY == 47 && l.picture.width == CGFloat(w)
                && l.picture.maxY <= l.handle.minY && l.picture.height > 100
                && l.buttons.allSatisfy { $0.width >= 44 || !expanded }
        }
    }
}
check("full screen at every phone size: everything on screen, in order", fsOK)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
