package me.saffer.sill.core

/**
 * How a session's end reads and whether to reconnect (iOSClient/GoodbyePolicy.swift): today's reasons
 * keep their own words; "update" and any reason this build does not know are notices, shown in the
 * Mac's words (SafeText, 300 characters), with a reconnect only when the Mac asks for one.
 */
object GoodbyePolicy {
    const val MESSAGE_LIMIT = 300

    data class Outcome(val text: String, val reconnect: Boolean, val remoteAllowed: Boolean, val isNotice: Boolean, val offerUpdate: Boolean = false)

    /** `goodbye` null: the connection ended without one. */
    fun outcome(goodbye: Goodbye?, mac: String, device: String, saved: Boolean): Outcome {
        val g = goodbye ?: return Outcome(
            if (saved) "$mac disconnected. Sill will reconnect when it can reach it." else "$mac disconnected. It will reconnect when the Mac is back.",
            reconnect = true, remoteAllowed = saved, isNotice = false)
        return when (g.reason) {
            Goodbye.QUIT -> Outcome("$mac quit Sill. This $device reconnects when it’s back.", true, saved, false)
            Goodbye.REMOVED -> Outcome("$mac removed this $device. To use it again, pair it again.", false, false, false)
            Goodbye.REMOTE_OFF -> Outcome("$mac turned off Remote Access.", true, false, false)
            Goodbye.INTERNET_OFF -> Outcome("$mac stopped accepting connections from the internet. Connect through your VPN.", true, false, false)
            Goodbye.BUSY -> Outcome("$mac is already serving 8 devices.", true, saved, false)
            Goodbye.PAIRING_REQUIRED -> Outcome("$mac now asks devices to pair. Tap it to pair this $device.", false, false, false)
            Goodbye.UPDATE -> {
                var own = "Update Sill on this $device to keep using $mac."
                g.minimumVersion?.let(SillVersion::parse)?.let { own += " It needs version $it or later." }
                Outcome(words(g, own), g.reconnect == true, saved, true, offerUpdate = true)
            }
            else -> {
                val reconnect = g.reconnect == true
                val own = if (reconnect) "$mac closed the connection. Sill will reconnect when it can." else "$mac closed the connection. Tap it to try again."
                Outcome(words(g, own), reconnect, saved, true)
            }
        }
    }

    private fun words(g: Goodbye, own: String) = SafeText.label(g.message ?: "", MESSAGE_LIMIT).ifEmpty { own }
}

/**
 * How a client dials a Mac it sees on the network (DiscoveryPolicy.homeDial), from the row's TXT
 * record and what this client saved.
 */
object HomeDial {
    sealed class Decision {
        /** A saved Mac: a session pinned to its key. */
        data class Pinned(val mac: SavedMac) : Decision()
        /** An open door (Require pairing off): a session that takes any P-256 key, pinned for the rest of the session. */
        object AnyKey : Decision()
        /** Not paired (or removed, or set up again): a tap asks the Mac to show its code. */
        data class Ask(val pin: ByteArray?) : Decision()
        /** A plain door: only a development build dials it; a release says to update Sill on the Mac. */
        object Plain : Decision()
        object UpdateSill : Decision()
    }

    fun decide(door: HomeDoorTxt.Door, saved: SavedMac?, allowPlain: Boolean): Decision = when (door) {
        HomeDoorTxt.Door.PLAIN -> if (allowPlain) Decision.Plain else Decision.UpdateSill
        else -> when {
            saved != null && saved.newKey -> Decision.Ask(null)
            saved != null && saved.revoked -> Decision.Ask(saved.fingerprintBytes)
            saved != null -> Decision.Pinned(saved)
            door == HomeDoorTxt.Door.OPEN -> Decision.AnyKey
            else -> Decision.Ask(null)
        }
    }

    /**
     * Where this device sees its Mac (DiscoveryPolicy.Method): the cable, Wi-Fi or peer-to-peer
     * Wi-Fi, read from the name of the interface mDNS answered on, since the JDK says no more than
     * that (Linux and Android's "wlan0", "eth0"; Windows' adapter description, "Intel(R) Wi-Fi 6
     * AX201", "Realtek PCIe GbE Family Controller"). A virtual or tunnel interface (a VPN, a
     * hypervisor's switch, loopback) has no word, as an interface of no known kind has none on iOS.
     */
    enum class Method(val word: String) {
        Wired("Wired"), WiFi("Wi\u2011Fi"), Direct("Direct");

        companion object {
            fun of(interfaceName: String?): Method? {
                val n = interfaceName?.lowercase() ?: return null
                fun has(vararg s: String) = s.any { it in n }
                return when {
                    has("loopback", "virtual", "vpn", "tunnel", "tailscale", "wireguard", "zerotier", "hyper-v", "vethernet", "vmware", "virtualbox") ||
                        n == "lo" || n.startsWith("tun") || n.startsWith("tap") || n.startsWith("utun") || n.startsWith("docker") || n.startsWith("veth") || n.startsWith("br-") -> null
                    has("awdl", "llw", "wi-fi direct", "wifi direct") || n.startsWith("p2p") -> Direct
                    has("wi-fi", "wifi", "wireless", "wlan", "802.11") || n.startsWith("wl") -> WiFi
                    has("ethernet", "gbe", "gigabit", "usb", "rndis") || n.startsWith("eth") || n.startsWith("en") -> Wired
                    else -> null
                }
            }
        }
    }

    /**
     * The word a row ends in (DiscoveryPolicy.rowWord): a saved Mac's way in (Wired, Wi-Fi, Direct,
     * or nothing), "Not paired" for a Mac this device has not paired with, an open door's included
     * (the review fix of 2026-09-27 on iOS), and the plain door's words.
     */
    fun rowWord(d: Decision, interfaceName: String? = null): String? = when (d) {
        is Decision.Pinned -> Method.of(interfaceName)?.word
        Decision.AnyKey -> "Not paired"
        is Decision.Ask -> "Not paired"
        Decision.Plain -> "Development"
        Decision.UpdateSill -> "Update Sill"
    }
}

/**
 * The automatic reconnect's dials of a Mac it still sees (DiscoveryPolicy.redialRow): the first at
 * once, then 5, 10, 20 and every 30 s after the last started, 12 at most; and the line it shows.
 */
object Redial {
    val RETRY = doubleArrayOf(5.0, 10.0, 20.0, 30.0)
    const val QUIET_AFTER = 3
    const val DIALS = 12

    /** Whether to dial now after `failed` dials that did not connect, the last started at `lastDialAt`; else when to look again. */
    fun next(failed: Int, lastDialAt: Double?, now: Double): Pair<Boolean, Double?> {
        if (failed >= DIALS) return false to null
        if (failed == 0 || lastDialAt == null) return true to null
        val due = lastDialAt + RETRY[minOf(failed, RETRY.size) - 1]
        return if (now >= due) true to null else false to due
    }

    fun line(mac: String, failed: Int) = when {
        failed >= DIALS -> "Stopped trying to reach $mac. Tap it to try again."
        failed >= QUIET_AFTER -> "$mac isn’t answering. It may be asleep. Sill keeps trying, or tap it to try now."
        else -> "Reconnecting to $mac…"
    }
}
