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

/// Sill's hold on the device's own auto-lock (UIApplication.isIdleTimerDisabled) across its windows
/// (DeviceIdlePolicy, PR #230). Each window's WindowSessionObserver says which session it shows and
/// in which UIWindow, both weak as MacMenuHub's are, so a window that closed leaves nothing, whether
/// or not its stream screen ran its onDisappear; every look lists them afresh: whether a window's
/// scene is foreground active now, whether its session is connected and streaming, and when the
/// person last used it (DeviceIdlePolicy.lastUse: input the person sent the Mac, one of the stream
/// screen's controls, the start of a session the person started, the moment the window came to the
/// front; nothing the device did by itself). It looks again when a scene comes, goes or changes its
/// activation, when a session connects, disconnects or changes its source, when the person uses a
/// session while nothing holds, and when the hold would end. Main thread.
final class DeviceIdleTimer {
    static let shared = DeviceIdleTimer()

    private struct Entry {
        weak var client: StreamClient?
        weak var window: UIWindow?
        /// When its window's scene last came to the front (systemUptime); nil while it is not there.
        var frontSince: Double?
    }
    private var entries: [Entry] = []
    private var observers: [NSObjectProtocol] = []
    private var recheck: Timer?
    /// Whether auto-lock is held off now.
    private(set) var holding = false

    private init() {
        for name in [UIScene.willConnectNotification, UIScene.didDisconnectNotification, UIScene.didActivateNotification,
                     UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // A scene's activation state reads its new value once its notification has gone out.
                DispatchQueue.main.async { self?.update() }
            })
        }
    }

    /// A session's screen moved into `window` (nil: out of every window).
    func session(_ client: StreamClient, window: UIWindow?) {
        let kept = entries.first { $0.client === client }
        entries.removeAll { $0.client == nil || $0.client === client }
        if let window {
            entries.append(Entry(client: client, window: window, frontSince: kept?.window === window ? kept?.frontSince : nil))
        }
        update()
    }

    /// The person used a session (input to the Mac, one of the stream screen's controls). While
    /// auto-lock is held off its timer looks again when the hold would end; while it is not, now.
    func used() { if !holding { update() } }

    /// Lists the windows afresh and applies DeviceIdlePolicy.
    func update() {
        let now = ProcessInfo.processInfo.systemUptime
        entries.removeAll { $0.client == nil || $0.window == nil }
        var windows: [DeviceIdlePolicy.Window] = []
        for i in entries.indices {
            guard let client = entries[i].client, let window = entries[i].window else { continue }
            let streaming = client.connected && client.active != .none
            let front = window.windowScene?.activationState == .foregroundActive
            if !front { entries[i].frontSince = nil } else if entries[i].frontSince == nil { entries[i].frontSince = now }
            let used = DeviceIdlePolicy.lastUse(.init(input: client.lastPersonInputAt, control: client.lastActionAt,
                                                      session: client.personSessionAt, front: entries[i].frontSince))
            windows.append(DeviceIdlePolicy.Window(foregroundActive: front, streaming: streaming, lastUsedAt: used))
        }
        let ends = DeviceIdlePolicy.holdEnds(windows, now: now, limit: Self.limit)
        recheck?.invalidate()
        recheck = nil
        if let ends {
            let timer = Timer(timeInterval: max(ends - now, 0.5), repeats: false) { [weak self] _ in self?.update() }
            RunLoop.main.add(timer, forMode: .common)
            recheck = timer
        }
        let hold = ends != nil
        guard hold != holding || UIApplication.shared.isIdleTimerDisabled != hold else { return }
        holding = hold
        UIApplication.shared.isIdleTimerDisabled = hold
        #if DEBUG
        if let ends {
            print("idle: auto-lock held off while a window streams, \(Int((ends - now).rounded())) s more without use")
        } else {
            print("idle: auto-lock is the device's own again")
        }
        #endif
    }

    /// DEBUG `-SillIdleLimit <s>`: the hold's limit for one run, to see it end without waiting ten
    /// minutes; DeviceIdlePolicy.idleLimit otherwise, and always in a Release build.
    #if DEBUG
    private static let limit: Double = {
        let s = UserDefaults.standard.double(forKey: "SillIdleLimit")
        return s > 0 ? s : DeviceIdlePolicy.idleLimit
    }()
    #else
    private static let limit = DeviceIdlePolicy.idleLimit
    #endif
}

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
    /// The thumbnail whose traffic-light submenu is open (held for ThumbnailHold's length, 0.5 s unless
    /// changed in Settings; issue #113). The bars clip their content, so the submenu is drawn by this
    /// root, anchored to the thumbnail's frame.
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
    /// The picture's pinch zoom (StreamZoom, issue #65): one per stream screen, so a turn keeps it and
    /// the next session starts at 1×. Held, not watched (`@State`, as `overlay` is; a `@StateObject`
    /// would redraw this whole screen at every step of a pinch): only the picture's own view watches it
    /// (ZoomedStreamView).
    @State private var zoom = StreamZoomModel()
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
    /// The Keyboard toggle on the Duo's inner display (#215), while it shows: the clipboard's chip keeps clear.
    @State private var keyboardToggleFrame: CGRect? = nil
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
    /// Larger Picture as it was in effect when the Settings panel opened (`largerPictureNow`), which
    /// the arrangement keeps until the panel closes; nil while it is closed. The panel hangs under row
    /// 1, which the arrangement moves by the picture's growth (157 pt on an 18 Pro Max), so a change
    /// applied at once would move the panel under the finger: the switch flipped there, or what
    /// streams changing meanwhile (a window closed on the Mac, another device's pick). It applies as
    /// the panel goes, in the same motion.
    @State private var largerPictureHeld: Bool? = nil

    // Full screen (docs/full-screen-plan.md; FullScreenPolicy, FullScreen.swift): Sill's interface hidden, the
    // picture in the screen's room. Up here, as the drawer is, so a rotation and a trip to another app keep it;
    // a new session's screen (a launch, a reconnect) starts with everything shown, and nothing is stored.
    /// How much of the interface shows.
    @State private var chrome: ChromeLevel = .shown
    /// The swipe in from the left bezel while it drags: how far the interface has come in (0…1), drawn over
    /// the hidden picture (`revealPreview`); nil otherwise.
    @State private var reveal: CGFloat? = nil
    /// Whether the controls slide in and out with the left edge as they come and go; off for the moment an
    /// interactive swipe in lands, whose preview has brought them in already.
    @State private var chromeSlides = true
    /// Sill's window covers the screen (FullScreenEdges; FullScreenPolicy.offered): full screen is offered.
    @State private var coversScreen = true
    /// The window's safe area while the controls last showed (its status bar's room included): where the swipe
    /// in's preview lays them out, so they land where the shown layout puts them; nil before any was read.
    @State private var shownInsets: FullScreenPolicy.Insets? = nil
    /// The window's safe area as UIKit has it now (FullScreenEdges): full screen's room is measured by it, since
    /// this screen's reader, which ignores the safe area while hidden, then reports none (`deviceInsets`).
    @State private var windowInsets: FullScreenPolicy.Insets? = nil
    /// The harness's fake screen's safe area (ContentView's LayoutHarness, DEBUG), which stands for the window's
    /// there; nil on a device.
    @Environment(\.harnessSafeArea) private var harnessSafeArea
    /// The person's own software keyboard was up when the interface hid: it comes back with the interface.
    @State private var keyboardBeforeHide = false
    /// The hint over the hidden picture (FullScreenHint), the first few times, and its fade.
    @State private var hintShown = false
    @State private var hintFade: Task<Void, Never>? = nil
    /// How many times the hint has shown on this device (FullScreenPolicy.showsHint).
    @AppStorage(StreamScreen.fullScreenHintsKey) private var hintsShown = 0
    /// Shake to Show Controls (Settings › This iPad): on unless turned off (FullScreenPolicy.shakeShows).
    @AppStorage(FullScreenPolicy.shakeKey) private var shakeShowsControls = true
    /// This screen turned iOS's Shake to Undo off for the app (FullScreenPolicy.shakeToUndoOff), so it is the
    /// one to turn it back on.
    @State private var shakeToUndoTurnedOff = false
    static let fullScreenHintsKey = "Sill.fullScreenHints"
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
        // `-SillFullScreen 1`: the interface hidden from the start (FullScreenDebug), and `-SillFullScreenReveal
        // P` the swipe in caught at P of the way, so each can be photographed.
        let debug = FullScreenDebug.current
        _chrome = State(initialValue: debug.startHidden ? .hidden : .shown)
        _reveal = State(initialValue: debug.startHidden ? debug.reveal : nil)
        _hintShown = State(initialValue: debug.startHidden && debug.hint != .off)
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
            // Full screen (docs/full-screen-plan.md): while hidden this reader takes the whole screen (the
            // safe area ignored), and the picture goes in the room FullScreenPolicy gives (clear of the
            // sensor housing, down to the bottom edge; above the fold in the Duo's laptop pose).
            let hidden = chromeHidden
            let insets = deviceInsets(geo)
            let room = FullScreenPolicy.room(size: geo.size, insets: insets, choice: Self.roomChoice,
                                             topIsStatusBar: !DuoLayout.phoneArrangement,
                                             foldTop: posture.info(in: geo.size).horizontalBand?.minY)
            ZStack {
                Group {
                    layouts(duo, size: geo.size, posture: posture, largerKeyboard: largerKeyboard, hidden: hidden, room: room)
                }
                // Under the pairing overlay and the tour nothing takes a touch: not the bar, and
                // not the stream's UIKit input view (nor, so, the Pencil, a hover or a key).
                .allowsHitTesting(!overlayShown && tour == nil)
                // The pointer sprite follows the layout: the trackpad's arrow shows only in the
                // laptop layout, and a rotation re-renders it at once; the Mac's arrow stays. Full screen
                // has no trackpad, so none of its arrow either.
                .onChange(of: DuoLayout.of(geo.size).isPortrait && !hidden, initial: true) { _, portrait in
                    client.setPointerLayout(portrait: portrait)
                }
                // The clipboard's chip on screen or not: its 20 s run only while it is, and VoiceOver
                // is told when it first shows (ClipboardPolicy.chipCounts).
                .onChange(of: clipboardChipOnScreen, initial: true) { _, onScreen in
                    client.clipboardChipShown(onScreen)
                }
                // The swipe in from the left bezel, while it drags: the interface as it will be, coming in
                // with the finger over the hidden picture, which shows through its picture's pane.
                if hidden, let progress = reveal {
                    revealPreview(progress, size: geo.size, posture: posture, insets: insets)
                }
                // The hint, the first few times the interface hides: how to bring it back, by the left edge.
                if hidden, hintShown {
                    FullScreenHint()
                        .padding(.leading, room.minX + 18)
                        .padding(.trailing, 18)
                        .frame(width: geo.size.width, alignment: .leading)
                        .position(x: geo.size.width / 2, y: room.midY)
                        .transition(.opacity)
                }
                // The clipboard's chip (docs/clipboard-plan.md): a sibling after the layouts, so its
                // Paste button and Dismiss take their touches over the stream's UIKit input view, and
                // nothing else does (the frame around it is empty). Near the bar, off the link's line,
                // inside the stream panel's corner; never while something is open over the stream.
                if clipboardChipAllowed, client.clipboardChip || client.clipboardNote != nil, let panel = tourTargets[.stream] {
                    let corner = ClipboardPolicy.chipCorner(landscape: layout == .landscape, linkLineShown: streamLine != nil)
                    // Never over the Keyboard toggle in the pane's other bottom corner (#215).
                    let widest = corner == .bottomTrailing ? DuoPosture.clipboardChipMaxWidth(panel: panel, toggle: keyboardToggleFrame)
                                                           : max(0, panel.width - 16)
                    ClipboardChip(client: client)
                        .frame(maxWidth: widest, alignment: .trailing)
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
                    // upright stand in the picture's whole room, the black under a short picture. The
                    // words follow what this Mac and this device have now (TourFeatures).
                    let features = tourFeatures(offersLarger: offersLarger)
                    let copy = tourCopy(run, layout, keysOnItsSide: posture.onInnerDisplay,
                                        thumbnails: largerKeyboard == nil, features: features)
                    TourOverlay(run: run, copy: copy,
                                layout: layout, targets: tourTargets,
                                thumbnails: largerKeyboard == nil,
                                room: largerKeyboard.map { PhonePortraitLayout(size: geo.size, keyboard: $0).picture },
                                screen: geo.size, bottomInset: geo.safeAreaInsets.bottom,
                                next: tourNext, skip: tourSkip)
                        .transition(.opacity)
                        #if DEBUG
                        // The console's line for the photo gates: each card's rows and what they looked at.
                        .onChange(of: Self.tourRowsLine(run, copy, features), initial: true) { _, line in print(line) }
                        #endif
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
            .onPreferenceChange(KeyboardToggleFrameKey.self) { keyboardToggleFrame = $0 }
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
            // Full screen's edges on the window: the swipe in from the left edge and the pointer at the edge
            // while the interface is hidden (nothing while it shows), the shake, and whether the window covers
            // the screen.
            .background(fullScreenEdges)
            // The layouts and the overlays share this screen's space, and so its fold; the inner
            // display gives the picture the status bar's strip in every pose.
            .duoFold(posture, size: geo.size, screen: "stream screen")
            .duoStatusBar(posture, size: geo.size)
            .modifier(FullScreenSystem(hidden: hidden))
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
        // Full screen takes the whole screen; otherwise the bottom alone, under the home indicator, as before.
        .ignoresSafeArea(edges: chromeHidden ? .all : .bottom)
        .onAppear {
            // Where the software keyboard is, from now on: the laptop pose's key row follows it (#215).
            _ = KeyboardFrameMonitor.shared
            // A click, a key, a pick, a menu item or a gesture from anywhere on this screen, before it
            // goes out: the input view sends what is still composed, then forgets what was typed, which
            // dictation and an input method may revise (#138).
            let proxy = overlay
            client.onCaretMayMove = { [weak proxy] in proxy?.caretMayHaveMoved() }
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
            // Another source, whoever picked it: the whole picture again (a new frame size of the same
            // source keeps the zoom where it is on the pane).
            zoom.reset()
            if source != .none { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
            // Another source, whoever picked it: the Mac's caret is in another window (#138). A pick or a
            // launch from this device has let go of what was typed already, before it went out.
            overlay.caretMayHaveMoved()
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
        // Same wait for Aa: cycling from Off to 0.8× passes three sizes nobody wants the Mac to try.
        .onChange(of: textScale) { _, _ in sendViewport(after: 0.25) }
        // Full screen: the interface comes back by itself whenever something needs it (FullScreenPolicy.mustShow).
        // Shake to Show Controls turned on or off (Settings): Shake to Undo follows while hidden.
        .onChange(of: shakeShowsControls) { _, _ in applyShakeToUndo() }
        .onChange(of: FullScreenPolicy.mustShow(fullScreenSituation)) { _, reason in
            if let reason, chrome != .shown { showChrome(by: reason.rawValue, person: false) }
        }
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
        // The off-console view (docs/off-console-plan.md): VoiceOver hears what the picture is, once, as it comes.
        .onChange(of: client.lockView) { _, on in if on { AccessibilityNotification.Announcement(LockedMac.viewLine).post() } }
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
            // Shake to Undo back for the rest of the app, should this screen go while hidden.
            if shakeToUndoTurnedOff {
                UIApplication.shared.applicationSupportsShakeToEdit = true
                shakeToUndoTurnedOff = false
            }
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
    private var linkLineAllowed: Bool { !settingsOpen && !drawerOpen && !overlayShown && !tourOnScreen }

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

    /// The line over the stream: the off-console view's while it lasts and nothing is open over the stream
    /// (LockedMac.viewLine; docs/off-console-plan.md), else the link's.
    private var streamLine: String? {
        if client.lockView { return linkLineAllowed ? LockedMac.viewLine : nil }
        return shownLinkLine
    }
    /// The off-console view's line takes three lines at most, the link's two.
    private var streamLineLines: Int { client.lockView ? 3 : 2 }

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
                  + (textScale.map { TextScaleControl.label($0) } ?? "off") + ", \(fps) fps")
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
        // `-SillAXAction '<label>|<action>'`: half a second after the dump, that element's custom action.
        if dump > 0, let spec = defaults.string(forKey: "SillAXAction") { after(dump + 0.5) { Self.accessibilityPerform(spec) } }
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
        // `-SillZoom 'S@X,Y[; T S@X,Y …]'`: the picture's zoom for photos (StreamZoom): at T seconds (1
        // without one), one pinch step of factor S about that fraction of the picture's pane (its middle
        // without one), then the lift's settle, as two fingers would leave it: `2.5@0.3,0.4`, then
        // `3 0.1` for a pinch all the way out. In the mock too.
        for (time, factor, point) in Self.zoomSteps(defaults.string(forKey: "SillZoom") ?? "") {
            after(time) {
                var z = zoom.zoom
                let size = z.pane
                guard size.width > 0, size.height > 0 else { print("harness: -SillZoom: no picture pane yet"); return }
                let at = CGPoint(x: point.x * size.width, y: point.y * size.height)
                z.pinch(factor: factor, from: at, to: at, in: size)
                z.settle()
                zoom.set(z)
                print("harness: -SillZoom \(factor)@\(point.x),\(point.y): " + Self.zoomLine(z))
            }
        }
        // `-SillHitTest 'S x,y[; x,y …]'`: at S seconds, what UIKit's hit test finds at each point of the
        // window (its points), for the zoom's gate: a zoomed picture never under the bar's or the keys'
        // touches (StreamZoom; HEVCDisplayView takes none).
        let probe = (defaults.string(forKey: "SillHitTest") ?? "").split(separator: ";").map { $0.split(separator: " ").map(String.init) }
        if let first = probe.first, first.count == 2, let time = Double(first[0]) {
            let points = ([first[1]] + probe.dropFirst().compactMap { $0.first }).compactMap { item -> CGPoint? in
                let xy = item.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            }
            after(time) {
                guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
                for point in points {
                    let hit = window.hitTest(point, with: nil)
                    print("harness: hit test at (\(Self.points(point.x)), \(Self.points(point.y))): "
                          + (hit.map { String(describing: type(of: $0)) } ?? "nothing") + ", the zoom " + Self.zoomLine(zoom.zoom))
                }
            }
        }
        // Full screen (FullScreenDebug; docs/full-screen-plan.md): hidden or shown at these seconds, as Settings ›
        // Full Screen and the swipe in do; a swipe in played; a shake.
        let fullScreen = FullScreenDebug.current
        for time in fullScreen.toggles {
            after(time) {
                print("harness: full screen toggled at " + Self.points(CGFloat(time)) + " s (the controls were " + (chrome == .shown ? "shown" : "hidden") + ")")
                if chrome == .shown { hideChrome(by: "the harness") } else { showChrome(by: "the harness") }
            }
        }
        for time in fullScreen.swipes {
            // Its progress in five steps of 0.1, 30 ms apart, then its lift at a flick's speed.
            for step in 1...5 {
                after(time + Double(step) * 0.03) {
                    let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                    revealMoved(step == 1 ? .began : .changed, travel: width * 0.1 * CGFloat(step), speed: 0, width: width)
                }
            }
            after(time + 0.2) {
                let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                print("harness: a swipe in from the left edge played at " + Self.points(CGFloat(time)) + " s")
                revealMoved(.ended, travel: width * 0.5, speed: 600, width: width)
            }
        }
        for time in fullScreen.takeBacks {
            // In 60 % of the width in six steps 30 ms apart, then lifted moving back at 1,500 pt/s: it springs back.
            for step in 1...6 {
                after(time + Double(step) * 0.03) {
                    let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                    revealMoved(step == 1 ? .began : .changed, travel: width * 0.1 * CGFloat(step), speed: 0, width: width)
                }
            }
            after(time + 0.25) {
                let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                print("harness: a swipe in taken back at " + Self.points(CGFloat(time)) + " s")
                revealMoved(.ended, travel: width * 0.6, speed: -1500, width: width)
            }
        }
        for time in fullScreen.shakes {
            after(time) {
                print("harness: a shake at " + Self.points(CGFloat(time)) + " s")
                let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
                NotificationCenter.default.post(name: .sillDeviceShaken, object: window)
            }
        }
        if fullScreen.startHidden, fullScreen.hint == .every { showHint() }
        guard live else { return }
        client.runSoundArguments()
        // `-SillDesktopTapAt <s>[,<s>…]` (live): the Desktop button tapped at those seconds, as a finger does
        // (StreamClient.tapDesktop: with the Desktop streaming on a Mac of two stops or more, the next stop), so
        // a gate can show that full screen keeps the stop the Desktop is on (docs/full-screen-plan.md).
        for time in (defaults.string(forKey: "SillDesktopTapAt") ?? "").split(separator: ",").compactMap({ Double($0) }) {
            after(time) {
                print("harness: the Desktop button tapped at " + Self.points(CGFloat(time)) + " s (it read \"" + client.desktopButton.label + "\")")
                client.tapDesktop()
            }
        }
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
                if scale > 0 { textScale = TextScale.scale(at: scale) }     // 0.25 is Off's place: no scale
                // Aa sizes a window: over the Desktop, or nothing, its ruler does not open (TextScale.selectable).
                guard client.textScaleSelectable else {
                    print("harness: the Aa ruler stays closed: Aa is for a window, and none streams")
                    return
                }
                print("harness: the Aa ruler opened")
                scaleOpen = true
            }
        }
        // `-SillScaleScript '<s> <scale|off>[; …]'`: Aa's value set s seconds in, as the ruler's release
        // sets it, whatever streams (a synthetic host streams only the Desktop, over which Aa is dimmed):
        // the viewport it sends (the console's `viewport: …` line), and the host's `win.fitOff` for a
        // scale then Off (issue #179). A test hook: the bars never send a scale while Aa is dimmed.
        for step in (defaults.string(forKey: "SillScaleScript") ?? "").split(separator: ";") {
            let parts = step.split(separator: " ")
            let time = parts.count == 2 ? Double(parts[0]) : nil
            let off = parts.count == 2 && parts[1].lowercased() == "off"
            let scale = parts.count == 2 ? Double(parts[1]).map { TextScale.snap($0, offered: false) } : nil
            guard let time, time >= 0, off || scale != nil else {
                print("harness: -SillScaleScript: “\(step.trimmingCharacters(in: .whitespaces))” is not “<s> <scale|off>”; skipped")
                continue
            }
            after(time) {
                print("harness: Aa set to " + (off ? "Off" : TextScale.title(at: scale!)) + " at " + Self.points(CGFloat(time)) + " s")
                textScale = off ? nil : scale
            }
        }
    }
    private static var launchArgumentsRan = false

    /// `-SillZoom`'s steps: (seconds, factor, the fraction of the pane); none for what does not read.
    static func zoomSteps(_ text: String) -> [(Double, CGFloat, CGPoint)] {
        text.split(separator: ";").compactMap { item in
            let words = item.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count == 1 || words.count == 2 else { return nil }
            let time = words.count == 2 ? Double(words[0]) : 1
            let parts = words[words.count - 1].split(separator: "@")
            guard let time, time >= 0, let factor = Double(parts[0]), factor > 0, parts.count <= 2 else { return nil }
            let xy = parts.count == 2 ? parts[1].split(separator: ",").compactMap { Double($0) } : [0.5, 0.5]
            guard xy.count == 2 else { return nil }
            return (time, CGFloat(factor), CGPoint(x: xy[0], y: xy[1]))
        }
    }

    /// "2.50×, offset (125.0, 60.0) in a 1000×650 pt pane", for the console.
    static func zoomLine(_ z: StreamZoom) -> String {
        String(format: "%.2f×, offset (%.1f, %.1f) in a %@×%@ pt pane", z.scale, z.offset.width, z.offset.height,
               points(z.pane.width), points(z.pane.height))
    }

    /// `-SillAXDump`: walks the key window as an assistive technology does (an element, else its
    /// `accessibilityElements`, else its element count, else its subviews) and prints one line per
    /// element: "ax: 1 Apps (14,454 76×50)".
    static func accessibilityDump() {
        guard let elements = accessibilityElementsInOrder() else { print("ax: no key window"); return }
        for (i, element) in elements.enumerated() {
            let f = element.accessibilityFrame
            let label = element.accessibilityLabel ?? element.accessibilityValue ?? "(no label)"
            // What VoiceOver says after the name: the value, the hint, dimmed and adjustable (Aa's
            // Off and its dimmed state over the Desktop, issue #179); and its actions (the version's Copy).
            var said: [String] = []
            if element.accessibilityLabel != nil, let value = element.accessibilityValue, !value.isEmpty { said.append("value “\(value)”") }
            if let hint = element.accessibilityHint, !hint.isEmpty { said.append("hint “\(hint)”") }
            if element.accessibilityTraits.contains(.notEnabled) { said.append("dimmed") }
            if element.accessibilityTraits.contains(.adjustable) { said.append("adjustable") }
            if let actions = element.accessibilityCustomActions, !actions.isEmpty {
                said.append("actions " + actions.map { "“\($0.name)”" }.joined(separator: ", "))
            }
            print("ax: \(i + 1) \(label) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))"
                  + (said.isEmpty ? "" : ": " + said.joined(separator: ", ")))
        }
    }

    /// The key window's accessibility elements in the order the tree hands them out.
    private static func accessibilityElementsInOrder() -> [NSObject]? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        var elements: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: Any, _ depth: Int) {
            guard depth < 60, seen.count < 5000, let element = object as? NSObject, !element.accessibilityElementsHidden,
                  seen.insert(ObjectIdentifier(element)).inserted else { return }
            if element.isAccessibilityElement { elements.append(element); return }
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
        return elements
    }

    /// `-SillAXAction '<label>|<action>'`: performs the custom action of that name on the first element
    /// whose label begins with that label, as VoiceOver's actions rotor does, and says what the
    /// clipboard holds after it (the version's Copy: docs/version-label-plan.md).
    static func accessibilityPerform(_ spec: String) {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { print("ax: -SillAXAction wants '<label>|<action>'"); return }
        guard let element = accessibilityElementsInOrder()?.first(where: { ($0.accessibilityLabel ?? "").hasPrefix(parts[0]) }) else {
            print("ax: no element whose label begins “\(parts[0])”"); return
        }
        guard let action = element.accessibilityCustomActions?.first(where: { $0.name == parts[1] }) else {
            print("ax: “\(element.accessibilityLabel ?? "")” has no action “\(parts[1])”"); return
        }
        let done: Bool
        if let handler = action.actionHandler { done = handler(action) }
        else if let target = action.target as? NSObject { _ = target.perform(action.selector, with: action); done = true }
        else { done = false }
        print("ax: performed “\(action.name)” on “\(element.accessibilityLabel ?? "")”: \(done); the clipboard holds "
              + (UIPasteboard.general.string.map { "“\($0)”" } ?? "no text"))
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
        if drawerOpen { takers.insert(.drawer) }
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
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
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
            withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
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
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
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

    // MARK: Full screen

    /// The interface is hidden (docs/full-screen-plan.md): the picture alone, in the screen's room.
    private var chromeHidden: Bool { chrome == .hidden }

    /// Full screen's edges on the window: the swipe in from the left edge and the pointer at the edge while the
    /// interface is hidden (while it shows nothing of full screen's listens), the shake, whether the window
    /// covers the screen, and its safe area.
    private var fullScreenEdges: FullScreenEdges {
        FullScreenEdges(
            hidden: chrome != .shown,
            onReveal: { state, travel, speed, width in revealMoved(state, travel: travel, speed: speed, width: width) },
            onDwell: { showChrome(by: "the pointer at the left edge") },
            onShake: {
                if FullScreenPolicy.shakeShows(chrome, switchOn: shakeShowsControls) {
                    showChrome(by: "a shake")
                } else if chrome != .shown {
                    #if DEBUG
                    print("full screen: a shake, and Shake to Show Controls is off: the controls stay hidden")
                    #endif
                }
            },
            onCoverage: { coversScreen = $0 },
            onInsets: { e in
                let now = FullScreenPolicy.Insets(top: e.top, left: e.left, bottom: e.bottom, right: e.right)
                windowInsets = now
                if chrome == .shown { shownInsets = now }
            })
    }

    /// What FullScreenPolicy weighs: whether a hide may start, and the interface must come back by itself (the
    /// tour, a pairing, the link's line, the Mac's cover or off-console view, nothing streaming, the window no
    /// longer filling the screen).
    private var fullScreenSituation: FullScreenPolicy.Situation {
        FullScreenPolicy.Situation(coversScreen: coversScreen,
                                   streaming: client.active != .none,
                                   somethingOpen: settingsOpen || drawerOpen || menusOpen || windowMenu != nil || scaleOpen,
                                   tour: tour != nil,
                                   pairing: overlayShown,
                                   linkLine: linkReportLine != nil,
                                   lockCover: client.lockShade != nil,
                                   offConsoleView: client.lockView)
    }

    /// Settings › Full Screen's row: dimmed while a hide could not start (nothing streams, the window does
    /// not fill the screen, something that would bring the controls straight back); the panel itself is
    /// not counted, as the row closes it first.
    private var fullScreenRow: HostSettingsPanel.FullScreenRow {
        var s = fullScreenSituation
        s.somethingOpen = false
        return HostSettingsPanel.FullScreenRow(offered: FullScreenPolicy.hideAllowed(s), coversScreen: coversScreen,
                                               hide: hideFromSettings)
    }

    /// The safe area as FullScreenPolicy takes it.
    private static func insets(_ e: EdgeInsets) -> FullScreenPolicy.Insets {
        FullScreenPolicy.Insets(top: e.top, left: e.leading, bottom: e.bottom, right: e.trailing)
    }

    /// The screen's safe area as full screen measures its room and the swipe in's preview by (the sensor
    /// housing's side, the status bar's room, the home indicator's): the window's, as UIKit gives it, or in the
    /// harness its fake screen's. Not this screen's reader's: a GeometryReader that ignores the safe area, as
    /// this one does while hidden, reports none (the live gate measured the hidden room at 393×852 on a
    /// 393×852 screen with a 59 pt Dynamic Island), so the picture would have gone under the island. The
    /// reader's own only before the window has said.
    private func deviceInsets(_ geo: GeometryProxy) -> FullScreenPolicy.Insets {
        if let harnessSafeArea { return Self.insets(harnessSafeArea) }
        return windowInsets ?? Self.insets(geo.safeAreaInsets)
    }

    /// Where the hidden picture goes: clear of the sensor housing, down to the bottom edge (open question 5;
    /// DEBUG `-SillFullScreenRoom` photographs the others).
    private static var roomChoice: FullScreenPolicy.Room {
        #if DEBUG
        return FullScreenDebug.current.room ?? .clearOfHousing
        #else
        return .clearOfHousing
        #endif
    }

    /// The motion of the controls going and coming: they slide with the left edge, the picture's pane grows
    /// and shrinks; a fade under Reduce Motion.
    private var chromeMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.34, bounce: 0.06)
    }

    /// The controls' own transition as they go and come: out by the left edge and back from it, but not while
    /// an interactive swipe in lands (its preview brought them in already).
    private var chromeTransition: AnyTransition {
        guard chromeSlides else { return .identity }
        return reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

    /// Hides the interface: Settings › Full Screen, or the harness. Only while a hide
    /// may start (FullScreenPolicy.hideAllowed). The person's own software keyboard goes with it (a hardware
    /// keyboard's hold stays, and keeps typing to the Mac: HardwareKeyboardPolicy.toggled), and comes back with
    /// the interface. The hint the first few times; VoiceOver hears where the controls went every time.
    private func hideChrome(by how: String, keyboardWasUp: Bool? = nil) {
        guard chrome == .shown else { return }
        guard FullScreenPolicy.hideAllowed(fullScreenSituation) else {
            #if DEBUG
            print("full screen: \(how): not now (" + (FullScreenPolicy.mustShow(fullScreenSituation)?.rawValue ?? "something is open") + ")")
            #endif
            return
        }
        keyboardBeforeHide = keyboardWasUp ?? keyboardShown
        if keyboardShown { overlay.toggleKeyboard() }
        chromeSlides = true
        reveal = nil
        withAnimation(chromeMotion) { chrome = chrome.afterHide }
        applyShakeToUndo()
        client.noteAction()
        if FullScreenPolicy.showsHint(shownBefore: hintsShown, forced: hintForced) {
            hintsShown += 1
            showHint()
        }
        // The screen is new to VoiceOver (the picture alone): it reads it afresh, and says where the controls went.
        UIAccessibility.post(notification: .screenChanged, argument: FullScreenPolicy.Copy.announcement)
        #if DEBUG
        print("full screen: hidden by \(how)" + (keyboardBeforeHide ? "; the keyboard comes back with the controls" : ""))
        #endif
    }

    /// Brings the interface back: the swipe in, a shake, an assistive technology, the pointer at the edge, the
    /// harness, or by itself (`person` false: FullScreenPolicy.mustShow).
    private func showChrome(by why: String, person: Bool = true) {
        guard chrome != .shown else { return }
        hintFade?.cancel()
        hintFade = nil
        withAnimation(chromeMotion) {
            chrome = chrome.afterReveal
            reveal = nil
            hintShown = false
        }
        applyShakeToUndo()
        if keyboardBeforeHide { overlay.setKeyboard(shown: true) }
        keyboardBeforeHide = false
        if person { client.noteAction() }
        if voiceOverEnabled { UIAccessibility.post(notification: .screenChanged, argument: FullScreenPolicy.Copy.shownAnnouncement) }
        #if DEBUG
        print("full screen: shown by \(why)")
        #endif
    }

    /// iOS's Shake to Undo for the app: off only while the interface is hidden and a shake is Sill's
    /// (FullScreenPolicy.shakeToUndoOff), so a shake never brings an Undo alert then; otherwise as it was.
    private func applyShakeToUndo() {
        let off = FullScreenPolicy.shakeToUndoOff(chrome, switchOn: shakeShowsControls)
        guard off != shakeToUndoTurnedOff else { return }
        UIApplication.shared.applicationSupportsShakeToEdit = !off
        shakeToUndoTurnedOff = off
    }

    /// Settings › Full Screen: the panel closes (the keyboard it took down stays down, and comes back with the
    /// controls if it was up before the panel), then the interface hides.
    private func hideFromSettings() {
        let keyboard = keyboardBeforeSettings
        setSettings(false, restoreKeyboard: false)
        let mark = client.connectedAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))       // the panel's close
            guard sameSession(mark) else { return }
            hideChrome(by: "Settings › Full Screen", keyboardWasUp: keyboard)
        }
    }

    /// The hint: on, then faded after `hintSeconds` (DEBUG `-SillFullScreenHint hold` keeps it).
    private func showHint() {
        hintFade?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { hintShown = true }
        #if DEBUG
        if FullScreenDebug.current.hint == .hold { return }
        #endif
        hintFade = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FullScreenPolicy.hintSeconds))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.35)) { hintShown = false } }
        }
    }

    /// DEBUG `-SillFullScreenHint 1`: the hint every time.
    private var hintForced: Bool {
        #if DEBUG
        return FullScreenDebug.current.hint != .off
        #else
        return false
        #endif
    }

    /// The swipe in from the left bezel (RevealEdgePan): the preview follows the finger, and at the lift it
    /// finishes or springs back (EdgeReveal).
    private func revealMoved(_ state: UIGestureRecognizer.State, travel: CGFloat, speed: CGFloat, width: CGFloat) {
        guard chrome != .shown else { return }
        switch state {
        case .began, .changed:
            reveal = CGFloat(EdgeReveal.progress(translation: Double(travel), width: Double(width)))
        case .ended:
            let finishes = EdgeReveal.finishes(translation: Double(travel), velocity: Double(speed), width: Double(width))
            #if DEBUG
            print(String(format: "reveal: lifted after %.0f pt at %.0f pt/s on a screen %.0f pt wide: %@ (it finishes past %.0f pt)",
                         Double(travel), Double(speed), Double(width), finishes ? "comes in" : "springs back",
                         EdgeReveal.distance(width: Double(width))))
            #endif
            if finishes { landReveal() } else { springBack() }
        default:
            #if DEBUG
            print(String(format: "reveal: cancelled after %.0f pt", Double(travel)))
            #endif
            springBack()
        }
    }

    /// The swipe in finished: the preview the rest of the way in, then the controls in its place with no slide
    /// of their own, and the picture into its pane.
    private func landReveal() {
        withAnimation(.easeOut(duration: 0.14 * revealSlow)) { reveal = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.14 * revealSlow))
            guard chrome != .shown, reveal != nil else { return }
            chromeSlides = false
            showChrome(by: "the swipe in from the left edge")
            try? await Task.sleep(for: .seconds(0.4))
            chromeSlides = true
        }
    }

    /// The swipe in's own animations at their speed (1), or slower for photos mid-way (DEBUG `-SillRevealSlow`).
    private var revealSlow: Double {
        #if DEBUG
        return FullScreenDebug.current.slow
        #else
        return 1
        #endif
    }

    /// The swipe in sprang back: the preview out by the left edge, then gone.
    private func springBack() {
        withAnimation(.easeOut(duration: 0.2 * revealSlow)) { reveal = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.22 * revealSlow))
            if chrome != .shown, reveal == 0 { reveal = nil }
        }
    }

    /// The layout for a screen of `size`: the real one, or (`preview`) the swipe in's picture of it.
    @ViewBuilder
    private func layouts(_ duo: DuoLayout, size: CGSize, posture: DuoPosture, largerKeyboard: CGFloat?, hidden: Bool,
                         room: CGRect, preview: Bool = false) -> some View {
        switch duo {
        case .innerLandscape:
            landscape(bar: .regular, width: size.width, fold: posture.info(in: size), screen: size, hidden: hidden,
                      room: room, preview: preview)
        case .outerLandscape:
            landscape(bar: .compact, width: size.width, fold: posture.info(in: size), screen: size, hidden: hidden,
                      room: room, preview: preview)
        case .innerPortrait:
            portrait(metrics: .regular, hidden: hidden, room: room, preview: preview)
        case .outerPortrait:
            portrait(metrics: DuoLayout.phoneArrangement ? .phone : .compact, largerKeyboard: largerKeyboard,
                     hidden: hidden, room: room, preview: preview)
        }
    }

    /// The swipe in's preview: the interface as it will show, laid out where it will be (the safe area, down to
    /// the bottom edge, as the stream screen is while shown), `progress` of the way in from the left edge, over
    /// the hidden picture. Each layout's preview draws its controls with the background they sit on and nothing
    /// of the picture's place (RevealCut): no pane, panel, rim, margin or black there, by construction, and no
    /// mask or measurement that could arrive a frame late, so the hidden picture is all there is around the
    /// controls until they land. It takes no touch, says nothing to VoiceOver and reports no tour target.
    private func revealPreview(_ progress: CGFloat, size: CGSize, posture: DuoPosture, insets now: FullScreenPolicy.Insets) -> some View {
        // Where the shown layout will be: the safe area now, down to the bottom edge; on an iPad with the status
        // bar's room it had while shown (hidden now, the status bar comes back as the controls land). An iPhone's
        // top inset is its sensor housing's, the same either way, and a turn while hidden changes it.
        let pad = !DuoLayout.phoneArrangement      // an iPad's idiom (DEBUG `-SillIdiom` changes it, as for the layouts)
        let insets = FullScreenPolicy.Insets(top: pad ? (shownInsets?.top ?? now.top) : now.top, left: now.left,
                                             bottom: now.bottom, right: now.right)
        let shown = CGRect(x: insets.left, y: insets.top, width: max(0, size.width - insets.left - insets.right),
                           height: max(0, size.height - insets.top))
        let duo = DuoLayout.of(shown.size)
        let keyboard = DuoLayout.drawsPhone(shown.size)
            ? PhonePortraitLayout.keyboard(for: shown.size, largerPicture: largerPictureNow, foldable: posture.hinge != .unknown) : nil
        return layouts(duo, size: shown.size, posture: posture, largerKeyboard: keyboard, hidden: false, room: .zero, preview: true)
            .frame(width: shown.width, height: shown.height)
            .transformPreference(TourTargetsKey.self) { $0 = [:] }
            .transformPreference(KeyboardToggleFrameKey.self) { $0 = nil }
            .offset(x: shown.minX - (1 - progress) * size.width, y: shown.minY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.identity)
    }

    // MARK: The tour

    /// The picture, as the tour counts it: the Mac's first window list, a frame size and a source
    /// that streams. A Mac that refuses this device, or cannot capture, never gets here.
    private var pictureReady: Bool {
        // Not in the off-console view: nothing the tour teaches reaches the Mac then (docs/off-console-plan.md).
        !client.macName.isEmpty && client.videoSize != .zero && client.active != .none && !client.lockView
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
        if settingsOpen { return "Settings was open" }
        if windowMenu != nil { return "a window's lights were open" }
        if scaleOpen { return "the Aa ruler was open" }
        // The person's own keyboard: a hardware keyboard's hold is not theirs, so a person with a
        // keyboard attached still gets the tour (HardwareKeyboardPolicy).
        if keyboardShown { return "the keyboard was up" }
        if overlayShown { return "the pairing overlay was open" }
        // Full screen: the tour points at the controls, which the person has just put away.
        if chrome != .shown { return "the controls were hidden" }
        // UIKit's word, not the scene phase: in a headless simulator the environment's scenePhase
        // stays inactive for an app that is active and on screen.
        if UIApplication.shared.applicationState != .active { return "the app was not active" }
        return nil
    }

    /// `keysOnItsSide`: the iPhone Duo open, whose keys and trackpad come with the device on its side.
    /// `thumbnails`: false for a phone with Larger Picture. `features`: `tourFeatures`.
    private func tourCopy(_ run: TourRun, _ layout: TourLayout, keysOnItsSide: Bool = false, thumbnails: Bool = true,
                          features: TourFeatures) -> TourCopy {
        TourPolicy.copy(run.at, layout, mac: client.macName, device: StreamClient.deviceWord,
                        voiceOver: tourVoiceOver, firstOfRun: run.firstOfRun, keysOnItsSide: keysOnItsSide,
                        thumbnails: thumbnails, features: features)
    }

    /// What the tour's words depend on now (TourFeatures): the Menus button on screen (its target
    /// reported), this device's Three-Finger Gestures with a Mac that takes them, the Mac's Virtual
    /// Display setting as the Settings panel shows it, the clipboard the Mac's window list shares, this
    /// device's Paste on ‹Mac› Right Away, a Mac with sound (Send Audio, on or off), and
    /// `offersLarger`, the Settings panel's Larger Picture switch offered here (`body`). The window
    /// list comes before the picture and kind 16 right after it, so a card sees them; a late change
    /// redraws its rows.
    private func tourFeatures(offersLarger: Bool) -> TourFeatures {
        TourFeatures(menus: tourTargets[.menus] != nil,
                     gestures: StreamClient.gesturesOn && (client.hostGestures ?? 0) >= TrackpadGesture.generation,
                     virtualDisplay: client.settings.displayed?.virtualDisplay == true,
                     clipboard: ClipboardPolicy.hostTakes(client.hostClipboard),
                     pasteRightAway: StreamClient.pasteRightAwayOn,
                     sound: client.macHasSound,
                     largerPicture: offersLarger)
    }

    #if DEBUG
    /// "tour: card bar (Windows and Menus): 5 rows, 2 New; Menus button, gestures, no Virtual Display,
    /// clipboard, paste right away, sound, no Larger Picture".
    static func tourRowsLine(_ run: TourRun, _ copy: TourCopy, _ f: TourFeatures) -> String {
        func has(_ on: Bool, _ name: String) -> String { on ? name : "no " + name }
        let what = [has(f.menus, "Menus button"), has(f.gestures, "gestures"), has(f.virtualDisplay, "Virtual Display"),
                    has(f.clipboard, "clipboard"), has(f.pasteRightAway, "paste right away"), has(f.sound, "sound"),
                    has(f.largerPicture, "Larger Picture")]
        return "tour: card \(run.at.rawValue) (\(copy.title)): \(copy.rows.count) rows, \(copy.rows.filter(\.isNew).count) New; "
            + what.joined(separator: ", ")
    }
    #endif

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

    /// `hidden`: full screen (docs/full-screen-plan.md): no bar, and the stream panel at `room` with no
    /// margin, corner or rim, its letterbox black; the panel is the same view either way (its input view stays
    /// first responder, a composition and a coast go on), so its frame animates. `screen`: this layout's size.
    /// `preview`: the swipe in's picture of the shown layout: the bar alone, which carries its own background;
    /// nothing under it, the picture's place (RevealCut.landscape), is drawn.
    private func landscape(bar plain: BarMetrics, width: CGFloat, fold: FoldInfo, screen: CGSize, hidden: Bool = false,
                           room: CGRect = .zero, preview: Bool = false) -> some View {
        // The book pose (docs/iphone-duo-plan.md, (a)): nothing on the fold's band; elsewhere as before.
        let (bar, stripWidth) = plain.clearing(fold, width: width)
        return VStack(spacing: 0) {
            if !hidden {
                TopBar(client: client, metrics: bar, stripWidth: stripWidth, drawerOpen: $drawerOpen,
                       keyboardShown: $keyboardShown,
                       textScale: $textScale, scaleOpen: $scaleOpen, windowMenu: $windowMenu,
                       settingsOpen: settingsOpen,
                       // Apps, Menus, Aa, Keyboard, Desktop, Settings, and the strip. The Mac's sound has no
                       // button: Send Audio and Mute are the Settings panel's switches (Noah, 2026-10-27).
                       menusFit: MacMenuButton.fits(width: width - 2 * bar.padding, buttons: 6, buttonWidth: bar.buttonWidth,
                                                    gap: bar.gap, thumbWidth: bar.thumbWidth),
                       toggleKeyboard: { overlay.toggleKeyboard() },
                       setSettings: { setSettings($0, restoreKeyboard: $1) },
                       menusOpened: menusOpened, menusClosed: menusClosed)
                    .transition(chromeTransition)
            }
            contentArea(bar: bar, screen: screen, hidden: hidden, room: room, preview: preview)
        }
    }

    /// `largerKeyboard`: Larger Picture's keyboard on a phone (see `body`), nil otherwise. `hidden`, `room`,
    /// `preview`: full screen's, as `landscape`'s.
    private func portrait(metrics: PortraitMetrics, largerKeyboard: CGFloat? = nil, hidden: Bool = false,
                          room: CGRect = .zero, preview: Bool = false) -> some View {
        PortraitStreamScreen(client: client, metrics: metrics, drawerOpen: $drawerOpen,
                             keyboardShown: $keyboardShown,
                             textScale: $textScale, scaleOpen: $scaleOpen, windowMenu: $windowMenu,
                             latched: $latched, overlay: overlay,
                             settingsOpen: settingsOpen,
                             setSettings: { setSettings($0, restoreKeyboard: $1) },
                             menusOpened: menusOpened, menusClosed: menusClosed,
                             settingsTransition: { settingsTransition(anchor: $0) },
                             onPanelSize: { if !preview { panelSize = $0 } },
                             pairThisDevice: openPairingOverlay,
                             linkLine: streamLine,
                             linkLineLines: streamLineLines,
                             takeTour: takeTour,
                             largerKeyboard: largerKeyboard,
                             zoom: zoom,
                             hidden: hidden, room: room, preview: preview,
                             chromeTransition: chromeTransition,
                             fullScreen: fullScreenRow,
                             showChrome: { showChrome(by: "an assistive technology") })
    }

    /// The stream panel's shape: rounded inside its margin, square while full screen.
    private func streamShape(_ hidden: Bool) -> RoundedRectangle { RoundedRectangle(cornerRadius: hidden ? 0 : 12, style: .continuous) }

    /// Under the bar: the stream panel, the drawer and the Settings panel. In the swipe in's preview, nothing at
    /// all: it is the picture's place (RevealCut.landscape), so no pane, rim, margin or black can come in with
    /// the bar, by construction (Noah, 2026-11-12: "no bezel gets rendered above or below the controls until
    /// they are fully summoned").
    @ViewBuilder
    private func contentArea(bar: BarMetrics, screen: CGSize, hidden: Bool, room: CGRect, preview: Bool) -> some View {
        if preview {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            liveContentArea(bar: bar, screen: screen, hidden: hidden, room: room)
        }
    }

    private func liveContentArea(bar: BarMetrics, screen: CGSize, hidden: Bool, room: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black

            ZStack {
                // Scaled and moved by the picture's zoom, inside the clip below.
                ZoomedStreamView(client: client, zoom: zoom)
                // Same frame as the video, so a touch maps straight onto the streamed frame (through the
                // zoom, StreamZoom.unzoomedPoint).
                InputOverlay(videoSize: client.videoSize,
                             send: { client.sendInput($0) },
                             setOwnPointer: { client.setOwnPointer($0, from: $1) },
                             proxy: overlay,
                             isKeyboardShown: $keyboardShown,
                             latchedModifiers: latched,
                             onModifiersConsumed: { latched = [] },
                             sendGesture: { client.sendGesture($0, fingers: $1) },
                             macRepeatsKeys: { KeyTyping.macRepeats(keyRepeat: client.hostKeyRepeat) },
                             readZoom: { [zoom] in zoom.zoom },
                             writeZoom: { [zoom] in zoom.set($0) })
            }
            // Full screen's letterbox is black, as a film's; the panel's own grey otherwise.
            .background(hidden ? Color.black : Palette.panel)
            // A locked Mac: its cover over the picture (LockedMac), under the link's line.
            .overlay { LockedMacShade(client: client) }
            .overlay(alignment: .top) { LinkLineView(text: streamLine, lines: streamLineLines) }
            // Full screen: the picture as one element for VoiceOver, Switch Control and Voice Control.
            .overlay { HiddenPictureElement(hidden: hidden, mac: client.macName.isEmpty ? "The Mac" : client.macName,
                                            show: { showChrome(by: "an assistive technology") }) }
            .clipShape(streamShape(hidden))
            .overlay(streamShape(hidden).strokeBorder(Color.white.opacity(hidden ? 0 : 0.09), lineWidth: 1))
            // The panel itself, inside the padding: the size the host fits the Mac window to.
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { panelSize = $0 })
            .tourTarget(.stream)
            // 8 pt all round; full screen, the room (the panel's frame is the room, in this area's space).
            .padding(hidden ? EdgeInsets(top: room.minY, leading: room.minX, bottom: max(0, screen.height - room.maxY),
                                         trailing: max(0, screen.width - room.maxX))
                            : EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

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
                                  takeTour: takeTour, fullScreen: fullScreenRow)
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
    /// Two lines for the link's words; the off-console view's take three (docs/off-console-plan.md).
    var lines = 2
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
                    .lineLimit(lines)
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

// MARK: - A locked Mac's cover

/// What covers the stream while the Mac shows nothing of itself (`StreamClient.lockShade`, LockedMac,
/// docs/locked-mac-plan.md): an opaque panel with why, then after the unlock "Unlocking…" until its
/// picture's first keyframe. The picture under it was removed at the lock (HEVCDisplayView.blank), and the
/// Mac streams a black placeholder meanwhile. It takes no touch: a paired device's keys and taps still
/// reach a locked screen, where the Mac takes them; off console the Mac drops them. VoiceOver reads it as
/// one element.
struct LockedMacShade: View {
    @ObservedObject var client: StreamClient

    var body: some View {
        ZStack {
            if let shade = client.lockShade {
                Palette.panel
                VStack(spacing: 10) {
                    if shade == .unlocking {
                        ProgressView().tint(Palette.muted)
                    } else {
                        Image(systemName: shade == .locked(.otherUser) ? "person.2.fill" : "lock.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.muted)
                            .accessibilityHidden(true)
                    }
                    Text(LockedMac.title(mac: client.macName, shade: shade))
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                    if let detail = LockedMac.detail(shade: shade, paired: client.settings.host?.sessionPaired) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: 440)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: client.lockShade)
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
                             pointsPerStep: metrics.buttonHeight >= 60 ? 44 : 40,
                             offered: client.textScaleOffersOff, available: client.textScaleSelectable,
                             unavailableHint: client.textScaleUnavailableHint)
                .tourTarget(.textSize)

            button(open: keyboardShown, symbol: "keyboard", label: "Keyboard",
                   accessibilityLabel: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                   action: { setSettings(false, false); toggleKeyboard() })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
                .tourTarget(.keyboard)

            // The Desktop on the Mac's stop it shows, and with two stops or more the next at a tap
            // (DesktopDisplays): "Desktop 2", a dot per stop while the Desktop streams.
            let desktop = client.desktopButton
            button(open: client.active == .desktop, symbol: "desktopcomputer", label: desktop.label,
                   accessibilityLabel: desktop.accessibilityLabel,
                   action: { client.tapDesktop() })
                .desktopStops(desktop, inset: metrics.buttonHeight >= 60 ? 5 : 3.5)
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

extension View {
    /// The Desktop button beyond its label and symbol (DesktopDisplays.button), on a Mac with two stops or
    /// more: VoiceOver's value ("Display 2 of 3, DELL U2723QE") and hint ("Shows the next display." while
    /// a tap steps), and the stops' dots, the shown one filled ("3/7" from seven), over the button's bottom
    /// margin `inset` from its edge while the Desktop streams, so no bar's layout moves for them. Nothing
    /// with one stop or a Mac from before this, as before.
    func desktopStops(_ face: DesktopDisplays.Button, inset: CGFloat, dot: CGFloat = 4) -> some View {
        accessibilityValue(face.accessibilityValue ?? "")
            .accessibilityHint(face.accessibilityHint ?? "")
            .overlay(alignment: .bottom) { DesktopStopDots(face: face, dot: dot).padding(.bottom, inset) }
    }
}

/// The Desktop button's place among the Mac's stops while the Desktop streams (DesktopDisplays): one dot per
/// stop, the shown one filled, as a page control shows a page; "3/7" in place of seven dots or more. The
/// button reads it whole; VoiceOver hears its value instead.
struct DesktopStopDots: View {
    let face: DesktopDisplays.Button
    var dot: CGFloat = 4

    var body: some View {
        Group {
            if let counter = face.counter {
                // As tall as the dots it stands for, so its digits sit where they would and never reach the
                // label above (an 8 pt line of its own overlapped "Desktop 3" in a 58 pt window bar).
                Text(counter)
                    .font(.system(size: dot + 3, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .frame(height: dot)
            } else if face.dots > 0 {
                HStack(spacing: dot * 0.75) {
                    ForEach(1...face.dots, id: \.self) { i in
                        Circle()
                            .fill(Palette.accent.opacity(i == face.lit ? 1 : 0.32))
                            .frame(width: dot, height: dot)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Text size control

/// The Aa control: a bar button that opens into a ruler while the finger is down, the way the
/// camera's zoom button opens into its dial and the Dynamic Island timer scrubs. The thumb stays
/// put at the button's centre and the ruler slides under it: six detents, Off and then 0.5× to 1.5×
/// in 0.25 steps, a tick of haptic at each. The bar fades the buttons next to it while `open` and
/// brings them back on release, when the chosen value is applied once (every change restarts the
/// stream, so nothing is sent mid-drag). A nil scale means the Mac window is not fitted: the leftmost
/// detent, Off, one step below 0.5× (`TextScale`; issue #179). Off is not offered while the virtual
/// display is on, where a nil scale is 1× (`offered`). Only a window is sized by it: while anything
/// else streams it is dimmed, its ruler never opens and VoiceOver hears why (`available`,
/// `TextScale.selectable`; Noah, 2026-10-29).
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
    /// Whether the ruler has an Off detent (`TextScale.detents`, `TextScale.offersOff`).
    var offered = true
    /// Whether Aa can be used now (`TextScale.selectable`: only while a window streams). Otherwise
    /// dimmed, no ruler, a VoiceOver swipe changes nothing, and VoiceOver hears
    /// `TextScale.unavailableHint`; its value stays, for the next window.
    var available = true
    /// What VoiceOver hears while Aa cannot be used (the off-console view's own, else `TextScale.unavailableHint`).
    var unavailableHint = TextScale.unavailableHint

    var steps: [Double] { TextScale.detents(offered: offered) }
    /// Padding either side of the visible ruler; two detents show each side of the thumb.
    static let sliderInset: CGFloat = 30
    /// The ruler's frame shows two detents either side of the thumb, whatever the detents: Off's
    /// sixth slides in as the finger nears it. So every bar's ruler keeps the width it had with five,
    /// and a phone's row 1 the room it was laid out for (PhonePortraitLayout's `rulerSpans`).
    static let detentsEachSide = 2
    var sliderWidth: CGFloat { pointsPerStep * CGFloat(2 * Self.detentsEachSide) + Self.sliderInset * 2 }
    /// How much of itself a dimmed Aa shows.
    static let unavailableOpacity = 0.35

    @State private var live: Double = 1.0
    @State private var startValue: Double = 1.0
    /// Where the ruler has the scale now.
    private var position: Double { TextScale.position(of: scale, offered: offered) }
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
            Text(TextScale.title(at: position))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.barLabel)
        }
        .opacity(available ? 1 : Self.unavailableOpacity)     // dimmed: Aa sizes a window, and none streams
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
        // A ruler asked open while Aa cannot be used (the harness's `-SillScaleOpen` over the Desktop)
        // folds at once; one open when the window stops streaming (closed on the Mac, the Desktop
        // picked from another device) folds without applying (`onChange(of: available)`, and `onEnded`
        // applies nothing while Aa cannot be used).
        .onChange(of: open, initial: true) { _, isOpen in
            guard isOpen else { return }
            if available { live = position } else { open = false }
        }
        .onChange(of: available) { _, now in if !now, open { withAnimation(.easeOut(duration: 0.2)) { open = false } } }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    if !open {
                        startValue = position
                        live = startValue
                        startX = g.location.x
                        withAnimation(.spring(duration: 0.22, bounce: 0.15)) { open = true }
                    }
                    // The ruler follows the finger: dragging right raises the value, and the ticks
                    // slide left under the fixed thumb.
                    let dx = g.location.x - startX
                    let snapped = TextScale.snap(startValue + Double(dx / pointsPerStep) * 0.25, offered: offered)
                    if snapped != live {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.1)) { live = snapped }
                    }
                }
                .onEnded { _ in
                    // A plain tap on an untouched control changes nothing, and nor does a drag the
                    // stream left a window during.
                    if available, position != live { scale = TextScale.scale(at: live) }
                    withAnimation(.easeOut(duration: 0.2)) { open = false }
                },
            including: available ? .all : .none      // dimmed: a touch opens nothing
        )
        .onDisappear { open = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text size")
        .accessibilityValue(TextScale.spoken(at: position))
        .accessibilityHint(available ? "" : unavailableHint)
        // Always adjustable, so Aa stays one view and one accessibility element when a window starts or
        // stops streaming: VoiceOver keeps its place on it, and the ruler's fold above runs. Dimmed, it
        // is what a disabled slider is ("dimmed, adjustable"): a swipe changes nothing. (Adding the
        // action only while Aa can be used made a new view and element at every change: the review of
        // #181.)
        .accessibilityAdjustableAction { direction in
            guard available else { return }
            switch direction {
            case .increment: scale = TextScale.scale(at: TextScale.step(from: position, up: true, offered: offered))
            case .decrement: scale = TextScale.scale(at: TextScale.step(from: position, up: false, offered: offered))
            @unknown default: break
            }
        }
        .disabled(!available)     // VoiceOver: "dimmed"
    }

    /// The ruler: a track with a tick and a label at each detent that slides so the live value sits
    /// under the fixed thumb; the ends fade out where they run past the frame (two detents each side).
    private var slider: some View {
        let w = sliderWidth
        let step = pointsPerStep
        let midX = w / 2
        let midY = height / 2 + 4
        func x(_ value: Double) -> CGFloat { midX + CGFloat((value - live) / 0.25) * step }
        let steps = self.steps
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.controlOpen)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.barLabel.opacity(0.35))
                    .frame(width: step * CGFloat(steps.count - 1), height: 3)
                    .offset(x: x(steps[0]), y: midY - 1.5)
                ForEach(steps, id: \.self) { value in
                    Rectangle().fill(Palette.barLabel.opacity(0.6))
                        .frame(width: 2, height: 9)
                        .offset(x: x(value) - 1, y: midY - 4.5)
                    Text(value == TextScale.off ? "Off" : TextScale.number(value))
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
            Text(TextScale.title(at: live))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 60, alignment: .center)
                .offset(x: midX - 30, y: max(midY - 34, -1))
        }
        .frame(width: w, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 0.5, 0.75, 1, 1.25, 1.5: trailing zeros dropped, and "1" rather than "1.0".
    static func label(_ scale: Double) -> String { TextScale.number(scale) }
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

    /// Press and hold a thumbnail for the hold (ThumbnailHold: 0.5 s unless changed in Settings ›
    /// This iPad or iPhone, 0.2 to 3 s; issue #113, it was a fixed 1.5 s): it starts to wiggle and its traffic
    /// lights (close, minimize, full screen) appear in a submenu beside it, the way a held Home Screen
    /// icon offers its menu. Keep holding and move: the submenu goes, the thumbnail lifts and drags
    /// into a new slot. The arrangement is the device's own, persisted per Mac. A tap selects.
    ///
    /// `Sill.thumbnailHold`, read for its changes (the panel's stepper writes it, and this redraws the
    /// strip, whose thumbnails take the new length at once); the length itself through
    /// `ThumbnailHold.seconds(stored:)`, since `-Sill.thumbnailHold 0.3` is a string in UserDefaults.
    @AppStorage(ThumbnailHold.key) private var storedHold = ThumbnailHold.standard
    private var hold: TimeInterval {
        _ = storedHold
        return ThumbnailHold.seconds(stored: UserDefaults.standard.object(forKey: ThumbnailHold.key))
    }
    #if DEBUG
    /// The last length the console was told ("thumbnails: hold 0.5 s"), so a strip that comes and goes
    /// (a rotation, another bar) says it only when it changes.
    @MainActor private static var loggedHold: TimeInterval?
    @MainActor private static func logHold(_ hold: TimeInterval) {
        guard loggedHold != hold else { return }
        loggedHold = hold
        print(ThumbnailHold.consoleLine(hold))
    }
    #endif
    /// What the tour lights of the strip: its thumbnails' band (the strip is as tall as its bar),
    /// with the active halo's 5 pt above and the app badge's 6 pt below.
    static func tourBand(pad: CGFloat) -> EdgeInsets {
        EdgeInsets(top: max(0, pad - 5), leading: 0, bottom: max(0, pad - 6), trailing: 0)
    }
    @State private var lifted: UInt32? = nil
    @State private var liftOffset: CGFloat = 0
    @State private var liftStartIndex = 0

    var body: some View {
        let windows = client.orderedWindows
        let slot = width + spacing
        let hold = self.hold    // read here, in the body, so a change of the setting redraws the strip
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
                            HoldDragOverlay(minimumHold: hold,
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
            Self.logHold(hold)
            if UserDefaults.standard.bool(forKey: "SillWindowMenu"), let first = client.orderedWindows.first { menuFor = first.id }
        }
        .onChange(of: hold) { _, now in Self.logHold(now) }
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
    /// The hold's length (ThumbnailHold): a change reaches the long press already made, so the
    /// thumbnails on screen wait the new length from their next press.
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
        context.coordinator.hold = hold
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        // Settings › This iPad (or iPhone) changed the hold: this thumbnail's next press waits the new length.
        if let hold = context.coordinator.hold, hold.minimumPressDuration != minimumHold { hold.minimumPressDuration = minimumHold }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: HoldDragOverlay
        /// The thumbnail's long press, for `updateUIView` to give it a new length.
        weak var hold: UILongPressGestureRecognizer?
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
            if let why = client.lockWhy, !client.lockView {
                // A locked Mac sends no windows, apps or icons (its LockPolicy, docs/locked-mac-plan.md),
                // and launches nothing: one line where they would be.
                lockedLine(why)
                Spacer(minLength: 0)
            } else {
                // The off-console view (docs/off-console-plan.md): what the picture is, above the open apps; nothing
                // is launched then, so no All apps.
                if client.lockView { viewLine }
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
                        if !closedApps.isEmpty, !client.lockView {
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
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.bar))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 30, x: 0, y: 24)
    }

    /// A locked Mac (`StreamClient.lockWhy`): one line in place of the search field and both lists, read
    /// by VoiceOver as it is (the lock symbol is not).
    private func lockedLine(_ why: LockedMac.Why) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: why == .otherUser ? "person.2.fill" : "lock.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(LockedMac.line(mac: client.macName, why: why))
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }

    /// The off-console view's line, in the locked line's look (person.2.fill), read by VoiceOver as it is.
    private var viewLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(LockedMac.viewPanelLine)
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
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
