import AppKit

/// The status item's image: the app icon (Packaging/AppIcon.icon) reduced to a menu bar template.
/// The Mac's screen is an outline (its stand left out), the iPhone lies sideways in front of its lower right
/// corner as in the icon, cut out of the Mac's line, and the state shows on the iPhone's screen:
/// empty (idle), a dot (a device is connected), a window (streaming), or a badge at the lower
/// right (Sill needs attention).
///
/// Drawn in code from the icon's own coordinates (its layers' 1024 grid, as generated for
/// AppIcon.icon's Assets), so there is no asset to keep in sync, and marked as a template so the
/// menu bar tints it for light and dark bars and highlights it when the menu is open.
/// `symbolFallback` (SF Symbol macbook.and.iphone) is the stand-in if this drawing is ever
/// dropped; the previews render both side by side.
enum StatusGlyph {
    enum State: Equatable, CaseIterable { case idle, connected, streaming, attention }

    /// 18 pt tall, like the system's own items, and 21 wide to fit the square status item; the
    /// drawing fills the width and is centred in the height.
    static let size = NSSize(width: 21, height: 18)

    static let symbolFallback: NSImage? = {
        let image = NSImage(systemSymbolName: "macbook.and.iphone", accessibilityDescription: "Sill")
        image?.isTemplate = true
        return image
    }()

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sill"
        return image
    }

    // MARK: Geometry, in the icon's units (1024 grid)

    /// The drawing's extent: the Mac's screen from (100, 214) to the iPhone's corner at (928, 782).
    private static let extent = CGRect(x: 100, y: 214, width: 828, height: 568)
    /// Units → points: the extent in 21 × 16 pt at most, centred in the image.
    private static let scale: CGFloat = min(16 / extent.height, size.width / extent.width)
    private static let offset = CGPoint(x: (size.width - extent.width * scale) / 2,
                                        y: (size.height - extent.height * scale) / 2)

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: (x - extent.minX) * scale + offset.x, y: (y - extent.minY) * scale + offset.y,
               width: w * scale, height: h * scale)
    }

    private static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let c = min(radius * scale, r.width / 2, r.height / 2)
        return CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil)
    }

    private static func draw(_ state: State, in ctx: CGContext) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)

        // The Mac: its screen's outline (stroked inside the icon's 600×400 frame). The icon's stand is
        // left out: the iPhone would cut it to a stub at this size.
        let stroke: CGFloat = 58                              // about 1.5 pt
        ctx.setLineWidth(stroke * scale)
        ctx.addPath(rounded(rect(100 + stroke / 2, 214 + stroke / 2, 600 - stroke, 400 - stroke), 60 - stroke / 2))
        ctx.strokePath()

        // The iPhone, sideways (the icon's 540×270), cut out of the Mac with a gap around it.
        let phone = rect(388, 512, 540, 270)
        let radius: CGFloat = 72
        let gap: CGFloat = 40                                 // about 1 pt
        ctx.setBlendMode(.clear)
        ctx.addPath(rounded(phone.insetBy(dx: -gap * scale, dy: -gap * scale), radius + gap))
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        let border: CGFloat = 50                              // about 1.25 pt
        ctx.setLineWidth(border * scale)
        ctx.addPath(rounded(phone.insetBy(dx: border / 2 * scale, dy: border / 2 * scale), radius - border / 2))
        ctx.strokePath()

        // Its screen shows the state.
        let screen = phone.insetBy(dx: (border + 34) * scale, dy: (border + 34) * scale)
        switch state {
        case .connected:
            let d: CGFloat = 70 * scale
            ctx.fillEllipse(in: CGRect(x: screen.midX - d / 2, y: screen.midY - d / 2, width: d, height: d))
        case .streaming:
            ctx.addPath(rounded(screen, 20))
            ctx.fillPath()
        case .idle, .attention:
            break
        }

        // Attention: a dot at the lower right, cut out of whatever it overlaps.
        if state == .attention {
            let d = size.height - phone.minY                  // as tall as the iPhone, so no corner peeks out
            let dot = CGRect(x: size.width - d, y: size.height - d, width: d, height: d)
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: dot.insetBy(dx: -1.5, dy: -1.5))
            ctx.setBlendMode(.normal)
            ctx.fillEllipse(in: dot)
        }
    }
}
