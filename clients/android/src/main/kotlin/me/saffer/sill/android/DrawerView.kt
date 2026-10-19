package me.saffer.sill.android

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import me.saffer.sill.core.AppInfo
import me.saffer.sill.core.WindowInfo
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui

/**
 * A sheet over the stream (the Apps drawer and the Settings panel): the bar's colour, 20 pt
 * corners, a white hairline and the iOS shadow, 14 pt inside.
 */
abstract class Sheet(context: Context, protected val dp: Dp) : ViewGroup(context) {
    private val fill = Look.fill(Palette.bar).apply {
        setShadowLayer(dp(Ui.sheetShadowRadius / 2), 0f, dp(Ui.sheetShadowY / 2), Rgba.black.opacity(Ui.sheetShadowAlpha).argb)
    }
    private val line = Look.stroke(Rgba.white.opacity(Ui.sheetStrokeAlpha), dp(1.0))

    private val r = RectF()
    init { setWillNotDraw(false); setLayerType(LAYER_TYPE_SOFTWARE, null); isClickable = true }

    override fun onDraw(c: Canvas) {
        r.set(0f, 0f, width.toFloat(), height.toFloat())
        val rad = dp(Ui.sheetRadius)
        c.drawRoundRect(r, rad, rad, fill)
        Look.strokeBorder(c, r, rad, line)
    }

    protected fun text(style: TextStyle, color: Rgba) = TextView(context).apply {
        typeface = Look.typeface(style.weight)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, dp.text(style))
        setTextColor(color.argb)
        includeFontPadding = false
    }
}

/** One app in the drawer: its icon (or its first two letters), its name, and its windows' count. */
@SuppressLint("ViewConstructor")
class AppRowView(context: Context, private val dp: Dp, val name: String, val icon: Bitmap?, val trailing: String?, val rowHeight: Double) : View(context) {
    var highlighted = false
    private val title = Look.textPaint(dp, Type.rowTitle, Palette.text)
    private val trail = Look.textPaint(dp, Type.rowTrailing, Palette.muted)
    private val iconBg = Look.fill(Palette.iconFallback)
    private val hi = Look.fill(Palette.control)
    private val initials = Look.textPaint(dp, TextStyle(13.0, TextStyle.Weight.Semibold), Rgba.white, capped = false)
    private val bitmap = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val clip = Path()

    init {
        isClickable = true; isFocusable = true
        contentDescription = listOfNotNull(name, trailing).joinToString(", ")
        minimumHeight = dp(rowHeight).toInt()
    }

    override fun onMeasure(w: Int, h: Int) = setMeasuredDimension(MeasureSpec.getSize(w), dp(rowHeight).toInt())
    override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }

    override fun onDraw(c: Canvas) {
        if (highlighted || isPressed) c.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), dp(Ui.rowRadius), dp(Ui.rowRadius), hi)
        val s = dp(Ui.rowIcon); val x = dp(10.0); val y = (height - s) / 2
        val r = rect.apply { set(x, y, x + s, y + s) }
        val ir = dp(Ui.rowIconRadius)
        if (icon != null) {
            clip.reset(); clip.addRoundRect(r, ir, ir, Path.Direction.CW)
            c.save(); c.clipPath(clip); c.drawBitmap(icon, null, r, bitmap); c.restore()
        } else {
            c.drawRoundRect(r, ir, ir, iconBg)
            Look.textCentred(c, Look.initials(name), r.centerX(), r.centerY(), initials)
        }
        val tx = r.right + dp(12.0)
        var room = width - tx - dp(10.0)
        val tr = trailing
        if (tr != null) {
            val tw = trail.measureText(tr)
            Look.textLeft(c, tr, width - dp(10.0) - tw, height / 2f, trail)
            room -= tw + dp(8.0)
        }
        Look.textLeft(c, Look.fit(name, title, room), tx, height / 2f, title)
    }
}

/**
 * The Apps drawer (AppDrawer): a search field, the apps with windows open ("Open now", how many
 * each), then every app ("All apps"); a tap on an open one shows its next window, on another
 * launches it, and either closes the drawer.
 */
@SuppressLint("ViewConstructor")
class DrawerView(context: Context, dp: Dp) : Sheet(context, dp) {
    var onPickWindow: (Long) -> Unit = {}
    var onLaunch: (String) -> Unit = {}
    private val search = SearchField(context, dp)
    private val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(context).apply { addView(list); isVerticalScrollBarEnabled = true; overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS }
    private var windows: List<WindowInfo> = emptyList()
    private var active: Long? = null
    private var apps: List<AppInfo> = emptyList()
    private var icons: Map<String, Bitmap> = emptyMap()

    init {
        addView(search); addView(scroll)
        search.field.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) = rebuild()
        })
    }

    fun setMac(name: String) { search.field.hint = Copy.searchApps(name.ifEmpty { "the Mac" }) }

    fun update(windows: List<WindowInfo>, active: Long?, apps: List<AppInfo>, icons: Map<String, Bitmap>) {
        this.windows = windows; this.active = active; this.apps = apps; this.icons = icons
        rebuild()
    }

    fun clearSearch() { search.field.setText("") }

    private fun rebuild() {
        list.removeAllViews()
        val q = search.field.text.toString().trim()
        fun match(n: String) = q.isEmpty() || n.contains(q, ignoreCase = true)
        val open = windows.groupBy { it.bundleID }.entries.filter { match(it.value.first().appName) }
        if (open.isNotEmpty()) {
            list.addView(header(Copy.openNow))
            for ((bundle, ws) in open) {
                val row = AppRowView(context, dp, ws.first().appName, icons[bundle], Copy.windows(ws.size), Ui.openRowHeight)
                row.highlighted = ws.any { it.id == active }
                row.setOnClickListener {
                    // An open app again shows its next window.
                    val i = ws.indexOfFirst { it.id == active }
                    onPickWindow(ws[(i + 1).mod(ws.size)].id)
                }
                list.addView(row)
            }
        }
        val all = apps.filter { match(it.name) }
        if (all.isNotEmpty()) {
            list.addView(header(Copy.allApps))
            for (a in all) {
                val row = AppRowView(context, dp, a.name, icons[a.bundleID], null, Ui.closedRowHeight)
                row.setOnClickListener { onLaunch(a.bundleID) }
                list.addView(row)
            }
        }
    }

    private fun header(t: String) = text(Type.sectionHeader, Palette.muted).apply {
        text = t
        setPadding(dp(10.0).toInt(), dp(14.0).toInt(), 0, dp(6.0).toInt())
        isAccessibilityHeading = true
    }

    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w); val height = MeasureSpec.getSize(h)
        val pad = dp(Ui.sheetPadding).toInt()
        val inner = width - 2 * pad
        search.measure(MeasureSpec.makeMeasureSpec(inner, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(dp(Ui.searchHeight).toInt(), MeasureSpec.EXACTLY))
        scroll.measure(MeasureSpec.makeMeasureSpec(inner, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec((height - 2 * pad - search.measuredHeight - dp(6.0).toInt()).coerceAtLeast(0), MeasureSpec.EXACTLY))
        setMeasuredDimension(width, height)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val pad = dp(Ui.sheetPadding).toInt()
        search.layout(pad, pad, pad + search.measuredWidth, pad + search.measuredHeight)
        val top = pad + search.measuredHeight + dp(6.0).toInt()
        scroll.layout(pad, top, pad + scroll.measuredWidth, top + scroll.measuredHeight)
    }
}

/** A 48 pt field on the control colour (the drawer's search, PairingField): a magnifier or none, and the text. */
@SuppressLint("ViewConstructor")
class SearchField(context: Context, private val dp: Dp, private val magnifier: Boolean = true) : ViewGroup(context) {
    val field = EditText(context).apply {
        background = null
        typeface = Look.typeface(Type.search.weight)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, dp.text(Type.search))
        setTextColor(Palette.text.argb)
        setHintTextColor(Palette.muted.argb)
        setSingleLine()
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        imeOptions = EditorInfo.IME_ACTION_SEARCH or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, 0, 0, 0)
        includeFontPadding = false
    }
    private val bg = Look.fill(Palette.control)

    init { setWillNotDraw(false); addView(field) }

    override fun onDraw(c: Canvas) {
        c.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), dp(Ui.fieldRadius), dp(Ui.fieldRadius), bg)
        if (magnifier) Look.symbol(c, dp, Symbol.Magnifier, dp(14.0) + dp(Symbol.boxFor(Ui.searchIconSize)) / 2, height / 2f, Ui.searchIconSize, Palette.muted, Palette.control)
    }

    private val textLeft get() = (if (magnifier) dp(14.0 + Symbol.boxFor(Ui.searchIconSize) + 8.0) else dp(14.0)).toInt()

    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w)
        val height = dp(Ui.searchHeight).toInt()
        field.measure(MeasureSpec.makeMeasureSpec((width - textLeft - dp(14.0).toInt()).coerceAtLeast(0), MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
        setMeasuredDimension(width, height)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        field.layout(textLeft, 0, textLeft + field.measuredWidth, field.measuredHeight)
    }

    override fun dispatchKeyEventPreIme(event: KeyEvent): Boolean = super.dispatchKeyEventPreIme(event)
}

/** A view's children for `View.forEach`-style walks without AndroidX. */
internal fun ViewGroup.children(): List<View> = (0 until childCount).map { getChildAt(it) }
