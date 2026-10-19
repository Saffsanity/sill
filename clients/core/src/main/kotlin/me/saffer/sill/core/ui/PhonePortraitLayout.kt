package me.saffer.sill.core.ui

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Where everything goes on a phone held upright: iOSClient/PhonePortraitLayout.swift, line for line
 * (its doc comment has the reasons for every number), so an Android phone upright draws the iPhone's
 * arrangement: the picture in a fixed 16:10 pane at the top, row 1 (Apps, Aa, Keyboard, Desktop,
 * Settings), row 2 (the thumbnails), row 3 (esc, tab, ctrl, opt, cmd, shift) and the trackpad in the
 * rest. Every rectangle is a function of the stream screen's size (and Larger Picture's keyboard)
 * alone. clients/design/generate.sh compiles the Swift and writes layout-vectors.json; the core's
 * tests hold this port to it at every size.
 */
class PhonePortraitLayout(val size: Size, val keyboard: Double? = null) {
    enum class Button { Apps, TextSize, Keyboard, Desktop, Settings }
    enum class Streaming { Nothing, Desktop, Window }

    val picture: Rect
    val row1: Rect
    val buttons: List<Rect>
    val buttonsBesideMenus: List<Rect>
    val strip: Rect
    val menus: Rect
    val stripBesideMenus: Rect
    val keys: Rect
    val caps: List<Rect>
    val trackpad: Rect
    val trackpadSpan: Double
    val ruler: Rect
    val rulerStep: Double
    val rulerBesideMenus: Rect
    val rulerStepBesideMenus: Double
    val drawer: Rect
    val settings: Rect
    val settingsAnchorX: Double
    val settingsAnchorY: Double
    val dim: List<Rect>

    val largerPicture: Boolean get() = keyboard != null

    init {
        val width = size.width
        val height = size.height

        val pictureWidth = max(0.0, width - 2 * margin)
        val natural = floor(pictureWidth / aspect)
        val pictureHeight = min(natural, max(0.0, height - fixedHeight - minTrackpad))
        val footprint = keyboard?.let { max(it, minTrackpad + bottom) }
        val largerHeight = footprint?.let { max(0.0, floor(height - it - largerFixedHeight)) }
        picture = Rect(margin, margin, pictureWidth, largerHeight ?: pictureHeight)

        val rowWidth = max(0.0, width - 2 * side)
        row1 = Rect(side, picture.maxY + margin + underPicture + band, rowWidth, buttonHeight)
        buttons = split(row1, Button.entries.size, gap)

        val settingsButton = buttons[Button.Settings.ordinal]
        if (footprint == null) {
            strip = Rect(side - stripInset, row1.maxY + band + rowGap, max(0.0, width - 2 * (side - stripInset)), stripHeight)
            menus = Rect(settingsButton.minX, strip.minY + (stripHeight - buttonHeight) / 2, settingsButton.width, buttonHeight)
            stripBesideMenus = Rect(strip.minX, strip.minY, max(0.0, menus.minX - gap - strip.minX), strip.height)
            buttonsBesideMenus = buttons
        } else {
            val six = split(row1, Button.entries.size + 1, gap)
            val gone = Rect(side - stripInset, row1.maxY + band, max(0.0, width - 2 * (side - stripInset)), 0.0)
            strip = gone
            stripBesideMenus = gone
            menus = six[1]
            buttonsBesideMenus = listOf(six[0]) + six.drop(2)
        }

        keys = Rect(side, strip.maxY + rowGap, rowWidth, capHeight)
        caps = split(keys, capCount, gap)

        var padTop = keys.maxY + rowGap
        if (footprint != null) padTop = max(keys.maxY + keyboardClearance, height - footprint)
        trackpad = Rect(side, padTop, rowWidth, max(0.0, height - bottom - padTop))
        trackpadSpan = trackpad.width / aspect

        ruler(buttons[Button.TextSize.ordinal], row1).let { ruler = it.first; rulerStep = it.second }
        ruler(buttonsBesideMenus[Button.TextSize.ordinal], row1).let { rulerBesideMenus = it.first; rulerStepBesideMenus = it.second }

        val panelTop = row1.maxY + panelGap
        val panelHeight = max(0.0, height - bottom - panelTop)
        drawer = if (footprint == null) Rect(side, panelTop, rowWidth, panelHeight)
        else Rect(side, margin, rowWidth, max(0.0, row1.minY - panelGap - margin))
        settings = Rect(side, panelTop, rowWidth, panelHeight)
        settingsAnchorX = if (width > 0) settings.maxX / width else 1.0
        settingsAnchorY = if (height > 0) settings.minY / height else 0.0

        dim = listOf(Rect(0.0, 0.0, width, row1.minY), Rect(0.0, row1.maxY, width, max(0.0, height - row1.maxY)))
    }

    /** The frame the video is drawn in, for a picture of `video`'s shape (PhonePortraitLayout.pane). */
    fun pane(video: Size): Rect {
        if (!largerPicture || picture.width <= 0 || picture.height <= 0) return picture
        val known = video.width > 0 && video.height > 0
        val w = if (known) video.width else aspect
        val h = if (known) video.height else 1.0
        val tall = picture.width * h / w
        if (tall <= picture.height + 0.01) {
            return Rect(picture.minX, picture.minY, picture.width, min(picture.height, floor(tall + 0.01)))
        }
        val wide = min(picture.width, floor(picture.height * w / h + 0.01))
        return Rect(picture.minX + floor((picture.width - wide) / 2), picture.minY, wide, picture.height)
    }

    /** What the pad's vertical motion is measured against for a picture of `video`'s shape. */
    fun trackpadSpan(video: Size): Double {
        if (!largerPicture) return trackpadSpan
        val frame = pane(video)
        if (frame.width <= 0 || frame.height <= 0) return trackpadSpan
        return trackpad.width * frame.height / frame.width
    }

    companion object {
        const val margin = 8.0
        const val aspect = 1.6
        const val underPicture = 10.0
        const val band = 6.0
        const val side = 14.0
        const val bottom = 16.0
        const val rowGap = 10.0
        const val gap = 8.0
        const val buttonHeight = 50.0
        const val stripHeight = 62.0
        const val stripInset = 8.0
        const val capHeight = 44.0
        const val minTrackpad = 120.0
        const val panelGap = 8.0
        const val maxRulerStep = 36.0
        const val rulerInset = 30.0
        const val rulerSpans = 4.0
        const val keyboardClearance = 10.0
        const val homeButtonKeyboard = 233.0
        const val faceIDKeyboard = 301.0
        const val miniKeyboard = 310.0
        const val wideKeyboard = 320.0
        const val wideKeyboardFrom = 414.0
        const val faceIDKeyboardFrom = 390.0
        const val miniKeyboardFrom = 375.0
        const val faceIDShape = 1.9
        const val minButtonWidth = 44.0
        const val capCount = 6

        val fixedHeight: Double get() =
            margin + margin + underPicture + band + buttonHeight + band + rowGap + stripHeight + rowGap + capHeight + rowGap + bottom
        val largerFixedHeight: Double get() =
            margin + margin + underPicture + band + buttonHeight + band + capHeight + rowGap + keyboardClearance

        /**
         * The iPhone's keyboard height by the stream screen's shape and width. On Android the
         * clients use the real keyboard's height from the window insets instead (it is measured, not
         * guessed); this stays for parity checks and for a screen whose keyboard has not shown yet.
         */
        fun keyboardHeight(container: Size): Double {
            if (container.width <= 0 || container.height / container.width < faceIDShape) return homeButtonKeyboard
            if (container.width >= wideKeyboardFrom) return wideKeyboard
            if (container.width >= faceIDKeyboardFrom) return faceIDKeyboard
            if (container.width >= miniKeyboardFrom) return miniKeyboard
            return wideKeyboard
        }

        fun largerPicture(switchOn: Boolean, streaming: Streaming) = switchOn && streaming == Streaming.Window

        fun keyboard(container: Size, largerPicture: Boolean, foldable: Boolean, measured: Double? = null): Double? {
            if (!largerPicture || foldable) return null
            val keyboard = measured ?: keyboardHeight(container)
            return if (largerPictureGains(container, keyboard)) keyboard else null
        }

        fun largerPictureGains(container: Size, keyboard: Double): Boolean {
            val larger = PhonePortraitLayout(container, keyboard)
            return larger.picture.height > PhonePortraitLayout(container).picture.height && larger.menus.width >= minButtonWidth
        }

        fun offersLargerPicture(screen: Size): Boolean {
            val upright = Size(min(screen.width, screen.height), max(screen.width, screen.height))
            return keyboard(upright, largerPicture = true, foldable = false) != null
        }

        private fun ruler(aa: Rect, row: Rect): Pair<Rect, Double> {
            val room = (aa.midX - row.minX) * 2 - 2 * rulerInset
            val step = max(0.0, min(maxRulerStep, room / rulerSpans))
            val w = step * rulerSpans + 2 * rulerInset
            return Rect(aa.midX - w / 2, row.minY, w, buttonHeight) to step
        }

        /** `count` equal parts of `row`, `gap` apart, filling it. */
        fun split(row: Rect, count: Int, gap: Double): List<Rect> {
            val each = max(0.0, (row.width - (count - 1) * gap) / count)
            return (0 until count).map { i -> Rect(row.minX + i * (each + gap), row.minY, each, row.height) }
        }
    }
}
