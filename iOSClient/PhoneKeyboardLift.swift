import CoreGraphics

/// The modifier keys kept above the software keyboard on a phone held upright, whatever the keyboard's
/// height (asked for by mail; docs/steps/2026-11-19-keys-above-keyboard.md). `PhonePortraitLayout` places
/// its rows for no keyboard at all: the standard arrangement's key row where Apple's own keyboard leaves it
/// clear on most iPhones, and Larger Picture's exactly `keyboardClearance` above `keyboardHeight(for:)`, a
/// table of Apple's keyboards as measured. Nothing read the keyboard that came up, so a taller one covered
/// the key row, and ctrl, opt, cmd and shift with it: a third-party keyboard with a bar of its own, an input
/// method's candidates (44 pt more), an iPhone SE's own 233 pt keyboard (by 24 pt), and on the iPhone Duo's
/// cover every keyboard over 236 pt. This places the rows from the keyboard's real top as UIKit reports it
/// (`glass`, in the stream screen's space; KeyboardFrameMonitor's frame), only while the person's own
/// keyboard is up (StreamScreen's `keyboardShown`: never the drawer's search field, never a hardware
/// keyboard's hold):
/// - **The key row is never under the keyboard.** While the keyboard would cover it (its foot closer to the
///   glass than `keyboardClearance`), row 1, the thumbnails' row and the key row lift together by just that
///   much (`lift`, in whole points), and the picture's frame keeps its shape in the room left above them
///   (`frame(video:)`, from the room's top, centred across). The viewport is the layout's `picture` still, so
///   the Mac resizes nothing, and the lift is at most the picture's height. A keyboard that leaves the key
///   row clear moves nothing.
/// - **Hide Thumbnails While Typing** (`switchKey`, off unless turned on): while a keyboard is up the
///   thumbnails' row, the strip and the Menus button at its end, is tucked away (`tucked`) and the key row
///   takes its place, 16 pt under row 1's buttons as Larger Picture has it, so more of the trackpad shows
///   above the keyboard; the lift then only if the keyboard still covers the key row. Larger Picture's
///   arrangement has no thumbnails' row, so the switch changes nothing there.
/// While anything moved, the trackpad runs from `rowGap` under the key row to `bottom` off the screen's
/// foot (under the keyboard but for what shows above it). The drawer follows row 1 (the standard one hangs
/// from it, Larger Picture's stands above it) and the dim is everything but row 1. The Settings panel keeps
/// the layout's place: opening it takes the keyboard down. Pure (CoreGraphics only), so
/// `Tests/checks/phone-keyboard-lift` compiles it with PhonePortraitLayout.swift and checks it at every size
/// and keyboard height.
struct PhoneKeyboardLift: Equatable {
    /// The UserDefaults key of Hide Thumbnails While Typing, read by the stream screen (`@AppStorage`) and the
    /// Settings panel's This iPhone; never sent. `-Sill.hideThumbnailsWhileTyping 1` turns it on for one run.
    static let switchKey = "Sill.hideThumbnailsWhileTyping"
    /// New behaviour is off unless turned on (Noah, 2026-11-18).
    static let defaultOn = false

    /// The arrangement for no keyboard: the standard one, or Larger Picture's above its estimate.
    let layout: PhonePortraitLayout
    /// The software keyboard's top in the stream screen as UIKit reports it; nil while the person's own
    /// keyboard is not up. A top at or under the stream screen's foot is no keyboard.
    let glass: CGFloat?
    /// Whether the thumbnails' row (the strip and the Menus button beside it) is tucked away: Hide Thumbnails
    /// While Typing on, a keyboard up, the standard arrangement.
    let tucked: Bool
    /// How far row 1 and everything under it down to the key row moved up, in whole points: what the
    /// keyboard would otherwise cover of the key row and its clearance, at most the picture's height.
    let lift: CGFloat
    let row1: CGRect
    let buttons: [CGRect]
    let buttonsBesideMenus: [CGRect]
    let menus: CGRect
    /// The thumbnails' row where it is drawn: lifted with row 1, and hidden while `tucked`.
    let strip: CGRect
    let stripBesideMenus: CGRect
    let keys: CGRect
    let caps: [CGRect]
    let trackpad: CGRect
    let ruler: CGRect
    let rulerBesideMenus: CGRect
    let drawer: CGRect
    let dim: [CGRect]
    /// The room the picture's frame keeps to: the layout's picture (the viewport, unchanged) less the lift at
    /// its foot.
    let room: CGRect

    /// `glass`: the keyboard's top in the stream screen, nil for none; `tuck`: Hide Thumbnails While Typing.
    init(_ layout: PhonePortraitLayout, glass: CGFloat?, tuck: Bool) {
        typealias L = PhonePortraitLayout
        self.layout = layout
        self.glass = glass
        let height = layout.size.height, width = layout.size.width
        // A keyboard over the stream screen: its top above the screen's foot.
        let top: CGFloat? = glass.flatMap { $0 < height ? $0 : nil }
        tucked = tuck && top != nil && !layout.largerPicture
        // The key row's top before any lift: the thumbnails' place while they are tucked away.
        let keysTop = tucked ? layout.strip.minY : layout.keys.minY
        let needed = top.map { keysTop + L.capHeight + L.keyboardClearance - $0 } ?? 0
        let lifted = min(layout.picture.height, max(0, needed.rounded(.up)))
        lift = lifted
        let up = -lifted
        row1 = layout.row1.offsetBy(dx: 0, dy: up)
        buttons = layout.buttons.map { $0.offsetBy(dx: 0, dy: up) }
        buttonsBesideMenus = layout.buttonsBesideMenus.map { $0.offsetBy(dx: 0, dy: up) }
        menus = layout.menus.offsetBy(dx: 0, dy: up)
        strip = layout.strip.offsetBy(dx: 0, dy: up)
        stripBesideMenus = layout.stripBesideMenus.offsetBy(dx: 0, dy: up)
        ruler = layout.ruler.offsetBy(dx: 0, dy: up)
        rulerBesideMenus = layout.rulerBesideMenus.offsetBy(dx: 0, dy: up)
        let keysY = keysTop - lifted
        keys = CGRect(x: layout.keys.minX, y: keysY, width: layout.keys.width, height: layout.keys.height)
        caps = layout.caps.map { CGRect(x: $0.minX, y: keysY, width: $0.width, height: $0.height) }
        // The trackpad as laid out while nothing moved; else from the key row down.
        let padTop = tucked || lifted > 0 ? keys.maxY + L.rowGap : layout.trackpad.minY
        trackpad = CGRect(x: layout.trackpad.minX, y: padTop, width: layout.trackpad.width,
                          height: max(0, height - L.bottom - padTop))
        if layout.largerPicture {
            drawer = CGRect(x: layout.drawer.minX, y: layout.drawer.minY, width: layout.drawer.width,
                            height: max(0, layout.drawer.height - lift))
        } else {
            drawer = CGRect(x: layout.drawer.minX, y: layout.drawer.minY - lift, width: layout.drawer.width,
                            height: layout.drawer.height + lift)
        }
        dim = [CGRect(x: 0, y: 0, width: width, height: row1.minY),
               CGRect(x: 0, y: row1.maxY, width: width, height: max(0, height - row1.maxY))]
        room = CGRect(x: layout.picture.minX, y: layout.picture.minY, width: layout.picture.width,
                      height: layout.picture.height - lift)
    }

    /// The frame the video is drawn in for a picture of `video`'s shape: the layout's (`picture`, or with
    /// Larger Picture `pane(video:)`) while it fits the room; else as tall as the room, at its own shape,
    /// whole points, centred across, from the room's top.
    func frame(video: CGSize) -> CGRect {
        let laid = layout.largerPicture ? layout.pane(video: video) : layout.picture
        guard laid.height > room.height else { return laid }
        let wide = min(room.width, (laid.width * room.height / laid.height + 0.01).rounded(.down))
        return CGRect(x: room.minX + ((room.width - wide) / 2).rounded(.down), y: room.minY, width: wide, height: room.height)
    }

    /// Whether anything is placed otherwise than the layout has it.
    var moved: Bool { tucked || lift > 0 }

    /// Whether Settings offers Hide Thumbnails While Typing: wherever a phone's arrangement is drawn
    /// (`DuoLayout.phoneArrangement`: every iPhone, and the iPhone Duo for its cover), not on an iPad, whose
    /// halves have no thumbnails' row under the picture.
    static func offered(phoneArrangement: Bool) -> Bool { phoneArrangement }

    /// The console's line for the gates (PortraitStreamScreen, DEBUG), each time the placement changes: `keys:
    /// no keyboard`, `keys: as laid out, the key row 56 pt above the keyboard at 511`, `keys: lifted 34 pt, the
    /// key row 10 pt above the keyboard at 414, the picture 304×190 in a room of 359×190`, or `keys: the
    /// thumbnails tucked away, the key row 339–383, 128 pt above the keyboard at 511, the trackpad from 393`.
    func line(video: CGSize) -> String {
        guard let top = glass, top < layout.size.height else { return "keys: no keyboard" }
        // Whole points as whole numbers, anything else to a tenth.
        func n(_ v: CGFloat) -> String { abs(v - v.rounded()) < 0.01 ? "\(Int(v.rounded()))" : "\(Double((v * 10).rounded()) / 10)" }
        let clear = top - keys.maxY
        let above = "\(n(abs(clear))) pt " + (clear >= 0 ? "above" : "under") + " the keyboard at \(n(top))"
        var parts: [String] = []
        if tucked { parts.append("the thumbnails tucked away") }
        if lift > 0 { parts.append("lifted \(n(lift)) pt") }
        if parts.isEmpty { parts.append("as laid out") }
        var line = "keys: " + parts.joined(separator: ", ")
        line += tucked ? ", the key row \(n(keys.minY))–\(n(keys.maxY)), \(above)" : ", the key row \(above)"
        if lift > 0 {
            let f = frame(video: video)
            line += ", the picture \(n(f.width))×\(n(f.height)) in a room of \(n(room.width))×\(n(room.height))"
        }
        if moved { line += ", the trackpad from \(n(trackpad.minY))" }
        return line
    }

    /// The words, in one place for the check.
    enum Copy {
        static let title = "Hide Thumbnails While Typing"
        /// Under the switch: what it does and when, what goes with the thumbnails, and that they come back.
        static let footnote = "Held upright, while the keyboard is up the window thumbnails and the Menus button beside them step aside, so the keys sit right under the buttons and more of the trackpad shows. Put the keyboard away to bring them back."
    }
}
