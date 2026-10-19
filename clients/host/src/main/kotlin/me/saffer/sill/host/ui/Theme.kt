package me.saffer.sill.host.ui

import me.saffer.sill.core.ui.Glyph
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.host.RowSymbol
import me.saffer.sill.swingui.SillSwing
import java.awt.BasicStroke
import java.awt.Color
import java.awt.Font
import java.awt.Graphics2D
import java.awt.geom.Ellipse2D
import java.awt.geom.Line2D
import java.awt.geom.Path2D
import java.awt.geom.RoundRectangle2D
import java.util.concurrent.TimeUnit

/**
 * Sill.app's look on the PC. Sill.app draws with AppKit's semantic colours (no palette of its own:
 * `.secondary`, `.orange`, the window's and the grouped Form's backgrounds, the menu's material), so
 * the host draws with those colours as macOS shows them in its dark and light appearances, chosen as
 * the PC's own appearance is: macOS 26's, as Sill.app's previews draw them (the window white or #171717,
 * a group's rows 3 % over it with no stroke, a button 8 % with no stroke; measured from
 * `-SillRenderPreviews`' pane-*.png and pairing-*.png). Sizes are AppKit's text styles (headline 13 semibold, body 13,
 * subheadline 11, caption and footnote 10) in points, 1 pt to 1 logical pixel (Java2D scales to the
 * display's DPI, as AppKit does to a Retina display).
 */
data class MacColors(
    val dark: Boolean,
    val window: Rgba,
    val groupBox: Rgba,
    val groupStroke: Rgba,
    val label: Rgba,
    val secondary: Rgba,
    val tertiary: Rgba,
    val separator: Rgba,
    val accent: Rgba,
    val onAccent: Rgba,
    val orange: Rgba,
    val menu: Rgba,
    val menuStroke: Rgba,
    val control: Rgba,
    val controlStroke: Rgba,
    val switchOff: Rgba,
    val knob: Rgba,
    val toolbarSelected: Rgba,
)

object HostTheme {
    /** NSColor's dark-appearance values: labelColor white 85 %, secondaryLabelColor 55 %, systemOrange #FF9F0A, controlAccentColor #0A84FF. */
    val darkColors = MacColors(
        dark = true,
        window = Rgba(0x171717), groupBox = Rgba.white.opacity(0.03), groupStroke = Rgba.white.opacity(0.0),
        label = Rgba.white.opacity(0.85), secondary = Rgba.white.opacity(0.55), tertiary = Rgba.white.opacity(0.25),
        separator = Rgba.white.opacity(0.05), accent = Rgba(0x0A84FF), onAccent = Rgba.white, orange = Rgba(0xFF9F0A),
        menu = Rgba(0x2B2B2D), menuStroke = Rgba.white.opacity(0.14), control = Rgba.white.opacity(0.08), controlStroke = Rgba.white.opacity(0.0),
        switchOff = Rgba.white.opacity(0.18), knob = Rgba(0xEDEDED), toolbarSelected = Rgba.white.opacity(0.1),
    )

    /** The light appearance: labelColor black 85 %, secondaryLabelColor 50 %, systemOrange #FF9500, controlAccentColor #007AFF. */
    val lightColors = MacColors(
        dark = false,
        window = Rgba(0xFFFFFF), groupBox = Rgba.black.opacity(0.031), groupStroke = Rgba.black.opacity(0.0),
        label = Rgba.black.opacity(0.85), secondary = Rgba.black.opacity(0.5), tertiary = Rgba.black.opacity(0.26),
        separator = Rgba.black.opacity(0.05), accent = Rgba(0x007AFF), onAccent = Rgba.white, orange = Rgba(0xFF9500),
        menu = Rgba(0xF2F2F2), menuStroke = Rgba.black.opacity(0.12), control = Rgba.black.opacity(0.08), controlStroke = Rgba.black.opacity(0.0),
        switchOff = Rgba.black.opacity(0.09), knob = Rgba.white, toolbarSelected = Rgba.black.opacity(0.07),
    )

    /** `-Dsill.appearance=dark|light`, else the PC's own setting, else dark. */
    val colors: MacColors by lazy { if (prefersDark()) darkColors else lightColors }
    @Volatile var override: MacColors? = null
    val c: MacColors get() = override ?: colors

    fun prefersDark(): Boolean {
        when (System.getProperty("sill.appearance")) { "dark" -> return true; "light" -> return false }
        val os = System.getProperty("os.name").lowercase()
        return if (os.startsWith("windows")) windowsDark() ?: true else linuxDark() ?: true
    }

    /** Settings › Personalisation › Colours › "Choose your app mode": AppsUseLightTheme 0 is dark. */
    private fun windowsDark(): Boolean? = run("reg", "query", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", "/v", "AppsUseLightTheme")
        ?.let { out -> Regex("AppsUseLightTheme\\s+REG_DWORD\\s+0x(\\d+)").find(out)?.groupValues?.get(1)?.let { it == "0" } }

    /** GNOME's (and most desktops' portal) color-scheme, then the GTK theme's name. */
    private fun linuxDark(): Boolean? {
        val scheme = run("gsettings", "get", "org.gnome.desktop.interface", "color-scheme")
        if (scheme != null) { if ("prefer-dark" in scheme) return true; if ("prefer-light" in scheme) return false }
        val theme = run("gsettings", "get", "org.gnome.desktop.interface", "gtk-theme") ?: System.getenv("GTK_THEME") ?: return null
        return "dark" in theme.lowercase()
    }

    private fun run(vararg cmd: String): String? = try {
        val p = ProcessBuilder(*cmd).redirectErrorStream(true).start()
        if (!p.waitFor(2, TimeUnit.SECONDS)) { p.destroyForcibly(); null } else if (p.exitValue() == 0) p.inputStream.readBytes().decodeToString() else null
    } catch (_: Exception) { null }
}

/** AppKit's text styles, at the PC's text scale (SillSwing.textScale). */
object MacType {
    val headline = TextStyle(13.0, TextStyle.Weight.Semibold)
    val body = TextStyle(13.0)
    val bodyMedium = TextStyle(13.0, TextStyle.Weight.Medium)
    val callout = TextStyle(12.0)
    val subheadline = TextStyle(11.0)
    val caption = TextStyle(10.0)
    val footnote = TextStyle(10.0)
    val toolbarLabel = TextStyle(11.0)
    fun font(s: TextStyle): Font = SillSwing.font(s)

    /** `.system(size: 22, weight: .medium, design: .monospaced)`: the code's digits. */
    val code: Font by lazy {
        val have = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().availableFontFamilyNames.toSet()
        val family = listOf("SF Mono", "Cascadia Mono", "Consolas", "JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono").firstOrNull { it in have } ?: Font.MONOSPACED
        Font(family, Font.PLAIN, 1).deriveFont((22 * SillSwing.textScale.coerceIn(1.0, 1.35)).toFloat())
    }
    val mono: Font by lazy { code.deriveFont(12f) }
}

/** Glyphs Sill.app shows that core's Symbol has no shape for (SF Symbols are Apple's alone), in its 24-unit box. */
object HostGlyphs {
    /** "macwindow". */
    val window = listOf(Glyph.RoundRect(2.5, 4.0, 19.0, 16.0, 2.5, 1.7), Glyph.Line(2.5, 8.5, 21.5, 8.5, 1.7),
        Glyph.Circle(5.3, 6.3, 0.75, null), Glyph.Circle(7.8, 6.3, 0.75, null), Glyph.Circle(10.3, 6.3, 0.75, null))
    /** "menubar.dock.rectangle". */
    val desktop = listOf(Glyph.RoundRect(2.0, 4.0, 20.0, 16.0, 2.5, 1.7), Glyph.Line(2.0, 7.5, 22.0, 7.5, 1.4), Glyph.RoundRect(6.5, 15.5, 11.0, 2.2, 0.8, null))
    /** "iphone". */
    val phone = listOf(Glyph.RoundRect(7.0, 2.0, 10.0, 20.0, 2.8, 1.7), Glyph.Line(10.5, 4.6, 13.5, 4.6, 1.4))
    /** "ipad". */
    val tablet = listOf(Glyph.RoundRect(4.0, 2.5, 16.0, 19.0, 2.4, 1.7), Glyph.Line(10.5, 19.2, 13.5, 19.2, 1.4))
    /** "pc": a laptop for the PC clients. */
    val computer = listOf(Glyph.RoundRect(4.5, 5.0, 15.0, 10.5, 1.6, 1.7), Glyph.Line(2.0, 18.5, 22.0, 18.5, 1.9))
    /** "ipad.and.iphone": Settings' Devices tab. */
    val devices = listOf(Glyph.RoundRect(2.0, 3.0, 13.0, 17.0, 2.0, 1.6), Glyph.RoundRect(13.5, 9.0, 8.5, 13.0, 2.0, 1.6))
    /** "play.rectangle": Settings' Streaming tab. */
    val stream = listOf(Glyph.RoundRect(2.0, 4.0, 20.0, 16.0, 3.0, 1.6), Glyph.Polygon(listOf(10.0 to 8.5, 16.0 to 12.0, 10.0 to 15.5), null))
    /** The menu's checkmark. */
    val check = listOf(Glyph.Polyline(listOf(5.5 to 12.5, 10.0 to 17.0, 18.5 to 7.0), 2.4))

    fun row(s: RowSymbol) = when (s) {
        RowSymbol.WINDOW -> window; RowSymbol.DESKTOP -> desktop; RowSymbol.PHONE -> phone
        RowSymbol.TABLET -> tablet; RowSymbol.COMPUTER -> computer
    }

    /** Shapes in a `box`-sized square at (x, y), as SillSwing.glyph draws a Symbol's. */
    fun paint(g: Graphics2D, shapes: List<Glyph>, x: Double, y: Double, box: Double, c: Rgba, background: Rgba = Rgba.black) {
        val k = box / 24.0
        val g2 = g.create() as Graphics2D
        g2.translate(x, y); g2.scale(k, k)
        for (shape in shapes) {
            g2.color = SillSwing.color(if (shape.cutout) background else c)
            val stroke = shape.stroke
            if (stroke != null) g2.stroke = BasicStroke(stroke.toFloat(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)
            val awt = when (shape) {
                is Glyph.Circle -> Ellipse2D.Double(shape.cx - shape.r, shape.cy - shape.r, shape.r * 2, shape.r * 2)
                is Glyph.Line -> Line2D.Double(shape.x1, shape.y1, shape.x2, shape.y2)
                is Glyph.RoundRect -> RoundRectangle2D.Double(shape.x, shape.y, shape.w, shape.h, shape.r * 2, shape.r * 2)
                is Glyph.Polygon -> Path2D.Double().apply { shape.points.forEachIndexed { i, p -> if (i == 0) moveTo(p.first, p.second) else lineTo(p.first, p.second) }; closePath() }
                is Glyph.Polyline -> Path2D.Double().apply { shape.points.forEachIndexed { i, p -> if (i == 0) moveTo(p.first, p.second) else lineTo(p.first, p.second) } }
            }
            if (stroke != null) g2.draw(awt) else g2.fill(awt)
        }
        g2.dispose()
    }

    fun paint(g: Graphics2D, s: Symbol, x: Double, y: Double, box: Double, c: Rgba, background: Rgba = Rgba.black) = paint(g, s.shapes, x, y, box, c, background)
}

fun Rgba.awt(): Color = SillSwing.color(this)
