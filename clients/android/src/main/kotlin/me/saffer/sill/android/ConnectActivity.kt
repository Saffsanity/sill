package me.saffer.sill.android

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.EditorInfo
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import me.saffer.sill.core.ClientListener
import me.saffer.sill.core.GoodbyePolicy
import me.saffer.sill.core.MacRow
import me.saffer.sill.core.PairLink
import me.saffer.sill.core.PairOutcome
import me.saffer.sill.core.PairingPrompt
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.ui.ConnectLayout
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.PlatformCopy
import me.saffer.sill.core.ui.FoldInfo
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Size
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import kotlin.math.max

/**
 * The connect screen (ContentView's ConnectScreen): "Connect to a Mac", the status line, the Macs
 * this device sees and the saved ones as rows that end in how each is reached, Add a Mac… with its
 * card in the column (the address and code its pairing window shows, or a pairing link), the card
 * again when a Mac shows a code for a tap or a pairing link arrives from the camera app (always
 * confirmed), and the footer with where to get Sill for the Mac. The column sits per ConnectLayout:
 * centred, beside a book pose's fold in the leading page, above a laptop pose's fold.
 */
class ConnectActivity : Activity(), ClientListener {
    private val app get() = application as SillApp
    private lateinit var dp: Dp
    private lateinit var root: ConnectRoot
    private lateinit var status: TextView
    private lateinit var rows: LinearLayout
    private lateinit var addMac: TextView
    private lateinit var card: PairCard
    private var insets = Insets.zero
    private lateinit var foldReader: FoldReader
    private var reading: FoldMapping.Reading = FoldMapping.Reading.Nothing

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dp = Dp(this)
        Look.edgeToEdge(this)
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        column.addView(label(Type.connectTitle, Palette.text).apply { text = Copy.connectTitle; isAccessibilityHeading = true })
        status = label(Type.connectStatus, Palette.muted).apply { setPadding(0, dp(4.0).toInt(), 0, 0); accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE }
        column.addView(status)
        rows = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(0, dp(12.0).toInt(), 0, 0) }
        column.addView(rows)
        addMac = label(Type.connectLink, Palette.accent).apply {
            text = Copy.addMac
            gravity = Gravity.CENTER_VERTICAL
            minHeight = dp(Targets.MIN).toInt()
            setPadding(dp(10.0).toInt(), 0, dp(10.0).toInt(), 0)
            isClickable = true; isFocusable = true
            setOnClickListener { card.showAdd() }
        }
        column.addView(addMac, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        card = PairCard(this, dp, app).apply { visibility = View.GONE; onChanged = { addMac.visibility = if (visibility == View.VISIBLE) View.GONE else View.VISIBLE } }
        column.addView(card)
        root = ConnectRoot(this, dp, column, Footer(this, dp))
        root.setBackgroundColor(Color.BLACK)
        root.setOnApplyWindowInsetsListener { v, wi -> onInsets(wi); v.onApplyWindowInsets(wi) }
        setContentView(root)
        foldReader = FoldReader(this) { r -> reading = r; refold() }
        handleLink(intent)
    }

    override fun onStart() { super.onStart(); if (window.decorView.isAttachedToWindow) foldReader.start() }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); foldReader.start() }
    override fun onStop() { foldReader.stop(); super.onStop() }

    private fun refold() {
        if (root.width == 0) return
        val loc = IntArray(2); root.getLocationInWindow(loc)
        val safe = insets.safe(Size(dp.px.dp(root.width), dp.px.dp(root.height)))
        root.fold = FoldMapping.info(reading, loc[0] + dp.px.of(insets.left), loc[1] + dp.px.of(insets.top), dp.density, safe)
        root.requestLayout()
    }

    private fun onInsets(wi: WindowInsets) {
        val d = dp.density
        insets = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val i = wi.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout() or WindowInsets.Type.ime())
            Insets(i.left / d, i.top / d, i.right / d, i.bottom / d)
        } else {
            @Suppress("DEPRECATION") Insets(wi.systemWindowInsetLeft / d, wi.systemWindowInsetTop / d, wi.systemWindowInsetRight / d, wi.systemWindowInsetBottom / d)
        }
        root.insets = insets
        root.post { refold() }
    }

    private fun label(style: TextStyle, color: Rgba) = TextView(this).apply {
        typeface = Look.typeface(style.weight)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, (style.size * dp.density).toFloat())   // the column keeps its fixed sizes, as on iOS
        setTextColor(color.argb)
        includeFontPadding = false
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        if (dp.density != resources.displayMetrics.density.toDouble() || dp.fontScale != newConfig.fontScale.toDouble()) { recreate(); return }
        root.post { refold() }
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); handleLink(intent) }

    override fun onResume() {
        super.onResume()
        app.ui = this
        onRows(app.rows)
        onStatus(app.status)
        app.session?.let { onSessionStarted(it, app.sessionMac) }
    }

    override fun onPause() { if (app.ui === this) app.ui = null; super.onPause() }

    @Deprecated("Activity.onBackPressed; the platform's own until predictive back is opted into")
    override fun onBackPressed() { if (card.visibility == View.VISIBLE) card.close() else @Suppress("DEPRECATION") super.onBackPressed() }

    /** A sill://pair link from the camera app or another app: confirmed first, never paired by itself. */
    private fun handleLink(intent: Intent?) {
        val url = intent?.data?.toString() ?: return
        intent.data = null
        val parsed = PairLink.parse(url)
        if (parsed !is PairLink.Parsed.Ok) { onStatus("That isn’t a Sill pairing link."); return }
        card.showLink(parsed.link.name, url)
    }

    // ClientListener (worker threads)

    override fun onRows(rows: List<MacRow>) = runOnUiThread {
        this.rows.removeAllViews()
        for (r in rows) this.rows.addView(MacRowView(this, dp, r).apply {
            setOnClickListener { app.client.connect(r) }
            setOnLongClickListener {
                r.saved?.let { s ->
                    AlertDialog.Builder(this@ConnectActivity, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                        .setMessage("Forget ${s.name}? You’ll pair again to use it.")
                        .setPositiveButton("Forget") { _, _ -> app.client.forget(s.macID) }.setNegativeButton("Cancel", null).show()
                }
                true
            }
        })
    }
    override fun onStatus(text: String?) = runOnUiThread { status.text = text ?: "Looking for Macs…" }
    override fun onPairingPrompt(prompt: PairingPrompt) = runOnUiThread { card.showPrompt(prompt) }
    override fun onSessionStarted(session: SillSession, mac: String) = runOnUiThread {
        card.close()
        if (app.streamScreen == null) startActivity(Intent(this, StreamActivity::class.java))
    }
    override fun onSessionEnded(outcome: GoodbyePolicy.Outcome) = onStatus(outcome.text)
}

/** The column over the footer (ColumnOverFooter): centred, rising only to keep 24 pt above the footer, scrolling past that. */
@SuppressLint("ViewConstructor")
class ConnectRoot(context: Context, private val dp: Dp, column: View, private val footer: View) : ViewGroup(context) {
    var insets = Insets.zero
    var fold: FoldInfo = FoldInfo.Inferred
    private val scroll = ScrollView(context).apply { addView(column); isFillViewport = false; overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS }
    init { addView(scroll); addView(footer) }

    private fun layoutFor() = ConnectLayout(insets.safe(Size(dp.px.dp(width), dp.px.dp(height))), fold)

    override fun onMeasure(w: Int, h: Int) {
        setMeasuredDimension(MeasureSpec.getSize(w), MeasureSpec.getSize(h))
        @Suppress("DrawAllocation") val cl = ConnectLayout(insets.safe(Size(dp.px.dp(measuredWidth), dp.px.dp(measuredHeight))), fold)
        val cw = dp(cl.columnWidth).toInt()
        footer.measure(MeasureSpec.makeMeasureSpec(cw, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        scroll.measure(MeasureSpec.makeMeasureSpec(cw, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.AT_MOST))
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val cl = layoutFor()
        val x = dp(insets.left + cl.columnX).toInt()
        val footerH = dp.px.dp(footer.measuredHeight)
        val screenH = cl.size.height
        // The footer along the bottom; the column in the room above a laptop pose's fold, else the screen's.
        val fy = dp(insets.top + screenH - footerH - Ui.connectLinkReach).toInt()
        footer.layout(x, fy, x + footer.measuredWidth, fy + footer.measuredHeight)
        val room = cl.roomAboveFold
        val columnH = dp.px.dp(scroll.getChildAt(0).let { c ->
            c.measure(MeasureSpec.makeMeasureSpec(scroll.measuredWidth, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)); c.measuredHeight })
        val place = if (room != null) ColumnPlace.of(room, columnH, 0.0, 0.0)
                    else ColumnPlace.of(screenH, columnH, footerH + Ui.connectLinkReach, Ui.connectFooterGap)
        val y = dp(insets.top + place.y).toInt()
        val hgt = dp(place.height).toInt()
        scroll.measure(MeasureSpec.makeMeasureSpec(scroll.measuredWidth, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(hgt, MeasureSpec.EXACTLY))
        scroll.layout(x, y, x + scroll.measuredWidth, y + hgt)
    }
}

/** A Mac's row (DrawerRow's look): the Desktop symbol on its 32 pt badge, the name, the way it is reached. */
@SuppressLint("ViewConstructor")
class MacRowView(context: Context, private val dp: Dp, private val row: MacRow) : View(context) {
    private val title = Look.textPaint(dp, Type.rowTitle, Palette.text, capped = false)
    private val trail = Look.textPaint(dp, Type.rowTrailing, Palette.muted, capped = false)
    private val badge = Look.fill(Palette.iconFallback)
    private val hi = Look.fill(Palette.control)
    private val rect = RectF()

    init {
        isClickable = true; isFocusable = true; isLongClickable = true
        contentDescription = listOfNotNull(row.name, row.word).joinToString(", ")
    }

    override fun onMeasure(w: Int, h: Int) = setMeasuredDimension(MeasureSpec.getSize(w), dp(Ui.connectRowHeight).toInt())
    override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }

    override fun onDraw(c: Canvas) {
        if (isPressed || isFocused) c.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), dp(Ui.rowRadius), dp(Ui.rowRadius), hi)
        val s = dp(Ui.rowIcon); val x = dp(10.0); val y = (height - s) / 2
        val r = rect.apply { set(x, y, x + s, y + s) }
        c.drawRoundRect(r, dp(Ui.rowIconRadius), dp(Ui.rowIconRadius), badge)
        Look.symbol(c, dp, Symbol.Desktop, r.centerX(), r.centerY(), Ui.connectRowSymbolSize, Palette.text, Palette.iconFallback)
        var room = width - r.right - dp(12.0 + 10.0)
        row.word?.let { w -> val tw = trail.measureText(w); Look.textLeft(c, w, width - dp(10.0) - tw, height / 2f, trail); room -= tw + dp(8.0) }
        Look.textLeft(c, Look.fit(row.name, title, room), r.right + dp(12.0), height / 2f, title)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) { super.onInitializeAccessibilityNodeInfo(info); info.className = "android.widget.Button" }
}

/** The footer: what else Sill needs, and the links (muted footnote, accent links, one line while they fit). */
@SuppressLint("ViewConstructor")
class Footer(context: Context, private val dp: Dp) : LinearLayout(context) {
    init {
        orientation = VERTICAL
        setPadding(dp(10.0).toInt(), 0, dp(10.0).toInt(), 0)
        addView(text(Copy.needsMacApp, Palette.muted))
        val links = listOf(Copy.getItAt("getsill.app") to "https://getsill.app/download", Copy.support to "https://getsill.app/support",
            Copy.privacyPolicy to "https://getsill.app/privacy")
        addView(FlowLine(context, dp, links.map { (t, u) -> link(t, u) }) { text(" · ", Palette.muted).apply { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO } })
    }

    private fun text(t: String, color: Rgba) = TextView(context).apply {
        text = t
        typeface = Look.typeface(TextStyle.Weight.Regular)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, dp.text(Type.footnote))
        setTextColor(color.argb)
        includeFontPadding = false
    }

    private fun link(t: String, url: String) = text(t, Palette.accent).apply {
        val reach = dp(Ui.connectLinkReach).toInt()
        setPadding(0, reach, 0, reach)
        isClickable = true; isFocusable = true
        setOnClickListener { try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (_: Exception) {} }
        accessibilityDelegate = object : AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(host, info); info.className = "android.widget.Button"
            }
        }
    }
}

/** Links on one line with a separator while they fit, else the first over the rest (the footer's ViewThatFits). */
@SuppressLint("ViewConstructor")
class FlowLine(context: Context, private val dp: Dp, private val items: List<View>, separator: () -> View) : ViewGroup(context) {
    private val seps = List(items.size - 1) { separator() }
    private var oneLine = true
    init { items.forEachIndexed { i, v -> addView(v); if (i < seps.size) addView(seps[i]) } }

    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w)
        val any = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        (items + seps).forEach { it.measure(any, any) }
        val total = items.sumOf { it.measuredWidth } + seps.sumOf { it.measuredWidth }
        oneLine = total <= width
        val lineH = items.maxOf { it.measuredHeight }
        setMeasuredDimension(width, if (oneLine) lineH else 2 * lineH)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val lineH = items.maxOf { it.measuredHeight }
        var x = 0; var y = 0
        items.forEachIndexed { i, v ->
            if (!oneLine && i == 1) { x = 0; y = lineH }
            v.layout(x, y, x + v.measuredWidth, y + v.measuredHeight); x += v.measuredWidth
            if (i < seps.size) {
                val s = seps[i]
                if (!oneLine && i == 0) { s.layout(0, 0, 0, 0) } else {
                    val sy = y + (lineH - s.measuredHeight) / 2
                    s.layout(x, sy, x + s.measuredWidth, sy + s.measuredHeight); x += s.measuredWidth
                }
            }
        }
    }
}

/**
 * Add a Mac's card (AddMacCard) in the column: Add a Mac by the address and code its pairing window
 * shows, or a pasted pairing link; a Mac showing its code for a tap (the code alone); a pairing link
 * from outside, confirmed. Its words 13 pt, its fields 48 pt on the control colour, Pair on the
 * accent, Cancel and the other path as accent links. It unfolds on Motion.card.
 */
@SuppressLint("ViewConstructor")
class PairCard(context: Context, private val dp: Dp, private val app: SillApp) : LinearLayout(context) {
    var onChanged: () -> Unit = {}
    private val title = text(Type.subheadline.copy(weight = TextStyle.Weight.Semibold), Palette.text)
    private val words = text(Type.footnote, Palette.muted)
    private val address = SearchField(context, dp, magnifier = false)
    private val code = SearchField(context, dp, magnifier = false)
    private val linkField = SearchField(context, dp, magnifier = false)
    private val pair = PairButton(context, dp)
    private val progress = text(Type.footnote, Palette.muted)
    private val other = linkText("")
    private val cancel = linkText(Copy.cancel)
    private var mode: Mode = Mode.Add
    private var prompt: PairingPrompt? = null
    private var url: String? = null

    private enum class Mode { Add, AddLink, Prompt, Link }

    init {
        orientation = VERTICAL
        setPadding(0, dp(12.0).toInt(), 0, 0)
        address.field.hint = "100.101.102.103 or mac.example.net"
        address.field.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
        address.field.imeOptions = EditorInfo.IME_ACTION_NEXT or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        address.field.contentDescription = "Address"
        code.field.hint = "0000 0000 0000"
        code.field.inputType = InputType.TYPE_CLASS_NUMBER
        code.field.imeOptions = EditorInfo.IME_ACTION_GO or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        code.field.contentDescription = "Code"
        code.field.fontFeatureSettings = "tnum"
        code.field.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val g = CodeText.grouped(s.toString())
                if (g != s.toString()) { code.field.setText(g); code.field.setSelection(g.length) }
            }
        })
        code.field.setOnEditorActionListener { _, _, _ -> submit(); true }
        linkField.field.hint = "sill://pair?…"
        linkField.field.contentDescription = "Pairing link"
        for (v in listOf(title, words)) addView(v, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(6.0).toInt() })
        for (v in listOf(address, code, linkField)) addView(v, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(8.0).toInt() })
        addView(pair, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(6.0).toInt() })
        addView(progress)
        val links = LinearLayout(context).apply { orientation = HORIZONTAL; addView(other); addView(cancel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(18.0).toInt() }) }
        addView(links)
        pair.setOnClickListener { submit() }
        cancel.setOnClickListener { close() }
        other.setOnClickListener { set(if (mode == Mode.Add) Mode.AddLink else Mode.Add) }
    }

    fun showAdd() { prompt = null; url = null; set(Mode.Add) }
    fun showPrompt(p: PairingPrompt) { prompt = p; set(Mode.Prompt) }
    fun showLink(name: String, link: String) { url = link; title.text = "Pair with $name?"; set(Mode.Link) }

    fun close() {
        prompt?.let { app.client.cancelPrompt(it) }
        prompt = null; url = null
        visibility = GONE; onChanged()
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(windowToken, 0)
    }

    private fun set(m: Mode) {
        mode = m
        progress.text = ""
        pair.working = false
        when (m) {
            Mode.Add -> {
                title.text = Copy.addMacTitle
                words.text = Copy.addMacPairOnce + "\n" + Copy.addMacTyped
                other.text = PlatformCopy.usePairingLink
            }
            Mode.AddLink -> { title.text = Copy.addMacTitle; words.text = PlatformCopy.pastePairingLink; other.text = Copy.enterCodeInstead }
            Mode.Prompt -> { title.text = "Pair with ${prompt?.macName}"; words.text = prompt?.words ?: "" }
            Mode.Link -> words.text = "Only pair with a Mac you can see showing this code now."
        }
        address.visibility = if (m == Mode.Add) VISIBLE else GONE
        code.visibility = if (m == Mode.Add || m == Mode.Prompt) VISIBLE else GONE
        linkField.visibility = if (m == Mode.AddLink) VISIBLE else GONE
        other.visibility = if (m == Mode.Add || m == Mode.AddLink) VISIBLE else GONE
        if (visibility != VISIBLE) {
            visibility = VISIBLE; onChanged()
            if (!Motions.reduced) { alpha = 0f; translationY = -dp(8.0); Motions.run(Motion.card, { p -> alpha = p.coerceIn(0f, 1f); translationY = -dp(8.0) * (1 - p) }) }
        }
        (if (m == Mode.Add) address else if (m == Mode.AddLink) linkField else code).field.requestFocus()
    }

    private fun submit() {
        if (pair.working) return
        pair.working = true
        progress.text = "Pairing…"
        val report: (PairOutcome) -> Unit = { out ->
            post {
                pair.working = false
                progress.setTextColor((if (out is PairOutcome.Paired) Palette.text else Rgba.orange).argb)
                progress.text = when (out) {
                    is PairOutcome.Paired -> "Paired with ${out.mac.name}."
                    is PairOutcome.Refused -> out.words
                    is PairOutcome.Failed -> out.words
                }
                announceForAccessibility(progress.text)
            }
        }
        progress.setTextColor(Palette.muted.argb)
        when (mode) {
            Mode.Add -> app.client.addByAddress(address.field.text.toString().trim(), code.field.text.toString(), report)
            Mode.AddLink -> app.client.pairWithLink(linkField.field.text.toString().trim(), report)
            Mode.Prompt -> prompt?.let { p -> app.client.submitCode(p, code.field.text.toString(), report); prompt = null }
            Mode.Link -> url?.let { app.client.pairWithLink(it, report) }
        }
    }

    private fun text(style: TextStyle, color: Rgba) = TextView(context).apply {
        typeface = Look.typeface(style.weight)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, (style.size * dp.density).toFloat())
        setTextColor(color.argb)
    }

    private fun linkText(t: String) = text(Type.connectLink, Palette.accent).apply {
        text = t; gravity = Gravity.CENTER_VERTICAL; minHeight = dp(Targets.MIN).toInt(); isClickable = true; isFocusable = true
    }
}

/** Pair: black words on the accent, at least 88×44 (48 here, Android's least target), faded while it works. */
@SuppressLint("ViewConstructor")
class PairButton(context: Context, private val dp: Dp) : View(context) {
    var working = false
        set(v) { field = v; isEnabled = !v; invalidate() }
    private val bg = Look.fill(Palette.accent)
    private val text = Look.textPaint(dp, Type.connectLink, Rgba.black, capped = false)
    init { isClickable = true; isFocusable = true; contentDescription = Copy.pair }
    override fun onMeasure(w: Int, h: Int) = setMeasuredDimension(max(dp(88.0), text.measureText(Copy.pair) + dp(24.0)).toInt(), dp(Targets.MIN).toInt())
    override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }
    override fun onDraw(c: Canvas) {
        bg.alpha = if (working) 102 else if (isPressed) 200 else 255
        c.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), dp(Ui.fieldRadius), dp(Ui.fieldRadius), bg)
        Look.textCentred(c, Copy.pair, width / 2f, height / 2f, text)
    }
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) { super.onInitializeAccessibilityNodeInfo(info); info.className = "android.widget.Button" }
}
