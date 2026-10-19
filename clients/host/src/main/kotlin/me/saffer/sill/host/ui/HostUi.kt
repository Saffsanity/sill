package me.saffer.sill.host.ui

import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.host.HostConfig
import me.saffer.sill.host.HostGlyph
import me.saffer.sill.host.HostMenu
import me.saffer.sill.host.HostStatusSnapshot
import me.saffer.sill.host.HostStatusText
import me.saffer.sill.host.LoginItemSpec
import me.saffer.sill.host.LoginState
import me.saffer.sill.host.MenuAction
import me.saffer.sill.host.PairedDevice
import me.saffer.sill.host.PairingCopy
import me.saffer.sill.host.StreamHost
import me.saffer.sill.swingui.SillSwing
import java.awt.BorderLayout
import java.awt.Color
import java.awt.Font
import java.awt.Point
import java.awt.RenderingHints
import java.awt.SystemTray
import java.awt.TrayIcon
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.awt.geom.Ellipse2D
import java.awt.geom.Path2D
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage
import java.io.File
import java.util.concurrent.TimeUnit
import javax.swing.AbstractAction
import javax.swing.JCheckBox
import javax.swing.JComponent
import javax.swing.JFrame
import javax.swing.JPanel
import javax.swing.JScrollPane
import javax.swing.JTextArea
import javax.swing.KeyStroke
import javax.swing.SwingUtilities
import javax.swing.Timer

/** What the host's UI reads and does: the running host, or a stand-in for the UI tests. */
interface HostModel {
    val version: String
    val runningFrom: String
    fun status(): HostStatusSnapshot
    val config: HostConfig
    fun setConfig(c: HostConfig)
    fun paired(): List<PairedDevice>
    val requirePairing: Boolean
    fun setRequirePairing(on: Boolean)
    val shareClipboard: Boolean
    fun setShareClipboard(on: Boolean)
    fun removeDevice(fingerprint: String)
    fun openPairing()
    fun cancelPairing()
    fun pairing(): PairingView?
    fun login(): LoginState
    fun setLogin(on: Boolean)
    val logFile: File?
    fun recentLog(): List<String>
    fun showLog()
    fun revealLog()
    fun quit()
    /** Startup's failure, for the card's "Sill Couldn’t Start". */
    val startupError: String? get() = null
}

/**
 * The host's UI, as Sill.app's (StatusItemController, SettingsWindow, PairDeviceWindow, LogWindow):
 * a tray icon whose click opens the status menu (its card, then MenuBuilder's entries) beside it, the
 * Settings window, the pairing window, brought forward when a device asks, and the log. With no
 * system tray (a Linux desktop without one) the menu lives in a window titled "Sill Host" instead,
 * and closing that window quits, as closing the old window did.
 */
class HostUi(private val model: HostModel) {
    val settings = SettingsWindow(model)
    val pair = PairWindow(model)
    val log = LogWindow(model)
    private var tray: TrayIcon? = null
    private var popup: MenuPopup? = null
    private var fallback: JFrame? = null
    private var fallbackMenu: MenuView? = null
    private var glyph: HostGlyph? = null

    fun presentation() = HostStatusText.present(model.status(), model.startupError)
    fun entries() = HostMenu.entries(presentation(), model.config, model.login())

    fun act(a: MenuAction) {
        val c = model.config
        when (a) {
            MenuAction.None, is MenuAction.Choose -> {}
            is MenuAction.SetMaxFPS -> model.setConfig(c.copy(maxFPS = a.fps))
            is MenuAction.SetBitrate -> model.setConfig(c.copy(bitrate = a.bitrate))
            is MenuAction.SetCaptureScale -> model.setConfig(c.copy(captureScale = a.scale))
            MenuAction.ToggleLaunchAtLogin -> model.setLogin(!model.login().on)
            MenuAction.ShowPairing -> { model.openPairing(); pair.refresh(open = true) }
            MenuAction.ShowLog -> log.show()
            MenuAction.ShowSettings -> settings.show()
            MenuAction.Quit -> quit()
        }
        refresh()
    }

    fun start() {
        installTray()
        if (tray == null) showFallback()
        Timer(1000) { refresh() }.start()
        refresh()
    }

    /** The host's state changed (or a second passed): the icon, the open menu, Settings and the pairing window follow. */
    fun refresh() {
        val p = presentation()
        tray?.let { t ->
            if (p.glyph != glyph) { glyph = p.glyph; t.image = trayImage(p.glyph, 32) }
            t.toolTip = p.tooltip
        }
        popup?.takeIf { it.isVisible }?.view?.update(HostMenu.entries(p, model.config, model.login()), p)
        fallbackMenu?.let { m -> m.update(HostMenu.entries(p, model.config, model.login()), p); fallback?.pack() }
        if (settings.frame.isVisible) settings.refresh()
        pair.refresh()
    }

    private fun installTray() {
        if (!SystemTray.isSupported()) return
        try {
            val t = TrayIcon(trayImage(HostGlyph.IDLE, 32), "Sill")
            t.isImageAutoSize = true
            t.addMouseListener(object : MouseAdapter() {
                override fun mouseReleased(e: MouseEvent) = toggleMenu(e.locationOnScreen)
            })
            t.addActionListener { toggleMenu(java.awt.MouseInfo.getPointerInfo()?.location ?: Point(0, 0)) }
            SystemTray.getSystemTray().add(t)
            tray = t
        } catch (_: Exception) { tray = null }
    }

    private var closedAt = 0L

    /** A click opens the menu at the icon; a click while it shows (which first took its focus) leaves it closed. */
    fun toggleMenu(at: Point) {
        if (popup?.isVisible == true) { popup?.closeAll(); return }
        if (System.currentTimeMillis() - closedAt < 250) return
        val p = presentation()
        popup = MenuPopup(HostMenu.entries(p, model.config, model.login()), p, ::act).apply {
            onClosed = { closedAt = System.currentTimeMillis(); if (popup === this) popup = null }
            showAt(at)
        }
    }

    private fun showFallback() {
        val p = presentation()
        val menu = MenuView(HostMenu.entries(p, model.config, model.login()), p, ::act)
        val f = JFrame("Sill Host")
        f.contentPane = object : JComponent() {
            override fun paintComponent(g: java.awt.Graphics) { g.color = HostTheme.c.menu.awt(); g.fillRect(0, 0, width, height) }
        }.apply { layout = BorderLayout(); add(menu, BorderLayout.CENTER) }
        f.iconImage = appIcon(64)
        f.isResizable = false
        f.defaultCloseOperation = JFrame.DISPOSE_ON_CLOSE
        f.addWindowListener(object : WindowAdapter() { override fun windowClosed(e: WindowEvent) = quit() })
        f.pack(); f.setLocationRelativeTo(null); f.isVisible = true
        menu.requestFocusInWindow()
        fallback = f; fallbackMenu = menu
    }

    fun quit() {
        tray?.let { SystemTray.getSystemTray().remove(it) }
        tray = null
        model.quit()
    }

    companion object {
        /**
         * The status item's glyph (StatusGlyph): the window on its sill, filled once a device is
         * connected, with a dot while streaming and the orange sign when the host needs the person.
         * Light on Windows' and GNOME's dark panels.
         */
        fun trayImage(state: HostGlyph, size: Int): BufferedImage {
            val img = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
            val g = img.createGraphics()
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
            g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE)
            val s = size / 32.0
            g.scale(s, s)
            g.color = Color(0xF2, 0xF2, 0xF2)
            g.stroke = java.awt.BasicStroke(2.4f)
            val frame = RoundRectangle2D.Double(5.0, 5.0, 22.0, 15.0, 5.0, 5.0)
            if (state == HostGlyph.IDLE) g.draw(frame) else g.fill(frame)
            g.fill(RoundRectangle2D.Double(3.0, 23.5, 26.0, 3.2, 3.0, 3.0))
            when (state) {
                HostGlyph.STREAMING -> { g.color = Color(0x1E, 0x1E, 0x1E); g.fill(Path2D.Double().apply { moveTo(13.5, 9.0); lineTo(20.0, 12.5); lineTo(13.5, 16.0); closePath() }) }
                HostGlyph.ATTENTION -> {
                    g.color = SillSwing.color(HostTheme.darkColors.orange)
                    g.fill(Path2D.Double().apply { moveTo(24.0, 13.0); lineTo(31.5, 27.0); lineTo(16.5, 27.0); closePath() })
                    g.color = Color(0x1E, 0x1E, 0x1E); g.fillRect(23, 17, 2, 6); g.fill(Ellipse2D.Double(22.9, 23.6, 2.2, 2.2))
                }
                else -> {}
            }
            g.dispose()
            return img
        }

        /** The app's icon (design/AppIcon.svg's idea): a window's frame on a sill, in the icon's greys. */
        fun appIcon(size: Int): BufferedImage {
            val img = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
            val g = img.createGraphics()
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
            g.color = Color(0x2C, 0x2F, 0x36); g.fillRoundRect(0, 0, size, size, size / 4, size / 4)
            g.color = Color(0xE8, 0xEA, 0xED)
            val m = size / 6
            g.fillRoundRect(m, m, size - 2 * m, size * 3 / 5 - m, size / 10, size / 10)
            g.fillRoundRect(m / 2, size * 3 / 4, size - m, size / 10, size / 20, size / 20)
            g.dispose()
            return img
        }
    }
}

/**
 * Sill Log (LogWindow.swift): the host's last lines in a monospaced view, newest at the bottom and
 * followed while the view is at its end; Show per-second stats, Clear and Reveal Log File under it.
 */
class LogWindow(private val model: HostModel) {
    val frame = JFrame("Sill Host Log")
    private val area = JTextArea().apply { isEditable = false; font = MacType.mono; lineWrap = false; margin = java.awt.Insets(6, 6, 6, 6) }
    private val stats = JCheckBox("Show per-second stats")
    private var cleared = 0

    init {
        frame.defaultCloseOperation = JFrame.HIDE_ON_CLOSE
        val bar = JPanel(BorderLayout()).apply {
            border = javax.swing.BorderFactory.createEmptyBorder(8, 12, 10, 12)
            add(stats, BorderLayout.WEST)
            add(JPanel(java.awt.FlowLayout(java.awt.FlowLayout.RIGHT, 8, 0)).apply {
                isOpaque = false
                add(PushButton("Clear") { cleared = model.recentLog().size; reload() })
                add(PushButton("Reveal Log File") { model.revealLog() }.apply { enabledState = model.logFile != null })
            }, BorderLayout.EAST)
        }
        stats.addActionListener { reload() }
        frame.contentPane = JPanel(BorderLayout()).apply { add(JScrollPane(area).apply { border = null }, BorderLayout.CENTER); add(bar, BorderLayout.SOUTH) }
        frame.setSize(900, 520)
        frame.minimumSize = java.awt.Dimension(480, 240)
        frame.rootPane.getInputMap(JComponent.WHEN_IN_FOCUSED_WINDOW).put(KeyStroke.getKeyStroke(KeyEvent.VK_W, KeyEvent.CTRL_DOWN_MASK), "close")
        frame.rootPane.actionMap.put("close", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent?) { frame.isVisible = false } })
        theme()
    }

    private fun theme() {
        val c = HostTheme.c
        area.background = c.window.awt(); area.foreground = c.label.awt(); area.caretColor = c.accent.awt()
        for (comp in listOf(frame.contentPane, stats)) { comp.background = c.window.awt(); comp.foreground = c.label.awt() }
        (frame.contentPane as JPanel).components.forEach { it.background = c.window.awt() }
        stats.font = MacType.font(MacType.body)
    }

    fun reload() {
        val lines = model.recentLog().drop(cleared).filter { stats.isSelected || "[1s]" !in it }
        val atEnd = area.caretPosition >= area.document.length - 1
        area.text = lines.joinToString("\n")
        if (atEnd) area.caretPosition = area.document.length
    }

    /** A new line, while the window shows. */
    fun append(line: String) { if (frame.isVisible && (stats.isSelected || "[1s]" !in line)) { area.append((if (area.document.length > 0) "\n" else "") + line); area.caretPosition = area.document.length } }

    fun show() { reload(); if (!frame.isVisible) frame.setLocationRelativeTo(null); frame.isVisible = true; frame.toFront() }
}

/** Launch at Login on this PC (LoginItemSpec): the Run value or the autostart entry, written only on a click. */
class LoginItem(private val executable: String?) {
    private val windows = System.getProperty("os.name").lowercase().startsWith("windows")
    @Volatile var error: String? = null; private set

    /** Only an installed copy (jpackage's launcher) can start itself; a run from Gradle or a jar cannot. */
    val available get() = executable != null

    fun state() = LoginState(available, available && isOn(), error)

    private fun desktopFile() = File(LoginItemSpec.autostartDir(System.getenv(), System.getProperty("user.home")), LoginItemSpec.DESKTOP_FILE)

    private fun isOn(): Boolean = if (windows) run("reg", "query", LoginItemSpec.RUN_KEY, "/v", LoginItemSpec.RUN_VALUE)?.contains(LoginItemSpec.RUN_VALUE) == true
        else desktopFile().isFile

    fun set(on: Boolean) {
        val exe = executable ?: return
        error = try {
            if (windows) {
                val ok = if (on) run("reg", "add", LoginItemSpec.RUN_KEY, "/v", LoginItemSpec.RUN_VALUE, "/t", "REG_SZ", "/d", LoginItemSpec.windowsCommand(exe), "/f") != null
                    else run("reg", "delete", LoginItemSpec.RUN_KEY, "/v", LoginItemSpec.RUN_VALUE, "/f") != null
                if (ok) null else "Couldn’t change the startup entry"
            } else {
                val f = desktopFile()
                if (on) { f.parentFile.mkdirs(); f.writeText(LoginItemSpec.desktopEntry(exe)) } else f.delete()
                null
            }
        } catch (e: Exception) { "Couldn’t change the startup entry: ${e.message}" }
    }

    private fun run(vararg cmd: String): String? = try {
        val p = ProcessBuilder(*cmd).redirectErrorStream(true).start()
        if (!p.waitFor(5, TimeUnit.SECONDS)) { p.destroyForcibly(); null } else if (p.exitValue() == 0) p.inputStream.readBytes().decodeToString() else null
    } catch (_: Exception) { null }

    companion object {
        /** jpackage's launcher sets jpackage.app-path; that is what a login item starts. */
        fun installedExecutable(): String? = System.getProperty("jpackage.app-path")?.takeIf { File(it).canExecute() }
    }
}

/** [HostModel] over the running host. */
class LiveModel(private val host: StreamHost, private val log: me.saffer.sill.host.HostLog, override val version: String,
                private val login: LoginItem = LoginItem(LoginItem.installedExecutable()), private val exit: () -> Unit) : HostModel {
    override val runningFrom: String = LoginItem.installedExecutable() ?: (runCatching { File(LiveModel::class.java.protectionDomain.codeSource.location.toURI()).parent }.getOrNull() ?: "")
    override fun status() = host.status()
    override val config get() = host.config
    override fun setConfig(c: HostConfig) = host.setConfig(c)
    override fun paired() = host.trust.devices
    override val requirePairing get() = host.trust.requirePairing
    override fun setRequirePairing(on: Boolean) = host.setRequirePairing(on)
    override val shareClipboard get() = host.shareClipboard
    override fun setShareClipboard(on: Boolean) { host.setShareClipboard(on) }
    override fun removeDevice(fingerprint: String) = host.removeDevice(fingerprint)
    override fun openPairing() { host.openPairing() }
    override fun cancelPairing() = host.cancelPairing()
    override fun pairing(): PairingView? {
        val phase = host.pairingPhase() ?: return null
        val w = host.pairing.current
        return PairingView(w?.code ?: "", w?.let(host::pairingLink) ?: "", w?.let { it.expiresAt - System.nanoTime() / 1e9 } ?: 0.0,
            phase, host.pairingAskedBy(), host.pairingAddress())
    }
    override fun login() = login.state()
    override fun setLogin(on: Boolean) = login.set(on)
    override val logFile get() = log.file.takeIf { it.isFile }
    override fun recentLog() = log.recent()
    var onShowLog: () -> Unit = {}
    override fun showLog() = onShowLog()
    override fun revealLog() {
        val dir = log.file.parentFile ?: return
        try { java.awt.Desktop.getDesktop().open(dir) } catch (_: Exception) {}
    }
    override fun quit() = exit()
}
