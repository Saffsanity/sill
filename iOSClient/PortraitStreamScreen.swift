import SwiftUI
import StreamProtocol

// MARK: - Keys

/// The USB HID usages the portrait key row sends, plus the small character table a latched
/// ⌘/⌃/⌥ needs: those combinations never reach the software keyboard as text.
enum HIDKey {
    static let escape: UInt16 = 0x29
    static let tab: UInt16 = 0x2B
    static let deleteBackward: UInt16 = 0x2A
    static let rightArrow: UInt16 = 0x4F
    static let leftArrow: UInt16 = 0x50
    static let downArrow: UInt16 = 0x51
    static let upArrow: UInt16 = 0x52

    /// US-layout character → HID usage. Shortcuts are named by the unshifted key (⌘⇧S is the S
    /// key with two modifiers), so the character is lowercased first. Returns nil for anything
    /// outside the table — accented letters, emoji, IME output — which stays on the text path.
    static func usage(for character: Character) -> UInt16? {
        let lowered = character.lowercased()
        guard lowered.count == 1, let ascii = lowered.first?.asciiValue else { return nil }
        switch ascii {
        case 0x61...0x7A: return 0x04 + UInt16(ascii - 0x61)   // a–z
        case 0x31...0x39: return 0x1E + UInt16(ascii - 0x31)   // 1–9
        case 0x30: return 0x27                                  // 0
        case 0x20: return 0x2C                                  // space
        case 0x0A, 0x0D: return 0x28                            // return
        case 0x09: return tab
        case 0x08: return deleteBackward
        case 0x2D: return 0x2D                                  // -
        case 0x3D: return 0x2E                                  // =
        case 0x5B: return 0x2F                                  // [
        case 0x5D: return 0x30                                  // ]
        case 0x5C: return 0x31                                  // \
        case 0x3B: return 0x33                                  // ;
        case 0x27: return 0x34                                  // '
        case 0x60: return 0x35                                  // `
        case 0x2C: return 0x36                                  // ,
        case 0x2E: return 0x37                                  // .
        case 0x2F: return 0x38                                  // /
        default: return nil
        }
    }
}

// MARK: - Screen

/// Everything the portrait layouts size: the halves at the inner display's size (`.regular`) and at
/// the outer display's (`.compact`), which an iPad window narrower than 600 pt keeps, and a phone
/// held upright (`.phone`), whose rects come from `PhonePortraitLayout`.
///
/// The compact halves are the same screen as the inner display's, not a different one: same 50/50
/// split, same three rows in the same order. They are only 500 pt wide, so the numbers shrink — but
/// nothing shrinks below a 44 pt touch target, which is what forces the one real change: twelve caps
/// do not fit across 472 pt at 44 pt each, so the key row folds into two rows of six.
struct PortraitMetrics {
    let padTop: CGFloat
    let padSide: CGFloat
    let padBottom: CGFloat
    let rowGap: CGFloat

    let barHeight: CGFloat
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    let buttonRadius: CGFloat
    let buttonIcon: CGFloat
    let buttonSpacing: CGFloat

    let thumbWidth: CGFloat
    let thumbHeight: CGFloat
    let thumbRadius: CGFloat
    let thumbSpacing: CGFloat
    let thumbPad: CGFloat
    let thumbFade: Double
    let badge: CGFloat

    let capHeight: CGFloat
    let keyGap: CGFloat
    let keyRowGap: CGFloat
    /// Whether the key row folds into two.
    let splitKeys: Bool
    /// The phone's arrangement (`PhonePortraitLayout`) rather than the halves.
    let phone: Bool

    var keyBlockHeight: CGFloat { splitKeys ? capHeight * 2 + keyRowGap : capHeight }

    /// The Laptop board at the inner display's 710×1000.
    static let regular = PortraitMetrics(
        padTop: 12, padSide: 14, padBottom: 22, rowGap: 10,
        barHeight: 78, buttonWidth: 64, buttonHeight: 58, buttonRadius: 16,
        buttonIcon: 22, buttonSpacing: 3,
        thumbWidth: 92, thumbHeight: 58, thumbRadius: 9, thumbSpacing: 14, thumbPad: 10,
        thumbFade: 0.88, badge: 24,
        capHeight: 48, keyGap: 8, keyRowGap: 8, splitKeys: false, phone: false)

    /// The same thing on the outer display's 500×710: an iPad window narrower than 600 pt held
    /// upright (Slide Over, a narrow Split View), as before the phone's arrangement.
    static let compact = PortraitMetrics(
        padTop: 10, padSide: 14, padBottom: 16, rowGap: 10,
        barHeight: 62, buttonWidth: 56, buttonHeight: 50, buttonRadius: 14,
        buttonIcon: 20, buttonSpacing: 3,
        thumbWidth: 80, thumbHeight: 50, thumbRadius: 8, thumbSpacing: 12, thumbPad: 6,
        thumbFade: 0.88, badge: 22,
        capHeight: 44, keyGap: 8, keyRowGap: 8, splitKeys: true, phone: false)

    /// A phone held upright, and the Duo's outer display upright (500×710): the compact styles
    /// (radii, symbol and thumbnail sizes, the badge, the fade). The sizes that place things are
    /// `PhonePortraitLayout`'s, and a button's width is its share of the row at the screen's width.
    static let phone = PortraitMetrics(
        padTop: PhonePortraitLayout.underPicture, padSide: PhonePortraitLayout.side,
        padBottom: PhonePortraitLayout.bottom, rowGap: PhonePortraitLayout.rowGap,
        barHeight: PhonePortraitLayout.stripHeight, buttonWidth: 0,
        buttonHeight: PhonePortraitLayout.buttonHeight, buttonRadius: 14,
        buttonIcon: 20, buttonSpacing: 3,
        thumbWidth: 80, thumbHeight: 50, thumbRadius: 8, thumbSpacing: 12,
        thumbPad: (PhonePortraitLayout.stripHeight - 50) / 2,
        thumbFade: 0.88, badge: 22,
        capHeight: PhonePortraitLayout.capHeight, keyGap: PhonePortraitLayout.gap,
        keyRowGap: PhonePortraitLayout.gap, splitKeys: false, phone: true)

    /// Row 1's symbols sit in a box this tall on the phone, so their labels share one line whatever
    /// each symbol's height (the keyboard's is 15 pt, the gear's 21), as a tab bar's do; Aa's text
    /// gets the same box (`TextScaleControl.iconBox`).
    static let phoneIconBox: CGFloat = 24
}

/// Portrait, in two arrangements. The halves (the inner display's, and an iPad window's) are the
/// "Laptop mode, half folded" board: the upper half is the streamed window on its own, touched
/// directly like in landscape; the lower half is the machine you drive it with (window bar, key
/// row, trackpad), the way a folded laptop's bottom half carries them. A phone's (Noah, 2026-09-27)
/// puts the picture in a fixed 16:10 pane at the top and gives the rest to the controls: row 1
/// (Apps, Aa, Keyboard, Desktop, Settings), the thumbnails, six keys and a taller trackpad
/// (`PhonePortraitLayout`). The picture pane, the key row, the trackpad, the drawer and the Settings
/// panel are the same views in both; each arrangement places them.
struct PortraitStreamScreen: View {
    @ObservedObject var client: StreamClient
    var metrics: PortraitMetrics = .regular
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    @Binding var textScale: Double?
    @Binding var scaleOpen: Bool
    @Binding var windowMenu: UInt32?
    @Binding var latched: KeyModifiers
    let overlay: InputOverlayProxy
    /// The Settings panel, owned by `StreamScreen` (see its `setSettings`).
    let settingsOpen: Bool
    let setSettings: (_ open: Bool, _ restoreKeyboard: Bool) -> Void
    /// The Menus pull-down opened and went (see `StreamScreen.menusOpened`).
    let menusOpened: () -> Void
    let menusClosed: () -> Void
    /// The panel's open and close motion, scaled about the given point (see `StreamScreen`).
    let settingsTransition: (_ anchor: UnitPoint) -> AnyTransition
    /// The stream panel's size in points, for the viewport `StreamScreen` sends the host.
    let onPanelSize: (CGSize) -> Void
    /// Pair This iPad… in the panel (see `StreamScreen.openPairingOverlay`).
    var pairThisDevice: () -> Void = {}
    /// Take the Tour in the panel (see `StreamScreen.takeTour`).
    var takeTour: () -> Void = {}

    private var streamShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
    /// The Duo's fold across this screen (StreamScreen, iOS 27.1): where the halves split.
    @Environment(\.duoFold) private var duoFold

    var body: some View {
        GeometryReader { geo in
            if metrics.phone {
                phone(PhonePortraitLayout(size: geo.size))
            } else {
                halves(geo.size)
            }
        }
    }

    // MARK: Two halves: the inner display, an iPad window

    private func halves(_ size: CGSize) -> some View {
        // At the middle, as before; on the Duo (iOS 27.1) at the fold's real band half-folded, and
        // open flat at the picture's own shape (docs/iphone-duo-plan.md, (b1) and (b2)).
        let split = DuoPosture.portraitSplit(size, duoFold, aspect: client.duoPaneAspect(textScale: textScale),
                                             controls: metrics.controlsHeight)
        let half = split.picture
        return ZStack(alignment: .topLeading) {
            Color.black

            VStack(spacing: split.controls - half) {
                picturePane.padding(8).frame(height: half)
                controls(width: size.width).frame(height: size.height - split.controls)
            }

            // Same order as landscape: the dim goes over the stream so a tap with the drawer
            // open closes the drawer instead of clicking the Mac. It covers both halves.
            if drawerOpen {
                dim

                drawer
                    .frame(width: min(380, size.width - 44))
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 22)
                    // Hangs from just under the window bar, so the button that opened it stays visible.
                    .padding(.top, split.controls + metrics.padTop + metrics.barHeight + 8)
                    .padding(.bottom, metrics.padBottom)
                    .transition(.opacity)
            }

            // The drawer's mirror: from just under the window bar at the trailing edge, lined up
            // with the Settings button, entirely in the lower half, so it never spans the Duo's
            // crease and the stream above stays in view. No dim; the tap catcher covers both
            // halves, as the drawer's dim does, so a tap anywhere outside closes the panel first
            // and never reaches the Mac.
            if settingsOpen {
                let top = split.controls + metrics.padTop + metrics.barHeight + 8
                catcher

                settingsPanel
                    .frame(width: min(360, size.width - 2 * metrics.padSide))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, top)
                    .padding(.bottom, metrics.padBottom)
                    .padding(.trailing, metrics.padSide)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    // The view carrying the transition fills the screen, so the panel's own
                    // top-trailing corner, under the Settings button, is given as a point in it.
                    .transition(settingsTransition(UnitPoint(x: 1 - metrics.padSide / max(size.width, 1),
                                                             y: top / max(size.height, 1))))
            }
        }
    }

    private func controls(width: CGFloat) -> some View {
        VStack(spacing: metrics.rowGap) {
            windowBar(width: width - 2 * metrics.padSide)
            keyRow(.full)
            trackpad(verticalSpan: nil)
        }
        .padding(.top, metrics.padTop)
        .padding(.horizontal, metrics.padSide)
        .padding(.bottom, metrics.padBottom)
    }

    /// The same Apps button and thumbnails as landscape, at the board's tighter size, with no
    /// Keyboard button (it is in the key row) but with the Aa control, whose ruler opens centred on
    /// it; the strip's end and the Desktop button fade while it is open. `width`: the bar's row.
    private func windowBar(width: CGFloat) -> some View {
        // Apps, Menus, Aa, Desktop, Settings, and the strip: Menus only where the row holds it and
        // still a whole thumbnail (not in a 320 pt Slide Over).
        let menusFit = MacMenuButton.fits(width: width, buttons: 5, buttonWidth: metrics.buttonWidth, gap: 12,
                                          thumbWidth: metrics.thumbWidth)
        return HStack(spacing: 12) {
            appsButton()

            windowStrip
                .opacity(scaleOpen ? 0.2 : 1)      // the slider unfolds over the strip's end
                .allowsHitTesting(!scaleOpen)

            // The Mac's menus, as in the landscape bar: only while the Mac sent some.
            if client.menus.hasMenus, menusFit {
                MacMenuButton(client: client, width: metrics.buttonWidth, height: metrics.buttonHeight,
                              radius: metrics.buttonRadius, iconSize: metrics.buttonIcon, spacing: metrics.buttonSpacing,
                              onOpen: menusOpened, onClose: menusClosed)
                    .opacity(scaleOpen ? 0 : 1)
                    .allowsHitTesting(!scaleOpen)
                    .transition(.opacity)
            }

            TextScaleControl(scale: $textScale, open: $scaleOpen,
                             width: metrics.buttonWidth, height: metrics.buttonHeight,
                             radius: metrics.buttonRadius, pointsPerStep: 36)
                .tourTarget(.textSize)

            desktopButton()
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)

            settingsButton()
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
        }
        .frame(height: metrics.barHeight)
        .animation(.easeOut(duration: 0.16), value: scaleOpen)
        .animation(.easeOut(duration: 0.18), value: client.menus.hasMenus)
    }

    // MARK: A phone held upright

    /// Every rect is `PhonePortraitLayout`'s, from this screen's size alone: the picture's pane is
    /// fixed at 16:10, so a 16:9 window gets black bars above and below and nothing under it moves.
    /// Row 1 holds the Keyboard button, which the software keyboard never covers; the keyboard
    /// covers the trackpad (this screen ignores its safe area, so nothing moves up). The drawer and
    /// the Settings panel hang under row 1, which stays live and undimmed while they are open, as
    /// the landscape bar does; the dim and the tap catcher cover everything else, so a tap outside
    /// closes them and never reaches the Mac.
    private func phone(_ layout: PhonePortraitLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black

            // In reading order, which is also top to bottom. While the drawer is open VoiceOver
            // skips what it dims (a double-tap there would reach the Mac, where a tap only closes
            // the drawer): row 1, then the drawer. The drawer and the Settings panel cover the strip
            // but for its first thumbnail's badge, which sticks out past row 1's leading edge; the
            // strip goes while either is open, so nothing cut shows beside them.
            PhoneRows(layout: layout) {
                picturePane.accessibilityHidden(drawerOpen)
                phoneRow1(layout)
                phoneRow2(layout)
                    .opacity(drawerOpen || settingsOpen ? 0 : 1)
                    .accessibilityHidden(drawerOpen)
                keyRow(.phone).accessibilityHidden(drawerOpen)
                trackpad(verticalSpan: layout.trackpadSpan).accessibilityHidden(drawerOpen)
            }

            if drawerOpen {
                ForEach(layout.dim.indices, id: \.self) { index in
                    dim.placed(layout.dim[index], in: layout.size)
                }
                drawer
                    .placed(layout.drawer, in: layout.size)
                    .transition(.opacity)
            }

            if settingsOpen {
                ForEach(layout.dim.indices, id: \.self) { index in
                    catcher.placed(layout.dim[index], in: layout.size)
                }
                settingsPanel
                    .frame(width: layout.settings.width)
                    .frame(maxHeight: layout.settings.height, alignment: .top)
                    .placed(at: layout.settings.origin, in: layout.size)
                    // Placed in a view the screen's size, so the anchor is the panel's top-trailing
                    // corner as a point of the screen, as in the halves.
                    .transition(settingsTransition(UnitPoint(x: layout.settingsAnchor.x, y: layout.settingsAnchor.y)))
            }
        }
    }

    /// Row 1: the landscape bar's five, in its order, widened to share the row with the key row's
    /// whitespace between them (Noah). Aa's ruler unfolds over the row; the other four fade and take
    /// no touch until it folds.
    private func phoneRow1(_ layout: PhonePortraitLayout) -> some View {
        let width = layout.buttons[PhonePortraitLayout.Button.apps.rawValue].width
        return HStack(spacing: PhonePortraitLayout.gap) {
            appsButton(width: width)
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)

            TextScaleControl(scale: $textScale, open: $scaleOpen,
                             width: width, height: layout.row1.height,
                             radius: metrics.buttonRadius, pointsPerStep: layout.rulerStep,
                             iconBox: PortraitMetrics.phoneIconBox, iconSpacing: metrics.buttonSpacing)
                .tourTarget(.textSize)

            barButton(open: keyboardShown, symbol: "keyboard", label: "Keyboard", width: width,
                      accessibilityLabel: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                      action: {
                          setSettings(false, false)
                          overlay.toggleKeyboard()
                      })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
                .tourTarget(.keyboard)

            desktopButton(width: width)
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)

            settingsButton(width: width)
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
        }
        .animation(.easeOut(duration: 0.16), value: scaleOpen)
    }

    /// Row 2: the thumbnails, and at the row's end, under Settings, the Menus button while the Mac
    /// sent menus (`PhonePortraitLayout.menus`), which it takes from the strip's width: next to the
    /// thumbnails because its menus are the picked window's app's, as in the other bars, and out of
    /// row 1, whose five share the row (the approved mockup's). The strip still shows a whole
    /// thumbnail and more on every phone.
    private func phoneRow2(_ layout: PhonePortraitLayout) -> some View {
        let menus = client.menus.hasMenus
        let strip = menus ? layout.stripBesideMenus : layout.strip
        return ZStack(alignment: .topLeading) {
            windowStrip.frame(width: strip.width, height: strip.height)
            if menus {
                MacMenuButton(client: client, width: layout.menus.width, height: layout.menus.height,
                              radius: metrics.buttonRadius, iconSize: metrics.buttonIcon, spacing: metrics.buttonSpacing,
                              iconBox: PortraitMetrics.phoneIconBox, onOpen: menusOpened, onClose: menusClosed)
                    .offset(x: layout.menus.minX - layout.strip.minX, y: layout.menus.minY - layout.strip.minY)
                    .transition(.opacity)
            }
        }
        .frame(width: layout.strip.width, height: layout.strip.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.18), value: menus)
    }

    // MARK: Shared by both

    /// Identical to the landscape stream panel, including the direct-touch overlay: in every layout
    /// this is the view that holds first responder, so the software keyboard types here. Measured
    /// as it is drawn: the panel the video is fitted into, which the viewport sends the Mac.
    private var picturePane: some View {
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
        .background(Palette.panel)
        .clipShape(streamShape)
        .overlay(streamShape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onPanelSize)
        .tourTarget(.stream)
    }

    private var windowStrip: some View {
        WindowStrip(client: client, width: metrics.thumbWidth, height: metrics.thumbHeight,
                    radius: metrics.thumbRadius, spacing: metrics.thumbSpacing,
                    pad: metrics.thumbPad, fade: metrics.thumbFade, badge: metrics.badge,
                    menuFor: $windowMenu)
            .tourTarget(.strip, inset: WindowStrip.tourBand(pad: metrics.thumbPad))
    }

    /// A key row key keeps what the sprite shows (StreamClient.sendFromKeyRow).
    private func keyRow(_ keys: KeyRow.Keys) -> some View {
        KeyRow(metrics: metrics, keys: keys, latched: $latched, keyboardShown: keyboardShown,
               send: { client.sendFromKeyRow($0) },
               toggleKeyboard: { overlay.toggleKeyboard() },
               showSpotlight: client.active == .desktop)
            .tourTarget(.keys)
    }

    private func trackpad(verticalSpan: CGFloat?) -> some View {
        Trackpad(send: { client.sendInput($0) },
                 setPointer: { client.setOwnPointer($0, from: .trackpad) },
                 feed: { let f = client.pointerFeedState; return (f.anchor, f.reseeds) },
                 onFingers: { client.trackpadFingers($0) },
                 latched: latched,
                 onModifiersConsumed: { latched = [] },
                 verticalSpan: verticalSpan,
                 sendGesture: { client.sendGesture($0, fingers: $1) })
            .tourTarget(.trackpad)
    }

    private var drawer: some View { AppDrawer(client: client, drawerOpen: $drawerOpen) }

    private var settingsPanel: some View {
        HostSettingsPanel(client: client, close: { setSettings(false, true) }, pairThisDevice: pairThisDevice,
                          takeTour: takeTour)
    }

    /// The drawer's dim: a tap on it closes the drawer instead of clicking the Mac.
    private var dim: some View {
        Color.black.opacity(0.58)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    /// The Settings panel's tap catcher: clear, so the stream stays in view while a setting changes.
    private var catcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { setSettings(false, true) }
            .accessibilityHidden(true)
    }

    private func appsButton(width: CGFloat? = nil) -> some View {
        barButton(open: drawerOpen, symbol: "magnifyingglass", label: "Apps", width: width,
                  accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                  action: {
                      setSettings(false, false)
                      withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() }
                  })
    }

    private func desktopButton(width: CGFloat? = nil) -> some View {
        barButton(open: client.active == .desktop, symbol: "desktopcomputer", label: "Desktop", width: width,
                  accessibilityLabel: "Show the full Mac desktop",
                  action: { client.select(.desktop) })
    }

    /// Leave's old slot: Disconnect is the Settings panel's pinned last row now.
    private func settingsButton(width: CGFloat? = nil) -> some View {
        barButton(open: settingsOpen, symbol: "gearshape", label: "Settings", width: width,
                  accessibilityLabel: settingsOpen ? "Close settings" : "Settings for \(client.macName.isEmpty ? "the Mac" : client.macName)",
                  action: { setSettings(!settingsOpen, true) })
            .tourTarget(.settings)
    }

    /// A bar button at the board's size, or at `width` (the phone's share of its row). On the phone
    /// the symbol sits in a fixed box, so the five labels share one line, and the labels stay on one
    /// line, shrinking a little before they would wrap (Bold Text at 320 pt); the row does not grow
    /// with the text size, so at the accessibility sizes a long press shows the button large.
    @ViewBuilder
    private func barButton(open: Bool, symbol: String, label: String, width: CGFloat? = nil,
                           accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        if metrics.phone {
            BarButton(open: open, width: width ?? metrics.buttonWidth, height: metrics.buttonHeight,
                      radius: metrics.buttonRadius, accessibilityLabel: accessibilityLabel,
                      action: action) {
                VStack(spacing: metrics.buttonSpacing) {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.buttonIcon))
                        .foregroundStyle(open ? Palette.accent : Palette.text)
                        .frame(height: PortraitMetrics.phoneIconBox)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(open ? Palette.accent : Palette.barLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
        } else {
            BarButton(open: open, width: width ?? metrics.buttonWidth, height: metrics.buttonHeight,
                      radius: metrics.buttonRadius, accessibilityLabel: accessibilityLabel,
                      action: action) {
                VStack(spacing: metrics.buttonSpacing) {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.buttonIcon))
                        .foregroundStyle(open ? Palette.accent : Palette.text)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(open ? Palette.accent : Palette.barLabel)
                }
            }
        }
    }
}

/// The phone's five parts at their `PhonePortraitLayout` rects, each proposed exactly its rect, in
/// the order they are declared (picture, row 1, strip, key row, trackpad), which is the reading
/// order VoiceOver takes.
private struct PhoneRows: Layout {
    let layout: PhonePortraitLayout

    private var rects: [CGRect] { [layout.picture, layout.row1, layout.strip, layout.keys, layout.trackpad] }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, rect) in zip(subviews, rects) {
            subview.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(rect.size))
        }
    }
}

private extension View {
    /// This view with its top-leading corner at `origin`, in a view the size of the whole screen, so
    /// a transition's anchor is a point of the screen; the room around it takes no touch.
    func placed(at origin: CGPoint, in size: CGSize) -> some View {
        padding(.leading, origin.x)
            .padding(.top, origin.y)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// This view at exactly `rect`, in a view the size of the whole screen.
    func placed(_ rect: CGRect, in size: CGSize) -> some View {
        frame(width: rect.width, height: rect.height).placed(at: rect.origin, in: size)
    }
}

// MARK: - Key row

/// One cap in the key row, as data, so each layout can pick its own set and fold it.
private enum Key {
    /// A key that types itself: the cap's text, its HID usage, its accessibility label.
    case press(String, UInt16, String)
    /// An arrow: SF Symbol, HID usage, label.
    case arrow(String, UInt16, String)
    /// A latching modifier: cap text, the bit it holds, its name.
    case modifier(String, KeyModifiers, String)
    /// The software keyboard toggle.
    case keyboard
    /// Spotlight on the Mac: always exactly ⌘Space, whatever is latched.
    case spotlight

    #if DEBUG
    /// What the cap says, for `-SillInputTest` to find it by.
    var title: String? {
        switch self {
        case .press(let title, _, _), .modifier(let title, _, _): return title
        case .arrow, .keyboard, .spotlight: return nil
        }
    }
    #endif
}

/// The keys a Mac needs that a software keyboard does not offer. In the halves (`.full`): escape,
/// tab, the four modifiers, the four arrows, the keyboard itself and Spotlight, twelve equal caps
/// across the screen at 48 pt tall, ≈49 pt wide at 710 pt — or, in the compact halves where twelve
/// 44 pt caps do not fit across 472 pt, six and then six, 72 pt wide at 500 pt. On a phone
/// (`.phone`): escape, tab and the four modifiers, six caps across the row; the Keyboard button is
/// in row 1, and Spotlight is cmd then space on the keyboard (a latched ⌘ turns a typed space into
/// ⌘Space). Arrows there come from a hardware keyboard.
private struct KeyRow: View {
    enum Keys { case full, phone }

    let metrics: PortraitMetrics
    let keys: Keys
    @Binding var latched: KeyModifiers
    let keyboardShown: Bool
    let send: (InputEvent) -> Void
    let toggleKeyboard: () -> Void
    /// Spotlight's panel is its own Mac window, so it only shows up in the stream while the whole
    /// desktop is the source. Anywhere else the key would be a cap that does something invisible.
    let showSpotlight: Bool

    private static let all: [Key] = [
        .press("esc", HIDKey.escape, "Escape"),
        .press("tab", HIDKey.tab, "Tab"),
        .modifier("ctrl", .control, "Control"),
        .modifier("opt", .option, "Option"),
        .modifier("cmd", .command, "Command"),
        .modifier("shift", .shift, "Shift"),
        .arrow("chevron.left", HIDKey.leftArrow, "Left arrow"),
        .arrow("chevron.down", HIDKey.downArrow, "Down arrow"),
        .arrow("chevron.up", HIDKey.upArrow, "Up arrow"),
        .arrow("chevron.right", HIDKey.rightArrow, "Right arrow"),
        .keyboard,
        .spotlight,
    ]

    /// The six that name a key.
    private static let phone = Array(all.prefix(6))

    private var shown: [Key] {
        switch keys {
        case .phone: return Self.phone
        case .full: return showSpotlight ? Self.all : Self.all.filter { if case .spotlight = $0 { return false } else { return true } }
        }
    }

    /// One row, or the compact halves' split: the six that name a key, then the four arrows, the
    /// keyboard and Spotlight. The break falls where the row changes job, not merely where it runs
    /// out of width.
    private var rows: [[Key]] {
        guard metrics.splitKeys else { return [shown] }
        return [Array(shown.prefix(6)), Array(shown.dropFirst(6))]
    }

    var body: some View {
        VStack(spacing: metrics.keyRowGap) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: metrics.keyGap) {
                    ForEach(rows[row].indices, id: \.self) { index in
                        key(rows[row][index])
                    }
                }
                .frame(height: metrics.capHeight)
            }
        }
        .frame(height: metrics.keyBlockHeight)
        #if DEBUG
        .onAppear(perform: runInputTest)
        #endif
    }

    @ViewBuilder private func key(_ key: Key) -> some View {
        switch key {
        case .press(let title, _, let label):
            cap(open: false, label: label, largeContent: title, action: { tap(key) }) { text(title) }
        case .arrow(let symbol, _, let label):
            cap(open: false, label: label, action: { tap(key) }) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
        case .modifier(let title, let flag, let label):
            latchKey(key, title, flag, label: label)
        case .keyboard:
            cap(open: keyboardShown,
                label: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                action: { tap(key) }) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20))
                    .foregroundStyle(keyboardShown ? Palette.accent : Palette.text)
            }
        case .spotlight:
            cap(open: false, label: "Open Spotlight on the Mac", action: { tap(key) }) {
                Image(systemName: Spotlight.symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.text)
            }
        }
    }

    /// What a tap on each cap does.
    private func tap(_ key: Key) {
        switch key {
        case .press(_, let usage, _), .arrow(_, let usage, _):
            press(usage)
        case .modifier(_, let flag, _):
            latched.formSymmetricDifference(flag)
        case .keyboard:
            toggleKeyboard()
        case .spotlight:
            // Latched modifiers do not join ⌘Space, but the tap still spends them.
            Spotlight.press(send: send)
            latched = []
        }
    }

    // MARK: Caps

    /// `largeContent`: the cap's text, which the phone's caps (fixed in size, as the row is) show
    /// large on a long press at the accessibility text sizes.
    @ViewBuilder
    private func cap<Content: View>(open: Bool, label: String, largeContent: String? = nil,
                                    action: @escaping () -> Void,
                                    @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let button = Button(action: action) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(open ? Palette.controlOpen : Palette.control))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        if keys == .phone, let largeContent {
            button.accessibilityShowsLargeContentViewer { Text(largeContent) }
        } else {
            button
        }
    }

    private func text(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
    }

    /// A latching modifier: it stays lit until something uses it, or until it is tapped again.
    private func latchKey(_ key: Key, _ title: String, _ flag: KeyModifiers, label: String) -> some View {
        let on = latched.contains(flag)
        return cap(open: on,
                   label: on ? "\(label), held. Tap to release." : "\(label), hold for the next key",
                   largeContent: title, action: { tap(key) }) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Palette.accent : Palette.text)
        }
    }

    /// escape, tab and the arrows: down and up, carrying whatever is latched, and the latch is
    /// spent — ⌥← is one tap on opt then one on the left arrow.
    private func press(_ usage: UInt16) {
        KeyChord.press(usage, with: latched).forEach(send)
        latched = []
    }

    #if DEBUG
    /// DEBUG `-SillInputTest 1` (ContentView's contract), the key row's half: once per launch, taps
    /// cmd, esc, shift and ctrl through `tap`, as the caps do, 1.0, 1.4, 1.8 and 2.0 s after the row
    /// shows: ⌘esc goes out and spends the ⌘ latch, and shift and ctrl stay latched for the
    /// trackpad's tap (TrackpadSurface's half).
    private func runInputTest() {
        guard InputTest.claim("key row") else { return }
        for (time, title) in [(1.0, "cmd"), (1.4, "esc"), (1.8, "shift"), (2.0, "ctrl")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                guard let key = shown.first(where: { $0.title == title }) else {
                    print("input test: no \(title) cap in this key row"); return
                }
                tap(key)
                print("input test: the key row's \(title) tapped; latched now " + InputTest.describe(latched))
            }
        }
    }
    #endif
}
