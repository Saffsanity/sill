import Foundation
// In the app StreamProtocol is its own module; the ledger check (H2) compiles this file together
// with Sources/StreamProtocol/HostSettings.swift as one module, where there is nothing to import.
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// One of the six settings a device can change on the Mac.
enum SettingsField: CaseIterable, Hashable {
    case maxFPS, bitrate, captureScale, prioritizeSpeed, virtualDisplay, directWireless
}

extension HostSettingsChange {
    /// The setting fields this change names.
    var fields: [SettingsField] {
        var f: [SettingsField] = []
        if maxFPS != nil { f.append(.maxFPS) }
        if bitrate != nil { f.append(.bitrate) }
        if captureScale != nil { f.append(.captureScale) }
        if prioritizeSpeed != nil { f.append(.prioritizeSpeed) }
        if virtualDisplay != nil { f.append(.virtualDisplay) }
        if directWireless != nil { f.append(.directWireless) }
        return f
    }

    /// This change's value for `field` alone, without the token.
    func only(_ field: SettingsField) -> HostSettingsChange {
        switch field {
        case .maxFPS: HostSettingsChange(maxFPS: maxFPS)
        case .bitrate: HostSettingsChange(bitrate: bitrate)
        case .captureScale: HostSettingsChange(captureScale: captureScale)
        case .prioritizeSpeed: HostSettingsChange(prioritizeSpeed: prioritizeSpeed)
        case .virtualDisplay: HostSettingsChange(virtualDisplay: virtualDisplay)
        case .directWireless: HostSettingsChange(directWireless: directWireless)
        }
    }

    /// This change with `other`'s fields added (the token stays this one's).
    func adding(_ other: HostSettingsChange) -> HostSettingsChange {
        HostSettingsChange(token: token, maxFPS: other.maxFPS ?? maxFPS, bitrate: other.bitrate ?? bitrate,
                           captureScale: other.captureScale ?? captureScale,
                           prioritizeSpeed: other.prioritizeSpeed ?? prioritizeSpeed,
                           virtualDisplay: other.virtualDisplay ?? virtualDisplay,
                           directWireless: other.directWireless ?? directWireless)
    }
}

/// What the Settings panel shows: the Mac's last word on this connection with this device's
/// unanswered picks laid over it, field by field. Pure logic (no UIKit), so it is checked on its
/// own (H2 in docs/ipad-host-settings-plan.md).
///
/// The rules, each of which a model check exercised over thousands of random runs with two
/// devices, the Mac's menu, disconnects and slow hosts:
/// 1. No state on this connection (an older Mac, or not yet): `pick` sends nothing.
/// 2. A pick sends only the fields whose value differs from what is shown, so picking what is
///    shown sends nothing, and tapping back to the Mac's value while another pick for that field
///    is pending does send.
/// 3. Each sent field is held under the pick's token, replacing an older pick for that field.
/// 4. Broadcasts never clear a pick; an answer clears exactly the picks whose token it carries.
///    So a double tap 60 → 120 → 60 never shows 120: the answer to the first finds the field
///    held by the third.
/// 5. A cleared pick whose value differs from the answer's settings was refused: the control
///    goes back to the Mac's value and the caller tells the user.
/// 6. A pick unanswered for the timeout goes back to the Mac's value; a late answer or broadcast
///    still applies normally.
/// 7. Reset on every tear-down, and never persisted: a Mac's settings are only ever the ones it
///    sent on this connection.
/// 8. Nothing is sent on its own: only `pick`, called from a control's action, produces a change.
/// 9. A field this Mac did not report (nil in its state: an older host) is never sent, so an older
///    host is never asked for what it cannot show. A property of the model, not of the view.
struct SettingsLedger: Equatable {
    /// One field's unanswered pick. `change` names that field only.
    struct Entry: Equatable {
        var change: HostSettingsChange
        var token: Int
        var sentAt: Double
    }

    /// The last state on this connection, `answering` stripped; nil until the Mac has sent one.
    private(set) var host: HostSettingsState?
    /// The latest unanswered pick per field.
    private(set) var pending: [SettingsField: Entry] = [:]

    /// `host.settings` with every pending pick applied; nil while there is no state.
    var displayed: StreamSettings? {
        guard let h = host else { return nil }
        return pending.values.reduce(h.settings) { $1.change.applied(to: $0) }
    }

    /// When the pick for `field` was sent, while it waits for its answer (for the row's spinner).
    func pendingSince(_ field: SettingsField) -> Double? { pending[field]?.sentAt }

    /// A control changed `change`'s fields. Returns the message to send (carrying `token`), or nil
    /// when nothing should go out: no state yet, or every field already shows that value.
    mutating func pick(_ change: HostSettingsChange, token: Int, now: Double) -> HostSettingsChange? {
        guard let shown = displayed else { return nil }
        var out = HostSettingsChange(token: token)
        for field in change.fields {
            // Rule 9: applied(to:) would set the field anyway, and a nil differs from any value.
            if field == .directWireless, shown.directWireless == nil { continue }
            let single = change.only(field)
            guard single.applied(to: shown) != shown else { continue }
            pending[field] = Entry(change: single, token: token, sentAt: now)
            out = out.adding(single)
        }
        return out.isEmpty ? nil : out
    }

    /// A state arrived from the Mac. Returns the fields this answer refused (empty for a broadcast).
    mutating func receive(_ state: HostSettingsState) -> Set<SettingsField> {
        var s = state
        s.answering = nil
        host = s
        guard let token = state.answering else { return [] }
        var refused: Set<SettingsField> = []
        for (field, entry) in pending where entry.token == token {
            pending[field] = nil
            if entry.change.applied(to: s.settings) != s.settings { refused.insert(field) }
        }
        return refused
    }

    /// Drops the picks older than `timeout` seconds; true if any was dropped.
    mutating func expire(now: Double, timeout: Double) -> Bool {
        let before = pending.count
        pending = pending.filter { now - $0.value.sentAt <= timeout }
        return pending.count != before
    }

    /// The connection ended: nothing of it is kept.
    mutating func reset() {
        host = nil
        pending = [:]
    }
}
