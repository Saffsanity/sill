import Foundation
import CoreGraphics
#if canImport(StreamProtocol)
import StreamProtocol
#endif

// Two-dimensional cursor scrubbing for the full key row's `< v ^ >` arrow cluster and `UITextInput`'s
// Space-bar floating cursor.
//
// Lifecycle on an arrow cap (`begin` → `holdReady` / `move` → `end` / `cancel`):
//   - Quick tap (< `dragThreshold` travel, lifted before `holdDelay`): emits one press of the tapped
//     arrow with any latched modifiers, then spends the latch.
//   - Stationary hold (< `dragThreshold` travel, held ≥ `holdDelay`): `holdReady` sends `KeyChord.down`
//     and spends the latch once so the Mac repeats at its own Delay Until Repeat and Key Repeat Rate
//     until `end` or `cancel` sends `KeyChord.up`.
//   - Press and slide (≥ `dragThreshold` travel): enters `.scrubbing` (releasing any held chord first
//     and quantizing the crossing movement immediately), converting horizontal travel into ←/→ steps
//     with velocity acceleration and vertical travel into ↑/↓ steps with cross-axis drift dampening,
//     retaining latched modifiers (`opt` for word jumps, `shift` for selection) across every step of the
//     drag and spending an unspent latch once on `end` or `cancel` if at least one step went out.
//
// Pure: Foundation + CoreGraphics + KeyChords + StreamProtocol only, checked standalone in
// `Tests/checks/arrow-scrub`.

struct ArrowScrub {
    static let leftUsage: UInt16  = 0x50
    static let rightUsage: UInt16 = 0x4F
    static let downUsage: UInt16  = 0x51
    static let upUsage: UInt16    = 0x52

    /// Finger travel (points) that switches a press on an arrow cap into continuous cursor scrubbing.
    static let dragThreshold: CGFloat = 8.0
    /// Stationary hold duration (seconds) before classic Mac key-down begins.
    static let holdDelay: Double = 0.18
    /// Minimum time delta (seconds) for speed calculation (one 120 Hz ProMotion frame).
    static let minSampleInterval: Double = 1.0 / 120.0
    /// Horizontal points per character step at slow, medium and fast finger speeds.
    static let slowStepX: CGFloat = 8.0
    static let mediumStepX: CGFloat = 5.0
    static let fastStepX: CGFloat = 2.8
    /// Vertical points per line step.
    static let stepY: CGFloat = 16.0
    /// Speed thresholds (points/second) for horizontal acceleration.
    static let mediumSpeed: CGFloat = 240.0
    static let fastSpeed: CGFloat = 520.0
    /// Cross-axis dominance ratio above which the minor axis delta and remainder are dampened.
    static let axisLockRatio: CGFloat = 1.3
    static let minorAxisDecay: CGFloat = 0.25
    /// Maximum total arrow presses emitted from a single update across both axes combined.
    static let maxStepsPerUpdate = 8

    struct StepResult: Equatable {
        var events: [InputEvent] = []
        var ticks: Int = 0
        var spendsLatch: Bool = false
    }

    enum Phase: Equatable {
        case idle
        case waiting(cap: UInt16, start: CGPoint, startedAt: Double, modifiers: KeyModifiers)
        case holding(cap: UInt16, start: CGPoint, heldAt: Double, modifiers: KeyModifiers)
        case scrubbing(fromCap: Bool, last: CGPoint, lastAt: Double, accumX: CGFloat, accumY: CGFloat,
                       modifiers: KeyModifiers, stepped: Bool, latchSpent: Bool)
    }

    private(set) var phase: Phase = .idle

    var isActive: Bool { phase != .idle }
    var isScrubbing: Bool {
        if case .scrubbing = phase { return true }
        return false
    }

    /// Starts a touch on an arrow cap (`cap` in 0x4F...0x52).
    mutating func begin(cap: UInt16, at point: CGPoint, time: Double, latched: KeyModifiers) -> StepResult {
        let cleanup = cancel()
        phase = .waiting(cap: cap, start: point, startedAt: time, modifiers: latched)
        return cleanup
    }

    /// Starts direct scrubbing with no initial cap (`UITextInput.beginFloatingCursor`).
    mutating func beginFloating(at point: CGPoint, time: Double, latched: KeyModifiers) -> StepResult {
        let cleanup = cancel()
        phase = .scrubbing(fromCap: false, last: point, lastAt: time, accumX: 0, accumY: 0,
                           modifiers: latched, stepped: false, latchSpent: false)
        return cleanup
    }

    /// Called when `holdDelay` elapses: begins classic key-down hold only if the finger is still waiting.
    mutating func holdReady(at time: Double) -> StepResult {
        guard case .waiting(let cap, let start, let startedAt, let modifiers) = phase,
              time - startedAt >= Self.holdDelay - 0.001 else {
            return StepResult()
        }
        phase = .holding(cap: cap, start: start, heldAt: time, modifiers: modifiers)
        return StepResult(events: KeyChord.down(cap, with: modifiers), ticks: 0, spendsLatch: !modifiers.isEmpty)
    }

    /// Finger moved to `point` at `time`.
    mutating func move(to point: CGPoint, time: Double) -> StepResult {
        switch phase {
        case .idle:
            return StepResult()

        case .waiting(_, let start, let startedAt, let modifiers):
            let dx = point.x - start.x, dy = point.y - start.y
            guard hypot(dx, dy) >= Self.dragThreshold else { return StepResult() }
            phase = .scrubbing(fromCap: true, last: start, lastAt: startedAt, accumX: 0, accumY: 0,
                               modifiers: modifiers, stepped: false, latchSpent: false)
            return advanceScrub(to: point, time: time)

        case .holding(let cap, let start, let heldAt, let modifiers):
            let dx = point.x - start.x, dy = point.y - start.y
            guard hypot(dx, dy) >= Self.dragThreshold else { return StepResult() }
            let release = KeyChord.up(cap, with: modifiers)
            phase = .scrubbing(fromCap: true, last: start, lastAt: heldAt, accumX: 0, accumY: 0,
                               modifiers: modifiers, stepped: true, latchSpent: true)
            let sub = advanceScrub(to: point, time: time)
            return StepResult(events: release + sub.events, ticks: sub.ticks, spendsLatch: false)

        case .scrubbing:
            return advanceScrub(to: point, time: time)
        }
    }

    /// Finger lifted at `point` and `time`. Feeds any final movement arriving with `touchesEnded` first.
    mutating func end(at point: CGPoint? = nil, time: Double) -> StepResult {
        var moved = StepResult()
        if let point {
            moved = move(to: point, time: time)
        }
        defer { phase = .idle }
        switch phase {
        case .idle:
            return moved
        case .waiting(let cap, _, _, let modifiers):
            return StepResult(events: moved.events + KeyChord.press(cap, with: modifiers),
                              ticks: moved.ticks,
                              spendsLatch: moved.spendsLatch || !modifiers.isEmpty)
        case .holding(let cap, _, _, let modifiers):
            return StepResult(events: moved.events + KeyChord.up(cap, with: modifiers),
                              ticks: moved.ticks,
                              spendsLatch: moved.spendsLatch)
        case .scrubbing(let fromCap, _, _, let accumX, let accumY, let modifiers, let stepped, let latchSpent):
            if fromCap, !stepped, hypot(accumX, accumY) >= Self.dragThreshold * 0.5 {
                let usage: UInt16
                if abs(accumX) >= abs(accumY) {
                    usage = accumX >= 0 ? Self.rightUsage : Self.leftUsage
                } else {
                    usage = accumY >= 0 ? Self.downUsage : Self.upUsage
                }
                return StepResult(events: moved.events + KeyChord.press(usage, with: modifiers),
                                  ticks: moved.ticks + 1,
                                  spendsLatch: !latchSpent && !modifiers.isEmpty)
            }
            return StepResult(events: moved.events,
                              ticks: moved.ticks,
                              spendsLatch: moved.spendsLatch || (stepped && !latchSpent && !modifiers.isEmpty))
        }
    }

    /// Cancels an interrupted gesture (rotation, Control Center, disappearance): releases any held chord
    /// and spends the UI latch if a scrub step already went out on the Mac.
    mutating func cancel() -> StepResult {
        defer { phase = .idle }
        switch phase {
        case .holding(let cap, _, _, let modifiers):
            return StepResult(events: KeyChord.up(cap, with: modifiers), ticks: 0, spendsLatch: false)
        case .scrubbing(_, _, _, _, _, let modifiers, let stepped, let latchSpent):
            return StepResult(events: [], ticks: 0, spendsLatch: stepped && !latchSpent && !modifiers.isEmpty)
        case .idle, .waiting:
            return StepResult()
        }
    }

    private mutating func advanceScrub(to point: CGPoint, time: Double) -> StepResult {
        guard case .scrubbing(let fromCap, let last, let lastAt, var accumX, var accumY,
                              let modifiers, var stepped, let latchSpent) = phase else {
            return StepResult()
        }
        let ddx = point.x - last.x
        let ddy = point.y - last.y
        let dt = max(time - lastAt, Self.minSampleInterval)
        let speed = hypot(ddx, ddy) / CGFloat(dt)

        if abs(ddx) > abs(ddy) * Self.axisLockRatio {
            accumX += ddx
            accumY = (accumY + ddy) * Self.minorAxisDecay
        } else if abs(ddy) > abs(ddx) * Self.axisLockRatio {
            accumY += ddy
            accumX = (accumX + ddx) * Self.minorAxisDecay
        } else {
            accumX += ddx
            accumY += ddy
        }

        let unitX: CGFloat
        if speed >= Self.fastSpeed {
            unitX = Self.fastStepX
        } else if speed >= Self.mediumSpeed {
            unitX = Self.mediumStepX
        } else {
            unitX = Self.slowStepX
        }

        var rawX = Int((accumX / unitX).rounded(.towardZero))
        var rawY = Int((accumY / Self.stepY).rounded(.towardZero))

        if rawX != 0 { accumX -= CGFloat(rawX) * unitX }
        if rawY != 0 { accumY -= CGFloat(rawY) * Self.stepY }

        if abs(rawY) > abs(rawX) {
            rawY = min(max(rawY, -Self.maxStepsPerUpdate), Self.maxStepsPerUpdate)
            let rem = Self.maxStepsPerUpdate - abs(rawY)
            rawX = min(max(rawX, -rem), rem)
        } else {
            rawX = min(max(rawX, -Self.maxStepsPerUpdate), Self.maxStepsPerUpdate)
            let rem = Self.maxStepsPerUpdate - abs(rawX)
            rawY = min(max(rawY, -rem), rem)
        }

        var events: [InputEvent] = []
        var ticks = 0

        if rawX != 0 {
            let usage = rawX > 0 ? Self.rightUsage : Self.leftUsage
            let count = abs(rawX)
            for _ in 0..<count {
                events += KeyChord.press(usage, with: modifiers)
            }
            ticks += count
            stepped = true
        }
        if rawY != 0 {
            let usage = rawY > 0 ? Self.downUsage : Self.upUsage
            let count = abs(rawY)
            for _ in 0..<count {
                events += KeyChord.press(usage, with: modifiers)
            }
            ticks += count
            stepped = true
        }

        phase = .scrubbing(fromCap: fromCap, last: point, lastAt: time, accumX: accumX, accumY: accumY,
                           modifiers: modifiers, stepped: stepped, latchSpent: latchSpent)
        return StepResult(events: events, ticks: ticks, spendsLatch: false)
    }
}
