import Foundation
var checks = 0
func expect(_ value: Bool, _ label: String) { checks += 1; if !value { fatalError(label) } }
for hidden: Bool? in [true, false, nil] {
    for minimized: Bool? in [true, false, nil] {
        expect(WindowCatalogPolicy.includesOffscreen(appHidden: hidden, minimized: minimized) == (hidden == false && minimized == false), "only confirmed visible, nonminimized state is eligible")
    }
}
let frame = CGRect(x: 10, y: 20, width: 600, height: 400)
let other = CGRect(x: 900, y: 20, width: 600, height: 400)
expect(WindowCatalogPolicy.uniqueFrameMatch(frame, in: [other, frame]) == 1, "find correct window across Space")
expect(WindowCatalogPolicy.uniqueFrameMatch(frame, in: [frame, frame]) == nil, "overlapping ambiguous windows must not borrow minimized state")
expect(WindowCatalogPolicy.uniqueFrameMatch(frame, in: [nil, frame]) == nil, "unknown candidate cannot establish uniqueness")
expect(WindowCatalogPolicy.uniqueFrameMatch(frame, in: [other]) == nil, "closed window not retained")
expect(WindowCatalogPolicy.uniqueFrameMatch(frame, in: []) == nil, "empty catalog")
expect(WindowCatalogPolicy.uniqueFrameMatch(.zero, in: [.zero]) == nil, "invalid geometry")
expect(WindowCatalogPolicy.uniqueFrameMatch(frame, in: [frame.offsetBy(dx: 4, dy: -4)]) == 0, "rounding tolerance")
expect(WindowCatalogPolicy.uniqueFrameMatch(frame, in: [frame.offsetBy(dx: 5, dy: 0)]) == nil, "different frame excluded")
print("window-catalog: \(checks) checks passed")

// Run the production worker pool with a slow first app and twelve later apps. All later apps
// must still be visited, and no more than four IPC probes may run together.
final class ProbeLog: @unchecked Sendable {
    let lock = NSLock()
    var active = 0, peak = 0
    var visited = Set<Int>()
    func begin(_ id: Int) { lock.lock(); active += 1; peak = max(peak, active); visited.insert(id); lock.unlock() }
    func end() { lock.lock(); active -= 1; lock.unlock() }
}
let log = ProbeLog(), finished = DispatchSemaphore(value: 0)
Task.detached {
    let result = await WindowCatalogPolicy.scanApps(Array(0..<13)) { id in
        log.begin(id)
        Thread.sleep(forTimeInterval: id == 0 ? 0.08 : 0.005)
        log.end()
        return id == 0 ? [] : [UInt32(id)]
    }
    expect(result == Set((1..<13).map(UInt32.init)), "slow/failed first app cannot starve any later app")
    expect(log.visited == Set(0..<13), "every app visited exactly once")
    expect(log.peak <= 4 && log.active == 0, "worker count bounded and all probes completed")
    let empty = await WindowCatalogPolicy.scanApps([Int]()) { _ in Set<UInt32>() }
    expect(empty.isEmpty, "empty app catalog completes")
    print("window-catalog: bounded four-worker pool visits all thirteen apps despite slow first probe")
    finished.signal()
}
expect(finished.wait(timeout: .now() + 5) == .success, "worker pool must complete")
