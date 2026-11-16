import CoreGraphics
import Foundation
import StreamProtocol
#if canImport(AppKit)
import AppKit
#endif

/// Synthesizes macOS Quartz tablet events for Apple Pencil samples (kind 45, Pen.swift).
///
/// Posts both event forms for each proximity and point transition (derived from CGEvent.h / IOLLEvent.h
/// and verified against AppKit / Clip Studio Paint / Photoshop / Krita):
/// 1. A standard mouse event (`mouseMoved`, `leftMouseDown`, `leftMouseDragged`, `leftMouseUp`) with
///    `.mouseEventSubtype` set to `1` (`kCFNumberTabletPointEventType`) or `2` (`kCFNumberTabletProximityEventType`)
///    and both `.tabletEventPointPressure` and `.mouseEventPressure` populated.
/// 2. A standalone `.tabletPointer` (or `.tabletProximity`) event carrying the same tablet fields for
///    apps that override `NSView.tabletPoint(with:)` or `tabletProximity(with:)` directly.
@MainActor
final class PenInjector {
    private static let subtypeTabletPoint: Int64 = 1
    private static let subtypeTabletProximity: Int64 = 2
    private static let pointerTypePen: Int64 = 1
    private static let capabilityMask: Int64 = 0x0587   // deviceID, pointerX/Y, pressure, tilt, buttons
    private static let vendorID: Int64 = 1
    private static let tabletID: Int64 = 1
    private static let deviceID: Int64 = 1

    private static let multiClickInterval: CFTimeInterval = 0.35
    private static let multiClickSlop: CGFloat = 12

    private struct ClickState {
        var clicks: Int64 = 1
        var lastDownAt: CFAbsoluteTime = -1_000
        var lastDownPoint: CGPoint = .zero
    }

    private let source = CGEventSource(stateID: .hidSystemState)
    private var states: [ObjectIdentifier: PenState] = [:]
    private var lastPoints: [ObjectIdentifier: CGPoint] = [:]
    private var deltaRemainder: [ObjectIdentifier: CGPoint] = [:]
    private var clickStates: [ObjectIdentifier: ClickState] = [:]
    private var strokeClockOffsetNs: [ObjectIdentifier: Int64] = [:]
    private var lastEmittedPoint: CGPoint = .zero
    private var lastTimestampNs: UInt64 = 0

    var watch: PointerWatch?
    var dryRun = false
    var testLog = false
    var isPenDown: Bool { states.values.contains(where: \.down) }

    /// True when `batch` only lifts or leaves a pen this device currently holds down on the Mac.
    func releasesWhatItHolds(_ batch: PenBatch, from device: ObjectIdentifier) -> Bool {
        guard let state = states[device], let samples = Pen.accepted(batch) else { return false }
        return state.onlyLifts(samples)
    }

    private func pointerNow(fallback: CGPoint? = nil) -> CGPoint {
        if !dryRun, let location = CGEvent(source: nil)?.location { return location }
        return fallback ?? lastEmittedPoint
    }

    /// Applies validated `samples` inside `rect` (or at the last known point when `rect.isNull`).
    func apply(_ samples: [PenSample], in rect: CGRect, from device: ObjectIdentifier, showOverlay: Bool = false) {
        var state = states[device] ?? PenState()
        var lastPoint: CGPoint?
        var lastPressure: Double = 0
        var sawLeave = false

        for sample in samples {
            let wasDown = state.down
            let previousPoint = lastPoints[device]
            let point: CGPoint
            if rect.isNull {
                point = pointerNow(fallback: previousPoint)
            } else {
                point = Pen.point(sample, in: rect)
                lastPoints[device] = point
            }
            let ts = resolveTimestamp(for: sample, wasDown: wasDown, device: device)
            let posts = state.posts(for: sample.phase)
            for post in posts {
                if post == .leave { sawLeave = true }
                emit(post, sample: sample, at: point, from: previousPoint, timestamp: ts, device: device)
            }
            lastPoint = point
            lastPressure = state.down ? sample.pressure : 0
        }

        #if canImport(AppKit)
        if !dryRun {
            if showOverlay {
                if sawLeave || (!state.near && !state.down) {
                    PenLandingOverlay.shared.dismiss()
                } else if let pt = lastPoint {
                    PenLandingOverlay.shared.update(at: pt, pressure: lastPressure, isDown: state.down)
                }
            } else {
                PenLandingOverlay.shared.dismiss(animated: false)
            }
        }
        #endif

        if state.near || state.down {
            states[device] = state
        } else {
            states[device] = nil
            lastPoints[device] = nil
            deltaRemainder[device] = nil
            strokeClockOffsetNs[device] = nil
        }
    }

    /// Lifts the pen and leaves proximity if `device` disconnected or the source vanished mid-stroke.
    func release(device: ObjectIdentifier) {
        clickStates.removeValue(forKey: device)
        deltaRemainder.removeValue(forKey: device)
        strokeClockOffsetNs.removeValue(forKey: device)
        guard var state = states.removeValue(forKey: device) else {
            lastPoints.removeValue(forKey: device)
            return
        }
        let point = lastPoints.removeValue(forKey: device) ?? pointerNow()
        let neutral = PenSample(phase: PenPhase.leave, x: 0, y: 0)
        let ts = resolveTimestamp(for: neutral, wasDown: true, device: device)
        for post in state.letGo() {
            emit(post, sample: neutral, at: point, from: point, timestamp: ts, device: device)
        }
        #if canImport(AppKit)
        if states.isEmpty {
            PenLandingOverlay.shared.dismiss(animated: false)
        }
        #endif
    }

    /// Lifts and leaves proximity for every connected device (host shutdown).
    func releaseAll() {
        let allDevices = Set(states.keys).union(clickStates.keys)
        for device in allDevices {
            release(device: device)
        }
        #if canImport(AppKit)
        PenLandingOverlay.shared.dismiss(animated: false)
        #endif
    }

    // MARK: - Event synthesis

    /// Maps the iPad's 240 Hz hardware digitizer timestamp (`sample.t`) onto the Mac's monotonic
    /// `CLOCK_UPTIME_RAW` clock using a constant offset per stroke so network packet batching never
    /// creates velocity spikes or frame-boundary beading in velocity-sensitive brush engines.
    private func resolveTimestamp(for sample: PenSample, wasDown: Bool, device: ObjectIdentifier) -> CGEventTimestamp {
        let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let minStepNs: UInt64 = 500_000       // 0.5 ms floor when two samples share a timestamp
        let defaultStepNs: UInt64 = 4_166_667 // 240 Hz (~4.17 ms) fallback when `sample.t` is absent

        if let sampleT = sample.t, sampleT.isFinite, sampleT > 0 {
            let sampleNs = Int64(sampleT * 1_000_000_000.0)
            let isStrokeStart = !wasDown && (sample.phase == PenPhase.down || sample.phase == PenPhase.drag)
            let offset: Int64
            if isStrokeStart || strokeClockOffsetNs[device] == nil {
                let anchorNs = max(nowNs, lastTimestampNs &+ minStepNs)
                offset = Int64(bitPattern: anchorNs) &- sampleNs
                strokeClockOffsetNs[device] = offset
            } else if !wasDown {
                // While hovering between strokes, gently re-anchor if clock drift exceeds 80 ms.
                let existing = strokeClockOffsetNs[device]!
                let mapped = sampleNs &+ existing
                let diff = Int64(bitPattern: nowNs) &- mapped
                if abs(diff) > 80_000_000 {
                    let anchorNs = max(nowNs, lastTimestampNs &+ minStepNs)
                    offset = Int64(bitPattern: anchorNs) &- sampleNs
                    strokeClockOffsetNs[device] = offset
                } else {
                    offset = existing
                }
            } else {
                // Mid-stroke: keep the clock offset strictly locked so inter-sample dt equals the
                // exact Apple Pencil hardware intervals regardless of Wi-Fi packet arrival jitter.
                offset = strokeClockOffsetNs[device]!
            }

            let rawMapped = sampleNs &+ offset
            let mappedNs = rawMapped > 0 ? UInt64(bitPattern: rawMapped) : nowNs
            let ts = max(mappedNs, lastTimestampNs &+ minStepNs)
            lastTimestampNs = ts
            return ts
        }

        // Fallback when `sample.t` is nil: pace samples smoothly at 240 Hz without burst compression.
        let ts: UInt64
        if wasDown, nowNs <= lastTimestampNs &+ 40_000_000 {
            ts = lastTimestampNs &+ defaultStepNs
        } else {
            ts = max(nowNs, lastTimestampNs &+ defaultStepNs)
        }
        lastTimestampNs = ts
        return ts
    }

    private func consumeDelta(to point: CGPoint, from previous: CGPoint?, device: ObjectIdentifier) -> (Int64, Int64) {
        guard let previous else {
            deltaRemainder[device] = .zero
            return (0, 0)
        }
        let rem = deltaRemainder[device] ?? .zero
        let rawDx = (point.x - previous.x) + rem.x
        let rawDy = (point.y - previous.y) + rem.y
        let dx = Int64(rawDx.rounded())
        let dy = Int64(rawDy.rounded())
        deltaRemainder[device] = CGPoint(x: rawDx - Double(dx), y: rawDy - Double(dy))
        return (dx, dy)
    }

    private func emit(_ post: Pen.Post, sample: PenSample, at point: CGPoint, from previous: CGPoint?, timestamp: CGEventTimestamp, device: ObjectIdentifier) {
        switch post {
        case .enter:
            postProximity(entering: true, at: point, timestamp: timestamp)
        case .leave:
            postProximity(entering: false, at: point, timestamp: timestamp)
        case .move:
            postPoint(mouseType: .mouseMoved, sample: sample, at: point, from: previous, timestamp: timestamp, clickState: 0, device: device)
        case .down:
            var cs = clickStates[device] ?? ClickState()
            let now = CFAbsoluteTimeGetCurrent()
            let moved = hypot(point.x - cs.lastDownPoint.x, point.y - cs.lastDownPoint.y)
            if now - cs.lastDownAt <= Self.multiClickInterval && moved <= Self.multiClickSlop {
                cs.clicks += 1
            } else {
                cs.clicks = 1
            }
            cs.lastDownAt = now
            cs.lastDownPoint = point
            clickStates[device] = cs
            postPoint(mouseType: .leftMouseDown, sample: sample, at: point, from: previous, timestamp: timestamp, clickState: cs.clicks, device: device)
        case .drag:
            let clicks = clickStates[device]?.clicks ?? 1
            postPoint(mouseType: .leftMouseDragged, sample: sample, at: point, from: previous, timestamp: timestamp, clickState: clicks, device: device)
        case .up:
            let clicks = clickStates[device]?.clicks ?? 1
            postPoint(mouseType: .leftMouseUp, sample: sample, at: point, from: previous, timestamp: timestamp, clickState: clicks, device: device)
        }
    }

    private func postProximity(entering: Bool, at point: CGPoint, timestamp: CGEventTimestamp) {
        guard let mouseEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                       mouseCursorPosition: point, mouseButton: .left) else { return }
        mouseEvent.timestamp = timestamp
        mouseEvent.setIntegerValueField(.mouseEventSubtype, value: Self.subtypeTabletProximity)
        applyProximityFields(entering: entering, to: mouseEvent)

        guard let standalone = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                       mouseCursorPosition: point, mouseButton: .left) else { return }
        standalone.type = .tabletProximity
        standalone.timestamp = timestamp
        applyProximityFields(entering: entering, to: standalone)

        if dryRun {
            if testLog {
                print("Test input: pen proximity \(entering ? "enter" : "leave") at \(Int(point.x)),\(Int(point.y))")
            }
            Stats.shared.bump("in.dry")
            return
        }
        mouseEvent.post(tap: .cghidEventTap)
        standalone.post(tap: .cghidEventTap)
        Stats.shared.bump("in.pen")
    }

    private func postPoint(mouseType: CGEventType, sample: PenSample, at point: CGPoint, from previous: CGPoint?, timestamp: CGEventTimestamp, clickState: Int64, device: ObjectIdentifier) {
        let tilt = Pen.tilt(altitude: sample.altitude, azimuth: sample.azimuth)
        guard let mouseEvent = CGEvent(mouseEventSource: source, mouseType: mouseType,
                                       mouseCursorPosition: point, mouseButton: .left) else { return }
        let (dx, dy) = consumeDelta(to: point, from: previous, device: device)
        mouseEvent.timestamp = timestamp
        mouseEvent.setIntegerValueField(.mouseEventDeltaX, value: dx)
        mouseEvent.setIntegerValueField(.mouseEventDeltaY, value: dy)
        mouseEvent.setIntegerValueField(.mouseEventNumber, value: 0)
        if mouseType != .mouseMoved {
            mouseEvent.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        // Subtype must be set before tablet fields (CGEvent.h).
        mouseEvent.setIntegerValueField(.mouseEventSubtype, value: Self.subtypeTabletPoint)
        applyPointFields(mouseType: mouseType, pressure: sample.pressure, tiltX: tilt.x, tiltY: tilt.y, to: mouseEvent)

        let standalone = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                 mouseCursorPosition: point, mouseButton: .left)
        if let standalone {
            standalone.type = .tabletPointer
            standalone.timestamp = timestamp
            applyPointFields(mouseType: mouseType, pressure: sample.pressure, tiltX: tilt.x, tiltY: tilt.y, to: standalone)
        }

        lastEmittedPoint = point
        watch?.sillMoved(to: point)
        if dryRun {
            if testLog {
                let p = String(format: "%.2f", sample.pressure)
                print("Test input: pen \(mouseType.rawValue) p=\(p) at \(Int(point.x)),\(Int(point.y))")
            }
            Stats.shared.bump("in.dry")
            return
        }
        mouseEvent.post(tap: .cghidEventTap)
        standalone?.post(tap: .cghidEventTap)
        Stats.shared.bump("in.pen")
    }

    private func applyProximityFields(entering: Bool, to event: CGEvent) {
        event.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        event.setIntegerValueField(.tabletProximityEventPointerType, value: Self.pointerTypePen)
        event.setIntegerValueField(.tabletProximityEventDeviceID, value: Self.deviceID)
        event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: Self.capabilityMask)
        event.setIntegerValueField(.tabletProximityEventVendorID, value: Self.vendorID)
        event.setIntegerValueField(.tabletProximityEventTabletID, value: Self.tabletID)
        event.setIntegerValueField(.tabletProximityEventVendorPointerType, value: Self.pointerTypePen)
        event.setIntegerValueField(.tabletProximityEventPointerID, value: Self.deviceID)
    }

    private func applyPointFields(mouseType: CGEventType, pressure: Double, tiltX: Double, tiltY: Double, to event: CGEvent) {
        event.setIntegerValueField(.tabletEventPointButtons, value: (mouseType == .leftMouseDown || mouseType == .leftMouseDragged) ? 1 : 0)
        event.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        event.setDoubleValueField(.mouseEventPressure, value: pressure)
        event.setDoubleValueField(.tabletEventTiltX, value: tiltX)
        event.setDoubleValueField(.tabletEventTiltY, value: tiltY)
        event.setIntegerValueField(.tabletEventDeviceID, value: Self.deviceID)
    }
}

#if canImport(AppKit)
@MainActor
final class PenLandingOverlay {
    static let shared = PenLandingOverlay()

    private var window: NSPanel?
    private var pendingFadeItem: DispatchWorkItem?

    private func ensureWindow() -> NSPanel {
        if let window { return window }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.sharingType = .none
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = PenIndicatorView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        self.window = panel
        return panel
    }

    func update(at quartzPoint: CGPoint, pressure: Double, isDown: Bool) {
        pendingFadeItem?.cancel()
        pendingFadeItem = nil

        let panel = ensureWindow()
        if let screen = NSScreen.screens.first {
            let cocoaY = screen.frame.height - quartzPoint.y
            panel.setFrameOrigin(NSPoint(x: quartzPoint.x - 16, y: cocoaY - 16))
        }
        if let view = panel.contentView as? PenIndicatorView {
            view.pressure = pressure
            view.isDown = isDown
            view.needsDisplay = true
        }
        panel.alphaValue = 1.0
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func dismiss(animated: Bool = true) {
        pendingFadeItem?.cancel()
        pendingFadeItem = nil
        guard let panel = window, panel.isVisible else { return }
        if animated {
            let item = DispatchWorkItem { [weak self] in
                guard let self, let panel = self.window, panel.isVisible else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.20
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    panel.orderOut(nil)
                })
            }
            pendingFadeItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        } else {
            panel.orderOut(nil)
        }
    }
}

private final class PenIndicatorView: NSView {
    var pressure: Double = 0
    var isDown: Bool = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius: CGFloat = isDown ? CGFloat(7.0 + 5.0 * pressure) : 8.0

        // Outer dark shadow ring for contrast
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(3.0)
        ctx.strokeEllipse(in: CGRect(x: center.x - baseRadius, y: center.y - baseRadius,
                                     width: baseRadius * 2, height: baseRadius * 2))

        // Inner bright ring
        let ringColor = isDown ? NSColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 0.95)
                               : NSColor.white.withAlphaComponent(0.85)
        ctx.setStrokeColor(ringColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(x: center.x - baseRadius, y: center.y - baseRadius,
                                     width: baseRadius * 2, height: baseRadius * 2))

        // Center dot / crosshair
        let dotRadius: CGFloat = isDown ? 2.0 : 1.5
        ctx.setFillColor(ringColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius,
                                   width: dotRadius * 2, height: dotRadius * 2))
        ctx.restoreGState()
    }
}
#endif
