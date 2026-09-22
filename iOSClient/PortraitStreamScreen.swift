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

/// Portrait: the "Laptop mode, half folded" board. The upper half is the streamed window on its
/// own, touched directly like in landscape; the lower half is the machine you drive it with —
/// window bar, key row, trackpad — the way a folded laptop's bottom half carries them.
struct PortraitStreamScreen: View {
    @ObservedObject var client: StreamClient
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    @Binding var latched: KeyModifiers
    let overlay: InputOverlayProxy

    // The board's lower half: padding 12 / 14 / 22, 10 between the three rows, a 78 pt bar.
    private static let padTop: CGFloat = 12
    private static let padSide: CGFloat = 14
    private static let padBottom: CGFloat = 22
    private static let rowGap: CGFloat = 10
    private static let barHeight: CGFloat = 78

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
                        .padding(.top, half + Self.padTop + Self.barHeight + 8)
                        .padding(.bottom, Self.padBottom)
                        .transition(.opacity)
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
                         proxy: overlay,
                         isKeyboardShown: $keyboardShown,
                         latchedModifiers: latched,
                         onModifiersConsumed: { latched = [] })
        }
        .background(Palette.panel)
        .clipShape(streamShape)
        .overlay(streamShape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .padding(8)
    }

    // MARK: Lower half

    private var controls: some View {
        VStack(spacing: Self.rowGap) {
            windowBar
            KeyRow(latched: $latched, keyboardShown: keyboardShown,
                   send: { client.sendInput($0) },
                   toggleKeyboard: { overlay.toggleKeyboard() })
            Trackpad(send: { client.sendInput($0) },
                     latched: latched,
                     onModifiersConsumed: { latched = [] })
        }
        .padding(.top, Self.padTop)
        .padding(.horizontal, Self.padSide)
        .padding(.bottom, Self.padBottom)
    }

    /// The same Apps button and thumbnails as landscape, at the board's tighter size, with no
    /// Keyboard or Aa button: the keyboard moved into the key row and Aa is not in this layout.
    private var windowBar: some View {
        HStack(spacing: 12) {
            BarButton(open: drawerOpen, width: 64, height: 58,
                      accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                      action: { withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() } }) {
                VStack(spacing: 3) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(drawerOpen ? Palette.accent : Palette.text)
                    Text("Apps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(drawerOpen ? Palette.accent : Palette.barLabel)
                }
            }

            WindowStrip(client: client, width: 92, height: 58, radius: 9, spacing: 14, fade: 0.88)

            BarButton(open: client.active == .desktop, width: 64, height: 58,
                      accessibilityLabel: "Show the full Mac desktop",
                      action: { client.select(.desktop) }) {
                VStack(spacing: 3) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 22))
                        .foregroundStyle(client.active == .desktop ? Palette.accent : Palette.text)
                    Text("Desktop")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(client.active == .desktop ? Palette.accent : Palette.barLabel)
                }
            }
        }
        .frame(height: Self.barHeight)
    }
}

// MARK: - Key row

/// The keys a Mac needs that a software keyboard does not offer: escape, tab, the four arrows, the
/// four modifiers, and the keyboard itself. Eleven equal caps, 48 pt tall.
private struct KeyRow: View {
    @Binding var latched: KeyModifiers
    let keyboardShown: Bool
    let send: (InputEvent) -> Void
    let toggleKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            cap(open: false, label: "Escape", action: { press(HIDKey.escape) }) { text("esc") }
            cap(open: false, label: "Tab", action: { press(HIDKey.tab) }) { text("tab") }
            latchKey("ctrl", .control, label: "Control")
            latchKey("opt", .option, label: "Option")
            latchKey("cmd", .command, label: "Command")
            latchKey("shift", .shift, label: "Shift")
            arrow("chevron.left", HIDKey.leftArrow, label: "Left arrow")
            arrow("chevron.down", HIDKey.downArrow, label: "Down arrow")
            arrow("chevron.up", HIDKey.upArrow, label: "Up arrow")
            arrow("chevron.right", HIDKey.rightArrow, label: "Right arrow")
            cap(open: keyboardShown,
                label: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                action: toggleKeyboard) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20))
                    .foregroundStyle(keyboardShown ? Palette.accent : Palette.text)
            }
        }
        .frame(height: 48)
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
