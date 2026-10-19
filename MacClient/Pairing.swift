import SwiftUI
import StreamProtocol

/// Add a Mac… (an address and the 12-digit code its pairing window shows) and the home card (a Mac
/// on this network shows its code because a click asked: the code alone). The iPhone and iPad app's
/// AddMacCard without the camera: a Mac types the code.
struct PairingCard: View {
    @ObservedObject var client: StreamClient
    /// The home card's Mac, as its row names it; nil for Add a Mac.
    let home: String?
    let close: () -> Void

    @State private var address = ""
    @State private var code = ""
    @FocusState private var focus: Field?
    private enum Field: Hashable { case address, code }

    private var working: Bool {
        if case .working = client.pairing { return true }
        if case .paired = client.pairing { return true }
        return false
    }
    private var problem: PairingProblem? { if case .failed(let p) = client.pairing { return p }; return nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let mac = home {
                Text(DiscoveryPolicy.HomeCopy.typeCode(mac: mac))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Pair once, and Sill reaches your other Mac from anywhere, through your VPN or the internet.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("On the other Mac, choose Pair iPhone or iPad… in the Sill menu, then type the address and code it shows.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                if home == nil {
                    TextField("Address", text: $address, prompt: Text("100.101.102.103 or mac.example.net"))
                        .focused($focus, equals: .address)
                        .onSubmit { focus = .code }
                    if let problem, problem.field == .address { problemLine(problem.text) }
                }
                TextField("Code", text: $code, prompt: Text("0000 0000 0000"))
                    .font(.body.monospacedDigit())
                    .focused($focus, equals: .code)
                    .onSubmit(pair)
                    .onChange(of: code) { _, typed in
                        let grouped = Self.grouped(typed)
                        if grouped != typed { code = grouped }
                    }
                if let problem, problem.field == .code { problemLine(problem.text) }
            }
            .formStyle(.columns)
            .disabled(working)

            progress

            HStack {
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Pair", action: pair)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || code.filter(\.isNumber).count < 12 || (home == nil && address.isEmpty))
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
        .onAppear { focus = home == nil ? .address : .code }
    }

    private func pair() {
        guard !working else { return }
        if home != nil {
            client.pairHome(code: code)
        } else {
            client.pairTyped(code: code, address: address, overlay: false)
        }
    }

    @ViewBuilder private var progress: some View {
        switch client.pairing {
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text)
            }
            .foregroundStyle(.secondary)
        case .paired(let name):
            Label("Paired with \(name).", systemImage: "checkmark.circle.fill")
        case .failed(let p) where p.field == .card:
            problemLine(p.text)
        default:
            EmptyView()
        }
    }

    private func problemLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { UIAccessibility.post(notification: .announcement, argument: text) }
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

/// A sill://pair link from outside the app, waiting for the person: never acted on by itself.
struct LinkConfirmationCard: View {
    let link: PairLink
    @ObservedObject var client: StreamClient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pair with \(link.name) at \(link.addresses.first?.text ?? "its address")?")
                .font(.headline)
            Text("Only pair with a code your own Mac shows.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { client.cancelPendingLink() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Pair") { client.confirmPendingLink() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}
