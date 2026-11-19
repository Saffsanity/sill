import Foundation

/// Who a two-finger pinch belongs to, and the Settings panel's two rows that decide it: Pinch, Zoom Picture or
/// Zoom on ‹Mac›, and under Zoom on ‹Mac› the switch Rotate on ‹Mac› (issue #260; PR #261 by mrandika, which
/// sent the pinch to the Mac; the review of 2026-11-18, which added the turn and the rows' words). Both this
/// device's own, stored in UserDefaults and never sent; `-Sill.pinchZoomsMac 1` and `-Sill.rotateOnMac 1`
/// set them for one run.
///
/// - Zoom Picture, the default, is as before: two fingers on the picture zoom it on this device, up to 5×
///   (StreamZoom), and nothing goes to the Mac. A pinch on a trackpad (the on-screen one, Trackpad mode's over the
///   picture, or one connected to an iPad) does what it did: the on-screen trackpad's two fingers scroll, and a
///   connected trackpad's pinch goes nowhere.
/// - Zoom on ‹Mac›, for a Mac whose window list says `pinch` (`Pinch.generation`), sends every pinch to the
///   Mac as its own trackpad's (`InputEvent.magnify`): fingers on the picture at the point between them,
///   a trackpad's where the pointer is. With Rotate on ‹Mac› on, two fingers turning go too
///   (`InputEvent.rotate`). The picture is never zoomed then: a zoom made before is undone as the choice
///   changes (StreamScreen), as nothing could undo it after.
/// - A Mac that does not take the pinch (a Sill for Mac before it) is sent neither, whatever is stored: the
///   picture zooms there, and the row is dimmed and says to update Sill on the Mac. What is stored stays
///   for the next Mac that takes it.
///
/// Who decides a stroke of fingers, the Mac's scroll or the pinch, is StreamZoom.Stroke's one rule, the
/// same for the picture and the Mac (`Stroke.Target`): two fingers at 1× scroll unless they pinch first,
/// or, with Rotate on ‹Mac›, turn first; a stroke is one or the other, so the Mac never gets a scroll and
/// a pinch at once. A connected trackpad's pinch and turn are iPadOS's transform events, which carry no
/// touch, so a click of that trackpad or the Apple Pencil is never held back by them.
///
/// Pure (Tests/checks/pinch-routing).
enum PinchRouting {
    /// Where a pinch comes from.
    enum Source: CaseIterable, Equatable, Sendable {
        /// Fingers on the picture (the stream's input view).
        case fingers
        /// Fingers on a trackpad of Sill's own: the on-screen trackpad, or Trackpad mode's laid over the picture (#222).
        case pad
        /// A trackpad connected to an iPad: its pinch and turn, at iPadOS's pointer.
        case pointer
    }

    enum Owner: Equatable, Sendable {
        /// The picture on this device zooms (StreamZoom); nothing is sent to the Mac.
        case picture
        /// The Mac gets the pinch (`InputEvent.magnify`), and with Rotate on ‹Mac› the turn (`.rotate`); the
        /// picture is left as it is.
        case mac
        /// Neither: a trackpad's pinch under Zoom Picture, or on a Mac that cannot take it. The on-screen
        /// trackpad's two fingers scroll, as they always did.
        case none
    }

    /// UserDefaults' key for Pinch: true is Zoom on ‹Mac›. The pull request's own key, kept.
    static let zoomOnMacKey = "Sill.pinchZoomsMac"
    /// Zoom Picture unless Zoom on ‹Mac› is chosen: new behaviour is off unless turned on (Noah, 2026-11-18).
    static let zoomOnMacDefault = false
    /// UserDefaults' key for Rotate on ‹Mac›.
    static let rotateKey = "Sill.rotateOnMac"
    /// Off unless turned on, as the Mac keeps Rotate a checkbox of its own in its Trackpad settings.
    static let rotateDefault = false

    /// Who a pinch from `source` belongs to, with Pinch at Zoom on ‹Mac› (`zoomOnMac`) or not, for a Mac that
    /// takes the pinch (`macTakesPinch`: its window list says `pinch` 1 or more) or not.
    static func owner(_ source: Source, zoomOnMac: Bool, macTakesPinch: Bool) -> Owner {
        if zoomOnMac && macTakesPinch { return .mac }
        return source == .fingers ? .picture : .none
    }

    /// Whether two fingers from `source` turning go to the Mac as well: only with its pinch, and Rotate on ‹Mac› on.
    static func turns(_ source: Source, zoomOnMac: Bool, rotate: Bool, macTakesPinch: Bool) -> Bool {
        rotate && owner(source, zoomOnMac: zoomOnMac, macTakesPinch: macTakesPinch) == .mac
    }

    /// The window list's `pinch` as the device keeps it (`StreamClient.hostPinch`): a Mac takes the pinch at
    /// generation 1 or later.
    static func macTakes(_ pinch: Int?) -> Bool { (pinch ?? 0) >= 1 }

    /// A switch as UserDefaults holds it: the panel's Bool, a number, or a launch argument's string ("1",
    /// "YES", "true"); anything else, nothing included, `standard`.
    static func on(stored: Any?, standard: Bool) -> Bool {
        switch stored {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String: return NSString(string: text).boolValue
        default: return standard
        }
    }

    /// Pinch as stored now (`-Sill.pinchZoomsMac 1` too).
    static var zoomOnMacStored: Bool {
        on(stored: UserDefaults.standard.object(forKey: zoomOnMacKey), standard: zoomOnMacDefault)
    }
    /// Rotate on ‹Mac› as stored now (`-Sill.rotateOnMac 1` too).
    static var rotateStored: Bool {
        on(stored: UserDefaults.standard.object(forKey: rotateKey), standard: rotateDefault)
    }

    // MARK: The Settings panel's rows

    /// What Pinch's control shows: Zoom on ‹Mac› only while it is what happens (stored, and the Mac takes the
    /// pinch); for a Mac that cannot take it, Zoom Picture, dimmed, whatever is stored, since the picture
    /// zooms there.
    static func shownZoomOnMac(stored: Bool, macTakesPinch: Bool) -> Bool { stored && macTakesPinch }
    /// The control can be changed: only for a Mac that takes the pinch.
    static func enabled(macTakesPinch: Bool) -> Bool { macTakesPinch }
    /// Rotate on ‹Mac›'s row shows under Zoom on ‹Mac›, for a Mac that takes the pinch.
    static func rotateRowShown(zoomOnMac: Bool, macTakesPinch: Bool) -> Bool { zoomOnMac && macTakesPinch }

    static let title = "Pinch"
    static let zoomPictureTitle = "Zoom Picture"
    static func zoomOnMacTitle(mac: String) -> String { "Zoom on \(mac)" }
    static func rotateTitle(mac: String) -> String { "Rotate on \(mac)" }

    /// Under Pinch, for ‹Mac› (its name, or "the Mac") and this ‹device› ("iPad" or "iPhone"): what each choice
    /// does (the review's words, 2026-11-18); for a Mac that cannot take the pinch, what to update.
    static func footnote(mac: String, device: String, macTakesPinch: Bool) -> String {
        guard macTakesPinch else { return "Update Sill on \(mac) to send pinches to its apps." }
        return "Zoom Picture magnifies the picture on this \(device), up to 5×, and sends nothing. Zoom on \(mac) sends the pinch to the app under your fingers, as \(mac)’s trackpad would, so Maps, Safari or Preview zoom their own content. On a trackpad, it goes where the pointer is."
    }

    /// Under Rotate on ‹Mac› (the review's words).
    static let rotateFootnote = "Turn two fingers to rotate what’s under them in apps that rotate, such as Preview, Photos and Maps."
}

/// The Mac's pinch and turn a surface has open (InputOverlayView.sendMac): for each of the two, who opened it
/// (a stroke of fingers, or a connected trackpad) and where, as a frame fraction. So a change or an end goes only
/// while its began is out and from the source that began it, every event of a gesture at its began's place, and
/// a second gesture of one source joins the first's place, as one hand's pinch that turns. Pure.
struct MacPinchSent: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case magnify, rotate }
    enum Source: Equatable, Sendable { case stroke, pointer }
    struct Open: Equatable, Sendable { var source: Source; var x: Double; var y: Double }
    private(set) var open: [Kind: Open] = [:]

    var isOpen: Bool { !open.isEmpty }
    /// Where a gesture `source` already has open is, for another of its own to begin at.
    func place(_ source: Source) -> (x: Double, y: Double)? {
        for kind in [Kind.magnify, .rotate] { if let o = open[kind], o.source == source { return (o.x, o.y) } }
        return nil
    }
    /// Where `kind` is, while `source` has it open; nil otherwise (its change and end then go nowhere).
    func at(_ kind: Kind, _ source: Source) -> (x: Double, y: Double)? {
        guard let o = open[kind], o.source == source else { return nil }
        return (o.x, o.y)
    }
    /// `kind` began from `source` at `p` (one of another source left open is the Mac's to end: PinchGestures ends
    /// it as this one begins).
    mutating func began(_ kind: Kind, _ source: Source, at p: (x: Double, y: Double)) { open[kind] = Open(source: source, x: p.x, y: p.y) }
    mutating func ended(_ kind: Kind) { open[kind] = nil }
    /// The Mac no longer takes the pinch (another session): nothing is open as far as this surface is concerned.
    mutating func forget() { open = [:] }
}
