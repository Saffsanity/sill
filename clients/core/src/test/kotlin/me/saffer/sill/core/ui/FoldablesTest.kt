package me.saffer.sill.core.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The stream screen's layouts on real foldables, in dp, flat, half-open and folded: which
 * arrangement each gets, nothing interactive on the fold's band, nothing off the screen, and every
 * control at least 48 dp each way once the platform has grown a 44 dp cap into the 8 dp beside it.
 *
 * Sizes are the displays' pixels over Android's density for them (2.625 for Samsung's and Google's
 * default 420 dpi), rounded; GUESSED marks those not taken from a published spec (the Z Fold 8 is
 * the user's 4:3 inner display, not announced at these numbers). The fold's band is Android's least
 * (40 dp, the Duo's stand-in thickness) across the middle of the side the hinge runs along.
 */
class FoldablesTest {
    enum class Hinge { AlongHeight, AlongWidth }

    /** One screen of one device, upright as the device holds it natively, and where its hinge runs
     *  (AlongHeight: a fold down the screen as shown; AlongWidth: across it). Null: a cover screen. */
    data class Screen(val name: String, val width: Double, val height: Double, val phone: Boolean, val hinge: Hinge?)

    private val screens = listOf(
        // Galaxy Z Fold 8: a 4:3 inner display (GUESSED ~900×675 dp), the hinge down its middle when held as a book.
        Screen("Z Fold 8 inner, book", 675.0, 900.0, phone = false, hinge = Hinge.AlongHeight),
        Screen("Z Fold 8 inner, sideways", 900.0, 675.0, phone = false, hinge = Hinge.AlongWidth),
        Screen("Z Fold 8 cover", 411.0, 960.0, phone = true, hinge = null),               // GUESSED, as the Z Fold 7's 21:9 cover
        Screen("Z Fold 8 cover sideways", 960.0, 411.0, phone = true, hinge = null),
        // Z Fold 5 and 6: 2176×1812 px inner (~5:4), 904×2316 px cover (~23:9).
        Screen("Z Fold 5 inner, book", 690.0, 829.0, phone = false, hinge = Hinge.AlongHeight),
        Screen("Z Fold 5 inner, sideways", 829.0, 690.0, phone = false, hinge = Hinge.AlongWidth),
        Screen("Z Fold 5 cover", 344.0, 882.0, phone = true, hinge = null),
        Screen("Z Fold 5 cover sideways", 882.0, 344.0, phone = true, hinge = null),
        // Pixel Fold: 2208×1840 px inner, landscape-native; 1080×2092 px cover.
        Screen("Pixel Fold inner", 841.0, 701.0, phone = false, hinge = Hinge.AlongHeight),
        Screen("Pixel Fold inner upright", 701.0, 841.0, phone = false, hinge = Hinge.AlongWidth),
        Screen("Pixel Fold cover", 411.0, 797.0, phone = true, hinge = null),
        // Pixel 9 Pro Fold: 2076×2152 px inner (near square), 1080×2424 px cover.
        Screen("Pixel 9 Pro Fold inner, book", 791.0, 820.0, phone = false, hinge = Hinge.AlongHeight),
        Screen("Pixel 9 Pro Fold inner, sideways", 820.0, 791.0, phone = false, hinge = Hinge.AlongWidth),
        Screen("Pixel 9 Pro Fold cover", 411.0, 923.0, phone = true, hinge = null),
        // OnePlus Open: 2440×2268 px inner, 2484×1116 px cover (GUESSED density 2.8).
        Screen("OnePlus Open inner, book", 810.0, 871.0, phone = false, hinge = Hinge.AlongHeight),
        Screen("OnePlus Open inner, sideways", 871.0, 810.0, phone = false, hinge = Hinge.AlongWidth),
        Screen("OnePlus Open cover", 398.0, 887.0, phone = true, hinge = null),
        // Z Flip 6 and Moto Razr (2024): 1080×2640 px inner (22:9), the hinge across it; the Flip 5's 1080×2400.
        Screen("Z Flip 6 inner", 411.0, 1005.0, phone = true, hinge = Hinge.AlongWidth),
        Screen("Z Flip 6 inner sideways", 1005.0, 411.0, phone = true, hinge = Hinge.AlongHeight),
        Screen("Z Flip 5 inner", 411.0, 914.0, phone = true, hinge = Hinge.AlongWidth),
        Screen("Moto Razr inner", 413.0, 1013.0, phone = true, hinge = Hinge.AlongWidth),    // GUESSED density
        Screen("Moto Razr inner sideways", 1013.0, 413.0, phone = true, hinge = Hinge.AlongHeight),
    )

    /** The flip phones' covers: too short for the stream screen (GUESSED: Flip 6 720×748 px, Razr+ 1066×1056 px). */
    private val tinyCovers = listOf(Size(360.0, 374.0), Size(406.0, 402.0))

    private fun band(s: Screen): Rect? = when (s.hinge) {
        Hinge.AlongHeight -> Rect(s.width / 2 - 20, 0.0, 40.0, s.height)
        Hinge.AlongWidth -> Rect(0.0, s.height / 2 - 20, s.width, 40.0)
        null -> null
    }

    private fun on(r: Rect, s: Size) = r.minX >= -0.5 && r.minY >= -0.5 && r.maxX <= s.width + 0.5 && r.maxY <= s.height + 0.5 && r.width >= 0 && r.height >= 0
    private fun overlaps(a: Rect, b: Rect) = minOf(a.maxX, b.maxX) > maxOf(a.minX, b.minX) && minOf(a.maxY, b.maxY) > maxOf(a.minY, b.minY)

    /** What a person touches: the bar's buttons and strip, the caps, the trackpad, the drawer and the panel. */
    private fun touched(l: StreamLayout) = l.items.entries.map { it.key.name to it.value } +
        l.caps.flatten().map { "cap" to it } + listOfNotNull(l.trackpad?.let { "trackpad" to it }) +
        listOf("drawer" to l.drawer, "settings" to l.settings)

    private fun check(s: Screen, fold: FoldInfo, state: String) {
        val size = Size(s.width, s.height)
        val at = "${s.name} ($state, ${s.width.toInt()}×${s.height.toInt()})"
        val l = StreamLayout.of(size, phone = s.phone, menus = true, spotlight = true, fold = fold)
        for ((what, r) in touched(l) + listOf("panel" to l.panel)) if (!on(r, size)) fail("$at: $what $r is off the screen")
        assertTrue((l.trackpad?.height ?: 100.0) >= 60, "$at: trackpad ${l.trackpad}")
        assertTrue(l.panel.height >= 100 && l.panel.width >= 200, "$at: picture ${l.panel}")
        val b = fold.band
        if (b != null) {
            for ((what, r) in touched(l)) if (overlaps(r, b)) fail("$at: $what $r lies on the fold $b")
            if (fold.horizontalBand != null) assertTrue(l.panel.maxY <= b.minY, "$at: the picture ${l.panel} crosses the fold $b")
        }
        for ((item, r) in l.items) if (item != BarItem.Strip) assertTrue(r.width >= 48 && r.height >= 48, "$at: $item $r under 48 dp")
        assertTrue((l.items[BarItem.Strip]?.height ?: 48.0) >= 48, "$at: the strip")
        val gap = (l as? StreamLayout.Halves)?.metrics?.keyGap ?: PhonePortraitLayout.gap
        for (c in l.caps.flatten()) assertTrue(c.width + gap >= 48 && c.height + gap >= 48, "$at: a cap $c can't grow to 48 dp")
    }

    @Test fun everyFoldableFlatHalfOpenAndFolded() {
        for (s in screens) {
            check(s, FoldInfo.none, "flat")
            band(s)?.let { check(s, FoldInfo.known(it), "half-open") }
        }
    }

    @Test fun eachScreenGetsTheArrangementItsPostureAsks() {
        fun of(name: String, folded: Boolean): StreamLayout {
            val s = screens.first { it.name == name }
            return StreamLayout.of(Size(s.width, s.height), s.phone, fold = if (folded) FoldInfo.known(band(s)) else FoldInfo.none)
        }
        // The Z Fold 8's 4:3 inner display: upright the halves (an iPad's), sideways the bar.
        assertTrue(of("Z Fold 8 inner, book", false) is StreamLayout.Halves)
        assertTrue(of("Z Fold 8 inner, sideways", false) is StreamLayout.Landscape)
        // Half-open as a book: the halves keep to their pages; sideways in tabletop, split at the fold.
        val book = of("Z Fold 8 inner, book", true) as StreamLayout.Halves
        assertTrue(book.pages != null && book.caps.size == 2 && book.caps[0][0].minY == book.caps[1][0].minY)
        val table = of("Z Fold 8 inner, sideways", true) as StreamLayout.Halves
        assertEquals(317.0, table.half)                      // the picture above the band's top, 317.5, in whole points
        // Covers: the phone's arrangement upright, the compact bar sideways.
        assertTrue(of("Z Fold 8 cover", false) is StreamLayout.Phone)
        assertTrue(of("Z Fold 8 cover sideways", false) is StreamLayout.Landscape)
        // A flip phone: the phone's arrangement open flat, the halves half-open (picture above the hinge).
        assertTrue(of("Z Flip 6 inner", false) is StreamLayout.Phone)
        val flex = of("Z Flip 6 inner", true) as StreamLayout.Halves
        assertEquals(PortraitMetrics.compact, flex.metrics)
        // Sideways half-open (a book): the compact bar, clear of the fold.
        val side = of("Z Flip 6 inner sideways", true) as StreamLayout.Landscape
        assertTrue(side.book != null)
    }

    @Test fun theDuoIsUnchangedByAndroidsCases() {
        // The Duo's inner display in its book pose: the bar as DuoPosture.bookBar, nothing else.
        val s = Size(951.0, 669.0)
        val fold = FoldInfo.known(DuoPosture.standInFold(s))
        val l = StreamLayout.of(s, phone = false, fold = fold) as StreamLayout.Landscape
        val b = DuoPosture.bookBar(951.0, fold, 22.0, 12.0, 66.0, 64.0, 5, 360.0)
        assertEquals(b.stripWidth, l.items.getValue(BarItem.Strip).width)
        assertEquals(380.0, l.drawer.width)                   // 22 + 380 never reaches the fold at 455.5
        // Upright, the laptop pose: the picture above the fold, the controls below it.
        val up = Size(669.0, 951.0)
        val h = StreamLayout.of(up, phone = false, fold = FoldInfo.known(DuoPosture.standInFold(up))) as StreamLayout.Halves
        assertEquals(DuoPosture.PortraitSplit(455.0, 496.0), h.split)
        // No fold known: the middle, as before.
        assertEquals(500.0, (StreamLayout.of(Size(710.0, 1000.0), phone = false) as StreamLayout.Halves).half)
    }

    @Test fun flipCoversAreTooShortForThePhonesArrangement() {
        // Not supported, and said so: a flip's cover is about square. The Razr+'s (406×402) gets the
        // compact bar over a usable picture (no room for thumbnails: the Apps drawer lists the
        // windows' apps); the Flip 6's (360×374) gets the phone's arrangement with a 14 dp picture,
        // since the compact bar's buttons don't fit 360 dp. Open the phone to stream.
        val razr = StreamLayout.of(tinyCovers[1], phone = true)
        assertTrue(razr is StreamLayout.Landscape && razr.panel.height > 300)
        val flip = StreamLayout.of(tinyCovers[0], phone = true)
        assertTrue(flip is StreamLayout.Phone && flip.panel.height < 20)
    }

    @Test fun theConnectColumnKeepsToAPageAndAboveTheFold() {
        val book = ConnectLayout(Size(900.0, 675.0), FoldInfo.known(Rect(430.0, 0.0, 40.0, 675.0)))
        assertEquals(25.0, book.columnX)                      // centred in the 430 dp leading page
        val laptop = ConnectLayout(Size(411.0, 1005.0), FoldInfo.known(Rect(0.0, 482.5, 411.0, 40.0)))
        assertEquals(482.5, laptop.roomAboveFold)
        assertTrue(laptop.short)
        assertEquals(null, ConnectLayout(Size(675.0, 900.0), FoldInfo.none).roomAboveFold)
    }
}
