import SwiftUI
import UIKit

// MARK: - Deployment compatibility

/// SwiftUI conveniences introduced after iOS 16, preserving newer behaviour where possible and
/// omitting only decorative behaviour where the older system has no equivalent.
extension View {
    func sillOnChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        _ action: @escaping (_ old: Value, _ new: Value) -> Void
    ) -> some View {
        modifier(SillOnChange(value: value, initial: initial, action: action))
    }

    @ViewBuilder
    func sillCoordinateSpace(_ name: some Hashable) -> some View {
        if #available(iOS 17.0, *) {
            coordinateSpace(.named(name))
        } else {
            coordinateSpace(name: name)
        }
    }

    @ViewBuilder
    func sillSafeAreaPadding(_ insets: EdgeInsets) -> some View {
        if #available(iOS 17.0, *) {
            safeAreaPadding(insets)
        } else {
            padding(insets)
        }
    }

    @ViewBuilder
    func sillScrollPresentation() -> some View {
        if #available(iOS 17.0, *) {
            scrollIndicatorsFlash(onAppear: true)
                .scrollBounceBehavior(.basedOnSize)
        } else if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    func sillScrollPresentation<Value: Equatable>(trigger: Value) -> some View {
        if #available(iOS 17.0, *) {
            scrollIndicatorsFlash(onAppear: true)
                .scrollIndicatorsFlash(trigger: trigger)
                .scrollBounceBehavior(.basedOnSize)
        } else if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    func sillSymbolEffect<Value: Equatable>(trigger: Value, reduceMotion: Bool) -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: trigger)
                .symbolEffectsRemoved(reduceMotion)
        } else {
            transition(.opacity)
        }
    }

    @ViewBuilder
    func sillDefaultScrollAnchor(_ anchor: UnitPoint) -> some View {
        if #available(iOS 17.0, *) {
            defaultScrollAnchor(anchor)
        } else {
            self
        }
    }

    @ViewBuilder
    func sillWarningFeedback<Value: Equatable>(trigger: Value) -> some View {
        if #available(iOS 17.0, *) {
            sensoryFeedback(.warning, trigger: trigger)
        } else {
            sillOnChange(of: trigger) { _, _ in
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    @ViewBuilder
    func sillSelectionFeedback<Value: Equatable>(trigger: Value) -> some View {
        if #available(iOS 17.0, *) {
            sensoryFeedback(.selection, trigger: trigger)
        } else {
            sillOnChange(of: trigger) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }
}

private struct SillOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (_ old: Value, _ new: Value) -> Void
    @State private var previous: Value

    init(value: Value, initial: Bool, action: @escaping (_ old: Value, _ new: Value) -> Void) {
        self.value = value
        self.initial = initial
        self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if initial { action(value, value) }
            }
            .onChange(of: value) { new in
                let old = previous
                previous = new
                action(old, new)
            }
    }
}

enum SillAccessibility {
    static func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    static func layoutChanged() {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    static func screenChanged() {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}

@main
struct SillApp: App {
    /// Only `buildMenu(with:)`: the Mac's menus in the iPad's menu bar on iPadOS 26 (SillAppDelegate).
    @UIApplicationDelegateAdaptor(SillAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // iOS 27.1 on the iPhone Duo: the hinge for the layouts (DuoPostureReader); nothing
            // before iOS 27.1 or on a device without a hinge.
            ContentView()
                .readsDuoPosture()
        }
    }
}
