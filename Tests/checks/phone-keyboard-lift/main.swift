// iOSClient/PhoneKeyboardLift.swift with iOSClient/PhonePortraitLayout.swift: a phone held upright's rows
// placed from the software keyboard's real top (docs/steps/2026-11-19-keys-above-keyboard.md). The phones
// with Apple's own keyboards as measured (nothing moves but on the SE, whose key row its own keyboard
// covered by 24 pt), taller keyboards (an input method's candidates, a third-party keyboard's bar, the
// harness's stand-in), the iPhone Duo's cover, Larger Picture over its estimate and over a taller keyboard,
// Hide Thumbnails While Typing, the lift's ceiling, the frame and the viewport, the switch and its words;
// then a grid of every width from 300 to 599 pt, heights to 1,400 and twenty keyboard heights, with and
// without the switch, in both arrangements.
//   swiftc -O iOSClient/PhonePortraitLayout.swift iOSClient/PhoneKeyboardLift.swift Tests/checks/phone-keyboard-lift/main.swift -o .build/checks/phone-keyboard-lift/check
import CoreGraphics
import Foundation

typealias L = PhonePortraitLayout
typealias K = PhoneKeyboardLift
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", name) } else { passes += 1; print("ok  ", name) } }
func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
func str(_ r: CGRect) -> String { String(format: "(%.2f, %.2f, %.2f×%.2f)", r.minX, r.minY, r.width, r.height) }
func shifted(_ r: CGRect, _ dy: CGFloat) -> CGRect { r.offsetBy(dx: 0, dy: dy) }

/// Every rect of the lift equal to the layout's: nothing moved.
func unmoved(_ k: K) -> Bool {
    let l = k.layout
    return k.lift == 0 && !k.tucked && !k.moved && k.row1 == l.row1 && k.buttons == l.buttons
        && k.buttonsBesideMenus == l.buttonsBesideMenus && k.menus == l.menus && k.strip == l.strip
        && k.stripBesideMenus == l.stripBesideMenus && k.keys == l.keys && k.caps == l.caps && k.trackpad == l.trackpad
        && k.ruler == l.ruler && k.rulerBesideMenus == l.rulerBesideMenus && k.drawer == l.drawer && k.dim == l.dim
        && k.room == l.picture
}
let videos = [CGSize.zero, CGSize(width: 3024, height: 1964), CGSize(width: 1512, height: 949), CGSize(width: 2560, height: 1080),
              CGSize(width: 848, height: 844), CGSize(width: 1000, height: 1000), CGSize(width: 1000, height: 2000)]
/// The frame the layout draws for each video: the picture, or Larger Picture's pane at the video's shape.
func laid(_ l: L, _ v: CGSize) -> CGRect { l.largerPicture ? l.pane(video: v) : l.picture }

// MARK: - The phones, as phone-portrait has them

struct Phone {
    let name: String
    let screen: CGSize
    let inset: CGFloat
    /// Apple's keyboard as Sill's input view shows it, measured on the iOS 27 simulators (phone-portrait's).
    let keyboard: CGFloat
    var container: CGSize { CGSize(width: screen.width, height: screen.height - inset) }
    /// The keyboard's top in the stream screen for a keyboard `k` tall: the screen's foot less it, less the inset.
    func glass(_ k: CGFloat) -> CGFloat { container.height - k }
}
let proMax = Phone(name: "iPhone 18 Pro Max", screen: CGSize(width: 440, height: 956), inset: 62, keyboard: 320)
let pro = Phone(name: "iPhone 18 Pro", screen: CGSize(width: 402, height: 874), inset: 62, keyboard: 301)
let fifteenPro = Phone(name: "iPhone 15 Pro", screen: CGSize(width: 393, height: 852), inset: 59, keyboard: 301)
let seventeenE = Phone(name: "iPhone 17e", screen: CGSize(width: 390, height: 844), inset: 47, keyboard: 301)
let mini = Phone(name: "iPhone 13 mini", screen: CGSize(width: 375, height: 812), inset: 50, keyboard: 310)
let se = Phone(name: "iPhone SE (3rd generation)", screen: CGSize(width: 375, height: 667), inset: 20, keyboard: 233)
/// The iPhone Duo's cover upright (iOS 27.1, less its camera's strip): its keyboard was never measured; 233
/// is the estimate's, the Home-button shape's.
let duoCover = Phone(name: "the iPhone Duo's cover", screen: CGSize(width: 382, height: 678), inset: 0, keyboard: 233)
let seZoom = Phone(name: "iPhone SE with Display Zoom", screen: CGSize(width: 320, height: 568), inset: 20, keyboard: 233)
let phones = [proMax, pro, fifteenPro, seventeenE, mini, se]

// Nothing up: every phone, both arrangements, the switch either way: the layout as it is.
for p in phones + [duoCover, seZoom] {
    for larger in [false, true] {
        let l = L(size: p.container, keyboard: larger ? p.keyboard : nil)
        for tuck in [false, true] {
            let none = K(l, glass: nil, tuck: tuck)
            let foot = K(l, glass: p.container.height, tuck: tuck)
            let under = K(l, glass: p.container.height + 40, tuck: tuck)
            check("\(p.name)\(larger ? ", Larger Picture" : ""), switch \(tuck ? "on" : "off"): no keyboard, or one at or under the screen's foot: the layout, every rect and frame",
                  unmoved(none) && unmoved(foot) && unmoved(under) && videos.allSatisfy { none.frame(video: $0) == laid(l, $0) && foot.frame(video: $0) == laid(l, $0) })
        }
    }
}

// Apple's own keyboards, the switch off: nothing moves on any phone but the SE, whose 233 pt keyboard covered
// its key row by 24 pt (phone-portrait's keyboard table): there the rows lift 34 pt, the key row 10 above it.
for (p, clear) in [(proMax, CGFloat(95)), (pro, 56), (fifteenPro, 43), (seventeenE, 49), (mini, 14)] {
    let l = L(size: p.container), k = K(l, glass: p.glass(p.keyboard), tuck: false)
    check("\(p.name), its \(Int(p.keyboard)) pt keyboard: nothing moves, the key row \(Int(clear)) pt above it",
          unmoved(k) && p.glass(p.keyboard) - l.keys.maxY == clear)
}
do {
    let l = L(size: se.container), k = K(l, glass: se.glass(233), tuck: false)
    check("iPhone SE, its 233 pt keyboard (its top at 414): main's key row ended 24 pt under it",
          se.glass(233) == 414 && l.keys.maxY - 414 == 24)
    check("iPhone SE: lifted 34 pt: row 1 222–272, the strip 288–350, the key row 360–404, 10 pt above the keyboard",
          k.lift == 34 && !k.tucked && k.row1 == CGRect(x: 14, y: 222, width: 347, height: 50) && k.strip == shifted(l.strip, -34)
            && k.strip.minY == 288 && k.keys == CGRect(x: 14, y: 360, width: 347, height: 44) && 414 - k.keys.maxY == 10)
    check("iPhone SE: the picture's room 359×190 (the viewport stays 359×224); its 16:10 frame 304×190, centred at 35",
          k.room == CGRect(x: 8, y: 8, width: 359, height: 190) && l.picture.size == CGSize(width: 359, height: 224)
            && k.frame(video: .zero) == CGRect(x: 35, y: 8, width: 304, height: 190))
    check("iPhone SE: the trackpad from 414 (the keyboard's top) to 631, under the keyboard",
          k.trackpad == CGRect(x: 14, y: 414, width: 347, height: 217))
    check("iPhone SE: the drawer from 8 under the lifted row 1 to the trackpad's foot (280 to 631)",
          k.drawer == CGRect(x: 14, y: 280, width: 347, height: 351))
    check("iPhone SE: the dim above and below the lifted row 1",
          k.dim == [CGRect(x: 0, y: 0, width: 375, height: 222), CGRect(x: 0, y: 272, width: 375, height: 375)])
    check("iPhone SE: the line", k.line(video: .zero) == "keys: lifted 34 pt, the key row 10 pt above the keyboard at 414, the picture 304×190 in a room of 359×190, the trackpad from 414")
}

// Taller keyboards, the switch off: an input method's candidates (44 pt more), the harness's stand-in (60 pt
// more), a keyboard 100 pt taller. The rows lift just enough: the key row 10 pt above the keyboard.
struct Taller { let phone: Phone; let extra: CGFloat; let lift: CGFloat; let frame: CGRect }
let tallers: [Taller] = [
    Taller(phone: proMax, extra: 44, lift: 0, frame: CGRect(x: 8, y: 8, width: 424, height: 265)),
    Taller(phone: proMax, extra: 100, lift: 15, frame: CGRect(x: 20, y: 8, width: 400, height: 250)),
    Taller(phone: pro, extra: 44, lift: 0, frame: CGRect(x: 8, y: 8, width: 386, height: 241)),
    Taller(phone: pro, extra: 60, lift: 14, frame: CGRect(x: 19, y: 8, width: 363, height: 227)),
    Taller(phone: pro, extra: 100, lift: 54, frame: CGRect(x: 51, y: 8, width: 299, height: 187)),
    Taller(phone: fifteenPro, extra: 60, lift: 27, frame: CGRect(x: 30, y: 8, width: 333, height: 208)),
    Taller(phone: mini, extra: 44, lift: 40, frame: CGRect(x: 40, y: 8, width: 294, height: 184)),
    Taller(phone: se, extra: 44, lift: 78, frame: CGRect(x: 70, y: 8, width: 234, height: 146)),
]
for t in tallers {
    let c = t.phone.container, l = L(size: c), g = t.phone.glass(t.phone.keyboard + t.extra)
    let k = K(l, glass: g, tuck: false)
    let n = "\(t.phone.name), a keyboard \(Int(t.extra)) pt taller (\(Int(t.phone.keyboard + t.extra)) pt, its top at \(Int(g)))"
    check("\(n): lifted \(Int(t.lift)) pt; the picture \(Int(t.frame.width))×\(Int(t.frame.height))",
          k.lift == t.lift && k.frame(video: .zero) == t.frame && !k.tucked)
    check("\(n): the key row clear of it by 10 pt or more\(t.lift > 0 ? ", exactly 10" : "")",
          g - k.keys.maxY >= 10 && (t.lift == 0 || g - k.keys.maxY == 10))
    check("\(n): row 1, the strip and the key row lifted together, 24 pt under the room",
          k.row1 == shifted(l.row1, -t.lift) && k.strip == shifted(l.strip, -t.lift) && k.keys == shifted(l.keys, -t.lift)
            && k.row1.minY - k.room.maxY == 24)
}

// The iPhone Duo's cover (382×678, no top inset): main's key row (398–442) under any keyboard over 236 pt.
do {
    let l = L(size: duoCover.container)
    check("the Duo's cover: main's key row ends 236 pt above the screen's foot", 678 - l.keys.maxY == 236)
    for (kb, lift, frame) in [(CGFloat(233), CGFloat(7), CGRect(x: 14, y: 8, width: 354, height: 221)),
                              (260, 34, CGRect(x: 35, y: 8, width: 311, height: 194)),
                              (301, 75, CGRect(x: 68, y: 8, width: 245, height: 153)),
                              (361, 135, CGRect(x: 116, y: 8, width: 149, height: 93))] {
        let k = K(l, glass: 678 - kb, tuck: false)
        check("the Duo's cover, a \(Int(kb)) pt keyboard: lifted \(Int(lift)), the key row 10 pt above it, the picture \(Int(frame.width))×\(Int(frame.height))",
              k.lift == lift && 678 - kb - k.keys.maxY == 10 && k.frame(video: .zero) == frame)
    }
    // With the switch on, the cover's thumbnails make way first: a 301 pt keyboard needs a 33 pt lift, not 75.
    let k = K(l, glass: 678 - 301, tuck: true)
    check("the Duo's cover, a 301 pt keyboard, the switch on: tucked, the key row 326–370 lifted 3 pt to 323–367, 10 above it",
          k.tucked && l.strip.minY == 326 && k.lift == 3 && k.keys.minY == 323 && 377 - k.keys.maxY == 10)
    let tall = K(l, glass: 678 - 361, tuck: true)
    check("the Duo's cover, the 301 pt keyboard with the harness's 60 pt over it, the switch on: lifted 63 (135 off)",
          tall.tucked && tall.lift == 63 && 317 - tall.keys.maxY == 10)
    check("…its line, tucked and lifted at once",
          tall.line(video: .zero) == "keys: the thumbnails tucked away, lifted 63 pt, the key row 263–307, 10 pt above the keyboard at 317, the picture 264×165 in a room of 366×165, the trackpad from 317")
}

// MARK: - Hide Thumbnails While Typing

for p in phones + [duoCover] {
    let l = L(size: p.container), g = p.glass(p.keyboard)
    let k = K(l, glass: g, tuck: true)
    let n = "\(p.name), its \(Int(p.keyboard)) pt keyboard, the switch on"
    check("\(n): the thumbnails tucked away, the key row in their place, 16 pt under row 1's buttons",
          k.tucked && k.keys.minY == l.strip.minY - k.lift && k.keys.minY - k.row1.maxY == 16 && k.moved)
    check("\(n): the trackpad from 10 pt under the key row\(k.lift == 0 ? ", \(Int(g - k.trackpad.minY)) pt of it above the keyboard" : "")",
          k.trackpad.minY == k.keys.maxY + 10 && k.trackpad.maxY == p.container.height - 16
            && (k.lift > 0 || g - k.trackpad.minY == (g - l.strip.minY - 54)))
    check("\(n): the caps on the key row, as laid out across it",
          k.caps.count == 6 && zip(k.caps, l.caps).allSatisfy { $0.minX == $1.minX && $0.width == $1.width && $0.minY == k.keys.minY && $0.height == 44 })
}
do {
    let l = L(size: pro.container), k = K(l, glass: 511, tuck: true)
    check("iPhone 18 Pro, the switch on: the key row 339–383, 118 pt of trackpad above the keyboard (46 without), the picture as it is",
          k.keys == CGRect(x: 14, y: 339, width: 374, height: 44) && k.trackpad.minY == 393 && 511 - k.trackpad.minY == 118
            && 511 - l.trackpad.minY == 46 && k.lift == 0 && k.frame(video: .zero) == l.picture && k.row1 == l.row1)
    check("iPhone 18 Pro, the switch on: the line",
          k.line(video: .zero) == "keys: the thumbnails tucked away, the key row 339–383, 128 pt above the keyboard at 511, the trackpad from 393")
    check("iPhone 18 Pro, the switch off: the line", K(l, glass: 511, tuck: false).line(video: .zero) == "keys: as laid out, the key row 56 pt above the keyboard at 511")
    check("no keyboard: the line", K(l, glass: nil, tuck: true).line(video: .zero) == "keys: no keyboard")
    let se1 = K(L(size: se.container), glass: 414, tuck: true)
    check("iPhone SE, its own keyboard, the switch on: no lift (the key row 322–366, 48 pt above it): the picture whole",
          se1.lift == 0 && se1.keys.minY == 322 && 414 - se1.keys.maxY == 48 && se1.frame(video: .zero) == L(size: se.container).picture)
}

// MARK: - Larger Picture

for p in phones {
    let l = L(size: p.container, keyboard: p.keyboard)
    let n = "Larger Picture, \(p.name)"
    check("\(n): over the keyboard it was laid out for, nothing moves, the switch either way",
          unmoved(K(l, glass: p.glass(p.keyboard), tuck: false)) && unmoved(K(l, glass: p.glass(p.keyboard), tuck: true)))
    for extra: CGFloat in [44, 60, 100] {
        let g = p.glass(p.keyboard + extra), k = K(l, glass: g, tuck: true)
        check("\(n), a keyboard \(Int(extra)) pt taller: lifted \(Int(extra)), the key row 10 pt above it, no thumbnails to tuck",
              k.lift == extra && g - k.keys.maxY == 10 && !k.tucked && k == K(l, glass: g, tuck: false))
        check("\(n), \(Int(extra)) pt taller: the trackpad from its top, the drawer above row 1 shorter by as much",
              k.trackpad.minY == g && k.drawer == CGRect(x: 14, y: 8, width: l.drawer.width, height: l.drawer.height - extra)
                && k.drawer.maxY == k.row1.minY - 8)
        check("\(n), \(Int(extra)) pt taller: Menus in row 1 lifted with it",
              k.menus == shifted(l.menus, -extra) && k.buttonsBesideMenus == l.buttonsBesideMenus.map { shifted($0, -extra) })
    }
}
do {
    // The 18 Pro Max's room, 424×422 over its 320 pt keyboard; a candidate bar's 44 pt more.
    let l = L(size: proMax.container, keyboard: 320), k = K(l, glass: proMax.glass(364), tuck: false)
    check("Larger Picture, 18 Pro Max, 44 pt more: the room 424×378; a 16:10 window keeps 424×265 (it fits)",
          k.room == CGRect(x: 8, y: 8, width: 424, height: 378) && k.frame(video: CGSize(width: 1512, height: 945)) == CGRect(x: 8, y: 8, width: 424, height: 265))
    check("…a window the Mac fitted to the room (848×844) 379×378, centred at 30",
          k.frame(video: CGSize(width: 848, height: 844)) == CGRect(x: 30, y: 8, width: 379, height: 378))
    check("…a square one 378×378 at 31; one twice as tall as wide 189×378 at 125",
          k.frame(video: CGSize(width: 1000, height: 1000)) == CGRect(x: 31, y: 8, width: 378, height: 378)
            && k.frame(video: CGSize(width: 1000, height: 2000)) == CGRect(x: 125, y: 8, width: 189, height: 378))
    check("…the viewport (the layout's picture) is still the whole room, 424×422", k.layout.picture.size == CGSize(width: 424, height: 422))
}

// MARK: - The ceiling, fractions, the switch's words

do {
    let l = L(size: pro.container)
    let huge = K(l, glass: 100, tuck: false)
    check("a keyboard up to 100 pt from the top: the lift is the picture's whole height (241); the room and the frame 0 tall, row 1 from 32",
          huge.lift == 241 && huge.room.height == 0 && huge.frame(video: .zero).height == 0 && huge.row1.minY == 32
            && huge.keys.maxY == 214)
    let above = K(l, glass: -50, tuck: true)
    check("a keyboard's top above the screen's: the same ceiling", above.lift == 241 && above.tucked)
    let half = K(l, glass: 433.5, tuck: false)
    check("a keyboard's top at 433.5: lifted 32 (whole points), the key row 10.5 above it",
          half.lift == 32 && 433.5 - half.keys.maxY == 10.5 && half.lift == half.lift.rounded())
    check("…and its line, a tenth where a point is not whole",
          half.line(video: .zero) == "keys: lifted 32 pt, the key row 10.5 pt above the keyboard at 433.5, the picture 334×209 in a room of 386×209, the trackpad from 433")
    let exact = K(l, glass: 465, tuck: false)
    check("a keyboard's top exactly 10 pt under the key row: nothing moves; a point higher, a 1 pt lift",
          unmoved(exact) && K(l, glass: 464, tuck: false).lift == 1 && K(l, glass: 464.9, tuck: false).lift == 1)
}
check("the switch: Sill.hideThumbnailsWhileTyping, off unless turned on",
      K.switchKey == "Sill.hideThumbnailsWhileTyping" && K.defaultOn == false)
check("the switch offered wherever a phone's arrangement is drawn (the Duo's too), never on an iPad",
      K.offered(phoneArrangement: true) && !K.offered(phoneArrangement: false))
check("its words", K.Copy.title == "Hide Thumbnails While Typing"
      && K.Copy.footnote == "Held upright, while the keyboard is up the window thumbnails and the Menus button beside them step aside, so the keys sit right under the buttons and more of the trackpad shows. Put the keyboard away to bring them back.")

// MARK: - The grid: every width from 300 to 599, heights from the width + 1 to 1,400 by 7, twenty keyboards

final class Rule {
    let name: String
    var firstFailure: String?
    init(_ name: String) { self.name = name }
    func expect(_ ok: @autoclosure () -> Bool, _ where: @autoclosure () -> String) {
        guard firstFailure == nil else { return }
        if !ok() { firstFailure = `where`() }
    }
}
let gInside = Rule("everything inside the screen, the frame inside the room")
let gNone = Rule("no keyboard, or one at or under the foot: the layout, every rect and frame, the switch either way")
let gClear = Rule("the key row never closer to the keyboard than 10 pt unless the lift is at its ceiling (the picture's height); never more than 11 pt above it after a lift")
let gMinimal = Rule("nothing moves for a keyboard that leaves the key row clear with the switch off; the lift whole points, 0 or more, at most the picture's height")
let gTogether = Rule("row 1, its buttons, Menus, the rulers and the thumbnails' row lifted by the lift alone; the key row too, from the thumbnails' place while tucked")
let gGaps = Rule("24 from the room to row 1's buttons; 16 to the thumbnails and 10 to the key row, or 16 to the key row without them")
let gTuck = Rule("tucked exactly when the switch is on, a keyboard up and the standard arrangement; the switch changes nothing in Larger Picture's")
let gPad = Rule("the trackpad as laid out while nothing moved; else from 10 under the key row to 16 off the foot")
let gDrawer = Rule("the drawer from 8 under row 1 to the trackpad's foot, or with Larger Picture from 8 to 8 above row 1; the dim all but row 1")
let gFrame = Rule("the frame the layout's while it fits the room; else as tall as the room, at its shape to a point, whole points, centred across, from the room's top; the room the picture less the lift")
let grid = [gInside, gNone, gClear, gMinimal, gTogether, gGaps, gTuck, gPad, gDrawer, gFrame]
func within(_ r: CGRect, _ size: CGSize) -> Bool {
    r.minX >= -0.001 && r.minY >= -0.001 && r.maxX <= size.width + 0.001 && r.maxY <= size.height + 0.001 && r.width >= 0 && r.height >= 0
}
let keyboards: [CGFloat] = [150, 216, 233, 260, 291, 300.5, 301, 310, 320, 336, 345.5, 346, 364, 380, 400, 450, 520, 600]
var lifts = 0
for w in 300...599 {
    for h in stride(from: w + 1, through: 1400, by: 7) {
        let size = CGSize(width: w, height: h), H = CGFloat(h), W = CGFloat(w)
        let standard = L(size: size)
        var arrangements = [standard]
        // Larger Picture over the size's own estimate (as StreamScreen hands it, wherever it applies) and over 320.
        for kb in [L.keyboardHeight(for: size), 320] where H - kb - 152 > 0 { arrangements.append(L(size: size, keyboard: kb)) }
        for l in arrangements {
            for tuck in [false, true] {
                for g in [nil, H, H + 10] as [CGFloat?] {
                    let k = K(l, glass: g, tuck: tuck)
                    lifts += 1
                    gNone.expect(unmoved(k) && videos.allSatisfy { k.frame(video: $0) == laid(l, $0) }, "\(w)×\(h) \(String(describing: g))")
                }
                for kb in keyboards + [H + 50] {
                    let g = H - kb
                    let k = K(l, glass: g, tuck: tuck)
                    lifts += 1
                    let at = "\(w)×\(h), keyboard \(kb), switch \(tuck), larger \(l.largerPicture)"
                    let all = [k.row1, k.keys, k.trackpad, k.drawer, k.room, k.menus, k.strip, k.ruler, k.rulerBesideMenus] + k.buttons + k.buttonsBesideMenus + k.caps + k.dim
                    gInside.expect(all.allSatisfy { within($0, size) } && videos.allSatisfy { let f = k.frame(video: $0); return f.minY >= k.room.minY && f.maxY <= k.room.maxY + 0.001 && f.minX >= k.room.minX - 0.001 && f.maxX <= k.room.maxX + 0.001 },
                                   at + ": " + (all.first { !within($0, size) }.map(str) ?? "a frame"))
                    let ceiling = k.lift == l.picture.height
                    gClear.expect((g - k.keys.maxY >= 10 - 0.001 || ceiling) && (k.lift == 0 || ceiling || g - k.keys.maxY < 11), at + ": clear by \(g - k.keys.maxY), lift \(k.lift)")
                    let wouldClear = g - l.keys.maxY >= 10
                    gMinimal.expect(k.lift >= 0 && k.lift == k.lift.rounded() && k.lift <= l.picture.height
                                    && (!(wouldClear && !tuck) || unmoved(k)), at + ": lift \(k.lift)")
                    let d = -k.lift
                    let keysTop = k.tucked ? l.strip.minY : l.keys.minY
                    gTogether.expect(k.row1 == shifted(l.row1, d) && k.buttons == l.buttons.map { shifted($0, d) }
                                     && k.buttonsBesideMenus == l.buttonsBesideMenus.map { shifted($0, d) } && k.menus == shifted(l.menus, d)
                                     && k.ruler == shifted(l.ruler, d) && k.rulerBesideMenus == shifted(l.rulerBesideMenus, d)
                                     && k.strip == shifted(l.strip, d) && k.stripBesideMenus == shifted(l.stripBesideMenus, d)
                                     && k.keys == CGRect(x: l.keys.minX, y: keysTop + d, width: l.keys.width, height: 44)
                                     && k.caps.count == 6 && zip(k.caps, l.caps).allSatisfy { $0 == CGRect(x: $1.minX, y: k.keys.minY, width: $1.width, height: 44) }, at)
                    gGaps.expect(near(k.row1.minY - k.room.maxY, 24) && ((l.largerPicture || k.tucked) ? near(k.keys.minY - k.row1.maxY, 16)
                                                                       : near(k.strip.minY - k.row1.maxY, 16) && near(k.keys.minY - k.strip.maxY, 10)), at)
                    gTuck.expect(k.tucked == (tuck && !l.largerPicture) && (!l.largerPicture || k == K(l, glass: g, tuck: !tuck)), at)
                    gPad.expect(k.moved ? (k.trackpad == CGRect(x: 14, y: k.keys.maxY + 10, width: W - 28, height: max(0, H - 16 - k.keys.maxY - 10)))
                                        : k.trackpad == l.trackpad, at + ": " + str(k.trackpad))
                    gDrawer.expect((l.largerPicture ? k.drawer == CGRect(x: 14, y: 8, width: W - 28, height: max(0, k.row1.minY - 16))
                                                    : k.drawer == CGRect(x: 14, y: k.row1.maxY + 8, width: W - 28, height: H - 16 - k.row1.maxY - 8))
                                   && k.dim == [CGRect(x: 0, y: 0, width: W, height: k.row1.minY), CGRect(x: 0, y: k.row1.maxY, width: W, height: H - k.row1.maxY)],
                                   at + ": " + str(k.drawer))
                    var framesOK = k.room == CGRect(x: l.picture.minX, y: l.picture.minY, width: l.picture.width, height: l.picture.height - k.lift)
                    for v in videos where framesOK {
                        let was = laid(l, v), f = k.frame(video: v)
                        if was.height <= k.room.height {
                            framesOK = f == was
                        } else {
                            framesOK = f.minY == k.room.minY && f.height == k.room.height && f.width == f.width.rounded() && f.minX == f.minX.rounded()
                                && f.width <= was.width && abs(f.width - was.width * k.room.height / was.height) < 1
                                && abs((f.minX - k.room.minX) - (k.room.maxX - f.maxX)) <= 1
                        }
                    }
                    gFrame.expect(framesOK, at)
                }
            }
        }
    }
}
for rule in grid {
    check("grid (\(lifts) placements): \(rule.name)" + (rule.firstFailure.map { " — first failure at \($0)" } ?? ""), rule.firstFailure == nil)
}

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
