package me.saffer.sill.host

import me.saffer.sill.core.Dns
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.nio.ByteBuffer

/**
 * Advertises the host's home door as Bonjour does for the Mac (`_sill._tcp`, the instance named
 * after the computer, TXT `r` the recognition tag and `p` how the door speaks), with its own
 * multicast DNS responder (RFC 6762, RFC 6763): it answers PTR, SRV, TXT, A and AAAA questions for
 * its names, one-shot queries (from a port other than 5353) by unicast with the query's ID as
 * RFC 6762 §6.7 asks, others on the group; announces itself twice at start and whenever its TXT
 * changes; says goodbye (TTL 0) at stop. Port 5353 is shared with the system's own responder
 * (Windows' DNS Client, Avahi) through SO_REUSEADDR.
 *
 * Names: the instance is the computer's name; the SRV target is a name of its own
 * (`sill-<id>.local.`), so it never answers for the computer's own host name.
 */
class MdnsResponder(
    instanceName: String,
    targetLabel: String,
    @Volatile var port: Int,
    @Volatile private var txt: Map<String, String?>,
    private val serviceType: String = "_sill._tcp.local.",
    private val log: (String) -> Unit = {},
    /** The addresses answered for the target; by default every non-loopback address of the machine. */
    private val addresses: () -> List<InetAddress> = ::machineAddresses,
) : AutoCloseable {
    val instance: String = Dns.splitName(serviceType).let { "${escape(instanceName.take(60))}.$serviceType" }
    val target: String = "${targetLabel.lowercase().filter { it.isLetterOrDigit() || it == '-' }.take(50)}.local."
    private val sockets = ArrayList<Pair<MulticastSocket, InetSocketAddress>>()
    @Volatile private var running = false

    fun start(): Boolean {
        running = true
        for (ni in NetworkInterface.getNetworkInterfaces().toList()) {
            try {
                if (!ni.isUp || !ni.supportsMulticast() || ni.isLoopback || ni.isPointToPoint) continue
                if (ni.inetAddresses.toList().any { it is Inet4Address }) open(ni, InetAddress.getByName("224.0.0.251"))
                if (ni.inetAddresses.toList().any { it is Inet6Address && it.isLinkLocalAddress })
                    open(ni, Inet6Address.getByAddress(null, byteArrayOf(0xff.toByte(), 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xfb.toByte()), ni))
            } catch (e: Exception) { log("mDNS: ${ni.name}: ${e.message}") }
        }
        if (sockets.isEmpty()) { log("mDNS: no interface takes multicast; devices find this host by address only"); return false }
        Thread({ announce(); Thread.sleep(1000); announce() }, "sill-mdns-announce").apply { isDaemon = true }.start()
        return true
    }

    private fun open(ni: NetworkInterface, group: InetAddress) {
        val s = MulticastSocket(null as java.net.SocketAddress?)
        s.reuseAddress = true
        s.bind(InetSocketAddress(if (group is Inet6Address) InetAddress.getByName("::") else InetAddress.getByName("0.0.0.0"), 5353))
        s.networkInterface = ni
        s.joinGroup(InetSocketAddress(group, 5353), ni)
        s.timeToLive = 255
        s.soTimeout = 1000
        val g = InetSocketAddress(group, 5353)
        synchronized(sockets) { sockets.add(s to g) }
        Thread({
            val buf = ByteArray(9000)
            while (running && !s.isClosed) {
                val p = DatagramPacket(buf, buf.size)
                try { s.receive(p) } catch (_: SocketTimeoutException) { continue } catch (_: Exception) { break }
                val reply = try { answer(buf.copyOf(p.length), p.port) } catch (_: Exception) { null } ?: continue
                val (bytes, unicast) = reply
                try { s.send(DatagramPacket(bytes, bytes.size, if (unicast) p.socketAddress else g)) } catch (_: Exception) {}
            }
        }, "sill-mdns-${ni.name}").apply { isDaemon = true }.start()
    }

    fun updateTxt(t: Map<String, String?>) { txt = t; if (running) announce() }

    private fun announce() {
        val r = response(id = 0, questions = emptyList(), ttl = TTL, all = true)
        synchronized(sockets) { for ((s, g) in sockets) try { s.send(DatagramPacket(r, r.size, g)) } catch (_: Exception) {} }
    }

    override fun close() {
        if (!running) return
        val bye = response(id = 0, questions = emptyList(), ttl = 0, all = true)
        synchronized(sockets) {
            for ((s, g) in sockets) try { s.send(DatagramPacket(bye, bye.size, g)) } catch (_: Exception) {}
            running = false
            sockets.forEach { it.first.close() }; sockets.clear()
        }
    }

    /**
     * The response to one packet, and whether it goes by unicast; null when it asks nothing of ours.
     * Public for tests.
     */
    fun answer(packet: ByteArray, sourcePort: Int): Pair<ByteArray, Boolean>? {
        if (packet.size < 12) return null
        val b = ByteBuffer.wrap(packet)
        val id = b.short.toInt() and 0xFFFF
        val flags = b.short.toInt() and 0xFFFF
        if (flags and 0x8000 != 0) return null                       // a response, not a query
        val qd = b.short.toInt() and 0xFFFF
        var off = 12
        val asked = ArrayList<Triple<String, Int, Boolean>>()        // name, type, unicast-response bit
        repeat(qd) {
            val (name, after) = Dns.readName(packet, off)
            val type = ((packet[after].toInt() and 0xFF) shl 8) or (packet[after + 1].toInt() and 0xFF)
            val cls = ((packet[after + 2].toInt() and 0xFF) shl 8) or (packet[after + 3].toInt() and 0xFF)
            asked.add(Triple(name, type, cls and Dns.QU != 0))
            off = after + 4
        }
        val ours = asked.filter { (n, t, _) -> matches(n, t) }
        if (ours.isEmpty()) return null
        val legacy = sourcePort != 5353
        val unicast = legacy || ours.all { it.third }
        // A one-shot query gets its question back, its ID, and TTLs of at most 10 s (RFC 6762 §6.7).
        val r = response(if (legacy) id else 0, if (legacy) ours.map { it.first to it.second } else emptyList(),
            if (legacy) minOf(TTL, 10) else TTL, all = false, questions2 = ours.map { it.first to it.second })
        return r to unicast
    }

    private fun matches(name: String, type: Int): Boolean {
        val n = name.lowercase()
        return when {
            n == serviceType.lowercase() -> type == Dns.PTR || type == Dns.ANY
            n == "_services._dns-sd._udp.local." -> type == Dns.PTR || type == Dns.ANY
            n == instance.lowercase() -> type == Dns.SRV || type == Dns.TXT || type == Dns.ANY
            n == target.lowercase() -> type == Dns.A || type == Dns.AAAA || type == Dns.ANY
            else -> false
        }
    }

    /** A response: the answers to `questions2` (or every record), with SRV, TXT and addresses as additionals. */
    private fun response(id: Int, questions: List<Pair<String, Int>>, ttl: Int, all: Boolean, questions2: List<Pair<String, Int>> = emptyList()): ByteArray {
        val answers = ArrayList<ByteArray>()
        val additional = ArrayList<ByteArray>()
        val addrs = addresses()
        fun ptr() = record(serviceType, Dns.PTR, ttl, false, Dns.encodeName(instance))
        fun srv() = record(instance, Dns.SRV, ttl, true, ByteBuffer.allocate(6).putShort(0).putShort(0).putShort(port.toShort()).array() + Dns.encodeName(target))
        fun txtRecord() = record(instance, Dns.TXT, ttl, true, Dns.encodeTxt(txt))
        fun addr(a: InetAddress) = record(target, if (a is Inet4Address) Dns.A else Dns.AAAA, ttl, true, a.address)
        if (all) {
            answers += ptr(); answers += srv(); answers += txtRecord(); addrs.forEach { answers += addr(it) }
        } else {
            for ((name, type) in questions2) {
                val n = name.lowercase()
                when {
                    n == "_services._dns-sd._udp.local." -> answers += record("_services._dns-sd._udp.local.", Dns.PTR, ttl, false, Dns.encodeName(serviceType))
                    n == serviceType.lowercase() -> { answers += ptr(); additional += srv(); additional += txtRecord(); addrs.forEach { additional += addr(it) } }
                    n == instance.lowercase() -> {
                        if (type == Dns.SRV || type == Dns.ANY) answers += srv()
                        if (type == Dns.TXT || type == Dns.ANY) answers += txtRecord()
                        addrs.forEach { additional += addr(it) }
                    }
                    n == target.lowercase() -> addrs.filter {
                        type == Dns.ANY || (type == Dns.A && it is Inet4Address) || (type == Dns.AAAA && it is Inet6Address)
                    }.forEach { answers += addr(it) }
                }
            }
        }
        val o = ByteArrayOutputStream()
        o.write(ByteBuffer.allocate(12).putShort(id.toShort()).putShort(0x8400.toShort()).putShort(questions.size.toShort())
            .putShort(answers.size.toShort()).putShort(0).putShort(additional.size.toShort()).array())
        for ((name, type) in questions) { o.write(Dns.encodeName(name)); o.write(type ushr 8); o.write(type and 0xFF); o.write(0); o.write(1) }
        answers.forEach(o::write); additional.forEach(o::write)
        return o.toByteArray()
    }

    private fun record(name: String, type: Int, ttl: Int, unique: Boolean, data: ByteArray): ByteArray {
        val o = ByteArrayOutputStream()
        o.write(Dns.encodeName(name))
        val cls = Dns.IN or if (unique) 0x8000 else 0               // the cache-flush bit on records only this host owns
        o.write(ByteBuffer.allocate(10).putShort(type.toShort()).putShort(cls.toShort()).putInt(ttl).putShort(data.size.toShort()).array())
        o.write(data)
        return o.toByteArray()
    }

    companion object {
        const val TTL = 120

        private fun escape(label: String) = label.replace("\\", "\\\\").replace(".", "\\.")

        fun machineAddresses(): List<InetAddress> = NetworkInterface.getNetworkInterfaces().toList()
            .filter { try { it.isUp && !it.isLoopback && !it.isPointToPoint } catch (_: Exception) { false } }
            .flatMap { ni -> ni.inetAddresses.toList().map { a -> if (a is Inet6Address && a.isLinkLocalAddress) Inet6Address.getByAddress(null, a.address, ni) else a } }
            .filter { it is Inet4Address || (it as Inet6Address).isLinkLocalAddress || !it.isSiteLocalAddress }
            .sortedBy { if (it is Inet4Address) 0 else 1 }
    }
}
