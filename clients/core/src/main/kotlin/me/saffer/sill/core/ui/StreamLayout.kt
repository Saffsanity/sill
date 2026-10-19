package me.saffer.sill.core.ui

import kotlin.math.max
import kotlin.math.min

/**
 * Which layout a stream screen gets, from its size alone: the iOS app's `DuoLayout`
 * (StreamScreen.swift). 600 and 560 points are its thresholds; an Android phone upright is
 * `OuterPortrait` and draws the phone's arrangement as an iPhone does, a tablet upright the halves.
 */
enum class ScreenLayout {
    InnerLandscape, InnerPortrait, OuterPortrait, OuterLandscape;

    val isPortrait get() = this == InnerPortrait || this == OuterPortrait
    val isLandscape get() = !isPortrait

    companion object {
        const val outerMaxWidth = 600.0
        const val outerMaxHeight = 560.0

        fun of(size: Size): ScreenLayout {
            if (size.height > size.width && size.width < outerMaxWidth) return OuterPortrait
            if (size.width > size.height && size.height < outerMaxHeight) return OuterLandscape
            return if (size.width > size.height) InnerLandscape else InnerPortrait
        }
    }
}

/** The bar's buttons, in the landscape bar's order (TopBar), which every arrangement keeps. */
enum class BarItem { Apps, Strip, Menus, TextSize, Keyboard, Desktop, Settings }

/**
 * Everything a stream screen places, for one of the iOS app's four arrangements: the landscape bar
 * over the stream (`Landscape`), the two halves upright (`Halves`, an iPad's and a tablet's), and a
 * phone upright (`Phone`, PhonePortraitLayout's). The platforms draw these rectangles; they decide
 * nothing about where things go themselves.
 */
sealed class StreamLayout {
    abstract val size: Size
    /** The stream panel: the video is aspect-fit inside it, and it is the viewport sent to the Mac. */
    abstract val panel: Rect
    /** Each bar button's frame (BarItem.Strip is the thumbnails' row). */
    abstract val items: Map<BarItem, Rect>
    /** The Aa ruler while a finger holds Aa, and its points per detent. */
    abstract val ruler: Rect
    abstract val rulerStep: Double
    /** The Apps drawer, and the most room the Settings panel may take (it is as tall as its content). */
    abstract val drawer: Rect
    abstract val settings: Rect
    /** Where the Settings panel grows from, as a point of the screen. */
    abstract val settingsAnchorX: Double
    abstract val settingsAnchorY: Double
    /** The dim (and the panel's tap catcher): what a tap closes the drawer or the panel on. */
    abstract val dim: List<Rect>
    /** Key caps (empty in landscape), and the trackpad (none in landscape). */
    abstract val caps: List<List<Rect>>
    abstract val trackpad: Rect?
    abstract val trackpadSpan: Double?
    /** The bar's or row's button size, radius and symbol size, for drawing. */
    abstract val buttonRadius: Double
    abstract val buttonIcon: Double
    abstract val buttonSpacing: Double
    /** Thumbnails' numbers. */
    abstract val thumbWidth: Double
    abstract val thumbHeight: Double
    abstract val thumbRadius: Double
    abstract val thumbSpacing: Double
    abstract val thumbPad: Double
    abstract val thumbFade: Double
    abstract val badge: Double
    abstract val arrangement: ScreenLayout
    /** Whether a held thumbnail's lights open below it (the bar at the top) rather than above. */
    abstract val lightsBelow: Boolean

    /** The landscape bar over the stream (TopBar and contentArea in StreamScreen.swift). */
    class Landscape(override val size: Size, val metrics: BarMetrics, menus: Boolean, val fold: FoldInfo = FoldInfo.Inferred) : StreamLayout() {
        override val arrangement = if (metrics == BarMetrics.compact) ScreenLayout.OuterLandscape else ScreenLayout.InnerLandscape
        val bar = Rect(0.0, 0.0, size.width, metrics.height)
        /** The book pose (DuoPostureReader's BarMetrics.clearing): the right group past the fold's band,
         *  the strip ending a gap short of it, the Settings panel off it. Menus is counted whether or not
         *  it shows, so the bar never moves when the Mac's menus come and go. */
        val book = DuoPosture.bookBar(size.width, fold, metrics.padding, metrics.gap, metrics.buttonWidth,
            BarMetrics.compact.buttonWidth, 5, metrics.settingsWidth).takeIf { it.stripWidth != null }
        private val buttonWidth = book?.buttonWidth ?: metrics.buttonWidth
        private val gap = book?.gap ?: metrics.gap
        /** Whether the bar holds the Menus button and still a whole thumbnail (MacMenuButton.fits). */
        val menusFit = fits(size.width - 2 * metrics.padding, 6, buttonWidth, gap, metrics.thumbWidth)
        val menusShown = menus && menusFit
        override val items: Map<BarItem, Rect>
        override val panel: Rect
        override val ruler: Rect
        override val rulerStep = if (metrics.buttonHeight >= 60) Ui.rulerStepRegular else Ui.rulerStepCompact
        override val drawer: Rect
        override val settings: Rect
        override val settingsAnchorX: Double
        override val settingsAnchorY: Double
        override val dim: List<Rect>
        override val caps = emptyList<List<Rect>>()
        override val trackpad: Rect? = null
        override val trackpadSpan: Double? = null
        override val buttonRadius = Ui.barButtonRadius
        override val buttonIcon = Ui.barIconSize
        override val buttonSpacing = metrics.buttonSpacing
        override val thumbWidth = metrics.thumbWidth
        override val thumbHeight = metrics.thumbHeight
        override val thumbRadius = metrics.thumbRadius
        override val thumbSpacing = metrics.thumbSpacing
        override val thumbPad = metrics.thumbPad
        override val thumbFade = metrics.thumbFade
        override val badge = 24.0
        override val lightsBelow = true

        init {
            val bw = buttonWidth
            val bh = metrics.buttonHeight
            val y = (metrics.height - bh) / 2
            val right = listOfNotNull(if (menusShown) BarItem.Menus else null, BarItem.TextSize, BarItem.Keyboard, BarItem.Desktop, BarItem.Settings)
            val m = LinkedHashMap<BarItem, Rect>()
            m[BarItem.Apps] = Rect(metrics.padding, y, bw, bh)
            var x = size.width - metrics.padding
            for (item in right.reversed()) { x -= bw; m[item] = Rect(x, y, bw, bh); x -= gap }
            val stripX = metrics.padding + bw + gap
            val stripH = metrics.thumbHeight + 2 * metrics.thumbPad
            m[BarItem.Strip] = Rect(stripX, (metrics.height - stripH) / 2, book?.stripWidth ?: max(0.0, x - stripX), stripH)
            items = BarItem.entries.mapNotNull { k -> m[k]?.let { k to it } }.toMap()

            val content = Rect(0.0, metrics.height, size.width, max(0.0, size.height - metrics.height))
            panel = content.inset(Ui.panelInset, Ui.panelInset)
            val aa = items.getValue(BarItem.TextSize)
            val w = TextScale.sliderWidth(rulerStep)
            ruler = Rect(aa.midX - w / 2, aa.minY, w, bh)
            drawer = Rect(Ui.drawerLeading, content.minY + Ui.drawerTop, onLeadingPage(min(Ui.drawerWidth, size.width - 2 * Ui.drawerLeading), Ui.drawerLeading, fold),
                max(0.0, content.height - Ui.drawerTop - Ui.drawerBottom))
            val sw = min(book?.panelWidth ?: metrics.settingsWidth, size.width - 2 * metrics.padding)
            settings = Rect(size.width - metrics.padding - sw, content.minY + Ui.drawerTop, sw,
                max(0.0, content.height - Ui.drawerTop - Ui.drawerBottom))
            settingsAnchorX = if (size.width > 0) settings.maxX / size.width else 1.0
            settingsAnchorY = if (size.height > 0) settings.minY / size.height else 0.0
            dim = listOf(content)
        }
    }

    /**
     * The halves upright (PortraitStreamScreen.halves): the picture over the window bar, the key
     * row and the trackpad, split where DuoPosture.portraitSplit says: at the middle (no fold known),
     * at a laptop pose's fold (the picture above it, the controls below), or open flat at the
     * picture's shape (`aspect`, DuoPosture.paneAspect).
     *
     * Android's foldables add a case the Duo never has, a fold down an upright screen (a Galaxy Z
     * Fold half-open as a book, held upright): the halves then keep every control off the band, the
     * bar as the book pose's (DuoPosture.bookBar), the key row's two lines side by side, one on each
     * page, the trackpad on the trailing page, the drawer on the leading one and the Settings panel
     * on the trailing one. The picture spans the fold, as the book pose's does.
     */
    class Halves(override val size: Size, val metrics: PortraitMetrics, menus: Boolean, spotlight: Boolean,
                 val fold: FoldInfo = FoldInfo.Inferred, aspect: Double = DuoPosture.defaultAspect) : StreamLayout() {
        override val arrangement = if (metrics == PortraitMetrics.compact) ScreenLayout.OuterPortrait else ScreenLayout.InnerPortrait
        val split = DuoPosture.portraitSplit(size, fold, aspect, metrics.controlsHeight)
        /** The picture's pane's height, from the top (the middle without a fold). */
        val half = split.picture
        /** The fold down this upright screen, when the halves keep to its pages. */
        val pages: Rect? = fold.verticalBand?.takeIf { it.minX > metrics.padSide && it.maxX < size.width - metrics.padSide }
        val book = pages?.let { DuoPosture.bookBar(size.width, fold, metrics.padSide, 12.0, metrics.buttonWidth,
            PortraitMetrics.compact.buttonWidth, 4, 360.0) }
        private val buttonWidth = book?.buttonWidth ?: metrics.buttonWidth
        private val gap = book?.gap ?: 12.0
        val menusFit = fits(size.width - 2 * metrics.padSide, 5, buttonWidth, gap, metrics.thumbWidth)
        val menusShown = menus && menusFit
        val keys: List<List<KeyRow.Key>> = KeyRow.rows(KeyRow.full(spotlight), metrics.splitKeys || pages != null)
        override val panel = Rect(Ui.panelInset, Ui.panelInset, max(0.0, size.width - 2 * Ui.panelInset), max(0.0, half - 2 * Ui.panelInset))
        override val items: Map<BarItem, Rect>
        override val ruler: Rect
        override val rulerStep = Ui.rulerStepPortrait
        override val drawer: Rect
        override val settings: Rect
        override val settingsAnchorX: Double
        override val settingsAnchorY: Double
        override val dim = listOf(Rect(0.0, 0.0, size.width, size.height))
        override val caps: List<List<Rect>>
        override val trackpad: Rect
        override val trackpadSpan: Double? = null
        override val buttonRadius = metrics.buttonRadius
        override val buttonIcon = metrics.buttonIcon
        override val buttonSpacing = metrics.buttonSpacing
        override val thumbWidth = metrics.thumbWidth
        override val thumbHeight = metrics.thumbHeight
        override val thumbRadius = metrics.thumbRadius
        override val thumbSpacing = metrics.thumbSpacing
        override val thumbPad = metrics.thumbPad
        override val thumbFade = metrics.thumbFade
        override val badge = metrics.badge
        override val lightsBelow = false

        init {
            val left = metrics.padSide
            val rowW = max(0.0, size.width - 2 * metrics.padSide)
            val barY = split.controls + metrics.padTop
            val bw = buttonWidth
            val by = barY + (metrics.barHeight - metrics.buttonHeight) / 2
            val m = LinkedHashMap<BarItem, Rect>()
            m[BarItem.Apps] = Rect(left, by, bw, metrics.buttonHeight)
            val right = listOfNotNull(if (menusShown) BarItem.Menus else null, BarItem.TextSize, BarItem.Desktop, BarItem.Settings)
            var x = left + rowW
            for (item in right.reversed()) { x -= bw; m[item] = Rect(x, by, bw, metrics.buttonHeight); x -= gap }
            val stripX = left + bw + gap
            val stripH = metrics.thumbHeight + 2 * metrics.thumbPad
            m[BarItem.Strip] = Rect(stripX, barY + (metrics.barHeight - stripH) / 2, book?.stripWidth ?: max(0.0, x - stripX), stripH)
            items = BarItem.entries.mapNotNull { k -> m[k]?.let { k to it } }.toMap()

            val aa = items.getValue(BarItem.TextSize)
            val w = TextScale.sliderWidth(rulerStep)
            // On a page, the ruler stays on Aa's page: against the fold or the screen's edge.
            val rx = pages?.let { band -> (aa.midX - w / 2).coerceIn(band.maxX, max(band.maxX, size.width - metrics.padSide - w)) } ?: (aa.midX - w / 2)
            ruler = Rect(rx, aa.minY, w, metrics.buttonHeight)

            val keysTop = barY + metrics.barHeight + metrics.rowGap
            val padTop: Double
            if (pages != null) {
                // The key row's two lines side by side, one on each page; the trackpad on the trailing page.
                val leadW = max(0.0, pages.minX - metrics.keyGap - left)
                val trailX = pages.maxX + metrics.keyGap
                val trailW = max(0.0, size.width - metrics.padSide - trailX)
                caps = keys.mapIndexed { i, row ->
                    val r = if (i == 0) Rect(left, keysTop, leadW, metrics.capHeight) else Rect(trailX, keysTop, trailW, metrics.capHeight)
                    PhonePortraitLayout.split(r, row.size, metrics.keyGap)
                }
                padTop = keysTop + metrics.capHeight + metrics.rowGap
                trackpad = Rect(trailX, padTop, trailW, max(0.0, size.height - metrics.padBottom - padTop))
            } else {
                var y = keysTop
                caps = keys.map { row ->
                    val r = PhonePortraitLayout.split(Rect(left, y, rowW, metrics.capHeight), row.size, metrics.keyGap)
                    y += metrics.capHeight + metrics.keyRowGap
                    r
                }
                padTop = keysTop + metrics.keyBlockHeight + metrics.rowGap
                trackpad = Rect(left, padTop, rowW, max(0.0, size.height - metrics.padBottom - padTop))
            }

            val top = split.controls + metrics.padTop + metrics.barHeight + 8
            drawer = Rect(22.0, top, onLeadingPage(min(Ui.drawerWidth, size.width - 44), 22.0, fold), max(0.0, size.height - metrics.padBottom - top))
            val sw = min(book?.panelWidth ?: 360.0, rowW)
            settings = Rect(size.width - metrics.padSide - sw, top, sw, max(0.0, size.height - metrics.padBottom - top))
            settingsAnchorX = if (size.width > 0) 1 - metrics.padSide / size.width else 1.0
            settingsAnchorY = if (size.height > 0) top / size.height else 0.0
        }
    }

    /** A phone upright (PhonePortraitLayout), Larger Picture included. */
    class Phone(val layout: PhonePortraitLayout, menus: Boolean, video: Size = Size.zero) : StreamLayout() {
        override val size = layout.size
        override val arrangement = ScreenLayout.OuterPortrait
        val metrics = PortraitMetrics.phone
        /** With Larger Picture the Menus button joins row 1; else it ends row 2 under Settings. */
        val menusInRow1 = menus && layout.largerPicture
        val menusShown = menus
        override val panel = layout.pane(video)
        /** The viewport: the picture's pane, or with Larger Picture its whole room. */
        val viewport = layout.picture
        override val items: Map<BarItem, Rect>
        override val ruler = if (menusInRow1) layout.rulerBesideMenus else layout.ruler
        override val rulerStep = if (menusInRow1) layout.rulerStepBesideMenus else layout.rulerStep
        override val drawer = layout.drawer
        override val settings = layout.settings
        override val settingsAnchorX = layout.settingsAnchorX
        override val settingsAnchorY = layout.settingsAnchorY
        override val dim = layout.dim
        override val caps = listOf(layout.caps)
        override val trackpad = layout.trackpad
        override val trackpadSpan = layout.trackpadSpan(video)
        override val buttonRadius = metrics.buttonRadius
        override val buttonIcon = metrics.buttonIcon
        override val buttonSpacing = metrics.buttonSpacing
        override val thumbWidth = metrics.thumbWidth
        override val thumbHeight = metrics.thumbHeight
        override val thumbRadius = metrics.thumbRadius
        override val thumbSpacing = metrics.thumbSpacing
        override val thumbPad = metrics.thumbPad
        override val thumbFade = metrics.thumbFade
        override val badge = metrics.badge
        override val lightsBelow = true

        init {
            val b = if (menusInRow1) layout.buttonsBesideMenus else layout.buttons
            val m = LinkedHashMap<BarItem, Rect>()
            m[BarItem.Apps] = b[PhonePortraitLayout.Button.Apps.ordinal]
            if (!layout.largerPicture) m[BarItem.Strip] = if (menus) layout.stripBesideMenus else layout.strip
            if (menus) m[BarItem.Menus] = layout.menus
            m[BarItem.TextSize] = b[PhonePortraitLayout.Button.TextSize.ordinal]
            m[BarItem.Keyboard] = b[PhonePortraitLayout.Button.Keyboard.ordinal]
            m[BarItem.Desktop] = b[PhonePortraitLayout.Button.Desktop.ordinal]
            m[BarItem.Settings] = b[PhonePortraitLayout.Button.Settings.ordinal]
            items = BarItem.entries.mapNotNull { k -> m[k]?.let { k to it } }.toMap()
        }
    }

    companion object {
        /** The least room under a fold across the screen for the halves' controls and a trackpad:
         *  less than that, and the fold is laid out as if flat (Android's: no Duo is that short). */
        const val minimumTrackpadUnderFold = 60.0

        /** Android's: the drawer kept to the leading page beside a fold down the screen (the Duo's
         *  never reaches its fold), unless that would leave it under 280 points. */
        fun onLeadingPage(width: Double, x: Double, fold: FoldInfo): Double {
            val band = fold.verticalBand ?: return width
            val page = band.minX - x - 8
            return if (x < band.minX && page >= 280) min(width, page) else width
        }

        /** MacMenuButton.fits: the bar holds `buttons` buttons and still a whole thumbnail. */
        fun fits(width: Double, buttons: Int, buttonWidth: Double, gap: Double, thumbWidth: Double) =
            width >= buttons * (buttonWidth + gap) + thumbWidth + 16

        /**
         * The layout for a stream screen of `size` (StreamScreen.body): `phone` says whether an
         * upright screen narrower than 600 draws the phone's arrangement (a phone: yes; a tablet's
         * narrow window: the compact halves), `keyboard` Larger Picture's keyboard height (nil for
         * the standard arrangement), `menus` whether the Mac sent menus, `spotlight` whether the
         * Desktop streams (the key row's Spotlight cap), `video` the picture's pixel size.
         */
        fun of(size: Size, phone: Boolean, menus: Boolean = false, spotlight: Boolean = false,
               keyboard: Double? = null, video: Size = Size.zero, fold: FoldInfo = FoldInfo.Inferred,
               aspect: Double = DuoPosture.defaultAspect): StreamLayout {
            val layout = ScreenLayout.of(size)
            val halves = if (size.width < ScreenLayout.outerMaxWidth) PortraitMetrics.compact else PortraitMetrics.regular
            // A fold across the screen (the laptop pose; on Android also a foldable in tabletop sideways
            // and a flip phone half-open): the halves, split at it, wherever the controls fit under it.
            val across = fold.horizontalBand
            if (across != null && size.height - DuoPosture.portraitSplit(size, fold, aspect, halves.controlsHeight).controls >=
                halves.controlsHeight + minimumTrackpadUnderFold) return Halves(size, halves, menus, spotlight, fold, aspect)
            val flat = if (across != null) FoldInfo.none else fold
            // A fold down an upright screen (Android's book pose held upright): the halves on their pages.
            if (flat.verticalBand != null && layout.isPortrait) return Halves(size, halves, menus, spotlight, flat, aspect)
            return when (layout) {
                ScreenLayout.InnerLandscape -> Landscape(size, BarMetrics.regular, menus, flat)
                ScreenLayout.OuterLandscape -> Landscape(size, BarMetrics.compact, menus, flat)
                ScreenLayout.InnerPortrait -> Halves(size, PortraitMetrics.regular, menus, spotlight, flat, aspect)
                ScreenLayout.OuterPortrait ->
                    if (phone) Phone(PhonePortraitLayout(size, keyboard), menus, video)
                    else Halves(size, PortraitMetrics.compact, menus, spotlight, flat, aspect)
            }
        }
    }
}

/** The halves' controls but the trackpad: the bar, the key row, their gaps and paddings (DuoPostureReader.swift). */
val PortraitMetrics.controlsHeight: Double get() = padTop + barHeight + 2 * rowGap + keyBlockHeight + padBottom

/** The connect screen's column (ConnectLayout in AddMacCard.swift): 380 wide, or the screen less
 *  32 on one narrower than 412, centred across the screen, or across a book pose's fold in its
 *  leading page; in a laptop pose it lives above the fold. */
data class ConnectLayout(val size: Size, val fold: FoldInfo = FoldInfo.Inferred) {
    val columnWidth get() = if (size.width < Ui.columnNarrowBelow) max(200.0, size.width - Ui.columnMargins) else Ui.columnWidth
    val columnX get() = DuoPosture.columnX(columnWidth, size.width, fold)
    /** The laptop pose (or, with no fold known, a Duo-like screen's middle): the room above the fold. */
    val topRoom get() = DuoPosture.crease(size, fold)?.first
    val topHalf get() = topRoom != null
    /** The laptop pose as the device reports it: all the column has; it scrolls there. */
    val roomAboveFold get() = DuoPosture.roomAboveFold(size, fold)
    /** The book pose: the leading page's width. */
    val leadingPage get() = DuoPosture.leadingPage(fold)
    val short get() = size.height < 520 || (roomAboveFold ?: Double.MAX_VALUE) < 520
    val compactPortrait get() = size.height > size.width && size.width < 600
}

/** The Aa control (TextScaleControl in StreamScreen.swift): five detents, the ruler's arithmetic. */
object TextScale {
    val steps = listOf(0.5, 0.75, 1.0, 1.25, 1.5)

    fun sliderWidth(pointsPerStep: Double) = pointsPerStep * (steps.size - 1) + Ui.rulerInset * 2

    fun snap(value: Double): Double {
        val c = min(max(value, steps.first()), steps.last())
        return steps.minByOrNull { kotlin.math.abs(it - c) } ?: 1.0
    }

    /** 0.5, 0.75, 1, 1.25, 1.5: trailing zeros dropped. */
    fun label(scale: Double): String {
        var t = String.format(java.util.Locale.ROOT, "%.2f", scale)
        while (t.endsWith("0")) t = t.dropLast(1)
        if (t.endsWith(".")) t = t.dropLast(1)
        return t
    }

    /** The value a drag of `dx` from where the finger came down gives, starting at `start`. */
    fun dragged(start: Double, dx: Double, pointsPerStep: Double) = snap(start + dx / pointsPerStep * 0.25)

    /** Where a detent sits on the ruler (from its leading edge) while `live` is under the thumb. */
    fun tickX(value: Double, live: Double, pointsPerStep: Double) = sliderWidth(pointsPerStep) / 2 + (value - live) / 0.25 * pointsPerStep

    /** VoiceOver's adjustable action (and the arrow keys on the desktop): one detent up or down. */
    fun step(scale: Double?, up: Boolean): Double {
        val i = steps.indexOf(scale ?: 1.0).let { if (it < 0) 2 else it }
        return steps[if (up) min(i + 1, steps.size - 1) else max(i - 1, 0)]
    }
}
