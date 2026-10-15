import Foundation

/// An opt-in, parent-owned host. The private stdin pipe is the entire control
/// surface; there is no additional socket or unauthenticated network endpoint.
enum EmbeddedCommand: String {
    case settings, pair, quit
}

/// Bounded framing also handles commands split across reads. Invalid or oversized
/// input closes the control channel, rather than accumulating arbitrary data.
struct EmbeddedCommandDecoder {
    private var pending = Data()
    private(set) var closed = false

    mutating func feed(_ bytes: Data) -> [EmbeddedCommand] {
        guard !closed else { return [] }
        var commands: [EmbeddedCommand] = []
        for byte in bytes {
            if byte == 10 {
                guard let line = String(data: pending, encoding: .utf8),
                      let command = EmbeddedCommand(rawValue: line) else {
                    closed = true
                    return commands + [.quit]
                }
                pending.removeAll(keepingCapacity: true)
                commands.append(command)
                if command == .quit { closed = true; return commands }
            } else {
                guard pending.count < 32 else {
                    closed = true
                    return commands + [.quit]
                }
                pending.append(byte)
            }
        }
        return commands
    }
}
