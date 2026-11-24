// ReelRenderer v3.1 — the Sill sizzle reel's third version (SHOTLIST-v3.md), rendered with Apple frameworks only.
// A copy of v2's fourth cut (W/v2n1) with the remote beats (V3.swift), Act IV 8.0 s later and no camera dots.
// v3.1 (W/v31, a copy of W/v3's): S18's pointer drawn smooth (V31.swift); everything else is v3's.
//
//   ReelRenderer render [--out file.mp4] [--from s] [--to s] [--frames dir --every n] [--no-video]
//   ReelRenderer stills <dir> <t> [<t> …]          full frames at reel times (PNG)
//   ReelRenderer icon-check <reference.png> <out.png>
//   ReelRenderer score <out.m4a> [--wav out.wav]   the generated score (§10)
//   ReelRenderer mux <silent.mp4> <score.m4a> <out.mp4>
//   ReelRenderer sheet <movie.mp4> <out.png>       contact sheet (§11.1)
//   ReelRenderer verify <movie.mp4> [<silent.mp4>] format, blacks, silence, hero timing
//   ReelRenderer strip-edts <movie.mp4> …          remove the video track's identity edit list
//   ReelRenderer finalize [--cover p.png [--poster-out p.jpg]] <movie.mp4> …   no video elst, cover art, moov first
import AppKit
import AVFoundation
import CoreImage
import Foundation
import SwiftUI

@MainActor
func makeEnv(_ comp: Compositor) throws -> Env {
    ShadowCache.shared.ci = comp.ci
    IconShadows.shared.build(ci: comp.ci)
    let clips = ClipLibrary(ci: comp.ci)
    guard let portrait = loadStill(reelDir.appendingPathComponent("capture/final-portrait.png"),
                                   crop: CGRect(x: 322, y: 376, width: 1420, height: 2000), ci: comp.ci) else {
        throw NSError(domain: "Reel", code: 1, userInfo: [NSLocalizedDescriptionKey: "portrait still missing"])
    }
    return Env(clips: clips, portrait: portrait, v3: try V3Stills(ci: comp.ci))
}

@MainActor
func layers(frame i: Int, env: Env) throws -> FrameLayers {
    let t = Double(i) / Double(Stage.fps)
    let shot = Timeline.shot(at: i)
    return try shot.build(t, env)
}

@MainActor
func render(args: [String]) throws {
    // v3: never the delivered files in design/reel (first cut, v2-preview, v2 or v3); the working copy is W/v3/out.
    // v3.1: W/v31/out.
    var out = reelDir.appendingPathComponent("v31/out/silent.mp4")
    var from = 0.0, to = Stage.duration
    var framesDir: URL?
    var every = 12
    var video = true
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--out": out = URL(fileURLWithPath: args[i + 1]); i += 2
        case "--from": from = Double(args[i + 1])!; i += 2
        case "--to": to = Double(args[i + 1])!; i += 2
        case "--frames": framesDir = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 2
        case "--every": every = Int(args[i + 1])!; i += 2
        case "--no-video": video = false; i += 1
        default: i += 1
        }
    }
    let comp = Compositor()
    let env = try makeEnv(comp)
    if PointerArrow.noArrow { print("TEST: REEL_V31_NO_ARROW=1: S18 is drawn without its arrow (never a delivered render)") }
    if PointerArrow.flat { print("TEST: REEL_V31_FLAT=1: S18's picture is flat grey (never a delivered render)") }
    if PointerArrow.noGrain { print("TEST: REEL_V31_NO_GRAIN=1: no grain (never a delivered render)") }
    if let framesDir { try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true) }
    let first = Int((from * 60).rounded()), last = min(Stage.frames, Int((to * 60).rounded())) - 1
    let writer = video ? try VideoWriter(url: out) : nil
    let started = Date()
    var lastReport = Date()
    for f in first...last {
        var l = try layers(frame: f, env: env)
        if PointerArrow.noGrain { l.grain = false }
        if let writer {
            try writer.append(frame: f - first) { pb in comp.compose(l, frame: f, into: pb) }
        }
        if let framesDir, (f - first) % every == 0 || !video {
            if !video && (f - first) % every != 0 { continue }
            let img = comp.still(l, frame: f)
            writePNG(img, to: framesDir.appendingPathComponent(String(format: "f%04d-%@-%06.3f.png", f, Timeline.shot(at: f).id, Double(f) / 60)))
        }
        if Date().timeIntervalSince(lastReport) > 10 {
            lastReport = Date()
            let done = f - first + 1
            let rate = Double(done) / Date().timeIntervalSince(started)
            print(String(format: "  frame %d/%d (%@, %.2f s) · %.1f fps · eta %.0f s", f, last, Timeline.shot(at: f).id,
                         Double(f) / 60, rate, Double(last - f) / rate))
            fflush(stdout)
        }
    }
    if let writer { try writer.finish() }
    let secs = Date().timeIntervalSince(started)
    print(String(format: "rendered frames %d…%d in %.1f s (%.1f fps)%@", first, last, secs, Double(last - first + 1) / secs,
                 video ? " → \(out.path)" : ""))
    // Speed check data: every clip read, for §11.2 check 2.
    for (id, ts) in env.clips.reads.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        print("  reads \(id.rawValue): \(ts.count) frames, \(String(format: "%.3f", ts.min() ?? 0))…\(String(format: "%.3f", ts.max() ?? 0)) s")
    }
}

@MainActor
func stills(args: [String]) throws {
    let dir = URL(fileURLWithPath: args[0], isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let comp = Compositor()
    let env = try makeEnv(comp)
    let raw = args.contains("--no-finish")
    for a in args.dropFirst() {
        guard let t = Double(a) else { continue }
        let f = min(Stage.frames - 1, Int((t * 60).rounded()))
        let started = Date()
        var l = try layers(frame: f, env: env)
        if raw { l.grain = false; l.vignette = false }
        let img = comp.still(l, frame: f)
        let url = dir.appendingPathComponent(String(format: "still-%@-%06.3f.png", Timeline.shot(at: f).id, Double(f) / 60))
        writePNG(img, to: url)
        print(String(format: "%@ %.0f ms", url.lastPathComponent, Date().timeIntervalSince(started) * 1000))
    }
}

@MainActor
func iconCheck(args: [String]) throws {
    let comp = Compositor()
    _ = try makeEnv(comp)
    // The icon at 1024 px on black, unmasked by grain/vignette, compared with the qlmanage render.
    var st = IconState()
    st.camera = IconCamera(k: 1, anchorIcon: CGPoint(x: 512, y: 512), anchorScreen: CGPoint(x: 512, y: 512))
    let view = IconCanvas(s: st, part: .all, size: CGSize(width: 1024, height: 1024)).background(Color.black)
    let r = ImageRenderer(content: ZStack(alignment: .topLeading) { view }.frame(width: 1024, height: 1024, alignment: .topLeading))
    r.scale = 1
    guard let mine = r.cgImage else { print("render failed"); return }
    writePNG(mine, to: URL(fileURLWithPath: args[1]))
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[0]) as CFURL, nil),
          let ref = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("no reference"); return }
    func pixels(_ img: CGImage) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let ctx = CGContext(data: &buf, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        return buf
    }
    let a = pixels(mine), b = pixels(ref)
    // Inside the continuous squircle mask (radius 229): approximate with a rounded rect test.
    let mask = Path(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerRadius: 229, style: .continuous)
    var sum = 0.0, n = 0.0, worst = 0
    for y in stride(from: 0, to: 1024, by: 1) {
        for x in stride(from: 0, to: 1024, by: 1) where mask.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
            let i = ((1023 - y) * 1024 + x) * 4       // CG buffer rows run bottom-up
            for ch in 0..<3 {
                let d = abs(Int(a[i + ch]) - Int(b[i + ch]))
                sum += Double(d); n += 1; worst = max(worst, d)
            }
        }
    }
    print(String(format: "icon check: mean |Δ| %.2f/255 inside the mask (limit 3), worst %d", sum / n, worst))
}

// MARK: - Entry

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("usage: ReelRenderer render|stills|icon-check|score|mux|sheet|verify …"); exit(2)
}
do {
    switch command {
    case "render": try MainActor.assumeIsolated { try render(args: Array(args.dropFirst())) }
    case "stills": try MainActor.assumeIsolated { try stills(args: Array(args.dropFirst())) }
    case "icon-check": try MainActor.assumeIsolated { try iconCheck(args: Array(args.dropFirst())) }
    case "score": try Score.render(args: Array(args.dropFirst()))
    case "mux": try muxScore(args: Array(args.dropFirst()))
    case "sheet": try contactSheet(args: Array(args.dropFirst()))
    case "verify": try verify(args: Array(args.dropFirst()))
    case "strip-edts": for a in args.dropFirst() { try stripVideoEditList(URL(fileURLWithPath: a)) }
    case "finalize":
        // finalize [--cover poster.png [--poster-out poster.jpg]] <movie.mp4> …
        var rest = Array(args.dropFirst())
        var cover: Data?
        if let i = rest.firstIndex(of: "--cover") {
            cover = try jpegData(fromPNG: URL(fileURLWithPath: rest[i + 1]))
            rest.removeSubrange(i...(i + 1))
        }
        if let i = rest.firstIndex(of: "--poster-out") {
            if let cover { try cover.write(to: URL(fileURLWithPath: rest[i + 1])) }
            rest.removeSubrange(i...(i + 1))
        }
        for a in rest { try finalizeMP4(URL(fileURLWithPath: a), cover: cover) }
    default: print("unknown command \(command)"); exit(2)
    }
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
exit(0)
