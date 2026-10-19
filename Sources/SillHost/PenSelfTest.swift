import Foundation
import AppKit
import CoreGraphics

/// `SillHost --pen-selftest`: what AppKit reads from the tablet events Sill would post for an
/// Apple Pencil (docs/pencil-pressure-plan.md §9, H0). Each event is built as the injector would
/// build it (PenEvents), serialized and read back as the window server would hand it on, then
/// turned into the NSEvent an app would get. **Nothing is posted**, the pointer never moves, and
/// no permission is needed. Exit code 0 when every reading is what was written.
package enum PenSelfTest {
    package static func run() -> Never {
        print("Pen self-test (macOS \(ProcessInfo.processInfo.operatingSystemVersionString)); nothing is posted.")
        var failed = 0
        func check(_ ok: Bool, _ what: String) {
            print("  \(ok ? "ok  " : "FAIL") \(what)")
            if !ok { failed += 1 }
        }
        /// As an app gets it: through the event's serialized form, then AppKit's own conversion.
        func delivered(_ event: CGEvent) -> NSEvent? {
            guard let data = event.data, let copy = CGEvent(withDataAllocator: nil, data: data) else { return nil }
            return NSEvent(cgEvent: copy)
        }
        // A UInt16 of pressure and a SInt16 of tilt are what the event holds.
        let pressureStep = 1.0 / 65535, tiltStep = 1.0 / 32767
        let source = CGEventSource(stateID: .hidSystemState)
        let at = CGPoint(x: 400, y: 300)

        // Proximity, entering and leaving.
        for entering in [true, false] {
            let name = entering ? "enter" : "leave"
            guard let event = PenEvents.proximity(entering: entering, source: source), let ns = delivered(event) else {
                check(false, "proximity \(name): no event"); continue
            }
            guard ns.type == .tabletProximity else {
                check(false, "proximity \(name): AppKit reads type \(ns.type.rawValue), not tabletProximity"); continue
            }
            check(ns.isEnteringProximity == entering, "proximity \(name): isEnteringProximity \(ns.isEnteringProximity)")
            check(ns.pointingDeviceType == .pen, "proximity \(name): pointingDeviceType \(ns.pointingDeviceType.rawValue) (1 is a pen)")
            check(ns.deviceID == Int(PenEvents.deviceID), "proximity \(name): deviceID \(ns.deviceID)")
            check(ns.capabilityMask == Int(PenEvents.capabilities),
                  "proximity \(name): capabilityMask 0x\(String(ns.capabilityMask, radix: 16))")
        }

        // A point on each mouse event Sill posts, at each pressure.
        let kinds: [(CGEventType, String, Bool)] = [(.leftMouseDown, "down", true), (.leftMouseDragged, "dragged", true),
                                                    (.leftMouseUp, "up", false), (.mouseMoved, "moved", false)]
        for (type, name, tipDown) in kinds {
            for pressure in [0, 0.01, 0.25, 0.5, 1] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left) else {
                    check(false, "\(name): no event"); continue
                }
                PenEvents.stamp(event, with: .init(pressure: pressure, tiltX: 0.5, tiltY: -0.25, tipDown: tipDown))
                guard let ns = delivered(event) else { check(false, "\(name) at \(pressure): not delivered"); continue }
                guard ns.subtype == .tabletPoint else {
                    check(false, "\(name) at \(pressure): AppKit reads subtype \(ns.subtype.rawValue), not tabletPoint"); continue
                }
                let ok = abs(Double(ns.pressure) - pressure) <= pressureStep
                    && abs(Double(ns.tilt.x) - 0.5) <= tiltStep && abs(Double(ns.tilt.y) + 0.25) <= tiltStep
                    && ns.deviceID == Int(PenEvents.deviceID)
                    && abs(event.getDoubleValueField(.tabletEventPointPressure) - pressure) <= pressureStep
                check(ok, "\(name) at pressure \(pressure): AppKit reads pressure \(ns.pressure), tilt \(ns.tilt.x),\(ns.tilt.y), deviceID \(ns.deviceID)")
            }
        }

        // Tilt's sign and scale, on a drag.
        for (x, y) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0), (0.3, 0.7)] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: at, mouseButton: .left) else { continue }
            PenEvents.stamp(event, with: .init(pressure: 0.5, tiltX: x, tiltY: y, tipDown: true))
            guard let ns = delivered(event), ns.subtype == .tabletPoint else { check(false, "tilt \(x),\(y): not a tablet point"); continue }
            check(abs(Double(ns.tilt.x) - x) <= tiltStep && abs(Double(ns.tilt.y) - y) <= tiltStep,
                  "tilt \(x),\(y): AppKit reads \(ns.tilt.x),\(ns.tilt.y)")
        }

        // Why the mouse event's own pressure stays 0 (PenEvents.stamp): set as well, it is what
        // AppKit reads, and it holds 8 bits.
        for pressure in [0.25, 0.3333, 0.5] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: at, mouseButton: .left) else { continue }
            PenEvents.stamp(event, with: .init(pressure: pressure, tipDown: true), mousePressureToo: true)
            guard let ns = delivered(event) else { check(false, "both pressures at \(pressure): not delivered"); continue }
            let eightBits = (pressure * 255).rounded(.down) / 255
            check(abs(Double(ns.pressure) - eightBits) < 1e-6,
                  "with the mouse event's pressure set too, \(pressure) reads \(ns.pressure) (8 bits: \(eightBits))")
        }

        // The control: a mouse event Sill posts today is no pen's.
        if let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: at, mouseButton: .left),
           let ns = delivered(event) {
            check(ns.subtype != .tabletPoint, "a plain drag: subtype \(ns.subtype.rawValue), pressure \(ns.pressure) (not a tablet point)")
        }

        print(failed == 0 ? "All readings are what was written." : "\(failed) reading(s) differ.")
        exit(failed == 0 ? 0 : 1)
    }
}
