package me.saffer.sill.core

import java.util.Base64

// The JSON payloads, field for field the Swift types in Sources/StreamProtocol (each type's comment
// names its file). Swift property names are the JSON keys, nil optionals are left out, enums with
// associated values encode as Swift's synthesized Codable does (`{"window":{"_0":42}}`), and a
// decode fails where Swift's would (a required key missing, an enum case unknown), so this core
// reads and writes exactly what the Mac does. clients/wire-vectors checks both directions against
// the Swift types themselves.
//
// HostSettings.swift's rules hold here as there: fields added later are optional, never renamed or
// retyped, and no new enum cases on the wire.

/** Something that becomes one JSON payload. */
interface WirePayload {
    fun toJson(): Any?
    fun bytes(): ByteArray = Json.bytes(toJson())
}

private fun obj(vararg pairs: Pair<String, Any?>): Map<String, Any?> = linkedMapOf(*pairs)

/** Swift's enum with associated values: exactly one key, the case. */
private fun enumCase(o: JsonObj): Pair<String, JsonObj> {
    if (o.map.size != 1) throw JsonException("an enum needs exactly one key, got ${o.map.keys}")
    val (k, v) = o.map.entries.first()
    return k to JsonObj.of(v)
}

// MARK: Switcher.swift

sealed class StreamSource : WirePayload {
    object None : StreamSource() { override fun toJson() = obj("none" to emptyMap<String, Any?>()); override fun toString() = "none" }
    object Desktop : StreamSource() { override fun toJson() = obj("desktop" to emptyMap<String, Any?>()); override fun toString() = "desktop" }
    data class Window(val id: Long) : StreamSource() { override fun toJson() = obj("window" to obj("_0" to id)) }

    companion object {
        fun fromJson(o: JsonObj): StreamSource {
            val (k, v) = enumCase(o)
            return when (k) {
                "none" -> None
                "desktop" -> Desktop
                "window" -> Window(v.reqLong("_0").also { if (it !in 0..0xFFFFFFFFL) throw JsonException("not a UInt32") })
                else -> throw JsonException("unknown source '$k'")
            }
        }
    }
}

data class WindowInfo(val id: Long, val title: String, val appName: String, val bundleID: String, val width: Int, val height: Int) : WirePayload {
    override fun toJson() = obj("id" to id, "title" to title, "appName" to appName, "bundleID" to bundleID, "width" to width, "height" to height)
    companion object {
        fun fromJson(o: JsonObj) = WindowInfo(o.reqLong("id"), o.reqString("title"), o.reqString("appName"), o.reqString("bundleID"), o.reqInt("width"), o.reqInt("height"))
    }
}

data class AppInfo(val name: String, val bundleID: String) : WirePayload {
    override fun toJson() = obj("name" to name, "bundleID" to bundleID)
    companion object {
        fun fromJson(o: JsonObj) = AppInfo(o.reqString("name"), o.reqString("bundleID"))
        fun listFromJson(v: Any?): List<AppInfo> = (v as? List<*> ?: throw JsonException("not an array")).map { fromJson(JsonObj.of(it)) }
    }
}

data class WindowList(
    val macName: String, val windows: List<WindowInfo>, val active: StreamSource, val launchID: String? = null,
    val hostVersion: String? = null, val protocol: Int? = null, val gestures: Int? = null, val clipboard: Int? = null,
) : WirePayload {
    override fun toJson() = obj("macName" to macName, "windows" to windows.map { it.toJson() }, "active" to active.toJson(),
        "launchID" to launchID, "hostVersion" to hostVersion, "protocol" to protocol, "gestures" to gestures, "clipboard" to clipboard)
    companion object {
        fun fromJson(o: JsonObj) = WindowList(o.reqString("macName"), o.reqObjects("windows", WindowInfo::fromJson),
            StreamSource.fromJson(o.reqObj("active")), o.optString("launchID"), o.optString("hostVersion"), o.optInt("protocol"),
            o.optInt("gestures"), o.optInt("clipboard"))
    }
}

data class LaunchApp(val bundleID: String) : WirePayload {
    override fun toJson() = obj("bundleID" to bundleID)
    companion object { fun fromJson(o: JsonObj) = LaunchApp(o.reqString("bundleID")) }
}

data class WindowCommand(val id: Long, val action: String) : WirePayload {
    override fun toJson() = obj("id" to id, "action" to action)
    companion object {
        const val CLOSE = "close"; const val MINIMIZE = "minimize"; const val FULL_SCREEN = "fullScreen"
        fun fromJson(o: JsonObj): WindowCommand {
            val a = o.reqString("action")
            if (a !in setOf(CLOSE, MINIMIZE, FULL_SCREEN)) throw JsonException("unknown action '$a'")
            return WindowCommand(o.reqLong("id"), a)
        }
    }
}

// MARK: Input.swift

/** The pointer actions, by their raw values. */
enum class PointerAction(val raw: String) {
    MOVE("move"), LEFT_DOWN("leftDown"), LEFT_UP("leftUp"), RIGHT_DOWN("rightDown"), RIGHT_UP("rightUp");
    companion object { fun of(raw: String) = entries.firstOrNull { it.raw == raw } ?: throw JsonException("unknown pointer action '$raw'") }
}

enum class ScrollPhase(val raw: String) {
    BEGAN("began"), ENDED("ended"), MOMENTUM_BEGAN("momentumBegan"), MOMENTUM_ENDED("momentumEnded");
    companion object { fun of(raw: String) = entries.firstOrNull { it.raw == raw } ?: throw JsonException("unknown scroll phase '$raw'") }
}

/**
 * Client → host input (kind 8). Positions are fractions of the streamed frame, 0…1 across its width
 * and height. Modifier bits are UIKeyModifierFlags' (and CGEventFlags'): [Modifiers].
 */
sealed class InputEvent : WirePayload {
    data class Pointer(val action: PointerAction, val x: Double, val y: Double) : InputEvent() {
        override fun toJson() = obj("pointer" to obj("_0" to action.raw, "x" to x, "y" to y))
    }
    /** dx/dy: fractions of the frame the content should move, natural sign (positive dy: content moves down). */
    data class Scroll(val x: Double, val y: Double, val dx: Double, val dy: Double) : InputEvent() {
        override fun toJson() = obj("scroll" to obj("x" to x, "y" to y, "dx" to dx, "dy" to dy))
    }
    /** "\n", "\t" and "\u0008" (backspace) arrive as those keys; anything else is typed as Unicode. */
    data class Text(val text: String) : InputEvent() {
        override fun toJson() = obj("text" to obj("_0" to text))
    }
    data class ScrollGesture(val phase: ScrollPhase, val x: Double, val y: Double) : InputEvent() {
        override fun toJson() = obj("scrollGesture" to obj("_0" to phase.raw, "x" to x, "y" to y))
    }
    /** A key by USB HID usage (page 7) with [Modifiers] bits. */
    data class Key(val hidUsage: Int, val down: Boolean, val modifiers: Long) : InputEvent() {
        override fun toJson() = obj("key" to obj("hidUsage" to hidUsage, "down" to down, "modifiers" to modifiers))
    }

    companion object {
        fun fromJson(o: JsonObj): InputEvent {
            val (k, v) = enumCase(o)
            return when (k) {
                "pointer" -> Pointer(PointerAction.of(v.reqString("_0")), v.reqDouble("x"), v.reqDouble("y"))
                "scroll" -> Scroll(v.reqDouble("x"), v.reqDouble("y"), v.reqDouble("dx"), v.reqDouble("dy"))
                "text" -> Text(v.reqString("_0"))
                "scrollGesture" -> ScrollGesture(ScrollPhase.of(v.reqString("_0")), v.reqDouble("x"), v.reqDouble("y"))
                "key" -> Key(v.reqInt("hidUsage").also { if (it !in 0..0xFFFF) throw JsonException("not a UInt16") }, v.reqBool("down"), v.reqLong("modifiers"))
                else -> throw JsonException("unknown input '$k'")
            }
        }
    }
}

/** UIKeyModifierFlags, the bits InputEvent.Key carries (the same positions as CGEventFlags'). */
object Modifiers {
    const val SHIFT = 1L shl 17
    const val CONTROL = 1L shl 18
    const val OPTION = 1L shl 19
    const val COMMAND = 1L shl 20
}

// MARK: Viewport.swift

data class Viewport(val width: Double, val height: Double, val scale: Double?, val localCursor: Boolean? = null, val fps: Int? = null) : WirePayload {
    override fun toJson() = obj("width" to width, "height" to height, "scale" to scale, "localCursor" to localCursor, "fps" to fps)
    companion object {
        fun fromJson(o: JsonObj) = Viewport(o.reqDouble("width"), o.reqDouble("height"), o.optDouble("scale"), o.optBool("localCursor"), o.optInt("fps"))
    }
}

data class ClientStats(val fps: Int, val frameAgeMs: Int, val rttMs: Int, val device: String, val frameAgeMaxMs: Int? = null, val rttMaxMs: Int? = null) : WirePayload {
    override fun toJson() = obj("fps" to fps, "frameAgeMs" to frameAgeMs, "rttMs" to rttMs, "device" to device, "frameAgeMaxMs" to frameAgeMaxMs, "rttMaxMs" to rttMaxMs)
    companion object {
        fun fromJson(o: JsonObj) = ClientStats(o.reqInt("fps"), o.reqInt("frameAgeMs"), o.reqInt("rttMs"), o.reqString("device"), o.optInt("frameAgeMaxMs"), o.optInt("rttMaxMs"))
    }
}

// MARK: HostSettings.swift

data class StreamSettings(val maxFPS: Int, val bitrate: Int, val captureScale: Double, val prioritizeSpeed: Boolean, val virtualDisplay: Boolean, val directWireless: Boolean?) : WirePayload {
    override fun toJson() = obj("maxFPS" to maxFPS, "bitrate" to bitrate, "captureScale" to captureScale, "prioritizeSpeed" to prioritizeSpeed, "virtualDisplay" to virtualDisplay, "directWireless" to directWireless)
    companion object {
        fun fromJson(o: JsonObj) = StreamSettings(o.reqInt("maxFPS"), o.reqInt("bitrate"), o.reqDouble("captureScale"), o.reqBool("prioritizeSpeed"), o.reqBool("virtualDisplay"), o.optBool("directWireless"))
    }
}

data class RunningStream(val width: Int, val height: Int, val fps: Int, val mbps: Int, val onVirtualDisplay: Boolean) : WirePayload {
    override fun toJson() = obj("width" to width, "height" to height, "fps" to fps, "mbps" to mbps, "onVirtualDisplay" to onVirtualDisplay)
    companion object {
        fun fromJson(o: JsonObj) = RunningStream(o.reqInt("width"), o.reqInt("height"), o.reqInt("fps"), o.reqInt("mbps"), o.reqBool("onVirtualDisplay"))
    }
}

data class AwayQuality(val homeBitrate: Int, val homeCaptureScale: Double, val awayBitrate: Int, val awayCaptureScale: Double, val thisConnectionAway: Boolean, val awayRunning: Boolean) : WirePayload {
    override fun toJson() = obj("homeBitrate" to homeBitrate, "homeCaptureScale" to homeCaptureScale, "awayBitrate" to awayBitrate, "awayCaptureScale" to awayCaptureScale, "thisConnectionAway" to thisConnectionAway, "awayRunning" to awayRunning)
    companion object {
        fun fromJson(o: JsonObj) = AwayQuality(o.reqInt("homeBitrate"), o.reqDouble("homeCaptureScale"), o.reqInt("awayBitrate"), o.reqDouble("awayCaptureScale"), o.reqBool("thisConnectionAway"), o.reqBool("awayRunning"))
    }
}

data class LinkReport(val state: String, val withheldPerSecond: Int, val bitrate: Int, val carriedKbps: Int? = null, val suggestedBitrate: Int? = null, val suggestedCaptureScale: Double? = null) : WirePayload {
    /** A state this build does not know reads as keeping up (the compatibility floor). */
    val isBehind get() = state == "behind"
    override fun toJson() = obj("state" to state, "withheldPerSecond" to withheldPerSecond, "bitrate" to bitrate, "carriedKbps" to carriedKbps, "suggestedBitrate" to suggestedBitrate, "suggestedCaptureScale" to suggestedCaptureScale)
    companion object {
        fun fromJson(o: JsonObj) = LinkReport(o.reqString("state"), o.reqInt("withheldPerSecond"), o.reqInt("bitrate"), o.optInt("carriedKbps"), o.optInt("suggestedBitrate"), o.optDouble("suggestedCaptureScale"))
    }
}

data class HostSettingsState(
    val settings: StreamSettings, val persistent: Boolean, val virtualDisplayAvailable: Boolean, val virtualDisplayNote: String? = null,
    val softwareEncoder: Boolean, val stream: RunningStream? = null, val answering: Int? = null, val away: AwayQuality? = null, val link: LinkReport? = null,
) : WirePayload {
    override fun toJson() = obj("settings" to settings.toJson(), "persistent" to persistent, "virtualDisplayAvailable" to virtualDisplayAvailable,
        "virtualDisplayNote" to virtualDisplayNote, "softwareEncoder" to softwareEncoder, "stream" to stream?.toJson(), "answering" to answering,
        "away" to away?.toJson(), "link" to link?.toJson())
    companion object {
        fun fromJson(o: JsonObj) = HostSettingsState(StreamSettings.fromJson(o.reqObj("settings")), o.reqBool("persistent"), o.reqBool("virtualDisplayAvailable"),
            o.optString("virtualDisplayNote"), o.reqBool("softwareEncoder"), o.optObj("stream")?.let(RunningStream::fromJson), o.optInt("answering"),
            o.optObj("away")?.let(AwayQuality::fromJson), o.optObj("link")?.let(LinkReport::fromJson))
    }
}

/** Kind 17: only the fields one control changed, and a token strictly increasing per device process. */
data class HostSettingsChange(val token: Int? = null, val maxFPS: Int? = null, val bitrate: Int? = null, val captureScale: Double? = null,
                              val prioritizeSpeed: Boolean? = null, val virtualDisplay: Boolean? = null, val directWireless: Boolean? = null) : WirePayload {
    override fun toJson() = obj("token" to token, "maxFPS" to maxFPS, "bitrate" to bitrate, "captureScale" to captureScale,
        "prioritizeSpeed" to prioritizeSpeed, "virtualDisplay" to virtualDisplay, "directWireless" to directWireless)
    companion object {
        fun fromJson(o: JsonObj) = HostSettingsChange(o.optInt("token"), o.optInt("maxFPS"), o.optInt("bitrate"), o.optDouble("captureScale"),
            o.optBool("prioritizeSpeed"), o.optBool("virtualDisplay"), o.optBool("directWireless"))
    }
}

/** The bitrate presets, per 60 fps, as both ends name them (HostSettings.swift's QualityPreset), ascending. */
enum class QualityPreset(val title: String, val bitrate: Int) {
    LOW("Low", 4_000_000), EFFICIENT("Efficient", 8_000_000), BALANCED("Balanced", 15_000_000), HIGH("High", 25_000_000),
    PRO("Pro", 40_000_000), ULTRA("Ultra", 80_000_000), EXTREME("Extreme", 150_000_000);
    val label get() = "$title — ${bitrate / 1_000_000} Mbps"
    companion object { fun of(bitrate: Int) = entries.firstOrNull { it.bitrate == bitrate } }
}

/** The Mac menu's values a device may set (SettingsChoices). */
object SettingsChoices {
    val maxFPS = listOf(60, 120)
    val captureScale = listOf(2.0, 1.0)
}

// MARK: MacMenu.swift

data class MacMenuItem(val id: String? = null, val title: String? = null, val separator: Boolean? = null, val enabled: Boolean? = null,
                       val mark: String? = null, val key: String? = null, val submenu: Boolean? = null) : WirePayload {
    override fun toJson() = obj("id" to id, "title" to title, "separator" to separator, "enabled" to enabled, "mark" to mark, "key" to key, "submenu" to submenu)
    companion object {
        fun fromJson(o: JsonObj) = MacMenuItem(o.optString("id"), o.optString("title"), o.optBool("separator"), o.optBool("enabled"), o.optString("mark"), o.optString("key"), o.optBool("submenu"))
    }
}

data class MacMenu(val version: Int? = null, val app: String? = null, val bundleID: String? = null, val menus: List<MacMenuItem>? = null,
                   val answering: Int? = null, val menu: String? = null, val items: List<MacMenuItem>? = null, val more: Int? = null,
                   val pressed: Boolean? = null, val stale: Boolean? = null, val note: String? = null) : WirePayload {
    override fun toJson() = obj("version" to version, "app" to app, "bundleID" to bundleID, "menus" to menus?.map { it.toJson() }, "answering" to answering,
        "menu" to menu, "items" to items?.map { it.toJson() }, "more" to more, "pressed" to pressed, "stale" to stale, "note" to note)
    companion object {
        fun fromJson(o: JsonObj) = MacMenu(o.optInt("version"), o.optString("app"), o.optString("bundleID"), o.optObjects("menus", MacMenuItem::fromJson),
            o.optInt("answering"), o.optString("menu"), o.optObjects("items", MacMenuItem::fromJson), o.optInt("more"), o.optBool("pressed"), o.optBool("stale"), o.optString("note"))
    }
}

/** Kind 27; without an id, the subscription to the top level. */
data class FetchMenu(val version: Int? = null, val id: String? = null, val title: String? = null, val token: Int? = null) : WirePayload {
    override fun toJson() = obj("version" to version, "id" to id, "title" to title, "token" to token)
    companion object { fun fromJson(o: JsonObj) = FetchMenu(o.optInt("version"), o.optString("id"), o.optString("title"), o.optInt("token")) }
}

data class PressMenuItem(val version: Int? = null, val id: String? = null, val title: String? = null, val token: Int? = null) : WirePayload {
    override fun toJson() = obj("version" to version, "id" to id, "title" to title, "token" to token)
    companion object { fun fromJson(o: JsonObj) = PressMenuItem(o.optInt("version"), o.optString("id"), o.optString("title"), o.optInt("token")) }
}

// MARK: Pointer.swift, Gesture.swift, Clipboard.swift

data class MacPointer(val x: Double? = null, val y: Double? = null, val inside: Boolean? = null, val seen: Int? = null) : WirePayload {
    /** Where to draw the Mac's pointer: x and y when inside is true and both are finite. */
    val position: Pair<Double, Double>?
        get() = if (inside == true && x != null && y != null && x.isFinite() && y.isFinite()) x to y else null
    override fun toJson() = obj("x" to x, "y" to y, "inside" to inside, "seen" to seen)
    companion object { fun fromJson(o: JsonObj) = MacPointer(o.optDouble("x"), o.optDouble("y"), o.optBool("inside"), o.optInt("seen")) }
}

/** Kind 28, only to a host whose window list says `gestures` 1 or more. */
data class TrackpadGesture(val gesture: String, val fingers: Int? = null) : WirePayload {
    override fun toJson() = obj("gesture" to gesture, "fingers" to fingers)
    companion object {
        val names = listOf("swipeUp", "swipeDown", "swipeLeft", "swipeRight", "pinch", "spread")
        const val GENERATION = 1
        fun fromJson(o: JsonObj) = TrackpadGesture(o.reqString("gesture"), o.optInt("fingers"))
    }
}

/** Kind 32, both ways; `{}` subscribes, `stop` ends it, `text` becomes the receiver's clipboard. */
data class Clipboard(val text: String? = null, val image: ByteArray? = null, val stop: Boolean? = null) : WirePayload {
    override fun toJson() = obj("text" to text, "image" to image?.let { Base64.getEncoder().encodeToString(it) }, "stop" to stop)
    override fun equals(other: Any?) = other is Clipboard && other.text == text && other.stop == stop &&
        (other.image?.contentEquals(image ?: ByteArray(0)) ?: (image == null))
    override fun hashCode() = (text?.hashCode() ?: 0) * 31 + (stop?.hashCode() ?: 0)
    companion object {
        const val MAX_TEXT_BYTES = 256 * 1024
        const val GENERATION = 1
        fun fromJson(o: JsonObj) = Clipboard(o.optString("text"),
            o.optString("image")?.let { try { Base64.getDecoder().decode(it) } catch (_: IllegalArgumentException) { throw JsonException("'image' is not base64") } },
            o.optBool("stop"))
    }
}

// MARK: Compatibility.swift

/** Kind 23: the first message of every session connection; never on a pairing connection. */
data class Hello(val appVersion: String? = null, val build: String? = null, val protocol: Int? = null, val device: String? = null) : WirePayload {
    override fun toJson() = obj("appVersion" to appVersion, "build" to build, "protocol" to protocol, "device" to device)
    companion object { fun fromJson(o: JsonObj) = Hello(o.optString("appVersion"), o.optString("build"), o.optInt("protocol"), o.optString("device")) }
}

// MARK: Remote.swift

/** Kind 22: why the Mac is about to close this session. */
data class Goodbye(val reason: String, val message: String? = null, val minimumVersion: String? = null, val reconnect: Boolean? = null) : WirePayload {
    override fun toJson() = obj("reason" to reason, "message" to message, "minimumVersion" to minimumVersion, "reconnect" to reconnect)
    companion object {
        const val REMOVED = "removed"; const val REMOTE_OFF = "remoteOff"; const val INTERNET_OFF = "internetOff"
        const val QUIT = "quit"; const val BUSY = "busy"; const val PAIRING_REQUIRED = "pairingRequired"; const val UPDATE = "update"
        fun fromJson(o: JsonObj) = Goodbye(o.reqString("reason"), o.optString("message"), o.optString("minimumVersion"), o.optBool("reconnect"))
    }
}

/** Kind 19: a pairing connection's one message. */
data class PairRequest(val v: Int = VERSION, val method: String, val proof: String, val name: String, val model: String?, val cable: Boolean? = null) : WirePayload {
    override fun toJson() = obj("v" to v, "method" to method, "proof" to proof, "name" to name, "model" to model, "cable" to cable)
    companion object {
        const val VERSION = 1
        const val QR = "qr"; const val CODE = "code"; const val ASK = "ask"; const val CANCEL = "cancel"
        fun fromJson(o: JsonObj) = PairRequest(o.reqInt("v"), o.reqString("method"), o.reqString("proof"), o.reqString("name"), o.optString("model"), o.optBool("cable"))
    }
}

/** Kind 20: the Mac's answer to 19, after which it closes the connection. */
data class PairResult(val ok: Boolean, val proof: String? = null, val macID: String? = null, val name: String? = null, val recognitionKey: String? = null,
                      val reason: String? = null, val triesLeft: Int? = null, val retryAfter: Double? = null, val method: String? = null,
                      val message: String? = null) : WirePayload {
    override fun toJson() = obj("ok" to ok, "proof" to proof, "macID" to macID, "name" to name, "recognitionKey" to recognitionKey,
        "reason" to reason, "triesLeft" to triesLeft, "retryAfter" to retryAfter, "method" to method, "message" to message)

    /** The Mac's own words for a refusal whose reason this build does not know (SafeText, 300 characters). */
    val unknownReasonMessage: String?
        get() {
            if (ok || reason in KNOWN_REASONS) return null
            return SafeText.label(message ?: "", 300).ifEmpty { null }
        }

    companion object {
        const val CODE = "code"; const val CLOSED = "closed"; const val EXPIRED = "expired"; const val STOPPED = "stopped"; const val BUSY = "busy"
        const val SHOWN = "shown"; const val OPEN_ON_MAC = "openOnMac"; const val LOCKED = "locked"; const val CABLE = "cable"
        val KNOWN_REASONS = setOf(CODE, CLOSED, EXPIRED, STOPPED, BUSY, SHOWN, OPEN_ON_MAC, LOCKED)
        fun fromJson(o: JsonObj) = PairResult(o.reqBool("ok"), o.optString("proof"), o.optString("macID"), o.optString("name"), o.optString("recognitionKey"),
            o.optString("reason"), o.optInt("triesLeft"), o.optDouble("retryAfter"), o.optString("method"), o.optString("message"))
    }
}

data class MacAddress(val host: String, val port: Int? = null, val kind: String, val via: String) : WirePayload {
    override fun toJson() = obj("host" to host, "port" to port, "kind" to kind, "via" to via)
    companion object { fun fromJson(o: JsonObj) = MacAddress(o.reqString("host"), o.optInt("port"), o.reqString("kind"), o.reqString("via")) }
}

data class MacInfo(val v: Int = 1, val macID: String, val name: String, val issuedAt: Double, val remoteAccess: Boolean, val remotePort: Int,
                   val internet: Boolean, val addresses: List<MacAddress>) : WirePayload {
    override fun toJson() = obj("v" to v, "macID" to macID, "name" to name, "issuedAt" to issuedAt, "remoteAccess" to remoteAccess,
        "remotePort" to remotePort, "internet" to internet, "addresses" to addresses.map { it.toJson() })
    companion object {
        fun fromJson(o: JsonObj) = MacInfo(o.reqInt("v"), o.reqString("macID"), o.reqString("name"), o.reqDouble("issuedAt"), o.reqBool("remoteAccess"),
            o.reqInt("remotePort"), o.reqBool("internet"), o.reqObjects("addresses", MacAddress::fromJson))
    }
}

/** Kind 18: `info` is base64 of MacInfo's exact JSON bytes, signed by `key` (X9.63) with ECDSA P-256 / SHA-256 (`sig`, DER). */
data class SignedMacInfo(val info: String, val key: String, val sig: String) : WirePayload {
    override fun toJson() = obj("info" to info, "key" to key, "sig" to sig)

    /** The MacInfo and its signer's fingerprint when the signature verifies and the Mac ID is the key's ([MacInfoSignature]). */
    fun verified(): Pair<MacInfo, ByteArray>? = MacInfoSignature.verify(this)

    /** For display only: the MacInfo without checking anything. Never saved. */
    fun unverifiedInfo(): MacInfo? = try { MacInfo.fromJson(JsonObj.parse(Base64.getDecoder().decode(info))) } catch (_: Exception) { null }

    companion object { fun fromJson(o: JsonObj) = SignedMacInfo(o.reqString("info"), o.reqString("key"), o.reqString("sig")) }
}

/**
 * Every payload type by its Swift name: decodes one JSON payload as that type (what the vectors'
 * `type` names). Used by the wire check and the model host.
 */
object Payloads {
    val decoders: Map<String, (ByteArray) -> WirePayload> = mapOf(
        "StreamSource" to { b -> StreamSource.fromJson(JsonObj.parse(b)) },
        "WindowList" to { b -> WindowList.fromJson(JsonObj.parse(b)) },
        "AppList" to { b -> AppListPayload(AppInfo.listFromJson(Json.parse(b))) },
        "LaunchApp" to { b -> LaunchApp.fromJson(JsonObj.parse(b)) },
        "WindowCommand" to { b -> WindowCommand.fromJson(JsonObj.parse(b)) },
        "InputEvent" to { b -> InputEvent.fromJson(JsonObj.parse(b)) },
        "Viewport" to { b -> Viewport.fromJson(JsonObj.parse(b)) },
        "ClientStats" to { b -> ClientStats.fromJson(JsonObj.parse(b)) },
        "HostSettingsState" to { b -> HostSettingsState.fromJson(JsonObj.parse(b)) },
        "HostSettingsChange" to { b -> HostSettingsChange.fromJson(JsonObj.parse(b)) },
        "MacMenu" to { b -> MacMenu.fromJson(JsonObj.parse(b)) },
        "FetchMenu" to { b -> FetchMenu.fromJson(JsonObj.parse(b)) },
        "PressMenuItem" to { b -> PressMenuItem.fromJson(JsonObj.parse(b)) },
        "MacPointer" to { b -> MacPointer.fromJson(JsonObj.parse(b)) },
        "TrackpadGesture" to { b -> TrackpadGesture.fromJson(JsonObj.parse(b)) },
        "Clipboard" to { b -> Clipboard.fromJson(JsonObj.parse(b)) },
        "Hello" to { b -> Hello.fromJson(JsonObj.parse(b)) },
        "Goodbye" to { b -> Goodbye.fromJson(JsonObj.parse(b)) },
        "PairRequest" to { b -> PairRequest.fromJson(JsonObj.parse(b)) },
        "PairResult" to { b -> PairResult.fromJson(JsonObj.parse(b)) },
        "MacInfo" to { b -> MacInfo.fromJson(JsonObj.parse(b)) },
        "SignedMacInfo" to { b -> SignedMacInfo.fromJson(JsonObj.parse(b)) },
    )
}

/** Kind 5's payload, a bare array. */
data class AppListPayload(val apps: List<AppInfo>) : WirePayload {
    override fun toJson() = apps.map { it.toJson() }
}
