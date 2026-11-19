import SwiftUI

/// Over the picture while this window records the stream (#284, docs/recording-plan.md; #303's RecordingBadge):
/// the count (3, 2, 1, large, spoken), then the light in the picture's top-leading corner, or its bottom-leading
/// one while the link's line shows across the top (the plan's "its corner by the link's line"): a red dot with
/// the movie's time and size ("0:42 · 126 MB", "· 4 min left" while space is low), "Starting…" until its first
/// picture. On screen whenever a recording runs, Full Screen included (App Review 2.5.14: a clear indication
/// while it records); never in the movie, which is the Mac's picture alone. Takes no touches.
struct RecordingLight: View {
    @ObservedObject var client: StreamClient
    var linkLineShown = false

    var body: some View {
        let r = client.recording
        switch r.phase {
        case .counting(let n):
            Text(RecordingPolicy.Copy.count(n))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityLabel(RecordingPolicy.Copy.countSpoken(n))
        case .starting, .recording:
            let seconds: Double? = r.phase == .recording ? r.seconds ?? 0 : nil
            HStack(spacing: 6) {
                Circle()
                    .fill(r.phase == .recording ? Color.red : Color.red.opacity(0.45))
                    .frame(width: 10, height: 10)
                Text(RecordingPolicy.Copy.light(seconds: seconds, bytes: r.bytes, minutesLeft: r.minutesLeft))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(r.minutesLeft == nil ? Color.white : Color.orange)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RecordingPolicy.Copy.lightSpoken(seconds: seconds, bytes: r.bytes, minutesLeft: r.minutesLeft))
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: linkLineShown ? .bottomLeading : .topLeading)
            .allowsHitTesting(false)
        case .idle, .finishing:
            EmptyView()
        }
    }
}

/// The note after a recording, over the stream in the clipboard chip's corner (never with the chip: the chip
/// waits while it shows), and on the connect screen after a session ended while recording.
struct RecordingNoteView: View {
    let note: RecordingNote

    var body: some View {
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
        .accessibilityLabel(note.text)
        .accessibilityAddTraits(.isStaticText)
    }
}
