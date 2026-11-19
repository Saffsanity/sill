import Foundation

/// Every sentence that names the Virtual Desktop to a person (docs/virtual-desktop-plan.md, "Every sentence shown to a
/// person", as revised 2026-11-18; phase 2b), for both apps and for kind 16's note, so a rename is one edit here (Noah,
/// 2026-11-12: "We can workshop the name but for now its a good placeholder"; "Virtual Display" stays the name of the
/// windows' setting). Sill.log's lines are the host's own (VirtualDesktopLife, VirtualDesktopSize).
///
/// Pure (Foundation); checked by Tests/checks/virtual-desktop.
public enum VirtualDesktopWords {
    /// Its name: the Mac's Settings and menu, a device's Settings panel, the stop's name among the Desktop's stops.
    public static let name = "Virtual Desktop"

    // MARK: Why this Mac cannot make it now (kind 16's `virtualDesktopState.note`; Sill for Mac's Settings › Displays)

    /// The CLI without the AppKit loop, which every display Sill makes needs.
    public static let needsLoop = "Start SillHost with --virtual-desktop to use it."
    /// A synthetic test host: its Desktop is a test pattern.
    public static let testHost = "Not on a test host."
    /// The private CGVirtualDisplay API is missing or changed (`problem`: VirtualDisplay.checkPrivateAPI's words).
    public static func apiMissing(_ problem: String) -> String { "Not available on this version of macOS: \(problem)" }
    /// No Screen Recording: Sill makes no display without it (VirtualStage.prepare's rule).
    public static let needsScreenRecording = "Needs Screen Recording."
    /// The guard for #380 holds (DisplayMakeGuard): Sill stopped while making a display two runs in a row.
    public static let guardHolds = "Off for now: Sill stopped while making a display, twice in a row."
    /// Another user, or the login window, has this Mac's screen: a display made now would be theirs.
    public static let offConsole = "Not while another user is on this Mac’s screen."
    /// A make failed this run (`why`: the error, or that it never came up): no more tries until the switch is turned off
    /// and on, as the stage's own failures.
    public static func failed(_ why: String) -> String { "Off for this session: \(why). Turn it off and on to try again." }

    /// Why this Mac cannot make it now: the first of these that applies, in this order, or nil when it can. A test host
    /// (`testHost`); no AppKit loop (the CLI without its flag); the private API missing (`apiProblem`); no Screen Recording;
    /// a make that failed this run (`failure`); the guard for #380; this session off the console. A locked screen is no
    /// reason: the switch and the stop wait for the unlock.
    public static func note(testHost: Bool, appKitLoop: Bool, apiProblem: String?, screenRecording: Bool, failure: String?,
                            guardHolds: Bool, offConsole: Bool) -> String? {
        if testHost { return Self.testHost }
        if !appKitLoop { return needsLoop }
        if let apiProblem { return apiMissing(apiProblem) }
        if !screenRecording { return needsScreenRecording }
        if let failure { return failed(failure) }
        if guardHolds { return Self.guardHolds }
        if offConsole { return Self.offConsole }
        return nil
    }

    // MARK: A device's Settings panel (the Mac's group, after Virtual Display; #393's pane puts it in its Mac part)

    /// The footnote under the switch: off, what it is and that turning it on shows it (open decision 12 (a)); on, how to
    /// reach it and how long it stays; then its size and rate when the Mac says them (`size`: kind 16's
    /// `VirtualDesktopState.size` as `VirtualDesktopState.parse` reads it; `hz`).
    public static func panelFootnote(on: Bool, mac: String, size: (widthPt: Int, heightPt: Int)?, hz: Int?) -> String {
        let what = on ? "Tap Desktop to step to it. It is here only while a device shows it."
                      : "A desktop of its own for your devices, after \(mac)’s screens. Turning it on shows it."
        guard on, let size else { return what }
        return what + " " + sizeLine(widthPt: size.widthPt, heightPt: size.heightPt, hz: hz)
    }

    /// "Its size: 1218 × 800 at 60 Hz."
    public static func sizeLine(widthPt: Int, heightPt: Int, hz: Int?) -> String {
        "Its size: \(widthPt) × \(heightPt)" + (hz.map { " at \($0) Hz" } ?? "") + "."
    }

    /// The switch on a session the Mac does not say is paired: disabled, and why.
    public static func unpaired(mac: String) -> String { "Only a device paired with \(mac) can change this." }

    // MARK: Sill for Mac (Settings › Displays, the status menu, the card)

    /// Settings › Displays' switch.
    public static let macSwitch = "Add a desktop for your devices"
    /// Its footnote.
    public static let macFootnote = "Your iPhone or iPad gets a desktop of its own after this Mac’s screens: tap Desktop on the device to step to it. It is the size of the device that shows it, unless you choose another, and is here only while a device shows it. Windows you leave on it move to your main screen 30 seconds after no device shows it, and go back when it returns. Your devices can turn it on from their Settings too."
    /// Under the Resolution and Refresh Rate pickers.
    public static let pickersFootnote = "A new size or rate applies the next time the Virtual Desktop is made. Larger sizes and 120 Hz may not keep their full frame rate on every Mac: Sill drops frames rather than letting the picture fall behind. 120 Hz needs a ProMotion iPhone or iPad."
    /// Beside a size more than 4096 pixels wide.
    public static let wideFootnote = "Some Macs’ video encoders take no picture wider than 4096 pixels; on those Sill streams it scaled down, or more slowly."
    /// Its status while it can be made and nothing shows it.
    public static let available = "Available"
    /// Without Accessibility: it works, but Sill moves no window off it or back.
    public static let withoutAccessibility = "Without Accessibility, windows left on it go where macOS puts them"

    /// "Showing on iPad mini: 1218 × 800, 60 Hz" (Settings › Displays' status), or "1218 × 800, 60 Hz, for iPad mini" while
    /// it exists and no device shows it.
    public static func status(widthPt: Int, heightPt: Int, hz: Int, device: String?, shown: Bool) -> String {
        let size = "\(widthPt) × \(heightPt), \(hz) Hz"
        if shown { return device.map { "Showing on \($0): \(size)" } ?? "Showing: \(size)" }
        return size + (device.map { ", for \($0)" } ?? "") + ", until no device has shown it for 30 seconds"
    }

    /// The status menu's item.
    public static let menuItem = "Virtual Desktop"
    /// Its subtitle: off; on, not made or not shown; shown ("On iPad mini: 1218 × 800, 60 Hz"); or why it cannot be made.
    public static func menuSubtitle(on: Bool, note: String?, shownOn device: String?, size: (widthPt: Int, heightPt: Int)?, hz: Int?) -> String {
        guard on else { return "A desktop for your devices, after your screens" }
        if let note { return note }
        if let size, let hz, let device { return "On \(device): \(size.widthPt) × \(size.heightPt), \(hz) Hz" }
        return "Tap Desktop on your device to step to it"
    }

    /// The card's title for the Desktop on it: "Virtual Desktop · 1218×800".
    public static func cardTitle(widthPt: Int, heightPt: Int) -> String { "\(name) · \(widthPt)×\(heightPt)" }
}
