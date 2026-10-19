package me.saffer.sill.android

import android.animation.ValueAnimator
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.text.InputType
import android.view.Choreographer
import android.view.InputDevice
import android.view.KeyEvent
import android.view.WindowManager
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import me.saffer.sill.core.AppInfo
import me.saffer.sill.core.ClientStats
import me.saffer.sill.core.FrameMapping
import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.HostSettingsState
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.ScrollPhase
import me.saffer.sill.core.SessionListener
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.StreamSource
import me.saffer.sill.core.TouchGestures
import me.saffer.sill.core.Viewport
import me.saffer.sill.core.WindowList
import me.saffer.sill.core.FetchMenu
import me.saffer.sill.core.MacMenu
import me.saffer.sill.core.PressMenuItem
import me.saffer.sill.core.ui.MacMenus
import me.saffer.sill.core.ui.BarItem
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.DuoPosture
import me.saffer.sill.core.ui.FoldInfo
import me.saffer.sill.core.ui.KeyRow
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.PanelCopy
import me.saffer.sill.core.ui.PortraitMetrics
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.SettingsField
import me.saffer.sill.core.ui.SettingsLedger
import me.saffer.sill.core.ui.Size
import me.saffer.sill.core.ui.StreamLayout
import me.saffer.sill.core.ui.StreamUi
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.Ui
import kotlin.math.max

/**
 * The stream screen (StreamScreen and PortraitStreamScreen): core's StreamLayout places every part
 * for this screen's size and fold (the landscape bar over the stream, the halves, a phone upright),
 * core's StreamUi decides what opens and closes, and this activity draws and wires them: the picture
 * in a SurfaceView (MediaCodec), fingers on it (TouchGestures), a mouse or stylus as the pointer,
 * the soft keyboard as text, a hardware keyboard as keys, the key row and the trackpad upright.
 */
class StreamActivity : Activity(), SessionListener, SurfaceHolder.Callback {
    private val app get() = application as SillApp
    private var session: SillSession? = null
    private lateinit var dp: Dp
    private lateinit var root: StreamRoot
    private val ui = StreamUi { s, e -> onUi(s, e) }
    private val ledger = SettingsLedger()
    private val main = Handler(Looper.getMainLooper())

    private lateinit var barBg: BarBackground
    private lateinit var backdrop: PanelBackdrop
    private lateinit var surface: SurfaceView
    private lateinit var outline: PanelOutline
    private lateinit var pointer: PointerOverlay
    private lateinit var input: KeyInputView
    private lateinit var strip: StripView
    private lateinit var apps: BarButton
    private lateinit var keyboard: BarButton
    private lateinit var desktop: BarButton
    private lateinit var settingsButton: BarButton
    private lateinit var menusButton: BarButton
    private lateinit var menuPopup: MacMenuPopup
    /** The Mac's menus (kinds 24, 25, 27): the Menus button shows while the Mac sends a top level or a note. */
    private val macMenus by lazy {
        MacMenus(app.sessionMac, send = { p ->
            when (p) { is FetchMenu -> session?.fetchMenu(p); is PressMenuItem -> session?.pressMenuItem(p) }
        }, worstRtt = { session?.worstRtt }, now = { now() }, postDelayed = { s, f -> main.postDelayed(f, (s * 1000).toLong().coerceAtLeast(1)) }).apply {
            onTop = { relayout() }
            onRefusal = { r -> root.announceForAccessibility(r.announcement); root.performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 30) android.view.HapticFeedbackConstants.REJECT else android.view.HapticFeedbackConstants.LONG_PRESS) }
        }
    }
    private lateinit var aa: TextSizeButton
    private lateinit var pad: PadView
    private lateinit var drawer: DrawerView
    private lateinit var panel: SettingsPanelView
    private lateinit var lights: LightsView
    private val dims = ArrayList<Catcher>()
    private var caps: List<KeyCapView> = emptyList()

    private val decoder = HevcSurfaceDecoder { w, h -> runOnUiThread { videoW = w; videoH = h; relayout() } }
    private var videoW = 0
    private var videoH = 0
    private var list: WindowList? = null
    private val thumbBitmaps = HashMap<Long, Bitmap>()
    private val icons = HashMap<String, Bitmap>()
    private var appList: List<AppInfo> = emptyList()
    private var order: List<Long> = emptyList()
    private lateinit var gestures: TouchGestures
    private var ticking = false
    private var lastClip: String? = null
    private var insets = Insets.zero
    private var reading: FoldMapping.Reading = FoldMapping.Reading.Nothing
    private var fold: FoldInfo = FoldInfo.Inferred
    private lateinit var foldReader: FoldReader
    private var layout: StreamLayout? = null
    private var videoBox = PxBox(0, 0, 1, 1)
    private var sentViewport: Viewport? = null
    private var macPointer: Pair<Double, Double>? = null
    private var ownPointer: Pair<Double, Double>? = null
    private var pointerReseeds = 0
    private var problem: String? = null
    private var olderMac = false
    private var rttMax: Int? = null
    private var listAt = 0.0
    private var drawerProgress = 0f
    private var panelProgress = 0f
    private var drawerAnim: ValueAnimator? = null
    private var panelAnim: ValueAnimator? = null
    private var fadeAnim: ValueAnimator? = null
    private var faded = 1f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        session = app.session ?: return finish()
        app.streamScreen = this
        dp = Dp(this)
        gestures = TouchGestures(dp.density) { e -> session?.input(e) }
        Look.edgeToEdge(this)

        root = StreamRoot(this).apply { setBackgroundColor(Color.BLACK) }
        barBg = BarBackground(this)
        backdrop = PanelBackdrop(this, dp)
        surface = SurfaceView(this).apply { holder.addCallback(this@StreamActivity) }
        outline = PanelOutline(this, dp)
        pointer = PointerOverlay(this, dp)
        input = KeyInputView(this)
        strip = StripView(this, dp)
        apps = BarButton(this, dp, Symbol.Magnifier, Copy.apps)
        keyboard = BarButton(this, dp, Symbol.Keyboard, Copy.keyboard)
        desktop = BarButton(this, dp, Symbol.Desktop, Copy.desktop).apply { contentDescription = Copy.showDesktop }
        settingsButton = BarButton(this, dp, Symbol.Gear, Copy.settings)
        menusButton = BarButton(this, dp, Symbol.Menus, Copy.menus)
        menuPopup = MacMenuPopup(this, menusButton, macMenus)
        aa = TextSizeButton(this, dp) { layout?.rulerStep ?: Ui.rulerStepRegular }
        pad = PadView(this, dp) { e -> session?.input(e) }
        drawer = DrawerView(this, dp)
        panel = SettingsPanelView(this, dp)
        lights = LightsView(this, dp)
        for (v in listOf(barBg, backdrop, surface, outline, pointer, input, strip, apps, menusButton, keyboard, desktop, settingsButton, aa, pad)) root.addView(v)
        root.addView(drawer); root.addView(panel); root.addView(lights)
        drawer.visibility = View.GONE; panel.visibility = View.GONE

        wire()
        root.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, or, ob -> if (r - l != or - ol || b - t != ob - ot) root.post { relayout() } }
        root.setOnApplyWindowInsetsListener { v, wi -> onInsets(wi); v.onApplyWindowInsets(wi) }
        setContentView(root)
        title = app.sessionMac
        foldReader = FoldReader(this) { r -> reading = r; relayout() }
        app.router.attach(this)
        onUi(ui.state, emptyList())
    }

    override fun onDestroy() {
        app.router.detach(this)
        if (::menuPopup.isInitialized) menuPopup.dismiss()
        macMenus.onTop = {}; macMenus.reset()
        if (app.streamScreen === this) app.streamScreen = null
        main.removeCallbacksAndMessages(null)
        if (::foldReader.isInitialized) foldReader.stop()
        decoder.release()
        super.onDestroy()
    }

    override fun onStart() { super.onStart(); if (::foldReader.isInitialized && window.decorView.isAttachedToWindow) foldReader.start() }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); if (::foldReader.isInitialized) foldReader.start() }
    override fun onStop() { if (::foldReader.isInitialized) foldReader.stop(); super.onStop() }

    override fun onResume() {
        super.onResume()
        // This device's copy reaches the Mac when the stream comes back to the front (Share Clipboard).
        val clip = (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
        val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(this)?.toString()
        if (text != null && text != lastClip && session?.sendClipboard(text) == true) lastClip = text
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // The cover and the inner display, a rotation: same activity, a new layout. A new density
        // (a display of another density, the display size setting): every view is made again.
        if (dp.density != resources.displayMetrics.density.toDouble() || dp.fontScale != newConfig.fontScale.toDouble()) { recreate(); return }
        root.post { relayout() }
    }

    /** The session ended (the Mac's goodbye, a loss): back to the connect screen with its words. */
    fun finishFromSession() = runOnUiThread { ui.reset(); finish() }

    // MARK: Wiring

    private fun wire() {
        apps.onTap = { ui.tapApps() }
        keyboard.onTap = { ui.tapKeyboard() }
        desktop.onTap = { ui.tapDesktop() }
        settingsButton.onTap = { ui.tapSettings() }
        menusButton.onTap = { menuPopup.showTop() }
        aa.onDown = { aa.snap(ui.state.textScale ?: 1.0); ui.rulerDown() }
        aa.onMoved = { dx -> ui.rulerMoved(dx, layout?.rulerStep ?: Ui.rulerStepRegular).also { aa.live = ui.rulerLive } }
        aa.onUp = { ui.rulerUp() }
        aa.onStep = { up -> ui.stepScale(up) }
        strip.onSelect = { id -> ui.closeWindowMenu(); session?.select(StreamSource.Window(id)) }
        strip.onHold = { id -> ui.openWindowMenu(id) }
        strip.onCloseMenu = { ui.closeWindowMenu() }
        strip.onCommand = { id, cmd -> session?.windowCommand(id, cmd) }
        strip.onReorder = { o -> order = o; saveOrder(o) }
        lights.onCommand = { cmd -> ui.state.windowMenu?.let { session?.windowCommand(it, cmd) }; ui.closeWindowMenu() }
        lights.onDismiss = { ui.closeWindowMenu() }
        drawer.onPickWindow = { id -> session?.select(StreamSource.Window(id)); ui.closeDrawer() }
        drawer.onLaunch = { b -> session?.launch(b); ui.closeDrawer() }
        panel.onChange = { c -> changeSettings(c) }
        panel.onDone = { ui.closeSettings() }
        panel.onDisconnect = { app.client.disconnect(); finish() }
        panel.onKeepScreenOn = { on -> prefs.edit().putString(KEEP_SCREEN_ON, if (on) "1" else "0").apply(); applyKeepScreenOn(); refreshPanel() }
        applyKeepScreenOn()
        pad.tracker.latched = { ui.state.latched }
        pad.tracker.onLatchSpent = { ui.latch(0) }
        pad.tracker.feed = { (macPointer ?: ownPointer) to pointerReseeds }
        pad.tracker.onPointer = { x, y -> ownPointer = x to y; macPointer = null; showPointer() }
    }

    // MARK: State

    private fun onUi(s: StreamUi.State, effects: List<StreamUi.Effect>) {
        for (e in effects) when (e) {
            is StreamUi.Effect.Keyboard -> setIme(e.shown)
            StreamUi.Effect.SendViewport -> scheduleViewport()
            StreamUi.Effect.SelectDesktop -> session?.select(StreamSource.Desktop)
        }
        apps.open = s.drawerOpen
        apps.contentDescription = if (s.drawerOpen) Copy.closeAppList else Copy.openAppList
        keyboard.open = s.keyboardShown
        keyboard.contentDescription = if (s.keyboardShown) Copy.hideKeyboard else Copy.showKeyboard
        settingsButton.open = s.settingsOpen
        settingsButton.contentDescription = if (s.settingsOpen) Copy.closeSettings else Copy.settingsFor(app.sessionMac)
        aa.scale = s.textScale
        aa.unfold(s.scaleOpen)
        fadeOthers(s.scaleOpen)
        for (c in caps) c.lit = when (val k = c.key) {
            is KeyRow.Key.Modifier -> s.latched and k.bit != 0L
            KeyRow.Key.Keyboard -> s.keyboardShown
            else -> false
        }
        strip.menuFor = s.windowMenu
        showLights(s.windowMenu)
        showDrawer(s.drawerOpen)
        showPanel(s.settingsOpen)
    }

    /** The Aa ruler open: everything else in the bar fades and takes no touch. */
    private fun fadeOthers(open: Boolean) {
        val target = if (open) 0.2f else 1f
        for (v in listOf(apps, menusButton, keyboard, desktop, settingsButton, strip)) v.isEnabled = !open
        if (faded == target) return
        fadeAnim?.cancel()
        val from = faded
        fadeAnim = Motions.run(Motion.scaleFade, { p -> faded = from + (target - from) * p; applyFade() })
        if (Motions.reduced) { fadeAnim?.end() }
    }

    private fun applyFade() { for (v in listOf(apps, menusButton, keyboard, desktop, settingsButton, strip)) v.alpha = faded }

    private fun showLights(id: Long?) {
        val l = layout
        if (id == null || l == null) { if (lights.visibility == View.VISIBLE) lights.show(false); return }
        val f = strip.frameOf(id) ?: return
        val sx = strip.left + f.left; val sy = strip.top + f.top
        lights.anchor = Rect(dp.px.dp(sx), dp.px.dp(sy), dp.px.dp(f.width()), dp.px.dp(f.height()))
        lights.window = list?.windows?.firstOrNull { it.id == id }
        lights.below = l.lightsBelow || (sy + f.height() / 2) < root.height / 2f
        lights.fold = shifted(fold)
        lights.show(true)
    }

    private fun showDrawer(open: Boolean) {
        val target = if (open) 1f else 0f
        if (drawerProgress == target && (open == (drawer.visibility == View.VISIBLE))) return
        if (open) {
            drawer.setMac(app.sessionMac); drawer.clearSearch(); refreshDrawer()
            drawer.visibility = View.VISIBLE
            dims.forEach { it.visibility = View.VISIBLE; it.onTap = { ui.closeDrawer() } }
        }
        drawerAnim?.cancel()
        val from = drawerProgress
        val end = { if (!open) { drawer.visibility = View.GONE; if (!ui.state.settingsOpen) dims.forEach { it.visibility = View.GONE } } }
        if (Motions.reduced) { drawerProgress = target; applyDrawer(); end(); return }
        drawerAnim = Motions.run(Motion.drawer, { p -> drawerProgress = from + (target - from) * p; applyDrawer() }, end)
    }

    private fun applyDrawer() {
        drawer.alpha = drawerProgress
        dims.forEach { it.dim = if (ui.state.settingsOpen) 0f else drawerProgress }
    }

    private fun showPanel(open: Boolean) {
        val target = if (open) 1f else 0f
        if (panelProgress == target && (open == (panel.visibility == View.VISIBLE))) return
        if (open) {
            refreshPanel()
            panel.visibility = View.VISIBLE
            dims.forEach { it.visibility = View.VISIBLE; it.dim = 0f; it.onTap = { ui.closeSettings() } }
            panel.post { panel.requestFocus() }
        }
        panelAnim?.cancel()
        val from = panelProgress
        val end = { if (!open) { panel.visibility = View.GONE; if (!ui.state.drawerOpen) dims.forEach { it.visibility = View.GONE } } }
        if (Motions.reduced) { panelProgress = target; applyPanel(); end(); return }
        panelAnim = Motions.run(if (open) Motion.settingsOpen else Motion.settingsClose, { p -> panelProgress = from + (target - from) * p; applyPanel() }, end)
    }

    /** Grows from the Settings button's corner (the panel's top-trailing one), fading; a fade alone with Reduce Motion. */
    private fun applyPanel() {
        val l = layout ?: return
        panel.alpha = panelProgress.coerceIn(0f, 1f)
        val s = if (Motions.reduced) 1f else (Motion.settingsScale + (1 - Motion.settingsScale) * panelProgress).toFloat()
        panel.pivotX = (dp(l.settingsAnchorX * l.size.width + insets.left) - panel.left).coerceIn(0f, panel.width.toFloat())
        panel.pivotY = (dp(l.settingsAnchorY * l.size.height + insets.top) - panel.top).coerceAtLeast(0f)
        panel.scaleX = s; panel.scaleY = s
    }

    // MARK: Layout

    /** The fold in the layout's space: the safe area's, the insets taken off. */
    private fun shifted(f: FoldInfo) = f.band?.let { FoldInfo.known(it.offset(insets.left, insets.top)) } ?: f

    private fun relayout() {
        if (!::root.isInitialized || root.width == 0 || root.height == 0) return
        val win = Size(dp.px.dp(root.width), dp.px.dp(root.height))
        val safe = insets.safe(win)
        val loc = IntArray(2); root.getLocationInWindow(loc)
        fold = FoldMapping.info(reading, loc[0] + dp.px.of(insets.left), loc[1] + dp.px.of(insets.top), dp.density, safe)
        val active = list?.active
        val video = Size(videoW.toDouble(), videoH.toDouble())
        val fitted = active is StreamSource.Window && (ui.state.textScale != null || ledger.host?.stream?.onVirtualDisplay == true)
        val l = StreamLayout.of(safe, phone = resources.configuration.smallestScreenWidthDp < 600, menus = macMenus.state.hasMenus,
            spotlight = active == StreamSource.Desktop, video = video, fold = fold, aspect = DuoPosture.paneAspect(video, fitted))
        layout = l
        val ox = insets.left; val oy = insets.top
        fun box(r: Rect) = dp.px.box(r, ox, oy)

        root.place(barBg, (l as? StreamLayout.Landscape)?.let { PxBox(0, 0, root.width, dp.px.of(oy + it.bar.height)) })
        val pb = box(l.panel)
        root.place(backdrop, pb); root.place(outline, pb); root.place(pointer, pb); root.place(input, pb)
        val fit = FrameMapping.fit(if (videoW > 0) videoW.toDouble() else 16.0, if (videoH > 0) videoH.toDouble() else 10.0, pb.width.toDouble(), pb.height.toDouble())
        videoBox = PxBox(pb.left + fit.x.toInt(), pb.top + fit.y.toInt(), pb.left + (fit.x + fit.w).toInt(), pb.top + (fit.y + fit.h).toInt())
        root.place(surface, videoBox)
        gestures.frameRect = fit
        pointer.frame = android.graphics.RectF(fit.x.toFloat(), fit.y.toFloat(), (fit.x + fit.w).toFloat(), (fit.y + fit.h).toFloat())

        val phoneRow = l is StreamLayout.Phone
        for (b in listOf(apps, menusButton, keyboard, desktop, settingsButton)) {
            b.radius = l.buttonRadius; b.iconSize = l.buttonIcon; b.spacing = l.buttonSpacing
            b.iconBox = if (phoneRow) PortraitMetrics.phoneIconBox else null
            b.invalidate()
        }
        root.place(apps, l.items[BarItem.Apps]?.let(::box))
        root.place(keyboard, l.items[BarItem.Keyboard]?.let(::box))
        root.place(desktop, l.items[BarItem.Desktop]?.let(::box))
        root.place(settingsButton, l.items[BarItem.Settings]?.let(::box))
        root.place(menusButton, l.items[BarItem.Menus]?.let(::box))
        val aaRect = l.items[BarItem.TextSize]
        if (aaRect != null) {
            val rb = box(l.ruler.copy(y = aaRect.y, height = aaRect.height))
            val left = minOf(rb.left, box(aaRect).left); val right = maxOf(rb.right, box(aaRect).right)
            val area = PxBox(left, rb.top, right, rb.bottom)
            root.place(aa, area)
            val ab = box(aaRect)
            aa.button = android.graphics.RectF((ab.left - left).toFloat(), 0f, (ab.right - left).toFloat(), ab.height.toFloat())
            aa.radius = l.buttonRadius; aa.iconSize = l.buttonIcon; aa.spacing = l.buttonSpacing
            aa.iconBox = if (phoneRow) PortraitMetrics.phoneIconBox else null
        } else root.place(aa, null)

        strip.thumbWidth = l.thumbWidth; strip.thumbHeight = l.thumbHeight; strip.radius = l.thumbRadius
        strip.spacing = l.thumbSpacing; strip.pad = l.thumbPad; strip.fade = l.thumbFade; strip.badge = l.badge
        root.place(strip, l.items[BarItem.Strip]?.let(::box))

        placeCaps(l, ::box)
        root.place(pad, l.trackpad?.let(::box))
        pad.setSpan(l.trackpadSpan)

        root.place(drawer, box(l.drawer))
        root.place(panel, box(l.settings), wrapHeight = true)
        panel.maxHeight = box(l.settings).height
        root.place(lights, PxBox(0, 0, root.width, root.height))
        placeDims(l.dim.map(::box))

        root.systemGestureExclusionRects = listOfNotNull(l.items[BarItem.Strip], l.trackpad, l.items[BarItem.TextSize]?.let { l.ruler }).map {
            val b = box(it); android.graphics.Rect(b.left, b.top, b.right, b.bottom)
        }
        root.requestLayout()
        applyPanel()
        showLights(ui.state.windowMenu)
        scheduleViewport()
    }

    private fun placeCaps(l: StreamLayout, box: (Rect) -> PxBox) {
        val keys: List<KeyRow.Key> = when (l) {
            is StreamLayout.Halves -> l.keys.flatten()
            is StreamLayout.Phone -> KeyRow.phone
            else -> emptyList()
        }
        val rects = l.caps.flatten()
        if (caps.map { it.key } != keys) {
            caps.forEach { root.removeView(it) }
            caps = keys.map { k -> KeyCapView(this, dp, k).also { it.onTap = ::tapKey; root.addView(it, root.indexOfChild(pad)) } }
            onUi(ui.state, emptyList())
        }
        val gap = (l as? StreamLayout.Halves)?.metrics?.keyGap ?: me.saffer.sill.core.ui.PhonePortraitLayout.gap
        caps.zip(rects).forEach { (v, r) ->
            val t = Targets.expand(r, gap / 2)
            val tb = box(t); val rb = box(r)
            root.place(v, tb)
            v.drawn = android.graphics.RectF((rb.left - tb.left).toFloat(), (rb.top - tb.top).toFloat(), (rb.right - tb.left).toFloat(), (rb.bottom - tb.top).toFloat())
            v.invalidate()
        }
    }

    private fun placeDims(boxes: List<PxBox>) {
        while (dims.size < boxes.size) Catcher(this).also { c ->
            c.visibility = if (ui.state.overStream) View.VISIBLE else View.GONE
            c.onTap = { if (ui.state.settingsOpen) ui.closeSettings() else ui.closeDrawer() }
            dims.add(c); root.addView(c, root.indexOfChild(drawer))
        }
        while (dims.size > boxes.size) root.removeView(dims.removeAt(dims.size - 1))
        dims.zip(boxes).forEach { (c, b) -> root.place(c, b) }
        applyDrawer()
    }

    private fun onInsets(wi: WindowInsets) {
        val d = dp.density
        val new = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val i = wi.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            // The keyboard came or went by itself (the system's hide key): the Keyboard button follows,
            // only for the stream's own input (not the drawer's search field).
            if (currentFocus === input || !wi.isVisible(WindowInsets.Type.ime())) ui.keyboardChanged(wi.isVisible(WindowInsets.Type.ime()) && currentFocus === input)
            Insets(i.left / d, i.top / d, i.right / d, i.bottom / d)
        } else {
            @Suppress("DEPRECATION") val c = wi.displayCutout
            @Suppress("DEPRECATION")
            Insets(max(wi.stableInsetLeft, c?.safeInsetLeft ?: 0) / d, max(wi.stableInsetTop, c?.safeInsetTop ?: 0) / d,
                max(wi.stableInsetRight, c?.safeInsetRight ?: 0) / d, max(wi.stableInsetBottom, c?.safeInsetBottom ?: 0) / d)
        }
        if (new != insets) { insets = new; root.post { relayout() } }
    }

    // MARK: Viewport

    private val sendViewportNow = Runnable { sendViewport() }

    /** A new panel size or text scale reaches the Mac after Ui.viewportDebounce, once. */
    private fun scheduleViewport() {
        main.removeCallbacks(sendViewportNow)
        main.postDelayed(sendViewportNow, (Ui.viewportDebounce * 1000).toLong())
    }

    private fun sendViewport() {
        val l = layout ?: return
        val area = (l as? StreamLayout.Phone)?.viewport ?: l.panel
        if (area.width <= 0 || area.height <= 0) return
        @Suppress("DEPRECATION")
        val rate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display?.refreshRate else windowManager.defaultDisplay.refreshRate
        val lowPower = (getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode
        val fps = if (!lowPower && (rate ?: 60f) >= 100f) 120 else 60
        val v = Viewport(area.width, area.height, ui.state.textScale, fps = fps)
        if (v == sentViewport) return
        sentViewport = v
        session?.setViewport(v)
    }

    // MARK: Surface

    override fun surfaceCreated(holder: SurfaceHolder) { decoder.setSurface(holder.surface) }
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
    override fun surfaceDestroyed(holder: SurfaceHolder) { decoder.setSurface(null) }

    // MARK: Input

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            gestures.tick(frameTimeNanos / 1e9)
            if (gestures.needsTicks) Choreographer.getInstance().postFrameCallback(this) else ticking = false
        }
    }

    private fun ensureTicks() {
        if (!ticking && gestures.needsTicks) { ticking = true; Choreographer.getInstance().postFrameCallback(frameCallback) }
    }

    /** Touches on the picture; a mouse or stylus is the Mac's pointer. */
    fun touch(e: MotionEvent): Boolean {
        val s = session ?: return false
        if (ownPointer != null) { ownPointer = null; showPointer() }
        val t = e.eventTime / 1000.0
        val tool = e.getToolType(e.actionIndex)
        if (tool == MotionEvent.TOOL_TYPE_MOUSE || tool == MotionEvent.TOOL_TYPE_STYLUS) {
            val p = FrameMapping.toFrame(e.x.toDouble(), e.y.toDouble(), gestures.frameRect, clamped = true)!!
            val secondary = e.buttonState and MotionEvent.BUTTON_SECONDARY != 0
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    FrameMapping.toFrame(e.x.toDouble(), e.y.toDouble(), gestures.frameRect, clamped = false) ?: return true
                    s.input(InputEvent.Pointer(PointerAction.MOVE, p.first, p.second))
                    s.input(InputEvent.Pointer(if (secondary) PointerAction.RIGHT_DOWN else PointerAction.LEFT_DOWN, p.first, p.second))
                }
                MotionEvent.ACTION_MOVE -> s.input(InputEvent.Pointer(PointerAction.MOVE, p.first, p.second))
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                    s.input(InputEvent.Pointer(if (secondary) PointerAction.RIGHT_UP else PointerAction.LEFT_UP, p.first, p.second))
            }
            return true
        }
        val i = e.actionIndex
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> gestures.down(e.getPointerId(i), e.getX(i).toDouble(), e.getY(i).toDouble(), t)
            MotionEvent.ACTION_MOVE -> for (k in 0 until e.pointerCount) gestures.move(e.getPointerId(k), e.getX(k).toDouble(), e.getY(k).toDouble(), t)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> gestures.up(e.getPointerId(i), e.getX(i).toDouble(), e.getY(i).toDouble(), t)
            MotionEvent.ACTION_CANCEL -> gestures.cancel()
        }
        ensureTicks()
        return true
    }

    /** A mouse's hover and wheel (no button down). */
    fun generic(e: MotionEvent): Boolean {
        val s = session ?: return false
        if (e.source and InputDevice.SOURCE_CLASS_POINTER == 0) return false
        val p = FrameMapping.toFrame(e.x.toDouble(), e.y.toDouble(), gestures.frameRect, clamped = true)!!
        when (e.actionMasked) {
            MotionEvent.ACTION_HOVER_MOVE -> s.input(InputEvent.Pointer(PointerAction.MOVE, p.first, p.second))
            MotionEvent.ACTION_SCROLL -> {
                val r = gestures.frameRect
                val notch = 40.0 * dp.density
                s.input(InputEvent.ScrollGesture(ScrollPhase.BEGAN, p.first, p.second))
                s.input(InputEvent.Scroll(p.first, p.second, -e.getAxisValue(MotionEvent.AXIS_HSCROLL) * notch / r.w, e.getAxisValue(MotionEvent.AXIS_VSCROLL) * notch / r.h))
                s.input(InputEvent.ScrollGesture(ScrollPhase.ENDED, p.first, p.second))
            }
            else -> return false
        }
        return true
    }

    private fun tapKey(k: KeyRow.Key) {
        if (k == KeyRow.Key.Keyboard) { ui.tapKeyboard(); return }
        val (events, latch) = KeyRow.tap(k, ui.state.latched)
        events.forEach { session?.input(it) }
        ui.latch(latch)
    }

    /** Text from the soft keyboard: with a modifier latched, a letter is that shortcut (⌘ then c is ⌘C). */
    fun typed(text: String) {
        val s = session ?: return
        val latched = ui.state.latched
        val usage = if (latched != 0L && text.length == 1) CharKeys.usage(text[0]) else null
        if (usage != null) { KeyRow.press(usage, latched).forEach(s::input); ui.latch(0) }
        else s.input(InputEvent.Text(text))
    }

    private val keys = HardwareKeys { e -> session?.input(e) }

    /** A hardware keyboard: Esc closes what is open over the stream; the rest by [HardwareKeys]' rules.
     *  The drawer's search field keeps its own keys, but a key that went to the Mac comes up there. */
    override fun dispatchKeyEvent(e: KeyEvent): Boolean {
        if (e.keyCode == KeyEvent.KEYCODE_ESCAPE && e.action == KeyEvent.ACTION_DOWN && closeOne(leave = false)) return true
        if (e.keyCode == KeyEvent.KEYCODE_ESCAPE && e.action == KeyEvent.ACTION_UP && !keys.isDown(e.keyCode) && ui.state.overStream) return true
        if (session == null) return super.dispatchKeyEvent(e)
        var bits = 0L
        if (e.isShiftPressed) bits = bits or Modifiers.SHIFT
        if (e.isCtrlPressed) bits = bits or Modifiers.COMMAND          // Ctrl is ⌘, as on the Windows client
        if (e.isMetaPressed) bits = bits or Modifiers.CONTROL
        if (e.isAltPressed) bits = bits or Modifiers.OPTION
        if (e.action == KeyEvent.ACTION_UP && keys.up(e.keyCode, bits)) return true
        if (e.keyCode == KeyEvent.KEYCODE_BACK || currentFocus is EditText) return super.dispatchKeyEvent(e)
        val usage = HidKeys.android[e.keyCode] ?: return super.dispatchKeyEvent(e)
        if (e.action != KeyEvent.ACTION_DOWN) return true
        return keys.down(e.keyCode, usage, bits, e.unicodeChar, ::typed) || super.dispatchKeyEvent(e)
    }

    // MARK: Keep Screen On

    private val prefs by lazy { getSharedPreferences("sill", Context.MODE_PRIVATE) }
    /** On unless turned off: this screen exists only while connected, so it is "while connected". */
    private val keepScreenOn get() = prefs.getString(KEEP_SCREEN_ON, null) != "0"

    /** The window's keep-screen-on flag, as a video player's: a stream only watched never dims or locks. */
    private fun applyKeepScreenOn() {
        if (keepScreenOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /** Every key sent down, let go: the window lost focus or Sill left the screen, so its ups may never come here. */
    private fun releaseKeys() = keys.releaseAll()

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) releaseKeys()
    }

    override fun onPause() { releaseKeys(); super.onPause() }

    /** Back closes the ruler, the lights, the drawer, then the panel, one a press, before it leaves
     *  (to the home screen: the session goes on, as when an iPad goes home). */
    @Deprecated("Activity.onBackPressed; the platform's own until predictive back is opted into")
    override fun onBackPressed() { if (!closeOne(leave = true)) @Suppress("DEPRECATION") super.onBackPressed() }

    private fun closeOne(leave: Boolean): Boolean {
        val s = ui.state
        when (BackPlan.next(s.scaleOpen, s.windowMenu != null, s.drawerOpen, s.settingsOpen)) {
            BackPlan.Step.Ruler -> ui.rulerUp()
            BackPlan.Step.Lights -> ui.closeWindowMenu()
            BackPlan.Step.Drawer -> ui.closeDrawer()
            BackPlan.Step.Settings -> ui.closeSettings()
            BackPlan.Step.Leave -> { if (leave) moveTaskToBack(true); return leave }
        }
        return true
    }

    private fun setIme(shown: Boolean) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (shown) { input.requestFocus(); imm.showSoftInput(input, 0) }
        else imm.hideSoftInputFromWindow(input.windowToken, 0)
    }

    private fun showPointer() {
        pointer.at = if (layout is StreamLayout.Landscape) macPointer else macPointer ?: ownPointer
    }

    // MARK: Settings

    private fun now() = SystemClock.elapsedRealtime() / 1000.0

    private fun changeSettings(change: HostSettingsChange) {
        val s = session ?: return
        problem = null
        s.changeSettings { token -> ledger.pick(change, token, now()) } ?: return
        refreshPanel()
        main.removeCallbacks(expiry); main.postDelayed(expiry, 100)
    }

    /** While a pick waits: its spinner after 0.3 s, and back after SettingsLedger.timeout. */
    private val expiry = object : Runnable {
        override fun run() {
            if (ledger.expire(now(), SettingsLedger.timeout(rttMax))) {
                problem = PanelCopy.noAnswer(PanelCopy.macName(app.sessionMac))
                panel.announceForAccessibility(problem)
                Haptics.refused(panel)
            }
            refreshPanel()
            if (SettingsField.entries.any { ledger.pendingSince(it) != null }) main.postDelayed(this, 100)
        }
    }

    private fun refreshPanel() {
        if (!::panel.isInitialized) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val rate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display?.refreshRate else windowManager.defaultDisplay.refreshRate
        val wanted = if (!pm.isPowerSaveMode && (rate ?: 60f) >= 100f) 120 else 60
        val noun = if (resources.configuration.smallestScreenWidthDp >= 600) "tablet" else "phone"
        panel.update(PanelModel(app.sessionMac, noun, ledger.host, ledger.displayed, wanted, pm.isPowerSaveMode, olderMac, problem,
            { f -> ledger.pendingSince(f) }, now(), keepScreenOn))
    }

    private fun refreshStrip() {
        val l = list ?: return
        order = Reorder.arrange(l.windows.map { it.id }, order.ifEmpty { loadOrder() })
        val active = (l.active as? StreamSource.Window)?.id
        strip.thumbs = order.mapNotNull { id -> l.windows.firstOrNull { it.id == id } }
            .map { w -> Thumb(w, thumbBitmaps[w.id], icons[w.bundleID], w.id == active) }
    }

    private fun refreshDrawer() {
        val l = list ?: return
        drawer.update(l.windows, (l.active as? StreamSource.Window)?.id, appList, icons)
    }

    private fun orderKey() = "Sill.windowOrder.${app.sessionMac}"
    private fun loadOrder() = getSharedPreferences("sill", MODE_PRIVATE).getString(orderKey(), null)
        ?.split(',')?.mapNotNull { it.toLongOrNull() } ?: emptyList()
    private fun saveOrder(o: List<Long>) = getSharedPreferences("sill", MODE_PRIVATE).edit().putString(orderKey(), o.joinToString(",")).apply()

    // MARK: SessionListener (session threads)

    override fun onWindowList(list: WindowList) = runOnUiThread {
        val sourceChanged = this.list?.active != list.active
        if (this.list == null) listAt = now()
        this.list = list
        ui.windowsChanged(list.windows.map { it.id }.toSet())
        refreshStrip()
        if (ui.state.drawerOpen) refreshDrawer()
        if (sourceChanged) relayout()
    }
    override fun onThumbnail(windowID: Long, jpeg: ByteArray) {
        val bm = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return
        runOnUiThread { thumbBitmaps[windowID] = bm; refreshStrip() }
    }
    override fun onAppIcon(bundleID: String, png: ByteArray) {
        val bm = BitmapFactory.decodeByteArray(png, 0, png.size) ?: return
        runOnUiThread { icons[bundleID] = bm; refreshStrip(); if (ui.state.drawerOpen) refreshDrawer() }
    }
    override fun onAppList(apps: List<AppInfo>) = runOnUiThread { appList = apps; if (ui.state.drawerOpen) refreshDrawer() }
    override fun onVideoFormat(sets: ParameterSets) { decoder.format(sets) }
    override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { decoder.frame(annexB, keyframe) }
    override fun onMacPointer(position: Pair<Double, Double>?) = runOnUiThread {
        macPointer = position
        if (position != null) { pointerReseeds++; ownPointer = null }
        showPointer()
    }
    override fun onHostSettings(state: HostSettingsState) = runOnUiThread {
        val refused = ledger.receive(state)
        if (refused.isNotEmpty()) {
            panel.announceForAccessibility(PanelCopy.kept(PanelCopy.macName(app.sessionMac)))
            Haptics.refused(panel)
        }
        refreshPanel()
    }
    override fun onClipboard(text: String) = runOnUiThread {
        lastClip = text
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Mac", text))
    }
    override fun onMacMenu(menu: MacMenu) = runOnUiThread { macMenus.receive(menu) }
    override fun onStats(stats: ClientStats) = runOnUiThread {
        stats.rttMaxMs?.let { rttMax = it }
        // A Mac without kind 16 has said nothing two seconds into the session: older (HostSettingsPanel's olderMac).
        if (ledger.host == null && !olderMac && list != null && now() - listAt > 2.5) { olderMac = true; if (ui.state.settingsOpen) refreshPanel() }
    }
}

/** The stream screen's root: each child at the box the activity gives it (core's layout in pixels). */
class StreamRoot(context: Context) : ViewGroup(context) {
    private val boxes = HashMap<View, PxBox>()
    private val wraps = HashSet<View>()

    fun place(v: View, box: PxBox?, wrapHeight: Boolean = false) {
        if (box == null) { boxes.remove(v); v.visibility = if (v is Catcher || v is DrawerView || v is SettingsPanelView || v is LightsView) v.visibility else View.GONE; return }
        boxes[v] = box
        if (wrapHeight) wraps.add(v) else wraps.remove(v)
        if (v.visibility == View.GONE && v !is Catcher && v !is DrawerView && v !is SettingsPanelView && v !is LightsView) v.visibility = View.VISIBLE
    }

    override fun onMeasure(w: Int, h: Int) {
        setMeasuredDimension(MeasureSpec.getSize(w), MeasureSpec.getSize(h))
        for (i in 0 until childCount) {
            val c = getChildAt(i)
            val b = boxes[c] ?: run { c.measure(MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.EXACTLY)); null } ?: continue
            c.measure(MeasureSpec.makeMeasureSpec(b.width.coerceAtLeast(0), MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(b.height.coerceAtLeast(0), if (c in wraps) MeasureSpec.AT_MOST else MeasureSpec.EXACTLY))
        }
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            val c = getChildAt(i)
            val bx = boxes[c] ?: run { c.layout(0, 0, 0, 0); null } ?: continue
            c.layout(bx.left, bx.top, bx.left + c.measuredWidth, bx.top + c.measuredHeight)
        }
    }
}

/**
 * The view over the picture: it takes the touches (passed to the activity) and is what the soft
 * keyboard types into, as text (the Mac's layout never re-maps what was typed), backspace and Enter.
 */
class KeyInputView(private val activity: StreamActivity) : View(activity) {
    init { isFocusable = true; isFocusableInTouchMode = true; contentDescription = "The Mac's screen" }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (e.actionMasked == MotionEvent.ACTION_UP) performClick()
        return activity.touch(e)
    }
    override fun performClick(): Boolean = super.performClick()
    override fun onGenericMotionEvent(e: MotionEvent) = activity.generic(e) || super.onGenericMotionEvent(e)
    override fun onCheckIsTextEditor() = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_ACTION_NONE
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence, newCursorPosition: Int): Boolean {
                if (text.isNotEmpty()) activity.typed(text.toString())
                return true
            }
            override fun deleteSurroundingText(before: Int, after: Int): Boolean {
                repeat(before.coerceAtMost(64)) { activity.typed("\u0008") }
                return true
            }
            override fun sendKeyEvent(event: KeyEvent) = activity.dispatchKeyEvent(event)
        }
    }
}

/** This device's Keep Screen On (the Settings panel's This phone group; iOS's `Sill.keepScreenOn`). */
private const val KEEP_SCREEN_ON = "Sill.keepScreenOn"
