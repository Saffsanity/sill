package me.saffer.sill.host

import me.saffer.sill.core.Base64Url
import me.saffer.sill.core.PairRequest
import me.saffer.sill.core.PairResult
import me.saffer.sill.core.PairingCode
import me.saffer.sill.core.PairingProof
import java.security.SecureRandom
import kotlin.math.ceil

/**
 * The host's pairing window, with the Mac's rules (PairingWindow.swift): a 12-digit code and a
 * 16-byte secret (the QR code's link), open 300 s, single use, five wrong proofs and it stops, a
 * wrong proof slowing the next by 1, 2, 4 then 8 s, one try per source every 5 s, and opening it
 * again while it is open keeps its code. The typed code's key (PBKDF2, 600,000 rounds) is derived
 * as the window opens, off the caller's thread; a code that arrives first is told to wait a second.
 * Thread safe; `clock` is seconds on a monotonic scale.
 */
class PairingWindow(
    private val macFingerprint: ByteArray,
    private val clock: () -> Double = { System.nanoTime() / 1e9 },
    private val random: SecureRandom = SecureRandom(),
) {
    /** What a pairing proof got. */
    sealed class Outcome {
        /** Paired: `key` is the proof's key, for the Mac's own proof back. */
        class Paired(val key: ByteArray, val method: String) : Outcome()
        class Refused(val result: PairResult) : Outcome()
    }

    /** The open window, for the host's UI. */
    data class Shown(val code: String, val secret: ByteArray, val openedAt: Double, val expiresAt: Double, val byDevice: String?)

    private enum class State { CLOSED, OPEN, EXPIRED }

    /** How the last window ended, for the UI's line under its code (PairDeviceView.Phase). */
    enum class End { PAIRED, STOPPED, EXPIRED, CLOSED }

    private var state = State.CLOSED
    private var shown: Shown? = null
    @Volatile private var codeKey: ByteArray? = null
    private var wrong = 0
    private var nextTryAt = 0.0
    private val lastTryBySource = HashMap<String, Double>()
    /** Since the last open: how it ended, and where the last wrong code came from. */
    @Volatile var lastEnd: End? = null; private set
    @Volatile var wrongFrom: String? = null; private set
    val triesLeft: Int @Synchronized get() = MAX_WRONG - wrong
    /** Told when the window opens, closes or changes (the UI shows or hides it). */
    @Volatile var onChange: (Shown?) -> Unit = {}

    val current: Shown? @Synchronized get() { expireIfDue(); return shown }

    /** Opens the window, or keeps the open one's code; `byDevice` names the device whose ask opened it. */
    @Synchronized fun open(byDevice: String? = null): Shown {
        expireIfDue()
        shown?.let { return it }
        val code = PairingCode.generate(random)
        val secret = ByteArray(16).also(random::nextBytes)
        val now = clock()
        val s = Shown(code, secret, now, now + TTL, byDevice)
        state = State.OPEN; shown = s; codeKey = null; wrong = 0; nextTryAt = 0.0; lastTryBySource.clear(); lastEnd = null; wrongFrom = null
        Thread({ val k = PairingProof.codeKey(code, macFingerprint); synchronized(this) { if (shown === s) codeKey = k } }, "sill-pair-key")
            .apply { isDaemon = true }.start()
        notifyLater(s)
        return s
    }

    /** The Mac's Cancel, a device's cancel, or a pairing done: closed, not expired. */
    @Synchronized fun close() = end(End.CLOSED)

    private fun end(how: End) {
        if (shown == null) return
        state = State.CLOSED; shown = null; codeKey = null; lastEnd = how
        notifyLater(null)
    }

    /** A proof by `method` ("qr" or "code") from `deviceFingerprint` at `source` (its address). */
    @Synchronized fun check(method: String, proof: String, deviceFingerprint: ByteArray, source: String): Outcome {
        expireIfDue()
        if (state == State.EXPIRED) return refuse(PairResult.EXPIRED)
        val s = shown ?: return refuse(PairResult.CLOSED)
        val now = clock()
        val wait = maxOf(nextTryAt - now, (lastTryBySource[source] ?: Double.NEGATIVE_INFINITY) + PER_SOURCE - now)
        if (wait > 0) return busy(wait)
        val key = when (method) {
            PairRequest.CODE -> codeKey ?: return busy(1.0)
            PairRequest.QR -> PairingProof.qrKey(s.secret)
            else -> return refuse(PairResult.CLOSED)
        }
        lastTryBySource[source] = now
        val p = Base64Url.decode(proof)
        if (p != null && PairingProof.isValidDeviceProof(p, key, deviceFingerprint, macFingerprint)) {
            end(End.PAIRED)
            return Outcome.Paired(key, method)
        }
        wrong++
        wrongFrom = source
        if (wrong >= MAX_WRONG) {
            end(End.STOPPED)
            return refuse(PairResult.STOPPED)
        }
        nextTryAt = now + BACKOFF[(wrong - 1).coerceAtMost(BACKOFF.size - 1)]
        return Outcome.Refused(PairResult(ok = false, reason = PairResult.CODE, triesLeft = MAX_WRONG - wrong))
    }

    private fun expireIfDue() {
        val s = shown ?: return
        if (clock() >= s.expiresAt) { state = State.EXPIRED; shown = null; codeKey = null; lastEnd = End.EXPIRED; notifyLater(null) }
    }

    private fun refuse(reason: String) = Outcome.Refused(PairResult(ok = false, reason = reason))
    private fun busy(seconds: Double) = Outcome.Refused(PairResult(ok = false, reason = PairResult.BUSY, retryAfter = ceil(seconds * 10) / 10))

    private fun notifyLater(s: Shown?) { val f = onChange; Thread({ f(s) }, "sill-pair-ui").apply { isDaemon = true }.start() }

    companion object {
        const val TTL = 300.0
        const val MAX_WRONG = 5
        const val PER_SOURCE = 5.0
        val BACKOFF = doubleArrayOf(1.0, 2.0, 4.0, 8.0)
    }
}

/**
 * When a device's "pair me" (kind 19 `ask`) opens the window by itself (the Mac's AskLimits and
 * DoorPolicy's ask rule): never while this computer is locked, one window at a time (an open one is
 * "shown"), none for 10 minutes to a key or address whose window the host's Cancel or five wrong
 * codes ended, and at most three device-opened windows in 10 minutes. Thread safe.
 */
class AskLimits(private val clock: () -> Double = { System.nanoTime() / 1e9 }, private val quietSeconds: Double = QUIET) {
    private val opened = ArrayList<Double>()
    private val quietUntil = HashMap<String, Double>()

    sealed class Decision {
        object Open : Decision()
        data class Answer(val reason: String) : Decision()
    }

    @Synchronized fun decide(locked: Boolean, windowOpen: Boolean, key: String, address: String): Decision {
        val now = clock()
        if (locked) return Decision.Answer(PairResult.LOCKED)
        if (windowOpen) return Decision.Answer(PairResult.SHOWN)
        if ((quietUntil[key] ?: 0.0) > now || (quietUntil[address] ?: 0.0) > now) return Decision.Answer(PairResult.OPEN_ON_MAC)
        opened.removeAll { now - it > WINDOW }
        if (opened.size >= MAX_OPENED) return Decision.Answer(PairResult.OPEN_ON_MAC)
        opened.add(now)
        return Decision.Open
    }

    /** The window this key's ask opened was cancelled on the host or stopped by wrong codes. */
    @Synchronized fun quiet(key: String, address: String) {
        val until = clock() + quietSeconds
        quietUntil[key] = until; quietUntil[address] = until
    }

    companion object {
        const val QUIET = 600.0
        const val WINDOW = 600.0
        const val MAX_OPENED = 3
    }
}
