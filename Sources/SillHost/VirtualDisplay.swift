import Foundation
import CoreGraphics
import ObjectiveC

/// A virtual monitor on the Mac, made with CoreGraphics' **private** `CGVirtualDisplay` API.
///
/// Why: milestone 3 gives each client device its own display at the device's HiDPI size,
/// so the streamed window renders crisp at device scale and keeps repainting no matter what
/// covers the Mac's real screen (window capture freezes when the window is occluded).
///
/// Private API, read before shipping:
/// - `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`, `CGVirtualDisplaySettings` and
///   `CGVirtualDisplayMode` live in CoreGraphics.framework but are in no public header.
///   They have existed since macOS 11 and are used by shipping apps (DeskPad, BetterDisplay,
///   Chromium's test harness), but Apple can rename or remove them in any release.
/// - Every class and selector is looked up through the Objective-C runtime and its type
///   encoding is checked before the call, so a missing or changed API becomes a thrown
///   `VirtualDisplay.Failure`, never a crash. Callers must treat a throw as "fall back to
///   streaming the real window" (docs/BRIEF.md risk 3).
/// - App Store: guideline 2.5.1 forbids non-public API, and App Review scans binaries for
///   private symbols. The runtime lookups here reference no private *symbols* (only strings),
///   so the linker and a notarization scan see nothing, but using it in an App Store build
///   is still a guideline violation. The Mac companion ships outside the Mac App Store
///   (Developer ID + notarization), where this is allowed; notarization checks signing and
///   malware, not API usage. No entitlement is needed and SIP is not involved.
///
/// Identity: macOS remembers a display's arrangement (where it sits relative to the main
/// display) and chosen mode by vendorID/productID/serial. Keep those stable per client device
/// (e.g. serial derived from the device's identifier) so the display comes back in the same
/// place every session instead of piling up new entries in System Settings › Displays.
///
/// Lifetime: the display exists exactly as long as this object holds the `CGVirtualDisplay`
/// instance. `destroy()` (or deinit) releases it and the display disappears; windows on it
/// are moved back to a real display by the window server. If the process dies the display
/// goes with it.
///
/// Event loop (measured on macOS 27): the owning process must run an AppKit event loop,
/// `NSApplication.shared.run()` with activation policy `.accessory` or `.prohibited`. The
/// window server delivers display reconfiguration through the app's event port, which
/// `dispatchMain()` or a bare `RunLoop` never drains. Without it the display still works
/// (other processes and the window server see it at the right mode) but *this* process's
/// CoreGraphics never learns about it: `CGDisplayCopyDisplayMode` returns nil,
/// `CGDisplayCopyAllDisplayModes` is empty, so the HiDPI mode can't be selected, and
/// reconfiguration callbacks never fire. SillHost's `dispatchMain()` has to become
/// `NSApplication.run()` before it adopts this type.
///
/// Threading: create, wait and destroy on the main thread / main actor.
final class VirtualDisplay {
    enum Failure: Error, CustomStringConvertible {
        case classMissing(String)
        case selectorMissing(cls: String, selector: String)
        case signatureChanged(cls: String, selector: String, expected: String, found: String)
        case initReturnedNil(String)
        case applySettingsFailed
        case noDisplayID
        case invalidSize(String)

        var description: String {
            switch self {
            case .classMissing(let c):
                return "private class \(c) not found in CoreGraphics (API removed or renamed)"
            case .selectorMissing(let c, let s):
                return "private class \(c) does not respond to \(s)"
            case .signatureChanged(let c, let s, let e, let f):
                return "\(c) \(s) changed signature: expected \(e), found \(f)"
            case .initReturnedNil(let c):
                return "\(c) init returned nil"
            case .applySettingsFailed:
                return "CGVirtualDisplay applySettings: returned NO (mode rejected)"
            case .noDisplayID:
                return "CGVirtualDisplay was created but reported displayID 0"
            case .invalidSize(let why):
                return "invalid size: \(why)"
            }
        }
    }

    let name: String
    let widthPt: Int
    let heightPt: Int
    let scale: Int
    let refreshHz: Double
    let vendorID: UInt32
    let productID: UInt32
    let serialNum: UInt32

    /// Zero after `destroy()`.
    private(set) var displayID: CGDirectDisplayID = 0

    /// Called (on an internal queue) if the window server tears the display down on its own.
    var onTerminated: (() -> Void)?

    /// The display in global points, as CoreGraphics and window frames use them.
    /// Can read as zero for a moment right after creation, until the window server
    /// finishes reconfiguring; `waitUntilOnline` covers that.
    var bounds: CGRect { displayID == 0 ? .zero : CGDisplayBounds(displayID) }

    /// Backing pixels of the current mode (points × scale when HiDPI took effect).
    var pixelSize: (width: Int, height: Int) {
        guard displayID != 0, let mode = CGDisplayCopyDisplayMode(displayID) else { return (0, 0) }
        return (mode.pixelWidth, mode.pixelHeight)
    }

    var isAlive: Bool { object != nil }

    /// The retained CGVirtualDisplay instance. Releasing it removes the display.
    private var object: AnyObject?
    private let queue = DispatchQueue(label: "sill.virtualdisplay")

    /// - Parameters:
    ///   - widthPt, heightPt: the size windows see, in points.
    ///   - scale: 2 for HiDPI (backing store is widthPt×2 by heightPt×2 pixels), 1 for not.
    ///   - vendorID, productID, serialNum: display identity; keep stable (see type docs).
    init(name: String,
         widthPt: Int,
         heightPt: Int,
         scale: Int = 2,
         refreshHz: Double = 60,
         vendorID: UInt32 = 0x5111,
         productID: UInt32 = 0x0001,
         serialNum: UInt32 = 1) throws {
        guard widthPt >= 320, heightPt >= 240, widthPt <= 8192, heightPt <= 8192 else {
            throw Failure.invalidSize("\(widthPt)×\(heightPt) pt is outside 320×240…8192×8192")
        }
        guard scale == 1 || scale == 2 else { throw Failure.invalidSize("scale must be 1 or 2") }
        self.name = name
        self.widthPt = widthPt
        self.heightPt = heightPt
        self.scale = scale
        self.refreshHz = refreshHz
        self.vendorID = vendorID
        self.productID = productID
        self.serialNum = serialNum

        let pxW = widthPt * scale, pxH = heightPt * scale

        // --- Descriptor ---------------------------------------------------------------
        let descriptor = try Runtime.newObject("CGVirtualDisplayDescriptor")
        try Runtime.setObject(descriptor, "setName:", name as NSString)
        try Runtime.setUInt32(descriptor, "setMaxPixelsWide:", UInt32(pxW))
        try Runtime.setUInt32(descriptor, "setMaxPixelsHigh:", UInt32(pxH))
        // Physical size drives the DPI macOS reports. ~110 pt per inch is what Apple's own
        // Retina panels use, which keeps the default "looks like" choice sensible.
        let mm = CGSize(width: Double(widthPt) / 110 * 25.4, height: Double(heightPt) / 110 * 25.4)
        try Runtime.setSize(descriptor, "setSizeInMillimeters:", mm)
        try Runtime.setUInt32(descriptor, "setVendorID:", vendorID)
        try Runtime.setUInt32(descriptor, "setProductID:", productID)
        try Runtime.setUInt32(descriptor, "setSerialNum:", serialNum)
        // sRGB-ish primaries (same values Chromium uses); without them some macOS versions
        // build a display with a degenerate colour profile.
        try? Runtime.setPoint(descriptor, "setRedPrimary:", CGPoint(x: 0.6797, y: 0.3203))
        try? Runtime.setPoint(descriptor, "setGreenPrimary:", CGPoint(x: 0.2559, y: 0.6983))
        try? Runtime.setPoint(descriptor, "setBluePrimary:", CGPoint(x: 0.1494, y: 0.0557))
        try? Runtime.setPoint(descriptor, "setWhitePoint:", CGPoint(x: 0.3125, y: 0.3291))
        do {
            try Runtime.setObject(descriptor, "setQueue:", queue)
        } catch {
            try Runtime.setObject(descriptor, "setDispatchQueue:", queue)
        }
        // The handler's real signature is believed to be ^(id, CGVirtualDisplay *). The
        // arguments are taken as raw pointers so a different arity can't cause a bad retain.
        let terminated: @convention(block) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void = { [weak self] _, _ in
            self?.onTerminated?()
        }
        try Runtime.setBlock(descriptor, "setTerminationHandler:", terminated)

        // --- Display ------------------------------------------------------------------
        let display = try Runtime.allocInit("CGVirtualDisplay", "initWithDescriptor:", descriptor)

        // --- Settings: one mode, given in points. With hiDPI = 1 macOS derives two modes
        // from it, widthPt×heightPt at 1× and at 2× (backing pxW×pxH, which is why
        // maxPixels is the 2× size). Measured on macOS 27: which of the two is current at
        // creation depends on what macOS remembered for this vendor/product/serial, so
        // `waitUntilOnline` selects the requested one explicitly with public API.
        let mode = try Runtime.newMode(width: UInt32(widthPt), height: UInt32(heightPt), refreshRate: refreshHz)
        let settings = try Runtime.newObject("CGVirtualDisplaySettings")
        try Runtime.setUInt32(settings, "setHiDPI:", scale == 2 ? 1 : 0)
        try Runtime.setObject(settings, "setModes:", [mode] as NSArray)
        guard try VirtualDisplay.applySettings(settings, to: display) else { throw Failure.applySettingsFailed }

        let id = try Runtime.getUInt32(display, "displayID")
        guard id != 0 else { throw Failure.noDisplayID }
        self.object = display
        self.displayID = id
    }

    deinit { destroy() }

    /// True when the current mode is the requested point size at the requested scale.
    var hasRequestedMode: Bool {
        let b = bounds, px = pixelSize
        return Int(b.width) == widthPt && Int(b.height) == heightPt && px.width == widthPt * scale
    }

    /// Waits until the display is online at the requested point size and scale, selecting
    /// that mode with public CoreGraphics calls if macOS brought it up in another one.
    /// Returns false on timeout (the display may still be usable at whatever mode it has;
    /// check `bounds` and `pixelSize`). Needs the NSApplication event loop running (see the
    /// type docs), so call it from an async context on the main actor, not by blocking main.
    @discardableResult
    func waitUntilOnline(timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var nextSelect = Date()
        while Date() < deadline {
            if hasRequestedMode { return true }
            if bounds.width > 0, Date() >= nextSelect {
                selectRequestedMode()
                nextSelect = Date().addingTimeInterval(0.5)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return hasRequestedMode
    }

    /// Picks the mode whose point size and pixel size match the request. Public API.
    @discardableResult
    func selectRequestedMode() -> Bool {
        guard displayID != 0 else { return false }
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode] else { return false }
        guard let want = modes.first(where: {
            $0.width == widthPt && $0.height == heightPt && $0.pixelWidth == widthPt * scale
        }) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, displayID, want, nil)
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    /// Every mode macOS offers for this display, for diagnostics.
    func availableModes() -> [String] {
        guard displayID != 0 else { return [] }
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode]) ?? []
        return modes.map { "\($0.width)×\($0.height) pt @ \($0.pixelWidth)×\($0.pixelHeight) px, \(Int($0.refreshRate)) Hz" }
    }

    /// Every private class/selector/type encoding this file calls, in the order it calls them.
    /// Encodings are Objective-C type strings with the frame offsets stripped, and a `BOOL` return
    /// is written "B", which `TypeEncoding.accepted` also takes spelled "c".
    static let privateAPISurface: [(cls: String, selector: String, encoding: String)] = [
        ("CGVirtualDisplayDescriptor", "init", "@@:"),
        ("CGVirtualDisplayDescriptor", "setName:", "v@:@"),
        ("CGVirtualDisplayDescriptor", "setMaxPixelsWide:", "v@:I"),
        ("CGVirtualDisplayDescriptor", "setMaxPixelsHigh:", "v@:I"),
        ("CGVirtualDisplayDescriptor", "setSizeInMillimeters:", "v@:{CGSize=dd}"),
        ("CGVirtualDisplayDescriptor", "setVendorID:", "v@:I"),
        ("CGVirtualDisplayDescriptor", "setProductID:", "v@:I"),
        ("CGVirtualDisplayDescriptor", "setSerialNum:", "v@:I"),
        ("CGVirtualDisplayDescriptor", "setQueue:", "v@:@"),
        ("CGVirtualDisplayDescriptor", "setTerminationHandler:", "v@:@?"),
        ("CGVirtualDisplay", "initWithDescriptor:", "@@:@"),
        ("CGVirtualDisplay", "applySettings:", "B@:@"),
        ("CGVirtualDisplay", "displayID", "I@:"),
        ("CGVirtualDisplayMode", "initWithWidth:height:refreshRate:", "@@:IId"),
        ("CGVirtualDisplaySettings", "init", "@@:"),
        ("CGVirtualDisplaySettings", "setHiDPI:", "v@:I"),
        ("CGVirtualDisplaySettings", "setModes:", "v@:@"),
    ]

    /// Checks the whole private surface without creating anything. Empty means every class
    /// and selector is present with the expected signature; otherwise one line per problem.
    /// Cheap enough to call at launch to decide between virtual display and window fallback.
    /// (The colour primaries setters are optional and not listed; `setDispatchQueue:` is
    /// accepted in place of `setQueue:`.)
    static func checkPrivateAPI() -> [String] {
        privateAPISurface.compactMap { entry -> String? in
            let problem = methodProblem(cls: entry.cls, selector: entry.selector, encoding: entry.encoding)
            guard problem != nil, entry.selector == "setQueue:" else { return problem }
            return methodProblem(cls: entry.cls, selector: "setDispatchQueue:", encoding: entry.encoding)
        }
    }

    /// `Runtime.method`'s decision for one entry of the surface: nil when the class named `cls` has
    /// an instance method `selector` whose type encoding, without its offsets, is one that
    /// `TypeEncoding.accepted(encoding)` takes; else the problem, as `checkPrivateAPI` lists it.
    /// Tests/checks/virtual-display-api asks it about classes it makes at run time, so the check
    /// runs this decision rather than a copy of it.
    static func methodProblem(cls: String, selector: String, encoding: String) -> String? {
        do {
            _ = try Runtime.method(Runtime.cls(cls), selector, encoding)
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// `[display applySettings:settings]`, as `init` sends it to its `CGVirtualDisplay`. The method
    /// is checked first (`Runtime.method`) against "B@:@", a `BOOL` return, which the runtime
    /// spells "B" or "c" (`TypeEncoding.accepted` has where each was seen). Either way it is one
    /// byte in the return register, read here as `ObjCBool`, which is `BOOL` on each architecture:
    /// C99 `bool` on arm64, the same code a Swift `Bool` gives there, and `signed char` on x86_64,
    /// where any byte but 0 is YES; a Swift `Bool` there would take the byte as it comes, which is
    /// safe only for a 0 or a 1. Tests/checks/virtual-display-api sends it to classes it makes at
    /// run time.
    static func applySettings(_ settings: AnyObject, to display: AnyObject) throws -> Bool {
        let (fn, sel) = try Runtime.imp(display, "applySettings:", "B@:@", as: Runtime.ApplyFn.self)
        return fn(display, sel, settings).boolValue
    }

    /// How a method's type encoding, as the Objective-C runtime reports it, is matched against the
    /// one `privateAPISurface` gives. Pure: `Tests/checks/virtual-display-api` holds it, and the
    /// surface, to the encodings measured on Apple silicon, natively and under Rosetta, and
    /// reported from Intel machines.
    enum TypeEncoding {
        /// `v24@0:8@16` → `v@:@`. Offsets vary by architecture; the types are what matter.
        static func normalized(_ encoding: String) -> String {
            String(encoding.filter { !$0.isNumber })
        }

        /// The spellings that count as `expected`: itself and, for a `BOOL` return (written "B",
        /// C99 `bool`), the same with "c" (`signed char`).
        ///
        /// The runtime spells a `BOOL` return as the Mac's CoreGraphics was built, and on x86_64
        /// `applySettings:` has been spelled both ways: "c@:@" on an Intel Mac mini with macOS
        /// 15.7.3 (#87), where "B@:@" alone made `Runtime.method` throw `Failure.signatureChanged`
        /// and every virtual display fall back to the real window, though the method was there and
        /// worked; "B@:@" on an Intel machine running macOS 26.7.1 through OpenCore, going by #62's
        /// report, where an x86_64 build of 985a733 (build 585), which expected "B@:@" alone,
        /// passed the self test (the encoding itself was not printed); and "c@:@" again under
        /// Rosetta on macOS 27.0.1 (c24@0:8@16). arm64 reads "B@:@" (B24@0:8@16 on macOS 27.0.1).
        /// So both are taken on every architecture, with no `#if arch`, and the arm64 build CI
        /// makes compiles the only path. Either is one byte in the return register, which
        /// `applySettings(_:to:)` reads as `ObjCBool`.
        static func accepted(_ expected: String) -> [String] {
            expected.first == "B" ? [expected, "c" + expected.dropFirst()] : [expected]
        }
    }

    /// Releases the CGVirtualDisplay; the display disappears. Safe to call twice.
    func destroy() {
        object = nil
        displayID = 0
    }
}

// MARK: - Objective-C runtime access

/// Looks up private classes and methods by name and checks each method's type encoding
/// against what this code was written for before calling its IMP. Anything unexpected
/// throws instead of sending a message with the wrong ABI.
private enum Runtime {
    static func cls(_ name: String) throws -> AnyClass {
        guard let c = NSClassFromString(name) else { throw VirtualDisplay.Failure.classMissing(name) }
        return c
    }

    /// Finds an instance method and checks its type encoding (`VirtualDisplay.TypeEncoding`). Used
    /// on classes (for init selectors, before an instance exists, and by `VirtualDisplay.methodProblem`)
    /// and via `imp` on live objects.
    static func method(_ c: AnyClass, _ selector: String, _ encoding: String) throws -> (IMP, Selector) {
        let sel = NSSelectorFromString(selector)
        guard let method = class_getInstanceMethod(c, sel) else {
            throw VirtualDisplay.Failure.selectorMissing(cls: NSStringFromClass(c), selector: selector)
        }
        let found = method_getTypeEncoding(method).map { VirtualDisplay.TypeEncoding.normalized(String(cString: $0)) } ?? "?"
        let accepted = VirtualDisplay.TypeEncoding.accepted(encoding)
        guard accepted.contains(found) else {
            throw VirtualDisplay.Failure.signatureChanged(cls: NSStringFromClass(c), selector: selector,
                                                         expected: accepted.joined(separator: " or "), found: found)
        }
        return (method_getImplementation(method), sel)
    }

    static func imp<F>(_ target: AnyObject, _ selector: String, _ encoding: String, as: F.Type) throws -> (F, Selector) {
        let (imp, sel) = try method(object_getClass(target)!, selector, encoding)
        return (unsafeBitCast(imp, to: F.self), sel)
    }

    /// `[[Class alloc] init]`.
    static func newObject(_ className: String) throws -> NSObject {
        guard let type = try cls(className) as? NSObject.Type else {
            throw VirtualDisplay.Failure.classMissing("\(className) (not an NSObject)")
        }
        return type.init()
    }

    typealias AllocFn = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    typealias InitObjFn = @convention(c) (UnsafeMutableRawPointer, Selector, AnyObject) -> UnsafeMutableRawPointer?
    typealias InitModeFn = @convention(c) (UnsafeMutableRawPointer, Selector, UInt32, UInt32, Double) -> UnsafeMutableRawPointer?

    /// `[[Class alloc] <initSelector>:arg]` for an init taking one object.
    /// alloc returns +1; init consumes it and returns +1, which `takeRetainedValue` adopts.
    static func allocInit(_ className: String, _ initSelector: String, _ arg: AnyObject) throws -> AnyObject {
        let c: AnyClass = try cls(className)
        let raw = try alloc(c)
        let (initFn, sel) = try initIMP(c, initSelector, "@@:@", as: InitObjFn.self)
        guard let obj = initFn(raw, sel, arg) else { throw VirtualDisplay.Failure.initReturnedNil(className) }
        return Unmanaged<AnyObject>.fromOpaque(obj).takeRetainedValue()
    }

    /// `[[CGVirtualDisplayMode alloc] initWithWidth:height:refreshRate:]`.
    static func newMode(width: UInt32, height: UInt32, refreshRate: Double) throws -> AnyObject {
        let name = "CGVirtualDisplayMode"
        let c: AnyClass = try cls(name)
        let (initFn, sel) = try initIMP(c, "initWithWidth:height:refreshRate:", "@@:IId", as: InitModeFn.self)
        let raw = try alloc(c)
        guard let obj = initFn(raw, sel, width, height, refreshRate) else { throw VirtualDisplay.Failure.initReturnedNil(name) }
        return Unmanaged<AnyObject>.fromOpaque(obj).takeRetainedValue()
    }

    private static func alloc(_ c: AnyClass) throws -> UnsafeMutableRawPointer {
        let sel = NSSelectorFromString("alloc")
        guard let method = class_getClassMethod(c, sel) else {
            throw VirtualDisplay.Failure.selectorMissing(cls: NSStringFromClass(c), selector: "+alloc")
        }
        let fn = unsafeBitCast(method_getImplementation(method), to: AllocFn.self)
        guard let raw = fn(c, sel) else { throw VirtualDisplay.Failure.initReturnedNil(NSStringFromClass(c)) }
        return raw
    }

    private static func initIMP<F>(_ c: AnyClass, _ selector: String, _ encoding: String, as: F.Type) throws -> (F, Selector) {
        let (imp, sel) = try method(c, selector, encoding)
        return (unsafeBitCast(imp, to: F.self), sel)
    }

    typealias SetObjFn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    typealias SetUIntFn = @convention(c) (AnyObject, Selector, UInt32) -> Void
    typealias SetSizeFn = @convention(c) (AnyObject, Selector, CGSize) -> Void
    typealias SetPointFn = @convention(c) (AnyObject, Selector, CGPoint) -> Void
    typealias SetBlockFn = @convention(c) (AnyObject, Selector, @convention(block) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void) -> Void
    typealias GetUIntFn = @convention(c) (AnyObject, Selector) -> UInt32
    typealias ApplyFn = @convention(c) (AnyObject, Selector, AnyObject) -> ObjCBool

    static func setObject(_ target: AnyObject, _ selector: String, _ value: AnyObject) throws {
        let (fn, sel) = try imp(target, selector, "v@:@", as: SetObjFn.self)
        fn(target, sel, value)
    }

    static func setUInt32(_ target: AnyObject, _ selector: String, _ value: UInt32) throws {
        let (fn, sel) = try imp(target, selector, "v@:I", as: SetUIntFn.self)
        fn(target, sel, value)
    }

    static func setSize(_ target: AnyObject, _ selector: String, _ value: CGSize) throws {
        let (fn, sel) = try imp(target, selector, "v@:{CGSize=dd}", as: SetSizeFn.self)
        fn(target, sel, value)
    }

    static func setPoint(_ target: AnyObject, _ selector: String, _ value: CGPoint) throws {
        let (fn, sel) = try imp(target, selector, "v@:{CGPoint=dd}", as: SetPointFn.self)
        fn(target, sel, value)
    }

    static func setBlock(_ target: AnyObject, _ selector: String,
                         _ block: @escaping @convention(block) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void) throws {
        let (fn, sel) = try imp(target, selector, "v@:@?", as: SetBlockFn.self)
        fn(target, sel, block)
    }

    static func getUInt32(_ target: AnyObject, _ selector: String) throws -> UInt32 {
        let (fn, sel) = try imp(target, selector, "I@:", as: GetUIntFn.self)
        return fn(target, sel)
    }
}
