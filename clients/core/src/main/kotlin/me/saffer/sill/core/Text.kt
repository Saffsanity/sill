package me.saffer.sill.core

import java.text.BreakIterator

/** The wire's generation (Compatibility.swift): 1 is `sill/1`. */
object SillProtocol {
    const val CURRENT = 1
}

/**
 * A version as tags, bundles and the wire write it (Compatibility.swift's SillVersion): one leading
 * "v" dropped, then the longest prefix of ASCII digits and dots without the dots at its end, at most
 * 8 parts of 1–9 digits each; compared part by part, a missing part counting as 0; shown with at
 * least two parts and no trailing zeros beyond them.
 */
class SillVersion(components: List<Int>) : Comparable<SillVersion> {
    val components: List<Int> = components.dropLastWhile { it == 0 }

    override fun compareTo(other: SillVersion): Int {
        for (i in 0 until maxOf(components.size, other.components.size)) {
            val x = components.getOrElse(i) { 0 }
            val y = other.components.getOrElse(i) { 0 }
            if (x != y) return x.compareTo(y)
        }
        return 0
    }

    override fun equals(other: Any?) = other is SillVersion && other.components == components
    override fun hashCode() = components.hashCode()
    override fun toString(): String {
        val c = components.toMutableList()
        while (c.size < 2) c.add(0)
        return c.joinToString(".")
    }

    companion object {
        val ZERO = SillVersion(emptyList())

        fun parse(text: String): SillVersion? {
            var s = text.trim(::isUnicodeSpace)
            if (s.startsWith("v") || s.startsWith("V")) s = s.substring(1)
            val prefix = s.takeWhile { it in '0'..'9' || it == '.' }.trimEnd('.')
            if (prefix.isEmpty() || prefix[0] !in '0'..'9') return null
            val parts = prefix.split(".")
            if (parts.size > 8) return null
            val numbers = parts.map { p -> if (p.length !in 1..9) return null else p.toInt() }
            return SillVersion(numbers)
        }

        // Swift's .whitespacesAndNewlines: the Unicode White_Space characters.
        private fun isUnicodeSpace(c: Char) = SafeText.isWhiteSpace(c.code)
    }
}

/**
 * Text a device or a Mac supplies about itself, as one line (SafeText.swift): whitespace of every
 * kind becomes one space, control, format, surrogate, private-use and unassigned characters are
 * removed, runs of spaces collapse, the ends are trimmed, and at most `limit` characters (grapheme
 * clusters) are kept. Both ends clean names the same way.
 */
object SafeText {
    const val LABEL_LIMIT = 64

    /** Unicode's White_Space property (Swift's `isWhitespace`), which also covers U+2028 and U+2029. */
    fun isWhiteSpace(cp: Int) = cp in 0x09..0x0D || cp == 0x20 || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        cp in 0x2000..0x200A || cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000

    /** 0 kept, 1 a space, 2 removed: what [label] does with one scalar. */
    fun scalarClass(cp: Int): Int {
        if (isWhiteSpace(cp)) return 1
        val t = Character.getType(cp)
        if (t == Character.LINE_SEPARATOR.toInt() || t == Character.PARAGRAPH_SEPARATOR.toInt()) return 1
        return when (t) {
            Character.CONTROL.toInt(), Character.FORMAT.toInt(), Character.SURROGATE.toInt(),
            Character.PRIVATE_USE.toInt(), Character.UNASSIGNED.toInt() -> 2
            else -> 0
        }
    }

    fun label(text: String, limit: Int = LABEL_LIMIT): String {
        val sb = StringBuilder()
        var pendingSpace = false
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            i += Character.charCount(cp)
            when (scalarClass(cp)) {
                1 -> { pendingSpace = sb.isNotEmpty(); continue }
                2 -> continue
            }
            if (pendingSpace) { sb.append(' '); pendingSpace = false }
            sb.appendCodePoint(cp)
        }
        var out = sb.toString()
        if (characterCount(out) > limit) {
            out = prefixCharacters(out, limit).trimEnd(' ')
        }
        return out
    }

    /** Grapheme clusters, as Swift's `String.count`. */
    fun characterCount(s: String): Int {
        val it = BreakIterator.getCharacterInstance()
        it.setText(s)
        var n = 0
        while (it.next() != BreakIterator.DONE) n++
        return n
    }

    private fun prefixCharacters(s: String, n: Int): String {
        val bi = BreakIterator.getCharacterInstance()
        bi.setText(s)
        var end = 0
        repeat(n) { val e = bi.next(); if (e == BreakIterator.DONE) return s; end = e }
        return s.substring(0, end)
    }
}

/** One address a person typed, pasted or scanned (AddressParser.swift's ParsedAddress). */
data class ParsedAddress(val host: String, val port: Int?, val kind: Kind) {
    enum class Kind(val raw: String) { IPV4("ipv4"), IPV6("ipv6"), NAME("name") }

    /** "host" or "host:port", an IPv6 address in brackets. */
    val text: String get() {
        val h = if (kind == Kind.IPV6) "[$host]" else host
        return if (port != null) "$h:$port" else h
    }
}

/**
 * The strict parser for every address Sill takes from a person or a link (AddressParser.swift),
 * with the C library's `inet_pton`, `inet_ntop` and `inet_aton` written out, so it answers the same
 * on every platform: an IPv4 address only as four decimal octets, a bare IPv6 address as its
 * compressed lowercase form (IPv4-mapped ones as IPv4), a name under RFC 1123, a port 1–65535.
 */
object AddressParser {
    enum class Failure(val raw: String) { EMPTY("empty"), MALFORMED("malformed"), ZONE("zone"), IPV4("ipv4"), IPV6("ipv6"), NAME("name"), PORT("port"), PAIRING_LINK("pairingLink") }

    sealed class Result {
        data class Ok(val address: ParsedAddress) : Result()
        data class Failed(val failure: Failure) : Result()
    }

    fun parse(raw: String): Result {
        val s = raw.trim { SafeText.isWhiteSpace(it.code) }
        if (s.isEmpty()) return Result.Failed(Failure.EMPTY)
        if (s.lowercase().startsWith("sill:")) return Result.Failed(Failure.PAIRING_LINK)
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            if (SafeText.isWhiteSpace(cp) || cp < 0x20 || cp == 0x7F) return Result.Failed(Failure.MALFORMED)
            i += Character.charCount(cp)
        }
        if ('%' in s) return Result.Failed(Failure.ZONE)
        if (s.startsWith("[")) {
            val close = s.indexOf(']')
            if (close < 0) return Result.Failed(Failure.IPV6)
            val hostPart = s.substring(1, close)
            val rest = s.substring(close + 1)
            var portPart: String? = null
            if (rest.isNotEmpty()) {
                if (rest[0] != ':') return Result.Failed(Failure.MALFORMED)
                portPart = rest.substring(1)
            }
            val v6 = ipv6(hostPart) ?: return Result.Failed(Failure.IPV6)
            if (portPart != null) {
                val p = parsePort(portPart) ?: return Result.Failed(Failure.PORT)
                return Result.Ok(v6.copy(port = p))
            }
            return Result.Ok(v6)
        }
        val colons = s.count { it == ':' }
        if (colons >= 2) return ipv6(s)?.let { Result.Ok(it) } ?: Result.Failed(Failure.IPV6)
        val hostPart: String
        var portPart: String? = null
        if (colons == 1) {
            val c = s.indexOf(':')
            hostPart = s.substring(0, c)
            portPart = s.substring(c + 1)
        } else hostPart = s
        val host = when (val h = hostOnly(hostPart)) { is Result.Ok -> h.address; is Result.Failed -> return h }
        if (portPart != null) {
            val p = parsePort(portPart) ?: return Result.Failed(Failure.PORT)
            return Result.Ok(host.copy(port = p))
        }
        return Result.Ok(host)
    }

    private fun isAsciiDigit(c: Char) = c in '0'..'9'

    private fun hostOnly(h: String): Result {
        if (h.isEmpty()) return Result.Failed(Failure.MALFORMED)
        val labels = (if (h.endsWith(".")) h.dropLast(1) else h).split(".")
        val allNumeric = labels.isNotEmpty() && labels.all { it.isNotEmpty() && it.all(::isAsciiDigit) }
        if (allNumeric) {
            val ok = !h.endsWith(".") && labels.size == 4 &&
                labels.all { (it == "0" || it[0] != '0') && it.length <= 3 && it.toInt() <= 255 }
            return if (ok) Result.Ok(ParsedAddress(h, null, ParsedAddress.Kind.IPV4)) else Result.Failed(Failure.IPV4)
        }
        if (inetAton(h) != null) return Result.Failed(Failure.IPV4)
        if (!isName(h)) return Result.Failed(Failure.NAME)
        return Result.Ok(ParsedAddress(h, null, ParsedAddress.Kind.NAME))
    }

    private fun isName(h: String): Boolean {
        val body = if (h.endsWith(".")) h.dropLast(1) else h
        if (body.isEmpty() || body.length > 253) return false
        for (label in body.split(".")) {
            if (label.length !in 1..63 || label.first() == '-' || label.last() == '-') return false
            if (!label.all { it in 'a'..'z' || it in 'A'..'Z' || isAsciiDigit(it) || it == '-' }) return false
        }
        return true
    }

    private fun parsePort(p: String): Int? {
        if (p.isEmpty() || p.length > 5 || !p.all(::isAsciiDigit)) return null
        return p.toInt().takeIf { it in 1..65535 }
    }

    private fun ipv6(h: String): ParsedAddress? {
        if (h.isEmpty() || '%' in h) return null
        val b = inetPton6(h) ?: return null
        if ((0 until 10).all { b[it] == 0 } && b[10] == 0xFF && b[11] == 0xFF) {
            return ParsedAddress("${b[12]}.${b[13]}.${b[14]}.${b[15]}", null, ParsedAddress.Kind.IPV4)
        }
        return ParsedAddress(inetNtop6(b), null, ParsedAddress.Kind.IPV6)
    }

    /** The C library's inet_aton: one to four parts, each decimal, octal (a leading 0) or hex (0x). */
    fun inetAton(s: String): Long? {
        val parts = s.split(".")
        if (parts.size > 4 || parts.any { it.isEmpty() }) return null
        val values = parts.map { p ->
            val (digits, radix) = when {
                p.startsWith("0x") || p.startsWith("0X") -> p.substring(2) to 16
                p.length > 1 && p[0] == '0' -> p.substring(1) to 8
                else -> p to 10
            }
            if (digits.isEmpty()) { if (radix == 16) 0L else return null }
            else {
                if (!digits.all { Character.digit(it, radix) >= 0 && it.code < 0x80 }) return null
                digits.toBigInteger(radix).takeIf { it.bitLength() <= 32 }?.toLong() ?: return null
            }
        }
        val n = values.size
        for (j in 0 until n - 1) if (values[j] > 255) return null
        val maxLast = when (n) { 1 -> 0xFFFFFFFFL; 2 -> 0xFFFFFFL; 3 -> 0xFFFFL; else -> 0xFFL }
        if (values.last() > maxLast) return null
        var r = 0L
        for (j in 0 until n - 1) r = r or (values[j] shl (24 - 8 * j))
        return r or values.last()
    }

    /** The C library's inet_pton(AF_INET6): 16 bytes (as ints), or null. */
    fun inetPton6(s: String): IntArray? {
        val words = IntArray(8)
        var w = 0
        var gap = -1
        var i = 0
        if (s.startsWith("::")) { gap = 0; i = 2; if (s.length == 2) return IntArray(16) }
        else if (s.startsWith(":")) return null
        while (i < s.length) {
            // An embedded IPv4 address in the last 32 bits.
            val nextColon = s.indexOf(':', i).let { if (it < 0) s.length else it }
            val token = s.substring(i, nextColon)
            if ('.' in token) {
                if (nextColon != s.length || w > 6) return null
                val v4 = inetPton4(token) ?: return null
                words[w++] = (v4[0] shl 8) or v4[1]
                words[w++] = (v4[2] shl 8) or v4[3]
                i = s.length
                break
            }
            if (token.isEmpty() || token.length > 4 || !token.all { Character.digit(it, 16) >= 0 && it.code < 0x80 }) return null
            if (w >= 8) return null
            words[w++] = token.toInt(16)
            i = nextColon
            if (i < s.length) {
                // At a colon: "::" marks the gap (once), a lone ':' separates, and none may end the text.
                if (i + 1 < s.length && s[i + 1] == ':') {
                    if (gap >= 0) return null
                    gap = w
                    i += 2
                } else {
                    i += 1
                    if (i == s.length) return null
                }
            }
        }
        val out = IntArray(8)
        if (gap >= 0) {
            if (w == 8) return null
            for (j in 0 until gap) out[j] = words[j]
            val tail = w - gap
            for (j in 0 until tail) out[8 - tail + j] = words[gap + j]
        } else {
            if (w != 8) return null
            words.copyInto(out)
        }
        return IntArray(16) { k -> if (k % 2 == 0) out[k / 2] shr 8 else out[k / 2] and 0xFF }
    }

    /** inet_pton(AF_INET): exactly four decimal octets, no leading zeros. */
    private fun inetPton4(s: String): IntArray? {
        val parts = s.split(".")
        if (parts.size != 4) return null
        return IntArray(4) { k ->
            val p = parts[k]
            if (p.isEmpty() || p.length > 3 || !p.all(::isAsciiDigit) || (p.length > 1 && p[0] == '0')) return null
            p.toInt().takeIf { it <= 255 } ?: return null
        }
    }

    /** inet_ntop(AF_INET6): the longest run of two or more zero words (the first on a tie) as "::". */
    fun inetNtop6(b: IntArray): String {
        val words = IntArray(8) { (b[2 * it] shl 8) or b[2 * it + 1] }
        var bestBase = -1; var bestLen = 0; var curBase = -1; var curLen = 0
        for (k in 0 until 8) {
            if (words[k] == 0) {
                if (curBase < 0) { curBase = k; curLen = 1 } else curLen++
            } else if (curBase >= 0) {
                if (curLen > bestLen) { bestBase = curBase; bestLen = curLen }
                curBase = -1
            }
        }
        if (curBase >= 0 && curLen > bestLen) { bestBase = curBase; bestLen = curLen }
        if (bestLen < 2) bestBase = -1
        val sb = StringBuilder()
        var k = 0
        while (k < 8) {
            if (bestBase >= 0 && k >= bestBase && k < bestBase + bestLen) {
                if (k == bestBase) sb.append(':')
                k++
                continue
            }
            if (k != 0) sb.append(':')
            // An IPv4-compatible or -mapped address keeps its last 32 bits dotted, as the C library does.
            if (k == 6 && bestBase == 0 && (bestLen == 6 || (bestLen == 5 && words[5] == 0xFFFF))) {
                sb.append("${b[12]}.${b[13]}.${b[14]}.${b[15]}")
                return sb.toString()
            }
            sb.append(Integer.toHexString(words[k]))
            k++
        }
        if (bestBase >= 0 && bestBase + bestLen == 8) sb.append(':')
        return sb.toString()
    }
}
