import AppKit

/// The status item's image: the app icon (Packaging/AppIcon.icon) reduced to a menu bar template.
/// The iPhone, held open sideways, as an outline; on its screen the iMac's screen as an outline, its
/// stand and its keyboard; the state shows on the iMac's screen: empty (idle), a dot (a device is
/// connected), a window (streaming), or a badge at the lower right (Sill needs attention). The icon's
/// home indicator and the keyboard's keys are left out: too small to see at this size.
///
/// Drawn in code from the icon's own coordinates (its layers' 1024 grid, as generated for
/// AppIcon.icon's Assets), so there is no asset to keep in sync, and marked as a template so the
/// menu bar tints it for light and dark bars and highlights it when the menu is open.
/// `symbolFallback` (SF Symbol macbook.and.iphone) is the stand-in if this drawing is ever
/// dropped; the previews render both side by side.
enum StatusGlyph {
    enum State: Equatable, CaseIterable { case idle, connected, streaming, attention }

    /// 18 pt tall, like the system's own items, and 20 wide to fit the square status item; the
    /// drawing is centred in both.
    static let size = NSSize(width: 20, height: 18)

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

    /// The drawing's extent: the iPhone, from (92, 124), 840 × 776.
    private static let extent = CGRect(x: 92, y: 124, width: 840, height: 776)
    /// Units → points: the extent in 20 × 17 pt at most, centred in the image.
    private static let scale: CGFloat = min(17 / extent.height, size.width / extent.width)
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

        // The iPhone: its outline, stroked inside the icon's 840 × 776 frame (corner radius 130).
        let border: CGFloat = 60                              // about 1.3 pt
        ctx.setLineWidth(border * scale)
        ctx.addPath(rounded(rect(92 + border / 2, 124 + border / 2, 840 - border, 776 - border), 130 - border / 2))
        ctx.strokePath()

        // The iMac: its screen's outline (the icon's 550 × 344, radius 40), stand and foot.
        let stroke: CGFloat = 50                              // about 1.1 pt
        let mac = rect(237, 262, 550, 344)
        ctx.setLineWidth(stroke * scale)
        ctx.addPath(rounded(mac.insetBy(dx: stroke / 2 * scale, dy: stroke / 2 * scale), 40 - stroke / 2))
        ctx.strokePath()
        ctx.fill(rect(512 - 30, 606, 60, 42))
        ctx.addPath(rounded(rect(512 - 100, 644, 200, 26), 13))
        ctx.fillPath()

        // Its keyboard, solid (the icon's 460 × 74; drawn 90 tall so it reads as more than a line).
        ctx.addPath(rounded(rect(512 - 230, 696, 460, 90), 20))
        ctx.fillPath()

        // The iMac's screen shows the state.
        let screen = mac.insetBy(dx: (stroke + 40) * scale, dy: (stroke + 40) * scale)
        switch state {
        case .connected:
            let d: CGFloat = 90 * scale
            ctx.fillEllipse(in: CGRect(x: screen.midX - d / 2, y: screen.midY - d / 2, width: d, height: d))
        case .streaming:
            ctx.addPath(rounded(screen, 20))
            ctx.fillPath()
        case .idle, .attention:
            break
        }

        // Attention: a dot at the lower right, cut out of whatever it overlaps.
        if state == .attention {
            let d: CGFloat = 8
            let dot = CGRect(x: size.width - d, y: size.height - d, width: d, height: d)
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: dot.insetBy(dx: -1.5, dy: -1.5))
            ctx.setBlendMode(.normal)
            ctx.fillEllipse(in: dot)
        }
    }
}
