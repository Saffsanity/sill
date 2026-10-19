import CoreGraphics

/// An Apple Pencil's input as a Mac tablet pen's events (docs/pencil-pressure-plan.md §4.2): the
/// tablet fields a mouse event carries while a pen draws, and the proximity event that says a pen
/// came into range or left it. Building only: nothing here posts.
///
/// A pen's point is the mouse event Sill posts anyway (down, dragged, up, moved) with the tablet
/// point subtype and its pressure and tilt; apps pair it with the proximity event of the same
/// device ID, and many read pressure only from a pen that entered.
package enum PenEvents {
    /// The system-assigned device ID a tablet's proximity and point events share (a UInt16 on the
    /// wire). Any constant does: Sill is the only tablet it posts for.
    package static let deviceID: Int64 = 0x5111
    /// What the pen reports (IOLLEvent.h's NX_TABLET_CAPABILITY_*): a device ID, tilt on both axes
    /// and pressure. No absolute position: the mouse event's own location is the position.
    package static let capabilities: Int64 = 0x0001 | 0x0080 | 0x0100 | 0x0400
    /// NX_TABLET_POINTER_PEN.
    package static let penPointer: Int64 = 1

    /// One sample as macOS wants it (PenTablet.swift, which decides them).
    package typealias Point = PenPoint

    /// Makes a mouse event a pen's point. The subtype first: it says which of the event's two
    /// tablet layouts the fields after it are written to.
    ///
    /// The pressure goes in the tablet point alone, and the mouse event's own pressure is set to 0.
    /// AppKit's `NSEvent.pressure` reads the mouse event's when it is not 0, and that one holds 8
    /// bits (255 steps); only when it is 0 does AppKit read the tablet point's 16 (measured,
    /// `SillHost --pen-selftest`; a down and a drag are made with a mouse pressure of 1).
    /// `mousePressureToo` writes both, for a probe of apps that read the mouse event's directly.
    package static func stamp(_ event: CGEvent, with point: Point, mousePressureToo: Bool = false) {
        event.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        event.setDoubleValueField(.mouseEventPressure, value: mousePressureToo ? point.pressure : 0)
        event.setDoubleValueField(.tabletEventPointPressure, value: point.pressure)
        event.setDoubleValueField(.tabletEventTiltX, value: point.tiltX)
        event.setDoubleValueField(.tabletEventTiltY, value: point.tiltY)
        event.setIntegerValueField(.tabletEventPointButtons, value: point.tipDown ? 1 : 0)
        event.setIntegerValueField(.tabletEventDeviceID, value: deviceID)
    }

    /// The pen coming into range (`entering`) or leaving it, where the pointer is.
    package static func proximity(entering: Bool, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(source: source) else { return nil }
        event.type = .tabletProximity
        event.setIntegerValueField(.tabletProximityEventDeviceID, value: deviceID)
        event.setIntegerValueField(.tabletProximityEventPointerID, value: 1)
        event.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: deviceID)
        event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: capabilities)
        event.setIntegerValueField(.tabletProximityEventPointerType, value: penPointer)
        event.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        return event
    }
}
