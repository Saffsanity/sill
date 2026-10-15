import Foundation
import UIKit
import UniformTypeIdentifiers
import StreamProtocol

/// A moment's line after a Paste: "Sent to ‹Mac›’s clipboard…" or "Too long to send…", under the
/// chip's place and the Settings group's Paste.
struct ClipboardNote: Equatable {
    var text: String
    var spoken: String
    var warning: Bool
    /// When it came (systemUptime): two of the same words in a row are two notes.
    var at: TimeInterval
}

/// A Paste waiting for its receipt (ClipboardPolicy.receiptLength): the ping sent after the text, whose
/// pong says the Mac has read it.
struct ClipboardReceipt: Equatable {
    /// The receipt ping's payload, random.
    let nonce: Data
    /// This device's clipboard's change count when the text went: dealt with once the Mac has it.
    let changeCount: Int
    /// Its time ran out ("Didn’t reach…" shown, the chip offered again); a receipt that comes later
    /// still counts.
    var late = false
}

// The clipboard, this device's side (kind 32; docs/clipboard-plan.md). ClipboardPolicy has the rules;
// this reads and writes UIPasteboard and keeps the session's state.
//
// - The Mac's text: written with `.localOnly` (Universal Clipboard does not carry it back to the Mac)
//   and a 10-minute expiration, while the switch is on; its change count becomes the handled one, so
//   the chip never offers the Mac's own text back.
// - This device's text: Sill never reads the clipboard by itself (iOS would ask "Allow Paste?"). It
//   reads only `changeCount` and `hasStrings`, which never ask, to offer the chip; the text is read
//   by the system's Paste control (UIPasteControl, SwiftUI's PasteButton) when the person taps it,
//   and counts as sent only once the Mac has read it (a ping after it comes back: the receipt).
// - The subscription: an empty kind 32 once the Mac's list says it takes the clipboard and the switch
//   is on, again on a move's new connection; `stop` when the switch goes off.
//
// Everything here is main thread.
extension StreamClient {
    /// This device's switch, Share Clipboard (the Settings panel's This iPad group): on unless turned
    /// off. The device's own preference, never sent; read at each decision.
    static let clipboardKey = "Sill.shareClipboard"
    static var clipboardOn: Bool {
        // `bool(forKey:)`, not `as? Bool`: a launch argument's "0" is a string, which it reads as
        // @AppStorage does, so the switch and the panel always agree.
        let defaults = UserDefaults.standard
        return defaults.object(forKey: clipboardKey) == nil || defaults.bool(forKey: clipboardKey)
    }

    /// The clipboard's change count Sill last handled (sent, written from the Mac, the chip dismissed
    /// or timed out), kept across launches so a relaunch does not offer old text again.
    static let clipboardHandledKey = "Sill.clipboardHandled"
    var clipboardHandled: Int? {
        get { UserDefaults.standard.object(forKey: Self.clipboardHandledKey) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: Self.clipboardHandledKey) }
    }

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Sill becoming active (and a scene of it) is when the chip looks; Sill no longer active, and
    /// VoiceOver turning on or off, stop or start the chip's time (`updateClipboardChipClock`). From init.
    func observeClipboardActivation() {
        let center = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.clipboardBecameActive()
            }
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.clipboardAppActive = false
            self.updateClipboardChipClock()
        }
        center.addObserver(forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateClipboardChipClock()
        }
    }

    // MARK: The subscription

    /// Each window list's `clipboard`: the subscription follows it, and a session that starts soon
    /// after Sill became active gets the chip's look then.
    func hostClipboardChanged(_ value: Int?) {
        let took = ClipboardPolicy.hostTakes(hostClipboard)
        if hostClipboard != value { hostClipboard = value }
        updateClipboardSubscription()
        let takes = ClipboardPolicy.hostTakes(value)
        if !takes { hideClipboardChip() }
        if !took, takes, ClipboardPolicy.looksAtSessionStart(activatedAt: clipboardActivatedAt, now: uptime) {
            lookAtClipboard(why: "the session started")
        }
    }

    /// Subscribes or stops as ClipboardPolicy says for the Mac's word, the switch and this connection.
    func updateClipboardSubscription() {
        let step = ClipboardPolicy.deviceSubscription(hostClipboard: hostClipboard, switchOn: Self.clipboardOn,
                                                      subscribed: clipboardSubscribed)
        clipboardSubscribed = step.subscribed
        switch step.send {
        case .subscribe:
            send(.clipboard, payload: ClipboardPolicy.subscription)
            #if DEBUG
            print("clipboard: subscribed")
            #endif
        case .stop:
            send(.clipboard, payload: ClipboardPolicy.stopping)
            #if DEBUG
            print("clipboard: stopped")
            #endif
        case .none:
            break
        }
    }

    /// The Settings group's switch moved.
    func clipboardSwitchChanged() {
        updateClipboardSubscription()
        if !Self.clipboardOn { hideClipboardChip() }
    }

    /// A move handed the session to its new connection (`finishMove`): the Mac keeps subscriptions per
    /// connection, so the new one subscribes.
    func clipboardMoved() {
        clipboardSubscribed = false
        updateClipboardSubscription()
    }

    /// The session ended: nothing of it is kept but the handled count.
    func resetClipboard() {
        hostClipboard = nil
        clipboardSubscribed = false
        clipboardSent = nil
        clipboardReceipt = nil
        clipboardReceiptExpiry?.cancel()
        clipboardReceiptExpiry = nil
        hideClipboardChip()
        // The next stream screen says again whether the chip shows (its onChange starts from this).
        clipboardChipOnScreen = false
        clipboardNoteExpiry?.cancel()
        clipboardNoteExpiry = nil
        clipboardNote = nil
    }

    // MARK: The Mac's text

    /// A kind 32 from the Mac.
    func receiveClipboard(_ payload: Data) {
        let board = UIPasteboard.general
        guard let text = ClipboardPolicy.deviceWrites(payload, switchOn: Self.clipboardOn, hostClipboard: hostClipboard,
                                                      lastSent: clipboardSent, changeCount: board.changeCount) else { return }
        board.setItems([[UTType.utf8PlainText.identifier: text]],
                       options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(ClipboardPolicy.deviceExpiry)])
        clipboardHandled = board.changeCount
        hideClipboardChip()
        #if DEBUG
        print("clipboard: wrote \(text.utf8.count) bytes from the Mac (change \(board.changeCount))")
        #endif
    }

    // MARK: The chip

    /// Sill became active: the chip's time runs again if it shows, and the chip looks now, or at the
    /// session's start soon after (`hostClipboardChanged`).
    func clipboardBecameActive() {
        clipboardAppActive = true
        updateClipboardChipClock()
        // The app's and its scene's notifications come together: one look.
        if let last = clipboardActivatedAt, uptime - last < 0.5 { return }
        clipboardActivatedAt = uptime
        guard ClipboardPolicy.hostTakes(hostClipboard) else { return }
        lookAtClipboard(why: "Sill became active")
    }

    /// Offers the chip when ClipboardPolicy says; reads only the change count and whether there is text.
    func lookAtClipboard(why: String) {
        #if DEBUG
        // The harness's mock Mac: the chip only by `-SillClipboardChip 1`, whatever the simulator's
        // clipboard holds, so its photos never depend on it.
        if mockDiscovery { return }
        #endif
        let board = UIPasteboard.general
        let count = board.changeCount
        // Not while a Paste waits for its receipt: the chip comes back if it never comes.
        let waiting = clipboardReceipt.map { !$0.late } ?? false
        let offer = !waiting && ClipboardPolicy.offersChip(connected: connected, hostClipboard: hostClipboard, switchOn: Self.clipboardOn,
                                                           hasStrings: board.hasStrings, changeCount: count, handled: clipboardHandled)
        #if DEBUG
        print("clipboard: \(why): change \(count), handled \(clipboardHandled.map(String.init) ?? "none")"
              + (waiting ? ", a Paste waiting for its receipt" : "") + ": \(offer ? "the chip" : "no chip")")
        #endif
        guard offer, !clipboardChip else { return }
        clipboardChip = true
        clipboardChipShownFor = 0
        clipboardChipAnnounced = false
        updateClipboardChipClock()
    }

    /// The stream screen says whether the chip itself is on screen (StreamScreen.clipboardChipOnScreen):
    /// its time runs only then, and VoiceOver is told the first time it shows for a copy.
    func clipboardChipShown(_ onScreen: Bool) {
        guard onScreen != clipboardChipOnScreen else { return }
        clipboardChipOnScreen = onScreen
        if onScreen, clipboardChip, !clipboardChipAnnounced {
            clipboardChipAnnounced = true
            let mac = macName.isEmpty ? "the Mac" : macName
            UIAccessibility.post(notification: .announcement, argument: ClipboardPolicy.Copy.chipAnnouncement(mac: mac))
            #if DEBUG
            print("clipboard: the chip shows; VoiceOver told")
            #endif
        }
        updateClipboardChipClock()
    }

    /// The chip's `chipLifetime`, counted only while ClipboardPolicy.chipCounts says (on screen, Sill
    /// active, VoiceOver off), from what it has spent so far; at its end the copy is dealt with.
    func updateClipboardChipClock() {
        let now = uptime
        if let since = clipboardChipCountingSince {
            clipboardChipShownFor += now - since
            clipboardChipCountingSince = nil
        }
        clipboardChipExpiry?.cancel()
        clipboardChipExpiry = nil
        guard clipboardChip else { return }
        #if DEBUG
        if mockDiscovery { return }      // the harness's chip stays
        #endif
        let counts = ClipboardPolicy.chipCounts(onScreen: clipboardChipOnScreen, active: clipboardAppActive,
                                                voiceOver: HostSettingsPanel.voiceOverRunning)
        let left = ClipboardPolicy.chipLifetime - clipboardChipShownFor
        #if DEBUG
        print("clipboard: the chip's time " + (counts ? "runs" : "waits") + String(format: ", %.1f s left", max(0, left)))
        #endif
        guard counts else { return }
        guard left > 0 else { dismissClipboardChip(); return }
        clipboardChipCountingSince = now
        let work = DispatchWorkItem { [weak self] in
            #if DEBUG
            print("clipboard: the chip's time is up")
            #endif
            self?.dismissClipboardChip()
        }
        clipboardChipExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + left, execute: work)
    }

    /// Dismiss, or its time on screen was up: handled for this change count.
    func dismissClipboardChip() {
        guard clipboardChip else { return }
        clipboardHandled = UIPasteboard.general.changeCount
        hideClipboardChip()
    }

    func hideClipboardChip() {
        clipboardChipExpiry?.cancel()
        clipboardChipExpiry = nil
        clipboardChipCountingSince = nil
        if clipboardChip { clipboardChip = false }
    }

    // MARK: Paste on the Mac

    /// What the system's Paste control read on the person's tap (the chip's, or the Settings group's):
    /// sent to the Mac, with its receipt to wait for, or "too long".
    func sendClipboard(_ strings: [String]) {
        let mac = macName.isEmpty ? "the Mac" : macName
        switch ClipboardPolicy.deviceSends(strings, connected: connected, hostClipboard: hostClipboard, switchOn: Self.clipboardOn) {
        case .send(let payload):
            send(.clipboard, payload: payload)
            // Its receipt: a ping after it through the same door, whose pong says the Mac has read it.
            // Until then nothing says it was sent, and the copy is not dealt with.
            let nonce = Data((0..<ClipboardPolicy.receiptLength).map { _ in UInt8.random(in: .min ... .max) })
            send(.ping, payload: nonce)
            let count = UIPasteboard.general.changeCount
            if let text = strings.first(where: { !$0.isEmpty }) { clipboardSent = ClipboardPolicy.Sent(text: text, changeCount: count) }
            clipboardReceipt = ClipboardReceipt(nonce: nonce, changeCount: count)
            hideClipboardChip()
            clipboardReceiptExpiry?.cancel()
            let wait = ClipboardPolicy.receiptWait(worstRttMs: lastRttMaxMs)
            let work = DispatchWorkItem { [weak self] in self?.clipboardReceiptLate() }
            clipboardReceiptExpiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
            #if DEBUG
            print("clipboard: sent \(payload.count) bytes of JSON to the Mac (change \(count)), its receipt awaited for \(wait) s")
            #endif
        case .tooLong:
            showClipboardNote(ClipboardPolicy.Copy.tooLong(mac: mac), spoken: ClipboardPolicy.Copy.tooLong(mac: mac), warning: true)
            if UIDevice.current.userInterfaceIdiom == .phone { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        case .nothing:
            break
        }
    }

    /// A receipt's pong (StreamClient.handle): the Mac has read the text. "Sent…", and the copy is dealt
    /// with. One that comes after its time ran out still counts.
    func clipboardReceiptCame(_ payload: Data) {
        guard let receipt = clipboardReceipt, receipt.nonce == payload else { return }
        clipboardReceiptExpiry?.cancel()
        clipboardReceiptExpiry = nil
        clipboardReceipt = nil
        clipboardHandled = receipt.changeCount
        hideClipboardChip()
        let mac = macName.isEmpty ? "the Mac" : macName
        showClipboardNote(ClipboardPolicy.Copy.sent(mac: mac), spoken: ClipboardPolicy.Copy.sentSpoken(mac: mac), warning: false)
        if UIDevice.current.userInterfaceIdiom == .phone { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        #if DEBUG
        print("clipboard: the Mac has read it (its receipt" + (receipt.late ? ", after its time ran out)" : ")"))
        #endif
    }

    /// No receipt in time: "Didn’t reach…", and the copy not dealt with, so the chip offers it again (once
    /// the note has gone) while the session lasts, and at the next look after.
    private func clipboardReceiptLate() {
        clipboardReceiptExpiry = nil
        guard var receipt = clipboardReceipt, !receipt.late else { return }
        receipt.late = true
        clipboardReceipt = receipt
        let mac = macName.isEmpty ? "the Mac" : macName
        showClipboardNote(ClipboardPolicy.Copy.notSent(mac: mac), spoken: ClipboardPolicy.Copy.notSent(mac: mac), warning: true)
        if UIDevice.current.userInterfaceIdiom == .phone { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        #if DEBUG
        print("clipboard: no receipt in time: did not reach the Mac")
        #endif
        lookAtClipboard(why: "a Paste did not reach the Mac")
    }

    func showClipboardNote(_ text: String, spoken: String, warning: Bool) {
        clipboardNote = ClipboardNote(text: text, spoken: spoken, warning: warning, at: uptime)
        UIAccessibility.post(notification: .announcement, argument: spoken)
        clipboardNoteExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clipboardNote = nil }
        clipboardNoteExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ClipboardPolicy.noteLifetime, execute: work)
    }
}
