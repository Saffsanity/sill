import UIKit
import ObjectiveC

/// The scene owns this sentinel independently of SwiftUI's representable lifetime. Closing a
/// window can dismantle its view before UIKit broadcasts didDisconnect; that must still stop the
/// owning stream. The scene reference is weak; the client is retained only until deterministic
/// disconnect cleanup completes, then remembered weakly for paired workspace reactivation. No sibling is inspected.
final class VisionSceneSessionLifecycle {
    private static var associationKey: UInt8 = 0
    private weak var scene: UIWindowScene?
    private var client: StreamClient?
    private weak var stoppedClient: StreamClient?
    private var observer: NSObjectProtocol?
    private var stopped = false

    static func attach(client: StreamClient, to scene: UIWindowScene) {
        if let existing = objc_getAssociatedObject(scene, &associationKey) as? VisionSceneSessionLifecycle {
            if existing.stopped {
                existing.stoppedClient = client
                if scene.activationState == .foregroundActive { existing.resumeForRestoration() }
                return
            }
            if existing.client !== client {
                existing.client?.stopSpatialWindow()
                existing.client = client
            }
            return
        }
        let lifecycle = VisionSceneSessionLifecycle(scene: scene, client: client)
        objc_setAssociatedObject(scene, &associationKey, lifecycle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private init(scene: UIWindowScene, client: StreamClient) {
        self.scene = scene
        self.client = client
        observeDisconnect()
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func observeDisconnect() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let current = self.scene, let disconnected = note.object as? UIWindowScene,
                  disconnected === current else { return }
            self.stopped = true
            let stoppedClient = self.client
            self.client = nil
            self.stoppedClient = stoppedClient
            stoppedClient?.stopSpatialWindow()
            self.observeReactivation()
        }
    }

    private func observeReactivation() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let current = self.scene, let activated = note.object as? UIWindowScene,
                  activated === current, self.stopped else { return }
            self.resumeForRestoration()
        }
    }

    private func resumeForRestoration() {
        stopped = false
        client = stoppedClient
        stoppedClient = nil
        client?.resumeSpatialWorkspace()
        observeDisconnect()
    }
}
