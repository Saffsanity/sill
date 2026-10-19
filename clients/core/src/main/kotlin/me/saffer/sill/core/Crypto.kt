package me.saffer.sill.core

import java.io.ByteArrayOutputStream
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

// Pairing and identity, as Sources/StreamProtocol's Pairing.swift and RemoteIdentity.swift have
// them (docs/remote-access-plan.md §3.4–3.6): trust is a P-256 key, pinned as the SHA-256 of its
// SubjectPublicKeyInfo; names, dates and chains mean nothing. The JDK's own providers do every
// operation (Android's too), so the core needs no crypto library.

/** base64url without padding (RFC 4648 §5); decoding refuses anything not canonical. */
object Base64Url {
    fun encode(d: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(d)

    fun decode(text: String): ByteArray? {
        if (!text.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' } || text.length % 4 == 1) return null
        val d = try { Base64.getUrlDecoder().decode(text) } catch (_: IllegalArgumentException) { return null }
        return d.takeIf { encode(it) == text }
    }
}

fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }
fun String.unhex(): ByteArray = ByteArray(length / 2) { substring(2 * it, 2 * it + 2).toInt(16).toByte() }

fun sha256(vararg parts: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").run { parts.forEach { update(it) }; digest() }

fun hmacSha256(key: ByteArray, vararg parts: ByteArray): ByteArray =
    Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key, "HmacSHA256")); parts.forEach { update(it) }; doFinal() }

/** Just enough DER for one certificate and one SPKI (RemoteIdentity.swift's DER). */
internal object Der {
    val ecPublicKey = byteArrayOf(0x2A, 0x86.toByte(), 0x48, 0xCE.toByte(), 0x3D, 0x02, 0x01)
    val prime256v1 = byteArrayOf(0x2A, 0x86.toByte(), 0x48, 0xCE.toByte(), 0x3D, 0x03, 0x01, 0x07)
    val ecdsaWithSHA256 = byteArrayOf(0x2A, 0x86.toByte(), 0x48, 0xCE.toByte(), 0x3D, 0x04, 0x03, 0x02)
    val commonName = byteArrayOf(0x55, 0x04, 0x03)

    fun length(n: Int): ByteArray {
        if (n < 0x80) return byteArrayOf(n.toByte())
        val bytes = ArrayList<Byte>()
        var v = n
        while (v > 0) { bytes.add(0, (v and 0xFF).toByte()); v = v ushr 8 }
        return byteArrayOf((0x80 or bytes.size).toByte()) + bytes.toByteArray()
    }
    fun tlv(tag: Int, content: ByteArray) = byteArrayOf(tag.toByte()) + length(content.size) + content
    fun sequence(vararg parts: ByteArray) = tlv(0x30, concat(*parts))
    fun set(vararg parts: ByteArray) = tlv(0x31, concat(*parts))
    fun oid(b: ByteArray) = tlv(0x06, b)
    fun bitString(b: ByteArray) = tlv(0x03, byteArrayOf(0) + b)
    fun integer(raw: ByteArray): ByteArray {
        var b = if (raw.isEmpty()) byteArrayOf(0) else raw
        while (b.size > 1 && b[0] == 0.toByte() && b[1].toInt() and 0x80 == 0) b = b.copyOfRange(1, b.size)
        if (b[0].toInt() and 0x80 != 0) b = byteArrayOf(0) + b
        return tlv(0x02, b)
    }
    fun concat(vararg parts: ByteArray): ByteArray = ByteArrayOutputStream().also { o -> parts.forEach { o.write(it) } }.toByteArray()
}

/** The SubjectPublicKeyInfo of a P-256 key and its SHA-256, the fingerprint every pin compares. */
object Spki {
    fun der(point: ByteArray): ByteArray =
        Der.sequence(Der.sequence(Der.oid(Der.ecPublicKey), Der.oid(Der.prime256v1)), Der.bitString(point))

    fun fingerprint(point: ByteArray): ByteArray = sha256(der(point))

    /** The 65-byte uncompressed point (04 ‖ X ‖ Y) of a P-256 public key; null for any other key. */
    fun point(key: PublicKey): ByteArray? {
        val ec = key as? ECPublicKey ?: return null
        if (ec.params.curve.field.fieldSize != 256) return null
        fun pad(v: java.math.BigInteger): ByteArray? {
            val b = v.toByteArray().let { if (it.size == 33 && it[0] == 0.toByte()) it.copyOfRange(1, 33) else it }
            return if (b.size > 32) null else ByteArray(32 - b.size) + b
        }
        val x = pad(ec.w.affineX) ?: return null
        val y = pad(ec.w.affineY) ?: return null
        // Only prime256v1: its SPKI is exactly ours.
        if (!ec.encoded.contentEquals(der(byteArrayOf(4) + x + y))) return null
        return byteArrayOf(4) + x + y
    }

    fun fingerprint(key: PublicKey): ByteArray? = point(key)?.let(::fingerprint)

    /** A P-256 public key from its 65-byte point; null when it is not one. */
    fun publicKey(point: ByteArray): PublicKey? {
        if (point.size != 65 || point[0] != 4.toByte()) return null
        return try { KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(der(point))) } catch (_: Exception) { null }
    }
}

/** The Mac ID: Crockford base32 of the fingerprint's first 10 bytes, 16 characters. */
object MacId {
    const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    fun make(fingerprint: ByteArray): String {
        if (fingerprint.size < 10) return ""
        val sb = StringBuilder()
        var buffer = 0; var bits = 0
        for (i in 0 until 10) {
            buffer = (buffer shl 8) or (fingerprint[i].toInt() and 0xFF); bits += 8
            while (bits >= 5) { bits -= 5; sb.append(ALPHABET[(buffer shr bits) and 31]) }
            buffer = buffer and ((1 shl bits) - 1)
        }
        return sb.toString()
    }

    fun isWellFormed(text: String) = text.length == 16 && text.all { it in ALPHABET }

    /** "5KD2Q7": the first characters of a fingerprint's Mac ID form, for logs and lists. */
    fun shortName(fingerprint: ByteArray) = make(fingerprint).take(6)
}

/**
 * The certificate a device presents (RemoteIdentity.swift's SelfSignedCertificate, the same bytes
 * in the same order): X.509 v3, no extensions, a 16-byte random serial, issuer = subject = a CN of
 * 16 random hex characters, valid from 2026-01-01 to 9999-12-31, ECDSA with SHA-256. The pin is the
 * key, so it is rebuilt from the stored key at every launch and never stored.
 */
object SelfSignedCertificate {
    fun make(keyPair: KeyPair, random: SecureRandom = SecureRandom()): ByteArray {
        val point = Spki.point(keyPair.public) ?: throw IllegalArgumentException("not a P-256 key")
        val cn = ByteArray(8).also(random::nextBytes)
        val serial = ByteArray(16).also(random::nextBytes)
        serial[0] = ((serial[0].toInt() and 0x7F) or 0x01).toByte()
        val name = Der.sequence(Der.set(Der.sequence(Der.oid(Der.commonName), Der.tlv(0x0C, cn.hex().encodeToByteArray()))))
        val algorithm = Der.sequence(Der.oid(Der.ecdsaWithSHA256))
        val tbs = Der.sequence(
            Der.tlv(0xA0, Der.integer(byteArrayOf(2))),
            Der.integer(serial),
            algorithm,
            name,
            Der.sequence(Der.tlv(0x17, "260101000000Z".encodeToByteArray()), Der.tlv(0x18, "99991231235959Z".encodeToByteArray())),
            name,
            Spki.der(point),
        )
        val sig = Signature.getInstance("SHA256withECDSA").run { initSign(keyPair.private); update(tbs); sign() }
        return Der.sequence(tbs, algorithm, Der.bitString(sig))
    }
}

/** A P-256 key pair and the certificate made from it: what this client presents in TLS. */
class Identity(val keyPair: KeyPair) {
    val point: ByteArray = Spki.point(keyPair.public) ?: throw IllegalArgumentException("not a P-256 key")
    val fingerprint: ByteArray = Spki.fingerprint(point)
    val certificateDER: ByteArray = SelfSignedCertificate.make(keyPair)
    val certificate: java.security.cert.X509Certificate =
        java.security.cert.CertificateFactory.getInstance("X.509").generateCertificate(certificateDER.inputStream()) as java.security.cert.X509Certificate

    /** The private key as PKCS#8, for a store. */
    fun exportPrivate(): ByteArray = keyPair.private.encoded

    companion object {
        fun generate(): Identity = Identity(KeyPairGenerator.getInstance("EC").run { initialize(ECGenParameterSpec("secp256r1")); generateKeyPair() })

        /** An identity back from [exportPrivate] and its public point. */
        fun restore(pkcs8: ByteArray, point: ByteArray): Identity? = try {
            val kf = KeyFactory.getInstance("EC")
            val priv: PrivateKey = kf.generatePrivate(PKCS8EncodedKeySpec(pkcs8))
            val pub = Spki.publicKey(point) ?: return null
            // The halves must belong together: a signature by one checks with the other.
            val probe = "sill-identity".encodeToByteArray()
            val sig = Signature.getInstance("SHA256withECDSA").run { initSign(priv); update(probe); sign() }
            val ok = Signature.getInstance("SHA256withECDSA").run { initVerify(pub); update(probe); verify(sig) }
            if (ok) Identity(KeyPair(pub, priv)) else null
        } catch (_: Exception) { null }
    }
}

/** The 12-digit typed code: 11 random digits, then a Damm check digit (Pairing.swift's PairingCode). */
object PairingCode {
    private val table = arrayOf(
        intArrayOf(0, 3, 1, 7, 5, 9, 8, 6, 4, 2), intArrayOf(7, 0, 9, 2, 1, 5, 4, 8, 6, 3), intArrayOf(4, 2, 0, 6, 8, 7, 1, 3, 5, 9),
        intArrayOf(1, 7, 5, 0, 9, 8, 3, 4, 2, 6), intArrayOf(6, 1, 2, 3, 0, 4, 5, 9, 7, 8), intArrayOf(3, 6, 7, 4, 2, 0, 9, 5, 8, 1),
        intArrayOf(5, 8, 6, 9, 7, 2, 0, 1, 3, 4), intArrayOf(8, 9, 4, 5, 3, 6, 2, 0, 1, 7), intArrayOf(9, 4, 3, 8, 6, 1, 7, 2, 0, 5),
        intArrayOf(2, 5, 8, 1, 4, 3, 6, 7, 9, 0),
    )
    const val LENGTH = 12

    fun checkDigit(digits: List<Int>): Int = digits.fold(0) { i, d -> table[i][d] }

    /** A fresh code (the Mac makes these; here for tests and a model host). */
    fun generate(random: SecureRandom = SecureRandom()): String {
        val digits = ArrayList<Int>()
        while (digits.size < LENGTH - 1) { val b = random.nextInt(256); if (b < 250) digits.add(b % 10) }
        return (digits + checkDigit(digits)).joinToString("")
    }

    enum class Problem { LENGTH, TYPO }

    sealed class Checked {
        data class Ok(val code: String) : Checked()
        data class Bad(val problem: Problem) : Checked()
    }

    /** Spaces, hyphens and no-break spaces removed; exactly 12 ASCII digits; the check digit valid. */
    fun check(input: String): Checked {
        val kept = input.filter { it != ' ' && it != '-' && it != ' ' }
        if (SafeText.characterCount(kept) != LENGTH || !kept.all { it in '0'..'9' }) return Checked.Bad(Problem.LENGTH)
        if (checkDigit(kept.map { it - '0' }) != 0) return Checked.Bad(Problem.TYPO)
        return Checked.Ok(kept)
    }

    /** "4829 1355 7208". */
    fun grouped(code: String) = code.chunked(4).joinToString(" ")
}

/**
 * The keys and proofs of one pairing exchange (Pairing.swift's PairingProof). Each side takes the
 * other's fingerprint from the TLS session, never from a message.
 * - QR: the key is the link's 16-byte secret.
 * - Typed: K = PBKDF2-HMAC-SHA256(the 12 digits, "sill-pair-v1" ‖ fp_mac, 600,000 rounds, 32 bytes).
 * - proof_D = HMAC(key, "sill-pair-v1 device" ‖ 0 ‖ fp_device ‖ fp_mac); proof_M with "mac" and the two swapped.
 */
object PairingProof {
    const val ROUNDS = 600_000
    private const val LABEL = "sill-pair-v1"

    fun codeKey(code: String, macFingerprint: ByteArray): ByteArray? {
        if (code.length != PairingCode.LENGTH || !code.all { it in '0'..'9' }) return null
        val spec = PBEKeySpec(code.toCharArray(), LABEL.encodeToByteArray() + macFingerprint, ROUNDS, 256)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }

    fun qrKey(secret: ByteArray) = secret

    private fun deviceMessage(fpDevice: ByteArray, fpMac: ByteArray) = "$LABEL device".encodeToByteArray() + byteArrayOf(0) + fpDevice + fpMac
    private fun macMessage(fpMac: ByteArray, fpDevice: ByteArray) = "$LABEL mac".encodeToByteArray() + byteArrayOf(0) + fpMac + fpDevice

    fun deviceProof(key: ByteArray, deviceFingerprint: ByteArray, macFingerprint: ByteArray) = hmacSha256(key, deviceMessage(deviceFingerprint, macFingerprint))
    fun macProof(key: ByteArray, macFingerprint: ByteArray, deviceFingerprint: ByteArray) = hmacSha256(key, macMessage(macFingerprint, deviceFingerprint))

    fun isValidDeviceProof(proof: ByteArray, key: ByteArray, deviceFingerprint: ByteArray, macFingerprint: ByteArray) =
        MessageDigest.isEqual(proof, deviceProof(key, deviceFingerprint, macFingerprint))

    fun isValidMacProof(proof: ByteArray, key: ByteArray, macFingerprint: ByteArray, deviceFingerprint: ByteArray) =
        MessageDigest.isEqual(proof, macProof(key, macFingerprint, deviceFingerprint))
}

/** The Bonjour TXT record's `r`: `p ‖ HMAC-SHA256(recognitionKey, "sill-tag-v1" ‖ p)[0..<6]`, base64url, 16 characters. */
object RecognitionTag {
    const val TXT_KEY = "r"
    private const val LABEL = "sill-tag-v1"

    fun make(recognitionKey: ByteArray, nonce: ByteArray? = null): String {
        val p = if (nonce != null && nonce.size == 6) nonce else ByteArray(6).also(SecureRandom()::nextBytes)
        return Base64Url.encode(p + mac(recognitionKey, p))
    }

    fun matches(tag: String, recognitionKey: ByteArray): Boolean {
        val b = Base64Url.decode(tag) ?: return false
        if (b.size != 12) return false
        return MessageDigest.isEqual(mac(recognitionKey, b.copyOfRange(0, 6)), b.copyOfRange(6, 12))
    }

    private fun mac(key: ByteArray, nonce: ByteArray) = hmacSha256(key, LABEL.encodeToByteArray(), nonce).copyOfRange(0, 6)
}

/** The Bonjour TXT record's `p`: how the home door speaks (Pairing.swift's HomeDoorTXT). */
object HomeDoorTxt {
    const val KEY = "p"
    enum class Door { PLAIN, PAIRING_REQUIRED, OPEN }

    /**
     * The door a received record describes. `txt` maps each key (as received) to its value, null for
     * a key without '=' (a boolean attribute). Keys are case-insensitive (RFC 6763 §6.4).
     */
    fun door(txt: Map<String, String?>): Door {
        val entry = txt.entries.firstOrNull { it.key.equals(KEY, ignoreCase = true) } ?: return Door.PLAIN
        return if (entry.value == "0") Door.OPEN else Door.PAIRING_REQUIRED
    }
}

/**
 * The QR code's content, also a link another app hands over (always behind a confirmation):
 * `sill://pair?v=1&m=<macID>&k=<fp>&s=<secret>&n=<name>&p=<port>&a=<address>…` (Pairing.swift's PairLink).
 */
class PairLink(val fingerprint: ByteArray, val secret: ByteArray, name: String, val port: Int, addresses: List<ParsedAddress>) {
    val macID = MacId.make(fingerprint)
    val name: String = SafeText.label(name, NAME_LIMIT).ifEmpty { "Mac" }
    val addresses: List<ParsedAddress> = addresses.take(MAX_ADDRESSES)

    val url: String get() {
        val items = mutableListOf("v" to "1", "m" to macID, "k" to Base64Url.encode(fingerprint), "s" to Base64Url.encode(secret), "n" to name, "p" to port.toString())
        items += addresses.map { "a" to it.text }
        return "sill://pair?" + items.joinToString("&") { "${it.first}=${escape(it.second)}" }
    }

    override fun equals(other: Any?) = other is PairLink && other.fingerprint.contentEquals(fingerprint) && other.secret.contentEquals(secret) &&
        other.name == name && other.port == port && other.addresses == addresses
    override fun hashCode() = fingerprint.contentHashCode()

    sealed class Failure {
        object NotALink : Failure()
        object Version : Failure()
        data class Field(val key: String) : Failure()
        object MacIdMismatch : Failure()
        data class Address(val text: String) : Failure()
    }

    sealed class Parsed {
        data class Ok(val link: PairLink) : Parsed()
        data class Bad(val failure: Failure) : Parsed()
    }

    companion object {
        const val MAX_ADDRESSES = 5
        const val NAME_LIMIT = 64

        private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:"

        fun escape(s: String): String {
            val sb = StringBuilder()
            for (b in s.encodeToByteArray()) {
                val c = (b.toInt() and 0xFF).toChar()
                if (b >= 0 && c in UNRESERVED) sb.append(c) else sb.append('%').append("%02X".format(b.toInt() and 0xFF))
            }
            return sb.toString()
        }

        private fun unescape(s: String): String? {
            val o = ByteArrayOutputStream()
            var i = 0
            while (i < s.length) {
                val c = s[i]
                if (c == '%') {
                    if (i + 3 > s.length) return null
                    val v = s.substring(i + 1, i + 3).toIntOrNull(16) ?: return null
                    o.write(v); i += 3
                } else { o.write(c.toString().encodeToByteArray()); i++ }
            }
            return try { o.toByteArray().decodeToString(throwOnInvalidSequence = true) } catch (_: CharacterCodingException) { null }
        }

        fun parse(text: String): Parsed {
            val t = text.trim { SafeText.isWhiteSpace(it.code) }
            val schemeEnd = t.indexOf("://")
            if (schemeEnd < 0 || !t.substring(0, schemeEnd).equals("sill", true)) return Parsed.Bad(Failure.NotALink)
            val rest = t.substring(schemeEnd + 3)
            val q = rest.indexOf('?')
            if (q < 0) return Parsed.Bad(Failure.NotALink)
            val hostPath = rest.substring(0, q)
            val host = hostPath.substringBefore('/')
            val path = hostPath.substring(host.length)
            if (!host.equals("pair", true) || (path.isNotEmpty() && path != "/")) return Parsed.Bad(Failure.NotALink)
            val query = rest.substring(q + 1).substringBefore('#')
            val items = ArrayList<Pair<String, String?>>()
            if (query.isNotEmpty()) for (part in query.split("&")) {
                val eq = part.indexOf('=')
                val k = unescape(if (eq < 0) part else part.substring(0, eq)) ?: return Parsed.Bad(Failure.NotALink)
                val v = if (eq < 0) null else unescape(part.substring(eq + 1)) ?: return Parsed.Bad(Failure.NotALink)
                items.add(k to v)
            }
            fun single(key: String): String? {
                val values = items.filter { it.first == key }
                return if (values.size == 1 && !values[0].second.isNullOrEmpty()) values[0].second else null
            }
            val v = single("v") ?: return Parsed.Bad(Failure.Version)
            if (v != "1") return Parsed.Bad(Failure.Version)
            val m = single("m")?.takeIf(MacId::isWellFormed) ?: return Parsed.Bad(Failure.Field("m"))
            val fp = single("k")?.let(Base64Url::decode)?.takeIf { it.size == 32 } ?: return Parsed.Bad(Failure.Field("k"))
            val secret = single("s")?.let(Base64Url::decode)?.takeIf { it.size == 16 } ?: return Parsed.Bad(Failure.Field("s"))
            val port = single("p")?.takeIf { it.length <= 5 && it.all { c -> c in '0'..'9' } }?.toInt()?.takeIf { it in 1..65535 }
                ?: return Parsed.Bad(Failure.Field("p"))
            if (m != MacId.make(fp)) return Parsed.Bad(Failure.MacIdMismatch)
            val addresses = ArrayList<ParsedAddress>()
            for ((k, value) in items) if (k == "a") {
                val r = value?.let(AddressParser::parse)
                if (r !is AddressParser.Result.Ok) return Parsed.Bad(Failure.Address(value ?: ""))
                addresses.add(r.address)
            }
            val name = items.firstOrNull { it.first == "n" }?.second ?: ""
            return Parsed.Ok(PairLink(fp, secret, name, port, addresses))
        }
    }
}

/** Kind 18's signature (Remote.swift's SignedMacInfo.signing and verified). */
object MacInfoSignature {
    fun sign(info: MacInfo, keyPair: KeyPair): SignedMacInfo {
        val bytes = info.bytes()
        val point = Spki.point(keyPair.public) ?: throw IllegalArgumentException("not a P-256 key")
        val sig = Signature.getInstance("SHA256withECDSA").run { initSign(keyPair.private); update(bytes); sign() }
        val b64 = Base64.getEncoder()
        return SignedMacInfo(b64.encodeToString(bytes), b64.encodeToString(point), b64.encodeToString(sig))
    }

    fun verify(s: SignedMacInfo): Pair<MacInfo, ByteArray>? = try {
        val dec = Base64.getDecoder()
        val bytes = dec.decode(s.info)
        val point = dec.decode(s.key)
        val sig = dec.decode(s.sig)
        val pub = Spki.publicKey(point)
        if (pub == null) null
        else {
            val ok = Signature.getInstance("SHA256withECDSA").run { initVerify(pub); update(bytes); verify(sig) }
            val info = if (ok) MacInfo.fromJson(JsonObj.parse(bytes)) else null
            val fp = Spki.fingerprint(point)
            if (info != null && info.macID == MacId.make(fp)) info to fp else null
        }
    } catch (_: Exception) { null }
}
