import Foundation
import QuartzCore
import StreamProtocol
import UIKit

// MARK: - Recording the stream (#284, docs/recording-plan.md)

/// A window's recording as its views read it: the phase, the light's numbers, space's word.
struct RecordingStatus: Equatable {
    var phase: RecordingPolicy.Phase = .idle
    /// The movie's time so far; nil before the light and while "Starting…".
    var seconds: Double?
    var bytes: Int64 = 0
    /// Space is low: about this many minutes are left (RecordingPolicy.space).
    var minutesLeft: Int?
}

/// The note after a recording: over the stream in the clipboard chip's corner, on the connect screen after a
/// session ended, in Settings' top row when Stop was tapped there.
struct RecordingNote: Equatable {
    var text: String
    var warning: Bool
}

/// What "Starting…" keeps between its asks (rule 3). Main thread.
struct RecordingStart {
    /// When the light came (systemUptime).
    var lightAt: TimeInterval?
    /// Asks made (or awaited) for the start, the one at "1" counted, and when the last went.
    var asks = 0
    var lastAsk: TimeInterval?
    /// An ask the Mac's second holds back is due: one at a time.
    var heldAsk: DispatchWorkItem?
    /// "Starting…"'s next step, an ask or the give-up: one at a time.
    var next: DispatchWorkItem?
}

extension StreamClient {
    /// Record Sound (#303's key): the Mac's sound in the next recording, while it sends it. On unless turned off.
    static let recordSoundKey = "Sill.recordSound"

    /// How long a recording's note stays over the stream and in Settings.
    static let recordingNoteLifetime: TimeInterval = 4

    /// Whether the next recording records the Mac's sound (RecordingPolicy.recordsSound): Record Sound on and the
    /// Mac's Send Audio on. Main thread.
    var recordsSound: Bool {
        RecordingPolicy.recordsSound(switchOn: UserDefaults.standard.object(forKey: Self.recordSoundKey) as? Bool ?? true,
                                     sendAudio: settings.displayed?.sendAudio)
    }

    /// Start Recording's row for this window now (RecordingPolicy.row). Main thread.
    var recordingRow: RecordingPolicy.Row {
        RecordingPolicy.row(recording.phase, connected: connected, streaming: active != .none, pictureCame: videoSize != .zero)
    }

    /// For the device's auto-lock (DeviceIdlePolicy.Uses.recording): now while this window counts, waits or
    /// records, the end of its last recording after. Main thread.
    func recordingHoldsAwake(now: TimeInterval) -> Double? {
        switch recording.phase {
        case .counting, .starting, .recording: return now
        case .idle, .finishing: return recordingEndedAt
        }
    }

    // MARK: Start, the count, "1" and the light

    /// Settings' Start Recording: the space looked at (under 1.5 GB the space note instead), then 3, 2, 1 over
    /// the picture, the keyframe ask at "1" and the light. Settings closes for it (the caller). Main thread.
    func startRecording() {
        noteAction()
        guard recordingRow == .start else { return }
        guard RecordingPolicy.startAllowed(freeBytes: SillDocuments.availableCapacity()) else {
            showRecordingNote(RecordingPolicy.Copy.noSpace(device: Self.deviceWord), warning: true)
            return
        }
        recordingGeneration += 1
        let generation = recordingGeneration
        recordingStart = RecordingStart()
        recording = RecordingStatus(phase: .counting(RecordingPolicy.countFrom))
        recordingNote = nil
        announceRecording(RecordingPolicy.Copy.countSpoken(RecordingPolicy.countFrom))
        observeRecordingEndings()
        DeviceIdleTimer.shared.update()
        #if DEBUG
        print("recording: Start: 3, 2, 1; the sound \(recordsSound ? "recorded" : "not recorded")")
        #endif
        for elapsed in 1...RecordingPolicy.countFrom {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(elapsed)) { [weak self] in
                guard let self, self.recordingGeneration == generation, case .counting = self.recording.phase else { return }
                if let n = RecordingPolicy.count(elapsed: elapsed) {
                    self.recording.phase = .counting(n)
                    self.announceRecording(RecordingPolicy.Copy.countSpoken(n))
                    if n == RecordingPolicy.askAtCount { self.recordingOne() }
                } else {
                    self.recordingLightCame(generation)
                }
            }
        }
    }

    /// "1": the recorder made (its folder, the sound decided), its taps on the network queue from here on, and
    /// the keyframe asked for (rule 2).
    private func recordingOne() {
        let folder: URL
        do {
            folder = try SillDocuments.make(.recordings)
        } catch {
            stopRecording(.writerFailed(RecordingPolicy.Copy.writerReason(domain: (error as NSError).domain, code: (error as NSError).code,
                                                                          description: error.localizedDescription, device: Self.deviceWord)))
            return
        }
        var setup = StreamRecorder.Setup(folder: folder, start: Date(), withSound: recordsSound)
        setup.device = Self.deviceWord
        setup.protect = { SillDocuments.protect($0, in: .recordings) }
        setup.freeSpace = { SillDocuments.availableCapacity() }
        let rec = StreamRecorder(setup)
        let generation = recordingGeneration
        rec.onEvent = { [weak self] event in self?.recordingEvent(event, generation: generation) }
        recorder = rec
        queue.async { [self] in installRecordingTap(rec) }
        recordingAsk(forStart: true)
    }

    /// The light: where the movie starts, decided on the network queue in the stream's order.
    private func recordingLightCame(_ generation: Int) {
        guard let rec = recorder else { return }
        recordingStart.lightAt = ProcessInfo.processInfo.systemUptime
        recording.phase = .starting
        queue.async { [self] in
            let start = recordingLight(rec)
            DispatchQueue.main.async { [self] in
                guard recordingGeneration == generation else { return }
                #if DEBUG
                print("recording: the light: \(start)")
                #endif
                if case .atNextKeyframe = start, recording.phase == .starting {
                    announceRecording(RecordingPolicy.Copy.startingSpoken)
                    scheduleRecordingStart(generation)
                }
            }
        }
    }

    /// While "Starting…": the next ask at the recovery's wait, or the give-up (rule 3), one step pending at a time.
    /// Something is always due: an ask the Mac's second holds back schedules the next step once it has gone.
    private func scheduleRecordingStart(_ generation: Int) {
        recordingStart.next?.cancel()
        recordingStart.next = nil
        guard recording.phase == .starting, let lightAt = recordingStart.lightAt else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let step = RecordingPolicy.starting(now: now, lightAt: lightAt, asks: recordingStart.asks,
                                            lastAsk: recordingStart.lastAsk, wait: keyframeAnswerWait)
        let at: TimeInterval
        let ask: Bool
        switch step {
        case .askAt(let t): at = t; ask = true
        case .giveUpAt(let t): at = t; ask = false
        case .giveUp: stopRecording(.gaveUp); return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.recordingGeneration == generation, self.recording.phase == .starting else { return }
            self.recordingStart.next = nil
            if !ask {
                self.stopRecording(.gaveUp)
            } else if self.recordingAsk(forStart: true) {
                self.scheduleRecordingStart(generation)
            }
        }
        recordingStart.next = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, at - now), execute: work)
    }

    /// The recording's ask (rule 2): now, at the Mac's second after the last ask on this connection (one held
    /// at a time; a start's held ask goes on with "Starting…" once it has gone), or the picture recovery's
    /// awaited while its keyframe is due. True when it went now or the recovery's is awaited.
    @discardableResult
    func recordingAsk(forStart: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        switch RecordingPolicy.keyframeAsk(now: now, lastAsk: lastKeyframeAskAt, recoveryDueUntil: recoveryAskDueUntil) {
        case .now:
            sendKeyframeRequest()
            if forStart { recordingStart.asks += 1; recordingStart.lastAsk = now }
            #if DEBUG
            print("recording: asked the Mac for a keyframe (\(forStart ? "the start's \(recordingStart.asks)" : "the chain broke"))")
            #endif
            return true
        case .at(let t):
            guard recordingStart.heldAsk == nil else { return false }
            let generation = recordingGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.recordingGeneration == generation else { return }
                self.recordingStart.heldAsk = nil
                if self.recordingAsk(forStart: forStart), forStart, self.recording.phase == .starting {
                    self.scheduleRecordingStart(generation)
                }
            }
            recordingStart.heldAsk = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, t - now), execute: work)
            return false
        case .awaitRecovery:
            if forStart { recordingStart.asks += 1; recordingStart.lastAsk = recoveryLastAsk ?? now }
            return true
        }
    }

    /// What the recorder says, on the main thread.
    private func recordingEvent(_ event: StreamRecorder.Event, generation: Int) {
        guard recordingGeneration == generation else { return }
        switch event {
        case .started:
            guard recording.phase == .starting || recording.phase == .counting(1) else { return }
            recording.phase = .recording
            recording.seconds = 0
            announceRecording(RecordingPolicy.Copy.startSpoken)
            #if DEBUG
            print("recording: the movie's 0:00 is known")
            #endif
        case .progress(let seconds, let bytes, let space):
            guard recording.phase == .recording || recording.phase == .starting else { return }
            if recording.phase == .recording { recording.seconds = seconds }
            recording.bytes = bytes
            switch space {
            case .fine:
                recording.minutesLeft = nil
            case .low(let minutes):
                if recording.minutesLeft == nil { announceRecording(RecordingPolicy.Copy.lowSpoken(minutes)) }
                recording.minutesLeft = minutes
            case .stop:
                stopRecording(.space)
            }
        case .askKeyframe:
            recordingAsk(forStart: false)
        case .failed(let why):
            stopRecording(.writerFailed(why))
        }
    }

    // MARK: The end

    /// Stop, Cancel, and every other ending (RecordingPolicy.Ending): the count cancelled, or the movie closed at
    /// the stop's time and finished in a background task, then the note. Main thread.
    func stopRecording(_ ending: RecordingPolicy.Ending) {
        guard recording.phase != .idle, recording.phase != .finishing else { return }
        recordingGeneration += 1
        removeRecordingObservers()
        recordingStart.heldAsk?.cancel()
        recordingStart.next?.cancel()
        recordingStart = RecordingStart()
        recordingEndedAt = ProcessInfo.processInfo.systemUptime
        defer { DeviceIdleTimer.shared.update() }
        guard let rec = recorder else {
            // The count, before "1": nothing was made.
            recording = RecordingStatus()
            #if DEBUG
            print("recording: cancelled during the count")
            #endif
            return
        }
        recorder = nil
        recording.phase = .finishing
        let at = CACurrentMediaTime()
        queue.async { [self] in
            rec.closeTaps()
            if recordingTap === rec { recordingTap = nil }
        }
        // The movie is finished in a background task (Sill may be leaving the screen); at its expiry what the
        // fragments kept stays, and the task ends.
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Finish the recording") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        let mac = macName.isEmpty ? nil : macName
        let takesAsks = RecordingPolicy.macTakesKeyframeAsks(hostVersion: hostVersion)
        #if DEBUG
        print("recording: stop: \(ending)")
        #endif
        rec.stop(arrival: at) { [weak self] outcome in
            defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid } }
            guard let self else { return }
            if self.recording.phase == .finishing, self.recorder == nil { self.recording = RecordingStatus() }
            var failure = outcome.failure
            if case .writerFailed = ending { failure = nil }   // its own words already
            let note = RecordingPolicy.Copy.note(ending, movies: outcome.movies.count, failure: failure, device: Self.deviceWord,
                                                 mac: mac, macTakesAsks: takesAsks)
            #if DEBUG
            print("recording: \(outcome.movies.count) movie(s) \(outcome.movies.map(\.lastPathComponent))\(outcome.failure.map { ", the writer: \($0)" } ?? "")")
            #endif
            if let note {
                let warning: Bool
                switch ending {
                case .space, .writerFailed, .gaveUp: warning = true
                default: warning = failure != nil || outcome.movies.isEmpty
                }
                self.showRecordingNote(note, warning: warning)
            }
            DeviceIdleTimer.shared.update()
        }
    }

    /// The note, for `recordingNoteLifetime` once Sill is on the screen (one shown while it is away waits for
    /// its return), and spoken.
    func showRecordingNote(_ text: String, warning: Bool) {
        recordingNote = RecordingNote(text: text, warning: warning)
        announceRecording(text)
        recordingNoteExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recordingNote = nil }
        recordingNoteExpiry = work
        if UIApplication.shared.applicationState == .background {
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                if let token { NotificationCenter.default.removeObserver(token) }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordingNoteLifetime, execute: work)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordingNoteLifetime, execute: work)
        }
    }

    /// Sill leaving the screen (the app, or this window's scene, to the background, Picture in Picture or not:
    /// decision 4) and the device's lock end the recording (rule 8).
    private func observeRecordingEndings() {
        removeRecordingObservers()
        let center = NotificationCenter.default
        recordingObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopRecording(.leftScreen)
        })
        if let scene = displayView.window?.windowScene {
            recordingObservers.append(center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { [weak self] _ in
                self?.stopRecording(.leftScreen)
            })
        }
        recordingObservers.append(center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil,
                                                     queue: .main) { [weak self] _ in
            self?.stopRecording(.deviceLocked)
        })
    }

    private func removeRecordingObservers() {
        recordingObservers.forEach { NotificationCenter.default.removeObserver($0) }
        recordingObservers = []
    }

    private func announceRecording(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    #if DEBUG
    /// `-SillRecording count|starting|on|low` (the mock's recording states, never a recorder) and
    /// `-SillRecordingNote saved|parts|left|ended|space|failed|gaveup|nospace` (its note, kept): MockCatalog.
    func mockRecording(_ state: String?, note: String?) {
        switch state {
        case "count"?: recording = RecordingStatus(phase: .counting(3))
        case "starting"?: recording = RecordingStatus(phase: .starting)
        case "on"?: recording = RecordingStatus(phase: .recording, seconds: 42, bytes: 126_000_000)
        case "low"?: recording = RecordingStatus(phase: .recording, seconds: 102, bytes: 230_000_000, minutesLeft: 4)
        default: break
        }
        let device = Self.deviceWord, mac = macName
        let text: String?
        switch note {
        case "saved"?: text = RecordingPolicy.Copy.note(.stop, movies: 1, failure: nil, device: device, mac: mac, macTakesAsks: true)
        case "parts"?: text = RecordingPolicy.Copy.note(.stop, movies: 3, failure: nil, device: device, mac: mac, macTakesAsks: true)
        case "left"?: text = RecordingPolicy.Copy.note(.leftScreen, movies: 1, failure: nil, device: device, mac: mac, macTakesAsks: true)
        case "ended"?: text = RecordingPolicy.Copy.note(.sessionEnded, movies: 1, failure: nil, device: device, mac: mac, macTakesAsks: true)
        case "space"?: text = RecordingPolicy.Copy.note(.space, movies: 1, failure: nil, device: device, mac: mac, macTakesAsks: true)
        case "failed"?: text = RecordingPolicy.Copy.note(.writerFailed("this \(device) ran out of space"), movies: 1, failure: nil, device: device,
                                                          mac: mac, macTakesAsks: true)
        case "gaveup"?: text = RecordingPolicy.Copy.note(.gaveUp, movies: 0, failure: nil, device: device, mac: mac, macTakesAsks: false)
        case "nospace"?: text = RecordingPolicy.Copy.noSpace(device: device)
        default: text = nil
        }
        if let text { recordingNote = RecordingNote(text: text, warning: note != "saved" && note != "parts" && note != "left" && note != "ended") }
    }
    #endif
}
