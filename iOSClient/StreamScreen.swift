import SwiftUI
import Combine
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
/// so an iPad at an odd split size and an iPhone each get the layout their dimensions deserve (only
/// the arrangement `.outerPortrait` draws depends on the device; below). The numbers are written
/// for the iPhone Duo and its four postures:
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
///
/// The same sizes catch the phones: every iPhone held upright (375–440 pt wide, 320 with Display
/// Zoom) is `.outerPortrait` and on its side `.outerLandscape`, and so is an iPad window narrower
/// than 600 pt held upright (Slide Over, a narrow Split View). On an iPhone `.outerPortrait` draws
/// the phone's arrangement (Noah, 2026-09-27: the picture in a fixed 16:10 pane on top, then the
/// Keyboard button's row, the thumbnails, six keys and the trackpad; `PhonePortraitLayout`), the
/// Duo's outer display included: it has a phone's shape and the same keyboard over its key row. An
/// iPad keeps the compact halves in such a window, as before: the approval covered iPhones and left
/// the iPad as it was (`phoneArrangement`, the one place the layout reads the idiom). To give the
/// Duo's outer display back the halves, draw `.compact` from 480 pt wide (phones are at most 440;
/// docs/iphone-portrait-plan.md, Detection).
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

    /// The laptop layout, inner or outer: stream on top, the key row and the trackpad below. Only
    /// there does the device draw its own pointer, for the trackpad (PointerPresence).
    var isPortrait: Bool { self == .innerPortrait || self == .outerPortrait }

    /// Whether `.outerPortrait` draws the phone's arrangement: on an iPhone, yes; on an iPad (a
    /// window narrower than 600 pt held upright), no: the compact halves, as before. DEBUG:
    /// `-SillIdiom pad` (or `phone`) draws the other device's, so the harness can photograph an
    /// iPad window's on an iPhone simulator (ContentView's contract).
    static var phoneArrangement: Bool {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "SillIdiom") {
        case "pad"?: return false
        case "phone"?: return true
        default: break
        }
        #endif
        return UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Whether a screen of this size draws the phone's arrangement.
    static func drawsPhone(_ size: CGSize) -> Bool { of(size) == .outerPortrait && phoneArrangement }
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
    /// The Aa control's text scale, device points per Mac point; nil means the Mac window has never
    /// been asked to fit (the control shows 1× for it). Up here, like `latched`, so it survives
    /// rotation and both layouts share it.
    @State private var textScale: Double? = nil
    /// The Aa slider is unfolded (finger down): the bars fade their other buttons meanwhile.
    @State private var scaleOpen = false
    /// The thumbnail whose traffic-light submenu is open (held for 1.5 s). The bars clip their
    /// content, so the submenu is drawn by this root, anchored to the thumbnail's frame.
    @State private var windowMenu: UInt32? = nil
    /// The Settings panel (the Mac's streaming settings) is open. Up here, next to the drawer, so a
    /// rotation keeps it open and it re-anchors in the other layout.
    @State private var settingsOpen = false
    /// The keyboard was up (the overlay first responder) when the panel opened: closing the panel
    /// puts it back.
    @State private var keyboardBeforeSettings = false
    /// Pair This iPad… (the panel's Away from home group): the pairing overlay covers the stream.
    /// Up here, like the panel, so a rotation keeps it. An outside sill://pair link shows the same
    /// overlay with its confirmation.
    @State private var pairingOverlay = false
    /// The DEBUG harness's stand-in for the camera (the simulator has none); nil on a device.
    private var scannerOverride: CodeScanner.Mode? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The stream panel's size in points, reported by whichever layout is showing.
    @State private var panelSize: CGSize = .zero
    /// The viewport send waiting out its debounce, if any.
    @State private var pendingViewport: Task<Void, Never>? = nil
    /// The line over the stream while the link cannot carry the quality (docs/remote-bundle-plan.md
    /// §6.7; AwayCopy's LinkLine), and its next look (the linger's end).
    @State private var linkLine = LinkLine()
    @State private var linkLineCheck: Task<Void, Never>? = nil

    #if DEBUG
    /// DEBUG only, for the layout harness: start on a given state so a posture can be photographed
    /// with the drawer already open. `StreamScreen(client:)` still means exactly what it did.
    init(client: StreamClient, drawerOpen: Bool = false, keyboardShown: Bool = false,
         scaleOpen: Bool = false, textScale: Double? = nil, settingsOpen: Bool = false,
         pairingOverlay: Bool = false, scannerOverride: CodeScanner.Mode? = nil) {
        self.client = client
        _drawerOpen = State(initialValue: drawerOpen)
        _keyboardShown = State(initialValue: keyboardShown)
        _scaleOpen = State(initialValue: scaleOpen)
        _textScale = State(initialValue: textScale)
        _settingsOpen = State(initialValue: settingsOpen)
        _pairingOverlay = State(initialValue: pairingOverlay)
        self.scannerOverride = scannerOverride
    }
    #endif

    var body: some View {
        // Which layout, and at which size — see `DuoLayout` for the thresholds and the Duo posture
        // behind each one.
        GeometryReader { geo in
            ZStack {
                Group {
                    switch DuoLayout.of(geo.size) {
                    case .innerLandscape:
                        landscape(bar: .regular)
                    case .outerLandscape:
                        landscape(bar: .compact)
                    case .innerPortrait:
                        portrait(metrics: .regular)
                    case .outerPortrait:
                        portrait(metrics: DuoLayout.phoneArrangement ? .phone : .compact)
                    }
                }
                // Under the pairing overlay nothing takes a touch: not the bar, and not the
                // stream's UIKit input view.
                .allowsHitTesting(!overlayShown)
                // The pointer sprite follows the layout: the trackpad's arrow shows only in the
                // laptop layout, and a rotation re-renders it at once; the Mac's arrow stays.
                .onChange(of: DuoLayout.of(geo.size).isPortrait, initial: true) { _, portrait in
                    client.setPointerLayout(portrait: portrait)
                }
                // A sibling in the same stack, not an `.overlay`: over the stream's UIKit input
                // view, only a sibling drawn after it received the touches (measured on the
                // simulator: an overlay's buttons were drawn but never tapped).
                if overlayShown {
                    PairingOverlay(client: client, scannerMode: scannerOverride ?? CodeScanner.currentMode,
                                   close: { withAnimation(.easeOut(duration: 0.2)) { pairingOverlay = false } })
                }
            }
        }
        .background(Color.black)
        .overlayPreferenceValue(WindowMenuAnchorKey.self) { anchor in
            if let anchor, let id = windowMenu, let window = client.windows.first(where: { $0.id == id }) {
                WindowLightsMenu(anchor: anchor, window: window,
                                 command: { action in client.command(action, window: id); closeWindowMenu() },
                                 dismiss: closeWindowMenu,
                                 alwaysBelow: DuoLayout.drawsPhone)
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.2), value: windowMenu)
        .onChange(of: client.pendingLink) { _, link in
            // An outside link while streaming: the panel and the keyboard go first, as for Pair This iPad….
            if link != nil { openLinkOverlay() }
        }
        .onChange(of: scenePhase) { _, phase in
            // A gesture cut short by a scene change never ends: put the transient UI away.
            if phase != .active { scaleOpen = false; windowMenu = nil }
        }
        // One thing open at a time: the Aa ruler and a thumbnail's traffic lights put the Settings
        // panel away. (Opening the panel closes them, the drawer and the keyboard.)
        .onChange(of: scaleOpen) { _, open in if open { setSettings(false) } }
        .onChange(of: windowMenu) { _, menu in if menu != nil { setSettings(false) } }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            // A fresh connection starts on the Desktop (the client asks for it as soon as the host
            // reports nothing streaming), so the drawer stays closed until the user opens it.
            sendViewport()
            // A link that came in before this connection did waits here now.
            if client.pendingLink != nil { openLinkOverlay() }
            #if DEBUG
            runLaunchArguments()
            #endif
        }
        .onChange(of: client.active) { _, source in
            if source != .none { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
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
        // The stream rate follows the panel (`StreamClient.wantedFPS`): re-send when Low Power Mode
        // toggles or the screen's mode changes. Both notifications can arrive off the main thread.
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            sendViewport(after: 0.25)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.modeDidChangeNotification).receive(on: RunLoop.main)) { _ in
            sendViewport(after: 0.25)
        }
        // The link's line over the stream (§6.7): a report arriving or clearing, or the panel, the
        // drawer or the pairing overlay opening or closing over it.
        .onChange(of: linkReportLine, initial: true) { _, _ in updateLinkLine() }
        .onChange(of: linkLineAllowed) { _, _ in updateLinkLine() }
    }

    // MARK: The link's line

    /// What the Mac's report says for the line now: nil while the link keeps up.
    private var linkReportLine: String? {
        let host = client.settings.host
        return AwayCopy.streamLine(link: host?.link, away: host?.away, mac: client.macName.isEmpty ? "the Mac" : client.macName)
    }

    /// Nothing open over the stream: the Settings panel (which has the callout), the drawer, the
    /// pairing overlay.
    private var linkLineAllowed: Bool { !settingsOpen && !drawerOpen && !overlayShown }

    /// Runs LinkLine on the report and what is open, says the line once a spell, and looks again at
    /// the linger's end.
    private func updateLinkLine() {
        if let words = linkLine.update(report: linkReportLine, allowed: linkLineAllowed, now: ProcessInfo.processInfo.systemUptime) {
            AccessibilityNotification.Announcement(words).post()
            #if DEBUG
            print("link: the stream's line “\(words)” (announced)")
            #endif
        }
        linkLineCheck?.cancel()
        linkLineCheck = nil
        guard let at = linkLine.recheckAt else { return }
        linkLineCheck = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0.01, at - ProcessInfo.processInfo.systemUptime)))
            if !Task.isCancelled { updateLinkLine() }
        }
    }

    /// The line as it shows over the stream now, or nil.
    private var shownLinkLine: String? { linkLine.visible ? linkLine.text : nil }

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
            let fps = StreamClient.wantedFPS(remote: client.awayCapsFrameRate)
            #if DEBUG
            print("viewport: \(Self.points(panelSize.width))×\(Self.points(panelSize.height)) pt, scale "
                  + (textScale.map { TextScaleControl.label($0) } ?? "none") + ", \(fps) fps")
            #endif
            client.sendViewport(Viewport(width: Double(panelSize.width),
                                         height: Double(panelSize.height),
                                         scale: textScale,
                                         fps: fps))
        }
    }

    #if DEBUG
    /// A length for the console: whole points as whole numbers (within a hundredth: a scaled harness
    /// screen measures 693.99…), anything else to a tenth.
    private static func points(_ value: CGFloat) -> String {
        abs(value - value.rounded()) < 0.01 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }

    /// The harness's arguments that act once the stream screen shows (ContentView's contract), once
    /// per launch. `-SillKeyboard 1` brings the software keyboard up for real in a live session (the
    /// mock only lights the button, from its init); `-SillKeyboardToggle <s>[,<s>…]` toggles it at
    /// those seconds as the Keyboard button does, a stand-in for a tap. In a live session (the
    /// normal app with `-SillConnect`, or `-SillLive 1`) `-SillDrawer 1`, `-SillSettings 1` and
    /// `-SillScaleOpen 1` (with `-SillScale`) open theirs 1.5 s in, once the Desktop has started:
    /// its start closes a drawer opened before it, and the normal app has no harness to pass them
    /// in at the start.
    private func runLaunchArguments() {
        guard !Self.launchArgumentsRan else { return }
        Self.launchArgumentsRan = true
        let defaults = UserDefaults.standard
        let live = !client.mockDiscovery
        func after(_ seconds: Double, _ step: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: step)
        }
        if defaults.bool(forKey: "SillKeyboard"), live {
            after(0.5) {
                print("keyboard: -SillKeyboard 1, the input view takes first responder")
                overlay.setKeyboard(shown: true)
            }
        }
        let times = (defaults.string(forKey: "SillKeyboardToggle") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        for time in times {
            after(time) {
                print("keyboard: toggled at \(Self.points(CGFloat(time))) s, as the Keyboard button does (it was "
                      + (keyboardShown ? "up" : "down") + ")")
                setSettings(false, restoreKeyboard: false)
                overlay.toggleKeyboard()
            }
        }
        guard live else { return }
        if defaults.bool(forKey: "SillDrawer") {
            after(1.5) { print("harness: the drawer opened"); withAnimation(.easeOut(duration: 0.18)) { drawerOpen = true } }
        }
        if defaults.bool(forKey: "SillSettings") {
            after(1.5) { print("harness: the Settings panel opened"); setSettings(true) }
        }
        if defaults.bool(forKey: "SillScaleOpen") {
            after(1.5) {
                let scale = defaults.double(forKey: "SillScale")
                if scale > 0 { textScale = scale }
                print("harness: the Aa ruler opened")
                scaleOpen = true
            }
        }
    }
    private static var launchArgumentsRan = false
    #endif

    private func closeWindowMenu() { windowMenu = nil }

    /// Pair This iPad…, or an outside link waiting for its confirmation.
    private var overlayShown: Bool { pairingOverlay || client.pendingLink != nil }

    /// Pair This iPad…: the panel and the keyboard are put away first, so no key reaches the Mac
    /// while the code is typed, then the overlay covers the stream. What an earlier pairing left
    /// (a "Paired with…" whose fade never ran, an error) goes first: the overlay would show it,
    /// and a stale "Paired" closed it after a second.
    private func openPairingOverlay() {
        putAwayForOverlay()
        client.cancelPairing()
        withAnimation(.easeOut(duration: 0.2)) { pairingOverlay = true }
    }

    /// An outside link to confirm over the stream. The overlay is held open, not shown only while
    /// the link waits: Pair clears the link, and the overlay went with it, before "Pairing with…",
    /// any error or "Paired with…" could show. A pairing still running is left alone; one that
    /// ended earlier leaves nothing behind.
    private func openLinkOverlay() {
        putAwayForOverlay()
        if !pairingOverlay {
            switch client.pairing {
            case .working, .idle: break
            case .failed, .paired: client.pairing = .idle
            }
        }
        withAnimation(.easeOut(duration: 0.2)) { pairingOverlay = true }
    }

    private func putAwayForOverlay() {
        setSettings(false, restoreKeyboard: false)
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
        windowMenu = nil
        scaleOpen = false
        overlay.setKeyboard(shown: false)
    }

    /// Opens or closes the Settings panel. Opening puts the drawer, the traffic lights and the Aa
    /// ruler away and takes the keyboard down: with the overlay not first responder no hardware
    /// key reaches the Mac, and Esc (or ⌘.) reaches the panel's Done instead. Closing (Done, a tap
    /// outside, the Settings button, Esc, the VoiceOver escape gesture) puts the keyboard back if
    /// the panel took it down; the Apps and Keyboard buttons close it with `restoreKeyboard: false`
    /// because they decide about the keyboard themselves.
    private func setSettings(_ open: Bool, restoreKeyboard: Bool = true) {
        guard open != settingsOpen else { return }
        if open {
            withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
            windowMenu = nil
            scaleOpen = false
            keyboardBeforeSettings = keyboardShown
            overlay.setKeyboard(shown: false)
        }
        let motion: Animation = open && !reduceMotion ? .spring(duration: 0.25, bounce: 0.15) : .easeOut(duration: 0.18)
        withAnimation(motion) { settingsOpen = open }
        if !open {
            if restoreKeyboard, keyboardBeforeSettings { overlay.setKeyboard(shown: true) }
            keyboardBeforeSettings = false
        }
    }

    /// Grows from the Settings button's corner, the way a popover would; a plain fade under Reduce
    /// Motion. `anchor` is the panel's top-trailing corner as a point of the view the transition is
    /// attached to. In landscape that view is the content area, whose corner is within a few
    /// points of the panel's; in portrait it is the whole screen, where `.topTrailing` would make
    /// the panel slide down over the window bar (PortraitStreamScreen passes its own).
    private func settingsTransition(anchor: UnitPoint = .topTrailing) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.94, anchor: anchor).combined(with: .opacity)
    }

    private func landscape(bar: BarMetrics) -> some View {
        VStack(spacing: 0) {
            TopBar(client: client, metrics: bar, drawerOpen: $drawerOpen,
                   keyboardShown: $keyboardShown,
                   textScale: $textScale, scaleOpen: $scaleOpen, windowMenu: $windowMenu,
                   settingsOpen: settingsOpen,
                   toggleKeyboard: { overlay.toggleKeyboard() },
                   setSettings: { setSettings($0, restoreKeyboard: $1) })
            contentArea(bar: bar)
        }
    }

    private func portrait(metrics: PortraitMetrics) -> some View {
        PortraitStreamScreen(client: client, metrics: metrics, drawerOpen: $drawerOpen,
                             keyboardShown: $keyboardShown,
                             textScale: $textScale, scaleOpen: $scaleOpen, windowMenu: $windowMenu,
                             latched: $latched, overlay: overlay,
                             settingsOpen: settingsOpen,
                             setSettings: { setSettings($0, restoreKeyboard: $1) },
                             settingsTransition: { settingsTransition(anchor: $0) },
                             onPanelSize: { panelSize = $0 },
                             pairThisDevice: openPairingOverlay,
                             linkLine: shownLinkLine)
    }

    private var streamShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private func contentArea(bar: BarMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black

            ZStack {
                StreamView(client: client)
                // Same frame as the video, so a touch maps straight onto the streamed frame.
                InputOverlay(videoSize: client.videoSize,
                             send: { client.sendInput($0) },
                             setOwnPointer: { client.setOwnPointer($0, from: $1) },
                             proxy: overlay,
                             isKeyboardShown: $keyboardShown,
                             latchedModifiers: latched,
                             onModifiersConsumed: { latched = [] })
            }
            .background(Palette.panel)
            .overlay(alignment: .top) { LinkLineView(text: shownLinkLine) }
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

            // The drawer's mirror on the trailing edge, its right side lined up with the Settings
            // button's. No dim: the stream stays as it is, so a change can be watched taking effect.
            // A tap on it closes the panel and never clicks the Mac; the bar above stays live.
            if settingsOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { setSettings(false) }
                    .accessibilityHidden(true)

                HostSettingsPanel(client: client, close: { setSettings(false) }, pairThisDevice: openPairingOverlay)
                    .frame(width: bar.settingsWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    .padding(.trailing, bar.padding)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(settingsTransition())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - The link's line

/// The line over the stream while the link cannot carry the quality (docs/remote-bundle-plan.md §6.7):
/// a capsule at the top centre of the stream panel, 8 pt inside its top edge and at most the panel's
/// width less 32 pt, footnote text on the bar's colour; two lines at most, the text no larger than
/// xxLarge. It never takes a touch meant for the Mac, and comes and goes with a fade (with Reduce
/// Motion too). VoiceOver hears it once a spell (StreamScreen.updateLinkLine) and can read it here.
struct LinkLineView: View {
    let text: String?
    var body: some View {
        ZStack {
            if let text {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(Palette.bar.opacity(0.92)))
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: text)
    }
}

// MARK: - Top bar

/// The landscape top bar's numbers. The inner display gets the Main board's roomy bar; the outer
/// display gets the Laptop board's compact one, which is 8 pt shorter and tighter all round — on a
/// 500 pt tall screen the bar is a sixth of everything there is, so every point it gives back is a
/// point of Mac. Every bar carries the Aa control (Noah, 2026-09-22: both orientations); it takes
/// one button's width and unfolds over its neighbours only while touched.
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
    /// The Settings panel hanging under this bar.
    let settingsWidth: CGFloat

    static let regular = BarMetrics(height: 86, padding: 22, gap: 12,
                                    buttonWidth: 66, buttonHeight: 66, buttonSpacing: 4,
                                    thumbWidth: 104, thumbHeight: 66, thumbRadius: 10,
                                    thumbSpacing: 16, thumbPad: 10, thumbFade: 0.86,
                                    showsTextSize: true, settingsWidth: 360)

    static let compact = BarMetrics(height: 78, padding: 14, gap: 12,
                                    buttonWidth: 64, buttonHeight: 58, buttonSpacing: 3,
                                    thumbWidth: 92, thumbHeight: 58, thumbRadius: 9,
                                    thumbSpacing: 14, thumbPad: 10, thumbFade: 0.88,
                                    showsTextSize: true, settingsWidth: 340)
}

private struct TopBar: View {
    @ObservedObject var client: StreamClient
    let metrics: BarMetrics
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    @Binding var textScale: Double?
    @Binding var scaleOpen: Bool
    @Binding var windowMenu: UInt32?
    let settingsOpen: Bool
    let toggleKeyboard: () -> Void
    /// Opens or closes the Settings panel; the second argument says whether closing puts the
    /// keyboard back (see `StreamScreen.setSettings`).
    let setSettings: (_ open: Bool, _ restoreKeyboard: Bool) -> Void

    var body: some View {
        HStack(spacing: metrics.gap) {
            button(open: drawerOpen, symbol: "magnifyingglass", label: "Apps",
                   accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                   action: {
                       setSettings(false, false)
                       withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() }
                   })

            WindowStrip(client: client, width: metrics.thumbWidth, height: metrics.thumbHeight,
                        radius: metrics.thumbRadius, spacing: metrics.thumbSpacing,
                        pad: metrics.thumbPad, fade: metrics.thumbFade, menuFor: $windowMenu)
                .opacity(scaleOpen ? 0.2 : 1)      // the ruler is centred on Aa and reaches over the strip's end
                .allowsHitTesting(!scaleOpen)

            // Text size: the host sizes the Mac window to the panel divided by this scale, so a
            // bigger number means a smaller Mac window and bigger text here. The slider unfolds to
            // the right, over the two buttons after it, which fade while it is open.
            TextScaleControl(scale: $textScale, open: $scaleOpen,
                             width: metrics.buttonWidth, height: metrics.buttonHeight,
                             pointsPerStep: metrics.buttonHeight >= 60 ? 44 : 40)

            button(open: keyboardShown, symbol: "keyboard", label: "Keyboard",
                   accessibilityLabel: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                   action: { setSettings(false, false); toggleKeyboard() })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)

            button(open: client.active == .desktop, symbol: "desktopcomputer", label: "Desktop",
                   accessibilityLabel: "Show the full Mac desktop",
                   action: { client.select(.desktop) })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)

            // Leave's old slot: Disconnect is the Settings panel's pinned last row now.
            button(open: settingsOpen, symbol: "gearshape", label: "Settings",
                   accessibilityLabel: settingsOpen ? "Close settings" : "Settings for \(client.macName.isEmpty ? "the Mac" : client.macName)",
                   action: { setSettings(!settingsOpen, true) })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
        }
        .animation(.easeOut(duration: 0.16), value: scaleOpen)
        .frame(height: metrics.height)
        .padding(.horizontal, metrics.padding)
        // The bar's colour runs to the screen edge; its contents stay inside the safe area.
        .background(Palette.bar.ignoresSafeArea(edges: .top))
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
/// 56×50 with a 14 pt radius in the outer display's portrait bar, and 50 pt tall with its share of
/// the row's width in a phone's row 1.
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

// MARK: - Text size control

/// The Aa control: a bar button that opens into a ruler while the finger is down, the way the
/// camera's zoom button opens into its dial and the Dynamic Island timer scrubs. The thumb stays
/// put at the button's centre and the ruler slides under it: five detents, 0.5× to 1.5× in 0.25
/// steps, a tick of haptic at each. The bar fades the buttons next to it while `open` and brings
/// them back on release, when the chosen value is applied once (every change restarts the stream,
/// so nothing is sent mid-drag). A nil scale means the Mac window has never been asked to fit; it
/// shows 1×.
struct TextScaleControl: View {
    @Binding var scale: Double?
    @Binding var open: Bool
    var width: CGFloat = 66
    var height: CGFloat = 66
    var radius: CGFloat = 16
    /// Finger travel (and ruler spacing) per detent; smaller in the tighter bars so the ruler,
    /// centred on the button, stays inside the screen.
    var pointsPerStep: CGFloat = 44
    /// A fixed height for "Aa", and the space under it, so its value lines up with the labels of
    /// bar buttons whose symbols sit in a box of that height (a phone's row 1); nil: as tall as the
    /// text, 2 pt over the value (every bar that has always had it).
    var iconBox: CGFloat? = nil
    var iconSpacing: CGFloat = 2

    static let steps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]
    /// Padding either side of the visible ruler; two detents show each side of the thumb.
    static let sliderInset: CGFloat = 30
    var sliderWidth: CGFloat { pointsPerStep * CGFloat(Self.steps.count - 1) + Self.sliderInset * 2 }

    @State private var live: Double = 1.0
    @State private var startValue: Double = 1.0
    @State private var startX: CGFloat = 0

    var body: some View {
        VStack(spacing: iconBox == nil ? 2 : iconSpacing) {
            if let iconBox {
                Text("Aa")
                    .font(.system(size: height >= 60 ? 19 : 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(height: iconBox)
            } else {
                Text("Aa")
                    .font(.system(size: height >= 60 ? 19 : 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
            Text(Self.label(scale ?? 1.0) + "×")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.barLabel)
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.control))
        .opacity(open ? 0 : 1)
        .overlay {
            // Centred on the button: the thumb is where the finger came down.
            slider
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.6)
                .allowsHitTesting(false)
        }
        .zIndex(open ? 1 : 0)
        .onChange(of: open, initial: true) { _, isOpen in if isOpen { live = scale ?? 1.0 } }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    if !open {
                        startValue = scale ?? 1.0
                        live = startValue
                        startX = g.location.x
                        withAnimation(.spring(duration: 0.22, bounce: 0.15)) { open = true }
                    }
                    // The ruler follows the finger: dragging right raises the value, and the ticks
                    // slide left under the fixed thumb.
                    let dx = g.location.x - startX
                    let snapped = Self.snap(startValue + Double(dx / pointsPerStep) * 0.25)
                    if snapped != live {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.1)) { live = snapped }
                    }
                }
                .onEnded { _ in
                    if (scale ?? 1.0) != live { scale = live }     // a plain tap on an untouched control changes nothing
                    withAnimation(.easeOut(duration: 0.2)) { open = false }
                }
        )
        .onDisappear { open = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text size")
        .accessibilityValue("\(Self.label(scale ?? 1.0)) times")
        .accessibilityAdjustableAction { direction in
            let i = Self.steps.firstIndex(of: scale ?? 1.0) ?? 2
            switch direction {
            case .increment: scale = Self.steps[min(i + 1, Self.steps.count - 1)]
            case .decrement: scale = Self.steps[max(i - 1, 0)]
            @unknown default: break
            }
        }
    }

    /// The ruler: a track with five ticks and labels that slides so the live value sits under the
    /// fixed thumb; the ends fade out where they run past the panel.
    private var slider: some View {
        let w = sliderWidth
        let step = pointsPerStep
        let midX = w / 2
        let midY = height / 2 + 4
        func x(_ value: Double) -> CGFloat { midX + CGFloat((value - live) / 0.25) * step }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.controlOpen)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.barLabel.opacity(0.35))
                    .frame(width: step * CGFloat(Self.steps.count - 1), height: 3)
                    .offset(x: x(Self.steps[0]), y: midY - 1.5)
                ForEach(Self.steps, id: \.self) { value in
                    Rectangle().fill(Palette.barLabel.opacity(0.6))
                        .frame(width: 2, height: 9)
                        .offset(x: x(value) - 1, y: midY - 4.5)
                    Text(Self.label(value))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(value == live ? Palette.text : Palette.barLabel)
                        .frame(width: step, alignment: .center)
                        .offset(x: x(value) - step / 2, y: midY + 9)
                }
            }
            .frame(width: w, height: height, alignment: .topLeading)   // the mask below is sized to this
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            Circle().fill(Palette.accent)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .offset(x: midX - 11, y: midY - 11)
            // The live value over the thumb, where the finger does not cover it. In a 50 pt ruler
            // (a phone's row 1, the compact window bar) `midY - 34` put the top of its digits 2 pt
            // outside the clip; it sits where the 58 pt bars put it (1 pt above the frame's top,
            // the digits 2 pt inside), and in the taller bars as it always has.
            Text(Self.label(live) + "×")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 60, alignment: .center)
                .offset(x: midX - 30, y: max(midY - 34, -1))
        }
        .frame(width: w, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Nearest detent, clamped to the ends.
    static func snap(_ value: Double) -> Double {
        let clamped = min(max(value, steps[0]), steps[steps.count - 1])
        return steps.min { abs($0 - clamped) < abs($1 - clamped) } ?? 1.0
    }

    /// 0.5, 0.75, 1, 1.25, 1.5: trailing zeros dropped, and "1" rather than "1.0".
    static func label(_ scale: Double) -> String {
        var text = String(format: "%.2f", scale)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
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
    /// Which thumbnail has its traffic-light submenu open. Owned by the screen root, which draws
    /// the submenu outside this clipped strip.
    @Binding var menuFor: UInt32?

    /// Press and hold a thumbnail for 1.5 s: it starts to wiggle and its traffic lights (close,
    /// minimize, full screen) appear in a submenu beside it, the way a held Home Screen icon
    /// offers its menu. Keep holding and move: the submenu goes, the thumbnail lifts and drags
    /// into a new slot. The arrangement is the device's own, persisted per Mac. A tap selects.
    static let holdToOpen: TimeInterval = 1.5
    @State private var lifted: UInt32? = nil
    @State private var liftOffset: CGFloat = 0
    @State private var liftStartIndex = 0

    var body: some View {
        let windows = client.orderedWindows
        let slot = width + spacing
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    WindowThumbnail(window: window,
                                    image: client.thumbnails[window.id],
                                    icon: client.icons[window.bundleID],
                                    isActive: client.active == .window(window.id),
                                    width: width, height: height, radius: radius, badge: badge,
                                    menuOpen: menuFor == window.id,
                                    lifted: lifted == window.id,
                                    onSelect: { client.select(.window(window.id)) },
                                    onCommand: { client.command($0, window: window.id) },
                                    onMove: { step in
                                        client.moveWindow(window.id, to: index + step)
                                        client.persistWindowOrder()
                                    })
                        .overlay {
                            HoldDragOverlay(minimumHold: Self.holdToOpen,
                                            onTap: { if menuFor != nil { closeMenu() } else { client.select(.window(window.id)) } },
                                            onHold: { openMenu(for: window.id) },
                                            onMove: { t in holdMoved(window: window, index: index, count: windows.count, slot: slot, translation: t) },
                                            onEnd: { holdEnded(window: window) })
                        }
                        .offset(x: lifted == window.id ? liftOffset : 0)
                        .zIndex(lifted == window.id ? 1 : 0)
                        // The lifted thumbnail follows the finger: its slot change must not animate,
                        // or the layout springs one way while the compensating offset jumps the other.
                        .transaction { if lifted == window.id { $0.animation = nil } }
                }
            }
            .padding(.vertical, pad)
            .padding(.horizontal, 8)
        }
        .coordinateSpace(name: "strip")
        .scrollDisabled(lifted != nil)
        .frame(maxWidth: .infinity)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: fade),
                                     .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .onChange(of: client.windows) { _, now in
            // A window that closed or minimized takes its menu, and any drag, with it.
            if let id = menuFor, !now.contains(where: { $0.id == id }) { closeMenu() }
            if let id = lifted, !now.contains(where: { $0.id == id }) {
                lifted = nil; liftOffset = 0
                client.persistWindowOrder()
            }
        }
        .onDisappear { lifted = nil; liftOffset = 0 }
        #if DEBUG
        // Harness: `-SillWindowMenu 1` opens the first window's submenu at launch.
        .onAppear {
            if UserDefaults.standard.bool(forKey: "SillWindowMenu"), let first = client.orderedWindows.first { menuFor = first.id }
        }
        #endif
    }

    /// The finger moved while the hold is still down. More than 8 pt lifts the thumbnail and
    /// drags it; the drag reorders live: crossing the middle of a neighbour swaps slots, and the
    /// lifted thumbnail's offset is corrected by the slots it has moved so it stays under the finger.
    private func holdMoved(window: WindowInfo, index: Int, count: Int, slot: CGFloat, translation t: CGSize) {
        if lifted == nil {
            guard abs(t.width) > 8 || abs(t.height) > 8 else { return }
            closeMenu()
            lifted = window.id
            liftStartIndex = index
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        guard lifted == window.id else { return }
        let shift = Int((t.width / slot).rounded())
        let target = max(0, min(count - 1, liftStartIndex + shift))
        if let current = client.orderedWindows.firstIndex(where: { $0.id == window.id }), current != target {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) { client.moveWindow(window.id, to: target) }
        }
        liftOffset = t.width - CGFloat(target - liftStartIndex) * slot
    }

    /// The finger lifted after a hold: drop the thumbnail (the submenu, if open, stays).
    private func holdEnded(window: WindowInfo) {
        guard lifted == window.id else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { lifted = nil; liftOffset = 0 }
        client.persistWindowOrder()
    }

    private func openMenu(for id: UInt32) {
        guard menuFor != id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        menuFor = id
    }

    private func closeMenu() { menuFor = nil }
}

/// A thumbnail's touch handling, in UIKit: a tap selects; a hold of `minimumHold` opens the
/// submenu and keeps tracking the finger, so moving it afterwards drags. UIKit rather than SwiftUI
/// gestures because a SwiftUI long press sequenced with a drag swallowed plain taps inside the
/// ScrollView (2026-09-23), and UIKit's long press is exactly the Home Screen mechanic: by the time
/// it recognizes, the scroll view's pan has already given up, so the drag is ours.
struct HoldDragOverlay: UIViewRepresentable {
    var minimumHold: TimeInterval
    var onTap: () -> Void
    var onHold: () -> Void
    /// Translation since the hold began, in window coordinates (stable while the view moves).
    var onMove: (CGSize) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = minimumHold
        hold.allowableMovement = 12        // more than this before the hold fires is a scroll, not a hold
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: HoldDragOverlay
        private var start = CGPoint.zero
        init(_ parent: HoldDragOverlay) { self.parent = parent }

        @objc func tapped() { parent.onTap() }

        @objc func held(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: g.view?.window)
            switch g.state {
            case .began: start = p; parent.onHold()
            case .changed: parent.onMove(CGSize(width: p.x - start.x, height: p.y - start.y))
            case .ended, .cancelled, .failed: parent.onEnd()
            default: break
            }
        }
    }
}

/// The frame of the thumbnail whose submenu is open, reported up to the screen root.
struct WindowMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

/// macOS's three lights in a floating submenu beside the held thumbnail: below it when the bar
/// is at the top of the screen, above it when the bar is at the bottom (portrait's halves), and
/// always below it on a phone upright, where the strip sits under row 1 and the key row below has
/// room on every phone (above, it would cover row 1 on the shortest). A tap anywhere else
/// dismisses it. Drawn by the screen root, over everything.
struct WindowLightsMenu: View {
    let anchor: Anchor<CGRect>
    let window: WindowInfo
    let command: (WindowCommand.Action) -> Void
    let dismiss: () -> Void
    /// Whether a screen of this size always puts the lights below the thumbnail (the phone's
    /// arrangement); otherwise they go on the side of the screen's middle away from it.
    var alwaysBelow: (CGSize) -> Bool = { _ in false }

    private static let size = CGSize(width: 214, height: 62)

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy[anchor]
            let below = alwaysBelow(proxy.size) || frame.midY < proxy.size.height / 2
            let w = Self.size.width, h = Self.size.height
            let x = min(max(frame.midX, w / 2 + 8), proxy.size.width - w / 2 - 8)
            let y = below ? frame.maxY + 8 + h / 2 : frame.minY - 8 - h / 2
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: dismiss)
                HStack(spacing: 6) {
                    light(.close, Color(hex: 0xFF5F57), "xmark", "Close")
                    light(.minimize, Color(hex: 0xFEBC2E), "minus", "Minimize")
                    light(.fullScreen, Color(hex: 0x28C840), "arrow.up.left.and.arrow.down.right", "Full Screen")
                }
                .padding(.horizontal, 10)
                .frame(width: w, height: h)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.control)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                )
                .position(x: x, y: y)
                .transition(.scale(scale: 0.8, anchor: below ? .top : .bottom).combined(with: .opacity))
            }
            .accessibilityLabel("\(window.appName) window actions")
        }
    }

    private func light(_ action: WindowCommand.Action, _ color: Color, _ symbol: String, _ label: String) -> some View {
        Button { command(action) } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(color).frame(width: 24, height: 24)
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.65))
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.barLabel)
                    .lineLimit(1)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) window")
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
    let menuOpen: Bool
    let lifted: Bool
    /// VoiceOver's routes to what the finger does with a tap, the hold submenu and the drag.
    let onSelect: () -> Void
    let onCommand: (WindowCommand.Action) -> Void
    let onMove: (Int) -> Void

    var body: some View {
        // Two stages: one long chain of modifiers here is more than the type checker will take.
        card
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.appName) window: \(window.title)" + (isActive ? ", showing now" : ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onSelect() }
            .accessibilityAction(named: "Close window") { onCommand(.close) }
            .accessibilityAction(named: "Minimize window") { onCommand(.minimize) }
            .accessibilityAction(named: "Full screen") { onCommand(.fullScreen) }
            .accessibilityAction(named: "Move left") { onMove(-1) }
            .accessibilityAction(named: "Move right") { onMove(1) }
    }

    /// The thumbnail with its badge, halo, wiggle and lift.
    private var card: some View {
        let halo = RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
            .strokeBorder(Palette.accent, lineWidth: 2)
            .padding(-5)
        return preview
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            // The active halo sits under the app badge: the badge's bar-coloured ring then reads as
            // cutting through the halo, instead of the halo slicing across the icon. It follows the
            // thumbnail's own radius so both sizes keep the same 3 pt gap.
            .overlay { if isActive { halo } }
            // The badge barely scales with the thumbnail; it is the app's identity, not chrome,
            // so it only shrinks once, to 22 pt, on the outer display's smallest bar.
            .overlay(alignment: .bottomLeading) { appBadge.offset(x: -6, y: 6) }
            // Held: the Home Screen wiggle, until the submenu is dismissed. Lifted: bigger, with a shadow.
            .rotationEffect(.degrees(menuOpen ? 1.8 : 0))
            .offset(y: menuOpen ? -1 : 0)
            .animation(menuOpen ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .easeOut(duration: 0.15),
                       value: menuOpen)
            .scaleEffect(lifted ? 1.08 : (menuOpen ? 1.04 : 1))
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 10, y: 4)
            .anchorPreference(key: WindowMenuAnchorKey.self, value: .bounds) { menuOpen ? $0 : nil }
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
