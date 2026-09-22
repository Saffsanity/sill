import Foundation

/// Per-second counters for the spike, printed as one line so a stalled stage is obvious.
/// Bumped from the capture queue, VideoToolbox's callback thread and the network queue
/// under a lock; the snapshot and print happen on the main queue.
final class Stats {
    static let shared = Stats()

    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var timer: DispatchSourceTimer?

    func bump(_ key: String) {
        lock.lock(); counts[key, default: 0] += 1; lock.unlock()
    }

    func startPrinting() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [self] in
            lock.lock(); let snapshot = counts; counts = [:]; lock.unlock()
            let line = snapshot.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "  ")
            print("[1s] " + (line.isEmpty ? "nothing captured" : line))
        }
        timer.resume()
        self.timer = timer
    }
}
