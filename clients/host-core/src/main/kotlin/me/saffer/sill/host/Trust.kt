package me.saffer.sill.host

import me.saffer.sill.core.Base64Url
import me.saffer.sill.core.Identity
import me.saffer.sill.core.IdentityStore
import me.saffer.sill.core.Json
import me.saffer.sill.core.JsonException
import me.saffer.sill.core.JsonObj
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.MacId
import me.saffer.sill.core.RecognitionTag
import me.saffer.sill.core.SafeText
import java.security.SecureRandom

/**
 * Who this host is, kept across launches as the Mac keeps its in the keychain: its P-256 key (the
 * pin every device saves; the Mac ID is its fingerprint's), and the 32-byte recognition key that
 * makes the Bonjour TXT tag `r` only paired devices can read.
 */
class HostIdentity(store: KeyValueStore) {
    val identity: Identity = IdentityStore.loadOrCreate(object : IdentityStore {
        val inner = IdentityStore.InKeyValue(Prefixed(store, "Host."))
        override fun load() = inner.load()
        override fun save(identity: Identity) = inner.save(identity)
    })
    val macID: String = MacId.make(identity.fingerprint)
    val recognitionKey: ByteArray = store.get(KEY_RECOGNITION)?.let(Base64Url::decode)?.takeIf { it.size == 32 }
        ?: ByteArray(32).also(SecureRandom()::nextBytes).also { store.put(KEY_RECOGNITION, Base64Url.encode(it)) }

    /** A fresh tag for one Bonjour registration (RecognitionTag: a new nonce each time). */
    fun tag(): String = RecognitionTag.make(recognitionKey)

    private class Prefixed(val s: KeyValueStore, val prefix: String) : KeyValueStore {
        override fun get(key: String) = s.get(prefix + key)
        override fun put(key: String, value: String?) = s.put(prefix + key, value)
    }

    companion object { const val KEY_RECOGNITION = "Host.recognitionKey" }
}

/** One device this host paired (the Mac's PairedDevice). */
data class PairedDevice(
    /** base64url of the SHA-256 of its SPKI. */
    val fingerprint: String,
    val name: String,
    val model: String?,
    /** "qr" or "code". */
    val method: String,
    val pairedAt: Double,
    val lastConnectedAt: Double? = null,
) {
    fun toJson() = linkedMapOf("fingerprint" to fingerprint, "name" to name, "model" to model, "method" to method,
        "pairedAt" to pairedAt, "lastConnectedAt" to lastConnectedAt)

    companion object {
        fun fromJson(o: JsonObj) = PairedDevice(o.reqString("fingerprint"), o.reqString("name"), o.optString("model"), o.reqString("method"),
            o.reqDouble("pairedAt"), o.optDouble("lastConnectedAt"))
    }
}

/**
 * The devices this host lets in, and Require pairing (on by default: the TXT `p` 1, only paired keys
 * at `sill/1`; off: `p` 0, any key, still over TLS). Read on the door's threads, so every read is of
 * an immutable snapshot.
 */
class TrustList(private val store: KeyValueStore) {
    @Volatile var devices: List<PairedDevice> = load(); private set
    @Volatile var requirePairing: Boolean = store.get(KEY_REQUIRE) != "0"; private set
    /** Told of every change (the UI, the door's live sessions, Bonjour's `p`). */
    @Volatile var onChange: () -> Unit = {}

    private fun load(): List<PairedDevice> = try {
        (Json.parse(store.get(KEY_DEVICES) ?: "[]") as List<*>).mapNotNull { try { PairedDevice.fromJson(JsonObj.of(it)) } catch (_: JsonException) { null } }
    } catch (_: Exception) { emptyList() }

    fun isPaired(fingerprint: ByteArray) = devices.any { it.fingerprint == Base64Url.encode(fingerprint) }

    /** Whether a session from this key is let in. */
    fun admits(fingerprint: ByteArray?) = fingerprint != null && (!requirePairing || isPaired(fingerprint))

    @Synchronized fun add(fingerprint: ByteArray, name: String, model: String?, method: String, now: Double) {
        val fp = Base64Url.encode(fingerprint)
        devices = devices.filter { it.fingerprint != fp } + PairedDevice(fp, SafeText.label(name).ifEmpty { "Device" },
            model?.let { SafeText.label(it) }, method, now)
        persist()
    }

    @Synchronized fun remove(fingerprint: String) { devices = devices.filter { it.fingerprint != fingerprint }; persist() }

    @Synchronized fun connected(fingerprint: ByteArray, now: Double) {
        val fp = Base64Url.encode(fingerprint)
        if (devices.none { it.fingerprint == fp }) return
        devices = devices.map { if (it.fingerprint == fp) it.copy(lastConnectedAt = now) else it }
        store.put(KEY_DEVICES, Json.write(devices.map { it.toJson() }))          // no onChange: nothing a door decides on moved
    }

    @Synchronized fun setRequirePairing(on: Boolean) {
        requirePairing = on
        store.put(KEY_REQUIRE, if (on) "1" else "0")
        onChange()
    }

    private fun persist() { store.put(KEY_DEVICES, Json.write(devices.map { it.toJson() })); onChange() }

    companion object {
        const val KEY_DEVICES = "Host.pairedDevices"
        const val KEY_REQUIRE = "Host.requirePairing"
    }
}
