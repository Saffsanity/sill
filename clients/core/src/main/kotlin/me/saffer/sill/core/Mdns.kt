package me.saffer.sill.core

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
 * One Mac found on the network: its Bonjour instance name, where its home door listens, and its TXT
 * record (`r`, the recognition tag; `p`, how the door speaks).
 */
data class FoundService(
    val name: String,
    val host: String,
    val port: Int,
    val addresses: List<InetAddress>,
    val txt: Map<String, String?>,
    /** The interface it answered on ("eth0", "Wi-Fi"), for logs and the row's word. */
    val interfaceName: String?,
) {
    val tag: String? get() = txt.entries.firstOrNull { it.key.equals(RecognitionTag.TXT_KEY, true) }?.value
    val door: HomeDoorTxt.Door get() = HomeDoorTxt.door(txt)
}

/**
 * Just enough DNS (RFC 1035, RFC 6762, RFC 6763) for browsing one service type: queries, and the
 * PTR, SRV, TXT, A and AAAA answers to them, with name compression.
 */
object Dns {
    const val A = 1; const val PTR = 12; const val TXT = 16; const val AAAA = 28; const val SRV = 33; const val ANY = 255
    const val IN = 1
    const val QU = 0x8000

    class Record(val name: String, val type: Int, val ttl: Long, val data: Any?)

    /** A query for each (name, type), with the unicast-response bit. */
    fun query(questions: List<Pair<String, Int>>, id: Int = 0): ByteArray {
        val o = ByteArrayOutputStream()
        val b = ByteBuffer.allocate(12).putShort(id.toShort()).putShort(0).putShort(questions.size.toShort()).putShort(0).putShort(0).putShort(0)
        o.write(b.array())
        for ((name, type) in questions) {
            o.write(encodeName(name))
            o.write(type ushr 8); o.write(type and 0xFF)
            o.write((IN or QU) ushr 8); o.write(IN and 0xFF)
        }
        return o.toByteArray()
    }

    fun encodeName(name: String): ByteArray {
        val o = ByteArrayOutputStream()
        for (label in splitName(name)) {
            val b = label.encodeToByteArray()
            require(b.size in 1..63) { "label '$label'" }
            o.write(b.size); o.write(b)
        }
        o.write(0)
        return o.toByteArray()
    }

    /** Labels of a dotted name, where "\." is a dot inside a label (an instance name can hold one). */
    fun splitName(name: String): List<String> {
        val labels = ArrayList<String>()
        val cur = StringBuilder()
        var i = 0
        while (i < name.length) {
            val c = name[i]
            if (c == '\\' && i + 1 < name.length) { cur.append(name[i + 1]); i += 2; continue }
            if (c == '.') { if (cur.isNotEmpty()) labels.add(cur.toString()); cur.clear() } else cur.append(c)
            i++
        }
        if (cur.isNotEmpty()) labels.add(cur.toString())
        return labels
    }

    private fun escapeLabel(l: String) = l.replace("\\", "\\\\").replace(".", "\\.")

    /** Every answer, authority and additional record of a response; null for a query or a malformed packet. */
    fun parseResponse(p: ByteArray): List<Record>? {
        if (p.size < 12) return null
        val b = ByteBuffer.wrap(p)
        b.short
        val flags = b.short.toInt() and 0xFFFF
        if (flags and 0x8000 == 0) return null            // a query, not a response
        val qd = b.short.toInt() and 0xFFFF
        val count = (b.short.toInt() and 0xFFFF) + (b.short.toInt() and 0xFFFF) + (b.short.toInt() and 0xFFFF)
        var off = 12
        try {
            repeat(qd) { off = readName(p, off).second + 4 }
            val out = ArrayList<Record>()
            repeat(count) {
                val (name, after) = readName(p, off)
                val rb = ByteBuffer.wrap(p, after, 10)
                val type = rb.short.toInt() and 0xFFFF
                rb.short                                       // class, with the cache-flush bit
                val ttl = rb.int.toLong() and 0xFFFFFFFFL
                val len = rb.short.toInt() and 0xFFFF
                val start = after + 10
                if (start + len > p.size) return null
                val data: Any? = when (type) {
                    PTR -> readName(p, start).first
                    SRV -> {
                        val sb = ByteBuffer.wrap(p, start, len)
                        sb.short; sb.short
                        val port = sb.short.toInt() and 0xFFFF
                        port to readName(p, start + 6).first
                    }
                    TXT -> parseTxt(p.copyOfRange(start, start + len))
                    A -> if (len == 4) InetAddress.getByAddress(p.copyOfRange(start, start + 4)) else null
                    AAAA -> if (len == 16) InetAddress.getByAddress(p.copyOfRange(start, start + 16)) else null
                    else -> null
                }
                out.add(Record(name, type, ttl, data))
                off = start + len
            }
            return out
        } catch (_: Exception) {
            return null
        }
    }

    /** A TXT record's strings: "key=value" (the value may be empty), or "key" alone (a boolean attribute: null). */
    fun parseTxt(d: ByteArray): Map<String, String?> {
        val m = LinkedHashMap<String, String?>()
        var i = 0
        while (i < d.size) {
            val len = d[i].toInt() and 0xFF
            i++
            if (len == 0 || i + len > d.size) { i += len; continue }
            val s = d.copyOfRange(i, i + len).decodeToString()
            i += len
            val eq = s.indexOf('=')
            val key = if (eq < 0) s else s.substring(0, eq)
            if (key.isEmpty() || m.keys.any { it.equals(key, true) }) continue   // RFC 6763 §6.4: the first wins
            m[key] = if (eq < 0) null else s.substring(eq + 1)
        }
        return m
    }

    fun encodeTxt(m: Map<String, String?>): ByteArray {
        val o = ByteArrayOutputStream()
        for ((k, v) in m) { val b = (if (v == null) k else "$k=$v").encodeToByteArray(); o.write(b.size); o.write(b) }
        if (o.size() == 0) o.write(0)
        return o.toByteArray()
    }

    /** A name at `off`, following compression pointers (at most 32 jumps); the offset after it in place. */
    fun readName(p: ByteArray, start: Int): Pair<String, Int> {
        val labels = ArrayList<String>()
        var off = start
        var end = -1
        var jumps = 0
        while (true) {
            val len = p[off].toInt() and 0xFF
            when {
                len == 0 -> { off++; break }
                len and 0xC0 == 0xC0 -> {
                    if (++jumps > 32) throw IllegalArgumentException("a compression loop")
                    if (end < 0) end = off + 2
                    off = ((len and 0x3F) shl 8) or (p[off + 1].toInt() and 0xFF)
                }
                len and 0xC0 != 0 -> throw IllegalArgumentException("a label type DNS no longer has")
                else -> { labels.add(escapeLabel(String(p, off + 1, len, Charsets.UTF_8))); off += 1 + len }
            }
        }
        return labels.joinToString(".", postfix = ".") to (if (end >= 0) end else off)
    }
}

/**
 * Browses `_sill._tcp` with one-shot multicast DNS queries (RFC 6762 §5.1) from an ephemeral port on
 * every multicast interface, IPv4 and IPv6: the responders answer by unicast, so nothing here binds
 * port 5353 (Windows' own mDNS responder and Android's hold it) and Android needs no multicast lock.
 * Queries go out at once, after 1 and 2 s, then every 3 s while browsing; an answer's TTL (at most
 * 10 s for such queries) keeps a Mac listed between them, and one that stops answering drops off.
 * Instances seen without their SRV, TXT or address records get a follow-up query for them.
 */
class MdnsBrowser(
    private val serviceType: String = "_sill._tcp.local.",
    private val clock: Clock = Clock.System,
    private val includeLoopback: Boolean = false,
    private val onChange: (List<FoundService>) -> Unit,
) {
    private class Instance(var srv: Pair<Int, String>? = null, var txt: Map<String, String?>? = null, var expires: Double = 0.0, var iface: String? = null)
    private class HostAddr(val address: InetAddress, val expires: Double)

    private val instances = HashMap<String, Instance>()
    private val hosts = HashMap<String, MutableMap<InetAddress, HostAddr>>()
    private val sockets = ArrayList<Pair<MulticastSocket, InetSocketAddress>>()
    @Volatile private var running = false
    private var last: List<FoundService> = emptyList()

    fun start() {
        running = true
        for (ni in NetworkInterface.getNetworkInterfaces().toList()) {
            try {
                if (!ni.isUp || !ni.supportsMulticast() || (ni.isLoopback && !includeLoopback) || ni.isPointToPoint) continue
                val v4 = ni.inetAddresses.toList().any { it is Inet4Address }
                val v6 = ni.inetAddresses.toList().any { it is Inet6Address && it.isLinkLocalAddress }
                if (v4) open(ni, InetSocketAddress(InetAddress.getByName("224.0.0.251"), 5353))
                if (v6) open(ni, InetSocketAddress(Inet6Address.getByAddress(null, "ff0200000000000000000000000000fb".unhex(), ni), 5353))
            } catch (_: Exception) { /* an interface that will not take a socket: browse the others */ }
        }
        Thread({
            val waits = longArrayOf(0, 1000, 1000)
            var n = 0
            while (running) {
                sendQueries()
                Thread.sleep(if (n < waits.size) waits[n++] else 3000)
                publish()
            }
        }, "sill-mdns").apply { isDaemon = true }.start()
    }

    fun stop() {
        running = false
        synchronized(sockets) { sockets.forEach { it.first.close() }; sockets.clear() }
    }

    private fun open(ni: NetworkInterface, group: InetSocketAddress) {
        val s = MulticastSocket(InetSocketAddress(if (group.address is Inet6Address) InetAddress.getByName("::") else InetAddress.getByName("0.0.0.0"), 0))
        s.networkInterface = ni
        s.timeToLive = 255
        s.soTimeout = 1000
        synchronized(sockets) { sockets.add(s to group) }
        Thread({
            val buf = ByteArray(9000)
            while (running && !s.isClosed) {
                val p = DatagramPacket(buf, buf.size)
                try { s.receive(p) } catch (_: SocketTimeoutException) { continue } catch (_: Exception) { break }
                handlePacket(buf.copyOf(p.length), ni.displayName ?: ni.name, ni)
            }
        }, "sill-mdns-${ni.name}").apply { isDaemon = true }.start()
    }

    private fun sendQueries() {
        val qs = ArrayList<Pair<String, Int>>()
        qs.add(serviceType to Dns.PTR)
        synchronized(this) {
            for ((name, inst) in instances) {
                if (inst.srv == null || inst.txt == null) { qs.add(name to Dns.SRV); qs.add(name to Dns.TXT) }
                val target = inst.srv?.second
                if (target != null && hosts[target].isNullOrEmpty()) { qs.add(target to Dns.A); qs.add(target to Dns.AAAA) }
            }
        }
        val packet = Dns.query(qs)
        synchronized(sockets) {
            for ((s, group) in sockets) try { s.send(DatagramPacket(packet, packet.size, group)) } catch (_: Exception) {}
        }
    }

    /** One response, from one interface (`ni`, for an IPv6 link-local address's scope). Public for tests. */
    fun handlePacket(p: ByteArray, ifaceName: String?, ni: NetworkInterface? = null) {
        val records = Dns.parseResponse(p) ?: return
        val now = clock.mono()
        synchronized(this) {
            for (r in records) {
                val expires = now + r.ttl
                when (r.type) {
                    Dns.PTR -> if (r.name.equals(serviceType, true)) {
                        val name = r.data as String
                        if (r.ttl == 0L) instances.remove(name)
                        else instances.getOrPut(name) { Instance() }.also { it.expires = maxOf(it.expires, expires); it.iface = ifaceName }
                    }
                    Dns.SRV -> instances[r.name]?.let { inst ->
                        @Suppress("UNCHECKED_CAST")
                        inst.srv = r.data as Pair<Int, String>
                        if (r.ttl > 0) inst.expires = maxOf(inst.expires, expires)
                    }
                    Dns.TXT -> instances[r.name]?.let { it.txt = r.data as Map<String, String?> }
                    Dns.A, Dns.AAAA -> {
                        var a = r.data as? InetAddress ?: continue
                        if (a is Inet6Address && a.isLinkLocalAddress && ni != null) a = Inet6Address.getByAddress(null, a.address, ni)
                        val m = hosts.getOrPut(r.name.lowercase()) { LinkedHashMap() }
                        if (r.ttl == 0L) m.remove(a) else m[a] = HostAddr(a, expires)
                    }
                }
            }
        }
        publish()
    }

    /** What is listed now. Public for tests. */
    @Synchronized fun current(): List<FoundService> {
        val now = clock.mono()
        instances.entries.removeAll { it.value.expires < now }
        hosts.values.forEach { m -> m.entries.removeAll { it.value.expires < now } }
        return instances.mapNotNull { (fqdn, inst) ->
            val (port, target) = inst.srv ?: return@mapNotNull null
            val addrs = hosts[target.lowercase()]?.keys?.toList().orEmpty()
            if (addrs.isEmpty()) return@mapNotNull null
            val label = Dns.splitName(fqdn).firstOrNull() ?: return@mapNotNull null
            // IPv4 first: it needs no scope, and a Mac's home door listens on both.
            FoundService(label, target, port, addrs.sortedBy { if (it is Inet4Address) 0 else 1 }, inst.txt ?: emptyMap(), inst.iface)
        }.sortedBy { it.name.lowercase() }
    }

    private fun publish() {
        val now = current()
        val changed = synchronized(this) { (now != last).also { last = now } }
        if (changed) onChange(now)
    }
}
