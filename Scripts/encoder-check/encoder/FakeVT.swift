// A stand-in for the VideoToolbox calls HEVCEncoder.swift makes, and for the two names it takes
// from StreamProtocol and SillHostCore (ParameterSets, Stats). run.sh compiles a copy of the real
// Sources/SillHost/HEVCEncoder.swift with its `import VideoToolbox` and `import StreamProtocol`
// lines removed against these, with the real EncoderMailbox.swift and EncoderProbe.swift, so the
// binary links no VideoToolbox and cannot open an encoder session (run.sh checks with otool). No
// NSLock here (os_unfair_lock only): a check that times the encoder's own NSLock sees only its.
import Foundation
import CoreMedia
import CoreVideo
import QuartzCore

final class UnfairLock {
    private let p: UnsafeMutablePointer<os_unfair_lock>
    init() { p = .allocate(capacity: 1); p.initialize(to: os_unfair_lock()) }
    func lock() { os_unfair_lock_lock(p) }
    func unlock() { os_unfair_lock_unlock(p) }
    func run<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}

// MARK: - Frames whose content and lifetime the check can see

/// Every frame carries one as an attachment: its number (a higher number is newer content), and
/// `alive` counts the frames not yet destroyed, as the pixel buffer lets go of its attachments.
final class Tracker {
    private static let lock = UnfairLock()
    private static var live: Set<Int> = []
    static var alive: [Int] { lock.run { live.sorted() } }
    let seq: Int
    init(seq: Int) { self.seq = seq; Self.lock.run { _ = Self.live.insert(seq) } }
    deinit { let s = seq; Self.lock.run { _ = Self.live.remove(s) } }
}
let trackerKey = "sill.encoder-check.tracker" as CFString

func makeFrame(seq: Int, width: Int = 16, height: Int = 16) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CoreVideo.CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &pb)
    CVBufferSetAttachment(pb!, trackerKey, Tracker(seq: seq), .shouldNotPropagate)
    return pb!
}
func seqOf(_ b: CVBuffer) -> Int {
    guard let v = CVBufferCopyAttachment(b, trackerKey, nil) else { return -1 }
    return (v as? Tracker)?.seq ?? -1
}

/// EncoderProbe's own test frames: CoreVideo's CVPixelBufferCreate (shadowed for this module), with
/// a tracker numbered from 1_000_001. `probeSeqNow`: the last number given out.
private let probeSeqLock = UnfairLock()
private var probeSeq = 1_000_000
var probeSeqNow: Int { probeSeqLock.run { probeSeq } }
@discardableResult
func CVPixelBufferCreate(_ allocator: CFAllocator?, _ width: Int, _ height: Int, _ format: OSType, _ attrs: CFDictionary?,
                         _ out: UnsafeMutablePointer<CVPixelBuffer?>) -> CVReturn {
    let r = CoreVideo.CVPixelBufferCreate(allocator, width, height, format, attrs, out)
    if r == kCVReturnSuccess, let b = out.pointee {
        let s = probeSeqLock.run { probeSeq += 1; return probeSeq }
        CVBufferSetAttachment(b, trackerKey, Tracker(seq: s), .shouldNotPropagate)
    }
    return r
}

// MARK: - The stand-in session

/// What the stand-in does with one encode call.
enum Behavior {
    /// Accepted; its output comes this long after the call (on a serial engine, this long after the
    /// frame before it is done), never before an earlier frame's (decode order).
    case returnAfter(Double)
    /// Accepted and never comes out; in decode order nothing after it comes out either. The session
    /// keeps the frames it holds, as VideoToolbox keeps a frame's surface until its output.
    case stuck
    /// The encode call itself never returns (2026-09-22's `sample`: the thread inside
    /// VTCompressionSessionEncodeFrameWithOutputHandler → RemoteVideoEncoder).
    case blockCall
    /// The encode call blocks this long, then refuses the frame: an error status, no output.
    case refuse(after: Double)
}

struct Call {
    let session: Int
    let n: Int              // 1 for the session's first encode call
    let seq: Int            // the frame's content
    let pts: CMTime
    let forced: Bool
    let at: CFTimeInterval
    var refused = false
}
struct Output { let session: Int; let n: Int; let at: CFTimeInterval }

enum FakeVT {
    static let lock = UnfairLock()
    /// How each call behaves, by session number (1 for the first session made), call number and the
    /// frame's content number.
    static var plan: (_ session: Int, _ call: Int, _ seq: Int, _ software: Bool) -> Behavior = { _, _, _, _ in .returnAfter(0.009) }
    /// One engine: a frame's time starts when the frame before it is done. Else each frame's time
    /// starts at its call and they overlap.
    static var serialEngine = false
    static var calls: [Call] = []
    static var outputs: [Output] = []
    /// The most frames each session held at once, by session number.
    static var maxHeld: [Int: Int] = [:]
    /// Sessions invalidated: when, and how many frames each still held then.
    static var invalidated: [Int: (at: CFTimeInterval, held: Int)] = [:]
    /// How long VTCompressionSessionCreate takes (a new session for the slow state is made off every
    /// queue of the encoder's, so this delays only its taking over).
    static var createDelay: Double = 0
    /// Called on a session's callback queue just before and just after it runs an output handler,
    /// with the session's number (the delivery-order case of E7 holds a handler with `Inject`).
    static var beforeHandler: ((Int) -> Void)?
    static var afterHandler: ((Int) -> Void)?
    private static var sessionCount = 0

    static func reset(plan p: @escaping (_ session: Int, _ call: Int, _ seq: Int, _ software: Bool) -> Behavior = { _, _, _, _ in .returnAfter(0.009) },
                      serial: Bool = false) {
        lock.run {
            plan = p; serialEngine = serial; calls = []; outputs = []; maxHeld = [:]; invalidated = [:]; createDelay = 0
            beforeHandler = nil; afterHandler = nil
        }
    }
    static func newSession() -> Int { lock.run { sessionCount += 1; return sessionCount } }
    /// The session and call an encoded frame (`onEncoded`'s data) came from.
    static func origin(_ data: Data) -> (session: Int, call: Int)? {
        guard data.count == 8 else { return nil }
        let v = data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
        return (Int(v / 1_000_000), Int(v % 1_000_000))
    }
    static var lastSession: Int { lock.run { sessionCount } }
    static func callsOf(_ session: Int) -> [Call] { lock.run { calls.filter { $0.session == session } } }
    static func outputsOf(_ session: Int) -> [Output] { lock.run { outputs.filter { $0.session == session } } }
}

final class VTCompressionSession {
    let index: Int
    let software: Bool
    private let lock = UnfairLock()
    private var callCount = 0
    /// Frames accepted and not out yet, by call number: the surfaces this "encoder" holds.
    private var held: [Int: CVPixelBuffer] = [:]
    private var lastDue: CFTimeInterval = 0
    private var engineFree: CFTimeInterval = 0
    private var invalid = false
    /// Outputs one after another, in the order the frames went in, as VideoToolbox's.
    private let callbacks: DispatchQueue
    private let never = DispatchSemaphore(value: 0)

    init(software: Bool) {
        self.software = software
        index = FakeVT.newSession()
        callbacks = DispatchQueue(label: "fakevt.callback.\(index)", qos: .userInteractive)
    }

    func encode(_ pb: CVPixelBuffer, pts: CMTime, props: CFDictionary?, handler: @escaping VTCompressionOutputHandler) -> OSStatus {
        let forced = ((props as NSDictionary?)?[kVTEncodeFrameOptionKey_ForceKeyFrame as String] as? Bool) ?? false
        let seq = seqOf(pb)
        let now = CACurrentMediaTime()
        let (n, invalidNow) = lock.run { () -> (Int, Bool) in callCount += 1; return (callCount, invalid) }
        if invalidNow { return -12903 }
        let behavior = FakeVT.lock.run { FakeVT.plan(index, n, seq, software) }
        var call = Call(session: index, n: n, seq: seq, pts: pts, forced: forced, at: now)
        switch behavior {
        case .refuse(let after):
            if after > 0 { Thread.sleep(forTimeInterval: after) }
            call.refused = true
            FakeVT.lock.run { FakeVT.calls.append(call) }
            return -12902
        case .blockCall:
            FakeVT.lock.run { FakeVT.calls.append(call) }
            withExtendedLifetime(pb) { never.wait() }   // never returns: this thread holds the frame for good
            return noErr
        case .stuck:
            FakeVT.lock.run { FakeVT.calls.append(call) }
            let count = lock.run { () -> Int in held[n] = pb; return held.count }
            FakeVT.lock.run { FakeVT.maxHeld[index] = max(FakeVT.maxHeld[index] ?? 0, count) }
            callbacks.async { [never] in never.wait() }   // decode order: nothing after it comes out
            return noErr
        case .returnAfter(let d):
            let serial = FakeVT.lock.run { () -> Bool in
                FakeVT.calls.append(call)
                return FakeVT.serialEngine
            }
            let key = forced || n == 1
            let (due, count) = lock.run { () -> (CFTimeInterval, Int) in
                held[n] = pb
                var due = now + d
                if serial { due = max(now, engineFree) + d; engineFree = due }
                due = max(due, lastDue)
                lastDue = due
                return (due, held.count)
            }
            FakeVT.lock.run { FakeVT.maxHeld[index] = max(FakeVT.maxHeld[index] ?? 0, count) }
            let session = index
            callbacks.async { [self] in
                let wait = due - CACurrentMediaTime()
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                lock.run { _ = held.removeValue(forKey: n) }
                let (before, after) = FakeVT.lock.run { () -> (((Int) -> Void)?, ((Int) -> Void)?) in
                    FakeVT.outputs.append(Output(session: session, n: n, at: CACurrentMediaTime()))
                    return (FakeVT.beforeHandler, FakeVT.afterHandler)
                }
                before?(session)
                handler(noErr, [], Self.sample(session: session, call: n, pts: pts, key: key))
                after?(session)
            }
            return noErr
        }
    }

    /// Waits until every frame inside came out (never, behind a stuck one).
    func completeFrames() { callbacks.sync {} }

    func invalidate() {
        callbacks.sync {}
        let count = lock.run { () -> Int in let n = held.count; invalid = true; held.removeAll(); return n }
        FakeVT.lock.run { FakeVT.invalidated[index] = (CACurrentMediaTime(), count) }
    }

    /// 8 bytes: session × 1,000,000 + the call number, so the check knows which call of which session
    /// an output belongs to (`FakeVT.origin`).
    static func sample(session: Int, call: Int, pts: CMTime, key: Bool) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 8, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: 8,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block else { return nil }
        var v = Int64(session) * 1_000_000 + Int64(call)
        _ = withUnsafeBytes(of: &v) { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: 8)
        }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var size = 8
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: nil, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sb) == noErr,
              let sb else { return nil }
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as NSArray?,
           let d = arr.firstObject as? NSMutableDictionary {
            d[kCMSampleAttachmentKey_NotSync as String] = !key
        }
        return sb
    }
}

// MARK: - The VideoToolbox names HEVCEncoder.swift uses

struct VTEncodeInfoFlags: OptionSet { let rawValue: UInt32; init(rawValue: UInt32) { self.rawValue = rawValue } }
typealias VTCompressionOutputHandler = (OSStatus, VTEncodeInfoFlags, CMSampleBuffer?) -> Void

@discardableResult
func VTCompressionSessionCreate(allocator: CFAllocator?, width: Int32, height: Int32, codecType: CMVideoCodecType,
                                encoderSpecification: CFDictionary?, imageBufferAttributes: CFDictionary?,
                                compressedDataAllocator: CFAllocator?, outputCallback: UnsafeRawPointer?,
                                refcon: UnsafeMutableRawPointer?,
                                compressionSessionOut: UnsafeMutablePointer<VTCompressionSession?>) -> OSStatus {
    let spec = encoderSpecification as NSDictionary?
    let software = (spec?[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String] as? Bool) == false
    let delay = FakeVT.lock.run { FakeVT.createDelay }
    if delay > 0 { Thread.sleep(forTimeInterval: delay) }
    compressionSessionOut.pointee = VTCompressionSession(software: software)
    return noErr
}
@discardableResult func VTSessionSetProperty(_ session: VTCompressionSession, key: CFString, value: CFTypeRef?) -> OSStatus { noErr }
@discardableResult func VTCompressionSessionPrepareToEncodeFrames(_ session: VTCompressionSession) -> OSStatus { noErr }
func VTCompressionSessionEncodeFrame(_ session: VTCompressionSession, imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime,
                                     duration: CMTime, frameProperties: CFDictionary?,
                                     infoFlagsOut: UnsafeMutablePointer<VTEncodeInfoFlags>?,
                                     outputHandler: @escaping VTCompressionOutputHandler) -> OSStatus {
    session.encode(imageBuffer, pts: presentationTimeStamp, props: frameProperties, handler: outputHandler)
}
@discardableResult
func VTCompressionSessionCompleteFrames(_ session: VTCompressionSession, untilPresentationTimeStamp: CMTime) -> OSStatus {
    session.completeFrames(); return noErr
}
func VTCompressionSessionInvalidate(_ session: VTCompressionSession) { session.invalidate() }

let kVTCompressionPropertyKey_RealTime = "RealTime" as CFString
let kVTCompressionPropertyKey_ProfileLevel = "ProfileLevel" as CFString
let kVTProfileLevel_HEVC_Main_AutoLevel = "HEVC_Main_AutoLevel" as CFString
let kVTCompressionPropertyKey_AllowFrameReordering = "AllowFrameReordering" as CFString
let kVTCompressionPropertyKey_MaxKeyFrameInterval = "MaxKeyFrameInterval" as CFString
let kVTCompressionPropertyKey_ExpectedFrameRate = "ExpectedFrameRate" as CFString
let kVTCompressionPropertyKey_AverageBitRate = "AverageBitRate" as CFString
let kVTCompressionPropertyKey_DataRateLimits = "DataRateLimits" as CFString
let kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality = "PrioritizeEncodingSpeedOverQuality" as CFString
let kVTEncodeFrameOptionKey_ForceKeyFrame = "ForceKeyFrame" as CFString
let kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder = "EnableHardwareAcceleratedVideoEncoder" as CFString

// MARK: - StreamProtocol's and SillHostCore's names

struct ParameterSets { let nalUnitHeaderLength: Int; let sets: [Data] }

/// SillHostCore's counters, as HEVCEncoder.swift and EncoderProbe.swift use them.
final class Stats {
    static let shared = Stats()
    private let lock = UnfairLock()
    private var counts: [String: Int] = [:]
    func bump(_ key: String) { lock.run { counts[key, default: 0] += 1 } }
    func take() -> [String: Int] { lock.run { defer { counts = [:] }; return counts } }
}

// MARK: - A stand-in for a thread descheduled right after it releases a lock

/// `-[NSLock unlock]` is swizzled (`Inject.install`): on a thread that armed it, the `sleepOn`th
/// unlock after arming is followed by a sleep, as if the thread were descheduled there. Only the
/// encoder's NSLocks are ever unlocked on an armed thread (this file uses none).
final class InjectState {
    var count = 0
    let sleepOn: Int
    let delay: Double
    init(sleepOn: Int, delay: Double) { self.sleepOn = sleepOn; self.delay = delay }
}
enum Inject {
    static var key: pthread_key_t = { var k = pthread_key_t(); pthread_key_create(&k, nil); return k }()
    static func arm(sleepOn: Int, delay: Double) {
        pthread_setspecific(key, Unmanaged.passRetained(InjectState(sleepOn: sleepOn, delay: delay)).toOpaque())
    }
    /// How many NSLock unlocks this thread made while armed.
    @discardableResult
    static func disarm() -> Int {
        guard let p = pthread_getspecific(key) else { return -1 }
        pthread_setspecific(key, nil)
        return Unmanaged<InjectState>.fromOpaque(p).takeRetainedValue().count
    }
    static func install() {
        _ = key
        let sel = NSSelectorFromString("unlock")
        guard let m = class_getInstanceMethod(NSLock.self, sel) else { fatalError("no -[NSLock unlock]") }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        let block: @convention(block) (AnyObject) -> Void = { object in
            original(object, sel)
            if let p = pthread_getspecific(Inject.key) {
                let state = Unmanaged<InjectState>.fromOpaque(p).takeUnretainedValue()
                state.count += 1
                if state.count == state.sleepOn, state.delay > 0 { usleep(useconds_t(state.delay * 1_000_000)) }
            }
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }
}
