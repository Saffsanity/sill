import SwiftUI
import StreamProtocol

/// How the connect screen's column sits on this screen (docs/remote-access-plan.md §7.10).
struct ConnectLayout {
    let size: CGSize

    /// 380 pt, or the screen's width less 32 pt on one narrower than 412 pt (which also gives the
    /// old column the margin it lacked at 375 pt).
    var columnWidth: CGFloat { size.width < 412 ? max(200, size.width - 32) : 380 }
    /// The column's leading edge: where the 380 pt column sits centred. What widens the column
    /// (the side-by-side card) grows towards the trailing edge, so the title never moves sideways.
    var columnX: CGFloat { max(16, (size.width - columnWidth) / 2) }
    /// The card side by side (a short screen): the viewfinder's 260 pt and its words, from the
    /// column's leading edge to 24 pt short of the screen's trailing one, at most 620 pt.
    var sideBySideWidth: CGFloat { max(columnWidth, min(size.width - columnX - 24, 620)) }
    /// The Duo half-folded, or in its laptop posture (710×1000): the column lives in the top half,
    /// so nothing crosses the crease at the middle and the keyboard has the lower half.
    var topHalf: Bool { size.height > size.width && size.width >= 600 && size.width < 740 && size.height < 1100 }
    /// Any height under 520 pt (the Duo's outer display on its side, an iPhone in landscape): the
    /// card goes side by side.
    var short: Bool { size.height < 520 }
    /// The Duo's outer display upright (500×710) and phones: the column anchors to the top while a
    /// field has the keyboard.
    var compactPortrait: Bool { size.height > size.width && size.width < 600 }
}

/// Add a Mac (docs/remote-access-plan.md §7.7–7.8, §7.10), unfolded in the connect screen's column
/// in place of the rows. Scanning the code on the Mac is the default; Enter Code Instead types its
/// address and 12-digit code. Pairing progress and every error show inline, never in an alert.
struct AddMacCard: View {
    @ObservedObject var client: StreamClient
    let layout: ConnectLayout
    /// The scanner, or the typed path; the connect screen keeps it so the harness can start there.
    @Binding var typed: Bool
    let scannerMode: CodeScanner.Mode
    /// Folds the card back (Cancel, Esc, the VoiceOver escape gesture).
    let close: () -> Void
    /// A field has the keyboard: the column collapses its words to one line.
    @Binding var editing: Bool

    @State private var address = ""
    @State private var code = ""
    @FocusState private var focus: Field?
    enum Field: Hashable { case address, code }

    private var device: String { StreamClient.deviceWord }
    private var working: Bool { if case .working = client.pairing { return true }; if case .paired = client.pairing { return true }; return false }
    private var problem: PairingProblem? { if case .failed(let p) = client.pairing { return p }; return nil }

    var body: some View {
        Group {
            if layout.short && !typed {
                HStack(alignment: .top, spacing: 16) {
                    CodeScanner(mode: scannerMode, onLink: { client.pair(link: $0, overlay: false) })
                        .frame(width: 260, height: 200)
                    VStack(alignment: .leading, spacing: 8) {
                        words
                        progress
                        links
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    words
                    if typed {
                        fields
                    } else if !working {
                        CodeScanner(mode: scannerMode, onLink: { client.pair(link: $0, overlay: false) })
                            .frame(height: layout.short ? 200 : 230)
                    }
                    progress
                    links
                }
            }
        }
        .onChange(of: focus) { _, f in editing = f != nil }
        .accessibilityAction(.escape, close)
        .background(EscapeKey(action: close))
    }

    // MARK: Words

    @ViewBuilder private var words: some View {
        if editing && (layout.compactPortrait || layout.short) {
            Text("Type the address and code from your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
        } else {
            Text("Pair once, and Sill reaches your Mac from anywhere, through your VPN or the internet.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(typed ? "Type the address and code that Sill shows on your Mac."
                       : "On your Mac, choose Pair iPhone or iPad… in the Sill menu, then point this \(device) at the code.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The typed path

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            PairingField(prompt: "100.101.102.103 or mac.example.net", label: "Address", text: $address,
                         keyboard: .URL, submit: .next)
                .focused($focus, equals: .address)
                .onSubmit { focus = .code }
            if let problem, problem.field == .address { ProblemLine(text: problem.text) }
            PairingField(prompt: "0000 0000 0000", label: "Code", text: $code, keyboard: PairingField.codeKeyboard, submit: .go, monospaced: true)
                .focused($focus, equals: .code)
                .onSubmit(pair)
                .onChange(of: code) { _, typed in
                    let grouped = PairingField.grouped(typed)
                    if grouped != typed { code = grouped }
                }
            if let problem, problem.field == .code { ProblemLine(text: problem.text) }
            Button(action: pair) {
                Text("Pair")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(minWidth: 88, minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent.opacity(working ? 0.4 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(working)
            .keyboardShortcut(.defaultAction)
        }
        .disabled(working)
    }

    private func pair() {
        guard !working else { return }
        focus = nil
        client.pairTyped(code: code, address: address, overlay: false)
    }

    // MARK: Progress and errors

    @ViewBuilder private var progress: some View {
        switch client.pairing {
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Palette.muted)
                Text(text)
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.muted)
            .frame(minHeight: 24)
            .accessibilityElement(children: .combine)
        case .paired(let name):
            Label("Paired with \(name).", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Palette.text)
        case .failed(let p) where p.field == .card || !typed:
            ProblemLine(text: p.text)
        default:
            EmptyView()
        }
    }

    // MARK: Links

    /// Side by side, or one above the other where the words beside a viewfinder are narrow (a
    /// 667 pt wide phone on its side).
    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { pathToggle; cancelButton }
            VStack(alignment: .leading, spacing: 0) { pathToggle; cancelButton }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var pathToggle: some View {
        if CodeScanner.isSupported || scannerMode != .live {
            Button(typed ? "Scan Code Instead" : "Enter Code Instead") {
                client.pairing = .idle
                focus = nil
                typed.toggle()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
            .disabled(working)
        }
    }

    private var cancelButton: some View {
        Button("Cancel", action: close)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
            .keyboardShortcut(.cancelAction)
    }
}

/// A 48 pt field on the drawer's control colour, like the app drawer's search field.
struct PairingField: View {
    let prompt: String
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var submit: SubmitLabel = .done
    var monospaced = false

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(Palette.muted))
            .font(.system(size: 15).monospacedDigit())
            .foregroundStyle(Palette.text)
            .textFieldStyle(.plain)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submit)
            .accessibilityLabel(label)
            .frame(height: 48)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The number pad on a phone (the Duo's is what the digits are for). On an iPad the number pad
    /// floats as a popover that swallows the next tap outside it, so Pair took two taps (measured
    /// on the simulator): the docked keyboard's numbers and punctuation instead, whose Return
    /// pairs.
    static var codeKeyboard: UIKeyboardType {
        UIDevice.current.userInterfaceIdiom == .pad ? .numbersAndPunctuation : .numberPad
    }

    /// "4829 1355 7208" as it is typed or pasted: digits only, at most 12, in groups of 4.
    static func grouped(_ text: String) -> String {
        let digits = text.filter { $0.isASCII && $0.isNumber }.prefix(12)
        return stride(from: 0, to: digits.count, by: 4).map { i -> String in
            let start = digits.index(digits.startIndex, offsetBy: i)
            return String(digits[start..<digits.index(start, offsetBy: min(4, digits.count - i))])
        }.joined(separator: " ")
    }
}

/// An inline problem, orange, under the field it belongs to; VoiceOver announces it.
struct ProblemLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.orange)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
        .onAppear { AccessibilityNotification.Announcement(text).post() }
        .onChange(of: text) { _, t in AccessibilityNotification.Announcement(t).post() }
    }
}

/// Esc on a hardware keyboard, also while a field has the keyboard. The text system may claim a
/// key before any key command sees it, and SwiftUI's `.cancelAction` shortcut does not ask for
/// priority, so while this view is on screen a key command that does sits on the hosting
/// controller, which every responder chain in the window passes through. ⌘. stays with the
/// Cancel buttons' shortcuts (verified in the simulator). Esc itself is unverified: XCUITest's
/// Escape never reaches the app on the iPadOS 27 simulator (a first-responder probe saw no press
/// at all), so a real keyboard decides (R12).
struct EscapeKey: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ anchor: Anchor, context: Context) { anchor.action = action }
    static func dismantleUIView(_ anchor: Anchor, coordinator: ()) { anchor.detach() }

    /// A zero-size view that finds its view controller when it joins a window.
    final class Anchor: UIView {
        var action: (() -> Void)?
        /// The anchors on screen, newest last: the pairing overlay over a card answers first.
        fileprivate static var live: [Anchor] = []
        private weak var host: UIViewController?
        private let command: UIKeyCommand = {
            let command = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [],
                                       action: #selector(UIViewController.sillEscapeKey(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }()

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        private func attach() {
            guard host == nil else { return }
            var responder: UIResponder? = next
            while let r = responder, !(r is UIViewController) { responder = r.next }
            guard let controller = responder as? UIViewController else { return }
            host = controller
            controller.addKeyCommand(command)
            Self.live.append(self)
        }

        func detach() {
            host?.removeKeyCommand(command)
            host = nil
            Self.live.removeAll { $0 === self }
        }

        fileprivate static func fire() { live.last?.action?() }
    }
}

extension UIViewController {
    /// EscapeKey's command: the chain from whichever responder has the keyboard reaches a view
    /// controller, which hands the key to the newest anchor on screen.
    @objc fileprivate func sillEscapeKey(_ sender: UIKeyCommand) {
        EscapeKey.Anchor.fire()
    }
}

/// A sill://pair link from outside the app, waiting for the person (§7.7): shown in the card's
/// place on the connect screen, or over the stream. Never acted on by itself: a poster or a message
/// could otherwise add a look-alike "Mac" that collects keystrokes.
struct LinkConfirmation: View {
    let link: PairLink
    let pair: () -> Void
    let cancel: () -> Void

    private var at: String { link.addresses.first?.text ?? "its address" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pair with \(link.name) at \(at)?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Only pair with a code your own Mac shows.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button(action: pair) {
                    Text("Pair")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(minWidth: 88, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent))
                }
                .buttonStyle(.plain)
                Button("Cancel", action: cancel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityAction(.escape, cancel)
    }
}
