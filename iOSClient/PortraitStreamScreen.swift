import SwiftUI
import StreamProtocol

// MARK: - Keys

/// The modifier bits an `InputEvent.key` carries: `UIKeyModifierFlags` raw values, which sit at the
/// same bit positions as the `CGEventFlags` the host posts with, so they travel unchanged.
struct KeyModifiers: OptionSet {
    let rawValue: UInt64

    static let shift   = KeyModifiers(rawValue: 1 << 17)
    static let control = KeyModifiers(rawValue: 1 << 18)
    static let option  = KeyModifiers(rawValue: 1 << 19)
    static let command = KeyModifiers(rawValue: 1 << 20)

    /// The three that make shortcuts instead of characters. Shift is not one of them: it changes
    /// which character the keyboard produces, which the text path already handles.
    static let shortcutMakers: KeyModifiers = [.control, .option, .command]

    /// Each latched modifier as its own key: the HID usage to press, and the bit it contributes.
    /// A pointer event has no modifier field, so a modified click has to hold these down around it.
    var keys: [(usage: UInt16, flag: KeyModifiers)] {
        var out: [(usage: UInt16, flag: KeyModifiers)] = []
        if contains(.control) { out.append((0xE0, .control)) }
        if contains(.shift)   { out.append((0xE1, .shift)) }
        if contains(.option)  { out.append((0xE2, .option)) }
        if contains(.command) { out.append((0xE3, .command)) }
        return out
    }
}

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

/// Everything the portrait layout sizes, at the inner display's size and the outer display's.
///
/// The outer display is the same screen, not a different one: same 50/50 split, same three rows in
/// the same order. It is only 500 pt wide, so the numbers shrink — but nothing shrinks below a
/// 44 pt touch target, which is what forces the one real change: twelve caps do not fit across
/// 472 pt at 44 pt each, so the key row folds into two rows of six.
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

    var keyBlockHeight: CGFloat { splitKeys ? capHeight * 2 + keyRowGap : capHeight }

    /// The Laptop board at the inner display's 710×1000.
    static let regular = PortraitMetrics(
        padTop: 12, padSide: 14, padBottom: 22, rowGap: 10,
        barHeight: 78, buttonWidth: 64, buttonHeight: 58, buttonRadius: 16,
        buttonIcon: 22, buttonSpacing: 3,
        thumbWidth: 92, thumbHeight: 58, thumbRadius: 9, thumbSpacing: 14, thumbPad: 10,
        thumbFade: 0.88, badge: 24,
        capHeight: 48, keyGap: 8, keyRowGap: 8, splitKeys: false)

    /// The same thing on the outer display's 500×710.
    static let compact = PortraitMetrics(
        padTop: 10, padSide: 14, padBottom: 16, rowGap: 10,
        barHeight: 62, buttonWidth: 56, buttonHeight: 50, buttonRadius: 14,
        buttonIcon: 20, buttonSpacing: 3,
        thumbWidth: 80, thumbHeight: 50, thumbRadius: 8, thumbSpacing: 12, thumbPad: 6,
        thumbFade: 0.88, badge: 22,
        capHeight: 44, keyGap: 8, keyRowGap: 8, splitKeys: true)
}

/// Portrait: the "Laptop mode, half folded" board. The upper half is the streamed window on its
/// own, touched directly like in landscape; the lower half is the machine you drive it with —
/// window bar, key row, trackpad — the way a folded laptop's bottom half carries them.
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
    /// The panel's open and close motion, scaled about the given point (see `StreamScreen`).
    let settingsTransition: (_ anchor: UnitPoint) -> AnyTransition
    /// The stream panel's size in points, for the viewport `StreamScreen` sends the host.
    let onPanelSize: (CGSize) -> Void
    /// Pair This iPad… in the panel (see `StreamScreen.openPairingOverlay`).
    var pairThisDevice: () -> Void = {}

    private var streamShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        GeometryReader { geo in
            let half = (geo.size.height / 2).rounded()
            ZStack(alignment: .topLeading) {
                Color.black

                VStack(spacing: 0) {
                    streamPane.frame(height: half)
                    controls.frame(height: geo.size.height - half)
                }

                // Same order as landscape: the dim goes over the stream so a tap with the drawer
                // open closes the drawer instead of clicking the Mac. It covers both halves.
                if drawerOpen {
                    Color.black.opacity(0.58)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    AppDrawer(client: client, drawerOpen: $drawerOpen)
                        .frame(width: min(380, geo.size.width - 44))
                        .frame(maxHeight: .infinity)
                        .padding(.leading, 22)
                        // Hangs from just under the window bar, so the button that opened it stays visible.
                        .padding(.top, half + metrics.padTop + metrics.barHeight + 8)
                        .padding(.bottom, metrics.padBottom)
                        .transition(.opacity)
                }

                // The drawer's mirror: from just under the window bar at the trailing edge, lined up
                // with the Settings button, entirely in the lower half, so it never spans the Duo's
                // crease and the stream above stays in view. No dim; the tap catcher covers both
                // halves, as the drawer's dim does, so a tap anywhere outside closes the panel first
                // and never reaches the Mac.
                if settingsOpen {
                    let top = half + metrics.padTop + metrics.barHeight + 8
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { setSettings(false, true) }
                        .accessibilityHidden(true)

                    HostSettingsPanel(client: client, close: { setSettings(false, true) }, pairThisDevice: pairThisDevice)
                        .frame(width: min(360, geo.size.width - 2 * metrics.padSide))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, top)
                        .padding(.bottom, metrics.padBottom)
                        .padding(.trailing, metrics.padSide)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        // The view carrying the transition fills the screen, so the panel's own
                        // top-trailing corner, under the Settings button, is given as a point in it.
                        .transition(settingsTransition(UnitPoint(x: 1 - metrics.padSide / max(geo.size.width, 1),
                                                                 y: top / max(geo.size.height, 1))))
                }
            }
        }
    }

    // MARK: Upper half

    /// Identical to the landscape stream panel, including the direct-touch overlay: in both
    /// layouts this is the view that holds first responder, so the software keyboard types here.
    private var streamPane: some View {
        ZStack {
            StreamView(client: client)
            InputOverlay(videoSize: client.videoSize,
                         send: { client.sendInput($0) },
                         setOwnPointer: { client.setOwnPointer($0, from: $1) },
                         proxy: overlay,
                         isKeyboardShown: $keyboardShown,
                         latchedModifiers: latched,
                         onModifiersConsumed: { latched = [] })
        }
        .background(Palette.panel)
        .clipShape(streamShape)
        .overlay(streamShape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        // Measured inside the padding, as in landscape: the panel the video is drawn in.
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onPanelSize)
        .padding(8)
    }

    // MARK: Lower half

    private var controls: some View {
        VStack(spacing: metrics.rowGap) {
            windowBar
            // A key row key keeps what the sprite shows (StreamClient.sendFromKeyRow).
            KeyRow(metrics: metrics, latched: $latched, keyboardShown: keyboardShown,
                   send: { client.sendFromKeyRow($0) },
                   toggleKeyboard: { overlay.toggleKeyboard() },
                   showSpotlight: client.active == .desktop)
            Trackpad(send: { client.sendInput($0) },
                     setPointer: { client.setOwnPointer($0, from: .trackpad) },
                     feed: { let f = client.pointerFeedState; return (f.anchor, f.reseeds) },
                     onFingers: { client.trackpadFingers($0) },
                     latched: latched,
                     onModifiersConsumed: { latched = [] })
        }
        .padding(.top, metrics.padTop)
        .padding(.horizontal, metrics.padSide)
        .padding(.bottom, metrics.padBottom)
    }

    /// The same Apps button and thumbnails as landscape, at the board's tighter size, with no
    /// Keyboard button (it moved into the key row) but with the Aa control, whose ruler opens
    /// centred on it; the strip's end and the Desktop button fade while it is open.
    private var windowBar: some View {
        HStack(spacing: 12) {
            barButton(open: drawerOpen, symbol: "magnifyingglass", label: "Apps",
                      accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                      action: {
                          setSettings(false, false)
                          withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() }
                      })

            WindowStrip(client: client, width: metrics.thumbWidth, height: metrics.thumbHeight,
                        radius: metrics.thumbRadius, spacing: metrics.thumbSpacing,
                        pad: metrics.thumbPad, fade: metrics.thumbFade, badge: metrics.badge,
                        menuFor: $windowMenu)
                .opacity(scaleOpen ? 0.2 : 1)      // the slider unfolds over the strip's end
                .allowsHitTesting(!scaleOpen)

            TextScaleControl(scale: $textScale, open: $scaleOpen,
                             width: metrics.buttonWidth, height: metrics.buttonHeight,
                             radius: metrics.buttonRadius, pointsPerStep: 36)

            barButton(open: client.active == .desktop, symbol: "desktopcomputer", label: "Desktop",
                      accessibilityLabel: "Show the full Mac desktop",
                      action: { client.select(.desktop) })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)

            // Leave's old slot: Disconnect is the Settings panel's pinned last row now.
            barButton(open: settingsOpen, symbol: "gearshape", label: "Settings",
                      accessibilityLabel: settingsOpen ? "Close settings" : "Settings for \(client.macName.isEmpty ? "the Mac" : client.macName)",
                      action: { setSettings(!settingsOpen, true) })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
        }
        .frame(height: metrics.barHeight)
        .animation(.easeOut(duration: 0.16), value: scaleOpen)
    }

    private func barButton(open: Bool, symbol: String, label: String, accessibilityLabel: String,
                           action: @escaping () -> Void) -> some View {
        BarButton(open: open, width: metrics.buttonWidth, height: metrics.buttonHeight,
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

// MARK: - Key row

/// One cap in the key row, as data, so the same twelve can be laid out as one row or two.
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
}

/// The keys a Mac needs that a software keyboard does not offer: escape, tab, the four arrows, the
/// four modifiers, the keyboard itself and Spotlight. Twelve equal caps across the screen at 48 pt
/// tall, ≈49 pt wide at 710 pt — or, on the outer display where twelve 44 pt caps do not fit
/// across 472 pt, six and then six, 72 pt wide at 500 pt.
private struct KeyRow: View {
    let metrics: PortraitMetrics
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

    /// One row of twelve, or the split: the six that name a key, then the four arrows, the
    /// keyboard and Spotlight. The break falls where the row changes job, not merely where it runs
    /// out of width.
    private var keys: [Key] {
        showSpotlight ? Self.all : Self.all.filter { if case .spotlight = $0 { return false } else { return true } }
    }

    private var rows: [[Key]] {
        guard metrics.splitKeys else { return [keys] }
        return [Array(keys.prefix(6)), Array(keys.dropFirst(6))]
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
    }

    @ViewBuilder private func key(_ key: Key) -> some View {
        switch key {
        case .press(let title, let usage, let label):
            cap(open: false, label: label, action: { press(usage) }) { text(title) }
        case .arrow(let symbol, let usage, let label):
            arrow(symbol, usage, label: label)
        case .modifier(let title, let flag, let label):
            latchKey(title, flag, label: label)
        case .keyboard:
            cap(open: keyboardShown,
                label: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                action: toggleKeyboard) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20))
                    .foregroundStyle(keyboardShown ? Palette.accent : Palette.text)
            }
        case .spotlight:
            // Latched modifiers do not join ⌘Space, but the tap still spends them.
            cap(open: false, label: "Open Spotlight on the Mac",
                action: { Spotlight.press(send: send); latched = [] }) {
                Image(systemName: Spotlight.symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.text)
            }
        }
    }

    // MARK: Caps

    private func cap<Content: View>(open: Bool, label: String, action: @escaping () -> Void,
                                    @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return Button(action: action) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(open ? Palette.controlOpen : Palette.control))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func text(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
    }

    private func arrow(_ symbol: String, _ usage: UInt16, label: String) -> some View {
        cap(open: false, label: label, action: { press(usage) }) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
        }
    }

    /// A latching modifier: it stays lit until something uses it, or until it is tapped again.
    private func latchKey(_ title: String, _ flag: KeyModifiers, label: String) -> some View {
        let on = latched.contains(flag)
        return cap(open: on,
                   label: on ? "\(label), held. Tap to release." : "\(label), hold for the next key",
                   action: { latched.formSymmetricDifference(flag) }) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Palette.accent : Palette.text)
        }
    }

    /// escape, tab and the arrows: down and up, carrying whatever is latched, and the latch is
    /// spent — ⌥← is one tap on opt then one on the left arrow.
    private func press(_ usage: UInt16) {
        send(.key(hidUsage: usage, down: true, modifiers: latched.rawValue))
        send(.key(hidUsage: usage, down: false, modifiers: latched.rawValue))
        latched = []
    }
}
