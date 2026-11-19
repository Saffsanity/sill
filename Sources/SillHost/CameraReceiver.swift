import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import Network
import os
import UniformTypeIdentifiers
import VideoToolbox
import StreamProtocol

/// Where a device's decoded camera frames go (docs/camera-plan.md §7): the seam where Sill Camera, the
/// Core Media I/O camera extension, takes them (Sill.app's CameraSink, with the extension, in a later
/// step), or the TEST ONLY CameraTestOutput on a test host. Everything here is called on `sill.camera`.
protocol CameraOutput: AnyObject {
    /// The pixel format the receiver's decoder makes for it (NV12 for Sill Camera, BGRA for the test's PNGs).
    var pixelFormat: OSType { get }
    /// What Sill Camera shows while no frame is live: nobody, "Turn on Share Camera…", or the holder's name
    /// and its pause.
    func feedChanged(_ feed: CameraHostPolicy.Feed)
    /// One decoded frame, upright as the device sent it, with its capture time (the device's wall clock).
    func frame(_ image: CVPixelBuffer, captured: Double)
    /// Set by the receiver before `start`: an app opening or closing Sill Camera, and Sill Camera's
    /// readiness (installed, allowed, running), as they change. Call on any queue.
    var onApp: ((CameraHostPolicy.AppUse?) -> Void)? { get set }
    var onReady: ((Bool) -> Void)? { get set }
    /// Whether Sill Camera is ready now; then `onReady` for every change.
    var ready: Bool { get }
    func start()
}

/// The Mac's receiving side of the devices' cameras (kind 46, docs/camera-plan.md §6.3, §7, §9): every
/// kind 46 comes here from StreamServer's network queue, in arrival order, with the lock's reading as it
/// arrived, never through the main actor; CameraHostPolicy decides on its own queue `sill.camera`; the
/// holder's frames go to VideoToolbox's decoder (never an encoder: on a test host VideoToolbox's software
/// decoder) and on to the output. Type 3 leaves through the server; kind 16's camera per connection and
/// what the window list says reach the main actor only when they change, never per frame. Nothing here
/// touches AppKit, so the CLI's `dispatchMain` is no concern (the CLI makes no receiver anyway).
final class CameraReceiver: @unchecked Sendable {
    /// `sill.camera`: the policy, the decoder, the output; every member below is touched only on it.
    let queue = DispatchQueue(label: "sill.camera", qos: .userInitiated)
    private var policy = CameraHostPolicy()
    private let output: CameraOutput
    private let server: StreamServer
    private let gate: LockGate
    /// A test host decodes in software, never on the Mac's media engines Noah's stream shares.
    private let software: Bool
    private let testLog: Bool
    private var ids: [ObjectIdentifier: Int] = [:]
    private var connections: [Int: NWConnection] = [:]
    private var names: [Int: String] = [:]
    private var keys: [Int: String] = [:]
    private var paired: [Int: Bool] = [:]
    private var nextID = 1
    private var decoder: CameraDecoder?
    /// After a new decoder or a failed decode: frames wait for a keyframe (the header's flag).
    private var awaitingKeyframe = true
    private var liveSaid: (session: Int, epoch: Int)?
    private var decoderFailedSaid: (session: Int, epoch: Int)?
    private var advertised: Int?
    private var timer: DispatchSourceTimer?
    private var decodedCount = 0
    /// Bytes of kind 46 handed over by the network queue and not yet dealt with here; past `maxBacklog` a
    /// frame is dropped before it is queued (latency beats quality).
    private let backlog = OSAllocatedUnfairLock(initialState: 0)
    static let maxBacklog = 2 << 20

    /// Each connection's kind 16 camera when it changes (nil: none), and the window list's `camera` (1 or
    /// 0) when it changes. Called on `sill.camera`; the coordinator hops to the main actor.
    var onStates: (([ObjectIdentifier: CameraState?]) -> Void)?
    var onAdvertised: ((Int) -> Void)?

    init(output: CameraOutput, server: StreamServer, gate: LockGate, software: Bool, testLog: Bool) {
        self.output = output
        self.server = server
        self.gate = gate
        self.software = software
        self.testLog = testLog
    }

    /// Starts: the switch, the lock's reading and Sill Camera's readiness pushed in, the output's
    /// callbacks set, the grace's tick every second.
    func start(switchOn: Bool) {
        output.onApp = { [weak self] app in self?.queue.async { self?.handle(.appChanged(app)) } }
        output.onReady = { [weak self] ready in self?.queue.async { self?.handle(.readyChanged(ready)) } }
        let unlocked = gate.reading == .unlocked
        queue.async { [self] in
            handle(.switchChanged(switchOn))
            handle(.readyChanged(output.ready))
            handle(.unlockedChanged(unlocked))
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
            t.setEventHandler { [weak self] in self?.handle(.tick) }
            t.resume()
            timer = t
            output.start()
        }
    }

    // MARK: From the coordinator (the main actor): sessions, the trust list, the lock, the switch

    /// A session joined, before its catalog goes: its key (nil at a plain door), whether that key is on
    /// the trust list now, its name for the lines, and whether it is away.
    func joined(_ connection: NWConnection, key: Data?, paired isPaired: Bool, name: String, away: Bool) {
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            let id = nextID
            nextID += 1
            ids[oid] = id
            connections[id] = connection
            names[id] = name
            keys[id] = key.map { Base64URL.encode($0) }
            paired[id] = isPaired
            handle(.joined(id, key: keys[id], paired: isPaired, name: name, away: away, reads: true))
        }
    }

    func left(_ connection: NWConnection) {
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            guard let id = ids.removeValue(forKey: oid) else { return }
            handle(.left(id))
            connections[id] = nil; names[id] = nil; keys[id] = nil; paired[id] = nil
        }
    }

    /// The Mac no longer serves the session (cut off): its camera ends now, its offer after the grace.
    func revoked(_ connection: NWConnection) {
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            guard let id = ids[oid] else { return }
            paired[id] = false
            handle(.paired(id, false))
        }
    }

    /// Each session's key as the trust list has it now (the status snapshot, on every change): one that
    /// left the list is the device's removal (its camera freed at once), one that joined it counts from now.
    func syncPaired(_ now: [ObjectIdentifier: Bool]) {
        queue.async { [self] in
            for (oid, isPaired) in now {
                guard let id = ids[oid], let was = paired[id], was != isPaired else { continue }
                paired[id] = isPaired
                if !isPaired, let key = keys[id] { handle(.removed(key: key)) } else { handle(.paired(id, isPaired)) }
            }
        }
    }

    func setSwitch(_ on: Bool) { queue.async { [self] in handle(.switchChanged(on)) } }

    /// This user on the console with its screen unlocked (LockPolicy's reading, as the coordinator acts on it).
    func setUnlocked(_ unlocked: Bool) { queue.async { [self] in handle(.unlockedChanged(unlocked)) } }

    // MARK: From the network queue: kind 46

    /// A kind 46 from `connection`, with the lock's reading as it arrived. Never waits: past `maxBacklog`
    /// bytes not yet dealt with, a frame is dropped here and counted.
    func received(_ message: StreamMessage, from connection: NWConnection, arrived: LockPolicy.Reading) {
        let size = message.payload.count
        let taken = backlog.withLock { pending -> Bool in
            guard pending + size <= Self.maxBacklog || message.payload.first != CameraMessage.typeFrame else { return false }
            pending += size
            return true
        }
        guard taken else { Stats.shared.bump("cam.dropped.backlog"); return }
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            defer { backlog.withLock { $0 -= size } }
            take(message, from: oid, arrived: arrived)
        }
    }

    // MARK: Inside, on `sill.camera`

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private func handle(_ event: CameraHostPolicy.Event) {
        apply(policy.handle(event, at: now))
    }

    private func take(_ message: StreamMessage, from oid: ObjectIdentifier, arrived: LockPolicy.Reading) {
        guard let id = ids[oid] else { Stats.shared.bump("cam.refused.unknown"); return }
        // Judged at the more restrictive of the reading as it arrived and the reading now (LockPolicy): what a
        // device sent while this Mac was locked never acts after the unlock.
        if case .refuse = LockPolicy.decide(.camera, arrived: arrived, now: gate.reading, paired: paired[id] ?? false) {
            apply(policy.lockedArrival(id, at: now))
            return
        }
        guard let m = CameraMessage.parse(message.payload) else { Stats.shared.bump("cam.dropped.malformed"); return }
        switch m {
        case .format(let f):
            if testLog, f.isEpoch { print("Test camera: epoch \(f.epoch ?? -1) from \(names[id] ?? "?"), \(f.width ?? 0)×\(f.height ?? 0) at \(f.fps ?? 0) fps") }
            handle(.format(id, f))
        case .frame(let frame):
            let r = policy.takesFrame(id, epoch: frame.epoch, at: now)
            apply(r.effects)
            guard r.take else { return }
            decode(frame, from: id, keyframe: message.isKeyframe, captured: message.timestamp)
        case .demand:
            Stats.shared.bump("cam.dropped.wrongWay")   // type 3 goes Mac → device only
        }
    }

    private func decode(_ frame: CameraFrame, from id: Int, keyframe: Bool, captured: Double) {
        guard let d = decoder, d.session == id, d.epoch == frame.epoch else { Stats.shared.bump("cam.dropped.noDecoder"); return }
        if awaitingKeyframe {
            guard keyframe else { Stats.shared.bump("cam.dropped.awaitingKeyframe"); return }
            awaitingKeyframe = false
        }
        let status = d.decode(frame.data, captured: captured) { [weak self, weak d] status, image in
            guard let self else { return }
            self.queue.async {
                guard let d, self.decoder === d else { return }
                self.decoded(d, status: status, image: image, captured: captured)
            }
        }
        if status != noErr { failed(d, status: status) }
    }

    private func decoded(_ d: CameraDecoder, status: OSStatus, image: CVPixelBuffer?, captured: Double) {
        guard status == noErr, let image else { failed(d, status: status); return }
        Stats.shared.bump("cam.decoded")
        decodedCount += 1
        if liveSaid.map({ $0.session != d.session || $0.epoch != d.epoch }) ?? true {
            liveSaid = (d.session, d.epoch)
            let mbps = d.format.bitrate.map { String(format: ", %.1f Mbps", Double($0) / 1_000_000) } ?? ""
            print("Camera: \(names[d.session] ?? "A device")'s camera is live: \(d.format.width ?? 0)×\(d.format.height ?? 0), \(d.format.fps ?? 0) fps, HEVC\(mbps).")
        }
        if testLog {
            let late = Int(((Date().timeIntervalSince1970 - captured) * 1000).rounded())
            print("Test camera: frame \(decodedCount) \(CVPixelBufferGetWidth(image))×\(CVPixelBufferGetHeight(image)), \(late) ms after its capture")
        }
        output.frame(image, captured: captured)
    }

    /// A frame that did not decode: later frames wait for a keyframe, which the policy asks for (once a
    /// second at most).
    private func failed(_ d: CameraDecoder, status: OSStatus) {
        Stats.shared.bump("cam.decodeFailed")
        awaitingKeyframe = true
        let effects = policy.handle(.decodeFailed(d.session), at: now)
        if effects.contains(where: { if case .demand = $0 { return true }; return false }) {
            print("Camera: a frame from \(names[d.session] ?? "a device") did not decode (\(status)); asked for a keyframe.")
        }
        apply(effects)
    }

    private func apply(_ effects: [CameraHostPolicy.Effect]) {
        var states: [ObjectIdentifier: CameraState?] = [:]
        for e in effects {
            switch e {
            case .state(let id, let s):
                if let c = connections[id] { states[ObjectIdentifier(c)] = s }
            case .demand(let id, let d):
                if let c = connections[id], let m = CameraMessage.message(.demand(d), now: Date().timeIntervalSince1970) { server.sendCamera(m, to: c) }
            case .decoder(let id, let f):
                decoder = nil
                awaitingKeyframe = true
                switch CameraDecoder.make(session: id, format: f, pixelFormat: output.pixelFormat, software: software) {
                case .success(let d):
                    decoder = d
                case .failure(let status):
                    Stats.shared.bump("cam.decoderFailed")
                    if decoderFailedSaid.map({ $0.session != id || $0.epoch != f.epoch }) ?? true {
                        decoderFailedSaid = (id, f.epoch ?? -1)
                        print("Camera: \(names[id] ?? "A device")'s format did not make a decoder (\(status)).")
                    }
                }
            case .noDecoder:
                decoder = nil
            case .feed(let f):
                output.feedChanged(f)
            case .line(let l):
                print(l)
            case .count(let k):
                Stats.shared.bump(k)
            }
        }
        if !states.isEmpty { onStates?(states) }
        let now = policy.switchOn && policy.ready ? CameraCodec.generation : 0
        if now != advertised {
            advertised = now
            onAdvertised?(now)
        }
    }
}

/// One epoch's VideoToolbox decoder: its parameter sets' format, a decompression session that makes the
/// output's pixel format (IOSurface-backed), hardware preferred, VideoToolbox's software decoder on a test
/// host. Never an encoder.
final class CameraDecoder: @unchecked Sendable {
    let session: Int
    let epoch: Int
    let format: CameraFormat
    private let vt: VTDecompressionSession
    private let description: CMVideoFormatDescription

    private init(session: Int, format: CameraFormat, vt: VTDecompressionSession, description: CMVideoFormatDescription) {
        self.session = session; self.epoch = format.epoch ?? -1; self.format = format; self.vt = vt; self.description = description
    }

    deinit { VTDecompressionSessionInvalidate(vt) }

    static func make(session: Int, format: CameraFormat, pixelFormat: OSType, software: Bool) -> Result<CameraDecoder, OSStatusError> {
        guard let encoded = format.parameterSets, let ps = ParameterSets(encoded: encoded), !ps.sets.isEmpty else { return .failure(OSStatusError(-1)) }
        let buffers = ps.sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, set.count))
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        var desc: CMVideoFormatDescription?
        var status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            allocator: nil, parameterSetCount: buffers.count, parameterSetPointers: buffers.map { UnsafePointer($0) },
            parameterSetSizes: ps.sets.map(\.count), nalUnitHeaderLength: Int32(ps.nalUnitHeaderLength),
            extensions: nil, formatDescriptionOut: &desc)
        guard status == noErr, let desc else { return .failure(OSStatusError(status)) }
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: pixelFormat,
                                           kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var spec: [CFString: Any] = [:]
        if software { spec[kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder] = false }
        var made: VTDecompressionSession?
        status = VTDecompressionSessionCreate(allocator: nil, formatDescription: desc, decoderSpecification: spec as CFDictionary,
                                              imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
                                              decompressionSessionOut: &made)
        guard status == noErr, let vt = made else { return .failure(OSStatusError(status)) }
        VTSessionSetProperty(vt, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        return .success(CameraDecoder(session: session, format: format, vt: vt, description: desc))
    }

    /// One access unit (4-byte lengths before each NAL unit, as VideoToolbox's encoder gives them); `done`
    /// on whatever thread VideoToolbox calls it. Returns the call's own status.
    func decode(_ data: Data, captured: Double, done: @escaping (OSStatus, CVPixelBuffer?) -> Void) -> OSStatus {
        let count = data.count
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count, blockAllocator: nil,
                                                        customBlockSource: nil, offsetToData: 0, dataLength: count, flags: 0,
                                                        blockBufferOut: &block)
        guard status == noErr, let block else { return status }
        status = CMBlockBufferAssureBlockMemory(block)
        guard status == noErr else { return status }
        status = data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard status == noErr else { return status }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: captured, preferredTimescale: 1_000_000),
                                        decodeTimeStamp: .invalid)
        var size = count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: description, sampleCount: 1,
                                           sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                           sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { return status }
        return VTDecompressionSessionDecodeFrame(vt, sampleBuffer: sample, flags: [._EnableAsynchronousDecompression], infoFlagsOut: nil) { s, flags, image, _, _ in
            done(s, flags.contains(.frameDropped) ? nil : image)
        }
    }
}

/// An OSStatus as an Error, for Result.
struct OSStatusError: Error, CustomStringConvertible {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
    var description: String { "\(status)" }
}

/// TEST ONLY (SILL_TEST_CAMERA, CameraTestHook): a test host's Sill Camera. It counts each frame, writes
/// every 30th as a PNG when asked (frames 1, 31, 61…), and plays the script of what its apps would do.
/// Never a window, never the main actor, never ImageIO on a device's bytes (only on its own decoded frames).
final class CameraTestOutput: CameraOutput, @unchecked Sendable {
    private let hook: CameraTestHook.Hook
    private var frames = 0
    private(set) var ready = true
    var onApp: ((CameraHostPolicy.AppUse?) -> Void)?
    var onReady: ((Bool) -> Void)?
    var pixelFormat: OSType { kCVPixelFormatType_32BGRA }

    init(hook: CameraTestHook.Hook) { self.hook = hook }

    func start() {
        let t0 = DispatchTime.now()
        for (at, step) in hook.script {
            DispatchQueue.global().asyncAfter(deadline: t0 + at) { [weak self] in
                guard let self else { return }
                switch step {
                case .on(let w, let h, let fps, let name):
                    print("Test camera: \(name) opens Sill Camera at \(w)×\(h), \(fps) fps.")
                    self.onApp?(CameraHostPolicy.AppUse(name: name, width: w, height: h, fps: fps))
                case .off:
                    print("Test camera: no app uses Sill Camera.")
                    self.onApp?(nil)
                case .notReady:
                    print("Test camera: Sill Camera not ready.")
                    self.onReady?(false)
                case .ready:
                    print("Test camera: Sill Camera ready.")
                    self.onReady?(true)
                }
            }
        }
    }

    func feedChanged(_ feed: CameraHostPolicy.Feed) {
        let words: String
        switch feed {
        case .unavailable: words = "nobody (unavailable)"
        case .waiting: words = "Turn on Share Camera…"
        case .device(let name, let pause): words = name + (pause.map { " (paused: \($0))" } ?? "")
        }
        print("Test camera: Sill Camera shows \(words).")
    }

    func frame(_ image: CVPixelBuffer, captured: Double) {
        frames += 1
        guard case .dump(let dir) = hook.output, (frames - 1) % 30 == 0 else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "frame-%05d.png", frames))
        if !Self.writePNG(image, to: url) { print("Test camera: could not write \(url.path).") }
    }

    /// A BGRA pixel buffer as a PNG.
    static func writePNG(_ image: CVPixelBuffer, to url: URL) -> Bool {
        guard CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA else { return false }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(image) else { return false }
        let w = CVPixelBufferGetWidth(image), h = CVPixelBufferGetHeight(image), row = CVPixelBufferGetBytesPerRow(image)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let context = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue),
              let cg = context.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest)
    }
}
