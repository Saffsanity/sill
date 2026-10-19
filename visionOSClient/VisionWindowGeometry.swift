import SwiftUI
import UIKit
import StreamProtocol

/// A scene-local bridge is needed because SwiftUI has no imperative scene-size request API.
/// It never enumerates UIApplication windows or applies changes to a sibling scene.
struct VisionWindowGeometry: UIViewRepresentable {
    @ObservedObject var client: StreamClient
    var hasRestoredWorkspace = false

    func makeUIView(context: Context) -> VisionWindowGeometryView {
        VisionWindowGeometryView()
    }

    func updateUIView(_ view: VisionWindowGeometryView, context: Context) {
        #if DEBUG
        // Exact-size mock/live harness frames are visual test fixtures, not scene-size requests.
        if LayoutHarness.Spec.fromLaunchArguments != nil { return }
        #endif
        view.update(client: client, hasRestoredWorkspace: hasRestoredWorkspace)
    }

    static func dismantleUIView(_ view: VisionWindowGeometryView, coordinator: ()) {
        view.removeObservers()
    }
}

final class VisionWindowGeometryView: UIView {
    private enum Token: Equatable {
        case login
        case source(Date?, StreamSource, CGSize?)
    }
    private var diagnosticSourceSize: CGSize?
    private let diagnosticScene = VisionGeometryDiagnostics.nextScene()
    private weak var client: StreamClient?
    private weak var owningScene: UIWindowScene?
    private var applied: Token?
    private var waitingForDimensions: Token?
    private var attempted: Token?
    private var resizeTask: Task<Void, Never>?
    private var requestGeneration = UUID()
    private var requestFailed = false
    private var disconnected = false
    private var hasRestoredWorkspace = false
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        observers = [
            NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let current = self.owningScene, let scene = note.object as? UIWindowScene, scene === current else { return }
                self.disconnected = true
                self.applied = nil
                self.cancelResize()
            },
            NotificationCenter.default.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let current = self.owningScene, let scene = note.object as? UIWindowScene, scene === current else { return }
                self.cancelResize()
                self.attempted = nil
            },
            NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let current = self.owningScene, let scene = note.object as? UIWindowScene, scene === current else { return }
                self.disconnected = false
                self.attempted = nil // An activation can recover a previously refused request.
                self.applySize()
            }
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { removeObservers() }

    func removeObservers() {
        cancelResize()
        owningScene = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let scene = window?.windowScene else {
            cancelResize()
            owningScene = nil
            applied = nil
            attempted = nil
            return
        }
        if owningScene !== scene {
            cancelResize()
            applied = nil
            attempted = nil
        }
        owningScene = scene
        if let client { VisionSceneSessionLifecycle.attach(client: client, to: scene) }
        applySize()
    }

    func update(client: StreamClient, hasRestoredWorkspace: Bool = false) {
        self.hasRestoredWorkspace = hasRestoredWorkspace
        self.client = client
        if let scene = owningScene { VisionSceneSessionLifecycle.attach(client: client, to: scene) }
        applySize()
    }

    private func recordPresentationSize() {
        guard let client, client.connected, let applied, isCurrentSourceToken(applied),
              let size = window?.bounds.size, let source = diagnosticSourceSize,
              VisionWindowSizePolicy.matchesAspect(size, source: source) else { return }
        let active = client.active
        let started = client.connectedAt
        let generation = requestGeneration
        DispatchQueue.main.async { [weak self, weak client] in
            guard let self, self.requestGeneration == generation, self.applied == applied,
                  self.isCurrentSourceToken(applied) else { return }
            client?.noteSpatialPresentationSize(size, source: active, session: started, confirmed: true)
        }
    }

    private func applySize() {
        guard !disconnected, let client, let scene = owningScene, scene.activationState == .foregroundActive else { return }
        let token: Token
        let desired: CGSize
        if !client.connected {
            // A restored scene already has system-owned geometry. Do not collapse it to login.
            if hasRestoredWorkspace || client.spatialPreservesRestoredSize { return }
            token = .login
            diagnosticSourceSize = nil
            desired = VisionWindowSizePolicy.login
        } else {
            token = .source(client.connectedAt, client.active,
                            client.active == .desktop ? client.spatialDesktopVideoSize : nil)
            guard token != applied, token != attempted else { return }
            let source: CGSize
            switch client.active {
            case .window(let id):
                if let snapshot = client.spatialPreferredSourceSize, snapshot.source == client.active {
                    source = snapshot.size
                } else {
                    // Host-initiated selections have no local request snapshot.
                    guard let window = client.windows.first(where: { $0.id == id }) else {
                        releaseWhileWaiting(token, in: scene)
                        return
                    }
                    source = CGSize(width: window.width, height: window.height)
                }
            case .desktop:
                guard let desktop = client.spatialDesktopVideoSize else {
                    releaseWhileWaiting(token, in: scene)
                    return
                }
                source = desktop
            case .none:
                diagnosticSourceSize = nil
                cancelResize()
                applied = token
                request(nil, in: scene) // Waiting for a selection must not retain a previous lock.
                return
            }
            guard var geometry = VisionWindowSizePolicy.geometry(source: source) else {
                releaseWhileWaiting(token, in: scene)
                return
            }
            if client.spatialPreservesRestoredSize,
               let restored = client.spatialRestoredSize ?? window?.bounds.size,
               let preferred = VisionWindowSizePolicy.restoredSize(restored, source: source) {
                geometry = .init(preferred: preferred, minimum: geometry.minimum, maximum: geometry.maximum)
            }
            waitingForDimensions = nil
            diagnosticSourceSize = source
            resize(to: geometry, token: token, in: scene)
            return
        }
        guard token != applied else { return }
        cancelResize()
        applied = token
        request(desired, in: scene)
    }

    private func releaseWhileWaiting(_ token: Token, in scene: UIWindowScene) {
        // Missing dimensions must release a previous window's ratio, but remain retryable
        // when a later catalog supplies them. Do not send on every observed client change.
        guard waitingForDimensions != token else { return }
        cancelResize()
        applied = nil
        attempted = nil
        waitingForDimensions = token
        diagnosticSourceSize = nil
        record(phase: 6)
        #if DEBUG
        print("NATIVE_GEOMETRY awaiting source dimensions; releasing previous aspect")
        #endif
        request(nil, in: scene)
    }

    private func record(phase: Int, source: CGSize? = nil, requested: CGSize? = nil, errorCode: Int? = nil) {
        let kind: Int
        if client?.connected != true { kind = 0 }
        else {
            switch client?.active {
            case .window?: kind = 1
            case .desktop?: kind = 2
            default: kind = 3
            }
        }
        VisionGeometryDiagnostics.record(phase: phase, scene: diagnosticScene, sourceKind: kind,
                                         source: diagnosticSourceSize ?? source, actual: window?.bounds.size, requested: requested,
                                         restriction: owningScene?.effectiveGeometry.resizingRestrictions.rawValue,
                                         errorCode: errorCode)
    }

    private func cancelResize() {
        resizeTask?.cancel()
        resizeTask = nil
        attempted = nil
        waitingForDimensions = nil
        requestGeneration = UUID()
    }

    private func isCurrentSourceToken(_ token: Token) -> Bool {
        guard let client, client.connected else { return false }
        return token == .source(client.connectedAt, client.active,
                                client.active == .desktop ? client.spatialDesktopVideoSize : nil)
    }

    /// `.uniform` preserves the *current* ratio, so first observe the requested ratio
    /// under freeform resizing. A request is a preference, not a completion callback.
    private func resize(to geometry: VisionWindowSizePolicy.WindowGeometry, token: Token, in scene: UIWindowScene) {
        cancelResize()
        attempted = token // Includes bounded failures; unrelated client updates must not restart it.
        applied = nil
        resizeTask = Task { @MainActor [weak self, weak scene] in
            guard let self, let scene else { return }
            for _ in 0..<2 {
                guard !Task.isCancelled, self.owningScene === scene, self.window?.windowScene === scene,
                      scene.activationState == .foregroundActive, self.isCurrentSourceToken(token) else { return }
                let generation = UUID()
                self.requestGeneration = generation
                self.requestFailed = false
                self.request(nil, in: scene, geometry: geometry, locked: false, generation: generation)
                var requestedSize = false
                var locking = false
                for _ in 0..<20 {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    guard !Task.isCancelled, self.owningScene === scene,
                          self.window?.windowScene === scene, self.requestGeneration == generation,
                          self.isCurrentSourceToken(token) else { return }
                    if self.requestFailed { break }
                    let actual = self.window?.bounds.size ?? .zero
                    let matches = VisionWindowSizePolicy.matchesAspect(actual, source: geometry.preferred)
                    let restriction = scene.effectiveGeometry.resizingRestrictions
                    if !requestedSize, restriction == .freeform {
                        requestedSize = true
                        self.request(geometry.preferred, in: scene, geometry: geometry, locked: false, generation: generation)
                    } else if locking {
                        if matches && restriction == .uniform {
                            self.applied = token
                            self.recordPresentationSize()
                            self.record(phase: 4, source: geometry.preferred)
                            #if DEBUG
                            print("NATIVE_GEOMETRY applied=\(actual) source=\(geometry.preferred) restriction=uniform")
                            #endif
                            self.resizeTask = nil
                            return
                        }
                    } else if requestedSize && matches && restriction == .freeform {
                        locking = true
                        // An explicit accepted size is required here: on the native simulator,
                        // a nil-size restriction-only update left effectiveGeometry freeform.
                        self.request(actual, in: scene, geometry: geometry, locked: true, generation: generation)
                    }
                }
            }
            self.record(phase: 7, source: geometry.preferred)
            // A late or constrained uniform update must not preserve an unconfirmed ratio.
            self.request(nil, in: scene, geometry: geometry)
            print("spatial window aspect not confirmed after bounded retries; remains retryable on activation or source change")
            self.resizeTask = nil
        }
    }

    private func request(_ desired: CGSize?, in scene: UIWindowScene,
                         geometry: VisionWindowSizePolicy.WindowGeometry? = nil,
                         locked: Bool = false, generation: UUID? = nil) {
        // UIKit can ignore restriction-only preferences with nil size. Explicitly preserve
        // the current size when releasing a previous ratio as well as when locking a new one.
        let actual = window?.bounds.size
        let requested = desired ?? actual.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        record(phase: locked ? 3 : (desired == nil ? 1 : 2), source: geometry?.preferred, requested: requested)
        #if DEBUG
        print("NATIVE_GEOMETRY request=\(String(describing: desired)) lock=\(locked) before=\(window?.bounds.size ?? .zero) restriction=\(scene.effectiveGeometry.resizingRestrictions.rawValue)")
        #endif
        scene.requestGeometryUpdate(.Vision(size: requested,
                                             minimumSize: geometry?.minimum ?? VisionWindowSizePolicy.minimum,
                                             maximumSize: geometry?.maximum ?? ((hasRestoredWorkspace || client?.spatialPreservesRestoredSize == true)
                                                 ? VisionWindowSizePolicy.streamMaximum : VisionWindowSizePolicy.openingMaximum),
                                             resizingRestrictions: locked ? .uniform : .freeform)) { [weak self, weak scene] error in
            guard let self, let scene, self.owningScene === scene else { return }
            if let generation {
                guard self.requestGeneration == generation else { return }
                self.requestFailed = true
            }
            self.record(phase: 5, source: geometry?.preferred, requested: requested, errorCode: (error as NSError).code)
            print("spatial window size request declined: \(error.localizedDescription)")
        }
    }
}
