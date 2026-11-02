// Shots060Mac.swift — Act IV's first part: S18 (62.4–65.6), Sill for Mac on Intel, and the one cutaway, S19–S20
// (65.6–72.0), "Fixed in 0.6.0." (storyboard §3, Assets060Fixes.swift). The cutaway's type is drawn here as glyph
// outlines on its exact scroll path (GlyphCanvas), so typecheck measures every line of it; the bug, its touch dot and
// the line it becomes are Assets060Fixes.swift's.
import SwiftUI

// MARK: S18 · Intel

enum Intel060 {
    static let start = 62.4, end = 65.6
    static let headline = 62.45, sub = 63.25, foot = 63.65
}

@MainActor func s060_18(_ t: Double, _ e: Env) throws -> FrameLayers {
    let i = Intel060.self
    let lines = [LineSpec(Copy060.intel, .T1c, baseline: 158, snap: i.headline, holdEnd: i.end),
                 LineSpec(Copy060.intelSub, .T2, baseline: 222, snap: i.sub, holdEnd: i.end),
                 LineSpec(Copy060.intelFoot, .T3, baseline: 266, snap: i.foot, holdEnd: i.end, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: CGPoint(x: 960, y: 660))
        IntelIMac060(t: t, k: 1.06, center: CGPoint(x: 960, y: 668))
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S19–S20 · the fixes, and the bug

extension TypeStyle {
    /// The cutaway's fix lines: 44 px medium, white (storyboard §3).
    static let TF = TypeStyle(size: Fixes060.lineSize, weight: .medium, tracking: Fixes060.lineTracking, color: Palette.text1)
    /// Its group headers: T3's size in text.3.
    static let TFh = TypeStyle(size: Fixes060.headerSize, weight: .regular, tracking: 0, color: Palette.text3)
}

/// The column's type: the title (v3's snap, word by word), the headers and the lines, moved up by the scroll as one
/// layer (its `transform`), the lines and headers stepping back to 45 % with the squash and fading out (the column's
/// opacity). The top and bottom 140 px fade them out: there typecheck fits them but does not judge them (`covered`).
struct FixesType060: View {
    let t: Double
    static let bands = [CGRect(x: 0, y: 0, width: 1920, height: Fixes060.fade),
                        CGRect(x: 0, y: 1080 - Fixes060.fade, width: 1920, height: Fixes060.fade)]

    var body: some View {
        let F = Fixes060.self
        let scroll = CGAffineTransform(translationX: 0, y: -CGFloat(F.scroll(t)))
        var title = LineSpec(words: F.title, .T1s, x: F.columnX, baseline: F.titleBaseline, align: .leading,
                             snap: F.titleSnap, holdEnd: F.titleSnap)
        title.holdScale = false
        var nodes: [TypeNode] = []
        for p in F.placed {
            let y = F.titleBaseline + p.y
            let screen = y - CGFloat(F.scroll(t))
            guard screen > -80, screen < Stage.size.height + 80 else { continue }
            switch p.item {
            case .header(let s): nodes.append(StaticLine.node(s, .TFh, x: F.columnX, baseline: y, align: .leading))
            case .line(let s): nodes.append(StaticLine.node(s, .TF, x: F.columnX, baseline: y, align: .leading))
            }
        }
        let alpha = F.columnOpacity(t)
        return ZStack {
            if F.screenY(0, t) > -60, let n = TypeLine.node(title, t) {
                GlyphCanvas(nodes: [n], transform: scroll, covered: FixesType060.bands)
            }
            if alpha > 0.002 {
                GlyphCanvas(nodes: nodes, transform: scroll, opacity: alpha, covered: FixesType060.bands)
            }
        }
        .canvas()
    }
}

@MainActor func s060_19(_ t: Double, _ e: Env) throws -> FrameLayers {
    let F = Fixes060.self
    let fades = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: F.fade / Stage.size.height),
                                       .init(color: .white, location: 1 - F.fade / Stage.size.height), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom).canvas()
    let v = ZStack {
        Color.black
        ZStack {
            FixesType060(t: t)
            FixesColumn060(t: t, drawsType: false)
        }
        .canvas()
        .mask(fades)
        FixesLine060(t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}
