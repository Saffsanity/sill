package me.saffer.sill.core

/**
 * Just enough JSON for the wire's payloads (RFC 8259), with no dependency: the core stays the
 * standard library alone, as Sources/StreamProtocol stays Foundation.
 *
 * Values are Kotlin's own: an object is a `Map<String, Any?>` in key order, an array a `List<Any?>`,
 * a string a `String`, `true`/`false` a `Boolean`, `null` Kotlin's null, and a number a [JsonNumber]
 * that keeps its text, so an integer is never read through a Double. Decoding follows Swift's
 * JSONDecoder where the payloads depend on it: an unknown key is ignored, a key whose value is null
 * reads as absent, and a required key that is missing or of the wrong type fails the whole payload
 * ([JsonException]), which is how an older Mac would treat it too.
 */
class JsonNumber(val text: String) {
    fun toDouble(): Double = text.toDouble()
    /** The number as an integer, or null when it has a fraction or an exponent that leaves one. */
    fun toLongOrNull(): Long? = text.toLongOrNull() ?: text.toBigDecimalOrNull()?.let {
        try { it.longValueExact() } catch (_: ArithmeticException) { null }
    }
    override fun equals(other: Any?) = other is JsonNumber && other.toDouble() == toDouble()
    override fun hashCode() = toDouble().hashCode()
    override fun toString() = text
}

class JsonException(message: String) : Exception(message)

object Json {
    fun parse(text: String): Any? {
        val p = Parser(text)
        p.skipSpace()
        val v = p.value(0)
        p.skipSpace()
        if (p.i != text.length) throw JsonException("trailing characters at ${p.i}")
        return v
    }

    fun parse(bytes: ByteArray): Any? = parse(bytes.decodeToString(throwOnInvalidSequence = true))

    /** `value` as JSON text. Map entries whose value is null are left out, as Swift leaves out a nil optional. */
    fun write(value: Any?): String = StringBuilder().also { write(it, value) }.toString()

    fun bytes(value: Any?): ByteArray = write(value).encodeToByteArray()

    private fun write(sb: StringBuilder, v: Any?) {
        when (v) {
            null -> sb.append("null")
            is String -> string(sb, v)
            is Boolean -> sb.append(if (v) "true" else "false")
            is JsonNumber -> sb.append(v.text)
            is Int, is Long, is Short, is Byte -> sb.append(v.toString())
            is UInt -> sb.append(v.toString())
            is Double -> number(sb, v)
            is Float -> number(sb, v.toDouble())
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, value) in v) {
                    if (value == null) continue
                    if (!first) sb.append(',')
                    first = false
                    string(sb, k as String)
                    sb.append(':')
                    write(sb, value)
                }
                sb.append('}')
            }
            is List<*> -> {
                sb.append('[')
                v.forEachIndexed { i, e -> if (i > 0) sb.append(','); write(sb, e) }
                sb.append(']')
            }
            else -> throw IllegalArgumentException("not a JSON value: ${v::class}")
        }
    }

    private fun number(sb: StringBuilder, d: Double) {
        require(d.isFinite()) { "JSON has no $d" }
        // Integral doubles without a fraction ("2", as Swift writes them); others in Kotlin's
        // shortest round-trip form, whose exponent ("1.0E-5") is valid JSON.
        if (d == Math.rint(d) && kotlin.math.abs(d) < 1e15) sb.append(d.toLong()) else sb.append(d.toString())
    }

    private fun string(sb: StringBuilder, s: String) {
        sb.append('"')
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                else -> if (c < ' ') sb.append("\\u").append(String.format("%04x", c.code)) else sb.append(c)
            }
        }
        sb.append('"')
    }

    private class Parser(val s: String) {
        var i = 0

        fun skipSpace() { while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++ }

        fun fail(what: String): Nothing = throw JsonException("$what at $i")

        fun value(depth: Int): Any? {
            if (depth > 64) fail("nested too deep")
            if (i >= s.length) fail("unexpected end")
            return when (val c = s[i]) {
                '{' -> obj(depth)
                '[' -> arr(depth)
                '"' -> str()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", null)
                else -> if (c == '-' || c in '0'..'9') num() else fail("unexpected '$c'")
            }
        }

        fun literal(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) fail("bad literal")
            i += word.length
            return v
        }

        fun obj(depth: Int): Map<String, Any?> {
            i++
            val m = LinkedHashMap<String, Any?>()
            skipSpace()
            if (i < s.length && s[i] == '}') { i++; return m }
            while (true) {
                skipSpace()
                if (i >= s.length || s[i] != '"') fail("expected a key")
                val k = str()
                skipSpace()
                if (i >= s.length || s[i] != ':') fail("expected ':'")
                i++
                skipSpace()
                m[k] = value(depth + 1)
                skipSpace()
                if (i >= s.length) fail("unexpected end")
                when (s[i]) { ',' -> i++; '}' -> { i++; return m }; else -> fail("expected ',' or '}'") }
            }
        }

        fun arr(depth: Int): List<Any?> {
            i++
            val l = ArrayList<Any?>()
            skipSpace()
            if (i < s.length && s[i] == ']') { i++; return l }
            while (true) {
                skipSpace()
                l.add(value(depth + 1))
                skipSpace()
                if (i >= s.length) fail("unexpected end")
                when (s[i]) { ',' -> i++; ']' -> { i++; return l }; else -> fail("expected ',' or ']'") }
            }
        }

        fun str(): String {
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= s.length) fail("unterminated string")
                val c = s[i++]
                when {
                    c == '"' -> return sb.toString()
                    c == '\\' -> {
                        if (i >= s.length) fail("bad escape")
                        when (val e = s[i++]) {
                            '"' -> sb.append('"'); '\\' -> sb.append('\\'); '/' -> sb.append('/')
                            'b' -> sb.append('\b'); 'f' -> sb.append('\u000C'); 'n' -> sb.append('\n')
                            'r' -> sb.append('\r'); 't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) fail("bad \\u escape")
                                val code = s.substring(i, i + 4).toIntOrNull(16) ?: fail("bad \\u escape")
                                sb.append(code.toChar())
                                i += 4
                            }
                            else -> fail("bad escape '\\$e'")
                        }
                    }
                    c < ' ' -> fail("control character in a string")
                    else -> sb.append(c)
                }
            }
        }

        fun num(): JsonNumber {
            val start = i
            if (s[i] == '-') i++
            if (i < s.length && s[i] == '0') i++
            else if (i < s.length && s[i] in '1'..'9') while (i < s.length && s[i].isAsciiDigit()) i++
            else fail("bad number")
            if (i < s.length && s[i] == '.') {
                i++
                if (i >= s.length || !s[i].isAsciiDigit()) fail("bad number")
                while (i < s.length && s[i].isAsciiDigit()) i++
            }
            if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
                i++
                if (i < s.length && (s[i] == '+' || s[i] == '-')) i++
                if (i >= s.length || !s[i].isAsciiDigit()) fail("bad number")
                while (i < s.length && s[i].isAsciiDigit()) i++
            }
            return JsonNumber(s.substring(start, i))
        }

        private fun Char.isAsciiDigit() = this in '0'..'9'
    }
}

/**
 * Typed reads of one JSON object, as Swift's Codable reads them: `req*` fails the payload when the
 * key is missing or has another type, `opt*` returns null for a missing or null key and fails for a
 * present key of another type (Swift's `decodeIfPresent`).
 */
@Suppress("UNCHECKED_CAST")
class JsonObj(val map: Map<String, Any?>) {
    private fun present(k: String): Any? = map[k]

    private fun bad(k: String, want: String): Nothing = throw JsonException("'$k' is not $want")

    fun optString(k: String): String? = present(k)?.let { it as? String ?: bad(k, "a string") }
    fun reqString(k: String): String = optString(k) ?: throw JsonException("'$k' is missing")

    fun optBool(k: String): Boolean? = present(k)?.let { it as? Boolean ?: bad(k, "a bool") }
    fun reqBool(k: String): Boolean = optBool(k) ?: throw JsonException("'$k' is missing")

    fun optLong(k: String): Long? = present(k)?.let { (it as? JsonNumber)?.toLongOrNull() ?: bad(k, "an integer") }
    fun reqLong(k: String): Long = optLong(k) ?: throw JsonException("'$k' is missing")
    fun optInt(k: String): Int? = optLong(k)?.let { if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else bad(k, "an Int") }
    fun reqInt(k: String): Int = optInt(k) ?: throw JsonException("'$k' is missing")

    fun optDouble(k: String): Double? = present(k)?.let { (it as? JsonNumber)?.toDouble() ?: bad(k, "a number") }
    fun reqDouble(k: String): Double = optDouble(k) ?: throw JsonException("'$k' is missing")

    fun optObj(k: String): JsonObj? = present(k)?.let { JsonObj(it as? Map<String, Any?> ?: bad(k, "an object")) }
    fun reqObj(k: String): JsonObj = optObj(k) ?: throw JsonException("'$k' is missing")

    fun optList(k: String): List<Any?>? = present(k)?.let { it as? List<Any?> ?: bad(k, "an array") }
    fun reqList(k: String): List<Any?> = optList(k) ?: throw JsonException("'$k' is missing")

    fun <T> optObjects(k: String, f: (JsonObj) -> T): List<T>? = optList(k)?.map { f(JsonObj(it as? Map<String, Any?> ?: bad(k, "an array of objects"))) }
    fun <T> reqObjects(k: String, f: (JsonObj) -> T): List<T> = optObjects(k, f) ?: throw JsonException("'$k' is missing")

    companion object {
        @Suppress("UNCHECKED_CAST")
        fun of(value: Any?): JsonObj = JsonObj(value as? Map<String, Any?> ?: throw JsonException("not an object"))
        fun parse(bytes: ByteArray): JsonObj = of(Json.parse(bytes))
    }
}
