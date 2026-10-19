import Foundation

/// One pipeline's output admission on its server's network queue. Reset and output checks
/// share the queue: a callback already executing on a retired encoder cannot cross the
/// reset barrier, even if it enqueues after the new source acknowledgment.
final class StreamOutputGate {
    struct Generation: Equatable { fileprivate let id = UUID() }
    private let queue: DispatchQueue
    private var current: Generation?

    init(queue: DispatchQueue) { self.queue = queue }

    @discardableResult
    func reset(perform body: @escaping () -> Void) -> Generation {
        let generation = Generation()
        queue.async { [self] in
            current = generation
            body()
        }
        return generation
    }

    func enqueue(generation: Generation?, perform body: @escaping () -> Void) {
        queue.async { [self] in
            guard generation == nil || generation == current else { return }
            body()
        }
    }
}
