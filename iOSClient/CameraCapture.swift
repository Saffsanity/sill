import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import StreamProtocol

/// What gives the device's camera pictures to DeviceCamera (StreamClient+Camera): the camera itself
/// (`CameraCapture`), or DEBUG's moving pattern where there is none (`PatternSource`, the simulator). The seam
/// a test or a harness stands in at: nothing behind it opens a camera unless the person's switch, the Mac's
/// word and CameraPolicy all say so.
protocol CameraSource: AnyObject {
    /// Each picture, upright, with its capture time on the host clock (CMClockGetHostTimeClock), on the queue
    /// the source was made with.
    var onPicture: ((CVPixelBuffer, CMTime) -> Void)? { get set }
    /// What happened to the camera, on any queue.
    var onEvent: ((CameraCapture.Event) -> Void)? { get set }
    /// Runs at this rate with this camera, at about this size in the camera's own landscape terms; called again
    /// with other values, changes to them.
    func start(_ request: CameraCapture.Request)
    func stop()
}

/// The device's camera (docs/camera-plan.md §8): one AVCaptureSession on its own queue `sill.camera.session`, the
/// front wide camera (the back one by the row), the active format closest to the asked size and rate, pictures
/// in NV12 delivered on the media queue, upright (AVCaptureDevice.RotationCoordinator turns the output as the
/// device turns: a phone held upright gives tall pictures, which the Mac pillarboxes), never mirrored (the apps
/// on the Mac mirror their own self-view), late pictures discarded. It never configures the app's audio session
/// (`automaticallyConfiguresApplicationAudioSession` off: SharedSession owns it, the overview's §2.3), never asks
/// for multitasking camera access, and declares no background mode: iOS stops the camera in the background, in
/// Picture in Picture and, on an iPad, while another app shares the screen, and says so (`Event`), which
/// CameraPolicy turns into the pause the Mac hears.
final class CameraCapture: NSObject, CameraSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Request: Equatable {
        var position: String
        var width: Int
        var height: Int
        var fps: Int
    }

    /// Why iOS took the camera away (AVCaptureSession.InterruptionReason, as DeviceCamera reads it).
    enum Interruption: Equatable {
        /// Sill in the background (Picture in Picture too).
        case background
        /// Another app shares the iPad's screen (Split View, Slide Over, Stage Manager without an external display).
        case multitasking
        /// Another app or a call uses the camera.
        case busy
        /// The system's pressure (heat, power) stopped it.
        case pressure
    }

    enum Event: Equatable {
        /// The session runs (again), its pictures coming.
        case running
        /// iOS took the camera away, and why (nil: a reason this build does not know).
        case interrupted(Interruption?)
        case interruptionEnded
        /// The session stopped on an error; it starts again by itself when it can.
        case failed(String)
        /// The camera's system pressure (heat, power), as CameraPolicy reads it.
        case pressure(CameraPolicy.Pressure)
        /// No camera at the position asked for.
        case noCamera
    }

    var onPicture: ((CVPixelBuffer, CMTime) -> Void)?
    var onEvent: ((Event) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sill.camera.session", qos: .userInitiated)
    private let outputQueue: DispatchQueue
    private var request: Request?
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private let output = AVCaptureVideoDataOutput()
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private var notes: [NSObjectProtocol] = []

    /// `outputQueue`: where the pictures come (DeviceCamera's media queue).
    init(outputQueue: DispatchQueue) {
        self.outputQueue = outputQueue
        super.init()
        session.automaticallyConfiguresApplicationAudioSession = false
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: outputQueue)
        let center = NotificationCenter.default
        notes.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            self?.onEvent?(.interrupted(raw.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }.flatMap(Self.interruption)))
        })
        notes.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.onEvent?(.interruptionEnded)
        })
        notes.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self?.onEvent?(.failed(error.map { "\($0.code.rawValue)" } ?? "unknown"))
            // A media services reset (or another error) leaves the session stopped: it runs again if it still should.
            self?.sessionQueue.async { [weak self] in
                guard let self, self.request != nil, !self.session.isRunning else { return }
                self.session.startRunning()
            }
        })
        notes.append(center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: nil) { [weak self] _ in
            self?.onEvent?(.running)
        })
    }

    deinit {
        notes.forEach(NotificationCenter.default.removeObserver)
        observations.forEach { $0.invalidate() }
    }

    /// iOS's reasons, as CameraPolicy reads them.
    static func interruption(_ reason: AVCaptureSession.InterruptionReason) -> Interruption? {
        switch reason {
        case .videoDeviceNotAvailableInBackground: return .background
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return .multitasking
        case .videoDeviceInUseByAnotherClient, .audioDeviceInUseByAnotherClient: return .busy
        case .videoDeviceNotAvailableDueToSystemPressure: return .pressure
        default: return nil
        }
    }

    /// The camera at a position, and whether it has a format of this size (its own landscape terms) at this rate.
    static func camera(at position: String) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                position: CameraCodec.position(position) == CameraCodec.positionBack ? .back : .front)
    }

    static func supports(_ device: AVCaptureDevice?, width: Int, height: Int, fps: Int) -> Bool {
        guard let device else { return false }
        return device.formats.contains { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return Int(d.width) == width && Int(d.height) == height
                && f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(fps) && Double(fps) <= $0.maxFrameRate }
        }
    }

    func start(_ next: Request) {
        sessionQueue.async { [self] in
            guard next != request else {
                if !session.isRunning { session.startRunning() }
                return
            }
            let positionChanged = request?.position != next.position
            request = next
            session.beginConfiguration()
            if positionChanged || input == nil {
                if let input { session.removeInput(input) }
                input = nil
                observations.forEach { $0.invalidate() }
                observations = []
                rotation = nil
                guard let camera = Self.camera(at: next.position), let made = try? AVCaptureDeviceInput(device: camera),
                      session.canAddInput(made) else {
                    session.commitConfiguration()
                    request = nil
                    onEvent?(.noCamera)
                    return
                }
                session.addInput(made)
                input = made
                device = camera
                if session.outputs.isEmpty, session.canAddOutput(output) { session.addOutput(output) }
                observe(camera)
            }
            if let camera = device { configure(camera, for: next) }
            if let connection = output.connection(with: .video) {
                connection.automaticallyAdjustsVideoMirroring = false
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
                if let angle = rotation?.videoRotationAngleForHorizonLevelCapture, connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            request = nil
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            session.commitConfiguration()
            input = nil
            device = nil
            observations.forEach { $0.invalidate() }
            observations = []
            rotation = nil
        }
    }

    /// The active format: the asked size if the camera has it at the rate, else the smallest format at least as
    /// large that has the rate (CameraPolicy.format asks only for sizes `supports` said yes to, or 1280×720), NV12
    /// video range first, and the rate as its frame duration. On `sessionQueue`, inside a configuration.
    private func configure(_ camera: AVCaptureDevice, for r: Request) {
        let fits = camera.formats.filter { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return Int(d.width) >= r.width && Int(d.height) >= r.height
                && f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(r.fps) && Double(r.fps) <= $0.maxFrameRate }
        }
        let area = { (f: AVCaptureDevice.Format) -> Int in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return Int(d.width) * Int(d.height)
        }
        // NV12 video range first, as the output asks, then the smallest.
        let best = fits.min { a, b in
            let av = CMFormatDescriptionGetMediaSubType(a.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let bv = CMFormatDescriptionGetMediaSubType(b.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            return av != bv ? av : area(a) < area(b)
        }
        guard (try? camera.lockForConfiguration()) != nil else { return }
        if let best { camera.activeFormat = best }
        let duration = CMTime(value: 1, timescale: CMTimeScale(max(1, r.fps)))
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= Double(r.fps) && Double(r.fps) <= $0.maxFrameRate }) {
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
        }
        camera.unlockForConfiguration()
        // The pictures come at the active format's size (on iOS the output takes only a pixel format): the asked one
        // whenever the camera has it, which CameraPolicy.format makes sure of, falling back to 1280×720, which every
        // iPhone and iPad camera has.
    }

    /// The camera's pressure, and its rotation to keep the pictures upright as the device turns. On `sessionQueue`.
    private func observe(_ camera: AVCaptureDevice) {
        observations.append(camera.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] device, _ in
            self?.onEvent?(.pressure(Self.pressure(device.systemPressureState.level)))
        })
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotation = coordinator
        observations.append(coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] c, _ in
            let angle = c.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async { [weak self] in
                guard let connection = self?.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        })
    }

    static func pressure(_ level: AVCaptureDevice.SystemPressureState.Level) -> CameraPolicy.Pressure {
        switch level {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        case .shutdown: return .shutdown
        default: return .nominal
        }
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate, on the output queue

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onPicture?(image, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}

/// DEBUG `-SillCameraSource pattern`: CameraPattern's moving pattern instead of the camera, at the asked size and
/// rate, from a timer on the media queue. For the simulator, which has no camera; its encoder there is
/// VideoToolbox's software one (DeviceCamera), never the Mac's hardware encoder.
final class PatternSource: CameraSource {
    var onPicture: ((CVPixelBuffer, CMTime) -> Void)?
    var onEvent: ((CameraCapture.Event) -> Void)?
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var request: CameraCapture.Request?
    private var n = 0

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(_ r: CameraCapture.Request) {
        queue.async { [self] in
            guard r != request || timer == nil else { return }
            request = r
            timer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1 / Double(max(1, r.fps)), leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
            onEvent?(.running)
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            request = nil
        }
    }

    private func tick() {
        guard let r = request, let picture = CameraPattern.picture(n, width: r.width, height: r.height) else { return }
        n += 1
        onPicture?(picture, CMClockGetTime(CMClockGetHostTimeClock()))
    }
}
