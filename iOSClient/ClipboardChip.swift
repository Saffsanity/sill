import SwiftUI
import UniformTypeIdentifiers
import StreamProtocol

/// The clipboard's chip over the stream (docs/clipboard-plan.md): "Paste on ‹Mac›", where the text goes
/// with Paste on ‹Mac› Right Away on ("Where the cursor is.": the Paste presses ⌘V there too),
/// else "Then press ⌘V there.", with the system's Paste button and Dismiss; for a moment after a Paste,
/// its note in the same place. Offered by StreamClient (`clipboardChip`, ClipboardPolicy.offersChip);
/// placed and hidden by StreamScreen. Takes no touch outside itself.
struct ClipboardChip: View {
    @ObservedObject var client: StreamClient
    /// Paste on ‹Mac› Right Away (StreamClient.pasteRightAwayOn), for the words.
    @AppStorage(StreamClient.pasteRightAwayKey) private var pasteRightAway = true

    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let note = client.clipboardNote {
                noteView(note)
                    .transition(.opacity)
            } else if client.clipboardChip {
                chip
                    .transition(.opacity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.easeOut(duration: 0.2), value: client.clipboardChip)
        .animation(.easeOut(duration: 0.2), value: client.clipboardNote)
    }

    private var chip: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ClipboardPolicy.Copy.chipTitle(mac: mac))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ClipboardPolicy.Copy.chipSubtitle(rightAway: pasteRightAway))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .layoutPriority(-1)
            // One element for the words; the Paste button and Dismiss are their own.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ClipboardPolicy.Copy.chipSpoken(mac: mac, device: StreamClient.deviceWord, rightAway: pasteRightAway))
            .accessibilityAddTraits(.isStaticText)
            ClipboardPasteButton(client: client)
            Button(action: { client.dismissClipboardChip() }) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ClipboardPolicy.Copy.dismiss)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Palette.bar))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func noteView(_ note: ClipboardNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: note.warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(note.warning ? Color.orange : Palette.accent)
                .accessibilityHidden(true)
            Text(note.text)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule(style: .continuous).fill(Palette.bar))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.spoken)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// The system's Paste button (SwiftUI's PasteButton, UIPasteControl): the person's tap reads this
/// device's clipboard without iOS asking, and what it read goes to the Mac (`sendClipboard`), pasted
/// there once the Mac has it while Paste on ‹Mac› Right Away is on. Disabled by the system while the
/// clipboard has no text. Its label is the system's ("Paste").
struct ClipboardPasteButton: View {
    @ObservedObject var client: StreamClient
    @AppStorage(StreamClient.pasteRightAwayKey) private var pasteRightAway = true

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            // On the main thread whatever queue the system hands it on.
            DispatchQueue.main.async { client.sendClipboard(strings) }
        }
        .buttonBorderShape(.capsule)
        .labelStyle(.titleAndIcon)
        .tint(Palette.accent)
        .accessibilityHint(ClipboardPolicy.Copy.pasteHint(mac: client.macName.isEmpty ? "the Mac" : client.macName,
                                                          device: StreamClient.deviceWord, rightAway: pasteRightAway))
    }
}

/// "Send Files to ‹Mac›…" in Settings › This iPad / This iPhone (Roadmap Item 8): opens the
/// system file picker and sends the chosen files to `~/Downloads/From ‹device›/` on the Mac.
struct SendFileRow: View {
    @ObservedObject var client: StreamClient
    let mac: String
    @State private var importing = false

    var body: some View {
        Button(action: { importing = true }) {
            HStack(spacing: 8) {
                Text("Send Files to \(mac)…")
                    .foregroundStyle(Palette.accent)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.doc")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                client.sendFileURLs(urls)
            }
        }
    }
}
