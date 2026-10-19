package me.saffer.sill.host

import me.saffer.sill.core.Identity
import me.saffer.sill.core.QualityPreset
import me.saffer.sill.host.HostStatusSnapshot.Network
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The host's card, menu and pairing words against Sill.app's rules (StatusText.swift, MenuBuilder, PairDeviceWindow.swift). */
class HostStatusTest {
    private val home = Network.Advertising("DESKTOP-4K2Q")
    private fun dev(name: String?, fps: Int? = null, age: Int? = null, rtt: Int? = null, route: String? = null) =
        HostStatusSnapshot.Device("id-$name", name, "192.168.1.30", fps, age, rtt, route)
    private val window = HostStatusSnapshot.Stream(HostStatusSnapshot.Stream.Kind.WINDOW, "Notepad — notes.txt", 2560, 1440, 60, 15)

    @Test fun headlinesInSillAppsOrder() {
        fun h(s: HostStatusSnapshot, err: String? = null) = HostStatusText.present(s, err).let { it.header to it.subtitle }
        assertEquals("Sill Couldn’t Start" to "Port 7455 is in use.", h(HostStatusSnapshot(home), "Port 7455 is in use."))
        assertEquals("Starting…" to null, h(HostStatusSnapshot(Network.Starting)))
        assertEquals("Not Visible on the Network" to "Bonjour failed. Quit and reopen Sill Host to try again.", h(HostStatusSnapshot(Network.Failed("Bonjour failed"))))
        assertEquals("Not Advertised" to "Not advertised; devices connect to port 7455 by address.", h(HostStatusSnapshot(Network.NotAdvertised(7455))))
        assertEquals("Waiting for a Device" to "Open Sill on your device. This PC appears as “DESKTOP-4K2Q”.", h(HostStatusSnapshot(home)))
        assertEquals("iPad Connected" to "Pick a window on the device to start streaming.", h(HostStatusSnapshot(home, listOf(dev("iPad (iPad14,1)")))))
        assertEquals("Device Connected" to "Pick a window on the device to start streaming.", h(HostStatusSnapshot(home, listOf(dev(null)))))
        assertEquals("2 Devices Connected" to "Pick a window on the device to start streaming.", h(HostStatusSnapshot(home, listOf(dev("iPad"), dev("Pixel 9")))))
        assertEquals("Streaming to iPad" to null, h(HostStatusSnapshot(home, listOf(dev("iPad (iPad14,1)")), window)))
        assertEquals("Streaming to a Device" to null, h(HostStatusSnapshot(home, listOf(dev(null)), window)))
        assertEquals("Streaming to 2 Devices" to null, h(HostStatusSnapshot(home, listOf(dev("a"), dev("b")), window)))
        assertEquals("Sill — Waiting for a Device", HostStatusText.present(HostStatusSnapshot(home)).tooltip)
    }

    @Test fun glyphs() {
        fun g(s: HostStatusSnapshot, err: String? = null) = HostStatusText.present(s, err).glyph
        assertEquals(HostGlyph.IDLE, g(HostStatusSnapshot(home)))
        assertEquals(HostGlyph.CONNECTED, g(HostStatusSnapshot(home, listOf(dev("iPad")))))
        assertEquals(HostGlyph.STREAMING, g(HostStatusSnapshot(home, listOf(dev("iPad")), window)))
        assertEquals(HostGlyph.ATTENTION, g(HostStatusSnapshot(Network.Failed("x"))))
        assertEquals(HostGlyph.ATTENTION, g(HostStatusSnapshot(home), "x"))
        assertEquals(HostGlyph.ATTENTION, g(HostStatusSnapshot(home, pairingRequest = HostStatusSnapshot.PairingRequest("iPad (iPad14,1)"))))
    }

    @Test fun sourceAndDeviceRows() {
        val one = HostStatusText.present(HostStatusSnapshot(home, listOf(dev("iPad (iPad14,1)", 58, 9, 7, "Wi-Fi")), window, encodedFps = 58))
        assertEquals(HostPresentation.Row("source", RowSymbol.WINDOW, "Notepad — notes.txt", "2560×1440 · 58 of 60 fps · 15 Mbps · Wi\u2011Fi"), one.source)
        assertEquals("58 fps · frame age 9 ms · RTT 7 ms · Wi\u2011Fi", one.devices[0].detail)
        assertEquals(RowSymbol.TABLET, one.devices[0].symbol)
        // Still, clamped, two devices (no route on the source row), software encoder, the Desktop.
        assertEquals("2560×1440 · 60 fps, still · 15 Mbps", HostStatusText.present(HostStatusSnapshot(home, listOf(dev("a")), window)).source!!.detail)
        assertEquals("2560×1440 · 60 of 60 fps · 15 Mbps", HostStatusText.present(HostStatusSnapshot(home, listOf(dev("a", route = "Wired"), dev("b")), window, 61)).source!!.detail)
        val desk = HostStatusText.present(HostStatusSnapshot(home, listOf(dev("a"), dev("b")), window.copy(kind = HostStatusSnapshot.Stream.Kind.DESKTOP, softwareEncoder = true), 30)).source!!
        assertEquals("Whole Desktop", desk.title); assertEquals(RowSymbol.DESKTOP, desk.symbol)
        assertEquals("2560×1440 · 30 of 60 fps · 15 Mbps · software encoder", desk.detail)
        // A long title is cut in the middle at 44, as StatusText.middleTruncated.
        val long = "Visual Studio Code — a very long window title that goes on and on"
        assertEquals("Visual Studio Code — a…e that goes on and on", HostStatusText.present(HostStatusSnapshot(home, listOf(dev("a")), window.copy(title = long))).source!!.title)
        assertEquals(44, HostStatusText.middleTruncated(long, 44).length)
        // No stats yet: the address and no detail; a second without a sample reads "–".
        val early = HostStatusText.present(HostStatusSnapshot(home, listOf(dev(null)))).devices[0]
        assertEquals("192.168.1.30", early.title); assertNull(early.detail)
        assertEquals("0 fps · frame age – · RTT 12 ms", HostStatusText.present(HostStatusSnapshot(home, listOf(dev("iPhone", 0, -1, 12)))).devices[0].detail)
        assertEquals(RowSymbol.PHONE, HostStatusText.symbolFor("iPhone (iPhone16,1)"))
        assertEquals(RowSymbol.PHONE, HostStatusText.symbolFor("Pixel 9 Pro"))
        assertEquals(RowSymbol.COMPUTER, HostStatusText.symbolFor("Windows PC"))
        assertEquals("iPad", HostStatusText.shortName("iPad (iPad14,1)"))
        assertEquals("(odd)", HostStatusText.shortName("(odd)"))
    }

    @Test fun pairingRequestIsAttention() {
        val p = HostStatusText.present(HostStatusSnapshot(home, pairingRequest = HostStatusSnapshot.PairingRequest("iPad (iPad14,1)")))
        assertEquals(listOf(HostPresentation.Attention("iPad Wants to Pair", "A code is showing.", MenuAction.ShowPairing)), p.attention)
        val menu = HostMenu.entries(p, HostConfig(), LoginState(true, false))
        assertEquals(MenuEntry.Kind.CARD, menu[0].kind)
        assertTrue(menu[1].attention && menu[1].title == "iPad Wants to Pair")
    }

    @Test fun menuOrderIsMenuBuilders() {
        val p = HostStatusText.present(HostStatusSnapshot(home))
        val menu = HostMenu.entries(p, HostConfig(maxFPS = 120, bitrate = 12_000_000, captureScale = 1.0), LoginState(true, true))
        assertEquals(listOf("Waiting for a Device", "-", "Frame Rate", "Quality", "Resolution", "-", "Launch at Login", "-", "Pair a Device…", "Show Log…", "Settings…", "-", "Quit Sill Host"),
            menu.map { if (it.kind == MenuEntry.Kind.SEPARATOR) "-" else it.title })
        assertEquals(listOf("Up to 60 fps" to false, "Up to 120 fps" to true), menu[2].children.map { it.title to it.checked })
        assertEquals(QualityPreset.entries.map { it.title } + "Custom — 12 Mbps", menu[3].children.map { it.title })
        assertTrue(menu[3].children.last().let { it.checked && !it.enabled })
        assertEquals("Per 60 fps; a 120 fps stream gets twice as much", menu[3].subtitle)
        assertEquals(listOf("Retina" to false, "Standard" to true), menu[4].children.map { it.title to it.checked })
        assertEquals("A quarter of the pixels; much lighter to encode", menu[4].children[1].subtitle)
        assertTrue(menu[6].checked)
        assertEquals("Ctrl+,", menu[10].shortcut); assertEquals("Ctrl+Q", menu[12].shortcut)
        val off = HostMenu.entries(p, HostConfig(), LoginState(false, false))
        assertEquals("Available when Sill Host runs from its installed copy", off[6].subtitle)
        assertTrue(!off[6].enabled)
        assertTrue(off[3].children.first { it.title == "Balanced" }.checked)
    }

    @Test fun pairingWords() {
        assertEquals("iPad (iPad14,1) on this network asked to pair.", PairingCopy.askedLine("iPad (iPad14,1)", null))
        assertEquals("A device on this network asked to pair.", PairingCopy.askedLine(null, null))
        assertEquals("Works once, for the next 4:59.", PairingCopy.countdown(298.2))
        assertEquals("Works once, for the next 0:00.", PairingCopy.countdown(-3.0))
        assertEquals("1234 5678 9012", PairingCopy.grouped("123456789012"))
        assertEquals("A wrong code came from 10.0.0.4. 1 try left.", PairingCopy.wrongCode("10.0.0.4", 1))
        assertEquals("A wrong code came from 10.0.0.4. 3 tries left.", PairingCopy.wrongCode("10.0.0.4", 3))
        assertEquals("Paired with iPad.", PairingCopy.ended(PairingCopy.Phase.Paired("iPad")))
        assertEquals("Pairing stopped after 5 wrong codes.", PairingCopy.ended(PairingCopy.Phase.Stopped))
        assertEquals("This code expired.", PairingCopy.ended(PairingCopy.Phase.Expired))
        assertEquals("This code no longer works.", PairingCopy.ended(PairingCopy.Phase.Closed))
        assertEquals(listOf("Cancel", "New Code"), PairingCopy.buttons(PairingCopy.Phase.Expired))
        assertEquals(listOf("Done"), PairingCopy.buttons(PairingCopy.Phase.Paired("x")))
        assertEquals(listOf("Cancel"), PairingCopy.buttons(PairingCopy.Phase.Waiting(5, null)))
        assertEquals(PairingCopy.Address("100.101.102.103", "192.168.1.20"), PairingCopy.address(listOf("192.168.1.20"), listOf("100.101.102.103"), 7455))
        assertEquals(PairingCopy.Address("192.168.1.20:5000", "10.8.0.6:5000"), PairingCopy.address(listOf("192.168.1.20"), listOf("10.8.0.6"), 5000))
        assertEquals(PairingCopy.Address("192.168.1.20", null), PairingCopy.address(listOf("192.168.1.20"), emptyList(), 7455))
        assertNull(PairingCopy.address(emptyList(), emptyList(), 7455))
        assertTrue(PairingCopy.isTailscale("100.127.0.1")); assertTrue(!PairingCopy.isTailscale("100.128.0.1"))
    }

    @Test fun pairingWindowRemembersHowItEnded() {
        val t = doubleArrayOf(0.0)
        val w = PairingWindow(Identity.generate().fingerprint, { t[0] })
        val dev = Identity.generate().fingerprint
        w.open(); assertNull(w.lastEnd); assertEquals(5, w.triesLeft)
        w.check("qr", "AAAA", dev, "10.0.0.4")
        assertEquals("10.0.0.4", w.wrongFrom); assertEquals(4, w.triesLeft)
        w.close(); assertEquals(PairingWindow.End.CLOSED, w.lastEnd)
        w.open(); assertNull(w.lastEnd); assertNull(w.wrongFrom)
        t[0] = 301.0; assertNull(w.current); assertEquals(PairingWindow.End.EXPIRED, w.lastEnd)
        w.open()
        for (i in 0 until 5) { t[0] += 20; w.check("qr", "AAAA", dev, "10.0.0.$i") }
        assertEquals(PairingWindow.End.STOPPED, w.lastEnd)
    }

    @Test fun settingsWords() {
        val d = PairedDevice("fp", "iPad", "iPad14,1", "code", pairedAt = 1_791_000_000.0, lastConnectedAt = 1_791_000_000.0 + 3600)
        val zone = java.time.ZoneOffset.UTC
        assertEquals("Paired Oct 3 with the code · last connected 2 hours ago", SettingsCopy.pairedDetail(d, 1_791_000_000.0 + 3 * 3600, zone))
        assertEquals("Paired Oct 3, 2026 with the QR code", SettingsCopy.pairedDetail(d.copy(method = "qr", lastConnectedAt = null), 1_830_000_000.0, zone))
        assertEquals("just now", SettingsCopy.relative(10.0)); assertEquals("1 minute ago", SettingsCopy.relative(61.0))
        assertEquals("yesterday", SettingsCopy.relative(90_000.0)); assertEquals("3 days ago", SettingsCopy.relative(3 * 86_400.0))
        assertTrue(SettingsCopy.streamingFooter("X.").contains("a 120 fps stream gets twice as much. X. Changes apply at once"))
    }

    @Test fun loginItem() {
        assertEquals("/home/a/.config/autostart", LoginItemSpec.autostartDir(emptyMap(), "/home/a"))
        assertEquals("/x/autostart", LoginItemSpec.autostartDir(mapOf("XDG_CONFIG_HOME" to "/x"), "/home/a"))
        assertEquals("/home/a/.config/autostart", LoginItemSpec.autostartDir(mapOf("XDG_CONFIG_HOME" to "rel"), "/home/a"))
        assertTrue(LoginItemSpec.desktopEntry("/opt/sillhost/bin/SillHost").contains("\nExec=/opt/sillhost/bin/SillHost\n"))
        assertTrue(LoginItemSpec.desktopEntry("/opt/Sill Host/bin/SillHost").contains("\nExec=\"/opt/Sill Host/bin/SillHost\"\n"))
        assertEquals("\"C:\\Program Files\\SillHost\\SillHost.exe\"", LoginItemSpec.windowsCommand("C:\\Program Files\\SillHost\\SillHost.exe"))
    }
}
