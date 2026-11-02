// Stacks.swift — shared builders for the layer stacks of §9.2 (D, M, R, K, G, A, C, I).
import SwiftUI

@MainActor
struct Env {
    let clips: ClipLibrary
    let portrait: CGImage?         // HT-C, the portrait harness screenshot, cropped to its interior (v3.1 only)
    let v3: V3Stills!              // v3: the harness screenshots and Mac previews of the new beats (V3.swift; v3.1 only)
    // v2: the Mac pane and HT-S left with the shared-settings shots (note 13).
    /// 0.6.0: its stills, pictures and the v3.1 film it quotes (Reel060.swift); nil for v3.1.
    var f: Footage060! = nil
    /// v4.1: film time and the shot's time map (Retime060.swift), set for each frame of a mapped 0.6 shot; nil otherwise.
    var clock: ShotClock? = nil
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

/// The type layer of a shot: several lines, each with its own snap, drawn as glyph outlines in one canvas.
/// `transform` moves the whole layer (canvas → canvas: a card's hold, S05's lift): move type with it, never with
/// SwiftUI's `.offset` or `.scaleEffect` around the layer, so typecheck knows where every glyph should be.
struct TypeLayer: View {
    let lines: [LineSpec]
    let t: Double
    var transform: CGAffineTransform = .identity
    /// Where the shot masks or covers this layer, in canvas coordinates (GlyphCanvas's `covered`).
    var covered: [CGRect] = []
    /// False for type that belongs to a picture (GlyphCanvas's `checked`).
    var checked = true

    init(lines: [LineSpec], t: Double, transform: CGAffineTransform = .identity, covered: [CGRect] = [], checked: Bool = true) {
        self.lines = lines; self.t = t; self.transform = transform; self.covered = covered; self.checked = checked
        // v4.1's `holds`: every line a shot builds, as it builds it (no rendering needed).
        if TypeRecorder.active && checked { TypeRecorder.layers.append((lines, t, TypeRecorder.opacity)) }
    }

    var body: some View {
        let nodes = lines.compactMap { TypeLine.node($0, t) }
        if TypeProbe.legacy {
            // REEL_TYPE_LEGACY=1 (comparison only): v3.1's SwiftUI Text, moved as v3.1 moved it, over the canvas
            // that records where the glyphs should be.
            ZStack(alignment: .topLeading) {
                Color.clear.canvas()
                ForEach(0..<lines.count, id: \.self) { i in LegacyTypeLine(spec: lines[i], t: t) }
            }
            .canvas()
            .transformEffect(transform)
            .overlay(GlyphCanvas(nodes: nodes, transform: transform, covered: covered, checked: checked))
        } else {
            GlyphCanvas(nodes: nodes, transform: transform, covered: covered, checked: checked)
        }
    }
}

func any<V: View>(_ v: V) -> AnyView { AnyView(v) }

/// v4.1's `holds` command (Holds060.swift): the type layers a frame's builder makes, recorded as it makes them, with the
/// opacity the shot fades them by from outside (S21–S23's card fade: `opacity`, set by the builder around its layer).
enum TypeRecorder {
    nonisolated(unsafe) static var active = false
    nonisolated(unsafe) static var layers: [(lines: [LineSpec], t: Double, opacity: Double)] = []
    nonisolated(unsafe) static var opacity = 1.0
}
