// Retouch060.swift — the 0.6.0 reel's retouches of its stills (the review of 2026-11-02): words painted out over their
// own background and drawn again in the picture's own type, and the QuickTime Player picture redrawn.
//
// - v3.1's Weather window (behind S07–S08, and inside S06's and S14's QuickTime picture before this) carried Noah's
//   saved places, his home among them (its first card's location and home labels, the main pane's "HOME"). The places
//   are renamed (neutral cities in the same time zones, so the cards' times still agree) and the home and location
//   labels painted out (`weather`).
// - The iPhone stills of S10 read "This iPad" over Larger Picture (shot on an iPad simulator drawing the phone's
//   layout) and Aa "Off" in row 1, a state in which the Mac never fits the window to the taller picture: they read
//   "This iPhone" and "1×" (`iphone`).
// - QuickTime's title named an internal file ("Sill-sizzle-v3.1.mp4") and its controls a time from another shot: the
//   window is drawn again, titled "Sill.mp4", its elapsed time and progress those of the frame it shows (`QuickTime060`).
// Each paint-out fills the words' box from the background around it (per column, between the rows above and below, for
// these vertical gradients and flat fills), and the new words are Core Text in the face, size and colour fitted to the
// old ones (the fit: wt-reel/.build/reel060/fix/bin/textfit2).
import AppKit
import CoreText

enum Retouch060 {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An RGBA8 (premultiplied) copy of `img`, its first row the image's top.
    struct Pixels {
        var px: [UInt8]
        let w: Int, h: Int
        init(_ img: CGImage) {
            w = img.width; h = img.height
            px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { buf in
                let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: Retouch060.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        /// Fills `r` (whole px, top-left origin) column by column with the straight line between the pixel above it
        /// and the pixel below it.
        mutating func fillVertical(_ r: CGRect) {
            let x0 = max(0, Int(r.minX)), x1 = min(w - 1, Int(r.maxX) - 1)
            let y0 = max(1, Int(r.minY)), y1 = min(h - 2, Int(r.maxY) - 1)
            guard x0 <= x1, y0 <= y1 else { return }
            for x in x0...x1 {
                let a = ((y0 - 1) * w + x) * 4, b = ((y1 + 1) * w + x) * 4
                for y in y0...y1 {
                    let f = Double(y - y0 + 1) / Double(y1 - y0 + 2)
                    let i = (y * w + x) * 4
                    for c in 0..<4 { px[i + c] = UInt8((Double(px[a + c]) * (1 - f) + Double(px[b + c]) * f).rounded()) }
                }
            }
        }
        /// Fills `r` with one colour.
        mutating func fill(_ r: CGRect, _ c: (UInt8, UInt8, UInt8)) {
            for y in max(0, Int(r.minY))..<min(h, Int(r.maxY)) {
                for x in max(0, Int(r.minX))..<min(w, Int(r.maxX)) {
                    let i = (y * w + x) * 4
                    px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2; px[i + 3] = 255
                }
            }
        }
        func image() -> CGImage {
            let data = Data(px)
            let provider = CGDataProvider(data: data as CFData)!
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: Retouch060.srgb,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                           decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        }
    }

    enum Align { case inkLeft(CGFloat), center(CGFloat) }

    /// Draws `s` into a y-down context: `font` at `scale` (a 2× still draws an 11 pt label at 22 px with the 11 pt
    /// face's own optical size), its baseline at `baseline`, its ink's left edge or its advance's centre at x.
    static func text(_ ctx: CGContext, _ s: String, font: NSFont, scale: CGFloat = 1, color: CGColor, _ align: Align, baseline: CGFloat,
                     squeeze: CGFloat = 1) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let x: CGFloat
        switch align {
        case .inkLeft(let l): x = l - ink.minX * scale * squeeze
        case .center(let c): x = c - width * scale * squeeze / 2
        }
        ctx.saveGState()
        ctx.translateBy(x: x, y: baseline)
        ctx.scaleBy(x: scale * squeeze, y: -scale)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// A y-down context of `img`'s size with `img` drawn in it, handed to `draw`, made an image.
    static func over(_ img: CGImage, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.translateBy(x: 0, y: CGFloat(img.height)); ctx.scaleBy(x: 1, y: -1)
        draw(ctx)
        return ctx.makeImage()!
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    // MARK: Weather (v3.1's window, its 15.9 s frame cut to 1246×779 px)

    /// The places renamed in the same time zones (the cards' times stay true), the home and location labels gone.
    static func weather(_ img: CGImage) -> CGImage {
        var p = Pixels(img)
        // Measured on the cut (fix/look/weather.png): each name's ink box, its card's subtitle, the main pane's label.
        let paint: [CGRect] = [
            CGRect(x: 0, y: 140, width: 124, height: 25),     // the first card's place
            CGRect(x: 0, y: 168, width: 156, height: 17),     // the first card's location and home label
            CGRect(x: 760, y: 108, width: 60, height: 16),    // the main pane's "➚ HOME"
            CGRect(x: 700, y: 128, width: 180, height: 38),   // the main pane's place
            CGRect(x: 0, y: 267, width: 112, height: 24),     // the second card's place
            CGRect(x: 0, y: 397, width: 136, height: 25),     // the third card's place
            CGRect(x: 0, y: 524, width: 56, height: 22),      // the fourth card's place
            CGRect(x: 0, y: 652, width: 150, height: 23),     // the fifth card's place
        ]
        for r in paint { p.fillVertical(r) }
        let cityFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let white = rgb(240, 245, 249)
        return over(p.image()) { c in
            // Philadelphia at 7:04 PM, where the first card's place was: Eastern, as the place it replaces and as the main
            // pane's hourly row ("Now, 8PM, 9PM…") and the Eastern cards' 7:04 PM say (Cupertino's 4:04 PM, the first fix,
            // disagreed with that row).
            text(c, "Philadelphia", font: cityFont, color: white, .inkLeft(2), baseline: 158.5)
            text(c, "7:04 PM", font: NSFont.systemFont(ofSize: 13, weight: .medium), color: rgb(215, 217, 240), .inkLeft(2), baseline: 180.3)
            text(c, "Philadelphia", font: NSFont.systemFont(ofSize: 32, weight: .regular), color: rgb(243, 250, 255), .center(790.5), baseline: 156.3)
            text(c, "Chicago", font: cityFont, color: rgb(239, 245, 249), .inkLeft(3), baseline: 286.5)       // Central, as the place it replaces
            text(c, "Kingston", font: cityFont, color: rgb(241, 243, 250), .inkLeft(3), baseline: 416.5)      // Jamaica, as the place it replaces
            text(c, "Boston", font: cityFont, color: rgb(238, 241, 245), .inkLeft(3), baseline: 543)          // Eastern, as the place it replaces
            text(c, "Atlanta", font: cityFont, color: rgb(235, 237, 244), .inkLeft(2), baseline: 672)         // Eastern, as the place it replaces
        }
    }

    // MARK: S10's iPhone stills (786×1704 px: a 393×852 pt screen at 2×)

    /// Row 1's Aa reads "1×" (its value label's box, measured: D1, D4, D5 x 227–258 y 721–736; D2, D3, whose row has six
    /// buttons, x 314–345 y 931–946), the label in its own face (11 pt regular at 2×, fitted).
    /// `header`: "This iPad" over Larger Picture reads "This iPhone" (13 pt medium at 2×, fitted; its ink (164, 171, 181)).
    static func iphone(_ img: CGImage, larger: Bool, header: Bool) -> CGImage {
        var p = Pixels(img)
        let box = larger ? CGRect(x: 311, y: 928, width: 38, height: 22) : CGRect(x: 224, y: 718, width: 38, height: 22)
        p.fill(box, (35, 38, 44))
        if header { p.fill(Larger060.header, (20, 22, 25)) }
        return over(p.image()) { c in
            text(c, "1\u{00D7}", font: NSFont.systemFont(ofSize: 11, weight: .regular), scale: 2, color: rgb(196, 201, 209),
                 .center(larger ? 330 : 243), baseline: larger ? 947 : 737)
            if header {
                text(c, "This iPhone", font: NSFont.systemFont(ofSize: 13, weight: .medium), scale: 2, color: rgb(164, 171, 181),
                     .inkLeft(85), baseline: 933.5)
            }
        }
    }
}

// MARK: - QuickTime Player, drawn (S06; the tile in S14 and the thumbnail in S06's bar)

/// QuickTime Player's window playing a movie, as `tools/draw.swift` drew qt-play (2880×1800 px, a 1440×900 pt window at
/// 2×): the movie letterboxed at y 90–1710, the title bar over it (#1C1C1E at 85 %, the three lights, the title), the
/// controls (a #2C2C2E rounded bar at 82 %, the pause bars, the elapsed and total times, the progress) over it. Titled
/// "Sill.mp4", its elapsed time and progress the movie's own.
enum QuickTime060 {
    static let size = CGSize(width: 2880, height: 1800)
    static let movie = CGRect(x: 0, y: 90, width: 2880, height: 1620)
    static let title = "Sill.mp4"
    /// v3.1 runs 83.2 s ("1:23").
    static let length = 83.2

    static func elapsed(_ t: Double) -> String {
        let s = max(0, Int(t.rounded(.down)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// The chrome (no movie) into a y-down context whose units are the window's px.
    static func drawChrome(_ c: CGContext, movieTime: Double) {
        let W = size.width, H = size.height
        c.setFillColor(Retouch060.rgb(0x1C, 0x1C, 0x1E, 0.85)); c.fill(CGRect(x: 0, y: 0, width: W, height: 104))
        for (i, hex) in [(255, 95, 87), (254, 188, 46), (40, 200, 72)].enumerated() {
            c.setFillColor(Retouch060.rgb(hex.0, hex.1, hex.2)); c.fillEllipse(in: CGRect(x: 40 + CGFloat(i) * 52, y: 38, width: 28, height: 28))
        }
        Retouch060.text(c, title, font: NSFont.systemFont(ofSize: 34, weight: .semibold), color: Retouch060.rgb(0xE5, 0xE5, 0xEA),
                        .center(W / 2), baseline: 62.5)
        let bar = CGRect(x: W / 2 - 700, y: H - 220, width: 1400, height: 150)
        func round(_ r: CGRect, _ rad: CGFloat, _ col: CGColor) {
            c.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)); c.setFillColor(col); c.fillPath()
        }
        round(bar, 36, Retouch060.rgb(0x2C, 0x2C, 0x2E, 0.82))
        round(CGRect(x: bar.midX - 30, y: bar.minY + 26, width: 20, height: 60), 4, Retouch060.rgb(255, 255, 255))
        round(CGRect(x: bar.midX + 10, y: bar.minY + 26, width: 20, height: 60), 4, Retouch060.rgb(255, 255, 255))
        let track = CGRect(x: bar.minX + 160, y: bar.maxY - 44, width: 1080, height: 10)
        round(track, 5, Retouch060.rgb(255, 255, 255, 0.25))
        let p = CGFloat(min(1, max(0, movieTime / length)))
        if p * track.width >= 10 { round(CGRect(x: track.minX, y: track.minY, width: track.width * p, height: 10), 5, Retouch060.rgb(255, 255, 255, 0.9)) }
        let grey = Retouch060.rgb(0xD1, 0xD1, 0xD6)
        Retouch060.text(c, elapsed(movieTime), font: NSFont.systemFont(ofSize: 30), color: grey, .inkLeft(bar.minX + 41), baseline: 1694.5)
        Retouch060.text(c, "1:23", font: NSFont.systemFont(ofSize: 30), color: grey, .inkLeft(bar.maxX - 109), baseline: 1694.5)
    }

    /// The whole window: `frame` (a 1920×1080 movie frame) letterboxed, the chrome over it.
    static func picture(frame: CGImage, movieTime: Double) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: Retouch060.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.saveGState()
        ctx.translateBy(x: movie.minX, y: movie.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: movie.width, height: movie.height))
        ctx.restoreGState()
        drawChrome(ctx, movieTime: movieTime)
        return ctx.makeImage()!
    }
}
