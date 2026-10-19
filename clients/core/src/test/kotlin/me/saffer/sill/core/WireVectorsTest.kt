package me.saffer.sill.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The core against vectors.json, which clients/wire-vectors/generate.sh writes from the real
 * Sources/StreamProtocol: every payload decodes and round-trips, every binary layout is byte for
 * byte, every rule answers as the Mac's code does. It also writes this core's encodings of every
 * payload (build/kotlin-wire.json), which `generate.sh --check` decodes with the Mac's own types.
 */
class WireVectorsTest {
    private val root: JsonObj = JsonObj.of(Json.parse(javaClass.getResource("/sill/vectors.json")!!.readBytes()))

    private fun objects(key: String) = root.reqList(key).map { JsonObj.of(it) }

    @Test
    fun everyPayloadDecodesAndRoundTrips() {
        val out = ArrayList<Map<String, Any?>>()
        val messages = objects("messages")
        assertTrue(messages.size >= 50, "vectors.json has ${messages.size} messages")
        for (m in messages) {
            val name = m.reqString("name")
            val type = m.reqString("type")
            val decode = Payloads.decoders[type] ?: fail("no decoder for $type")
            val swift = m.reqString("json").encodeToByteArray()
            val value = try { decode(swift) } catch (e: JsonException) { fail("$name: ${e.message}") }
            val ours = value.bytes()
            // Ours decodes again to the same value, and has the same content as Swift's (key order aside).
            assertEquals(value, decode(ours), "$name round trip")
            assertEquals(normalize(Json.parse(m.reqString("sorted"))), normalize(Json.parse(ours)), "$name content")
            out.add(linkedMapOf("name" to name, "type" to type, "json" to ours.decodeToString()))
        }
        System.getProperty("sill.wireOut")?.let { File(it).apply { parentFile.mkdirs() }.writeText(Json.write(out)) }
    }

    /** Numbers compared by value (Swift writes 2, this core 2 or 2.0), maps by content. */
    private fun normalize(v: Any?): Any? = when (v) {
        is Map<*, *> -> v.entries.associate { it.key to normalize(it.value) }
        is List<*> -> v.map(::normalize)
        is JsonNumber -> v.toDouble()
        else -> v
    }

    @Test
    fun theKindsAreTheMacs() {
        val swift = objects("kinds").associate { it.reqInt("kind") to it.reqString("name") }
        assertEquals(swift, Kind.names)
    }

    @Test
    fun binaryLayouts() {
        for (b in objects("binary")) {
            val name = b.reqString("name")
            val want = b.reqString("hex")
            when (b.reqString("what")) {
                "message" -> {
                    val m = StreamMessage(b.reqInt("kind"), b.reqDouble("timestamp"), b.reqBool("keyframe"), b.reqString("payload").unhex())
                    assertEquals(want, m.serialized().hex(), name)
                    val h = StreamMessage.parseHeader(want.unhex())!!
                    assertEquals(m.kind, h.kind); assertEquals(m.timestamp, h.timestamp); assertEquals(m.isKeyframe, h.isKeyframe)
                    assertEquals(m.payload.size.toLong(), h.payloadLength)
                }
                "parameterSets" -> {
                    val p = ParameterSets(b.reqInt("nalLength"), b.reqList("sets").map { (it as String).unhex() })
                    assertEquals(want, p.encoded().hex(), name)
                    assertEquals(p, ParameterSets.decode(want.unhex()))
                }
                "thumbnail" -> {
                    assertEquals(want, ImageBlob.encodeThumbnail(b.reqLong("windowID"), b.reqString("image").unhex()).hex(), name)
                    val t = ImageBlob.decodeThumbnail(want.unhex())!!
                    assertEquals(b.reqLong("windowID"), t.windowID); assertEquals(b.reqString("image"), t.jpeg.hex())
                }
                "appIcon" -> {
                    assertEquals(want, ImageBlob.encodeIcon(b.reqString("bundleID"), b.reqString("image").unhex()).hex(), name)
                    assertEquals(b.reqString("bundleID"), ImageBlob.decodeIcon(want.unhex())!!.bundleID)
                }
                "cursorShape" -> {
                    val c = CursorShape(b.reqDouble("hotX").toFloat(), b.reqDouble("hotY").toFloat(), b.reqDouble("width").toFloat(),
                        b.reqDouble("height").toFloat(), b.reqString("image").unhex())
                    assertEquals(want, c.encoded().hex(), name)
                    val d = CursorShape.decode(want.unhex())!!
                    assertEquals(c.hotX, d.hotX); assertEquals(c.height, d.height)
                }
                else -> fail("unknown binary vector $name")
            }
        }
        // An unknown kind parses (and is skipped by the reader), never fails the header.
        assertEquals(200, StreamMessage.parseHeader(StreamMessage(200, 0.0, false, ByteArray(3)).serialized())!!.kind)
        assertEquals(null, StreamMessage.parseHeader(ByteArray(13)))
    }

    @Test
    fun limitsAndNames() {
        val l = root.reqObj("limits")
        assertEquals(StreamMessage.HEADER_LENGTH, l.reqInt("header"))
        assertEquals(StreamMessage.MAX_CLIENT_PAYLOAD, l.reqInt("maxClientPayload"))
        assertEquals(StreamMessage.MAX_PAIRING_PAYLOAD, l.reqInt("maxPairingPayload"))
        assertEquals(StreamMessage.MAX_FRAME_PAYLOAD, l.reqInt("maxFramePayload"))
        assertEquals(StreamMessage.MAX_OTHER_HOST_PAYLOAD, l.reqInt("maxOtherHostPayload"))
        assertEquals(SillProtocol.CURRENT, l.reqInt("protocol"))
        assertEquals(Clipboard.MAX_TEXT_BYTES, l.reqInt("clipboardMaxTextBytes"))
        assertEquals(PairRequest.VERSION, l.reqInt("pairRequestVersion"))
        assertEquals(objects("presets").map { it.reqString("name") to it.reqInt("bitrate") }, QualityPreset.entries.map { it.title to it.bitrate })
        assertEquals(root.reqList("gestures"), TrackpadGesture.names)
    }

    @Test
    fun versions() {
        for (v in objects("versions")) {
            val input = v.reqString("input")
            val got = SillVersion.parse(input)
            val shown = v.optString("shown")
            assertEquals(shown, got?.toString(), "version '$input'")
            if (got != null) assertEquals(v.reqList("components").map { (it as JsonNumber).toLongOrNull()!!.toInt() }, got.components, input)
        }
        for (row in root.reqList("versionOrder")) {
            row as List<*>
            val a = SillVersion.parse(row[0] as String)!!
            val b = SillVersion.parse(row[1] as String)!!
            assertEquals((row[2] as JsonNumber).toLongOrNull()!!.toInt(), a.compareTo(b).coerceIn(-1, 1), "${row[0]} vs ${row[1]}")
        }
    }

    @Test
    fun safeTextEveryScalar() {
        // Swift's table from its own Unicode data; this JVM's from its own. They may differ only where
        // one Unicode version assigns a character the other does not have yet.
        var compared = 0
        var tolerated = 0
        val differ = ArrayList<String>()
        for (run in root.reqList("safeTextClasses")) {
            run as List<*>
            val start = (run[0] as JsonNumber).toLongOrNull()!!.toInt()
            val end = (run[1] as JsonNumber).toLongOrNull()!!.toInt()
            val cls = (run[2] as JsonNumber).toLongOrNull()!!.toInt()
            for (cp in start..end) {
                compared++
                val ours = SafeText.scalarClass(cp)
                if (ours != cls) {
                    val unassignedHere = Character.getType(cp) == Character.UNASSIGNED.toInt()
                    if (unassignedHere && cls == 0) tolerated++ else differ.add("U+%04X swift %d jvm %d".format(cp, cls, ours))
                }
            }
        }
        assertEquals(0x110000 - 0x800, compared, "every scalar")
        assertTrue(differ.isEmpty(), "${differ.size} scalars differ: ${differ.take(20)}")
        // Unicode 15.1 and 16.0 assigned about 5,500 characters a Java 21 runtime does not know yet.
        // Those it removes from a name (Swift keeps them): a rare letter goes missing, nothing unsafe
        // gets through. More than that would be a real disagreement.
        assertTrue(tolerated <= 6000, "$tolerated scalars assigned by Swift's Unicode and not this JVM's")
        println("SafeText: $compared scalars, $tolerated newer than this JVM's Unicode")
    }

    @Test
    fun safeTextLabels() {
        for (l in objects("safeTextLabels")) {
            assertEquals(l.reqString("output"), SafeText.label(l.reqString("input"), l.reqInt("limit")), "label of ${l.reqString("input")}")
        }
        assertEquals(SafeText.LABEL_LIMIT, root.reqInt("safeTextLimit"))
    }

    @Test
    fun addresses() {
        val rows = objects("addresses")
        assertTrue(rows.size >= 60)
        for (a in rows) {
            val input = a.reqString("input")
            when (val r = AddressParser.parse(input)) {
                is AddressParser.Result.Ok -> {
                    assertTrue(a.reqBool("ok"), "'$input' should fail with ${a.optString("failure")}, got ${r.address}")
                    assertEquals(a.reqString("host"), r.address.host, input)
                    assertEquals(a.optInt("port"), r.address.port, input)
                    assertEquals(a.reqString("kind"), r.address.kind.raw, input)
                    assertEquals(a.reqString("text"), r.address.text, input)
                }
                is AddressParser.Result.Failed -> {
                    assertTrue(!a.reqBool("ok"), "'$input' should parse to ${a.optString("host")}, got ${r.failure}")
                    assertEquals(a.reqString("failure"), r.failure.raw, input)
                }
            }
        }
    }

    @Test
    fun jsonEdges() {
        assertEquals(mapOf("a" to listOf(JsonNumber("1"), true, null, "xé\n")), Json.parse("""{"a":[1,true,null,"xé\n"]}"""))
        for (bad in listOf("", "{", "[1,]", "{\"a\":}", "01", "1.", "\"\u0001\"", "tru", "{} x", "[1 2]")) {
            try { Json.parse(bad); fail("'$bad' parsed") } catch (_: JsonException) {}
        }
        // A required key missing fails the payload, an unknown key is ignored, null reads as absent.
        try { Goodbye.fromJson(JsonObj.parse("{}".encodeToByteArray())); fail("no reason decoded") } catch (_: JsonException) {}
        assertEquals(Goodbye("quit"), Goodbye.fromJson(JsonObj.parse("""{"reason":"quit","later":{"x":1},"message":null}""".encodeToByteArray())))
        // Swift's enums: exactly one key.
        try { StreamSource.fromJson(JsonObj.parse("""{"none":{},"desktop":{}}""".encodeToByteArray())); fail() } catch (_: JsonException) {}
        try { InputEvent.fromJson(JsonObj.parse("""{"pointer":{"_0":"middleDown","x":0,"y":0}}""".encodeToByteArray())); fail() } catch (_: JsonException) {}
        // Integers stay integers: 4294967295 and 2^53+1 are exact.
        assertEquals(StreamSource.Window(4294967295), StreamSource.fromJson(JsonObj.parse("""{"window":{"_0":4294967295}}""".encodeToByteArray())))
        assertEquals(9007199254740993L, JsonObj.parse("""{"n":9007199254740993}""".encodeToByteArray()).reqLong("n"))
        assertNotNull(Json.write(mapOf("d" to 0.1, "i" to 2.0, "e" to 1e-7)).let { assertEquals("""{"d":0.1,"i":2,"e":1.0E-7}""", it) })
    }
}
