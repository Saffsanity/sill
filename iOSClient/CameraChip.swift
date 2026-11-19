import SwiftUI
import StreamProtocol

/// Share Camera's indicator over the stream (docs/camera-plan.md §6.1 point 9, §11; App Review 2.5.14: a clear sign
/// whenever the camera runs): "Camera" over "‹FaceTime› on ‹Mac›" with Stop while the camera runs for the Mac,
/// "Camera Paused" while the Mac wants it and it pauses, nothing otherwise (CameraPolicy.chip). In Full Screen the
/// camera symbol alone, read "Camera on". Placed by StreamScreen in the chip corner with the clipboard's chip, and
/// shown whatever else is over the stream but Settings, whose rows say it, the pairing overlay and the tour. Takes no
/// touch outside itself; Stop turns Share Camera off.
struct CameraChip: View {
    @ObservedObject var client: StreamClient
    /// Full Screen: the symbol alone.
    var compact = false

    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }

    /// What it shows now.
    static func chip(_ client: StreamClient) -> CameraPolicy.Chip {
        CameraPolicy.chip(offering: client.cameraLook.offering, state: client.cameraState, capturing: client.cameraLook.capturing)
    }

    var body: some View {
        let chip = Self.chip(client)
        ZStack(alignment: .trailing) {
            switch chip {
            case .none:
                EmptyView()
            case .on(let app):
                if compact { dot(on: true) } else { running(app: app) }
            case .paused:
                if compact { dot(on: false) } else { paused }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.easeOut(duration: 0.2), value: chip)
    }

    private func running(app: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(CameraPolicy.Copy.chipTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(CameraPolicy.Copy.chipDetail(app: app, mac: mac))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(-1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CameraPolicy.Copy.chipLabel(app: app, mac: mac))
            .accessibilityAddTraits(.isStaticText)
            Button(action: { client.stopSharingCamera() }) {
                Text(CameraPolicy.Copy.chipStop)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CameraPolicy.Copy.chipStopLabel)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Palette.bar))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var paused: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.slash.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(CameraPolicy.Copy.chipPaused)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule(style: .continuous).fill(Palette.bar))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CameraPolicy.Copy.chipPausedLabel)
        .accessibilityAddTraits(.isStaticText)
    }

    /// Full Screen: the camera symbol alone, on a small dark disc.
    private func dot(on: Bool) -> some View {
        Image(systemName: on ? "video.fill" : "video.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(on ? Color.green : Palette.muted)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(on ? CameraPolicy.Copy.chipFullScreenLabel : CameraPolicy.Copy.chipPausedLabel)
            .accessibilityAddTraits(.isStaticText)
    }
}
