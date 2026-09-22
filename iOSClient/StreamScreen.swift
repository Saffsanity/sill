import SwiftUI
import StreamProtocol

// MARK: - Palette

extension Color {
    /// 0xRRGGBB, the way the design boards write colours.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    static let bar = Color(hex: 0x16181C)          // top bar and drawer background
    static let control = Color(hex: 0x23262C)      // bar buttons, search field, selected row
    static let controlOpen = Color(hex: 0x2C3550)  // a bar button whose thing is showing
    static let accent = Color(hex: 0x9BB7FF)
    static let text = Color(hex: 0xEEF0F3)
    static let barLabel = Color(hex: 0xC4C9D1)     // the 11pt labels under the bar icons
    static let muted = Color(hex: 0xA4ABB5)        // section headers, window counts, placeholder
    static let panel = Color(hex: 0x1F2126)        // the stream panel behind the video
    static let trackpad = Color(hex: 0x101215)     // the portrait trackpad's well
    static let thumbBody = Color(hex: 0x26282D)    // thumbnail placeholder
    static let thumbTitleBar = Color(hex: 0x34373D)
    static let iconFallback = Color(hex: 0x3A3D44) // two-letter app badge
}

// MARK: - Layout selection

/// Which layout a screen gets, decided from its size in points alone: no device check, no idiom,
/// so an iPad at an odd split size and an iPhone each get the layout their dimensions deserve.
/// The numbers are written for the iPhone Duo and its four postures:
///
/// * inner display, unfolded landscape — 1000×710 → `.innerLandscape` (top bar over the stream)
/// * inner display, portrait or half-folded — 710×1000 → `.innerPortrait` (stream over controls)
/// * outer display, on its side — 710×500 → `.outerLandscape`
/// * outer display, upright — 500×710 → `.outerPortrait`
///
/// The outer display is not a different app: it is the same two layouts at compact sizes, because
/// the posture only changed how much room there is, not what the screen is for. The thresholds sit
/// between those sizes with room to spare — 600 separates the 500 pt outer width from the 710 pt
/// inner one, and 560 the 500 pt outer height from the inner 710.
enum DuoLayout {
    case innerLandscape, innerPortrait, outerPortrait, outerLandscape

    /// Narrower than this and taller than wide: the outer display held upright.
    static let outerMaxWidth: CGFloat = 600
    /// Shorter than this and wider than tall: the outer display on its side.
    static let outerMaxHeight: CGFloat = 560

    static func of(_ size: CGSize) -> DuoLayout {
        if size.height > size.width, size.width < outerMaxWidth { return .outerPortrait }
        if size.width > size.height, size.height < outerMaxHeight { return .outerLandscape }
        return size.width > size.height ? .innerLandscape : .innerPortrait
    }
}

// MARK: - Screen

struct StreamScreen: View {
    @ObservedObject var client: StreamClient
    @State private var drawerOpen = false
    @State private var keyboardShown = false
    /// Modifiers held down by the portrait key row until the next key, character or click uses
    /// them. Lives up here so rotating the iPad does not drop a half-typed shortcut.
    @State private var latched: KeyModifiers = []
    /// The bar's Keyboard button drives the overlay's first responder through this.
    @State private var overlay = InputOverlayProxy()
    /// The Aa button's text scale, device points per Mac point; nil leaves the Mac window alone.
    /// Up here, like `latched`, so it survives rotation and both layouts share it.
    @State private var textScale: Double? = nil
    /// The stream panel's size in points, reported by whichever layout is showing.
    @State private var panelSize: CGSize = .zero
    /// The viewport send waiting out its debounce, if any.
    @State private var pendingViewport: Task<Void, Never>? = nil

    /// What the Aa button cycles through. Off first: the Mac window is left alone until asked.
    static let textScaleSteps: [Double?] = [nil, 1.0, 1.25, 1.5, 0.8]

    #if DEBUG
    /// DEBUG only, for the layout harness: start on a given state so a posture can be photographed
    /// with the drawer already open. `StreamScreen(client:)` still means exactly what it did.
    init(client: StreamClient, drawerOpen: Bool = false, keyboardShown: Bool = false) {
        self.client = client
        _drawerOpen = State(initialValue: drawerOpen)
        _keyboardShown = State(initialValue: keyboardShown)
    }
    #endif

    var body: some View {
        // Which layout, and at which size — see `DuoLayout` for the thresholds and the Duo posture
        // behind each one.
        GeometryReader { geo in
            switch DuoLayout.of(geo.size) {
            case .innerLandscape:
                landscape(bar: .regular)
            case .outerLandscape:
                landscape(bar: .compact)
            case .innerPortrait:
                portrait(metrics: .regular)
            case .outerPortrait:
                portrait(metrics: .compact)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            // A fresh connection streams nothing: the Mac no longer picks a window, the iPad does.
            if client.active == .none { drawerOpen = true }
            sendViewport()
        }
        .onChange(of: client.active) { _, source in
            withAnimation(.easeOut(duration: 0.18)) { drawerOpen = (source == .none) }
            // The host sizes a window as it selects it, from the last viewport it has; this repeat
            // is for a host that restarted, or a window that was picked from the Mac's side.
            sendViewport()
        }
        .onChange(of: client.connected) { _, up in
            if up { sendViewport() }
        }
        // Rotation animates, and a Mac window resize restarts the stream, so let the size settle.
        .onChange(of: panelSize) { _, _ in sendViewport(after: 0.25) }
        // Same wait for Aa: cycling from Off to 0.8× passes three sizes nobody wants the Mac to try.
        .onChange(of: textScale) { _, _ in sendViewport(after: 0.25) }
    }

    // MARK: Viewport

    /// Tells the host the panel size and text scale, now or after `delay` seconds. A newer call
    /// replaces a pending one, so a burst of changes sends only the last. Nothing goes out until the
    /// panel has been measured, or while disconnected.
    private func sendViewport(after delay: Double = 0) {
        pendingViewport?.cancel()
        pendingViewport = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            guard client.connected, panelSize.width > 0, panelSize.height > 0 else { return }
            client.sendViewport(Viewport(width: Double(panelSize.width),
                                         height: Double(panelSize.height),
                                         scale: textScale))
        }
    }

    private func cycleTextScale() {
        let steps = Self.textScaleSteps
        let index = steps.firstIndex(of: textScale) ?? 0
        textScale = steps[(index + 1) % steps.count]
    }

    private func landscape(bar: BarMetrics) -> some View {
        VStack(spacing: 0) {
            TopBar(client: client, metrics: bar, drawerOpen: $drawerOpen,
                   keyboardShown: $keyboardShown,
                   textScale: textScale,
                   toggleKeyboard: { overlay.toggleKeyboard() },
                   cycleTextScale: cycleTextScale)
            contentArea
        }
    }

    private func portrait(metrics: PortraitMetrics) -> some View {
        PortraitStreamScreen(client: client, metrics: metrics, drawerOpen: $drawerOpen,
                             keyboardShown: $keyboardShown, latched: $latched,
                             overlay: overlay,
                             onPanelSize: { panelSize = $0 })
    }

    private var streamShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private var contentArea: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            ZStack {
                StreamView(client: client)
                // Same frame as the video, so a touch maps straight onto the streamed frame.
                InputOverlay(videoSize: client.videoSize,
                             send: { client.sendInput($0) },
                             proxy: overlay,
                             isKeyboardShown: $keyboardShown,
                             latchedModifiers: latched,
                             onModifiersConsumed: { latched = [] })
            }
            .background(Palette.panel)
            .clipShape(streamShape)
            .overlay(streamShape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            // The panel itself, inside the padding: the size the host fits the Mac window to.
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { panelSize = $0 })
            .padding(8)

            // The dim comes after the overlay on purpose: with the drawer open a tap on the dim
            // closes the drawer instead of clicking the Mac.
            if drawerOpen {
                Color.black.opacity(0.58)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
                    .accessibilityHidden(true)
                    .transition(.opacity)

                AppDrawer(client: client, drawerOpen: $drawerOpen)
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Top bar

/// The landscape top bar's numbers. The inner display gets the Main board's roomy bar; the outer
/// display gets the Laptop board's compact one, which is 8 pt shorter and tighter all round — on a
/// 500 pt tall screen the bar is a sixth of everything there is, so every point it gives back is a
/// point of Mac. The compact bar also drops the Aa button, exactly as the Laptop board does: with
/// this little room, a setting you change once is the first thing that should go. The scale it set
/// still applies there; it lives in `StreamScreen`, not in the bar.
struct BarMetrics {
    let height: CGFloat
    let padding: CGFloat
    let gap: CGFloat
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    let buttonSpacing: CGFloat      // between a button's icon and its label
    let thumbWidth: CGFloat
    let thumbHeight: CGFloat
    let thumbRadius: CGFloat
    let thumbSpacing: CGFloat
    let thumbPad: CGFloat
    let thumbFade: Double
    let showsTextSize: Bool

    static let regular = BarMetrics(height: 86, padding: 22, gap: 12,
                                    buttonWidth: 66, buttonHeight: 66, buttonSpacing: 4,
                                    thumbWidth: 104, thumbHeight: 66, thumbRadius: 10,
                                    thumbSpacing: 16, thumbPad: 10, thumbFade: 0.86,
                                    showsTextSize: true)

    static let compact = BarMetrics(height: 78, padding: 14, gap: 12,
                                    buttonWidth: 64, buttonHeight: 58, buttonSpacing: 3,
                                    thumbWidth: 92, thumbHeight: 58, thumbRadius: 9,
                                    thumbSpacing: 14, thumbPad: 10, thumbFade: 0.88,
                                    showsTextSize: false)
}

private struct TopBar: View {
    @ObservedObject var client: StreamClient
    let metrics: BarMetrics
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    let textScale: Double?
    let toggleKeyboard: () -> Void
    let cycleTextScale: () -> Void

    var body: some View {
        HStack(spacing: metrics.gap) {
            button(open: drawerOpen, symbol: "magnifyingglass", label: "Apps",
                   accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                   action: { withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() } })

            WindowStrip(client: client, width: metrics.thumbWidth, height: metrics.thumbHeight,
                        radius: metrics.thumbRadius, spacing: metrics.thumbSpacing,
                        pad: metrics.thumbPad, fade: metrics.thumbFade)

            if metrics.showsTextSize {
                // Text size: the host resizes the Mac window to the panel divided by this scale, so
                // a bigger number means a smaller Mac window and bigger text here. Off leaves the
                // window as it is (and does not put it back).
                BarButton(open: false, width: metrics.buttonWidth, height: metrics.buttonHeight,
                          accessibilityLabel: textScale.map { "Text size, \(Self.scaleLabel($0)) times" }
                              ?? "Text size, off",
                          action: cycleTextScale) {
                    VStack(spacing: 2) {
                        Text("Aa")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Text(textScale.map { Self.scaleLabel($0) + "×" } ?? "Off")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.barLabel)
                    }
                }
            }

            button(open: keyboardShown, symbol: "keyboard", label: "Keyboard",
                   accessibilityLabel: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                   action: toggleKeyboard)

            button(open: client.active == .desktop, symbol: "desktopcomputer", label: "Desktop",
                   accessibilityLabel: "Show the full Mac desktop",
                   action: { client.select(.desktop) })
        }
        .frame(height: metrics.height)
        .padding(.horizontal, metrics.padding)
        // The bar's colour runs to the screen edge; its contents stay inside the safe area.
        .background(Palette.bar.ignoresSafeArea(edges: .top))
    }

    /// 1.0, 1.25, 1.5, 0.8: two decimals, less a trailing zero, but never fewer than one.
    static func scaleLabel(_ scale: Double) -> String {
        let text = String(format: "%.2f", scale)
        return text.hasSuffix("0") ? String(text.dropLast()) : text
    }

    private func button(open: Bool, symbol: String, label: String, accessibilityLabel: String,
                        action: @escaping () -> Void) -> some View {
        BarButton(open: open, width: metrics.buttonWidth, height: metrics.buttonHeight,
                  accessibilityLabel: accessibilityLabel, action: action) {
            VStack(spacing: metrics.buttonSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(open ? Palette.accent : Palette.text)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(open ? Palette.accent : Palette.barLabel)
            }
        }
    }
}

// MARK: - Spotlight

/// Spotlight on the Mac: exactly ⌘Space, down then up. Whatever modifiers are latched never join
/// it — the button means Spotlight, not "space with whatever happens to be held".
enum Spotlight {
    /// The sparkle magnifier where the system has it. The Apps button already uses the plain
    /// magnifier, so the fallback must still look different from it.
    static let symbol: String = UIImage(systemName: "sparkle.magnifyingglass") != nil
        ? "sparkle.magnifyingglass" : "magnifyingglass.circle"

    static func press(send: (InputEvent) -> Void) {
        let space: UInt16 = 0x2C
        send(.key(hidUsage: space, down: true, modifiers: KeyModifiers.command.rawValue))
        send(.key(hidUsage: space, down: false, modifiers: KeyModifiers.command.rawValue))
    }
}

/// A bar button: 66×66 in the roomy top bar, 64×58 in the compact one and the portrait window bar,
/// 56×50 with a 14 pt radius in the outer display's portrait bar.
struct BarButton<Content: View>: View {
    let open: Bool
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let accessibilityLabel: String
    let action: () -> Void
    let content: () -> Content

    init(open: Bool, width: CGFloat = 66, height: CGFloat = 66, radius: CGFloat = 16,
         accessibilityLabel: String,
         action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.open = open
        self.width = width
        self.height = height
        self.radius = radius
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(open ? Palette.controlOpen : Palette.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Window thumbnails

/// The live window thumbnails. Defaults are the roomy top bar's numbers; the compact bars are
/// tighter (92×58 gap 14 fade 88%, and 80×50 radius 8 gap 12 with a 22 pt badge on the outer
/// display), so every size travels as a parameter and the thumbnail, its badge and its active halo
/// stay one view in every posture.
struct WindowStrip: View {
    @ObservedObject var client: StreamClient
    var width: CGFloat = 104
    var height: CGFloat = 66
    var radius: CGFloat = 10
    var spacing: CGFloat = 16
    /// Room above and below for the badge (6 pt out) and the active halo (5 pt out), which the
    /// ScrollView would otherwise clip. It is also what makes the strip as tall as its bar.
    var pad: CGFloat = 10
    var fade: Double = 0.86
    var badge: CGFloat = 24

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(client.windows) { window in
                    WindowThumbnail(window: window,
                                    image: client.thumbnails[window.id],
                                    icon: client.icons[window.bundleID],
                                    isActive: client.active == .window(window.id),
                                    width: width, height: height, radius: radius, badge: badge,
                                    action: { client.select(.window(window.id)) })
                }
            }
            .padding(.vertical, pad)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: fade),
                                     .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }
}

private struct WindowThumbnail: View {
    let window: WindowInfo
    let image: UIImage?
    let icon: UIImage?
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let badge: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            preview
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .overlay {
                    // The active halo sits under the app badge: the badge's bar-coloured ring then
                    // reads as cutting through the halo, instead of the halo slicing across the icon.
                    // It follows the thumbnail's own radius so both sizes keep the same 3 pt gap.
                    if isActive {
                        RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 2)
                            .padding(-5)
                    }
                }
                // The badge barely scales with the thumbnail; it is the app's identity, not chrome,
                // so it only shrinks once, to 22 pt, on the outer display's smallest bar.
                .overlay(alignment: .bottomLeading) { appBadge.offset(x: -6, y: 6) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(window.appName) window: \(window.title)" + (isActive ? ", showing now" : ""))
    }

    @ViewBuilder private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            VStack(spacing: 0) {
                Palette.thumbTitleBar.frame(height: 9)
                Palette.thumbBody
            }
        }
    }

    /// The app icon, with a 2 pt bar-coloured ring around it so it cuts through the thumbnail's
    /// edge and its halo instead of sitting on top of them.
    private var appBadge: some View {
        let corner = (badge * 0.29).rounded()      // 7 at 24 pt, 6 at 22
        return AppIcon(image: icon, name: window.appName, size: badge, radius: corner,
                       fontSize: (badge * 0.42).rounded())
            .background {
                RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                    .fill(Palette.bar)
                    .frame(width: badge + 4, height: badge + 4)
            }
    }
}

/// An app icon, or its first two letters while the host has not sent one.
struct AppIcon: View {
    let image: UIImage?
    let name: String
    let size: CGFloat
    let radius: CGFloat
    let fontSize: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Palette.iconFallback.overlay(
                    Text(String(name.prefix(2)))
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - App drawer

private struct OpenApp: Identifiable {
    let bundleID: String
    let name: String
    let windows: [WindowInfo]
    var id: String { bundleID }
}

struct AppDrawer: View {
    @ObservedObject var client: StreamClient
    @Binding var drawerOpen: Bool
    @State private var search = ""

    var body: some View {
        VStack(spacing: 6) {
            searchField
            ScrollView {
                VStack(spacing: 6) {
                    if !openApps.isEmpty {
                        header("Open now")
                        ForEach(openApps) { app in
                            DrawerRow(height: 50,
                                      highlighted: app.bundleID == activeBundleID,
                                      title: app.name,
                                      trailing: app.windows.count == 1 ? "1 window" : "\(app.windows.count) windows",
                                      action: { show(app) }) {
                                AppIcon(image: client.icons[app.bundleID], name: app.name,
                                        size: 32, radius: 9, fontSize: 12)
                            }
                        }
                    }
                    if !closedApps.isEmpty {
                        header("All apps").padding(.top, 2)
                        ForEach(closedApps) { app in
                            DrawerRow(height: 46, highlighted: false, title: app.name, trailing: nil,
                                      action: { client.launch(bundleID: app.bundleID) }) {
                                AppIcon(image: client.icons[app.bundleID], name: app.name,
                                        size: 32, radius: 9, fontSize: 12)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.bar))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 30, x: 0, y: 24)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(Palette.muted)
            TextField("", text: $search,
                      prompt: Text("Search apps on \(client.macName)").foregroundColor(Palette.muted))
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel("Search apps on this Mac")
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }

    // MARK: Contents

    /// Running apps, grouped from the window list and kept in its front-to-back order.
    private var openApps: [OpenApp] {
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [WindowInfo]] = [:]
        for window in client.windows {
            if grouped[window.bundleID] == nil {
                order.append(window.bundleID)
                names[window.bundleID] = window.appName
            }
            grouped[window.bundleID, default: []].append(window)
        }
        return order.map { OpenApp(bundleID: $0, name: names[$0] ?? $0, windows: grouped[$0] ?? []) }
            .filter { matches($0.name) }
    }

    private var closedApps: [AppInfo] {
        let running = Set(client.windows.map(\.bundleID))
        return client.apps
            .filter { !running.contains($0.bundleID) && matches($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var activeBundleID: String? {
        guard case .window(let id) = client.active else { return nil }
        return client.windows.first { $0.id == id }?.bundleID
    }

    private func matches(_ name: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || name.range(of: query, options: .caseInsensitive) != nil
    }

    /// First window of the app, or the next one if this app is already showing.
    private func show(_ app: OpenApp) {
        guard !app.windows.isEmpty else { return }
        var target = app.windows[0]
        if case .window(let id) = client.active,
           let index = app.windows.firstIndex(where: { $0.id == id }) {
            target = app.windows[(index + 1) % app.windows.count]
        }
        client.select(.window(target.id))
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
    }
}

/// One app row: icon, name, optional trailing count.
struct DrawerRow<Leading: View>: View {
    let height: CGFloat
    let highlighted: Bool
    let title: String
    let trailing: String?
    let action: () -> Void
    let leading: () -> Leading

    init(height: CGFloat, highlighted: Bool, title: String, trailing: String?,
         action: @escaping () -> Void, @ViewBuilder leading: @escaping () -> Leading) {
        self.height = height
        self.highlighted = highlighted
        self.title = title
        self.trailing = trailing
        self.action = action
        self.leading = leading
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? Palette.control : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
