import AppKit
import Darwin

@MainActor
final class EmbeddedControl {
    nonisolated static let enabled = CommandLine.arguments.contains("--embedded")
    private weak var delegate: AppDelegate?
    private var ready = false
    private var waiting: [EmbeddedCommand] = []

    init(delegate: AppDelegate) { self.delegate = delegate }

    func start() {
        // A blocking read off the main thread costs no idle polling. Commands
        // enter AppKit through a run-loop timer, outside a dispatch/Task block.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var decoder = EmbeddedCommandDecoder()
            while !decoder.closed {
                var buffer = [UInt8](repeating: 0, count: 256)
                let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                let bytes = count > 0 ? Data(buffer.prefix(count)) : Data()
                let commands = bytes.isEmpty ? [.quit] : decoder.feed(bytes)
                for command in commands {
                    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
                            MainActor.assumeIsolated { self?.receive(command) }
                        }
                        RunLoop.main.add(timer, forMode: .common)
                    }
                    CFRunLoopWakeUp(CFRunLoopGetMain())
                }
                if bytes.isEmpty { break }
            }
        }
    }

    func hostDidStart() {
        ready = true
        Swift.print("SILL_EMBEDDED_READY")
        let commands = waiting
        waiting.removeAll()
        for command in commands { receive(command) }
    }

    private func receive(_ command: EmbeddedCommand) {
        if command == .quit {
            NSApp.terminate(nil)
        } else if !ready {
            guard waiting.count < 16 else { NSApp.terminate(nil); return }
            waiting.append(command)
        } else {
            switch command {
            case .settings: delegate?.showSettings(tab: nil)
            case .pair: delegate?.model.pairDevice()
            case .quit: break
            }
        }
    }
}
