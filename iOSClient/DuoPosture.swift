import Foundation
import CoreGraphics

// The iPhone Duo's posture, and the layout rules that follow from it (docs/iphone-duo-plan.md).
//
// Pure: Foundation and CoreGraphics only, so Tests/checks/duo compiles it with swiftc on its own. Its
// inputs come from DuoPostureReader.swift, which reads iOS 27.1's hinge (`onHingeChange`) and the
// fold's reserved region (`GeometryProxy.reservedRegions(kind: .division)`). Before iOS 27.1, and on
// any device without a hinge (every iPhone and iPad until the Duo), nothing is known and every rule
// here answers exactly as the size alone did before (`FoldInfo.inferred`).
//
// What the device reports, measured on the iOS 27.1 simulator (the plan's Facts): one window scene
// that moves between the displays as the hinge closes and opens; on the inner display (951×669 pt
// sideways, 669×951 upright) a `.division` region 40 pt wide down the middle of its longer side (the
// crease at 475.5, with 20 pt of margin each side), active exactly while the hinge is partly open
// (the book and laptop poses) and inactive open flat; on the cover (466×678, 678×466) none.

/// What a layout knows of a fold across it.
enum FoldInfo: Equatable {
    /// Nothing known (before iOS 27.1, a device without a hinge): the rules infer the half-folded
    /// Duo's crease from the screen's size alone, exactly as before.
    case inferred
    /// The device said: the band nothing interactive sits on while the display is half-folded (the
    /// fold's reserved region, margins included, in the layout's own space and clipped to it), or
    /// nil when nothing is folded across this screen (open flat, the cover).
    case known(CGRect?)

    /// The band, when the device said there is one.
    var band: CGRect? {
        if case .known(let band) = self { return band }
        return nil
    }

    /// A fold down the middle of a screen held sideways: the book pose.
    var verticalBand: CGRect? {
        guard let band, band.height > band.width else { return nil }
        return band
    }

    /// A fold across a screen held upright: the laptop pose.
    var horizontalBand: CGRect? {
        guard let band, band.width >= band.height else { return nil }
        return band
    }
}

/// The posture as one screen of Sill sees it: the hinge, and the fold in that screen's own space.
struct DuoPosture: Equatable {
    /// The hinge as iOS 27.1 reports it (`DeviceHinge.Status`); `unknown` before iOS 27.1 and on a
    /// device without one.
    enum Hinge: String, Equatable {
        case unknown, closed, partiallyOpen, fullyOpen
    }

    /// The six poses, in duorig's words (Tests/duorig); `unknown` when nothing is known.
    enum Pose: String, Equatable {
        case unknown
        case book
        case laptop
        case flatLandscape = "flat-landscape"
        case flatPortrait = "flat-portrait"
        case closedUpright = "closed-upright"
        case closedSide = "closed-side"
    }

    var hinge: Hinge = .unknown
    /// The display's fold (its `.division` reserved region, margins included) in the screen's own
    /// space, in the way or not; nil on a display without one (the cover).
    var fold: CGRect? = nil

    static let unknown = DuoPosture()

    /// The fold is in the way exactly while the hinge is partly open: iOS reports the region active
    /// then and only then (90° and 174° alike), and the hinge's change is what redraws the layouts.
    var foldActive: Bool { hinge == .partiallyOpen && fold != nil }

    /// What the layout rules get for a screen of `size`.
    func info(in size: CGSize) -> FoldInfo {
        guard hinge != .unknown else { return .inferred }
        guard foldActive, let fold else { return .known(nil) }
        let band = fold.intersection(CGRect(origin: .zero, size: size))
        return .known(band.isNull || band.isEmpty ? nil : band)
    }

    /// Which of the six poses a screen of `size` is in.
    func pose(_ size: CGSize) -> Pose {
        let sideways = size.width > size.height
        switch hinge {
        case .unknown: return .unknown
        case .closed: return sideways ? .closedSide : .closedUpright
        case .partiallyOpen: return sideways ? .book : .laptop
        case .fullyOpen: return sideways ? .flatLandscape : .flatPortrait
        }
    }

    /// The hinge open: Sill is on the inner display (the book, laptop and open flat poses).
    var onInnerDisplay: Bool { hinge == .partiallyOpen || hinge == .fullyOpen }

    /// The hinge to go by: what `onHingeChange` reported, or, before its first call (a frame or two
    /// after launch on a device, longer in the simulator), what the display's fold says where it has
    /// one (only the inner display does): in the way, half-folded; not, open flat. Neither: unknown,
    /// as on every device without a hinge, where no display has a fold.
    static func hinge(reported: Hinge, regionActive: Bool?) -> Hinge {
        guard reported == .unknown, let regionActive else { return reported }
        return regionActive ? .partiallyOpen : .fullyOpen
    }

    /// Whether the stream screen hides the status bar: on the inner display in every pose (Noah,
    /// 2026-10-09: option 1 of the three the mock canvas drew side by side). Upright (the laptop
    /// pose, open flat upright) it would take 82 pt at the top out of the picture above the fold;
    /// sideways (the book pose, open flat sideways) an 84 pt strip at the side out of the picture's
    /// width, so Sill has all 951 pt and the book pose's bar keeps its regular size (`bookBar`). It
    /// stays on the cover, as on an iPhone, and on every other screen in every pose (the connect
    /// screen keeps the clock and the Wi-Fi it asks about). The alternatives: `pose == .laptop ||
    /// pose == .flatPortrait` here keeps it sideways; dropping StreamScreen's `.duoStatusBar` line
    /// keeps it everywhere.
    static func hidesStatusBar(_ pose: Pose) -> Bool {
        pose == .laptop || pose == .flatPortrait || pose == .book || pose == .flatLandscape
    }

    /// "book, the fold x 455.5–495.5 in the way, 951×669", for the DEBUG console.
    func describe(_ size: CGSize) -> String {
        func n(_ v: CGFloat) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", Double(v)) }
        var words = pose(size).rawValue
        if let fold {
            let along = fold.height > fold.width ? "x \(n(fold.minX))–\(n(fold.maxX))" : "y \(n(fold.minY))–\(n(fold.maxY))"
            words += ", the fold \(along) " + (foldActive ? "in the way" : "flat")
        }
        return words + ", \(n(size.width))×\(n(size.height))"
    }
}

// MARK: - The laptop pose: the crease across a screen held upright

extension DuoPosture {
    /// The fold across a screen held upright, its top and bottom edges. Known: the band of the
    /// laptop pose, else none (open flat nothing pins the split). Inferred, as before iOS 27.1: the
    /// middle of a screen taller than wide, 600 to 740 pt wide and under 1100 tall (the half-folded
    /// Duo as Sill's first numbers, 710×1000, guessed it), as a band of no height.
    static func crease(_ size: CGSize, _ fold: FoldInfo) -> (top: CGFloat, bottom: CGFloat)? {
        switch fold {
        case .inferred:
            guard size.height > size.width, size.width >= 600, size.width < 740, size.height < 1100 else { return nil }
            return (size.height / 2, size.height / 2)
        case .known:
            guard let band = fold.horizontalBand else { return nil }
            return (band.minY, band.maxY)
        }
    }

    /// The room above a fold the device reported across the screen (the laptop pose), from the
    /// screen's top: the connect screen's column lives and scrolls there, so that a long list or a
    /// card never runs onto the fold. Nil for the inferred crease (as before iOS 27.1, where the
    /// column is only centred in the top half) and without a fold across.
    static func roomAboveFold(_ size: CGSize, _ fold: FoldInfo) -> CGFloat? {
        guard case .known = fold, let crease = crease(size, fold) else { return nil }
        return max(0, crease.top)
    }

    /// The portrait halves' split (the inner display upright, an iPad's window): how tall the
    /// picture's pane is, from the top, and where the controls begin.
    struct PortraitSplit: Equatable {
        var picture: CGFloat
        var controls: CGFloat
    }

    /// The picture pane's padding round the picture (PortraitStreamScreen's `picturePane.padding(8)`).
    static let paneInset: CGFloat = 8
    /// Open flat, the picture pane is never shorter than this, and leaves the trackpad at least that.
    static let minimumPane: CGFloat = 160
    static let minimumTrackpad: CGFloat = 200
    /// 16:10, the shape of most Macs' displays and windows.
    static let defaultAspect: CGFloat = 1.6

    /// - Inferred (before iOS 27.1, an iPad): at the middle, as before.
    /// - The laptop pose (approved (b1)): the picture above the fold, the controls below it, at the
    ///   fold's real band (whole points, never into it).
    /// - Open flat upright (approved (b2)): nothing pins the split. The pane takes the picture's
    ///   shape across the screen's width (`aspect`, width over height), between `minimumPane` and
    ///   what leaves the controls (`controls`, their rows but the trackpad) a `minimumTrackpad`; the
    ///   trackpad grows into the rest.
    static func portraitSplit(_ size: CGSize, _ fold: FoldInfo, aspect: CGFloat, controls: CGFloat) -> PortraitSplit {
        switch fold {
        case .inferred:
            let half = (size.height / 2).rounded()
            return PortraitSplit(picture: half, controls: half)
        case .known:
            if let band = fold.horizontalBand {
                let top = max(0, band.minY.rounded(.down))
                let bottom = min(size.height, band.maxY.rounded(.up))
                return PortraitSplit(picture: top, controls: max(top, bottom))
            }
            let pictureWidth = max(0, size.width - 2 * paneInset)
            let natural = (pictureWidth / max(aspect, 0.1)).rounded() + 2 * paneInset
            let most = max(0, size.height - controls - minimumTrackpad)
            let least = min(minimumPane, most)
            let pane = min(max(natural, least), most)
            return PortraitSplit(picture: pane, controls: pane)
        }
    }

    /// The pane's shape open flat: the picture's own (`video`, in pixels) while the Mac keeps the
    /// window's shape; 16:10 before there is a picture, and while the Mac fits the window to the pane
    /// (a window with Aa set, or on the virtual display), so the pane never follows a shape it gave
    /// the window itself (an app's least size would shrink the pane step by step).
    static func paneAspect(video: CGSize, fitsWindowToPane: Bool) -> CGFloat {
        guard !fitsWindowToPane, video.width > 0, video.height > 0 else { return defaultAspect }
        return video.width / video.height
    }
}

// MARK: - The book pose: the fold down the middle of a screen held sideways

extension DuoPosture {
    /// The landscape bar in the book pose (approved (a)): Apps, the thumbnails, then the right group
    /// of buttons against the trailing edge, and nothing on the fold's band.
    struct BookBar: Equatable {
        var buttonWidth: CGFloat
        var gap: CGFloat
        /// The strip's width, so that it ends a gap short of the band; nil when there is no band in
        /// the bar (the strip as before).
        var stripWidth: CGFloat?
        /// The Settings panel's width: it hangs from the bar's trailing end, kept off the band.
        var panelWidth: CGFloat
        /// Whether the right group begins past the band (false only when no step makes it).
        var clears: Bool
    }

    /// The least gap the right group steps down to.
    static let minimumGap: CGFloat = 6

    /// The bar `width` wide, its `padding` at each end, its buttons `buttonWidth` wide with `gap`
    /// between everything, and a right group of `buttons` (Menus may come: count it). The group
    /// keeps its size while it begins past the band; else it takes `compactButtonWidth` (the
    /// approved step), then smaller gaps, down to `minimumGap`. The strip ends a gap short of the
    /// band; the Settings panel is at most as wide as the room past the band.
    static func bookBar(width: CGFloat, fold: FoldInfo, padding: CGFloat, gap: CGFloat, buttonWidth: CGFloat,
                        compactButtonWidth: CGFloat, buttons: Int, panelWidth: CGFloat) -> BookBar {
        let unchanged = BookBar(buttonWidth: buttonWidth, gap: gap, stripWidth: nil, panelWidth: panelWidth, clears: true)
        guard let band = fold.verticalBand, buttons > 0, band.minX > padding, band.maxX < width - padding else { return unchanged }
        let count = CGFloat(buttons)
        func start(_ button: CGFloat, _ g: CGFloat) -> CGFloat { width - padding - count * button - (count - 1) * g }
        var button = buttonWidth, g = gap
        if start(button, g) < band.maxX { button = min(button, compactButtonWidth) }
        if start(button, g) < band.maxX, buttons > 1 {
            let room = ((width - padding - count * button - band.maxX) / (count - 1)).rounded(.down)
            g = max(minimumGap, min(g, room))
        }
        let stripStart = padding + button + g          // after Apps
        let strip = max(0, band.minX - g - stripStart)
        let panel = min(panelWidth, max(0, width - padding - band.maxX))
        return BookBar(buttonWidth: button, gap: g, stripWidth: strip, panelWidth: panel, clears: start(button, g) >= band.maxX)
    }

    /// Something `width` wide at `x` on a screen `screenWidth` wide, kept off a vertical fold's band
    /// (a tour card): moved as little as it takes, against the fold, onto the page its middle is on
    /// (the leading one on a tie) when that page holds it within `margin` of the screen's edge, else
    /// onto the other page when that one does; unchanged when it is clear of the band, or when no
    /// page holds it.
    static func offTheFold(x: CGFloat, width: CGFloat, screenWidth: CGFloat, margin: CGFloat, fold: FoldInfo) -> CGFloat {
        guard let band = fold.verticalBand, x < band.maxX, x + width > band.minX else { return x }
        let leadingFits = width <= band.minX - margin
        let trailingFits = width <= screenWidth - margin - band.maxX
        let leading = band.minX - width, trailing = band.maxX
        if x + width / 2 <= band.midX {
            if leadingFits { return leading }
            if trailingFits { return trailing }
        } else {
            if trailingFits { return trailing }
            if leadingFits { return leading }
        }
        return x
    }

    /// Where the window lights' menu goes (WindowLightsMenu), `size` and centred on its thumbnail at
    /// `x`, on the side `below` says, `gap` from it: kept off the fold, beside a vertical one onto a
    /// page (`offTheFold`, 8 pt from the screen's edge), and below its thumbnail when above it would
    /// sit on a horizontal one (the laptop pose, whose window bar is just under the fold).
    static func lightsMenu(x: CGFloat, below: Bool, thumbnail: CGRect, size: CGSize, gap: CGFloat, screenWidth: CGFloat,
                           fold: FoldInfo) -> (x: CGFloat, y: CGFloat, below: Bool) {
        func rect(below: Bool) -> CGRect {
            CGRect(x: x - size.width / 2, y: below ? thumbnail.maxY + gap : thumbnail.minY - gap - size.height,
                   width: size.width, height: size.height)
        }
        var down = below
        if !down, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }
        let left = offTheFold(x: x - size.width / 2, width: size.width, screenWidth: screenWidth, margin: 8, fold: fold)
        return (left + size.width / 2, rect(below: down).midY, down)
    }

    /// The page beside a vertical fold that `target`'s middle is on (the leading one on a tie, as
    /// `offTheFold` decides), less the margin at the screen's edge: the most a card about it may be
    /// wide, so that it stays beside what it points at (with the status bar's strip shown, 867 pt,
    /// the trailing page is 355.5 and a 360 pt card about Settings would otherwise go to the far
    /// page). Without a target, the wider page. Nil without a vertical fold.
    static func pageWidth(screenWidth: CGFloat, margin: CGFloat, fold: FoldInfo, for target: CGRect? = nil) -> CGFloat? {
        guard let band = fold.verticalBand else { return nil }
        let leading = max(0, band.minX - margin), trailing = max(0, screenWidth - margin - band.maxX)
        guard let target, !target.isNull else { return max(leading, trailing) }
        return target.midX <= band.midX ? leading : trailing
    }

    /// The connect screen's column across the book pose's fold: centred in the leading page while
    /// it holds the column with 16 pt each side; elsewhere, as before, centred in the screen (at
    /// least 16 pt from its leading edge).
    static func columnX(columnWidth: CGFloat, screenWidth: CGFloat, fold: FoldInfo) -> CGFloat {
        let centred = max(16, (screenWidth - columnWidth) / 2)
        guard let band = fold.verticalBand, columnWidth + 32 <= band.minX else { return centred }
        return max(16, (band.minX - columnWidth) / 2)
    }

    /// The leading page's width, for content placed on it (the pairing overlay), when a vertical
    /// fold divides the screen.
    static func leadingPage(_ fold: FoldInfo) -> CGFloat? {
        fold.verticalBand.map { max(0, $0.minX) }
    }
}

// MARK: - The harness's stand-in (ContentView's -SillLayout and -SillHinge)

extension DuoPosture {
    /// The named space a harness's fake display defines, in which its stand-in fold is given.
    static let displaySpace = "sill.display"

    /// The hinge `-SillHinge closed|half|flat` stands in for.
    static func hinge(argument: String?) -> Hinge? {
        switch argument?.lowercased() {
        case "closed"?: return .closed
        case "half"?: return .partiallyOpen
        case "flat"?: return .fullyOpen
        default: return nil
        }
    }

    /// The fold the inner display reports, for the stand-in: 40 pt (20 each side of the crease)
    /// across the middle of the screen's longer side, in the display's own space.
    static func standInFold(_ size: CGSize) -> CGRect {
        size.width > size.height ? CGRect(x: size.width / 2 - 20, y: 0, width: 40, height: size.height)
                                 : CGRect(x: 0, y: size.height / 2 - 20, width: size.width, height: 40)
    }

    /// The safe area (top, leading, bottom, trailing) each of the Duo's displays gives Sill, as the
    /// probe measured it on the iOS 27.1 simulator: the inner display with its status bar, a strip
    /// of 84 pt at the side sideways and 82 at the top upright, and the home indicator's 34; with the
    /// status bar hidden (the stream screen on the inner display, `hidesStatusBar`), the 34 alone; the cover its
    /// camera's 84 pt strip at the right upright and at the left on its side (the duorig pose
    /// closed-side), and the 34, either way. Nil for any other size.
    static func displayInsets(_ size: CGSize, statusBarHidden: Bool = false) -> (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat)? {
        switch (size.width, size.height) {
        case (951, 669): return statusBarHidden ? (0, 0, 34, 0) : (0, 0, 34, 84)
        case (669, 951): return statusBarHidden ? (0, 0, 34, 0) : (82, 0, 34, 0)
        case (466, 678): return (0, 0, 34, 84)
        case (678, 466): return (0, 84, 34, 0)
        default: return nil
        }
    }
}
