// Clearance060.swift — `clearance`: how close the film's words come to what is drawn beside them (the 0.6.0 review's
// rule, v2 S23's: a column of words keeps 80 px or more from the edge of the device beside it).
//
// A frame is rendered twice without its finish, as typecheck renders it: with its type, recording every glyph as the
// canvases draw it (TypeProbe), and with the type canvases empty. For each line of type (its glyphs at half their
// opacity or more, none of them a picture's), its ink box; then, in the frame without type, over the line's rows and
// `band` px above and below them, the first column to the right of the ink, and the first to its left, where anything
// brighter than `level` in luma is drawn: a device's rim or screen, a macro's picture, a drawn keyboard. The gap is
// that column's distance from the ink. The summary gives each shot's smallest gap on either side, its line and frame,
// and every line under `min`.
import CoreImage
import Foundation
import SwiftUI

@MainActor
final class ClearanceChecker {
    struct Gap { let frame: Int; let shot: String; let line: String; let right: Double?; let left: Double? }

    var level: Float = 30.0 / 255
    /// The rows above and below a line that count (the drawing's px; × the output scale where it is measured).
    var band = 24
    private let with = Compositor()
    private let without = Compositor()
    private(set) var gaps: [Gap] = []

    private func luma(_ layers: FrameLayers, frame: Int, comp: Compositor) -> [Float] {
        var l = layers
        l.grain = false; l.vignette = false
        let dither = comp.dither
        comp.dither = false
        defer { comp.dither = dither }
        let img = comp.composeImage(l, frame: frame)
        // The 4K pass: measured at the output resolution, in its pixels.
        let W = Stage.pixelWidth, H = Stage.pixelHeight
        var px = [UInt8](repeating: 0, count: W * H * 4)
        comp.ci.render(img, toBitmap: &px, rowBytes: W * 4, bounds: CGRect(x: 0, y: 0, width: W, height: H),
                       format: .RGBA8, colorSpace: comp.sRGB)
        var y = [Float](repeating: 0, count: W * H)
        for i in 0..<(W * H) {
            y[i] = (0.2126 * Float(px[i * 4]) + 0.7152 * Float(px[i * 4 + 1]) + 0.0722 * Float(px[i * 4 + 2])) / 255
        }
        return y
    }

    func check(frame: Int, shot: String, _ build: () throws -> FrameLayers) rethrows {
        let probe = TypeProbe.shared
        let layers = try build()
        probe.begin()
        _ = luma(layers, frame: frame, comp: with)
        let glyphs = probe.end()
        probe.set { $0.hidden = true }
        let bare = luma(layers, frame: frame, comp: without)
        probe.set { $0.hidden = false }
        // Lines: a TypeLine's words are tagged "line#word", a StaticLine's by its text.
        var boxes: [String: CGRect] = [:]
        let k = Stage.scale
        for g in glyphs where g.opacity >= 0.5 && !g.picture {
            let name = g.tag.split(separator: "#").first.map(String.init) ?? g.tag
            // The glyph's box in output px (its path is in the drawing's points).
            let b = Stage.scaled ? g.outline.boundingBoxOfPath.applying(g.transform.concatenating(CGAffineTransform(scaleX: k, y: k)))
                                 : g.outline.boundingBoxOfPath.applying(g.transform)
            guard b.width > 0.5 * k, b.height > 0.5 * k else { continue }
            boxes[name] = boxes[name].map { $0.union(b) } ?? b
        }
        let W = Stage.pixelWidth, H = Stage.pixelHeight
        let band = self.band * Int(k)
        for (name, b) in boxes.sorted(by: { $0.key < $1.key }) {
            let y0 = max(0, Int(b.minY.rounded(.down)) - band), y1 = min(H - 1, Int(b.maxY.rounded(.up)) + band)
            // A line wholly off the frame (v5's cutaway title rising from under it) has nothing beside it.
            guard y0 <= y1 else { continue }
            let x1 = Int(b.maxX.rounded(.up)), x0 = Int(b.minX.rounded(.down))
            var right: Double?, left: Double?
            if x1 + 1 < W {
                rows: for x in (x1 + 1)..<W {
                    for y in y0...y1 where bare[y * W + x] > level { right = Double(x) - Double(b.maxX); break rows }
                }
            }
            if x0 - 1 > 0 {
                rows: for x in stride(from: x0 - 1, through: 0, by: -1) {
                    for y in y0...y1 where bare[y * W + x] > level { left = Double(b.minX) - Double(x + 1); break rows }
                }
            }
            gaps.append(Gap(frame: frame, shot: shot, line: name, right: right, left: left))
        }
    }

    /// Per shot: the smallest gap on each side (its line and frame), and every line closer than `min`.
    func summary(min: Double) -> (String, Bool) {
        var out = ""
        var ok = true
        let shots = Array(Set(gaps.map(\.shot))).sorted()
        for s in shots {
            let g = gaps.filter { $0.shot == s }
            let r = g.compactMap { x in x.right.map { (x, $0) } }.min { $0.1 < $1.1 }
            let l = g.compactMap { x in x.left.map { (x, $0) } }.min { $0.1 < $1.1 }
            out += String(format: "%@  right: %@   left: %@\n", s,
                          r.map { String(format: "%6.1f px (%@, %.3f s)", $0.1, $0.0.line, Double($0.0.frame) / 60) } ?? "   none",
                          l.map { String(format: "%6.1f px (%@, %.3f s)", $0.1, $0.0.line, Double($0.0.frame) / 60) } ?? "   none")
        }
        let close = gaps.filter { ($0.right ?? .infinity) < min || ($0.left ?? .infinity) < min }
        if !close.isEmpty {
            ok = false
            out += String(format: "closer than %.0f px: %d line-frames\n", min, close.count)
            var seen = Set<String>()
            for c in close where seen.insert("\(c.shot)|\(c.line)").inserted {
                let worst = close.filter { $0.shot == c.shot && $0.line == c.line }
                    .min { Swift.min($0.right ?? .infinity, $0.left ?? .infinity) < Swift.min($1.right ?? .infinity, $1.left ?? .infinity) }!
                out += String(format: "  %@ “%@”: %.1f px at %.3f s\n", c.shot, c.line,
                              Swift.min(worst.right ?? .infinity, worst.left ?? .infinity), Double(worst.frame) / 60)
            }
        }
        return (out, ok)
    }
}

/// `clearance [--from s] [--to s] [--every n] [--min px] [--level 0…255] [--band px]`: the words' gap to what is drawn
/// beside them (the summary above); exit 1 if a line comes closer than `--min` (80 px by default).
@MainActor
func clearanceCommand(args: [String]) throws {
    var from = 0.0, to = Stage.duration, every = 6, minGap = 80.0
    let checker = ClearanceChecker()
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--from": from = Double(args[i + 1])!; i += 2
        case "--to": to = Double(args[i + 1])!; i += 2
        case "--every": every = max(1, Int(args[i + 1])!); i += 2
        case "--min": minGap = Double(args[i + 1])!; i += 2
        case "--level": checker.level = Float(Double(args[i + 1])! / 255); i += 2
        case "--band": checker.band = Int(args[i + 1])!; i += 2
        default: i += 1
        }
    }
    let comp = Compositor()
    let env = try makeEnv(comp)
    let first = Int((from * 60).rounded()), last = min(Stage.frames, Int((to * 60).rounded())) - 1
    for f in stride(from: first, through: last, by: every) {
        // Each frame's autoreleased objects go with it (main.swift's render loop says why).
        try autoreleasepool { try checker.check(frame: f, shot: Timeline.shot(at: f).id) { try layers(frame: f, env: env) } }
    }
    // The 4K pass: the gaps are in output px, so the rule's 80 px of the drawing is 80 × scale.
    if Stage.scaled {
        print(String(format: "clearance at the output scale %.0f (%d×%d): gaps in output px, the minimum the drawing's %.0f px × %.0f = %.0f px",
                     Stage.scale, Stage.pixelWidth, Stage.pixelHeight, minGap, Stage.scale, minGap * Double(Stage.scale)))
        minGap *= Double(Stage.scale)
    }
    let (text, ok) = checker.summary(min: minGap)
    print(text, terminator: "")
    if !ok { exit(1) }
}
