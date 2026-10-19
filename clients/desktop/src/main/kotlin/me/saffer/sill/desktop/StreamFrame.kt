package me.saffer.sill.desktop

import me.saffer.sill.core.AppInfo
import me.saffer.sill.core.ClientStats
import me.saffer.sill.core.CursorShape
import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.HostSettingsState
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.SessionListener
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.StreamSource
import me.saffer.sill.core.Viewport
import me.saffer.sill.core.WindowCommand
import me.saffer.sill.core.WindowList
import me.saffer.sill.core.ui.BarItem
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.KeyRow
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.PadTracker
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.SettingsLedger
import me.saffer.sill.core.ui.Size
import me.saffer.sill.core.ui.StreamLayout
import me.saffer.sill.core.ui.StreamUi
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.Ui
import me.saffer.sill.swingui.AppDrawer
import me.saffer.sill.swingui.BarButton
import me.saffer.sill.swingui.KeyCap
import me.saffer.sill.swingui.LightsMenu
import me.saffer.sill.swingui.ListItem
import me.saffer.sill.swingui.Scrim
import me.saffer.sill.swingui.SettingsSheet
import me.saffer.sill.swingui.SillControl
import me.saffer.sill.swingui.SillSwing
import me.saffer.sill.swingui.StripItem
import me.saffer.sill.swingui.StripMetrics
import me.saffer.sill.swingui.TextScaleButton
import me.saffer.sill.swingui.TextScaleRuler
import me.saffer.sill.swingui.TrackpadWell
import me.saffer.sill.swingui.WindowStrip
import java.awt.Dimension
import java.awt.Graphics
import java.awt.Rectangle
import java.awt.Toolkit
import java.awt.datatransfer.DataFlavor
import java.awt.datatransfer.StringSelection
import java.awt.event.ComponentAdapter
import java.awt.event.ComponentEvent
import java.awt.event.FocusAdapter
import java.awt.event.FocusEvent
import java.awt.event.KeyAdapter
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.event.MouseWheelEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.awt.image.BufferedImage
import javax.imageio.ImageIO
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.JFrame
import javax.swing.JLayeredPane
import javax.swing.KeyStroke
import javax.swing.SwingUtilities
import javax.swing.Timer
import kotlin.math.roundToInt

/**
 * The stream window: the iOS app's stream screen (StreamScreen.swift) drawn from the shared design
 * layer. Every rectangle is [StreamLayout]'s for the window's size (the landscape bar over the
 * stream; the halves, with the key row and the trackpad, in a window taller than wide); what is open
 * is [StreamUi]'s state and every control goes through it; the Settings panel shows the
 * [SettingsLedger]'s view. Built and changed on the event thread; the session's callbacks hop there.
 */
class StreamFrame(
    private val session: SillSession,
    private val macName: String,
    private val store: KeyValueStore = KeyValueStore.Memory(),
    private val onDisconnect: () -> Unit,
) : JFrame("$macName — Sill"), SessionListener {
    val video = VideoPanel()
    private val mapper = InputMapper()
    val ui = StreamUi { s, effects -> onUi(s, effects) }
    private val ledger = SettingsLedger()

    // The bar's buttons, and the strip.
    val apps = BarButton(Symbol.Magnifier, Copy.apps)
    val strip = WindowStrip()
    val textSize = TextScaleButton()
    val keyboard = BarButton(Symbol.Keyboard, Copy.keyboard)
    val desktop = BarButton(Symbol.Desktop, Copy.desktop)
    val settingsButton = BarButton(Symbol.Gear, Copy.settings)
    /** The Mac's menus (kinds 24, 25, 27), shown while the Mac sends a top level or a note. */
    val menusButton = BarButton(Symbol.Menus, Copy.menus)
    val macMenus = me.saffer.sill.core.ui.MacMenus(macName, send = { p ->
        when (p) { is me.saffer.sill.core.FetchMenu -> session.fetchMenu(p); is me.saffer.sill.core.PressMenuItem -> session.pressMenuItem(p) }
    }, worstRtt = { session.worstRtt }, now = { System.nanoTime() / 1e9 },
        postDelayed = { s, f -> Timer((s * 1000).toInt().coerceAtLeast(1)) { f() }.apply { isRepeats = false; start() } }).apply {
        onTop = { relayout() }
        onRefusal = { r -> java.awt.Toolkit.getDefaultToolkit().beep(); System.err.println("menus: ${r.announcement}") }
    }
    val ruler = TextScaleRuler()

    // What opens over the stream.
    val drawer = AppDrawer()
    val settings = SettingsSheet()
    private val scrim = Scrim()
    private val lightsCatcher = object : JComponent() {
        init { isVisible = false; addMouseListener(object : MouseAdapter() { override fun mousePressed(e: MouseEvent) { this@StreamFrame.ui.closeWindowMenu() } }) }
    }
    val lights = LightsMenu()

    // The halves' key row and trackpad (none in landscape).
    var caps: List<Pair<KeyRow.Key, KeyCap>> = emptyList(); private set
    private var capKeys: List<List<KeyRow.Key>> = emptyList()
    private var macPointerMoves = 0
    val padTracker = PadTracker(session::input).apply {
        latched = { ui.state.latched }
        onLatchSpent = { ui.latch(0) }
        feed = { (video.macPointer ?: video.ownPointer) to macPointerMoves }
        onPointer = { x, y -> video.ownPointer = x to y; video.macPointer = null; video.repaint() }
    }
    val trackpad = TrackpadWell(padTracker)

    var streamLayout: StreamLayout = StreamLayout.of(Size(1280.0, 800.0), phone = false)
        private set
    private val root = Root()

    private val thumbs = HashMap<Long, BufferedImage>()
    private val icons = HashMap<String, BufferedImage>()
    private var list: WindowList? = null
    private var appList: List<AppInfo> = emptyList()
    private var windowOrder: List<Long> = store.get(orderKey())?.split(',')?.mapNotNull { it.toLongOrNull() } ?: emptyList()
    private var lastClipboard: String? = null
    private var keyboardBeforeDrawer = false
    private var rulerActive = false
    private var lastStats: ClientStats? = null
    private val settingsView = SettingsView(this)
    private val pipeline = VideoPipeline(targetSize = { w, h -> video.targetPixels(w, h) },
        onPicture = { p, w, h -> video.show(p, w, h) }, log = { System.err.println(it) })

    private val viewportSoon = Timer((Ui.viewportDebounce * 1000).toInt()) { sendViewport() }.apply { isRepeats = false }
    private val wheelEnd = Timer(40) { send(mapper.wheelIdle()) }.apply { start() }

    private fun orderKey() = "Sill.windowOrder.$macName"

    // MARK: The layout

    /** The window's content in logical pixels (one iOS point each). */
    fun contentSize() = Size(root.width.toDouble(), root.height.toDouble())

    /** Sets the window so its content is `w`×`h` logical pixels (tests, and a first size). */
    fun setContentSize(w: Int, h: Int) {
        val i = insets
        setSize(w + i.left + i.right, h + i.top + i.bottom)
        validate()
    }

    /** The narrowest window that holds the bar's buttons and still a whole thumbnail (MacMenuButton.fits). */
    private fun applyMinimumSize() {
        val m = me.saffer.sill.core.ui.BarMetrics.regular
        val w = 2 * m.padding + 6 * (m.buttonWidth + m.gap) + m.thumbWidth + 16
        val i = insets
        minimumSize = Dimension(w.roundToInt() + i.left + i.right, 440 + i.top + i.bottom)
    }

    private fun Rect.awt() = Rectangle(x.roundToInt(), y.roundToInt(), width.roundToInt(), height.roundToInt())
    private fun JComponent.place(r: Rect?) { if (r == null) isVisible = false else { bounds = r.awt(); isVisible = true } }

    fun relayout() {
        val size = contentSize()
        if (size.width <= 0 || size.height <= 0) return
        val before = streamLayout.panel
        val l = StreamLayout.of(size, phone = false, menus = macMenus.state.hasMenus, spotlight = list?.active == StreamSource.Desktop)
        streamLayout = l
        video.place(l.panel)
        val bar = listOf(apps, menusButton, keyboard, desktop, settingsButton)
        for (b in bar) { b.radius = l.buttonRadius; b.iconSize = l.buttonIcon; b.spacing = l.buttonSpacing }
        textSize.radius = l.buttonRadius
        apps.place(l.items[BarItem.Apps]); keyboard.place(l.items[BarItem.Keyboard]); desktop.place(l.items[BarItem.Desktop])
        menusButton.place(l.items[BarItem.Menus])
        settingsButton.place(l.items[BarItem.Settings]); textSize.place(l.items[BarItem.TextSize]); strip.place(l.items[BarItem.Strip])
        strip.metrics = StripMetrics(l.thumbWidth, l.thumbHeight, l.thumbRadius, l.thumbSpacing, l.thumbPad, l.thumbFade, l.badge)
        ruler.bounds = l.ruler.awt(); ruler.pointsPerStep = l.rulerStep; ruler.radius = l.buttonRadius
        // The halves: the key row (Spotlight while the Desktop streams) and the trackpad.
        val halves = l as? StreamLayout.Halves
        val keys = halves?.keys ?: emptyList()
        if (keys != capKeys) rebuildCaps(keys)
        caps.forEachIndexed { i, (_, cap) -> cap.place(flatCaps(l).getOrNull(i)) }
        trackpad.place(l.trackpad)
        padTracker.verticalSpan = l.trackpadSpan
        drawer.bounds = l.drawer.awt()
        placeSettings()
        val dim = l.dim.firstOrNull() ?: Rect.zero
        scrim.bounds = dim.awt()
        lightsCatcher.bounds = Rectangle(0, 0, size.width.toInt(), size.height.toInt())
        placeLights()
        if (l.panel != before) viewportSoon.restart()
        root.repaint()
    }

    private fun flatCaps(l: StreamLayout) = l.caps.flatten()

    private fun placeSettings() {
        val r = streamLayout.settings
        settings.maxHeight = r.height.roundToInt()
        settings.setBounds(r.x.roundToInt(), r.y.roundToInt(), r.width.roundToInt(), settings.heightAt(r.width.roundToInt()))
    }

    private fun placeLights() {
        val id = ui.state.windowMenu ?: return
        val t = strip.thumbBounds(id) ?: return
        val s = strip.bounds
        val thumb = t.offset(s.x.toDouble(), s.y.toDouble())
        val size = contentSize()
        val w = Ui.lightsWidth; val h = Ui.lightsHeight
        val below = streamLayout.lightsBelow || thumb.midY < size.height / 2
        val x = thumb.midX.coerceIn(w / 2 + 8, size.width - w / 2 - 8)
        val y = if (below) thumb.maxY + 8 + h / 2 else thumb.minY - 8 - h / 2
        lights.below = below
        lights.place(x, y)
    }

    private fun rebuildCaps(keys: List<List<KeyRow.Key>>) {
        caps.forEach { root.remove(it.second) }
        capKeys = keys
        caps = keys.flatten().map { key ->
            val cap = when (key) {
                is KeyRow.Key.Press -> KeyCap(key.title, null)
                is KeyRow.Key.Modifier -> KeyCap(key.title, null)
                is KeyRow.Key.Arrow -> KeyCap(null, when (key.direction) {
                    KeyRow.Direction.Left -> Symbol.ChevronLeft; KeyRow.Direction.Down -> Symbol.ChevronDown
                    KeyRow.Direction.Up -> Symbol.ChevronUp; KeyRow.Direction.Right -> Symbol.ChevronRight
                })
                KeyRow.Key.Keyboard -> KeyCap(null, Symbol.Keyboard)
                KeyRow.Key.Spotlight -> KeyCap(null, Symbol.Spotlight)
            }
            cap.accessibleName = key.label
            cap.onAction = { tapKey(key) }
            root.add(cap, JLayeredPane.DEFAULT_LAYER as Any)
            key to cap
        }
        renderCaps(ui.state)
    }

    private fun tapKey(key: KeyRow.Key) {
        if (key == KeyRow.Key.Keyboard) { ui.tapKeyboard(); return }
        val (events, latched) = KeyRow.tap(key, ui.state.latched)
        events.forEach(session::input)
        ui.latch(latched)
    }

    // MARK: The bar

    private fun wireBar() {
        apps.onAction = { ui.tapApps() }
        keyboard.onAction = { ui.tapKeyboard() }
        desktop.onAction = { ui.tapDesktop() }
        desktop.accessibleName = Copy.showDesktop
        settingsButton.onAction = { ui.tapSettings() }
        menusButton.onAction = { me.saffer.sill.swingui.MacMenuPopup.show(macMenus, menusButton, 0, menusButton.height) }
        textSize.accessibleName = Copy.textSize
        textSize.onDown = { rulerActive = true; ui.rulerDown() }
        textSize.onDrag = { dx -> if (rulerActive && ui.rulerMoved(dx, streamLayout.rulerStep)) ruler.moveTo(ui.rulerLive) }
        textSize.onUp = { if (rulerActive) { rulerActive = false; ui.rulerUp() } }
        textSize.onStep = { up -> ui.stepScale(up) }
        strip.onSelect = { id -> session.select(StreamSource.Window(id)) }
        strip.onHold = { id -> ui.openWindowMenu(id) }
        strip.onCloseMenu = { ui.closeWindowMenu() }
        strip.onReorder = { order -> windowOrder = order; store.put(orderKey(), order.joinToString(",")) }
    }

    private fun wireOverlays() {
        drawer.setMac(macName)
        drawer.sections = { q -> drawerSections(q) }
        drawer.onPick = { key -> pickInDrawer(key) }
        drawer.onHidden = { updateScrim() }
        settings.onHidden = { updateScrim() }
        settings.done.onAction = { ui.closeSettings() }
        settings.foot.onAction = { onDisconnect() }
        scrim.onClick = { if (ui.state.drawerOpen) ui.closeDrawer() else if (ui.state.settingsOpen) ui.closeSettings() }
        lights.onCommand = { action ->
            ui.state.windowMenu?.let { session.windowCommand(it, action) }
            ui.closeWindowMenu()
        }
        // Esc, wherever the focus is: the ruler, then the lights, then the drawer, then the panel.
        root.getInputMap(JComponent.WHEN_IN_FOCUSED_WINDOW).put(KeyStroke.getKeyStroke(KeyEvent.VK_ESCAPE, 0), "sill.escape")
        root.actionMap.put("sill.escape", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { closeTopmost() } })
    }

    /** Esc's order of closing; false when nothing was open (then Esc is the Mac's). */
    fun closeTopmost(): Boolean {
        val s = ui.state
        when {
            s.scaleOpen -> { rulerActive = false; ui.rulerMoved(0.0, streamLayout.rulerStep); ui.rulerUp() }
            s.windowMenu != null -> ui.closeWindowMenu()
            s.drawerOpen -> ui.closeDrawer()
            s.settingsOpen -> ui.closeSettings()
            else -> return false
        }
        return true
    }

    // MARK: State

    private fun onUi(s: StreamUi.State, effects: List<StreamUi.Effect>) {
        for (e in effects) when (e) {
            is StreamUi.Effect.Keyboard -> if (e.shown) video.requestFocusInWindow() else root.requestFocusInWindow()
            StreamUi.Effect.SendViewport -> viewportSoon.restart()
            StreamUi.Effect.SelectDesktop -> session.select(StreamSource.Desktop)
        }
        render(s)
    }

    private var rendered = StreamUi.State()

    private fun render(s: StreamUi.State) {
        val was = rendered
        rendered = s
        apps.open = s.drawerOpen
        apps.accessibleName = if (s.drawerOpen) Copy.closeAppList else Copy.openAppList
        keyboard.open = s.keyboardShown
        keyboard.accessibleName = if (s.keyboardShown) Copy.hideKeyboard else Copy.showKeyboard
        settingsButton.open = s.settingsOpen
        settingsButton.accessibleName = if (s.settingsOpen) Copy.closeSettings else Copy.settingsFor(macName)
        desktop.open = list?.active == StreamSource.Desktop
        textSize.scale = s.textScale
        textSize.accessibleName = Copy.textSize

        // The Aa ruler: open under the pointer, the other buttons fading (and taking no click).
        if (s.scaleOpen != was.scaleOpen) {
            if (s.scaleOpen) ruler.open(ui.rulerLive) else ruler.close()
            textSize.hiddenForRuler = s.scaleOpen
            strip.fade.animate(if (s.scaleOpen) 0.2 else 1.0, Motion.scaleFade)
            for (b in listOf<SillControl>(menusButton, keyboard, desktop, settingsButton)) b.fadeTo(if (s.scaleOpen) 0.0 else 1.0)
        }

        // The drawer: the field takes the keys while it is open; they go back to the Mac after.
        if (s.drawerOpen != was.drawerOpen) {
            if (s.drawerOpen) { keyboardBeforeDrawer = s.keyboardShown; drawer.open() }
            else { drawer.present(false); if (keyboardBeforeDrawer && !s.settingsOpen) video.requestFocusInWindow() }
        }
        // The Settings panel.
        if (s.settingsOpen != was.settingsOpen) {
            if (s.settingsOpen) { settingsView.rebuild(force = true); placeSettings(); settings.present(true) } else settings.present(false)
        }
        updateScrim()

        // A thumbnail's lights.
        strip.setMenu(s.windowMenu)
        if (s.windowMenu != was.windowMenu) {
            val id = s.windowMenu
            if (id != null) {
                lights.windowName = list?.windows?.firstOrNull { it.id == id }?.appName ?: ""
                placeLights()
                lightsCatcher.isVisible = true; lights.isVisible = true; lights.open()
            } else { lightsCatcher.isVisible = false; lights.isVisible = false }
        }
        renderCaps(s)
        root.repaint()
    }

    private fun renderCaps(s: StreamUi.State) {
        for ((key, cap) in caps) cap.open = when (key) {
            is KeyRow.Key.Modifier -> s.latched and key.bit != 0L
            KeyRow.Key.Keyboard -> s.keyboardShown
            else -> false
        }
    }

    private fun updateScrim() {
        val s = ui.state
        val sheet = if (s.drawerOpen || (!s.settingsOpen && drawer.isVisible)) drawer else settings
        scrim.sheet = sheet
        scrim.isVisible = s.overStream || drawer.isVisible || settings.isVisible
        scrim.dim.animate(if (s.drawerOpen) Ui.dimAlpha else 0.0, Motion.drawer)
    }

    // MARK: The drawer's rows

    private fun drawerSections(query: String): List<ListItem> {
        val l = list ?: return emptyList()
        fun matches(name: String) = query.isEmpty() || name.contains(query, ignoreCase = true)
        val order = LinkedHashMap<String, MutableList<me.saffer.sill.core.WindowInfo>>()
        for (w in l.windows) order.getOrPut(w.bundleID) { ArrayList() }.add(w)
        val activeBundle = (l.active as? StreamSource.Window)?.let { a -> l.windows.firstOrNull { it.id == a.id }?.bundleID }
        val open = order.filter { matches(it.value.first().appName) }
        val running = order.keys
        val closed = appList.filter { it.bundleID !in running && matches(it.name) }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
        val out = ArrayList<ListItem>()
        if (open.isNotEmpty()) {
            out += ListItem.Header(Copy.openNow)
            for ((bundle, ws) in open) out += ListItem.Row("open:$bundle", ws.first().appName, Copy.windows(ws.size), Ui.openRowHeight, bundle == activeBundle, icons[bundle])
        }
        if (closed.isNotEmpty()) {
            out += ListItem.Header(Copy.allApps, extraTop = 2.0)
            for (a in closed) out += ListItem.Row("app:${a.bundleID}", a.name, null, Ui.closedRowHeight, false, icons[a.bundleID])
        }
        return out
    }

    /** An open app: its first window, or the next one if it is the one showing; the drawer closes. A closed app launches. */
    private fun pickInDrawer(key: String) {
        val l = list ?: return
        if (key.startsWith("open:")) {
            val ws = l.windows.filter { it.bundleID == key.removePrefix("open:") }
            if (ws.isEmpty()) return
            val i = ws.indexOfFirst { StreamSource.Window(it.id) == l.active }
            session.select(StreamSource.Window(ws[if (i >= 0) (i + 1) % ws.size else 0].id))
            ui.closeDrawer()
        } else if (key.startsWith("app:")) session.launch(key.removePrefix("app:"))
    }

    // MARK: Settings (SettingsView builds the panel's rows)

    internal val mac get() = macName
    internal fun hostSettings() = ledger.host
    internal fun displayedSettings() = ledger.displayed
    internal fun pendingSince(f: me.saffer.sill.core.ui.SettingsField) = ledger.pendingSince(f)
    internal fun wantedFps() = graphicsConfiguration?.device?.displayMode?.refreshRate?.takeIf { it > 0 }?.let { if (it >= 100) 120 else 60 } ?: 60
    internal fun disconnect() = onDisconnect()
    internal var problem: String? = null
    private val expiry = Timer(500) { expirePicks() }
    private val olderMacTimer = Timer(2000) { settingsView.olderMac = true; settingsView.rebuild() }.apply { isRepeats = false; start() }

    /** A control's pick: only what changes what the panel shows goes to the Mac, with its token. */
    internal fun pick(change: HostSettingsChange) {
        // The session gives the token, so the ledger waits for exactly what the Mac will answer.
        session.changeSettings { token -> ledger.pick(change, token, me.saffer.sill.swingui.Clock.now()) } ?: return
        problem = null
        if (!expiry.isRunning) expiry.start()
        settingsView.rebuild()
    }

    private fun expirePicks() {
        val timeout = SettingsLedger.timeout(lastStats?.rttMaxMs)
        if (ledger.expire(me.saffer.sill.swingui.Clock.now(), timeout)) {
            problem = me.saffer.sill.core.ui.PanelCopy.noAnswer(me.saffer.sill.core.ui.PanelCopy.macName(macName))
            settingsView.rebuild()
        }
        if (me.saffer.sill.core.ui.SettingsField.entries.none { ledger.pendingSince(it) != null }) expiry.stop()
    }

    internal fun relayoutSettings() { if (settings.isVisible) { placeSettings(); settings.revalidate(); settings.repaint() } }

    // MARK: Input

    private fun send(events: List<InputEvent>) = events.forEach(session::input)

    private fun installInput() {
        val m = object : MouseAdapter() {
            override fun mousePressed(e: MouseEvent) { video.requestFocusInWindow(); mapper.frameRect = video.frameRect(); send(mapper.mouse(e)) }
            override fun mouseReleased(e: MouseEvent) { mapper.frameRect = video.frameRect(); send(mapper.mouse(e)) }
            override fun mouseMoved(e: MouseEvent) { mapper.frameRect = video.frameRect(); send(mapper.mouse(e)); video.macPointer = null; video.ownPointer = null }
            override fun mouseDragged(e: MouseEvent) { mapper.frameRect = video.frameRect(); send(mapper.mouse(e)) }
            override fun mouseWheelMoved(e: MouseWheelEvent) { mapper.frameRect = video.frameRect(); send(mapper.wheel(e)) }
        }
        video.addMouseListener(m); video.addMouseMotionListener(m); video.addMouseWheelListener(m)
        video.addKeyListener(object : KeyAdapter() {
            override fun keyPressed(e: KeyEvent) {
                if (e.keyCode == KeyEvent.VK_ESCAPE && e.modifiersEx == 0 && closeTopmost()) { e.consume(); return }
                send(mapper.keyPressed(e)); e.consume()
            }
            override fun keyReleased(e: KeyEvent) { send(mapper.keyReleased(e)); e.consume() }
            override fun keyTyped(e: KeyEvent) { send(mapper.keyTyped(e)); e.consume() }
        })
        video.addFocusListener(object : FocusAdapter() {
            override fun focusGained(e: FocusEvent) { ui.keyboardChanged(true) }
            override fun focusLost(e: FocusEvent) { if (!e.isTemporary) { send(mapper.releaseAll()); ui.keyboardChanged(false) } }
        })
    }

    private fun sendViewport() {
        val p = streamLayout.panel
        if (p.width <= 0 || p.height <= 0) return
        session.setViewport(Viewport(p.width, p.height, ui.state.textScale, fps = wantedFps()))
    }

    private fun sendClipboardIfChanged() {
        val text = try { Toolkit.getDefaultToolkit().systemClipboard.getData(DataFlavor.stringFlavor) as? String } catch (_: Exception) { null } ?: return
        if (text != lastClipboard && session.sendClipboard(text)) lastClipboard = text
    }

    // MARK: The strip's items

    private fun refreshStrip() {
        val l = list ?: return
        val ids = l.windows.map { it.id }
        // The device's own arrangement first, then windows it has not placed, in the Mac's order.
        val ordered = windowOrder.filter { it in ids } + ids.filter { it !in windowOrder }
        val byId = l.windows.associateBy { it.id }
        strip.setItems(ordered.mapNotNull { id -> byId[id]?.let { w -> StripItem(w.id, w.title, w.appName, thumbs[w.id], icons[w.bundleID], l.active == StreamSource.Window(w.id)) } })
        if (drawer.isVisible) drawer.refresh()
    }

    private fun hop(f: () -> Unit) = SwingUtilities.invokeLater(f)

    // MARK: SessionListener (session threads)

    override fun onWindowList(list: WindowList) = hop {
        val spotlightBefore = this.list?.active == StreamSource.Desktop
        this.list = list
        thumbs.keys.retainAll(list.windows.map { it.id }.toSet())
        ui.windowsChanged(list.windows.map { it.id }.toSet())
        refreshStrip()
        desktop.open = list.active == StreamSource.Desktop
        if ((list.active == StreamSource.Desktop) != spotlightBefore) relayout()
        if (ui.state.windowMenu != null) placeLights()
    }
    override fun onThumbnail(windowID: Long, jpeg: ByteArray) {
        val img = try { ImageIO.read(jpeg.inputStream()) } catch (_: Exception) { null } ?: return
        hop { thumbs[windowID] = img; refreshStrip() }
    }
    override fun onAppIcon(bundleID: String, png: ByteArray) {
        val img = try { ImageIO.read(png.inputStream()) } catch (_: Exception) { null } ?: return
        hop { icons[bundleID] = img; refreshStrip() }
    }
    override fun onAppList(apps: List<AppInfo>) = hop { appList = apps; if (drawer.isVisible) drawer.refresh() }
    override fun onVideoFormat(sets: ParameterSets) { pipeline.format(sets) }
    override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { pipeline.frame(annexB, keyframe) }
    override fun onCursorShape(shape: CursorShape) = hop { video.cursorShape(shape) }
    override fun onMacPointer(position: Pair<Double, Double>?) = hop {
        video.macPointer = position
        if (position != null) { macPointerMoves++; video.ownPointer = null }
        video.repaint()
    }
    override fun onHostSettings(state: HostSettingsState) = hop {
        val refused = ledger.receive(state)
        if (refused.isNotEmpty()) Toolkit.getDefaultToolkit().beep()
        settingsView.rebuild()
    }
    override fun onClipboard(text: String) = hop {
        lastClipboard = text
        try { Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(text), null) } catch (_: Exception) {}
    }
    override fun onStats(stats: ClientStats) = hop { lastStats = stats }
    override fun onMacMenu(menu: me.saffer.sill.core.MacMenu) = hop { macMenus.receive(menu) }

    // Last, once every property above has its value: the first render reads them all.
    init {
        defaultCloseOperation = DISPOSE_ON_CLOSE
        contentPane = root
        background = java.awt.Color.BLACK
        root.add(video, JLayeredPane.DEFAULT_LAYER as Any)
        for (c in listOf(apps, strip, menusButton, textSize, keyboard, desktop, settingsButton, trackpad)) root.add(c, JLayeredPane.DEFAULT_LAYER as Any)
        root.add(scrim, JLayeredPane.PALETTE_LAYER as Any)
        root.add(drawer, JLayeredPane.MODAL_LAYER as Any)
        root.add(settings, JLayeredPane.MODAL_LAYER as Any)
        root.add(ruler, JLayeredPane.POPUP_LAYER as Any)
        root.add(lightsCatcher, JLayeredPane.DRAG_LAYER as Any)
        root.add(lights, JLayeredPane.DRAG_LAYER as Any)
        wireBar()
        wireOverlays()
        installInput()
        // Tab goes through the bar in its order: Apps, the strip, Aa, Keyboard, Desktop, Settings.
        focusTraversalPolicy = object : javax.swing.LayoutFocusTraversalPolicy() {
            override fun accept(c: java.awt.Component) = super.accept(c) && c !== video
        }
        root.addComponentListener(object : ComponentAdapter() { override fun componentResized(e: ComponentEvent) = relayout() })
        addWindowListener(object : WindowAdapter() {
            override fun windowOpened(e: WindowEvent) { applyMinimumSize(); video.requestFocusInWindow() }
            override fun windowActivated(e: WindowEvent) { sendClipboardIfChanged(); if (ui.state.keyboardShown) video.requestFocusInWindow() }
            override fun windowDeactivated(e: WindowEvent) = send(mapper.releaseAll())
            override fun windowClosed(e: WindowEvent) { pipeline.close(); onDisconnect() }
        })
        // A hardware keyboard is always there: the stream takes it from the start (HardwareKeyboardPolicy).
        ui.keyboardChanged(true)
        size = Dimension(1280, 860)
        setLocationRelativeTo(null)
        relayout()
    }

    fun close() {
        macMenus.reset()
        wheelEnd.stop(); viewportSoon.stop(); expiry.stop(); olderMacTimer.stop()
        // Timers that would outlive the window: the held thumbnail's wiggle, the ruler, the panel's spinners.
        strip.setMenu(null); ruler.close(); settings.body.removeAll()
        pipeline.close()
        dispose()
    }

    /** The window's root: black, the landscape bar's colour behind the bar; the layers over it. */
    private inner class Root : JLayeredPane() {
        init { isOpaque = true; isFocusable = true; layout = null }
        override fun paintComponent(g: Graphics) {
            g.color = java.awt.Color.BLACK
            g.fillRect(0, 0, width, height)
            (this@StreamFrame.streamLayout as? StreamLayout.Landscape)?.let { l ->
                g.color = SillSwing.color(Palette.bar)
                g.fillRect(0, 0, width, l.bar.height.roundToInt())
            }
        }
    }
}
