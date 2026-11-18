import Foundation

/// The detents of Aa, the device's text size control (issue #179), and what each one means to the
/// Mac. A scale is device points per Mac point: the host sizes the window it streams to the device's
/// panel divided by it (`Viewport.scale`). With no scale (nil) the host leaves the window alone, and
/// the control shows that detent as "Off", one step below 0.5×: a control that showed 1× for both an
/// untouched Aa and a fit at 1× left no way back to "leave my window alone" short of reconnecting.
///
/// On the virtual display the host sizes the window on its own display and takes no scale for "off"
/// (a nil scale means 1× there), so the control does not offer Off while a window streams there
/// (`offered` false, `offersOff`). It does where the window streams in place with Virtual Display on
/// (the virtual display not available on that macOS, off for the session, or a staging that failed):
/// there a nil scale leaves the window alone again.
///
/// Aa sizes a window, never the Desktop (the host ignores a viewport's scale for it), so it can be
/// used only while a window streams (`selectable`; Noah, 2026-10-29): elsewhere every bar dims it.
///
/// Pure: the control (StreamScreen's `TextScaleControl`) and the host both ask here.
public enum TextScale {
    /// Where the ruler puts "Off": one 0.25 step below the smallest scale.
    public static let off = 0.25
    /// The scales, 0.5× to 1.5× in 0.25 steps.
    public static let scales: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]

    /// The ruler's detents, left to right: Off first when it is offered.
    public static func detents(offered: Bool) -> [Double] { offered ? [off] + scales : scales }

    /// Where `scale` sits on the ruler: its own value, or Off's place for nil when Off is offered,
    /// else 1× (an untouched Aa without Off is at 1×).
    public static func position(of scale: Double?, offered: Bool) -> Double { scale ?? (offered ? off : 1.0) }

    /// The scale a detent stands for: nil for Off.
    public static func scale(at position: Double) -> Double? { position == off ? nil : position }

    /// The nearest detent to `value`, clamped to the ends.
    public static func snap(_ value: Double, offered: Bool) -> Double {
        let detents = detents(offered: offered)
        let clamped = min(max(value, detents[0]), detents[detents.count - 1])
        return detents.min { abs($0 - clamped) < abs($1 - clamped) } ?? 1.0
    }

    /// "Off", or the scale with trailing zeros dropped and "×" after it: 0.5×, 1×, 1.25×.
    public static func title(at position: Double) -> String {
        position == off ? "Off" : number(position) + "×"
    }

    /// 0.5, 0.75, 1, 1.25, 1.5: trailing zeros dropped, and "1" rather than "1.0".
    public static func number(_ scale: Double) -> String {
        var text = String(format: "%.2f", scale)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// What VoiceOver speaks: "Off", or "1.25 times".
    public static func spoken(at position: Double) -> String {
        position == off ? "Off" : number(position) + " times"
    }

    /// The detent one step along for an accessibility increment (`up`) or decrement, stopping at the ends.
    public static func step(from position: Double, up: Bool, offered: Bool) -> Double {
        let detents = detents(offered: offered)
        let i = detents.firstIndex(of: position) ?? detents.firstIndex(of: 1.0) ?? 0
        return detents[up ? min(i + 1, detents.count - 1) : max(i - 1, 0)]
    }

    /// Whether a device's viewport going from `previous` to `now` ends a fit: it had a scale and has
    /// none, which is Aa set to Off. The host then puts the window back where it was
    /// (`WindowRestore`), as when the window stops streaming.
    public static func endsFit(from previous: Double?, to now: Double?) -> Bool {
        previous != nil && now == nil
    }

    /// Whether the ruler has Off: only where no scale leaves the window alone, which is everywhere but
    /// a window on the Mac's virtual display (no scale is 1× there). While a window streams (`source`),
    /// where it streams decides (`onVirtualDisplay`: the running stream's, in the Mac's settings state,
    /// kind 16, which goes out before the window list that names the window): the Virtual Display
    /// setting can be on while the window streams in place (the virtual display not available on that
    /// macOS, off for the session after a problem, or a staging that failed), and there Off is back; a
    /// window still staged after the setting went off keeps 1× until its restart. Otherwise (nothing
    /// or the Desktop streams, whose running stream says nothing of a window, or the Mac has not said)
    /// the setting as the device knows it: not while it is on, where the next window goes on Sill's
    /// display; offered while it is off, and before the Mac said (an older Mac, or the state not in
    /// yet), where no scale leaves the window alone in regular mode.
    public static func offersOff(virtualDisplay: Bool?, streaming source: StreamSource = .none,
                                 onVirtualDisplay: Bool? = nil) -> Bool {
        if case .window = source, let staged = onVirtualDisplay { return !staged }
        return virtualDisplay != true
    }

    /// Whether Aa can be used while `source` streams: only a window's. The Mac sizes a window to the
    /// device's panel at Aa's scale; it ignores the scale for the Desktop, and with nothing streaming
    /// there is nothing to size. Noah, 2026-10-29: "it should not be selectable while you are in
    /// desktop mode, misleading". Elsewhere every bar dims Aa, its ruler never opens and VoiceOver hears
    /// `unavailableHint`; the scale it shows stays, for the next window.
    public static func selectable(streaming source: StreamSource) -> Bool {
        if case .window = source { return true }
        return false
    }

    /// What VoiceOver hears after a dimmed Aa's name and value.
    public static let unavailableHint = "Available for a window."
}
