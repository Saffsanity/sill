package me.saffer.sill.core.ui

import me.saffer.sill.core.Json
import me.saffer.sill.core.JsonNumber
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The fold's rules against iOSClient/DuoPosture.swift: ui-vectors.json's duo sections are what the
 * Swift computed (clients/design/generate.sh) over the Duo's, the foldables' and plain screens, with
 * no fold known, none folded, and bands down and across them.
 */
class DuoPostureTest {
    @Suppress("UNCHECKED_CAST")
    private val vectors = Json.parse(javaClass.getResource("/sill/ui-vectors.json")!!.readBytes()) as Map<String, Any?>

    private fun d(v: Any?) = (v as JsonNumber).toDouble()
    @Suppress("UNCHECKED_CAST")
    private fun rect(v: Any?) = (v as List<Any?>).map(::d).let { Rect(it[0], it[1], it[2], it[3]) }
    private fun fold(v: Any?): FoldInfo = when (v) { "inferred" -> FoldInfo.Inferred; null -> FoldInfo.Known(null); else -> FoldInfo.Known(rect(v)) }
    private fun near(a: Double?, b: Double?, at: String) {
        if (a == null && b == null) return
        if (a == null || b == null || abs(a - b) > 1e-5) fail("$at: Swift $a, Kotlin $b")
    }
    private fun near(a: Rect?, b: Rect?, at: String) {
        if (a == null && b == null) return
        if (a == null || b == null) fail("$at: Swift $a, Kotlin $b")
        near(a.x, b.x, at); near(a.y, b.y, at); near(a.width, b.width, at); near(a.height, b.height, at)
    }
    @Suppress("UNCHECKED_CAST") private fun list(v: Any?) = v as List<Any?>

    @Test fun everyRuleIsTheSwiftOne() {
        @Suppress("UNCHECKED_CAST")
        val all = vectors["duoRules"] as List<Map<String, Any?>>
        assertTrue(all.size >= 100)
        for (v in all) {
            val w = d(v["w"]); val h = d(v["h"]); val s = Size(w, h)
            val f = fold(v["f"])
            val at = "${w}×$h $f"
            near(v["vertical"]?.let(::rect), f.verticalBand, "$at vertical")
            near(v["horizontal"]?.let(::rect), f.horizontalBand, "$at horizontal")
            val crease = v["crease"]?.let { list(it).map(::d) }
            val k = DuoPosture.crease(s, f)
            near(crease?.get(0), k?.first, "$at crease top"); near(crease?.get(1), k?.second, "$at crease bottom")
            near(v["roomAboveFold"]?.let(::d), DuoPosture.roomAboveFold(s, f), "$at roomAboveFold")
            var i = 0
            for (a in listOf(1.6, 0.6, 2.4)) for (c in listOf(180.0, 204.0, 400.0)) {
                val e = list(list(v["splits"])[i++]).map(::d)
                val p = DuoPosture.portraitSplit(s, f, a, c)
                near(e[0], p.picture, "$at split $a $c picture"); near(e[1], p.controls, "$at split $a $c controls")
            }
            val cx = list(v["columnX"]).map(::d)
            near(cx[0], DuoPosture.columnX(380.0, w, f), "$at columnX 380")
            near(cx[1], DuoPosture.columnX(maxOf(200.0, w - 32), w, f), "$at columnX narrow")
            near(v["leadingPage"]?.let(::d), DuoPosture.leadingPage(f), "$at leadingPage")
            val targets = listOf(null, Rect(20.0, 10.0, 60.0, 60.0), Rect(w - 80, 10.0, 60.0, 60.0))
            list(v["pageWidth"]).zip(targets).forEach { (e, t) -> near(e?.let(::d), DuoPosture.pageWidth(w, 12.0, f, t), "$at pageWidth $t") }
            val bars = listOf(listOf(22.0, 12.0, 66.0, 64.0, 5.0, 360.0), listOf(14.0, 12.0, 64.0, 64.0, 5.0, 340.0), listOf(14.0, 12.0, 64.0, 56.0, 4.0, 360.0))
            list(v["bookBars"]).zip(bars).forEach { (e, p) ->
                val b = DuoPosture.bookBar(w, f, p[0], p[1], p[2], p[3], p[4].toInt(), p[5])
                val l = list(e)
                near(d(l[0]), b.buttonWidth, "$at book button"); near(d(l[1]), b.gap, "$at book gap")
                near(l[2]?.let(::d), b.stripWidth, "$at book strip"); near(d(l[3]), b.panelWidth, "$at book panel")
                assertEquals(l[4] as Boolean, b.clears, "$at book clears")
            }
            i = 0
            for (cw in listOf(200.0, 360.0, 500.0)) for (x in listOf(0.0, w / 2 - 100, w - 300)) {
                near(d(list(v["offTheFold"])[i++]), DuoPosture.offTheFold(x, cw, w, 12.0, f), "$at offTheFold $cw $x")
            }
            i = 0
            for (t in listOf(Rect(w / 2 - 46, 20.0, 92.0, 58.0), Rect(w * 0.2, h * 0.55, 92.0, 58.0), Rect(w * 0.6, h * 0.4, 92.0, 58.0))) {
                for (below in listOf(true, false)) {
                    val e = list(list(v["lights"])[i++])
                    val m = DuoPosture.lightsMenu(t.midX, below, t, Size(214.0, 62.0), 8.0, w, f)
                    near(d(e[0]), m.x, "$at lights x"); near(d(e[1]), m.y, "$at lights y")
                    assertEquals(e[2] as Boolean, m.below, "$at lights below $t $below")
                }
            }
        }
    }

    @Test fun postureIsTheSwiftOne() {
        @Suppress("UNCHECKED_CAST")
        val all = vectors["duoPostures"] as List<Map<String, Any?>>
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val s = Size(d(v["w"]), d(v["h"]))
            val p = DuoPosture(DuoPosture.Hinge.entries.first { it.raw == v["hinge"] }, v["fold"]?.let(::rect))
            val at = "$s $p"
            val info = p.info(s)
            when (val e = v["info"]) {
                "inferred" -> assertEquals(FoldInfo.Inferred, info, at)
                null -> assertEquals(FoldInfo.Known(null), info, at)
                else -> near(rect(e), info.band, "$at info")
            }
            assertEquals(v["pose"], p.pose(s).raw, at)
            assertEquals(v["active"], p.foldActive, at)
            assertEquals(v["inner"], p.onInnerDisplay, at)
            assertEquals(v["hides"], DuoPosture.hidesStatusBar(p.pose(s)), at)
        }
        for (r in list(vectors["duoHinge"])) {
            val l = list(r)
            val reported = DuoPosture.Hinge.entries.first { it.raw == l[0] }
            assertEquals(l[2], DuoPosture.hinge(reported, l[1] as Boolean?).raw, "$l")
        }
        for (r in list(vectors["duoAspects"])) {
            val l = list(r)
            near(d(l[3]), DuoPosture.paneAspect(Size(d(l[0]), d(l[1])), l[2] as Boolean), "$l")
        }
    }
}
