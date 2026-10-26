import SwiftUI
import StreamProtocol

/// The clipboard's chip on a Mac (the iPhone and iPad app's ClipboardChip, in a Mac's own look): when
/// this Mac has new text on its clipboard as the viewer comes forward, "Paste on ‹Mac›" with the
/// system's Paste button, which reads it only when clicked, and Dismiss; after a Paste, a moment's
/// note. The rules are StreamClient+Clipboard's and ClipboardPolicy's, unchanged. The other Mac's
/// copies land on this Mac's clipboard by themselves.
struct MacClipboardChip: View {
    @ObservedObject var client: StreamClient
    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }

    var body: some View {
        ZStack {
            if let note = client.clipboardNote {
                Label(note.text, systemImage: note.warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false)
                    .accessibilityLabel(note.spoken)
                    .transition(.opacity)
            } else if client.clipboardChip {
                chip.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: client.clipboardChip)
        .animation(.easeOut(duration: 0.2), value: client.clipboardNote)
        .onChange(of: client.clipboardChip, initial: true) { _, shown in client.clipboardChipShown(shown) }
        .onDisappear { client.clipboardChipShown(false) }
    }

    private var chip: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(ClipboardPolicy.Copy.chipTitle(mac: mac)).font(.callout.weight(.semibold)).lineLimit(1)
                Text(ClipboardPolicy.Copy.chipSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ClipboardPolicy.Copy.chipSpoken(mac: mac, device: StreamClient.deviceWord))
            PasteButton(payloadType: String.self) { strings in
                DispatchQueue.main.async { client.sendClipboard(strings) }
            }
            .labelStyle(.titleAndIcon)
            Button { client.dismissClipboardChip() } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(ClipboardPolicy.Copy.dismiss)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}
