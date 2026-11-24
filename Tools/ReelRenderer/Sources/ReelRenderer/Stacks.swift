// Stacks.swift — shared builders for the layer stacks of §9.2 (D, M, R, K, G, A, C, I).
import SwiftUI

@MainActor
struct Env {
    let clips: ClipLibrary
    let portrait: CGImage          // HT-C, the portrait harness screenshot, cropped to its interior
    let v3: V3Stills               // v3: the harness screenshots and Mac previews of the new beats (V3.swift)
    // v2: the Mac pane and HT-S left with the shared-settings shots (note 13).
}

/// Positive yaw brings the device's right side toward the lens; positive pitch its top edge.
let yawSign: Double = -1
let pitchSign: Double = 1

/// A device (with its shadow) whose outer box is centred at `center`; 3D per §3.3.
struct PlacedDevice<Content: View>: View {
    let spec: DeviceSpec
    let center: CGPoint
    var yaw: Double = 0
    var pitch: Double = 0
    var scale: CGFloat = 1
    @ViewBuilder var content: () -> Content

    var body: some View {
        let o = spec.outer
        let pad = ShadowCache.pad
        ZStack {
            DeviceView(spec: spec, shadow: true, content: content)
                .frame(width: o.width, height: o.height)
                .frame(width: o.width + 2 * pad, height: o.height + 2 * pad)
                .modifier(Tilt(yaw: yaw, pitch: pitch))
                .scaleEffect(scale)
                .position(x: center.x, y: center.y)
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
    }
}

struct Tilt: ViewModifier {
    let yaw: Double
    let pitch: Double
    func body(content: Content) -> some View {
        if abs(yaw) < 0.001 && abs(pitch) < 0.001 {
            content
        } else if abs(pitch) < 0.001 {
            content.rotation3DEffect(.degrees(yawSign * yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        } else {
            content
                .rotation3DEffect(.degrees(pitchSign * pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
                .rotation3DEffect(.degrees(yawSign * yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        }
    }
}

/// Scales a full-canvas view about a screen point.
extension View {
    func scaled(_ s: CGFloat, about p: CGPoint) -> some View {
        self.scaleEffect(s, anchor: UnitPoint(x: p.x / Stage.size.width, y: p.y / Stage.size.height))
    }
    func canvas() -> some View { self.frame(width: Stage.size.width, height: Stage.size.height) }
}

/// bg.0 plus the glow.
struct Backdrop: View {
    var color: Color = .black
    var glow: Double = 0.06
    var glowCenter = CGPoint(x: 960, y: 540)
    var body: some View {
        ZStack {
            color
            if glow > 0.0005 { Glow(center: glowCenter, opacity: glow) }
        }
        .canvas()
    }
}

/// The type layer of a shot: several lines, each with its own snap.
struct TypeLayer: View {
    let lines: [LineSpec]
    let t: Double
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.canvas()
            ForEach(0..<lines.count, id: \.self) { i in TypeLine(spec: lines[i], t: t) }
        }
        .canvas()
    }
}

func any<V: View>(_ v: V) -> AnyView { AnyView(v) }
