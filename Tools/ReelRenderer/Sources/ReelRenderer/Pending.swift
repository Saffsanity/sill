// Pending.swift — placeholders for the three shots that need new real captures against Noah's Mac
// (CAPTURE-REQUEST.md). Each is a dark card reading "CAPTURE PENDING: <what>" inside the device frame the
// finished shot will use, with the shot's intended duration and a running clip clock, so the cut, the beats
// and the score can be judged before the footage exists. Nothing on these cards is meant for the release.
import SwiftUI

struct PendingShot {
    let id: String              // N1…N3 (CAPTURE-REQUEST.md)
    let what: String            // the card's headline
    let detail: String          // what the clip must show
    let file: String            // the file the capture agent writes (W/real-captures/…)
    let start: Double
    let duration: Double
    let portrait: Bool
}

enum Pending {
    static let n1 = PendingShot(id: "N1", what: "Window \u{2192} Desktop switch",
                                detail: "A window streams, Desktop is tapped, the Mac\u{2019}s Desktop arrives",
                                file: "real-captures/11-window-to-desktop.mov", start: 23.2, duration: 3.2, portrait: false)
    static let n2 = PendingShot(id: "N2", what: "Aa resizes a Mac window",
                                detail: "Weather or Clock re-lays out at a new Aa scale",
                                file: "real-captures/12-aa-resize.mov", start: 31.2, duration: 3.2, portrait: false)
    static let n3 = PendingShot(id: "N3", what: "Trackpad moves the pointer",
                                detail: "The arrow crosses a streamed window; no clicks",
                                file: "real-captures/13-trackpad-pointer.mov", start: 37.6, duration: 2.4, portrait: true)
}

/// The card on the device's screen, sized to its interior.
struct PendingCard: View {
    let shot: PendingShot
    let t: Double
    let size: CGSize

    var body: some View {
        let u = min(size.width, size.height) / 639            // 1 at the M45 device's short edge
        let clock = max(0, min(shot.duration, t - shot.start))
        ZStack {
            Color(hex: 0x0B0C10)
            // A faint diagonal hatch, so the card can never pass for a black stream frame.
            Canvas { ctx, sz in
                var p = Path()
                var x: CGFloat = -sz.height
                while x < sz.width { p.move(to: CGPoint(x: x, y: sz.height)); p.addLine(to: CGPoint(x: x + sz.height, y: 0)); x += 28 * u }
                ctx.stroke(p, with: .color(.white.opacity(0.035)), lineWidth: 1.5 * u)
            }
            RoundedRectangle(cornerRadius: 10 * u).strokeBorder(Color(hex: Palette.accent, alpha: 0.55),
                                                                  style: StrokeStyle(lineWidth: 2 * u, dash: [10 * u, 8 * u]))
                .padding(18 * u)
            VStack(spacing: 14 * u) {
                Text("CAPTURE PENDING \u{00B7} \(shot.id)")
                    .font(.system(size: 30 * u, weight: .semibold, design: .monospaced)).tracking(3 * u)
                    .foregroundStyle(Color(hex: Palette.accent))
                Text(shot.what)
                    .font(.system(size: 54 * u, weight: .bold)).tracking(-1 * u)
                    .foregroundStyle(Color(hex: Palette.text1))
                    .multilineTextAlignment(.center)
                Text(shot.detail)
                    .font(.system(size: 24 * u, weight: .regular))
                    .foregroundStyle(Color(hex: Palette.text2))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: size.width * 0.8)
                Text(String(format: "%@  \u{00B7}  %.1f / %.1f s", shot.file, clock, shot.duration))
                    .font(.system(size: 20 * u, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: Palette.text3))
                    .padding(.top, 6 * u)
                // The shot's length as a bar that fills with the clip clock.
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(Color(hex: Palette.accent, alpha: 0.8))
                        .frame(width: max(6 * u, 0.5 * size.width * CGFloat(clock / shot.duration)))
                }
                .frame(width: 0.5 * size.width, height: 6 * u)
            }
            .padding(.horizontal, 40 * u)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A pending landscape shot: device H, centred, near-frontal, with a slow push (the finished shot's framing).
@MainActor func pendingLandscape(_ p: PendingShot, _ t: Double) -> FrameLayers {
    let spec = DeviceSpec.H
    let k = ramp(t, p.start, p.start + p.duration)
    let v = deviceShot(spec: spec, center: CGPoint(x: 960, y: 540), yaw: lerp(2, 0, k), push: 1 + 0.03 * CGFloat(k),
                       image: nil, t: t, glow: 0.06,
                       screenOverlay: any(PendingCard(shot: p, t: t, size: spec.interior)))
    return FrameLayers(base: v)
}

/// A pending portrait shot: device P, whole and centred at 0.82 (the stream above, where the pointer moves,
/// and the trackpad below both in frame), standing on the sill at y 1024.
@MainActor func pendingPortrait(_ p: PendingShot, _ t: Double) -> FrameLayers {
    let spec = DeviceSpec.P
    let k = ramp(t, p.start, p.start + p.duration)
    let centre = CGPoint(x: 960, y: 540)
    let s: CGFloat = 0.82 * (1 + 0.02 * CGFloat(k))
    // deviceShot scales the device and its sill about the centre: y 1130 lands on 540 + 0.82 · 590 = 1024.
    let v = deviceShot(spec: spec, center: centre, yaw: lerp(-4, -2, k), push: s, pushAbout: centre,
                       image: nil, t: t, sill: (1130, 1400, 960), glow: 0.06,
                       screenOverlay: any(PendingCard(shot: p, t: t, size: spec.interior)))
    return FrameLayers(base: v)
}
