import SwiftUI

/// The Full-Screen Viewer on an iPhone (docs/iphone-viewer-plan.md), a VNC viewer's arrangement:
/// the picture takes the whole screen, pinch zooms it (ViewerCamera) and the pointer pushing the
/// screen's edges pans it; the whole screen is the trackpad (TrackpadSurface: drag moves the
/// pointer, tap clicks, two fingers scroll, press and hold drags, three fingers are the Mac's
/// gestures; pointer travel is divided by the zoom). Windows, apps, menus, keys and settings wait
/// behind a slim bar at the top, which hides to a tab. Settings › This iPhone › Full-Screen Viewer
/// (`StreamClient.viewerModeKey`, off by default); StreamScreen draws it in place of the phone's
/// arrangements, held upright or sideways.

/// Which of the bar's pull-downs is open.
enum ViewerPanel: Equatable { case windows, keys }

struct ViewerScreen: View {
    @ObservedObject var client: StreamClient
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    @Binding var windowMenu: UInt32?
    @Binding var latched: KeyModifiers
    let overlay: InputOverlayProxy
    let settingsOpen: Bool
    let setSettings: (Bool, Bool) -> Void
    let menusOpened: () -> Void
    let menusClosed: () -> Void
    let onPanelSize: (CGSize) -> Void
    let pairThisDevice: () -> Void
    let takeTour: () -> Void
    let linkLine: String?

    @State private var camera = ViewerCamera()
    @State private var keyboardFrame: CGRect = .null
    @AppStorage("Sill.viewerBarShown") private var barShown = true
    @State private var panel: ViewerPanel? = nil
    @State private var pinchAt: CGPoint? = nil
    /// The pointer as this screen last put it, for Fill's focus.
    @State private var lastPointer: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let bounds = geo.frame(in: .global)
            let overlap = bounds.intersection(keyboardFrame)
            // Keep the camera above the keyboard even though the stream screen ignores its safe area.
            let visibleSize = CGSize(width: size.width, height: overlap.isNull || overlap.isEmpty
                                     ? size.height : max(1, overlap.minY - bounds.minY))
            ZStack(alignment: .top) {
                Color.black

                picture
                    .frame(width: camera.rect.width, height: camera.rect.height)
                    .position(x: camera.rect.midX, y: camera.rect.midY)

                // The whole screen is the trackpad. It sits over the picture, so the picture's
                // direct-touch overlay (kept for the keyboard's first responder) never sees a touch.
                TrackpadView(send: { client.sendInput($0) },
                             setPointer: { p in
                                 client.setOwnPointer(p, from: .trackpad)
                                 lastPointer = p
                                 camera.follow(p)
                             },
                             feed: { let f = client.pointerFeedState; return (f.anchor, f.reseeds) },
                             onFingers: { client.trackpadFingers($0) },
                             latched: latched,
                             onModifiersConsumed: { latched = [] },
                             sendGesture: { client.sendGesture($0, fingers: $1) },
                             travelScale: camera.zoom,
                             onPinch: pinch)

                LinkLineView(text: linkLine)
                    .padding(.top, barShown ? 64 : 12)
                    .allowsHitTesting(false)

                topBar
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                if drawerOpen {
                    dim { drawerOpen = false }
                    AppDrawer(client: client, drawerOpen: $drawerOpen)
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 10)
                        .padding(.top, 60)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if settingsOpen {
                    dim { setSettings(false, true) }
                    HostSettingsPanel(client: client, close: { setSettings(false, true) },
                                      pairThisDevice: pairThisDevice, takeTour: takeTour)
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 10)
                        .padding(.top, 60)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
            .onAppear {
                layout(visibleSize, panel: size)
                #if DEBUG
                // -SillViewerZoom 2.5: the harness's zoomed-in picture (docs/iphone-viewer-plan.md).
                let z = UserDefaults.standard.double(forKey: "SillViewerZoom")
                if z > 1 { camera.pinch(scale: CGFloat(z), from: CGPoint(x: size.width / 2, y: size.height / 2),
                                        to: CGPoint(x: size.width / 2, y: size.height / 2)) }
                #endif
            }
            .onChange(of: size) { _, now in layout(visibleSize, panel: now) }
            .onChange(of: client.videoSize) { _, _ in layout(visibleSize, panel: size) }
            .onChange(of: visibleSize) { _, now in
                layout(now, panel: size)
                if let lastPointer { camera.follow(lastPointer) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                updateKeyboard(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { note in
                updateKeyboard(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardFrame = .null
            }
        }
        .background(Color.black)
        .animation(.easeOut(duration: 0.18), value: barShown)
        .animation(.easeOut(duration: 0.18), value: panel)
        .animation(.easeOut(duration: 0.18), value: drawerOpen)
        .animation(.easeOut(duration: 0.18), value: settingsOpen)
    }

    private func updateKeyboard(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeOut(duration: duration)) { keyboardFrame = frame }
    }

    private func layout(_ size: CGSize, panel: CGSize) {
        camera.layout(screen: size, video: client.videoSize)
        onPanelSize(panel)
    }

    private func pinch(_ state: UIGestureRecognizer.State, _ scale: CGFloat, _ at: CGPoint) {
        switch state {
        case .began, .changed:
            camera.pinch(scale: scale, from: pinchAt ?? at, to: at)
            pinchAt = at
        default:
            pinchAt = nil
        }
    }

    private var picture: some View {
        ZStack {
            StreamView(client: client)
            InputOverlay(videoSize: client.videoSize,
                         send: { client.sendInput($0) },
                         setOwnPointer: { client.setOwnPointer($0, from: $1) },
                         proxy: overlay,
                         isKeyboardShown: $keyboardShown,
                         latchedModifiers: latched,
                         onModifiersConsumed: { latched = [] },
                         sendGesture: { client.sendGesture($0, fingers: $1) })
        }
    }

    private func dim(_ close: @escaping () -> Void) -> some View {
        Color.black.opacity(0.5)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { close() } }
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    // MARK: The bar

    @ViewBuilder private var topBar: some View {
        if barShown {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    barButton("rectangle.on.rectangle", "Windows", open: panel == .windows) { toggle(.windows) }
                    barButton("square.grid.2x2", "Apps", open: drawerOpen) {
                        panel = nil
                        if settingsOpen { setSettings(false, true) }
                        drawerOpen.toggle()
                    }
                    if client.menus.hasMenus {
                        MacMenuButton(client: client, width: 44, height: 40, radius: 12, iconSize: 18, spacing: 0,
                                      onOpen: menusOpened, onClose: menusClosed)
                    }
                    barButton("keyboard", "Keyboard", open: keyboardShown) { overlay.toggleKeyboard() }
                    barButton("command", "Keys", open: panel == .keys || !latched.isEmpty) { toggle(.keys) }
                    barButton(camera.isZoomedIn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                              camera.isZoomedIn ? "Fit" : "Fill", open: false) {
                        withAnimation(.easeOut(duration: 0.2)) { camera.toggleFill(focus: lastPointer) }
                    }
                    barButton("gearshape", "Settings", open: settingsOpen) {
                        panel = nil
                        drawerOpen = false
                        setSettings(!settingsOpen, true)
                    }
                    barButton("chevron.up", "Hide the bar", open: false) {
                        panel = nil
                        barShown = false
                    }
                }
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .environment(\.colorScheme, .dark)

                switch panel {
                case .windows: windowsPanel
                case .keys: keysPanel
                case nil: EmptyView()
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            // A tab at the top centre brings the bar back.
            Button(action: { barShown = true }) {
                Capsule().fill(Color.white.opacity(0.55))
                    .frame(width: 54, height: 5)
                    .frame(width: 120, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the bar")
            .transition(.opacity)
        }
    }

    private func toggle(_ p: ViewerPanel) {
        drawerOpen = false
        if settingsOpen { setSettings(false, true) }
        panel = panel == p ? nil : p
    }

    private func barButton(_ symbol: String, _ label: String, open: Bool, action: @escaping () -> Void) -> some View {
        BarButton(open: open, width: 44, height: 40, radius: 12, accessibilityLabel: label, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(open ? Palette.accent : Color.white)
        }
    }

    private var windowsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { client.select(.desktop); panel = nil }) {
                Label("Desktop", systemImage: "desktopcomputer")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(client.active == .desktop ? Palette.accent : Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(client.active == .desktop ? Palette.controlOpen : Palette.control))
            }
            .buttonStyle(.plain)
            WindowStrip(client: client, width: 104, height: 66, menuFor: $windowMenu)
                .frame(height: 86)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
    }

    private var keysPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            KeyRow(metrics: .phone, keys: .full, latched: $latched, keyboardShown: keyboardShown,
                   send: { client.sendFromKeyRow($0) },
                   toggleKeyboard: { overlay.toggleKeyboard() },
                   showSpotlight: client.active == .desktop)
        }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .environment(\.colorScheme, .dark)
            .transition(.opacity)
    }
}
