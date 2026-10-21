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
/// for the iPhone Duo (first guessed at 1000×710 and 500×710; the real sizes, from the iOS 27.1
/// simulator, are these, the stream screen's: docs/iphone-duo-plan.md):
///
/// * inner display sideways, open flat or half-folded (the book pose) — 951×669 → `.innerLandscape`
///   (top bar over the stream)
/// * inner display upright, open flat or half-folded (the laptop pose) — 669×951 → `.innerPortrait`
///   (stream over controls)
/// * the cover on its side — 594×466 (678×466 less the camera's strip) → `.outerLandscape`
/// * the cover upright — 382×678 (466×678 less that strip) → `.outerPortrait`
///
/// The outer display is not a different app: it is the same two layouts at compact sizes, because
/// the posture only changed how much room there is, not what the screen is for. The thresholds sit
/// between those sizes with room to spare — 600 separates the cover's 382 pt width from the inner
/// 669, and 560 the cover's 466 pt height from the inner 669. Where the fold runs across the inner
/// display, and whether it is in the way, is the device's word (iOS 27.1, DuoPosture), not the size's.
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
    /// The phone's Shortcuts drawer (row 1's Shortcuts button, `ShortcutsDrawer`).
    @State private var shortcutsOpen = false
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
    /// The Menus pull-down closed the Settings panel, which had taken the keyboard down: it comes
    /// back when the pull-down goes (`menusClosed`).
    @State private var keyboardAfterMenus = false
    /// The Menus pull-down is open: it takes the arrows and Return itself, so a hardware keyboard's
    /// hold lets go meanwhile (`keyboardTakers`).
    @State private var menusOpen = false
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

    // The first-run tour (TourPolicy, TourOverlay; docs/first-run-walkthrough-plan.md). One stream
    // screen is one session. What the session decided is `client.tourSession`, which outlives the
    // screen: the automatic reconnect's session goes on with it (TourPolicy.nextSession).
    /// The tour on screen, if any. While it shows the layouts take no touch and the keyboard is down.
    @State private var tour: TourRun? = nil
    /// Where the tour's targets are, as the layout on screen reports them.
    @State private var tourTargets: [TourTarget: CGRect] = [:]
    /// This session's first picture (the Mac's name, a frame size, a source), systemUptime.
    @State private var pictureAt: Double? = nil
    /// The layout on screen (nil until the screen has a size), and when it began.
    @State private var tourLayout: TourLayout? = nil
    @State private var layoutAt: Double = ProcessInfo.processInfo.systemUptime
    /// The decision waiting out its beat.
    @State private var tourWait: Task<Void, Never>? = nil
    /// Every touch on the screen, taken by none.
    @State private var touches = TouchWatch()
    @State private var tourStore = TourStore()
    /// The keyboard comes back when the tour ends: it was up when the tour came, or when the
    /// Settings panel that started it opened.
    @State private var tourKeyboardAfter = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    /// The Duo's hinge (iOS 27.1, DuoPostureReader): with the fold, the book and laptop poses.
    @Environment(\.duoEnvironment) private var duoEnvironment
    /// This device's Larger Picture switch (the Settings panel's This iPhone; docs/larger-picture-plan.md).
    /// It acts only while a window streams (`largerPictureNow`).
    @AppStorage(StreamClient.largerPictureKey) private var largerPicture = false
    /// Full Screen on a phone held upright (`FullScreenLayout`), and its input mode, and how the
    /// Desktop shows there ("fill": the frame covers the screen and follows the pointer; "fit": whole).
    @AppStorage(StreamClient.fullScreenKey) private var fullScreen = false
    @AppStorage("Sill.fullScreenTrackpad") private var fullScreenTrackpad = false
    @AppStorage(StreamClient.fullScreenDesktopKey) private var fullScreenDesktop = "fill"
    /// Full Screen's controls showing (row 1 and the key row), or only its handle.
    @State private var fullScreenExpanded = true
    /// Full Screen's switch as it was when the Settings panel opened: the arrangement holds still under
    /// the panel, and a change applies as it closes (as Larger Picture's does).
    @State private var fullScreenHeld: Bool? = nil
    /// Full Screen in effect now, as the body last found it (the tour's rule reads it).
    @State private var fullScreenShown = false
    /// Aa's Auto (`AutoFit`): the scale that fit each window in each room ("id@W×H"), once found.
    @State private var autoScales: [String: Double] = [:]
    /// The check that follows a viewport sent under Auto: whether the Mac's app took the window whole.
    @State private var autoCheck: Task<Void, Never>?
    /// The screen stays awake while a session shows (Settings › This iPhone).
    @AppStorage(StreamClient.keepScreenOnKey) private var keepScreenOn = false
    /// Larger Picture as it was in effect when the Settings panel opened (`largerPictureNow`), which
    /// the arrangement keeps until the panel closes; nil while it is closed. The panel hangs under row
    /// 1, which the arrangement moves by the picture's growth (157 pt on an 18 Pro Max), so a change
    /// applied at once would move the panel under the finger: the switch flipped there, or what
    /// streams changing meanwhile (a window closed on the Mac, another device's pick). It applies as
    /// the panel goes, in the same motion.
    @State private var largerPictureHeld: Bool? = nil
    #if DEBUG
    /// The console says once when a decision starts to wait.
    @State private var tourWaitLogged: Double? = nil
    /// `-SillTourPress skip@S` skips once.
    @State private var tourSkipPressed = false
    #endif

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
        // The panel open over the keyboard, as in a session: it took the keyboard down, and closing
        // it puts it back (`-SillSettings 1 -SillKeyboard 1`).
        _keyboardBeforeSettings = State(initialValue: settingsOpen && keyboardShown)
        // And it holds the Larger Picture it opened with, as `setSettings` does.
        _largerPictureHeld = State(initialValue: settingsOpen
            ? PhonePortraitLayout.largerPicture(switchOn: UserDefaults.standard.bool(forKey: StreamClient.largerPictureKey),
                                                streaming: .init(client.active))
            : nil)
        _pairingOverlay = State(initialValue: pairingOverlay)
        self.scannerOverride = scannerOverride
    }
    #endif

    var body: some View {
        // Which layout, and at which size — see `DuoLayout` for the thresholds and the Duo posture
        // behind each one.
        GeometryReader { geo in
            let duo = DuoLayout.of(geo.size)
            let layout: TourLayout = duo == .innerLandscape || duo == .outerLandscape ? .landscape
                : (DuoLayout.drawsPhone(geo.size) ? .phone : .portrait)
            // The fold across this screen, in its own space (iOS 27.1 on the Duo; else as before).
            let posture = DuoPosture.read(geo, duoEnvironment)
            // Larger Picture on a phone held upright: the software keyboard its rows are kept above;
            // none with the switch off, while the Desktop or nothing streams (`largerPictureNow`),
            // sideways, on an iPad, on the iPhone Duo (a hinge), and where the picture would be no
            // larger (Display Zoom at 320 pt wide). While the Settings panel is open, Larger Picture
            // as it was in effect when it opened (`largerPictureHeld`). The arrangement, its viewport
            // (PortraitStreamScreen's picture) and the tour's targets and words all follow from this.
            let largerKeyboard = layout == .phone
                ? PhonePortraitLayout.keyboard(for: geo.size, largerPicture: largerPictureHeld ?? largerPictureNow,
                                               foldable: posture.hinge != .unknown) : nil
            // The Settings panel's switch: on an iPhone without a hinge whose picture Larger Picture
            // makes larger, judged on this screen held upright, whichever way it is held now.
            let offersLarger = DuoLayout.phoneArrangement && posture.hinge == .unknown
                && PhonePortraitLayout.offersLargerPicture(screen: geo.size)
            ZStack {
                Group {
                    switch duo {
                    case .innerLandscape:
                        landscape(bar: .regular, width: geo.size.width, fold: posture.info(in: geo.size))
                    case .outerLandscape:
                        landscape(bar: .compact, width: geo.size.width, fold: posture.info(in: geo.size))
                    case .innerPortrait:
                        portrait(metrics: .regular)
                    case .outerPortrait:
                        portrait(metrics: DuoLayout.phoneArrangement ? .phone : .compact, largerKeyboard: largerKeyboard,
                                 fullScreen: fullScreenOn(layout, posture) ? fullScreenControls : nil)
                            .ignoresSafeArea(edges: fullScreenOn(layout, posture) ? .all : [])
                    }
                }
                // Under the pairing overlay and the tour nothing takes a touch: not the bar, and
                // not the stream's UIKit input view (nor, so, the Pencil, a hover or a key).
                .allowsHitTesting(!overlayShown && tour == nil)
                // The pointer sprite follows the layout: the trackpad's arrow shows only in the
                // laptop layout, and a rotation re-renders it at once; the Mac's arrow stays.
                .onChange(of: DuoLayout.of(geo.size).isPortrait, initial: true) { _, portrait in
                    client.setPointerLayout(portrait: portrait)
                }
                // The clipboard's chip on screen or not: its 20 s run only while it is, and VoiceOver
                // is told when it first shows (ClipboardPolicy.chipCounts).
                .onChange(of: clipboardChipOnScreen, initial: true) { _, onScreen in
                    client.clipboardChipShown(onScreen)
                }
                // The clipboard's chip (docs/clipboard-plan.md): a sibling after the layouts, so its
                // Paste button and Dismiss take their touches over the stream's UIKit input view, and
                // nothing else does (the frame around it is empty). Near the bar, off the link's line,
                // inside the stream panel's corner; never while something is open over the stream.
                if clipboardChipAllowed, client.clipboardChip || client.clipboardNote != nil, let panel = tourTargets[.stream] {
                    let corner = ClipboardPolicy.chipCorner(landscape: layout == .landscape, linkLineShown: shownLinkLine != nil)
                    ClipboardChip(client: client)
                        .frame(maxWidth: max(0, panel.width - 16), alignment: .trailing)
                        .padding(8)
                        .frame(width: panel.width, height: panel.height,
                               alignment: corner == .topTrailing ? .topTrailing : .bottomTrailing)
                        .position(x: panel.midX, y: panel.midY)
                        .transition(.opacity)
                }
                // The tour: a sibling above the layouts, as the pairing overlay is, and under it: an
                // outside link puts the tour aside until the overlay has closed.
                if let run = tour, !overlayShown {
                    // With Larger Picture no thumbnails: the bar card is about Apps, and the cards
                    // upright stand in the picture's whole room, the black under a short picture.
                    TourOverlay(run: run, copy: tourCopy(run, layout, keysOnItsSide: posture.onInnerDisplay,
                                                         thumbnails: largerKeyboard == nil),
                                layout: layout, targets: tourTargets,
                                thumbnails: largerKeyboard == nil,
                                room: largerKeyboard.map { PhonePortraitLayout(size: geo.size, keyboard: $0).picture },
                                screen: geo.size, bottomInset: geo.safeAreaInsets.bottom,
                                next: tourNext, skip: tourSkip)
                        .transition(.opacity)
                }
                // A sibling in the same stack, not an `.overlay`: over the stream's UIKit input
                // view, only a sibling drawn after it received the touches (measured on the
                // simulator: an overlay's buttons were drawn but never tapped).
                if overlayShown {
                    PairingOverlay(client: client, scannerMode: scannerOverride ?? CodeScanner.currentMode,
                                   close: { withAnimation(.easeOut(duration: 0.2)) { pairingOverlay = false } })
                }
            }
            .coordinateSpace(.named(TourSpace.name))
            .onPreferenceChange(TourTargetsKey.self) { tourTargets = $0 }
            .onChange(of: layout, initial: true) { _, now in layoutChanged(to: now) }
            // A thumbnail's lights hang from the strip, which Larger Picture's arrangement has none
            // of: when the arrangement changes under them (what streams changed, or a turn), they
            // close rather than wait, unseen, to come back with the strip.
            .onChange(of: largerKeyboard != nil) { _, _ in
                #if DEBUG
                if windowMenu != nil { print("lights: closed, the phone's arrangement changed under them") }
                #endif
                closeWindowMenu()
            }
            .background(TouchWatcher(watch: touches))
            // The layouts and the overlays share this screen's space, and so its fold; the inner
            // display gives the picture the status bar's strip in every pose.
            .duoFold(posture, size: geo.size, screen: "stream screen")
            .duoStatusBar(posture, size: geo.size)
            // Full Screen: the home indicator dimmed, and the Desktop filling the picture if chosen.
            .persistentSystemOverlays(fullScreenOn(layout, posture) ? .hidden : .automatic)
            .onChange(of: fullScreenOn(layout, posture), initial: true) { _, on in fullScreenShown = on }
            .onChange(of: fullScreenOn(layout, posture) && fullScreenDesktop == "fill" && client.active == .desktop,
                      initial: true) { _, fill in client.zoom.fill = fill }
            .environment(\.largerPictureOffered, offersLarger)
            #if DEBUG
            // The console's line for the gates: what Larger Picture's rule made of the switch and of
            // what streams, on a phone held upright, each time one of them or the outcome changes.
            .onChange(of: layout == .phone ? largerPictureLine(largerKeyboard) : "", initial: true) { _, line in
                if !line.isEmpty { print(line) }
            }
            #endif
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
        .overlayPreferenceValue(StackAnchorKey.self) { anchor in
            if let anchor, client.openStack == anchor.app {
                GeometryReader { geo in
                    // Below the strip when it is in the screen's top third (a landscape bar), else above.
                    let below = geo[anchor.bounds].midY < geo.size.height / 3
                    StackPanel(client: client, anchor: anchor, screen: geo.size, below: below)
                }
            }
        }
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
        // Keep Screen On: no auto-lock while the stream screen shows.
        .onChange(of: keepScreenOn, initial: true) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
        .onChange(of: client.active, initial: true) { _, source in
            // The zoom each source had (PictureZoom.source); nothing streaming keeps the last.
            switch source {
            case .desktop: client.zoom.source("desktop")
            case .window(let id): client.zoom.source("window:\(id)")
            case .none: break
            }
            if source != .none { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
            // The host sizes a window as it selects it, from the last viewport it has; this repeat
            // is for a host that restarted, or a window that was picked from the Mac's side.
            sendViewport()
        }
        .onChange(of: client.connected) { _, up in
            if up { sendViewport() }
        }
        // A hardware keyboard (docs/hardware-keyboard-plan.md §2): the input view takes the keyboard by
        // itself while one is attached and nothing open takes it, never as the person's own.
        .onReceive(HardwareKeyboardMonitor.shared.$attached) { overlay.update(attached: $0) }
        .onChange(of: keyboardTakers, initial: true) { _, takers in overlay.update(takers: takers) }
        // Rotation animates, and a Mac window resize restarts the stream, so let the size settle.
        .onChange(of: panelSize) { _, _ in sendViewport(after: 0.25) }
        .onChange(of: fullScreenShown) { _, _ in sendViewport(after: 0.25) }
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
        // Away from home the stream rate follows the route (60 fps through a VPN or the internet): a
        // session that stops being away (the move home) asks for its full rate whatever path it took
        // (docs/remote-bundle-plan.md §7.3).
        .onChange(of: client.remoteRoute) { _, _ in sendViewport() }
        // The link's line over the stream (§6.7): a report arriving or clearing, or the panel, the
        // drawer or the pairing overlay opening or closing over it.
        .onChange(of: linkReportLine, initial: true) { _, _ in updateLinkLine() }
        .onChange(of: linkLineAllowed) { _, _ in updateLinkLine() }
        // The tour: the first picture starts its beat; an outside link puts it aside and back.
        .onChange(of: pictureReady, initial: true) { _, ready in if ready { pictureCame() } }
        // The bar's own controls used, by a tap or by VoiceOver, Switch Control, Voice Control or
        // Full Keyboard Access (none of which makes a touch): something happening, for its rule.
        .onChange(of: drawerOpen) { _, _ in client.noteAction() }
        .onChange(of: settingsOpen) { _, _ in client.noteAction() }
        .onChange(of: keyboardShown) { _, _ in client.noteAction() }
        .onChange(of: scaleOpen) { _, _ in client.noteAction() }
        .onChange(of: textScale) { _, _ in client.noteAction() }
        .onChange(of: tourCard, initial: true) { _, card in tourCardChanged(card) }
        .onChange(of: tourVoiceOver) { _, _ in carryTour(reason: "VoiceOver") }
        // The session is over: a decision still waiting out its beat must not land in the next
        // session's `client.tourSession`.
        .onDisappear {
            tourWait?.cancel()
            tourWait = nil
        }
    }

    // MARK: The link's line

    /// What the Mac's report says for the line now: nil while the link keeps up.
    private var linkReportLine: String? {
        let host = client.settings.host
        return AwayCopy.streamLine(link: host?.link, away: host?.away, mac: client.macName.isEmpty ? "the Mac" : client.macName)
    }

    /// Nothing open over the stream: the Settings panel (which has the callout), the drawer, the
    /// pairing overlay, the first-run tour (its dim and card; VoiceOver is on its card meanwhile).
    private var linkLineAllowed: Bool { !settingsOpen && !drawerOpen && !shortcutsOpen && !overlayShown && !tourOnScreen }

    /// The clipboard's chip shows where the link's line may, and not over a thumbnail's lights or the
    /// Aa ruler either (the Settings panel has its own Paste).
    private var clipboardChipAllowed: Bool { linkLineAllowed && windowMenu == nil && !scaleOpen }

    /// The chip itself on screen, not its note in its place: its time runs only then.
    private var clipboardChipOnScreen: Bool {
        clipboardChipAllowed && client.clipboardChip && client.clipboardNote == nil && tourTargets[.stream] != nil
    }

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
            let scale = textScale ?? autoScale
            #if DEBUG
            print("viewport: \(Self.points(panelSize.width))×\(Self.points(panelSize.height)) pt, scale "
                  + TextScaleControl.label(scale) + (textScale == nil ? " (Auto)" : "") + ", \(fps) fps")
            #endif
            client.sendViewport(Viewport(width: Double(panelSize.width),
                                         height: Double(panelSize.height),
                                         scale: scale,
                                         fps: fps))
            if textScale == nil { checkAutoFit() }
        }
    }

    /// Auto's key for the window streaming now in this room, nil for the Desktop or nothing.
    private var autoKey: String? {
        guard case .window(let id) = client.active else { return nil }
        return "\(id)@\(Int(panelSize.width))x\(Int(panelSize.height))"
    }

    /// Auto's scale for what streams now: what fit before in this room, else 1×.
    private var autoScale: Double { autoKey.flatMap { autoScales[$0] } ?? AutoFit.steps[0] }

    /// Auto: once the Mac has had time to resize the window (and list it again), a window larger than
    /// asked (its app's minimum) tries the next smaller scale, until one fits or none is left.
    private func checkAutoFit() {
        autoCheck?.cancel()
        guard let key = autoKey, case .window(let id) = client.active else { return }
        let scale = autoScale, room = panelSize
        autoCheck = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, textScale == nil, autoKey == key, panelSize == room,
                  let w = client.windows.first(where: { $0.id == id }) else { return }
            let window = CGSize(width: w.width, height: w.height)
            guard !AutoFit.fits(window: window, room: room, scale: scale), let next = AutoFit.next(after: scale) else {
                autoScales[key] = scale
                return
            }
            #if DEBUG
            print("auto: \(w.appName) is \(w.width)×\(w.height) pt, larger than asked at \(TextScaleControl.label(scale))×; trying \(TextScaleControl.label(next))×")
            #endif
            autoScales[key] = next
            sendViewport()
        }
    }

    #if DEBUG
    /// A length for the console: whole points as whole numbers (within a hundredth: a scaled harness
    /// screen measures 693.99…), anything else to a tenth.
    private static func points(_ value: CGFloat) -> String {
        abs(value - value.rounded()) < 0.01 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }

    /// `larger picture: the switch on, the Desktop streams: the standard arrangement`, or `…, a window
    /// streams: Larger Picture above a 301 pt keyboard`, with `(held … while Settings is open)` while
    /// the panel holds it; nothing while the switch is off and nothing is held (the other gates'
    /// consoles stay as they were).
    private func largerPictureLine(_ keyboard: CGFloat?) -> String {
        guard largerPicture || largerPictureHeld != nil || keyboard != nil else { return "" }
        let streaming: String
        switch client.active {
        case .none: streaming = "nothing streams"
        case .desktop: streaming = "the Desktop streams"
        case .window: streaming = "a window streams"
        }
        var line = "larger picture: the switch " + (largerPicture ? "on" : "off") + ", " + streaming + ": "
        line += keyboard.map { "Larger Picture above a \(Self.points($0)) pt keyboard" } ?? "the standard arrangement"
        if let held = largerPictureHeld { line += " (held " + (held ? "on" : "off") + " while Settings is open)" }
        return line
    }

    /// The harness's arguments that act once the stream screen shows (ContentView's contract), once
    /// per launch. `-SillKeyboard 1` brings the software keyboard up for real in a live session (the
    /// mock only lights the button, from its init); `-SillKeyboardToggle <s>[,<s>…]` toggles it at
    /// those seconds as the Keyboard button does, a stand-in for a tap. In a live session (the
    /// normal app with `-SillConnect`, or `-SillLive 1`) `-SillDrawer 1`, `-SillSettings 1` and
    /// `-SillScaleOpen 1` (with `-SillScale`) open theirs 1.5 s in, once the Desktop has started
    /// (`-SillSettingsCloseAt <s>` closes the panel again s seconds in):
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
        // `-SillTurnAt <s>[,<s>…]`: at each second the scene is asked for the other orientation (upright
        // or sideways, from the screen's shape then), a turn mid-session with no hand on the simulator
        // (an iPhone's; iPadOS's windowing refuses it, and says so).
        let turns = (defaults.string(forKey: "SillTurnAt") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        for time in turns {
            after(time) {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    let bounds = scene.keyWindow?.bounds ?? .zero
                    let mask: UIInterfaceOrientationMask = bounds.width > bounds.height ? .portrait : .landscapeRight
                    print("turn: at \(Self.points(CGFloat(time))) s, asking for " + (mask == .portrait ? "portrait" : "landscape"))
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                        print("turn: refused: \(error.localizedDescription)")
                    }
                }
            }
        }
        // `-SillAXDump <s>`: s seconds in, the screen's accessibility elements in the order the
        // accessibility tree hands them out (VoiceOver's order, without VoiceOver), labels and frames.
        let dump = defaults.double(forKey: "SillAXDump")
        if dump > 0 { after(dump) { Self.accessibilityDump() } }
        // `-SillLargerPictureToggle <s>[,<s>…]`: Larger Picture switched at those seconds, as the
        // Settings panel's switch does (saved; without `-Sill.largerPicture`, which would hold it).
        let toggles = (defaults.string(forKey: "SillLargerPictureToggle") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        for time in toggles {
            after(time) {
                largerPicture.toggle()
                print("harness: Larger Picture switched " + (largerPicture ? "on" : "off") + " at " + Self.points(CGFloat(time)) + " s"
                      + (largerPictureHeld != nil ? "; the Settings panel is open, so it applies when the panel closes" : ""))
            }
        }
        guard live else { return }
        if defaults.bool(forKey: "SillDrawer") {
            after(1.5) { print("harness: the drawer opened"); withAnimation(.easeOut(duration: 0.18)) { drawerOpen = true } }
        }
        if defaults.bool(forKey: "SillSettings") {
            after(1.5) { print("harness: the Settings panel opened"); setSettings(true) }
            // `-SillSettingsCloseAt <s>`: closed again s seconds in, as Done does (the clipboard's chip
            // waiting under it, then showing: docs/clipboard-plan.md).
            let closeAt = defaults.double(forKey: "SillSettingsCloseAt")
            if closeAt > 1.5 { after(closeAt) { print("harness: the Settings panel closed"); setSettings(false) } }
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

    /// `-SillAXDump`: walks the key window as an assistive technology does (an element, else its
    /// `accessibilityElements`, else its element count, else its subviews) and prints one line per
    /// element: "ax: 1 Apps (14,454 76×50)".
    private static func accessibilityDump() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
            print("ax: no key window"); return
        }
        var lines: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: Any, _ depth: Int) {
            guard depth < 60, seen.count < 5000, let element = object as? NSObject, !element.accessibilityElementsHidden,
                  seen.insert(ObjectIdentifier(element)).inserted else { return }
            if element.isAccessibilityElement {
                let f = element.accessibilityFrame
                let label = element.accessibilityLabel ?? element.accessibilityValue ?? "(no label)"
                lines.append("\(label) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))")
                return
            }
            if let children = element.accessibilityElements, !children.isEmpty {
                children.forEach { visit($0, depth + 1) }
                return
            }
            let count = element.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                (0..<count).forEach { if let child = element.accessibilityElement(at: $0) { visit(child, depth + 1) } }
                return
            }
            if let view = element as? UIView {
                view.subviews.filter { !$0.isHidden && $0.alpha > 0 }.forEach { visit($0, depth + 1) }
            }
        }
        visit(window, 0)
        for (i, line) in lines.enumerated() { print("ax: \(i + 1) \(line)") }
    }
    #endif

    private func closeWindowMenu() { windowMenu = nil }

    /// Pair This iPad…, or an outside link waiting for its confirmation.
    private var overlayShown: Bool { pairingOverlay || client.pendingLink != nil }

    /// What is open over the stream that takes the keyboard for itself or must keep keys from the Mac
    /// (HardwareKeyboardPolicy.Taker): while any is, a hardware keyboard's hold lets go, and it comes
    /// back when the last closes.
    private var keyboardTakers: Set<HardwareKeyboardPolicy.Taker> {
        var takers: Set<HardwareKeyboardPolicy.Taker> = []
        if settingsOpen { takers.insert(.settings) }
        if overlayShown { takers.insert(.pairing) }
        if tour != nil { takers.insert(.tour) }
        if drawerOpen || shortcutsOpen { takers.insert(.drawer) }
        if menusOpen { takers.insert(.menus) }
        return takers
    }

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
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false; shortcutsOpen = false }
        windowMenu = nil
        scaleOpen = false
        overlay.setKeyboard(shown: false)
    }

    /// Larger Picture in effect now (PhonePortraitLayout's rule): the switch, while a window streams.
    /// The Desktop, which Aa never resizes, and nothing streaming keep the standard arrangement.
    private var largerPictureNow: Bool {
        PhonePortraitLayout.largerPicture(switchOn: largerPicture, streaming: .init(client.active))
    }

    /// Opens or closes the Settings panel. Opening puts the drawer, the traffic lights and the Aa
    /// ruler away and takes the keyboard down: with the overlay not first responder no hardware
    /// key reaches the Mac, and Esc (or ⌘.) reaches the panel's Done instead. Closing (Done, a tap
    /// outside, the Settings button, Esc, the VoiceOver escape gesture) puts the keyboard back if
    /// the panel took it down; the Apps and Keyboard buttons close it with `restoreKeyboard: false`
    /// because they decide about the keyboard themselves. While it is open the arrangement keeps the
    /// Larger Picture it opened with (`largerPictureHeld`); a change of the switch, or of what
    /// streams, applies as it closes.
    private func setSettings(_ open: Bool, restoreKeyboard: Bool = true) {
        guard open != settingsOpen else { return }
        if open {
            withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false; shortcutsOpen = false }
            windowMenu = nil
            scaleOpen = false
            keyboardBeforeSettings = keyboardShown
            overlay.setKeyboard(shown: false)
        }
        let motion: Animation = open && !reduceMotion ? .spring(duration: 0.25, bounce: 0.15) : .easeOut(duration: 0.18)
        withAnimation(motion) {
            settingsOpen = open
            // Larger Picture keeps the arrangement the panel opened with while it is open, so the
            // panel never moves under the finger: a change of the switch, or of what streams,
            // applies as the panel goes.
            largerPictureHeld = open ? largerPictureNow : nil
            fullScreenHeld = open ? fullScreen : nil
        }
        if !open {
            if restoreKeyboard, keyboardBeforeSettings { overlay.setKeyboard(shown: true) }
            keyboardBeforeSettings = false
        }
    }

    /// The Menus pull-down opened: the drawer, a thumbnail's lights and the Settings panel go, one
    /// thing open at a time; the keyboard stays as it is (the plan's §7.5). The panel had taken it
    /// down, so it comes back, but only when the pull-down goes: raised now, the software keyboard
    /// would come up, and key focus move, under the open menu.
    private func menusOpened() {
        keyboardAfterMenus = settingsOpen && keyboardBeforeSettings
        #if DEBUG
        if settingsOpen { print("menus: the pull-down opened over the Settings panel, which closes; the keyboard " + (keyboardAfterMenus ? "comes back when the pull-down goes" : "was down before it")) }
        #endif
        setSettings(false, restoreKeyboard: false)
        windowMenu = nil
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false; shortcutsOpen = false }
        menusOpen = true
    }

    private func menusClosed() {
        #if DEBUG
        if keyboardAfterMenus { print("menus: the pull-down went; the keyboard back up, as before the Settings panel") }
        #endif
        if keyboardAfterMenus { overlay.setKeyboard(shown: true) }
        keyboardAfterMenus = false
        menusOpen = false
    }

    // MARK: The tour

    /// The picture, as the tour counts it: the Mac's first window list, a frame size and a source
    /// that streams. A Mac that refuses this device, or cannot capture, never gets here.
    private var pictureReady: Bool {
        !client.macName.isEmpty && client.videoSize != .zero && client.active != .none
    }

    /// The tour is on screen (not put aside under the pairing overlay).
    private var tourOnScreen: Bool { tour != nil && !overlayShown }

    /// Whether the session a piece of the tour's delayed work began in (`client.connectedAt` then) is
    /// still the one on screen. A stream screen that has gone keeps its last state, and work it left
    /// waiting would act on it (a DEBUG stand-in pressed a card's Next after its session ended), and
    /// now write the next session's `client.tourSession`.
    private func sameSession(_ mark: Date?) -> Bool { client.connected && client.connectedAt == mark }
    /// The card on screen, if any.
    private var tourCard: TourTopic? { tourOnScreen ? tour?.at : nil }

    private var tourVoiceOver: Bool {
        #if DEBUG
        if TourDebug.current.voiceOver { return true }
        #endif
        return voiceOverEnabled
    }

    /// What is open at the decision, if anything (the rule's `busy`), in the console's words.
    private var tourBusy: String? {
        if drawerOpen { return "the Apps list was open" }
        if shortcutsOpen { return "the Shortcuts drawer was open" }
        if fullScreenShown { return "Full Screen was on" }
        if settingsOpen { return "Settings was open" }
        if windowMenu != nil { return "a window's lights were open" }
        if scaleOpen { return "the Aa ruler was open" }
        // The person's own keyboard: a hardware keyboard's hold is not theirs, so a person with a
        // keyboard attached still gets the tour (HardwareKeyboardPolicy).
        if keyboardShown { return "the keyboard was up" }
        if overlayShown { return "the pairing overlay was open" }
        // UIKit's word, not the scene phase: in a headless simulator the environment's scenePhase
        // stays inactive for an app that is active and on screen.
        if UIApplication.shared.applicationState != .active { return "the app was not active" }
        return nil
    }

    /// `keysOnItsSide`: the iPhone Duo open, whose keys and trackpad come with the device on its side.
    /// `thumbnails`: false for a phone with Larger Picture.
    private func tourCopy(_ run: TourRun, _ layout: TourLayout, keysOnItsSide: Bool = false, thumbnails: Bool = true) -> TourCopy {
        TourPolicy.copy(run.at, layout, mac: client.macName, device: StreamClient.deviceWord,
                        voiceOver: tourVoiceOver, firstOfRun: run.firstOfRun, keysOnItsSide: keysOnItsSide,
                        thumbnails: thumbnails)
    }

    private func tourLog(_ line: @autoclosure () -> String) {
        #if DEBUG
        print("tour: " + line())
        #endif
    }

    /// The first picture: once per session. Its decision comes a beat later.
    private func pictureCame() {
        guard pictureAt == nil else { return }
        pictureAt = ProcessInfo.processInfo.systemUptime
        #if DEBUG
        let debug = TourDebug.current
        let mark = client.connectedAt
        if let step = debug.start {
            // A turn later, once the screen has said which layout it is.
            Task { @MainActor in
                guard sameSession(mark) else { return }
                startTour(TourPolicy.replay(tourLayout ?? .landscape, voiceOver: tourVoiceOver, from: step))
            }
        }
        if let s = debug.activityAt, !TourDebug.touchedOnce {
            TourDebug.touchedOnce = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(s))
                guard sameSession(mark) else { return }
                touches.lastTouchAt = ProcessInfo.processInfo.systemUptime
                tourLog("a stand-in touch \(s) s after the picture")
                considerTour()
            }
        }
        if let s = debug.takeTourAt {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(s))
                guard sameSession(mark) else { return }
                tourLog("a stand-in for Settings, then Take the Tour")
                setSettings(true)
                try? await Task.sleep(for: .seconds(1))
                guard sameSession(mark) else { return }
                takeTour()
            }
        }
        #endif
        considerTour()
    }

    /// Portrait or landscape changed (a rotation, a resize, the Duo folding), or the screen came.
    /// A turn after the picture's decision gets one of its own; a run on screen follows the layout.
    private func layoutChanged(to layout: TourLayout) {
        let changed = tourLayout != nil && layout != tourLayout
        tourLayout = layout
        if changed {
            layoutAt = ProcessInfo.processInfo.systemUptime
            carryTour(reason: "a turn")
        }
        considerTour()
    }

    /// The run on screen as the layout (or VoiceOver) now has it; it ends, nothing more saved,
    /// when nothing of it is left here.
    private func carryTour(reason: String) {
        guard let run = tour, let layout = tourLayout else { return }
        guard let carried = TourPolicy.carry(run, to: layout, voiceOver: tourVoiceOver, memory: tourStore.memory) else {
            tourLog("ended by \(reason): nothing of it here (\(layout.rawValue))")
            endTour()
            return
        }
        // Shown in this layout now: a later turn back into it offers nothing again this session.
        client.tourSession.offered.insert(layout)
        guard carried != run else { return }
        tourLog("carried to \(carried.at.rawValue) (\(carried.index + 1) of \(carried.count), \(layout.rawValue))")
        tour = carried
    }

    /// The automatic tour's rule (TourPolicy.automatic), asked at the picture, at a layout change
    /// and when a wait runs out. One decision per session and layout.
    private func considerTour() {
        tourWait?.cancel()
        tourWait = nil
        guard tour == nil, let layout = tourLayout else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // A touch anywhere, input sent to the Mac, or a control used by any means. VoiceOver's
        // swipes that only move its focus are reading, as a look around the screen is, and are not
        // counted; VoiceOver also moves its focus by itself as a screen or a layout comes.
        let activity = [touches.lastTouchAt, client.lastInputAt, client.lastActionAt].compactMap { $0 }.max()
        let session = client.tourSession
        let moment = TourMoment(now: now, pictureAt: pictureAt, layoutAt: layoutAt, decided: session.decided,
                                lastActivityAt: activity, touchesDown: touches.down, busy: tourBusy != nil,
                                offered: session.offered.contains(layout), voiceOver: tourVoiceOver,
                                enabled: tourStore.automatic)
        switch TourPolicy.automatic(moment, layout, tourStore.memory) {
        case .wait(let until):
            guard let until else { return }
            #if DEBUG
            if tourWaitLogged != until {
                tourWaitLogged = until
                let owed = TourPolicy.owed(layout, voiceOver: tourVoiceOver, tourStore.memory)
                tourLog("owed here: \(Self.names(owed.map(\.rawValue))) (\(layout.rawValue); seen: \(Self.names(tourStore.memory.names)))")
                tourLog("waiting until 1.0 s after the \(session.decided && layoutAt > (pictureAt ?? 0) ? "turn" : "picture")")
            }
            #endif
            let mark = client.connectedAt
            tourWait = Task { @MainActor in
                try? await Task.sleep(for: .seconds(max(0.01, until - ProcessInfo.processInfo.systemUptime)))
                if !Task.isCancelled, sameSession(mark) { considerTour() }
            }
        case .pass(let reason):
            // A pass before the picture (the tour off) or once decided changes nothing.
            guard pictureAt != nil, moment.enabled, !moment.offered else { return }
            let since = session.decided && layoutAt > (pictureAt ?? 0) ? "the turn" : "the picture"
            client.tourSession.offered.insert(layout)
            client.tourSession.decided = true
            switch reason {
            case .nothingOwed:
                tourLog("nothing owed here (\(layout.rawValue); seen: \(Self.names(tourStore.memory.names))\(tourStore.memory.skipped ? "; skipped" : ""))")
            case .used:
                tourLog("not this session: used within a second of \(since)")
            case .busy:
                tourLog("not this session: \(touches.down > 0 ? "a touch was down" : tourBusy ?? "something was open")")
            }
        case .show(let steps):
            startTour(TourPolicy.run(owed: steps))
        }
    }

    private static func names(_ list: [String]) -> String {
        list.isEmpty ? "none" : list.joined(separator: ", ")
    }

    /// Starts a run: what could be open goes away (as for the pairing overlay), the keyboard goes
    /// down, and so hardware keys stop reaching the Mac. `keyboardAfter` is whether it comes back at
    /// the end (Take the Tour: whether it was up before Settings opened).
    private func startTour(_ run: TourRun?, keyboardAfter: Bool? = nil) {
        guard let run else { return }
        tourWait?.cancel()
        tourWait = nil
        if let layout = tourLayout { client.tourSession.offered.insert(layout) }
        client.tourSession.decided = true
        client.tourSession.running = true
        let keyboard = keyboardAfter ?? keyboardShown
        putAwayForOverlay()
        tourKeyboardAfter = keyboard
        withAnimation(.easeOut(duration: 0.25)) { tour = run }
    }

    /// Next, or Done on the last card: the step is saved as passed.
    private func tourNext() {
        guard let run = tour else { return }
        tourStore.save(TourPolicy.passed(run.at, tourStore.memory))
        tourLog("passed \(run.at.rawValue)")
        if let next = TourPolicy.next(run) {
            let motion: Animation = reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.1)
            withAnimation(motion) { tour = next }
        } else {
            tourLog("done (saved: \(Self.names(tourStore.memory.names))\(tourStore.writes ? "" : "; this run only"))")
            endTour()
        }
    }

    /// Skip (Esc, VoiceOver's escape gesture): the automatic tour is off for good on this device;
    /// in Take the Tour it only closes the run (TourPolicy.skip).
    private func tourSkip() {
        guard let run = tour else { return }
        let memory = TourPolicy.skip(run, tourStore.memory)
        if memory != tourStore.memory { tourStore.save(memory) }
        tourLog(run.replay ? "closed (Take the Tour; nothing more saved)" : "skipped (saved\(tourStore.writes ? "" : "; this run only"))")
        endTour()
    }

    /// The run ends: Done, Skip, or a turn with nothing of it left. Put aside under the pairing
    /// overlay (an outside link), it ends there too, and the keyboard stays down under that
    /// overlay, as the overlay leaves it at its own close.
    private func endTour() {
        let onScreen = tourOnScreen
        withAnimation(.easeOut(duration: 0.2)) { tour = nil }
        client.tourSession.running = false
        if tourKeyboardAfter && !overlayShown { overlay.setKeyboard(shown: true) }
        tourKeyboardAfter = false
        // VoiceOver reads the stream screen afresh (not from under the pairing overlay).
        if onScreen { AccessibilityNotification.ScreenChanged().post() }
    }

    /// Settings › Take the Tour: the panel closes without putting the keyboard back (the tour does,
    /// at its end, if it was up before the panel opened), then every step of the layout on screen.
    private func takeTour() {
        // The tour's cards point at the usual arrangement's rows: Full Screen goes first.
        fullScreen = false
        let keyboard = keyboardBeforeSettings
        setSettings(false, restoreKeyboard: false)
        tourLog("Take the Tour")
        let mark = client.connectedAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.18))      // the panel's close
            guard sameSession(mark) else { return }         // the session ended meanwhile
            startTour(TourPolicy.replay(tourLayout ?? .landscape, voiceOver: tourVoiceOver), keyboardAfter: keyboard)
        }
    }

    /// A card came on screen (the tour's first, the next, or the same one back from under the
    /// pairing overlay), or the tour went or was put aside under that overlay.
    private func tourCardChanged(_ card: TourTopic?) {
        // Nothing reaches the Mac as input while a card shows (StreamClient.inputPaused).
        client.inputPaused = card != nil
        guard let run = tour else { return }
        if card != nil {
            let since = pictureAt.map { String(format: ", %.2f s after the picture", ProcessInfo.processInfo.systemUptime - $0) } ?? ""
            tourLog("showing \(run.at.rawValue) (\(run.index + 1) of \(run.count))\(since)")
            tourPressLater(run)
        } else {
            tourLog("put aside for the pairing overlay, at \(run.at.rawValue)")
        }
    }

    /// DEBUG `-SillTourPress`: presses a card's Next (or Skip, once) a while after it appears.
    private func tourPressLater(_ run: TourRun) {
        #if DEBUG
        guard let press = TourDebug.current.press else { return }
        let seconds: Double
        let skip: Bool
        switch press {
        case .next(let s): seconds = s; skip = false
        case .skip(let s): seconds = s; skip = !tourSkipPressed
        }
        if skip { tourSkipPressed = true }
        let mark = client.connectedAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard sameSession(mark), tour?.at == run.at, tourOnScreen else { return }
            tourLog("a stand-in presses \(skip ? "Skip" : run.isLast ? "Done" : "Next")")
            if skip { tourSkip() } else { tourNext() }
        }
        #endif
    }

    /// Grows from the Settings button's corner, the way a popover would; a plain fade under Reduce
    /// Motion. `anchor` is the panel's top-trailing corner as a point of the view the transition is
    /// attached to. In landscape that view is the content area, whose corner is within a few
    /// points of the panel's; in portrait it is the whole screen, where `.topTrailing` would make
    /// the panel slide down over the window bar (PortraitStreamScreen passes its own).
    private func settingsTransition(anchor: UnitPoint = .topTrailing) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.94, anchor: anchor).combined(with: .opacity)
    }

    private func landscape(bar plain: BarMetrics, width: CGFloat, fold: FoldInfo) -> some View {
        // The book pose (docs/iphone-duo-plan.md, (a)): nothing on the fold's band; elsewhere as before.
        let (bar, stripWidth) = plain.clearing(fold, width: width)
        return VStack(spacing: 0) {
            TopBar(client: client, metrics: bar, stripWidth: stripWidth, drawerOpen: $drawerOpen,
                   keyboardShown: $keyboardShown,
                   textScale: $textScale, scaleOpen: $scaleOpen, windowMenu: $windowMenu,
                   settingsOpen: settingsOpen,
                   // Apps, Menus, Aa, Keyboard, Desktop, Settings, and the strip.
                   menusFit: MacMenuButton.fits(width: width - 2 * bar.padding, buttons: 6, buttonWidth: bar.buttonWidth,
                                                gap: bar.gap, thumbWidth: bar.thumbWidth),
                   toggleKeyboard: { overlay.toggleKeyboard() },
                   setSettings: { setSettings($0, restoreKeyboard: $1) },
                   menusOpened: menusOpened, menusClosed: menusClosed)
            contentArea(bar: bar)
        }
    }

    /// `largerKeyboard`: Larger Picture's keyboard on a phone (see `body`), nil otherwise.
    private func portrait(metrics: PortraitMetrics, largerKeyboard: CGFloat? = nil,
                          fullScreen: FullScreenControls? = nil) -> some View {
        PortraitStreamScreen(client: client, metrics: metrics, drawerOpen: $drawerOpen,
                             shortcutsOpen: $shortcutsOpen,
                             keyboardShown: $keyboardShown,
                             textScale: $textScale, scaleOpen: $scaleOpen, windowMenu: $windowMenu,
                             latched: $latched, overlay: overlay,
                             settingsOpen: settingsOpen,
                             setSettings: { setSettings($0, restoreKeyboard: $1) },
                             menusOpened: menusOpened, menusClosed: menusClosed,
                             settingsTransition: { settingsTransition(anchor: $0) },
                             onPanelSize: { panelSize = $0 },
                             pairThisDevice: openPairingOverlay,
                             linkLine: shownLinkLine,
                             takeTour: takeTour,
                             largerKeyboard: largerKeyboard,
                             fullScreen: fullScreen,
                             enterFullScreen: metrics.phone && duoEnvironment.hinge == .unknown
                                ? { withAnimation(.easeOut(duration: 0.2)) { self.fullScreen = true } } : nil)
    }

    /// Full Screen in effect: the switch on (as it was when Settings opened, while it is open), a
    /// phone held upright, no hinge. Whatever streams, so a window closing (nothing, for a moment,
    /// until the Desktop) never drops out of it and back, each time with a new viewport.
    private func fullScreenOn(_ layout: TourLayout, _ posture: DuoPosture) -> Bool {
        (fullScreenHeld ?? fullScreen) && layout == .phone && DuoLayout.phoneArrangement && posture.hinge == .unknown
    }

    private var fullScreenControls: FullScreenControls {
        FullScreenControls(trackpad: $fullScreenTrackpad, expanded: $fullScreenExpanded,
                           insets: Self.windowInsets,
                           exit: { withAnimation(.easeOut(duration: 0.2)) { fullScreen = false } })
    }

    /// The key window's safe-area insets: Full Screen's picture starts under the top one (the status
    /// bar and the notch), its controls keep above the bottom one.
    private static var windowInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
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
                             onModifiersConsumed: { latched = [] },
                             sendGesture: { client.sendGesture($0, fingers: $1) })
            }
            .background(Palette.panel)
            .overlay(alignment: .top) { LinkLineView(text: shownLinkLine) }
            .clipShape(streamShape)
            .overlay(streamShape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            // The panel itself, inside the padding: the size the host fits the Mac window to.
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { panelSize = $0 })
            .tourTarget(.stream)
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

                HostSettingsPanel(client: client, close: { setSettings(false) }, pairThisDevice: openPairingOverlay,
                                  takeTour: takeTour)
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
/// In the iPhone Duo's book pose it is centred on the leading page instead, off the fold
/// (docs/iphone-duo-plan.md).
struct LinkLineView: View {
    let text: String?
    /// The Duo's hinge (iOS 27.1): with the fold, where the line goes.
    @Environment(\.duoEnvironment) private var duoEnvironment
    var body: some View {
        GeometryReader { geo in
            let page = DuoPosture.leadingPage(DuoPosture.read(geo, duoEnvironment).info(in: geo.size))
            line
                .frame(width: page ?? geo.size.width)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private var line: some View {
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
    /// The book pose: the strip's width, so that it ends short of the fold (BarMetrics.clearing);
    /// nil: it takes the room there is, as before.
    var stripWidth: CGFloat? = nil
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    @Binding var textScale: Double?
    @Binding var scaleOpen: Bool
    @Binding var windowMenu: UInt32?
    let settingsOpen: Bool
    /// Whether the bar holds the Menus button and still a whole thumbnail (`MacMenuButton.fits`).
    let menusFit: Bool
    let toggleKeyboard: () -> Void
    /// Opens or closes the Settings panel; the second argument says whether closing puts the
    /// keyboard back (see `StreamScreen.setSettings`).
    let setSettings: (_ open: Bool, _ restoreKeyboard: Bool) -> Void
    /// The Menus pull-down opened and went (see `StreamScreen.menusOpened`).
    let menusOpened: () -> Void
    let menusClosed: () -> Void

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
                .frame(width: stripWidth)
                .tourTarget(.strip, inset: WindowStrip.tourBand(pad: metrics.thumbPad))
            // The book pose: the fold's band, and nothing on it, between the strip and the buttons.
            if stripWidth != nil { Spacer(minLength: 0) }

            // The Mac's menus of the streamed app, next to the thumbnails because they are the picked
            // window's app's. Only while the Mac sent some, and where the bar holds it: with none the
            // strip takes its room back.
            if client.menus.hasMenus, menusFit {
                MacMenuButton(client: client, width: metrics.buttonWidth, height: metrics.buttonHeight,
                              spacing: metrics.buttonSpacing, onOpen: menusOpened, onClose: menusClosed)
                    .opacity(scaleOpen ? 0 : 1)    // under the Aa ruler, as the buttons after Aa
                    .allowsHitTesting(!scaleOpen)
                    .transition(.opacity)
            }

            // Text size: the host sizes the Mac window to the panel divided by this scale, so a
            // bigger number means a smaller Mac window and bigger text here. The slider unfolds to
            // the right, over the two buttons after it, which fade while it is open.
            TextScaleControl(scale: $textScale, open: $scaleOpen,
                             width: metrics.buttonWidth, height: metrics.buttonHeight,
                             pointsPerStep: metrics.buttonHeight >= 60 ? 44 : 40)
                .tourTarget(.textSize)

            button(open: keyboardShown, symbol: "keyboard", label: "Keyboard",
                   accessibilityLabel: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                   action: { setSettings(false, false); toggleKeyboard() })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
                .tourTarget(.keyboard)

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
                .tourTarget(.settings)
        }
        .animation(.easeOut(duration: 0.16), value: scaleOpen)
        .animation(.easeOut(duration: 0.18), value: client.menus.hasMenus)
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
        KeyChord.spotlight.forEach(send)
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
    /// The picture's zoom, where this Aa offers it (a phone's row 1): a tap turns it on and off, and
    /// a hold shows its ruler above Aa's, which the finger reaches by moving up. nil: Aa alone.
    var zoom: PictureZoom? = nil

    /// The detents, Auto first: 0 stands for Auto (`scale` nil), the Sill's own pick
    /// (`AutoFit`): the largest text whose window the Mac's app takes whole.
    static let steps: [Double] = [0, 0.5, 0.75, 1.0, 1.25, 1.5]
    /// Padding either side of the visible ruler; two detents show each side of the thumb.
    static let sliderInset: CGFloat = 30
    var sliderWidth: CGFloat { pointsPerStep * CGFloat(Self.steps.count - 1) + Self.sliderInset * 2 }
    /// Between Aa's ruler and the zoom's above it.
    static let rulerGap: CGFloat = 8
    /// A touch that moves less than this and lifts within `tapTime` is a tap.
    static let tapSlop: CGFloat = 8
    static let tapTime: TimeInterval = 0.3

    @State private var live: Double = 1.0
    @State private var startValue: Double = 1.0
    @State private var startX: CGFloat = 0
    /// The zoom ruler is the one the finger is on.
    @State private var onZoom = false
    @State private var liveZoom: Double = 1.0
    @State private var touchStart: Date?

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
            if let zoom {
                ZoomValueLabel(zoom: zoom, text: Self.valueLabel(scale ?? 0))
            } else {
                Text(Self.valueLabel(scale ?? 0))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.barLabel)
            }
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.control))
        .opacity(open ? 0 : 1)
        .overlay {
            // Centred on the button: the thumb is where the finger came down.
            slider(values: Self.steps, live: live, active: !onZoom)
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.6)
                .allowsHitTesting(false)
        }
        .overlay {
            if zoom != nil {
                // The zoom's ruler, over Aa's, on the picture's edge.
                slider(values: PictureZoom.steps, live: liveZoom, active: onZoom)
                    .offset(y: -(height + Self.rulerGap))
                    .opacity(open ? 1 : 0)
                    .scaleEffect(open ? 1 : 0.6, anchor: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(open ? 1 : 0)
        .onChange(of: open, initial: true) { _, isOpen in
            if isOpen { live = scale ?? 0; liveZoom = zoom?.scale ?? 1.0 }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    if touchStart == nil {
                        let start = Date()
                        touchStart = start
                        onZoom = false
                        startValue = scale ?? 0
                        live = startValue
                        liveZoom = zoom?.scale ?? 1.0
                        startX = g.location.x
                        if zoom == nil {
                            unfold()
                        } else {
                            // Where Aa offers the zoom a quick tap turns it on or off, so the rulers wait
                            // for a hold or a move: a tap never flashes them (nor folds row 1 away).
                            DispatchQueue.main.asyncAfter(deadline: .now() + Self.tapTime) {
                                if touchStart == start, !open { unfold() }
                            }
                        }
                    }
                    if !open {
                        guard hypot(g.translation.width, g.translation.height) >= Self.tapSlop else { return }
                        unfold()
                    }
                    // Up past half a button's height: the zoom's ruler; back down: Aa's. A change of
                    // ruler starts from where the finger is, so neither value jumps.
                    let wantsZoom = zoom != nil && g.translation.height < -height / 2
                    if wantsZoom != onZoom {
                        onZoom = wantsZoom
                        startX = g.location.x
                        startValue = wantsZoom ? liveZoom : live
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    // The ruler follows the finger: dragging right raises the value, and the ticks
                    // slide left under the fixed thumb.
                    let steps = Double((g.location.x - startX) / pointsPerStep)
                    if onZoom {
                        let snapped = Self.snap(startValue, by: steps, in: PictureZoom.steps)
                        if snapped != liveZoom {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeOut(duration: 0.1)) { liveZoom = snapped }
                        }
                    } else {
                        let snapped = Self.snap(startValue, by: steps, in: Self.steps)
                        if snapped != live {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeOut(duration: 0.1)) { live = snapped }
                        }
                    }
                }
                .onEnded { g in
                    let tapped = hypot(g.translation.width, g.translation.height) < Self.tapSlop
                        && Date().timeIntervalSince(touchStart ?? .distantPast) < Self.tapTime
                    if let zoom, tapped {
                        zoom.toggle()                                // a tap: the zoom on or off
                    } else if onZoom {
                        if let zoom, zoom.scale != liveZoom { zoom.scale = liveZoom }
                    } else if (scale ?? 0) != live {
                        scale = live == 0 ? nil : live     // a plain tap on an untouched control changes nothing
                    }
                    touchStart = nil
                    withAnimation(.easeOut(duration: 0.2)) { open = false; onZoom = false }
                }
        )
        .onDisappear { open = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text size")
        .accessibilityValue(scale.map { "\(Self.label($0)) times" } ?? "Auto")
        .accessibilityAdjustableAction { direction in
            let i = Self.steps.firstIndex(of: scale ?? 0) ?? 0
            let next: Double
            switch direction {
            case .increment: next = Self.steps[min(i + 1, Self.steps.count - 1)]
            case .decrement: next = Self.steps[max(i - 1, 0)]
            @unknown default: return
            }
            scale = next == 0 ? nil : next
        }
        .modifier(ZoomActions(zoom: zoom))
    }

    /// The rulers open, centred on Aa.
    private func unfold() {
        withAnimation(.spring(duration: 0.22, bounce: 0.15)) { open = true }
    }

    /// A ruler: a track with a tick and a label per value, sliding so the live value sits under the
    /// fixed thumb; the ends fade out where they run past the panel. The ruler the finger is not on
    /// is dimmed.
    private func slider(values: [Double], live: Double, active: Bool) -> some View {
        let w = sliderWidth
        let step = pointsPerStep
        let midX = w / 2
        let midY = height / 2 + 4
        let liveIndex = CGFloat(values.firstIndex(of: live) ?? 0)
        func x(_ index: Int) -> CGFloat { midX + (CGFloat(index) - liveIndex) * step }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.controlOpen)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.barLabel.opacity(0.35))
                    .frame(width: step * CGFloat(values.count - 1), height: 3)
                    .offset(x: x(0), y: midY - 1.5)
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Rectangle().fill(Palette.barLabel.opacity(0.6))
                        .frame(width: 2, height: 9)
                        .offset(x: x(index) - 1, y: midY - 4.5)
                    Text(Self.label(value))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(value == live ? Palette.text : Palette.barLabel)
                        .frame(width: step, alignment: .center)
                        .offset(x: x(index) - step / 2, y: midY + 9)
                }
            }
            .frame(width: w, height: height, alignment: .topLeading)   // the mask below is sized to this
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            Circle().fill(active ? Palette.accent : Palette.barLabel)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .offset(x: midX - 11, y: midY - 11)
            // The live value over the thumb, where the finger does not cover it. In a 50 pt ruler
            // (a phone's row 1, the compact window bar) `midY - 34` put the top of its digits 2 pt
            // outside the clip; it sits where the 58 pt bars put it (1 pt above the frame's top,
            // the digits 2 pt inside), and in the taller bars as it always has.
            Text(Self.valueLabel(live))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 60, alignment: .center)
                .offset(x: midX - 30, y: max(midY - 34, -1))
        }
        .frame(width: w, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(active ? 1 : 0.55)
    }

    /// `values`' detent `steps` detents (rounded) from `start`, clamped to the ends.
    static func snap(_ start: Double, by steps: Double, in values: [Double]) -> Double {
        let from = values.firstIndex(of: start) ?? 0
        let index = min(max(from + Int(steps.rounded()), 0), values.count - 1)
        return values[index]
    }

    /// Under Aa and over the thumb: "Auto", or "0.75×".
    static func valueLabel(_ scale: Double) -> String { scale == 0 ? "Auto" : label(scale) + "×" }

    /// 0.5, 0.75, 1, 1.25, 1.5: trailing zeros dropped, and "1" rather than "1.0"; 0 is Auto.
    static func label(_ scale: Double) -> String {
        if scale == 0 { return "Auto" }
        var text = String(format: "%.2f", scale)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// Aa's value line where Aa offers the zoom: Aa's value, and the zoom's beside it while zoomed.
private struct ZoomValueLabel: View {
    @ObservedObject var zoom: PictureZoom
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
            if zoom.scale > 1 {
                Image(systemName: "plus.magnifyingglass").font(.system(size: 9, weight: .semibold))
                Text(TextScaleControl.label(zoom.scale) + "×")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(zoom.scale > 1 ? Palette.text : Palette.barLabel)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// VoiceOver's way to the zoom: actions on Aa, where it offers one.
private struct ZoomActions: ViewModifier {
    let zoom: PictureZoom?

    func body(content: Content) -> some View {
        if let zoom {
            content
                .accessibilityAction(named: "Zoom in") {
                    let i = PictureZoom.steps.firstIndex(of: zoom.scale) ?? 0
                    zoom.scale = PictureZoom.steps[min(i + 1, PictureZoom.steps.count - 1)]
                }
                .accessibilityAction(named: "Zoom out") {
                    let i = PictureZoom.steps.firstIndex(of: zoom.scale) ?? 0
                    zoom.scale = PictureZoom.steps[max(i - 1, 0)]
                }
        } else {
            content
        }
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
    /// The Desktop as the strip's first tile, fixed there (a phone's row 2, where row 1 has no
    /// Desktop button; Raffael, 2026-10-21). It never moves, and windows cannot be dragged before it.
    var desktopFirst = false
    /// Which thumbnail has its traffic-light submenu open. Owned by the screen root, which draws
    /// the submenu outside this clipped strip.
    @Binding var menuFor: UInt32?

    /// Press and hold a thumbnail for 1.5 s: it starts to wiggle and its traffic lights (close,
    /// minimize, full screen) appear in a submenu beside it, the way a held Home Screen icon
    /// offers its menu. Keep holding and move: the submenu goes, the thumbnail lifts and drags
    /// into a new slot. The arrangement is the device's own, persisted per Mac. A tap selects.
    static let holdToOpen: TimeInterval = 1.5
    /// What the tour lights of the strip: its thumbnails' band (the strip is as tall as its bar),
    /// with the active halo's 5 pt above and the app badge's 6 pt below.
    static func tourBand(pad: CGFloat) -> EdgeInsets {
        EdgeInsets(top: max(0, pad - 5), leading: 0, bottom: max(0, pad - 6), trailing: 0)
    }
    /// The item being dragged (`StripItem.id`).
    @State private var lifted: String? = nil
    @State private var liftOffset: CGFloat = 0
    @State private var liftStartIndex = 0
    /// The slot the dragging finger last reached.
    @State private var lastTarget = -1

    /// One thumbnail in the strip: a window, or a stack of one app's windows (Raffael, 2026-10-21:
    /// one per app). A stack shows its app's window that streams, else its first; a tap opens its
    /// panel over the strip (`StackPanel`), where a window is chosen.
    struct StripItem: Identifiable {
        let id: String
        let windows: [WindowInfo]
        let stacked: Bool
        var front: WindowInfo { windows[0] }
    }

    /// `windows` (each app's together, `StreamClient.orderedWindows`) as the strip's items: one app's
    /// several windows a stack.
    static func items(_ windows: [WindowInfo], active: StreamSource) -> [StripItem] {
        var runs: [[WindowInfo]] = []
        for window in windows {
            if let last = runs.last?.last, last.bundleID == window.bundleID { runs[runs.count - 1].append(window) } else { runs.append([window]) }
        }
        return runs.flatMap { run -> [StripItem] in
            guard run.count > 1 else {
                return run.map { StripItem(id: "w\($0.id)", windows: [$0], stacked: false) }
            }
            var ordered = run
            if case .window(let id) = active, let i = run.firstIndex(where: { $0.id == id }) { ordered.insert(ordered.remove(at: i), at: 0) }
            return [StripItem(id: "s" + run[0].bundleID, windows: ordered, stacked: true)]
        }
    }

    private var currentItems: [StripItem] {
        Self.items(client.orderedWindows, active: client.active)
    }

    var body: some View {
        let items = currentItems
        let slot = width + spacing
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                if desktopFirst {
                    DesktopTile(isActive: client.active == .desktop, width: width, height: height, radius: radius,
                                onSelect: { if menuFor != nil { closeMenu() } else { pick(.desktop) } })
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    tile(item, index: index)
                        .overlay {
                            HoldDragOverlay(minimumHold: Self.holdToOpen,
                                            onTap: { tapped(item) },
                                            onHold: { if !item.stacked { openMenu(for: item.front.id) } },
                                            onMove: { t in holdMoved(item: item, index: index, count: items.count, slot: slot, translation: t) },
                                            onEnd: { holdEnded(item: item) })
                        }
                        .offset(x: lifted == item.id ? liftOffset : 0)
                        .zIndex(lifted == item.id ? 1 : 0)
                        // The lifted thumbnail follows the finger: its slot change must not animate,
                        // or the layout springs one way while the compensating offset jumps the other.
                        .transaction { if lifted == item.id { $0.animation = nil } }
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
            if let id = lifted, !currentItems.contains(where: { $0.id == id }) {
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

    /// A window's thumbnail, or a stack: its front window's thumbnail over two cards, the count on it.
    @ViewBuilder private func tile(_ item: StripItem, index: Int) -> some View {
        let window = item.front
        let thumbnail = WindowThumbnail(window: window,
                                        image: client.thumbnails[window.id],
                                        icon: client.icons[window.bundleID],
                                        isActive: item.windows.contains { client.active == .window($0.id) },
                                        width: width, height: height, radius: radius, badge: badge,
                                        menuOpen: menuFor == window.id,
                                        lifted: lifted == item.id,
                                        onSelect: { pick(.window(window.id)) },
                                        onCommand: { client.command($0, window: window.id) },
                                        onMove: { step in
                                            client.moveWindow(window.id, to: Self.windowIndex(ofItem: index + step, in: currentItems, windows: client.orderedWindows))
                                            client.persistWindowOrder()
                                        })
        if item.stacked {
            ZStack {
                ForEach([2, 1], id: \.self) { depth in
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Palette.control)
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .frame(width: width, height: height)
                        .scaleEffect(1 - CGFloat(depth) * 0.06)
                        .offset(y: -CGFloat(depth) * 4)
                }
                thumbnail
            }
            .overlay(alignment: .topTrailing) {
                Text("\(item.windows.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Palette.accent))
                    .offset(x: 6, y: -6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.appName), \(item.windows.count) windows")
            .accessibilityHint("Shows its windows")
            .anchorPreference(key: StackAnchorKey.self, value: .bounds) {
                client.openStack == window.bundleID ? StackAnchor(app: window.bundleID, bounds: $0) : nil
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { tapped(item) }
        } else {
            thumbnail
        }
    }

    /// A tap: a stack opens its panel (again: closes it); a window streams.
    private func tapped(_ item: StripItem) {
        if menuFor != nil { closeMenu(); return }
        if item.stacked {
            UISelectionFeedbackGenerator().selectionChanged()
            let app = item.front.bundleID
            withAnimation(.spring(duration: 0.28, bounce: 0.15)) { client.openStack = client.openStack == app ? nil : app }
        } else {
            pick(.window(item.front.id))
        }
    }

    private func pick(_ source: StreamSource) {
        client.select(source)
        if client.openStack != nil { withAnimation(.easeOut(duration: 0.18)) { client.openStack = nil } }
    }

    /// Where item `index` starts among the windows (its first window's place); past the end, the last.
    static func windowIndex(ofItem index: Int, in items: [StripItem], windows: [WindowInfo]) -> Int {
        guard !items.isEmpty else { return 0 }
        let item = items[min(max(index, 0), items.count - 1)]
        return windows.firstIndex { $0.id == item.windows.last(where: { _ in index >= items.count - 1 })?.id ?? item.front.id }
            ?? max(0, windows.count - 1)
    }

    /// The finger moved while the hold is still down. More than 8 pt lifts the thumbnail (or the
    /// stack) and drags it; the drag reorders live: crossing the middle of a neighbour swaps slots,
    /// and the lifted thumbnail's offset is corrected by the slots it has moved so it stays under the
    /// finger. A stack moves its app's windows together (StreamClient.moveWindow).
    private func holdMoved(item: StripItem, index: Int, count: Int, slot: CGFloat, translation t: CGSize) {
        if lifted == nil {
            guard abs(t.width) > 8 || abs(t.height) > 8 else { return }
            closeMenu()
            lifted = item.id
            liftStartIndex = index
            lastTarget = index
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        guard lifted == item.id else { return }
        let shift = Int((t.width / slot).rounded())
        let target = max(0, min(count - 1, liftStartIndex + shift))
        // One move a slot the finger reaches: an app's windows move as a run, so the tile need not
        // land on `target`, and asking again would buzz on every move.
        if target != lastTarget, let current = currentItems.firstIndex(where: { $0.id == item.id }), current != target {
            UISelectionFeedbackGenerator().selectionChanged()
            let to = Self.windowIndex(ofItem: target, in: currentItems, windows: client.orderedWindows)
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) { client.moveWindow(item.front.id, to: to) }
        }
        lastTarget = target
        let now = currentItems.firstIndex(where: { $0.id == item.id }) ?? target
        liftOffset = t.width - CGFloat(now - liftStartIndex) * slot
    }

    /// The finger lifted after a hold: drop the thumbnail (the submenu, if open, stays).
    private func holdEnded(item: StripItem) {
        guard lifted == item.id else { return }
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
/// Where the open stack's tile is, for its panel (`StackPanel`), drawn by the stream screen.
struct StackAnchor: Equatable {
    let app: String
    let bounds: Anchor<CGRect>
    static func == (a: StackAnchor, b: StackAnchor) -> Bool { a.app == b.app }
}

struct StackAnchorKey: PreferenceKey {
    static var defaultValue: StackAnchor? = nil
    static func reduce(value: inout StackAnchor?, nextValue: () -> StackAnchor?) {
        if let next = nextValue() { value = next }
    }
}

/// An app's windows, opened from its stack in the strip: a panel over the strip, the app's name and
/// count on top, each window larger than in the strip with its title under it. A tap shows that window
/// and closes the panel; a tap anywhere else closes it.
struct StackPanel: View {
    @ObservedObject var client: StreamClient
    let anchor: StackAnchor
    let screen: CGSize
    let below: Bool

    static let cardWidth: CGFloat = 132
    static let cardHeight: CGFloat = 82

    var body: some View {
        let windows = client.orderedWindows.filter { $0.bundleID == anchor.app }
        GeometryReader { geo in
            let tile = geo[anchor.bounds]
            let width = min(geo.size.width - 24, CGFloat(windows.count) * (Self.cardWidth + 10) + 30)
            let height: CGFloat = 44 + Self.cardHeight + 36
            let x = min(max(tile.midX, width / 2 + 12), geo.size.width - width / 2 - 12)
            let y = below ? tile.maxY + 10 + height / 2 : tile.minY - 10 - height / 2
            ZStack {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AppIcon(image: client.icons[anchor.app], name: windows.first?.appName ?? "", size: 22, radius: 6, fontSize: 9)
                        Text(windows.first?.appName ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Text("\(windows.count) windows")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.barLabel)
                        Spacer(minLength: 0)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(windows, id: \.id) { window in card(window) }
                        }
                    }
                }
                .padding(12)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.bar))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
                .position(x: x, y: y)
                .transition(.scale(scale: 0.9, anchor: below ? .top : .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: windows.count) { _, n in if n < 2 { close() } }
    }

    private func card(_ window: WindowInfo) -> some View {
        let active = client.active == .window(window.id)
        return Button {
            client.select(.window(window.id))
            close()
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let image = client.thumbnails[window.id] {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Palette.thumbBody
                    }
                }
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(active ? Palette.accent : Color.white.opacity(0.12), lineWidth: active ? 2 : 1))
                Text(window.title.isEmpty ? window.appName : window.title)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Palette.text : Palette.barLabel)
                    .lineLimit(1)
                    .frame(width: Self.cardWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(window.title.isEmpty ? window.appName : window.title)" + (active ? ", showing now" : ""))
    }

    private func close() { withAnimation(.easeOut(duration: 0.18)) { client.openStack = nil } }
}

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
    /// The Duo's hinge (iOS 27.1): the lights keep off its fold.
    @Environment(\.duoEnvironment) private var duoEnvironment

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy[anchor]
            let w = Self.size.width, h = Self.size.height
            // Off the Duo's fold (iOS 27.1): onto a page beside it, below the thumbnail when above it
            // would sit on it; elsewhere as before.
            let at = DuoPosture.lightsMenu(x: min(max(frame.midX, w / 2 + 8), proxy.size.width - w / 2 - 8),
                                           below: alwaysBelow(proxy.size) || frame.midY < proxy.size.height / 2,
                                           thumbnail: frame, size: Self.size, gap: 8, screenWidth: proxy.size.width,
                                           fold: DuoPosture.read(proxy, duoEnvironment).info(in: proxy.size))
            let below = at.below, x = at.x, y = at.y
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

/// The Desktop as a thumbnail (`WindowStrip.desktopFirst`): the Mac's symbol on a thumbnail's
/// ground, its name under it, the active halo while the Desktop streams. A tap shows the Desktop.
private struct DesktopTile: View {
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: height * 0.36, weight: .regular))
                Text("Desktop")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Palette.accent : Palette.text)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.control))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
                        .strokeBorder(Palette.accent, lineWidth: 2)
                        .padding(-5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show the full Mac desktop" + (isActive ? ", showing now" : ""))
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
    /// The search field has the keyboard. Set only by DEBUG `-SillDrawerSearch` (ContentView's
    /// contract); a tap focuses the field as before.
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            searchField
            ScrollView {
                VStack(spacing: 6) {
                    if search.isEmpty {
                        DrawerRow(height: 50, highlighted: client.active == .desktop, title: "Desktop",
                                  trailing: nil, action: {
                                      client.select(.desktop)
                                      withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
                                  }) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 16))
                                .foregroundStyle(Palette.text)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.control))
                        }
                    }
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
                .focused($searchFocused)
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
        #if DEBUG
        .onAppear(perform: searchFromLaunchArguments)
        #endif
    }

    #if DEBUG
    /// `-SillDrawerSearch <text>` (ContentView's contract): the drawer, once open, searches for that
    /// text with the keyboard up for its field, as a tap and typing would, so a photo shows what the
    /// keyboard leaves in view of the results.
    private func searchFromLaunchArguments() {
        guard let query = UserDefaults.standard.string(forKey: "SillDrawerSearch") else { return }
        search = query
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            searchFocused = true
            print("harness: the drawer's search field has the keyboard, searching for \"\(query)\"")
        }
    }
    #endif

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
                    // Whole, on one line, whatever the title's length: the title truncates instead
                    // ("Not paired", "Update Sill" and "3 windows" hold a space).
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .fixedSize()
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

// MARK: - Larger Picture's view of what streams

extension PhonePortraitLayout.Streaming {
    /// What the Mac's window list says streams (`StreamClient.active`), as Larger Picture's rule
    /// (`PhonePortraitLayout.largerPicture(switchOn:streaming:)`) reads it.
    init(_ source: StreamSource) {
        switch source {
        case .none: self = .nothing
        case .desktop: self = .desktop
        case .window: self = .window
        }
    }
}
