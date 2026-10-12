import AppKit
import StreamProtocol

/// A drag of files over this Mac's windows, followed as it goes (kind 38, LiveDrag), so the app under
/// the pointer takes it as a drag of its own: it highlights where the files would land (a folder, a
/// web page's drop zone, the address bar), and the device's modifier keys choose what a drop does
/// (Finder moves, copies with ⌥, makes an alias with ⌥⌘). Two kinds:
///
/// - The host's own files (`offer`): an app here is already dragging them under the device's held
///   button (DragOut), and the device carried the drag over another of this Mac's windows. The button
///   stays down; the pointer follows onto that window (each on its own display of the desk), and the
///   drag lands where it is let go.
/// - The device's files: sent as kind 34 parts as the drag comes over the window; once all are here,
///   this Mac starts a drag of them under the pointer (FileDrops' panel takes the press) and follows
///   it as for its own.
///
/// Every event goes the way a device's input does (`deliver`: InputInjector, its held buttons and keys
/// tracked, let go of when the device leaves). One drag per device. Main actor.
@MainActor
final class LiveDrags {
    /// A device's input, in a window's rectangle (the coordinator's `deliver`).
    var deliver: ((InputEvent, CGRect, KeyStrokes.Device) -> Void)?
    /// A window's rectangle on screen (global, top-left origin): one shown beside the streamed one,
    /// else (nil) the streamed one.
    var rect: ((UInt32?) -> CGRect?)?
    /// The host's own drag of an offer is over (the drag-out watch stops).
    var ownDragEnded: ((KeyStrokes.Device) -> Void)?

    private let fileDrops: FileDrops
    init(fileDrops: FileDrops) { self.fileDrops = fileDrops }

    private struct Drag {
        let id: UInt32
        let own: Bool
        var window: UInt32?
        var x: Double
        var y: Double
        var modifiers: UInt64 = 0
        var began = false
        /// The button went down for this Mac's drag of the device's files (before `began`).
        var pressed = false
        var dropWanted = false
        var received: [URL] = []
        var watchdog: DispatchWorkItem?
    }
    private var drags: [KeyStrokes.Device: Drag] = [:]

    /// The modifier keys a drag carries: shift, control, option, command (InputEvent's bits, which
    /// are CGEventFlags') and the HID usage of each one's left key.
    private static let modifierKeys: [(bit: UInt64, usage: UInt16)] = [
        (1 << 17, 0xE1), (1 << 18, 0xE0), (1 << 19, 0xE2), (1 << 20, 0xE3),
    ]
    private static let modifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
    /// A drag that hears nothing for this long is given up (the device stalled mid-drag).
    private static let silence: TimeInterval = 10

    func handle(_ d: LiveDrag, from device: KeyStrokes.Device, name: String) {
        if d.phase == LiveDrag.start {
            if let old = drags[device], old.id != d.id { end(device, dropped: false) }
            guard drags[device] == nil else { return }
            var drag = Drag(id: d.id, own: d.offer != nil, window: d.window, x: d.x, y: d.y)
            drag.began = drag.own   // the host's own drag is already under way, its button held
            drags[device] = drag
            print("Live drag from \(name): \(drag.own ? "this Mac's own files" : "files on their way") over \(d.window.map { "window \($0)" } ?? "the streamed window")")
            if drag.own { follow(device, to: d) }
            arm(device)
            return
        }
        guard var drag = drags[device], drag.id == d.id else {
            // A drag given up before its files were all sent: what arrived goes.
            if d.phase == LiveDrag.filesSent { discard(fileDrops.received(d.files ?? [], folders: d.folders ?? [])) }
            return
        }
        arm(device)
        switch d.phase {
        case LiveDrag.filesSent where !drag.own && !drag.began:
            drag.received = fileDrops.received(d.files ?? [], folders: d.folders ?? [])
            drags[device] = drag
            guard !drag.received.isEmpty else { print("Live drag from \(name): no file arrived whole"); end(device, dropped: false); return }
            begin(device)
        case LiveDrag.move:
            drag.window = d.window; drag.x = d.x; drag.y = d.y
            drags[device] = drag
            if drag.began { follow(device, to: d) } else { pendingModifiers[device] = d.modifiers ?? 0 }
        case LiveDrag.drop:
            drag.window = d.window; drag.x = d.x; drag.y = d.y
            drag.dropWanted = true
            drags[device] = drag
            if drag.began { follow(device, to: d); release(device) }
            else { pendingModifiers[device] = d.modifiers ?? 0 }
        case LiveDrag.cancel:
            end(device, dropped: false)
        default:
            break
        }
    }

    /// Modifier keys asked for before this Mac's drag of the device's files began: pressed once it has.
    private var pendingModifiers: [KeyStrokes.Device: UInt64] = [:]

    func clientLeft(_ device: KeyStrokes.Device) {
        guard let drag = drags.removeValue(forKey: device) else { return }
        drag.watchdog?.cancel()
        pendingModifiers[device] = nil
        if !drag.own { discard(drag.received) }
    }

    // MARK: The drag

    /// The device's files are all here: this Mac's drag of them starts under the pointer, as a person's
    /// would (press on Sill's panel, move a little, the drag is under way), then goes to where the
    /// device's pointer is now.
    private func begin(_ device: KeyStrokes.Device) {
        guard let drag = drags[device], let rect = rect?(drag.window) else { end(device, dropped: false); return }
        let point = CGPoint(x: rect.minX + drag.x * rect.width, y: rect.minY + drag.y * rect.height)
        fileDrops.showPanel(for: drag.received, at: point)
        let x = drag.x, y = drag.y, nudge = 6 / max(rect.width, 1)
        let steps: [(Double, InputEvent?)] = [
            (0.05, .pointer(.move, x: x, y: y)),
            (0.10, .pointer(.leftDown, x: x, y: y)),
            (0.20, .pointer(.move, x: x + nudge, y: y + nudge)),
            (0.30, nil),   // the panel goes: the app under it is the drag's target from here
        ]
        for (after, event) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let self, self.drags[device]?.id == drag.id else { return }
                if case .pointer(.leftDown, _, _) = event { self.drags[device]?.pressed = true }
                if let event { self.deliver?(event, rect, device) } else { self.fileDrops.hidePanel() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, var now = self.drags[device], now.id == drag.id else { return }
            now.began = true
            self.drags[device] = now
            let mods = self.pendingModifiers.removeValue(forKey: device) ?? 0
            self.follow(device, to: LiveDrag(id: now.id, phase: LiveDrag.move, window: now.window, x: now.x, y: now.y, modifiers: mods))
            if now.dropWanted { self.release(device) }
        }
    }

    /// The pointer to where the device's is, over the window it names, the modifier keys as the
    /// device holds them.
    private func follow(_ device: KeyStrokes.Device, to d: LiveDrag) {
        guard var drag = drags[device], let rect = rect?(d.window) else { return }
        let wanted = (d.modifiers ?? 0) & Self.modifierMask
        if wanted != drag.modifiers {
            for (bit, usage) in Self.modifierKeys where (wanted & bit) != (drag.modifiers & bit) {
                deliver?(.key(hidUsage: usage, down: wanted & bit != 0, modifiers: wanted), rect, device)
            }
            drag.modifiers = wanted
            drags[device] = drag
        }
        deliver?(.pointer(.move, x: min(max(d.x, 0), 1), y: min(max(d.y, 0), 1)), rect, device)
    }

    /// Let go where the pointer is: the app there takes the drop.
    private func release(_ device: KeyStrokes.Device) {
        guard let drag = drags[device], let rect = rect?(drag.window) else { end(device, dropped: false); return }
        deliver?(.pointer(.leftUp, x: min(max(drag.x, 0), 1), y: min(max(drag.y, 0), 1)), rect, device)
        print("Live drag: dropped at \(drag.window.map { "window \($0)" } ?? "the streamed window") (\(Int(drag.x * 100))%, \(Int(drag.y * 100))%)")
        end(device, dropped: true)
    }

    /// The drag is over: let go of the modifier keys it pressed; one not dropped is given up (Esc, then
    /// the button), and the device's files it had received are removed.
    private func end(_ device: KeyStrokes.Device, dropped: Bool) {
        guard let drag = drags.removeValue(forKey: device) else { return }
        drag.watchdog?.cancel()
        pendingModifiers[device] = nil
        let rect = rect?(drag.window) ?? .null
        if !dropped && (drag.began || drag.pressed) {
            // A drag under way is cancelled (Esc) before the button lets go; a press that never became
            // one only lets go, with no Esc for whatever app is under it.
            if drag.began {
                deliver?(.key(hidUsage: 0x29, down: true, modifiers: drag.modifiers), rect, device)
                deliver?(.key(hidUsage: 0x29, down: false, modifiers: drag.modifiers), rect, device)
            }
            deliver?(.pointer(.leftUp, x: min(max(drag.x, 0), 1), y: min(max(drag.y, 0), 1)), rect, device)
        }
        for (bit, usage) in Self.modifierKeys where drag.modifiers & bit != 0 {
            deliver?(.key(hidUsage: usage, down: false, modifiers: 0), rect, device)
        }
        if drag.own { ownDragEnded?(device) }
        fileDrops.hidePanel()
        if !dropped {
            print("Live drag: given up")
            if !drag.own { discard(drag.received) }
        }
    }

    /// A part of the device's files arrived (kind 34): its drag is alive, however long they take.
    func heard(_ device: KeyStrokes.Device) {
        if drags[device] != nil { arm(device) }
    }

    private func arm(_ device: KeyStrokes.Device) {
        drags[device]?.watchdog?.cancel()
        guard let id = drags[device]?.id else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.drags[device]?.id == id else { return }
            print("Live drag: nothing heard for \(Int(Self.silence)) s; given up")
            self.end(device, dropped: false)
        }
        drags[device]?.watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.silence, execute: work)
    }

    /// The device's files received for a drag that never landed: removed (a moment later, so a drop
    /// that is still being taken is not robbed of them). Only files still where they arrived.
    private func discard(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for url in urls where FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
        }
    }
}
