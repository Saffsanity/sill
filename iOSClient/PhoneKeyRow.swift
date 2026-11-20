import CoreGraphics

/// The key row of a phone held upright (row 3 of PhonePortraitLayout; KeyRow's `.phone` set in
/// PortraitStreamScreen.swift) and its switch, Arrow Keys (issue #287, PR #315 by oyyblin).
///
/// - Off, the default (`arrowKeysDefault`): the six caps that name a key, esc, tab, ctrl, opt, cmd and
///   shift, equal across the row (`PhonePortraitLayout.caps`), as in the phone layout Noah approved on
///   2026-09-27, which left the arrows to a hardware keyboard.
/// - On (Settings › This iPhone › Keys › Arrow Keys): the four arrows after shift, ← ↓ ↑ →, in one row
///   that scrolls sideways as the window thumbnails above it do (`Strip`). As many caps as fit whole at
///   `minCapWidth` or wider show at rest, six at most, and `peek` of the next shows past them, fading out
///   at the edge, so the row says there is more; a swipe brings the arrows in beside shift (and cmd,
///   where six fit). The row stops with a cap at its leading edge (SwiftUI's view-aligned scrolling).
///   VoiceOver's action on every cap takes the row to the arrows, or back from them (`Copy.scrollAction`,
///   `voiceOverFocus`), as #293's pages did.
///
/// Only an iPhone has this row (`offered`): an iPad's key row, a narrow iPad window's and the iPhone Duo's
/// open ones have the arrows already. The switch is the device's own, never sent to the Mac, and the row's
/// room is the same 44 pt either way, so nothing else on the screen moves. Pure (CoreGraphics only):
/// checked with swiftc, against PhonePortraitLayout's row at every width, in Tests/checks/phone-key-row.
enum PhoneKeyRow {
    /// Arrow Keys, this device's switch (Settings › This iPhone › Keys): off unless turned on, read by the
    /// key row and the Settings panel. The device's own preference, never sent.
    static let arrowKeysKey = "Sill.arrowKeys"
    static let arrowKeysDefault = false

    /// The caps that name a key, esc to shift: the whole row with the switch off.
    static let named = 6
    /// The arrows the switch adds after them.
    static let arrows = 4
    /// Where the arrows start among the caps: the left arrow, right after shift.
    static var firstArrow: Int { named }

    /// How many of the key row's caps a phone shows, from the start of its list (esc, tab, ctrl, opt, cmd,
    /// shift, ←, ↓, ↑, →): the six that name a key, and with Arrow Keys on the four arrows after them.
    static func capCount(arrowKeys: Bool) -> Int { arrowKeys ? named + arrows : named }

    /// Whether the row scrolls (`Strip`): with Arrow Keys on. Off, it is the six equal caps, as before.
    static func scrolls(arrowKeys: Bool) -> Bool { arrowKeys }

    /// Whether Settings offers Arrow Keys: where the stream screen draws a phone's arrangement upright (an
    /// iPhone, the iPhone Duo's cover among them: DuoLayout.phoneArrangement), never on an iPad.
    static func offered(phoneArrangement: Bool) -> Bool { phoneArrangement }

    /// A cap of the row that scrolls is never narrower than this: a touch target's least.
    static let minCapWidth: CGFloat = 44
    /// At most this many caps show whole before the row scrolls: the six that name a key.
    static let maxWhole = 6
    /// How much of the next cap shows past the whole ones: over half, so the row says there is more.
    static let peek: CGFloat = 0.6

    /// The row that scrolls: `count` caps, `gap` apart, in a row `rowWidth` wide.
    struct Strip: Equatable {
        let rowWidth: CGFloat
        let gap: CGFloat
        let count: Int
        /// The caps that show whole at rest: the most, `maxWhole` at most, that leave every cap at least
        /// `minCapWidth` wide with `peek` of the next showing past them (six on every iPhone from 375 pt
        /// wide, five at Display Zoom's 320); one where not even one does.
        let whole: Int
        /// Every cap's width: `whole` caps, a gap after each and `peek` of the next fill the row.
        let capWidth: CGFloat

        init(rowWidth: CGFloat, gap: CGFloat, count: Int) {
            self.rowWidth = rowWidth
            self.gap = gap
            self.count = count
            var whole = PhoneKeyRow.maxWhole
            while whole > 1, Self.capWidth(whole: whole, rowWidth: rowWidth, gap: gap) < PhoneKeyRow.minCapWidth {
                whole -= 1
            }
            self.whole = whole
            capWidth = Self.capWidth(whole: whole, rowWidth: rowWidth, gap: gap)
        }

        /// A cap's width with `whole` caps whole: they, a gap after each and `peek` of the next fill the row.
        static func capWidth(whole: Int, rowWidth: CGFloat, gap: CGFloat) -> CGFloat {
            max(0, (rowWidth - CGFloat(whole) * gap) / (CGFloat(whole) + PhoneKeyRow.peek))
        }

        /// The caps and the gaps between them, end to end.
        var content: CGFloat { CGFloat(count) * capWidth + CGFloat(max(0, count - 1)) * gap }
        /// How far the row scrolls from its start (0): to its end, the last cap's trailing edge at the row's.
        var maxScroll: CGFloat { max(0, content - rowWidth) }
        /// Where cap `index` starts in the row, scrolled `scrolled` from the start.
        func capStart(_ index: Int, scrolled: CGFloat) -> CGFloat { CGFloat(index) * (capWidth + gap) - scrolled }

        /// What fades out at an edge with caps past it: the cut cap's part in view and the gap before it.
        var fadeWidth: CGFloat { PhoneKeyRow.peek * capWidth + gap }
        /// That as a share of the row, at most half: the fade's stops.
        var fadeShare: CGFloat { rowWidth > 0 ? min(0.5, fadeWidth / rowWidth) : 0 }
        /// Caps past the leading edge, so it fades: the row scrolled from its start (by over half a point).
        func fadesLeading(scrolled: CGFloat) -> Bool { scrolled > 0.5 }
        /// Caps past the trailing edge, so it fades: the row short of its end (by over half a point).
        func fadesTrailing(scrolled: CGFloat) -> Bool { scrolled < maxScroll - 0.5 }
        /// At the row's end, the last arrow in view.
        func atEnd(scrolled: CGFloat) -> Bool { !fadesTrailing(scrolled: scrolled) }
    }

    /// The cap VoiceOver goes to once its action has scrolled the row: from its end back to its start, esc;
    /// from anywhere short of the end on to it, the left arrow.
    static func voiceOverFocus(atEnd: Bool) -> Int { atEnd ? 0 : firstArrow }

    /// The words: Settings › This iPhone › Keys, and VoiceOver's action on the row's caps.
    enum Copy {
        /// The group's heading in Settings, under This iPhone: the key row's switches.
        static let group = "Keys"
        static let title = "Arrow Keys"
        /// Under the switch.
        static let footnote = "Adds ← ↓ ↑ → after shift in the key row. Swipe the row to reach them."
        /// VoiceOver's action on every cap of the row that scrolls (#293's): to the arrows, or back from them
        /// at the row's end.
        static let showArrows = "Show the arrow keys"
        static let showModifiers = "Show the modifier keys"
        static func scrollAction(atEnd: Bool) -> String { atEnd ? showModifiers : showArrows }
    }
}
