import CoreGraphics

/// Where everything goes on a phone held upright (Noah, 2026-09-27; docs/iphone-portrait-plan.md):
/// the picture in a fixed 16:10 pane at the top, then row 1 (Apps, Aa, Keyboard, Shortcuts,
/// Settings, widened to the row), row 2 (the Desktop, then the window thumbnails), row 3 (esc, tab, ctrl, opt, cmd,
/// shift), and the trackpad in everything left. Every rectangle is a function of the stream
/// screen's size alone, the screen less its top safe-area inset down to its bottom edge (the stream
/// screen ignores the bottom inset and the keyboard), so nothing moves when the streamed window
/// changes shape (a 16:9 one gets black bars above and below) or the keyboard comes up (it covers
/// the trackpad; row 1, with the Keyboard button, stays above it on every phone).
///
/// Larger Picture (Settings › This iPhone, issue #58; docs/larger-picture-plan.md): with the switch
/// on while a window streams (`largerPicture(switchOn:streaming:)`; the Desktop and nothing
/// streaming keep the standard arrangement) and the software keyboard's height known (`keyboard`),
/// the thumbnails' row goes and the picture gets every point that keeps the key row
/// `keyboardClearance` above the keyboard (on an 18 Pro Max 424×422 against 424×265); the trackpad
/// is the keyboard's footprint, so nothing moves when it comes up, and the Apps drawer opens above
/// row 1, where no keyboard reaches (`drawer`). The picture's frame then takes the picture's own
/// shape inside that room (`pane(video:)`, so a 16:10 window keeps its shape and a taller one
/// gains), and the viewport is the whole room, which the Mac fits a window to once Aa sets its text
/// size (or on the virtual display). It applies only where it makes the picture larger
/// (`largerPictureGains`: not where Display Zoom makes the screen 320 pt wide). Every rectangle is
/// still a function of the screen's size, the keyboard's height and the switch (with what streams)
/// alone; the frame and the trackpad's span also of the picture's shape.
///
/// `DuoLayout.outerPortrait` on an iPhone draws this (`DuoLayout.phoneArrangement`): every iPhone
/// upright, and the Duo's outer display upright; an iPad window that narrow keeps the compact halves.
/// The vertical rhythm is the approved mockup's, with the compact halves' paddings and gaps: 24 pt
/// from the picture to the buttons and 22 from the buttons to the thumbnails, as the compact window
/// bar centres its 50 pt buttons in 62 (so 412×389 pt of trackpad on an 18 Pro Max, 374×331 on an
/// 18 Pro). Pure (CoreGraphics only), so `Tests/checks/phone-portrait` compiles it with swiftc and
/// checks it at every size.
struct PhonePortraitLayout: Equatable {
    /// Around the picture: its pane's margin from the screen's sides and top.
    static let margin: CGFloat = 8
    /// The picture's shape: 16:10, the shape most Mac windows and displays have. Whole points,
    /// rounded down, so it is never taller than 16:10 and the rows below sit on whole points.
    static let aspect: CGFloat = 1.6
    /// From the picture's margin to row 1's band.
    static let underPicture: CGFloat = 10
    /// Row 1 sits in a band 12 pt taller than its buttons, the buttons centred, as the compact window
    /// bar holds its 50 pt buttons in 62: 6 pt above and below them. So 24 pt from the picture to the
    /// buttons (8 + 10 + 6) and 16 from the buttons to the strip (6 + 10), whose thumbnails sit 6 pt
    /// into it: 22 from the buttons to the thumbnails, the mockup Noah approved.
    static let band: CGFloat = 6
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
    /// The least trackpad there is: only a screen too short for it makes the picture give way, and
    /// the shortest phone only just (an iPhone SE with Display Zoom, 320×548 under its status bar:
    /// the picture 188 pt tall, 2 pt short of 16:10).
    static let minTrackpad: CGFloat = 120
    /// From row 1 to the drawer and the Settings panel, which hang under it.
    static let panelGap: CGFloat = 8
    /// The Aa ruler's finger travel per detent at most, and `TextScaleControl.sliderInset`, the room
    /// either side of its four detent spans.
    static let maxRulerStep: CGFloat = 36
    static let rulerInset: CGFloat = 30
    static let rulerSpans: CGFloat = 4

    // MARK: Larger Picture

    /// Larger Picture: the key row's bottom at least this far above the software keyboard's top.
    static let keyboardClearance: CGFloat = 10
    /// The software keyboard as Sill's input view shows it on an iPhone held upright (autocorrection
    /// is off, so it has no suggestions bar), measured on the iOS 27 simulators
    /// (docs/larger-picture-plan.md, Results): 233 pt on an iPhone with a Home button (the SE); with
    /// Face ID, by the stream screen's width, 320 from 414 pt (the 11 and 11 Pro Max, the Plus and
    /// Pro Max sizes, the Air), 301 from 390 (the 12 to 18, 16e, 17e, the Pros), and 310 from 375
    /// (the 12 and 13 mini; the 11 Pro's is 301). Narrower than any phone (Display Zoom), the
    /// tallest, 320, so the key row stays clear of a keyboard nobody measured.
    static let homeButtonKeyboard: CGFloat = 233
    static let faceIDKeyboard: CGFloat = 301
    static let miniKeyboard: CGFloat = 310
    static let wideKeyboard: CGFloat = 320
    static let wideKeyboardFrom: CGFloat = 414
    static let faceIDKeyboardFrom: CGFloat = 390
    static let miniKeyboardFrom: CGFloat = 375
    /// A Home-button iPhone's stream screen is less than this many times as tall as it is wide (the
    /// SE's 375×647, 1.73; with Display Zoom 320×548, 1.71); one with Face ID is 2.0 or more (from
    /// the 13 mini's 375×762 to a Plus's 428×879, and the same shape with Display Zoom), so the shape
    /// tells them apart however the screen is zoomed. (The Duo's cover, 382×678, would read as one
    /// with a Home button; its keyboard is not known, so Larger Picture leaves it alone: `keyboard`.)
    static let faceIDShape: CGFloat = 1.9
    /// Larger Picture's row 1 holds six buttons (Menus with the five), each at least this wide: a
    /// touch target's least, so the arrangement needs a stream screen 332 pt wide or more.
    static let minButtonWidth: CGFloat = 44

    /// Row 1, in the landscape bar's order but with Shortcuts in the Desktop's place: on a phone the
    /// Desktop is the strip's first tile (Raffael, 2026-10-21).
    enum Button: Int, CaseIterable { case apps, textSize, keyboard, shortcuts, settings }
    /// Row 3's caps: esc, tab, ctrl, opt, cmd, shift.
    static let capCount = 6

    /// The stream screen's size, which everything below is measured in (origin at its top left).
    let size: CGSize
    /// Larger Picture's keyboard: the software keyboard's height the rows are kept above, which makes
    /// this the Larger Picture arrangement; nil for the standard one.
    let keyboard: CGFloat?
    /// The picture's pane: the frame the video is drawn in, aspect-fit, and the viewport the Mac
    /// fits windows to. With Larger Picture, the picture's room: the viewport still, but the frame is
    /// the picture's own shape inside it (`pane(video:)`).
    let picture: CGRect
    /// Row 1's buttons, across the row and 50 pt tall (their band is 6 pt more above and below).
    let row1: CGRect
    /// Row 1's buttons, in `Button` order.
    let buttons: [CGRect]
    /// Row 1's buttons while the Mac sent its menus, in `Button` order: as `buttons`, but with Larger
    /// Picture, where the Menus button joins row 1 after Apps (the strip, its usual row, is gone),
    /// five of six across the row.
    let buttonsBesideMenus: [CGRect]
    /// Row 2, the thumbnails. With Larger Picture none: a row of no height at row 1's band's bottom.
    let strip: CGRect
    /// The Menus button while the Mac sent its menus: in row 2 at the row's end, under Settings and
    /// as wide, as tall as row 1's buttons and centred in the strip's height, and the strip ending
    /// `gap` before it (docs/menu-bar-plan.md §7.5), row 1 keeping its five; with Larger Picture in
    /// row 1, the second of six (`buttonsBesideMenus`), as the landscape bar has it after Apps.
    let menus: CGRect
    let stripBesideMenus: CGRect
    /// Row 3.
    let keys: CGRect
    let caps: [CGRect]
    let trackpad: CGRect
    /// The pad's vertical motion is measured against this, not its height: its width ÷ 1.6, so a
    /// stroke moves the pointer as far down as across on a 16:10 picture, however tall the pad is.
    /// With Larger Picture the picture's own shape decides (`trackpadSpan(video:)`).
    let trackpadSpan: CGFloat
    /// The Aa ruler while a finger holds Aa: centred on it, over row 1, and never past the row's
    /// leading edge; `rulerStep` is its points per detent.
    let ruler: CGRect
    let rulerStep: CGFloat
    /// The same, on Aa of `buttonsBesideMenus`.
    let rulerBesideMenus: CGRect
    let rulerStepBesideMenus: CGFloat
    /// The app drawer and the Settings panel, from under row 1 across its whole span (Apps' leading
    /// edge to Settings' trailing one), so nothing cut shows beside them; each is at most this tall
    /// (the panel follows its content). With Larger Picture the drawer is above row 1 instead, over
    /// the picture's room, clear of any keyboard (on an 18 Pro Max 412×438 from 8).
    let drawer: CGRect
    let settings: CGRect
    /// The Settings panel's top-trailing corner as fractions of `size`: where it grows from.
    let settingsAnchor: CGPoint
    /// What the drawer's dim and the panel's tap catcher cover: everything but row 1's buttons,
    /// which stay live while they are open, as the landscape bar does.
    let dim: [CGRect]

    /// Whether this is the Larger Picture arrangement (no thumbnails' row).
    var largerPicture: Bool { keyboard != nil }

    /// Everything but the picture and the trackpad, top to bottom: 240 pt.
    static var fixedHeight: CGFloat {
        margin + margin + underPicture + band + buttonHeight + band + rowGap + stripHeight + rowGap + capHeight
            + rowGap + bottom
    }

    /// Larger Picture: everything but the picture above the keyboard's top, top to bottom: 152 pt
    /// (no strip; the key row `keyboardClearance` above the keyboard).
    static var largerFixedHeight: CGFloat {
        margin + margin + underPicture + band + buttonHeight + band + capHeight + rowGap + keyboardClearance
    }

    /// `keyboard`: Larger Picture above a software keyboard this tall (`PhonePortraitLayout.keyboard(for:…)`),
    /// or nil for the standard arrangement.
    init(size: CGSize, keyboard: CGFloat? = nil) {
        self.size = size
        self.keyboard = keyboard
        let width = size.width, height = size.height

        // The picture: full width less the margins, 16:10, unless the trackpad would drop under
        // its least height; then the picture gives way (to nothing, at worst).
        let pictureWidth = max(0, width - 2 * Self.margin)
        let natural = (pictureWidth / Self.aspect).rounded(.down)
        let pictureHeight = min(natural, max(0, height - Self.fixedHeight - Self.minTrackpad))
        // Larger Picture: every point above the keyboard but the rows', in whole points; the
        // keyboard's footprint is never less than the least trackpad and its margin.
        let footprint = keyboard.map { max($0, Self.minTrackpad + Self.bottom) }
        let largerHeight = footprint.map { max(0, (height - $0 - Self.largerFixedHeight).rounded(.down)) }
        picture = CGRect(x: Self.margin, y: Self.margin, width: pictureWidth, height: largerHeight ?? pictureHeight)

        // Row 1: five equal buttons across the row, `gap` apart, centred in their band.
        let rowWidth = max(0, width - 2 * Self.side)
        row1 = CGRect(x: Self.side, y: picture.maxY + Self.margin + Self.underPicture + Self.band,
                      width: rowWidth, height: Self.buttonHeight)
        buttons = Self.split(row1, count: Button.allCases.count, gap: Self.gap)

        let settingsButton = buttons[Button.settings.rawValue]
        if footprint == nil {
            // Row 2: the strip, under row 1's band, wider than the rows by its own padding. With the
            // Mac's menus, the Menus button under Settings, and the strip up to `gap` before it.
            strip = CGRect(x: Self.side - Self.stripInset, y: row1.maxY + Self.band + Self.rowGap,
                           width: max(0, width - 2 * (Self.side - Self.stripInset)), height: Self.stripHeight)
            menus = CGRect(x: settingsButton.minX, y: strip.minY + (Self.stripHeight - Self.buttonHeight) / 2,
                           width: settingsButton.width, height: Self.buttonHeight)
            stripBesideMenus = CGRect(x: strip.minX, y: strip.minY, width: max(0, menus.minX - Self.gap - strip.minX), height: strip.height)
            buttonsBesideMenus = buttons
        } else {
            // Larger Picture: no strip, so the key row comes straight under row 1's band; the Menus
            // button joins row 1 after Apps, six sharing the row.
            let six = Self.split(row1, count: Button.allCases.count + 1, gap: Self.gap)
            let gone = CGRect(origin: CGPoint(x: Self.side - Self.stripInset, y: row1.maxY + Self.band),
                              size: CGSize(width: max(0, width - 2 * (Self.side - Self.stripInset)), height: 0))
            strip = gone
            stripBesideMenus = gone
            menus = six[1]
            buttonsBesideMenus = [six[0]] + six.dropFirst(2)
        }

        // Row 3: six equal caps, `gap` apart.
        keys = CGRect(x: Self.side, y: strip.maxY + Self.rowGap, width: rowWidth, height: Self.capHeight)
        caps = Self.split(keys, count: Self.capCount, gap: Self.gap)

        // The trackpad: the rest, to `bottom` above the screen's edge. With Larger Picture the
        // keyboard's footprint, from its top (`keyboardClearance` under the key row).
        var padTop = keys.maxY + Self.rowGap
        if let footprint { padTop = max(keys.maxY + Self.keyboardClearance, height - footprint) }
        trackpad = CGRect(x: Self.side, y: padTop, width: rowWidth, height: max(0, height - Self.bottom - padTop))
        trackpadSpan = trackpad.width / Self.aspect

        // The ruler, centred on Aa: as wide as the room between Aa's centre and the row's leading
        // edge allows, at most `maxRulerStep` a detent.
        (ruler, rulerStep) = Self.ruler(on: buttons[Button.textSize.rawValue], in: row1)
        (rulerBesideMenus, rulerStepBesideMenus) = Self.ruler(on: buttonsBesideMenus[Button.textSize.rawValue], in: row1)

        // The drawer and the panel hang under row 1 and span it, down to the trackpad's bottom. With
        // Larger Picture the drawer opens upward instead, over the picture's room to `panelGap` above
        // row 1: under row 1 is the keyboard's footprint, so a keyboard up (the Mac's, or the one the
        // drawer's own search field brings) would leave only the search field in view there. The
        // panel stays under row 1: opening it takes the keyboard down, and the picture stays in view.
        let panelTop = row1.maxY + Self.panelGap
        let panelHeight = max(0, height - Self.bottom - panelTop)
        if footprint == nil {
            drawer = CGRect(x: Self.side, y: panelTop, width: rowWidth, height: panelHeight)
        } else {
            drawer = CGRect(x: Self.side, y: Self.margin, width: rowWidth, height: max(0, row1.minY - Self.panelGap - Self.margin))
        }
        settings = CGRect(x: Self.side, y: panelTop, width: rowWidth, height: panelHeight)
        settingsAnchor = CGPoint(x: width > 0 ? settings.maxX / width : 1, y: height > 0 ? settings.minY / height : 0)

        dim = [CGRect(x: 0, y: 0, width: width, height: row1.minY),
               CGRect(x: 0, y: row1.maxY, width: width, height: max(0, height - row1.maxY))]
    }

    /// The frame the video is drawn in, for a picture of `video`'s shape (pixels; zero before the
    /// first frame, taken as 16:10): `picture` in the standard arrangement, whatever the video. With
    /// Larger Picture the picture's own shape inside the room, from its top: as wide as the room and
    /// as tall as the shape asks (a 16:10 window keeps its shape, a taller one gains), or, for a
    /// shape taller than the room, as tall as the room and centred across it. Whole points, rounded
    /// down past a hundredth of a point, so a window the Mac fitted to the room fills it exactly.
    func pane(video: CGSize) -> CGRect {
        guard largerPicture, picture.width > 0, picture.height > 0 else { return picture }
        let known = video.width > 0 && video.height > 0
        let (w, h) = known ? (video.width, video.height) : (Self.aspect, 1)
        let tall = picture.width * h / w
        if tall <= picture.height + 0.01 {
            return CGRect(x: picture.minX, y: picture.minY, width: picture.width,
                          height: min(picture.height, (tall + 0.01).rounded(.down)))
        }
        let wide = min(picture.width, (picture.height * w / h + 0.01).rounded(.down))
        return CGRect(x: picture.minX + ((picture.width - wide) / 2).rounded(.down), y: picture.minY,
                      width: wide, height: picture.height)
    }

    /// What the pad's vertical motion is measured against for a picture of `video`'s shape:
    /// `trackpadSpan` in the standard arrangement (its width ÷ 1.6, whatever the picture). With
    /// Larger Picture the picture's own shape (its frame, `pane(video:)`): the pad's width across
    /// moves the pointer the frame's width, and the span down its height, so the pointer moves as far
    /// down as across whatever the window's shape.
    func trackpadSpan(video: CGSize) -> CGFloat {
        guard largerPicture else { return trackpadSpan }
        let frame = pane(video: video)
        guard frame.width > 0, frame.height > 0 else { return trackpadSpan }
        return trackpad.width * frame.height / frame.width
    }

    /// The software keyboard's height on a phone whose stream screen is `container` (its screen less
    /// the top inset), upright: from the shape and the width, as measured (see `homeButtonKeyboard`).
    static func keyboardHeight(for container: CGSize) -> CGFloat {
        guard container.width > 0, container.height / container.width >= faceIDShape else { return homeButtonKeyboard }
        if container.width >= wideKeyboardFrom { return wideKeyboard }
        if container.width >= faceIDKeyboardFrom { return faceIDKeyboard }
        if container.width >= miniKeyboardFrom { return miniKeyboard }
        return wideKeyboard
    }

    /// What streams, as Larger Picture sees it: nothing (connecting, before the Desktop starts; a window
    /// closed, or off the Mac's list for a moment; a pick that failed), the Mac's whole Desktop, or a
    /// window: `StreamClient.active`'s three cases (StreamScreen maps them).
    enum Streaming: CaseIterable { case nothing, desktop, window }

    /// Larger Picture in effect: the switch on while a window streams, the one rule for everything the
    /// switch decides (the arrangement, its viewport, the tour's targets and words), which
    /// `keyboard(for:largerPicture:foldable:)` then places. The Desktop keeps the standard arrangement
    /// (Noah, 2026-10-15, on his iPhone 15 Pro: "when in Desktop mode, there is negative space on the
    /// bottom, seemingly because of the Mac aspect ratio"): Aa never resizes the Desktop, so the room's
    /// extra height could only ever be black under it. So does nothing streaming, so the Desktop a
    /// device asks for then (as it connects, and once a window has closed) arrives into the
    /// arrangement it keeps, with no flip after its first picture. The Mac never passes through
    /// nothing between two windows (it names the old one until the new one streams), so a switch
    /// from window to window keeps Larger Picture throughout.
    static func largerPicture(switchOn: Bool, streaming: Streaming) -> Bool {
        switchOn && streaming == .window
    }

    /// Larger Picture's keyboard for a stream screen of `container`: its estimate while Larger Picture
    /// is in effect (`largerPicture`: `largerPicture(switchOn:streaming:)`, which the stream screen
    /// holds while its Settings panel is open), on a phone without a hinge, where Larger Picture earns
    /// its name (`largerPictureGains`); nil (the standard arrangement) with the switch off, while the
    /// Desktop or nothing streams, on the iPhone Duo (`foldable`), whose cover's keyboard nobody has
    /// measured, and where the picture would not be larger.
    static func keyboard(for container: CGSize, largerPicture: Bool, foldable: Bool) -> CGFloat? {
        guard largerPicture, !foldable else { return nil }
        let keyboard = keyboardHeight(for: container)
        return largerPictureGains(container, keyboard: keyboard) ? keyboard : nil
    }

    /// Whether Larger Picture above a keyboard `keyboard` tall earns its name on a stream screen of
    /// `container`: its room taller than today's picture, and row 1's six buttons a touch target wide
    /// (`minButtonWidth`). Not so where Display Zoom makes the screen 320 pt wide (the SE, the minis
    /// and the 6.1-inch iPhones): a 6.1-inch one's room would be 304×173 against today's 304×190, the
    /// zoomed SE's 304×163 against 304×188, and six buttons 42 pt. There the layout stays today's and
    /// the Settings panel has no switch (`offersLargerPicture`).
    static func largerPictureGains(_ container: CGSize, keyboard: CGFloat) -> Bool {
        let larger = PhonePortraitLayout(size: container, keyboard: keyboard)
        return larger.picture.height > PhonePortraitLayout(size: container).picture.height
            && larger.menus.width >= minButtonWidth
    }

    /// Whether the Settings panel offers Larger Picture on a phone (without a hinge) whose stream
    /// screen is `screen` now, in either orientation: judged on it held upright, the shorter side
    /// across, and whatever streams: as for a window, the only source it acts on (the Desktop keeps
    /// the standard arrangement with the switch on, `largerPicture(switchOn:streaming:)`). On its
    /// side the stream screen's longer side is short of the upright one by the side insets (a notch's
    /// 44 to 68 pt each, none on an SE), which leaves the answer the same on every iPhone, zoomed or
    /// not (Tests/checks/phone-portrait).
    static func offersLargerPicture(screen: CGSize) -> Bool {
        let upright = CGSize(width: min(screen.width, screen.height), height: max(screen.width, screen.height))
        return keyboard(for: upright, largerPicture: true, foldable: false) != nil
    }

    /// The ruler centred on `aa`, over `row`: as wide as the room between Aa's centre and the row's
    /// leading edge allows, at most `maxRulerStep` a detent.
    static func ruler(on aa: CGRect, in row: CGRect) -> (CGRect, CGFloat) {
        let room = (aa.midX - row.minX) * 2 - 2 * rulerInset
        let rulerStep = max(0, min(maxRulerStep, room / rulerSpans))
        let rulerWidth = rulerStep * rulerSpans + 2 * rulerInset
        return (CGRect(x: aa.midX - rulerWidth / 2, y: row.minY, width: rulerWidth, height: buttonHeight), rulerStep)
    }

    /// `count` equal parts of `row`, `gap` apart, filling it.
    static func split(_ row: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        let each = max(0, (row.width - CGFloat(count - 1) * gap) / CGFloat(count))
        return (0..<count).map { i in
            CGRect(x: row.minX + CGFloat(i) * (each + gap), y: row.minY, width: each, height: row.height)
        }
    }
}

/// Full Screen on a phone held upright (Raffael, 2026-10-21): the picture takes the whole screen, edge
/// to edge, behind the status bar, and the controls float at the bottom over it: a handle (the input
/// mode, collapse or expand, leave Full Screen) and, expanded, row 1 and the key row under it, as the
/// usual arrangement has them. Collapsed, only the handle. A software keyboard up lifts them above it
/// (`keyboard`), so row 1's Keyboard can take it down. The drawer and the Settings panel hang from the
/// top, under the screen's top inset, down to just above the controls. Every rectangle is a function
/// of the screen's size, its insets, the keyboard and whether the controls are expanded; pure, so
/// `Tests/checks/phone-portrait` checks it with the usual arrangement.
struct FullScreenLayout: Equatable {
    static let handleHeight: CGFloat = 36
    /// Around the controls' ground: above the handle, and under the key row to the bottom inset.
    static let pad: CGFloat = 8
    /// The handle's three buttons, each this wide (and the handle's height tall).
    static let handleButton: CGFloat = 56

    let size: CGSize
    /// The picture's room, which is also its viewport (the Mac fits a window to it, as to a display):
    /// from under the status bar and the notch to just above the controls (to the handle's top, collapsed), and so above
    /// the keyboard while it is up.
    let picture: CGRect
    /// The handle's band, the rows' width; its buttons are `mode` (leading), `collapse` (centre) and
    /// `exit` (trailing).
    let handle: CGRect
    let mode: CGRect
    let collapse: CGRect
    let exit: CGRect
    /// Row 1 and the key row, expanded; zero height collapsed (nothing there).
    let row1: CGRect
    let buttons: [CGRect]
    /// Row 1 while the Mac sent its menus: Menus after Apps, six across (no strip to hold it here).
    let buttonsBesideMenus: [CGRect]
    let menus: CGRect
    let rulerBesideMenus: CGRect
    let rulerStepBesideMenus: CGFloat
    let keys: CGRect
    let caps: [CGRect]
    /// The controls' ground, from just above the handle to the screen's bottom; collapsed, none.
    let ground: CGRect
    let ruler: CGRect
    let rulerStep: CGFloat
    let drawer: CGRect
    let settings: CGRect
    let settingsAnchor: CGPoint
    /// What the drawer's dim and the panel's tap catcher cover: everything above the controls.
    let dim: [CGRect]
    let expanded: Bool

    /// `top` and `bottom`: the screen's safe-area insets (the status bar's and the home indicator's);
    /// `keyboard`: the software keyboard's height while it is up, else nil.
    init(size: CGSize, top: CGFloat, bottom: CGFloat, keyboard: CGFloat?, expanded: Bool) {
        self.size = size
        self.expanded = expanded
        let width = size.width, height = size.height
        let rowWidth = max(0, width - 2 * PhonePortraitLayout.side)
        let lift = max(bottom, keyboard.map { $0 + PhonePortraitLayout.keyboardClearance } ?? 0, Self.pad)
        let floor = height - lift
        if expanded {
            keys = CGRect(x: PhonePortraitLayout.side, y: floor - PhonePortraitLayout.capHeight,
                          width: rowWidth, height: PhonePortraitLayout.capHeight)
            row1 = CGRect(x: PhonePortraitLayout.side, y: keys.minY - PhonePortraitLayout.rowGap - PhonePortraitLayout.buttonHeight,
                          width: rowWidth, height: PhonePortraitLayout.buttonHeight)
            handle = CGRect(x: PhonePortraitLayout.side, y: row1.minY - PhonePortraitLayout.band - Self.handleHeight,
                            width: rowWidth, height: Self.handleHeight)
            ground = CGRect(x: 0, y: handle.minY - Self.pad, width: width, height: max(0, height - handle.minY + Self.pad))
        } else {
            handle = CGRect(x: PhonePortraitLayout.side, y: floor - Self.handleHeight, width: rowWidth, height: Self.handleHeight)
            row1 = CGRect(x: PhonePortraitLayout.side, y: handle.maxY, width: rowWidth, height: 0)
            keys = CGRect(x: PhonePortraitLayout.side, y: handle.maxY, width: rowWidth, height: 0)
            ground = .zero
        }
        buttons = PhonePortraitLayout.split(row1, count: PhonePortraitLayout.Button.allCases.count, gap: PhonePortraitLayout.gap)
        caps = PhonePortraitLayout.split(keys, count: PhonePortraitLayout.capCount, gap: PhonePortraitLayout.gap)
        let b = Self.handleButton
        mode = CGRect(x: handle.minX, y: handle.minY, width: b, height: handle.height)
        collapse = CGRect(x: handle.midX - b / 2, y: handle.minY, width: b, height: handle.height)
        exit = CGRect(x: handle.maxX - b, y: handle.minY, width: b, height: handle.height)
        (ruler, rulerStep) = PhonePortraitLayout.ruler(on: buttons[PhonePortraitLayout.Button.textSize.rawValue], in: row1)
        var withMenus = PhonePortraitLayout.split(row1, count: PhonePortraitLayout.Button.allCases.count + 1, gap: PhonePortraitLayout.gap)
        menus = withMenus.remove(at: 1)
        buttonsBesideMenus = withMenus
        (rulerBesideMenus, rulerStepBesideMenus) = PhonePortraitLayout.ruler(
            on: buttonsBesideMenus[PhonePortraitLayout.Button.textSize.rawValue], in: row1)
        let panelTop = max(top, Self.pad) + PhonePortraitLayout.panelGap
        let panelBottom = (expanded ? ground.minY : handle.minY) - PhonePortraitLayout.panelGap
        drawer = CGRect(x: PhonePortraitLayout.side, y: panelTop, width: rowWidth, height: max(0, panelBottom - panelTop))
        settings = drawer
        settingsAnchor = CGPoint(x: settings.maxX / max(width, 1), y: settings.minY / max(height, 1))
        dim = [CGRect(x: 0, y: 0, width: width, height: max(0, expanded ? ground.minY : handle.minY))]
        // Under the status bar and the notch, never behind them (the status bar shows).
        picture = CGRect(x: 0, y: top, width: width, height: max(0, (expanded ? ground.minY : handle.minY - Self.pad) - top))
    }
}
