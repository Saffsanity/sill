package me.saffer.sill.core.ui

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/*
 * A fold across the screen, and the layout rules that follow from it: iOSClient/DuoPosture.swift
 * line for line (docs/iphone-duo-plan.md), held to the Swift by ui-vectors.json's duo sections
 * (clients/design/generate.sh compiles DuoPosture.swift as it is). The iOS app reads the iPhone
 * Duo's hinge; the Android app reads any foldable's (the platform's window extensions, else the hinge
 * angle sensor) and hands the same FoldInfo to these rules, so a Galaxy Z Fold half-open as a book or
 * a Z Flip half-open as a laptop lays out as the Duo does.
 */

/** What a layout knows of a fold across it (FoldInfo). */
sealed class FoldInfo {
    /** Nothing known (iOS before 27.1, a device without a hinge): the rules infer the half-folded
     *  Duo's crease from the screen's size alone. The Android app says this for a screen with no fold
     *  to report, as iOS does for every iPhone and iPad. */
    data object Inferred : FoldInfo()

    /** The device said: the band nothing interactive sits on while the display is half-folded (in
     *  the layout's own space, clipped to it), or null when nothing is folded across this screen. */
    data class Known(val foldBand: Rect?) : FoldInfo()

    val band: Rect? get() = (this as? Known)?.foldBand

    /** A fold down the middle of a screen held sideways: the book pose. */
    val verticalBand: Rect? get() = band?.takeIf { it.height > it.width }

    /** A fold across a screen held upright: the laptop pose. */
    val horizontalBand: Rect? get() = band?.takeIf { it.width >= it.height }

    companion object {
        val none: FoldInfo = Known(null)
        fun known(band: Rect?): FoldInfo = Known(band)
    }
}

/** The posture as one screen sees it: the hinge, and the fold in that screen's own space. */
data class DuoPosture(val hinge: Hinge = Hinge.Unknown, val fold: Rect? = null) {
    enum class Hinge(val raw: String) { Unknown("unknown"), Closed("closed"), PartiallyOpen("partiallyOpen"), FullyOpen("fullyOpen") }

    enum class Pose(val raw: String) {
        Unknown("unknown"), Book("book"), Laptop("laptop"), FlatLandscape("flat-landscape"),
        FlatPortrait("flat-portrait"), ClosedUpright("closed-upright"), ClosedSide("closed-side")
    }

    /** The fold is in the way exactly while the hinge is partly open. */
    val foldActive get() = hinge == Hinge.PartiallyOpen && fold != null

    /** What the layout rules get for a screen of `size`. */
    fun info(size: Size): FoldInfo {
        if (hinge == Hinge.Unknown) return FoldInfo.Inferred
        val f = fold
        if (!foldActive || f == null) return FoldInfo.Known(null)
        return FoldInfo.Known(clip(f, size))
    }

    fun pose(size: Size): Pose {
        val sideways = size.width > size.height
        return when (hinge) {
            Hinge.Unknown -> Pose.Unknown
            Hinge.Closed -> if (sideways) Pose.ClosedSide else Pose.ClosedUpright
            Hinge.PartiallyOpen -> if (sideways) Pose.Book else Pose.Laptop
            Hinge.FullyOpen -> if (sideways) Pose.FlatLandscape else Pose.FlatPortrait
        }
    }

    val onInnerDisplay get() = hinge == Hinge.PartiallyOpen || hinge == Hinge.FullyOpen

    /** The portrait halves' split: how tall the picture's pane is, and where the controls begin. */
    data class PortraitSplit(val picture: Double, val controls: Double)

    /** The landscape bar in the book pose: nothing on the fold's band. */
    data class BookBar(val buttonWidth: Double, val gap: Double, val stripWidth: Double?, val panelWidth: Double, val clears: Boolean)

    /** Where the window lights' menu goes. */
    data class LightsPlace(val x: Double, val y: Double, val below: Boolean)

    companion object {
        val unknown = DuoPosture()

        /** The picture pane's padding round the picture. */
        const val paneInset = 8.0
        const val minimumPane = 160.0
        const val minimumTrackpad = 200.0
        /** 16:10, the shape of most Macs' displays and windows. */
        const val defaultAspect = 1.6
        /** The least gap the book bar's right group steps down to. */
        const val minimumGap = 6.0
        /** The Duo's fold band: 40 points, 20 each side of the crease (also the Android app's least band). */
        const val standInThickness = 40.0

        /** A rectangle clipped to a screen of `size`: null when nothing of it is left (CGRect's
         *  intersection, then isNull or isEmpty). */
        fun clip(r: Rect, size: Size): Rect? {
            val x0 = max(r.minX, 0.0); val y0 = max(r.minY, 0.0)
            val x1 = min(r.maxX, size.width); val y1 = min(r.maxY, size.height)
            if (x1 <= x0 || y1 <= y0) return null
            return Rect(x0, y0, x1 - x0, y1 - y0)
        }

        /** Swift's `rounded()`: half away from zero (Kotlin's round is half to even). */
        private fun rounded(v: Double) = if (v >= 0) floor(v + 0.5) else ceil(v - 0.5)

        /** The hinge to go by: what was reported, or before the first report what the fold says. */
        fun hinge(reported: Hinge, regionActive: Boolean?): Hinge {
            if (reported != Hinge.Unknown || regionActive == null) return reported
            return if (regionActive) Hinge.PartiallyOpen else Hinge.FullyOpen
        }

        /** Whether the stream screen hides the status bar: on the inner display in every pose. */
        fun hidesStatusBar(pose: Pose) = pose == Pose.Laptop || pose == Pose.FlatPortrait || pose == Pose.Book || pose == Pose.FlatLandscape

        /** The fold across a screen held upright, its top and bottom edges. */
        fun crease(size: Size, fold: FoldInfo): Pair<Double, Double>? = when (fold) {
            FoldInfo.Inferred ->
                if (size.height > size.width && size.width >= 600 && size.width < 740 && size.height < 1100) (size.height / 2) to (size.height / 2) else null
            is FoldInfo.Known -> fold.horizontalBand?.let { it.minY to it.maxY }
        }

        /** The room above a fold the device reported across the screen (the laptop pose). */
        fun roomAboveFold(size: Size, fold: FoldInfo): Double? {
            if (fold !is FoldInfo.Known) return null
            val c = crease(size, fold) ?: return null
            return max(0.0, c.first)
        }

        fun portraitSplit(size: Size, fold: FoldInfo, aspect: Double, controls: Double): PortraitSplit = when (fold) {
            FoldInfo.Inferred -> { val half = rounded(size.height / 2); PortraitSplit(half, half) }
            is FoldInfo.Known -> {
                val band = fold.horizontalBand
                if (band != null) {
                    val top = max(0.0, floor(band.minY))
                    val bottom = min(size.height, ceil(band.maxY))
                    PortraitSplit(top, max(top, bottom))
                } else {
                    val pictureWidth = max(0.0, size.width - 2 * paneInset)
                    val natural = rounded(pictureWidth / max(aspect, 0.1)) + 2 * paneInset
                    val most = max(0.0, size.height - controls - minimumTrackpad)
                    val least = min(minimumPane, most)
                    val pane = min(max(natural, least), most)
                    PortraitSplit(pane, pane)
                }
            }
        }

        fun paneAspect(video: Size, fitsWindowToPane: Boolean): Double {
            if (fitsWindowToPane || video.width <= 0 || video.height <= 0) return defaultAspect
            return video.width / video.height
        }

        fun bookBar(width: Double, fold: FoldInfo, padding: Double, gap: Double, buttonWidth: Double,
                    compactButtonWidth: Double, buttons: Int, panelWidth: Double): BookBar {
            val unchanged = BookBar(buttonWidth, gap, null, panelWidth, true)
            val band = fold.verticalBand ?: return unchanged
            if (buttons <= 0 || band.minX <= padding || band.maxX >= width - padding) return unchanged
            val count = buttons.toDouble()
            fun start(button: Double, g: Double) = width - padding - count * button - (count - 1) * g
            var button = buttonWidth
            var g = gap
            if (start(button, g) < band.maxX) button = min(button, compactButtonWidth)
            if (start(button, g) < band.maxX && buttons > 1) {
                val room = floor((width - padding - count * button - band.maxX) / (count - 1))
                g = max(minimumGap, min(g, room))
            }
            val stripStart = padding + button + g
            val strip = max(0.0, band.minX - g - stripStart)
            val panel = min(panelWidth, max(0.0, width - padding - band.maxX))
            return BookBar(button, g, strip, panel, start(button, g) >= band.maxX)
        }

        fun offTheFold(x: Double, width: Double, screenWidth: Double, margin: Double, fold: FoldInfo): Double {
            val band = fold.verticalBand ?: return x
            if (!(x < band.maxX && x + width > band.minX)) return x
            val leadingFits = width <= band.minX - margin
            val trailingFits = width <= screenWidth - margin - band.maxX
            val leading = band.minX - width
            val trailing = band.maxX
            if (x + width / 2 <= band.midX) {
                if (leadingFits) return leading
                if (trailingFits) return trailing
            } else {
                if (trailingFits) return trailing
                if (leadingFits) return leading
            }
            return x
        }

        fun lightsMenu(x: Double, below: Boolean, thumbnail: Rect, size: Size, gap: Double, screenWidth: Double, fold: FoldInfo): LightsPlace {
            fun rect(b: Boolean) = Rect(x - size.width / 2, if (b) thumbnail.maxY + gap else thumbnail.minY - gap - size.height, size.width, size.height)
            var down = below
            val band = fold.horizontalBand
            if (!down && band != null && intersects(rect(false), band)) down = true
            val left = offTheFold(x - size.width / 2, size.width, screenWidth, 8.0, fold)
            return LightsPlace(left + size.width / 2, rect(down).midY, down)
        }

        /** CGRect's `intersects` as Foundation computes it (its intersection is not null): rectangles
         *  that only touch along an edge count, as the vectors from the Swift show. */
        fun intersects(a: Rect, b: Rect) = min(a.maxX, b.maxX) >= max(a.minX, b.minX) && min(a.maxY, b.maxY) >= max(a.minY, b.minY)

        fun pageWidth(screenWidth: Double, margin: Double, fold: FoldInfo, target: Rect? = null): Double? {
            val band = fold.verticalBand ?: return null
            val leading = max(0.0, band.minX - margin)
            val trailing = max(0.0, screenWidth - margin - band.maxX)
            if (target == null) return max(leading, trailing)
            return if (target.midX <= band.midX) leading else trailing
        }

        fun columnX(columnWidth: Double, screenWidth: Double, fold: FoldInfo): Double {
            val centred = max(16.0, (screenWidth - columnWidth) / 2)
            val band = fold.verticalBand
            if (band == null || columnWidth + 32 > band.minX) return centred
            return max(16.0, (band.minX - columnWidth) / 2)
        }

        fun leadingPage(fold: FoldInfo): Double? = fold.verticalBand?.let { max(0.0, it.minX) }

        /** The Duo's fold for a screen of `size`: 40 points across the middle of its longer side. */
        fun standInFold(size: Size) =
            if (size.width > size.height) Rect(size.width / 2 - 20, 0.0, 40.0, size.height)
            else Rect(0.0, size.height / 2 - 20, size.width, 40.0)
    }
}
