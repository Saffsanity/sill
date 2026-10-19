import Foundation

let queue = DispatchQueue(label: "test.stream-output")
let root = StreamOutputGate(queue: queue)
let sibling = StreamOutputGate(queue: queue)
var delivered: [String] = []
var cachedFormat: String?
let old = root.reset { cachedFormat = nil }
root.enqueue(generation: old) { cachedFormat = "window"; delivered.append("old-before-reset") }
let siblingGeneration = sibling.reset { }
// Hold the old encoder callback until reset and the new source acknowledgment are queued.
let callbackEntered = DispatchSemaphore(value: 0)
let releaseCallback = DispatchSemaphore(value: 0)
let callbackDone = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    callbackEntered.signal()
    releaseCallback.wait()
    root.enqueue(generation: old) { cachedFormat = "stale-window"; delivered.append("stale-parameter-sets") }
    root.enqueue(generation: old) { delivered.append("stale-frame") }
    callbackDone.signal()
}
callbackEntered.wait()
let desktop = root.reset { cachedFormat = nil; delivered.append("reset") }
root.enqueue(generation: nil) { delivered.append("desktop-ack") }
releaseCallback.signal()
callbackDone.wait()
root.enqueue(generation: desktop) { cachedFormat = "desktop"; delivered.append("desktop-parameter-sets") }
root.enqueue(generation: desktop) { delivered.append("desktop-frame") }
sibling.enqueue(generation: siblingGeneration) { delivered.append("sibling-frame") }
// A failed first capture attempt must not publish into its fallback pipeline either.
let fallback = root.reset { cachedFormat = nil; delivered.append("fallback-reset") }
root.enqueue(generation: desktop) { cachedFormat = "failed-attempt"; delivered.append("failed-attempt-frame") }
root.enqueue(generation: fallback) { cachedFormat = "fallback"; delivered.append("fallback-frame") }
queue.sync { }
let expected = ["old-before-reset", "reset", "desktop-ack", "desktop-parameter-sets", "desktop-frame", "sibling-frame", "fallback-reset", "fallback-frame"]
precondition(delivered == expected, "Retired output crossed reset: \(delivered)")
precondition(cachedFormat == "fallback", "Retired parameter sets replaced the active cache")
print("stream-output: delayed callbacks, cache provenance, fallback, control ordering and sibling isolation passed")
