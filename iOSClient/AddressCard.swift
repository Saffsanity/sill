import SwiftUI
import StreamProtocol

/// Add an Address (docs/remote-access-plan.md §7.2, §7.7, §7.8): a saved Mac's menu unfolds this
/// card in the connect screen's column in place of the rows. One field, no code: the dial stays
/// pinned to the record's key, so the address only has to reach the Mac
/// (StreamClient.addTypedAddress). Problems and the added line show inline, never in an alert.
struct AddressCard: View {
    @ObservedObject var client: StreamClient
    let layout: ConnectLayout
    /// The saved Mac the address is for, as the connect screen found it when it unfolded the card.
    let mac: SavedMac
    /// Folds the card back (Cancel, Esc, the VoiceOver escape gesture).
    let close: () -> Void
    /// A field has the keyboard: the column collapses its words to one line.
    @Binding var editing: Bool

    @State private var address = ""
    @State private var problem: AddressProblem?
    /// The address as typed, once added: the checkmark line, the field gone.
    @State private var added: String?
    @FocusState private var focus: Field?
    enum Field: Hashable { case address }

    init(client: StreamClient, layout: ConnectLayout, mac: SavedMac, close: @escaping () -> Void, editing: Binding<Bool>) {
        self.client = client
        self.layout = layout
        self.mac = mac
        self.close = close
        _editing = editing
        #if DEBUG
        // The harness's photos of this card: a problem line, or the added line, without typing.
        if UserDefaults.standard.bool(forKey: "SillAddressAdded") {
            _added = State(initialValue: "mac.example.net")
        } else if let raw = UserDefaults.standard.string(forKey: "SillAddressProblem") {
            switch raw {
            case "address": _problem = State(initialValue: .address)
            case "zone": _problem = State(initialValue: .zone)
            case "notkeepable": _problem = State(initialValue: .notKeepable)
            case "full": _problem = State(initialValue: .full(mac.name))
            case "missing": _problem = State(initialValue: .missing(mac.name))
            default: _problem = State(initialValue: .alreadyDialed(mac.name))
            }
        }
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            words
            if let added {
                Label("Added \(added) to \(mac.name). It’s tried after \(mac.name)’s own addresses.",
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                fields
            }
            Button(added == nil ? "Cancel" : "Done", action: close)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
        }
        .onChange(of: focus) { _, f in editing = f != nil }
        .accessibilityAction(.escape, close)
        .background(EscapeKey(action: close))
    }

    // MARK: Words

    @ViewBuilder private var words: some View {
        if editing && (layout.compactPortrait || layout.short) {
            Text("Type an address that reaches \(mac.name).")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
        } else {
            Text("Reach \(mac.name) without pairing again.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("An address your VPN or the internet reaches, like 100.101.102.103 or mac.example.net. No code needed: Sill still checks it’s \(mac.name).")
                .font(.system(size: 13))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The field

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            PairingField(prompt: "100.101.102.103 or mac.example.net", label: "Address", text: $address,
                         keyboard: .URL, submit: .go)
                .focused($focus, equals: .address)
                .onSubmit(add)
            if let problem { ProblemLine(text: problem.text) }
            Button(action: add) {
                Text("Add")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(minWidth: 88, minHeight: 44)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func add() {
        focus = nil
        if let problem = client.addTypedAddress(address, for: mac.macID) {
            self.problem = problem
        } else {
            added = address
            problem = nil
            // The line below is a Label, which VoiceOver does not speak by itself (§7.8).
            AccessibilityNotification.Announcement("Added to \(mac.name).").post()
        }
    }
}
