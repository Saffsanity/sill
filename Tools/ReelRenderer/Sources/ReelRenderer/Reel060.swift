// Reel060.swift — the 0.6.0 update video (REEL=060): its inputs, the stills it derives from them, its copy, and its
// timeline. The storyboard is ~/Downloads/sill-handoff/release-060/reel-0.6.0-storyboard.md (approved 2026-11-02);
// the shot list with the as-built numbers is design/reel/v5/SHOTLIST-0.6.0.md. v4.2 (design/reel/v4.2/) is v4 without the
// tour (S17, 59.2–62.4): 76.8 s, 48 bars at 150 BPM, 22 shots; S18–S23 play v4's frames 3.2 s earlier. Two of v4.1's words
// come with it (Noah): "0.6" for the version, and S05's footnote (Copy060.version, pasteFoot). v5 is v4.2 with Noah's notes
// on it (2026-11-03): 84.8 s, 53 bars, 22 shots, S12, S13, S15 and S16 grown by whole bars (`Cut060`).
//
// Inputs, under `reelDir` (REEL_DIR; the assemble step's `.build/reel060/input`):
// - `stills/`: harness screenshots of Sill 0.6.0 (origin/main c4a331f) on private simulators: the iPad mini's
//   2266×1488 px screen (its Mac picture at x 106–2159, y 188–1471: Device060/MacPicture060), the iPhone's 786×1704.
// - `pictures/`: the drawn Mac pictures (2880×1800) and the drawn iPad note pages (2266×1488) the stills show.
// - `v31film/Sill-sizzle-v3.1-silent.mp4`: the delivered v3.1 film, decoded only (ClipID.v31film): Weather's window
//   behind S07–S08 (Noah's decision (c)) and the movie QuickTime plays in S06.
// Six of the scenes stand in for Noah's takes A–F (storyboard §5): each is a swap-in point the shot list names.
import AppKit
import CoreImage
import SwiftUI

// MARK: - Copy (storyboard §2–§4; every line traced in its §7)

enum Copy060 {
    /// v5, Noah: "What's new (no period)".
    static let whatsNew = "What\u{2019}s new"
    /// v4.1 (carried into v4.2), Noah: "when showing the version number, go with 0.6 not 0.6.0 for aesthetic": the lockup,
    /// the end card, the footnotes and the cutaway's title say 0.6 (no line names the app's own version string).
    static let version = "0.6"
    // S04–S05
    static let copyMac = "Copy on your Mac.", pasteIPad = "Paste on your iPad."
    static let needsMac = "Needs Sill for Mac 0.6."
    static let copyIPad = "Copy on your iPad.", pasteMac = "Paste on your Mac."
    static let pasteSub = "Tap Paste in Sill. It lands where the cursor is."
    /// v4.1 (carried into v4.2), Noah: "last line of text should read - Text only, Shared Clipboard in settings turns it on
    /// or off": the setting's name in the app is Share Clipboard (whats-new-0.6.0.txt; the iPad's Settings panel and the
    /// Mac's General).
    static let pasteFoot = "Text only. Share Clipboard, in Settings, turns it on or off."
    // S06
    static let sound = "Sound from your Mac."
    static let soundSub = "The window you\u{2019}re using, a moment behind the picture."
    static let soundFoot = "A beta. Send Audio covers every device, and Mute silences one."
    // S07–S08
    static let locked = "Mac locked?", lockScreen = "Sill shows its lock screen."
    /// "And nothing else: no windows, apps, menus, sound or clipboard." on two lines, so it clears the iPad.
    static let lockSub = ["And nothing else: no windows,", "apps, menus, sound or clipboard."]
    static let unlock = "Unlock it from here."
    static let unlockSub = "Type your password on your iPad."
    static let unlockFoot = "Only a paired device can type at the lock screen."
    // S09
    static let pinch = "Pinch to zoom.", upTo5 = "Up to 5\u{00D7}."
    static let pinchSub = "Taps and clicks land on what you see."
    // S10
    static let larger = "Larger Picture.", upright = "On iPhone, held upright."
    /// "The picture reaches down to where the keyboard comes up." on two lines.
    static let largerSub = ["The picture reaches down to", "where the keyboard comes up."]
    static let largerFoot = "In Settings. The Desktop keeps the usual layout."
    // S11
    static let attach = "Attach a keyboard.", justType = "Just type."
    static let esc = ["Esc", "included."]
    static let escFoot = "No Keyboard button needed."
    // S12, v5 (Noah's three lines, verbatim): "Two-finger scroll. Or use a mouse wheel." on two lines; the hardware line on two
    // lines; Reverse Scrolling.
    static let scroll = "Two-finger scroll.", wheel = "Or use a mouse wheel."
    static let hardware = ["Hardware mouse and trackpad support", "including Magic Keyboard for iPad."]
    static let reverse = "And choose your direction with Reverse Scrolling."
    // S13
    static let greetings = ["\u{4F60}\u{597D}", "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}", "\u{C548}\u{B155}\u{D558}\u{C138}\u{C694}"]
    static let greetingLanguages = ["zh-Hans", "ja", "ko"]
    /// v5, Noah: "It should have the 3 different languages, then "Dictation" and then the subtext of "Compose here. It types
    /// on your Mac."" (v4.2's footnote, "Chinese, Japanese, Korean and more. Dictation too.", goes).
    static let dictation = "Dictation"
    static let composeSub = "Compose here. It types on your Mac."
    // S14
    static let tiles = "Every Mac, a tile."
    /// "Each as you last left it, in groups like Home and Work." on two lines.
    static let tilesSub = ["Each as you last left it,", "in groups like Home and Work."]
    static let tilesFoot = "Prefer a list? Tap beside Connect to a Mac."
    // S15
    static let aaOff = "Aa starts at Off."
    static let aaSub = "Slide back to Off, and the window goes back to its own size."
    static let aaFoot = "With Sill for Mac 0.6."
    // S16
    static let hold = "Hold a thumbnail.", halfSecond = "Controls in half a second."
    static let holdFoot = "Hold to Show Window Controls sets 0.2 to 2 seconds."
    // S18
    static let intel = "Sill for Mac now runs on Intel."
    static let intelSub = "Apple silicon or an Intel processor, macOS 14 or later."
    static let intelFoot = "Virtual Display and Send Audio are now on by default."
    // S21–S22
    static let wordmark = "Sill"
    static let freeOpen = "Free. Open source."
    static let appStore = "For iPhone and iPad on the App Store."
    // NOAH, 2026-11-03 03:15, for v5's end card (S22): add a third line, "getsill.app/contribute", under the
    // "For iPhone and iPad on the App Store." and "For Mac at getsill.app/download" lines, in their type (T5),
    // the same spacing, snapping after them (the legal line moves down to make room). Keep it in every build from now on.
    static let download = "For Mac at getsill.app/download"
    static let legal = ["Mac, iPad and iPhone are trademarks of Apple Inc., registered in the U.S. and other countries. App Store is a service mark of Apple Inc.",
                        "Intel is a trademark of Intel Corporation. Other names and apps shown belong to their owners."]
}

// MARK: - The inputs

/// The iPad mini's stills (2266×1488 px) and where their parts are.
enum Mini060 {
    static let source = Device060.miniSource
    /// The Mac's picture (16:10) with the Settings panel closed, measured on L0: x 106–2159, y 188–1471.
    static let picture = CGRect(x: 106, y: 188, width: 2054, height: 1284)
    /// The stream panel the picture is fitted in (its hairline at x 16–17), measured on L0 and L1.
    static let panel = CGRect(x: 16, y: 188, width: 2234, height: 1284)
    /// The first thumbnail (L0): its selection ring's box, its picture and its app badge.
    static let thumbRing = CGRect(x: 206, y: 10, width: 228, height: 152)
    static let thumbImage = CGRect(x: 216, y: 20, width: 208, height: 132)
    static let thumbBadge = CGRect(x: 204, y: 116, width: 48, height: 48)
    /// The bar's height (the bar is y 0–171; the panel starts at 188).
    static let bar: CGFloat = 172
}

/// The 0.6.0 reel's stills and pictures, the stills it derives from them, and v3.1's film.
@MainActor final class Footage060 {
    let ci: CIContext
    let clips: ClipLibrary
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private var full: [String: CGImage] = [:]
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []

    /// Every input the cut reads, checked at start so a missing one fails at once, not mid-render.
    static let required = [
        "stills/A1-te-select", "stills/A2-te-cursor", "stills/A3p-chip", "stills/A4-note-pasted",
        "pictures/ipad-notes-paste", "pictures/ipad-notes-copy", "pictures/ipad-notes-pasted",
        "stills/B1-qt", "stills/B4-sound-sendaudio", "stills/B3-sound-muted", "pictures/qt-play",
        "stills/L0-unlocked", "stills/L1-locked", "stills/C0-sheet", "pictures/sheet",
        "stills/D1-iphone-standard", "stills/D4-iphone-settings-off", "stills/D5-iphone-settings-on",
        "stills/D2-iphone-larger-1610", "stills/D3-iphone-larger-fitted",
        "stills/D2k-iphone-larger-1610-kbbutton", "stills/D3k-iphone-larger-fitted-kbbutton",
        "stills/E0-te-empty", "stills/E1-te-typed", "stills/E2-te-save", "stills/E3-longdoc0", "pictures/longdoc-page",
        "stills/E6-reverse-off", "stills/E7-reverse-on",
        "stills/E3u-longdoc0-upright", "stills/E6u-reverse-off-upright", "stills/E7u-reverse-on-upright",
        "stills/F0-cjk0", "stills/F1-cjk1", "stills/F2-cjk2", "stills/F3-cjk3", "stills/F4-cjk4",
        "stills/N1-tiles", "stills/N2-list", "stills/H1-scale125-open", "stills/H2-scaleoff-open",
        "stills/J1-windowmenu", "stills/J2-hold-row",
    ]

    init(ci: CIContext, clips: ClipLibrary) throws {
        self.ci = ci
        self.clips = clips
        for name in Footage060.required { _ = try image(name) }
    }

    private func remember(_ key: String, _ make: () throws -> CGImage) rethrows -> CGImage {
        if let hit = cache[key] { return hit }
        let img = try make()
        cache[key] = img
        order.append(key)
        if order.count > 120 { cache[order.removeFirst()] = nil }
        return img
    }

    /// An input at full size ("stills/A1-te-select", "pictures/sheet"), or a derived still ("derived/L0w", below).
    func image(_ name: String) throws -> CGImage {
        if let hit = full[name] { return hit }
        let img: CGImage
        if name.hasPrefix("derived/") {
            img = try derive(String(name.dropFirst("derived/".count)))
        } else {
            let url = reelDir.appendingPathComponent(name + ".png")
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let i = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw NSError(domain: "Reel060", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(url.path)"])
            }
            img = i
        }
        full[name] = img
        return img
    }

    /// `name` Lanczos-scaled to `width` px (its aspect kept), cached.
    func scaled(_ name: String, width: CGFloat) throws -> CGImage {
        let src = try image(name)
        let w = width.rounded()
        return try remember("\(name)|w\(Int(w))") { scale(src, CGFloat(w) / CGFloat(src.width)) }
    }

    /// The region `r` (top-left origin, in `name`'s px) Lanczos-scaled by `scale`, cached.
    func crop(_ name: String, _ r: CGRect, scale: CGFloat) throws -> CGImage {
        let src = try image(name)
        return try remember("\(name)|\(r)|\(String(format: "%.5f", scale))") {
            guard let c = src.cropping(to: r.integral) else { throw NSError(domain: "Reel060", code: 2) }
            return self.scale(c, scale)
        }
    }

    /// A CGImage Lanczos-scaled by `s` (sRGB), as V3Stills does.
    func scale(_ img: CGImage, _ s: CGFloat) -> CGImage {
        if abs(s - 1) < 1e-4 { return img }
        let w = (CGFloat(img.width) * s).rounded(), h = (CGFloat(img.height) * s).rounded()
        let out = CIImage(cgImage: img).applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: s, kCIInputAspectRatioKey: 1])
        return ci.createCGImage(out, from: CGRect(x: 0, y: 0, width: w, height: h), format: .BGRA8, colorSpace: srgb)!
    }

    /// v3.1's film at reel time `t` (its latest sample at or before), the whole 1920×1080 frame, scaled by `scale`.
    func film(_ t: Double, scale: CGFloat = 1) throws -> CGImage {
        try clips.image(.v31film, at: t, treatment: .none, scale: scale, crop: CGRect(x: 0, y: 0, width: 1920, height: 1080)).image
    }

    // MARK: Derived stills (composed once, at full size)

    /// A context of `size` px, top-left origin (y down), sRGB.
    private func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) throws -> Void) rethrows -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        try draw(ctx)
        return ctx.makeImage()!
    }

    /// Draws `img` upright into `r` (top-left origin) of a y-down context.
    static func put(_ ctx: CGContext, _ img: CGImage, in r: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        ctx.restoreGState()
    }

    /// A thumbnail in the bar redrawn (a y-down context of a 2266×1488 still): `img` filling the thumbnail's picture box by
    /// its height, inside its 18 px continuous corners, over the bar's own colour `gap`; then its app badge, the harness's
    /// two letters on the app's colour, drawn again over it.
    static func thumbnail(_ c: CGContext, _ img: CGImage, thumb: CGRect, badge b: CGRect, badgeColor: CGColor, letters: String, gap: CGColor,
                          scale: (CGImage, CGFloat) -> CGImage) {
        c.setFillColor(gap)
        c.addPath(CGPath(roundedRect: thumb.insetBy(dx: -2, dy: -2), cornerWidth: 20, cornerHeight: 20, transform: nil)); c.fillPath()
        c.saveGState()
        c.addPath(Path(roundedRect: thumb, cornerRadius: 18, style: .continuous).cgPath); c.clip()
        let th = thumb.height, tw = th * CGFloat(img.width) / CGFloat(img.height)
        put(c, scale(img, th / CGFloat(img.height)), in: CGRect(x: thumb.midX - tw / 2, y: thumb.minY, width: tw, height: th))
        c.restoreGState()
        c.setFillColor(gap)
        c.addPath(CGPath(roundedRect: b.insetBy(dx: -4, dy: -4), cornerWidth: 15, cornerHeight: 15, transform: nil)); c.fillPath()
        c.setFillColor(badgeColor)
        c.addPath(CGPath(roundedRect: b, cornerWidth: 11, cornerHeight: 11, transform: nil)); c.fillPath()
        let font = NSFont.systemFont(ofSize: 27, weight: .semibold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: letters, attributes: [.font: font, .foregroundColor: NSColor.white]))
        let lb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        c.saveGState()
        c.translateBy(x: b.midX - lb.midX, y: b.midY + lb.midY); c.scaleBy(x: 1, y: -1)
        c.textPosition = .zero
        CTLineDraw(line, c)
        c.restoreGState()
    }

    /// The colour of one pixel of `img` (top-left origin).
    func sample(_ img: CGImage, _ x: Int, _ y: Int) -> CGColor {
        var px = [UInt8](repeating: 0, count: 4)
        let c = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: srgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }

    private func derive(_ name: String) throws -> CGImage {
        switch name {
        case "weather":
            // v3.1's Weather window (S08, 15.9 s: the device frontal, the swipe settled), its stream picture measured at
            // x 273.5–1567.5, y 201.5–992.5 of the frame, cut to 16:10 inside its rounded edges (Noah's decision (c)),
            // its saved places renamed and its home and location labels painted out (the review: Retouch060.weather).
            return Retouch060.weather(try film(15.9).cropping(to: CGRect(x: 298, y: 207, width: 1246, height: 779))!)
        case "qtv":
            // QuickTime Player playing v3.1 at 5.2 s, inside what S06's movie plays (its open: the icon's iMac and window, no
            // words of the old reel; at 6.4 it is dark), titled "Sill.mp4": the picture "as you last left it" on S14's
            // tile and in the bars' QuickTime thumbnails.
            return QuickTime060.picture(frame: try film(5.2), movieTime: 5.2)
        case "N1x":
            // N1 (the tiles) with the Work tile's picture, Noah's MacBook Pro's, as qtv: its band is 175×92 pt (x 384–734,
            // y 1169–1353 px, measured), the picture filling it (scaledToFill, centred) inside the tile's 1 pt border and
            // its 12 pt top corners (ContentView.macTile).
            let n1 = try image("stills/N1-tiles"), q = try image("derived/qtv")
            return try canvas(n1.width, n1.height) { c in
                Footage060.put(c, n1, in: CGRect(x: 0, y: 0, width: n1.width, height: n1.height))
                let band = CGRect(x: 384, y: 1169, width: 350, height: 184)
                c.saveGState()
                let inner = band.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: 2)
                c.addPath(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                                 topTrailingRadius: 22, style: .continuous)
                    .path(in: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: band.maxY - inner.minY)).cgPath)
                c.clip()
                let h = band.width * CGFloat(q.height) / CGFloat(q.width)
                Footage060.put(c, scale(q, band.width / CGFloat(q.width)), in: CGRect(x: band.minX, y: band.midY - h / 2, width: band.width, height: h))
                c.restoreGState()
            }
        case "B1x":
            // B1 with its QuickTime thumbnail (the third, selected: picture x 696–904, y 20–152, as the first's on L0, 240 px
            // apart) as qtv's, and its badge "Qu" drawn again over it, as L0w's first thumbnail is.
            let b1 = try image("stills/B1-qt"), q = try image("derived/qtv")
            let thumb = Mini060.thumbImage.offsetBy(dx: 480, dy: 0), badge = Mini060.thumbBadge.offsetBy(dx: 480, dy: 0)
            let gap = sample(b1, 692, 60)
            return try canvas(b1.width, b1.height) { c in
                Footage060.put(c, b1, in: CGRect(x: 0, y: 0, width: b1.width, height: b1.height))
                Footage060.thumbnail(c, q, thumb: thumb, badge: badge, badgeColor: CGColor.hex(0x3A3D44), letters: "Qu", gap: gap, scale: { self.scale($0, $1) })
            }
        case "notes-selected":
            // The iPad's note with the reply selected, its drawn Copy callout painted out (the shots draw the edit menu
            // themselves, opaque, with its tail).
            let p = try image("pictures/ipad-notes-copy")
            return try canvas(p.width, p.height) { c in
                Footage060.put(c, p, in: CGRect(x: 0, y: 0, width: p.width, height: p.height))
                c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 150, y: 214, width: 196, height: 112))
            }
        case "E2sheet":
            // v5 (S11): the Save sheet and its shadow alone, from E2 over E1 (the same picture outside Keys060.sheetRegion):
            // inside the sheet's rounded rect its own pixels, opaque; outside it the shadow, black at the alpha that darkens E1
            // to E2; on its anti-aliased rim the two, by the rim's coverage. So the sheet slides with its shadow and nothing of
            // the window behind it (v4's rectangular crop slid a box of the window with it, which its 10 % dim hid).
            return Footage060.matte(over: try image("stills/E1-te-typed"), composite: try image("stills/E2-te-save"),
                                    region: Keys060.sheetRegion, box: picRect(Keys060.sheetBox),
                                    radius: 28 * Mini060.picture.width / 2880, srgb: srgb)
        case "D1x", "D2x", "D3x", "D2kx", "D3kx":
            // S10's iPhone stills with Aa at 1× (Retouch060.iphone); v5's D2k and D3k with row 1's Keyboard button lit.
            let src = ["D1x": "stills/D1-iphone-standard", "D2x": "stills/D2-iphone-larger-1610", "D3x": "stills/D3-iphone-larger-fitted",
                       "D2kx": "stills/D2k-iphone-larger-1610-kbbutton", "D3kx": "stills/D3k-iphone-larger-fitted-kbbutton"][name]!
            return Retouch060.iphone(try image(src), larger: name != "D1x", header: false)
        case "L0w":
            // L0 (the stream screen, unlocked) with Weather in the picture and on the first thumbnail, badge "We", and its
            // QuickTime thumbnail (the third) as qtv's.
            let l0 = try image("stills/L0-unlocked"), w = try image("derived/weather"), q = try image("derived/qtv")
            let gap = sample(l0, 212, 60)
            return try canvas(l0.width, l0.height) { c in
                Footage060.put(c, l0, in: CGRect(x: 0, y: 0, width: l0.width, height: l0.height))
                Footage060.put(c, w, in: Mini060.picture)
                Footage060.thumbnail(c, w, thumb: Mini060.thumbImage, badge: Mini060.thumbBadge, badgeColor: CGColor.hex(0x2F7BE0),
                                     letters: "We", gap: gap, scale: { self.scale($0, $1) })
                Footage060.thumbnail(c, q, thumb: Mini060.thumbImage.offsetBy(dx: 480, dy: 0), badge: Mini060.thumbBadge.offsetBy(dx: 480, dy: 0),
                                     badgeColor: CGColor.hex(0x3A3D44), letters: "Qu", gap: gap, scale: { self.scale($0, $1) })
            }
        case "L1x":
            // L1's bar (the locked Mac's: no thumbnails, no Menus) over L0's stream panel: 0.6.0 covers nothing while
            // this session's screen is locked (LockedMac.shade), the Mac streams its lock screen, which the shot draws
            // into the picture. L1's own picture is the harness's cover for a mock with no frame.
            let l0 = try image("derived/L0w"), l1 = try image("stills/L1-locked")
            return try canvas(l0.width, l0.height) { c in
                Footage060.put(c, l0, in: CGRect(x: 0, y: 0, width: l0.width, height: l0.height))
                c.saveGState(); c.clip(to: CGRect(x: 0, y: 0, width: l1.width, height: 188))
                Footage060.put(c, l1, in: CGRect(x: 0, y: 0, width: l1.width, height: l1.height))
                c.restoreGState()
            }
        case "L0p", "L1p":
            // L0w's and L1x's picture alone, with 8 px of the panel's black round it, transparent elsewhere (S07–S08's Weather
            // fading from under the lock screen over L0b/L1b: Shots060Clip.lockDevice).
            let src = try image(name == "L0p" ? "derived/L0w" : "derived/L1x")
            return try canvas(src.width, src.height) { c in
                c.clip(to: Mini060.picture.insetBy(dx: -8, dy: -8))
                Footage060.put(c, src, in: CGRect(x: 0, y: 0, width: src.width, height: src.height))
            }
        case "L0b", "L1b":
            // L0w and L1x with no picture: the stream panel's black where the Mac's picture was (under S07–S08's lock screen,
            // so none of the Weather can show round it: Shots060Clip.lockDevice).
            let src = try image(name == "L0b" ? "derived/L0w" : "derived/L1x")
            let black = sample(try image("stills/L0-unlocked"), 60, 800)
            return try canvas(src.width, src.height) { c in
                Footage060.put(c, src, in: CGRect(x: 0, y: 0, width: src.width, height: src.height))
                c.setFillColor(black); c.fill(Mini060.picture)
            }
        case "notes-plain":
            // The iPad's note before the Mac's line is pasted: "Sounds good, see you then." alone.
            let p = try image("pictures/ipad-notes-pasted")
            let white = sample(p, 1200, 460)
            return try canvas(p.width, p.height) { c in
                Footage060.put(c, p, in: CGRect(x: 0, y: 0, width: p.width, height: p.height))
                c.setFillColor(white); c.fill(CGRect(x: 140, y: 420, width: 700, height: 80))
            }
        case "B5-muted":
            // Mute on with Send Audio still in view: B4 (Send Audio on, Mute off) with B3's panel content (Mute on and
            // its footnote's "This iPad is muted.") from the Mute row down, aligned on that row (measured: 89 px), down to the scrolling part's end above the pinned Disconnect.
            let b4 = try image("stills/B4-sound-sendaudio"), b3 = try image("stills/B3-sound-muted")
            return try canvas(b4.width, b4.height) { c in
                Footage060.put(c, b4, in: CGRect(x: 0, y: 0, width: b4.width, height: b4.height))
                c.saveGState()
                c.clip(to: Footage060.b5Clip)
                Footage060.put(c, b3, in: CGRect(x: 0, y: Footage060.b5Shift, width: CGFloat(b3.width), height: CGFloat(b3.height)))
                c.restoreGState()
            }
        default:
            throw NSError(domain: "Reel060", code: 3, userInfo: [NSLocalizedDescriptionKey: "no derived still \(name)"])
        }
    }

    /// An overlay (an opaque rounded box and its black shadow) cut out of `composite` where it differs from `under`, in
    /// `region` (px of both): premultiplied RGBA of `region`'s size. In `box` (corners `radius`) the composite's own colour;
    /// outside it black at the alpha that darkens `under` to `composite` (by luminance); on the box's rim, its coverage (4×4
    /// samples) of the box's colour and the rest of the shadow.
    static func matte(over under: CGImage, composite: CGImage, region: CGRect, box: CGRect, radius: CGFloat, srgb: CGColorSpace) -> CGImage {
        let W = under.width, H = under.height
        func pixels(_ img: CGImage) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: W * H * 4)
            let c = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: srgb,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
            return buf
        }
        let a = pixels(under), b = pixels(composite)
        let r = region.integral
        let w = Int(r.width), h = Int(r.height), x0 = Int(r.minX), y0 = Int(r.minY)
        func lum(_ p: [UInt8], _ o: Int) -> Double { (0.2126 * Double(p[o]) + 0.7152 * Double(p[o + 1]) + 0.0722 * Double(p[o + 2])) / 255 }
        func inside(_ x: Double, _ y: Double) -> Bool {
            let rx = Double(radius), bx = box
            guard x >= Double(bx.minX), x <= Double(bx.maxX), y >= Double(bx.minY), y <= Double(bx.maxY) else { return false }
            let cx = min(max(x, Double(bx.minX) + rx), Double(bx.maxX) - rx), cy = min(max(y, Double(bx.minY) + rx), Double(bx.maxY) - rx)
            return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rx * rx
        }
        // The box's own colour: the median luminance pixel of a patch inside it, away from its controls.
        let patch = (0..<25).map { i -> Int in ((Int(box.minY) + 30 + i / 5) * W + Int(box.minX) + 30 + i % 5) * 4 }
        let s = patch.sorted { lum(b, $0) < lum(b, $1) }[12]
        let sheet = (Double(b[s]), Double(b[s + 1]), Double(b[s + 2])), sheetLum = lum(b, s)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let X = x0 + x, Y = y0 + y, o = (Y * W + X) * 4, q = (y * w + x) * 4
                var cov = 0.0
                for j in 0..<4 { for i in 0..<4 where inside(Double(X) + (Double(i) + 0.5) / 4, Double(Y) + (Double(j) + 0.5) / 4) { cov += 1 / 16 } }
                if cov >= 1 {
                    out[q] = b[o]; out[q + 1] = b[o + 1]; out[q + 2] = b[o + 2]; out[q + 3] = 255
                    continue
                }
                let lu = max(lum(a, o), 1e-3), lc = lum(b, o)
                // What of the shadow's darkening is left once the box's share is taken out.
                let keep = cov > 0 ? (lc - cov * sheetLum) / ((1 - cov) * lu) : lc / lu
                let shadow = min(max(1 - keep, 0), 1)
                let alpha = cov + (1 - cov) * shadow
                out[q] = UInt8((cov * sheet.0).rounded()); out[q + 1] = UInt8((cov * sheet.1).rounded()); out[q + 2] = UInt8((cov * sheet.2).rounded())
                out[q + 3] = UInt8((alpha * 255).rounded())
            }
        }
        let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// B5-muted's patch: B3's rows moved down by `b5Shift` into the panel's scrolling part below B4's Mute row.
    static let b5Shift: CGFloat = 89
    static let b5Clip = CGRect(x: 1504, y: 406, width: 716, height: 904)
}

// MARK: - Drawing the iPad mini's screen

/// One layer of an iPad mini's screen: a still (or a derived one) filling the screen, `opacity`, and an x offset in
/// screen widths (an app switch slides one screen over the other).
struct MiniLayer {
    var name: String
    var opacity: Double = 1
    var slide: CGFloat = 0
}

extension Footage060 {
    /// A still scaled to fill an interior of `width` px, at `fetch` × that (so a push of up to `fetch` stays ≤ 1:1).
    func screen(_ name: String, width: CGFloat, fetch: CGFloat = 1) throws -> CGImage {
        try scaled(name, width: width * fetch)
    }
}

/// An iPad mini's screen in its interior's coordinates: the layers (stills), then `overlay` (drawn in the
/// interior's px; `k` = interior px per still px), then the touch dots (in the stills' px).
struct MiniScreen<Overlay: View>: View {
    let size: CGSize
    let layers: [(CGImage, MiniLayer)]
    var dots: [TouchDotSpec] = []
    var t: Double
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            ForEach(0..<layers.count, id: \.self) { i in
                let (img, l) = layers[i]
                if l.opacity > 0.001 {
                    if l.slide == 0 {
                        Image(decorative: img, scale: 1).resizable().interpolation(.high)
                            .frame(width: size.width, height: size.height)
                            .opacity(l.opacity)
                    } else {
                        // Sliding (an app switch): on its exact path (ExactPicture060; an offset is rounded to whole px, and a
                        // picture under any transform to a quarter of one).
                        ExactPicture060(image: img, transform: CGAffineTransform(scaleX: size.width / CGFloat(img.width), y: size.height / CGFloat(img.height))
                            .concatenating(CGAffineTransform(translationX: l.slide * size.width, y: 0)), size: size)
                            .opacity(l.opacity)
                    }
                }
            }
            overlay()
            ForEach(0..<dots.count, id: \.self) { i in
                TouchDot(spec: dots[i], t: t, clipScale: size.width / dots[i].interiorWidth)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}

extension View {
    /// A camera move as one render transform: scales the full-canvas view by `s` about `from` and puts that point at
    /// `to` (no layout rounding, so a move glides).
    func camera(_ s: CGFloat, from: CGPoint, to: CGPoint) -> some View {
        transformEffect(CGAffineTransform(translationX: -from.x, y: -from.y)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: to.x, y: to.y)))
    }
}

/// A rect in a still's px → an interior's px (`k` interior px per still px).
func scaledRect(_ r: CGRect, _ k: CGFloat) -> CGRect { CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k) }

/// Where an interior point of an unturned device at `center` lands on the canvas.
func onCanvas(_ spec: DeviceSpec, center: CGPoint, _ p: CGPoint) -> CGPoint {
    CGPoint(x: center.x - spec.interior.width / 2 + p.x, y: center.y - spec.interior.height / 2 + p.y)
}

/// A touch dot in canvas px, drawn in screen space (for drawn controls in front of a device: S08's keyboard): its
/// diameter `d`.
struct CanvasDot: View {
    let at: Double
    let point: CGPoint
    let d: CGFloat
    let t: Double
    var body: some View {
        // TouchDot draws a 128-unit dot at point × clipScale: hand it the canvas point in those units.
        let cs = d / 128
        TouchDot(spec: TouchDotSpec(at: at, point: CGPoint(x: point.x / cs, y: point.y / cs), interiorWidth: 1), t: t, clipScale: cs)
            .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    }
}

// MARK: - The timeline (v5: 84.8 s, 53 bars; acts on bar lines at 0, 6.4, 28.8 and 67.2)

/// v5 (Noah's notes on v4.2, 2026-11-03): four scenes grown by whole bars where his new lines need room, and every scene after
/// each shifted by as much: S12 by two bars (40.8–47.2), S13 by one (47.2–53.6), S15 by one (57.6–62.4), S16 by one
/// (62.4–67.2). Every builder keeps its own time, as v4.2 handed them theirs (v4.2's for S01–S16, v4's for S18–S23, where v4.2
/// was v4 without its tour): a grown builder runs on past its old end, a shifted one is handed its old time, and the finish
/// (the grain and the dither, seeded by the frame) its old frame index, so every frame of a scene that did not change is the
/// frame it was. S12 (reshot) takes the film's time.
enum Cut060 {
    /// Where a stretch of the film comes from: its builders are handed the film's time less `shift` (and the finish the frame
    /// less `shift` × 60).
    enum Scene { case early, s13, s14s15, s16, close }
    struct Segment { let from: Double, to: Double, shift: Double, scene: Scene; var frames: Int { Int((shift * 60).rounded()) } }
    static let segments: [Segment] = [
        Segment(from: 0, to: 47.2, shift: 0, scene: .early),           // S01–S12 (S12 grown, 40.8–47.2, on the film's time)
        Segment(from: 47.2, to: 53.6, shift: 3.2, scene: .s13),        // S13: its builder's 44.0–50.4 (v4.2's 44.0–48.8 and a bar)
        Segment(from: 53.6, to: 62.4, shift: 4.8, scene: .s14s15),     // S14, 48.8–52.8; S15, 52.8–57.6 (v4.2's 52.8–56.0 and a bar)
        Segment(from: 62.4, to: 67.2, shift: 6.4, scene: .s16),        // S16: 56.0–60.8 (v4.2's 56.0–59.2 and a bar)
        Segment(from: 67.2, to: 84.8, shift: 4.8, scene: .close),      // S18–S23: v4's 62.4–80.0
    ]
    static func segment(_ t: Double) -> Segment { segments.last { t >= $0.from - 1e-9 } ?? segments[0] }
    /// The film's time → its builder's. On a frame (as the timeline hands it a time, frame ÷ 60), exactly the builder's time of
    /// the old frame, (f − shift × 60) ÷ 60: t − shift can differ from it in its last bit, and a builder's `t >= …` with it.
    static func builder(_ t: Double) -> Double {
        let s = segment(t)
        guard s.shift != 0 else { return t }
        let f = (t * 60).rounded()
        return abs(t * 60 - f) < 1e-6 ? (f - Double(s.frames)) / 60 : t - s.shift
    }
    /// A builder's time in `scene` → the film's (the score's cues, the motion check's paths, `holds`).
    static func film(_ t: Double, _ scene: Scene) -> Double { t + (segments.first { $0.scene == scene }?.shift ?? 0) }
    /// The film's frame → the frame the finish is seeded with: the old one.
    static func finish(_ f: Int) -> Int { f - segment(Double(f) / 60).frames }
}

@MainActor
enum Timeline060 {
    /// A builder handed its own time (Cut060).
    private static func held(_ b: @escaping @MainActor (Double, Env) throws -> FrameLayers) -> @MainActor (Double, Env) throws -> FrameLayers {
        { t, e in try b(Cut060.builder(t), e) }
    }
    static let shots: [Shot] = [
        // Act I · the open (0–6.4, 4 bars)
        Shot(id: "S01", start: 0.0, end: 2.4, source: "drawn (v3's close: glint, sill line, the lit icon)", clip: nil, build: s060_01),
        Shot(id: "S02", start: 2.4, end: 4.8, source: "drawn (v3's lockup)", clip: nil, build: s060_02),
        Shot(id: "S03", start: 4.8, end: 6.4, source: "type", clip: nil, build: s060_03),
        // Act II · the big three (6.4–28.8, 14 bars)
        Shot(id: "S04", start: 6.4, end: 10.4, source: "stand-in for take A part 1: stills A1, drawn notes; drawn keycaps", clip: nil, build: s060_04),
        Shot(id: "S05", start: 10.4, end: 14.4, source: "stand-in for take A part 2: drawn notes, stills A2, A3p, A4", clip: nil, build: s060_05),
        Shot(id: "S06", start: 14.4, end: 19.2, source: "stand-in for take B: still B1 + v3.1 1.6–6.4, B4, B5; drawn arcs", clip: nil, build: s060_06),
        Shot(id: "S07", start: 19.2, end: 24.0, source: "stills L0w, L1x; drawn lock screen", clip: nil, build: s060_07),
        Shot(id: "S08", start: 24.0, end: 28.8, source: "drawn lock screen and keyboard; stills L1x, L0w", clip: nil, build: s060_08),
        // Act III · on iPhone and iPad (28.8–67.2, 24 bars; v4's tour, S17, cut in v4.2)
        Shot(id: "S09", start: 28.8, end: 32.8, source: "stand-in for take C: still C0, picture sheet zoomed", clip: nil, build: s060_09),
        Shot(id: "S10", start: 32.8, end: 36.8, source: "stand-in for take D: stills D1, D4, D5, D2, D3", clip: nil, build: s060_10),
        Shot(id: "S11", start: 36.8, end: 40.8, source: "stand-in for take E part 1: stills E0, E1, E2; drawn keyboard", clip: nil, build: s060_11),
        Shot(id: "S12", start: 40.8, end: 47.2, source: "stand-in for take E part 2: still E3, picture longdoc-page; stills E6, E7", clip: nil, build: s060_12),
        Shot(id: "S13", start: 47.2, end: 53.6, source: "stand-in for take F: stills F0–F4", clip: nil, build: held(s060_13)),
        Shot(id: "S14", start: 53.6, end: 57.6, source: "stills N1, N2", clip: nil, build: held(s060_14)),
        Shot(id: "S15", start: 57.6, end: 62.4, source: "stills H1, H2; drawn Mac (v3)", clip: nil, build: held(s060_15)),
        Shot(id: "S16", start: 62.4, end: 67.2, source: "stills L0w, J1, J2; drawn hold ring", clip: nil, build: held(s060_16)),
        // Act IV · the Mac, the fixes, the close (67.2–84.8, 11 bars): v4's 62.4–80.0, each builder handed v4's time.
        Shot(id: "S18", start: 67.2, end: 70.4, source: "drawn (the icon's iMac)", clip: nil, build: held(s060_18)),
        Shot(id: "S19", start: 70.4, end: 75.2, source: "type (the fixes' column)", clip: nil, build: held(s060_19)),
        Shot(id: "S20", start: 75.2, end: 76.8, source: "drawn (the bug) + type", clip: nil, build: held(s060_19)),
        Shot(id: "S21", start: 76.8, end: 79.2, source: "drawn + type", clip: nil, build: held(s060_21)),
        Shot(id: "S22", start: 79.2, end: 82.4, source: "type", clip: nil, build: held(s060_21)),
        Shot(id: "S23", start: 82.4, end: 84.8, source: "—", clip: nil, build: held(s060_21)),
    ]
}

/// The contact sheet's tiles: one frame per shot that shows its point.
let sheetTimes060: [(String, Double)] = [
    ("S01", 1.9), ("S02", 4.2), ("S03", 5.6), ("S04", 8.9), ("S05", 13.3), ("S06", 17.9),
    ("S07", 22.4), ("S08", 25.05), ("S09", 30.2), ("S10", 35.9), ("S11", 39.35), ("S12", 43.4),
    ("S13", 51.1), ("S14", 55.5), ("S15", 60.6), ("S16", 65.0), ("S18", 68.5),
    ("S19", 72.8), ("S20", 76.05), ("S21", 78.5), ("S22", 82.0), ("S23", 84.0),
]
