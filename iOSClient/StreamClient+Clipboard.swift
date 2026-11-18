import Foundation
import UIKit
import UniformTypeIdentifiers
import StreamProtocol

/// A moment's line after a Paste: "Pasted on ‹Mac›.", "Sent to ‹Mac›’s clipboard…" or "Too long to
/// send…", under the chip's place and the Settings group's Paste.
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
// - Paste right away (2026-10-29): with Paste on ‹Mac› Right Away on, the receipt also presses ⌘V on
//   the Mac a moment later (ClipboardPolicy.pastesOnReceipt, `pasteDelay`), so the text lands where
//   its cursor is. iOS has no such way back: no app pastes into another, so the Mac's text waits on
//   this device's clipboard for the person to paste.
// - The subscription: an empty kind 32 once the Mac's list says it takes the clipboard and the switch
//   is on, again on a move's new connection; `stop` when the switch goes off.
// - Images (generation 2, docs/clipboard-plan.md "Generation 2"): with Include Images on (off unless
//   turned on) the subscription says `{"accepts":2}`, and while the Mac's list says 2 the Paste control
//   takes an image too (text wins), fitted off the main thread to 8 MB, 2 MB away from home
//   (ClipboardPolicy.imageCap); the chip lights for one; a Mac's image is written as its text is. A big
//   Paste says "Sending to ‹Mac›…" until its receipt, which waits for its bytes too.
//
// Everything here is main thread, but the decoding of the Mac's kind 32 (`clipboardDecoding`) and the
// Paste control's image fit (ClipboardPasteButton).
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

    /// This device's switch, Paste on ‹Mac› Right Away (the Settings panel's This iPad group, under
    /// Share Clipboard, while it is on): on unless turned off. With it on, a Paste's receipt also
    /// presses ⌘V on the Mac (ClipboardPolicy.pastesOnReceipt), and the chip and the panel say where the
    /// text goes. The device's own preference, never sent; read at each receipt.
    static let pasteRightAwayKey = "Sill.pasteRightAway"
    static var pasteRightAwayOn: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: pasteRightAwayKey) == nil || defaults.bool(forKey: pasteRightAwayKey)
    }

    /// This device's switch, Include Images (the Settings panel's This iPad group, under Paste on ‹Mac›
    /// Right Away, while Share Clipboard is on and the Mac says it takes images): off unless turned on (the
    /// evaluation of #300: new behaviour stays off until a person turns it on, and the cost falls here, on
    /// this device's link and data). On, the subscription says `{"accepts":2}` (a move of it subscribes
    /// again at once), Paste takes images and the chip lights for one. The device's own preference, never
    /// sent but as what the subscription says; read at each decision.
    static let clipboardImagesKey = "Sill.clipboardImages"
    static var clipboardImagesOn: Bool { UserDefaults.standard.bool(forKey: clipboardImagesKey) }

    /// The Mac's kind 32s are decoded here, one at a time and in order, never on the main thread or the
    /// connection's queue: an image's is up to 11 MB of JSON (#300's D7).
    static let clipboardDecoding = DispatchQueue(label: "sill.clipboard.decode", qos: .userInitiated)

    /// Whether this session counts as away from home, for the cap an image is fitted to
    /// (ClipboardPolicy.imageCap): the Mac's word on this connection (its settings state's `away`), else
    /// the route a remote session took (a VPN or the internet; by address is home, as AwayPolicy has it).
    var clipboardAway: Bool {
        if let away = settings.host?.away { return away.thisConnectionAway }
        if case .remote(let r)? = session?.route { return r != .address }
        return false
    }

    /// How long after the receipt ⌘V goes: ClipboardPolicy.pasteDelay. DEBUG `-SillPasteDelay <s>`
    /// another (0: right behind the receipt), for the race docs/clipboard-plan.md measures.
    static var pasteDelay: Double {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "SillPasteDelay") != nil { return max(0, defaults.double(forKey: "SillPasteDelay")) }
        #endif
        return ClipboardPolicy.pasteDelay
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
        let images = Self.clipboardImagesOn
        let step = ClipboardPolicy.deviceSubscription(hostClipboard: hostClipboard, switchOn: Self.clipboardOn,
                                                      subscribed: clipboardSubscribed, imagesOn: images,
                                                      subscribedImages: clipboardSubscribedImages)
        clipboardSubscribed = step.subscribed
        switch step.send {
        case .subscribe:
            send(.clipboard, payload: ClipboardPolicy.subscription(images: images))
            clipboardSubscribedImages = images
            #if DEBUG
            print("clipboard: subscribed" + (images ? ", taking images" : ""))
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

    /// Include Images moved: the subscription says so at once; off, a chip offered for an image goes (one
    /// for text comes back at the next look), on, the chip looks again.
    func clipboardImagesSwitchChanged() {
        updateClipboardSubscription()
        if Self.clipboardImagesOn {
            lookAtClipboard(why: "Include Images turned on")
        } else {
            hideClipboardChip()
            lookAtClipboard(why: "Include Images turned off")
        }
    }

    /// A move handed the session to its new connection (`finishMove`): the Mac keeps subscriptions per
    /// connection, so the new one subscribes.
    func clipboardMoved() {
        clipboardSubscribed = false
        clipboardSubscribedImages = false
        updateClipboardSubscription()
    }

    /// The session ended: nothing of it is kept but the handled count.
    func resetClipboard() {
        hostClipboard = nil
        clipboardSubscribed = false
        clipboardSubscribedImages = false
        clipboardSent = nil
        clipboardReceipt = nil
        clipboardReceiptExpiry?.cancel()
        clipboardReceiptExpiry = nil
        clipboardPasteWork?.cancel()        // a ⌘V for this session never goes to the next
        clipboardPasteWork = nil
        hideClipboardChip()
        // The next stream screen says again whether the chip shows (its onChange starts from this).
        clipboardChipOnScreen = false
        clipboardNoteExpiry?.cancel()
        clipboardNoteExpiry = nil
        clipboardNote = nil
    }

    // MARK: The Mac's text and images

    /// A kind 32 from the Mac, decoded (`clipboardDecoding`; nil: it did not decode).
    func receiveClipboard(_ clip: Clipboard?) {
        // While the picture shows only in Picture in Picture (#291), the person is in another app: the Mac's copy
        // would replace what they copy there. Dropped, as before Picture in Picture, when Sill was suspended
        // in the background and none came (PictureInPicturePolicy.onlyInPictureInPicture).
        if shownOnlyInPictureInPicture {
            #if DEBUG
            print("clipboard: a copy from the Mac not written: the picture shows only in Picture in Picture")
            #endif
            return
        }
        let board = UIPasteboard.general
        let options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true, .expirationDate: Date().addingTimeInterval(ClipboardPolicy.deviceExpiry)]
        let wrote: String
        if let text = ClipboardPolicy.deviceWrites(clip, switchOn: Self.clipboardOn, hostClipboard: hostClipboard,
                                                   lastSent: clipboardSent, changeCount: board.changeCount) {
            board.setItems([[UTType.utf8PlainText.identifier: text]], options: options)
            wrote = "\(text.utf8.count) bytes of text"
        } else if let image = ClipboardPolicy.deviceWritesImage(clip, switchOn: Self.clipboardOn, imagesOn: Self.clipboardImagesOn,
                                                                hostClipboard: hostClipboard),
                  let type = Clipboard.imageType(image) {
            board.setItems([[type: image]], options: options)
            wrote = "an image of \(image.count) bytes (\(type))"
        } else {
            return
        }
        clipboardHandled = board.changeCount
        hideClipboardChip()
        #if DEBUG
        print("clipboard: wrote \(wrote) from the Mac (change \(board.changeCount))")
        #else
        _ = wrote
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
        let images = Self.clipboardImagesOn
        let offer = !waiting && ClipboardPolicy.offersChip(connected: connected, hostClipboard: hostClipboard, switchOn: Self.clipboardOn,
                                                           hasStrings: board.hasStrings, changeCount: count, handled: clipboardHandled,
                                                           hasImages: images && board.hasImages, imagesOn: images)
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
        sendClipboard(ClipboardPolicy.deviceSends(strings, connected: connected, hostClipboard: hostClipboard, switchOn: Self.clipboardOn),
                      text: strings.first(where: { !$0.isEmpty }), tooLong: ClipboardPolicy.Copy.tooLong)
    }

    /// An image the Paste control read, as ClipboardImage.fitted made it for `away` (the session's when the
    /// Paste was tapped), to a Mac that takes images; nil, it could not be read (#300's D11: that said
    /// "Too big to send…").
    func sendClipboardImage(_ image: Data?, away: Bool) {
        guard let image else {
            guard ClipboardPolicy.deviceOffersImages(imagesOn: Self.clipboardImagesOn, hostClipboard: hostClipboard), Self.clipboardOn else { return }
            showClipboardNote(ClipboardPolicy.Copy.imageUnreadable, spoken: ClipboardPolicy.Copy.imageUnreadable, warning: true)
            if UIDevice.current.userInterfaceIdiom == .phone { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            return
        }
        let send = ClipboardPolicy.deviceSendsImage(image, connected: connected, hostClipboard: hostClipboard, switchOn: Self.clipboardOn,
                                                    imagesOn: Self.clipboardImagesOn, away: away)
        sendClipboard(send, text: nil, tooLong: { ClipboardPolicy.Copy.imageTooBig(mac: $0, away: away) })
    }

    private func sendClipboard(_ decision: ClipboardPolicy.DeviceSend, text: String?, tooLong: (String) -> String) {
        let mac = macName.isEmpty ? "the Mac" : macName
        switch decision {
        case .send(let payload):
            send(.clipboard, payload: payload)
            // Its receipt: a ping after it through the same door, whose pong says the Mac has read it.
            // Until then nothing says it was sent, and the copy is not dealt with.
            let nonce = Data((0..<ClipboardPolicy.receiptLength).map { _ in UInt8.random(in: .min ... .max) })
            send(.ping, payload: nonce)
            let count = UIPasteboard.general.changeCount
            if let text { clipboardSent = ClipboardPolicy.Sent(text: text, changeCount: count) }
            clipboardReceipt = ClipboardReceipt(nonce: nonce, changeCount: count)
            hideClipboardChip()
            clipboardReceiptExpiry?.cancel()
            // Its bytes count too: an image's 11 MB of JSON is seconds on most uplinks (#300's D5).
            let wait = ClipboardPolicy.receiptWait(worstRttMs: lastRttMaxMs, bytes: payload.count)
            let work = DispatchWorkItem { [weak self] in self?.clipboardReceiptLate() }
            clipboardReceiptExpiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
            // A big one says so until its receipt or its time comes, never a silence.
            if ClipboardPolicy.showsSending(bytes: payload.count) {
                showClipboardNote(ClipboardPolicy.Copy.sending(mac: mac), spoken: ClipboardPolicy.Copy.sendingSpoken(mac: mac),
                                  warning: false, lasts: nil)
            }
            #if DEBUG
            print("clipboard: sent \(payload.count) bytes of JSON to the Mac (change \(count)), its receipt awaited for \(wait) s")
            #endif
        case .tooLong:
            showClipboardNote(tooLong(mac), spoken: tooLong(mac), warning: true)
            if UIDevice.current.userInterfaceIdiom == .phone { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        case .nothing:
            break
        }
    }

    /// A receipt's pong (StreamClient.handle): the Mac has read the text, and the copy is dealt with.
    /// With Paste on ‹Mac› Right Away on, ⌘V follows (`pasteOnMac`) and the note says "Pasted on
    /// ‹Mac›."; else "Sent…". One that comes after its time ran out still counts, and presses nothing
    /// (ClipboardPolicy.pastesOnReceipt).
    func clipboardReceiptCame(_ payload: Data) {
        guard let receipt = clipboardReceipt, receipt.nonce == payload else { return }
        clipboardReceiptExpiry?.cancel()
        clipboardReceiptExpiry = nil
        clipboardReceipt = nil
        clipboardHandled = receipt.changeCount
        hideClipboardChip()
        #if DEBUG
        print("clipboard: the Mac has read it (its receipt" + (receipt.late ? ", after its time ran out)" : ")"))
        #endif
        guard pastesNow(late: receipt.late) else { receiptNoted(pasted: false); return }
        pasteOnMac()
    }

    /// Whether ⌘V goes now (ClipboardPolicy.pastesOnReceipt: the switch, a receipt in time, something
    /// streaming, the Mac still sharing its clipboard, and never while the tour shows, which keeps
    /// every input from the Mac).
    private func pastesNow(late: Bool) -> Bool {
        let pastes = ClipboardPolicy.pastesOnReceipt(rightAway: Self.pasteRightAwayOn, late: late, streaming: active != .none,
                                                     hostClipboard: hostClipboard, tourShows: inputPaused)
        #if DEBUG
        if !pastes {
            print("clipboard: no ⌘V: " + (!Self.pasteRightAwayOn ? "Paste on the Mac Right Away is off"
                : late ? "the receipt came after its time ran out" : active == .none ? "nothing streams"
                : !ClipboardPolicy.hostTakes(hostClipboard) ? "the Mac no longer shares its clipboard" : "the tour shows"))
        }
        #endif
        return pastes
    }

    /// ⌘V on the Mac, `pasteDelay` after the receipt (the Mac writes the text to its pasteboard on a
    /// queue of its own once it has read it; a ⌘V right behind the receipt could paste what was there
    /// before), as a keyboard sends it (KeyChord.paste, so nothing stays held there), keeping what the
    /// pointer sprite shows as a key of the portrait key row does (`sendFromKeyRow`): a paste moves no
    /// pointer. Then the note, "Pasted on ‹Mac›.", or "Sent…" when the session lost what streams
    /// meanwhile; the session's end cancels both (`resetClipboard`).
    private func pasteOnMac() {
        clipboardPasteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.clipboardPasteWork = nil
            guard self.connected, self.pastesNow(late: false) else { self.receiptNoted(pasted: false); return }
            KeyChord.paste.forEach(self.sendFromKeyRow)
            #if DEBUG
            print("clipboard: ⌘V sent to the Mac")
            #endif
            self.receiptNoted(pasted: true)
        }
        clipboardPasteWork = work
        let delay = Self.pasteDelay
        #if DEBUG
        print(String(format: "clipboard: ⌘V in %.3f s", delay))
        #endif
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) } else { work.perform() }
    }

    /// A receipt's note and, on an iPhone, the success haptic.
    private func receiptNoted(pasted: Bool) {
        let note = ClipboardPolicy.receiptNote(pasted: pasted, mac: macName.isEmpty ? "the Mac" : macName)
        showClipboardNote(note.text, spoken: note.spoken, warning: false)
        if UIDevice.current.userInterfaceIdiom == .phone { UINotificationFeedbackGenerator().notificationOccurred(.success) }
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

    /// A note in the chip's place and under the Settings group's Paste, for `lasts` seconds (nil: until the
    /// next note, "Sending to ‹Mac›…" until its receipt or "Didn’t reach…").
    func showClipboardNote(_ text: String, spoken: String, warning: Bool, lasts: Double? = ClipboardPolicy.noteLifetime) {
        #if DEBUG
        print("clipboard: the note: \(text)")
        #endif
        clipboardNote = ClipboardNote(text: text, spoken: spoken, warning: warning, at: uptime)
        UIAccessibility.post(notification: .announcement, argument: spoken)
        clipboardNoteExpiry?.cancel()
        clipboardNoteExpiry = nil
        guard let lasts else { return }
        let work = DispatchWorkItem { [weak self] in self?.clipboardNote = nil }
        clipboardNoteExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lasts, execute: work)
    }
}
