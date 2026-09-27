import CoreGraphics

/// Where everything goes on a phone held upright (Noah, 2026-09-27; docs/iphone-portrait-plan.md):
/// the picture in a fixed 16:10 pane at the top, then row 1 (Apps, Aa, Keyboard, Desktop,
/// Settings, widened to the row), row 2 (the window thumbnails), row 3 (esc, tab, ctrl, opt, cmd,
/// shift), and the trackpad in everything left. Every rectangle is a function of the stream
/// screen's size alone, the screen less its top safe-area inset down to its bottom edge (the stream
/// screen ignores the bottom inset and the keyboard), so nothing moves when the streamed window
/// changes shape (a 16:9 one gets black bars above and below) or the keyboard comes up (it covers
/// the trackpad; row 1, with the Keyboard button, stays above it on every phone).
///
/// `DuoLayout.outerPortrait` draws this: every iPhone upright, the Duo's outer display upright and
/// an iPad window narrower than 600 pt held upright. Pure (CoreGraphics only), so
/// `Tests/checks/phone-portrait` compiles it with swiftc and checks it at every size.
struct PhonePortraitLayout: Equatable {
    /// Around the picture: its pane's margin from the screen's sides and top.
    static let margin: CGFloat = 8
    /// The picture's shape: 16:10, the shape most Mac windows and displays have. Whole points,
    /// rounded down, so it is never taller than 16:10 and the rows below sit on whole points.
    static let aspect: CGFloat = 1.6
    /// From the picture's margin to row 1 (so 18 pt from the picture itself).
    static let underPicture: CGFloat = 10
    /// The rows' and the trackpad's inset from the screen's sides.
    static let side: CGFloat = 14
    /// Under the trackpad, to the screen's bottom edge.
    static let bottom: CGFloat = 16
    /// Between rows, and from row 3 to the trackpad.
    static let rowGap: CGFloat = 10
    /// Between buttons in row 1 and between caps in row 3: the same whitespace in both (Noah).
    static let gap: CGFloat = 8
    static let buttonHeight: CGFloat = 50
    /// The strip: 50 pt thumbnails with 6 pt above and below for the app badge and the halo.
    static let stripHeight: CGFloat = 62
    /// `WindowStrip` pads its thumbnails this much at each end, so the strip starts this far left
    /// of the rows and its first thumbnail lines up with Apps and esc.
    static let stripInset: CGFloat = 8
    static let capHeight: CGFloat = 44
    /// The least trackpad there is: only a screen too short for it (an iPad window, never a phone)
    /// makes the picture give way.
    static let minTrackpad: CGFloat = 120
    /// From row 1 to the drawer and the Settings panel, which hang under it.
    static let panelGap: CGFloat = 8
    static let drawerWidth: CGFloat = 380
    static let settingsWidth: CGFloat = 360
    /// The Aa ruler's finger travel per detent at most, and `TextScaleControl.sliderInset`, the room
    /// either side of its four detent spans.
    static let maxRulerStep: CGFloat = 36
    static let rulerInset: CGFloat = 30
    static let rulerSpans: CGFloat = 4

    /// Row 1, in the landscape bar's order.
    enum Button: Int, CaseIterable { case apps, textSize, keyboard, desktop, settings }
    /// Row 3's caps: esc, tab, ctrl, opt, cmd, shift.
    static let capCount = 6

    /// The stream screen's size, which everything below is measured in (origin at its top left).
    let size: CGSize
    /// The picture's pane: the frame the video is drawn in, aspect-fit, and the viewport the Mac
    /// fits windows to.
    let picture: CGRect
    let row1: CGRect
    /// Row 1's buttons, in `Button` order.
    let buttons: [CGRect]
    let strip: CGRect
    /// Row 3.
    let keys: CGRect
    let caps: [CGRect]
    let trackpad: CGRect
    /// The pad's vertical motion is measured against this, not its height: its width ÷ 1.6, so a
    /// stroke moves the pointer as far down as across on a 16:10 picture, however tall the pad is.
    let trackpadSpan: CGFloat
    /// The Aa ruler while a finger holds Aa: centred on it, over row 1, and never past the row's
    /// leading edge; `rulerStep` is its points per detent.
    let ruler: CGRect
    let rulerStep: CGFloat
    /// The app drawer, from under row 1 at the leading edge, and the Settings panel, from under row
    /// 1 at the trailing edge; each is at most this tall (the panel follows its content).
    let drawer: CGRect
    let settings: CGRect
    /// The Settings panel's top-trailing corner as fractions of `size`: where it grows from.
    let settingsAnchor: CGPoint
    /// What the drawer's dim and the panel's tap catcher cover: everything but row 1's band, which
    /// stays live while they are open, as the landscape bar does.
    let dim: [CGRect]

    /// Everything but the picture and the trackpad, top to bottom: 228 pt.
    static var fixedHeight: CGFloat {
        margin + margin + underPicture + buttonHeight + rowGap + stripHeight + rowGap + capHeight + rowGap + bottom
    }

    init(size: CGSize) {
        self.size = size
        let width = size.width, height = size.height

        // The picture: full width less the margins, 16:10, unless the trackpad would drop under
        // its least height; then the picture gives way (to nothing, at worst).
        let pictureWidth = max(0, width - 2 * Self.margin)
        let natural = (pictureWidth / Self.aspect).rounded(.down)
        let pictureHeight = min(natural, max(0, height - Self.fixedHeight - Self.minTrackpad))
        picture = CGRect(x: Self.margin, y: Self.margin, width: pictureWidth, height: pictureHeight)

        // Row 1: five equal buttons across the row, `gap` apart.
        let rowWidth = max(0, width - 2 * Self.side)
        row1 = CGRect(x: Self.side, y: picture.maxY + Self.margin + Self.underPicture,
                      width: rowWidth, height: Self.buttonHeight)
        buttons = Self.split(row1, count: Button.allCases.count, gap: Self.gap)

        // Row 2: the strip, wider than the rows by its own padding.
        strip = CGRect(x: Self.side - Self.stripInset, y: row1.maxY + Self.rowGap,
                       width: max(0, width - 2 * (Self.side - Self.stripInset)), height: Self.stripHeight)

        // Row 3: six equal caps, `gap` apart.
        keys = CGRect(x: Self.side, y: strip.maxY + Self.rowGap, width: rowWidth, height: Self.capHeight)
        caps = Self.split(keys, count: Self.capCount, gap: Self.gap)

        // The trackpad: the rest, to `bottom` above the screen's edge.
        let padTop = keys.maxY + Self.rowGap
        trackpad = CGRect(x: Self.side, y: padTop, width: rowWidth, height: max(0, height - Self.bottom - padTop))
        trackpadSpan = trackpad.width / Self.aspect

        // The ruler, centred on Aa: as wide as the room between Aa's centre and the row's leading
        // edge allows, at most `maxRulerStep` a detent.
        let aa = buttons[Button.textSize.rawValue]
        let room = (aa.midX - row1.minX) * 2 - 2 * Self.rulerInset
        rulerStep = max(0, min(Self.maxRulerStep, room / Self.rulerSpans))
        let rulerWidth = rulerStep * Self.rulerSpans + 2 * Self.rulerInset
        ruler = CGRect(x: aa.midX - rulerWidth / 2, y: row1.minY, width: rulerWidth, height: Self.buttonHeight)

        // The drawer and the panel hang under row 1, down to the trackpad's bottom.
        let panelTop = row1.maxY + Self.panelGap
        let panelHeight = max(0, height - Self.bottom - panelTop)
        drawer = CGRect(x: Self.side, y: panelTop, width: min(Self.drawerWidth, rowWidth), height: panelHeight)
        let settingsWidth = min(Self.settingsWidth, rowWidth)
        settings = CGRect(x: width - Self.side - settingsWidth, y: panelTop, width: settingsWidth, height: panelHeight)
        settingsAnchor = CGPoint(x: width > 0 ? settings.maxX / width : 1, y: height > 0 ? settings.minY / height : 0)

        dim = [CGRect(x: 0, y: 0, width: width, height: row1.minY),
               CGRect(x: 0, y: row1.maxY, width: width, height: max(0, height - row1.maxY))]
    }

    /// `count` equal parts of `row`, `gap` apart, filling it.
    private static func split(_ row: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        let each = max(0, (row.width - CGFloat(count - 1) * gap) / CGFloat(count))
        return (0..<count).map { i in
            CGRect(x: row.minX + CGFloat(i) * (each + gap), y: row.minY, width: each, height: row.height)
        }
    }
}
