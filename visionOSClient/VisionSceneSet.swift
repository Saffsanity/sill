import Foundation

struct VisionScenePreferences: Codable, Equatable {
    var toolbarAutomatic = true
    var mouseMode = false
    var textScale = 0.0
    var isValid: Bool { textScale.isFinite && textScale >= 0 && textScale <= 8 }
}

/// A small credential-free recovery journal. Native SceneStorage remains authoritative when
/// available; this survives a whole-process exit even if visionOS recreates only one scene.
struct VisionSceneSet: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var windowID: UUID? // nil is the app's existing default/primary scene.
        var sessionID: String
        var workspace: VisionWorkspace
        var preferences = VisionScenePreferences()
        var key: String { windowID?.uuidString ?? "primary" }
    }
    var version = 2
    private(set) var entries: [Entry] = []
    private(set) var members: [String] = []
    /// Explicit user exclusions survive late saves, native background-only closures and relaunch.
    /// Descriptors remain available for native restoration and the membership editor.
    private(set) var excluded: [String] = []
    init() {}
    private enum CodingKeys: String, CodingKey { case version, entries, members, excluded }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        guard storedVersion == 1 || storedVersion == 2 else { throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported scene journal") }
        entries = try values.decode([Entry].self, forKey: .entries)
        // v29 accumulated descriptors without reliable current membership. Preserve fallback
        // descriptors, but only actual observed scenes may enrol in the new restore set.
        members = storedVersion == 2 ? try values.decode([String].self, forKey: .members) : []
        excluded = try values.decodeIfPresent([String].self, forKey: .excluded) ?? []
    }
    static let limit = 4
    static let storageKey = "Sill.spatialSceneSet.v1"
    static func key(_ id: UUID?) -> String { id?.uuidString ?? "primary" }
    func entry(_ id: UUID?) -> Entry? { entries.first { $0.key == Self.key(id) } }
    @discardableResult
    mutating func upsert(_ entry: Entry, admitVisible: Bool = false, protecting: Set<String> = []) -> Bool {
        guard entry.preferences.isValid, VisionWorkspace.decode(entry.workspace.encoded) != nil,
              entry.sessionID.utf8.count <= 256,
              entry.sessionID.isEmpty || !entries.contains(where: { $0.key != entry.key && $0.sessionID == entry.sessionID }) else { return false }
        if let index = entries.firstIndex(where: { $0.key == entry.key }) { entries[index] = entry }
        else if entries.count < Self.limit { entries.append(entry) }
        else if admitVisible, let obsolete = entries.firstIndex(where: { !protecting.contains($0.key) && !members.contains($0.key) }) ?? entries.firstIndex(where: { !protecting.contains($0.key) }) {
            let retiredKey = entries[obsolete].key
            entries.remove(at: obsolete); members.removeAll { $0 == retiredKey }; excluded.removeAll { $0 == retiredKey }; entries.append(entry)
        } else { return false }
        if admitVisible, !excluded.contains(entry.key), !members.contains(entry.key), members.count < Self.limit { members.append(entry.key) }
        return true
    }
    mutating func remove(_ id: UUID?) {
        entries.removeAll { $0.key == Self.key(id) }; members.removeAll { $0 == Self.key(id) }
        excluded.removeAll { $0 == Self.key(id) }
    }
    mutating func setRestoring(_ id: UUID?, enabled: Bool) {
        let key = Self.key(id)
        guard entries.contains(where: { $0.key == key }) else { return }
        if enabled {
            excluded.removeAll { $0 == key }
            if !members.contains(key) { members.append(key) }
        } else {
            members.removeAll { $0 == key }
            if !excluded.contains(key) { excluded.append(key) }
        }
    }
    mutating func retainMacs(_ admitted: Set<String>) {
        entries.removeAll { !admitted.contains($0.workspace.macID) }
        members.removeAll { key in !entries.contains { $0.key == key } }
        excluded.removeAll { key in !entries.contains { $0.key == key } }
    }
    var restoringEntries: [Entry] { entries.filter { members.contains($0.key) } }
    mutating func retireHandles(_ ids: Set<String>) {
        for index in entries.indices where ids.contains(entries[index].sessionID) { entries[index].sessionID = "" }
    }
    @discardableResult
    mutating func discard(_ sessions: Set<String>, launchSessions: [String: String] = [:]) -> Bool {
        let relevant = restoringEntries
        let identified = Set(relevant.map(\.sessionID).filter { !$0.isEmpty })
        // A whole-set native discard (for example Close App/force quit) retires native handles,
        // while preserving logical workspaces. A subset is an individually closed window.
        let currentWholeSet = identified.count == relevant.count && !identified.isEmpty && identified.isSubset(of: sessions)
        let launchIDs = relevant.compactMap { launchSessions[$0.key] }.filter { !$0.isEmpty }
        let launchWholeSet = launchIDs.count == relevant.count && !launchIDs.isEmpty && Set(launchIDs).isSubset(of: sessions)
        if currentWholeSet || launchWholeSet {
            for index in entries.indices where sessions.contains(entries[index].sessionID) { entries[index].sessionID = "" }
        } else {
            let retired = entries.filter { !$0.sessionID.isEmpty && sessions.contains($0.sessionID) }.map(\.key)
            entries.removeAll { retired.contains($0.key) }; members.removeAll { retired.contains($0) }
            excluded.removeAll { retired.contains($0) }
        }
        return currentWholeSet || launchWholeSet
    }
    static func decode(_ text: String?) -> Self {
        guard let text, text.utf8.count <= 20_480, let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 2,
              value.entries.count <= limit, Set(value.entries.map(\.key)).count == value.entries.count,
              value.members.count <= limit, Set(value.members).count == value.members.count,
              value.excluded.count <= limit, Set(value.excluded).count == value.excluded.count,
              Set(value.members).isDisjoint(with: value.excluded),
              value.excluded.allSatisfy({ key in value.entries.contains { $0.key == key } }),
              value.members.allSatisfy({ member in value.entries.contains { $0.key == member } }),
              Set(value.entries.map(\.sessionID).filter { !$0.isEmpty }).count == value.entries.filter({ !$0.sessionID.isEmpty }).count,
              value.entries.allSatisfy({ $0.sessionID.utf8.count <= 256 && $0.preferences.isValid && VisionWorkspace.decode($0.workspace.encoded) != nil }) else { return Self() }
        return value
    }
    var encoded: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// Bounded replay per launch or observed whole-background/reopen cycle. Native UUID
/// presentation supplies identity deduplication even for hidden scenes that remain bound.
struct VisionSceneReplay {
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var requested = Set<String>()
    mutating func start() -> Bool {
        guard !started else { return false }
        started = true
        return true
    }
    mutating func cancel() { cancelled = true }
    mutating func resetAfterConfirmedClosure() { self = Self() }
    mutating func claim(_ entry: VisionSceneSet.Entry, in journal: VisionSceneSet, bound: Set<String>) -> Bool {
        guard started, !cancelled, journal.members.contains(entry.key), journal.entry(entry.windowID) == entry,
              !bound.contains(entry.key), !requested.contains(entry.key) else { return false }
        requested.insert(entry.key)
        return true
    }
}

/// Native-session ownership fences late view updates after a permanent discard. Rebinding the
/// same logical UUID with a new native session is allowed; an old view cannot re-enrol itself.
struct VisionSceneBindings {
    private(set) var sessions: [String: String] = [:]
    private var retired = Set<String>()
    mutating func bind(_ key: String, session: String) -> Bool {
        guard !retired.contains(session), !sessions.contains(where: { $0.key != key && $0.value == session }) else { return false }
        sessions[key] = session
        return true
    }
    func owns(_ key: String, session: String) -> Bool { sessions[key] == session }
    mutating func discard(_ ids: Set<String>) {
        retired.formUnion(ids)
        sessions = sessions.filter { !ids.contains($0.value) }
    }
    mutating func disconnect(_ session: String) { sessions = sessions.filter { $0.value != session } }
}

/// Foreground-inactive still counts as present (keyboard, alerts and focus changes). Background
/// only arms restoration; it never opens a scene. A later real activation consumes that cycle.
struct VisionScenePresence {
    enum Phase: Int { case active = 0, inactive = 1, background = 2 }
    private(set) var phases: [String: Phase] = [:]
    private(set) var observed = Set<String>()
    private(set) var allBackground = false
    private(set) var reopenArmed = false
    var foreground: Set<String> { Set(phases.filter { $0.value != .background }.keys) }
    mutating func update(_ key: String, phase: Phase) {
        phases[key] = phase
        if phase == .active { observed.insert(key) }
        allBackground = !phases.isEmpty && phases.values.allSatisfy { $0 == .background }
        if allBackground, !observed.isEmpty { reopenArmed = true }
    }
    mutating func disconnect(_ key: String) { update(key, phase: .background) }
    mutating func retire(_ key: String) { phases[key] = nil; observed.remove(key) }
    mutating func consumeReopen() -> Bool {
        guard reopenArmed, !foreground.isEmpty else { return false }
        reopenArmed = false
        return true
    }
}

/// Latch the whole-app classification when observed, rather than reclassifying a quick reopen
/// from the later foreground state. Native session IDs fence replacement-scene ownership.
struct VisionSceneClosureBatch {
    var disconnected: [String: String] = [:]
    var discarded = Set<String>()
    private(set) var observedWholeSetHidden = false
    mutating func observe(_ presence: VisionScenePresence) {
        if presence.allBackground, !presence.observed.isEmpty { observedWholeSetHidden = true }
    }
    func shouldRetire(_ key: String, session: String, bindings: VisionSceneBindings) -> Bool {
        !observedWholeSetHidden && disconnected[key] == session && bindings.owns(key, session: session)
    }
}

#if os(visionOS)
import SwiftUI
import UIKit

private struct SpatialScenePreferencesKey: EnvironmentKey {
    static let defaultValue: Binding<VisionScenePreferences>? = nil
}
private struct SpatialWindowManagementKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
private struct SpatialSceneIDKey: EnvironmentKey { static let defaultValue: UUID? = nil }
private struct SpatialNativeSessionKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var spatialWindowManagement: (() -> Void)? {
        get { self[SpatialWindowManagementKey.self] }
        set { self[SpatialWindowManagementKey.self] = newValue }
    }
    var spatialScenePreferences: Binding<VisionScenePreferences>? {
        get { self[SpatialScenePreferencesKey.self] }
        set { self[SpatialScenePreferencesKey.self] = newValue }
    }
    var spatialNativeSession: String? {
        get { self[SpatialNativeSessionKey.self] }
        set { self[SpatialNativeSessionKey.self] = newValue }
    }
    var spatialSceneID: UUID? {
        get { self[SpatialSceneIDKey.self] }
        set { self[SpatialSceneIDKey.self] = newValue }
    }
}

@MainActor
final class VisionSceneSetRecovery {
    static let shared = VisionSceneSetRecovery()
    private var journal: VisionSceneSet
    private var bindings = VisionSceneBindings()
    private var presence = VisionScenePresence()
    private var launchSessions: [String: String] = [:]
    private var replay = VisionSceneReplay()
    private var recovery: Task<Void, Never>?
    private var generation = UUID()
    private var confirmedReplayKeys = Set<String>()
    private var observers: [NSObjectProtocol] = []
    private var settle: Task<Void, Never>?
    private var closure = VisionSceneClosureBatch()
    private final class Presenter {
        weak var scene: UIWindowScene?
        let open: (UUID?) -> Void
        init(scene: UIWindowScene, open: @escaping (UUID?) -> Void) { self.scene = scene; self.open = open }
    }
    private var presenters: [String: Presenter] = [:]
    private var latestDescriptors: [String: VisionSceneSet.Entry] = [:]

    #if DEBUG
    static var fixture: Bool { ProcessInfo.processInfo.arguments.contains("-SillSceneSetFixture") }
    #else
    static var fixture: Bool { false }
    #endif
    private init() {
        journal = VisionSceneSet.decode(UserDefaults.standard.string(forKey: VisionSceneSet.storageKey))
        pruneTrust()
        launchSessions = Dictionary(uniqueKeysWithValues: journal.entries.map { ($0.key, $0.sessionID) })
        record(.processStart)
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification, UIScene.didDisconnectNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? UIWindowScene else { return }
                MainActor.assumeIsolated { self?.changed(scene, notification: name) }
            })
        }
    }
    private func persist() { UserDefaults.standard.set(journal.encoded, forKey: VisionSceneSet.storageKey) }
    private func pruneTrust() {
        guard !Self.fixture else { return }
        let admitted = DeviceIdentity.existing() == nil ? [] : SavedMacs.decode(UserDefaults.standard.string(forKey: SavedMacs.defaultsKey)).filter {
            $0.revoked != true && $0.newKey != true && $0.fingerprintData != nil
        }.map(\.macID)
        journal.retainMacs(Set(admitted)); persist()
    }
    func bind(_ id: UUID?, to scene: UIWindowScene) -> VisionSceneSet.Entry? {
        let sessionID = scene.session.persistentIdentifier
        guard bindings.bind(VisionSceneSet.key(id), session: sessionID) else { return nil }
        let key = VisionSceneSet.key(id)
        if latestDescriptors[key]?.sessionID != sessionID { latestDescriptors[key] = nil }
        closure.disconnected[key] = nil
        presence.update(key, phase: phase(scene))
        record(.connect, secondary: id != nil)
        if phase(scene) == .active { noteReplayAccepted(key) }
        if var entry = journal.entry(id) {
            entry.sessionID = sessionID
            latestDescriptors[key] = entry
            journal.upsert(entry, admitVisible: presence.observed.contains(key), protecting: presence.foreground)
            persist()
            return entry
        }
        return nil
    }
    private func phase(_ scene: UIWindowScene) -> VisionScenePresence.Phase {
        switch scene.activationState {
        case .foregroundActive: return .active
        case .foregroundInactive: return .inactive
        default: return .background
        }
    }
    private func changed(_ scene: UIWindowScene, notification: Notification.Name) {
        let session = scene.session.persistentIdentifier
        guard let key = bindings.sessions.first(where: { $0.value == session })?.key else {
            let kind: VisionSceneRecoveryDiagnostics.Kind = notification == UIScene.didActivateNotification ? .unmatchedActivate :
                (notification == UIScene.didEnterBackgroundNotification ? .unmatchedBackground :
                    (notification == UIScene.didDisconnectNotification ? .unmatchedDisconnect : .unmatchedInactive))
            record(kind)
            return
        }
        if notification == UIScene.didDisconnectNotification {
            closure.disconnected[key] = session
            presence.disconnect(key)
            closure.observe(presence)
            record(.disconnect, secondary: key != "primary")
            scheduleSettle()
        } else {
            let state: VisionScenePresence.Phase = notification == UIScene.didEnterBackgroundNotification ? .background : (notification == UIScene.didActivateNotification ? .active : .inactive)
            presence.update(key, phase: state)
            closure.observe(presence)
            if state == .active { closure.disconnected[key] = nil }
            if notification == UIScene.didActivateNotification {
                if var entry = latestDescriptors[key] ?? journal.entries.first(where: { $0.key == key }) {
                    entry.sessionID = session
                    journal.upsert(entry, admitVisible: true, protecting: presence.foreground)
                    latestDescriptors[key] = entry
                    persist()
                }
                record(.activate, secondary: key != "primary"); noteReplayAccepted(key)
                if let presenter = presenters[key], presenter.scene === scene { recover(from: scene, open: presenter.open) }
            }
            if notification == UIScene.didEnterBackgroundNotification { record(.background, secondary: key != "primary"); scheduleSettle() }
        }
    }
    func save(_ id: UUID?, session: String, workspace: VisionWorkspace, preferences: VisionScenePreferences) {
        let key = VisionSceneSet.key(id)
        guard bindings.owns(key, session: session) else { return }
        if let scene = presenters[key]?.scene, scene.session.persistentIdentifier == session {
            presence.update(key, phase: phase(scene))
        }
        let entry = VisionSceneSet.Entry(windowID: id, sessionID: session, workspace: workspace, preferences: preferences)
        latestDescriptors[key] = entry
        let accepted = journal.upsert(entry, admitVisible: presence.observed.contains(key), protecting: presence.foreground)
        record(accepted ? .saveAccepted : .saveDeclined, secondary: id != nil)
        persist()
    }
    var managedEntries: [VisionSceneSet.Entry] { journal.entries }
    func isRestoring(_ id: UUID?) -> Bool { journal.members.contains(VisionSceneSet.key(id)) }
    func setRestoring(_ id: UUID?, enabled: Bool) {
        // Cancel an already queued replay before persisting the explicit membership change.
        cancelRecovery()
        journal.setRestoring(id, enabled: enabled)
        persist()
    }
    func close(_ id: UUID?, session: String, completion: @escaping (String) -> Void) {
        let key = VisionSceneSet.key(id)
        guard bindings.owns(key, session: session),
              let native = UIApplication.shared.openSessions.first(where: { $0.persistentIdentifier == session }) else {
            completion("This window is no longer available.")
            return
        }
        // Exclude BEFORE requesting native destruction; background-only lifecycle delivery and
        // late saves cannot re-enrol a window the user explicitly chose to close.
        setRestoring(id, enabled: false)
        UIApplication.shared.requestSceneSessionDestruction(native, options: nil) { _ in
            completion("Sill couldn't close this window. Its restore switch is off; you can close it with the system window controls.")
        }
    }
    func clear(_ id: UUID?, session: String) {
        let key = VisionSceneSet.key(id)
        guard bindings.owns(key, session: session) else { return }
        cancelRecovery(); journal.remove(id); latestDescriptors[key] = nil
        presence.retire(key); persist(); record(.clear, secondary: id != nil)
    }
    func prune(admitted: Set<String>) {
        journal.retainMacs(admitted)
        latestDescriptors = latestDescriptors.filter { admitted.contains($0.value.workspace.macID) }
        persist()
    }
    func discard(_ sessions: Set<String>) {
        closure.discarded.formUnion(sessions)
        for (key, session) in bindings.sessions where sessions.contains(session) { presence.disconnect(key) }
        closure.observe(presence)
        record(.discard)
        scheduleSettle()
    }
    private func scheduleSettle() {
        settle?.cancel()
        settle = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.settleClosure()
        }
    }
    private func settleClosure() {
        // A Close App batch may disconnect scenes in sequence. Wait for the final native state
        // before deciding if a vanished sibling was an individual close or the whole workspace.
        let entireSetHidden = closure.observedWholeSetHidden
        if !entireSetHidden {
            for (key, session) in closure.disconnected {
                guard closure.shouldRetire(key, session: session, bindings: bindings) else { continue }
                if let entry = journal.entries.first(where: { $0.key == key }) { journal.remove(entry.windowID) }
                presence.retire(key); presenters[key] = nil; latestDescriptors[key] = nil
            }
        }
        if entireSetHidden {
            // Only actually discarded old handles are obsolete. A rebound scene may already
            // have a new native ID; an unrelated delayed callback must not clear that handle.
            journal.retireHandles(closure.discarded)
        } else { _ = journal.discard(closure.discarded, launchSessions: launchSessions) }
        for (key, session) in bindings.sessions where closure.discarded.contains(session) {
            if !entireSetHidden, !journal.members.contains(key) { presence.retire(key) }
            presenters[key] = nil; latestDescriptors[key] = nil
        }
        bindings.discard(closure.discarded)
        for (key, session) in closure.disconnected {
            if presenters[key]?.scene?.session.persistentIdentifier == session { presenters[key] = nil }
            if latestDescriptors[key]?.sessionID == session { latestDescriptors[key] = nil }
            bindings.disconnect(session)
        }
        closure = VisionSceneClosureBatch()
        persist(); record(.settled)
    }
    private func cancelRecovery() {
        replay.cancel(); generation = UUID(); recovery?.cancel(); recovery = nil
    }
    func recover(from scene: UIWindowScene, open: @escaping (UUID?) -> Void) {
        guard let key = bindings.sessions.first(where: { $0.value == scene.session.persistentIdentifier })?.key else { return }
        presenters[key] = Presenter(scene: scene, open: open)
        guard scene.activationState == .foregroundActive else { return }
        if presence.consumeReopen() {
            cancelRecovery(); replay.resetAfterConfirmedClosure(); confirmedReplayKeys.removeAll()
            record(.reopenCycle)
        }
        guard replay.start() else { return }
        let token = generation
        recovery = Task { @MainActor [weak self, weak scene] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, let scene, !Task.isCancelled, token == self.generation else { return }
            guard scene.activationState == .foregroundActive else {
                // A transient inactive phase must not consume the only presentation attempt.
                self.replay.resetAfterConfirmedClosure(); self.record(.replayDeferred); return
            }
            let entries = self.journal.restoringEntries
            for entry in entries {
                guard !Task.isCancelled, token == self.generation else { return }
                if !self.replay.claim(entry, in: self.journal, bound: self.presence.foreground) { continue }
                self.record(.replayAttempt, secondary: entry.windowID != nil)
                if entry.windowID == nil, let existing = UIApplication.shared.openSessions.first(where: { $0.persistentIdentifier == entry.sessionID || self.bindings.sessions[entry.key] == $0.persistentIdentifier }) {
                    UIApplication.shared.requestSceneSessionActivation(existing, userActivity: nil, options: nil) { [weak self] error in
                        self?.record(.replayDeclined, secondary: false, error: (error as NSError).code)
                    }
                } else { open(entry.windowID) }
                self.record(.replayRequested, secondary: entry.windowID != nil)
            }
            self.recovery = nil
        }
    }
    private func noteReplayAccepted(_ key: String) {
        if replay.requested.contains(key), confirmedReplayKeys.insert(key).inserted {
            record(.replayAccepted, secondary: key != "primary")
        }
    }
    private func record(_ event: VisionSceneRecoveryDiagnostics.Kind, secondary: Bool = false, error: Int? = nil) {
        VisionSceneRecoveryDiagnostics.record(event, secondary: secondary, members: journal.members.count,
                                             descriptors: journal.entries.count, foreground: presence.foreground.count,
                                             bound: bindings.sessions.count, error: error)
    }
}

final class VisionSceneSetAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        VisionSceneSetRecovery.shared.discard(Set(sceneSessions.map(\.persistentIdentifier)))
    }
}

/// Bind the native session before starting a network client or using a ledger fallback.
struct VisionSceneSetBinding: UIViewRepresentable {
    var onBind: (UIWindowScene) -> Void
    func makeUIView(context: Context) -> BindingView { BindingView() }
    func updateUIView(_ view: BindingView, context: Context) { view.onBind = onBind; view.bind() }
    final class BindingView: UIView {
        var onBind: ((UIWindowScene) -> Void)?
        private var delivered: String?
        override func didMoveToWindow() { super.didMoveToWindow(); bind() }
        func bind() {
            guard let scene = window?.windowScene, delivered != scene.session.persistentIdentifier, let onBind else { return }
            delivered = scene.session.persistentIdentifier
            DispatchQueue.main.async { [weak self, weak scene] in
                guard let self, let scene, self.window?.windowScene === scene,
                      self.delivered == scene.session.persistentIdentifier else { return }
                onBind(scene)
            }
        }
    }
}
#endif
