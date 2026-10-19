package me.saffer.sill.android

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ProgressBar
import android.widget.ScrollView
import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.HostSettingsState
import me.saffer.sill.core.QualityPreset
import me.saffer.sill.core.StreamSettings
import me.saffer.sill.core.ui.PanelCopy
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.SettingsField
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import kotlin.math.max

/** What the Settings panel shows: the Mac's word with this device's picks over it. */
data class PanelModel(
    val mac: String,
    val device: String,
    val host: HostSettingsState?,
    val shown: StreamSettings?,
    val wantedFps: Int,
    val lowPower: Boolean,
    val olderMac: Boolean,
    val problem: String?,
    val pendingSince: (SettingsField) -> Double?,
    val now: Double,
    /** This device's Keep Screen On (its own preference, never sent). */
    val keepScreenOn: Boolean = true,
)

/**
 * The Settings panel (HostSettingsPanel): the Mac's name and what runs, Done; the Mac's streaming
 * settings in groups with PanelCopy's footnotes and callouts, each control sending only what it
 * changes (SettingsLedger); Disconnect pinned at the foot. As tall as its content, scrolling when
 * the room is shorter.
 */
@SuppressLint("ViewConstructor")
class SettingsPanelView(context: Context, dp: Dp) : Sheet(context, dp) {
    var onChange: (HostSettingsChange) -> Unit = {}
    var onDone: () -> Unit = {}
    var onDisconnect: () -> Unit = {}
    var onKeepScreenOn: (Boolean) -> Unit = {}
    /** The most height the panel may take (core's layout gives the room). */
    var maxHeight = Int.MAX_VALUE

    private val header = Header(context, dp)
    private val middle = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(context).apply { addView(middle); overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS; isVerticalScrollBarEnabled = true }
    private val foot = FootButton(context, dp)
    private var model: PanelModel? = null

    init {
        addView(header); addView(scroll); addView(foot)
        header.onDone = { onDone() }
        foot.setOnClickListener { onDisconnect() }
        accessibilityPaneTitle = "Settings"
    }

    fun update(m: PanelModel) {
        model = m
        header.set(m)
        foot.mac = m.mac
        foot.contentDescription = PanelCopy.disconnect(PanelCopy.macName(m.mac))
        rebuild(m)
        requestLayout()
    }

    private fun rebuild(m: PanelModel) {
        middle.removeAllViews()
        val mac = PanelCopy.macName(m.mac)
        val host = m.host
        val shown = m.shown
        if (host != null && shown != null) {
            if (host.softwareEncoder) middle.addView(Callout(context, dp, PanelCopy.softwareEncoder(mac)))
            m.problem?.let { middle.addView(Callout(context, dp, it)) }
            val stream = Group(context, dp)
            // "Balanced — 15 Mbps", as the iOS Picker shows QualityPreset.title (its menu the same).
            val qualityTitle = PanelCopy.qualityChoices(shown.bitrate).first { it.second == shown.bitrate }.first
            stream.add(ValueRow(context, dp, PanelCopy.quality, qualityTitle, pending(m, SettingsField.Bitrate)) { anchor ->
                PopupMenu(context, anchor, Gravity.END).apply {
                    PanelCopy.qualityChoices(shown.bitrate).forEach { (label, bitrate) ->
                        menu.add((if (bitrate == shown.bitrate) "✓ " else "") + label).apply {
                            isEnabled = QualityPreset.of(bitrate) != null
                            setOnMenuItemClickListener { onChange(HostSettingsChange(bitrate = bitrate)); true }
                        }
                    }
                }.show()
            })
            stream.add(SegmentRow(context, dp, PanelCopy.resolution, PanelCopy.resolutions.map { it.first },
                PanelCopy.resolutions.indexOfFirst { it.second == shown.captureScale }, pending(m, SettingsField.CaptureScale)) { i ->
                onChange(HostSettingsChange(captureScale = PanelCopy.resolutions[i].second))
            })
            stream.add(SegmentRow(context, dp, PanelCopy.frameRate, PanelCopy.frameRates.map { it.first },
                PanelCopy.frameRates.indexOfFirst { it.second == shown.maxFPS }, pending(m, SettingsField.MaxFPS)) { i ->
                onChange(HostSettingsChange(maxFPS = PanelCopy.frameRates[i].second))
            })
            middle.addView(stream)
            middle.addView(Footnote(context, dp, PanelCopy.streamFooter(m.device, m.wantedFps, lowPower = m.lowPower)))
            middle.addView(Group(context, dp).apply {
                add(SwitchRow(context, dp, PanelCopy.prioritizeSpeed, shown.prioritizeSpeed, true, pending(m, SettingsField.PrioritizeSpeed)) {
                    onChange(HostSettingsChange(prioritizeSpeed = it))
                })
            })
            middle.addView(Footnote(context, dp, PanelCopy.speedFooter(mac)))
            val unavailable = !host.virtualDisplayAvailable && !shown.virtualDisplay
            middle.addView(Group(context, dp).apply {
                add(SwitchRow(context, dp, PanelCopy.virtualDisplay, shown.virtualDisplay, !unavailable, pending(m, SettingsField.VirtualDisplay)) {
                    onChange(HostSettingsChange(virtualDisplay = it))
                })
            })
            val note = host.virtualDisplayNote
            middle.addView(if (note != null) Footnote(context, dp, note, warning = true) else Footnote(context, dp, PanelCopy.virtualDisplayFooter(mac)))
            middle.addView(Footnote(context, dp, PanelCopy.appliesFooter(mac)))
            shown.directWireless?.let { direct ->
                middle.addView(Group(context, dp).apply {
                    add(SwitchRow(context, dp, PanelCopy.directWireless, direct, true, pending(m, SettingsField.DirectWireless)) {
                        onChange(HostSettingsChange(directWireless = it))
                    })
                })
                middle.addView(Footnote(context, dp, PanelCopy.directFooter(mac, m.device, direct, connectedDirectly = false)))
            }
            if (!host.persistent) middle.addView(Footnote(context, dp, PanelCopy.persistentNote))
        } else if (m.olderMac) {
            middle.addView(Line(context, dp, PanelCopy.olderMac(mac), Symbol.UpdateCircle, Type.body, Palette.text))
        } else {
            middle.addView(Line(context, dp, PanelCopy.loading, null, Type.footnote, Palette.muted, spinner = true))
        }
        // This device's own group, after the Mac's, whatever the Mac runs.
        middle.addView(Line(context, dp, PanelCopy.thisDevice(m.device), null, Type.footnote, Palette.muted).apply {
            isAccessibilityHeading = true
            setPadding(0, dp(6.0).toInt(), 0, 0)
        })
        middle.addView(Group(context, dp).apply {
            add(SwitchRow(context, dp, PanelCopy.keepScreenOn, m.keepScreenOn, true, false) { onKeepScreenOn(it) })
        })
        middle.addView(Footnote(context, dp, PanelCopy.keepScreenOnFooter(mac, m.device, m.keepScreenOn)))
    }

    private fun pending(m: PanelModel, f: SettingsField) = m.pendingSince(f)?.let { m.now - it >= Ui.pendingDelay } ?: false

    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w)
        val pad = dp(Ui.sheetPadding).toInt()
        val inner = MeasureSpec.makeMeasureSpec(width - 2 * pad, MeasureSpec.EXACTLY)
        header.measure(inner, MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        foot.measure(inner, MeasureSpec.makeMeasureSpec(dp(Ui.footHeight + 10).toInt(), MeasureSpec.EXACTLY))
        val room = max(0, maxHeight - 2 * pad - header.measuredHeight - foot.measuredHeight)
        scroll.measure(inner, MeasureSpec.makeMeasureSpec(room, MeasureSpec.AT_MOST))
        setMeasuredDimension(width, 2 * pad + header.measuredHeight + scroll.measuredHeight + foot.measuredHeight)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val pad = dp(Ui.sheetPadding).toInt()
        var y = pad
        header.layout(pad, y, pad + header.measuredWidth, y + header.measuredHeight); y += header.measuredHeight
        scroll.layout(pad, y, pad + scroll.measuredWidth, y + scroll.measuredHeight); y += scroll.measuredHeight
        foot.layout(pad, y, pad + foot.measuredWidth, y + foot.measuredHeight)
    }

    /** The Mac's name (headline), the readout (footnote, muted) and Done. */
    private class Header(context: Context, private val dp: Dp) : ViewGroup(context) {
        var onDone: () -> Unit = {}
        private val name = TextPaint(Look.textPaint(dp, Type.headline, Palette.text))
        private val readout = TextPaint(Look.textPaint(dp, Type.footnote, Palette.muted)).apply { fontFeatureSettings = "tnum" }
        private val done = Look.textPaint(dp, Type.bodySemibold, Palette.accent)
        private var title = ""
        private var lines = ""
        private var nameLayout: StaticLayout? = null
        private var readLayout: StaticLayout? = null
        private val doneView = object : View(context) {
            init { isClickable = true; isFocusable = true; contentDescription = PanelCopy.done; setOnClickListener { onDone() } }
            override fun onDraw(c: Canvas) {
                done.alpha = if (isPressed) 120 else 255
                Look.textCentred(c, PanelCopy.done, width / 2f, height / 2f, done)
            }
            override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }
            override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) { super.onInitializeAccessibilityNodeInfo(info); info.className = "android.widget.Button" }
        }

        init { setWillNotDraw(false); addView(doneView) }

        fun set(m: PanelModel) {
            title = PanelCopy.title(m.mac)
            val stream = m.host?.stream
            lines = if (m.host == null) "" else PanelCopy.readout(stream) + if (stream?.onVirtualDisplay == true) "\n" + PanelCopy.onVirtualDisplay else ""
            contentDescription = listOf(title, lines.replace("\n", ", ")).filter { it.isNotEmpty() }.joinToString(", ")
            isFocusable = true
            requestLayout(); invalidate()
        }

        override fun onMeasure(w: Int, h: Int) {
            val width = MeasureSpec.getSize(w)
            val doneW = (done.measureText(PanelCopy.done) + dp(8.0)).toInt()
            doneView.measure(MeasureSpec.makeMeasureSpec(max(doneW, dp(48.0).toInt()), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(dp(48.0).toInt(), MeasureSpec.EXACTLY))
            val textW = max(1, width - doneView.measuredWidth - dp(8.0 + 8.0).toInt())
            nameLayout = StaticLayout.Builder.obtain(title, 0, title.length, name, textW).setMaxLines(2).setEllipsize(android.text.TextUtils.TruncateAt.END).build()
            readLayout = if (lines.isEmpty()) null else StaticLayout.Builder.obtain(lines, 0, lines.length, readout, textW).build()
            val textH = nameLayout!!.height + (readLayout?.let { it.height + dp(2.0).toInt() } ?: 0)
            setMeasuredDimension(width, max(textH, dp(44.0).toInt()) + dp(12.0).toInt())
        }

        override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
            val x = width - dp(4.0).toInt() - doneView.measuredWidth + dp(4.0).toInt()
            val top = ((nameLayout?.getLineBottom(0) ?: dp(22.0).toInt()) - doneView.measuredHeight) / 2
            doneView.layout(x, top, x + doneView.measuredWidth, top + doneView.measuredHeight)
        }

        override fun onDraw(c: Canvas) {
            c.save(); c.translate(dp(4.0), 0f)
            nameLayout?.draw(c)
            readLayout?.let { c.translate(0f, (nameLayout?.height ?: 0) + dp(2.0)); it.draw(c) }
            c.restore()
        }
    }

    /** Disconnect: 44 pt on the control colour, the accent's xmark.circle and words. */
    private class FootButton(context: Context, private val dp: Dp) : View(context) {
        var mac = ""
        private val bg = Look.fill(Palette.control)
        private val text = Look.textPaint(dp, Type.body, Palette.accent)
        private val rect = RectF()
        init { isClickable = true; isFocusable = true }
        override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }
        override fun onDraw(c: Canvas) {
            val top = dp(10.0)
            val r = rect.apply { set(0f, top, width.toFloat(), height.toFloat()) }
            c.drawRoundRect(r, dp(Ui.fieldRadius), dp(Ui.fieldRadius), bg)
            val glyph = dp(Symbol.boxFor(17.0))
            Look.symbol(c, dp, Symbol.XmarkCircle, dp(14.0) + glyph / 2, r.centerY(), 17.0, Palette.accent, Palette.control)
            val room = width - dp(14.0 + 8.0 + 14.0) - glyph
            val long = PanelCopy.disconnect(PanelCopy.macName(mac))
            val words = if (text.measureText(long) <= room) long else PanelCopy.disconnectShort
            Look.textLeft(c, Look.fit(words, text, room), dp(14.0 + 8.0) + glyph, r.centerY(), text)
            if (isPressed) c.drawRoundRect(r, dp(Ui.fieldRadius), dp(Ui.fieldRadius), BarButton.pressed)
        }
        override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) { super.onInitializeAccessibilityNodeInfo(info); info.className = "android.widget.Button" }
    }
}

/** Rows on the control colour, 12 pt corners, hairlines between them inset 14 pt (Rows, RowDivider). */
class Group(context: Context, private val dp: Dp) : LinearLayout(context) {
    private val bg = Look.fill(Palette.control)
    private val divider = Look.fill(Rgba.white.opacity(Ui.dividerAlpha))
    init { orientation = VERTICAL; setWillNotDraw(false) }
    fun add(v: View) = addView(v, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    override fun onDraw(c: Canvas) {
        c.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), dp(Ui.fieldRadius), dp(Ui.fieldRadius), bg)
        for (i in 1 until childCount) {
            val y = getChildAt(i).top.toFloat()
            c.drawRect(dp(Ui.rowInset), y - dp(Ui.dividerHeight) / 2, width - dp(Ui.rowInset), y + dp(Ui.dividerHeight) / 2, divider)
        }
    }
}

/** A row's frame: at least 44 pt tall, its title on the left with the pending spinner beside it. */
abstract class SettingRow(context: Context, protected val dp: Dp, val title: String, private val pending: Boolean) : ViewGroup(context) {
    protected val titlePaint = Look.textPaint(dp, Type.body, Palette.text)
    private val spinner = ProgressBar(context, null, android.R.attr.progressBarStyleSmall).apply {
        indeterminateTintList = ColorStateList.valueOf(Palette.muted.argb)
        visibility = if (pending) VISIBLE else GONE
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    init { setWillNotDraw(false); addView(spinner) }
    protected abstract val control: View
    protected val inset get() = dp(Ui.rowInset).toInt()

    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w)
        control.measure(MeasureSpec.makeMeasureSpec(width - 2 * inset, MeasureSpec.AT_MOST), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        spinner.measure(MeasureSpec.makeMeasureSpec(dp(16.0).toInt(), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(dp(16.0).toInt(), MeasureSpec.EXACTLY))
        val titleW = titlePaint.measureText(title)
        // Larger text: the control under the title when it does not fit beside it (AdaptiveRow).
        val stacked = titleW + dp(6.0 + 16.0 + 12.0) + control.measuredWidth > width - 2 * inset
        this.stacked = stacked
        val lineH = dp(44.0).toInt()
        setMeasuredDimension(width, if (stacked) lineH + control.measuredHeight + dp(10.0).toInt() else max(lineH, control.measuredHeight + dp(12.0).toInt()))
    }
    private var stacked = false

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val titleH = if (stacked) dp(44.0).toInt() else height
        val sx = inset + titlePaint.measureText(title).toInt() + dp(6.0).toInt()
        spinner.layout(sx, (titleH - spinner.measuredHeight) / 2, sx + spinner.measuredWidth, (titleH + spinner.measuredHeight) / 2)
        val cw = control.measuredWidth; val ch = control.measuredHeight
        if (stacked) control.layout(inset, titleH, inset + cw, titleH + ch)
        else control.layout(width - inset - cw, (height - ch) / 2, width - inset, (height + ch) / 2)
    }

    override fun onDraw(c: Canvas) {
        val titleH = if (stacked) dp(44.0) else height.toFloat()
        Look.textLeft(c, Look.fit(title, titlePaint, width - 2f * inset), inset.toFloat(), titleH / 2, titlePaint)
    }
}

/** Quality: the value in the accent, a menu of the presets on a tap (`.pickerStyle(.menu)`). */
@SuppressLint("ViewConstructor")
class ValueRow(context: Context, dp: Dp, title: String, value: String, pending: Boolean, open: (View) -> Unit) : SettingRow(context, dp, title, pending) {
    override val control = object : View(context) {
        private val p = Look.textPaint(dp, Type.body, Palette.accent)
        init { isClickable = true; isFocusable = true; contentDescription = "$title, $value"; setOnClickListener { open(this) } }
        override fun onMeasure(w: Int, h: Int) = setMeasuredDimension((p.measureText(value) + dp(4.0 + 14.0)).toInt().coerceAtMost(MeasureSpec.getSize(w)), dp(44.0).toInt())
        override fun onDraw(c: Canvas) {
            p.alpha = if (isPressed) 120 else 255
            Look.textLeft(c, Look.fit(value, p, width - dp(16.0)), 0f, height / 2f, p)
            // The menu picker's up-and-down chevrons.
            val x = width - dp(7.0)
            Look.symbol(c, dp, Symbol.ChevronUp, x, height / 2f - dp(3.5), 7.0, Palette.accent, Palette.control)
            Look.symbol(c, dp, Symbol.ChevronDown, x, height / 2f + dp(3.5), 7.0, Palette.accent, Palette.control)
        }
        override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }
        override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) { super.onInitializeAccessibilityNodeInfo(info); info.className = "android.widget.Spinner" }
    }
    init { addView(control) }
}

/** Resolution and Frame Rate: a segmented control (`.pickerStyle(.segmented)`); a Mac-held value selects none. */
@SuppressLint("ViewConstructor")
class SegmentRow(context: Context, dp: Dp, title: String, segments: List<String>, selected: Int, pending: Boolean, pick: (Int) -> Unit) : SettingRow(context, dp, title, pending) {
    override val control = Segmented(context, dp, title, segments, selected, pick)
    init { addView(control) }
}

@SuppressLint("ViewConstructor")
class Segmented(context: Context, private val dp: Dp, private val title: String, private val segments: List<String>, private val selected: Int, private val pick: (Int) -> Unit) : View(context) {
    private val track = Look.fill(Rgba(0x767680, 0.24))
    private val thumb = Look.fill(Rgba(0x636366))
    private val text = Look.textPaint(dp, TextStyle(13.0, TextStyle.Weight.Medium), Palette.text)
    private val segW get() = segments.maxOf { text.measureText(it) } + dp(24.0)
    init { isFocusable = true; contentDescription = "$title, ${segments.getOrNull(selected) ?: "none"}" }
    override fun onMeasure(w: Int, h: Int) = setMeasuredDimension((segW * segments.size).toInt().coerceAtMost(MeasureSpec.getSize(w)), dp(Targets.MIN).toInt())
    override fun onDraw(c: Canvas) {
        val h = dp(32.0); val top = (height - h) / 2
        c.drawRoundRect(0f, top, width.toFloat(), top + h, dp(9.0), dp(9.0), track)
        val sw = width.toFloat() / segments.size
        if (selected in segments.indices) c.drawRoundRect(selected * sw + dp(2.0), top + dp(2.0), (selected + 1) * sw - dp(2.0), top + h - dp(2.0), dp(7.0), dp(7.0), thumb)
        segments.forEachIndexed { i, s -> Look.textCentred(c, Look.fit(s, text, sw - dp(8.0)), i * sw + sw / 2, height / 2f, text) }
    }
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (e.actionMasked == MotionEvent.ACTION_UP) {
            val i = (e.x / (width.toFloat() / segments.size)).toInt().coerceIn(0, segments.size - 1)
            if (i != selected) { Haptics.detent(this); pick(i) }
            performClick()
        }
        return true
    }
    override fun performClick(): Boolean { super.performClick(); return true }
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.RadioGroup"
        segments.forEachIndexed { i, s -> info.addAction(AccessibilityNodeInfo.AccessibilityAction(SEG_BASE + i, s)) }
    }
    override fun performAccessibilityAction(action: Int, arguments: android.os.Bundle?): Boolean {
        val i = action - SEG_BASE
        if (i in segments.indices) { if (i != selected) pick(i); return true }
        return super.performAccessibilityAction(action, arguments)
    }
    companion object { const val SEG_BASE = 0x5e60000 }
}

/** A switch in the accent (`.tint(Palette.accent)` on a Toggle). */
@SuppressLint("ViewConstructor")
class SwitchRow(context: Context, dp: Dp, title: String, on: Boolean, enabled: Boolean, pending: Boolean, set: (Boolean) -> Unit) : SettingRow(context, dp, title, pending) {
    override val control = object : View(context) {
        private val trackOn = Look.fill(Palette.accent)
        private val trackOff = Look.fill(Rgba(0x787880, 0.32))
        private val knob = Look.fill(Rgba.white).apply { setShadowLayer(dp(2.0), 0f, dp(1.0), Rgba.black.opacity(0.25).argb) }
        init {
            isClickable = enabled; isFocusable = true; isEnabled = enabled; alpha = if (enabled) 1f else 0.45f
            contentDescription = title
            setOnClickListener { if (enabled) set(!on) }
            setLayerType(LAYER_TYPE_SOFTWARE, null)
        }
        override fun onMeasure(w: Int, h: Int) = setMeasuredDimension(dp(51.0 + 8).toInt(), dp(Targets.MIN).toInt())
        override fun onDraw(c: Canvas) {
            val w = dp(51.0); val h = dp(31.0); val x = width - w; val y = (height - h) / 2
            c.drawRoundRect(x, y, x + w, y + h, h / 2, h / 2, if (on) trackOn else trackOff)
            val k = h - dp(4.0)
            c.drawCircle(if (on) x + w - dp(2.0) - k / 2 else x + dp(2.0) + k / 2, y + h / 2, k / 2, knob)
        }
        override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
            super.onInitializeAccessibilityNodeInfo(info)
            info.className = "android.widget.Switch"; info.isCheckable = true; info.isChecked = on
        }
    }
    init { addView(control) }
}

/** A footnote under a group: 13 pt, muted, or orange with the warning symbol. */
@SuppressLint("ViewConstructor")
class Footnote(context: Context, private val dp: Dp, private val text: String, private val warning: Boolean = false) : View(context) {
    private val paint = TextPaint(Look.textPaint(dp, Type.footnote, if (warning) Rgba.orange else Palette.muted))
    private var layout: StaticLayout? = null
    private val glyphW get() = if (warning) dp(Symbol.boxFor(13.0) + 6.0) else 0f
    init { contentDescription = text }
    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w)
        layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, max(1, (width - dp(28.0) - glyphW).toInt())).build()
        setMeasuredDimension(width, layout!!.height + dp(6.0 + 12.0).toInt())
    }
    override fun onDraw(c: Canvas) {
        val l = layout ?: return
        if (warning) Look.symbol(c, dp, Symbol.Warning, dp(14.0) + dp(Symbol.boxFor(13.0)) / 2, dp(6.0) + l.getLineBaseline(0) - paint.textSize * 0.35f, 13.0, Rgba.orange, Palette.bar)
        c.save(); c.translate(dp(14.0) + glyphW, dp(6.0)); l.draw(c); c.restore()
    }
}

/** Something to know before touching anything (Callout): orange on a faint orange card. */
@SuppressLint("ViewConstructor")
class Callout(context: Context, private val dp: Dp, private val text: String) : View(context) {
    private val paint = TextPaint(Look.textPaint(dp, Type.footnote, Palette.text))
    private val bg = Look.fill(Rgba.orange.opacity(0.14))
    private var layout: StaticLayout? = null
    private val glyph get() = dp(Symbol.boxFor(13.0))
    init { contentDescription = text }
    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w)
        layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, max(1, (width - dp(24.0 + 8.0) - glyph).toInt())).build()
        setMeasuredDimension(width, layout!!.height + dp(24.0 + 10.0).toInt())
    }
    override fun onDraw(c: Canvas) {
        val l = layout ?: return
        c.drawRoundRect(0f, 0f, width.toFloat(), height - dp(10.0), dp(Ui.fieldRadius), dp(Ui.fieldRadius), bg)
        Look.symbol(c, dp, Symbol.Warning, dp(12.0) + glyph / 2, dp(12.0) + l.getLineBaseline(0) - paint.textSize * 0.35f, 13.0, Rgba.orange, Palette.bar)
        c.save(); c.translate(dp(12.0 + 8.0) + glyph, dp(12.0)); l.draw(c); c.restore()
    }
}

/** A line with a symbol or a spinner (an older Mac, the settings loading). */
@SuppressLint("ViewConstructor")
class Line(context: Context, private val dp: Dp, private val text: String, private val symbol: Symbol?, style: TextStyle, color: Rgba, spinner: Boolean = false) : ViewGroup(context) {
    private val paint = TextPaint(Look.textPaint(dp, style, color))
    private var layout: StaticLayout? = null
    private val spin = if (spinner) ProgressBar(context, null, android.R.attr.progressBarStyleSmall).apply {
        indeterminateTintList = ColorStateList.valueOf(Palette.muted.argb)
    } else null
    private val lead get() = dp(4.0) + if (symbol != null || spin != null) dp(20.0 + 8.0) else 0f
    init { setWillNotDraw(false); spin?.let(::addView); contentDescription = text }
    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w)
        layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, max(1, (width - lead).toInt())).setAlignment(Layout.Alignment.ALIGN_NORMAL).build()
        spin?.measure(MeasureSpec.makeMeasureSpec(dp(16.0).toInt(), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(dp(16.0).toInt(), MeasureSpec.EXACTLY))
        setMeasuredDimension(width, max(dp(44.0).toInt(), layout!!.height + dp(12.0).toInt()))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        spin?.let { it.layout(dp(4.0).toInt(), (height - it.measuredHeight) / 2, dp(4.0).toInt() + it.measuredWidth, (height + it.measuredHeight) / 2) }
    }
    override fun onDraw(c: Canvas) {
        val l = layout ?: return
        symbol?.let { Look.symbol(c, dp, it, dp(4.0 + 10.0), height / 2f, 17.0, Palette.text, Palette.bar) }
        c.save(); c.translate(lead, (height - l.height) / 2f); l.draw(c); c.restore()
    }
}
