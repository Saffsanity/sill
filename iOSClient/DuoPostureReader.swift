import SwiftUI

// Feeds DuoPosture (the pure rules, DuoPosture.swift) from iOS 27.1's foldable APIs, and hands the
// layouts what they need (docs/iphone-duo-plan.md). Nothing here runs before iOS 27.1, and on a
// device without a hinge iOS 27.1 reports none: the environment then says `unknown`, and every layout
// is what it was.
//
// - The hinge: `View.onHingeChange` at the app's root (SillApp, `readsDuoPosture()`), into the
//   environment as `\.duoEnvironment`. Its change is what redraws the screens that read it.
// - The fold: each screen reads it from its own GeometryReader (`DuoPosture.read`), as
//   `GeometryProxy.reservedRegions(kind: .division, options: .includeInactive)` gives it: in that
//   reader's own space. The stream screen hands it to its layouts and overlays as `\.duoFold`.
//   Before the hinge's first report the fold alone says which display this is and whether it is
//   folded (DuoPosture.hinge(reported:regionActive:)), so the first layout is already the pose's.
// - The stream screen hides the status bar on the inner display held upright
//   (DuoPosture.hidesStatusBar, `duoStatusBar`); every other screen keeps it.
//
// DEBUG: the harness's `-SillHinge closed|half|flat` stands in for all of it (ContentView's
// LayoutHarness): a hinge, and a fold given in the fake display's named space.

/// What the app's root knows of the hinge, for the screens below it.
struct DuoEnvironment: Equatable {
    var hinge: DuoPosture.Hinge = .unknown
    /// Where the fold comes from: iOS's reserved regions, or the harness's stand-in (in the fake
    /// display's space, `DuoPosture.displaySpace`; nil for none, as on the cover).
    var source: Source = .reservedRegions

    enum Source: Equatable {
        case reservedRegions
        case standIn(CGRect?)
    }
}

private struct DuoEnvironmentKey: EnvironmentKey {
    static let defaultValue = DuoEnvironment()
}

private struct DuoFoldKey: EnvironmentKey {
    static let defaultValue: FoldInfo = .inferred
}

extension EnvironmentValues {
    /// The hinge, from the app's root (`readsDuoPosture`) or the harness.
    var duoEnvironment: DuoEnvironment {
        get { self[DuoEnvironmentKey.self] }
        set { self[DuoEnvironmentKey.self] = newValue }
    }

    /// The fold across the stream screen, in its own space (StreamScreen sets it for its layouts and
    /// overlays, which share that space).
    var duoFold: FoldInfo {
        get { self[DuoFoldKey.self] }
        set { self[DuoFoldKey.self] = newValue }
    }
}

extension View {
    /// The app's root: the Duo's hinge into the environment. Nothing at all before iOS 27.1.
    func readsDuoPosture() -> some View { modifier(DuoPostureReader()) }

    /// The stream screen's status bar (DuoPosture.hidesStatusBar): hidden on the inner display held
    /// upright, as the approved boards drew those poses, so the picture keeps the 82 pt above the
    /// fold; shown everywhere else, as before. In a background, so that hiding and showing it never
    /// rebuilds the screen's views; off the Duo it adds nothing.
    func duoStatusBar(_ posture: DuoPosture, size: CGSize) -> some View {
        background {
            if DuoPosture.hidesStatusBar(posture.pose(size)) {
                Color.clear.statusBarHidden(true)
            }
        }
    }

    /// The stream screen's fold for everything under it, and, in DEBUG, one console line each time
    /// the posture changes ("duo: stream screen: book, the fold x 455.5–495.5 in the way, 951×669").
    func duoFold(_ posture: DuoPosture, size: CGSize, screen: String) -> some View {
        modifier(DuoFoldSetter(fold: posture.info(in: size), line: posture.describe(size), screen: screen,
                               known: posture.hinge != .unknown))
    }

    /// The same console line for a screen that keeps its fold to itself (the connect screen).
    func duoLog(_ posture: DuoPosture, size: CGSize, screen: String) -> some View {
        modifier(DuoLogger(line: posture.describe(size), screen: screen, known: posture.hinge != .unknown))
    }
}

private struct DuoPostureReader: ViewModifier {
    @State private var hinge: DuoPosture.Hinge = .unknown

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .environment(\.duoEnvironment, DuoEnvironment(hinge: hinge))
                .onHingeChange { _, new in
                    let now = DuoPosture.Hinge(new)
                    guard now != hinge else { return }      // it repeats itself while it settles
                    #if DEBUG
                    print("duo: hinge \(now.rawValue)" + (new.hinge.map { String(format: " %.1f°", $0.angle.degrees) } ?? ""))
                    #endif
                    hinge = now
                }
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
extension DuoPosture.Hinge {
    init(_ context: DeviceHingeContext) {
        guard let hinge = context.hinge else { self = .unknown; return }
        // A struct of statics, not an enum: anything else it may say later counts as partly open.
        if hinge.status == .closed {
            self = .closed
        } else if hinge.status == .fullyOpen {
            self = .fullyOpen
        } else {
            self = .partiallyOpen
        }
    }
}

extension DuoPosture {
    /// The posture as the view `geo` measures sees it: the hinge from the environment (before its
    /// first report, from the fold: `hinge(reported:regionActive:)`), the fold in that view's own
    /// space (the reserved region's frame, as iOS 27.1 gives it to a GeometryProxy; or the harness's
    /// stand-in, moved into that space). `unknown` before iOS 27.1, on a device without a hinge, and
    /// in the harness without `-SillHinge`.
    static func read(_ geo: GeometryProxy, _ environment: DuoEnvironment) -> DuoPosture {
        switch environment.source {
        case .standIn(let fold):
            guard environment.hinge != .unknown else { return .unknown }
            let origin = geo.frame(in: .named(displaySpace)).origin
            return DuoPosture(hinge: environment.hinge, fold: fold?.offsetBy(dx: -origin.x, dy: -origin.y))
        case .reservedRegions:
            if #available(iOS 27.1, *) {
                let region = geo.reservedRegions(kind: .division, options: .includeInactive).first
                let hinge = hinge(reported: environment.hinge, regionActive: region?.isActive)
                guard hinge != .unknown else { return .unknown }
                return DuoPosture(hinge: hinge, fold: region?.frame)
            }
            return .unknown
        }
    }
}

private struct DuoFoldSetter: ViewModifier {
    let fold: FoldInfo
    let line: String
    let screen: String
    let known: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.duoFold, fold)
            .modifier(DuoLogger(line: line, screen: screen, known: known))
    }
}

private struct DuoLogger: ViewModifier {
    let line: String
    let screen: String
    let known: Bool

    func body(content: Content) -> some View {
        #if DEBUG
        content.onChange(of: line, initial: true) { _, now in
            if known { print("duo: \(screen): \(now)") }
        }
        #else
        content
        #endif
    }
}

// MARK: - What the layouts ask

extension BarMetrics {
    /// This bar in the book pose (DuoPosture.bookBar): the right group's buttons and gaps as they
    /// clear the fold, the strip's width so that it ends short of it (nil: as before), the Settings
    /// panel no wider than the room past it. Unchanged anywhere else.
    func clearing(_ fold: FoldInfo, width: CGFloat) -> (bar: BarMetrics, stripWidth: CGFloat?) {
        // Menus, Aa, Keyboard, Desktop and Settings: Menus counted whether or not it shows, so the
        // bar never moves when the Mac's menus come and go.
        let book = DuoPosture.bookBar(width: width, fold: fold, padding: padding, gap: gap, buttonWidth: buttonWidth,
                                      compactButtonWidth: BarMetrics.compact.buttonWidth, buttons: 5,
                                      panelWidth: settingsWidth)
        guard book.stripWidth != nil else { return (self, nil) }
        let bar = BarMetrics(height: height, padding: padding, gap: book.gap,
                             buttonWidth: book.buttonWidth, buttonHeight: buttonHeight, buttonSpacing: buttonSpacing,
                             thumbWidth: thumbWidth, thumbHeight: thumbHeight, thumbRadius: thumbRadius,
                             thumbSpacing: thumbSpacing, thumbPad: thumbPad, thumbFade: thumbFade,
                             showsTextSize: showsTextSize, settingsWidth: book.panelWidth)
        return (bar, book.stripWidth)
    }
}

extension PortraitMetrics {
    /// The halves' controls but the trackpad: the bar, the key row, their gaps and paddings.
    var controlsHeight: CGFloat { padTop + barHeight + 2 * rowGap + keyBlockHeight + padBottom }
}

extension StreamClient {
    /// The Duo open flat, upright: the picture pane's shape (DuoPosture.paneAspect). The Mac fits a
    /// window to the pane once Aa is set, or on the virtual display; never the Desktop.
    func duoPaneAspect(textScale: Double?) -> CGFloat {
        var window = false
        if case .window = active { window = true }
        let fitted = window && (textScale != nil || settings.host?.stream?.onVirtualDisplay == true)
        return DuoPosture.paneAspect(video: videoSize, fitsWindowToPane: fitted)
    }
}
