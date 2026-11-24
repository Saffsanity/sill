#if os(macOS)
import CameraFeed
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import IOKit.audio
import os
import Security

/// Sill Camera, the Core Media I/O camera extension (docs/camera-plan.md §6.4, §7, §9): one device, "Sill Camera",
/// with a source stream that apps such as FaceTime, Zoom or a browser choose as a camera, and a sink stream that only
/// Sill for Mac feeds with the decoded frames of the device that shares its camera. CameraFeedPolicy decides
/// everything; this file carries it out with CoreMediaIO's extension API.
///
/// Threading: one serial queue, `sill.camera.feed`, is the provider's client queue (CoreMediaIO calls every source
/// method on it), and runs the feed's timer and the sink's consumption; the policy and every member below are
/// touched only on it. The sink's completion handlers hop onto it.
///
/// Never run by a test: it runs only once Sill for Mac activated it from /Applications and an administrator allowed
/// it (docs/camera-plan.md §13.5, N1). Scripts/camera-check/package.sh only builds and checks the bundle.
final class SillCameraProvider: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var device: SillCameraDevice!

    init(queue: DispatchQueue) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: queue)
        device = SillCameraDevice(queue: queue)
        do {
            try provider.addDevice(device.device)
        } catch {
            Log.feed.fault("Sill Camera: could not add its device: \(error.localizedDescription, privacy: .public)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {
        device.clientLeft(client)
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer, .providerName] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let p = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { p.manufacturer = "Sill" }
        if properties.contains(.providerName) { p.name = CameraFeedPolicy.Copy.title }
        return p
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

enum Log {
    static let feed = Logger(subsystem: "me.saffer.sill.mac.camera", category: "feed")
}

/// The two custom properties Sill for Mac uses (docs/camera-plan.md §7): `state`, written by it (what to show while no
/// frame is live; never read back, so no other process learns a device's name from it), and `demand`, read by it
/// (whether an app runs Sill Camera, its size and rate, the apps). CoreMediaIO's custom property keys:
/// "4cc_<selector>_<scope>_<element>", read from the device object as CFStrings by the CoreMediaIO C API.
extension CMIOExtensionProperty {
    static let sillState = CMIOExtensionProperty(rawValue: "4cc_SilS_glob_0000")
    static let sillDemand = CMIOExtensionProperty(rawValue: "4cc_SilD_glob_0000")
}

final class SillCameraDevice: NSObject, CMIOExtensionDeviceSource {
    /// Fixed, so apps find "Sill Camera" again after every launch and update.
    static let deviceID = UUID(uuidString: "E839B629-E61D-49BE-A432-1A5D122456D0")!
    static let sourceID = UUID(uuidString: "B0AB6BFC-2693-4A63-A8EA-2A47AEAE8832")!
    static let sinkID = UUID(uuidString: "8275CE4C-882E-4886-A391-121AAF8045D3")!

    private(set) var device: CMIOExtensionDevice!
    private var source: SillCameraStream!
    private var sink: SillCameraStream!
    private let queue: DispatchQueue
    private var policy = CameraFeedPolicy()
    private var timer: DispatchSourceTimer?
    /// The newest frame taken from the sink, and the placeholder for the words and size it says now.
    private var newest: CVPixelBuffer?
    private var placeholder: (CameraFeedPolicy.Placeholder, CVPixelBuffer)?
    private var descriptions: [String: CMFormatDescription] = [:]
    /// The feeder's client (Sill for Mac), whose frames the sink takes while `consuming`.
    private var feederClient: CMIOExtensionClient?
    private var consuming = false
    private var lastDemand = ""
    private var appsCheckedAt: Double = 0

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        device = CMIOExtensionDevice(localizedName: CameraFeedPolicy.Copy.title, deviceID: Self.deviceID,
                                     legacyDeviceID: nil, source: self)
        source = SillCameraStream(name: CameraFeedPolicy.Copy.title, id: Self.sourceID, direction: .source, owner: self)
        sink = SillCameraStream(name: "\(CameraFeedPolicy.Copy.title) Input", id: Self.sinkID, direction: .sink, owner: self)
        do {
            try device.addStream(source.stream)
            try device.addStream(sink.stream)
        } catch {
            Log.feed.fault("Sill Camera: could not add its streams: \(error.localizedDescription, privacy: .public)")
        }
        lastDemand = CameraFeedPolicy.encode(policy.demand)
    }

    // MARK: The device's properties

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel, .sillState, .sillDemand] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let p = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { p.transportType = Int(kIOAudioDeviceTransportTypeVirtual) }
        if properties.contains(.deviceModel) { p.model = CameraFeedPolicy.Copy.title }
        if properties.contains(.sillState) {
            let writable = CMIOExtensionPropertyAttributes<AnyObject>(minValue: nil, maxValue: nil, validValues: nil, readOnly: false)
            p.setPropertyState(CMIOExtensionPropertyState(value: "" as NSString, attributes: writable), forProperty: .sillState)
        }
        if properties.contains(.sillDemand) {
            p.setPropertyState(CMIOExtensionPropertyState(value: CameraFeedPolicy.encode(policy.demand) as NSString,
                                                          attributes: .readOnlyPropertyAttribute),
                               forProperty: .sillDemand)
        }
        return p
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        guard let state = deviceProperties.propertiesDictionary[.sillState]?.value as? String else { return }
        if !policy.stateWritten(state) {
            Log.feed.info("Sill Camera: a state was refused (nothing feeds it, or it does not read)")
        }
        if policy.frameAt == nil { newest = nil }
        tickNow()
    }

    // MARK: Streams

    func formatIndex(of stream: SillCameraStream) -> Int { policy.formatIndex }
    var fps: Int { policy.fps }

    func formatChosen(_ index: Int, by stream: SillCameraStream) {
        guard stream === source else { return }
        if !policy.formatChosen(index) {
            Log.feed.error("Sill Camera: no format \(index, privacy: .public)")
        }
        newest = nil
        publishDemand()
    }

    func frameDurationChosen(_ seconds: Double, by stream: SillCameraStream) {
        guard stream === source else { return }
        policy.frameDurationChosen(seconds: seconds)
        publishDemand()
    }

    /// Whether a client may start a stream: any app the source (macOS asks the person for camera access as for any
    /// camera), only Sill for Mac the sink.
    func authorized(_ client: CMIOExtensionClient, for stream: SillCameraStream) -> Bool {
        guard stream === sink else { return true }
        let valid = Self.signatureValid(pid: client.pid)
        let verdict = policy.sinkStart(client: client.clientID, signingID: client.signingID, signatureValid: valid)
        switch verdict {
        case .accept:
            feederClient = client
            if valid == nil {
                Log.feed.notice("Sill Camera: fed by Sill (pid \(client.pid, privacy: .public)), its signature not checked here")
            } else {
                Log.feed.notice("Sill Camera: fed by Sill (pid \(client.pid, privacy: .public))")
            }
            return true
        default:
            Log.feed.error("Sill Camera: refused a feed from \(client.signingID ?? "an unsigned process", privacy: .public) (pid \(client.pid, privacy: .public)): \(String(describing: verdict), privacy: .public)")
            return false
        }
    }

    func started(_ stream: SillCameraStream) {
        if stream === source {
            policy.sourceStarted()
            refreshApps(force: true)
            if timer == nil { startTimer() }
        } else if let client = feederClient, policy.feeder == client.clientID {
            consuming = true
            consume(from: client)
        }
    }

    func stopped(_ stream: SillCameraStream) {
        if stream === source {
            policy.sourceStopped()
            if !policy.running {
                timer?.cancel()
                timer = nil
            }
            publishDemand()
        } else if let client = feederClient {
            consuming = false
            policy.sinkStop(client: client.clientID)
            feederClient = nil
            newest = nil
            Log.feed.notice("Sill Camera: Sill stopped feeding it")
        }
    }

    func clientLeft(_ client: CMIOExtensionClient) {
        if feederClient?.clientID == client.clientID {
            consuming = false
            feederClient = nil
            newest = nil
            Log.feed.notice("Sill Camera: Sill left")
        }
        policy.clientLeft(client.clientID, pid: client.pid)
        publishDemand()
    }

    // MARK: The sink

    /// Takes the feeder's frames as they come. CoreMediaIO's completion brings the next frame, or nothing; on
    /// nothing, the next try waits 5 ms, so an empty queue costs no busy loop.
    private func consume(from client: CMIOExtensionClient) {
        guard consuming, feederClient?.clientID == client.clientID else { return }
        sink.stream.consumeSampleBuffer(from: client) { [weak self] buffer, sequence, _, more, _ in
            guard let self else { return }
            self.queue.async {
                guard self.consuming, self.feederClient?.clientID == client.clientID else { return }
                guard let buffer else {
                    self.queue.asyncAfter(deadline: .now() + .milliseconds(5)) { self.consume(from: client) }
                    return
                }
                let now = Self.hostSeconds()
                self.sink.stream.notifyScheduledOutputChanged(
                    CMIOExtensionScheduledOutput(sequenceNumber: sequence, hostTimeInNanoseconds: UInt64(now * 1e9)))
                self.take(buffer, from: client, more: more, at: now)
                self.consume(from: client)
            }
        }
    }

    private func take(_ buffer: CMSampleBuffer, from client: CMIOExtensionClient, more: Bool, at now: Double) {
        guard let image = CMSampleBufferGetImageBuffer(buffer) else { return }
        let verdict = policy.frame(from: client.clientID, width: CVPixelBufferGetWidth(image),
                                   height: CVPixelBufferGetHeight(image),
                                   pixelFormat: CVPixelBufferGetPixelFormatType(image), more: more, at: now)
        switch verdict {
        case .send:
            newest = image
            send(image, at: now)
        case .kept:
            newest = image
        case .notFeeder, .notLive, .wrongSize, .wrongFormat:
            break
        }
    }

    // MARK: The source

    private func startTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: CameraFeedPolicy.tickInterval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tickNow() }
        t.resume()
        timer = t
    }

    private func tickNow() {
        let now = Self.hostSeconds()
        if now - appsCheckedAt >= 1 { refreshApps(force: false) }
        switch policy.tick(at: now) {
        case .frame?:
            if let image = newest { send(image, at: now) }
        case .placeholder(let p)?:
            if placeholder?.0 != p, let image = Placeholder.draw(p) { placeholder = (p, image) }
            if let image = placeholder?.1 { send(image, at: now) }
        case nil:
            break
        }
    }

    /// The apps that run the source stream, from CoreMediaIO's streaming clients, at most once a second.
    private func refreshApps(force: Bool) {
        appsCheckedAt = Self.hostSeconds()
        let apps = source.stream.streamingClients.map { CameraFeedPolicy.App(id: $0.signingID, pid: $0.pid) }
        if policy.appsNow(apps) || force { publishDemand() }
    }

    private func publishDemand() {
        let text = CameraFeedPolicy.encode(policy.demand)
        guard text != lastDemand else { return }
        lastDemand = text
        device.notifyPropertiesChanged([.sillDemand: CMIOExtensionPropertyState<AnyObject>(value: text as NSString)])
    }

    /// One picture out to every app that runs the source stream, stamped with this Mac's host clock now.
    private func send(_ image: CVPixelBuffer, at now: Double) {
        let key = "\(CVPixelBufferGetWidth(image))x\(CVPixelBufferGetHeight(image))-\(CVPixelBufferGetPixelFormatType(image))"
        var description = descriptions[key]
        if description == nil {
            var made: CMFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
                                                         formatDescriptionOut: &made)
            description = made
            if let made { descriptions[key] = made }
        }
        guard let description else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(policy.fps)),
                                        presentationTimeStamp: CMTime(seconds: now, preferredTimescale: 1_000_000_000),
                                        decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, dataReady: true,
                                                        makeDataReadyCallback: nil, refcon: nil,
                                                        formatDescription: description, sampleTiming: &timing,
                                                        sampleBufferOut: &buffer)
        guard status == noErr, let buffer else { return }
        source.stream.send(buffer, discontinuity: [], hostTimeInNanoseconds: UInt64(now * 1e9))
    }

    // MARK: Time and signatures

    /// This Mac's host clock, the one CoreMediaIO's streams run on, in seconds.
    static func hostSeconds() -> Double {
        CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    }

    /// Whether the process `pid` is Sill for Mac signed by this extension's own team: nil when that cannot be
    /// told here (this extension is not signed by a team, as a development build, or its sandbox refuses the look
    /// at another process: docs/camera-plan.md §17, V6). A pid can be reused; CoreMediaIO gives no audit token.
    static func signatureValid(pid: pid_t) -> Bool? {
        guard let team = ownTeam() else { return nil }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return nil }
        let text = "identifier \"\(CameraFeedPolicy.sillIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else {
            return nil
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func ownTeam() -> String? {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(me, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        return team?.isEmpty == false ? team : nil
    }
}

/// One of Sill Camera's two streams: the source apps read, or the sink Sill for Mac feeds. Both offer the same
/// formats; the device decides.
final class SillCameraStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private unowned let owner: SillCameraDevice
    let direction: CMIOExtensionStream.Direction
    private let streamFormats: [CMIOExtensionStreamFormat]

    init(name: String, id: UUID, direction: CMIOExtensionStream.Direction, owner: SillCameraDevice) {
        self.owner = owner
        self.direction = direction
        self.streamFormats = CameraFeedPolicy.formats.compactMap { f in
            var description: CMFormatDescription?
            CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: CameraFeedPolicy.pixelFormat,
                                           width: Int32(f.width), height: Int32(f.height), extensions: nil,
                                           formatDescriptionOut: &description)
            guard let description else { return nil }
            return CMIOExtensionStreamFormat(formatDescription: description,
                                             maxFrameDuration: CMTime(value: 1, timescale: CMTimeScale(CameraFeedPolicy.fpsRange.lowerBound)),
                                             minFrameDuration: CMTime(value: 1, timescale: CMTimeScale(CameraFeedPolicy.fpsRange.upperBound)),
                                             validFrameDurations: nil)
        }
        super.init()
        stream = CMIOExtensionStream(localizedName: name, streamID: id, direction: direction, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { streamFormats }

    var availableProperties: Set<CMIOExtensionProperty> {
        var p: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if direction == .sink {
            p.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount,
                         .streamSinkEndOfData])
        }
        return p
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { p.activeFormatIndex = owner.formatIndex(of: self) }
        if properties.contains(.streamFrameDuration) {
            p.frameDuration = CMTime(value: 1, timescale: CMTimeScale(owner.fps))
        }
        if direction == .sink {
            if properties.contains(.streamSinkBufferQueueSize) { p.sinkBufferQueueSize = CameraFeedPolicy.sinkQueueSize }
            if properties.contains(.streamSinkBuffersRequiredForStartup) { p.sinkBuffersRequiredForStartup = 1 }
            if properties.contains(.streamSinkBufferUnderrunCount) { p.sinkBufferUnderrunCount = 0 }
            if properties.contains(.streamSinkEndOfData) { p.sinkEndOfData = 0 }
        }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex { owner.formatChosen(index, by: self) }
        if let duration = streamProperties.frameDuration { owner.frameDurationChosen(CMTimeGetSeconds(duration), by: self) }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        owner.authorized(client, for: self)
    }

    func startStream() throws { owner.started(self) }

    func stopStream() throws { owner.stopped(self) }
}
#endif
