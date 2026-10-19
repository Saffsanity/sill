import Foundation
import StreamProtocol

/// Reset phase without replacing the group identity on systems with native phase overrides.
/// Older systems retain the existing generation-key reset behavior.
struct VisionToolbarHoverCycle {
    private(set) var generation = 0
    private var scrollActive = false

    func groupID(nativeReset: Bool) -> String {
        nativeReset ? "toolbar" : "toolbar-\(generation)"
    }

    mutating func reset() { generation += 1 }
    mutating func resetScrollEpisode() { scrollActive = false }

    mutating func input(_ event: InputEvent, automatic: Bool, admitted: Bool) {
        guard admitted else { return }
        let controlling: Bool
        switch event {
        case .pointer(.leftDown, _, _), .pointer(.rightDown, _, _),
             .key(_, true, _), .text: controlling = true
        case .scroll: controlling = !scrollActive
        case .scrollGesture(.began, _, _), .scrollGesture(.momentumBegan, _, _):
            controlling = !scrollActive
            scrollActive = true
        case .scrollGesture(.ended, _, _), .scrollGesture(.momentumEnded, _, _):
            controlling = false
            scrollActive = false
        default: controlling = false
        }
        if automatic && controlling { reset() }
    }
}

#if os(visionOS)
import SwiftUI

/// All activation stays in the system hover compositor. No gaze position or hover state enters
/// application state, and revealing the toolbar never changes the stream's measured viewport.
struct VisionToolbarReveal: ViewModifier {
    let automatic: Bool
    let reduceMotion: Bool
    let group: HoverEffectGroup
    func body(content: Content) -> some View {
        content
            // Keep the bar's compositor fade separate from its visible glance target.
            .contentShape(.hoverEffect, Rectangle())
            .hoverEffect(in: group) { effect, active, _ in
                effect.animation(.easeInOut(duration: reduceMotion ? 0 : 0.18).delay(active ? 0.65 : 1.0)) {
                    $0.opacity(!automatic || active ? 1 : 0)
                }
            }
    }
}

/// A translucent surface remains visible while Auto is collapsed. It shares
/// the bars' hover group and stays centered behind each toolbar, rather than on a rail
/// between the picture and toolbar. It is a glance target, with no tap action to compete
/// with the controls above it in the ornament's hit-test hierarchy.
struct VisionToolbarGlanceTarget: View {
    let vertical: Bool
    let length: CGFloat
    let reduceMotion: Bool
    let group: HoverEffectGroup

    var body: some View {
        Capsule()
            .fill(.black.opacity(0.50))
            .frame(width: vertical ? 24 : length, height: vertical ? length : 24)
            .contentShape(.hoverEffect, Capsule())
            // Native highlight belongs only to this pill; only the fade joins the shared group.
            .hoverEffect(.highlight)
            .hoverEffect(in: group) { effect, active, _ in
                effect.animation(.easeInOut(duration: reduceMotion ? 0 : 0.18).delay(active ? 0.65 : 1.0)) {
                    $0.opacity(active ? 0 : 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// On visionOS 26+, looking back at the picture preserves an already revealed
/// group but cannot reveal an inactive group. Real remote input resets the
/// scene-local group to begin a fresh, inactive phase.
struct VisionToolbarPreserve: ViewModifier {
    let group: HoverEffectGroup
    func body(content: Content) -> some View {
        if #available(visionOS 26.0, *) {
            content
                .contentShape(Rectangle())
                .hoverEffect(in: group.behavior(.preservesGroup)) { effect, _, _ in effect }
        } else {
            content
        }
    }
}

/// Exactly one source owns the override for the scene's shared group. A disabled empty
/// effect sends app-initiated phase resets without adding another activation surface.
struct VisionToolbarReset: ViewModifier {
    let group: HoverEffectGroup
    let generation: Int
    let nativeReset: Bool

    func body(content: Content) -> some View {
        if #available(visionOS 26.0, *), nativeReset {
            content.hoverEffect(
                .empty
                    .hoverEffectGroup(group)
                    .hoverEffectPhaseOverride(.inactiveTemporarily(trigger: generation))
                    .hoverEffectDisabled(true)
            )
        } else {
            content
        }
    }
}
#endif
