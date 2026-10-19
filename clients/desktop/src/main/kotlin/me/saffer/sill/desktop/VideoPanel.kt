package me.saffer.sill.desktop

import me.saffer.sill.core.CursorShape
import me.saffer.sill.core.FrameMapping
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Ui
import me.saffer.sill.swingui.SillComponent
import me.saffer.sill.swingui.SillSwing
import java.awt.Color
import java.awt.Graphics
import java.awt.GraphicsEnvironment
import java.awt.Image
import java.awt.Point
import java.awt.RenderingHints
import java.awt.Toolkit
import java.awt.geom.Path2D
import java.awt.image.BufferedImage
import java.awt.image.DataBufferInt
import java.awt.image.DirectColorModel
import java.awt.image.Raster
import javax.imageio.ImageIO
import javax.swing.JComponent

/**
 * The stream panel (StreamScreen.contentArea): Palette.panel behind the picture, corners 12, the
 * white 9 % hairline, the picture aspect-fit inside, drawn at device pixels (the decoder scales each
 * picture to [targetPixels]), and the one pointer sprite: the Mac's arrow while the Mac moves it,
 * this PC's own only for the portrait trackpad. The Mac's cursor shape is also this panel's cursor.
 */
class VideoPanel : SillComponent() {
    @Volatile private var image: BufferedImage? = null
    @Volatile var videoW = 0; private set
    @Volatile var videoH = 0; private set
    /** Where the Mac's pointer is (frame fractions) while the Mac moves it. */
    @Volatile var macPointer: Pair<Double, Double>? = null
    /** This PC's own pointer, from the portrait trackpad. */
    @Volatile var ownPointer: Pair<Double, Double>? = null
    @Volatile private var pointerImage: Image? = null
    private var pointerHot = Point(0, 0)

    init {
        isOpaque = true
        isFocusable = true
        focusTraversalKeysEnabled = false             // Tab goes to the Mac
        getAccessibleContext().accessibleName = "Stream"
    }

    /** Where the frame is drawn, in this view's coordinates. */
    fun frameRect() = FrameMapping.fit(videoW.toDouble(), videoH.toDouble(), width.toDouble(), height.toDouble())

    /** The device pixels the frame's rectangle covers: the size pictures are scaled to. */
    fun targetPixels(vw: Int, vh: Int): Pair<Int, Int> {
        if (vw <= 0 || vh <= 0 || width <= 0 || height <= 0) return vw to vh
        val scale = SillSwing.deviceScale(this)
        val r = FrameMapping.fit(vw.toDouble(), vh.toDouble(), width * scale, height * scale)
        return maxOf(2, r.w.toInt() and 1.inv()) to maxOf(2, r.h.toInt() and 1.inv())
    }

    fun show(p: HevcDecoder.Picture, vw: Int, vh: Int) {
        val raster = Raster.createPackedRaster(DataBufferInt(p.pixels, p.pixels.size), p.width, p.height, p.width, intArrayOf(0xFF0000, 0xFF00, 0xFF), null)
        image = BufferedImage(DirectColorModel(24, 0xFF0000, 0xFF00, 0xFF), raster, false, null)
        videoW = vw; videoH = vh
        repaint()
    }

    fun cursorShape(shape: CursorShape) {
        val img = try { ImageIO.read(shape.png.inputStream()) } catch (_: Exception) { null } ?: return
        // The PNG is the cursor's best representation (usually 2×); its size in Mac points is the shape's.
        val w = maxOf(1, shape.width.toInt()); val h = maxOf(1, shape.height.toInt())
        val scaled = img.getScaledInstance(w, h, Image.SCALE_SMOOTH)
        pointerImage = scaled
        pointerHot = Point(shape.hotX.toInt().coerceIn(0, w - 1), shape.hotY.toInt().coerceIn(0, h - 1))
        if (!GraphicsEnvironment.isHeadless()) {
            val tk = Toolkit.getDefaultToolkit()
            val best = tk.getBestCursorSize(w, h)
            val canvas = BufferedImage(maxOf(best.width, 1), maxOf(best.height, 1), BufferedImage.TYPE_INT_ARGB)
            canvas.createGraphics().apply { drawImage(scaled, 0, 0, null); dispose() }
            cursor = tk.createCustomCursor(canvas, Point(pointerHot.x.coerceAtMost(canvas.width - 1), pointerHot.y.coerceAtMost(canvas.height - 1)), "mac")
        }
        repaint()
    }

    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val r = Rect(0.0, 0.0, width.toDouble(), height.toDouble())
        // Black behind the corners (the stream screen's own colour in every layout), then the panel.
        g.color = Color.BLACK
        g.fillRect(0, 0, width, height)
        val clip = g.clip
        g.clip(SillSwing.round(r, Ui.panelRadius))
        SillSwing.fill(g, r, 0.0, Palette.panel)
        val img = image
        if (img != null) {
            val f = frameRect()
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
            // The picture is already at the frame's device pixels: drawn 1:1 under the display's scale.
            val s = SillSwing.deviceScale(this)
            val t = g.transform
            g.translate(f.x, f.y); g.scale(1 / s, 1 / s)
            g.drawImage(img, 0, 0, (f.w * s).toInt(), (f.h * s).toInt(), null)
            g.transform = t
            val p = macPointer ?: ownPointer
            if (p != null) {
                val (px, py) = FrameMapping.fromFrame(p.first, p.second, f)
                val pi = pointerImage
                if (pi != null) g.drawImage(pi, (px - pointerHot.x).toInt(), (py - pointerHot.y).toInt(), null)
                else arrow(g, px, py)
            }
        }
        g.clip = clip
        SillSwing.strokeBorder(g, r, Ui.panelRadius, Rgba.white.opacity(Ui.panelStrokeAlpha))
        g.dispose()
    }

    /** The arrow sprite before the Mac has sent its cursor's shape. */
    private fun arrow(g: java.awt.Graphics2D, x: Double, y: Double) {
        val p = Path2D.Double().apply {
            moveTo(x, y); lineTo(x, y + 17); lineTo(x + 4.2, y + 13); lineTo(x + 7, y + 19.5); lineTo(x + 9.6, y + 18.4)
            lineTo(x + 6.9, y + 12); lineTo(x + 12.4, y + 12); closePath()
        }
        g.color = Color.BLACK; g.fill(p)
        g.color = Color.WHITE; g.stroke = java.awt.BasicStroke(1.2f); g.draw(p)
    }
}
