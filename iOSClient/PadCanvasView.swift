import QuartzCore
import StreamProtocol
import SwiftUI
import UIKit

/// Screenless drawing tablet surface (Pad Mode). Draws an aspect-fitted matte active region matching
/// the Mac's main display, accepts ONLY Apple Pencil for cursor/drawing with calibrated pressure and
/// anti-jitter smoothing, and maps finger sliding to Mac page scrolling.
struct PadCanvasView: View {
    @ObservedObject var client: StreamClient
    @AppStorage(StreamClient.reverseScrollKey) private var reverseScrolling = false

    private var displaySize: CGSize {
        if let pen = client.hostPen, pen.displayWidth > 0, pen.displayHeight > 0 {
            return CGSize(width: pen.displayWidth, height: pen.displayHeight)
        }
        return CGSize(width: 16, height: 10)
    }

    var body: some View {
        GeometryReader { geo in
            let activeRect = Pen.fit(displaySize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color(red: 0.06, green: 0.06, blue: 0.07)

                // Active tablet surface matched to the Mac display's aspect ratio
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)

                    // Subtle rule-of-thirds registration crosshair
                    Path { path in
                        for step in [1.0 / 3.0, 2.0 / 3.0] {
                            let x = activeRect.width * step
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: activeRect.height))
                            let y = activeRect.height * step
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: activeRect.width, y: y))
                        }
                    }
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)

                    Text("Tablet · \(Int(displaySize.width))×\(Int(displaySize.height)) · Apple Pencil · 1-finger scroll · 2-finger zoom")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.36))
                        .padding(12)
                }
                .frame(width: activeRect.width, height: activeRect.height)
                .offset(x: activeRect.minX, y: activeRect.minY)
                .allowsHitTesting(false)

                PadTouchRepresentable(
                    activeRect: activeRect,
                    reverseScrolling: reverseScrolling,
                    sendPen: { batch in client.sendPen(batch) },
                    sendInputEvent: { event in client.sendInput(event) },
                    usesPenProtocol: client.hostPen != nil
                )
            }
        }
    }
}

private struct PadTouchRepresentable: UIViewRepresentable {
    let activeRect: CGRect
    let reverseScrolling: Bool
    let sendPen: (PenBatch) -> Void
    let sendInputEvent: (InputEvent) -> Void
    let usesPenProtocol: Bool

    func makeUIView(context: Context) -> PadTouchUIView {
        let v = PadTouchUIView()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: PadTouchUIView, context: Context) {
        uiView.activeRect = activeRect
        uiView.reverseScrolling = reverseScrolling
        uiView.sendPen = sendPen
        uiView.sendInputEvent = sendInputEvent
        uiView.usesPenProtocol = usesPenProtocol
    }
}

private final class PadTouchUIView: UIView, UIGestureRecognizerDelegate {
    var activeRect: CGRect = .zero
    var reverseScrolling = false
    var sendPen: (PenBatch) -> Void = { _ in }
    var sendInputEvent: (InputEvent) -> Void = { _ in }
    var usesPenProtocol = true

    private var pencilDown = false
    private var hoverActive = false
    private var lastPencilAt: CFTimeInterval = 0
    private var smoothedX: Double?
    private var smoothedY: Double?
    private var pencilFilter = PenFilter()
    private var hoverFilter = PenFilter(minCutoff: 1.8, beta: 18.0)
    private var lastPressure: Double = 0
    private var lastPanTranslation: CGPoint = .zero
    private var lastScrollNorm: (x: Double, y: Double) = (0.5, 0.5)
    private var scrollGestureActive = false
    private var scrollCoasting: DispatchSourceTimer?

    private let indicatorLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Lightweight CALayer indicator so 240 Hz Pencil input never triggers SwiftUI view body updates.
        indicatorLayer.strokeColor = UIColor.white.withAlphaComponent(0.75).cgColor
        indicatorLayer.fillColor = UIColor.white.withAlphaComponent(0.25).cgColor
        indicatorLayer.lineWidth = 1.5
        indicatorLayer.isHidden = true
        layer.addSublayer(indicatorLayer)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        hover.delegate = self
        addGestureRecognizer(hover)

        // Single-finger pan → Mac page scroll (direct finger touch only; never Apple Pencil).
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleFingerScroll(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        addGestureRecognizer(pan)

        // Two-finger pinch → Mac software canvas zoom (direct finger touches only).
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchZoom(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.cancelsTouchesInView = false
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        scrollCoasting?.cancel()
    }

    // MARK: - UIGestureRecognizerDelegate

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer {
            // Suppress finger scroll and zoom while Apple Pencil is touching or just lifted (<80 ms).
            return !pencilDown && (CACurrentMediaTime() - lastPencilAt > 0.08)
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer {
            return touch.type == .direct && !pencilDown
        }
        return true
    }

    // MARK: - Visual Indicator (Zero-Allocation CALayer)

    private func updateIndicator(normX: Double?, normY: Double?, pressure: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let nx = normX, let ny = normY, activeRect.width > 0, activeRect.height > 0 {
            let radius = CGFloat(5.0 + 9.0 * pressure)
            let cx = activeRect.minX + CGFloat(nx) * activeRect.width
            let cy = activeRect.minY + CGFloat(ny) * activeRect.height
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            indicatorLayer.path = UIBezierPath(ovalIn: rect).cgPath
            indicatorLayer.fillColor = UIColor.white.withAlphaComponent(CGFloat(0.15 + 0.55 * pressure)).cgColor
            indicatorLayer.isHidden = false
        } else {
            indicatorLayer.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: - Velocity-Adaptive Anti-Jitter Filter & Pressure Mapping

    private func filterCoordinate(rawX: Double, rawY: Double, timestamp: Double?, reset: Bool) -> (x: Double, y: Double) {
        if reset { pencilFilter.reset() }
        let out = pencilFilter.apply(rawX: rawX, rawY: rawY, timestamp: timestamp)
        smoothedX = out.x
        smoothedY = out.y
        return out
    }

    private func sample(phase: Int, for touch: UITouch, resetFilter: Bool = false) -> PenSample? {
        let loc = touch.preciseLocation(in: self)
        guard let raw = Pen.fraction(loc, in: activeRect) else { return nil }
        let pos = filterCoordinate(rawX: raw.x, rawY: raw.y, timestamp: touch.timestamp, reset: resetFilter)
        let pressure: Double
        if phase == PenPhase.down || phase == PenPhase.drag {
            let prev = phase == PenPhase.down ? 0 : lastPressure
            let isEstimated = touch.estimatedPropertiesExpectingUpdates.contains(.force)
            pressure = Pen.mapPressure(force: Double(touch.force),
                                       maxForce: Double(touch.maximumPossibleForce),
                                       previous: prev,
                                       isEstimated: isEstimated)
            lastPressure = pressure
        } else {
            pressure = 0
            lastPressure = 0
        }
        return PenSample(phase: phase,
                         x: pos.x,
                         y: pos.y,
                         pressure: pressure,
                         altitude: Double(touch.altitudeAngle),
                         azimuth: Double(touch.azimuthAngle(in: self)),
                         t: touch.timestamp)
    }

    // MARK: - Apple Pencil Hover

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        if gesture.state != .began && gesture.state != .changed {
            guard hoverActive else { return }
            hoverActive = false
            hoverFilter.reset()
            let fallbackX = smoothedX ?? 0.5
            let fallbackY = smoothedY ?? 0.5
            smoothedX = nil
            smoothedY = nil
            updateIndicator(normX: nil, normY: nil, pressure: 0)
            guard usesPenProtocol else { return }
            let raw = Pen.fraction(gesture.location(in: self), in: activeRect) ?? (x: fallbackX, y: fallbackY)
            let s = PenSample(phase: PenPhase.leave, x: raw.x, y: raw.y, t: CACurrentMediaTime())
            sendPen(PenBatch(target: PenTarget.display, samples: [s]))
            return
        }
        // Ignore hover while the Pencil tip is down on the glass or immediately after lift
        // so hover and touch never fight each other and cause jitter.
        guard !pencilDown, CACurrentMediaTime() - lastPencilAt > 0.035 else { return }
        // Only accept Apple Pencil hover (which reports altitude or zOffset).
        let isPencilHover = gesture.zOffset > 0 || gesture.altitudeAngle > 0
        guard usesPenProtocol, isPencilHover,
              let raw = Pen.fraction(gesture.location(in: self), in: activeRect) else { return }
        let wasActive = hoverActive
        hoverActive = true
        let now = CACurrentMediaTime()
        if gesture.state == .began || !wasActive { hoverFilter.reset() }
        let pos = hoverFilter.apply(rawX: raw.x, rawY: raw.y, timestamp: now)
        smoothedX = pos.x
        smoothedY = pos.y
        let s = PenSample(phase: PenPhase.hover,
                          x: pos.x,
                          y: pos.y,
                          pressure: 0,
                          altitude: Double(gesture.altitudeAngle),
                          azimuth: Double(gesture.azimuthAngle(in: self)),
                          t: now)
        sendPen(PenBatch(target: PenTarget.display, samples: [s]))
        updateIndicator(normX: pos.x, normY: pos.y, pressure: 0)
    }

    // MARK: - Apple Pencil Touch (Pencil-Only; Palm & Finger Rejected)

    private static func pencilTouch(in touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .pencil }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = Self.pencilTouch(in: touches) else { return }
        stopScrollCoast()

        let coalesced = (event?.coalescedTouches(for: touch) ?? [touch]).filter { $0.type == .pencil }
        let samples = coalesced.enumerated().compactMap { idx, t in
            sample(phase: idx == 0 ? PenPhase.down : PenPhase.drag, for: t, resetFilter: idx == 0)
        }
        guard let last = samples.last else { return }
        hoverActive = false
        pencilDown = true
        lastPencilAt = CACurrentMediaTime()
        if usesPenProtocol {
            sendPen(PenBatch(target: PenTarget.display, samples: samples))
        } else {
            sendInputEvent(.pointer(.move, x: last.x, y: last.y))
            sendInputEvent(.pointer(.leftDown, x: last.x, y: last.y))
        }
        updateIndicator(normX: last.x, normY: last.y, pressure: last.pressure)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = Self.pencilTouch(in: touches) else { return }

        let coalesced = (event?.coalescedTouches(for: touch) ?? [touch]).filter { $0.type == .pencil }
        let samples = coalesced.compactMap { sample(phase: PenPhase.drag, for: $0, resetFilter: false) }
        guard let last = samples.last else { return }
        lastPencilAt = CACurrentMediaTime()
        if usesPenProtocol {
            sendPen(PenBatch(target: PenTarget.display, samples: samples))
        } else {
            sendInputEvent(.pointer(.move, x: last.x, y: last.y))
        }
        updateIndicator(normX: last.x, normY: last.y, pressure: last.pressure)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = Self.pencilTouch(in: touches) else { return }
        pencilDown = false
        lastPencilAt = CACurrentMediaTime()

        let fallback = (x: smoothedX ?? 0.5, y: smoothedY ?? 0.5)
        let coalesced = (event?.coalescedTouches(for: touch) ?? []).filter { $0.type == .pencil }
        var samples = coalesced.dropLast().compactMap { sample(phase: PenPhase.drag, for: $0, resetFilter: false) }
        if let up = sample(phase: PenPhase.up, for: touch, resetFilter: false) {
            samples.append(up)
        } else {
            let f = Pen.fraction(touch.preciseLocation(in: self), in: activeRect) ?? fallback
            samples.append(PenSample(phase: PenPhase.up, x: f.x, y: f.y, t: touch.timestamp))
        }
        if let last = samples.last {
            if usesPenProtocol {
                sendPen(PenBatch(target: PenTarget.display, samples: samples))
            } else {
                sendInputEvent(.pointer(.leftUp, x: last.x, y: last.y))
            }
        }
        pencilFilter.reset()
        smoothedX = nil
        smoothedY = nil
        lastPressure = 0
        updateIndicator(normX: nil, normY: nil, pressure: 0)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = Self.pencilTouch(in: touches) else { return }
        pencilDown = false
        lastPencilAt = CACurrentMediaTime()
        let fallback = (x: smoothedX ?? 0.5, y: smoothedY ?? 0.5)
        pencilFilter.reset()
        smoothedX = nil
        smoothedY = nil
        lastPressure = 0

        let f = Pen.fraction(touch.preciseLocation(in: self), in: activeRect) ?? fallback
        if usesPenProtocol {
            sendPen(PenBatch(target: PenTarget.display,
                             samples: [PenSample(phase: PenPhase.leave, x: f.x, y: f.y, t: touch.timestamp)]))
        } else {
            sendInputEvent(.pointer(.leftUp, x: f.x, y: f.y))
        }
        updateIndicator(normX: nil, normY: nil, pressure: 0)
    }

    // MARK: - Finger Sliding → Mac Page Scrolling

    private func stopScrollCoast() {
        if scrollCoasting != nil {
            scrollCoasting?.cancel()
            scrollCoasting = nil
        }
        if scrollGestureActive {
            scrollGestureActive = false
            sendInputEvent(.scrollGesture(.ended, x: lastScrollNorm.x, y: lastScrollNorm.y))
        }
    }

    private func normalizedScrollDelta(_ dxPt: CGFloat, _ dyPt: CGFloat) -> (Double, Double) {
        let w = max(activeRect.width, 1)
        let h = max(activeRect.height, 1)
        return (Double(dxPt / w), Double(dyPt / h))
    }

    @objc private func handleFingerScroll(_ pan: UIPanGestureRecognizer) {
        if pencilDown || (CACurrentMediaTime() - lastPencilAt <= 0.08) {
            stopScrollCoast()
            return
        }
        let loc = pan.location(in: self)
        if let f = Pen.fraction(loc, in: activeRect) {
            lastScrollNorm = f
        }
        let sign: CGFloat = reverseScrolling ? -1.0 : 1.0
        switch pan.state {
        case .began:
            stopScrollCoast()
            lastPanTranslation = .zero
            scrollGestureActive = true
            sendInputEvent(.scrollGesture(.began, x: lastScrollNorm.x, y: lastScrollNorm.y))
        case .changed:
            let cur = pan.translation(in: self)
            let dxPt = (cur.x - lastPanTranslation.x) * sign
            let dyPt = (cur.y - lastPanTranslation.y) * sign
            lastPanTranslation = cur
            let (dx, dy) = normalizedScrollDelta(dxPt, dyPt)
            if abs(dxPt) > 0.1 || abs(dyPt) > 0.1 {
                sendInputEvent(.scroll(x: lastScrollNorm.x, y: lastScrollNorm.y, dx: dx, dy: dy))
            }
        case .ended:
            let vel = pan.velocity(in: self)
            var vxPt = (vel.x * sign) / 60.0
            var vyPt = (vel.y * sign) / 60.0
            if hypot(vxPt, vyPt) < 2.0 {
                stopScrollCoast()
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + (1.0 / 60.0), repeating: 1.0 / 60.0)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                if self.pencilDown {
                    self.stopScrollCoast()
                    return
                }
                vxPt *= 0.92
                vyPt *= 0.92
                if hypot(vxPt, vyPt) < 0.45 {
                    self.stopScrollCoast()
                    return
                }
                let (dx, dy) = self.normalizedScrollDelta(vxPt, vyPt)
                self.sendInputEvent(.scroll(x: self.lastScrollNorm.x, y: self.lastScrollNorm.y, dx: dx, dy: dy))
            }
            scrollCoasting = timer
            timer.resume()
        default:
            stopScrollCoast()
        }
    }

    // MARK: - Two-Finger Pinch → Mac Canvas Zoom

    private var pinchAccumulator: CGFloat = 1.0

    @objc private func handlePinchZoom(_ pinch: UIPinchGestureRecognizer) {
        if pencilDown || (CACurrentMediaTime() - lastPencilAt <= 0.08) {
            return
        }
        switch pinch.state {
        case .began:
            stopScrollCoast()
            pinchAccumulator = 1.0
        case .changed:
            let scale = pinch.scale
            pinchAccumulator *= scale
            pinch.scale = 1.0

            // Every ~7% scale delta, trigger a zoom step on the Mac (⌘+ or ⌘-)
            if pinchAccumulator >= 1.07 {
                // Zoom in: ⌘ + (HID usage 0x2E: =/+)
                for event in KeyChord.press(0x2E, with: .command) {
                    sendInputEvent(event)
                }
                pinchAccumulator /= 1.07
            } else if pinchAccumulator <= 0.93 {
                // Zoom out: ⌘ - (HID usage 0x2D: -/_)
                for event in KeyChord.press(0x2D, with: .command) {
                    sendInputEvent(event)
                }
                pinchAccumulator /= 0.93
            }
        case .ended, .cancelled:
            pinchAccumulator = 1.0
        default:
            break
        }
    }
}
