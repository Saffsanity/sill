package me.saffer.sill.host.ui

import me.saffer.sill.core.QualityPreset
import me.saffer.sill.core.ui.Glyph
import me.saffer.sill.core.ui.PanelCopy
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.host.HostMenu
import me.saffer.sill.host.HostStatusSnapshot
import me.saffer.sill.host.SettingsCopy
import me.saffer.sill.swingui.SillSwing
import java.awt.BorderLayout
import java.awt.Dimension
import java.awt.Graphics
import java.awt.GraphicsEnvironment
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.geom.Rectangle2D
import java.awt.geom.RoundRectangle2D
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.JFrame
import javax.swing.JPanel
import javax.swing.JScrollPane
import javax.swing.KeyStroke
import javax.swing.ScrollPaneConstants

/** Settings' tabs in the toolbar's order (SettingsTab): the PC host's three of Sill.app's six. */
enum class SettingsTab(val title: String, val glyph: List<Glyph>) {
    GENERAL("General", Symbol.Gear.shapes), DEVICES("Devices", HostGlyphs.devices), STREAMING("Streaming", HostGlyphs.stream)
}

/**
 * Settings (SettingsWindow.swift with SettingsPanes.swift and DevicesPane.swift): toolbar tabs over
 * grouped Forms 520 pt wide, the window titled by its tab, made once and hidden on close, never
 * taller than its screen (Sill.app's issue #59: the Form scrolls). Ctrl+W closes, Ctrl+Tab and
 * Ctrl+Shift+Tab go through the tabs. Every control sets the host's settings as its menu does, and
 * each pane follows the host's state once a second and whenever it changes.
 */
class SettingsWindow(private val model: HostModel) {
    val frame = JFrame("General")
    var tab = SettingsTab.GENERAL; private set
    private val pages = SettingsTab.entries.associateWith { FormPage() }
    private val builders: Map<SettingsTab, PaneBuilder> = mapOf(
        SettingsTab.GENERAL to GeneralPane(model), SettingsTab.DEVICES to DevicesPane(model), SettingsTab.STREAMING to StreamingPane(model))
    private val toolbar = Toolbar { select(it) }
    private val scroll = JScrollPane().apply {
        border = null; horizontalScrollBarPolicy = ScrollPaneConstants.HORIZONTAL_SCROLLBAR_NEVER
        verticalScrollBar.unitIncrement = 16
    }

    init {
        frame.isResizable = false
        frame.defaultCloseOperation = JFrame.HIDE_ON_CLOSE
        frame.contentPane = JPanel(BorderLayout()).apply { add(toolbar, BorderLayout.NORTH); add(scroll, BorderLayout.CENTER) }
        val keys = frame.rootPane.getInputMap(JComponent.WHEN_IN_FOCUSED_WINDOW)
        keys.put(KeyStroke.getKeyStroke(KeyEvent.VK_W, KeyEvent.CTRL_DOWN_MASK), "close")
        keys.put(KeyStroke.getKeyStroke(KeyEvent.VK_TAB, KeyEvent.CTRL_DOWN_MASK), "next")
        keys.put(KeyStroke.getKeyStroke(KeyEvent.VK_TAB, KeyEvent.CTRL_DOWN_MASK or KeyEvent.SHIFT_DOWN_MASK), "previous")
        frame.rootPane.actionMap.put("close", action { frame.isVisible = false })
        frame.rootPane.actionMap.put("next", action { select(SettingsTab.entries[(tab.ordinal + 1) % 3]) })
        frame.rootPane.actionMap.put("previous", action { select(SettingsTab.entries[(tab.ordinal + 2) % 3]) })
        for ((t, b) in builders) b.build(pages.getValue(t))
        select(SettingsTab.GENERAL)
    }

    private fun action(f: () -> Unit) = object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent?) = f() }

    fun select(t: SettingsTab) {
        tab = t
        frame.title = t.title
        toolbar.selected = t; toolbar.repaint()
        val page = pages.getValue(t)
        builders.getValue(t).refresh(page)
        scroll.setViewportView(page)
        fit()
    }

    /** The window's height: the tab's whole Form, but no taller than the screen's usable area less 24 pt. */
    fun fit() {
        val page = pages.getValue(tab)
        page.doLayout()
        val gc = frame.graphicsConfiguration ?: GraphicsEnvironment.getLocalGraphicsEnvironment().defaultScreenDevice.defaultConfiguration
        val insets = java.awt.Toolkit.getDefaultToolkit().getScreenInsets(gc)
        val usable = gc.bounds.height - insets.top - insets.bottom - 24 - 40
        val h = minOf(page.pageHeight(), usable - Toolbar.HEIGHT).coerceAtLeast(200)
        scroll.preferredSize = Dimension(page.pageWidth + if (page.pageHeight() > h) scroll.verticalScrollBar.preferredSize.width else 0, h)
        frame.pack()
    }

    /** The host's state changed: each pane updates in place, or is made again when its rows change. */
    fun refresh() {
        for ((t, b) in builders) {
            val page = pages.getValue(t)
            if (b.refresh(page) && t == tab) { page.revalidate(); fit() }
            page.repaint()
        }
    }

    fun show(t: SettingsTab? = null) {
        t?.let(::select)
        refresh()
        if (!frame.isVisible) frame.setLocationRelativeTo(null)
        frame.isVisible = true
        frame.toFront()
    }

    /** Settings' toolbar: each tab its glyph over its title, the selected one on a rounded fill. */
    class Toolbar(val onSelect: (SettingsTab) -> Unit) : JComponent() {
        companion object { const val HEIGHT = 56; const val TAB_W = 72 }
        var selected = SettingsTab.GENERAL
        private val font = MacType.font(MacType.toolbarLabel)
        init {
            preferredSize = Dimension(520, HEIGHT)
            addMouseListener(object : MouseAdapter() {
                override fun mouseReleased(e: MouseEvent) { tabAt(e.x)?.let(onSelect) }
            })
        }
        private fun startX() = (width - TAB_W * SettingsTab.entries.size) / 2
        fun tabRect(t: SettingsTab) = Rectangle2D.Double((startX() + t.ordinal * TAB_W).toDouble() + 2, 5.0, TAB_W - 4.0, HEIGHT - 10.0)
        private fun tabAt(x: Int) = SettingsTab.entries.firstOrNull { tabRect(it).let { r -> x >= r.x && x < r.x + r.width } }
        override fun paintComponent(g0: Graphics) {
            val g = SillSwing.smooth(g0)
            val c = HostTheme.c
            g.color = c.window.awt(); g.fillRect(0, 0, width, height)
            g.color = c.separator.awt(); g.fill(Rectangle2D.Double(0.0, height - 1.0, width.toDouble(), 1.0))
            for (t in SettingsTab.entries) {
                val r = tabRect(t)
                val on = t == selected
                if (on) { g.color = c.toolbarSelected.awt(); g.fill(RoundRectangle2D.Double(r.x, r.y, r.width, r.height, 12.0, 12.0)) }
                val col = if (on) c.accent else c.secondary
                HostGlyphs.paint(g, t.glyph, r.centerX - 11, r.y + 4, 22.0, col, c.window)
                SillSwing.centred(g, t.title, me.saffer.sill.core.ui.Rect(r.x, 0.0, r.width, 0.0), r.y + 28, font, if (on) c.accent else c.label)
            }
            g.dispose()
        }
    }
}

/** One pane: built once, then refreshed; `refresh` makes it again when its rows changed and says so. */
abstract class PaneBuilder {
    private var key: Any? = null
    protected abstract fun structure(): Any
    protected abstract fun make(page: FormPage)
    protected open fun update() {}
    fun build(page: FormPage) { key = structure(); page.clear(); make(page); page.revalidate() }
    fun refresh(page: FormPage): Boolean {
        if (structure() != key) { build(page); return true }
        update(); return false
    }
}

class GeneralPane(private val model: HostModel) : PaneBuilder() {
    private lateinit var login: MacSwitch
    private lateinit var name: ValueText
    private lateinit var clipboard: MacSwitch
    override fun structure(): Any = model.login().let { it.available to it.error }
    override fun make(page: FormPage) {
        val l = model.login()
        login = MacSwitch(l.on) { model.setLogin(it) }.apply { enabledState = l.available }
        page.section(null, when {
            !l.available -> footnote("Available when Sill Host runs from its installed copy.")
            l.error != null -> footWarning(l.error!!)
            else -> null
        }, LabeledRow("Launch at login", login))
        page.section(null, null, LabeledRow("Running from", ValueText(model.runningFrom, 300)))
        name = ValueText(networkName(), 260)
        page.section(null, footnote(SettingsCopy.NAME_FOOTER), LabeledRow("Visible on your network as", name))
        clipboard = MacSwitch(model.shareClipboard) { model.setShareClipboard(it) }
        page.section(null, footnote(SettingsCopy.CLIPBOARD_FOOTER), LabeledRow("Share clipboard with devices", clipboard))
        page.section(null, null, ButtonsRow(PushButton("Show Log…") { model.showLog() }, PushButton("Reveal Log File") { model.revealLog() }.apply { enabledState = model.logFile != null }))
        page.section(null, footnote("Sill Host ${model.version}. Free and open source."), ButtonsRow(PushButton("Quit Sill Host") { model.quit() }))
    }
    override fun update() { login.set(model.login().on); clipboard.set(model.shareClipboard); name.text = networkName(); name.repaint() }

    private fun networkName() = when (val n = model.status().network) {
        is HostStatusSnapshot.Network.Advertising -> "“${n.name}”"
        is HostStatusSnapshot.Network.NotAdvertised -> "Not advertised (port ${n.port} by address)"
        is HostStatusSnapshot.Network.Failed -> "Not visible (Bonjour failed)"
        HostStatusSnapshot.Network.Starting -> "Registering…"
    }
}

class DevicesPane(private val model: HostModel) : PaneBuilder() {
    private lateinit var require: MacSwitch
    private var removed: String? = null
    override fun structure(): Any = listOf(model.requirePairing, model.paired().map { it.fingerprint to it.name }, removed, model.paired().map { it.lastConnectedAt })
    override fun make(page: FormPage) {
        require = MacSwitch(model.requirePairing) { model.setRequirePairing(it) }
        page.section(null, if (model.requirePairing) footnote(SettingsCopy.REQUIRE_ON) else footWarning(SettingsCopy.REQUIRE_OFF), LabeledRow("Require pairing", require))
        val rows = ArrayList<FormRow>()
        removed?.let { rows += TextRow(SettingsCopy.removed(it)) }
        val devices = model.paired()
        if (devices.isEmpty()) rows += TextRow(SettingsCopy.NO_DEVICES, secondary = true)
        val now = System.currentTimeMillis() / 1e3
        for (d in devices) rows += LabeledRow(d.name, PushButton("Remove") { removed = d.name; model.removeDevice(d.fingerprint) }, SettingsCopy.pairedDetail(d, now))
        rows += ButtonsRow(PushButton("Pair a Device…") { model.openPairing() })
        page.section("Paired Devices", footnote(SettingsCopy.PAIRED_FOOTER), *rows.toTypedArray())
    }
    override fun update() { require.set(model.requirePairing) }
}

class StreamingPane(private val model: HostModel) : PaneBuilder() {
    private lateinit var rate: Segmented
    private lateinit var quality: PopUpButton
    private lateinit var scale: PopUpButton
    private lateinit var speed: MacSwitch
    override fun structure(): Any = (model.status().stream?.softwareEncoder == true) to (QualityPreset.of(model.config.bitrate) == null)
    private fun qualities() = QualityPreset.entries.map { it.title to (it.bitrate as Any) } +
        (if (QualityPreset.of(model.config.bitrate) == null) listOf(HostMenu.qualityTitle(model.config.bitrate) to (model.config.bitrate as Any)) else emptyList())
    override fun make(page: FormPage) {
        val c = model.config
        rate = Segmented(listOf("60 fps" to 60, "120 fps" to 120), c.maxFPS) { model.setConfig(model.config.copy(maxFPS = it as Int)) }
        quality = PopUpButton(qualities(), c.bitrate) { model.setConfig(model.config.copy(bitrate = it as Int)) }
        scale = PopUpButton(listOf("Retina" to 2.0, "Standard" to 1.0), if (c.captureScale >= 1.5) 2.0 else 1.0) { model.setConfig(model.config.copy(captureScale = it as Double)) }
        speed = MacSwitch(c.prioritizeSpeed) { model.setConfig(model.config.copy(prioritizeSpeed = it)) }
        page.section(null, footnote(SettingsCopy.streamingFooter(PanelCopy.fastLinkNote)),
            LabeledRow("Frame rate limit", rate), LabeledRow("Quality", quality), LabeledRow("Resolution", scale))
        page.section(null, footnote(SettingsCopy.SPEED_FOOTER), LabeledRow("Prioritize encoding speed", speed))
        if (model.status().stream?.softwareEncoder == true)
            page.section(null, null, TextRow("This PC’s graphics have no HEVC encoder FFmpeg can use, so streams use the software encoder (x265): fewer frames at Retina resolution. Standard is much lighter to encode.", warning = true))
    }
    override fun update() {
        val c = model.config
        rate.select(c.maxFPS); quality.update(qualities(), c.bitrate); scale.update(listOf("Retina" to 2.0, "Standard" to 1.0), if (c.captureScale >= 1.5) 2.0 else 1.0)
        speed.set(c.prioritizeSpeed)
    }
}
