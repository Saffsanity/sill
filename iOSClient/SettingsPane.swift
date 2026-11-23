import CoreGraphics

/// Settings as a whole-screen pane on every device and in every layout (docs/settings-pane-plan.md; Noah,
/// 2026-11-18: "Whole screen everywhere: Settings covers the stream completely on every device, with Done to go
/// back, like a settings page"): where its two parts go on the stream screen, around the iPhone Duo's fold, and
/// what each way of closing it brings. The parts are HostSettingsPanel's: the Mac's (the header with Done, the
/// Mac's groups, Disconnect) and this device's (This iPad's group, Take the Tour, the version); a feature's rows
/// go in the one whose they are.
///
/// Pure (CoreGraphics, and DuoPosture's FoldInfo), so Tests/checks/settings-pane compiles it with
/// DuoPosture.swift and checks it at every size, both ways round and around every fold.
enum SettingsPane {
    // MARK: - Where the parts go

    /// From the safe area's sides, and a fold's page's edges, to a column.
    static let margin: CGFloat = 16
    /// The book pose keeps a column to each page only where each gets at least this (the Duo's pages give
    /// 423.5 pt); a fold whose pages are narrower is not kept to (no device has one).
    static let minColumn: CGFloat = 300
    /// No column wider than this, so a row's words and its control stay near each other on an iPad.
    static let maxColumn: CGFloat = 600
    /// The laptop pose's pages: each at least this tall (the lower one above the home indicator), or the
    /// fold is not kept to (no device has such a fold: the Duo's pages are 455.5 and 421.5 pt).
    static let minPage: CGFloat = 200
    /// Under Disconnect pinned at the screen's foot, where the screen has no home indicator (`Layout.footBottom`).
    static let footGap: CGFloat = 16
    /// Under Disconnect at the foot of the laptop pose's upper page, over the fold.
    static let foldGap: CGFloat = 12

    /// Where the pane's parts go on a stream screen of `size` (the screen less its top and side safe areas,
    /// down to its bottom edge: the layouts' own space, in which the fold is given). One column on every screen
    /// without a fold to keep to, an iPad's and an iPhone's either way round (Noah, 2026-11-23: "Settings should
    /// not be 2 columns, please make it 1 column"); around the iPhone Duo's fold, so that nothing lies across
    /// it, a column on each page in the book pose and a page each side of it in the laptop pose.
    struct Layout: Equatable {
        enum Arrangement: String, Equatable {
            /// One scroll view under the header, Disconnect under it: both parts in one column.
            case oneColumn = "one column"
            /// The book pose: the Mac's part in a column on the leading page, this device's in one on the
            /// trailing page.
            case twoColumns = "two columns"
            /// The laptop pose: the Mac's part on the page above the fold, this device's below it.
            case twoPages = "two pages"
        }

        let size: CGSize
        let arrangement: Arrangement
        /// The Mac's part in the leading-edge space: x from the screen's leading edge (its left in English, its
        /// right in Arabic or Hebrew), y from its top. In one column the column both parts share.
        let mac: CGRect
        /// This device's part in that space: the trailing page's column, the lower page, or `mac` in one column.
        let device: CGRect
        /// The fold's band in that space, when the parts keep off it; nil otherwise.
        let band: CGRect?
        /// What the content keeps clear of at the screen's bottom edge (the home indicator).
        let bottom: CGFloat
        let rightToLeft: Bool

        /// `bottomInset`: the safe area's at the bottom edge. `fold`: the Duo's fold across the screen
        /// (StreamScreen's `\.duoFold`), in the screen's own space, left to right.
        init(size: CGSize, bottomInset: CGFloat, fold: FoldInfo, rightToLeft: Bool = false) {
            let W = max(0, size.width), H = max(0, size.height)
            let m = SettingsPane.margin
            self.size = size
            self.bottom = max(0, bottomInset)
            self.rightToLeft = rightToLeft
            let column = min(SettingsPane.maxColumn, max(0, W - 2 * m))
            let centred = (W - column) / 2
            // The laptop pose: a page above the fold for the Mac's part, a page below it for this device's.
            if let across = fold.horizontalBand, across.minY >= SettingsPane.minPage,
               H - across.maxY - max(0, bottomInset) >= SettingsPane.minPage {
                arrangement = .twoPages
                mac = CGRect(x: centred, y: 0, width: column, height: across.minY)
                device = CGRect(x: centred, y: across.maxY, width: column, height: max(0, H - across.maxY))
                band = Self.leading(across, width: W, rightToLeft: rightToLeft)
                return
            }
            // The book pose: a column on each page, centred there; the band between them holds nothing.
            if let down = fold.verticalBand {
                let b = Self.leading(down, width: W, rightToLeft: rightToLeft)
                let leadingPage = b.minX, trailingPage = W - b.maxX
                let first = min(SettingsPane.maxColumn, leadingPage - 2 * m)
                let second = min(SettingsPane.maxColumn, trailingPage - 2 * m)
                if first >= SettingsPane.minColumn, second >= SettingsPane.minColumn {
                    arrangement = .twoColumns
                    mac = CGRect(x: (leadingPage - first) / 2, y: 0, width: first, height: H)
                    device = CGRect(x: b.maxX + (trailingPage - second) / 2, y: 0, width: second, height: H)
                    band = b
                    return
                }
            }
            // No fold to keep to: one column, both parts in it, whatever the screen's width or which way round it
            // is held (Noah, 2026-11-23: "Settings should not be 2 columns, please make it 1 column").
            arrangement = .oneColumn
            mac = CGRect(x: centred, y: 0, width: column, height: H)
            device = mac
            band = nil
        }

        /// A screen rect (left to right) in the leading-edge space.
        private static func leading(_ r: CGRect, width: CGFloat, rightToLeft: Bool) -> CGRect {
            rightToLeft ? CGRect(x: width - r.maxX, y: r.minY, width: r.width, height: r.height) : r
        }

        /// A rect of the leading-edge space in the screen's own, left to right (the checks' view of it).
        func onScreen(_ r: CGRect) -> CGRect { Self.leading(r, width: size.width, rightToLeft: rightToLeft) }

        /// The header's span, x and width in the leading-edge space: the Mac's column (one column, the laptop
        /// pose's upper page), and in the book pose from the leading page's column across the fold to the
        /// trailing page's column's far edge, where Done goes.
        var header: (x: CGFloat, width: CGFloat) {
            arrangement == .twoColumns ? (mac.minX, device.maxX - mac.minX) : (mac.minX, mac.width)
        }

        /// The header's own inset at each end (HostSettingsPanel: its words and Done 4 pt in from the span).
        static let headerInset: CGFloat = 4

        /// The room under Disconnect, which ends the Mac's part (HostSettingsPanel's `withDisconnect`): at the
        /// screen's foot the home indicator's (`bottom`), 16 pt at least; on the laptop pose's upper page 12 pt
        /// over the fold. So Disconnect is never in the home indicator's room, nor on the fold.
        var footBottom: CGFloat {
            arrangement == .twoPages ? SettingsPane.foldGap : max(bottom, SettingsPane.footGap)
        }

        /// How wide the Mac's name and lines may be in the header: in the book pose the leading page's column
        /// less the header's insets, so they never reach the fold; nil in one column and on the laptop pose's
        /// page, where they share the row with Done.
        var headerWords: CGFloat? {
            arrangement == .twoColumns ? max(0, mac.width - 2 * Self.headerInset) : nil
        }

        /// The DEBUG console's line: "one column 600 pt wide at 67 (734×393, 21 pt kept at the bottom)" (an
        /// iPhone 15 Pro on its side), "two columns 423.5 pt wide, the Mac's at 16, this device's at 511.5, the fold
        /// 455.5–495.5 between (951×669, 34 pt kept at the bottom)" (the book pose). The bottom is the home
        /// indicator's room the pane was given, so a gate sees it arrive (none said where there is none).
        var description: String {
            func n(_ v: CGFloat) -> String { abs(v - v.rounded()) < 0.01 ? "\(Int(v.rounded()))" : String(format: "%.1f", Double(v)) }
            let kept = bottom > 0 ? ", \(n(bottom)) pt kept at the bottom" : ""
            let screen = "(\(n(size.width))×\(n(size.height))\(kept)\(rightToLeft ? ", right to left" : ""))"
            switch arrangement {
            case .oneColumn:
                return "one column \(n(mac.width)) pt wide at \(n(mac.minX)) \(screen)"
            case .twoColumns:
                // The book pose's columns: its fold is always between them.
                let fold = band.map { b in ", the fold \(n(onScreen(b).minX))–\(n(onScreen(b).maxX)) between" } ?? ""
                let widths = mac.width == device.width ? "\(n(mac.width)) pt wide" : "\(n(mac.width)) and \(n(device.width)) pt wide"
                return "two columns \(widths), the Mac's at \(n(mac.minX)), this device's at \(n(device.minX))\(fold) \(screen)"
            case .twoPages:
                return "two pages \(n(mac.width)) pt wide at \(n(mac.minX)), the Mac's to \(n(mac.maxY)), this device's from "
                    + "\(n(device.minY)) \(screen)"
            }
        }
    }

    // MARK: - Closing

    /// The pane's motion: up from the bottom edge as it opens, down as it closes; a fade under Reduce Motion.
    static let openSeconds: Double = 0.35
    static let closeSeconds: Double = 0.25

    /// The ways the pane closes, by what comes after it (StreamScreen's `closeSettings`).
    enum Close: String, CaseIterable {
        /// Done, Esc, ⌘. or VoiceOver's escape gesture: the person is done with it.
        case done
        /// DEBUG `-SillSettingsCloseAt`: Done's stand-in.
        case harness
        /// The pairing overlay or the tour covers the stream next (Pair This iPad…, an outside sill://pair link,
        /// a tour's start).
        case overlay
        /// Take the Tour: the tour of the layout on screen runs next.
        case tour
        /// Full Screen: the controls hide next.
        case fullScreen
        /// A bar's control decides about the keyboard itself: the Menus pull-down opening, Apps, Keyboard, the Aa
        /// ruler, a thumbnail's lights (all under the pane while it shows; their own paths and the harness's
        /// keyboard toggle).
        case bar

        /// The stream screen is what shows next, as it was: the keyboard the pane took down comes back, and
        /// VoiceOver reads the screen afresh. Not where something else takes the screen or the keyboard (the
        /// overlay and the tour keep it down and put it back at their end, full screen brings it back with the
        /// controls, a bar's control does what it does).
        var backToStream: Bool { self == .done || self == .harness }

        /// What comes next waits for the pane's motion, so it never runs under the closing pane: the tour's
        /// card and full screen's hide. The pairing overlay comes over it at once, as it did over the panel.
        var waitsForClose: Bool { self == .tour || self == .fullScreen }
    }
}
