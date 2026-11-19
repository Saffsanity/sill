import SwiftUI
import QuickLook
import StreamProtocol

/// The chip over the stream for files and photos (docs/files-plan.md §10), in the clipboard chip's corner, which
/// waits while this one shows (files first, then the clipboard: the overview's §2.3): a transfer to the Mac with
/// its percentage and Cancel; its end for a moment ("Saved in Downloads › Sill on ‹Mac›.", or why it stopped);
/// and a file shared into Sill, "Send ‹name› to ‹Mac›?" with Send and Cancel. From the Mac: its question ("‹Mac›
/// wants to send you…", Accept, Decline), this device's Get Files waiting for the Mac's panel, the percentage and
/// Cancel, and the end with Show (Quick Look, which carries the system's Share) and Save to Photos. Which transfer
/// shows when both directions have one is DeviceFilesCopy.chip's. Placed and hidden by StreamScreen; takes no
/// touch outside itself.
struct FileChip: View {
    @ObservedObject var client: StreamClient
    /// The kept file Quick Look shows (Show).
    @State private var preview: URL?

    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }

    /// Whether the chip shows: a transfer, its end, or a file shared into Sill, asked about while the session
    /// takes files and said why not while it cannot (an older Sill, its switch off, not paired). A locked Mac's
    /// cover says why on its own.
    static func shows(_ client: StreamClient) -> Bool {
        DeviceFilesCopy.chip(out: client.fileOut, incoming: client.fileIn) != .none
            || (client.filesShared != nil && client.filesOffering != .hidden)
    }

    var body: some View {
        let which = DeviceFilesCopy.chip(out: client.fileOut, incoming: client.fileIn)
        ZStack(alignment: .trailing) {
            if which == .incoming, let i = client.fileIn, i.phase == .asking || i.phase == .picking {
                incoming(i).transition(.opacity)
            } else if let shared = client.filesShared, client.filesOffering == .yes, !OutgoingFiles.holdsMoves(client.fileOut) {
                question(shared)
                    .transition(.opacity)
            } else if let shared = client.filesShared, [.older, .off, .notPaired].contains(client.filesOffering),
                      let why = DeviceFilesCopy.footnote(client.filesOffering, mac: mac, device: StreamClient.deviceWord) {
                blocked(shared, why)
                    .transition(.opacity)
            } else if which == .incoming, let i = client.fileIn {
                incoming(i).transition(.opacity)
            } else if which == .outgoing, let out = client.fileOut {
                if out.isOver { result(out).transition(.opacity) } else { running(out).transition(.opacity) }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.easeOut(duration: 0.2), value: client.fileOut?.serial)
        .animation(.easeOut(duration: 0.2), value: client.fileOut?.isOver)
        .animation(.easeOut(duration: 0.2), value: client.fileIn?.serial)
        .animation(.easeOut(duration: 0.2), value: client.fileIn?.isOver)
        .animation(.easeOut(duration: 0.2), value: client.filesShared)
        .quickLookPreview($preview, in: keptURLs)
    }

    /// The last transfer from the Mac's kept files, for Quick Look.
    private var keptURLs: [URL] {
        guard let i = client.fileIn, let folder = i.folder, case .done(let kept) = i.phase else { return [] }
        return kept.map { folder.appendingPathComponent($0) }
    }

    /// A transfer from the Mac, in its phase.
    @ViewBuilder private func incoming(_ i: IncomingFiles) -> some View {
        switch i.phase {
        case .asking: incomingQuestion(i)
        case .picking, .receiving: incomingRunning(i)
        case .done: incomingDone(i)
        case .stopped: incomingStopped(i)
        }
    }

    private func incomingQuestion(_ i: IncomingFiles) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(DeviceFilesCopy.incomingTitle(i, mac: mac, device: StreamClient.deviceWord))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Button(DeviceFilesCopy.decline) { client.declineIncoming() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Palette.muted)
            Button(DeviceFilesCopy.accept) { client.acceptIncoming() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Palette.accent)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .chipBackground()
        .accessibilityElement(children: .contain)
    }

    private func incomingRunning(_ i: IncomingFiles) -> some View {
        let title = DeviceFilesCopy.incomingTitle(i, mac: mac, device: StreamClient.deviceWord)
        let detail = DeviceFilesCopy.incomingDetail(i)
        return HStack(spacing: 10) {
            Image(systemName: i.phase == .picking ? "folder" : "arrow.down.doc")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                if i.phase == .receiving {
                    ProgressView(value: i.fraction)
                        .tint(Palette.accent)
                        .frame(maxWidth: 160)
                }
            }
            .layoutPriority(-1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(detail ?? "")
            .accessibilityAddTraits(.updatesFrequently)
            Button(action: { client.cancelIncoming() }) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(i.phase == .picking ? DeviceFilesCopy.cancelPickSpoken : DeviceFilesCopy.cancelReceivingSpoken)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .chipBackground()
        .accessibilityElement(children: .contain)
    }

    private func incomingDone(_ i: IncomingFiles) -> some View {
        let photos = i.photos
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(DeviceFilesCopy.incomingTitle(i, mac: mac, device: StreamClient.deviceWord))
                    .font(.footnote)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let r = client.photosResult {
                    Text(DeviceFilesCopy.photosLine(r))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(-1)
            Button(DeviceFilesCopy.show) { preview = keptURLs.first }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Palette.accent)
            if !photos.isEmpty, client.photosResult == nil {
                Button(DeviceFilesCopy.saveToPhotos(count: photos.count)) { client.saveToPhotos() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Palette.accent)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .chipBackground()
        .accessibilityElement(children: .contain)
    }

    private func incomingStopped(_ i: IncomingFiles) -> some View {
        let warns = DeviceFilesCopy.incomingWarns(i)
        let title = DeviceFilesCopy.incomingTitle(i, mac: mac, device: StreamClient.deviceWord)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: warns ? "exclamationmark.triangle.fill" : "xmark.circle")
                .foregroundStyle(warns ? Color.orange : Palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .chipBackground()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isStaticText)
    }

    private func running(_ out: OutgoingFiles) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.doc")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(DeviceFilesCopy.title(out, mac: mac, device: StreamClient.deviceWord))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = DeviceFilesCopy.detail(out, mac: mac) {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                if out.phase == .sending || out.phase == .finishing {
                    ProgressView(value: out.fraction)
                        .tint(Palette.accent)
                        .frame(maxWidth: 160)
                }
            }
            .layoutPriority(-1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DeviceFilesCopy.title(out, mac: mac, device: StreamClient.deviceWord))
            .accessibilityValue(DeviceFilesCopy.detail(out, mac: mac) ?? "")
            .accessibilityAddTraits(.updatesFrequently)
            Button(action: { client.cancelFiles() }) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DeviceFilesCopy.cancelSpoken)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .chipBackground()
        .accessibilityElement(children: .contain)
    }

    private func result(_ out: OutgoingFiles) -> some View {
        let warns = DeviceFilesCopy.warns(out)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: warns ? "exclamationmark.triangle.fill" : (out.phase.isDone ? "checkmark.circle.fill" : "xmark.circle"))
                .foregroundStyle(warns ? Color.orange : Palette.accent)
                .accessibilityHidden(true)
            Text(DeviceFilesCopy.title(out, mac: mac, device: StreamClient.deviceWord))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .chipBackground()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DeviceFilesCopy.title(out, mac: mac, device: StreamClient.deviceWord))
        .accessibilityAddTraits(.isStaticText)
    }

    /// A shared file this session cannot send: why (the rows' footnote's words), and Cancel.
    private func blocked(_ shared: FilesShared, _ why: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text(why)
                .font(.footnote)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)
            Button(action: { client.cancelShared() }) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Don’t send \(DeviceFilesCopy.what(shared.names))")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .chipBackground()
        .accessibilityElement(children: .contain)
    }

    private func question(_ shared: FilesShared) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(DeviceFilesCopy.sendShared(shared.names, mac: mac))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Button(DeviceFilesCopy.send) { client.sendShared() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Palette.accent)
            Button(action: { client.cancelShared() }) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DeviceFilesCopy.cancel)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .chipBackground()
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    /// The clipboard chip's capsule, its edge and its shadow.
    func chipBackground() -> some View {
        background(Capsule(style: .continuous).fill(Palette.bar))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
    }
}

private extension OutgoingFiles.Phase {
    var isDone: Bool { if case .done = self { return true }; return false }
}
