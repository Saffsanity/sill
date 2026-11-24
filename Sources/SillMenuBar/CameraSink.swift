import AppKit
import AVFoundation
import CameraFeed
import CoreMedia
import CoreMediaIO
import CoreVideo
import SillHostCore
import VideoToolbox

/// Sill.app's feed into Sill Camera (docs/camera-plan.md §6.4, §7, §9): the CameraOutput the host's CameraReceiver
/// hands each decoded frame of the device that shares its camera. Through CoreMediaIO's C API it finds Sill Camera's
/// device by its fixed UID, starts the device's sink stream, writes what Sill Camera shows into its `state` property
/// before any frame (CameraSinkPolicy.state) and reads back its `demand` (which app uses it, at what size and rate),
/// fits each frame into that size, pillarboxed or letterboxed in black (VTPixelTransferSession, never an encoder), and
/// queues it, IOSurface-backed and stamped with this Mac's host clock as it goes in: two frames held in Sill Camera's
/// queue, the newest winning (CameraSinkPolicy.Slots).
///
/// Off while Use iPhone and iPad cameras is off: nothing of CoreMediaIO is touched then (no device lookup, no stream),
/// so Sill Camera, if installed, shows its own words for no feeder. A dry run in the bare SillMenuBar binary (previews,
/// gates): it says once what it would look for and never touches CoreMediaIO, so it is never ready.
///
/// Threading: everything runs on `queue`, `sill.camera`, which the receiver adopts as its own (CameraOutput.queue): the
/// receiver's calls, the frames, every CoreMediaIO call and listener, the queue-altered callback (hopped onto it).
/// `setEnabled` comes from the main actor and hops onto it; `onStatus` is called on it.
final class CameraSink: CameraOutput, @unchecked Sendable {
    let queue: DispatchQueue? = DispatchQueue(label: "sill.camera", qos: .userInitiated)
    private var q: DispatchQueue { queue! }
    private let dryRun: Bool

    // CameraOutput: set by the receiver before `start`, called on `queue`.
    var onApp: ((CameraAppUse?) -> Void)?
    var onReady: ((Bool) -> Void)?
    var pixelFormat: OSType { kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange }
    private(set) var ready = false

    /// The feed's status for Settings › Streaming, called on `queue` whenever it changes.
    var onStatus: ((CameraExtensionPolicy.Sink) -> Void)?

    // Everything below on `queue`.
    private var enabled = false
    private var status: CameraExtensionPolicy.Sink = .stopped
    private var show: CameraSinkPolicy.Feed = .unavailable
    private var connection: Connection?
    private var devicesListener: CMIOObjectPropertyListenerBlock?
    private var demandTimer: DispatchSourceTimer?
    private var lastDemand: String?
    private var use: CameraSinkPolicy.Use?
    private var slots = CameraSinkPolicy.Slots()
    private var pending: CVPixelBuffer?
    private var transfer: VTPixelTransferSession?
    private var pool: (CVPixelBufferPool, width: Int, height: Int)?
    private var saidDryRun = false
    private var saidProblem: String?

    /// Sill Camera's device, fixed in the extension (SillCameraDevice.deviceID), and its sink stream's name.
    static let deviceUID = "E839B629-E61D-49BE-A432-1A5D122456D0"
    static let sinkName = "\(CameraFeedPolicy.Copy.title) Input"

    init(dryRun: Bool) { self.dryRun = dryRun }

    // MARK: From the app

    /// Use iPhone and iPad cameras, as it is at launch and as the person turns it (main actor).
    func setEnabled(_ on: Bool) {
        q.async { [self] in
            guard on != enabled else { return }
            enabled = on
            if on { look() } else { stopFeeding(); stopLooking(); setStatus(.stopped) }
        }
    }

    // MARK: CameraOutput

    func start() {}

    func feedChanged(_ show: CameraShow) {
        switch show {
        case .unavailable: self.show = .unavailable
        case .waiting: self.show = .waiting
        case .device(let name, let pause): self.show = .device(name: name, pause: pause)
        }
        writeState()
    }

    func frame(_ image: CVPixelBuffer, captured: Double) {
        guard let c = connection, use != nil else { return }
        switch slots.arrive(count: Int(CMSimpleQueueGetCount(c.queue)), capacity: Int(CMSimpleQueueGetCapacity(c.queue)), at: Self.now) {
        case .enqueue:
            pending = nil
            enqueue(image, into: c)
        case .hold, .replace:
            pending = image
        }
    }

    // MARK: Looking for Sill Camera

    private func look() {
        guard enabled, connection == nil else { return }
        if dryRun {
            if !saidDryRun {
                saidDryRun = true
                print("Camera (dry run): Sill would look for Sill Camera's device \(Self.deviceUID) and feed it; this binary never touches CoreMediaIO.")
            }
            setStatus(.looking)
            return
        }
        if devicesListener == nil {
            var address = SinkCMIO.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.devicesChanged() }
            if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, q, listener) == noErr {
                devicesListener = listener
            }
        }
        guard let found = SinkCMIO.sillCamera(uid: Self.deviceUID, sinkName: Self.sinkName) else {
            setStatus(.looking)
            return
        }
        connect(device: found.device, sink: found.sink)
    }

    private func stopLooking() {
        guard let listener = devicesListener else { return }
        var address = SinkCMIO.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, q, listener)
        devicesListener = nil
    }

    /// The devices changed: Sill Camera came (look again) or went (its feed ends).
    private func devicesChanged() {
        guard enabled else { return }
        if let c = connection, !SinkCMIO.devices().contains(c.device) {
            print("Camera: Sill Camera went away; Sill feeds it again when it comes back.")
            stopFeeding()
            setStatus(.looking)
        }
        look()
    }

    // MARK: Feeding it

    private final class Connection {
        let device: CMIOObjectID
        let stream: CMIOStreamID
        let queue: CMSimpleQueue
        var demandListener: CMIOObjectPropertyListenerBlock?
        init(device: CMIOObjectID, stream: CMIOStreamID, queue: CMSimpleQueue) { self.device = device; self.stream = stream; self.queue = queue }
    }

    private func connect(device: CMIOObjectID, sink: CMIOStreamID) {
        var made: Unmanaged<CMSimpleQueue>?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var status = CMIOStreamCopyBufferQueue(sink, { _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<CameraSink>.fromOpaque(refcon).takeUnretainedValue()
            me.q.async { me.queueAltered() }
        }, refcon, &made)
        guard status == noErr, let bufferQueue = made?.takeRetainedValue() else {
            refused("Sill Camera's queue did not open (\(status))")
            return
        }
        status = CMIODeviceStartStream(device, sink)
        guard status == noErr else {
            // The callback unregistered; the queue that call copies again is released at once.
            made = nil
            CMIOStreamCopyBufferQueue(sink, nil, nil, &made)
            made?.release()
            // Starting a camera's stream may need Sill's own camera access (docs/camera-plan.md §17, V2): read, never asked.
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied || AVCaptureDevice.authorizationStatus(for: .video) == .restricted {
                say("Camera: Sill Camera's feed did not start: macOS denies Sill access to cameras (\(status)).")
                setStatus(.cameraDenied)
            } else {
                refused("Sill Camera's feed did not start (\(status))")
            }
            return
        }
        let c = Connection(device: device, stream: sink, queue: bufferQueue)
        connection = c
        saidProblem = nil
        print("Camera: feeding Sill Camera (its queue holds \(CMSimpleQueueGetCapacity(bufferQueue)) frames).")
        // What it shows first, before any frame: a frame counts only while the state says a device is live.
        writeState()
        watchDemand(c)
        ready = true
        onReady?(true)
        setStatus(.feeding)
    }

    private func refused(_ why: String) {
        say("Camera: \(why).")
        setStatus(.refused)
    }

    private func stopFeeding() {
        guard let c = connection else { return }
        if let l = c.demandListener {
            var address = SinkCMIO.address(SinkCMIO.demandSelector)
            CMIOObjectRemovePropertyListenerBlock(c.device, &address, q, l)
        }
        demandTimer?.cancel(); demandTimer = nil
        CMIODeviceStopStream(c.device, c.stream)
        var none: Unmanaged<CMSimpleQueue>?
        CMIOStreamCopyBufferQueue(c.stream, nil, nil, &none)
        none?.release()
        connection = nil
        slots.clear(); pending = nil
        lastDemand = nil
        if use != nil { use = nil; onApp?(nil) }
        if ready { ready = false; onReady?(false) }
        print("Camera: Sill no longer feeds Sill Camera.")
    }

    // MARK: What it shows, and what apps do with it

    private func writeState() {
        guard let c = connection else { return }
        let status = SinkCMIO.setString(CameraSinkPolicy.state(show), on: c.device, selector: SinkCMIO.stateSelector)
        if status != noErr { say("Camera: Sill Camera did not take what to show (\(status)).") }
    }

    /// The demand: on every change Sill Camera announces, and read once a second besides (a change notice is
    /// CoreMediaIO's to deliver; a missed one costs a second at most).
    private func watchDemand(_ c: Connection) {
        var address = SinkCMIO.address(SinkCMIO.demandSelector)
        let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.readDemand() }
        if CMIOObjectAddPropertyListenerBlock(c.device, &address, q, listener) == noErr { c.demandListener = listener }
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.readDemand() }
        t.resume()
        demandTimer = t
        readDemand()
    }

    private func readDemand() {
        guard let c = connection else { return }
        let text = SinkCMIO.string(c.device, selector: SinkCMIO.demandSelector)
        guard text != lastDemand else { return }
        lastDemand = text
        let next = CameraSinkPolicy.use(text) { pid in NSRunningApplication(processIdentifier: pid)?.localizedName }
        guard next != use else { return }
        if next?.width != use?.width || next?.height != use?.height { slots.clear(); pending = nil }
        use = next
        onApp?(next.map { CameraAppUse(name: $0.name, width: $0.width, height: $0.height, fps: $0.fps) })
    }

    // MARK: The frames

    /// Sill Camera took a frame from its queue: the one waiting goes in, if it still may.
    private func queueAltered() {
        guard let c = connection else { return }
        if slots.freed(count: Int(CMSimpleQueueGetCount(c.queue)), capacity: Int(CMSimpleQueueGetCapacity(c.queue)), at: Self.now),
           let image = pending {
            pending = nil
            enqueue(image, into: c)
        } else if slots.pendingSince == nil {
            pending = nil
        }
    }

    /// Fits `image` into the size the app chose, black around it, into a buffer of Sill's own pool (IOSurface-backed,
    /// so Sill Camera reads it in its own process without a copy), stamps it with this Mac's host clock and queues it.
    private func enqueue(_ image: CVPixelBuffer, into c: Connection) {
        guard let use, let fitted = fit(image, width: use.width, height: use.height) else { return }
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: fitted,
                                                            formatDescriptionOut: &description) == noErr, let description else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(max(1, use.fps))),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: fitted, dataReady: true,
                                                 makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
                                                 sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        // The queue takes a reference of its own, which Sill Camera's side gives back.
        let element = Unmanaged.passRetained(sample).toOpaque()
        if CMSimpleQueueEnqueue(c.queue, element: element) != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(element).release()
        }
    }

    private func fit(_ image: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        if transfer == nil {
            var made: VTPixelTransferSession?
            guard VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &made) == noErr, let made else { return nil }
            VTSessionSetProperty(made, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Letterbox)
            transfer = made
        }
        if pool.map({ $0.width != width || $0.height != height }) ?? true {
            let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: pixelFormat, kCVPixelBufferWidthKey: width,
                                               kCVPixelBufferHeightKey: height, kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            var made: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &made) == kCVReturnSuccess, let made else { return nil }
            pool = (made, width, height)
        }
        guard let transfer, let pool else { return nil }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool.0, &out) == kCVReturnSuccess, let out,
              VTPixelTransferSessionTransferImage(transfer, from: image, to: out) == noErr else { return nil }
        return out
    }

    // MARK: Small things

    private func setStatus(_ s: CameraExtensionPolicy.Sink) {
        guard s != status else { return }
        status = s
        onStatus?(s)
    }

    /// A problem's line, once until the feed starts again.
    private func say(_ line: String) {
        guard line != saidProblem else { return }
        saidProblem = line
        print(line)
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }
}

/// The few CoreMediaIO C calls the sink makes, by property address.
private enum SinkCMIO {
    /// Sill Camera's custom properties (SillCameraProvider: "4cc_SilS_glob_0000", "4cc_SilD_glob_0000").
    static let stateSelector = fourCC("SilS")
    static let demandSelector = fourCC("SilD")

    static func fourCC(_ s: String) -> CMIOObjectPropertySelector {
        s.utf8.reduce(0) { ($0 << 8) | CMIOObjectPropertySelector($1) }
    }

    static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func ids(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> [CMIOObjectID] {
        var a = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &a, 0, nil, size, &used, &list) == noErr else { return [] }
        return Array(list.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func devices() -> [CMIOObjectID] {
        ids(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    }

    /// A CFString property (a copy: released here).
    static func string(_ object: CMIOObjectID, selector: CMIOObjectPropertySelector) -> String? {
        var a = address(selector)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &value) { p in
            CMIOObjectGetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, p)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func setString(_ text: String, on object: CMIOObjectID, selector: CMIOObjectPropertySelector) -> OSStatus {
        var a = address(selector)
        var value = text as CFString
        return withUnsafePointer(to: &value) { p in
            CMIOObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<CFString>.size), p)
        }
    }

    static func uint32(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> UInt32? {
        var a = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr else { return nil }
        return value
    }

    /// Sill Camera's device and its sink stream: the device by its UID; its stream named as the extension names the
    /// sink, else the one a client feeds (an output stream, direction 0: CMIOHardwareStream.h), else the second of two.
    static func sillCamera(uid: String, sinkName: String) -> (device: CMIOObjectID, sink: CMIOStreamID)? {
        guard let device = devices().first(where: { string($0, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID)) == uid }) else { return nil }
        let streams = ids(device, CMIOObjectPropertySelector(kCMIODevicePropertyStreams))
        if let s = streams.first(where: { string($0, selector: CMIOObjectPropertySelector(kCMIOObjectPropertyName)) == sinkName }) { return (device, s) }
        if let s = streams.first(where: { uint32($0, CMIOObjectPropertySelector(kCMIOStreamPropertyDirection)) == 0 }) { return (device, s) }
        return streams.count == 2 ? (device, streams[1]) : nil
    }
}
