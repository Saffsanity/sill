import Foundation
import StreamProtocol

// Knobs for the latency spike. Change, rebuild, measure.
let fps = 60
let scale: CGFloat = 2.0          // 2 = Retina capture, 1 = points (much cheaper)
let bitrate = 15_000_000          // bits per second
let prioritizeSpeed = false       // Apple: trades quality for encode speed; try after the baseline

let match = CommandLine.arguments.dropFirst().first

Task {
    do {
        let window = try await WindowCapture.findWindow(matching: match)
        let width = evenPixels(window.frame.width * scale)
        let height = evenPixels(window.frame.height * scale)
        print("\nStreaming \(window.owningApplication?.applicationName ?? "?") — \(window.title ?? "") at \(width)×\(height), \(fps) fps, \(bitrate / 1_000_000) Mbps")
        print("Keep this window the same size; the encoder is fixed to it for now.\n")

        let encoder = try HEVCEncoder(width: width, height: height, fps: fps, bitrate: bitrate, prioritizeSpeed: prioritizeSpeed)
        let server = try StreamServer()
        let capture = WindowCapture()

        server.onClientConnected = { encoder.requestKeyframe() }
        encoder.onEncoded = { data, isKey, parameterSets in
            let now = Date().timeIntervalSince1970
            if let ps = parameterSets {
                server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: ps.encoded()))
            }
            server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: isKey, payload: data))
        }
        capture.onFrame = { pixelBuffer, pts in encoder.encode(pixelBuffer, pts: pts) }

        server.start()
        try await capture.start(window: window, scale: scale, fps: fps)
        print("Advertising _winstream._tcp on the local network. Open the iOS app. Ctrl-C to stop.")
    } catch {
        print("Error: \(error)")
        print("If this is a permissions error: System Settings › Privacy & Security › Screen Recording, enable Terminal, then run again.")
        exit(1)
    }
}

dispatchMain()
