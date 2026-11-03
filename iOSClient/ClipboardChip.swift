import SwiftUI
import StreamProtocol
import UniformTypeIdentifiers

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
        let images = ClipboardPolicy.hostTakesImages(client.hostClipboard)
        PasteButton(supportedContentTypes: images ? [.plainText, .image] : [.plainText]) { providers in
            Self.read(providers, images: images) { strings, image in
                // On the main thread whatever queue the system hands it on.
                DispatchQueue.main.async {
                    if let strings { client.sendClipboard(strings) } else { client.sendClipboardImage(image) }
                }
            }
        }
        .buttonBorderShape(.capsule)
        .labelStyle(.titleAndIcon)
        .tint(Palette.accent)
        .accessibilityHint(ClipboardPolicy.Copy.pasteHint(mac: client.macName.isEmpty ? "the Mac" : client.macName,
                                                          device: StreamClient.deviceWord, rightAway: pasteRightAway, images: images))
    }

    /// What the Paste control gave: its text when any item has some (as before), else its first image,
    /// fitted to the cap off the main thread (nil: none would fit).
    private static func read(_ providers: [NSItemProvider], images: Bool, done: @escaping @Sendable ([String]?, Data?) -> Void) {
        let texts = providers.filter { $0.canLoadObject(ofClass: String.self) }
        if !texts.isEmpty || !images {
            let group = DispatchGroup(), lock = NSLock()
            var strings = [String?](repeating: nil, count: texts.count)
            for (i, p) in texts.enumerated() {
                group.enter()
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    lock.lock(); strings[i] = s; lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .global()) { done(strings.compactMap { $0 }, nil) }
            return
        }
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
              let type = p.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            done([], nil)
            return
        }
        _ = p.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
            done(nil, data.flatMap { ClipboardImage.fitted($0) })
        }
    }
}
