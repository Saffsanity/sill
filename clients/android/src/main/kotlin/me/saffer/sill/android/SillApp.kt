package me.saffer.sill.android

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import me.saffer.sill.core.ClientInfo
import me.saffer.sill.core.ClientListener
import me.saffer.sill.core.GoodbyePolicy
import me.saffer.sill.core.Identity
import me.saffer.sill.core.IdentityStore
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.MacRow
import me.saffer.sill.core.PairingPrompt
import me.saffer.sill.core.ReplayingRouter
import me.saffer.sill.core.SillClient
import me.saffer.sill.core.SillSession
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The app's settings and saved Macs, in its own SharedPreferences (the app's sandbox; no backup). */
class PrefsStore(private val prefs: SharedPreferences) : KeyValueStore {
    override fun get(key: String): String? = prefs.getString(key, null)
    // commit, not apply: a pairing or the device key must be on disk before the next step uses it.
    @android.annotation.SuppressLint("ApplySharedPref")
    override fun put(key: String, value: String?) { prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.commit() }
}

/**
 * This device's P-256 key at rest: the PKCS#8 bytes sealed with AES-GCM by a key that lives in the
 * Android Keystore and never leaves it (the iPad keeps its key in its Keychain, this device only).
 * In use the key is in the app's memory, where the platform's TLS signs with it.
 */
class KeystoreIdentityStore(private val prefs: SharedPreferences) : IdentityStore {
    private val alias = "me.saffer.sill.device-key-wrap"

    private fun wrapKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }

    override fun load(): Identity? = try {
        val sealed = prefs.getString("Sill.deviceKeySealed", null)?.let { Base64.decode(it, Base64.NO_WRAP) }
        val iv = prefs.getString("Sill.deviceKeyIV", null)?.let { Base64.decode(it, Base64.NO_WRAP) }
        val point = prefs.getString("Sill.devicePoint", null)?.let { Base64.decode(it, Base64.NO_WRAP) }
        if (sealed == null || iv == null || point == null) null
        else {
            val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, wrapKey(), GCMParameterSpec(128, iv)) }
            Identity.restore(c.doFinal(sealed), point)
        }
    } catch (_: Exception) { null }

    @android.annotation.SuppressLint("ApplySharedPref")
    override fun save(identity: Identity) {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, wrapKey()) }
        val sealed = c.doFinal(identity.exportPrivate())
        prefs.edit()
            .putString("Sill.deviceKeySealed", Base64.encodeToString(sealed, Base64.NO_WRAP))
            .putString("Sill.deviceKeyIV", Base64.encodeToString(c.iv, Base64.NO_WRAP))
            .putString("Sill.devicePoint", Base64.encodeToString(identity.point, Base64.NO_WRAP))
            .commit()
    }
}

/**
 * The app: one [SillClient] for its whole life (the connect screen and the stream screen are views
 * over it), and the last state each screen shows when it opens.
 */
class SillApp : Application(), ClientListener {
    lateinit var client: SillClient
        private set
    /** The stream screen attaches late: what it missed is replayed. */
    val router = ReplayingRouter()
    @Volatile var rows: List<MacRow> = emptyList(); private set
    @Volatile var status: String? = null; private set
    @Volatile var session: SillSession? = null; private set
    @Volatile var sessionMac: String = ""; private set
    /** The screen that shows rows, status and prompts (the connect screen while it is visible). */
    @Volatile var ui: ClientListener? = null

    override fun onCreate() {
        super.onCreate()
        val prefs = getSharedPreferences("sill", Context.MODE_PRIVATE)
        client = SillClient(info(this), PrefsStore(prefs), KeystoreIdentityStore(prefs), this, router)
        client.start()
    }

    // ClientListener (worker threads): remembered, and passed on to the screen that shows it.
    override fun onRows(rows: List<MacRow>) { this.rows = rows; ui?.onRows(rows) }
    override fun onStatus(text: String?) { status = text; ui?.onStatus(text) }
    override fun onPairingPrompt(prompt: PairingPrompt) { ui?.onPairingPrompt(prompt) }
    override fun onSessionStarted(session: SillSession, mac: String) {
        router.reset()
        this.session = session; sessionMac = mac
        ui?.onSessionStarted(session, mac)
    }
    override fun onSessionEnded(outcome: GoodbyePolicy.Outcome) {
        session = null
        ui?.onSessionEnded(outcome)
        streamScreen?.finishFromSession()
    }

    @Volatile var streamScreen: StreamActivity? = null

    companion object {
        /** Who this device is: its hello, its stats, its pairing requests. */
        fun info(c: Context): ClientInfo {
            val name = Settings.Global.getString(c.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL
            val tablet = c.resources.configuration.smallestScreenWidthDp >= 600
            val version = try { c.packageManager.getPackageInfo(c.packageName, 0).versionName } catch (_: Exception) { null } ?: "0.6.0"
            return ClientInfo(appVersion = version, build = "1", device = "Android ($name)", noun = if (tablet) "tablet" else "phone",
                model = "${Build.MANUFACTURER} ${Build.MODEL}", name = name)
        }
    }
}
