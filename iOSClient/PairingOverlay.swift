import SwiftUI
import StreamProtocol

/// Pair This iPad… (docs/remote-access-plan.md §7.7, §7.10): over the stream while this device is
/// connected at home, in the view hierarchy (never a presentation, which the Duo harness could not
/// hold and which could cross the crease). Opening it asks the Mac to show its code (kind 21); the
/// scanner reads it, or the code is typed (the address comes from this connection's kind 18). A
/// pairing here never moves the session: the pairing connection closes and the home session goes
/// on. Also where an outside sill://pair link is confirmed while connected, and its pairing then
/// runs to its end.
struct PairingOverlay: View {
    @ObservedObject var client: StreamClient
    let scannerMode: CodeScanner.Mode
    let close: () -> Void
    @State private var typed: Bool
    @State private var code = ""
    @State private var asked = false
    /// An outside link confirmed here: the name of its Mac, whose pairing this overlay now shows.
    @State private var linkName: String?
    @FocusState private var codeFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(client: StreamClient, scannerMode: CodeScanner.Mode, typed: Bool = false, close: @escaping () -> Void) {
        self.client = client
        self.scannerMode = scannerMode
        self.close = close
        _typed = State(initialValue: typed || (scannerMode == .live && !CodeScanner.isSupported))
    }

    private var mac: String { client.macName.isEmpty ? "your Mac" : client.macName }
    private var working: Bool { if case .working = client.pairing { return true }; return false }

    var body: some View {
        GeometryReader { geo in
            let layout = ConnectLayout(size: geo.size)
            let width = min(layout.short ? 640 : 420, geo.size.width - 32)
            // The code field has the keyboard: the content goes to the top, so Pair stays above it
            // (the stream screen ignores the keyboard's safe area, so nothing moves by itself), as
            // on the connect screen. The half-folded Duo's is in the top half already.
            let toTop = codeFocused && !layout.topHalf
            ZStack(alignment: .top) {
                // No tap gesture here: one on this backdrop took the taps meant for the buttons in
                // front of it (measured on the simulator). What is under the overlay is not
                // hit-testable anyway (StreamScreen), so a touch on the backdrop does nothing.
                Color.black.opacity(0.85)
                    .accessibilityHidden(true)
                Group {
                    if let link = client.pendingLink {
                        LinkConfirmation(link: link, pair: {
                            // The overlay stays, now for this link's pairing (StreamScreen holds it open).
                            linkName = link.name
                            client.confirmPendingLink()
                        }, cancel: cancel)
                    } else if let linkName {
                        linkProgress(linkName)
                    } else {
                        content(layout)
                    }
                }
                .frame(width: width, alignment: .leading)
                .padding(.vertical, 16)
                // The Duo half-folded: the top half only (the crease is at the middle); elsewhere
                // centred, or at the top while the code is typed.
                .frame(maxWidth: .infinity, maxHeight: layout.topHalf ? geo.size.height / 2 : geo.size.height,
                       alignment: toTop ? .top : .center)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, cancel)
        .background(EscapeKey(action: cancel))
        .onAppear {
            titleFocused = true
            // "Show your pairing code": the Mac opens its pairing window by itself.
            if !asked, client.pendingLink == nil, client.connected { asked = true; client.requestPairingCode() }
        }
        .task(id: client.pairing) {
            // Paired: says so, then fades after a second; the stream never stopped.
            guard case .paired = client.pairing else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { close() }
                client.pairing = .idle
            }
        }
    }

    /// Cancel, Esc and the escape gesture: a pairing still dialing stops (as the connect screen's
    /// card does), and an outside link waiting here is dropped rather than shown again later.
    private func cancel() {
        client.cancelPendingLink()
        client.cancelPairing()
        close()
    }

    @ViewBuilder private func content(_ layout: ConnectLayout) -> some View {
        if layout.short && !typed {
            HStack(alignment: .top, spacing: 16) {
                CodeScanner(mode: scannerMode, onLink: { client.scanned($0, tapped: $1, overlay: true) },
                            retryNeedsTap: client.scanRetryNeedsTap)
                    .frame(width: 260, height: 200)
                VStack(alignment: .leading, spacing: 8) {
                    title
                    status
                    links
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                title
                if typed {
                    codeField
                } else {
                    CodeScanner(mode: scannerMode, onLink: { client.scanned($0, tapped: $1, overlay: true) },
                                retryNeedsTap: client.scanRetryNeedsTap)
                        .frame(maxWidth: 420, maxHeight: 300)
                        .frame(height: layout.topHalf ? 220 : 300)
                }
                status
                links
            }
        }
    }

    /// An outside link's pairing, once confirmed: its progress, its error or "Paired with…" (which
    /// fades the overlay after a second), and Cancel. No scanner: the link may name another Mac
    /// than the one this session streams.
    private func linkProgress(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair with \(name)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            status
            cancelButton
                .buttonStyle(.plain)
        }
        .onAppear { titleFocused = true }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The typed path is all a device without the scanner gets: it says what to do there.
            Text(typed ? "Enter the Code from \(mac)" : "Scan the Code on \(mac)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text("\(mac) is showing a code now.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
        }
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            PairingField(prompt: "0000 0000 0000", label: "Code", text: $code, keyboard: PairingField.codeKeyboard, submit: .go, monospaced: true)
                .focused($codeFocused)
                .onSubmit(pairTyped)
                .onChange(of: code) { _, typed in
                    let grouped = PairingField.grouped(typed)
                    if grouped != typed { code = grouped }
                }
            Button(action: pairTyped) {
                Text("Pair")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(minWidth: 88, minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent.opacity(working ? 0.4 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
    }

    /// The typed path here needs only the code: the address is this connection's Mac's own
    /// (StreamClient.overlayAddress).
    private func pairTyped() {
        guard !working else { return }
        codeFocused = false
        guard let address = client.overlayAddress() else {
            client.pairing = .failed(.notPairing(mac))
            return
        }
        client.pairTyped(code: code, address: address, overlay: true)
    }

    @ViewBuilder private var status: some View {
        switch client.pairing {
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Palette.muted)
                Text(text)
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.muted)
            .accessibilityElement(children: .combine)
        case .paired(let name):
            Label("Paired with \(name).", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)
                .onAppear { AccessibilityNotification.Announcement("Paired with \(name).").post() }
        case .failed(let p):
            ProblemLine(text: p.text)
        case .idle:
            EmptyView()
        }
    }

    private var links: some View {
        HStack(spacing: 18) {
            if CodeScanner.isSupported || scannerMode != .live {
                Button(typed ? "Scan Code Instead" : "Enter Code Instead") {
                    client.pairing = .idle
                    codeFocused = false
                    typed.toggle()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
            }
            cancelButton
        }
        .buttonStyle(.plain)
    }

    private var cancelButton: some View {
        Button("Cancel", action: cancel)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
            .keyboardShortcut(.cancelAction)
    }
}
