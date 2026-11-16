import Foundation
import AppKit
import ApplicationServices
import StreamProtocol

/// Streams the Mac's current cursor shape to the clients, so the pointer they draw themselves
/// turns into an I-beam over text, a hand over a link, a resize arrow at an edge, exactly as on
/// the Mac. `NSCursor.currentSystem` is the cursor the window server is showing, whichever app
/// owns it. Polled at 20 Hz on the main queue only while a source is streaming.
///
/// Also monitors macOS Accessibility focus off the main thread (`sill.axfocus` serial queue) so
/// Sill never stalls `@MainActor` if an app is slow to respond to Accessibility IPC, notifying the
/// coordinator whenever an editable text field gains or loses focus or its text/selected range changes.
@MainActor
final class CursorShapeWatcher {
    /// A new shape, already encoded. Main thread.
    var onChange: ((Data) -> Void)?
    /// Called whenever the Mac's editable text-input focus state or synchronized text changes. Main thread.
    var onTextInputFocusChanged: (() -> Void)?
    /// The last blob sent, for a client that just connected.
    private(set) var current: Data?
    /// Whether the Mac's currently focused UI element is an editable text input field.
    private(set) var isTextInputFocused = false
    /// Monotonic token incremented whenever focus moves to a new editable field or selection target.
    private(set) var textInputFocusID: UInt64 = 0
    /// Screen-space CG rect of the currently focused editable field, if Accessibility reported one.
    private(set) var textInputFrame: CGRect?
    /// Current text mirrored from the Mac's focused input field (either the selected text or full field text).
    private(set) var textInputValue: String?
    /// True when `textInputValue` reflects a highlighted text selection (`kAXSelectedTextAttribute`).
    private(set) var textInputIsSelection = false
    /// Monotonic revision incremented whenever `textInputValue` or `textInputIsSelection` changes on the Mac.
    private(set) var textInputRevision: UInt64 = 0

    var running = false {
        didSet {
            guard running != oldValue else { return }
            if running { start() } else { stop() }
        }
    }

    private var timer: DispatchSourceTimer?
    private var lastHash: Int?
    private var focusTick = 0

    // Off-main-thread AX state
    private let axQueue = DispatchQueue(label: "sill.axfocus", qos: .userInteractive)
    private var axQueryInFlight = false
    private var cachedAXTrusted = false
    private var lastAXTrustCheck: CFAbsoluteTime = 0
    private var lastElementSignature: UInt64?
    private var lastInputEventFromDeviceAt: CFAbsoluteTime = 0
    private var delayedFocusChecks: [DispatchWorkItem] = []

    /// Bundle ID prefixes of document/office suites (Word, Pages, LibreOffice, etc.) excluded from
    /// automatic handwriting popup and full-document text sync.
    nonisolated private static let excludedBundlePrefixes: [String] = [
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.microsoft.Powerpoint",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote",
        "org.libreoffice.",
        "com.kingsoft.wpsoffice",
    ]

    private func start() {
        cachedAXTrusted = AXIsProcessTrusted()
        lastAXTrustCheck = CFAbsoluteTimeGetCurrent()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
        checkTextInputFocusNow()
    }

    private func stop() {
        timer?.cancel(); timer = nil
        lastHash = nil
        for item in delayedFocusChecks { item.cancel() }
        delayedFocusChecks.removeAll()
        let changed = isTextInputFocused || textInputValue != nil
        isTextInputFocused = false
        textInputFrame = nil
        textInputValue = nil
        textInputIsSelection = false
        lastElementSignature = nil
        if changed {
            onTextInputFocusChanged?()
        }
    }

    /// Records that the iPad just sent text/backspace/key input to the Mac so AX value reads do not
    /// echo an intermediate half-typed string back to the iPad while strokes are still landing.
    func noteDeviceTyping() {
        lastInputEventFromDeviceAt = CFAbsoluteTimeGetCurrent()
    }

    /// Triggers immediate and short-follow-up focus/selection checks (e.g. right after a tap, drag-select,
    /// or key event so newly focused fields or newly selected text segments are mirrored promptly).
    func checkTextInputFocusAfterInteraction() {
        guard running else { return }
        for item in delayedFocusChecks { item.cancel() }
        delayedFocusChecks.removeAll()

        let delays: [TimeInterval] = [0.035, 0.14, 0.30]
        for delay in delays {
            let item = DispatchWorkItem { [weak self] in
                self?.checkTextInputFocusNow()
            }
            delayedFocusChecks.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    func checkTextInputFocusNow() {
        guard running else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastAXTrustCheck >= 5.0 {
            lastAXTrustCheck = now
            cachedAXTrusted = AXIsProcessTrusted()
        }
        guard cachedAXTrusted else {
            applyFocusResult(TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false))
            return
        }
        guard !axQueryInFlight else { return }
        axQueryInFlight = true
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontPid = frontApp?.processIdentifier
        let frontBundle = frontApp?.bundleIdentifier ?? ""
        let ownPid = getpid()

        axQueue.async { [weak self] in
            let result = Self.detectTextInputFocus(frontPid: frontPid, frontBundle: frontBundle, ownPid: ownPid)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.axQueryInFlight = false
                guard self.running else { return }
                self.applyFocusResult(result)
            }
        }
    }

    private func applyFocusResult(_ result: TextFocusProbeResult) {
        let wasFocused = isTextInputFocused
        let prevSig = lastElementSignature
        let prevVal = textInputValue
        let prevSel = textInputIsSelection

        if result.focused {
            let isNewField = !wasFocused || (prevSig != result.signature)
            let isNewSelectionMode = (prevSel != result.isSelection)
            isTextInputFocused = true
            textInputFrame = result.frame
            lastElementSignature = result.signature

            let recentlyTypedByDevice = (CFAbsoluteTimeGetCurrent() - lastInputEventFromDeviceAt) < 0.45
            var valueChanged = false

            // When a message is sent on Mac or the field is cleared, syncedText transitions to "" or nil.
            // Never suppress clearing/empty updates even if the user recently pressed Enter on the device.
            let isClearOrEmpty = (result.syncedText == nil || result.syncedText?.isEmpty == true) && (textInputValue != nil && textInputValue?.isEmpty == false)

            if isNewField || isNewSelectionMode || isClearOrEmpty || !recentlyTypedByDevice {
                if textInputValue != result.syncedText || textInputIsSelection != result.isSelection {
                    textInputValue = result.syncedText
                    textInputIsSelection = result.isSelection
                    textInputRevision &+= 1
                    if textInputRevision == 0 { textInputRevision = 1 }
                    valueChanged = true
                }
            }

            if isNewField || isNewSelectionMode {
                textInputFocusID &+= 1
                if textInputFocusID == 0 { textInputFocusID = 1 }
            }

            if isNewField || valueChanged || prevVal != textInputValue || prevSel != textInputIsSelection {
                onTextInputFocusChanged?()
            }
        } else {
            textInputFrame = nil
            textInputValue = nil
            textInputIsSelection = false
            lastElementSignature = nil
            if wasFocused {
                isTextInputFocused = false
                onTextInputFocusChanged?()
            }
        }
    }

    private func poll() {
        focusTick &+= 1
        if focusTick % 3 == 0 {
            checkTextInputFocusNow()
        }
        guard let cursor = NSCursor.currentSystem else { return }
        let image = cursor.image
        let hash = Self.fingerprint(of: image, hotspot: cursor.hotSpot)
        guard hash != lastHash else { return }
        // The representation nearest 2× the point size: what a Retina device draws, without the
        // 5× and 10× assets some system cursors carry.
        let wanted = image.size.width * 2
        guard let rep = image.representations.min(by: { abs(CGFloat($0.pixelsWide) - wanted) < abs(CGFloat($1.pixelsWide) - wanted) }),
              let png = Self.png(of: rep) else { return }
        lastHash = hash   // only once the PNG exists, so a failed encode is retried next poll
        let blob = CursorShapeBlob.encode(hotspot: cursor.hotSpot, size: image.size, png: png)
        current = blob
        onChange?(blob)
        Stats.shared.bump("cursor.shape")
    }

    private static func fingerprint(of image: NSImage, hotspot: NSPoint) -> Int {
        var hasher = Hasher()
        hasher.combine(hotspot.x); hasher.combine(hotspot.y)
        hasher.combine(image.size.width); hasher.combine(image.size.height)
        let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if let small = bitmaps.min(by: { $0.pixelsWide < $1.pixelsWide }), let bytes = small.bitmapData {
            hasher.combine(bytes: UnsafeRawBufferPointer(start: bytes, count: small.bytesPerRow * small.pixelsHigh))
        } else if let tiff = image.tiffRepresentation {
            hasher.combine(tiff)   // no bitmap representation: fall back to the expensive way
        }
        return hasher.finalize()
    }

    private static func png(of rep: NSImageRep) -> Data? {
        if let bitmap = rep as? NSBitmapImageRep { return bitmap.representation(using: .png, properties: [:]) }
        guard let cg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private struct TextFocusProbeResult: Sendable {
        let focused: Bool
        let frame: CGRect?
        let signature: UInt64
        let syncedText: String?
        let isSelection: Bool
    }

    nonisolated private static func isExcludedApp(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        for prefix in excludedBundlePrefixes {
            if bundleID.hasPrefix(prefix) { return true }
        }
        return false
    }

    /// Queries macOS Accessibility off the main thread to determine if the currently focused UI element
    /// is an editable text field, search field, combo box, or text editor, along with its screen frame
    /// and either its currently selected text (`kAXSelectedTextAttribute`) or its full value (`kAXValueAttribute`).
    nonisolated private static func detectTextInputFocus(frontPid: pid_t?, frontBundle: String, ownPid: pid_t) -> TextFocusProbeResult {
        if isExcludedApp(bundleID: frontBundle) {
            return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.04)

        var elementRef: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &elementRef)
        if status != .success || elementRef == nil, let frontPid, frontPid != ownPid {
            let appElem = AXUIElementCreateApplication(frontPid)
            AXUIElementSetMessagingTimeout(appElem, 0.04)
            status = AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute as CFString, &elementRef)
        }
        guard status == .success, let raw = elementRef, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
        }
        let elem = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(elem, 0.04)

        var elemPid: pid_t = 0
        AXUIElementGetPid(elem, &elemPid)
        if elemPid == ownPid {
            return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
        }
        if elemPid != frontPid, let app = NSRunningApplication(processIdentifier: elemPid),
           let bundle = app.bundleIdentifier, isExcludedApp(bundleID: bundle) {
            return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
        }

        // Disabled controls should never pop up handwriting input.
        var enabledRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXEnabledAttribute as CFString, &enabledRef) == .success,
           let enabled = enabledRef as? Bool, !enabled {
            return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
        }

        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String ?? "") : ""

        var subroleRef: CFTypeRef?
        let subrole = (AXUIElementCopyAttributeValue(elem, kAXSubroleAttribute as CFString, &subroleRef) == .success)
            ? (subroleRef as? String ?? "") : ""

        var isEditable = false
        var editableRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, "AXEditable" as CFString, &editableRef) == .success,
           let editable = editableRef as? Bool {
            if !editable {
                return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
            }
            isEditable = true
        }

        if !isEditable {
            let textRoles: Set<String> = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                kAXComboBoxRole as String,
                "AXSearchField",
            ]
            if textRoles.contains(role) || subrole == "AXSearchField" || subrole == "AXSecureTextField" {
                var settable: DarwinBoolean = false
                let st = AXUIElementIsAttributeSettable(elem, kAXValueAttribute as CFString, &settable)
                // If macOS explicitly reports AXValue is not settable, it's a read-only viewer/label.
                if st == .success && !settable.boolValue {
                    return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
                }
                isEditable = true
            } else if role == kAXStaticTextRole as String || role == "AXGroup" {
                var settable: DarwinBoolean = false
                if AXUIElementIsAttributeSettable(elem, kAXValueAttribute as CFString, &settable) == .success,
                   settable.boolValue {
                    isEditable = true
                }
            }
        }

        guard isEditable else {
            return TextFocusProbeResult(focused: false, frame: nil, signature: 0, syncedText: nil, isSelection: false)
        }

        var frame: CGRect?
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXPositionAttribute as CFString, &posRef) == .success,
           AXUIElementCopyAttributeValue(elem, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let posRaw = posRef, CFGetTypeID(posRaw) == AXValueGetTypeID(),
           let sizeRaw = sizeRef, CFGetTypeID(sizeRaw) == AXValueGetTypeID() {
            var pt = CGPoint.zero
            var sz = CGSize.zero
            let posVal = unsafeBitCast(posRaw, to: AXValue.self)
            let sizeVal = unsafeBitCast(sizeRaw, to: AXValue.self)
            if AXValueGetValue(posVal, .cgPoint, &pt), AXValueGetValue(sizeVal, .cgSize, &sz),
               sz.width > 0, sz.height > 0 {
                frame = CGRect(origin: pt, size: sz)
            }
        }

        // Read either selected text (highest priority when user highlights a range) or full text value
        var syncedText: String? = nil
        var isSelection = false
        if subrole != "AXSecureTextField" {
            var selectedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
               let selStr = selectedRef as? String, !selStr.isEmpty, selStr.utf16.count <= 2_000 {
                syncedText = selStr
                isSelection = true
            } else {
                var valRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valRef) == .success,
                   let valStr = valRef as? String, valStr.utf16.count <= 2_000 {
                    // Check if cursor is at the end (or field is empty) so live suffix edits stay in sync
                    var canSyncFullValue = true
                    var rangeRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(elem, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
                       let rangeRaw = rangeRef, CFGetTypeID(rangeRaw) == AXValueGetTypeID() {
                        var cfRange = CFRange(location: 0, length: 0)
                        let rangeVal = unsafeBitCast(rangeRaw, to: AXValue.self)
                        if AXValueGetValue(rangeVal, .cfRange, &cfRange) {
                            if cfRange.length > 0 && cfRange.location + cfRange.length <= valStr.utf16.count {
                                let nsStr = valStr as NSString
                                let sub = nsStr.substring(with: NSRange(location: cfRange.location, length: cfRange.length))
                                if !sub.isEmpty {
                                    syncedText = sub
                                    isSelection = true
                                    canSyncFullValue = false
                                }
                            } else if cfRange.location < valStr.utf16.count {
                                // Caret is positioned in the middle of existing text without a selection:
                                // leave the handwriting pad blank so new handwriting inserts cleanly at the caret.
                                canSyncFullValue = false
                            }
                        }
                    }
                    if canSyncFullValue {
                        syncedText = valStr
                    }
                }
            }
        }

        var hasher = Hasher()
        hasher.combine(elemPid)
        hasher.combine(role)
        hasher.combine(subrole)
        if let f = frame {
            // Quantize origin (not height, which grows as multi-line chat boxes expand)
            hasher.combine(Int((f.minX / 12).rounded()))
            hasher.combine(Int((f.minY / 12).rounded()))
        }
        let sig = UInt64(bitPattern: Int64(hasher.finalize()))
        return TextFocusProbeResult(focused: true, frame: frame, signature: sig, syncedText: syncedText, isSelection: isSelection)
    }
}
