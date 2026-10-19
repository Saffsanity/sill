package me.saffer.sill.android

import me.saffer.sill.core.ui.DuoPosture
import me.saffer.sill.core.ui.FoldInfo
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Size
import me.saffer.sill.core.ui.StreamLayout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The Android app's own arithmetic around core's layouts (Geometry.kt): no android.* in any of it. */
class GeometryTest {
    @Test fun dpBecomesWholePixelsThatStillTouch() {
        val px = Px(2.625)
        val a = px.box(Rect(0.0, 0.0, 33.3, 10.0)); val b = px.box(Rect(33.3, 0.0, 33.3, 10.0))
        assertEquals(a.right, b.left)
        assertEquals(PxBox(21, 21, 42, 47), px.box(Rect(0.0, 0.0, 8.0, 10.0), 8.0, 8.0))
        assertEquals(10.0, px.dp(26.25f).let { Math.round(it * 100) / 100.0 })
    }

    @Test fun theSafeAreaTakesTheBarsAndNeverTheKeyboard() {
        assertEquals(Size(411.0, 868.0), Insets(0.0, 40.0, 0.0, 52.0).safe(Size(411.0, 960.0)))
        assertEquals(Size(0.0, 0.0), Insets(300.0, 0.0, 300.0, 0.0).safe(Size(500.0, -1.0)))
    }

    @Test fun smallControlsGrowTo48WithoutOverlappingTheirNeighbours() {
        val cap = Rect(14.0, 100.0, 50.0, 44.0)
        assertEquals(Rect(14.0, 98.0, 50.0, 48.0), Targets.expand(cap, room = 4.0))
        assertEquals(Rect(10.0, 98.0, 42.0, 48.0), Targets.expand(Rect(12.0, 100.0, 38.0, 44.0), room = 2.0).let { Rect(it.x, it.y, it.width, it.height) })
        assertEquals(Rect(0.0, 0.0, 66.0, 66.0), Targets.expand(Rect(0.0, 0.0, 66.0, 66.0)))
    }

    @Test fun backClosesOneThingAtATimeInTheIosOrder() {
        assertEquals(BackPlan.Step.Ruler, BackPlan.next(true, true, true, true))
        assertEquals(BackPlan.Step.Lights, BackPlan.next(false, true, true, true))
        assertEquals(BackPlan.Step.Drawer, BackPlan.next(false, false, true, true))
        assertEquals(BackPlan.Step.Settings, BackPlan.next(false, false, false, true))
        assertEquals(BackPlan.Step.Leave, BackPlan.next(false, false, false, false))
    }

    @Test fun thumbnailsKeepThisDevicesOrderAndDragThroughIt() {
        assertEquals(listOf(3L, 1L, 2L, 4L), Reorder.arrange(listOf(1, 2, 3, 4), listOf(3, 9, 1)))
        assertEquals(2, Reorder.target(0, 250.0, 120.0, 4))
        assertEquals(3, Reorder.target(1, 9_000.0, 120.0, 4))
        assertEquals(0, Reorder.target(1, -9_000.0, 120.0, 4))
        assertEquals(listOf(2L, 3L, 1L, 4L), Reorder.moved(listOf(1, 2, 3, 4), 0, 2))
        assertEquals(listOf(0, -1, -1, 0), (0..3).map { Reorder.shift(it, 0, 2) })
        assertEquals(listOf(1, 1, 0, 0), (0..3).map { Reorder.shift(it, 2, 0) })
    }

    @Test fun theCodeGroupsAsTheIosField() {
        assertEquals("1234 5678 9012", CodeText.grouped("12 34-5678x90123"))
        assertEquals("12", CodeText.grouped("1a2"))
    }

    @Test fun theColumnCentresRisesThenScrolls() {
        assertEquals(ColumnPlace.Place(350.0, 200.0, false), ColumnPlace.of(900.0, 200.0, 60.0, 24.0))
        assertEquals(ColumnPlace.Place(100.0, 700.0, false), ColumnPlace.of(900.0, 700.0, 60.0, 24.0))
        assertEquals(ColumnPlace.Place(26.0, 790.0, false), ColumnPlace.of(900.0, 790.0, 60.0, 24.0))   // risen to keep the gap
        assertEquals(ColumnPlace.Place(16.0, 800.0, true), ColumnPlace.of(900.0, 1000.0, 60.0, 24.0))
    }

    @Test fun aLatchedLetterIsItsKey() {
        assertEquals(0x06, CharKeys.usage('c'))
        assertEquals(0x06, CharKeys.usage('C'))
        assertEquals(0x27, CharKeys.usage('0'))
        assertNull(CharKeys.usage('é'))
    }

    private val view = Size(900.0, 675.0)

    @Test fun aHalfOpenFoldBecomesABandInTheViewsDp() {
        // A Z Fold's hinge of no thickness at x = 1181 px in the window, the view at (0, 105) px, 2.625 px a dp.
        val f = FoldMapping.Feature(PxBox(1181, 0, 1181, 1877), halfOpened = true, separating = false)
        val band = FoldMapping.info(FoldMapping.Reading.Extensions(f), 0, 105, 2.625, view).band!!
        assertEquals(DuoPosture.standInThickness, band.width)
        assertEquals(1181 / 2.625 - 20, band.x, 1e-9)
        assertEquals(0.0, band.y)                     // clipped to the view
        assertEquals(675.0, band.height)
        assertTrue(FoldInfo.known(band).verticalBand != null)
    }

    @Test fun aFoldAcrossTheScreenIsHorizontal() {
        val f = FoldMapping.Feature(PxBox(0, 900, 2363, 900), halfOpened = true, separating = false)
        val band = FoldMapping.info(FoldMapping.Reading.Extensions(f), 0, 0, 2.625, view).band!!
        assertEquals(900 / 2.625 - 20, band.y, 1e-9)
        assertEquals(view.width, band.width)
    }

    @Test fun aFlatFoldIsNoFoldAndAHingeAlwaysSeparates() {
        val flat = FoldMapping.Feature(PxBox(1181, 0, 1181, 1877), halfOpened = false, separating = false)
        assertEquals(FoldInfo.none, FoldMapping.info(FoldMapping.Reading.Extensions(flat), 0, 0, 2.625, view))
        assertEquals(FoldInfo.Inferred, FoldMapping.info(FoldMapping.Reading.Extensions(null), 0, 0, 2.625, view))
        val hinge = FoldMapping.Feature(PxBox(1150, 0, 1210, 1877), halfOpened = false, separating = true)
        assertTrue(FoldMapping.info(FoldMapping.Reading.Extensions(hinge), 0, 0, 2.625, view).band != null)
        // A fold outside this view (the other window in split screen): nothing.
        val away = FoldMapping.Feature(PxBox(5000, 0, 5000, 1877), halfOpened = true, separating = false)
        assertEquals(FoldInfo.none, FoldMapping.info(FoldMapping.Reading.Extensions(away), 0, 0, 2.625, view))
    }

    @Test fun theHingeSensorStandsInAndNoFoldIsTheIPadsRule() {
        assertEquals(FoldInfo.known(DuoPosture.standInFold(view)), FoldMapping.info(FoldMapping.Reading.HingeAngle(90f), 0, 0, 2.625, view))
        assertEquals(FoldInfo.none, FoldMapping.info(FoldMapping.Reading.HingeAngle(178f), 0, 0, 2.625, view))
        assertEquals(FoldInfo.Inferred, FoldMapping.info(FoldMapping.Reading.HingeAngle(10f), 0, 0, 2.625, view))
        assertEquals(FoldInfo.Inferred, FoldMapping.info(FoldMapping.Reading.Nothing, 0, 0, 2.625, view))
    }

    @Test fun theMappedFoldLaysTheStreamScreenOut() {
        // The Z Fold 8 sideways in tabletop: the halves, the picture above the hinge.
        val f = FoldMapping.Feature(PxBox(0, 886, 2363, 886), halfOpened = true, separating = false)
        val fold = FoldMapping.info(FoldMapping.Reading.Extensions(f), 0, 0, 2.625, view)
        val l = StreamLayout.of(view, phone = false, fold = fold)
        assertTrue(l is StreamLayout.Halves && l.panel.maxY <= fold.band!!.minY)
    }
}
