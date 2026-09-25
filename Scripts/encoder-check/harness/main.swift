import Foundation
import CoreMedia
import CoreVideo
import QuartzCore

// Hardware harness (never shipped; USES THE MAC'S HARDWARE VIDEO ENCODER): drives the real
// HEVCEncoder.swift of a tree (compiled into this module with its EncoderProbe.swift, Stats.swift
// and StreamProtocol, by build.sh) with a moving test pattern in phases, and logs each second's
// frames in, enc.out, enc.mailboxDrop, the capture-to-output latency (host clock at the output
// handler minus the frame's timestamp, which is the host clock at capture, as ScreenCaptureKit's
// is), output handlers that overlapped and outputs out of timestamp order. Run it only through
// verify-hardware.sh, which checks first that no device is connected to Sill.app.
//
// usage: harness WIDTH HEIGHT BITRATE PHASE...      PHASE = dense:S | sparse:S@INTERVAL | still:S
//        harness probe WIDTH HEIGHT [N]             EncoderProbe.throughput N times at that size
//        harness keyframe WIDTH HEIGHT BITRATE [N]  N sessions: 12 frames at 60 fps, a keyframe
//                                                   asked for 5, 20 or 40 ms after the last, then
//                                                   still for 0.5 s: does a keyframe come out?
//
// The copy of HEVCEncoder.swift compiled here has one line added at the top of `handle(_:)`:
// `harnessOutputPTS = CMSampleBufferGetPresentationTimeStamp(sb)`.

var harnessOutputPTS = CMTime.invalid
setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())

if args.first == "probe" {
    let w = Int(args[1])!, h = Int(args[2])!, n = args.count > 3 ? Int(args[3])! : 3
    for i in 0..<n {
        let r = EncoderProbe.throughput(width: w, height: h)
        print(String(format: "probe %d: %dx%d ok %@ fps %@ ms %d", i + 1, w, h, r.ok ? "yes" : "no",
                     r.fps.map { String(format: "%.1f", $0) } ?? "-", r.ms))
        usleep(200_000)
    }
    exit(0)
}

if args.first == "keyframe" {
    // A device joining, or one whose delta was dropped, just after the window's last repaint: the
    // request comes within 50 ms of it and nothing repaints after. 4fe37d4 only set the flag then
    // (no keyframe until the next repaint); HEVCEncoder.keyframeCheck re-encodes the last frame
    // about 60 ms after that repaint.
    let w = Int(args[1])!, h = Int(args[2])!, rate = Int(args[3])!, n = args.count > 4 ? Int(args[4])! : 6
    var kpool: CVPixelBufferPool?
    let kattrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                   kCVPixelBufferWidthKey: w, kCVPixelBufferHeightKey: h,
                                   kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
    CVPixelBufferPoolCreate(nil, nil, kattrs as CFDictionary, &kpool)
    let capture = DispatchQueue(label: "harness.capture", qos: .userInteractive)
    func frame(_ k: Int) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, kpool!, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let yw = CVPixelBufferGetWidthOfPlane(pb!, 0), yh = CVPixelBufferGetHeightOfPlane(pb!, 0)
        if let y = CVPixelBufferGetBaseAddressOfPlane(pb!, 0) {
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pb!, 0)
            memset(y, 96, stride * yh)
            let bar = max(8, yw / 20), x0 = (k * max(1, yw / 60)) % max(1, yw - bar)
            for row in 0..<yh { memset(y.advanced(by: row * stride + x0), 235, bar) }
        }
        if let uv = CVPixelBufferGetBaseAddressOfPlane(pb!, 1) {
            memset(uv, 128, CVPixelBufferGetBytesPerRowOfPlane(pb!, 1) * CVPixelBufferGetHeightOfPlane(pb!, 1))
        }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
    }
    func until(_ t: CFTimeInterval) { while CACurrentMediaTime() < t { usleep(200) } }
    let gaps = [0.005, 0.020, 0.040]
    var answered = 0
    for i in 0..<n {
        let gap = gaps[i % gaps.count]
        let e = try! HEVCEncoder(width: w, height: h, fps: 60, bitrate: rate, prioritizeSpeed: false, software: false)
        let klock = NSLock()
        var keys: [CFTimeInterval] = []
        e.onEncoded = { _, isKey, _ in if isKey { klock.lock(); keys.append(CACurrentMediaTime()); klock.unlock() } }
        var lastAt: CFTimeInterval = 0
        let t0 = CACurrentMediaTime() + 0.01
        for k in 0..<12 {
            until(t0 + Double(k) / 60)
            let pb = frame(k)
            capture.sync { e.encode(pb, pts: CMClockGetTime(CMClockGetHostTimeClock())) }
            lastAt = CACurrentMediaTime()
        }
        until(lastAt + gap)
        let requestAt = CACurrentMediaTime()
        e.requestKeyframe()
        Thread.sleep(forTimeInterval: 0.5)
        klock.lock(); let after = keys.filter { $0 >= requestAt }; klock.unlock()
        if let first = after.first {
            answered += 1
            print(String(format: "keyframe %d: asked %.0f ms after the last frame; a keyframe came out %.0f ms after it", i + 1, (requestAt - lastAt) * 1000, (first - lastAt) * 1000))
        } else {
            print(String(format: "keyframe %d: asked %.0f ms after the last frame; NO keyframe in 0.5 s", i + 1, (requestAt - lastAt) * 1000))
        }
        withExtendedLifetime(e) {}
        Thread.sleep(forTimeInterval: 0.1)
    }
    print("keyframe: answered \(answered) of \(n) at \(w)x\(h)")
    exit(0)
}

let width = Int(args[0])!, height = Int(args[1])!, bitrate = Int(args[2])!
struct Phase { let kind: String; let seconds: Double; let interval: Double }
let phases: [Phase] = args.dropFirst(3).map { spec in
    let (head, interval) = spec.contains("@") ? (String(spec.split(separator: "@")[0]), Double(spec.split(separator: "@")[1])!) : (spec, 0)
    let parts = head.split(separator: ":")
    return Phase(kind: String(parts[0]), seconds: Double(parts[1])!, interval: interval)
}
let total = phases.reduce(0) { $0 + $1.seconds }

let enc = try! HEVCEncoder(width: width, height: height, fps: 60, bitrate: bitrate, prioritizeSpeed: false, software: false)
let lock = NSLock()
var active = 0, overlaps = 0, outOfOrder = 0, lastOut = CMTime.invalid
var secLatencies: [Double] = [], allLatencies: [(Double, Double)] = []   // (seconds since start, ms)
var secIn = 0
var hung = false
let start = CACurrentMediaTime()
enc.onEncoded = { _, _, _ in
    lock.lock(); active += 1; if active > 1 { overlaps += 1 }; lock.unlock()
    let pts = harnessOutputPTS
    let now = CMClockGetTime(CMClockGetHostTimeClock())
    let ms = CMTimeGetSeconds(CMTimeSubtract(now, pts)) * 1000
    lock.lock()
    if lastOut.isValid, CMTimeCompare(pts, lastOut) <= 0 { outOfOrder += 1 }
    lastOut = pts
    secLatencies.append(ms)
    allLatencies.append((CACurrentMediaTime() - start, ms))
    active -= 1
    lock.unlock()
}
enc.onHung = { lock.lock(); hung = true; lock.unlock(); print("HUNG at \(String(format: "%.2f", CACurrentMediaTime() - start)) s") }

var pool: CVPixelBufferPool?
let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                              kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                              kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
let feedQueue = DispatchQueue(label: "harness.feed", qos: .userInteractive)
var frameIndex = 0
var lastEmit = -1.0

func phase(at t: Double) -> (Phase, Int)? {
    var acc = 0.0
    for (i, p) in phases.enumerated() { acc += p.seconds; if t < acc { return (p, i) } }
    return nil
}

func emit() {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &pb)
    guard let pb else { return }
    frameIndex += 1
    CVPixelBufferLockBaseAddress(pb, [])
    let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
    if let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        memset(y, 96, stride * h)
        let bar = max(8, w / 20)
        let x0 = (frameIndex * max(1, w / 60)) % max(1, w - bar)
        for row in 0..<h { memset(y.advanced(by: row * stride + x0), 235, bar) }
    }
    if let uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
        memset(uv, 128, CVPixelBufferGetBytesPerRowOfPlane(pb, 1) * CVPixelBufferGetHeightOfPlane(pb, 1))
    }
    CVPixelBufferUnlockBaseAddress(pb, [])
    lock.lock(); secIn += 1; lock.unlock()
    enc.encode(pb, pts: CMClockGetTime(CMClockGetHostTimeClock()))
}

let timer = DispatchSource.makeTimerSource(queue: feedQueue)
timer.schedule(deadline: .now(), repeating: 1.0 / 60, leeway: .milliseconds(1))
timer.setEventHandler {
    let t = CACurrentMediaTime() - start
    guard let (p, _) = phase(at: t) else { return }
    switch p.kind {
    case "dense": emit()
    case "sparse": if t - lastEmit >= p.interval { lastEmit = t; emit() }
    default: break
    }
}
timer.resume()

func pct(_ xs: [Double], _ p: Double) -> Double { xs.isEmpty ? .nan : xs.sorted()[min(xs.count - 1, Int(Double(xs.count) * p))] }

var second = 0
Stats.shared.onTick = { counts in
    second += 1
    lock.lock()
    let lat = secLatencies; secLatencies = []
    let inCount = secIn; secIn = 0
    let ov = overlaps, ooo = outOfOrder
    lock.unlock()
    let t = CACurrentMediaTime() - start
    let name = phase(at: t - 0.5).map { "\($0.0.kind)" } ?? "end"
    print(String(format: "t=%2d %-6@ in %2d  enc.out %2d  mailboxDrop %2d  latency median %5.1f p95 %5.1f max %5.1f ms  overlaps %d  outOfOrder %d",
                 second, name as NSString, inCount, counts["enc.out"] ?? 0, counts["enc.mailboxDrop"] ?? 0,
                 pct(lat, 0.5), pct(lat, 0.95), lat.max() ?? .nan, ov, ooo))
}
DispatchQueue.main.async { Stats.shared.startPrinting() }
DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.6) {
    timer.cancel()
    lock.lock()
    let all = allLatencies
    lock.unlock()
    for (i, p) in phases.enumerated() {
        let from = phases.prefix(i).reduce(0) { $0 + $1.seconds }, to = from + p.seconds
        // The last 60 % of each phase: past its start-up.
        let lat = all.filter { $0.0 >= from + p.seconds * 0.4 && $0.0 < to }.map(\.1)
        print(String(format: "phase %d %@ %.0f s: %d outputs in its last 60 %%: %.1f/s, latency median %.1f p95 %.1f ms", i + 1,
                     p.kind as NSString, p.seconds, lat.count, Double(lat.count) / (p.seconds * 0.6), pct(lat, 0.5), pct(lat, 0.95)))
    }
    print("overlapping output handlers: \(overlaps); outputs out of timestamp order: \(outOfOrder); hung: \(hung)")
    exit(0)
}
dispatchMain()
