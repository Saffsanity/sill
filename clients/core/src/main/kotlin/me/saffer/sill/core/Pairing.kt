package me.saffer.sill.core

import java.io.IOException
import java.net.SocketAddress

/**
 * A Mac this client paired with (iOSClient/SavedMacs.swift's SavedMac): its pin, its recognition
 * key, and how to reach it from afar (kind 18's addresses).
 */
data class SavedMac(
    val macID: String,
    /** base64url of the SHA-256 of its SPKI: the pin. */
    val fingerprint: String,
    val name: String,
    /** base64url of 32 bytes: resolves its Bonjour TXT tag `r`. */
    val recognitionKey: String,
    val remotePort: Int = DEFAULT_REMOTE_PORT,
    val addresses: List<MacAddress> = emptyList(),
    /** Addresses typed in this client ("100.101.102.103:7455"). */
    val typedAddresses: List<String> = emptyList(),
    val infoIssuedAt: Double = 0.0,
    val bonjourName: String? = null,
    val pairedAt: Double,
    /** "qr", "code" or "cable". */
    val method: String,
    val lastConnectedAt: Double? = null,
    /** "host:port" where it last answered: the address a link or typed pairing reached, or the last session's. */
    val lastWorked: String? = null,
    /** The Mac removed this client (a goodbye "removed", or its key refused): pair again. */
    val revoked: Boolean = false,
    /** The Mac answered with another key than the pin: set up again, pair again. */
    val newKey: Boolean = false,
) {
    val fingerprintBytes: ByteArray get() = Base64Url.decode(fingerprint)!!
    val recognitionKeyBytes: ByteArray get() = Base64Url.decode(recognitionKey)!!

    fun toJson(): Map<String, Any?> = linkedMapOf("macID" to macID, "fingerprint" to fingerprint, "name" to name, "recognitionKey" to recognitionKey,
        "remotePort" to remotePort, "addresses" to addresses.map { it.toJson() }, "typedAddresses" to typedAddresses, "infoIssuedAt" to infoIssuedAt,
        "bonjourName" to bonjourName, "pairedAt" to pairedAt, "method" to method, "lastConnectedAt" to lastConnectedAt,
        "lastWorked" to lastWorked, "revoked" to revoked.takeIf { it }, "newKey" to newKey.takeIf { it })

    companion object {
        const val DEFAULT_REMOTE_PORT = 7455

        fun fromJson(o: JsonObj) = SavedMac(o.reqString("macID"), o.reqString("fingerprint"), o.reqString("name"), o.reqString("recognitionKey"),
            o.optInt("remotePort") ?: DEFAULT_REMOTE_PORT, o.optObjects("addresses", MacAddress::fromJson) ?: emptyList(),
            o.optList("typedAddresses")?.map { it as String } ?: emptyList(), o.optDouble("infoIssuedAt") ?: 0.0, o.optString("bonjourName"),
            o.reqDouble("pairedAt"), o.reqString("method"), o.optDouble("lastConnectedAt"), o.optString("lastWorked"), o.optBool("revoked") ?: false, o.optBool("newKey") ?: false)
    }
}

/** Where a client keeps small values: the desktop's file, Android's SharedPreferences. */
interface KeyValueStore {
    fun get(key: String): String?
    fun put(key: String, value: String?)

    class Memory : KeyValueStore {
        private val m = HashMap<String, String>()
        @Synchronized override fun get(key: String) = m[key]
        @Synchronized override fun put(key: String, value: String?) { if (value == null) m.remove(key) else m[key] = value }
    }
}

/** The saved Macs, at most 16, the least recently used dropped first; a record whose Mac ID is not its pin's is never kept. */
class SavedMacs(private val store: KeyValueStore) {
    @get:Synchronized var all: List<SavedMac> = load()
        private set

    private fun load(): List<SavedMac> = try {
        val text = store.get(KEY) ?: return emptyList()
        (Json.parse(text) as List<*>).mapNotNull { v ->
            try { SavedMac.fromJson(JsonObj.of(v)).takeIf { s -> Base64Url.decode(s.fingerprint)?.let { MacId.make(it) } == s.macID } } catch (_: JsonException) { null }
        }
    } catch (_: Exception) { emptyList() }

    @Synchronized fun save(mac: SavedMac) {
        val rest = all.filter { it.macID != mac.macID }
        all = (listOf(mac) + rest).sortedByDescending { it.lastConnectedAt ?: it.pairedAt }.take(LIMIT)
        persist()
    }

    @Synchronized fun remove(macID: String) { all = all.filter { it.macID != macID }; persist() }

    @Synchronized fun update(macID: String, change: (SavedMac) -> SavedMac) {
        all.firstOrNull { it.macID == macID }?.let { save(change(it)) }
    }

    fun byID(macID: String) = all.firstOrNull { it.macID == macID }

    /** The saved Mac whose recognition key made this TXT tag. */
    fun recognize(tag: String?): SavedMac? = tag?.let { t -> all.firstOrNull { RecognitionTag.matches(t, it.recognitionKeyBytes) } }

    /**
     * A verified kind 18 for a saved Mac: its pin must be the signer, and only a newer one replaces
     * the addresses (SavedMacs.refreshed). An empty address list, or Remote Access off, keeps the
     * saved ones (a Mac that has not looked yet).
     */
    @Synchronized fun refresh(info: MacInfo, signer: ByteArray): Boolean {
        val s = all.firstOrNull { it.macID == info.macID } ?: return false
        if (!s.fingerprintBytes.contentEquals(signer) || info.issuedAt <= s.infoIssuedAt) return false
        save(s.copy(name = SafeText.label(info.name).ifEmpty { s.name }, remotePort = info.remotePort, infoIssuedAt = info.issuedAt,
            addresses = if (info.addresses.isEmpty() || !info.remoteAccess) s.addresses else info.addresses))
        return true
    }

    private fun persist() = store.put(KEY, Json.write(all.map { it.toJson() }))

    companion object {
        const val KEY = "Sill.savedMacs"
        const val LIMIT = 16
    }
}

/** The outcome of one pairing exchange. */
sealed class PairOutcome {
    /** Paired: the saved record, and the address the pairing reached. */
    data class Paired(val mac: SavedMac, val address: SocketAddress? = null) : PairOutcome()
    /** The Mac said no, or not yet: its reason, and words to show. */
    data class Refused(val result: PairResult, val words: String, val macFingerprint: ByteArray?) : PairOutcome()
    data class Failed(val error: IOException, val words: String) : PairOutcome()
}

/**
 * Pairing on a `sill-pair/1` connection (StreamClient+Home.swift, docs/home-pairing-plan.md): one
 * kind 19 out, one kind 20 back, the Mac closes. The Mac's fingerprint is the TLS session's, never a
 * message's, so a relay in the middle makes this client's proof bind the wrong key.
 */
class Pairing(private val identity: Identity, private val client: ClientInfo, private val clock: Clock = Clock.System) {
    /** What a Mac answered on one pairing connection, and the key it presented there. */
    class Exchange(val result: PairResult, val macFingerprint: ByteArray)

    fun exchange(address: SocketAddress, trust: Trust, request: PairRequest): Exchange {
        val c = SillTls.dial(address, identity, SillTls.PAIRING_ALPN, trust)
        c.use {
            it.output.write(StreamMessage.json(Kind.PAIR_REQUEST, request.toJson()).serialized())
            it.output.flush()
            val reader = MessageReader(it.input, cap = { StreamMessage.MAX_PAIRING_PAYLOAD.toLong() })
            val m = try { reader.next() } catch (e: IOException) { throw SillTls.classifyAfterHandshake(e) }
                ?: throw IOException("the host closed the pairing connection without an answer")
            if (m.kind != Kind.PAIR_RESULT || m.payload.isEmpty()) throw IOException("the host answered with kind ${m.kind}")
            return Exchange(PairResult.fromJson(JsonObj.parse(m.payload)), it.peerFingerprint ?: throw IOException("no Mac key"))
        }
    }

    /** "Pair me": the Mac shows its code by itself (an answer "shown"), or says why not. */
    fun ask(address: SocketAddress, trust: Trust = Trust.AnyKey): Exchange =
        exchange(address, trust, PairRequest(method = PairRequest.ASK, proof = "", name = client.name, model = client.model))

    /** The code this client's ask put up is no longer needed. */
    fun cancel(address: SocketAddress, macFingerprint: ByteArray) {
        try { exchange(address, Trust.Pinned(macFingerprint), PairRequest(method = PairRequest.CANCEL, proof = "", name = client.name, model = client.model)) }
        catch (_: IOException) {}
    }

    /** The typed path: the code the Mac shows, at the Mac this client asked (its key pinned when known). */
    fun pairWithCode(address: SocketAddress, code: String, macFingerprint: ByteArray?, bonjourName: String? = null): PairOutcome {
        val checked = PairingCode.check(code)
        if (checked is PairingCode.Checked.Bad) return PairOutcome.Failed(IOException("bad code"), PairingWords.codeProblem(checked.problem))
        val digits = (checked as PairingCode.Checked.Ok).code
        // The key needs the Mac's fingerprint first: without one known, learn it from a first look.
        val fp = macFingerprint ?: try { ask(address).macFingerprint } catch (e: IOException) { return failed(e) }
        val key = PairingProof.codeKey(digits, fp) ?: return PairOutcome.Failed(IOException("bad code"), PairingWords.codeProblem(PairingCode.Problem.LENGTH))
        return prove(address, Trust.Pinned(fp), key, PairRequest.CODE, bonjourName)
    }

    /** The QR path: a pairing link's secret, at each of the given addresses in turn (pinned to the link's key). */
    fun pairWithLink(link: PairLink, addresses: List<SocketAddress>, bonjourName: String? = null): PairOutcome {
        var last: PairOutcome = PairOutcome.Failed(IOException("no address"), "${link.name} didn’t answer at any of its addresses.")
        for (a in addresses) {
            last = prove(a, Trust.Pinned(link.fingerprint), PairingProof.qrKey(link.secret), PairRequest.QR, bonjourName)
            if (last !is PairOutcome.Failed) return last
        }
        return last
    }

    private fun prove(address: SocketAddress, trust: Trust, key: ByteArray, method: String, bonjourName: String?, retried: Boolean = false): PairOutcome {
        val pin = (trust as Trust.Pinned).fingerprint
        val proof = Base64Url.encode(PairingProof.deviceProof(key, identity.fingerprint, pin))
        val ex = try { exchange(address, trust, PairRequest(method = method, proof = proof, name = client.name, model = client.model)) }
        catch (e: IOException) { return failed(e) }
        val r = ex.result
        if (!r.ok) {
            if (r.reason == PairResult.BUSY && !retried) {
                Thread.sleep(((r.retryAfter ?: 1.0).coerceIn(0.2, 10.0) * 1000).toLong())
                return prove(address, trust, key, method, bonjourName, true)
            }
            return PairOutcome.Refused(r, PairingWords.refusal(r, client.noun), ex.macFingerprint)
        }
        val proofM = r.proof?.let(Base64Url::decode)
        val rk = r.recognitionKey?.let(Base64Url::decode)
        if (proofM == null || !PairingProof.isValidMacProof(proofM, key, ex.macFingerprint, identity.fingerprint) ||
            r.macID != MacId.make(ex.macFingerprint) || rk == null || rk.size != 32) {
            return PairOutcome.Failed(IOException("the host's proof did not check"), "That host couldn’t prove it showed the code. Nothing was saved.")
        }
        return PairOutcome.Paired(address = address, mac = SavedMac(macID = r.macID, fingerprint = Base64Url.encode(ex.macFingerprint),
            name = SafeText.label(r.name ?: "").ifEmpty { "Host" }, recognitionKey = Base64Url.encode(rk), bonjourName = bonjourName,
            pairedAt = clock.wall(), method = method))
    }

    private fun failed(e: IOException) = PairOutcome.Failed(e, PairingWords.dialFailure(e))
}

/** The words pairing shows (AddMacCard and PairingOverlay's, for these clients). */
object PairingWords {
    fun codeProblem(p: PairingCode.Problem) = when (p) {
        PairingCode.Problem.LENGTH -> "A code has 12 digits."
        PairingCode.Problem.TYPO -> "That code has a typo. Check it against your host."
    }

    fun refusal(r: PairResult, noun: String): String {
        r.unknownReasonMessage?.let { return it }
        return when (r.reason) {
            PairResult.CODE -> "That code didn’t match." + (r.triesLeft?.let { " $it ${if (it == 1) "try" else "tries"} left." } ?: "")
            PairResult.CLOSED -> "The host isn’t showing a code. Choose Pair a Device… in Sill on the host."
            PairResult.EXPIRED -> "That code expired. Choose New Code on the host."
            PairResult.STOPPED -> "Too many wrong codes. Choose New Code on the host."
            PairResult.BUSY -> "The host is busy. Try again in a moment."
            PairResult.SHOWN -> "Enter the code your host shows now, or paste its pairing link."
            PairResult.OPEN_ON_MAC -> "On the host, choose Pair a Device… in Sill’s menu, then enter its code here."
            PairResult.LOCKED -> "Unlock the host, then try again."
            else -> "The host didn’t pair this $noun."
        }
    }

    fun dialFailure(e: IOException) = when (e) {
        is DialFailure.PinRefused -> "That isn’t the host the code or link came from."
        is DialFailure.KeyRefused -> "The host refused this device."
        is DialFailure.NotSill -> "That address isn’t a host running Sill, or its Sill is too old to pair. Update Sill on the host."
        is DialFailure.Unreachable -> "The host didn’t answer. Check that Sill is open on it and that both are on the same network."
        else -> "Pairing failed: ${e.message}"
    }
}
