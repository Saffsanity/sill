import Foundation

var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { fatalError(message) }
}
var cycle = VisionToolbarHoverCycle()
let click = InputEvent.pointer(.leftDown, x: 0.5, y: 0.5)
let events: [InputEvent] = [click, .pointer(.rightDown, x: 0.5, y: 0.5),
                          .key(hidUsage: 4, down: true, modifiers: 0), .text("fixture"),
                          .scroll(x: 0.5, y: 0.5, dx: 0, dy: 0.1)]
var nativeIDs: Set<String> = [cycle.groupID(nativeReset: true)]
var legacyIDs: Set<String> = [cycle.groupID(nativeReset: false)]
for index in 0..<10_000 {
    cycle.input(events[index % events.count], automatic: true, admitted: true)
    nativeIDs.insert(cycle.groupID(nativeReset: true))
    legacyIDs.insert(cycle.groupID(nativeReset: false))
}
check(cycle.generation == 10_000, "Every accepted control advances the reset trigger")
check(nativeIDs.count == 1, "Native reset keeps exactly one ID across ten thousand inputs")
check(legacyIDs.count == 10_001, "Before-26 fallback preserves the original identity reset")
for event in events {
    cycle.input(event, automatic: true, admitted: false)
    check(cycle.generation == 10_000, "Rejected/stale/paused input never resets")
    cycle.input(event, automatic: false, admitted: true)
    check(cycle.generation == 10_000, "Pinned input never resets")
}
for event in [InputEvent.pointer(.move, x: 0.5, y: 0.5), .pointer(.leftUp, x: 0.5, y: 0.5),
              .pointer(.rightUp, x: 0.5, y: 0.5), .key(hidUsage: 4, down: false, modifiers: 0)] {
    cycle.input(event, automatic: true, admitted: true)
    check(cycle.generation == 10_000, "Movement/releases never reset")
}
cycle.input(.scrollGesture(.began, x: 0.5, y: 0.5), automatic: true, admitted: true)
check(cycle.generation == 10_001, "Scroll start resets")
cycle.input(events[4], automatic: true, admitted: true)
check(cycle.generation == 10_001, "Scroll delta in an active episode does not reset")
cycle.input(.scrollGesture(.ended, x: 0.5, y: 0.5), automatic: true, admitted: true)
check(cycle.generation == 10_001, "Scroll end does not reset")
cycle.input(.scrollGesture(.momentumBegan, x: 0.5, y: 0.5), automatic: true, admitted: true)
check(cycle.generation == 10_002, "Momentum preserves existing reset policy")
cycle.resetScrollEpisode()
cycle.input(events[4], automatic: true, admitted: true)
check(cycle.generation == 10_003, "Scene/source/session boundary resets scroll admission")
cycle.reset()
check(cycle.generation == 10_004, "Lock toggle can reset phase explicitly")
check(cycle.groupID(nativeReset: true) == nativeIDs.first!, "Explicit reset also preserves native ID")
var otherScene = VisionToolbarHoverCycle()
check(otherScene.generation == 0, "Scene-local cycles remain independent")
print("vision-toolbar-hover: \(checks) checks passed")
