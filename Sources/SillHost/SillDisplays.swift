import Foundation
import CoreGraphics
import ScreenCaptureKit

/// Every display Sill makes, in one place (docs/virtual-desktop-plan.md §9 as revised 2026-11-18, phase 2b): one
/// manager for the stage's display (a picked window's, VirtualStage) and the Desktop's (a Mac with no working screen's,
/// PR #200; the Virtual Desktop's next), so the Virtual Desktop and the stage never make two of one role, nor one in a way
/// the other does not know. It owns, for each role (SillDisplayRole):
/// - making it, with the role's identity (the private CGVirtualDisplay, VirtualDisplay.swift), and waiting until it is
///   online at its mode and until ScreenCaptureKit lists it;
/// - the guard for #380 (DisplayMakeGuard): its marker just before the private calls, taken back once the display came
///   up or failed; whether the guard holds;
/// - its lost callback: macOS removed it on its own (a sleep, display arbitration), handed to the role's `onLost`;
/// - removing it;
/// - telling the catalog which displays are Sill's (the stage's IDs, `WindowCatalog.stageDisplayIDs`, kept for the run,
///   so a stage display that went is never one of the Desktop's stops).
///
/// What a role does with its display stays its own: the stage places its window, measures the menu bar and remakes the
/// display for it; the coordinator decides when the Desktop's is made and when it goes (HeadlessDesktopPolicy.Watch).
/// Each asks this for the display, and each display's lines are its owner's, as they were.
///
/// Threading: main actor, as the stage and the coordinator. A display's termination handler runs on its private queue
/// and hops here with `Task { @MainActor }`.
@MainActor
final class SillDisplays {
    let catalog: WindowCatalog
    /// The guard for #380 (Sill.app's, and a test host's under SILL_TEST_MAKE_GUARD; nil in the CLI, which keeps none).
    var makeGuard: DisplayMakeGuard.Store?
    /// What a role does when macOS removes its display on its own (the window server: a sleep, display arbitration),
    /// called on the main actor once the display is forgotten here. The stage puts its window home and stages it again. A
    /// role with none is told nothing, and its display is kept as it was until its owner removes it (the Desktop's:
    /// the coordinator finds it offline at the next Desktop, as #200 did).
    var onLost: [SillDisplayRole: () -> Void] = [:]

    private var made: [SillDisplayRole: VirtualDisplay] = [:]
    private var listedBy: [SillDisplayRole: SCDisplay] = [:]
    /// Bumped per display made, so a late termination callback for an old display is ignored (the stage's rule).
    private var generation = 0
    private var generations: [SillDisplayRole: Int] = [:]

    init(catalog: WindowCatalog) {
        self.catalog = catalog
    }

    /// The role's display, while it exists.
    func display(_ role: SillDisplayRole) -> VirtualDisplay? { made[role] }

    /// ScreenCaptureKit's listing of the role's display, once `waitUntilListed` found it.
    func listed(_ role: SillDisplayRole) -> SCDisplay? { listedBy[role] }

    /// Whether the guard for #380 holds: Sill stopped while making a display two runs in a row, and makes none by itself
    /// until Try Again.
    var guardHolds: Bool { makeGuard?.holds == true }

    /// Just before the private calls that make a display of `role`: the guard's marker, written and synced. The stage
    /// writes it before its old display goes too (#380's stops came right after "Removed virtual display N", a remake).
    func willMake(_ role: SillDisplayRole) {
        makeGuard?.willMake(role.rawValue)
    }

    /// Makes `role`'s display at `widthPt`×`heightPt` points, `scale` and `refreshHz`, with the role's identity, in place
    /// of the role's old one, which its owner removed first. A throw is VirtualDisplay's (a missing private method, a
    /// size out of bounds, a mode refused), with the guard's marker taken back as a make that failed. The display is
    /// online a moment later (`waitUntilOnline`).
    func make(_ role: SillDisplayRole, widthPt: Int, heightPt: Int, scale: Int = 2, refreshHz: Double) throws -> VirtualDisplay {
        let d: VirtualDisplay
        do {
            d = try VirtualDisplay(name: role.name, widthPt: widthPt, heightPt: heightPt, scale: scale, refreshHz: refreshHz,
                                   vendorID: role.vendor, productID: role.product, serialNum: role.serial)
        } catch {
            makeGuard?.made(cameUp: false)
            throw error
        }
        generation += 1
        let gen = generation
        generations[role] = gen
        made[role] = d
        listedBy[role] = nil
        // Never one of the Desktop's stops (DesktopDisplays.role), even once it has gone.
        if role == .stage { catalog.stageDisplayIDs.insert(d.displayID) }
        // Fires on the display's private queue; the roles live on the main actor.
        d.onTerminated = { [weak self] in Task { @MainActor [weak self] in self?.lost(role, generation: gen) } }
        return d
    }

    /// Waits until `d` is online at its mode (VirtualDisplay.waitUntilOnline, which selects it with public CoreGraphics
    /// if macOS brought it up at another), then takes the guard's marker back: a display that came up resets its count.
    func waitUntilOnline(_ d: VirtualDisplay, timeout: TimeInterval = 3) async -> Bool {
        let online = await d.waitUntilOnline(timeout: timeout)
        makeGuard?.made(cameUp: d.bounds.width > 0)
        return online
    }

    /// Waits until ScreenCaptureKit lists `d`, `role`'s display, as it lists new displays a little after CoreGraphics
    /// does, and keeps the listing (`listed`). Bounded: without Screen Recording this call has been seen to never return
    /// while a virtual display exists. Nil when it never did within `timeout`, or `d` is no longer the role's display.
    func waitUntilListed(_ d: VirtualDisplay, as role: SillDisplayRole, timeout: TimeInterval = 3) async -> SCDisplay? {
        let t1 = Date()
        var listed: SCDisplay?
        while Date().timeIntervalSince(t1) < timeout {
            let remaining = max(0.2, timeout - Date().timeIntervalSince(t1))
            if let c = await WindowCatalog.shareableContent(excludingDesktopWindows: true, onScreenWindowsOnly: true, timeout: remaining),
               let found = c.displays.first(where: { $0.displayID == d.displayID }) { listed = found; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let listed, made[role] === d else { return nil }
        listedBy[role] = listed
        return listed
    }

    /// Removes `role`'s display at once (VirtualDisplay.destroy: macOS takes it away; the window server moves any window
    /// on it to a real display): the ID it had, for its owner's line, or nil when there was none. Call it after the
    /// windows Sill put there went home (VirtualStage.releaseWindow, StageRelease).
    @discardableResult
    func remove(_ role: SillDisplayRole) -> CGDirectDisplayID? {
        listedBy[role] = nil
        guard let d = made.removeValue(forKey: role) else { return nil }
        let id = d.displayID
        d.destroy()
        return id
    }

    /// macOS tore the display down on its own (its termination handler; `destroy` may fire it too, which is ignored, as
    /// is an older display's). Forgotten here, then the role's `onLost`; a role with none keeps it as it was.
    private func lost(_ role: SillDisplayRole, generation gen: Int) {
        guard gen == generations[role], made[role] != nil, let handler = onLost[role] else { return }
        made[role] = nil
        listedBy[role] = nil
        handler()
    }
}
