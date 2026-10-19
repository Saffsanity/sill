package me.saffer.sill.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** A row's word as DiscoveryPolicy.rowWord gives it on iOS: a saved Mac's way in, else "Not paired". */
class RowWordTest {
    private val nb = "Wi‑Fi"

    @Test
    fun theWayInFromTheInterfacesName() {
        // Linux and Android name their interfaces; Windows gives the adapter's description.
        for (n in listOf("wlan0", "wlp2s0", "Intel(R) Wi-Fi 6 AX201 160MHz", "Qualcomm Atheros QCA9377 Wireless Network Adapter", "Wi-Fi"))
            assertEquals(HomeDial.Method.WiFi, HomeDial.Method.of(n), n)
        for (n in listOf("eth0", "enp3s0", "en7", "Realtek PCIe GbE Family Controller", "Intel(R) Ethernet Connection I219-V", "ASIX AX88179 USB 3.0 to Gigabit Ethernet Adapter"))
            assertEquals(HomeDial.Method.Wired, HomeDial.Method.of(n), n)
        for (n in listOf("p2p-wlan0-0", "awdl0"))
            assertEquals(HomeDial.Method.Direct, HomeDial.Method.of(n), n)
        // A tunnel, a VPN or a hypervisor's switch says nothing about the link, as on iOS.
        for (n in listOf("lo", "tun0", "utun3", "tailscale0", "WireGuard Tunnel", "vEthernet (Default Switch)", "Hyper-V Virtual Ethernet Adapter", "docker0", "veth12ab", null))
            assertNull(HomeDial.Method.of(n), "$n")
    }

    @Test
    fun theRowsWords() {
        val saved = SavedMac(macID = "M", name = "Studio", fingerprint = Base64Url.encode(ByteArray(32)), recognitionKey = Base64Url.encode(ByteArray(32)), pairedAt = 0.0, method = "code")
        assertEquals(nb, HomeDial.rowWord(HomeDial.Decision.Pinned(saved), "wlan0"))
        assertEquals("Wired", HomeDial.rowWord(HomeDial.Decision.Pinned(saved), "eth0"))
        assertNull(HomeDial.rowWord(HomeDial.Decision.Pinned(saved), "lo"))
        assertEquals("Not paired", HomeDial.rowWord(HomeDial.Decision.AnyKey, "wlan0"))
        assertEquals("Not paired", HomeDial.rowWord(HomeDial.Decision.Ask(null), "eth0"))
        assertEquals("Update Sill", HomeDial.rowWord(HomeDial.Decision.UpdateSill))
    }
}
