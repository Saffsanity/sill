package me.saffer.sill.desktop

import me.saffer.sill.core.HevcSample
import me.saffer.sill.core.ImageBlob
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.JsonObj
import me.saffer.sill.core.Kind
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.ModelHost
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.StreamMessage
import me.saffer.sill.core.StreamSource
import me.saffer.sill.core.Viewport
import me.saffer.sill.core.ui.BarItem
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Size
import me.saffer.sill.core.ui.StreamLayout
import org.junit.jupiter.api.Tag
import java.awt.Color
import java.awt.Component
import java.awt.GraphicsEnvironment
import java.awt.Point
import java.awt.Rectangle
import java.awt.Robot
import java.awt.event.InputEvent as Awt
import java.awt.event.KeyEvent
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import javax.imageio.ImageIO
import javax.swing.SwingUtilities
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The Windows client's real windows on a display (Xvfb here), against the model Mac: the connect
 * window lists it and a click connects; the stream window places everything at StreamLayout's
 * rectangles for its size (1000×710, landscape, and 710×1000, the halves) and draws the iOS
 * app's colours; the drawer and the Settings panel open and close by click; an Aa drag changes the
 * text scale and sends a viewport; the trackpad moves the Mac's pointer; a click and typing in the
 * picture reach the Mac. Run with `-Dsun.java2d.uiScale=2` (uiTestHiDpi) the logical rectangles are
 * the same and the picture is decoded at twice the pixels; there the window is larger than the
 * screen, so it drives the controls through their own actions instead of the pointer.
 * Screenshots go to build/ui-shots.
 */
@Tag("ui")
class UiTest {
    private val hiDpi = (System.getProperty("sun.java2d.uiScale") ?: "1").toDouble() > 1.0
    private val tag = if (hiDpi) "-2x" else ""
    private val shots = File(System.getProperty("sill.shots") ?: "build/ui-shots").apply { mkdirs() }

    private fun shot(robot: Robot, name: String, r: Rectangle) {
        val img = robot.createMultiResolutionScreenCapture(r).resolutionVariants.maxByOrNull { it.getWidth(null) }!!
        val out = BufferedImage(img.getWidth(null), img.getHeight(null), BufferedImage.TYPE_INT_RGB)
        out.createGraphics().apply { drawImage(img, 0, 0, null); dispose() }
        ImageIO.write(out, "png", File(shots, "$name$tag.png"))
    }

    private fun <T> waitForValue(seconds: Double, what: String, f: () -> T?): T {
        val until = System.nanoTime() + (seconds * 1e9).toLong()
        while (System.nanoTime() < until) { f()?.let { return it }; Thread.sleep(30) }
        throw AssertionError("timed out waiting for $what")
    }

    private fun waitFor(seconds: Double, what: String, f: () -> Boolean) {
        val end = System.nanoTime() + (seconds * 1e9).toLong()
        while (!edt(f)) { if (System.nanoTime() > end) throw AssertionError("timed out: $what"); Thread.sleep(50) }
    }

    private fun <T> edt(f: () -> T): T { var r: T? = null; SwingUtilities.invokeAndWait { r = f() }; @Suppress("UNCHECKED_CAST") return r as T }

    private fun screen(c: Component, x: Double, y: Double): Point = edt { val p = c.locationOnScreen; Point(p.x + x.toInt(), p.y + y.toInt()) }

    private fun click(robot: Robot, p: Point, button: Int = Awt.BUTTON1_DOWN_MASK) { robot.mouseMove(p.x, p.y); robot.mousePress(button); robot.mouseRelease(button) }

    private fun near(a: Rect, b: Rectangle, what: String) =
        assertTrue(abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1, "$what: layout $a, drawn at $b")

    private fun sameColour(c: Color, want: Rgba, what: String) =
        assertTrue(abs(c.red - want.red) <= 3 && abs(c.green - want.green) <= 3 && abs(c.blue - want.blue) <= 3, "$what: ${Integer.toHexString(c.rgb)} against ${Integer.toHexString(want.rgb)}")

    @Test
    fun connectStreamAndEveryControl() {
        if (GraphicsEnvironment.isHeadless()) return
        val robot = Robot().apply { autoDelay = 20 }
        ModelHost(macName = "Studio", video = HevcSample.load("sample-motion.hevc"), frameIntervalMs = 33).use { host ->
            host.requirePairing = false
            val app = Main(KeyValueStore.Memory())
            SwingUtilities.invokeAndWait { me.saffer.sill.swingui.SillSwing.install(); app.start() }
            app.client.setFound(listOf(host.found("Studio")))
            waitFor(5.0, "the row") { app.frame.isShowing && app.rows.items.isNotEmpty() }
            Thread.sleep(400)
            shot(robot, "connect", edt { app.frame.bounds })
            // The column: ConnectLayout's 380 pt, centred.
            edt {
                val l = me.saffer.sill.core.ui.ConnectLayout(Size(app.connect.width.toDouble(), app.connect.height.toDouble()))
                val p = SwingUtilities.convertPoint(app.rows, 0, 0, app.connect)
                assertEquals(l.columnX.toInt(), p.x, "the column's x"); assertEquals(l.columnWidth.toInt(), app.rows.width, "the column's width")
            }
            sameColour(robot.getPixelColor(screen(app.connect, 4.0, 4.0).x, screen(app.connect, 4.0, 4.0).y), Rgba.black, "the connect screen")

            // Add a Mac's card in the column's place; Esc puts the rows back.
            if (!hiDpi) {
                val b = edt { SwingUtilities.convertRectangle(app.connect.addMac.parent, app.connect.addMac.bounds, app.connect) }
                click(robot, screen(app.connect, b.centerX, b.centerY))
                waitFor(2.0, "Add a Host's card") { app.connect.card == ConnectView.Card.Address && app.connect.address.isShowing }
                Thread.sleep(300)
                shot(robot, "addmac", edt { app.frame.bounds })
                robot.keyPress(KeyEvent.VK_ESCAPE); robot.keyRelease(KeyEvent.VK_ESCAPE)
                waitFor(2.0, "the rows again") { app.connect.card == ConnectView.Card.None && app.rows.isShowing }
            }

            // A click on the row: an open door, so the session starts at once.
            val key = edt { (app.rows.items.first() as me.saffer.sill.swingui.ListItem.Row).key }
            val row = edt { app.rows.rowBounds(key)!! }
            if (hiDpi) edt { app.rows.onPick(key) } else click(robot, screen(app.rows, row.midX, row.midY))
            waitFor(10.0, "the stream window") { app.stream?.isShowing == true }
            val hs = assertNotNull(host.latestSession())
            for (w in host.windows) {
                val img = BufferedImage(160, 100, BufferedImage.TYPE_INT_RGB).apply { createGraphics().apply { color = if (w.id == 101L) Color.ORANGE else Color.CYAN; fillRect(0, 0, 160, 100); dispose() } }
                val jpeg = ByteArrayOutputStream().also { ImageIO.write(img, "jpg", it) }.toByteArray()
                hs.send(StreamMessage(Kind.THUMBNAIL, 0.0, false, ImageBlob.encodeThumbnail(w.id, jpeg)))
            }
            val stream = app.stream!!
            waitFor(10.0, "a picture") { stream.video.videoW == 642 }

            // MARK: Landscape at 1000×710.
            edt { stream.setLocation(0, 0); stream.setContentSize(1000, 710) }
            waitFor(5.0, "the content at 1000×710") { stream.contentSize() == Size(1000.0, 710.0) && stream.streamLayout is StreamLayout.Landscape }
            Thread.sleep(800)
            edt {
                val l = StreamLayout.of(Size(1000.0, 710.0), phone = false, menus = true, spotlight = true)
                near(l.panel, stream.video.bounds, "the stream panel")
                near(l.items.getValue(BarItem.Apps), stream.apps.bounds, "Apps")
                near(l.items.getValue(BarItem.Strip), stream.strip.bounds, "the strip")
                near(l.items.getValue(BarItem.TextSize), stream.textSize.bounds, "Aa")
                near(l.items.getValue(BarItem.Keyboard), stream.keyboard.bounds, "Keyboard")
                near(l.items.getValue(BarItem.Desktop), stream.desktop.bounds, "Desktop")
                near(l.items.getValue(BarItem.Settings), stream.settingsButton.bounds, "Settings")
                near(l.items.getValue(BarItem.Menus), stream.menusButton.bounds, "Menus (the model Mac sends a top level)")
                near(l.ruler, stream.ruler.bounds, "the Aa ruler")
                // The picture is decoded at the panel's device pixels.
                val s = me.saffer.sill.swingui.SillSwing.deviceScale(stream.video)
                val (tw, _) = stream.video.targetPixels(stream.video.videoW, stream.video.videoH)
                assertTrue(abs(tw - stream.video.frameRect().w * s) <= 2, "decoded at ${tw} px for a ${stream.video.frameRect().w} pt frame at ${s}x")
            }
            if (!hiDpi) {
                Thread.sleep(300)
                shot(robot, "stream", edt { stream.contentPane.let { Rectangle(it.locationOnScreen, it.size) } })
                val bar = screen(stream.contentPane, edt { stream.apps.bounds.maxX + 6.0 }, 43.0)
                sameColour(robot.getPixelColor(bar.x, bar.y), Palette.bar, "the bar")
                val sb = edt { stream.settingsButton.bounds }
                val ctl = screen(stream.contentPane, sb.centerX, sb.y + 4.0)
                sameColour(robot.getPixelColor(ctl.x, ctl.y), Palette.control, "a bar button")
                val f = edt { stream.video.frameRect() }
                val v = edt { stream.video.bounds }
                val letterbox = when {
                    f.y >= 6 -> v.width / 2.0 to f.y / 2
                    f.x >= 6 -> f.x / 2 to v.height / 2.0
                    else -> null
                }
                if (letterbox != null) {
                    val p = screen(stream.video, letterbox.first, letterbox.second)
                    sameColour(robot.getPixelColor(p.x, p.y), Palette.panel, "the stream panel")
                } else println("UI: the picture fills the panel, no panel colour to sample")
            }

            // The Mac's menus: the button's menu lists the top level; File is read from the Mac when it opens.
            if (!hiDpi) {
                click(robot, screen(stream.contentPane, edt { stream.menusButton.bounds.centerX }, edt { stream.menusButton.bounds.centerY }))
                val popup = waitForValue(3.0, "the Menus popup") { edt { javax.swing.MenuSelectionManager.defaultManager().selectedPath.firstOrNull() as? javax.swing.JPopupMenu } }
                val titles = edt { popup.components.filterIsInstance<javax.swing.JMenu>().map { it.text } }
                assertEquals(listOf("Code", "File", "Edit", "Selection", "View", "Go", "Run", "Terminal", "Window", "Help"), titles)
                val file = edt { popup.components.filterIsInstance<javax.swing.JMenu>()[1] }
                click(robot, edt { Point(file.locationOnScreen.x + 20, file.locationOnScreen.y + file.height / 2) })
                waitFor(4.0, "File's items from the host") { file.menuComponents.any { (it as? javax.swing.JMenuItem)?.text?.trim() == "Save" } }
                Thread.sleep(400)
                shot(robot, "menus", edt { Rectangle(stream.contentPane.locationOnScreen, stream.contentPane.size) })
                val save = edt { file.menuComponents.first { (it as? javax.swing.JMenuItem)?.text?.trim() == "Save" } as javax.swing.JMenuItem }
                click(robot, edt { Point(save.locationOnScreen.x + 20, save.locationOnScreen.y + save.height / 2) })
                val press = host.latestSession()!!.presses.poll(4, java.util.concurrent.TimeUnit.SECONDS)
                assertEquals("2.6", press?.id, "Save chosen on the host")
                assertEquals("Save", press?.title)
            }

            // The drawer: Apps opens it at StreamLayout's rectangle; a click on the dim closes it.
            if (hiDpi) edt { stream.apps.onAction() } else click(robot, screen(stream.contentPane, edt { stream.apps.bounds.centerX }, edt { stream.apps.bounds.centerY }))
            waitFor(3.0, "the drawer") { stream.ui.state.drawerOpen && stream.drawer.isVisible }
            Thread.sleep(400)
            edt { near(StreamLayout.of(Size(1000.0, 710.0), phone = false, menus = true).drawer, stream.drawer.bounds, "the drawer") }
            if (!hiDpi) {
                shot(robot, "drawer", edt { Rectangle(stream.contentPane.locationOnScreen, stream.contentPane.size) })
                // Type-to-search: the field has the keys.
                robot.keyPress(KeyEvent.VK_T); robot.keyRelease(KeyEvent.VK_T)
                waitFor(2.0, "the search") { stream.drawer.search.text == "t" }
                click(robot, screen(stream.contentPane, 900.0, 600.0))
            } else edt { stream.ui.closeDrawer() }
            waitFor(3.0, "the drawer closed") { !stream.ui.state.drawerOpen && !stream.drawer.isVisible }

            // The Settings panel: from the Settings button, its width and place StreamLayout's; Done closes it.
            if (hiDpi) edt { stream.settingsButton.onAction() } else click(robot, screen(stream.contentPane, edt { stream.settingsButton.bounds.centerX }, edt { stream.settingsButton.bounds.centerY }))
            waitFor(3.0, "the panel") { stream.ui.state.settingsOpen && stream.settings.isVisible }
            Thread.sleep(500)
            edt {
                val want = StreamLayout.of(Size(1000.0, 710.0), phone = false, menus = true).settings
                val b = stream.settings.bounds
                near(Rect(want.x, want.y, want.width, b.height.toDouble()), b, "the Settings panel")
                assertTrue(b.height <= want.height + 1 && b.height > 200, "the panel's height ${b.height} of at most ${want.height}")
                assertTrue(stream.settings.body.componentCount >= 5, "the host's settings rows")
            }
            if (!hiDpi) {
                shot(robot, "settings", edt { Rectangle(stream.contentPane.locationOnScreen, stream.contentPane.size) })
                val d = edt { SwingUtilities.convertRectangle(stream.settings, stream.settings.done.bounds, stream.contentPane) }
                click(robot, screen(stream.contentPane, d.centerX, d.centerY))
            } else edt { stream.settings.done.onAction() }
            waitFor(3.0, "the panel closed") { !stream.ui.state.settingsOpen && !stream.settings.isVisible }
            // Esc closes it too (and is not the Mac's while something is open).
            edt { stream.ui.tapSettings() }
            waitFor(2.0, "the panel again") { stream.settings.isVisible }
            if (!hiDpi) { robot.keyPress(KeyEvent.VK_ESCAPE); robot.keyRelease(KeyEvent.VK_ESCAPE) } else edt { stream.closeTopmost() }
            waitFor(3.0, "Esc closed the panel") { !stream.ui.state.settingsOpen }

            // A thumbnail's lights (a hold, or a right-click): below it, Esc first closes them.
            if (!hiDpi) {
                val strip = edt { stream.strip.bounds }
                val t = edt { stream.strip.thumbBounds(101)!! }
                click(robot, screen(stream.contentPane, strip.x + t.midX, strip.y + t.midY), Awt.BUTTON3_DOWN_MASK)
                waitFor(2.0, "the lights") { stream.ui.state.windowMenu == 101L && stream.lights.isVisible }
                Thread.sleep(400)
                shot(robot, "lights", edt { Rectangle(stream.contentPane.locationOnScreen, stream.contentPane.size) })
                robot.keyPress(KeyEvent.VK_ESCAPE); robot.keyRelease(KeyEvent.VK_ESCAPE)
                waitFor(2.0, "the lights closed") { stream.ui.state.windowMenu == null && !stream.lights.isVisible }
            }

            // Aa: a drag of 100 pt to the right is two detents (44 a detent), 1.5×, and a viewport with it.
            if (hiDpi) edt { stream.textSize.onDown(); stream.textSize.onDrag(100.0); stream.textSize.onUp() }
            else {
                val aa = edt { stream.textSize.bounds }
                val from = screen(stream.contentPane, aa.centerX, aa.centerY)
                robot.mouseMove(from.x, from.y); robot.mousePress(Awt.BUTTON1_DOWN_MASK)
                for (i in 1..10) { robot.mouseMove(from.x + i * 10, from.y); Thread.sleep(15) }
                Thread.sleep(250)
                shot(robot, "ruler", edt { Rectangle(stream.contentPane.locationOnScreen, stream.contentPane.size) })
                robot.mouseRelease(Awt.BUTTON1_DOWN_MASK)
            }
            waitFor(2.0, "the text scale") { stream.ui.state.textScale == 1.5 && !stream.ui.state.scaleOpen }
            waitFor(3.0, "a viewport at 1.5×") {
                hs.all.filter { it.kind == Kind.VIEWPORT }.map { Viewport.fromJson(JsonObj.parse(it.payload)) }.any { it.scale == 1.5 && abs(it.width - 984.0) < 1 }
            }

            // A click in the middle of the picture, then typing: they reach the Mac (Esc as a key: nothing is open).
            if (!hiDpi) {
                val v = edt { stream.video.bounds }
                click(robot, screen(stream.contentPane, v.centerX, v.centerY))
                Thread.sleep(300)
                for (k in listOf(KeyEvent.VK_H, KeyEvent.VK_I)) { robot.keyPress(k); robot.keyRelease(k) }
                robot.keyPress(KeyEvent.VK_ESCAPE); robot.keyRelease(KeyEvent.VK_ESCAPE)
                waitFor(5.0, "input at the host") { hs.all.count { it.kind == Kind.INPUT } >= 6 }
                Thread.sleep(300)
                val inputs = hs.all.filter { it.kind == Kind.INPUT }.map { InputEvent.fromJson(JsonObj.parse(it.payload)) }
                val down = inputs.filterIsInstance<InputEvent.Pointer>().first { it.action == PointerAction.LEFT_DOWN }
                assertTrue(abs(down.x - 0.5) < 0.02 && abs(down.y - 0.5) < 0.02, "the click landed at $down")
                val texts = inputs.filterIsInstance<InputEvent.Text>().joinToString("") { it.text }
                assertTrue(texts == "hi", "typed '$texts' (all: $inputs)")
                assertTrue(inputs.any { it is InputEvent.Key && it.hidUsage == 0x29 && it.down }, "Esc as a key")
            }

            // MARK: The halves at 710×1000.
            edt { stream.setContentSize(710, 1000) }
            waitFor(5.0, "the halves") { stream.contentSize() == Size(710.0, 1000.0) && stream.streamLayout is StreamLayout.Halves }
            Thread.sleep(800)
            edt {
                val l = StreamLayout.of(Size(710.0, 1000.0), phone = false, menus = true, spotlight = host.latestSession()?.active == StreamSource.Desktop) as StreamLayout.Halves
                near(l.panel, stream.video.bounds, "the halves' picture")
                near(l.items.getValue(BarItem.Apps), stream.apps.bounds, "the halves' Apps")
                near(l.items.getValue(BarItem.Strip), stream.strip.bounds, "the halves' strip")
                near(l.items.getValue(BarItem.Settings), stream.settingsButton.bounds, "the halves' Settings")
                near(l.trackpad, stream.trackpad.bounds, "the trackpad")
                assertTrue(!stream.keyboard.isVisible, "no Keyboard button in the halves' bar (a key cap instead)")
                val caps = l.caps.flatten()
                assertEquals(caps.size, stream.caps.size, "the key caps")
                caps.zip(stream.caps).forEachIndexed { i, (r, c) -> near(r, c.second.bounds, "cap $i (${c.first.label})") }
            }
            val before = hs.all.size
            val (startX, startY) = edt { stream.padTracker.cursorX to stream.padTracker.cursorY }
            if (!hiDpi) {
                Thread.sleep(300)
                shot(robot, "halves", edt { stream.contentPane.let { Rectangle(it.locationOnScreen, it.size) } })
                val pad = edt { stream.trackpad.bounds }
                val well = screen(stream.contentPane, pad.x + 9.0 + 4, pad.y + 9.0 + 4)
                sameColour(robot.getPixelColor(well.x, well.y), Palette.trackpad, "the trackpad's well")
                // A stroke across the pad moves the Mac's pointer, relative, from where it was.
                val from = screen(stream.contentPane, pad.centerX, pad.centerY)
                robot.mouseMove(from.x, from.y); robot.mousePress(Awt.BUTTON1_DOWN_MASK)
                for (i in 1..12) { robot.mouseMove(from.x + i * 10, from.y); Thread.sleep(16) }
                robot.mouseRelease(Awt.BUTTON1_DOWN_MASK)
            } else edt {
                val t = System.nanoTime() / 1e9
                stream.padTracker.down(0, 100.0, 100.0, t)
                for (i in 1..12) stream.padTracker.move(0, 100.0 + i * 10, 100.0, t + i * 0.016)
                stream.padTracker.up(0, 220.0, 100.0, t + 0.25)
            }
            // Relative, from where the pad's cursor was (moves within 8 ms go as one, so the last is what counts).
            waitFor(3.0, "the pointer moved by the trackpad") {
                val moves = hs.all.drop(before).filter { it.kind == Kind.INPUT }.map { InputEvent.fromJson(JsonObj.parse(it.payload)) }
                    .filterIsInstance<InputEvent.Pointer>().filter { it.action == PointerAction.MOVE }
                moves.isNotEmpty() && moves.last().x - startX > 0.05 && abs(moves.last().y - startY) < 0.02
            }

            // Disconnect from the panel's foot: back to the connect window.
            edt { stream.ui.tapSettings() }
            waitFor(2.0, "the panel") { stream.settings.isVisible }
            Thread.sleep(400)
            if (hiDpi) edt { stream.settings.foot.onAction() }
            else {
                val f = edt { SwingUtilities.convertRectangle(stream.settings, stream.settings.foot.bounds, stream.contentPane) }
                click(robot, screen(stream.contentPane, f.centerX, f.centerY))
            }
            waitFor(5.0, "back to the connect window") { app.frame.isShowing && app.stream == null }
            Thread.sleep(300)
            println("UI$tag: ${hs.all.count { it.kind == Kind.INPUT }} input messages, ${hs.all.count { it.kind == Kind.VIEWPORT }} viewports; shots in $shots")
            shot(robot, "disconnected", edt { app.frame.bounds })
        }
    }
}
