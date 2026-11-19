import AVFAudio
import Foundation
import StreamProtocol
import UIKit

// MARK: - This device's microphone as Sill Microphone on the Mac (docs/microphone-plan.md §3.3, §3.5)
//
// The glue between MicrophonePolicy's device rule and what reads the microphone: each change that bears on it
// (the switch, the permission, the Mac's list and kind 16, this window in front or not and chosen or not, a call)
// runs `microphoneUpdate`, which steps this connection's DeviceLink (the offers, the claim, the end) and starts or
// stops the recording (MicrophoneCapture, and the window's sound engine in its voice mode). The switch is the
// app's (MicrophoneSwitch), off at every launch; the window it records from is MicrophoneHub's choice.

/// Share Microphone: the app's one switch, off at every launch, kept through reconnects and moves while Sill runs
/// and never stored (the plan's open question 5); the microphone's permission as iOS reports it; and whether the
/// person's turning it on still owes the Mac a claim. Main thread.
final class MicrophoneSwitch: ObservableObject {
    static let shared = MicrophoneSwitch()
    static let changed = Notification.Name("SillMicrophoneSwitchChanged")

    @Published private(set) var on = false
    @Published private(set) var permission: MicrophonePolicy.Permission
    /// The person turned the switch on and no offer has gone since: the next one claims the Mac's microphone.
    private(set) var claimOwed = false
    /// The permission is being asked: the switch shows on meanwhile.
    @Published private(set) var asking = false

    private init() {
        permission = Self.readPermission()
        #if DEBUG
        // `-SillMicPermission granted|denied`: the permission as if iOS said it, with no prompt (the harness).
        switch UserDefaults.standard.string(forKey: "SillMicPermission") {
        case "granted"?: permission = .granted
        case "denied"?: permission = .denied
        default: break
        }
        // `-SillMicOn 1`: the switch on at launch, as if the person had turned it on.
        if UserDefaults.standard.bool(forKey: "SillMicOn"), permission == .granted { on = true; claimOwed = true }
        #endif
    }

    static func readPermission() -> MicrophonePolicy.Permission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    /// The row's switch. On: asks for the permission the first time (only here, never at launch or at a
    /// connection: the plan's rule 4); refused, it goes back off and the row says why with a button to Settings.
    func set(_ wanted: Bool) {
        guard wanted != on || asking else { return }
        if !wanted {
            on = false; claimOwed = false; asking = false
            announce()
            return
        }
        #if DEBUG
        let standIn = UserDefaults.standard.string(forKey: "SillMicPermission") != nil
        #else
        let standIn = false
        #endif
        if !standIn { permission = Self.readPermission() }
        switch permission {
        case .granted:
            on = true; claimOwed = true
            announce()
        case .denied:
            on = false
            announce()
        case .undetermined:
            asking = true
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { [self] in
                    asking = false
                    permission = granted ? .granted : .denied
                    on = granted
                    claimOwed = granted
                    #if DEBUG
                    print("mic: the permission \(granted ? "granted" : "refused")")
                    #endif
                    announce()
                }
            }
        }
    }

    /// The claim went with an offer.
    func claimSpent() { claimOwed = false }

    #if DEBUG
    /// The harness's photos (`-SillMicCase`): the switch and the permission as the case has them, nothing asked.
    func debugSet(on: Bool, permission: MicrophonePolicy.Permission) {
        self.permission = permission
        self.on = on && permission == .granted
        claimOwed = false
        announce()
    }
    #endif

    /// Sill came back to the front: the permission may have changed in Settings meanwhile.
    func reread() {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "SillMicPermission") != nil { return }
        #endif
        let p = Self.readPermission()
        guard p != permission else { return }
        permission = p
        if p == .denied, on { on = false; claimOwed = false }
        announce()
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

/// Which of Sill's windows the microphone goes from (MicrophonePolicy.chosen: the one used last among those in
/// front whose Mac takes it), so two Macs never both get it and one session never has two engines; and each
/// window told when anything bearing on its microphone changed. One per process, as PictureInPictureHub is.
/// Main thread.
final class MicrophoneHub {
    static let shared = MicrophoneHub()
    #if DEBUG
    /// The harness's photos (`-SillMicCase window|noinput`): every window hears that another sends the microphone,
    /// or that no microphone is there.
    static var debugOtherWindow = false
    static var debugNoInput = false
    #endif

    private struct Entry {
        weak var client: StreamClient?
        weak var window: UIWindow?
        let id: Int
        var frontSince: Double?
    }
    private var entries: [Entry] = []
    private var nextID = 1
    private var chosen: Int?
    private var observers: [NSObjectProtocol] = []

    private init() {
        for name in [UIScene.willConnectNotification, UIScene.didDisconnectNotification, UIScene.didActivateNotification,
                     UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.update() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: MicrophoneSwitch.changed, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MicrophoneSwitch.shared.reread()
            self?.update()
        })
    }

    /// A session's screen moved into `window` (nil: out of every window).
    func session(_ client: StreamClient, window: UIWindow?) {
        let kept = entries.first { $0.client === client }
        entries.removeAll { $0.client == nil || $0.client === client }
        if let window {
            let id: Int
            if let kept { id = kept.id } else { id = nextID; nextID += 1 }
            entries.append(Entry(client: client, window: window, id: id, frontSince: kept?.window === window ? kept?.frontSince : nil))
        } else {
            client.microphoneChosen(false, otherWindow: false)
        }
        update()
    }

    /// The person used `client`'s window: with several windows the choice may move to it.
    func used(_ client: StreamClient) {
        guard entries.count > 1, let entry = entries.first(where: { $0.client === client }), entry.id != chosen else { return }
        update()
    }

    /// Lists the windows afresh, chooses, and tells each whether it is the one.
    func update() {
        let now = ProcessInfo.processInfo.systemUptime
        entries.removeAll { $0.client == nil || $0.window == nil }
        var windows: [MicrophonePolicy.Window] = []
        for i in entries.indices {
            guard let client = entries[i].client, let window = entries[i].window else { continue }
            let front = window.windowScene?.activationState == .foregroundActive
            if !front { entries[i].frontSince = nil } else if entries[i].frontSince == nil { entries[i].frontSince = now }
            let used = DeviceIdlePolicy.lastUse(.init(input: client.lastPersonInputAt, control: client.lastActionAt,
                                                      session: client.personSessionAt, front: entries[i].frontSince))
            windows.append(MicrophonePolicy.Window(id: entries[i].id, foregroundActive: front,
                                                   takes: MicrophonePolicy.macTakes(client.microphoneInputs), lastUsedAt: used))
        }
        #if DEBUG
        let was = chosen
        #endif
        chosen = MicrophonePolicy.chosen(windows, previous: chosen)
        #if DEBUG
        if chosen != was, entries.count > 1 { print("mic: window \(chosen.map(String.init) ?? "none") of \(entries.count) sends the microphone") }
        #endif
        let anyChosen = chosen != nil
        for entry in entries {
            // A window the hub never saw (the mock, a session not on screen yet) counts as chosen: it is alone.
            var other = anyChosen && entry.id != chosen
            #if DEBUG
            if Self.debugOtherWindow { other = true }
            #endif
            entry.client?.microphoneChosen(entry.id == chosen || !anyChosen && entries.count == 1, otherWindow: other)
        }
    }
}

extension StreamClient {
    /// The device rule's inputs as this session has them now (MicrophonePolicy.Device). Main thread.
    var microphoneInputs: MicrophonePolicy.Device {
        var d = MicrophonePolicy.Device()
        let sw = MicrophoneSwitch.shared
        d.switchOn = sw.on
        d.permission = sw.permission
        d.connected = connected
        d.list = hostMicrophone
        d.locked = lockWhy != nil
        d.state = micState
        d.foreground = sceneInFront
        d.chosen = micChosen
        d.interrupted = micInterrupted
        d.inputAvailable = MicrophoneCapture.source == .tone || AVAudioSession.sharedInstance().isInputAvailable
        #if DEBUG
        if MicrophoneHub.debugNoInput { d.inputAvailable = false }
        if MicrophoneHub.debugOtherWindow { d.chosen = false }
        #endif
        return d
    }

    /// The hub's word, at each look (a scene in front or not, the switch, a window used): this window is the one
    /// the microphone goes from, or another window of Sill's is. The rule steps every time, since a scene leaving
    /// the front changes no choice but stops the recording.
    func microphoneChosen(_ chosen: Bool, otherWindow: Bool) {
        if micChosen != chosen { micChosen = chosen }
        if micOtherWindow != otherWindow { micOtherWindow = otherWindow }
        microphoneUpdate()
    }

    /// Each window list's `microphone` and `locked`.
    func hostMicrophoneChanged(_ value: Int?) {
        if hostMicrophone != value { hostMicrophone = value }
        MicrophoneHub.shared.update()
        microphoneUpdate()
    }

    /// Each kind 16's `microphone` (nil from a Mac without one, and while the Mac is locked).
    func microphoneStateChanged(_ state: MicrophoneState?) {
        #if DEBUG
        if micState != state { print("mic: the Mac says \(state.map { $0.state + ($0.device.map { " (\($0))" } ?? "") } ?? "nothing")") }
        #endif
        if micState != state { micState = state }
        microphoneUpdate()
    }

    /// A new session connection (not a move): what the last one offered and said is over.
    func microphoneSessionStarted() {
        micDeviceLink = MicrophonePolicy.DeviceLink()
        micState = nil
        microphoneUpdate()
    }

    /// A move's hand-over: the new connection starts its link afresh, so the offer goes again on it, with the
    /// recording's epoch when one runs (the Mac goes on with it); kind 16 stays as the last connection said until
    /// the new one says, so the recording goes on through the move.
    func microphoneMoved() {
        micDeviceLink = MicrophonePolicy.DeviceLink()
        #if DEBUG
        if micRecording { print("mic: format again after the move (epoch \(micCapture?.format?.format.epoch ?? -1))") }
        #endif
        microphoneUpdate()
    }

    /// The session ended: no recording, nothing more sent.
    func microphoneSessionEnded() {
        if micRecording { stopMicrophone(why: "the session ended") }
        micDeviceLink = MicrophonePolicy.DeviceLink()
        micState = nil
        hostMicrophone = nil
    }

    /// The rule, stepped: this connection's offers and ends go out, and the recording starts or stops. Main thread.
    func microphoneUpdate() {
        let d = microphoneInputs
        let step = micDeviceLink.step(d, claimOwed: MicrophoneSwitch.shared.claimOwed)
        if step.claimed { MicrophoneSwitch.shared.claimSpent() }
        for m in step.send { sendMicrophone(m) }
        let records = MicrophonePolicy.records(d)
        if records, !micRecording {
            startMicrophone()
        } else if !records, micRecording {
            let why = d.foreground ? (d.interrupted ? "a call" : !d.switchOn ? "the switch" : "the Mac's word") : "in the background"
            stopMicrophone(why: why)
        }
    }

    /// A type 1 or 3 on the session's link, in order with everything else this device sends; an offer while a
    /// recording runs carries its epoch's format, so a move's new connection goes on with the same epoch.
    private func sendMicrophone(_ m: MicrophoneMessage) {
        var message = m
        if case .format(let f) = m, micRecording, let current = micCapture?.format {
            message = .format(MicrophoneFormat(format: current.format, claim: f.claim, pause: f.pause))
        }
        guard let payload = message.serialized() else { return }
        send(.microphone, payload: payload)
        #if DEBUG
        switch message {
        case .format(let f): print("mic: offer\(f.claim == true ? " (claim)" : "")\(f.pause.map { " paused: \($0)" } ?? "")\(f.isEpoch ? " with epoch \(f.format.epoch ?? -1)" : "")")
        case .end: print("mic: end")
        case .packets: break
        }
        #endif
    }

    private func startMicrophone() {
        let capture = micCapture ?? MicrophoneCapture()
        micCapture = capture
        let link = sessionLink
        capture.onMessage = { message, kind in
            switch kind {
            case .format: link.send(message.serialized())          // in order, as every type 1 goes
            case .packets:
                let sent = link.sendMicrophone(message.serialized(), unsentAtMost: MicrophonePolicy.maxUnsentMessages)
                #if DEBUG
                if sent == .behind { print("mic: skipped a message (\(Int(MicrophonePolicy.maxUnsentSeconds * 1000)) ms unsent)") }
                #endif
                _ = sent
            }
        }
        micRecording = true
        if MicrophoneCapture.source == .microphone {
            sound.setMicrophone(capture.tap)
        }
        capture.start()
    }

    private func stopMicrophone(why: String) {
        micRecording = false
        if MicrophoneCapture.source == .microphone { sound.setMicrophone(nil) }
        micCapture?.stop()
        #if DEBUG
        print("mic: off (\(why))")
        #endif
    }

    /// The session's audio interruptions, for the microphone's pause. From init.
    func observeMicrophoneInterruptions() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self?.microphoneInterrupted(type == .began)
        }
    }

    /// An audio interruption (a call, another app's recording) pauses the microphone until it ends. Main thread.
    func microphoneInterrupted(_ began: Bool) {
        guard micInterrupted != began else { return }
        micInterrupted = began
        #if DEBUG
        print(began ? "mic: paused (interruption)" : "mic: interruption over")
        #endif
        microphoneUpdate()
    }

    /// The row as the rule words it, for the Settings panel. Main thread.
    var microphoneRow: MicrophonePolicy.Row {
        MicrophonePolicy.row(microphoneInputs, hostVersion: hostVersion, mac: macName.isEmpty ? "the Mac" : macName,
                             device: StreamClient.deviceWord, otherWindow: micOtherWindow)
    }
}
