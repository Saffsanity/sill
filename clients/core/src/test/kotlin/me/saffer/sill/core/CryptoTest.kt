package me.saffer.sill.core

import java.io.File
import java.nio.file.Files
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Pairing and identity against the vectors Tests/checks/protocol holds the Swift code to (computed
 * in Python, docs/remote-access-plan.md §3.6), and against the system's openssl, an implementation
 * that shares no code with either.
 */
class CryptoTest {
    private val fpMac = sha256("mac".encodeToByteArray())
    private val fpDev = sha256("device".encodeToByteArray())

    @Test
    fun proofVectors() {
        assertEquals("348a629f5ceed032c3e8706ec47d9bfafb00fb4250b018dd965435ca50cb836e", fpMac.hex())
        assertEquals("263a4dbe41488fb87214b0032339dbb9f0c8da14c16dfcf13084bf3c2552eca5", fpDev.hex())
        val k = PairingProof.codeKey("482913557208", fpMac)!!
        assertEquals("e9baf879a1cc4ac8b21554df480b6c1621671319107c91e7cb05d154f649d31d", k.hex())
        assertEquals("dk7PZj4vHsAxj--1u9Vg7ehSn8a1tWc0RCG46YpFVO8", Base64Url.encode(PairingProof.deviceProof(k, fpDev, fpMac)))
        assertEquals("6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk", Base64Url.encode(PairingProof.macProof(k, fpMac, fpDev)))
        val qr = PairingProof.qrKey(ByteArray(16) { 0x22 })
        val qrD = PairingProof.deviceProof(qr, fpDev, fpMac)
        val qrM = PairingProof.macProof(qr, fpMac, fpDev)
        assertEquals("AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo", Base64Url.encode(qrD))
        assertEquals("XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE", Base64Url.encode(qrM))
        assertTrue(PairingProof.isValidMacProof(qrM, qr, fpMac, fpDev))
        assertFalse(PairingProof.isValidMacProof(qrD, qr, fpMac, fpDev))
        assertFalse(PairingProof.isValidMacProof(qrM, qr, fpDev, fpMac))
        assertTrue(PairingProof.isValidDeviceProof(qrD, qr, fpDev, fpMac))
        assertNull(PairingProof.codeKey("48291355720", fpMac))
        assertNull(PairingProof.codeKey("48291355720x", fpMac))
    }

    @Test
    fun pairingCodes() {
        assertEquals(8, PairingCode.checkDigit("48291355720".map { it - '0' }))
        assertEquals(PairingCode.Checked.Ok("482913557208"), PairingCode.check("4829 1355 7208"))
        assertEquals(PairingCode.Checked.Ok("482913557208"), PairingCode.check("4829-1355-7208"))
        assertEquals(PairingCode.Checked.Ok("482913557208"), PairingCode.check("4829 1355 7208"))
        assertEquals(PairingCode.Checked.Bad(PairingCode.Problem.LENGTH), PairingCode.check("4829 1355 720"))
        assertEquals(PairingCode.Checked.Bad(PairingCode.Problem.LENGTH), PairingCode.check("4829 1355 72O8"))
        assertEquals(PairingCode.Checked.Bad(PairingCode.Problem.LENGTH), PairingCode.check("٤٨٢٩١٣٥٥٧٢٠٨"))
        assertEquals(PairingCode.Checked.Bad(PairingCode.Problem.TYPO), PairingCode.check("4829 1355 7209"))
        assertEquals(PairingCode.Checked.Bad(PairingCode.Problem.TYPO), PairingCode.check("4829 1355 7280"))
        assertEquals("4829 1355 7208", PairingCode.grouped("482913557208"))
        repeat(500) { assertIs<PairingCode.Checked.Ok>(PairingCode.check(PairingCode.generate())) }
    }

    @Test
    fun macIdAndTags() {
        assertEquals("A3C5HR4RBV67YR21", MacId.make("50d858e0985ecc7f6041".unhex() + ByteArray(22)))
        assertEquals("A3C5HR4RBV67YR21", MacId.make(sha256("example".encodeToByteArray())))
        assertEquals("0000000000000000", MacId.make(ByteArray(32)))
        assertEquals("ZZZZZZZZZZZZZZZZ", MacId.make(ByteArray(32) { -1 }))
        assertTrue(MacId.isWellFormed("A3C5HR4RBV67YR21"))
        assertFalse(MacId.isWellFormed("A3C5HR4RBV67YR2I"))
        val rk = ByteArray(32) { 0x11 }
        assertEquals("oaKjpKWmL4V47Ctm", RecognitionTag.make(rk, "a1a2a3a4a5a6".unhex()))
        assertTrue(RecognitionTag.matches("oaKjpKWmL4V47Ctm", rk))
        assertFalse(RecognitionTag.matches("oaKjpKWmL4V47Ctm", ByteArray(32) { 0x12 }))
        assertFalse(RecognitionTag.matches("oaKjpKWmL4V47Ct", rk))
        repeat(100) { assertTrue(RecognitionTag.matches(RecognitionTag.make(rk), rk)) }
    }

    @Test
    fun base64url() {
        assertEquals(43, Base64Url.encode(ByteArray(32)).length)
        assertEquals(22, Base64Url.encode(ByteArray(16)).length)
        for (n in 1..40) { val d = ByteArray(n) { (it * 37).toByte() }; assertContentEquals(d, Base64Url.decode(Base64Url.encode(d))) }
        for (bad in listOf("AA==", "A+A", "A/A", "A", "AB", " AAA")) assertNull(Base64Url.decode(bad), bad)
    }

    @Test
    fun homeDoorTxt() {
        assertEquals(HomeDoorTxt.Door.PLAIN, HomeDoorTxt.door(mapOf("r" to "x")))
        assertEquals(HomeDoorTxt.Door.OPEN, HomeDoorTxt.door(mapOf("p" to "0")))
        assertEquals(HomeDoorTxt.Door.PAIRING_REQUIRED, HomeDoorTxt.door(mapOf("p" to "1")))
        assertEquals(HomeDoorTxt.Door.PAIRING_REQUIRED, HomeDoorTxt.door(mapOf("P" to "yes")))
        assertEquals(HomeDoorTxt.Door.PAIRING_REQUIRED, HomeDoorTxt.door(mapOf("p" to null)))
        assertEquals(HomeDoorTxt.Door.PAIRING_REQUIRED, HomeDoorTxt.door(mapOf("p" to "")))
    }

    @Test
    fun certificateAsTheMacsAndOpenSSLRead() {
        val id = Identity.generate()
        assertEquals(91, Spki.der(id.point).size)
        assertContentEquals(id.fingerprint, Spki.fingerprint(id.certificate.publicKey))
        assertContentEquals(id.keyPair.public.encoded, Spki.der(id.point))
        val der = id.certificateDER
        assertTrue(der.size in 280..340, "${der.size} bytes")
        assertEquals(3, id.certificate.version)
        id.certificate.verify(id.keyPair.public)              // the self-signature checks
        val cn = id.certificate.subjectX500Principal.name
        assertTrue(Regex("CN=[0-9a-f]{16}").matches(cn), cn)
        assertEquals(id.certificate.subjectX500Principal, id.certificate.issuerX500Principal)
        // A rebuild has a new serial and CN, and the same fingerprint.
        val again = Identity(id.keyPair)
        assertNotEquals(id.certificate.serialNumber, again.certificate.serialNumber)
        assertContentEquals(id.fingerprint, again.fingerprint)
        // Restored from its parts, the same identity; mismatched halves refused.
        assertContentEquals(id.fingerprint, Identity.restore(id.exportPrivate(), id.point)!!.fingerprint)
        assertNull(Identity.restore(id.exportPrivate(), Identity.generate().point))
        // A non-P-256 key has no fingerprint.
        val p384 = KeyPairGenerator.getInstance("EC").run { initialize(ECGenParameterSpec("secp384r1")); generateKeyPair() }
        assertNull(Spki.fingerprint(p384.public))

        val openssl = File("/usr/bin/openssl").takeIf { it.canExecute() } ?: return
        val dir = Files.createTempDirectory("sillcert").toFile()
        val file = File(dir, "c.der").apply { writeBytes(der) }
        fun run(vararg a: String): String {
            val p = ProcessBuilder(openssl.path, *a).redirectErrorStream(true).start()
            val out = p.inputStream.readBytes().decodeToString()
            assertEquals(0, p.waitFor(), out)
            return out
        }
        val pem = File(dir, "c.pem")
        run("x509", "-inform", "DER", "-in", file.path, "-out", pem.path)
        assertTrue(run("verify", "-CAfile", pem.path, "-check_ss_sig", "-no_check_time", pem.path).contains("OK"))
        val text = run("x509", "-in", pem.path, "-noout", "-text")
        assertTrue("Version: 3" in text && "ecdsa-with-SHA256" in text && "prime256v1" in text && "9999" in text, text)
        // openssl's own SPKI hash is our fingerprint.
        val spki = File(dir, "k.der")
        run("x509", "-in", pem.path, "-noout", "-pubkey", "-out", File(dir, "k.pem").path)
        run("pkey", "-pubin", "-in", File(dir, "k.pem").path, "-outform", "DER", "-out", spki.path)
        assertContentEquals(id.fingerprint, sha256(spki.readBytes()))
        dir.deleteRecursively()
    }

    @Test
    fun macInfoSignatureAndOpenSSL() {
        val mac = Identity.generate()
        val info = MacInfo(macID = MacId.make(mac.fingerprint), name = "Mac mini", issuedAt = 1_790_000_000.5, remoteAccess = true,
            remotePort = 7455, internet = false, addresses = listOf(MacAddress("100.101.102.103", null, "vpn", "Tailscale")))
        val signed = MacInfoSignature.sign(info, mac.keyPair)
        val (back, fp) = assertNotNull(signed.verified())
        assertEquals(info, back)
        assertContentEquals(mac.fingerprint, fp)
        // Another key's signature, a Mac ID that is not the key's, a changed byte: refused.
        val other = Identity.generate()
        assertNull(signed.copy(key = Base64.getEncoder().encodeToString(other.point)).verified())
        assertNull(MacInfoSignature.sign(info.copy(macID = MacId.make(other.fingerprint)), mac.keyPair).verified())
        val tampered = Base64.getDecoder().decode(signed.info).also { it[5] = (it[5] + 1).toByte() }
        assertNull(signed.copy(info = Base64.getEncoder().encodeToString(tampered)).verified())
        assertEquals(info, signed.copy(sig = "MAA=").unverifiedInfo())

        val openssl = File("/usr/bin/openssl").takeIf { it.canExecute() } ?: return
        val dir = Files.createTempDirectory("sillsig").toFile()
        File(dir, "info").writeBytes(Base64.getDecoder().decode(signed.info))
        File(dir, "sig").writeBytes(Base64.getDecoder().decode(signed.sig))
        File(dir, "key.der").writeBytes(Spki.der(mac.point))
        val p = ProcessBuilder(openssl.path, "dgst", "-sha256", "-keyform", "DER", "-verify", File(dir, "key.der").path,
            "-signature", File(dir, "sig").path, File(dir, "info").path).redirectErrorStream(true).start()
        val out = p.inputStream.readBytes().decodeToString()
        assertEquals(0, p.waitFor(), out)
        assertTrue("Verified OK" in out, out)
        dir.deleteRecursively()
    }

    @Test
    fun pairLinks() {
        val fp = Identity.generate().fingerprint
        val secret = ByteArray(16) { it.toByte() }
        val v6 = ParsedAddress("fd7a:115c:a1e0::1234", null, ParsedAddress.Kind.IPV6)
        val addrs = listOf(ParsedAddress("mac-mini.tail1234.ts.net", null, ParsedAddress.Kind.NAME), ParsedAddress("100.101.102.103", null, ParsedAddress.Kind.IPV4),
            v6, ParsedAddress("192.168.1.20", null, ParsedAddress.Kind.IPV4), ParsedAddress("home.example.net", 17455, ParsedAddress.Kind.NAME))
        val link = PairLink(fp, secret, "Tom & Jerry’s Mac=mini?", 7455, addrs)
        val url = link.url
        assertTrue(url.encodeToByteArray().size < 300, url)
        assertTrue("n=Tom%20%26%20Jerry%E2%80%99s%20Mac%3Dmini%3F" in url, url)
        val back = assertIs<PairLink.Parsed.Ok>(PairLink.parse(url)).link
        assertEquals(link, back)
        assertEquals(v6, back.addresses[2])
        assertEquals(MacId.make(fp), back.macID)
        fun with(transform: (MutableList<Pair<String, String>>) -> Unit): String {
            val items = mutableListOf("v" to "1", "m" to MacId.make(fp), "k" to Base64Url.encode(fp), "s" to Base64Url.encode(secret),
                "n" to "Mac mini", "p" to "7455", "a" to "100.101.102.103")
            transform(items)
            return "sill://pair?" + items.joinToString("&") { "${it.first}=${PairLink.escape(it.second)}" }
        }
        assertIs<PairLink.Parsed.Ok>(PairLink.parse(with { }))
        assertEquals(PairLink.Failure.Version, (PairLink.parse(with { it[0] = "v" to "2" }) as PairLink.Parsed.Bad).failure)
        assertEquals(PairLink.Failure.Field("p"), (PairLink.parse(with { it[5] = "p" to "70000" }) as PairLink.Parsed.Bad).failure)
        assertEquals(PairLink.Failure.Field("k"), (PairLink.parse(with { it.add("k" to Base64Url.encode(fp)) }) as PairLink.Parsed.Bad).failure)
        assertEquals(PairLink.Failure.MacIdMismatch, (PairLink.parse(with { it[1] = "m" to MacId.make(Identity.generate().fingerprint) }) as PairLink.Parsed.Bad).failure)
        assertEquals(PairLink.Failure.Address("1.2.3"), (PairLink.parse(with { it[6] = "a" to "1.2.3" }) as PairLink.Parsed.Bad).failure)
        assertEquals(PairLink.Failure.NotALink, (PairLink.parse("https://getsill.app") as PairLink.Parsed.Bad).failure)
        assertEquals("Mac", assertIs<PairLink.Parsed.Ok>(PairLink.parse(with { it.removeAt(4) })).link.name)
        assertEquals(5, assertIs<PairLink.Parsed.Ok>(PairLink.parse(with { l -> repeat(6) { l.add("a" to "10.0.0.$it") } })).link.addresses.size)
    }
}
