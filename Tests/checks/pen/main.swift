// Sources/StreamProtocol/Pen.swift on its own: the wire shape of kind 45, what the host accepts of a
// batch, the tilt and place mapping, the tablet area's fit, and the pen's state machine.
//   swiftc -O Sources/StreamProtocol/Pen.swift Tests/checks/pen/main.swift -o check && ./check
import CoreGraphics
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

// MARK: - Wire

let batch = PenBatch(target: PenTarget.display, samples: [
    PenSample(phase: PenPhase.down, x: 0.25, y: 0.75, pressure: 0.5, altitude: 1.0, azimuth: 2.0)])
let data = try! JSONEncoder().encode(batch)
check("a batch round-trips through JSON", (try? JSONDecoder().decode(PenBatch.self, from: data)) == batch)
let json = String(decoding: data, as: UTF8.self)
check("phase and target are plain numbers on the wire", json.contains("\"phase\":1") && json.contains("\"target\":1"))
let cap = PenCapability(generation: Pen.generation, displayWidth: 1512, displayHeight: 982)
check("the capability round-trips", (try? JSONDecoder().decode(PenCapability.self, from: JSONEncoder().encode(cap))) == cap)

// MARK: - What the host accepts

check("an unknown target is refused", Pen.accepted(PenBatch(target: 7, samples: [PenSample(phase: 0, x: 0, y: 0)])) == nil)
check("the source target is accepted", Pen.accepted(PenBatch(target: PenTarget.source, samples: [])) == [])
let messy = PenBatch(target: PenTarget.source, samples: [
    PenSample(phase: 9, x: 0.5, y: 0.5),                                  // unknown phase
    PenSample(phase: PenPhase.drag, x: .nan, y: 0.5, pressure: 0.5),      // not finite
    PenSample(phase: PenPhase.drag, x: 1.5, y: -0.5, pressure: 3, altitude: 4, t: 123.456),
    PenSample(phase: PenPhase.hover, x: 0.5, y: 0.5, pressure: 0.8, t: -5),
    PenSample(phase: PenPhase.up, x: 0.5, y: 0.5, pressure: 0.8, t: .infinity),
])
let kept = Pen.accepted(messy)!
check("unknown phases and non-finite samples are dropped", kept.count == 3)
check("places are clamped to 0…1", kept[0].x == 1 && kept[0].y == 0)
check("pressure is clamped to 1 while touching", kept[0].pressure == 1)
check("altitude is clamped to π/2", near(kept[0].altitude, .pi / 2))
check("a valid device timestamp is preserved", kept[0].t == 123.456)
check("negative or non-finite timestamps become nil", kept[1].t == nil && kept[2].t == nil)
check("a hover carries no pressure", kept[1].pressure == 0)
check("an up carries no pressure", kept[2].pressure == 0)
let flood = PenBatch(target: PenTarget.source, samples: Array(repeating: PenSample(phase: PenPhase.drag, x: 0, y: 0), count: 500))
check("at most maxSamples are kept", Pen.accepted(flood)!.count == Pen.maxSamples)

// MARK: - Tilt and place

let upright = Pen.tilt(altitude: .pi / 2, azimuth: 1.3)
check("an upright pen has no tilt", abs(upright.x) < 1e-9 && abs(upright.y) < 1e-9)
let flatRight = Pen.tilt(altitude: 0, azimuth: 0)
check("flat, pointing right: tilt x 1", near(flatRight.x, 1) && abs(flatRight.y) < 1e-9)
let flatDown = Pen.tilt(altitude: 0, azimuth: .pi / 2)
check("flat, pointing down the screen: tilt y 1", abs(flatDown.x) < 1e-9 && near(flatDown.y, 1))
let half = Pen.tilt(altitude: .pi / 3, azimuth: .pi)
check("60° up, pointing left: tilt x −0.5", near(half.x, -0.5))

let rect = CGRect(x: 100, y: 50, width: 1000, height: 500)
check("a sample lands inside the target rectangle",
      Pen.point(PenSample(phase: 0, x: 0.5, y: 0.2), in: rect) == CGPoint(x: 600, y: 150))

// MARK: - The tablet area

let area = Pen.fit(CGSize(width: 16, height: 10), in: CGSize(width: 1000, height: 1000))
check("a 16:10 display in a square: full width, centred", area == CGRect(x: 0, y: 187.5, width: 1000, height: 625))
let tall = Pen.fit(CGSize(width: 10, height: 10), in: CGSize(width: 800, height: 400))
check("a square display in a wide area: full height, centred", tall == CGRect(x: 200, y: 0, width: 400, height: 400))
check("an empty display fills the area", Pen.fit(.zero, in: CGSize(width: 10, height: 20)) == CGRect(x: 0, y: 0, width: 10, height: 20))
let f = Pen.fraction(CGPoint(x: 600, y: 300), in: rect)!
check("a point's fractions in a rectangle", near(f.x, 0.5) && near(f.y, 0.5))
let edge = Pen.fraction(CGPoint(x: -50, y: 9999), in: rect)!
check("a point outside is clamped to the edge", edge.x == 0 && edge.y == 1)
check("an empty rectangle has no fractions", Pen.fraction(.zero, in: .zero) == nil)

// MARK: - The pen's state

func run(_ phases: [Int]) -> [[Pen.Post]] {
    var s = PenState()
    return phases.map { s.posts(for: $0) }
}
check("a whole stroke: enter, move, down, drag, drag, up, move, leave",
      run([PenPhase.hover, PenPhase.down, PenPhase.drag, PenPhase.drag, PenPhase.up, PenPhase.hover, PenPhase.leave])
        == [[.enter, .move], [.down], [.drag], [.drag], [.up], [.move], [.leave]])
check("a down without a hover enters first (an iPad without hover)", run([PenPhase.down]) == [[.enter, .down]])
check("a drag without a down is the down", run([PenPhase.drag, PenPhase.drag]) == [[.enter, .down], [.drag]])
check("a second down while down is a drag", run([PenPhase.down, PenPhase.down]) == [[.enter, .down], [.drag]])
check("a hover while down lifts first", run([PenPhase.down, PenPhase.hover]) == [[.enter, .down], [.up, .move]])
check("a leave while down lifts and leaves", run([PenPhase.down, PenPhase.leave]) == [[.enter, .down], [.up, .leave]])
check("an up when not down posts nothing", run([PenPhase.up]) == [[]])
check("a leave when not near posts nothing", run([PenPhase.leave]) == [[]])
check("an unknown phase posts nothing", run([42]) == [[]])

var held = PenState()
_ = held.posts(for: PenPhase.down)
check("an up only lifts a pen that is down", held.onlyLifts([PenSample(phase: PenPhase.up, x: 0, y: 0)]))
check("an up and a leave only lift", held.onlyLifts([PenSample(phase: PenPhase.up, x: 0, y: 0), PenSample(phase: PenPhase.leave, x: 0, y: 0)]))
check("a drag is more than a lift", !held.onlyLifts([PenSample(phase: PenPhase.up, x: 0, y: 0), PenSample(phase: PenPhase.drag, x: 0, y: 0)]))
check("an empty batch lifts nothing", !held.onlyLifts([]))
check("nothing lifts a pen that is up", !PenState().onlyLifts([PenSample(phase: PenPhase.up, x: 0, y: 0)]))
check("letting go of a down pen: up, then leave", held.letGo() == [.up, .leave] && !held.near && !held.down)
var idle = PenState()
check("letting go of a pen that was never near posts nothing", idle.letGo() == [])

// MARK: - Smoothing

let s0 = Pen.smooth(raw: (0.25, 0.75), previous: nil)
check("first sample passes through unsmoothed", near(s0.x, 0.25) && near(s0.y, 0.75))
let slow = Pen.smooth(raw: (0.2505, 0.75), previous: s0)
check("tiny micro-jitter damps near 0.42 alpha", slow.x > 0.25 && slow.x < 0.25025)
let fast = Pen.smooth(raw: (0.35, 0.75), previous: s0)
check("fast stroke ramps up to 0.92 alpha", near(fast.x, 0.25 + 0.92 * 0.1))

// MARK: - PenFilter (1€ Anti-Jitter Filter)

var filter = PenFilter()
let p0 = filter.apply(rawX: 0.25, rawY: 0.75)
check("PenFilter first sample passes through directly", near(p0.x, 0.25) && near(p0.y, 0.75))

// Test slow diagonal stroke with 10 Hz digitizer ripple
filter.reset()
let dt = 1.0 / 240.0
let speedNorm = 150.0 / 2000.0 // 150 px/sec across 2000 px screen
var rawYVals: [Double] = []
var filteredYVals: [Double] = []

for i in 0..<240 {
    let t = Double(i) * dt
    let idealX = 0.1 + speedNorm * t
    let idealY = 0.5
    let rippleY = (1.0 / 1500.0) * sin(2.0 * .pi * 10.0 * t) // 1.0 px ripple on 1500 px height
    rawYVals.append(rippleY)
    let out = filter.apply(rawX: idealX, rawY: idealY + rippleY, rate: 240.0)
    filteredYVals.append(out.y - idealY)
}

// Compare ripple amplitudes after filter warmup (drop first 30 samples)
let warmRaw = Array(rawYVals.dropFirst(30))
let warmFiltered = Array(filteredYVals.dropFirst(30))
let rawAmp = (warmRaw.max()! - warmRaw.min()!) / 2.0
let filteredAmp = (warmFiltered.max()! - warmFiltered.min()!) / 2.0
let suppression = (1.0 - (filteredAmp / rawAmp)) * 100.0

check("PenFilter suppresses 10 Hz digitizer ripple by over 80%", suppression > 80.0)

// Test fast stroke tracking lag
var fastFilter = PenFilter()
let fastSpeedNorm = 1500.0 / 2000.0 // 1500 px/sec fast flick
var lags: [Double] = []
for i in 0..<60 {
    let t = Double(i) * dt
    let rawX = 0.1 + fastSpeedNorm * t
    let out = fastFilter.apply(rawX: rawX, rawY: 0.5, rate: 240.0)
    if i >= 15 {
        let lagNorm = rawX - out.x
        let lagMs = (lagNorm / fastSpeedNorm) * 1000.0
        lags.append(lagMs)
    }
}
let avgLagMs = lags.reduce(0, +) / Double(lags.count)
check("PenFilter fast stroke tracking lag under 20 ms", avgLagMs < 20.0)

// Test reset
fastFilter.reset()
let pReset = fastFilter.apply(rawX: 0.8, rawY: 0.2)
check("PenFilter reset restarts tracking without lag from previous stroke", near(pReset.x, 0.8) && near(pReset.y, 0.2))

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
